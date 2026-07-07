// mock-server.mjs — the offline mock backend. A plain Node http server that
// serves the SAME route surface + canonical contract as the real Cloudflare
// worker (src/index.js), but instead of fetching ESPN it replays captured
// fixtures (scripts/capture-fixtures.mjs) through the synthesizer (mock/synth.mjs)
// and the EXACT same pure normalizers the worker uses. Point the Flutter app's
// Settings → worker URL at this (http://localhost:8787, or 10.0.2.2 on Android
// emulator) to walk every UI permutation — final + live + scheduled per sport —
// with zero dependency on the real-world calendar.
//
//   node scripts/mock-server.mjs                 # :8787
//   PORT=9000 node scripts/mock-server.mjs       # custom port
//
// No Cache API / stale-while-revalidate here on purpose: a single-user dev mock
// has nothing to coalesce, and skipping it keeps this readable. The data is
// deterministic per request (see synth.mjs), so polling never makes it flicker.

import http from 'node:http';
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import registry from '../../schema/league-profiles.json' with { type: 'json' };
import { leagueKeys, resolve } from '../../schema/tools/resolve.mjs';
import { normalizeScoreboard } from '../src/normalize.js';
import { normalizeSummary, normalizeMmaSummary } from '../src/summary.js';
import { normalizeStandings } from '../src/standings.js';
import { normalizeRankings } from '../src/rankings.js';
import { normalizeGolfScorecard } from '../src/scorecard.js';
import { normalizeTeams, normalizeTeamCard, applyScoreboardFallback } from '../src/team.js';
import { normalizeTeamDetail } from '../src/teamdetail.js';
import { buildCatalog } from '../src/catalog.js';
import { classifyLeague } from '../src/overview.js';
import {
  synthScoreboard, synthSummary, synthTeams, synthStandings, synthTeamScoreboard,
  synthRankings, synthGolfExtras, synthGolfScorecard, synthMmaCore,
  synthTeamDetailParts, synthStandingSummary,
} from '../mock/synth.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const FIX_DIR = join(HERE, '..', 'mock', 'fixtures');
const PORT = Number(process.env.PORT || 8787);

// ---- load fixtures into memory ----------------------------------------------
const fixtures = new Map(); // 'baseball/mlb' -> captured fixture object
function loadFixtures() {
  let files = [];
  try { files = readdirSync(FIX_DIR).filter((f) => f.endsWith('.json') && f !== '_manifest.json'); } catch { /* none yet */ }
  for (const f of files) {
    try {
      const fx = JSON.parse(readFileSync(join(FIX_DIR, f), 'utf8'));
      if (fx.key) fixtures.set(fx.key, fx);
    } catch (e) { console.warn(`  ! skipped ${f}: ${e.message}`); }
  }
}

// a fixture so leagues without a capture still serve a valid (fabricated/empty) slate
const emptyFixture = (key) => ({ key, events: [], teams: null, standings: null, summaries: {} });
const fxFor = (key) => fixtures.get(key) || emptyFixture(key);
const findRawTeam = (fx, teamId) => (fx.teams?.sports?.[0]?.leagues?.[0]?.teams || []).map((t) => t.team).find((t) => String(t?.id) === String(teamId));

// ---- response helpers (CORS + JSON, mirroring index.js) ---------------------
const CORS = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET,OPTIONS',
  'access-control-allow-headers': '*',
};
function send(res, data, status = 200) {
  const body = JSON.stringify(data);
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'x-mock': '1', ...CORS });
  res.end(body);
}

// ---- router -----------------------------------------------------------------
function handle(req, res) {
  if (req.method === 'OPTIONS') { res.writeHead(204, CORS); res.end(); return; }
  if (req.method !== 'GET') return send(res, { error: 'GET only' }, 405);

  const url = new URL(req.url, 'http://localhost');
  const [v, route, sport, league, eventId, subId] = url.pathname.split('/').filter(Boolean);
  const q = url.searchParams;
  const now = Date.now();

  try {
    if (v !== 'v1') return send(res, { error: 'use /v1/*' }, 404);

    if (route === 'health')
      return send(res, { ok: true, mock: true, leagues: fixtures.size, registryLeagues: Object.keys(registry.leagues).length, updated: new Date(now).toISOString() });

    if (route === 'catalog')
      return send(res, buildCatalog(registry, { priority: q.get('priority') || undefined, sport: q.get('sport') || undefined }));

    if (route === 'overview') {
      // Mirror the worker's selection semantics (worker/src/index.js): comma
      // priority sets, page slices of 48, and an explicit ?keys= override —
      // else clients paging the curated tiers get [] from the mock only.
      const CAP = 48;
      let keys;
      const keysParam = q.get('keys');
      if (keysParam) {
        keys = [...new Set(keysParam.split(',').map((s) => s.trim()))]
          .filter((k) => registry.leagues[k]).slice(0, CAP);
      } else {
        const priority = q.get('priority');
        const all = leagueKeys(registry, {
          priority: priority ? priority.split(',').map((s) => s.trim()) : undefined,
          sport: q.get('sport') || undefined,
        });
        const page = Math.max(0, parseInt(q.get('page') || '0', 10) || 0);
        keys = all.slice(page * CAP, (page + 1) * CAP);
      }
      const leagues = keys.map((key) => {
        const fx = fixtures.get(key);
        if (!fx) return { key, state: 'offseason', detail: 'No fixture', live: false };
        try {
          const sb = synthScoreboard(registry, key, fx, { now });
          return { key, ...classifyLeague(sb, new Date(now)) };
        } catch { return { key, state: 'unknown', detail: '', live: false }; }
      });
      return send(res, { updated: new Date(now).toISOString(), leagues });
    }

    const key = `${sport}/${league}`;
    const known = !!registry.leagues[key];

    if (route === 'scores') {
      if (!known) return send(res, { error: `unknown league "${key}"`, hint: 'GET /v1/catalog' }, 404);
      const fx = fxFor(key);
      const sb = synthScoreboard(registry, key, fx, { now, date: q.get('date') || null });
      // golf: meta.golf extras (captured core tournament or a fabricated one) —
      // mirrors the worker's golfExtras() enrichment.
      return send(res, normalizeScoreboard(registry, key, sb, synthGolfExtras(registry, key, fx, sb)));
    }

    if (route === 'summary') {
      if (!known) return send(res, { error: `unknown league "${key}"` }, 404);
      if (!eventId) return send(res, { error: 'missing event id' }, 400);
      // MMA mirrors the worker: rich tier is built from (fabricated) core shapes
      // through the SAME normalizeMmaSummary.
      if (resolve(registry, key).espnSport === 'mma') {
        const { coreEvent, statuses, linescores } = synthMmaCore(registry, key, fxFor(key), eventId, { now });
        return send(res, normalizeMmaSummary(coreEvent, statuses, linescores));
      }
      return send(res, normalizeSummary(registry, key, synthSummary(fxFor(key), eventId)));
    }

    if (route === 'scorecard') {
      if (!known) return send(res, { error: `unknown league "${key}"` }, 404);
      if (!eventId || !subId) return send(res, { error: 'missing ids', hint: '/v1/scorecard/{sport}/{league}/{eventId}/{playerId}' }, 400);
      const raw = synthGolfScorecard(registry, key, fxFor(key), eventId, subId, { now });
      return send(res, normalizeGolfScorecard(key, eventId, subId, raw));
    }

    if (route === 'rankings') {
      if (!known) return send(res, { error: `unknown league "${key}"` }, 404);
      return send(res, { league: key, ...normalizeRankings(synthRankings(fxFor(key))) });
    }

    if (route === 'standings') {
      if (!known) return send(res, { error: `unknown league "${key}"` }, 404);
      // Mirror the worker: no season default upstream; echo the requested one.
      const season = q.get('season');
      const columns = resolve(registry, key).standingsColumns || null;
      return send(res, { league: key, season: season ? Number(season) : new Date(now).getFullYear(), columns, groups: normalizeStandings(synthStandings(fxFor(key))) });
    }

    if (route === 'teams') {
      if (!known) return send(res, { error: `unknown league "${key}"` }, 404);
      return send(res, { league: key, sport, teams: normalizeTeams(registry, key, synthTeams(fxFor(key))) });
    }

    if (route === 'team') {
      if (!known) return send(res, { error: `unknown league "${key}"` }, 404);
      if (!eventId) return send(res, { error: 'missing team id' }, 400);
      const fx = fxFor(key);
      // seed identity from the teams list (+ a deterministic standingSummary so the
      // enriched hero card's season line is walkable offline), then fill
      // live/last/next from the synth slate via the SAME fallback the worker uses.
      const seed = { team: { ...(findRawTeam(fx, eventId) || { id: eventId }), standingSummary: synthStandingSummary(registry, key, fx, eventId) } };
      let card = normalizeTeamCard(registry, key, eventId, seed);
      card = applyScoreboardFallback(registry, key, eventId, card, synthTeamScoreboard(registry, key, fx, eventId, { now }));
      return send(res, card);
    }

    if (route === 'teamdetail') {
      if (!known) return send(res, { error: `unknown league "${key}"` }, 404);
      if (!eventId) return send(res, { error: 'missing team id' }, 400);
      const parts = synthTeamDetailParts(registry, key, fxFor(key), eventId, { now });
      return send(res, normalizeTeamDetail(registry, key, eventId, parts));
    }

    return send(res, { error: 'not found' }, 404);
  } catch (e) {
    return send(res, { error: String(e?.stack || e?.message || e) }, 502);
  }
}

// ---- boot -------------------------------------------------------------------
loadFixtures();
if (!fixtures.size) {
  console.warn('⚠  No fixtures found in mock/fixtures/. Run: node scripts/capture-fixtures.mjs\n');
}
http.createServer(handle).listen(PORT, '0.0.0.0', () => {
  const withEvents = [...fixtures.values()].filter((f) => f.events?.length).length;
  console.log(`Mock worker → http://localhost:${PORT}   (Android emulator: http://10.0.2.2:${PORT})`);
  console.log(`  ${fixtures.size} league fixtures loaded (${withEvents} with events). Routes: /v1/{health,catalog,overview,scores,summary,scorecard,rankings,standings,teams,team,teamdetail}`);
  console.log('  Point the Flutter app: Settings → tap About 6× → set worker URL.\n');
});
