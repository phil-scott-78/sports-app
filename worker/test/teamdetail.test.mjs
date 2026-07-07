// Live smoke test for the team-detail endpoint. Fetches real ESPN team
// schedule + roster + statistics + standings and asserts the canonical
// TeamDetailResponse shape, exercising both roster shapes (NBA flat / NFL
// grouped), soccer's tolerated-empty stats, and a college league. Run:
//   node test/teamdetail.test.mjs
// (no wrangler/build needed — the normalizers are pure.)

import registry from '../../schema/league-profiles.json' with { type: 'json' };
import { resolve } from '../../schema/tools/resolve.mjs';
import { fetchTeams, fetchTeamSchedule, fetchTeamRoster, fetchTeamStatistics, fetchStandings } from '../src/espn.js';
import { normalizeTeams } from '../src/team.js';
import { normalizeTeamDetail } from '../src/teamdetail.js';

let pass = 0, fail = 0;
const fails = [];
const ok = (cond, msg) => { if (cond) pass++; else { fail++; fails.push(msg); } };

const CASES = [
  { key: 'basketball/nba', roster: 'flat' },
  { key: 'football/nfl', roster: 'grouped' },
  { key: 'soccer/eng.1', statsMayBeEmpty: true }, // EPL returns empty results:{} (offseason)
  { key: 'basketball/mens-college-basketball' },  // a college league
];

for (const cse of CASES) {
  const { key } = cse;
  try {
    const teams = normalizeTeams(registry, key, await fetchTeams(key));
    ok(teams.length > 0, `${key}: teams list non-empty (${teams.length})`);
    if (!teams.length) continue;
    const t0 = teams[0];

    const [schedule, roster, stats, standingsRaw] = await Promise.all([
      fetchTeamSchedule(key, t0.id),
      fetchTeamRoster(key, t0.id).catch(() => null),
      fetchTeamStatistics(key, t0.id).catch(() => null),
      fetchStandings(key).catch(() => null),
    ]);
    const d = normalizeTeamDetail(registry, key, t0.id, { schedule, roster, stats, standingsRaw });

    ok(d.league === key && d.team.id === String(t0.id), `${key}: identity (league + team id)`);

    // schedule: array, start-ascending
    ok(Array.isArray(d.schedule), `${key}: schedule is array (${d.schedule.length})`);
    const starts = d.schedule.map(e => Date.parse(e.start) || 0);
    ok(starts.every((s, i) => i === 0 || s >= starts[i - 1]), `${key}: schedule sorted ascending`);

    // roster: two shapes discriminated structurally
    ok(Array.isArray(d.roster), `${key}: roster is array (${d.roster.length} groups)`);
    if (d.roster.length) {
      ok(d.roster.every(g => g.name && Array.isArray(g.athletes)), `${key}: every roster group has name + athletes[]`);
      ok(d.roster.some(g => g.athletes.some(a => a.id && a.name)), `${key}: ≥1 athlete carries id + name`);
      if (cse.roster === 'grouped') ok(d.roster.length > 1, `${key}: grouped roster → multiple position groups (${d.roster.map(g => g.name).join('/')})`);
      if (cse.roster === 'flat') ok(d.roster.length === 1 && d.roster[0].name === 'Roster', `${key}: flat roster → single "Roster" group (got ${d.roster.map(g => g.name).join('/')})`);
    }

    // stats: array; soccer may be empty. When curated (teamStatKeys) + present → one 'Season' group.
    ok(Array.isArray(d.stats), `${key}: stats is array (${d.stats.length} groups)`);
    ok(d.stats.every(g => g.stats.every(s => typeof s.value === 'string')), `${key}: stat values are strings`);
    if (!cse.statsMayBeEmpty) ok(d.stats.length > 0, `${key}: season stats present`);
    if (d.stats.length && Array.isArray(resolve(registry, key).teamStatKeys)) {
      ok(d.stats.length === 1 && d.stats[0].name === 'Season', `${key}: curated stats collapse to one 'Season' group`);
    }

    // standing: when present, contains this team's row
    if (d.standing) ok(d.standing.rows.some(r => r.team.id === String(t0.id)), `${key}: standing group contains the team`);

    console.log(`\n${key} — ${t0.displayName}: schedule=${d.schedule.length} roster=${d.roster.length}g stats=${d.stats.length}g standing=${d.standing ? d.standing.groupName : '—'}`);
  } catch (e) {
    fail++; fails.push(`${key}: threw ${e.message}`);
    console.log(`\n${key} — ERROR ${e.message}`);
  }
}

console.log(`\n${'='.repeat(48)}\n${pass} passed · ${fail} failed`);
if (fails.length) { console.log('\nFAILURES:'); for (const f of fails) console.log('  ✗ ' + f); }
process.exit(fail ? 1 : 0);
