// gen-goldens.mjs — Phase 0 of the "drop the worker" port (see drop-the-worker.md).
//
// Runs every committed RAW fixture (mock/fixtures/) through the EXISTING JS
// normalizers and writes {args, output} golden pairs to app/test/fixtures/golden/.
// These are the acceptance test for the Dart normalizer port: the Dart code must
// produce deep-equal `output` when fed the same `args`.
//
//   node scripts/gen-goldens.mjs
//
// The inputs here are real ESPN shapes (the raw fixtures), exactly what the Dart
// espn_client will hand the Dart normalizers in production — so parity against
// these goldens is parity against reality, not against a synth fabrication.
//
// The ONLY non-deterministic field any normalizer emits is the scoreboard's
// `updated: new Date().toISOString()`; we blank it to null in the golden and the
// Dart test blanks it on both sides before comparing. Everything else is a pure
// function of the raw input.

import { readFileSync, readdirSync, writeFileSync, mkdirSync, rmSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import registry from '../../schema/league-profiles.json' with { type: 'json' };
import { resolve } from '../../schema/tools/resolve.mjs';
import { normalizeScoreboard } from '../src/normalize.js';
import { normalizeSummary } from '../src/summary.js';
import { normalizeStandings } from '../src/standings.js';
import { normalizeRankings } from '../src/rankings.js';
import { normalizeGolfScorecard } from '../src/scorecard.js';
import { normalizeTeams, normalizeTeamCard, applyScoreboardFallback } from '../src/team.js';
import { normalizeTeamDetail } from '../src/teamdetail.js';
import { normalizeMmaSummary } from '../src/summary.js';
import { classifyLeague } from '../src/overview.js';
import { leagueKeys } from '../../schema/tools/resolve.mjs';
import { buildCatalog } from '../src/catalog.js';

// Fixed reference instant for the deterministic overview-classifier goldens.
const CLASSIFY_NOW_MS = Date.parse('2026-07-06T20:00:00.000Z');

const HERE = dirname(fileURLToPath(import.meta.url));
const FIX_DIR = join(HERE, '..', 'mock', 'fixtures');
const OUT_DIR = join(HERE, '..', '..', 'app', 'test', 'fixtures', 'golden');

const fileKey = (key) => key.replace(/\//g, '__');
// Deterministic: blank the one wall-clock field so JS and Dart agree.
const blankUpdated = (o) => { if (o && typeof o === 'object' && 'updated' in o) o.updated = null; return o; };

function loadFixtures() {
  const out = new Map();
  const files = readdirSync(FIX_DIR).filter((f) => f.endsWith('.json') && f !== '_manifest.json');
  for (const f of files) {
    const fx = JSON.parse(readFileSync(join(FIX_DIR, f), 'utf8'));
    if (fx.key) out.set(fx.key, fx);
  }
  return out;
}

function write(endpoint, name, args, output) {
  const dir = join(OUT_DIR, endpoint);
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, `${name}.json`), JSON.stringify({ endpoint, args, output }, null, 2));
}

// Rebuild from scratch so a removed fixture doesn't leave a stale golden.
try { rmSync(OUT_DIR, { recursive: true, force: true }); } catch { /* first run */ }

const fixtures = loadFixtures();
const counts = { scores: 0, summary: 0, standings: 0, teams: 0, rankings: 0, scorecard: 0, overview: 0, teamCard: 0, teamDetail: 0, mma: 0 };
const index = []; // manifest of every golden, for the Dart test to enumerate

for (const [key, fx] of fixtures) {
  const profile = resolve(registry, key);

  // ---- scores (raw scoreboard → canonical) — the big one, every league --------
  {
    const sb = { events: fx.events || [], leagues: fx.league ? [fx.league] : [], day: fx.day || undefined };
    // golf: meta.golf rides the captured core tournament resource (fx.tournaments,
    // keyed by event id) exactly as the worker's golfExtras() passes it in.
    const extras = fx.tournaments && Object.keys(fx.tournaments).length
      ? { golfTournaments: fx.tournaments } : {};
    const output = blankUpdated(normalizeScoreboard(registry, key, sb, extras));
    write('scores', fileKey(key), { key, sb, extras }, output);
    index.push({ endpoint: 'scores', file: `scores/${fileKey(key)}.json`, key });
    counts.scores++;
  }

  // ---- summary (rich detail) — leagues that captured any -----------------------
  // MMA is built from core resources (no raw /summary capture) — covered by the
  // synth-fed Set B goldens, not here.
  if (fx.summaries && profile.espnSport !== 'mma') {
    for (const [eventId, raw] of Object.entries(fx.summaries)) {
      if (!raw) continue;
      const output = blankUpdated(normalizeSummary(registry, key, raw));
      const name = `${fileKey(key)}__${eventId}`;
      write('summary', name, { key, eventId, raw }, output);
      index.push({ endpoint: 'summary', file: `summary/${name}.json`, key, eventId });
      counts.summary++;
    }
  }

  // ---- standings ---------------------------------------------------------------
  if (fx.standings) {
    const output = normalizeStandings(fx.standings);
    write('standings', fileKey(key), { key, raw: fx.standings }, output);
    index.push({ endpoint: 'standings', file: `standings/${fileKey(key)}.json`, key });
    counts.standings++;
  }

  // ---- teams (favorites picker) ------------------------------------------------
  if (fx.teams) {
    const output = normalizeTeams(registry, key, fx.teams);
    write('teams', fileKey(key), { key, raw: fx.teams }, output);
    index.push({ endpoint: 'teams', file: `teams/${fileKey(key)}.json`, key });
    counts.teams++;
  }

  // ---- rankings (polls / tours / divisions) ------------------------------------
  if (fx.rankings) {
    const output = normalizeRankings(fx.rankings);
    write('rankings', fileKey(key), { key, raw: fx.rankings }, output);
    index.push({ endpoint: 'rankings', file: `rankings/${fileKey(key)}.json`, key });
    counts.rankings++;
  }

  // ---- golf scorecard (hole-by-hole) — keyed "eventId/playerId" ----------------
  if (fx.scorecards) {
    for (const [k, raw] of Object.entries(fx.scorecards)) {
      if (!raw) continue;
      const [eventId, playerId] = k.split('/');
      const output = normalizeGolfScorecard(key, eventId, playerId, raw);
      const name = `${fileKey(key)}__${eventId}__${playerId}`;
      write('scorecard', name, { key, eventId, playerId, raw }, output);
      index.push({ endpoint: 'scorecard', file: `scorecard/${name}.json`, key, eventId, playerId });
      counts.scorecard++;
    }
  }

  // ---- overview: classifyLeague on the raw scoreboard (fixed now) ------------
  {
    const sb = { events: fx.events || [], leagues: fx.league ? [fx.league] : [], day: fx.day || undefined };
    const output = classifyLeague(sb, new Date(CLASSIFY_NOW_MS));
    write('overview', fileKey(key), { key, sb, nowMs: CLASSIFY_NOW_MS }, output);
    index.push({ endpoint: 'overview', file: `overview/${fileKey(key)}.json`, key });
    counts.overview++;
  }
}

// ---- Set B goldens from the live-captured raw inputs (_extra.json) -----------
// team.js card path (+ scoreboard fallback), teamdetail.js, and MMA summary — the
// normalizers whose raw inputs aren't in the committed per-league fixtures.
{
  let extra = null;
  try { extra = JSON.parse(readFileSync(join(FIX_DIR, '_extra.json'), 'utf8')); } catch { /* not captured */ }
  for (const t of (extra?.teams || [])) {
    const { key, teamId, schedule, roster, stats, standingsRaw } = t;
    const fx = fixtures.get(key);
    const sb = fx ? { events: fx.events || [], leagues: fx.league ? [fx.league] : [], day: fx.day || undefined } : { events: [] };
    // card path: normalizeTeamCard, then scoreboard fallback when no live game
    // (mirrors worker/src/index.js /team route).
    let card = normalizeTeamCard(registry, key, teamId, schedule);
    if (!card.live) {
      try { card = applyScoreboardFallback(registry, key, teamId, card, sb); } catch { /* keep card */ }
    }
    const cardName = `${fileKey(key)}__${teamId}`;
    write('teamCard', cardName, { key, teamId, schedule, sb }, card);
    index.push({ endpoint: 'teamCard', file: `teamCard/${cardName}.json`, key, teamId });
    counts.teamCard++;

    const detail = normalizeTeamDetail(registry, key, teamId, { schedule, roster, stats, standingsRaw });
    write('teamDetail', cardName, { key, teamId, schedule, roster, stats, standingsRaw }, detail);
    index.push({ endpoint: 'teamDetail', file: `teamDetail/${cardName}.json`, key, teamId });
    counts.teamDetail++;
  }
  for (const m of (extra?.mma || [])) {
    const { key, eventId, coreEvent, statuses, linescores } = m;
    const output = normalizeMmaSummary(coreEvent, statuses, linescores);
    const name = `${fileKey(key)}__${eventId}`;
    write('mma', name, { key, eventId, coreEvent, statuses, linescores }, output);
    index.push({ endpoint: 'mma', file: `mma/${name}.json`, key, eventId });
    counts.mma++;
  }
}

// ---- meta goldens: the Phase 1 foundation (resolve / leagueKeys / catalog) ----
// These verify the Dart port of resolve.mjs + catalog.js, independent of any
// fixture. resolve() every concrete league key; snapshot a few leagueKeys filters
// and the full catalog.
{
  const dir = join(OUT_DIR, 'meta');
  mkdirSync(dir, { recursive: true });
  const allKeys = leagueKeys(registry);
  const resolved = {};
  for (const k of allKeys) resolved[k] = resolve(registry, k);
  writeFileSync(join(dir, 'resolve.json'), JSON.stringify(resolved, null, 2));
  writeFileSync(join(dir, 'leagueKeys.json'), JSON.stringify({
    all: allKeys,
    v1: leagueKeys(registry, { priority: 'v1' }),
    v1v2: leagueKeys(registry, { priority: ['v1', 'v2'] }),
    soccer: leagueKeys(registry, { sport: 'soccer' }),
  }, null, 2));
  writeFileSync(join(dir, 'catalog.json'), JSON.stringify(buildCatalog(registry), null, 2));
  writeFileSync(join(dir, 'catalog_v1.json'), JSON.stringify(buildCatalog(registry, { priority: 'v1' }), null, 2));
}

mkdirSync(OUT_DIR, { recursive: true });
writeFileSync(join(OUT_DIR, 'index.json'), JSON.stringify(index, null, 2));

const total = Object.values(counts).reduce((a, b) => a + b, 0);
console.log(`Golden pairs written → ${OUT_DIR}`);
for (const [k, v] of Object.entries(counts)) console.log(`  ${k.padEnd(12)} ${v}`);
console.log(`  ${'TOTAL'.padEnd(12)} ${total}  (index.json lists all)`);
