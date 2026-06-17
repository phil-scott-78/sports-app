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
function sideMaps(raw) {
  const comps = raw.header?.competitions?.[0]?.competitors || [];
  const side = {}, abbr = {};
  for (const c of comps) {
    const id = String(c.id ?? c.team?.id ?? '');
    if (!id) continue;
    if (c.homeAway) side[id] = c.homeAway;
    const a = c.team?.abbreviation; if (a) abbr[id] = a;
  }
  return { side, abbr, comps };
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
  let src = [];
  if (Array.isArray(raw.scoringPlays) && raw.scoringPlays.length) {
    src = raw.scoringPlays; // NFL
  } else if (Array.isArray(raw.plays) && raw.plays.length) {
    src = raw.plays.filter(p => p.scoringPlay === true); // MLB/NBA/NHL
  } else if (Array.isArray(raw.keyEvents) && raw.keyEvents.length) {
    src = raw.keyEvents.filter(p => p.scoringPlay === true || SOCCER_KEEP.test(p.type?.text || '')); // soccer
  }
  const out = src.map(p => mapPlay(p, side, abbr)).filter(p => p.text);
  // Tidy soccer substitution text; leaves every other play's text untouched.
  for (const p of out) {
    if (/substitution/i.test(p.type || '')) p.text = cleanSubText(p.text);
  }
  return out.length > 120 ? out.slice(0, 120) : out;
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

// ---- full play-by-play (the expandable layer) -------------------------------
// raw.plays[] is the FULL chronological feed (NBA/NHL/MLB). The detail page shows
// the condensed scoring feed (scoringPlays) by default and expands into THIS. Same
// shape as scoringPlays (mapPlay). Capped so the rich payload stays bounded; a
// regulation game is well under the cap, so it only trims pathological multi-OT.
function buildPlays(raw, side, abbr) {
  const plays = raw.plays;
  if (!Array.isArray(plays) || !plays.length) return undefined;
  const mapped = plays.map(p => mapPlay(p, side, abbr)).filter(p => p.text);
  // Only worth shipping when there's more than the scoring feed already carries.
  if (mapped.length <= 1) return undefined;
  const CAP = 800;
  return mapped.length > CAP ? mapped.slice(mapped.length - CAP) : mapped;
}

// ---- top level --------------------------------------------------------------
export function normalizeSummary(reg, key, raw) {
  const profile = resolve(reg, key);
  const { side, abbr } = sideMaps(raw);
  const header = raw.header || {};
  const comp0 = header.competitions?.[0] || {};
  const status = comp0.status?.type || {};
  const lineups = buildLineups(raw, side);
  const periodLines = buildPeriodLines(raw, profile);
  const out = {
    eventId: String(header.id ?? raw.id ?? ''),
    live: status.state === 'in',
    teamStats: buildTeamStats(raw),
    boxGroups: buildBoxGroups(raw, side),
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
  const plays = buildPlays(raw, side, abbr);
  if (plays) out.plays = plays;
  // Pre-game kickoff time → lets the worker shorten the idle cache as the game
  // approaches, so the rich detail flips to live promptly (see ttl.js). Mirrors
  // normalizeScoreboard.nextStartMs; only meaningful while still scheduled.
  if (status.state === 'pre' && comp0.date) {
    const ms = Date.parse(comp0.date);
    if (!Number.isNaN(ms)) out.nextStartMs = ms;
  }
  return out;
}
