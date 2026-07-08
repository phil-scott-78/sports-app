// Unit test for the offline mock synthesizer (mock/synth.mjs). Pure, no network.
// Asserts the contract the mock backend relies on: a captured pool — whatever
// phase it was captured in — projects to a current final + live + scheduled slate
// that the REAL normalizers accept, and that the result is deterministic (so
// polling never makes a frozen game flicker). Run: node test/mock.test.mjs

import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import registry from '../../schema/league-profiles.json' with { type: 'json' };
import {
  synthScoreboard, synthSummary, synthTeamScoreboard, synthTeams,
  synthRankings, synthGolfExtras, synthGolfScorecard, synthMmaCore,
  synthTeamDetailParts, synthCoreSituation, synthCorePredictor, synthCorePlayText,
} from '../mock/synth.mjs';
import { getScenario } from '../mock/scenarios.mjs';
import { normalizeScoreboard } from '../src/normalize.js';
import { normalizeSummary, normalizeMmaSummary, buildCoreSituation, winProbabilityFromPredictor } from '../src/summary.js';
import { normalizeGolfScorecard } from '../src/scorecard.js';
import { normalizeRankings } from '../src/rankings.js';
import { normalizeTeamDetail } from '../src/teamdetail.js';

let pass = 0, fail = 0; const fails = [];
const ok = (cond, msg) => { if (cond) pass++; else { fail++; fails.push(msg); } };

const NOW = Date.parse('2026-06-15T18:00:00Z'); // fixed reference instant
const HERE = dirname(fileURLToPath(import.meta.url));
const FIX_DIR = join(HERE, '..', 'mock', 'fixtures');

const phasesOf = (norm) => {
  const ph = {};
  for (const e of norm.events) for (const c of e.competitions) ph[c.status.phase] = (ph[c.status.phase] || 0) + 1;
  return ph;
};

// ---- inline fixtures (no capture needed) ------------------------------------
const ls9 = () => Array.from({ length: 9 }, (_, i) => ({ value: 0, displayValue: '0', period: i + 1 }));
const mlbFinal = (id, h, a) => ({
  id, date: '2026-06-10T18:00Z', name: 'Away at Home', shortName: 'AWY @ HOM',
  competitions: [{
    id, status: { type: { name: 'STATUS_FINAL', state: 'post', completed: true, detail: 'Final', shortDetail: 'Final' } },
    competitors: [
      { id: '9', homeAway: 'home', order: 0, winner: h > a, team: { id: '9', displayName: 'Twins', abbreviation: 'MIN' }, score: String(h), linescores: ls9() },
      { id: '24', homeAway: 'away', order: 1, winner: a > h, team: { id: '24', displayName: 'Cardinals', abbreviation: 'STL' }, score: String(a), linescores: ls9() },
    ],
  }],
});
const mlbFixture = { key: 'baseball/mlb', league: { id: '10', name: 'MLB', slug: 'mlb' }, events: [mlbFinal('1', 5, 3), mlbFinal('2', 2, 7), mlbFinal('3', 1, 0), mlbFinal('4', 8, 6)], teams: null, standings: null, summaries: {} };

// ---- 1. today slate has all three phases + anyLive --------------------------
{
  const norm = normalizeScoreboard(registry, 'baseball/mlb', synthScoreboard(registry, 'baseball/mlb', mlbFixture, { now: NOW }));
  const ph = phasesOf(norm);
  ok(ph.final > 0, 'today: has final games');
  ok(ph.live > 0, 'today: has live games');
  ok(ph.scheduled > 0, 'today: has scheduled games');
  ok(norm.anyLive === true, 'today: anyLive true');
  ok(norm.day === '2026-06-15', `today: day stamped (${norm.day})`);
}

// ---- 2. deterministic on id (no flicker between polls) ----------------------
{
  const a = synthScoreboard(registry, 'baseball/mlb', mlbFixture, { now: NOW });
  const b = synthScoreboard(registry, 'baseball/mlb', mlbFixture, { now: NOW });
  ok(JSON.stringify(a) === JSON.stringify(b), 'same (fixture, now) → identical output');
}

// ---- 3. dates land in the right window ---------------------------------------
{
  const sb = synthScoreboard(registry, 'baseball/mlb', mlbFixture, { now: NOW });
  for (const ev of sb.events) {
    const ms = Date.parse(ev.date); const ph = ev.competitions[0].status.type.state;
    if (ph === 'in') ok(ms <= NOW && ms > NOW - 6 * 3600000, 'live game started recently (past, <6h)');
    if (ph === 'pre') ok(ms > NOW, 'scheduled game is in the future');
    if (ph === 'post') ok(ms < NOW, 'final game is in the past');
  }
}

// ---- 4. a past day → finals; a future day → scheduled -----------------------
{
  const past = normalizeScoreboard(registry, 'baseball/mlb', synthScoreboard(registry, 'baseball/mlb', mlbFixture, { now: NOW, date: '20260601' }));
  const fut = normalizeScoreboard(registry, 'baseball/mlb', synthScoreboard(registry, 'baseball/mlb', mlbFixture, { now: NOW, date: '20270101' }));
  ok(Object.keys(phasesOf(past)).every((p) => p === 'final'), 'past day → only finals');
  ok(Object.keys(phasesOf(fut)).every((p) => p === 'scheduled'), 'future day → only scheduled');
}

// ---- 5. authentic finals are preserved (scores not recomputed) --------------
{
  const sb = synthScoreboard(registry, 'baseball/mlb', mlbFixture, { now: NOW });
  const finals = sb.events.filter((e) => e.competitions[0].status.type.state === 'post');
  // every final's scoreline must be one of the captured pairs (5-3, 2-7, 1-0, 8-6)
  const pairs = new Set(['5,3', '2,7', '1,0', '8,6']);
  ok(finals.every((e) => pairs.has(e.competitions[0].competitors.map((c) => c.score).join(','))), 'captured final scores preserved verbatim');
}

// ---- 6. fabrication: empty pool + a teams list → a full slate ----------------
{
  const teams = { sports: [{ leagues: [{ teams: Array.from({ length: 8 }, (_, i) => ({ team: { id: String(i + 1), displayName: `Team ${i + 1}`, abbreviation: `T${i + 1}` } })) }] }] };
  const fx = { key: 'baseball/mlb', league: { id: '10', name: 'MLB', slug: 'mlb' }, events: [], teams, standings: null, summaries: {} };
  const norm = normalizeScoreboard(registry, 'baseball/mlb', synthScoreboard(registry, 'baseball/mlb', fx, { now: NOW }));
  const ph = phasesOf(norm);
  ok(ph.live > 0 && ph.final > 0 && ph.scheduled > 0, 'fabricated-from-teams slate has all three phases');
  ok(synthTeams(fx).sports[0].leagues[0].teams.length === 8, 'synthTeams passes the picker list through');
}

// ---- 7. team card slate gives the team a last + next -------------------------
{
  const sb = synthTeamScoreboard(registry, 'baseball/mlb', mlbFixture, '9', { now: NOW });
  const states = sb.events.map((e) => e.competitions[0].status.type.state);
  ok(sb.events.length >= 2, 'team slate has multiple games');
  ok(states.includes('post') && states.includes('pre'), 'team slate has a final (last) + a scheduled (next)');
  ok(sb.events.every((e) => e.competitions[0].competitors.some((c) => String(c.id) === '9')), 'every team-slate game features the team');
}

// ---- 8. minimal summary for an uncaptured event is valid --------------------
{
  const s = normalizeSummary(registry, 'baseball/mlb', synthSummary(mlbFixture, 'nope-123'));
  ok(s.eventId === 'nope-123', 'minimal summary carries the event id');
  ok(Array.isArray(s.boxGroups) && s.boxGroups.length === 0, 'minimal summary degrades to empty box groups');
}

// ---- 8b. borrowed summary (calendar-proof fix, §8.2): a summary-less event ----
// borrows another captured summary from the SAME league and rebases its date/status
// — deterministic by event id, stable across polls — instead of the empty envelope.
{
  const oldRaw = {
    header: { id: '999', competitions: [{
      id: '999', date: '2025-01-01T00:00:00Z',
      status: { type: { id: '3', name: 'STATUS_FINAL', state: 'post', completed: true, detail: 'Final', shortDetail: 'Final' }, period: 9 },
      competitors: [
        { id: '9', homeAway: 'home', team: { id: '9', abbreviation: 'MIN' }, score: '5' },
        { id: '24', homeAway: 'away', team: { id: '24', abbreviation: 'STL' }, score: '3' },
      ],
    }] },
    boxscore: { teams: [], players: [] }, plays: [], scoringPlays: [], keyEvents: [], rosters: [],
  };
  const fx = { ...mlbFixture, summaries: { 999: oldRaw } };
  const eventId = 'zzz-uncaptured-1'; // no exact/base match → must borrow
  const borrowed = synthSummary(fx, eventId, { now: NOW });
  const c = borrowed.header.competitions[0];
  ok(borrowed.header.id === eventId, `borrowed summary: header id rebased to the requested event (got ${borrowed.header.id})`);
  ok(c.id === eventId, 'borrowed summary: competition id rebased too');
  ok(['pre', 'in', 'post'].includes(c.status.type.state), `borrowed summary: valid status state (${c.status.type.state})`);
  ok(c.date !== '2025-01-01T00:00:00Z', 'borrowed summary: stale capture-time date replaced');
  ok(c.competitors.map((x) => x.score).join(',') === '5,3', 'borrowed summary: donor box score/scoreline left untouched');

  // deterministic per (eventId, now)
  const again = synthSummary(fx, eventId, { now: NOW });
  ok(JSON.stringify(borrowed) === JSON.stringify(again), 'borrowed summary: deterministic per (eventId, now)');

  // phase is keyed off the id, not `now` — never flickers state between polls
  const laterPoll = synthSummary(fx, eventId, { now: NOW + 20000 });
  ok(laterPoll.header.competitions[0].status.type.state === c.status.type.state, 'borrowed summary: phase stable across polls');

  // normalizes cleanly through the real normalizer, keyed to the rebased id
  const norm = normalizeSummary(registry, 'baseball/mlb', borrowed);
  ok(norm.eventId === eventId, 'borrowed summary: normalizer reads the rebased event id');
  ok(norm.live === (c.status.type.state === 'in'), 'borrowed summary: normalizer live flag matches rebased status');

  // exact-id match is still returned verbatim — NOT rebased (real capture, real date)
  const exact = synthSummary(fx, '999', { now: NOW });
  ok(exact.header.competitions[0].date === '2025-01-01T00:00:00Z', 'exact-match summary: returned verbatim, unrebased');
}

// ---- 9. sweep captured fixtures (if any): every one normalizes -------------
{
  let files = [];
  try { files = readdirSync(FIX_DIR).filter((f) => f.endsWith('.json') && f !== '_manifest.json'); } catch { /* none */ }
  for (const f of files) {
    let fx; try { fx = JSON.parse(readFileSync(join(FIX_DIR, f), 'utf8')); } catch { continue; }
    if (!fx.key || !registry.leagues[fx.key]) continue;
    let norm;
    try { norm = normalizeScoreboard(registry, fx.key, synthScoreboard(registry, fx.key, fx, { now: NOW })); }
    catch (e) { ok(false, `${fx.key}: synth+normalize threw — ${e.message}`); continue; }
    ok(Array.isArray(norm.events), `${fx.key}: produces events array`);
    if (fx.events?.length) {
      const ph = phasesOf(norm);
      ok((ph.live || 0) > 0, `${fx.key}: today slate has a live game`);
      ok((ph.final || 0) > 0 && (ph.scheduled || 0) > 0, `${fx.key}: today slate has final + scheduled`);
    }
  }
}

// ---- 10. golf mock: meta.golf extras + walkable scorecards -------------------
{
  const golfFixture = { key: 'golf/pga', league: { id: '1106', slug: 'pga', name: 'PGA Tour' }, events: [{
    id: 'G1', date: '2026-06-10T14:00Z', name: 'Mock Open', shortName: 'Open',
    competitions: [{ id: 'G1', status: { type: { name: 'STATUS_FINAL', state: 'post', completed: true } }, competitors: [
      { id: '111', order: 1, athlete: { displayName: 'A. Leader' }, score: '-12' },
      { id: '222', order: 2, athlete: { displayName: 'B. Chaser' }, score: '-9' },
    ] }],
  }], teams: null, standings: null, summaries: {} };
  const sb1 = synthScoreboard(registry, 'golf/pga', golfFixture, { now: NOW });
  const extras = synthGolfExtras(registry, 'golf/pga', golfFixture, sb1);
  ok(extras?.golfTournaments && Object.keys(extras.golfTournaments).length === sb1.events.length,
    'golf mock: extras fabricated for every synthesized event');
  const norm = normalizeScoreboard(registry, 'golf/pga', sb1, extras);
  ok(norm.events.every(e => e.competitions.every(c => c.meta?.golf?.numberOfRounds > 0)),
    'golf mock: every event gets meta.golf through the real normalizer');
  // deterministic: same now → same meta (no flicker on poll)
  const extras2 = synthGolfExtras(registry, 'golf/pga', golfFixture, synthScoreboard(registry, 'golf/pga', golfFixture, { now: NOW }));
  ok(JSON.stringify(extras) === JSON.stringify(extras2), 'golf mock: extras deterministic');

  // fabricated scorecard: every leaderboard row opens a walkable card
  const raw1 = synthGolfScorecard(registry, 'golf/pga', golfFixture, 'G1', '111', { now: NOW });
  const sc = normalizeGolfScorecard('golf/pga', 'G1', '111', raw1);
  ok(sc.player.name === 'A. Leader', `golf mock: scorecard resolves the pool athlete name (got ${sc.player.name})`);
  ok(sc.rounds.length === 4 && sc.rounds[0].holes.length === 18, 'golf mock: 4 rounds, 18 holes on completed rounds');
  ok(sc.rounds[3].holes.length === 0 && sc.rounds[3].teeTime, 'golf mock: final round pre-start → teeTime only');
  ok(sc.rounds[0].holes.every(h => h.par >= 3 && h.par <= 5 && h.scoreType), 'golf mock: holes carry par + scoreType');
  const raw2 = synthGolfScorecard(registry, 'golf/pga', golfFixture, 'G1', '111', { now: NOW });
  ok(JSON.stringify(raw1) === JSON.stringify(raw2), 'golf mock: scorecard deterministic');
  // captured passthrough wins over fabrication
  const withCaptured = { ...golfFixture, scorecards: { 'G1/111': { profile: { id: '111', displayName: 'Captured Guy' }, rounds: [] } } };
  ok(normalizeGolfScorecard('golf/pga', 'G1', '111', synthGolfScorecard(registry, 'golf/pga', withCaptured, 'G1', '111', { now: NOW })).player.name === 'Captured Guy',
    'golf mock: captured scorecard passthrough');
}

// ---- 11. MMA mock: core shapes through the real normalizeMmaSummary ----------
{
  const bout = (id, a, b) => ({ id, status: { type: { name: 'STATUS_FINAL', state: 'post', completed: true } }, competitors: [
    { id: a, order: 1, winner: true, athlete: { displayName: 'Fighter ' + a } },
    { id: b, order: 2, winner: false, athlete: { displayName: 'Fighter ' + b } },
  ] });
  const mmaFixture = { key: 'mma/ufc', league: { id: '3321', slug: 'ufc', name: 'UFC' }, events: [{
    id: 'M1', date: '2026-06-10T22:00Z', name: 'Mock Card', shortName: 'UFC',
    competitions: [bout('b1', 'f1', 'f2'), bout('b2', 'f3', 'f4'), bout('b3', 'f5', 'f6'), bout('b4', 'f7', 'f8')],
  }], teams: null, standings: null, summaries: {} };
  const sb1 = synthScoreboard(registry, 'mma/ufc', mmaFixture, { now: NOW });
  const evId = String(sb1.events[0].id);
  const { coreEvent, statuses, linescores } = synthMmaCore(registry, 'mma/ufc', mmaFixture, evId, { now: NOW });
  const s = normalizeMmaSummary(coreEvent, statuses, linescores);
  ok(s.eventId === evId, 'mma mock: summary keyed to the requested event');
  ok(s.bouts.length > 0, `mma mock: finished bouts carry results (got ${s.bouts.length})`);
  ok(s.bouts.every(b => b.result || b.round != null), 'mma mock: every shipped bout has result data');
  const dec = s.bouts.find(b => /decision/i.test(b.result || ''));
  if (dec) {
    ok(Array.isArray(dec.judges) && dec.judges.length === 2 && dec.judges[0].totals.length === 3,
      `mma mock: decision bouts get 2×3 judge totals (${JSON.stringify(dec.judges)})`);
  }
  const again = normalizeMmaSummary(...(({ coreEvent: ce, statuses: st, linescores: ls }) => [ce, st, ls])(synthMmaCore(registry, 'mma/ufc', mmaFixture, evId, { now: NOW })));
  ok(JSON.stringify(s) === JSON.stringify(again), 'mma mock: deterministic per event id');
}

// ---- 12. rankings mock: captured passthrough / empty default -----------------
{
  ok(normalizeRankings(synthRankings({})).polls.length === 0, 'rankings mock: no capture → empty polls');
  const fx = { rankings: { rankings: [{ name: 'ATP', shortName: 'ATP', ranks: [{ current: 1, points: 9999, athlete: { id: '1', displayName: 'Mock Star' } }] }] } };
  const r = normalizeRankings(synthRankings(fx));
  ok(r.polls[0]?.ranks[0]?.athlete?.name === 'Mock Star', 'rankings mock: captured payload flows through the real normalizer');
}

// ---- 13. team detail mock: schedule + fabricated roster/stats, deterministic --
{
  const parts = synthTeamDetailParts(registry, 'baseball/mlb', mlbFixture, '9', { now: NOW });
  const d = normalizeTeamDetail(registry, 'baseball/mlb', '9', parts);
  ok(d.team.id === '9', 'teamdetail mock: team identity');
  ok(typeof d.team.standingSummary === 'string' && d.team.standingSummary.length > 0, `teamdetail mock: standingSummary present (${d.team.standingSummary})`);
  ok(d.schedule.length >= 4, `teamdetail mock: multi-game schedule (${d.schedule.length})`);
  const phases = new Set(d.schedule.map((e) => e.competitions[0].status.phase));
  ok(phases.has('final') && phases.has('scheduled'), `teamdetail mock: has past finals + future scheduled (${[...phases]})`);
  ok(d.roster.length > 0 && d.roster[0].athletes.length > 0, 'teamdetail mock: fabricated roster non-empty');
  ok(d.stats.length > 0 && d.stats[0].stats.length > 0, 'teamdetail mock: fabricated stats non-empty');
  // deterministic per (team, now) so polling never flickers
  const again = normalizeTeamDetail(registry, 'baseball/mlb', '9', synthTeamDetailParts(registry, 'baseball/mlb', mlbFixture, '9', { now: NOW }));
  ok(JSON.stringify(d) === JSON.stringify(again), 'teamdetail mock: deterministic per (team, now)');
}

// ---- 14. scenario "megaweek": max-live today + one championship on the champ day ----
{
  const sc = getScenario('megaweek');
  ok(sc && sc.name === 'megaweek', 'megaweek: scenario resolves by name');
  ok(getScenario('nope') === null && getScenario(null) === null, 'megaweek: unknown/empty scenario → null');

  // today → mostly live, but still ≥1 final + ≥1 scheduled (every UI state reachable)
  const ph = phasesOf(normalizeScoreboard(registry, 'baseball/mlb', synthScoreboard(registry, 'baseball/mlb', mlbFixture, { now: NOW, scenario: sc })));
  ok((ph.live || 0) >= (ph.final || 0) + (ph.scheduled || 0), `megaweek today: live dominates the slate (${JSON.stringify(ph)})`);
  ok((ph.final || 0) > 0 && (ph.scheduled || 0) > 0, 'megaweek today: still keeps a final + a scheduled');

  // deterministic on (fixture, now) so polling never flickers
  const a = synthScoreboard(registry, 'baseball/mlb', mlbFixture, { now: NOW, scenario: sc });
  const b = synthScoreboard(registry, 'baseball/mlb', mlbFixture, { now: NOW, scenario: sc });
  ok(JSON.stringify(a) === JSON.stringify(b), 'megaweek: deterministic per (fixture, now)');

  // exactly one "Championship" hero across the week, and never today; ≤1 on any day
  const champDays = [];
  for (let d = 1; d <= 6; d++) {
    const ymd = new Date(NOW + d * 86400000).toISOString().slice(0, 10).replace(/-/g, '');
    const nrm = normalizeScoreboard(registry, 'baseball/mlb', synthScoreboard(registry, 'baseball/mlb', mlbFixture, { now: NOW, date: ymd, scenario: sc }));
    const champs = nrm.events.filter((e) => e.competitions.some((c) => c.meta?.round === 'Championship'));
    ok(champs.length <= 1, `megaweek day +${d}: at most one championship hero (${champs.length})`);
    if (champs.length) champDays.push(d);
  }
  ok(champDays.length === 1, `megaweek: exactly one champ day this week (got days ${JSON.stringify(champDays)})`);
  const todayChamp = normalizeScoreboard(registry, 'baseball/mlb', synthScoreboard(registry, 'baseball/mlb', mlbFixture, { now: NOW, scenario: sc }))
    .events.some((e) => e.competitions.some((c) => c.meta?.round === 'Championship'));
  ok(!todayChamp, 'megaweek: today is live spectacle, no championship badge');

  // regression: no scenario → the normal mixed 3-state slate, unchanged
  const plain = phasesOf(normalizeScoreboard(registry, 'baseball/mlb', synthScoreboard(registry, 'baseball/mlb', mlbFixture, { now: NOW })));
  ok((plain.live || 0) > 0 && (plain.final || 0) > 0 && (plain.scheduled || 0) > 0, 'no scenario → normal 3-state mix preserved');
}

// ---- 15. mock core resources (situation / predictor) through the normalizers --
{
  // Football: down/distance/yardLine/isRedZone + bare-number timeouts + lastPlay.
  {
    const prof = { espnSport: 'football' };
    const sit = synthCoreSituation(prof, 'cfb-1');
    sit.lastPlay = { $ref: 'x' };
    const c = buildCoreSituation(sit, synthCorePlayText('cfb-1', 'football'));
    ok(c && c.down >= 1 && c.down <= 4, `core-sit football: down (${c && c.down})`);
    ok(typeof c.yardLine === 'number' && typeof c.distance === 'number', 'core-sit football: distance + yardLine numeric');
    ok(typeof c.homeTimeouts === 'number' && typeof c.awayTimeouts === 'number', 'core-sit football: bare-number timeouts');
    ok(typeof c.lastPlay === 'string' && c.lastPlay.length > 0, 'core-sit football: lastPlay text resolved');
    ok(c.downDistanceText === undefined && c.possession === undefined, 'core-sit football: no downDistanceText/possession (core-only truth)');
  }
  // Basketball: bonusState → homeBonus/awayBonus + object-timeout remaining.
  {
    const sit = synthCoreSituation({ espnSport: 'basketball' }, 'nba-1');
    const c = buildCoreSituation(sit);
    ok(typeof c.homeBonus === 'string' && typeof c.awayBonus === 'string', 'core-sit basketball: bonus strings');
    ok(typeof c.homeTimeouts === 'number' && c.homeTimeouts >= 0 && c.homeTimeouts <= 7, 'core-sit basketball: timeoutsRemainingCurrent unwrapped to a number');
    ok(c.down === undefined && c.yardLine === undefined, 'core-sit basketball: no gridiron fields');
  }
  // Hockey: powerPlay/emptyNet booleans.
  {
    const c = buildCoreSituation(synthCoreSituation({ espnSport: 'hockey' }, 'nhl-1'));
    ok(typeof c.powerPlay === 'boolean' && typeof c.emptyNet === 'boolean', 'core-sit hockey: powerPlay/emptyNet booleans');
  }
  // Predictor → win probability that sums to 100, deterministic.
  {
    const wp = winProbabilityFromPredictor(synthCorePredictor('cfb-1'));
    ok(wp && wp.home + wp.away === 100, `predictor: win prob sums to 100 (${JSON.stringify(wp)})`);
    const again = winProbabilityFromPredictor(synthCorePredictor('cfb-1'));
    ok(JSON.stringify(wp) === JSON.stringify(again), 'predictor: deterministic per event id');
    ok(winProbabilityFromPredictor({}) === undefined, 'predictor: empty → undefined (fallback stays off)');
  }
  // Deterministic situation per event id (no flicker on poll).
  {
    const a = synthCoreSituation({ espnSport: 'football' }, 'cfb-9');
    const b = synthCoreSituation({ espnSport: 'football' }, 'cfb-9');
    ok(JSON.stringify(a) === JSON.stringify(b), 'core-sit: deterministic per event id');
  }
}

console.log(`\n${'='.repeat(48)}\n${pass} passed · ${fail} failed`);
if (fails.length) { console.log('\nFAILURES:'); for (const f of fails) console.log('  ✗ ' + f); }
process.exit(fail ? 1 : 0);
