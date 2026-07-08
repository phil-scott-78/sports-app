// synth.mjs — the offline mock's "schedule projector". Pure (no I/O): given a
// captured pool of REAL raw ESPN events (see scripts/capture-fixtures.mjs) plus a
// reference instant, it emits a raw ESPN-shaped scoreboard anchored to "now" with
// games in every phase — final + live + scheduled — so the app renders every UI
// permutation without depending on the real-world calendar. The mock server then
// runs the SAME pure normalizers the production worker uses (normalize.js etc.).
//
// Design rules:
//   - Deterministic on EVENT ID, never on `now`: scores/winners/linescores are
//     hashed from the id so polling (every 15s) never makes a frozen game flicker.
//     Only the dates follow `now`, so relative-time + Yesterday/Today/Upcoming
//     bucketing always read as current.
//   - Convert between ANY phases. A capture taken at night is all finals; an
//     off-season capture is all scheduled. Both must yield a full 3-state slate,
//     so every transform fabricates the score data its target phase needs.
//   - Branch on the resolved profile's discriminators (layout/scoreKind/periodUnit),
//     never on sport name — same contract the renderers obey.

import { resolve } from '../../schema/tools/resolve.mjs';

const DAY = 86400000, HOUR = 3600000, MIN = 60000;

// ---- deterministic PRNG (seeded by a string; no Date/Math.random dependence) --
function hashStr(s) {
  let h = 2166136261;
  for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); }
  return h >>> 0;
}
function mulberry(seed) {
  let a = seed >>> 0;
  return () => { a = (a + 0x6D2B79F5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}
const randInt = (seedStr, lo, hi) => lo + Math.floor(mulberry(hashStr(seedStr))() * (hi - lo + 1));

// ---- time helpers -----------------------------------------------------------
const iso = (ms) => new Date(ms).toISOString().replace('.000Z', 'Z');
// US-Eastern Y-M-D (matches ESPN's "sports day" bucketing + the app's `today`).
function etParts(ms) {
  const p = new Intl.DateTimeFormat('en-US', { timeZone: 'America/New_York', year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(new Date(ms));
  const g = (t) => Number(p.find((x) => x.type === t).value);
  return { y: g('year'), m: g('month'), d: g('day') };
}
const etDayDash = (ms) => { const { y, m, d } = etParts(ms); return `${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`; };
const etDayMs = (ms) => Date.parse(etDayDash(ms) + 'T00:00:00Z');
const ymdDash = (ymd) => `${ymd.slice(0, 4)}-${ymd.slice(4, 6)}-${ymd.slice(6, 8)}`; // 'YYYYMMDD' → 'YYYY-MM-DD'
function ymdToMs(ymd) { // 'YYYYMMDD' → that ET day's UTC-midnight stamp (approx)
  const m = /^(\d{4})(\d{2})(\d{2})$/.exec(ymd);
  return m ? Date.parse(`${m[1]}-${m[2]}-${m[3]}T00:00:00Z`) : null;
}

// human kickoff labels for a scheduled game (mirrors ESPN's status detail strings)
const MO = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
function kickShort(ms) {
  const p = new Intl.DateTimeFormat('en-US', { timeZone: 'America/New_York', month: 'numeric', day: 'numeric', hour: 'numeric', minute: '2-digit', hour12: true }).formatToParts(new Date(ms));
  const g = (t) => p.find((x) => x.type === t)?.value;
  return `${g('month')}/${g('day')} - ${g('hour')}:${g('minute')} ${g('dayPeriod')} ET`;
}

const ordinal = (n) => { const s = ['th', 'st', 'nd', 'rd'], v = n % 100; return `${n}${s[(v - 20) % 10] || s[v] || s[0]}`; };
const clone = (o) => JSON.parse(JSON.stringify(o));
const phaseOfRaw = (c) => { const t = c?.status?.type || {}; const st = t.state; if (st === 'in') return 'live'; if (st === 'post' || t.completed) return 'final'; if (st === 'pre') return 'scheduled'; return 'scheduled'; };

// ---- live label/clock per period unit (the only sport-flavored bit) ----------
// Returns { detail, shortDetail, clock, period } for an in-progress competition.
function liveLabels(profile, P) {
  const u = profile.periodUnit, sport = profile.espnSport;
  switch (u) {
    case 'inning': { const s = `Top ${ordinal(P)}`; return { detail: s, shortDetail: s, period: P }; }
    case 'quarter': { const clk = '6:24'; const s = `${clk} - ${ordinal(P)}`; return { detail: s, shortDetail: s, clock: clk, period: P }; }
    case 'period': { const clk = '8:42'; const s = `${clk} - ${ordinal(P)}`; return { detail: s, shortDetail: s, clock: clk, period: P }; }
    case 'half': {
      if (profile.clockDirection === 'down') { const clk = '8:42'; const s = `${clk} - ${ordinal(P)} Half`; return { detail: s, shortDetail: s, clock: clk, period: P }; }
      const min = (P - 1) * (profile.periodLengthMin || 45) + 18; const s = `${min}'`; // soccer/rugby count up
      return { detail: s, shortDetail: s, clock: s, period: P };
    }
    case 'round': { const clk = '2:30'; const s = `Round ${P}`; return { detail: s, shortDetail: s, clock: clk, period: P }; }
    case 'set': { const s = `Set ${P}`; return { detail: s, shortDetail: s, period: P }; }
    case 'lap': { const s = `Lap ${P}`; return { detail: s, shortDetail: s, period: P }; }
    case 'hole_rounds': { const s = `Round ${P}`; return { detail: s, shortDetail: s, period: P }; }
    case 'over_innings': { const s = 'In Progress'; return { detail: s, shortDetail: s, period: P }; }
    default: { const s = 'In Progress'; return { detail: s, shortDetail: s, period: P }; }
  }
}
// the mid-game period to freeze a live game at (a representative ~60%-through point)
const livePeriod = (profile) => Math.max(1, Math.ceil((profile.regulationPeriods || 1) * 0.6));
const finalDetail = (profile) => (profile.espnSport === 'soccer' ? 'FT' : 'Final');
const finalName = (profile) => (profile.espnSport === 'soccer' ? 'STATUS_FULL_TIME' : 'STATUS_FINAL');

// typical points scored in one period, for fabricating a slate the capture lacked
function perPeriodRange(profile) {
  switch (profile.periodUnit) {
    case 'quarter': return profile.espnSport === 'basketball' ? [14, 32] : [0, 14];
    case 'half': return profile.espnSport === 'basketball' ? [28, 44] : [0, 3];
    case 'period': return [0, 3];
    case 'inning': return [0, 3];
    default: return [0, 3];
  }
}

// ---- competitor-level score shaping -----------------------------------------
const numScore = (c) => { const v = parseInt(typeof c.score === 'object' ? (c.score?.displayValue ?? c.score?.value) : c.score, 10); return Number.isFinite(v) ? v : null; };

// Ensure a numeric competitor has linescores covering periods 1..P and a matching
// total. Truncates when the source has more (final→live), fabricates when it has
// none (scheduled→anything). No-op for non-numeric kinds (golf/cricket/racing/mma).
function shapeNumeric(comp, profile, eventId, P) {
  if (profile.scoreKind !== 'numeric') return;
  for (let i = 0; i < comp.competitors.length; i++) {
    const c = comp.competitors[i];
    const side = c.homeAway || `c${i}`;
    if (profile.hasLineScores) {
      let ls = Array.isArray(c.linescores) ? c.linescores.filter((x) => (x?.period ?? 0) <= P) : [];
      if (!ls.length) { // fabricate (the capture had no per-period data, e.g. a scheduled source)
        const [lo, hi] = perPeriodRange(profile);
        ls = Array.from({ length: P }, (_, k) => { const v = randInt(`${eventId}:${side}:${k + 1}`, lo, hi); return { value: v, displayValue: String(v), period: k + 1 }; });
      }
      c.linescores = ls;
      c.score = String(ls.reduce((s, x) => s + (Number(x.value) || 0), 0));
    } else { // no per-period array (soccer): just a running total
      let total = numScore(c);
      if (total == null) total = randInt(`${eventId}:${side}:tot`, 0, 3);
      c.score = String(total);
    }
  }
}

// Golf live shaping: the captured leaderboard is a FINISHED tournament (every
// competitor THRU F on the final round). Re-project it to a mid-round `now` —
// keep the completed rounds, drop rounds past the current one, and trim the
// current round to a varying THRU so the leaderboard reads genuinely live (§8.4).
function shapeGolfLive(comp, eventId, currentRound) {
  for (const c of comp.competitors || []) {
    if (!Array.isArray(c.linescores) || !c.linescores.length) continue;
    const kept = c.linescores.filter((ls) => (ls.period ?? 0) <= currentRound);
    const cur = kept.find((ls) => (ls.period ?? 0) === currentRound);
    if (cur && Array.isArray(cur.linescores) && cur.linescores.length) {
      const thru = 1 + (hashStr(`${eventId}:${c.id}:thru`) % 17); // 1..17 holes (mid-round)
      cur.linescores = cur.linescores.slice(0, thru);
    }
    c.linescores = kept;
  }
}

function setWinners(comp, profile) {
  if (profile.layout !== 'headToHead' || comp.competitors.length !== 2) return;
  if (profile.scoreKind !== 'numeric') return; // golf=order, mma=captured winner, racing=order
  let [a, b] = comp.competitors.map(numScore);
  if (a == null || b == null) return;
  const drawsOk = profile.espnSport === 'soccer' || profile.espnSport === 'rugby' || profile.espnSport === 'rugby-league';
  if (a === b && !drawsOk) { // nudge off a tie where ties aren't a real result
    comp.competitors[0].score = String(a + 1); a += 1;
  }
  comp.competitors[0].winner = a > b;
  comp.competitors[1].winner = b > a;
}

// ---- phase transforms (mutate a cloned competition in place) -----------------
function makeScheduled(comp, profile, startMs) {
  comp.date = iso(startMs);
  comp.status = { type: { id: '1', name: 'STATUS_SCHEDULED', state: 'pre', completed: false, description: 'Scheduled', detail: kickShort(startMs), shortDetail: kickShort(startMs) }, period: 0, displayClock: '0:00' };
  delete comp.situation;
  for (const c of comp.competitors) {
    delete c.linescores; delete c.winner; delete c.shootoutScore; delete c.aggregateScore;
    if (profile.scoreKind === 'numeric') c.score = '0'; else delete c.score;
  }
}

function makeLive(comp, profile, eventId, startMs) {
  comp.date = iso(startMs);
  const P = livePeriod(profile);
  shapeNumeric(comp, profile, eventId, P);
  if (profile.periodUnit === 'hole_rounds') shapeGolfLive(comp, eventId, P); // §8.4
  for (const c of comp.competitors) { delete c.winner; }
  const L = liveLabels(profile, P);
  comp.status = { type: { id: '2', name: 'STATUS_IN_PROGRESS', state: 'in', completed: false, description: 'In Progress', detail: L.detail, shortDetail: L.shortDetail }, period: L.period, displayClock: L.clock || '0:00' };
  injectSituation(comp, profile, eventId); // baseball count / gridiron down&distance, when live
}

function makeFinal(comp, profile, eventId, startMs, srcPhase) {
  comp.date = iso(startMs);
  const reg = profile.regulationPeriods || 0;
  if (srcPhase !== 'final') { // fabricate a result the capture didn't have; keep authentic finals intact
    shapeNumeric(comp, profile, eventId, reg || 99);
    setWinners(comp, profile);
  }
  delete comp.situation;
  const played = profile.scoreKind === 'numeric' && profile.hasLineScores
    ? Math.max(reg, ...comp.competitors.map((c) => (c.linescores?.length || 0)))
    : (comp.status?.period || reg || 1);
  comp.status = { type: { id: '3', name: finalName(profile), state: 'post', completed: true, description: 'Final', detail: finalDetail(profile), shortDetail: finalDetail(profile) }, period: played, displayClock: '0:00' };
}

// A small live "what's happening now" strip for the sports whose card shows one.
function injectSituation(comp, profile, eventId) {
  if (profile.espnSport === 'baseball') {
    const r = mulberry(hashStr(eventId + ':sit'));
    const outs = Math.floor(r() * 3);
    const plays = ['Ball', 'Strike looking', 'Foul', 'Single to left', 'Groundout to short', 'Walk'];
    comp.situation = {
      balls: Math.floor(r() * 4), strikes: Math.floor(r() * 3), outs,
      onFirst: r() > 0.5, onSecond: r() > 0.6, onThird: r() > 0.8,
      // ESPN ships lastPlay as an OBJECT (buildSituation reads lp.type?.text / lp.text),
      // NOT a bare string — match the raw shape so the real normalizer surfaces it.
      lastPlay: { text: plays[Math.floor(r() * plays.length)] },
    };
    comp.outsText = `${outs} Out${outs === 1 ? '' : 's'}`; // QUIRK: outsText lives on the competition, not situation
  } else if (profile.espnSport === 'football') {
    const r = mulberry(hashStr(eventId + ':gsit'));
    const down = 1 + Math.floor(r() * 4);   // 1..4
    const dist = 1 + Math.floor(r() * 12);  // 1..12
    const comps = comp.competitors || [];
    const poss = comps.length ? comps[r() < 0.5 ? 0 : comps.length - 1] : null;
    // possession must match the competitor's canonical id (normalize.js buildCompetitor:
    // id = raw.id ?? team.id); the field bar (situations.dart fieldPosition) parses the
    // "at ABBR yard" spot — so the drive graphic + LAST PLAY render, not just the
    // down&distance headline (§8.3 unblocks the §5a CFB Now).
    const possId = poss ? String(poss.id ?? poss.team?.id ?? '') : '';
    const abbr = poss?.team?.abbreviation || poss?.abbreviation;
    const yard = 20 + Math.floor(r() * 25); // a plausible mid-drive spot in own territory
    const spot = abbr ? ` at ${abbr} ${yard}` : '';
    const lastPlays = ['Run up the middle for 4 yards', 'Pass complete for a first down',
      'Incomplete pass down the sideline', 'Sacked for a loss of 6', 'Scramble for 9 yards', 'Screen pass for 5'];
    comp.situation = {
      down, distance: dist,
      downDistanceText: `${ordinal(down)} & ${dist}${spot}`,
      ...(possId ? { possession: possId } : {}),
      isRedZone: false,
      homeTimeouts: 1 + Math.floor(r() * 3),
      awayTimeouts: 1 + Math.floor(r() * 3),
      lastPlay: { text: lastPlays[Math.floor(r() * lastPlays.length)] },
    };
  }
}

// ---- CORE detail-open resources (situation / predictor / last-play text) ------
// The app fetches these on detail open (piggybacking the summary poll) for live
// gridiron/basketball/hockey. Real ESPN serves them on the core graph; the mock
// fabricates a deterministic-by-event-id shape so the CFB/NBA/NHL detail states are
// walkable offline through the SAME code path (mock-espn-server injects the
// lastPlay.$ref back at itself). Pure — no lastPlay ref here (the server adds it).
export function synthCoreSituation(profile, eventId) {
  const sport = profile.espnSport;
  const r = mulberry(hashStr(eventId + ':core-sit'));
  if (sport === 'football') {
    return {
      down: 1 + Math.floor(r() * 4),      // 1..4
      distance: 1 + Math.floor(r() * 12), // 1..12
      yardLine: 1 + Math.floor(r() * 99), // ESPN's raw absolute spot
      isRedZone: r() > 0.7,
      homeTimeouts: Math.floor(r() * 4),   // gridiron: a bare number
      awayTimeouts: Math.floor(r() * 4),
    };
  }
  if (sport === 'basketball') {
    const states = ['NONE', 'NONE', 'ONE', 'DOUBLE'];
    const fouls = () => ({
      bonusState: states[Math.floor(r() * states.length)],
      teamFouls: Math.floor(r() * 9),
      teamFoulsCurrent: Math.floor(r() * 8),
      foulsToGive: Math.floor(r() * 3),
    });
    // basketball: timeouts are an OBJECT with timeoutsRemainingCurrent (VERIFIED).
    const to = () => ({ timeoutsRemainingCurrent: Math.floor(r() * 7), timeoutsCurrent: 0 });
    return { homeFouls: fouls(), awayFouls: fouls(), homeTimeouts: to(), awayTimeouts: to() };
  }
  if (sport === 'hockey') {
    return { powerPlay: r() > 0.5, emptyNet: r() > 0.9 };
  }
  return {};
}

// Per-side gameProjection win % (sums to 100), the predictor shape the app's
// winProbabilityFromPredictor reads. Deterministic by event id.
export function synthCorePredictor(eventId) {
  const r = mulberry(hashStr(eventId + ':core-pred'));
  const home = 20 + Math.floor(r() * 60); // 20..79
  const stat = (v) => [{ name: 'gameProjection', displayName: 'WIN PROB', value: v, displayValue: String(v) }];
  return { homeTeam: { statistics: stat(home) }, awayTeam: { statistics: stat(100 - home) } };
}

// The text behind situation.lastPlay.$ref (the mock coreplay route resolves to this).
export function synthCorePlayText(eventId, sport) {
  const byS = {
    football: ['Run up the middle for 4 yards', 'Pass complete for a first down', 'Sacked for a loss of 6', 'Screen pass for a gain of 5'],
    basketball: ['Pull-up jumper good', 'Driving layup and the foul', 'Steal leads to a fast-break dunk', 'Corner three splashes'],
    hockey: ['Wrist shot turned aside, rebound cleared', 'Slap shot rings off the post', 'Faceoff won in the offensive zone', 'Shorthanded chance denied'],
  };
  const arr = byS[sport] || ['Play under review'];
  return arr[hashStr(eventId + ':coreplay') % arr.length];
}

// Apply a phase to a whole event. Multi-competition events (MMA cards, F1
// weekends) get a realistic progression when the event is the live centrepiece:
// early bouts done, one in progress, the rest upcoming.
function applyRole(ev, role, profile, startMs, eventId) {
  // tennis nests matches under groupings[].competitions[] (see buildEvent); flatten
  // so both applyRole and the downstream normalizer read events[].competitions[].
  if (!Array.isArray(ev.competitions) || !ev.competitions.length) {
    ev.competitions = (ev.groupings || []).flatMap((g) => g.competitions || []);
    delete ev.groupings;
  }
  const comps = ev.competitions;
  if (!comps.length) return;
  for (const c of comps) if (!Array.isArray(c.competitors)) c.competitors = []; // a future field event has no leaderboard yet
  if (comps.length > 1 && role === 'live') {
    const liveIdx = Math.floor(comps.length / 2);
    comps.forEach((c, i) => {
      const id = `${eventId}:${i}`;
      if (i < liveIdx) makeFinal(c, profile, id, startMs - HOUR, phaseOfRaw(c));
      else if (i === liveIdx) makeLive(c, profile, id, startMs);
      else makeScheduled(c, profile, startMs + (i - liveIdx) * 20 * MIN);
    });
    return;
  }
  for (let i = 0; i < comps.length; i++) {
    const id = comps.length > 1 ? `${eventId}:${i}` : eventId;
    if (role === 'scheduled') makeScheduled(comps[i], profile, startMs);
    else if (role === 'live') makeLive(comps[i], profile, id, startMs);
    else makeFinal(comps[i], profile, id, startMs, phaseOfRaw(comps[i]));
  }
}

// ---- slate composition ------------------------------------------------------
// Spread N start times across a window, deterministically by index.
const slotStart = (role, k, now) => {
  if (role === 'final') return now - (1.5 * HOUR + (k % 6) * 70 * MIN);   // earlier today
  if (role === 'live') return now - (35 * MIN + (k % 3) * 18 * MIN);      // in progress
  return now + (55 * MIN + (k % 8) * 80 * MIN);                            // later today / tonight
};
const dayStart = (dayMs, role, k) => dayMs + (13 * HOUR + (k % 8) * 70 * MIN); // a past/future day's slate

// roles for a today slate: guarantee ≥1 of each, lean toward a lively mix.
function mixedRoles(n) {
  const base = ['live', 'final', 'scheduled', 'final', 'scheduled', 'final', 'live', 'scheduled', 'final', 'scheduled'];
  const r = Array.from({ length: n }, (_, i) => base[i % base.length]);
  if (n >= 3) { r[0] = 'live'; r[1] = 'final'; r[2] = 'scheduled'; }
  return r;
}

// Ensure at least `min` events so a thin pool (or a single golf tournament) can
// still show all three states — clones with fresh ids when short.
function ensurePool(pool, min) {
  if (pool.length >= min || !pool.length) return pool.slice();
  const out = pool.slice();
  for (let k = 0; out.length < min; k++) {
    const src = clone(pool[k % pool.length]);
    src.id = `${src.id}-c${k}`;
    if (Array.isArray(src.competitions)) for (const c of src.competitions) c.id = src.id;
    out.push(src);
  }
  return out;
}

function fabricateFromTeams(fixture, profile, count) {
  const teams = (fixture.teams?.sports?.[0]?.leagues?.[0]?.teams || []).map((t) => t.team).filter(Boolean);
  if (teams.length < 2) return [];
  const out = [];
  for (let i = 0; i + 1 < teams.length && out.length < count; i += 2) {
    const home = teams[i], away = teams[i + 1];
    const mk = (t, ha, order) => ({ id: String(t.id), homeAway: ha, order, team: t, score: '0' });
    out.push({
      id: `mock-${profile.espnSport}-${out.length}`,
      date: iso(Date.now()),
      name: `${away.displayName} at ${home.displayName}`,
      shortName: `${away.abbreviation || ''} @ ${home.abbreviation || ''}`,
      competitions: [{ id: `mock-${profile.espnSport}-${out.length}`, competitors: [mk(home, 'home', 0), mk(away, 'away', 1)] }],
    });
  }
  return out;
}

// the synthetic leagues[0] header — current season window so /overview classifies
// the league as live/today rather than off-season.
function synthLeague(fixture, profile, key, now) {
  const sk = fixture.league || {};
  const y = new Date(now).getUTCFullYear();
  return {
    id: String(sk.id ?? fixture.stats?.id ?? profile.espnLeagueId ?? ''),
    uid: sk.uid, name: sk.name || profile.name || key, abbreviation: sk.abbreviation || profile.abbr,
    slug: sk.slug || key.split('/')[1],
    season: { year: y, type: 2, slug: 'regular-season', displayName: String(y), startDate: iso(now - 150 * DAY), endDate: iso(now + 150 * DAY) },
    calendarType: 'day',
    calendar: [iso(now - DAY), iso(now), iso(now + DAY)],
  };
}

/**
 * Build a raw ESPN-shaped scoreboard for a league at `now`, for an optional date
 * spec ('YYYYMMDD' or 'YYYYMMDD-YYYYMMDD'). null/today → a full final+live+scheduled
 * mix; a past day → finals; a future day → scheduled; a range → spread across it.
 */
export function synthScoreboard(registry, key, fixture, { now = Date.now(), date = null, scenario = null } = {}) {
  const profile = resolve(registry, key);
  let pool = (fixture.events && fixture.events.length) ? fixture.events : fabricateFromTeams(fixture, profile, 6);

  const out = { leagues: [synthLeague(fixture, profile, key, now)], events: [] };

  // date range (schedule strip): scatter events across the span, state by day vs now.
  const range = typeof date === 'string' && date.includes('-') ? date.split('-') : null;
  if (range) {
    const [s, e] = range.map(ymdToMs);
    if (s != null && e != null) {
      const today = etDayMs(now);
      const days = Math.max(1, Math.round((e - s) / DAY) + 1);
      pool = ensurePool(pool, Math.max(scenario ? scenario.minPool : 0, Math.min(days, 12)));
      const heroDays = new Set(); // scenario: at most one championship hero per day
      pool.forEach((src, i) => {
        const dayMs = s + (i % days) * DAY;
        const role = etDayMs(dayMs) < today ? 'final' : etDayMs(dayMs) > today ? 'scheduled' : 'live';
        const ev = clone(src);
        applyRole(ev, role, profile, dayStart(dayMs, role, i), String(ev.id));
        if (!ev.competitions?.[0]) return;
        ev.date = ev.competitions[0].date;
        if (scenario) {
          const dayOffset = Math.round((etDayMs(dayMs) - today) / DAY);
          scenario.frame(ev, { role, profile, key, dayOffset, firstOfDay: !heroDays.has(dayOffset) });
          if (role === 'scheduled') heroDays.add(dayOffset);
        }
        out.events.push(ev);
      });
      out.day = { date: ymdDash(range[0]) };
      return out;
    }
  }

  const today = etDayMs(now);
  // targetDay + today are both "UTC-midnight of an ET day" stamps → compare directly.
  const targetDay = date ? (ymdToMs(date) ?? today) : today;
  const cmp = targetDay - today;
  const dayOffset = Math.round(cmp / DAY); // whole-day delta a scenario reasons in

  let roles;
  if (scenario) { pool = ensurePool(pool, scenario.minPool); roles = scenario.roles(profile, key, dayOffset, pool.length); }
  else if (cmp === 0) { pool = ensurePool(pool, 3); roles = mixedRoles(pool.length); }
  else if (cmp < 0) roles = pool.map(() => 'final');
  else roles = pool.map(() => 'scheduled');

  const counters = { final: 0, live: 0, scheduled: 0 };
  let heroTaken = false; // scenario: at most one championship hero for this single day
  pool.forEach((src, i) => {
    const role = roles[i];
    const k = counters[role]++;
    const startMs = cmp === 0 ? slotStart(role, k, now) : dayStart(targetDay, role, i);
    const ev = clone(src);
    applyRole(ev, role, profile, startMs, String(ev.id));
    if (!ev.competitions?.[0]) return; // event with no competitions/groupings → skip
    ev.date = ev.competitions[0].date; // event date follows its (first) competition
    if (scenario) {
      scenario.frame(ev, { role, profile, key, dayOffset, firstOfDay: !heroTaken });
      if (role === 'scheduled') heroTaken = true;
    }
    out.events.push(ev);
  });
  out.day = { date: date ? ymdDash(date) : etDayDash(now) };
  return out;
}

// A borrowed summary's header still carries its CAPTURE-time date/status (often a
// months-old Final) — dropped verbatim onto a "now"-rebased slate it reads as
// stale/inconsistent (e.g. a "live" scoreboard event opening to a June Final). Patch
// just the header identity + date/status — deterministic by event id (stable across
// polls, same "never on `now` alone" rule every other synth transform follows) — and
// leave the borrowed box score/plays/rosters untouched (§8.2: the mock's job is to
// walk rich-detail rendering, not data fidelity).
function rebaseBorrowedSummary(raw, eventId, now) {
  const out = clone(raw);
  const header = out.header || (out.header = {});
  header.id = String(eventId);
  const comp = (header.competitions ||= [{}])[0] ||= {};
  comp.id = String(eventId);
  const roll = hashStr(`${eventId}:sumphase`) % 3; // 0 final · 1 live · 2 scheduled
  if (roll === 2) { // scheduled: a plausible upcoming kickoff
    const startMs = now + (30 + (hashStr(`${eventId}:sumsched`) % 300)) * MIN;
    comp.date = iso(startMs);
    comp.status = { type: { id: '1', name: 'STATUS_SCHEDULED', state: 'pre', completed: false, description: 'Scheduled', detail: kickShort(startMs), shortDetail: kickShort(startMs) }, period: 0, displayClock: '0:00' };
  } else if (roll === 1) { // live: recently started
    const startMs = now - (15 + (hashStr(`${eventId}:sumlive`) % 90)) * MIN;
    comp.date = iso(startMs);
    comp.status = { type: { id: '2', name: 'STATUS_IN_PROGRESS', state: 'in', completed: false, description: 'In Progress', detail: 'In Progress', shortDetail: 'In Progress' }, period: comp.status?.period || 1, displayClock: comp.status?.displayClock || '0:00' };
  } else { // final: earlier today
    const startMs = now - (1 + (hashStr(`${eventId}:sumfinal`) % 5)) * HOUR;
    comp.date = iso(startMs);
    comp.status = { type: { id: '3', name: 'STATUS_FINAL', state: 'post', completed: true, description: 'Final', detail: 'Final', shortDetail: 'Final' }, period: comp.status?.period || 1, displayClock: '0:00' };
  }
  return out;
}

/**
 * Raw ESPN-shaped summary for an event id. Returns the captured real summary when
 * we have one (best fidelity — real box scores), else a minimal valid envelope so
 * normalizeSummary yields empty tables and the detail page degrades to cheap-tier.
 */
export function synthSummary(fixture, eventId, { now = Date.now() } = {}) {
  const base = String(eventId).split('-c')[0].split(':')[0]; // strip clone/comp suffixes
  const raw = fixture.summaries?.[eventId] || fixture.summaries?.[base];
  if (raw) return raw;
  // No captured summary for THIS event → borrow one of the league's captured
  // summaries (deterministic by id, same calendar-proof fix as the scoreboard's own
  // pool-borrowing) so far more scoreboard events open a RICH detail offline instead
  // of the degraded empty envelope, then rebase its date/status so it doesn't read
  // stale. The borrowed box-score teams won't match the synthesized score block —
  // but the mock's job is to walk the rich-detail rendering (feeds, box tables,
  // scoring), not data fidelity.
  const captured = fixture.summaries ? Object.values(fixture.summaries) : [];
  if (captured.length) return rebaseBorrowedSummary(captured[hashStr(String(eventId)) % captured.length], eventId, now);
  return { header: { id: String(eventId), competitions: [{ id: String(eventId), competitors: [], status: { type: { state: 'post', completed: true } } }] }, boxscore: { teams: [], players: [] }, plays: [], scoringPlays: [], keyEvents: [], rosters: [] };
}

export const synthTeams = (fixture) => fixture.teams || { sports: [{ leagues: [{ teams: [] }] }] };
export const synthStandings = (fixture) => fixture.standings || {};
// Rankings ride a captured raw payload verbatim (polls/tours/divisions are
// season-stable); leagues without a capture get an empty list.
export const synthRankings = (fixture) => fixture.rankings || { rankings: [] };

// ---- golf: tournament meta + hole-by-hole scorecard ---------------------------
const baseId = (id) => String(id).split('-c')[0].split(':')[0]; // strip clone/comp suffixes

/** extras.golfTournaments for a SYNTHESIZED golf scoreboard: captured core
 * tournament JSON when the base event matches, else a fabricated one whose
 * currentRound tracks the synthesized status so the cut line reads coherently. */
export function synthGolfExtras(registry, key, fixture, sb) {
  const profile = resolve(registry, key);
  if (profile.espnSport !== 'golf' || profile.layout !== 'field') return undefined;
  const golfTournaments = {};
  const rounds = profile.regulationPeriods || 4;
  for (const ev of sb.events || []) {
    const id = String(ev.id);
    const status = ev.competitions?.[0]?.status;
    const live = status?.type?.state === 'in';
    const currentRound = Math.min(Math.max(status?.period || rounds, 1), rounds);
    const captured = fixture.tournaments?.[id] || fixture.tournaments?.[baseId(id)];
    if (captured) {
      // Align a captured (often finished R4) tournament's currentRound to the
      // synthesized live round so the pill (status.period) and GolfMeta.currentRound
      // agree; leave final/scheduled captures verbatim (§8.4).
      golfTournaments[id] = live ? { ...captured, currentRound } : captured;
      continue;
    }
    const noCut = hashStr(`${id}:cut`) % 3 === 0; // a third of events: signature/no-cut
    golfTournaments[id] = {
      displayName: ev.name, major: hashStr(`${id}:mj`) % 4 === 0,
      scoringSystem: { name: 'Medal' }, numberOfRounds: rounds,
      currentRound,
      cutRound: noCut ? 0 : 2,
      ...(noCut ? {} : { cutScore: -(hashStr(`${id}:cs`) % 4 + 1), cutCount: 65 + (hashStr(`${id}:cc`) % 15) }),
    };
  }
  return Object.keys(golfTournaments).length ? { golfTournaments } : undefined;
}

/** Raw playersummary-shaped payload: captured when present, else fabricated
 * deterministically (rounds 1..N-2 complete, N-1 in progress, N tee-time-only)
 * so EVERY leaderboard row opens a walkable scorecard offline. */
export function synthGolfScorecard(registry, key, fixture, eventId, playerId, { now = Date.now() } = {}) {
  const captured = fixture.scorecards?.[`${baseId(eventId)}/${playerId}`];
  if (captured) return captured;
  const profile = resolve(registry, key);
  const rounds = profile.regulationPeriods || 4;
  const PARS = [4, 4, 3, 5, 4, 4, 3, 4, 5, 4, 3, 4, 5, 4, 4, 3, 4, 5]; // a plausible par-72
  const name = (fixture.events || [])
    .flatMap((e) => e.competitions || [])
    .flatMap((c) => c.competitors || [])
    .find((c) => String(c.id) === String(playerId))?.athlete?.displayName || `Player ${playerId}`;
  const mkHoles = (r, count) => Array.from({ length: count }, (_, i) => {
    const par = PARS[i];
    const d = [0, 0, 0, -1, 1][hashStr(`${eventId}:${playerId}:${r}:${i}`) % 5]; // mostly pars
    const value = par + d;
    const types = { '-1': 'BIRDIE', 0: 'PAR', 1: 'BOGEY' };
    return { period: i + 1, value, displayValue: String(value), par, scoreType: { name: types[d], displayValue: d === 0 ? 'E' : d > 0 ? `+${d}` : String(d) } };
  });
  const mkRound = (r) => {
    const played = r < rounds - 1 ? 18 : r === rounds - 1 ? 12 : 0; // last round pre-start
    const holes = mkHoles(r, played);
    const strokes = holes.reduce((s, h) => s + h.value, 0);
    const toPar = holes.reduce((s, h) => s + (h.value - h.par), 0);
    return {
      period: r,
      value: strokes,
      displayValue: played ? (toPar === 0 ? 'E' : toPar > 0 ? `+${toPar}` : String(toPar)) : '-',
      ...(played >= 18 ? { outScore: holes.slice(0, 9).reduce((s, h) => s + h.value, 0), inScore: holes.slice(9).reduce((s, h) => s + h.value, 0) } : {}),
      teeTime: iso(now - (rounds - r) * DAY + 17 * HOUR),
      startTee: hashStr(`${eventId}:${playerId}:${r}:tee`) % 2 ? 1 : 10,
      groupNumber: 1 + (hashStr(`${eventId}:${playerId}:${r}:grp`) % 40),
      currentPosition: 1 + (hashStr(`${eventId}:${playerId}:pos`) % 70),
      linescores: holes,
    };
  };
  return {
    profile: { id: String(playerId), displayName: name },
    rounds: Array.from({ length: rounds }, (_, i) => mkRound(i + 1)),
    stats: [
      { name: 'scoreToPar', displayName: 'Score To Par', displayValue: String(-(hashStr(`${eventId}:${playerId}:stp`) % 15)) },
      { name: 'driveDistAvg', displayName: 'Driving Distance', displayValue: String(280 + (hashStr(`${eventId}:${playerId}:dd`) % 40)) },
    ],
  };
}

// ---- MMA: fabricated core-event + statuses + judge linescores -----------------
// The real worker builds the MMA rich tier from core resources (site /summary
// 404s for MMA). The mock fabricates the SAME core shapes from the synthesized
// scoreboard event — results deterministic per bout — and feeds them to the real
// normalizeMmaSummary, keeping the "same normalizers" guarantee.
const MMA_RESULTS = [
  { name: 'ko---punches', displayName: 'KO/TKO', shortDisplayName: 'KO' },
  { name: 'submission---rear-naked-choke', displayName: 'Submission', shortDisplayName: 'Sub' },
  { name: 'decision---unanimous', displayName: 'Decision - Unanimous', shortDisplayName: 'U Dec' },
  { name: 'decision---split', displayName: 'Decision - Split', shortDisplayName: 'S Dec' },
];
export function synthMmaCore(registry, key, fixture, eventId, { now = Date.now(), scenario = null } = {}) {
  const sb = synthScoreboard(registry, key, fixture, { now, scenario });
  const ev = (sb.events || []).find((e) => String(e.id) === String(eventId)) || (sb.events || [])[0];
  if (!ev) return { coreEvent: { id: String(eventId), competitions: [] }, statuses: {}, linescores: {} };
  const coreEvent = { id: String(ev.id), date: ev.date, competitions: [] };
  const statuses = {}, linescores = {};
  (ev.competitions || []).forEach((c, i) => {
    const boutId = String(c.id ?? `${ev.id}:${i}`);
    const competitors = (c.competitors || []).map((x) => ({ id: String(x.id) }));
    coreEvent.competitions.push({ id: boutId, competitors });
    const ph = phaseOfRaw(c);
    if (ph === 'live') { statuses[boutId] = { type: { state: 'in' }, period: c.status?.period || 2, displayClock: c.status?.displayClock || '2:30' }; return; }
    if (ph !== 'final') { statuses[boutId] = { type: { state: 'pre' } }; return; }
    const r = MMA_RESULTS[hashStr(`${boutId}:res`) % MMA_RESULTS.length];
    const decision = /decision/.test(r.name);
    statuses[boutId] = {
      type: { state: 'post', completed: true },
      result: r,
      // a decision goes the distance — round 3 (fabricated cards are 3-rounders)
      period: decision ? 3 : 1 + (hashStr(`${boutId}:rd`) % 3),
      displayClock: decision ? '5:00' : `${1 + (hashStr(`${boutId}:min`) % 4)}:${String(hashStr(`${boutId}:sec`) % 60).padStart(2, '0')}`,
    };
    if (decision && competitors.length === 2) {
      const winnerIdx = (c.competitors || []).findIndex((x) => x.winner === true);
      competitors.forEach((comp, ci) => {
        const wins = winnerIdx === -1 ? ci === 0 : ci === winnerIdx;
        const totals = [0, 1, 2].map((j) => {
          const split = /split/.test(r.name) && j === 2;
          return (wins ? (split ? 28 : 29) : (split ? 29 : 28));
        });
        linescores[`${boutId}/${comp.id}`] = { items: [{ value: totals.reduce((s, v) => s + v, 0), linescores: totals.map((v, j) => ({ value: v, order: j + 1 })) }] };
      });
    }
  });
  return { coreEvent, statuses, linescores };
}

// ---- favorite-team card slate ------------------------------------------------
const eventHasTeam = (ev, teamId) => (ev.competitions || ev.groupings?.flatMap((g) => g.competitions) || []).some((c) => (c.competitors || []).some((x) => String(x.id ?? x.team?.id) === String(teamId)));

// Make sure the (first) competition features this team — swap a competitor's
// identity to it when the source matchup didn't involve them (thin pools).
function ensureTeamPresent(ev, teamId, fixture) {
  if (eventHasTeam(ev, teamId)) return;
  const c0 = ev.competitions?.[0];
  const slot = c0?.competitors?.[0];
  if (!slot) return;
  const raw = findRawTeam(fixture, teamId);
  slot.id = String(teamId);
  if (raw) { slot.team = raw; }
}
const findRawTeam = (fx, teamId) => (fx.teams?.sports?.[0]?.leagues?.[0]?.teams || []).map((t) => t.team).find((t) => String(t?.id) === String(teamId));

/**
 * A raw scoreboard built AROUND one team, guaranteeing it has a recent final
 * (last), an upcoming game (next), and — for ~1/3 of teams, by id hash, so the
 * favorites rail shows both card layouts — a live game. Fed to the same
 * applyScoreboardFallback() the worker uses to assemble the team card.
 */
export function synthTeamScoreboard(registry, key, fixture, teamId, { now = Date.now() } = {}) {
  const profile = resolve(registry, key);
  const pool = (fixture.events && fixture.events.length) ? fixture.events : fabricateFromTeams(fixture, profile, 6);
  const mine = pool.filter((ev) => eventHasTeam(ev, teamId));
  let base = ensurePool(mine.length ? mine : pool, 3);
  const wantsLive = (hashStr(`${key}:${teamId}`) % 3) === 0;
  const roles = wantsLive ? ['live', 'final', 'scheduled'] : ['final', 'final', 'scheduled'];
  const startFor = (role, i) => role === 'live' ? now - 30 * MIN : role === 'final' ? now - (i + 1) * DAY : now + (i + 1) * DAY;
  const events = [];
  base.slice(0, roles.length).forEach((src, i) => {
    const ev = clone(src);
    ensureTeamPresent(ev, teamId, fixture);
    const eid = `${ev.id}-t${i}`;
    applyRole(ev, roles[i], profile, startFor(roles[i], i), eid);
    if (!ev.competitions?.[0]) return;
    ev.id = eid; ev.competitions[0].id = eid; ev.date = ev.competitions[0].date;
    events.push(ev);
  });
  return { leagues: [synthLeague(fixture, profile, key, now)], events };
}

// ---- team detail: schedule + roster + stats + standing -----------------------
// The rich team-page tier for the mock. schedule reuses the same phase machinery
// (a longer past+future slate so "last 5 / next 5" has something to show);
// roster/stats fall back to a deterministic fabrication when the fixture lacks a
// capture (so F2 is walkable offline without re-running capture-fixtures).

// Walk a raw ESPN standings tree for one team's group name + 1-based rank.
function findStandingInRaw(standingsRaw, teamId) {
  const id = String(teamId);
  let result;
  const walk = (n) => {
    if (result || !n) return;
    const entries = n.standings?.entries;
    if (Array.isArray(entries)) {
      const idx = entries.findIndex((e) => String((e.team || e.athlete)?.id) === id);
      if (idx >= 0) { result = { group: n.name || n.displayName || '', rank: idx + 1 }; return; }
    }
    for (const c of n.children || []) walk(c);
  };
  walk(standingsRaw);
  return result;
}

// A deterministic "Nth in <group>" — plucked from fixture standings when the team
// is present, else fabricated so the F3 season line + team-page header always read.
export function synthStandingSummary(registry, key, fixture, teamId) {
  const profile = resolve(registry, key);
  const found = findStandingInRaw(fixture.standings, teamId);
  const leagueName = fixture.name || profile.name || key.split('/')[1] || '';
  if (found) return `${ordinal(found.rank)} in ${found.group || leagueName}`;
  return `${ordinal(1 + (hashStr(`${key}:${teamId}:std`) % 8))} in ${leagueName}`;
}

const FIRST = ['Alex', 'Sam', 'Jordan', 'Chris', 'Taylor', 'Jamie', 'Casey', 'Drew', 'Morgan', 'Riley', 'Quinn', 'Avery', 'Parker', 'Reese', 'Skyler', 'Cameron'];
const LAST = ['Smith', 'Johnson', 'Williams', 'Brown', 'Jones', 'Garcia', 'Miller', 'Davis', 'Lopez', 'Wilson', 'Clark', 'Lee', 'Walker', 'Hall', 'Young', 'King'];
const POS_BY_SPORT = { basketball: ['G', 'G', 'F', 'F', 'C'], baseball: ['P', 'C', '1B', '2B', 'SS', '3B', 'LF', 'CF', 'RF'], football: ['QB', 'RB', 'WR', 'TE', 'OL', 'DL', 'LB', 'CB', 'S'], hockey: ['C', 'LW', 'RW', 'D', 'D', 'G'], soccer: ['GK', 'DF', 'MF', 'FW'] };

function fabricateRoster(profile, key, teamId) {
  const pos = POS_BY_SPORT[profile.espnSport] || ['—'];
  const athletes = Array.from({ length: 14 }, (_, i) => {
    const s = `${key}:${teamId}:ath:${i}`;
    return {
      id: `${teamId}-p${i}`,
      displayName: `${FIRST[hashStr(s + ':f') % FIRST.length]} ${LAST[hashStr(s + ':l') % LAST.length]}`,
      jersey: String(1 + (hashStr(s + ':j') % 98)),
      position: { abbreviation: pos[i % pos.length] },
    };
  });
  return { athletes };
}

function fabricateTeamStats(profile, key, teamId) {
  const keys = (Array.isArray(profile.teamStatKeys) && profile.teamStatKeys.length)
    ? profile.teamStatKeys
    : ['gamesPlayed', 'avgPointsFor', 'avgPointsAgainst', 'winPercent'];
  const stats = keys.map((name) => {
    const v = (1 + (hashStr(`${key}:${teamId}:${name}`) % 500) / 10).toFixed(1);
    return { name, displayName: name, shortDisplayName: name, abbreviation: name.slice(0, 3).toUpperCase(), value: Number(v), displayValue: String(v) };
  });
  return { results: { stats: { categories: [{ name: 'general', displayName: 'Season', stats }] } } };
}

/** Assemble the four raw inputs normalizeTeamDetail expects, keyed to one team.
 *  schedule: ~9 events (past finals + a live + future scheduled); roster/stats:
 *  captured when present, else deterministic fabrication; standingsRaw: the
 *  fixture's standings verbatim (so the standing-pluck runs the real normalizer). */
export function synthTeamDetailParts(registry, key, fixture, teamId, { now = Date.now() } = {}) {
  const profile = resolve(registry, key);
  const pool = (fixture.events && fixture.events.length) ? fixture.events : fabricateFromTeams(fixture, profile, 10);
  const mine = pool.filter((ev) => eventHasTeam(ev, teamId));
  const base = ensurePool(mine.length ? mine : pool, 9);
  const roles = ['final', 'final', 'final', 'final', 'final', 'live', 'scheduled', 'scheduled', 'scheduled'];
  const events = [];
  let past = 0, fut = 0;
  base.slice(0, roles.length).forEach((src, i) => {
    const role = roles[i];
    const ev = clone(src);
    ensureTeamPresent(ev, teamId, fixture);
    const eid = `${ev.id}-d${i}`;
    const startMs = role === 'final' ? now - (++past) * 3 * DAY
      : role === 'live' ? now - 40 * MIN
        : now + (++fut) * 3 * DAY;
    applyRole(ev, role, profile, startMs, eid);
    if (!ev.competitions?.[0]) return;
    ev.id = eid; ev.competitions[0].id = eid; ev.date = ev.competitions[0].date;
    events.push(ev);
  });
  const teamRaw = findRawTeam(fixture, teamId) || { id: String(teamId) };
  const team = { ...teamRaw, standingSummary: synthStandingSummary(registry, key, fixture, teamId) };
  return {
    schedule: { team, events },
    roster: fixture.rosters?.[teamId] || fabricateRoster(profile, key, teamId),
    stats: fixture.teamStats?.[teamId] || fabricateTeamStats(profile, key, teamId),
    standingsRaw: fixture.standings || null,
  };
}
