// Cloudflare Worker entry. Thin shell: route → fetch upstream → normalize →
// cache with stale-while-revalidate. All the real logic is in the pure modules.
//
//   GET /v1/health
//   GET /v1/catalog[?priority=v1&sport=soccer]
//   GET /v1/overview[?priority=v1&sport=soccer]   — per-league season-pulse states
//   GET /v1/scores/{sport}/{league}[?date=YYYYMMDD | YYYYMMDD-YYYYMMDD]
//   GET /v1/standings/{sport}/{league}[?season=YYYY]  — no season → ESPN's current
//   GET /v1/rankings/{sport}/{league}              — polls / tours / divisions
//   GET /v1/scorecard/{sport}/{league}/{eventId}/{playerId}[?season=YYYY] — golf
//   GET /v1/teams/{sport}/{league}                 — every team (favorites picker)
//   GET /v1/team/{sport}/{league}/{teamId}         — one team's live/last/next card
//   GET /v1/teamdetail/{sport}/{league}/{teamId}   — team page: schedule/roster/stats/standing

// esbuild (wrangler) bundles .json natively — no import attribute, which older
// esbuild can't parse. (The Node test harness DOES need `with { type: 'json' }`.)
import registry from '../../schema/league-profiles.json';
import {
  fetchScoreboard, fetchStandings, fetchSummary, fetchTeams, fetchTeamSchedule,
  fetchTeamRoster, fetchTeamStatistics,
  fetchRankings, fetchCoreEvent, fetchCoreRef, fetchGolfPlayerSummary,
} from './espn.js';
import { normalizeScoreboard } from './normalize.js';
import { normalizeSummary, normalizeMmaSummary } from './summary.js';
import { normalizeGolfScorecard } from './scorecard.js';
import { normalizeStandings } from './standings.js';
import { normalizeRankings } from './rankings.js';
import { normalizeTeams, normalizeTeamCard, applyScoreboardFallback } from './team.js';
import { normalizeTeamDetail } from './teamdetail.js';
import { buildCatalog } from './catalog.js';
import { classifyLeague } from './overview.js';
import { publicClient } from './client.js';
import { TTL, idleTtl, pastDatedTtl } from './ttl.js';
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
    const [v, route, sport, league, eventId, subId] = url.pathname.split('/').filter(Boolean);

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
            // ?date accepts a single YYYYMMDD or a YYYYMMDD-YYYYMMDD range —
            // ESPN's scoreboard serves multi-day ranges natively (VERIFIED
            // 2026-07: 9 WC days in one payload) and the normalizer is
            // per-event-dated, so ranges pass straight through.
            const date = url.searchParams.get('date') || undefined;
            const sb = await fetchScoreboard(key, date);
            const data = normalizeScoreboard(registry, key, sb, await golfExtras(registry, key, sb));
            // live = 15s; a fully-past dated slate = 6h (immutable); else 5m, but
            // 30s near a scheduled kickoff (see ttl.js).
            const ttl = data.anyLive
              ? TTL.scoresLive
              : (pastDatedTtl(date, data.anyLive, Date.now()) ?? idleTtl(data.nextStartMs, Date.now()));
            return json(data, { ttl });
          }
          if (route === 'summary') {
            if (!eventId) return json({ error: 'missing event id', hint: '/v1/summary/{sport}/{league}/{eventId}' }, { status: 400, ttl: 300 });
            // MMA: the site /summary 404s for every event (it proxies a broken
            // core call) — build the rich tier from core per-bout resources.
            if (resolve(registry, key).espnSport === 'mma') {
              const data = await mmaSummary(key, eventId);
              return json(data, { ttl: data.live ? TTL.summaryLive : idleTtl(data.nextStartMs, Date.now()) });
            }
            const raw = await fetchSummary(key, eventId);
            const data = normalizeSummary(registry, key, raw);
            // box scores tick slower than the score; near kickoff, poll the flip in.
            return json(data, { ttl: data.live ? TTL.summaryLive : idleTtl(data.nextStartMs, Date.now()) });
          }
          // Standings: NO season default. ESPN's own default IS the current
          // season, where getFullYear() is wrong mid-year for cross-year leagues
          // (in July 2026 the NHL current season is 2027). Forward only an
          // explicit client ?season=.
          const season = url.searchParams.get('season') || undefined;
          const raw = await fetchStandings(key, season);
          // Per-family preferred columns (from the registry) so the app shows W/L/PCT/GB
          // for NBA — not ESPN's meaningless internal "points" — while keeping PTS for
          // soccer/NHL. Absent → the app falls back to its generic heuristic.
          const columns = resolve(registry, key).standingsColumns || null;
          const seasonYear = raw?.season?.year ?? (season ? Number(season) : undefined);
          return json({ league: key, season: seasonYear, columns, groups: normalizeStandings(raw) }, { ttl: 3600 });
        });
      }

      // Golf hole-by-hole scorecard for one leaderboard row — lazy (fetched on a
      // row tap), never polled by the home feed. `eventId`/`subId` are the
      // event/player slots of the path split.
      if (route === 'scorecard') {
        const key = `${sport}/${league}`;
        if (!registry.leagues[key])
          return json({ error: `unknown league "${key}"`, hint: 'GET /v1/catalog' }, { status: 404, ttl: 300 });
        if (!eventId || !subId)
          return json({ error: 'missing ids', hint: '/v1/scorecard/{sport}/{league}/{eventId}/{playerId}' }, { status: 400, ttl: 300 });
        return cached(req, ctx, async () => {
          // Golf seasons are calendar-aligned (unlike standings), so the
          // current year is a safe default when the client doesn't pass one.
          const season = url.searchParams.get('season') || String(new Date().getFullYear());
          const raw = await fetchGolfPlayerSummary(key, eventId, season, subId);
          return json(normalizeGolfScorecard(key, eventId, subId, raw), { ttl: TTL.scorecard });
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

      // One team's rich detail page: full-season schedule + roster + season stats
      // + its standings group. The lean /v1/team card (above) is what the home
      // feed polls; this is opened once on a team page. Schedule is required;
      // roster/stats/standings are best-effort (each .catch → null). 4 subrequests
      // coalesced behind a 30m TTL — trivial vs the fan-out cap.
      if (route === 'teamdetail') {
        const key = `${sport}/${league}`;
        if (!registry.leagues[key])
          return json({ error: `unknown league "${key}"`, hint: 'GET /v1/catalog' }, { status: 404, ttl: 300 });
        if (!eventId)
          return json({ error: 'missing team id', hint: '/v1/teamdetail/{sport}/{league}/{teamId}' }, { status: 400, ttl: 300 });
        return cached(req, ctx, async () => {
          const teamId = eventId;
          const schedule = await fetchTeamSchedule(key, teamId);
          const [roster, stats, standingsRaw] = await Promise.all([
            fetchTeamRoster(key, teamId).catch(() => null),
            fetchTeamStatistics(key, teamId).catch(() => null),
            fetchStandings(key).catch(() => null),
          ]);
          const data = normalizeTeamDetail(registry, key, teamId, { schedule, roster, stats, standingsRaw });
          return json(data, { ttl: TTL.teamDetail });
        });
      }

      return json({ error: 'not found' }, { status: 404, ttl: 300 });
    } catch (e) {
      return json({ error: String(e?.message || e) }, { status: 502, ttl: 15 });
    }
  },
};

// ---- per-sport route enrichments --------------------------------------------

// Golf: the cut line / major / rounds meta (meta.golf) lives ONLY on the core
// tournament resource — fetch it per event (2 subrequests each, capped) and hand
// it to the pure normalizer. Best-effort: any failure just omits meta.golf.
async function golfExtras(reg, key, sb) {
  const prof = resolve(reg, key);
  if (prof.espnSport !== 'golf' || prof.layout !== 'field') return undefined;
  const ids = (sb.events || []).map(e => e?.id).filter(Boolean).slice(0, 3);
  if (!ids.length) return undefined;
  const pairs = await Promise.all(ids.map(async id => {
    try {
      const ev = await fetchCoreEvent(key, id);
      const ref = ev?.tournament?.$ref;
      return [String(id), ref ? await fetchCoreRef(ref) : null];
    } catch { return [String(id), null]; }
  }));
  const golfTournaments = Object.fromEntries(pairs.filter(([, t]) => t));
  return Object.keys(golfTournaments).length ? { golfTournaments } : undefined;
}

// MMA: core event → per-bout status (structured method of victory) → judge
// linescores for decisions only (subrequest budget: 1 + bouts + 2×decisions,
// ~30 worst case for a 14-bout card — under the ~50 cap with headroom).
async function mmaSummary(key, eventId) {
  const core = await fetchCoreEvent(key, eventId);
  const comps = Array.isArray(core?.competitions) ? core.competitions : [];
  const statuses = {};
  await Promise.all(comps.map(async c => {
    const ref = c?.status?.$ref;
    if (!c?.id || !ref) return;
    try { statuses[String(c.id)] = await fetchCoreRef(ref); } catch { /* bout stays unresolved */ }
  }));
  const linescores = {};
  await Promise.all(comps.flatMap(c => {
    const st = statuses[String(c?.id)];
    if (!/decision/i.test(st?.result?.name || st?.result?.displayName || '')) return [];
    return (c.competitors || []).map(async comp => {
      const ref = comp?.linescores?.$ref;
      if (!ref) return;
      try { linescores[`${c.id}/${comp.id}`] = await fetchCoreRef(ref); } catch { /* judges optional */ }
    });
  }));
  return normalizeMmaSummary(core, statuses, linescores);
}

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
