// mock-espn-server.mjs — the offline dev backend for the WORKERLESS app. Serves
// RAW ESPN-shaped responses on ESPN-shaped paths, replaying the committed fixtures
// (mock/fixtures/) through the pure synthesizer (mock/synth.mjs) — the SAME synth
// the old canonical mock used, but WITHOUT the normalizers (the app now normalizes
// on-device). Point the app's Settings "API base override" at this and it walks
// every UI state (final + live + scheduled per sport) offline.
//
//   node scripts/mock-espn-server.mjs            # :8787
//   PORT=9000 node scripts/mock-espn-server.mjs
//
// The app's EspnClient rewrites every ESPN request's ORIGIN to this base (path +
// query preserved), so this only has to match ESPN's PATHS. Core-API $refs
// (golf tournament meta, MMA bouts) are emitted as absolute core.api URLs whose
// PATH points back here (/mock/...) — the same origin-swap resolves them to us.

import http from 'node:http';
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import registry from '../../schema/league-profiles.json' with { type: 'json' };
import { resolve } from '../../schema/tools/resolve.mjs';
import {
  synthScoreboard, synthSummary, synthTeams, synthStandings, synthRankings,
  synthGolfExtras, synthGolfScorecard, synthMmaCore, synthTeamDetailParts,
  synthCoreSituation, synthCorePredictor, synthCorePlayText,
} from '../mock/synth.mjs';
import { getScenario } from '../mock/scenarios.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const FIX_DIR = join(HERE, '..', 'mock', 'fixtures');
const PORT = Number(process.env.PORT || 8787);
const REF_HOST = 'https://sports.core.api.espn.com'; // any host — the app swaps the origin to us

// Optional "director's cut" overlay (see mock/scenarios.mjs). Cross-platform: read
// `--scenario <name>` from argv (an env var like SCENARIO=x doesn't survive npm on
// Windows cmd) with SCENARIO as a fallback. null → normal mock behavior.
const scenarioName = (() => {
  const i = process.argv.indexOf('--scenario');
  return i !== -1 ? process.argv[i + 1] : (process.env.SCENARIO || null);
})();
const SCENARIO = getScenario(scenarioName);
if (scenarioName && !SCENARIO) console.warn(`⚠  Unknown scenario "${scenarioName}" — serving the normal mock.\n`);

const fixtures = new Map();
function loadFixtures() {
  let files = [];
  try { files = readdirSync(FIX_DIR).filter((f) => f.endsWith('.json') && !f.startsWith('_')); } catch { /* none */ }
  for (const f of files) {
    try { const fx = JSON.parse(readFileSync(join(FIX_DIR, f), 'utf8')); if (fx.key) fixtures.set(fx.key, fx); }
    catch (e) { console.warn(`  ! skipped ${f}: ${e.message}`); }
  }
}
const emptyFixture = (key) => ({ key, events: [], teams: null, standings: null, summaries: {} });
const fxFor = (key) => fixtures.get(key) || emptyFixture(key);

const CORS = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET,OPTIONS',
  'access-control-allow-headers': '*',
};
function send(res, data, status = 200) {
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'x-mock': '1', ...CORS });
  res.end(JSON.stringify(data));
}

function handle(req, res) {
  if (req.method === 'OPTIONS') { res.writeHead(204, CORS); res.end(); return; }
  if (req.method !== 'GET') return send(res, { error: 'GET only' }, 405);

  const url = new URL(req.url, 'http://localhost');
  const seg = url.pathname.split('/').filter(Boolean);
  const q = url.searchParams;
  const now = Date.now();
  const known = (key) => !!registry.leagues[key];

  try {
    // ---- our own core-ref routes (see the $refs we emit below) --------------
    // /mock/golf-tourn/{sport}/{league}/{eventId}
    if (seg[0] === 'mock' && seg[1] === 'golf-tourn') {
      const key = `${seg[2]}/${seg[3]}`, eventId = seg[4];
      const fx = fxFor(key);
      const sb = synthScoreboard(registry, key, fx, { now, scenario: SCENARIO });
      const extras = synthGolfExtras(registry, key, fx, sb) || {};
      return send(res, (extras.golfTournaments || {})[eventId] || {});
    }
    // /mock/mma-status/{sport}/{league}/{eventId}/{boutId}
    if (seg[0] === 'mock' && seg[1] === 'mma-status') {
      const key = `${seg[2]}/${seg[3]}`;
      const { statuses } = synthMmaCore(registry, key, fxFor(key), seg[4], { now, scenario: SCENARIO });
      return send(res, statuses[seg[5]] || { type: { state: 'pre' } });
    }
    // /mock/mma-linescore/{sport}/{league}/{eventId}/{boutId}/{compId}
    if (seg[0] === 'mock' && seg[1] === 'mma-linescore') {
      const key = `${seg[2]}/${seg[3]}`;
      const { linescores } = synthMmaCore(registry, key, fxFor(key), seg[4], { now, scenario: SCENARIO });
      return send(res, linescores[`${seg[5]}/${seg[6]}`] || { items: [] });
    }
    // /mock/coreplay/{sport}/{league}/{eventId} — the text behind situation.lastPlay.$ref
    if (seg[0] === 'mock' && seg[1] === 'coreplay') {
      const key = `${seg[2]}/${seg[3]}`;
      const prof = resolve(registry, key);
      return send(res, { id: seg[4], text: synthCorePlayText(seg[4], prof.espnSport) });
    }

    // ---- core event: /v2/sports/{sport}/leagues/{league}/events/{id} ---------
    if (seg[0] === 'v2' && seg[1] === 'sports' && seg[3] === 'leagues' && seg[5] === 'events') {
      const key = `${seg[2]}/${seg[4]}`, eventId = seg[6];
      const prof = resolve(registry, key);
      // Detail-open CORE resources: /events/{id}/competitions/{comp}/{situation|predictor}.
      // Fabricated deterministically so live gridiron/basketball/hockey detail is
      // walkable offline through the app's real core-fetch path.
      if (seg[7] === 'competitions' && seg[9] === 'predictor') {
        return send(res, { $ref: `${REF_HOST}${url.pathname}`, ...synthCorePredictor(eventId) });
      }
      if (seg[7] === 'competitions' && seg[9] === 'situation') {
        const sit = synthCoreSituation(prof, eventId);
        // inject the last-play $ref back at us (mirrors the golf/mma ref injection).
        sit.lastPlay = { $ref: `${REF_HOST}/mock/coreplay/${key}/${eventId}` };
        return send(res, { $ref: `${REF_HOST}${url.pathname}`, ...sit });
      }
      if (prof.espnSport === 'mma') {
        const { coreEvent } = synthMmaCore(registry, key, fxFor(key), eventId, { now, scenario: SCENARIO });
        // inject $refs pointing back at us so the app's per-bout follow works.
        for (const c of coreEvent.competitions || []) {
          c.status = { $ref: `${REF_HOST}/mock/mma-status/${key}/${eventId}/${c.id}` };
          for (const comp of c.competitors || []) {
            comp.linescores = { $ref: `${REF_HOST}/mock/mma-linescore/${key}/${eventId}/${c.id}/${comp.id}` };
          }
        }
        return send(res, coreEvent);
      }
      // golf (and anything else that fetches a core event): a tournament $ref.
      return send(res, { id: String(eventId), tournament: { $ref: `${REF_HOST}/mock/golf-tourn/${key}/${eventId}` } });
    }

    // ---- site v2: /apis/site/v2/sports/{sport}/{league}/{resource}[/...] -----
    // (golf hole-by-hole rides this too: resource 'leaderboard' + 'playersummary')
    if (seg[0] === 'apis' && seg[1] === 'site' && seg[2] === 'v2' && seg[3] === 'sports') {
      const sport = seg[4], league = seg[5], resource = seg[6];
      const key = `${sport}/${league}`;
      if (!known(key)) return send(res, { error: `unknown league "${key}"` }, 404);
      const fx = fxFor(key);
      if (resource === 'scoreboard') {
        return send(res, synthScoreboard(registry, key, fx, { now, date: q.get('dates') || null, scenario: SCENARIO }));
      }
      if (resource === 'summary') {
        return send(res, synthSummary(fx, q.get('event')));
      }
      if (resource === 'teams' && !seg[7]) {
        return send(res, synthTeams(fx));
      }
      if (resource === 'teams' && seg[7]) { // /teams/{id}/{schedule|roster|statistics}
        const teamId = seg[7], sub = seg[8];
        const parts = synthTeamDetailParts(registry, key, fx, teamId, { now });
        if (sub === 'schedule') return send(res, parts.schedule || { team: { id: teamId }, events: [] });
        if (sub === 'roster') return send(res, parts.roster || { athletes: [] });
        if (sub === 'statistics') return send(res, parts.stats || { results: {} });
      }
      if (resource === 'rankings') {
        return send(res, synthRankings(fx));
      }
      if (resource === 'leaderboard' && seg[8] === 'playersummary') {
        const eventId = seg[7], playerId = q.get('player');
        return send(res, synthGolfScorecard(registry, key, fx, eventId, playerId, { now }));
      }
    }

    // ---- core v2 standings: /apis/v2/sports/{sport}/{league}/standings -------
    if (seg[0] === 'apis' && seg[1] === 'v2' && seg[2] === 'sports' && seg[5] === 'standings') {
      const key = `${seg[3]}/${seg[4]}`;
      if (!known(key)) return send(res, { error: `unknown league "${key}"` }, 404);
      return send(res, synthStandings(fxFor(key)));
    }

    return send(res, { error: 'not found', path: url.pathname }, 404);
  } catch (e) {
    return send(res, { error: String(e?.stack || e?.message || e) }, 502);
  }
}

loadFixtures();
if (!fixtures.size) console.warn('⚠  No fixtures in mock/fixtures/. Run: node scripts/capture-fixtures.mjs\n');
http.createServer(handle).listen(PORT, '0.0.0.0', () => {
  const withEvents = [...fixtures.values()].filter((f) => f.events?.length).length;
  console.log(`Mock ESPN → http://localhost:${PORT}   (Android emulator: http://10.0.2.2:${PORT})`);
  console.log(`  ${fixtures.size} league fixtures (${withEvents} with events). Serves RAW ESPN shapes on ESPN paths.`);
  if (SCENARIO) console.log(`  🏆 scenario "${SCENARIO.name}" ON — every league lit up live now, championships staged across the week.`);
  console.log('  Point the app: Settings → set the API base override to this URL.\n');
});
