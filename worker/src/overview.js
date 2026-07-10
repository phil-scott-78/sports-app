// overview.js — per-league "season pulse" classifier. Pure (no I/O): given a raw
// ESPN scoreboard payload and a reference instant, it returns a compact
// {state, detail, live} the Leagues list shows as an at-a-glance dot + caption.
//
//   state ∈ live | today | upcoming | recent | offseason
//
// (The endpoint adds a sixth, 'unknown', when a league's fetch itself fails —
// classifyLeague never returns it; on degenerate input it falls back to offseason.)
//
// Why the scoreboard's own `events` aren't enough: the *default* scoreboard
// returns "the current relevant slate", which is NOT always today — between
// seasons ESPN happily hands back next season's opener (NFL in June → September
// games). The reliable signal is `leagues[0].calendar` (the season's game-day
// schedule) cross-referenced with `leagues[0].season.{startDate,endDate}`:
//   - calendarType "day"  → calendar is an ISO date[] (one entry per game day)
//   - calendarType "list" → calendar is an object[] of segments/events with
//                            [startDate,endDate] ranges (NFL nests weeks under
//                            `entries`; golf/F1/MMA list one event per entry)
// From those we derive: is there a game *today* (a range spanning today), how
// many days to the *next* game, how many since the *previous* one, and whether
// `now` falls inside the season window — then bucket into the five states.

// Calendar parsing lives in calendar.js (the single home for it — normalize.js's
// scores passthrough imports the same helpers). See that module for the
// "day" vs "list" calendar shapes.
import { easternDayMs, rangesFromCalendar } from './calendar.js';

const DAY = 86400000;
// A single sporting event (a golf tournament, a race weekend, a multi-day
// tournament) runs at most ~2 weeks; a season *bucket* (a weekly slot, a
// months-long phase) runs far longer. We only trust a calendar range to mean
// "a game is on TODAY" when it looks like one bounded event — see gameWindows.
const EVENT_SPAN_CAP = 14 * DAY;
const WD = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MO = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/**
 * Classify one league's raw ESPN scoreboard into a season-pulse state.
 * @param {object} raw  the ESPN scoreboard JSON
 * @param {Date}   now  reference instant (injected for testability)
 */
export function classifyLeague(raw, now = new Date()) {
  const today = easternDayMs(now);
  const lg = (raw && raw.leagues && raw.leagues[0]) || {};
  const events = (raw && raw.events) || [];
  const ranges = rangesFromCalendar(lg.calendarType, lg.calendar);

  // Actual game days from the returned slate (ET). A reliable *positive* signal:
  // ESPN may hand back a non-today slate, but it never misdates a game.
  const eventDays = [];
  for (const e of events) {
    const ms = easternDayMs(e.date);
    if (ms != null) eventDays.push(ms);
  }

  const todayEvents = events.filter((e) => easternDayMs(e.date) === today);

  // "Game today" fires from a calendar range ONLY when that range is a single
  // bounded event (golf/F1: the event's `date` is its start, so on Sat/Sun only
  // the [start,end] span reveals it's live). A nested season bucket — a weekly
  // slot or a months-long competition phase — spanning today does NOT mean a
  // game is on today: that false positive is what made UEFA (in the gap after
  // its May 30 final) and UFL (the day after a playoff game) read "Games today".
  // Those leagues fall through to their real `events` instead.
  const gameWindows = ranges.filter((r) => !r.nested && (r.end - r.start) <= EVENT_SPAN_CAP);
  const hasToday =
    todayEvents.length > 0 || gameWindows.some((r) => today >= r.start && today <= r.end);

  // A live golf final round / F1 race day is ONE multi-day event dated to its START
  // day, so it never lands in todayEvents — the league would read a static "Games
  // today" instead of "Live now". Detect it via the event window: any in-progress
  // event whose MULTI-day window (r.end > r.start, so a single-day day-calendar slot
  // with a stale overrunning game can't false-positive) spans today.
  const liveToday = todayEvents.some((e) => e?.competitions?.[0]?.status?.type?.state === 'in')
    || (events.some((e) => e?.competitions?.[0]?.status?.type?.state === 'in')
        && gameWindows.some((r) => r.end > r.start && today >= r.start && today <= r.end));

  // Nearest game day on either side — from real events AND every calendar range
  // (season buckets included, so a not-yet-started season still yields its
  // "Returns <date>" from the first bucket before any event is even listed).
  let next = null;
  let prev = null;
  const consider = (s, en) => {
    if (s > today) next = next == null ? s : Math.min(next, s);
    if (en < today) prev = prev == null ? en : Math.max(prev, en);
  };
  for (const r of ranges) consider(r.start, r.end);
  for (const d of eventDays) consider(d, d);

  const season = lg.season || {};
  const sStart = season.startDate ? easternDayMs(season.startDate) : (ranges.length ? ranges[0].start : null);
  const sEnd = season.endDate
    ? easternDayMs(season.endDate)
    : (ranges.length ? Math.max(...ranges.map((r) => r.end)) : null);
  const inSeason = (sStart != null && sEnd != null)
    ? (today >= sStart && today <= sEnd)
    : (hasToday || next != null);

  const dNext = next != null ? Math.round((next - today) / DAY) : null;
  const dPrev = prev != null ? Math.round((today - prev) / DAY) : null;
  const wd = (ms) => WD[new Date(ms).getUTCDay()];
  const md = (ms) => `${MO[new Date(ms).getUTCMonth()]} ${new Date(ms).getUTCDate()}`;

  if (hasToday) {
    return liveToday
      ? { state: 'live', detail: 'Live now', live: true }
      : { state: 'today', detail: 'Games today', live: false };
  }
  if (!inSeason) {
    return { state: 'offseason', detail: next != null ? `Returns ${md(next)}` : 'Off-season', live: false };
  }
  if (dNext != null && dNext <= 7) {
    return { state: 'upcoming', detail: dNext <= 1 ? 'Tomorrow' : wd(next), live: false };
  }
  if (dPrev != null && dPrev <= 3) {
    return { state: 'recent', detail: dPrev <= 1 ? 'Yesterday' : wd(prev), live: false };
  }
  if (dNext != null) return { state: 'upcoming', detail: `Next ${md(next)}`, live: false };
  if (dPrev != null) return { state: 'recent', detail: `Last ${md(prev)}`, live: false };
  return { state: 'offseason', detail: 'Off-season', live: false };
}

/**
 * Classify a MERGED `<sport>/all` scoreboard — one slate spanning every league
 * of a sport (exists for soccer/rugby/rugby-league/tennis/golf/mma, verified
 * live 2026-07; the registry capability `hasAllScoreboard` gates callers) —
 * into per-league pulse entries keyed by the numeric ESPN league id parsed
 * from each event's uid (`s:600~l:700~e:…`).
 *
 * The merged feed carries NO per-league season/calendar, so this can only
 * assert the POSITIVE states — live | today — and stays silent about every
 * league without a game in the slate (the per-league classifyLeague fan-out
 * supplies upcoming/recent/offseason captions behind it). Explore's hybrid
 * pulse runs this first, one fetch per sport, so LIVE NOW / ON TODAY fill in
 * a single round-trip instead of fetch-completion order.
 *
 * @param {object} raw  the merged ESPN scoreboard JSON
 * @param {Date}   now  reference instant (injected for testability)
 * @returns {Record<string, {state:string, detail:string, live:boolean}>}
 */
export function classifyMergedSlate(raw, now = new Date()) {
  const today = easternDayMs(now);
  // First-seen order per league id, matching the slate's own event order.
  const acc = new Map();
  for (const e of (raw && raw.events) || []) {
    const m = /(?:^|~)l:(\d+)(?:~|$)/.exec((e && e.uid) || '');
    if (!m) continue;
    const cur = acc.get(m[1]) || { live: false, today: false };
    // An in-progress event is live NOW regardless of its listed date (golf/MMA
    // date to their start day); a dated-today event marks the day's slate.
    if (e?.competitions?.[0]?.status?.type?.state === 'in') cur.live = true;
    if (easternDayMs(e.date) === today) cur.today = true;
    acc.set(m[1], cur);
  }
  const out = {};
  for (const [id, s] of acc) {
    if (s.live) out[id] = { state: 'live', detail: 'Live now', live: true };
    else if (s.today) out[id] = { state: 'today', detail: 'Games today', live: false };
  }
  return out;
}
