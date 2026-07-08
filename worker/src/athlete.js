// athlete.js — the athlete/player profile tier (canonical AthleteProfile;
// SCORES-APP-BUILD-SPEC §2.6 "Player rows"). Pure map→map, no I/O, so it runs in
// Node tests + the Dart port alike. This is the RICH, lazy, on-open detail for one
// player — identity + season stats + a last-N game log — NEVER on the cheap
// scoreboard poll. The caller (api.dart) does the CORE fetches + the $ref fan-out
// and hands this normalizer the already-resolved raws; this file only shapes them.
//
// Inputs (all pre-resolved by the caller):
//   • identity   — the roster row (denser, single-call when arriving from a team)
//                  OR the core athletes/{id} doc. Both share the same field shape.
//   • team       — the resolved team.$ref doc (name/color/logo), or null.
//   • statistics — the resolved athletes/{id}/statistics doc, or null.
//   • games      — [{ eventId, teamId, event, statistics }] — the last-N eventlog
//                  items with their event.$ref + statistics.$ref pre-resolved
//                  (either may be null on a failed resolve). Most-recent first.
//
// EVIDENCE: every path was OBSERVED in schema/espn-guide/core-athletes-id.md /
// -statistics.md / -eventlog.md and verified against a live probe (MLB + WNBA,
// 2026-07). Per-game stat NAMES are inferred in the guide → we bind to whatever the
// split carries, never fabricate. Fields not observed (see §2.6 Gaps) are omitted.

const https = (u) => (typeof u === 'string' ? u.replace(/^http:/, 'https:') : undefined);

// Dark-mode logo: explicit ESPN 'dark' rel when present, else the /500/→/500-dark/
// CDN derivation. Same rule as standings.js / rankings.js (no sport gate).
function darkLogoOf(team) {
  const ls = team?.logos;
  if (Array.isArray(ls)) {
    const d = ls.find((l) => (l.rel || []).includes('dark') && !(l.rel || []).includes('scoreboard'))
      || ls.find((l) => (l.rel || []).includes('dark'));
    if (d?.href) return https(d.href);
  }
  const light = https(ls?.[0]?.href);
  return (light && light.includes('/i/teamlogos/') && light.includes('/500/'))
    ? light.replace('/500/', '/500-dark/')
    : undefined;
}

// headshot.href (or a bare string) → https. Both the roster row and the core doc
// carry `headshot: { href, alt }`.
function headshotOf(o) {
  return https(o?.headshot?.href || o?.headshot);
}

// position.abbreviation (preferred — 'RP'/'G') falling back to displayName. Both
// identity sources carry the same position object.
function positionOf(o) {
  const p = o?.position;
  if (!p || typeof p !== 'object') return undefined;
  return p.abbreviation || p.displayName || undefined;
}

// splits.categories[] → compact [{ name, displayName, stats: [cell] }]. Shared by
// season totals and the per-game line (identical ESPN shape). Drops the verbose
// `description`; keeps only cells with a `name` and a `displayValue`. Categories
// with no usable cells are dropped; returns undefined when nothing survives.
function buildStatCategories(statsDoc) {
  const cats = statsDoc?.splits?.categories;
  if (!Array.isArray(cats) || !cats.length) return undefined;
  const out = [];
  for (const c of cats) {
    const cells = [];
    for (const s of Array.isArray(c?.stats) ? c.stats : []) {
      if (!s || !s.name || s.displayValue == null) continue;
      const cell = { name: String(s.name), displayValue: String(s.displayValue) };
      if (s.abbreviation != null && s.abbreviation !== '') cell.abbreviation = String(s.abbreviation);
      if (s.displayName != null && s.displayName !== '') cell.displayName = String(s.displayName);
      if (s.shortDisplayName != null && s.shortDisplayName !== '') cell.shortDisplayName = String(s.shortDisplayName);
      if (typeof s.value === 'number' && Number.isFinite(s.value)) cell.value = s.value;
      cells.push(cell);
    }
    if (!cells.length) continue;
    const cat = { name: String(c.name || c.abbreviation || ''), stats: cells };
    if (c.displayName != null && c.displayName !== '') cat.displayName = String(c.displayName);
    out.push(cat);
  }
  return out.length ? out : undefined;
}

// One last-N row from a resolved eventlog item. eventId/teamId are already strings
// on the item; date/name/shortName come from the resolved event; the per-game line
// from the resolved statistics. A wholly-unresolved row (no event, no stats) still
// keeps its id so the app can link it.
function buildGameRow(g) {
  if (!g || g.eventId == null) return null;
  const row = { eventId: String(g.eventId) };
  const ev = g.event;
  if (ev && typeof ev === 'object') {
    if (typeof ev.date === 'string' && ev.date) row.date = ev.date;
    if (typeof ev.name === 'string' && ev.name) row.name = ev.name;
    if (typeof ev.shortName === 'string' && ev.shortName) row.shortName = ev.shortName;
  }
  if (g.teamId != null && g.teamId !== '') row.teamId = String(g.teamId);
  const stats = buildStatCategories(g.statistics);
  if (stats) row.stats = stats;
  return row;
}

// team.$ref doc → the athlete's team block. null-safe: no doc → undefined.
function buildTeam(team) {
  if (!team || typeof team !== 'object' || team.id == null) return undefined;
  const out = {
    id: String(team.id),
    name: team.displayName || team.name || team.shortDisplayName || '',
  };
  if (team.abbreviation) out.abbr = String(team.abbreviation);
  if (team.color) out.color = String(team.color);
  const logo = https(team?.logos?.[0]?.href);
  if (logo) out.logo = logo;
  const dark = darkLogoOf(team);
  if (dark) out.logoDark = dark;
  return out;
}

/**
 * Compose a canonical AthleteProfile from the pre-resolved CORE inputs.
 * @param {string} league   the league key (e.g. 'baseball/mlb')
 * @param {string} athleteId
 * @param {object} parts    { identity, team, statistics, games }
 */
export function normalizeAthleteProfile(league, athleteId, parts = {}) {
  const { identity, team, statistics, games } = parts;
  const idn = identity && typeof identity === 'object' ? identity : {};
  const out = {
    id: String(idn.id != null ? idn.id : athleteId),
    league: String(league),
    name: idn.displayName || idn.fullName || idn.shortName || '',
  };
  if (idn.shortName) out.shortName = String(idn.shortName);
  if (idn.jersey != null && idn.jersey !== '') out.jersey = String(idn.jersey);
  const pos = positionOf(idn);
  if (pos) out.position = pos;
  const hs = headshotOf(idn);
  if (hs) out.headshot = hs;
  if (typeof idn.age === 'number' && Number.isFinite(idn.age)) out.age = idn.age;
  if (typeof idn.displayHeight === 'string' && idn.displayHeight) out.height = idn.displayHeight;
  if (typeof idn.displayWeight === 'string' && idn.displayWeight) out.weight = idn.displayWeight;

  const tm = buildTeam(team);
  if (tm) out.team = tm;

  const stats = buildStatCategories(statistics);
  if (stats) out.stats = stats;

  if (Array.isArray(games) && games.length) {
    const rows = games.map(buildGameRow).filter(Boolean);
    if (rows.length) out.lastGames = rows;
  }
  return out;
}
