// ttl.js — cache-lifetime policy for the Worker's routes. Pure (no I/O) so it
// runs identically in Node tests and the Worker. ONE place to answer "how
// aggressive is the cache", and the home of the kickoff-aware idle TTL.
//
// The trap it solves: a route picks its TTL from the payload it just fetched, so
// BEFORE kickoff a game reads 'scheduled' → we'd cache that "not started"
// snapshot for the full idle window and NOT look upstream again until it
// expires. The tight live TTL can't rescue us — it only engages once we've
// already SEEN a live game (chicken-and-egg). So when a scheduled game is within
// one idle window of kickoff — or just started and ESPN hasn't flipped it to
// 'in' yet — we drop to a short TTL and poll the idle→live flip in.

export const TTL = {
  scoresLive: 15,     // a game is live → tight refresh
  summaryLive: 20,    // box scores tick slower than the score
  idle: 300,          // nothing live, no kickoff imminent → 5m
  soon: 30,           // a scheduled game is near kickoff → poll the flip in
  overview: 300,      // coarse season pulse (heavy fan-out) → 5m
  overviewActive: 60, // …unless a league is live or has a game today
  scorecard: 60,      // golf hole-by-hole: on-demand per player tap; a live round
                      // adds a hole ~every 15 min, so 60s is already generous and
                      // the payload has no live flag to key a tighter tier off
  pastDay: 21600,     // a fully-past dated slate is immutable → 6h. Not infinite:
                      // SWR + late stat corrections (final H/E, an overturned call)
                      // argue for a bound; 6h keeps the shared refresh nearly free.
  teamDetail: 1800,   // team page (schedule/roster/stats/standing) — slow-moving,
                      // 4 subrequests coalesced behind one 30m fetch
};

// Idle-path TTL for scores/summary. Short when a scheduled kickoff falls within
// one idle window on EITHER side of `now` — the +side is "approaching", the
// −side is "started but ESPN still says pre" — otherwise the full idle TTL.
// `nextStartMs` is the soonest scheduled kickoff (epoch ms), or null/undefined
// when nothing is scheduled.
export function idleTtl(nextStartMs, now) {
  if (nextStartMs != null) {
    const dt = nextStartMs - now;
    if (dt <= TTL.idle * 1000 && dt >= -TTL.idle * 1000) return TTL.soon;
  }
  return TTL.idle;
}

// Today, ET-bucketed, as 'YYYYMMDD' — the same calendar ESPN's ?date= speaks and
// the mock synthesizer uses. `en-CA` yields 'YYYY-MM-DD'; strip the dashes.
function etYmd(now) {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/New_York', year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(new Date(now)).replace(/-/g, '');
}

// Long TTL for an IMMUTABLE past dated slate (the date-strip's "look back a day"
// path). `dateParam` is the client's ?date= — a single 'YYYYMMDD' or a
// 'YYYYMMDD-YYYYMMDD' range; we take the range END (the newest day requested).
// Returns TTL.pastDay only when that day is STRICTLY before ET-today AND nothing
// in the slate is live (a suspended game keeps the normal cadence). Else null →
// the caller falls back to idleTtl. Zero-padded 'YYYYMMDD' compares lexically.
export function pastDatedTtl(dateParam, anyLive, now) {
  if (!dateParam || anyLive) return null;
  const end = String(dateParam).split('-').pop();
  if (!/^\d{8}$/.test(end)) return null;
  return end < etYmd(now) ? TTL.pastDay : null;
}
