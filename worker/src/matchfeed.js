// matchfeed.js — raw CORE plays feed → canonical MatchFeed (see canonical.ts).
// SOCCER ONLY (capability hasMatchFeed). Pure function; no I/O.
//
// The core resource: /v2/sports/soccer/leagues/{lg}/events/{id}/competitions/{id}/plays
// VERIFIED 2026-07 (fifa.world, live): touch-by-touch — every pass, tackle,
// throw-in — each play carrying TEAM-RELATIVE pitch coordinates (fieldPositionX
// 0 = own goal line, 100 = opponent goal line; fieldPositionY 0..100 across),
// with passes/shots also carrying fieldPosition2X/Y (where the ball ended up).
// Participants are $refs only (no names) — athleteId is parsed from the ref and
// joined against the summary lineups downstream; shortText ('W. Saliba Pass')
// is the self-contained fallback label. Paginated ~25/page by default, ?limit
// honored to ≥300; APPEND-ONLY, so the caller caches full pages and merges.
//
// This deliberately is NOT the narrative feed (that's summary commentary[]) —
// it exists for the live-pitch view (pass trail, possession, restarts), the
// shot map (start→end trajectories) and the derived momentum chart.

const numOr = v => (typeof v === 'number' ? v : undefined);
const pick = (o, keys) => Object.fromEntries(keys.filter(k => o[k] != null && o[k] !== '').map(k => [k, o[k]]));

const teamIdFromRef = ref => {
  const m = typeof ref === 'string' ? ref.match(/\/teams\/(\d+)/) : null;
  return m ? m[1] : undefined;
};
const athleteIdFromRef = ref => {
  const m = typeof ref === 'string' ? ref.match(/\/athletes\/(\d+)/) : null;
  return m ? m[1] : undefined;
};

// raw = the merged core plays doc {count, items[]} (caller merges pages, in
// page order — ESPN pages oldest-first so the merge is chronological).
// homeId/awayId = the competition's team ids (from the scoreboard/summary
// header) — core plays tag their team as a $ref, resolved to a side here.
export function normalizeMatchFeed(raw, homeId, awayId) {
  const items = Array.isArray(raw?.items) ? raw.items : [];
  const home = homeId != null ? String(homeId) : '';
  const away = awayId != null ? String(awayId) : '';
  const plays = [];
  for (const p of items) {
    if (!p || p.valid === false) continue;
    const type = p.type?.text;
    if (!type) continue;
    const tid = teamIdFromRef(p.team?.$ref);
    const side = tid && tid === home ? 'home' : tid && tid === away ? 'away' : undefined;
    plays.push(pick({
      id: p.id != null ? String(p.id) : undefined,
      type,
      period: numOr(p.period?.number),
      clock: p.clock?.displayValue,
      sec: numOr(p.clock?.value),
      side,
      athleteId: athleteIdFromRef(p.participants?.[0]?.athlete?.$ref),
      shortText: p.shortText,
      text: p.text,
      x: numOr(p.fieldPositionX),
      y: numOr(p.fieldPositionY),
      x2: numOr(p.fieldPosition2X),
      y2: numOr(p.fieldPosition2Y),
      scoring: p.scoringPlay === true ? true : undefined,
    }, ['id', 'type', 'period', 'clock', 'sec', 'side', 'athleteId', 'shortText', 'text', 'x', 'y', 'x2', 'y2', 'scoring']));
  }
  return { count: typeof raw?.count === 'number' ? raw.count : plays.length, plays };
}
