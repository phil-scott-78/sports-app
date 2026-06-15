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
  // Pre-game kickoff time → lets the worker shorten the idle cache as the game
  // approaches, so the rich detail flips to live promptly (see ttl.js). Mirrors
  // normalizeScoreboard.nextStartMs; only meaningful while still scheduled.
  if (status.state === 'pre' && comp0.date) {
    const ms = Date.parse(comp0.date);
    if (!Number.isNaN(ms)) out.nextStartMs = ms;
  }
  return out;
}
