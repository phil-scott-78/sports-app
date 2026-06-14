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

// Collapse a league's calendar into sorted [startDay, endDay] ranges (ET days).
function rangesFromCalendar(calendarType, calendar) {
  const out = [];
  if (!Array.isArray(calendar) || !calendar.length) return out;
  const isDay = calendarType === 'day' || typeof calendar[0] === 'string';
  if (isDay) {
    for (const s of calendar) {
      const ms = easternDayMs(s);
      if (ms != null) out.push([ms, ms]);
    }
  } else {
    for (const entry of calendar) {
      // NFL nests weeks under `entries`; everyone else is one event per entry.
      const kids = Array.isArray(entry.entries) && entry.entries.length ? entry.entries : [entry];
      for (const k of kids) {
        if (!k || !k.startDate) continue;
        const start = easternDayMs(k.startDate);
        if (start == null) continue;
        // Pull the end back 1s so an end stamped at ET-midnight doesn't bleed
        // into the following day.
        const end = k.endDate ? easternDayMs(new Date(new Date(k.endDate).getTime() - 1000)) : start;
        out.push([start, Math.max(end ?? start, start)]);
      }
    }
  }
  return out.sort((a, b) => a[0] - b[0]);
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

  const todayEvents = events.filter((e) => easternDayMs(e.date) === today);
  const liveToday = todayEvents.some((e) => e?.competitions?.[0]?.status?.type?.state === 'in');
  const hasToday = ranges.some(([s, en]) => today >= s && today <= en) || todayEvents.length > 0;

  let next = null;
  let prev = null;
  for (const [s, en] of ranges) {
    if (s > today) next = next == null ? s : Math.min(next, s);
    if (en < today) prev = prev == null ? en : Math.max(prev, en);
  }

  const season = lg.season || {};
  const sStart = season.startDate ? easternDayMs(season.startDate) : (ranges.length ? ranges[0][0] : null);
  const sEnd = season.endDate ? easternDayMs(season.endDate) : (ranges.length ? ranges[ranges.length - 1][1] : null);
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
