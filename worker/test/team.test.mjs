// Live smoke test for the team endpoints. Fetches real ESPN team lists +
// schedules and asserts the canonical favorite-team shapes. Run:
//   node test/team.test.mjs
// (no wrangler/build needed — the normalizers are pure.)

import registry from '../../schema/league-profiles.json' with { type: 'json' };
import { fetchTeams, fetchTeamSchedule } from '../src/espn.js';
import { normalizeTeams, normalizeTeamCard } from '../src/team.js';

const PHASES = new Set(['scheduled', 'live', 'final', 'postponed', 'suspended', 'canceled', 'abandoned', 'delayed', 'unknown']);

let pass = 0, fail = 0;
const fails = [];
const ok = (cond, msg) => { if (cond) pass++; else { fail++; fails.push(msg); } };

function checkEvent(label, ev) {
  ok(typeof ev.id === 'string' && ev.id, `${label}: event id set`);
  ok(Array.isArray(ev.competitions) && ev.competitions.length > 0, `${label}: has competitions`);
  const c = ev.competitions[0];
  if (c) ok(PHASES.has(c.status.phase), `${label}: valid phase (${c.status?.phase})`);
  return c;
}

// teams list: every league should return a sane, sorted, unique set
const TEAM_CASES = [
  { key: 'basketball/nba', min: 20 },
  { key: 'soccer/eng.1', min: 18 }, // EPL ~20
];

for (const { key, min } of TEAM_CASES) {
  try {
    const teams = normalizeTeams(registry, key, await fetchTeams(key));
    ok(teams.length >= min, `${key}: teams.length >= ${min} (got ${teams.length})`);
    ok(teams.every(t => t.id && t.displayName), `${key}: every team has id + displayName`);
    ok(new Set(teams.map(t => t.id)).size === teams.length, `${key}: team ids unique`);
    ok(teams.some(t => t.logo), `${key}: at least one team has a logo`);
    const sorted = [...teams].sort((a, b) => a.displayName.localeCompare(b.displayName));
    ok(JSON.stringify(sorted.map(t => t.id)) === JSON.stringify(teams.map(t => t.id)), `${key}: teams sorted by name`);
    console.log(`\n${key} — ${teams.length} teams (e.g. ${teams.slice(0, 3).map(t => t.displayName).join(', ')})`);

    // team card for the first team in the (sorted) list
    const t0 = teams[0];
    const card = normalizeTeamCard(registry, key, t0.id, await fetchTeamSchedule(key, t0.id));
    ok(card.league === key, `${key}: card.league set`);
    ok(typeof card.sport === 'string' && card.sport, `${key}: card.sport non-empty`);
    ok(typeof card.leagueName === 'string' && card.leagueName, `${key}: card.leagueName non-empty`);
    ok(card.team && card.team.id === String(t0.id), `${key}: card.team.id matches (${card.team?.id} vs ${t0.id})`);
    ok(typeof card.anyLive === 'boolean', `${key}: anyLive boolean`);

    if (card.live) {
      const c = checkEvent(`${key} live`, card.live);
      ok(c?.status.live === true, `${key}: live event is live`);
      ok(card.anyLive === true, `${key}: anyLive true when live present`);
    }
    if (card.last) {
      const c = checkEvent(`${key} last`, card.last);
      ok(c?.status.ended || c?.status.phase === 'final', `${key}: last event ended/final`);
    }
    if (card.next) {
      const c = checkEvent(`${key} next`, card.next);
      ok(c?.status.phase === 'scheduled', `${key}: next event scheduled`);
    }
    if (card.last && card.next) {
      ok(Date.parse(card.next.start) >= Date.parse(card.last.start), `${key}: next.start >= last.start`);
    }
    const tag = card.live ? 'LIVE' : card.last ? 'has-last' : card.next ? 'has-next' : 'empty(offseason)';
    console.log(`  card ${t0.displayName} [${card.team.record ?? '—'}] · ${tag}`);
  } catch (e) {
    fail++; fails.push(`${key}: threw ${e.message}`);
    console.log(`\n${key} — ERROR ${e.message}`);
  }
}

console.log(`\n${'='.repeat(48)}\n${pass} passed · ${fail} failed`);
if (fails.length) { console.log('\nFAILURES:'); for (const f of fails) console.log('  ✗ ' + f); }
process.exit(fail ? 1 : 0);
