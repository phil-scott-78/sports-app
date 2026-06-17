// calendar.js — the season skeleton ESPN ships inside every scoreboard's
// leagues[0]. Pure (no I/O) so it runs identically in Node tests and the Worker,
// and it is the SINGLE home for reading ESPN's calendar (overview.js's
// season-pulse classifier and normalize.js's scores passthrough both import it —
// the "interpret a league's calendar" rule must never fork).
//
// Two shapes by `calendarType`:
//   "day"  → calendar is an ISO date[] (one entry per GAME DAY): NBA/NHL/MLB and
//            soccer leagues. This IS the authoritative "which days have games"
//            list — exactly what the league-detail Schedule strip needs.
//   "list" → calendar is an object[] of season-type buckets / events with
//            [startDate,endDate] ranges (NFL nests weeks under `entries`;
//            golf/F1/MMA list one event per entry). NOT per-day game presence.

// US-Eastern calendar day as a UTC-midnight stamp, matching ESPN's bucketing (and
// the app's "today"). Intl resolves EST/EDT automatically. Null if unparsable.
export function easternDayMs(input) {
  const d = input instanceof Date ? input : new Date(input);
  if (Number.isNaN(d.getTime())) return null;
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: 'America/New_York', year: 'numeric', month: '2-digit', day: '2-digit',
  }).formatToParts(d);
  const g = (t) => Number(parts.find((p) => p.type === t).value);
  return Date.UTC(g('year'), g('month') - 1, g('day'));
}

// Collapse a league's calendar into sorted ranges (ET days), each tagged with
// whether it came from a NESTED season bucket (a week/phase under `entries`) vs a
// flat top-level entry (a single event). Shape: { start, end, nested }.
export function rangesFromCalendar(calendarType, calendar) {
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

// 'YYYYMMDD' for an ET-day stamp (the app's date-param + day-key format).
const pad = (n) => (n < 10 ? '0' : '') + n;
export const ymd = (ms) => {
  const d = new Date(ms);
  return `${d.getUTCFullYear()}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}`;
};

// The on-the-scores-payload calendar: a precise game-day list for "day"-type
// leagues (drives the Schedule strip's empty-day dimming + auto-focus WITHOUT a
// separate range fetch — the data already rides the scoreboard we fetched), plus
// the season window for the offseason-opener jump. Returns {} when absent.
// "list"-type (gridiron/golf/F1/MMA) is deliberately omitted: its ranges are
// week/season buckets, not per-day game presence, so the app keeps its
// event-derived strip there (and gridiron games already carry weekLabel).
export function buildCalendar(lg) {
  const out = {};
  const cal = lg && lg.calendar;
  const isDay = lg && (lg.calendarType === 'day' || (Array.isArray(cal) && typeof cal[0] === 'string'));
  if (isDay && Array.isArray(cal) && cal.length) {
    const set = new Set();
    for (const s of cal) {
      const ms = easternDayMs(s);
      if (ms != null) set.add(ymd(ms));
    }
    if (set.size) out.calendarDays = [...set].sort();
  }
  const season = (lg && lg.season) || {};
  const win = {};
  if (season.startDate) win.startDate = season.startDate;
  if (season.endDate) win.endDate = season.endDate;
  if (win.startDate || win.endDate) out.seasonWindow = win;
  return out;
}
