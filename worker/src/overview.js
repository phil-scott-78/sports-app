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

const DAY = 86400000;
// A single sporting event (a golf tournament, a race weekend, a multi-day
// tournament) runs at most ~2 weeks; a season *bucket* (a weekly slot, a
// months-long phase) runs far longer. We only trust a calendar range to mean
// "a game is on TODAY" when it looks like one bounded event — see gameWindows.
const EVENT_SPAN_CAP = 14 * DAY;
const WD = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MO = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

// US-Eastern calendar day as a UTC-midnight stamp, matching ESPN's bucketing
// (and the app's "today"). Intl resolves EST/EDT automatically. Null if unparsable.
function easternDayMs(input) {
  const d = input instanceof Date ? input : new Date(input);
  if (Number.isNaN(d.getTime())) return null;
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: 'America/New_York', year: 'numeric', month: '2-digit', day: '2-digit',
  }).formatToParts(d);
  const g = (t) => Number(parts.find((p) => p.type === t).value);
  return Date.UTC(g('year'), g('month') - 1, g('day'));
}

// Collapse a league's calendar into sorted ranges (ET days), each tagged with
// whether it came from a NESTED season bucket (a week/phase under `entries`) vs
// a flat top-level entry (a single event). Shape: { start, end, nested }.
function rangesFromCalendar(calendarType, calendar) {
  const out = [];
  if (!Array.isArray(calendar) || !calendar.length) return out;
  const isDay = calendarType === 'day' || typeof calendar[0] === 'string';
  if (isDay) {
    for (const s of calendar) {
      const ms = easternDayMs(s);
      if (ms != null) out.push({ start: ms, end: ms, nested: false });
    }
  } else {
    for (const entry of calendar) {
      // NFL/UFL nest weeks and soccer nests competition phases under `entries`;
      // golf/F1/MMA are one event per (flat) entry. The nested children are
      // season buckets, NOT individual game days.
      const nested = Array.isArray(entry.entries) && entry.entries.length > 0;
      const kids = nested ? entry.entries : [entry];
      for (const k of kids) {
        if (!k || !k.startDate) continue;
        const start = easternDayMs(k.startDate);
        if (start == null) continue;
        // Pull the end back 1s so an end stamped at ET-midnight doesn't bleed
        // into the following day.
        const end = k.endDate ? easternDayMs(new Date(new Date(k.endDate).getTime() - 1000)) : start;
        out.push({ start, end: Math.max(end ?? start, start), nested });
      }
    }
  }
  return out.sort((a, b) => a.start - b.start);
}

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
