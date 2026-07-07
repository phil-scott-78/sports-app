// capture-extra.mjs — one-time capture of the RAW ESPN inputs that the committed
// mock fixtures don't carry (team schedule/roster/stats, MMA core event + per-bout
// refs). Needed so the Dart port of team.js / teamdetail.js / summary.js(MMA) can
// be golden-verified against real ESPN shapes. Commits worker/mock/fixtures/
// _extra.json; gen-goldens.mjs reads it (no network at golden-gen time).
//
//   node scripts/capture-extra.mjs
//
// Uses the same espn.js fetchers + the same MMA ref-following the worker route does.

import { writeFileSync } from 'node:fs';
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

const out = { capturedAt: new Date().toISOString(), teams: [], mma: [] };
for (const t of TEAM_CASES) {
  out.teams.push(await captureTeam(t));
  console.log(`✓ team ${t.key}/${t.teamId}`);
}
for (const m of MMA_CASES) {
  out.mma.push(await captureMma(m));
  console.log(`✓ mma ${m.key}/${m.eventId} (${out.mma[out.mma.length - 1].coreEvent?.competitions?.length ?? 0} bouts)`);
}
writeFileSync(OUT, JSON.stringify(out));
console.log(`\nWrote ${OUT}`);
