// Deterministic unit tests (no network) for the audit-fix pure functions, run
// against synthetic ESPN shapes so each fix is pinned against regression.
// Run: node test/units.test.mjs

import registry from '../../schema/league-profiles.json' with { type: 'json' };
import { normalizeScoreboard, golfMetaFromTournament } from '../src/normalize.js';
import { normalizeSummary, normalizeMmaSummary } from '../src/summary.js';
import { normalizeRankings } from '../src/rankings.js';
import { normalizeStandings } from '../src/standings.js';
import { normalizeGolfScorecard } from '../src/scorecard.js';
import { normalizeTeamCard, applyScoreboardFallback } from '../src/team.js';
import { normalizeTeamDetail } from '../src/teamdetail.js';
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

// ============================ 2026-07 additions ==============================

// ---- golf meta: core tournament → meta.golf ----------------------------------
{
  const t = { major: true, scoringSystem: { id: '1', name: 'Medal' }, numberOfRounds: 4, currentRound: 3, cutRound: 2, cutScore: -3, cutCount: 79 };
  const m = golfMetaFromTournament(t);
  ok(m.numberOfRounds === 4 && m.currentRound === 3 && m.cutRound === 2 && m.cutScore === -3 && m.cutCount === 79, `golf: tournament meta mapped (${JSON.stringify(m)})`);
  ok(m.major === true && m.scoringSystem === 'Medal', 'golf: major + scoringSystem.name mapped');
  ok(golfMetaFromTournament(null) === undefined, 'golf: null tournament → no meta');
  ok(golfMetaFromTournament({ major: true }) === undefined, 'golf: tournament without numberOfRounds → no meta (contract requires it)');

  // extras injection: lands on the toPar competition, keyed by event id
  const raw = {
    leagues: [{ id: '1106', slug: 'pga', season: {} }],
    events: [{
      id: 'E1', date: '2026-07-05T14:00Z', name: 'Open', shortName: 'Open',
      competitions: [{ id: 'E1', status: { type: { name: 'STATUS_IN_PROGRESS', state: 'in' }, period: 3 }, competitors: [] }],
    }],
  };
  const norm = normalizeScoreboard(registry, 'golf/pga', raw, { golfTournaments: { E1: t } });
  ok(norm.events[0].competitions[0].meta?.golf?.cutScore === -3, 'golf: extras.golfTournaments → meta.golf on the competition');
  const noExtras = normalizeScoreboard(registry, 'golf/pga', raw);
  ok(noExtras.events[0].competitions[0].meta?.golf === undefined, 'golf: no extras → no meta.golf (best-effort)');
}

// ---- golf: athlete id backfilled from competitor id ---------------------------
{
  const c = comp0('golf/pga', {
    status: { name: 'STATUS_IN_PROGRESS', state: 'in' }, period: 2,
    competitors: [{ id: '4690755', order: 1, athlete: { displayName: 'Chris Gotterup' }, score: '-20' }],
  });
  ok(c.competitors[0].athletes[0].id === '4690755', `golf: athlete id backfilled from competitor id (got ${c.competitors[0].athletes[0].id})`);
}

// ---- cheap passthroughs: attendance / headline / conferenceGame / wasSuspended -
{
  const c = comp0('baseball/mlb', {
    status: FINAL, period: 9,
    competitors: [
      { id: '1', homeAway: 'home', winner: true, score: '5', team: { id: '1', abbreviation: 'H' } },
      { id: '2', homeAway: 'away', winner: false, score: '4', team: { id: '2', abbreviation: 'A' } },
    ],
  });
  ok(c.attendance === undefined && c.headline === undefined && c.conferenceGame === undefined && c.wasSuspended === undefined,
    'cheap: absent scoreboard fields stay absent');
  const sb2 = sb('baseball/mlb', {
    status: FINAL, period: 9,
    competitors: [
      { id: '1', homeAway: 'home', winner: true, score: '5', team: { id: '1' } },
      { id: '2', homeAway: 'away', winner: false, score: '4', team: { id: '2' } },
    ],
  });
  Object.assign(sb2.events[0].competitions[0], {
    attendance: 41234,
    conferenceCompetition: true,
    wasSuspended: true,
    headlines: [{ type: 'Recap', shortLinkText: 'Judge&#039;s 3 HR carry Yankees', description: 'longer text' }],
  });
  const c2 = normalizeScoreboard(registry, 'baseball/mlb', sb2).events[0].competitions[0];
  ok(c2.attendance === 41234, `cheap: attendance passthrough (got ${c2.attendance})`);
  ok(c2.conferenceGame === true && c2.wasSuspended === true, 'cheap: conferenceGame + wasSuspended flags');
  ok(c2.headline === "Judge's 3 HR carry Yankees", `cheap: headline decoded from shortLinkText (got ${JSON.stringify(c2.headline)})`);
}

// ---- gridiron drives: rows + flattened plays + gameInfo -----------------------
{
  const raw = {
    header: { id: '9', competitions: [{ id: '9', status: { type: { state: 'post', completed: true } }, competitors: [
      { id: '26', homeAway: 'away', team: { id: '26', abbreviation: 'SEA' } },
      { id: '17', homeAway: 'home', team: { id: '17', abbreviation: 'NE' } },
    ] }] },
    drives: {
      previous: [
        { id: 'd1', description: '8 plays, 51 yards, 3:02', team: { id: '26', abbreviation: 'SEA' }, yards: 51, isScore: true, offensivePlays: 8, displayResult: 'Field Goal',
          plays: [
            { text: 'Kickoff to the SEA 35.', period: { number: 1 }, clock: { displayValue: '15:00' }, awayScore: 0, homeScore: 0, type: { text: 'Kickoff' } },
            { text: 'FG is GOOD.', period: { number: 1 }, clock: { displayValue: '11:58' }, awayScore: 3, homeScore: 0, type: { text: 'Field Goal Good' }, scoringPlay: true },
          ] },
        { id: 'd2', description: '3 plays, -2 yards, 1:40', team: { id: '17', abbreviation: 'NE' }, yards: -2, isScore: false, offensivePlays: 3, displayResult: 'Punt',
          plays: [{ text: 'Punt.', period: { number: 1 }, clock: { displayValue: '10:00' }, awayScore: 3, homeScore: 0, type: { text: 'Punt' } }] },
      ],
    },
    gameInfo: { attendance: 70823, officials: [{ fullName: 'Shawn Hochuli', position: { name: 'Referee' } }] },
  };
  const s = normalizeSummary(registry, 'football/nfl', raw);
  ok(s.drives?.length === 2, `drives: 2 rows (got ${s.drives?.length})`);
  ok(s.drives[0].side === 'away' && s.drives[0].teamAbbr === 'SEA' && s.drives[0].result === 'Field Goal' && s.drives[0].isScore === true,
    `drives: row fields mapped (${JSON.stringify(s.drives[0])})`);
  ok(s.plays?.length === 3, `drives: nested plays flattened into plays feed (got ${s.plays?.length})`);
  ok(s.plays[0].side === 'away' && s.plays[0].teamAbbr === 'SEA', 'drives: flattened play inherits the drive team');
  ok(s.attendance === 70823, `gameInfo: attendance (got ${s.attendance})`);
  ok(s.officials?.[0]?.name === 'Shawn Hochuli' && s.officials[0].role === 'Referee', 'gameInfo: officials name+role');
  // live drives.current is included once (deduped by id)
  const live = normalizeSummary(registry, 'football/nfl', { ...raw, drives: { previous: raw.drives.previous, current: { id: 'd3', description: '2 plays, 9 yards', team: { id: '26' }, plays: [] } } });
  ok(live.drives.length === 3, 'drives: current drive appended');
}

// ---- cricket matchcards → innings scorecard -----------------------------------
{
  const raw = {
    header: { id: 'c1', competitions: [{ id: 'c1', status: { type: { state: 'post', completed: true } }, competitors: [] }] },
    matchcards: [
      { headline: 'Batting', typeID: '11', inningsNumber: '2', teamName: 'Australia', runs: '241', total: '(4 wkts; 43 ovs)', extras: '(b 5, lb 2, w 11)',
        playerDetails: [{ playerName: 'DA Warner', dismissal: 'caught', runs: '7', ballsFaced: '3', fours: '1', sixes: '0' }] },
      { headline: 'Bowling', typeID: '12', inningsNumber: '2', teamName: 'India',
        playerDetails: [{ playerName: 'JJ Bumrah', overs: '9.0', maidens: '2', conceded: '43', wickets: '2', economyRate: '4.77', nbw: '' }] },
      { headline: 'Partnerships', typeID: '13', inningsNumber: '2', teamName: 'Australia',
        playerDetails: [{ partnershipRuns: '16', player1Name: 'DA Warner', player2Name: 'TM Head' }] },
      { headline: 'Batting', typeID: '11', inningsNumber: '1', teamName: 'India', runs: '240', total: '(all out; 48.1 ovs)',
        playerDetails: [{ playerName: 'V Kohli', dismissal: 'lbw', runs: '54', ballsFaced: '63', fours: '4', sixes: '0' }] },
    ],
  };
  const s = normalizeSummary(registry, 'cricket/8048', raw);
  ok(s.cricketInnings?.length === 2, `cricket: 2 innings cards (got ${s.cricketInnings?.length})`);
  ok(s.cricketInnings[0].innings === 1 && s.cricketInnings[1].innings === 2, 'cricket: innings sorted ascending');
  const inn2 = s.cricketInnings[1];
  ok(inn2.battingTeam === 'Australia' && inn2.bowlingTeam === 'India', 'cricket: batting/bowling teams paired by innings');
  ok(inn2.total === '241 (4 wkts; 43 ovs)' && inn2.extras === '(b 5, lb 2, w 11)', `cricket: total joined (got ${JSON.stringify(inn2.total)})`);
  ok(inn2.batting[0].name === 'DA Warner' && inn2.batting[0].balls === '3', 'cricket: batting row mapped (ballsFaced→balls)');
  ok(inn2.bowling[0].name === 'JJ Bumrah' && inn2.bowling[0].runs === '43' && inn2.bowling[0].economy === '4.77', 'cricket: bowling row mapped (conceded→runs)');
  ok(!JSON.stringify(s.cricketInnings).includes('partnership'), 'cricket: partnerships cards dropped');
}

// ---- MMA summary: core statuses → bouts + judges ------------------------------
{
  const coreEvent = {
    id: '600059467', date: '2026-06-28T22:00Z',
    competitions: [
      { id: 'b1', competitors: [{ id: 'f1' }, { id: 'f2' }] },
      { id: 'b2', competitors: [{ id: 'f3' }, { id: 'f4' }] },
      { id: 'b3', competitors: [{ id: 'f5' }, { id: 'f6' }] },
    ],
  };
  const statuses = {
    b1: { type: { state: 'post', completed: true }, result: { id: 263, name: 'decision---unanimous', displayName: 'Decision - Unanimous', shortDisplayName: 'U Dec' }, period: 3, displayClock: '5:00' },
    b2: { type: { state: 'post', completed: true }, result: { name: 'ko---punches', displayName: 'KO/TKO', shortDisplayName: 'KO' }, period: 1, displayClock: '1:34' },
    b3: { type: { state: 'pre' } },
  };
  const linescores = {
    'b1/f1': { items: [{ value: 81, linescores: [{ value: 27, order: 3 }, { value: 27, order: 1 }, { value: 27, order: 2 }] }] },
    'b1/f2': { items: [{ value: 88, linescores: [{ value: 30, order: 1 }, { value: 29, order: 2 }, { value: 29, order: 3 }] }] },
  };
  const s = normalizeMmaSummary(coreEvent, statuses, linescores);
  ok(s.eventId === '600059467' && s.live === false, 'mma: envelope');
  ok(s.bouts.length === 2, `mma: only resolved bouts shipped (got ${s.bouts.length})`);
  const dec = s.bouts.find(b => b.id === 'b1');
  ok(dec.result === 'Decision - Unanimous' && dec.shortResult === 'U Dec' && dec.round === 3 && dec.clock === '5:00', `mma: decision bout mapped (${JSON.stringify(dec)})`);
  ok(dec.judges?.length === 2 && dec.judges[0].totals.join() === '27,27,27', `mma: judge totals sorted by order (got ${dec.judges?.[0]?.totals})`);
  ok(dec.judges[1].total === 88 && dec.judges[1].totals.join() === '30,29,29', 'mma: second corner judge card');
  const ko = s.bouts.find(b => b.id === 'b2');
  ok(ko.result === 'KO/TKO' && ko.round === 1 && ko.clock === '1:34' && !ko.judges, 'mma: KO bout, no judges');
  ok(s.teamStats.length === 0 && s.boxGroups.length === 0, 'mma: GameSummary defaults present');
  // all-pre card → nextStartMs for the near-kickoff TTL
  const pre = normalizeMmaSummary(coreEvent, { b1: { type: { state: 'pre' } }, b2: { type: { state: 'pre' } }, b3: { type: { state: 'pre' } } }, {});
  ok(pre.bouts.length === 0 && pre.nextStartMs === Date.parse('2026-06-28T22:00Z'), 'mma: scheduled card → nextStartMs, no bouts');
  const live = normalizeMmaSummary(coreEvent, { ...statuses, b3: { type: { state: 'in' }, period: 2, displayClock: '3:10' } }, {});
  ok(live.live === true, 'mma: any in-progress bout → live');
}

// ---- golf scorecard normalizer ------------------------------------------------
{
  const raw = {
    profile: { id: '4690755', displayName: 'Chris Gotterup', headshot: 'http://a.espncdn.com/i/headshots/golf/players/full/4690755.png' },
    rounds: [
      { period: 1, value: 66, displayValue: '-5', inScore: 34, outScore: 32, teeTime: '2026-07-02T17:45Z', startTee: 1, groupNumber: 30, currentPosition: 9,
        linescores: [{ period: 1, value: 3, par: 4, scoreType: { name: 'BIRDIE', displayValue: '-1' } }, { period: 2, value: 5, par: 5, scoreType: { name: 'PAR', displayValue: 'E' } }] },
      { period: 4, value: 0, displayValue: '-', teeTime: '2026-07-05T18:10Z', startTee: 10, linescores: [] },
    ],
    stats: [
      { name: 'scoreToPar', displayName: 'Score To Par', displayValue: '-20' },
      { name: 'strokesGainedTotal', displayName: 'SG Total', displayValue: '2.1' }, // not in KEEP → dropped
    ],
  };
  const sc = normalizeGolfScorecard('golf/pga', '401811954', '4690755', raw);
  ok(sc.player.name === 'Chris Gotterup' && sc.player.headshot.startsWith('https://'), 'scorecard: player + https headshot');
  ok(sc.rounds.length === 2 && sc.rounds[0].round === 1 && sc.rounds[0].strokes === 66 && sc.rounds[0].toPar === '-5', `scorecard: round mapped (${JSON.stringify(sc.rounds[0]?.round)})`);
  ok(sc.rounds[0].outScore === 32 && sc.rounds[0].inScore === 34, 'scorecard: front/back nine');
  ok(sc.rounds[0].holes[0].scoreType === 'BIRDIE' && sc.rounds[0].holes[0].par === 4 && sc.rounds[0].holes[0].strokes === 3, 'scorecard: hole par/strokes/scoreType');
  const pre = sc.rounds[1];
  ok(pre.strokes === undefined && pre.toPar === undefined && pre.teeTime === '2026-07-05T18:10Z' && pre.holes.length === 0,
    `scorecard: pre-round → teeTime only, empty holes (${JSON.stringify(pre)})`);
  ok(sc.stats.length === 1 && sc.stats[0].name === 'scoreToPar', 'scorecard: stat allowlist applied');
}

// ---- rankings: athlete-based feeds (tennis/UFC) --------------------------------
{
  const raw = { rankings: [
    { name: 'ATP', shortName: 'ATP', ranks: [
      { current: 1, previous: 1, trend: '-', points: 13450, athlete: { id: '3623', displayName: 'Jannik Sinner', headshot: 'http://x/3623.png' } },
    ] },
    { name: "Men's Pound for Pound Rankings", shortName: 'P4P', ranks: [
      { current: 1, trend: '-', recordSummary: '21-4-0', hasAccolade: true, athlete: { id: '3088812', displayName: 'Kamaru Usman' } },
    ] },
    { name: 'Empty', shortName: 'E', ranks: [{ current: 1 }] }, // no team/athlete → dropped
  ] };
  const r = normalizeRankings(raw);
  ok(r.polls.length === 2, `rankings: entity-less poll dropped (got ${r.polls.length})`);
  ok(r.polls[0].ranks[0].athlete?.name === 'Jannik Sinner' && r.polls[0].ranks[0].points === 13450, 'rankings: tennis athlete + points');
  ok(r.polls[0].ranks[0].athlete.headshot.startsWith('https://'), 'rankings: athlete headshot forced https');
  ok(r.polls[1].ranks[0].champion === true && r.polls[1].ranks[0].record === '21-4-0', 'rankings: UFC champion flag + record');
  ok(r.polls[1].ranks[0].team === undefined, 'rankings: athlete entries carry no team');
}

// ---- standings: athlete-shaped entries (racing) --------------------------------
{
  const raw = { name: 'F1', children: [
    { name: 'Driver Standings', standings: { entries: [
      { athlete: { id: '5829', displayName: 'Kimi Antonelli' }, stats: [{ name: 'rank', displayValue: '1', value: 1 }, { name: 'championshipPts', displayValue: '179', value: 179 }] },
    ] } },
    { name: 'Constructor Standings', standings: { entries: [
      { team: { id: '106893', displayName: 'Mercedes', color: '00D2BE' }, stats: [{ name: 'rank', displayValue: '1' }, { name: 'championshipPts', displayValue: '260' }] },
    ] } },
  ] };
  const groups = normalizeStandings(raw);
  ok(groups.length === 2, `standings: both racing groups (got ${groups.length})`);
  ok(groups[0].rows[0].team.name === 'Kimi Antonelli' && groups[0].rows[0].rank === 1, `standings: athlete entry → team slot (${JSON.stringify(groups[0].rows[0].team)})`);
  ok(groups[0].rows[0].stats.championshipPts === '179', 'standings: championshipPts kept');
  ok(groups[1].rows[0].team.name === 'Mercedes', 'standings: constructor (team) entry unchanged');
}

// ---- team detail: identity + schedule + roster + stats + standing ------------
{
  const schedEvent = (id, dateIso, hScore, aScore) => ({
    id, date: dateIso, shortName: 'SAC @ LAL',
    competitions: [{
      id, status: { type: FINAL, period: 4 },
      competitors: [
        { id: '13', homeAway: 'home', winner: hScore > aScore, score: String(hScore), team: { id: '13', abbreviation: 'LAL' } },
        { id: '99', homeAway: 'away', winner: aScore > hScore, score: String(aScore), team: { id: '99', abbreviation: 'SAC' } },
      ],
    }],
  });
  const schedule = {
    team: { id: '13', displayName: 'Los Angeles Lakers', abbreviation: 'LAL', recordSummary: '50-32', standingSummary: '2nd in Pacific', color: '552583', logo: 'http://a/13.png' },
    // out of order on purpose → must sort ascending
    events: [schedEvent('g2', '2026-01-12T02:00Z', 118, 121), schedEvent('g1', '2026-01-10T02:00Z', 110, 100)],
  };
  const flatRoster = { athletes: [
    { id: '1', displayName: 'Player One', jersey: '23', position: { abbreviation: 'G' }, headshot: { href: 'http://a/1.png' } },
    { id: '2', displayName: 'Player Two', jersey: '3', position: { abbreviation: 'F' } },
  ] };
  const stats = { results: { stats: { categories: [
    { name: 'offensive', displayName: 'Offensive', stats: [{ name: 'avgPoints', displayName: 'Points Per Game', shortDisplayName: 'PPG', abbreviation: 'PTS', value: 112.3, displayValue: '112.3' }] },
    { name: 'general', displayName: 'General', stats: [{ name: 'avgRebounds', shortDisplayName: 'RPG', abbreviation: 'REB', value: 44.1, displayValue: '44.1' }, { name: 'gamesPlayed', shortDisplayName: 'GP', value: 60, displayValue: '60' }] },
  ] } } };
  const standingsRaw = { name: 'NBA', children: [
    { name: 'Pacific Division', standings: { entries: [
      { team: { id: '13', displayName: 'Los Angeles Lakers', abbreviation: 'LAL' }, stats: [{ name: 'rank', displayValue: '2', value: 2 }, { name: 'wins', displayValue: '50' }] },
      { team: { id: '99', displayName: 'Sacramento Kings' }, stats: [{ name: 'rank', displayValue: '3', value: 3 }] },
    ] } },
    { name: 'Atlantic Division', standings: { entries: [{ team: { id: '7', displayName: 'Boston Celtics' }, stats: [] }] } },
  ] };
  const d = normalizeTeamDetail(registry, 'basketball/nba', '13', { schedule, roster: flatRoster, stats, standingsRaw });

  ok(d.team.id === '13' && d.team.record === '50-32' && d.team.standingSummary === '2nd in Pacific', `teamdetail: identity + record + standingSummary (${JSON.stringify(d.team)})`);
  ok(d.schedule.length === 2 && d.schedule[0].id === 'g1' && d.schedule[1].id === 'g2', 'teamdetail: schedule sorted start-ascending');
  // flat roster → single "Roster" group
  ok(d.roster.length === 1 && d.roster[0].name === 'Roster' && d.roster[0].athletes.length === 2, `teamdetail: flat roster → one group (${JSON.stringify(d.roster.map(g => g.name))})`);
  ok(d.roster[0].athletes[0].jersey === '23' && d.roster[0].athletes[0].position === 'G' && d.roster[0].athletes[0].headshot === 'https://a/1.png', 'teamdetail: athlete fields mapped (https headshot)');
  // curated single group in teamStatKeys order (avgPoints before avgRebounds)
  ok(d.stats.length === 1 && d.stats[0].name === 'Season', `teamdetail: curated single stat group (${JSON.stringify(d.stats.map(g => g.name))})`);
  ok(d.stats[0].stats[0].name === 'avgPoints' && d.stats[0].stats[1].name === 'avgRebounds', `teamdetail: stats ordered by teamStatKeys (${d.stats[0].stats.map(s => s.name)})`);
  ok(d.stats[0].stats[0].value === '112.3' && typeof d.stats[0].stats[0].value === 'string', 'teamdetail: stat value is a STRING');
  ok(d.standing?.groupName === 'Pacific Division' && d.standing.rows.some(r => r.team.id === '13'), `teamdetail: standing plucked to the team's group (${d.standing?.groupName})`);
  ok(Array.isArray(d.standing?.columns) && d.standing.columns.some(c => c.key === 'wins' && c.label === 'W'), `teamdetail: standing carries the family standingsColumns (${JSON.stringify(d.standing?.columns)})`);
}

// grouped roster (NFL) + null stats/standings degrade cleanly
{
  const groupedRoster = { athletes: [
    { position: 'offense', items: [{ id: '10', displayName: 'QB Guy', jersey: '12', position: { abbreviation: 'QB' } }] },
    { position: 'defense', items: [{ id: '20', displayName: 'DL Guy', jersey: '99', position: { abbreviation: 'DL' } }] },
  ] };
  const d = normalizeTeamDetail(registry, 'football/nfl', '17', { schedule: { team: { id: '17' }, events: [] }, roster: groupedRoster, stats: null, standingsRaw: null });
  ok(d.roster.length === 2 && d.roster[0].name === 'Offense' && d.roster[1].name === 'Defense', `teamdetail: grouped roster → title-cased position groups (${d.roster.map(g => g.name)})`);
  ok(d.roster[0].athletes[0].id === '10' && d.roster[0].athletes[0].position === 'QB', 'teamdetail: grouped athlete mapped');
  ok(d.stats.length === 0, 'teamdetail: null stats → []');
  ok(d.standing === undefined && d.schedule.length === 0, 'teamdetail: null standings/empty schedule degrade');
}

// EPL empty stats (results:{}) tolerated; generic (uncurated) stats capped at 8
{
  const empty = normalizeTeamDetail(registry, 'soccer/eng.1', '359', { schedule: { team: { id: '359' }, events: [] }, roster: null, stats: { results: {} }, standingsRaw: null });
  ok(empty.stats.length === 0, 'teamdetail: EPL empty results:{} → [] (offseason)');
  ok(empty.roster.length === 0, 'teamdetail: null roster → []');
  const many = { results: { stats: { categories: [{ name: 'general', displayName: 'General', stats: Array.from({ length: 12 }, (_, i) => ({ name: 's' + i, shortDisplayName: 'S' + i, value: i, displayValue: String(i) })) }] } } };
  const d = normalizeTeamDetail(registry, 'soccer/eng.1', '359', { schedule: { team: { id: '359' }, events: [] }, roster: null, stats: many, standingsRaw: null });
  ok(d.stats.length === 1 && d.stats[0].name === 'General' && d.stats[0].stats.length === 8, `teamdetail: no teamStatKeys → per-category, capped at 8 (${d.stats[0]?.stats.length})`);
}

// athlete-shaped standings (racing) → omitted when this team id isn't among them
{
  const racing = { name: 'F1', children: [{ name: 'Driver Standings', standings: { entries: [{ athlete: { id: '5829', displayName: 'Antonelli' }, stats: [{ name: 'rank', displayValue: '1' }] }] } }] };
  const d = normalizeTeamDetail(registry, 'basketball/nba', '13', { schedule: { team: { id: '13' }, events: [] }, roster: null, stats: null, standingsRaw: racing });
  ok(d.standing === undefined, 'teamdetail: athlete-shaped standings without this team → standing omitted');
}

// standingSummary rides the lean /v1/team card too (F3, zero cost)
{
  const card = normalizeTeamCard(registry, 'baseball/mlb', '10', { team: { id: '10', displayName: 'Minnesota Twins', abbreviation: 'MIN', recordSummary: '49-40', standingSummary: '2nd in AL Central' }, events: [] });
  ok(card.team.standingSummary === '2nd in AL Central', `teamcard: standingSummary passthrough (${card.team.standingSummary})`);
  ok(card.team.record === '49-40', 'teamcard: record still present alongside standingSummary');
  const noSummary = normalizeTeamCard(registry, 'baseball/mlb', '10', { team: { id: '10', displayName: 'Twins' }, events: [] });
  ok(noSummary.team.standingSummary === undefined, 'teamcard: absent standingSummary stays undefined (national teams)');
}

// soccer summary: commentary[] → full plays feed; roster stats → box groups
{
  const soccerHeader = { id: '760506', competitions: [{ id: '760506', status: { type: { name: 'STATUS_HALFTIME', state: 'in' } }, competitors: [
    { id: '482', homeAway: 'home', team: { id: '482', abbreviation: 'POR', displayName: 'Portugal', shortDisplayName: 'Portugal' } },
    { id: '164', homeAway: 'away', team: { id: '164', abbreviation: 'ESP', displayName: 'Spain', shortDisplayName: 'Spain' } },
  ] }] };
  const stat = (name, v) => ({ name, value: v, displayValue: String(v) });
  const raw = {
    header: soccerHeader,
    commentary: [
      // deliberately shuffled — builder must sort by sequence
      { sequence: 2, time: { displayValue: "9'" }, text: 'Foul by Lamine Yamal (Spain).', play: { type: { text: 'Foul' }, period: { number: 1 }, team: { displayName: 'Spain' } } },
      { sequence: 0, time: { displayValue: '' }, text: 'Lineups are announced and players are warming up.' },
      { sequence: 3, time: { displayValue: "12'" }, text: 'Goal! Portugal 1, Spain 0.', play: { type: { text: 'Goal - Header' }, period: { number: 1 }, awayScore: 0, homeScore: 1, team: { displayName: 'Portugal' } } },
      { sequence: 1, text: 'First Half begins.', play: { type: { text: 'Kickoff' }, period: { number: 1 }, clock: { displayValue: "1'" } } },
    ],
    rosters: [
      { homeAway: 'home', team: { id: '482', abbreviation: 'POR' }, roster: [
        { starter: true, position: { abbreviation: 'G' }, athlete: { shortName: 'D. Costa' },
          stats: [stat('appearances', 1), stat('saves', 3), stat('goalsConceded', 0), stat('shotsFaced', 4)] },
        { starter: true, position: { abbreviation: 'F' }, athlete: { shortName: 'C. Ronaldo', position: { abbreviation: 'F' } },
          stats: [stat('appearances', 1), stat('totalGoals', 1), stat('totalShots', 2), stat('shotsOnTarget', 1), stat('foulsCommitted', 0), stat('foulsSuffered', 2), stat('yellowCards', 0), stat('redCards', 0), stat('goalAssists', 0)] },
        { starter: false, subbedIn: true, position: { abbreviation: 'M' }, athlete: { shortName: 'Sub Guy' },
          stats: [stat('appearances', 1), stat('totalShots', 1)] },
        { starter: false, subbedIn: false, position: { abbreviation: 'M' }, athlete: { shortName: 'Bench Guy' },
          stats: [stat('appearances', 0)] },
      ] },
      { homeAway: 'away', team: { id: '164', abbreviation: 'ESP' }, roster: [
        { starter: true, position: { abbreviation: 'G' }, athlete: { shortName: 'U. Simón' },
          stats: [stat('appearances', 1), stat('saves', 2), stat('goalsConceded', 1), stat('shotsFaced', 3)] },
      ] },
    ],
  };
  const s = normalizeSummary(registry, 'soccer/fifa.world', raw);
  ok(s.plays?.length === 4, `soccer: commentary → plays feed (got ${s.plays?.length})`);
  ok(s.plays?.[0].text.startsWith('Lineups') && s.plays?.[3].text.startsWith('Goal!'), 'soccer: plays sorted by sequence (bookend first, goal last)');
  const foul = s.plays?.[2];
  ok(foul?.side === 'away' && foul?.teamAbbr === 'ESP' && foul?.type === 'Foul', `soccer: side/abbr attributed via team display name (${JSON.stringify(foul)})`);
  const goal = s.plays?.[3];
  ok(goal?.away === 0 && goal?.home === 1 && goal?.clock === "12'", `soccer: goal row keeps score + clock (${JSON.stringify(goal)})`);
  ok(s.boxGroups.length === 2 && s.boxGroups[0].title === 'Players' && s.boxGroups[1].title === 'Goalkeepers', `soccer: roster stats → two box groups (${s.boxGroups.map(g => g.title)})`);
  const por = s.boxGroups[0].teams.find(t => t.abbr === 'POR');
  ok(por?.rows.length === 2 && por.rows[0].name === 'C. Ronaldo' && por.rows[1].name === 'Sub Guy', `soccer: outfield keeps starters + subbed-in, drops bench + keeper (${por?.rows.map(r => r.name)})`);
  ok(por?.rows[0].stats.join(',') === '1,0,2,1,0,0,0,2', `soccer: outfield stats follow G,A,SH,ST,YC,RC,FC,FA (${por?.rows[0].stats})`);
  const gk = s.boxGroups[1].teams.find(t => t.abbr === 'POR');
  ok(gk?.rows[0].name === 'D. Costa' && gk.rows[0].stats.join(',') === '4,3,0', `soccer: keeper group SHF,SV,GA (${gk?.rows[0].stats})`);
  // an explicit plays[] feed (NBA-style) still wins over commentary
  const nbaish = normalizeSummary(registry, 'soccer/fifa.world', { ...raw, plays: [
    { text: 'A', period: { number: 1 } }, { text: 'B', period: { number: 1 } },
  ] });
  ok(nbaish.plays?.length === 2 && nbaish.plays[0].text === 'A', 'soccer: raw plays[] takes precedence over commentary');
}

// soccer summary: keyEvents[] → structured timeline (goals/cards/subs), noise dropped
{
  const header = { id: 'M9', competitions: [{ id: 'M9', status: { type: { name: 'STATUS_FULL_TIME', state: 'post', completed: true } }, competitors: [
    { id: '10', homeAway: 'home', team: { id: '10', abbreviation: 'AUS', displayName: 'Australia' } },
    { id: '20', homeAway: 'away', team: { id: '20', abbreviation: 'TUR', displayName: 'Türkiye' } },
  ] }] };
  const a = name => ({ athlete: { displayName: name } });
  const keyEvents = [
    { type: { text: 'Kickoff' }, period: { number: 1 }, text: 'First Half begins.' },
    { type: { text: 'Own Goal' }, period: { number: 2 }, clock: { displayValue: "80'" }, scoringPlay: true, team: { id: '10' }, participants: [a('Some Defender')], text: 'Own Goal.' },
    { type: { text: 'Yellow Card' }, period: { number: 1 }, clock: { displayValue: "23'" }, scoringPlay: false, team: { id: '20' }, participants: [a('Yunus Akgün')] },
    { type: { text: 'Goal' }, period: { number: 1 }, clock: { displayValue: "27'" }, scoringPlay: true, team: { id: '10' }, participants: [a('Nestory Irankunda'), a('Paul Okon-Engstler')], text: 'Goal! Australia 1, Türkiye 0.' },
    { type: { text: 'Halftime' }, period: { number: 1 }, clock: { displayValue: "45'+2'" } },
    { type: { text: 'Substitution' }, period: { number: 2 }, clock: { displayValue: "60'" }, scoringPlay: false, team: { id: '10' }, participants: [a('Nishan Velupillay'), a('Nestory Irankunda')] },
  ];
  const s = normalizeSummary(registry, 'soccer/fifa.world', { header, keyEvents });
  const t = s.timeline || [];
  ok(t.length === 4, `soccer timeline: 4 events, Kickoff/Halftime dropped (got ${t.length})`);
  ok(s.plays === undefined, 'soccer timeline: commentary/plays not shipped alongside a timeline');
  ok(t.map(e => e.kind).join(',') === 'yellow-card,goal,substitution,own-goal', `soccer timeline: sorted by period then minute (${t.map(e => e.kind)})`);
  const goal = t.find(e => e.kind === 'goal');
  ok(goal.athlete === 'Nestory Irankunda' && goal.assist === 'Paul Okon-Engstler' && goal.side === 'home' && goal.teamAbbr === 'AUS' && goal.scoring === true, `soccer timeline: goal splits scorer/assist + side (${JSON.stringify(goal)})`);
  const sub = t.find(e => e.kind === 'substitution');
  ok(sub.athlete === 'Nishan Velupillay' && sub.assist === 'Nestory Irankunda' && sub.scoring === false, `soccer timeline: sub = [on, off] (${JSON.stringify(sub)})`);
  ok(t.find(e => e.kind === 'own-goal').scoring === true, 'soccer timeline: own goal counts as scoring');
  ok(t.find(e => e.kind === 'yellow-card').assist === undefined, 'soccer timeline: a card carries no assist');
}

// ---- Track B: sourced live-situation data (hockey power play, tennis serve) ----
{
  // hockey: powerPlay/emptyNet booleans + strength/strengthTeam from lastPlay.
  const nhlSb = {
    leagues: [{ id: '1', slug: 'nhl', name: '', season: {} }],
    events: [{ id: '1', date: '2026-04-01T00:00Z', name: 'A v B', shortName: 'A v B',
      competitions: [{ id: '1',
        status: { type: { name: 'STATUS_IN_PROGRESS', state: 'in', completed: false }, period: 2, displayClock: '5:00' },
        competitors: [
          { id: '17', homeAway: 'home', team: { id: '17', abbreviation: 'CAR', displayName: 'Hurricanes', color: 'cc0000' }, score: '3' },
          { id: '22', homeAway: 'away', team: { id: '22', abbreviation: 'VGK', displayName: 'Golden Knights', color: 'b9975b' }, score: '2' },
        ],
        situation: { powerPlay: true, emptyNet: false, lastPlay: { text: 'Slashing', strength: { abbreviation: 'power-play' }, team: { id: '17' } } },
      }],
    }],
  };
  const hs = normalizeScoreboard(registry, 'hockey/nhl', nhlSb).events[0].competitions[0].situation || {};
  ok(hs.powerPlay === true, 'hockey: situation.powerPlay surfaces');
  ok(hs.emptyNet === false, 'hockey: situation.emptyNet surfaces');
  ok(hs.strength === 'power-play', `hockey: situation.strength from lastPlay.strength (${hs.strength})`);
  ok(hs.strengthTeam === '17', `hockey: strengthTeam from lastPlay.team.id (${hs.strengthTeam})`);

  // tennis: the serving competitor is flagged by a bare `possession` boolean.
  const tennisSb = {
    leagues: [{ id: '1', slug: 'atp', name: '', season: {} }],
    events: [{ id: '1', date: '2026-07-01T00:00Z', name: 'A v B', shortName: 'A v B',
      competitions: [{ id: '1',
        status: { type: { name: 'STATUS_IN_PROGRESS', state: 'in', completed: false }, period: 2 },
        competitors: [
          { id: 'a1', possession: true, athletes: [{ athlete: { id: 'a1', displayName: 'C. Alcaraz', shortName: 'Alcaraz' } }], score: '1', linescores: [{ value: 6, winner: true }] },
          { id: 'a2', possession: false, athletes: [{ athlete: { id: 'a2', displayName: 'J. Sinner', shortName: 'Sinner' } }], score: '0', linescores: [{ value: 4 }] },
        ],
      }],
    }],
  };
  const tcs = normalizeScoreboard(registry, 'tennis/atp', tennisSb).events[0].competitions[0].competitors;
  ok(tcs[0].serving === true, 'tennis: competitor.possession → serving');
  ok(tcs[1].serving === undefined, 'tennis: non-serving competitor carries no serving flag');
}

console.log(`\n${'='.repeat(48)}\n${pass} passed · ${fail} failed`);
if (fails.length) { console.log('\nFAILURES:'); for (const f of fails) console.log('  ✗ ' + f); }
process.exit(fail ? 1 : 0);
