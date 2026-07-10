// Tests for the /overview season-pulse classifier. The bulk are PURE and
// deterministic (synthetic ESPN shapes + a fixed `now`), so they run without
// network; a short live smoke at the end asserts real leagues land on a valid
// state. Run: node test/overview.test.mjs
import { classifyLeague, classifyMergedSlate } from '../src/overview.js';
import { fetchScoreboard } from '../src/espn.js';

let pass = 0, fail = 0;
const fails = [];
const ok = (c, m) => { if (c) pass++; else { fail++; fails.push(m); } };
const eq = (a, b, m) => ok(a === b, `${m} (got ${JSON.stringify(a)}, want ${JSON.stringify(b)})`);

// Fixed reference instant → ET "today" = 2026-06-13 (14:00 EDT).
const NOW = new Date('2026-06-13T18:00:00Z');
const fullYear = { startDate: '2026-01-01T05:00Z', endDate: '2026-12-31T05:00Z' };

// day-type calendar (ISO date[]), list-type calendar (object ranges).
const dayCal = (...days) => ({ calendarType: 'day', calendar: days, season: fullYear });
const listCal = (entries, season = fullYear) => ({ calendarType: 'list', calendar: entries, season });
const sb = (league, events = []) => ({ leagues: [league], events });

// --- live: a game today, in progress -----------------------------------------
{
  const c = classifyLeague(sb(dayCal('2026-06-13T07:00Z'),
    [{ date: '2026-06-13T23:00:00Z', competitions: [{ status: { type: { state: 'in' } } }] }]), NOW);
  eq(c.state, 'live', 'live: state'); eq(c.live, true, 'live: live flag');
}
// --- today: a game today, not yet started ------------------------------------
{
  const c = classifyLeague(sb(dayCal('2026-06-13T07:00Z'),
    [{ date: '2026-06-13T23:00:00Z', competitions: [{ status: { type: { state: 'pre' } } }] }]), NOW);
  eq(c.state, 'today', 'today: state'); eq(c.live, false, 'today: not live');
}
// --- today via a multi-day (list) event spanning today (golf/F1) -------------
{
  const c = classifyLeague(sb(listCal([{ startDate: '2026-06-11T08:00Z', endDate: '2026-06-14T08:00Z' }])), NOW);
  eq(c.state, 'today', 'list-span: today');
}
// --- upcoming (tomorrow) -----------------------------------------------------
{
  const c = classifyLeague(sb(dayCal('2026-06-14T07:00Z')), NOW);
  eq(c.state, 'upcoming', 'tomorrow: state'); eq(c.detail, 'Tomorrow', 'tomorrow: detail');
}
// --- upcoming (this week → weekday) ------------------------------------------
{
  const c = classifyLeague(sb(dayCal('2026-06-17T07:00Z')), NOW); // Wed
  eq(c.state, 'upcoming', 'midweek: state'); eq(c.detail, 'Wed', 'midweek: detail');
}
// --- recent (yesterday), in-season, nothing upcoming -------------------------
{
  const c = classifyLeague(sb(dayCal('2026-06-12T07:00Z')), NOW);
  eq(c.state, 'recent', 'yesterday: state'); eq(c.detail, 'Yesterday', 'yesterday: detail');
}
// --- offseason: season window has ended --------------------------------------
{
  const c = classifyLeague(sb({
    calendarType: 'day', calendar: ['2026-05-24T07:00Z'],
    season: { startDate: '2025-08-15T07:00Z', endDate: '2026-05-31T07:00Z' },
  }), NOW);
  eq(c.state, 'offseason', 'ended: state'); eq(c.detail, 'Off-season', 'ended: detail');
}
// --- offseason: season not started → "Returns <date>" (NFL in June) ----------
{
  const c = classifyLeague(sb(listCal(
    [{ startDate: '2026-08-06T07:00Z', endDate: '2026-09-09T06:59Z',
       entries: [{ startDate: '2026-08-06T07:00Z', endDate: '2026-08-13T06:59Z' }] }],
    { startDate: '2026-08-06T07:00Z', endDate: '2027-02-16T07:00Z' })), NOW);
  eq(c.state, 'offseason', 'preseason: state'); eq(c.detail, 'Returns Aug 6', 'preseason: detail');
}
// --- degenerate input never throws -------------------------------------------
{
  const c = classifyLeague({}, NOW);
  ok(typeof c.state === 'string', 'empty payload yields a state, no throw');
  ok(['offseason', 'unknown'].includes(c.state), 'empty payload → offseason');
}

// --- merged '<sport>/all' slate → per-league-id live/today --------------------
{
  const ev = (leagueId, date, state) => ({
    uid: `s:600~l:${leagueId}~e:1`,
    date,
    competitions: [{ status: { type: { state } } }],
  });
  const m = classifyMergedSlate({ events: [
    ev(700, '2026-06-13T19:00Z', 'in'),   // live now
    ev(740, '2026-06-13T23:00Z', 'pre'),  // later today
    ev(720, '2026-06-14T19:00Z', 'pre'),  // tomorrow → silent
    ev(700, '2026-06-13T23:00Z', 'pre'),  // second eng.1 game doesn't demote live
    { date: '2026-06-13T19:00Z', competitions: [{ status: { type: { state: 'in' } } }] }, // no uid → skipped
  ] }, NOW);
  eq(m['700']?.state, 'live', 'merged: in-progress league is live');
  eq(m['700']?.live, true, 'merged: live flag');
  eq(m['740']?.state, 'today', 'merged: dated-today league is today');
  eq(m['720'], undefined, 'merged: future-dated league stays silent');
  eq(Object.keys(m).length, 2, 'merged: only positive states emitted');
}
// --- merged: a live event dated to its start day (golf Sunday) still reads live
{
  const m = classifyMergedSlate({ events: [{
    uid: 's:1106~l:1108~e:9',
    date: '2026-06-11T13:00Z', // tournament start day, not today
    competitions: [{ status: { type: { state: 'in' } } }],
  }] }, NOW);
  eq(m['1108']?.state, 'live', 'merged: in-progress multi-day event is live');
}
// --- merged: degenerate input never throws ------------------------------------
{
  ok(Object.keys(classifyMergedSlate({}, NOW)).length === 0, 'merged: empty payload → {}');
  ok(Object.keys(classifyMergedSlate(null, NOW)).length === 0, 'merged: null payload → {}');
}

// --- live smoke: real leagues land on a valid state --------------------------
const VALID = new Set(['live', 'today', 'upcoming', 'recent', 'offseason']);
for (const key of ['baseball/mlb', 'basketball/nba']) {
  try {
    const c = classifyLeague(await fetchScoreboard(key), new Date());
    ok(VALID.has(c.state), `${key}: valid state (${c.state})`);
    ok(typeof c.detail === 'string' && c.detail.length > 0, `${key}: has detail`);
    console.log(`${key} — ${c.state} · ${c.detail}`);
  } catch (e) {
    fail++; fails.push(`${key}: live smoke threw ${e.message}`);
  }
}

console.log(`\n${'='.repeat(48)}\n${pass} passed · ${fail} failed`);
if (fails.length) { console.log('\nFAILURES:'); for (const f of fails) console.log('  ✗ ' + f); }
process.exit(fail ? 1 : 0);
