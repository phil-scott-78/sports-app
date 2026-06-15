// normalize.js — raw ESPN scoreboard → canonical ScoresResponse (see
// schema/canonical.ts). Pure functions, no I/O, so they run in Node tests and
// in the worker alike. Behavior is driven by the resolved league profile, so a
// new league is data (league-profiles.json), not code here.

import { resolve } from '../../schema/tools/resolve.mjs';

export const https = u => (typeof u === 'string' ? u.replace(/^http:/, 'https:') : undefined);
const intOrNull = s => { const n = parseInt(s, 10); return Number.isFinite(n) ? n : null; };
// ESPN sometimes HTML-encodes free text (e.g. cricket "won by an inns &amp; 98 runs").
const decodeEntities = s => (typeof s === 'string'
  ? s.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#0?39;|&apos;/g, "'")
  : s);

// Dark-mode logo variant. ESPN ships a 'dark' (white/light) logo for dark
// backgrounds: explicit in team.logos[] (rel 'dark') when present, else derived
// from the team-logo CDN path (/500/ -> /500-dark/). The client falls back to
// the light logo if the dark URL 404s (e.g. soccer has no derived variant).
const deriveDark = u =>
  (typeof u === 'string' && u.includes('/i/teamlogos/') && u.includes('/500/'))
    ? u.replace('/500/', '/500-dark/')
    : undefined;
// Sports whose ESPN team-logo CDN reliably has a derived /500-dark/ variant.
// (Soccer/cricket/etc. have full-colour crests that read fine on dark and no
// derived dark file, so deriving there only yields wasted 404s.)
const DARK_LOGO_SPORTS = new Set(['baseball', 'basketball', 'football', 'hockey']);
export function darkLogoOf(team, light, espnSport) {
  const ls = team?.logos;
  if (Array.isArray(ls)) { // explicit ESPN 'dark' rel (summary/core) — always trustworthy
    const d = ls.find(l => (l.rel || []).includes('dark') && !(l.rel || []).includes('scoreboard'))
      || ls.find(l => (l.rel || []).includes('dark'));
    if (d?.href) return https(d.href);
  }
  return DARK_LOGO_SPORTS.has(espnSport) ? deriveDark(light) : undefined;
}

// ---- status -----------------------------------------------------------------
// Branch on type.name, never on state alone (postponed can read state='post').
export function statusToPhase(t = {}) {
  const name = t.name || '';
  const state = t.state;
  const completed = !!t.completed;
  if (/POSTPON/.test(name)) return { phase: 'postponed', live: false, ended: false };
  if (/CANCEL/.test(name)) return { phase: 'canceled', live: false, ended: false };
  if (/ABANDON/.test(name)) return { phase: 'abandoned', live: false, ended: false };
  if (/SUSPEND|RAIN|DELAY/.test(name)) return { phase: state === 'in' ? 'live' : 'suspended', live: state === 'in', ended: false };
  if (state === 'in') return { phase: 'live', live: true, ended: false };
  if (state === 'post' || completed) return { phase: 'final', live: false, ended: completed };
  if (state === 'pre') return { phase: 'scheduled', live: false, ended: false };
  return { phase: 'unknown', live: false, ended: false };
}

// ---- score (by scoreKind) ---------------------------------------------------
function buildScore(scoreKind, raw) {
  // ESPN's scoreboard serializes competitor.score as a STRING ("103"); the
  // team-schedule endpoint serializes it as an OBJECT ({value, displayValue},
  // soccer adds $ref/winner). Coerce to the scalar form FIRST so String() below
  // never yields "[object Object]" and intOrNull still sees the number.
  if (raw != null && typeof raw === 'object') raw = raw.displayValue ?? raw.value ?? '';
  const display = raw == null ? '' : String(raw);
  const s = { display };
  if (scoreKind === 'numeric') { const v = intOrNull(raw); if (v != null) s.value = v; }
  else if (scoreKind === 'toPar') { s.toPar = display === 'E' ? 0 : intOrNull(display.replace('+', '')) ?? undefined; }
  else if (scoreKind === 'cricket') {
    // Composite like "161/5 (18/20 ov, target 156)" or "106 (17/20 ov, target 171)"
    // (all-out → no "/wkts"). Anchor runs/wkts to the LEADING total only — the old
    // regex grabbed the "17/20" OVERS fragment as runs/wickets (→ runs:17,wkts:20).
    // Authoritative per-innings figures live in periodScores[].cricket regardless.
    const m = display.match(/^\s*(\d+)(?:\/(\d+))?/);
    if (m) { s.cricket = { runs: +m[1] }; if (m[2] != null) s.cricket.wickets = +m[2]; }
    const ov = display.match(/([\d.]+)\s*(?:\/\s*\d+)?\s*ov/i); if (ov && s.cricket) s.cricket.overs = +ov[1];
    const t = display.match(/target\s+(\d+)/i); if (t && s.cricket) s.cricket.target = +t[1];
  }
  return s;
}

// ---- competitor -------------------------------------------------------------
function buildCompetitor(profile, raw) {
  const kind = profile.competitorKind || 'team';
  const c = { kind, id: String(raw.id ?? raw.team?.id ?? raw.athlete?.id ?? ''), displayName: '' };
  const team = raw.team;

  if (kind === 'team' && team) {
    c.displayName = team.displayName || team.name || team.shortDisplayName || '';
    if (team.shortDisplayName) c.shortName = team.shortDisplayName;
    if (team.abbreviation) c.abbreviation = team.abbreviation;
    const logo = https(team.logo || team.logos?.[0]?.href);
    if (logo) { c.logo = logo; const d = darkLogoOf(team, logo, profile.espnSport); if (d) c.logoDark = d; }
    if (team.color) c.color = team.color;
    if (team.alternateColor) c.altColor = team.alternateColor; // cheap-tier; backs the card gradient
  } else {
    const list = raw.athlete ? [raw.athlete] : (raw.roster?.athletes?.map(a => a.athlete ?? a) || raw.athletes || []);
    c.athletes = list.map(a => {
      const o = { id: String(a.id ?? ''), name: a.displayName || a.fullName || a.shortName || '' };
      if (a.jersey) o.jersey = a.jersey;
      if (a.flag?.alt || a.citizenship) o.country = a.flag?.alt || a.citizenship;
      const hs = https(a.headshot?.href || a.headshot); if (hs) o.headshot = hs;
      if (a.position?.abbreviation) o.position = a.position.abbreviation;
      return o;
    });
    c.displayName = raw.roster?.displayName
      || c.athletes.map(a => a.name).filter(Boolean).join(' / ')
      || raw.athlete?.displayName
      // golf TEAM formats (PGA Zurich, LPGA Dow) ship only a `team` object and no
      // athlete/roster — fall back to the team name so rows aren't blank.
      || team?.displayName || team?.shortDisplayName || team?.name
      || '';
    if (c.athletes.length === 2 && raw.roster) c.kind = 'pair'; // tennis/golf doubles
    if (team?.abbreviation) c.abbreviation = team.abbreviation;
    if (!c.athletes.length && team?.shortDisplayName) c.shortName = team.shortDisplayName;
    if (!c.athletes.length && team?.color) c.color = team.color;
    const logo = https(team?.logo);
    if (logo) { c.logo = logo; const d = darkLogoOf(team, logo, profile.espnSport); if (d) c.logoDark = d; }
  }

  if (raw.homeAway) c.homeAway = raw.homeAway;
  if (raw.order != null) c.order = raw.order;
  if (raw.startOrder != null) c.startOrder = raw.startOrder;
  const cr = raw.curatedRank?.current; if (cr != null) c.rank = cr === 99 ? null : cr;
  if (raw.winner != null) c.winner = raw.winner;
  if (raw.score != null) c.score = buildScore(profile.scoreKind, raw.score);

  if (Array.isArray(raw.linescores) && raw.linescores.length) {
    const ignore = profile.ignorePeriods;                                  // rugby sentinel periods [20,60]
    // golf: ESPN appends a playoff as a "5th round" (period > regulation) only for
    // the players involved — drop it so the leaderboard gets no phantom R5 column
    // and the strokes total isn't inflated by playoff holes.
    const maxRound = profile.periodUnit === 'hole_rounds' ? (profile.regulationPeriods || 0) : 0;
    c.periodScores = raw.linescores
      // tennis linescores carry {value, winner} with NO period — synthesize it from
      // the position so the set scoreline survives (every other sport sends period).
      .map((ls, i) => ({ ls, period: ls && ls.period != null ? ls.period : i + 1 }))
      .filter(({ ls, period }) =>
        ls
        && (ls.value != null || ls.displayValue != null || ls.runs != null)
        && !(ignore && ignore.includes(period))
        && !(maxRound && period > maxRound))
      .map(({ ls, period }) => {
        const p = { period, value: ls.value ?? null, display: ls.displayValue ?? String(ls.value ?? '') };
        if (ls.tiebreak != null) p.tiebreak = ls.tiebreak;
        if (ls.winner != null) p.setWinner = ls.winner;                 // tennis: per-set winner
        if (Array.isArray(ls.linescores)) p.holesPlayed = ls.linescores.length; // golf: THRU
        if (ls.runs != null || ls.wickets != null) {
          p.cricket = { runs: ls.runs, wickets: ls.wickets };
          if (ls.overs != null) p.cricket.overs = ls.overs;
          if (ls.isBatting != null) p.cricket.isBatting = ls.isBatting;
          if (ls.target != null) p.cricket.target = ls.target;
          if (ls.description) p.cricket.reason = ls.description;
        }
        return p;
      });
  }
  // golf: total strokes = sum of per-round strokes (round value), backing the TOT
  // column. Sum ONLY completed rounds (18 holes played): an in-progress round's
  // value is strokes-so-far, which makes the running total non-monotonic across the
  // field (a leader thru 9 would show fewer strokes than a finished trailer). Playoff
  // rounds are already dropped above. Falls back to all rounds when no per-hole data.
  if (profile.scoreKind === 'toPar' && c.score && Array.isArray(c.periodScores) && c.periodScores.length) {
    const sumOf = pred => c.periodScores.reduce((s, p) => s + (pred(p) && typeof p.value === 'number' ? p.value : 0), 0);
    const anyHoleData = c.periodScores.some(p => p.holesPlayed != null);
    const strokes = anyHoleData ? sumOf(p => p.holesPlayed === 18) : sumOf(() => true);
    if (strokes > 0 && c.score.strokes == null) c.score.strokes = strokes;
  }
  if (Array.isArray(raw.records) && raw.records.length)
    c.records = raw.records.map(r => ({ type: r.type || r.name || 'total', summary: r.summary }));
  if (raw.shootoutScore != null) c.shootoutScore = raw.shootoutScore;
  if (raw.aggregateScore != null) c.aggregateScore = String(raw.aggregateScore); // STRING, per schema
  if (raw.advance != null) c.advance = raw.advance;
  if (raw.amateur != null) c.amateur = raw.amateur;
  if (raw.vehicle) c.vehicle = pick(raw.vehicle, ['number', 'manufacturer', 'team', 'owner', 'sponsor']);

  // ---- cheap-tier context the scoreboard already carries (see DISPLAY-SPEC.md) ----
  // These cost ZERO extra network — the scoreboard response holds them, the app just
  // wasn't surfacing them. Each is optional and only emitted when present.
  if (raw.hits != null) { const n = intOrNull(raw.hits); if (n != null) c.hits = n; }       // baseball R/H/E
  if (raw.errors != null) { const n = intOrNull(raw.errors); if (n != null) c.errors = n; }
  if (raw.form) c.form = String(raw.form);                                                  // soccer/rugby last-5 ('WLWWW')
  if (Array.isArray(raw.statistics) && raw.statistics.length) {                             // team stat line, keyed
    const stats = {};
    for (const s of raw.statistics) {
      const k = s.abbreviation || s.name;
      const v = s.displayValue ?? s.value;
      if (k != null && v != null && stats[k] == null) stats[k] = v;
    }
    if (Object.keys(stats).length) c.stats = stats;
  }
  if (Array.isArray(raw.leaders) && raw.leaders.length) {                                   // game/team leaders
    const leaders = raw.leaders.map(g => {
      const top = g.leaders?.[0];
      const ath = top?.athlete;
      return pick({
        name: g.name || g.shortDisplayName || g.abbreviation || '',
        label: g.shortDisplayName || g.abbreviation || g.displayName || g.name || '',
        display: top?.displayValue ?? undefined,
        athlete: ath ? (ath.shortName || ath.displayName || ath.fullName) : undefined,
      }, ['name', 'label', 'display', 'athlete']);
    }).filter(l => l.display || l.athlete);
    if (leaders.length) c.leaders = leaders;
  }
  if (Array.isArray(raw.probables) && raw.probables.length) {                               // probable pitcher / goalie
    const probables = raw.probables.map(pr => {
      const ath = pr.athlete;
      return pick({
        role: pr.shortDisplayName || pr.displayName || pr.name || '',
        athlete: ath ? (ath.shortName || ath.displayName || ath.fullName) : (typeof pr === 'string' ? pr : undefined),
      }, ['role', 'athlete']);
    }).filter(p => p.athlete);
    if (probables.length) c.probables = probables;
  }
  return c;
}

const pick = (o, keys) => Object.fromEntries(keys.filter(k => o[k] != null).map(k => [k, o[k]]));

// ---- live situation: the "what's happening right now" strip ------------------
// Sport-agnostic union — only present keys are emitted. Baseball: count/outs/
// baserunners/pitcher/batter. Gridiron: down/distance/possession/red-zone/timeouts.
function buildSituation(rc) {
  const sit = rc.situation;
  if (!sit || typeof sit !== 'object') return undefined;
  const s = {};
  for (const k of ['balls', 'strikes', 'outs', 'down', 'distance', 'homeTimeouts', 'awayTimeouts']) {
    const v = sit[k];
    const n = typeof v === 'number' ? v : (typeof v === 'string' && /^\d+$/.test(v) ? +v : null);
    if (n != null) s[k] = n;
  }
  for (const k of ['onFirst', 'onSecond', 'onThird', 'isRedZone']) if (sit[k] != null) s[k] = !!sit[k];
  const p = sit.pitcher?.athlete; if (p) s.pitcher = p.shortName || p.displayName || p.fullName;
  const b = sit.batter?.athlete; if (b) s.batter = b.shortName || b.displayName || b.fullName;
  if (sit.downDistanceText) s.downDistanceText = sit.downDistanceText;
  if (sit.possession != null) s.possession = String(sit.possession); // team id of the side in possession
  const lp = sit.lastPlay;
  const lpText = lp && (lp.type?.alternativeText || lp.text || lp.type?.text);
  if (lpText) s.lastPlay = lpText;
  if (rc.outsText) s.outsText = rc.outsText;
  return Object.keys(s).length ? s : undefined;
}

// units where played > regulation genuinely means extra play
const OT_UNITS = new Set(['half', 'quarter', 'period', 'inning', 'over_innings']);

// ---- decision (generic, refined by decorators) ------------------------------
function decide(profile, comp) {
  if (comp.status.phase !== 'final') return null;
  const cs = comp.competitors;
  if (cs.some(c => c.shootoutScore != null)) return 'shootout';
  if (cs.some(c => c.aggregateScore != null)) return 'aggregate';
  const isDraw = profile.layout === 'headToHead' && cs.length === 2 && cs.every(c => c.winner === false);
  if (profile.scoreKind === 'none') {
    // a 2-sided no-score contest where neither side won is a draw / no-contest —
    // surface it BEFORE 'method' so an MMA draw/NC isn't reported as a finish.
    if (isDraw) return 'draw';
    return profile.espnSport === 'mma' ? 'method' : 'regulation';
  }
  // "overtime" only means extra play for timed/inning units — but NOT baseball: its
  // "Final/10" status already conveys extra innings, so "After overtime" is wrong.
  if (comp.periods.isOvertime && profile.periodUnit !== 'inning') return 'overtime';
  if (isDraw) return 'draw';
  return 'regulation';
}

// per-family touch-ups for things the generic path can't infer from discriminators
const DECORATORS = {
  cricket(comp, rc) {
    const m = comp.meta || (comp.meta = {});
    if (rc.class?.generalClassCard) m.cricketClass = rc.class.generalClassCard;
    const summary = rc.status?.summary || rc.status?.type?.summary;
    if (summary) m.cricketSummary = decodeEntities(summary); // ESPN HTML-encodes "&amp;" etc.
  },
  mma(comp, rc) {
    const r = rc.status?.result;
    if (r) comp.method = pick({
      kind: r.displayName || r.shortDisplayName, detail: r.description,
      target: r.target?.name, finishRound: comp.status.period || undefined,
      finishTime: comp.status.detail || undefined,
    }, ['kind', 'detail', 'target', 'finishRound', 'finishTime']);
    else if (comp.status.phase === 'final') {
      // The site scoreboard carries NO status.result; the method of victory lives in
      // details[].type, e.g. "Unofficial Winner Kotko" / "...Submission" / "...Decision",
      // with the finish round in status.period and the time in status.displayClock.
      const det = (rc.details || [])
        .map(d => (typeof d.type === 'string' ? d.type : d.type?.text) || d.text || '')
        .find(t => /unofficial winner/i.test(t)) || '';
      const mm = det.match(/unofficial winner\s+(.+)$/i);
      if (mm) {
        let kind = mm[1].trim();
        if (/^kotko$/i.test(kind)) kind = 'KO/TKO'; // ESPN mangles "KO/TKO" → "Kotko"
        const decision = /decision/i.test(kind);    // a decision goes the distance — no round/time
        const clock = rc.status?.displayClock;
        comp.method = pick({
          kind,
          finishRound: decision ? undefined : (comp.status.period || undefined),
          finishTime: decision || !clock || clock === '-' || clock === '0:00' ? undefined : clock,
        }, ['kind', 'finishRound', 'finishTime']);
      }
    }
    if (rc.cardSegment?.description) (comp.meta ||= {}).cardSegment = rc.cardSegment.description;
    if (rc.status?.featured) (comp.meta ||= {}).featured = true;
  },
  racing(comp, rc) {
    if (rc.status?.flag) (comp.meta ||= {}).flag = rc.status.flag; // F1-only in practice
  },
};

// ---- competition ------------------------------------------------------------
function buildCompetition(profile, rc, rawEvent) {
  const st = rc.status || rawEvent.status || {};
  const type = st.type || {};
  const ph = statusToPhase(type);
  const competitors = (rc.competitors || []).map(x => buildCompetitor(profile, x));
  if (profile.layout === 'field') competitors.sort((a, b) => (a.order ?? 1e9) - (b.order ?? 1e9));

  const regCount = profile.regulationPeriods ?? 0;
  const stPeriod = typeof st.period === 'number' ? st.period : 0;
  // golf: ESPN bumps status.period to a 5th "round" during a playoff; clamp it to
  // regulation (the playoff linescore period is already dropped above) so the round
  // count + OT logic stay correct.
  const clampedStPeriod = (profile.periodUnit === 'hole_rounds' && regCount && stPeriod > regCount) ? regCount : stPeriod;
  const played = Math.max(
    clampedStPeriod,
    ...competitors.map(c => (c.periodScores?.length ? Math.max(...c.periodScores.map(p => p.period)) : 0)),
  );
  const comp = {
    id: String(rc.id ?? rawEvent.id),
    layout: profile.layout, scoreKind: profile.scoreKind, competitorKind: profile.competitorKind,
    status: {
      phase: ph.phase, live: ph.live, ended: ph.ended,
      period: clampedStPeriod,
      periodLabel: type.shortDetail || type.detail || type.description || '',
      espnName: type.name || '', detail: type.detail || '',
    },
    periods: {
      unit: profile.periodUnit, regulation: regCount, played,
      // "overtime" only means extra play for timed/inning units — NOT for sets
      // (best-of-5 ≠ OT), rounds (5-round MMA ≠ OT), laps, or golf rounds.
      isOvertime: OT_UNITS.has(profile.periodUnit) && regCount > 0 && played > regCount,
      ...(profile.periodLengthMin != null ? { lengthMin: profile.periodLengthMin } : {}),
    },
    decision: null,
    competitors,
  };
  // racing: a weekend event has several competitions (FP1/Qual/Race) — label them
  if (profile.espnSport === 'racing' && (rc.type?.abbreviation || rc.type?.text)) {
    comp.label = rc.type.abbreviation || rc.type.text;
  }
  if (type.shortDetail) comp.status.shortDetail = type.shortDetail;
  if (type.altDetail) comp.status.altDetail = type.altDetail;
  if (ph.live && st.displayClock && st.displayClock !== '0:00') comp.status.clock = st.displayClock;

  const notesHead = (rc.notes || []).map(n => n.headline).filter(Boolean);
  if (notesHead.length) (comp.meta ||= {}).round = notesHead[0];
  // golf playoff: flag it (the playoff linescore round was dropped, so detect it from
  // the RAW competitors' period > regulation) so the UI can badge "Playoff".
  const golfPlayoff = profile.periodUnit === 'hole_rounds' && regCount
    && (rc.competitors || []).some(x => Array.isArray(x.linescores) && x.linescores.some(ls => (ls?.period ?? 0) > regCount));
  if (rc.status?.hadPlayoff || golfPlayoff) (comp.meta ||= {}).hadPlayoff = true;
  if (rc.series?.summary) (comp.meta ||= {}).seriesSummary = rc.series.summary;

  const situation = buildSituation(rc);
  if (situation) comp.situation = situation;

  comp.decision = decide(profile, comp);
  DECORATORS[profile.espnSport]?.(comp, rc, profile);
  if (comp.meta) comp.decision = decide(profile, comp) ?? comp.decision; // re-decide if decorator added shootout/agg (rare)
  return comp;
}

// ---- event ------------------------------------------------------------------
function buildVenue(v) {
  if (!v) return undefined;
  return pick({ name: v.fullName, city: v.address?.city, country: v.address?.country, indoor: v.indoor }, ['name', 'city', 'country', 'indoor']);
}
export function buildEvent(profile, e) {
  // most sports: events[].competitions[]. Tennis nests matches under
  // events[].groupings[].competitions[] (singles/doubles draws) — flatten them.
  const rawComps = (e.competitions && e.competitions.length)
    ? e.competitions
    : (e.groupings || []).flatMap(g => g.competitions || []);
  const c0 = rawComps[0];
  const links = {};
  const web = https(e.links?.find(l => l.rel?.includes('summary') || l.rel?.includes('desktop'))?.href);
  const box = https(e.links?.find(l => l.rel?.includes('boxscore'))?.href);
  if (web) links.web = web; if (box) links.box = box;
  return {
    id: String(e.id), name: e.name || '', shortName: e.shortName || '',
    start: e.date, neutralSite: !!c0?.neutralSite,
    venue: buildVenue(c0?.venue || e.venue),
    broadcasts: [...new Set((c0?.broadcasts || []).flatMap(b => b.names || []))],
    notes: (c0?.notes || []).map(n => n.headline).filter(Boolean),
    links,
    competitions: rawComps.map(c => buildCompetition(profile, c, e)),
  };
}

// Soonest kickoff (epoch ms) among events still in the 'scheduled' phase, or
// undefined when none. The worker uses this to shorten the idle cache as a game
// approaches so the idle→live flip isn't hidden behind the 5m idle TTL (see
// ttl.js). Live/final events are skipped — only games yet to start matter here.
export function nextScheduledStart(events) {
  let min;
  for (const ev of events) {
    if (!ev.start || !ev.competitions.some(c => c.status.phase === 'scheduled')) continue;
    const ms = Date.parse(ev.start);
    if (Number.isNaN(ms)) continue;
    if (min === undefined || ms < min) min = ms;
  }
  return min;
}

// ---- top level --------------------------------------------------------------
export function normalizeScoreboard(reg, key, sb) {
  const profile = resolve(reg, key);
  const lg = (sb.leagues || [{}])[0];
  const events = (sb.events || []).map(e => buildEvent(profile, e));
  return {
    sport: profile.espnSport,
    league: lg.slug || key.split('/')[1],
    leagueId: String(lg.id ?? profile.espnLeagueId ?? ''),
    leagueName: lg.name || profile.name || '',
    season: pick({
      year: lg.season?.year,
      type: lg.season?.type?.type ?? (typeof lg.season?.type === 'number' ? lg.season.type : undefined),
      slug: lg.season?.slug || lg.season?.type?.name,
      displayName: lg.season?.displayName,
    }, ['year', 'type', 'slug', 'displayName']),
    // ESPN's reference "sports day" for this slate (YYYY-MM-DD), in its own ET
    // bucketing. The default (date-less) scoreboard does NOT roll at local
    // midnight — at 00:20 on the 14th it can still report the 13th — so the app
    // anchors its Yesterday/Upcoming offsets to this rather than the device clock.
    day: sb.day?.date || undefined,
    updated: new Date().toISOString(),
    anyLive: events.some(ev => ev.competitions.some(c => c.status.live)),
    nextStartMs: nextScheduledStart(events), // undefined when nothing scheduled
    events,
  };
}
