// Deterministic unit tests (no network) for the audit-fix pure functions, run
// against synthetic ESPN shapes so each fix is pinned against regression.
// Run: node test/units.test.mjs

import registry from '../../schema/league-profiles.json' with { type: 'json' };
import { normalizeScoreboard } from '../src/normalize.js';
import { normalizeTeamCard, applyScoreboardFallback } from '../src/team.js';

let pass = 0, fail = 0;
const fails = [];
const ok = (cond, msg) => { if (cond) pass++; else { fail++; fails.push(msg); } };

// Build a minimal scoreboard wrapper around one competition's competitors + status.
const sb = (key, { status, competitors, details, period, displayClock }) => ({
  leagues: [{ id: '1', slug: key.split('/')[1], name: '', season: {} }],
  events: [{
    id: '1', date: '2026-06-14T18:00:00Z', name: 'A v B', shortName: 'A v B',
    // displayClock lives on competition.status (sibling of type), per ESPN.
    competitions: [{ id: '1', status: { type: status, period, displayClock }, competitors, details }],
  }],
});
const comp0 = (key, ev) => normalizeScoreboard(registry, key, sb(key, ev)).events[0].competitions[0];
const FINAL = { name: 'STATUS_FINAL', state: 'post', completed: true, detail: 'Final', shortDetail: 'Final' };

// ---- C2: team-schedule serializes score as {value,displayValue} (object) -----
{
  const schedule = {
    team: { id: '24', displayName: 'San Antonio Spurs', abbreviation: 'SA' },
    events: [{
      id: '9', date: '2026-06-13T00:30:00Z', shortName: 'NY @ SA',
      competitions: [{
        id: '9', status: { type: FINAL, period: 4 },
        competitors: [
          { id: '24', homeAway: 'home', winner: false, score: { value: 90, displayValue: '90' }, team: { id: '24', abbreviation: 'SA' } },
          { id: '18', homeAway: 'away', winner: true, score: { value: 94, displayValue: '94' }, team: { id: '18', abbreviation: 'NY' } },
        ],
      }],
    }],
  };
  const card = normalizeTeamCard(registry, 'basketball/nba', '24', schedule);
  const sa = card.last?.competitions[0].competitors.find(c => c.abbreviation === 'SA');
  ok(sa?.score?.display === '90', `C2: object score coerced to "90" (got ${JSON.stringify(sa?.score?.display)})`);
  ok(sa?.score?.value === 90, `C2: object score value parsed (got ${sa?.score?.value})`);
}

// ---- H8: baseball extra-inning final is NOT "overtime" -----------------------
{
  const ls = n => Array.from({ length: n }, (_, i) => ({ period: i + 1, value: 1, displayValue: '1' }));
  const c = comp0('baseball/mlb', {
    status: { ...FINAL, detail: 'Final/10' }, period: 10,
    competitors: [
      { id: '1', homeAway: 'home', winner: true, score: '5', team: { id: '1', abbreviation: 'H' }, linescores: ls(10) },
      { id: '2', homeAway: 'away', winner: false, score: '4', team: { id: '2', abbreviation: 'A' }, linescores: ls(10) },
    ],
  });
  ok(c.periods.played === 10, `H8: played counts extra innings (got ${c.periods.played})`);
  ok(c.periods.isOvertime === true, 'H8: isOvertime invariant preserved');
  ok(c.decision === 'regulation', `H8: extra-inning decision is NOT overtime (got ${c.decision})`);
}

// ---- H14: rugby sentinel periods 20/60 dropped, no false OT ------------------
{
  const lc = [
    { period: 1, value: 7, displayValue: '7' },
    { period: 2, value: 19, displayValue: '19' },
    { period: 20, value: 0, displayValue: '0' },
    { period: 60, value: 0, displayValue: '0' },
  ];
  const c = comp0('rugby/180659', {
    status: { ...FINAL, detail: 'FT' }, period: 2,
    competitors: [
      { id: '1', homeAway: 'home', winner: true, score: '19', team: { id: '1', abbreviation: 'H' }, linescores: lc },
      { id: '2', homeAway: 'away', winner: false, score: '12', team: { id: '2', abbreviation: 'A' }, linescores: lc },
    ],
  });
  const periods = c.competitors[0].periodScores.map(p => p.period);
  ok(!periods.includes(20) && !periods.includes(60), `H14: sentinel periods dropped (got [${periods}])`);
  ok(c.periods.played === 2, `H14: played ignores sentinels (got ${c.periods.played})`);
  ok(c.periods.isOvertime === false, 'H14: no false overtime');
  ok(c.decision === 'regulation', `H14: decision regulation (got ${c.decision})`);
}

// ---- C1: tennis linescores carry no `period` → synthesize it -----------------
{
  const c = comp0('tennis/atp', {
    status: { ...FINAL }, period: 0,
    competitors: [
      { id: '1', athlete: { id: '1', displayName: 'Player A' }, winner: true, linescores: [{ value: 6, winner: true }, { value: 7, winner: true }] },
      { id: '2', athlete: { id: '2', displayName: 'Player B' }, winner: false, linescores: [{ value: 4, winner: false }, { value: 5, winner: false }] },
    ],
  });
  const ps = c.competitors[0].periodScores;
  ok(ps.length === 2, `C1: tennis sets survive (got ${ps.length})`);
  ok(ps[0].period === 1 && ps[1].period === 2, `C1: periods synthesized 1,2 (got ${ps.map(p => p.period)})`);
  ok(ps[0].setWinner === true, 'C1: setWinner carried through');
}

// ---- cricket: composite "106 (17/20 ov, target 171)" must NOT parse 17/20 ----
{
  const c = comp0('cricket/8052', {
    status: { name: 'STATUS_IN_PROGRESS', state: 'in' }, period: 2,
    competitors: [
      { id: '1', team: { id: '1', abbreviation: 'A' }, score: '106 (17/20 ov, target 171)' },
      { id: '2', team: { id: '2', abbreviation: 'B' }, score: '170/6' },
    ],
  });
  const a = c.competitors[0].score.cricket;
  ok(a?.runs === 106, `cricket: leading total is runs (got ${a?.runs})`);
  ok(a?.wickets !== 20, `cricket: did NOT grab overs as wickets (got wickets=${a?.wickets})`);
  ok(a?.target === 171, `cricket: target parsed (got ${a?.target})`);
  const b = c.competitors[1].score.cricket;
  ok(b?.runs === 170 && b?.wickets === 6, `cricket: "170/6" → 170/6 (got ${b?.runs}/${b?.wickets})`);
}

// ---- C4: MMA method derived from details[] ----------------------------------
{
  const c = comp0('mma/ufc', {
    status: { name: 'STATUS_FINAL', state: 'post', completed: true, detail: 'Final' }, period: 2, displayClock: '3:30',
    details: [{ type: 'Unofficial Winner Submission' }, { type: 'Results' }],
    competitors: [
      { id: '1', athlete: { id: '1', displayName: 'Fighter A' }, winner: true },
      { id: '2', athlete: { id: '2', displayName: 'Fighter B' }, winner: false },
    ],
  });
  ok(c.method?.kind === 'Submission', `C4: method kind (got ${c.method?.kind})`);
  ok(c.method?.finishRound === 2, `C4: finish round (got ${c.method?.finishRound})`);
  ok(c.method?.finishTime === '3:30', `C4: finish time (got ${c.method?.finishTime})`);
  ok(c.decision === 'method', `C4: decision method (got ${c.decision})`);
  // "Unofficial Winner Kotko" → KO/TKO
  const c2 = comp0('mma/ufc', {
    status: { name: 'STATUS_FINAL', state: 'post', completed: true }, period: 1, displayClock: '1:05',
    details: [{ type: 'Unofficial Winner Kotko' }],
    competitors: [
      { id: '1', athlete: { id: '1', displayName: 'A' }, winner: true },
      { id: '2', athlete: { id: '2', displayName: 'B' }, winner: false },
    ],
  });
  ok(c2.method?.kind === 'KO/TKO', `C4: "Kotko" → KO/TKO (got ${c2.method?.kind})`);
}

// ---- C3: scoreboard fallback adopts a live game the (empty) schedule missed ---
{
  const emptyCard = normalizeTeamCard(registry, 'soccer/fifa.world', '481', { team: { id: '481' }, events: [] });
  ok(emptyCard.live == null, 'C3: empty schedule → no live (pre-fallback)');
  const scoreboard = sb('soccer/fifa.world', {
    status: { name: 'STATUS_FIRST_HALF', state: 'in' }, period: 1,
    competitors: [
      { id: '481', homeAway: 'home', score: '1', team: { id: '481', displayName: 'Germany', abbreviation: 'GER' } },
      { id: '999', homeAway: 'away', score: '1', team: { id: '999', displayName: 'Curacao', abbreviation: 'CUW' } },
    ],
  });
  const patched = applyScoreboardFallback(registry, 'soccer/fifa.world', '481', emptyCard, scoreboard);
  ok(patched.live != null, 'C3: fallback surfaces the live game');
  ok(patched.anyLive === true, 'C3: anyLive set so TTL/poll speed up');
  ok(patched.team.displayName === 'Germany', `C3: team identity filled (got ${patched.team.displayName})`);
}

console.log(`\n${'='.repeat(48)}\n${pass} passed · ${fail} failed`);
if (fails.length) { console.log('\nFAILURES:'); for (const f of fails) console.log('  ✗ ' + f); }
process.exit(fail ? 1 : 0);
