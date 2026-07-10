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
import { normalizeStandings, extractGroupRecords } from '../src/standings.js';
import { normalizeTeamLeaders } from '../src/teamleaders.js';
import { normalizeRankings } from '../src/rankings.js';
import { normalizeGolfScorecard } from '../src/scorecard.js';
import { normalizeTeams, normalizeTeamCard, applyScoreboardFallback } from '../src/team.js';
import { normalizeTeamDetail } from '../src/teamdetail.js';
import { normalizeMmaSummary, buildCoreSituation, winProbabilityFromPredictor } from '../src/summary.js';
import { normalizeCompetitionOdds } from '../src/normalize.js';
import { classifyLeague, classifyMergedSlate } from '../src/overview.js';
import { normalizeVenueFacts, normalizeCircuitFacts } from '../src/venue.js';
import { normalizeMatchFeed } from '../src/matchfeed.js';
import { normalizeAthleteProfile } from '../src/athlete.js';
import { normalizeTournament } from '../src/tournament.js';
import { leagueKeys } from '../../schema/tools/resolve.mjs';
import { buildCatalog } from '../src/catalog.js';
import { applyOps, applyEventOps, normalizeFastcastSlate } from '../src/fastcast.js';

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
const counts = { scores: 0, summary: 0, standings: 0, teams: 0, rankings: 0, scorecard: 0, overview: 0, overviewMerged: 0, teamCard: 0, teamDetail: 0, mma: 0, odds: 0, matchfeed: 0, situationCore: 0, winprob: 0, venue: 0, circuit: 0, athlete: 0, teamLeaders: 0, standingsRecords: 0, tournament: 0, fastcast: 0 };
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

// ---- overviewMerged: classifyMergedSlate on synthesized '<sport>/all' slates --
// The merged pseudo-league (capability hasAllScoreboard) serves the SAME event
// objects the per-league scoreboards do, so each sport's merged input is
// synthesized by concatenating its committed fixtures' events — deterministic,
// no extra capture section needed.
{
  const bySport = new Map();
  for (const [key, fx] of fixtures) {
    const profile = resolve(registry, key);
    if (profile?.capabilities?.hasAllScoreboard !== true) continue;
    const sport = key.split('/')[0];
    if (!bySport.has(sport)) bySport.set(sport, []);
    bySport.get(sport).push(...(fx.events || []));
  }
  for (const [sport, events] of bySport) {
    const sb = { events };
    // Anchor "now" to the slate's own first event date (fixtures are dated at
    // capture time, not CLASSIFY_NOW) so the today/eastern-day bucketing is
    // actually exercised — still deterministic: derived from committed data.
    const nowMs = Date.parse(((events.find((e) => e && e.date) || {}).date) || '') || CLASSIFY_NOW_MS;
    const output = classifyMergedSlate(sb, new Date(nowMs));
    write('overviewMerged', sport, { sport, sb, nowMs }, output);
    index.push({ endpoint: 'overviewMerged', file: `overviewMerged/${sport}.json`, key: sport });
    counts.overviewMerged++;
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
  // soccer core match feed → canonical MatchFeed (the live-pitch/shot-map/momentum
  // source; capability hasMatchFeed). Team-relative coords, athlete/team $ref joins.
  for (const m of (extra?.matchFeeds || [])) {
    const { key, eventId, homeId, awayId, raw } = m;
    if (!raw) continue; // no soccer game at capture time
    const output = normalizeMatchFeed(raw, homeId, awayId);
    const name = `${fileKey(key)}__${eventId}`;
    write('matchfeed', name, { key, eventId, homeId, awayId, raw }, output);
    index.push({ endpoint: 'matchfeed', file: `matchfeed/${name}.json`, key, eventId });
    counts.matchfeed++;
  }
  // core competition-odds → canonical Odds (the pre-game moneyline enrichment).
  for (const o of (extra?.odds || [])) {
    const { key, eventId, competitionId, raw } = o;
    if (!raw) continue; // no scheduled game at capture time
    const output = normalizeCompetitionOdds(raw) ?? null;
    const name = `${fileKey(key)}__${eventId}`;
    write('odds', name, { key, eventId, competitionId, raw }, output);
    index.push({ endpoint: 'odds', file: `odds/${name}.json`, key, eventId });
    counts.odds++;
  }
  // Venue facts (§2.9): CORE venues/{id} → VenueFacts (stadium photo/surface/roof/
  // address; racing degrade = length/turns). Stable resource → evergreen goldens.
  for (const v of (extra?.venues || [])) {
    const { key, venueId, venue } = v;
    if (!venue) continue;
    const output = normalizeVenueFacts(venue) ?? null;
    const name = `${fileKey(key)}__${venueId}`;
    write('venue', name, { key, venueId, raw: venue }, output);
    index.push({ endpoint: 'venue', file: `venue/${name}.json`, key, venueId });
    counts.venue++;
  }
  // Circuit facts (§2.9): CORE circuits/{id} (+ resolved fastestLapDriver) →
  // CircuitFacts (track map + lap record). Reuses the racing capture's circuit doc.
  for (const r of (extra?.racing || [])) {
    const { key, circuit, fastestLapDriver } = r;
    if (!circuit || circuit.id == null) continue;
    const circuitId = String(circuit.id);
    const output = normalizeCircuitFacts(circuit, fastestLapDriver) ?? null;
    const name = `${fileKey(key)}__${circuitId}`;
    write('circuit', name, { key, circuitId, raw: circuit, driver: fastestLapDriver ?? null }, output);
    index.push({ endpoint: 'circuit', file: `circuit/${name}.json`, key, circuitId });
    counts.circuit++;
  }
  // Athlete/player profile (§2.6): identity + season stats + last-N game log, all
  // CORE-tier + fanned-out. The capture pre-resolves every $ref (identity/team/
  // statistics/games) exactly as api.dart does; the normalizer is pure map→map over
  // those. Covers both identity paths (MLB roster-row, WNBA core-athlete).
  for (const a of (extra?.athletes || [])) {
    if (!a || a.athleteId == null) continue;
    const { key, athleteId, identity, team, statistics, games } = a;
    const output = normalizeAthleteProfile(key, athleteId, { identity, team, statistics, games });
    const name = `${fileKey(key)}__${athleteId}`;
    write('athlete', name, { key, athleteId, identity, team, statistics, games }, output);
    index.push({ endpoint: 'athlete', file: `athlete/${name}.json`, key, athleteId });
    counts.athlete++;
  }
  // Team SEASON leaders (§2.6): the CORE leaders doc + the resolved-athlete map →
  // canonical TeamLeaders. The capture pre-resolves each top-leader athlete.$ref
  // exactly as api.dart does; the normalizer is pure over those.
  for (const l of (extra?.leaders || [])) {
    if (!l || l.teamId == null) continue;
    const { key, teamId, raw, athletes } = l;
    const output = normalizeTeamLeaders(key, teamId, raw, athletes || {});
    const name = `${fileKey(key)}__${teamId}`;
    write('teamLeaders', name, { key, teamId, raw, athletes: athletes || {} }, output);
    index.push({ endpoint: 'teamLeaders', file: `teamLeaders/${name}.json`, key, teamId });
    counts.teamLeaders++;
  }
  // Standings sub-records (§2.8): the committed site standings (fx.standings) merged
  // with the CORE group standings-id docs → extractGroupRecords → normalizeStandings.
  // Both inputs are real captures; the merge lands by (stable) team id.
  for (const s of (extra?.standingsRecords || [])) {
    if (!s || !s.key) continue;
    const { key, recordDocs } = s;
    const fx = fixtures.get(key);
    if (!fx?.standings || !Array.isArray(recordDocs) || !recordDocs.length) continue;
    const records = extractGroupRecords(recordDocs);
    const output = normalizeStandings(fx.standings, records);
    write('standingsRecords', fileKey(key), { key, raw: fx.standings, recordDocs }, output);
    index.push({ endpoint: 'standingsRecords', file: `standingsRecords/${fileKey(key)}.json`, key });
    counts.standingsRecords++;
  }
  // Standings qualification bands (§2.7/2.8): a FRESH soccer standings capture
  // that serves entries[].note {color, description} (the committed per-league
  // fixtures were captured band-less). Emitted onto the `standings` endpoint with
  // a `__notes` suffix so the existing standings parity test covers it for free.
  for (const s of (extra?.standingsNotes || [])) {
    if (!s || !s.key || !s.standings) continue;
    const output = normalizeStandings(s.standings);
    const name = `${fileKey(s.key)}__notes`;
    write('standings', name, { key: s.key, raw: s.standings }, output);
    index.push({ endpoint: 'standings', file: `standings/${name}.json`, key: `${s.key} (notes)` });
    counts.standings++;
  }
  // Tournaments (§2.7): the captured RAW range scoreboards (+ standings where the
  // profile has group tables) → canonical TournamentResponse. Three real 2026
  // tournaments cover all four grammars: WC groups+knockout (altGameNote rounds,
  // pens, shootout), the full Wimbledon draw (round.displayName, seeds, sets,
  // TBD placeholders), and the CWS pools + best-of-3 championship series.
  for (const t of (extra?.tournaments || [])) {
    if (!t || !t.key || !t.scoreboards?.length) continue;
    const args = { key: t.key, scoreboards: t.scoreboards };
    if (t.standings) args.standings = t.standings;
    if (t.grouping) args.grouping = t.grouping;
    if (t.eventId) args.eventId = t.eventId;
    const output = normalizeTournament(registry, t.key, args);
    write('tournament', fileKey(t.key), args, output);
    index.push({ endpoint: 'tournament', file: `tournament/${fileKey(t.key)}.json`, key: t.key });
    counts.tournament++;
  }
  // core situation + predictor → the detail-open enrichments. LIVE-only, so a golden
  // exists ONLY when a game was in progress at capture time (offseason leagues emit
  // nothing here; the guide-shaped unit tests keep the normalizer covered regardless).
  for (const s of (extra?.situation || [])) {
    const { key, eventId, situation, lastPlayText, predictor } = s;
    if (situation) {
      const output = buildCoreSituation(situation, lastPlayText) ?? null;
      const name = `${fileKey(key)}__${eventId}`;
      write('situationCore', name, { key, eventId, raw: situation, lastPlayText: lastPlayText ?? null }, output);
      index.push({ endpoint: 'situationCore', file: `situationCore/${name}.json`, key, eventId });
      counts.situationCore++;
    }
    if (predictor) {
      const output = winProbabilityFromPredictor(predictor) ?? null;
      const name = `${fileKey(key)}__${eventId}`;
      write('winprob', name, { key, eventId, raw: predictor }, output);
      index.push({ endpoint: 'winprob', file: `winprob/${name}.json`, key, eventId });
      counts.winprob++;
    }
  }
}

// ---- fastcast goldens: replay the captured push streams (fastcast-plan.md) ----
// Per committed capture (mock/fixtures/fastcast/): apply every patch frame in
// mid order — applyEventOps for event-* topics, applyOps for gp-* — and emit
// {args: the whole capture, output: {finalDoc, errors, slates?}}. `slates` (event
// topics only) is normalizeFastcastSlate at the checkpoint and after each frame,
// so the Dart port's applier AND normalizer are pinned stage by stage; gp topics
// pin the final doc byte-for-byte (the summary normalizer already has its own
// goldens — the gp checkpoint is summary-shaped by verified design).
{
  const FC_DIR = join(FIX_DIR, 'fastcast');
  let files = [];
  try { files = readdirSync(FC_DIR).filter((f) => f.endsWith('.json')); } catch { /* not captured */ }
  for (const f of files) {
    const fx = JSON.parse(readFileSync(join(FC_DIR, f), 'utf8'));
    const isGp = fx.topic.startsWith('gp-');
    const key = isGp ? null : fx.topic.replace(/^event-/, '').replace('-', '/');
    let doc = fx.checkpoint;
    const errors = [];
    const slates = key ? [normalizeFastcastSlate(registry, key, doc)] : null;
    for (const frame of fx.frames) {
      if (!frame.ops) continue;
      const r = isGp ? applyOps(doc, frame.ops) : applyEventOps(doc, frame.ops);
      doc = r.doc;
      errors.push(...r.errors);
      if (slates) slates.push(normalizeFastcastSlate(registry, key, doc));
    }
    const name = fx.topic;
    const output = { finalDoc: doc, errors };
    if (slates) output.slates = slates;
    write('fastcast', name, { topic: fx.topic, key, checkpoint: fx.checkpoint, frames: fx.frames }, output);
    index.push({ endpoint: 'fastcast', file: `fastcast/${name}.json`, key: key ?? fx.topic });
    counts.fastcast++;
    // The gp checkpoint IS a summary payload captured mid-broadcast — the only
    // committed baseball feed with pitch coordinates/types (final-game summary
    // captures ship types but no coords). Pin normalizeSummary on it too so the
    // Dart port's strike-zone inputs are golden-verified.
    if (isGp) {
      const seg = fx.topic.replace(/^gp-/, '').split('-');
      const eventId = seg.pop();
      const gpKey = `${seg.shift()}/${seg.join('-')}`;
      const gpName = `${fileKey(gpKey)}__${eventId}`;
      write('summary', gpName, { key: gpKey, eventId, raw: fx.checkpoint },
        blankUpdated(normalizeSummary(registry, gpKey, fx.checkpoint)));
      index.push({ endpoint: 'summary', file: `summary/${gpName}.json`, key: gpKey, eventId });
      counts.summary++;
    }
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
