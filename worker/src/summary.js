// summary.js — raw ESPN /summary → canonical GameSummary (see canonical.ts).
// Pure functions (run in Node tests and the worker). The /summary payload is the
// RICH tier: full per-player box scores, team-stat comparison, scoring feed,
// per-period splits and lineups — fetched only when a game detail is opened.
//
// One generic shape spans every sport: team differences are DATA not code. The
// only real branches are where ESPN itself diverges — scoring lives in plays[]
// (MLB/NBA/NHL), scoringPlays[] (NFL) or keyEvents[] (soccer); MLB team stats
// nest while everyone else is flat; soccer/rugby add rosters[] lineups.

import { resolve } from '../../schema/tools/resolve.mjs';

const str = v => (v == null ? '' : String(v));
const cap = s => (s ? s.charAt(0).toUpperCase() + s.slice(1) : s);
const numOrNull = v => (typeof v === 'number' ? v : (typeof v === 'string' && /^-?\d+$/.test(v) ? +v : null));
const pick = (o, keys) => Object.fromEntries(keys.filter(k => o[k] != null && o[k] !== '').map(k => [k, o[k]]));

// team.id -> 'home'|'away' and id -> abbreviation, from the summary header.
// Soccer commentary plays tag their team by NAME only (no id/abbr), so also map
// display names -> side and side -> abbreviation.
function sideMaps(raw) {
  const comps = raw.header?.competitions?.[0]?.competitors || [];
  const side = {}, abbr = {}, nameSide = {}, haAbbr = {};
  for (const c of comps) {
    const id = String(c.id ?? c.team?.id ?? '');
    if (id && c.homeAway) side[id] = c.homeAway;
    const a = c.team?.abbreviation;
    if (id && a) abbr[id] = a;
    if (c.homeAway) {
      if (a) haAbbr[c.homeAway] = a;
      const t = c.team || {};
      for (const n of [t.displayName, t.shortDisplayName, t.name]) if (n) nameSide[n] = c.homeAway;
    }
  }
  return { side, abbr, nameSide, haAbbr, comps };
}

const aShort = a => a?.shortName || a?.displayName || a?.fullName || '';
const aPos = a => a?.position?.abbreviation || a?.position?.name;

// Stat keys that aren't a glanceable head-to-head comparison: bare "meta" counts
// (largestLead/leadChanges/leadPercentage read as stray numbers), redundant
// duplicates of a stat we already keep, and game-management timeouts. Dropped so
// the comparison stays a clean box-score read.
const TEAM_STAT_DENY = new Set([
  'largestLead', 'leadChanges', 'leadPercentage',
  'totalTurnovers', 'teamTurnovers', 'totalTechnicalFouls',
  'fullTimeoutsRemaining', 'shortTimeoutsRemaining', 'timeoutsRemaining', 'timeoutsUsed',
]);

// ---- team stat comparison ---------------------------------------------------
function buildTeamStats(raw) {
  const teams = raw.boxscore?.teams || [];
  if (teams.length < 2) return [];
  const byHa = {};
  for (const t of teams) if (t.homeAway) byHa[t.homeAway] = t;
  const away = byHa.away || teams[0];
  const home = byHa.home || teams[1];
  const flat = t => {
    const m = {};
    for (const s of (t.statistics || [])) {
      if (s.displayValue == null) continue; // MLB nests (no top-level displayValue) — skip
      if (TEAM_STAT_DENY.has(s.name)) continue; // drop noise / timeouts
      m[s.name] = { label: s.label || s.shortDisplayName || s.displayName || s.name, value: String(s.displayValue) };
    }
    return m;
  };
  const A = flat(away), H = flat(home);
  const rows = [];
  const seen = new Set();
  for (const k of Object.keys(A)) {
    seen.add(k);
    rows.push(pick({ label: A[k].label, away: A[k].value, home: H[k]?.value }, ['label', 'away', 'home']));
  }
  for (const k of Object.keys(H)) {
    if (seen.has(k)) continue;
    rows.push(pick({ label: H[k].label, home: H[k].value }, ['label', 'home']));
  }
  return rows.filter(r => r.away != null || r.home != null);
}

// ---- per-player box groups --------------------------------------------------
function buildBoxGroups(raw, side) {
  const players = raw.boxscore?.players || [];
  if (!players.length) return [];
  const order = []; // preserve group order
  const byTitle = new Map();
  for (const teamBlock of players) {
    const tid = String(teamBlock.team?.id ?? '');
    const teamSide = side[tid];
    const teamAbbr = teamBlock.team?.abbreviation;
    for (const g of (teamBlock.statistics || [])) {
      const title = cap(g.name || g.type) || 'Players';
      const columns = (g.labels || []).map(str);
      const rows = (g.athletes || []).map(a => {
        const name = aShort(a.athlete);
        const stats = (a.stats || []).map(str);
        // drop DNPs / malformed rows: a row must have a name and align with columns
        if (!name || stats.length === 0 || (columns.length && stats.length !== columns.length)) return null;
        return pick({ name, pos: aPos(a.athlete) || a.position?.abbreviation, stats }, ['name', 'pos', 'stats']);
      }).filter(Boolean);
      if (!rows.length) continue;
      if (!byTitle.has(title)) { byTitle.set(title, { title, columns, teams: [] }); order.push(title); }
      const grp = byTitle.get(title);
      if (!grp.columns.length && columns.length) grp.columns = columns;
      grp.teams.push(pick({ side: teamSide, abbr: teamAbbr, rows }, ['side', 'abbr', 'rows']));
    }
  }
  return order.map(t => byTitle.get(t));
}

// ---- scoring feed -----------------------------------------------------------
const SOCCER_KEEP = /goal|card|penalt|substitution/i;

// ESPN ships substitutions as "Substitution, <Team>. X replaces Y." — strip the
// redundant team lead-in (the timeline already tags the team + draws a swap glyph)
// so the row reads "X replaces Y." Anchored on the period-free "replaces" tail
// rather than the first '.', so a dotted club name ("A.F.C. Bournemouth") isn't
// truncated; falls back to dropping just the "Substitution," keyword.
export function cleanSubText(text) {
  const t = typeof text === 'string' ? text : '';
  const tail = t.match(/([^.]*\breplaces\b[^.]*\.?)\s*$/i);
  return (tail ? tail[1] : t.replace(/^substitution[,.]?\s*/i, '')).trim() || t;
}

function mapPlay(p, side, abbr) {
  const tid = String(p.team?.id ?? '');
  return pick({
    period: p.period?.number,
    periodLabel: p.period?.displayValue,
    clock: p.clock?.displayValue,
    side: side[tid] || (p.team?.homeAway),
    teamAbbr: abbr[tid] || p.team?.abbreviation,
    text: p.text || p.shortText || '',
    away: numOrNull(p.awayScore),
    home: numOrNull(p.homeScore),
    type: p.scoringType?.displayName || p.type?.text,
  }, ['period', 'periodLabel', 'clock', 'side', 'teamAbbr', 'text', 'away', 'home', 'type']);
}

function buildScoringPlays(raw, side, abbr) {
  let src = [], soccer = false;
  if (Array.isArray(raw.scoringPlays) && raw.scoringPlays.length) {
    src = raw.scoringPlays; // NFL
  } else if (Array.isArray(raw.plays) && raw.plays.length) {
    src = raw.plays.filter(p => p.scoringPlay === true); // MLB/NBA/NHL
  } else if (Array.isArray(raw.keyEvents) && raw.keyEvents.length) {
    src = raw.keyEvents.filter(p => p.scoringPlay === true || SOCCER_KEEP.test(p.type?.text || '')); // soccer
    soccer = true;
  }
  const out = src.map(p => {
    const m = mapPlay(p, side, abbr);
    // Whether this row is an actual score (a goal) vs. one of the cards/subs
    // that ride soccer's keyEvents feed. Lets the app's condensed "Scoring"
    // recap show goals only, while the full Plays list still carries everything.
    m.scoring = soccer ? p.scoringPlay === true : true;
    return m;
  }).filter(p => p.text);
  // Tidy soccer substitution text; leaves every other play's text untouched.
  for (const p of out) {
    if (/substitution/i.test(p.type || '')) p.text = cleanSubText(p.text);
  }
  return out.length > 120 ? out.slice(0, 120) : out;
}

// ---- structured match timeline (soccer) -------------------------------------
// A first-class event feed for the design's Timeline tab: goals, cards, subs
// (and VAR when present), each with the scorer/assist — or sub on/off — split
// out of ESPN's keyEvents participants[]. The noise (Kickoff, Halftime, Start
// 2nd Half, injury Start/End Delay, End Regular Time…) is dropped; the app
// derives the half dividers from the period numbers. VERIFIED 2026-07
// (fifa.world, live + finals): keyEvent = { type:{text}, text, shortText,
// clock:{displayValue:"45'+7'"}, period:{number}, scoringPlay, team:{id} (no
// homeAway/abbr → resolve via the id maps), participants:[{athlete:{displayName}}] }.
// participants are [scorer, assist] for goals and [playerIn, playerOut] for
// substitutions. awayScore/homeScore are ALWAYS undefined here, so the running
// score is not shipped — the app tallies it from the ordered scoring events
// (each goal's `side`; ESPN attributes an Own Goal to the BENEFITING team).
const MINUTE_RE = /^(\d+)(?:'?\s*\+\s*(\d+))?/;
function clockMinutes(display) {
  const m = MINUTE_RE.exec(str(display).trim());
  if (!m) return undefined;
  return +m[1] + (m[2] ? +m[2] : 0);
}

function eventKind(typeText) {
  const t = str(typeText).toLowerCase();
  if (!t) return null;
  if (t.includes('own goal')) return 'own-goal';
  if (t.includes('penalt')) return /miss|saved/.test(t) ? 'penalty-missed' : 'penalty-goal';
  if (t.includes('goal')) return 'goal';
  if (t.includes('red card') || t.includes('second yellow')) return 'red-card';
  if (t.includes('yellow')) return 'yellow-card';
  if (t.includes('substitution')) return 'substitution';
  if (t.includes('var')) return 'var';
  return null; // Kickoff / Halftime / Start-2nd-Half / delays / full time → markers
}

export function buildMatchTimeline(raw, { side, abbr }) {
  const src = raw.keyEvents;
  if (!Array.isArray(src) || !src.length) return undefined;
  const out = [];
  for (const e of src) {
    const kind = eventKind(e.type?.text);
    if (!kind) continue;
    const tid = String(e.team?.id ?? '');
    const names = (e.participants || []).map(p => aShort(p.athlete)).filter(Boolean);
    // goals split into [scorer, assist]; subs into [on, off]; cards carry one.
    const twoActor = kind === 'substitution' || kind === 'goal' || kind === 'penalty-goal';
    out.push(pick({
      t: clockMinutes(e.clock?.displayValue),
      clock: e.clock?.displayValue,
      period: e.period?.number,
      kind,
      side: side[tid],
      teamAbbr: abbr[tid],
      athlete: names[0],
      assist: twoActor ? names[1] : undefined,
      text: e.text || e.shortText || '',
      scoring: e.scoringPlay === true,
    }, ['t', 'clock', 'period', 'kind', 'side', 'teamAbbr', 'athlete', 'assist', 'text', 'scoring']));
  }
  if (!out.length) return undefined;
  // Chronological (period, then minute incl. stoppage). keyEvents arrive ordered
  // but delays interleave; a stable sort keeps same-minute events in feed order.
  return out
    .map((e, i) => ({ e, i }))
    .sort((a, b) => (a.e.period ?? 0) - (b.e.period ?? 0) || (a.e.t ?? 0) - (b.e.t ?? 0) || a.i - b.i)
    .map(x => x.e);
}

// ---- per-period splits (NBA/NFL quarters, NHL periods) ----------------------
function buildPeriodLines(raw, profile) {
  const comps = raw.header?.competitions?.[0]?.competitors || [];
  if (comps.length < 2) return undefined;
  const byHa = {};
  for (const c of comps) if (c.homeAway) byHa[c.homeAway] = c;
  const away = byHa.away || comps[0];
  const home = byHa.home || comps[1];
  const aLs = away.linescores || [], hLs = home.linescores || [];
  const n = Math.max(aLs.length, hLs.length);
  if (n === 0) return undefined;
  const reg = profile.regulationPeriods || 0;
  // Did the game actually reach a shootout? Hockey only, and ONLY when the header
  // status says so ("Final/SO") — NEVER inferred from "2 extra periods": a playoff
  // 2OT also has 2 extras and must read [..,OT,2OT], not [..,1OT,SO].
  const st = raw.header?.competitions?.[0]?.status?.type || {};
  const wentToShootout = profile.periodUnit === 'period'
    && /\bSO\b|shootout/i.test(`${st.shortDetail || ''} ${st.detail || ''} ${st.description || ''}`);
  const labels = [];
  for (let i = 0; i < n; i++) {
    if (!reg || i < reg) { labels.push(`${i + 1}`); continue; }
    const ex = i - reg; // 0-based index among the extra periods
    if (wentToShootout && i === n - 1) { labels.push('SO'); continue; } // trailing extra is the shootout
    labels.push(ex === 0 ? 'OT' : `${ex + 1}OT`);                       // OT, 2OT, 3OT… (first extra is just "OT")
  }
  const vals = ls => ls.map(x => str(x.displayValue ?? x.value ?? ''));
  return {
    unit: profile.periodUnit,
    labels,
    away: pick({ abbr: away.team?.abbreviation, values: vals(aLs), total: str(away.score) }, ['abbr', 'values', 'total']),
    home: pick({ abbr: home.team?.abbreviation, values: vals(hLs), total: str(home.score) }, ['abbr', 'values', 'total']),
  };
}

// ---- soccer per-player lines (rosters[].roster[].stats) -----------------------
// VERIFIED 2026-07 (fifa.world, live): soccer's per-player numbers ride the lineup
// entries, NOT boxscore.players (empty for soccer) — so buildBoxGroups yields
// nothing and the Box tab had team totals only. Distill the ~14 ESPN stat entries
// (keyed by stat NAME — abbreviations drift) into two glanceable groups: outfield
// and goalkeepers. Only players who actually appeared make a row. Column ORDER is
// deliberate: the app's box table renders the first 5, so the glance set
// (G,A,SH,ST,YC) leads and the tail (RC,FC,FA) rides along for wider surfaces.
const SOCCER_OUTFIELD_COLS = [
  ['G', 'totalGoals'], ['A', 'goalAssists'], ['SH', 'totalShots'], ['ST', 'shotsOnTarget'],
  ['YC', 'yellowCards'], ['RC', 'redCards'], ['FC', 'foulsCommitted'], ['FA', 'foulsSuffered'],
];
const SOCCER_KEEPER_COLS = [['SHF', 'shotsFaced'], ['SV', 'saves'], ['GA', 'goalsConceded']];

function buildRosterBoxGroups(raw, side) {
  const rosters = raw.rosters || [];
  if (!rosters.some(r => (r.roster || []).some(p => Array.isArray(p.stats) && p.stats.length))) return [];
  const groups = [
    { title: 'Players', columns: SOCCER_OUTFIELD_COLS.map(c => c[0]), teams: [] },
    { title: 'Goalkeepers', columns: SOCCER_KEEPER_COLS.map(c => c[0]), teams: [] },
  ];
  for (const r of rosters) {
    const teamSide = r.homeAway || side[String(r.team?.id ?? '')];
    const teamAbbr = r.team?.abbreviation;
    const out = [], gk = [];
    for (const p of (r.roster || [])) {
      const name = aShort(p.athlete) || p.athlete?.displayName;
      const stats = {};
      for (const s of (p.stats || [])) if (s.name) stats[s.name] = str(s.displayValue ?? s.value ?? '');
      const played = p.starter === true || p.subbedIn === true
        || (numOrNull(stats.appearances) ?? 0) > 0;
      if (!name || !played || !Object.keys(stats).length) continue;
      const isKeeper = (p.position?.abbreviation || p.position?.name) === 'G';
      const cols = isKeeper ? SOCCER_KEEPER_COLS : SOCCER_OUTFIELD_COLS;
      (isKeeper ? gk : out).push(pick({
        name, pos: aPos(p.athlete) || p.position?.abbreviation,
        stats: cols.map(([, key]) => stats[key] ?? ''),
      }, ['name', 'pos', 'stats']));
    }
    if (out.length) groups[0].teams.push(pick({ side: teamSide, abbr: teamAbbr, rows: out }, ['side', 'abbr', 'rows']));
    if (gk.length) groups[1].teams.push(pick({ side: teamSide, abbr: teamAbbr, rows: gk }, ['side', 'abbr', 'rows']));
  }
  return groups.filter(g => g.teams.length);
}

// ---- lineups (soccer/rugby) -------------------------------------------------
function buildLineups(raw, side) {
  const rosters = raw.rosters || [];
  if (!rosters.length) return [];
  return rosters.map(r => {
    const players = (r.roster || []).map(p => pick({
      name: aShort(p.athlete) || p.athlete?.displayName,
      pos: p.position?.abbreviation || p.position?.name,
      jersey: p.jersey,
    }, ['name', 'pos', 'jersey'])).filter(p => p.name);
    return pick({
      side: r.homeAway || side[String(r.team?.id ?? '')],
      abbr: r.team?.abbreviation,
      formation: r.formation,
      starters: players.filter((_, i) => (r.roster[i]?.starter === true)),
      bench: players.filter((_, i) => (r.roster[i]?.starter !== true)),
    }, ['side', 'abbr', 'formation', 'starters', 'bench']);
  }).filter(l => (l.starters?.length || l.bench?.length));
}

// ---- season series (head-to-head this season) -------------------------------
// raw.seasonseries[] = [{type:'regular'|'preseason'|'total', summary:'Series tied
// 1-1', seriesScore:'1-1', title, ...}]. A calm one-line "how they've met"; prefer
// a real (non-preseason) series. Already in the /summary payload — free.
function buildSeasonSeries(raw) {
  const ss = raw.seasonseries;
  if (!Array.isArray(ss) || !ss.length) return undefined;
  const pref = ss.find(s => s.type && !/pre/i.test(s.type)) || ss[ss.length - 1];
  const summary = pref?.summary || pref?.description;
  if (!summary) return undefined;
  return pick({ summary: String(summary), score: pref.seriesScore != null ? String(pref.seriesScore) : undefined, title: pref.title }, ['summary', 'score', 'title']);
}

// ---- recent form (last-5) ---------------------------------------------------
// raw.lastFiveGames[] = [{team, events:[{gameResult:'W'|'L'|'T', gameDate, ...}]}].
// Distilled to a per-side form string (newest LAST, matching the cheap-scoreboard
// soccer/rugby `form`), so the detail page can show recent form for MLB/NBA/NFL/NHL
// too. Free — already in the /summary payload.
function buildRecentForm(raw, side) {
  const lf = raw.lastFiveGames;
  if (!Array.isArray(lf) || !lf.length) return undefined;
  const out = lf.map(t => {
    const tid = String(t.team?.id ?? '');
    const evs = (t.events || []).slice()
      .sort((a, b) => (Date.parse(a.gameDate || a.date || 0) || 0) - (Date.parse(b.gameDate || b.date || 0) || 0));
    const form = evs.map(e => String(e.gameResult || '').toUpperCase()).filter(r => /^[WLTD]$/.test(r)).join('');
    return pick({ side: side[tid] || t.team?.homeAway, abbr: t.team?.abbreviation, form }, ['side', 'abbr', 'form']);
  }).filter(x => x.form);
  return out.length ? out : undefined;
}

// ---- injuries (pre-game "key absences") -------------------------------------
// raw.injuries[] = [{team, injuries:[{status, athlete, type, details:{detail,
// returnDate,...}}]}]. We keep ONLY the glanceable structured fields (name /
// position / status / body-part / return) and DROP the long/short comment blurbs
// (those are the news bloat the product excludes). Free — already in /summary.
function buildInjuries(raw, side) {
  const inj = raw.injuries;
  if (!Array.isArray(inj) || !inj.length) return undefined;
  const out = inj.map(block => {
    const tid = String(block.team?.id ?? '');
    const items = (block.injuries || []).map(it => {
      const a = it.athlete;
      return pick({
        name: aShort(a),
        pos: aPos(a),
        status: it.status,                                              // 'Out' | 'Questionable' | 'Day-To-Day' …
        detail: it.details?.detail || it.type?.description || it.details?.type, // body part / nature
        returnDate: it.details?.returnDate,                             // ISO, optional
      }, ['name', 'pos', 'status', 'detail', 'returnDate']);
    }).filter(x => x.name && x.status);
    return pick({ side: side[tid] || block.team?.homeAway, abbr: block.team?.abbreviation, items }, ['side', 'abbr', 'items']);
  }).filter(b => Array.isArray(b.items) && b.items.length);
  return out.length ? out : undefined;
}

// ---- win probability (the single current/final number) ----------------------
// raw.winprobability[] = a per-play arc of {homeWinPercentage(0..1), tiePercentage,
// playId}. We keep ONLY the LAST value (current live / final) — never the 500-point
// curve (that's a chart, off-thesis). Present for NBA/NFL/MLB; ABSENT for NHL/soccer
// (empty array → omitted). It is an ESPN analytic, not a betting line. Free.
function buildWinProbability(raw) {
  const wp = raw.winprobability;
  if (!Array.isArray(wp) || !wp.length) return undefined;
  const last = wp[wp.length - 1];
  const h = typeof last.homeWinPercentage === 'number' ? last.homeWinPercentage : null;
  if (h == null) return undefined;
  const tie = Math.round((typeof last.tiePercentage === 'number' ? last.tiePercentage : 0) * 100);
  const home = Math.round(h * 100);
  const away = Math.max(0, 100 - home - tie);
  return pick({ home, away, tie: tie || undefined }, ['home', 'away', 'tie']);
}

// ---- gridiron drives (raw.drives) --------------------------------------------
// VERIFIED 2026-07: the NFL/CFB summary has ALWAYS carried drives.previous[] (28
// per game, each with nested plays[]) — we just never read it, so gridiron had no
// full play feed while NBA/NHL/MLB did. `previous` is chronological; a live game
// adds `current` (dedupe by id).
function drivesList(raw) {
  const d = raw.drives;
  if (!d || typeof d !== 'object') return [];
  const prev = Array.isArray(d.previous) ? d.previous : [];
  const cur = d.current;
  return (cur && cur.id && !prev.some(x => x.id === cur.id)) ? [...prev, cur] : prev;
}

function buildDrives(raw, side, abbr) {
  const rows = drivesList(raw).map(d => {
    const tid = String(d.team?.id ?? '');
    return pick({
      side: side[tid],
      teamAbbr: abbr[tid] || d.team?.abbreviation,
      description: d.description,
      result: d.displayResult || d.shortDisplayResult || d.result,
      isScore: d.isScore === true ? true : undefined,
      yards: typeof d.yards === 'number' ? d.yards : undefined,
      playCount: typeof d.offensivePlays === 'number' ? d.offensivePlays : undefined,
    }, ['side', 'teamAbbr', 'description', 'result', 'isScore', 'yards', 'playCount']);
  }).filter(d => d.description || d.result);
  return rows.length ? rows : undefined;
}

// ---- full play-by-play (the expandable layer) -------------------------------
// raw.plays[] is the FULL chronological feed (NBA/NHL/MLB). Gridiron nests its
// feed under drives.previous[].plays[] instead — flatten it (tagging each play
// with the drive's offense, since drive plays carry no team of their own) so
// football gets feed parity. Soccer/rugby ship neither: their full feed is
// commentary[] (see buildCommentaryPlays). Same shape as scoringPlays (mapPlay).
// Capped so the rich payload stays bounded; a regulation game is well under the
// cap, so it only trims pathological multi-OT.
function buildPlays(raw, maps) {
  const { side, abbr } = maps;
  let plays = raw.plays;
  if (!Array.isArray(plays) || !plays.length) {
    const drives = drivesList(raw);
    if (drives.length) plays = drives.flatMap(d => (d.plays || []).map(p => (p.team ? p : { ...p, team: d.team })));
  }
  if (!Array.isArray(plays) || !plays.length) return buildCommentaryPlays(raw, maps);
  const mapped = plays.map(p => {
    const m = mapPlay(p, side, abbr);
    m.scoring = p.scoringPlay === true; // per-play, so the app can highlight scores
    return m;
  }).filter(p => p.text);
  // Only worth shipping when there's more than the scoring feed already carries.
  if (mapped.length <= 1) return undefined;
  const CAP = 800;
  return mapped.length > CAP ? mapped.slice(mapped.length - CAP) : mapped;
}

// Soccer/rugby half label from the period number, for when ESPN omits a
// period.displayValue. 3 and 4 (the two extra-time halves) both collapse to a
// single "Extra Time" group; 5 is the shootout. Any other value → undefined
// (the app falls back to an ungrouped list).
function halfLabel(n) {
  return { 1: '1st Half', 2: '2nd Half', 3: 'Extra Time', 4: 'Extra Time', 5: 'Penalties' }[n];
}

// ---- soccer/rugby commentary → the full feed ---------------------------------
// VERIFIED 2026-07 (fifa.world, live): the soccer summary's narrative lives in
// commentary[] — timestamped curated moments (fouls, shots on/off target, corners,
// offsides, VAR, delays), each with a structured play {type, period, clock,
// team:{displayName}}. keyEvents[] carries only goals/cards/subs/bookends (a 0-0
// half is EMPTY after the timeline filter), and the core /plays feed is
// touch-by-touch noise (700+ items by the half — every pass — behind pagination).
// Commentary is the right depth and rides the payload we already fetch. NOTE:
// commentary play.team has NO id/abbreviation — side attribution goes through the
// team display name (sideMaps.nameSide).
function buildCommentaryPlays(raw, { nameSide, haAbbr }) {
  const src = raw.commentary;
  if (!Array.isArray(src) || !src.length) return undefined;
  const mapped = src.slice()
    .sort((a, b) => (numOrNull(a.sequence) ?? 0) - (numOrNull(b.sequence) ?? 0))
    .map(c => {
      const p = c.play || {};
      const side = nameSide[p.team?.displayName];
      return pick({
        period: p.period?.number,
        // Commentary play.period is often just {number}; synthesize the half
        // label so the app can group the full feed by half with no sport switch.
        periodLabel: p.period?.displayValue || halfLabel(p.period?.number),
        clock: c.time?.displayValue || p.clock?.displayValue,
        side,
        teamAbbr: side ? haAbbr[side] : undefined,
        text: c.text || p.text || '',
        away: numOrNull(p.awayScore),
        home: numOrNull(p.homeScore),
        type: p.type?.text,
        scoring: p.scoringPlay === true,
      }, ['period', 'periodLabel', 'clock', 'side', 'teamAbbr', 'text', 'away', 'home', 'type', 'scoring']);
    })
    .filter(p => p.text);
  if (mapped.length <= 1) return undefined;
  const CAP = 800;
  return mapped.length > CAP ? mapped.slice(mapped.length - CAP) : mapped;
}

// ---- attendance + officials (raw.gameInfo) ------------------------------------
// VERIFIED 2026-07 on NFL/soccer/cricket summaries: gameInfo = {venue, attendance,
// officials[]}. Venue already rides the cheap tier; this adds the two calm footer
// facts. Officials capped — soccer sends ref + ARs + 4th official.
function buildGameInfo(raw) {
  const gi = raw.gameInfo;
  if (!gi || typeof gi !== 'object') return {};
  const out = {};
  if (typeof gi.attendance === 'number' && gi.attendance > 0) out.attendance = gi.attendance;
  const officials = (Array.isArray(gi.officials) ? gi.officials : []).map(o => pick({
    name: o.fullName || o.displayName,
    role: o.position?.displayName || o.position?.name,
  }, ['name', 'role'])).filter(o => o.name);
  if (officials.length) out.officials = officials.slice(0, 6);
  return out;
}

// ---- cricket scorecard (raw.matchcards) ---------------------------------------
// VERIFIED 2026-07: matchcards[] rides the SAME site /summary we always fetched
// (fixture trimming had hidden it). Cards are typed by `headline` — 'Batting'
// (playerDetails: dismissal/runs/ballsFaced/fours/sixes + total/extras) and
// 'Bowling' (overs/maidens/conceded/wickets/economyRate) — and paired by
// inningsNumber. 'Partnerships' cards are dropped (depth, not glance). All
// figures arrive as STRINGS; kept as strings.
function buildCricketInnings(raw) {
  const cards = raw.matchcards;
  if (!Array.isArray(cards) || !cards.length) return undefined;
  const byInnings = new Map();
  const slot = n => {
    if (!byInnings.has(n)) byInnings.set(n, { innings: n, battingTeam: '', batting: [], bowling: [] });
    return byInnings.get(n);
  };
  for (const mc of cards) {
    const n = parseInt(mc?.inningsNumber, 10);
    if (!Number.isFinite(n)) continue;
    const rows = Array.isArray(mc.playerDetails) ? mc.playerDetails : [];
    const kind = String(mc.headline || '').toLowerCase();
    if (kind === 'batting') {
      const s = slot(n);
      if (mc.teamName) s.battingTeam = String(mc.teamName);
      const total = [mc.runs, mc.total].filter(v => v != null && v !== '').join(' ');
      if (total) s.total = total;                      // '241 (4 wkts; 43 ovs)'
      if (mc.extras) s.extras = String(mc.extras);
      s.batting = rows.map(r => pick({
        name: r.playerName, dismissal: r.dismissal, runs: r.runs,
        balls: r.ballsFaced, fours: r.fours, sixes: r.sixes,
      }, ['name', 'dismissal', 'runs', 'balls', 'fours', 'sixes'])).filter(r => r.name);
    } else if (kind === 'bowling') {
      const s = slot(n);
      if (mc.teamName) s.bowlingTeam = String(mc.teamName);
      s.bowling = rows.map(r => pick({
        name: r.playerName, overs: r.overs, maidens: r.maidens,
        runs: r.conceded, wickets: r.wickets, economy: r.economyRate,
      }, ['name', 'overs', 'maidens', 'runs', 'wickets', 'economy'])).filter(r => r.name);
    } // partnerships and any future card types: dropped
  }
  const out = [...byInnings.values()]
    .filter(s => s.batting.length || s.bowling.length)
    .sort((a, b) => a.innings - b.innings);
  return out.length ? out : undefined;
}

// ---- top level --------------------------------------------------------------
export function normalizeSummary(reg, key, raw) {
  const profile = resolve(reg, key);
  const maps = sideMaps(raw);
  const { side, abbr } = maps;
  const header = raw.header || {};
  const comp0 = header.competitions?.[0] || {};
  const status = comp0.status?.type || {};
  const lineups = buildLineups(raw, side);
  const periodLines = buildPeriodLines(raw, profile);
  // boxscore.players is the box-score home for most sports; soccer keeps its
  // per-player lines on the lineup entries instead — fall through on data presence.
  const boxGroups = buildBoxGroups(raw, side);
  const out = {
    eventId: String(header.id ?? raw.id ?? ''),
    live: status.state === 'in',
    teamStats: buildTeamStats(raw),
    boxGroups: boxGroups.length ? boxGroups : buildRosterBoxGroups(raw, side),
    scoringPlays: buildScoringPlays(raw, side, abbr),
    lineups,
  };
  if (periodLines) out.periodLines = periodLines;
  // Enrichments that ride this SAME /summary payload (zero extra fetch) — each
  // emitted only when present. See the builders above.
  const seasonSeries = buildSeasonSeries(raw);
  if (seasonSeries) out.seasonSeries = seasonSeries;
  const recentForm = buildRecentForm(raw, side);
  if (recentForm) out.recentForm = recentForm;
  const injuries = buildInjuries(raw, side);
  if (injuries) out.injuries = injuries;
  const winProbability = buildWinProbability(raw);
  if (winProbability) out.winProbability = winProbability;
  // Soccer's curated event feed (goals/cards/subs). When present it's the app's
  // Timeline tab, so the ~700-item ball-by-ball commentary isn't shipped too.
  const timeline = buildMatchTimeline(raw, maps);
  if (timeline) out.timeline = timeline;
  const plays = timeline ? undefined : buildPlays(raw, maps);
  if (plays) out.plays = plays;
  const drives = buildDrives(raw, side, abbr);
  if (drives) out.drives = drives;
  const cricketInnings = buildCricketInnings(raw);
  if (cricketInnings) out.cricketInnings = cricketInnings;
  Object.assign(out, buildGameInfo(raw)); // attendance + officials, when present
  // Pre-game kickoff time → lets the worker shorten the idle cache as the game
  // approaches, so the rich detail flips to live promptly (see ttl.js). Mirrors
  // normalizeScoreboard.nextStartMs; only meaningful while still scheduled.
  if (status.state === 'pre' && comp0.date) {
    const ms = Date.parse(comp0.date);
    if (!Number.isNaN(ms)) out.nextStartMs = ms;
  }
  return out;
}

// ---- MMA card summary ---------------------------------------------------------
// The site /summary 404s for EVERY MMA event (VERIFIED 2026-07: it proxies a
// broken core call), so the MMA rich tier is built from the CORE event instead:
// per-bout status $refs give the structured result (KO/TKO / Submission /
// 'Decision - Unanimous'), and per-competitor linescores give judge totals.
// The route does the fetching (this module stays pure):
//   statuses:   { [boutId]: statusJson }
//   linescores: { [`${boutId}/${competitorId}`]: linescoresJson }
export function normalizeMmaSummary(coreEvent, statuses = {}, linescores = {}) {
  const comps = Array.isArray(coreEvent?.competitions) ? coreEvent.competitions : [];
  const bouts = [];
  let anyLive = false;
  let allPre = comps.length > 0;
  for (const c of comps) {
    const id = String(c.id ?? '');
    if (!id) continue;
    const st = statuses[id];
    const state = st?.type?.state;
    if (state === 'in') anyLive = true;
    if (state !== 'pre') allPre = false;
    const r = st?.result;
    if (!r && state !== 'post') continue; // scheduled bouts carry nothing useful yet
    const bout = pick({
      id,
      result: r?.displayName || r?.name,
      shortResult: r?.shortDisplayName,
      round: typeof st?.period === 'number' && st.period > 0 ? st.period : undefined,
      clock: st?.displayClock && st.displayClock !== '-' ? String(st.displayClock) : undefined,
    }, ['id', 'result', 'shortResult', 'round', 'clock']);
    const judges = (Array.isArray(c.competitors) ? c.competitors : []).map(comp => {
      const ls = linescores[`${id}/${comp.id}`];
      const item = ls?.items?.[0];
      if (!item || !Array.isArray(item.linescores)) return null;
      const totals = item.linescores.slice()
        .sort((a, b) => (a.order ?? 0) - (b.order ?? 0))
        .map(l => l.value).filter(v => typeof v === 'number');
      if (!totals.length) return null;
      return pick({
        competitorId: String(comp.id ?? ''),
        total: typeof item.value === 'number' ? item.value : undefined,
        totals,
      }, ['competitorId', 'total', 'totals']);
    }).filter(Boolean);
    if (judges.length) bout.judges = judges;
    bouts.push(bout);
  }
  const out = {
    eventId: String(coreEvent?.id ?? ''),
    live: anyLive,
    teamStats: [], boxGroups: [], scoringPlays: [], lineups: [],
    bouts,
  };
  // pre-card: expose the start so the route's idle TTL tightens near door-open
  if (!anyLive && allPre && coreEvent?.date) {
    const ms = Date.parse(coreEvent.date);
    if (!Number.isNaN(ms)) out.nextStartMs = ms;
  }
  return out;
}
