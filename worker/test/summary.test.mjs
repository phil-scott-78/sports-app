// Live smoke test for the /summary normalizer. Fetches real ESPN summaries and
// asserts canonical GameSummary invariants. Run: node test/summary.test.mjs
import registry from '../../schema/league-profiles.json' with { type: 'json' };
import { fetchSummary } from '../src/espn.js';
import { normalizeSummary, cleanSubText } from '../src/summary.js';

// stable historical events (persist on ESPN) across the team-sport families
const CASES = [
  { key: 'baseball/mlb', id: '401815738', want: ['Batting', 'Pitching'] },
  { key: 'basketball/nba', id: '401859966', quarters: 4 },
  { key: 'football/nfl', id: '401772988', want: ['Passing', 'Rushing'] },
  { key: 'hockey/nhl', id: '401874173', goals: true },
  { key: 'soccer/fifa.world', id: '760420', lineups: 2, subs: true },
];

let pass = 0, fail = 0;
const fails = [];
const ok = (c, m) => { if (c) pass++; else { fail++; fails.push(m); } };

// Deterministic (no network): the substitution lead-in stripper. The live case
// above only proves SOME sub is clean; these pin the edge cases — notably a club
// name with internal periods, which a naive "cut at first '.'" would mangle.
ok(cleanSubText('Substitution, Qatar. Ahmed Fathy replaces Ayoub Al Oui.') === 'Ahmed Fathy replaces Ayoub Al Oui.', 'sub: simple club');
ok(cleanSubText('Substitution, A.F.C. Bournemouth. Solanke replaces Ouattara.') === 'Solanke replaces Ouattara.', 'sub: dotted club name kept intact');
ok(cleanSubText('Substitution, Switzerland. Fabian Rieder replaces Michel Aebischer.') === 'Fabian Rieder replaces Michel Aebischer.', 'sub: full names');
ok(cleanSubText('Substitution, Real Madrid.') === 'Real Madrid.', 'sub: no "replaces" → drops only the keyword');

for (const t of CASES) {
  try {
    const raw = await fetchSummary(t.key, t.id);
    const s = normalizeSummary(registry, t.key, raw);
    ok(s.eventId === t.id, `${t.key}: eventId (${s.eventId})`);
    ok(Array.isArray(s.teamStats), `${t.key}: teamStats array`);
    ok(Array.isArray(s.boxGroups), `${t.key}: boxGroups array`);
    ok(Array.isArray(s.scoringPlays), `${t.key}: scoringPlays array`);
    for (const g of s.boxGroups) {
      ok(typeof g.title === 'string' && g.title, `${t.key}: box group has title`);
      for (const tm of g.teams)
        for (const r of tm.rows)
          ok(r.stats.length === g.columns.length || g.columns.length === 0,
            `${t.key} ${g.title}: row "${r.name}" stats align with columns (${r.stats.length} vs ${g.columns.length})`);
    }
    if (t.want) for (const w of t.want) ok(s.boxGroups.some(g => g.title === w), `${t.key}: has ${w} box group`);
    if (t.quarters) ok(s.periodLines?.labels.length === t.quarters, `${t.key}: ${t.quarters} period splits`);
    if (t.goals) ok(s.scoringPlays.some(p => /goal/i.test(p.text)), `${t.key}: goals in feed`);
    // soccer subs ride the rich feed (the cheap scoreboard has none) with the
    // verbose "Substitution, <Team>. " lead-in stripped → "X replaces Y."
    if (t.subs) ok(s.scoringPlays.some(p => /substitution/i.test(p.type || '') && /replaces/i.test(p.text) && !/^substitution/i.test(p.text)),
      `${t.key}: cleaned subs in scoring feed`);
    if (t.lineups) ok(s.lineups.length === t.lineups, `${t.key}: ${t.lineups} lineups`);
    console.log(`${t.key} — ${s.boxGroups.length} box groups, ${s.teamStats.length} team stats, ${s.scoringPlays.length} plays, ${s.lineups.length} lineups`);
  } catch (e) {
    fail++; fails.push(`${t.key}: threw ${e.message}`);
    console.log(`${t.key} — ERROR ${e.message}`);
  }
}

console.log(`\n${'='.repeat(48)}\n${pass} passed · ${fail} failed`);
if (fails.length) { console.log('\nFAILURES:'); for (const f of fails) console.log('  ✗ ' + f); }
process.exit(fail ? 1 : 0);
