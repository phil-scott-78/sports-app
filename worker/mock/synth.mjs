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
    const down = 1 + Math.floor(mulberry(hashStr(eventId + ':dd'))() * 4), dist = randInt(eventId + ':dist', 1, 15);
    comp.situation = { down, distance: dist, downDistanceText: `${ordinal(down)} & ${dist}`, isRedZone: false };
  }
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
export function synthScoreboard(registry, key, fixture, { now = Date.now(), date = null } = {}) {
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
      pool = ensurePool(pool, Math.min(days, 12));
      pool.forEach((src, i) => {
        const dayMs = s + (i % days) * DAY;
        const role = etDayMs(dayMs) < today ? 'final' : etDayMs(dayMs) > today ? 'scheduled' : 'live';
        const ev = clone(src);
        applyRole(ev, role, profile, dayStart(dayMs, role, i), String(ev.id));
        if (!ev.competitions?.[0]) return;
        ev.date = ev.competitions[0].date;
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

  let roles;
  if (cmp === 0) { pool = ensurePool(pool, 3); roles = mixedRoles(pool.length); }
  else if (cmp < 0) roles = pool.map(() => 'final');
  else roles = pool.map(() => 'scheduled');

  const counters = { final: 0, live: 0, scheduled: 0 };
  pool.forEach((src, i) => {
    const role = roles[i];
    const k = counters[role]++;
    const startMs = cmp === 0 ? slotStart(role, k, now) : dayStart(targetDay, role, i);
    const ev = clone(src);
    applyRole(ev, role, profile, startMs, String(ev.id));
    if (!ev.competitions?.[0]) return; // event with no competitions/groupings → skip
    ev.date = ev.competitions[0].date; // event date follows its (first) competition
    out.events.push(ev);
  });
  out.day = { date: date ? ymdDash(date) : etDayDash(now) };
  return out;
}

/**
 * Raw ESPN-shaped summary for an event id. Returns the captured real summary when
 * we have one (best fidelity — real box scores), else a minimal valid envelope so
 * normalizeSummary yields empty tables and the detail page degrades to cheap-tier.
 */
export function synthSummary(fixture, eventId) {
  const base = String(eventId).split('-c')[0].split(':')[0]; // strip clone/comp suffixes
  const raw = fixture.summaries?.[eventId] || fixture.summaries?.[base];
  if (raw) return raw;
  return { header: { id: String(eventId), competitions: [{ id: String(eventId), competitors: [], status: { type: { state: 'post', completed: true } } }] }, boxscore: { teams: [], players: [] }, plays: [], scoringPlays: [], keyEvents: [], rosters: [] };
}

export const synthTeams = (fixture) => fixture.teams || { sports: [{ leagues: [{ teams: [] }] }] };
export const synthStandings = (fixture) => fixture.standings || {};

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
