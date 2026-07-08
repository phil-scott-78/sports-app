// capture-extra.mjs — one-time capture of the RAW ESPN inputs that the committed
// mock fixtures don't carry (team schedule/roster/stats, MMA core event + per-bout
// refs). Needed so the Dart port of team.js / teamdetail.js / summary.js(MMA) can
// be golden-verified against real ESPN shapes. Commits worker/mock/fixtures/
// _extra.json; gen-goldens.mjs reads it (no network at golden-gen time).
//
//   node scripts/capture-extra.mjs
//
// Uses the same espn.js fetchers + the same MMA ref-following the worker route does.

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  fetchTeamSchedule, fetchTeamRoster, fetchTeamStatistics, fetchStandings,
  fetchCoreEvent, fetchCoreRef,
} from '../src/espn.js';

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = join(HERE, '..', 'mock', 'fixtures', '_extra.json');

// team pages to capture (key, teamId). NBA = flat roster; a World Cup national
// team = the schedule-fallback path (events:[] → scoreboard backfill).
const TEAM_CASES = [
  { key: 'basketball/nba', teamId: '1' },
  { key: 'soccer/fifa.world', teamId: '624' },
];
const MMA_CASES = [{ key: 'mma/ufc', eventId: '600058854' }];
// racing: the site /summary 404s, so the rich detail (circuit dossier + the
// dark-SVG track MAP) is core-only — event → circuit.$ref → the circuit doc, which
// the cheap scoreboard's {id,fullName,address} circuit block does NOT carry. Spa
// (event 600057439 → circuit 616) is a stable, evergreen snapshot.
const RACING_CASES = [{ key: 'racing/f1', eventId: '600057439' }];
// Championship & award futures (title odds / MVP race) — season-scoped, so a
// stable snapshot: leagues/{}/seasons/{yr}/futures → items[].futures[].books[] =
// per-book {team|athlete:$ref, value:"+350"} American-odds lines. Core-only.
const FUTURES_CASES = [
  { key: 'baseball/mlb', season: '2026' },
  { key: 'basketball/nba', season: '2026' },
  { key: 'football/nfl', season: '2026' },
  { key: 'hockey/nhl', season: '2026' },
];
// Player salary/cap: athletes/{id}/contracts → items are per-season $ref stubs;
// resolving one yields salary + Bird status, trade kicker, cap exceptions, etc.
const CONTRACT_CASES = [{ key: 'basketball/nba', teamId: '1' }];

async function captureTeam({ key, teamId }) {
  const [schedule, roster, stats, standingsRaw] = await Promise.all([
    fetchTeamSchedule(key, teamId).catch(() => null),
    fetchTeamRoster(key, teamId).catch(() => null),
    fetchTeamStatistics(key, teamId).catch(() => null),
    fetchStandings(key).catch(() => null),
  ]);
  return { key, teamId, schedule, roster, stats, standingsRaw };
}

// Mirror worker/src/index.js mmaSummary(): core event → per-bout status refs →
// judge linescore refs (decisions only).
async function captureMma({ key, eventId }) {
  const core = await fetchCoreEvent(key, eventId);
  const comps = Array.isArray(core?.competitions) ? core.competitions : [];
  const statuses = {};
  await Promise.all(comps.map(async (c) => {
    const ref = c?.status?.$ref;
    if (!c?.id || !ref) return;
    try { statuses[String(c.id)] = await fetchCoreRef(ref); } catch { /* skip */ }
  }));
  const linescores = {};
  await Promise.all(comps.flatMap((c) => {
    const st = statuses[String(c?.id)];
    if (!/decision/i.test(st?.result?.name || st?.result?.displayName || '')) return [];
    return (c.competitors || []).map(async (comp) => {
      const ref = comp?.linescores?.$ref;
      if (!ref) return;
      try { linescores[`${c.id}/${comp.id}`] = await fetchCoreRef(ref); } catch { /* skip */ }
    });
  }));
  return { key, eventId, coreEvent: core, statuses, linescores };
}

// Mirror the MMA path: core event → circuit.$ref (the circuit dossier + track-map
// diagrams the scoreboard lacks), the lap-record holder athlete behind
// fastestLapDriver.$ref (a nice delighter), and each session's statistics.$ref
// (laps/pole/avgSpeed — .000 until the session runs).
async function captureRacing({ key, eventId }) {
  const core = await fetchCoreEvent(key, eventId);
  const comps = Array.isArray(core?.competitions) ? core.competitions : [];
  let circuit = null;
  let fastestLapDriver = null;
  const circRef = core?.circuit?.$ref;
  if (circRef) {
    try { circuit = await fetchCoreRef(circRef); } catch { /* skip */ }
    const drvRef = circuit?.fastestLapDriver?.$ref;
    if (drvRef) { try { fastestLapDriver = await fetchCoreRef(drvRef); } catch { /* skip */ } }
  }
  const statistics = {};
  await Promise.all(comps.map(async (c) => {
    const ref = c?.statistics?.$ref;
    if (!c?.id || !ref) return;
    try { statistics[String(c.id)] = await fetchCoreRef(ref); } catch { /* skip */ }
  }));
  return { key, eventId, coreEvent: core, circuit, fastestLapDriver, statistics };
}

function corePath(key) { return key.replace('/', '/leagues/'); } // baseball/mlb → baseball/leagues/mlb

async function captureFutures({ key, season }) {
  const url = `https://sports.core.api.espn.com/v2/sports/${corePath(key)}/seasons/${season}/futures?lang=en&region=us`;
  let futures = null;
  try { futures = await fetchCoreRef(url); } catch { /* skip */ }
  return { key, season, futures };
}

async function captureContracts({ key, teamId }) {
  const roster = await fetchTeamRoster(key, teamId).catch(() => null);
  const athItem = roster?.athletes?.[0]?.items?.[0] || roster?.athletes?.[0];
  const aid = athItem?.id;
  if (!aid) return { key, teamId, athlete: null, contracts: [] };
  const listUrl = `https://sports.core.api.espn.com/v2/sports/${corePath(key)}/athletes/${aid}/contracts?lang=en&region=us`;
  const list = await fetchCoreRef(listUrl).catch(() => null);
  const contracts = [];
  for (const it of (list?.items || [])) {
    if (it?.$ref) { try { contracts.push(await fetchCoreRef(it.$ref)); } catch { /* skip */ } }
    else contracts.push(it);
  }
  return { key, teamId, athlete: { id: aid, displayName: athItem?.displayName }, contracts };
}

// --only <section...> re-captures just those sections and MERGES onto the existing
// file, so a targeted `--only racing` run doesn't refresh (and risk drifting the
// committed goldens of) team/mma. No arg = full regen of every section.
const onlyIdx = process.argv.indexOf('--only');
const ONLY = onlyIdx >= 0 ? process.argv.slice(onlyIdx + 1).filter((a) => !a.startsWith('--')) : null;
const want = (section) => !ONLY || ONLY.includes(section);

const out = existsSync(OUT) ? JSON.parse(readFileSync(OUT, 'utf8')) : {};
out.capturedAt = new Date().toISOString();
out.teams ||= [];
out.mma ||= [];
out.racing ||= [];
out.futures ||= [];
out.contracts ||= [];

if (want('teams')) {
  out.teams = [];
  for (const t of TEAM_CASES) {
    out.teams.push(await captureTeam(t));
    console.log(`✓ team ${t.key}/${t.teamId}`);
  }
}
if (want('mma')) {
  out.mma = [];
  for (const m of MMA_CASES) {
    out.mma.push(await captureMma(m));
    console.log(`✓ mma ${m.key}/${m.eventId} (${out.mma[out.mma.length - 1].coreEvent?.competitions?.length ?? 0} bouts)`);
  }
}
if (want('racing')) {
  out.racing = [];
  for (const r of RACING_CASES) {
    out.racing.push(await captureRacing(r));
    const last = out.racing[out.racing.length - 1];
    console.log(`✓ racing ${r.key}/${r.eventId} — circuit: ${last.circuit?.fullName ?? '(none)'}, `
      + `diagrams: ${last.circuit?.diagrams?.length ?? 0}, sessions: ${last.coreEvent?.competitions?.length ?? 0}`);
  }
}
if (want('futures')) {
  out.futures = [];
  for (const f of FUTURES_CASES) {
    out.futures.push(await captureFutures(f));
    console.log(`✓ futures ${f.key} ${f.season} — ${out.futures[out.futures.length - 1].futures?.items?.length ?? 0} markets`);
  }
}
if (want('contracts')) {
  out.contracts = [];
  for (const c of CONTRACT_CASES) {
    out.contracts.push(await captureContracts(c));
    const last = out.contracts[out.contracts.length - 1];
    console.log(`✓ contracts ${c.key} — ${last.athlete?.displayName ?? '?'}: ${last.contracts.length} seasons, `
      + `latest salary ${last.contracts[0]?.salary ?? '?'}`);
  }
}
writeFileSync(OUT, JSON.stringify(out));
console.log(`\nWrote ${OUT}`);
