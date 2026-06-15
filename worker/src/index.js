// Cloudflare Worker entry. Thin shell: route → fetch upstream → normalize →
// cache with stale-while-revalidate. All the real logic is in the pure modules.
//
//   GET /v1/health
//   GET /v1/catalog[?priority=v1&sport=soccer]
//   GET /v1/overview[?priority=v1&sport=soccer]   — per-league season-pulse states
//   GET /v1/scores/{sport}/{league}[?date=YYYYMMDD]
//   GET /v1/standings/{sport}/{league}[?season=YYYY]
//   GET /v1/teams/{sport}/{league}                 — every team (favorites picker)
//   GET /v1/team/{sport}/{league}/{teamId}         — one team's live/last/next card

// esbuild (wrangler) bundles .json natively — no import attribute, which older
// esbuild can't parse. (The Node test harness DOES need `with { type: 'json' }`.)
import registry from '../../schema/league-profiles.json';
import { fetchScoreboard, fetchStandings, fetchSummary, fetchTeams, fetchTeamSchedule } from './espn.js';
import { normalizeScoreboard } from './normalize.js';
import { normalizeSummary } from './summary.js';
import { normalizeStandings } from './standings.js';
import { normalizeTeams, normalizeTeamCard, applyScoreboardFallback } from './team.js';
import { buildCatalog } from './catalog.js';
import { classifyLeague } from './overview.js';
import { TTL, idleTtl } from './ttl.js';
import { leagueKeys, resolve } from '../../schema/tools/resolve.mjs';

// Max leagues the /overview fan-out will fetch in one invocation — kept under
// Cloudflare's 50-subrequest-per-invocation cap (with headroom). See the route.
const OVERVIEW_FETCH_CAP = 48;

const CORS = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET,OPTIONS',
  'access-control-allow-headers': '*',
};

function json(data, { ttl = 15, status = 200 } = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': `public, max-age=${ttl}`,
      ...CORS,
    },
  });
}

export default {
  async fetch(req, _env, ctx) {
    if (req.method === 'OPTIONS') return new Response(null, { headers: CORS });
    if (req.method !== 'GET') return json({ error: 'GET only' }, { status: 405, ttl: 60 });

    const url = new URL(req.url);
    const [v, route, sport, league, eventId] = url.pathname.split('/').filter(Boolean);

    try {
      if (v !== 'v1') return json({ error: 'use /v1/*' }, { status: 404, ttl: 300 });

      if (route === 'health')
        return json({ ok: true, leagues: Object.keys(registry.leagues).length, updated: new Date().toISOString() }, { ttl: 60 });

      if (route === 'catalog')
        return json(buildCatalog(registry, {
          priority: url.searchParams.get('priority') || undefined,
          sport: url.searchParams.get('sport') || undefined,
        }), { ttl: 3600 });

      // Season-pulse for the Leagues list: one cheap scoreboard fetch per league,
      // classified into a state. Fanned out here, coalesced behind the Cache API
      // (stale-while-revalidate) so the whole list resolves from one shared pass
      // every TTL — not N fetches per client.
      if (route === 'overview') {
        return cached(req, ctx, async () => {
          const all = leagueKeys(registry, {
            priority: url.searchParams.get('priority') || undefined,
            sport: url.searchParams.get('sport') || undefined,
          });
          // The fan-out spends one subrequest per league and Cloudflare caps an
          // invocation at 50. Stay safely under it: leagues past the cap are
          // simply omitted (the client renders them with no pulse, same as an
          // 'unknown'). To cover a registry larger than this, the client should
          // page the call by ?priority / ?sport (each is its own invocation).
          const keys = all.slice(0, OVERVIEW_FETCH_CAP);
          const now = new Date();
          const leagues = await Promise.all(keys.map(async (key) => {
            try {
              return { key, ...classifyLeague(await fetchScoreboard(key), now) };
            } catch {
              return { key, state: 'unknown', detail: '', live: false };
            }
          }));
          // A coarse season pulse changes slowly and the fan-out is heavy, so it
          // deliberately does NOT follow the scores endpoint's 15s-when-live
          // rule — a flat 5m keeps the shared refresh cheap. But when a league is
          // live or has a game TODAY (the today→live flip we'd otherwise hide for
          // 5m), tighten to 1m so the pulse dot catches kickoff promptly.
          const active = leagues.some((l) => l.state === 'live' || l.state === 'today');
          return json({ updated: now.toISOString(), leagues }, { ttl: active ? TTL.overviewActive : TTL.overview });
        });
      }

      if (route === 'scores' || route === 'standings' || route === 'summary') {
        const key = `${sport}/${league}`;
        if (!registry.leagues[key])
          return json({ error: `unknown league "${key}"`, hint: 'GET /v1/catalog' }, { status: 404, ttl: 300 });

        return cached(req, ctx, async () => {
          if (route === 'scores') {
            const sb = await fetchScoreboard(key, url.searchParams.get('date') || undefined);
            const data = normalizeScoreboard(registry, key, sb);
            // live = 15s; else 5m, but 30s near a scheduled kickoff (see ttl.js).
            return json(data, { ttl: data.anyLive ? TTL.scoresLive : idleTtl(data.nextStartMs, Date.now()) });
          }
          if (route === 'summary') {
            if (!eventId) return json({ error: 'missing event id', hint: '/v1/summary/{sport}/{league}/{eventId}' }, { status: 400, ttl: 300 });
            const raw = await fetchSummary(key, eventId);
            const data = normalizeSummary(registry, key, raw);
            // box scores tick slower than the score; near kickoff, poll the flip in.
            return json(data, { ttl: data.live ? TTL.summaryLive : idleTtl(data.nextStartMs, Date.now()) });
          }
          const season = url.searchParams.get('season') || new Date().getFullYear();
          const raw = await fetchStandings(key, season);
          // Per-family preferred columns (from the registry) so the app shows W/L/PCT/GB
          // for NBA — not ESPN's meaningless internal "points" — while keeping PTS for
          // soccer/NHL. Absent → the app falls back to its generic heuristic.
          const columns = resolve(registry, key).standingsColumns || null;
          return json({ league: key, season: Number(season), columns, groups: normalizeStandings(raw) }, { ttl: 3600 });
        });
      }

      // Every team in a league — backs the favorites picker. Rosters change ~once
      // a season, so a flat 1-day TTL (vs catalog's 1h) keeps it nearly free.
      if (route === 'teams') {
        const key = `${sport}/${league}`;
        if (!registry.leagues[key])
          return json({ error: `unknown league "${key}"`, hint: 'GET /v1/catalog' }, { status: 404, ttl: 300 });
        return cached(req, ctx, async () => {
          const raw = await fetchTeams(key);
          return json({ league: key, sport, teams: normalizeTeams(registry, key, raw) }, { ttl: 86400 });
        });
      }

      // One favorite team's card: live game if any, else last result + next game.
      // `eventId` is the teamId slot of the path split.
      if (route === 'team') {
        const key = `${sport}/${league}`;
        if (!registry.leagues[key])
          return json({ error: `unknown league "${key}"`, hint: 'GET /v1/catalog' }, { status: 404, ttl: 300 });
        if (!eventId)
          return json({ error: 'missing team id', hint: '/v1/team/{sport}/{league}/{teamId}' }, { status: 400, ttl: 300 });
        return cached(req, ctx, async () => {
          const schedule = await fetchTeamSchedule(key, eventId);
          let data = normalizeTeamCard(registry, key, eventId, schedule);
          // The team-schedule endpoint is empty for national teams/tournament squads
          // (and can lag a club's live game) — when it gave us no live game, backfill
          // from the league scoreboard so a favorited team's live game always shows.
          if (!data.live) {
            try {
              data = applyScoreboardFallback(registry, key, eventId, data, await fetchScoreboard(key));
            } catch { /* scoreboard optional — keep the schedule-only card */ }
          }
          return json(data, { ttl: data.anyLive ? 15 : 300 }); // live = 15s, idle = 5m (mirrors scores)
        });
      }

      return json({ error: 'not found' }, { status: 404, ttl: 300 });
    } catch (e) {
      return json({ error: String(e?.message || e) }, { status: 502, ttl: 15 });
    }
  },
};

// ---- Cache API + stale-while-revalidate ------------------------------------
// One upstream fetch per league per TTL, shared by ALL clients. Stale responses
// are served instantly while a refresh runs in the background (ctx.waitUntil).
// Cache API has no write quota (unlike KV) — safe for a 15s hot path.
async function cached(req, ctx, build) {
  const cache = caches.default;
  const cacheKey = new Request(new URL(req.url).toString(), { method: 'GET' });

  const hit = await cache.match(cacheKey);
  if (hit) {
    const age = (Date.now() - Number(hit.headers.get('x-cached-at') || 0)) / 1000;
    const ttl = Number(hit.headers.get('x-ttl') || 15);
    if (age < ttl) return withHeader(hit, 'x-cache', 'HIT');
    ctx.waitUntil(refresh(cache, cacheKey, build));       // revalidate in background
    return withHeader(hit, 'x-cache', 'STALE');           // serve stale immediately
  }
  return refresh(cache, cacheKey, build, 'MISS');
}

async function refresh(cache, cacheKey, build, tag = 'REVALIDATE') {
  const res = await build();
  const ttl = (res.headers.get('cache-control') || '').match(/max-age=(\d+)/)?.[1] || '15';
  const stamped = new Response(res.body, res);
  stamped.headers.set('x-cached-at', String(Date.now()));
  stamped.headers.set('x-ttl', ttl);
  stamped.headers.set('x-cache', tag);
  await cache.put(cacheKey, stamped.clone());
  return stamped;
}

function withHeader(res, k, v) {
  const r = new Response(res.body, res);
  r.headers.set(k, v);
  return r;
}
