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
import { fetchScoreboard, fetchStandings, fetchSummary, fetchTeams, fetchTeamSchedule, fetchRankings } from './espn.js';
import { normalizeScoreboard } from './normalize.js';
import { normalizeSummary } from './summary.js';
import { normalizeStandings } from './standings.js';
import { normalizeRankings } from './rankings.js';
import { normalizeTeams, normalizeTeamCard, applyScoreboardFallback } from './team.js';
import { buildCatalog } from './catalog.js';
import { classifyLeague } from './overview.js';
import { publicClient } from './client.js';
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

    // Lightweight client-version telemetry: the app sends its baked build id
    // (`<versionCode> <versionName>`, see app/lib/src/version.dart). NOT used for
    // routing or as a cache-key dimension — it's only visible in `wrangler tail`
    // / observability so we can see the real-world version spread before deciding
    // to raise the gate in league-profiles.json or mint a new contract version.
    const clientVer = req.headers.get('x-scores-client');
    if (clientVer) console.log('client', clientVer, route || '/');

    try {
      // Path-major versioning: `/v1` is a contract NAME, not a build number — it
      // absorbs additive change (new fields/enums/sports/routes) forever; the
      // tolerant client parser makes that free. A new major (`/v2`) is minted
      // ONLY for a breaking reshape and would be added as another allowed key
      // here, coexisting in this one router (cache keys off the full URL, so
      // versions never collide). See schema/SCHEMA.md §11.
      if (v !== 'v1') return json({ error: 'use /v1/*' }, { status: 404, ttl: 300 });

      if (route === 'health')
        return json({
          ok: true,
          leagues: Object.keys(registry.leagues).length,
          updated: new Date().toISOString(),
          // Advisory client-version gate (min/recommended/latest + download URL),
          // authored in the registry, echoed here. null when the registry omits
          // it → the app shows no update banner (fail-open). See publicClient.
          client: publicClient(registry.client),
        }, { ttl: 60 });

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
          const sp = url.searchParams;
          // The fan-out spends one subrequest per league and Cloudflare caps an
          // invocation at ~50, so a request resolves at most OVERVIEW_FETCH_CAP
          // leagues. The tiered Leagues view selects WHICH leagues three ways,
          // keeping stable (shared-cache) URLs:
          //   ?priority=v1[,v2]          — a priority set (the curated tiers)
          //   &page=N                    — slice N of that set (cover >cap leagues)
          //   ?keys=a/b,c/d              — an explicit set (pinned/followed leagues)
          // `keys` overrides priority/sport. Unknown keys are skipped; the slice is
          // capped. (No params → the whole registry, page 0 — back-compat.)
          let keys;
          const keysParam = sp.get('keys');
          if (keysParam) {
            keys = [...new Set(keysParam.split(',').map(s => s.trim()))]
              .filter(k => registry.leagues[k]).slice(0, OVERVIEW_FETCH_CAP);
          } else {
            const priority = sp.get('priority');
            const all = leagueKeys(registry, {
              priority: priority ? priority.split(',').map(s => s.trim()) : undefined,
              sport: sp.get('sport') || undefined,
            });
            const page = Math.max(0, parseInt(sp.get('page') || '0', 10) || 0);
            keys = all.slice(page * OVERVIEW_FETCH_CAP, (page + 1) * OVERVIEW_FETCH_CAP);
          }
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

      // College polls (AP/Coaches/CFP) — the standalone Top-25 for a college
      // league-detail page. Updates ~weekly, so a flat 1h TTL is ample; lazy
      // (only when a college league page is open), never in the overview fan-out.
      if (route === 'rankings') {
        const key = `${sport}/${league}`;
        if (!registry.leagues[key])
          return json({ error: `unknown league "${key}"`, hint: 'GET /v1/catalog' }, { status: 404, ttl: 300 });
        return cached(req, ctx, async () => {
          const raw = await fetchRankings(key);
          return json({ league: key, ...normalizeRankings(raw) }, { ttl: 3600 });
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
