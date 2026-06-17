// Deterministic unit tests (no network) for the audit-fix pure functions, run
// against synthetic ESPN shapes so each fix is pinned against regression.
// Run: node test/units.test.mjs

import registry from '../../schema/league-profiles.json' with { type: 'json' };
import { normalizeScoreboard } from '../src/normalize.js';
import { normalizeSummary } from '../src/summary.js';
import { normalizeRankings } from '../src/rankings.js';
import { normalizeTeamCard, applyScoreboardFallback } from '../src/team.js';
import { publicClient } from '../src/client.js';
import { leagueKeys } from '../../schema/tools/resolve.mjs';

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

// ---- calendar passthrough: day-type → calendarDays; list-type → none --------
{
  const dayCal = {
    leagues: [{
      id: '46', slug: 'nba', name: 'NBA', calendarType: 'day',
      // two distinct ET days + a duplicate → deduped & sorted
      calendar: ['2026-06-14T04:00Z', '2026-06-16T04:00Z', '2026-06-14T04:00Z'],
      season: { startDate: '2025-10-01T04:00Z', endDate: '2026-06-30T04:00Z' },
    }],
    events: [],
  };
  const r = normalizeScoreboard(registry, 'basketball/nba', dayCal);
  ok(Array.isArray(r.calendarDays) && r.calendarDays.length === 2, `calendar: day-type yields unique sorted days (got ${JSON.stringify(r.calendarDays)})`);
  ok(r.calendarDays?.[0] === '20260614', `calendar: ET-bucketed YYYYMMDD (got ${r.calendarDays?.[0]})`);
  ok(r.seasonWindow?.startDate === '2025-10-01T04:00Z', 'calendar: seasonWindow passed through');

  const listCal = {
    leagues: [{
      id: '28', slug: 'nfl', name: 'NFL', calendarType: 'list',
      calendar: [{ label: 'Regular Season', startDate: '2026-09-01T04:00Z', endDate: '2027-01-01T04:00Z', entries: [{ label: 'Week 1', startDate: '2026-09-01T04:00Z', endDate: '2026-09-08T04:00Z' }] }],
      season: {},
    }],
    events: [],
  };
  const r2 = normalizeScoreboard(registry, 'football/nfl', listCal);
  ok(r2.calendarDays === undefined, `calendar: list-type omits calendarDays (got ${JSON.stringify(r2.calendarDays)})`);
}

// ---- rankings: poll list, name = location+name, https + dark logo -----------
{
  const raw = {
    rankings: [
      {
        name: 'AP Top 25', shortName: 'AP Poll', occurrence: { displayValue: 'Week 5' },
        ranks: [{ current: 1, previous: 2, trend: '+1', recordSummary: '5-0', team: { id: '99', location: 'Ohio State', name: 'Buckeyes', abbreviation: 'OSU', color: 'bb0000', logos: [{ href: 'http://a.espncdn.com/i/teamlogos/ncaa/500/99.png' }] } }],
        others: [], droppedOut: [],
      },
      { name: 'Empty', shortName: 'E', ranks: [] }, // dropped (no ranks)
    ],
  };
  const r = normalizeRankings(raw);
  ok(r.polls.length === 1, `rankings: empty polls dropped (got ${r.polls.length})`);
  const e = r.polls[0].ranks[0];
  ok(e.current === 1 && e.trend === '+1' && e.record === '5-0', 'rankings: fields mapped');
  ok(e.team.name === 'Ohio State Buckeyes', `rankings: name = location+name (got ${e.team.name})`);
  ok(e.team.logo === 'https://a.espncdn.com/i/teamlogos/ncaa/500/99.png', 'rankings: logo https-forced');
  ok(e.team.logoDark === 'https://a.espncdn.com/i/teamlogos/ncaa/500-dark/99.png', `rankings: dark logo derived (got ${e.team.logoDark})`);
}

// ---- summary enrichments: winProb / seasonSeries / form / injuries / PBP -----
{
  const raw = {
    header: { id: '7', competitions: [{ status: { type: { state: 'in' } }, competitors: [
      { id: 'H', homeAway: 'home', team: { id: 'H', abbreviation: 'HOM' } },
      { id: 'A', homeAway: 'away', team: { id: 'A', abbreviation: 'AWY' } },
    ] }] },
    boxscore: { teams: [], players: [] },
    // last entry wins (current/final), 0..1 → %
    winprobability: [{ homeWinPercentage: 0.5, tiePercentage: 0, playId: '1' }, { homeWinPercentage: 0.73, tiePercentage: 0, playId: '2' }],
    // prefer the non-preseason entry
    seasonseries: [{ type: 'preseason', summary: 'Preseason tied 1-1', seriesScore: '1-1' }, { type: 'regular', summary: 'HOM leads 2-1', seriesScore: '2-1', title: 'Regular Season Series' }],
    lastFiveGames: [
      { team: { id: 'H', abbreviation: 'HOM' }, events: [{ gameDate: '2026-06-10T00:00Z', gameResult: 'W' }, { gameDate: '2026-06-12T00:00Z', gameResult: 'L' }] },
      { team: { id: 'A', abbreviation: 'AWY' }, events: [{ gameDate: '2026-06-11T00:00Z', gameResult: 'L' }] },
    ],
    injuries: [{ team: { id: 'H', abbreviation: 'HOM' }, injuries: [
      { status: 'Out', athlete: { shortName: 'J. Doe', position: { abbreviation: 'PG' } }, details: { detail: 'Knee', returnDate: '2026-07-01' } },
      { status: '', athlete: {} }, // dropped: no name/status
    ] }],
    plays: [{ id: '1', text: 'Tip', period: { number: 1 }, scoringPlay: false }, { id: '2', text: 'Bucket', period: { number: 1 }, scoringPlay: true }],
  };
  const s = normalizeSummary(registry, 'basketball/nba', raw);
  ok(s.winProbability?.home === 73 && s.winProbability?.away === 27, `summary: winProb from last entry (got ${JSON.stringify(s.winProbability)})`);
  ok(s.seasonSeries?.summary === 'HOM leads 2-1', `summary: seasonSeries prefers non-preseason (got ${s.seasonSeries?.summary})`);
  const hForm = (s.recentForm || []).find(f => f.side === 'home');
  ok(hForm?.form === 'WL', `summary: recentForm newest-last (got ${hForm?.form})`);
  const hInj = (s.injuries || []).find(t => t.side === 'home');
  ok(hInj?.items.length === 1 && hInj.items[0].detail === 'Knee', `summary: injuries stripped, blank dropped (got ${JSON.stringify(hInj?.items)})`);
  ok(s.plays?.length === 2, `summary: full play-by-play present (got ${s.plays?.length})`);
}

// ---- leagueKeys: priority as string OR array (tiered overview paging) --------
{
  const v1 = leagueKeys(registry, { priority: 'v1' });
  const v2 = leagueKeys(registry, { priority: 'v2' });
  const both = leagueKeys(registry, { priority: ['v1', 'v2'] });
  ok(v1.length > 0 && v1.every(k => registry.leagues[k].priority === 'v1'), `leagueKeys: priority string filters v1 (got ${v1.length})`);
  ok(both.length === v1.length + v2.length, `leagueKeys: priority array = v1∪v2 (got ${both.length}, want ${v1.length + v2.length})`);
  ok(both.every(k => ['v1', 'v2'].includes(registry.leagues[k].priority)), 'leagueKeys: array members are v1/v2 only');
  // deterministic order → page slices are stable across calls
  ok(both.join() === leagueKeys(registry, { priority: ['v1', 'v2'] }).join(), 'leagueKeys: order is deterministic (stable paging)');
  // the curated set spans more than one 48-league page (drives the Active tier's 2 fetches)
  ok(both.length > 48, `leagueKeys: v1+v2 spans >1 page (got ${both.length})`);
  // dynamic `_*` buckets never appear (they have no addressable scoreboard)
  ok(!both.some(k => k.split('/')[1].startsWith('_')), 'leagueKeys: `_` buckets excluded');
}

// ---- client gate: /v1/health echo strips internals + fails open -------------
{
  // The registry's gate is projected to the wire shape, minus `_`-prefixed keys.
  const wire = publicClient(registry.client);
  ok(wire !== null, 'client: registry has a gate block');
  ok(!('_doc' in wire), 'client: internal _doc stripped from the wire shape');
  ok(typeof wire.minVersionCode === 'number', `client: minVersionCode is numeric (got ${typeof wire.minVersionCode})`);
  ok(typeof wire.recommendedVersionCode === 'number', 'client: recommendedVersionCode is numeric');
  ok(typeof wire.downloadUrl === 'string' && wire.downloadUrl.startsWith('https://'), `client: downloadUrl present (got ${wire.downloadUrl})`);
  // Default ships inert (0/0) so no user is nagged until the author raises it.
  ok(wire.minVersionCode === 0 && wire.recommendedVersionCode === 0, `client: gate ships inert 0/0 (got ${wire.minVersionCode}/${wire.recommendedVersionCode})`);
  // FAIL-OPEN: an absent gate (old worker / fork / offline mock) → null, never a
  // zero-version that would block every client.
  ok(publicClient(undefined) === null, 'client: missing gate → null (fail-open)');
  ok(publicClient(null) === null, 'client: null gate → null (fail-open)');
  ok(publicClient('nope') === null, 'client: non-object gate → null (fail-open)');
}

console.log(`\n${'='.repeat(48)}\n${pass} passed · ${fail} failed`);
if (fails.length) { console.log('\nFAILURES:'); for (const f of fails) console.log('  ✗ ' + f); }
process.exit(fail ? 1 : 0);
