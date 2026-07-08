// teamleaders.js — the TEAM LEADERS tier (canonical TeamLeaders; SCORES-APP-BUILD-
// SPEC §2.6 "TEAM LEADERS row"). Pure map→map, no I/O — runs in Node tests + the
// Dart port alike. The RICH, lazy, on-team-page-open season leaders for one team:
// the top player per stat category. NEVER on the cheap scoreboard poll (that carries
// the cheaper per-GAME competitors[].leaders glance).
//
// The caller (api.dart) fetches the CORE leaders doc, caps the category fan-out, and
// resolves each unique athlete.$ref ONCE (cached); this file only shapes the
// already-resolved raws.
//
// Inputs:
//   • raw       — the CORE .../types/{t}/teams/{id}/leaders doc:
//                 { categories:[{ name, displayName, shortDisplayName, abbreviation,
//                   leaders:[{ value, displayValue, athlete:{ $ref } }] }] }
//   • athletes  — map athleteId → the resolved athlete doc ({ displayName, headshot,
//                 position, ... }), keyed by the id parsed from the athlete.$ref.
//
// EVIDENCE: every path OBSERVED in schema/espn-guide/core-season-types-id-teams-id-
// leaders.md (categories[].leaders[].{value,displayValue,athlete.$ref}, 100% across
// 8 sports). A category whose top leader has no resolvable name is DROPPED (never
// faked); ~6 categories surface (the caller's cap, mirrored here for safety).

const https = (u) => (typeof u === 'string' ? u.replace(/^http:/, 'https:') : undefined);

const MAX_CATEGORIES = 6;

// athlete id from a `.../athletes/{id}?...` $ref (the same key the caller resolves by).
export function athleteIdFromRef(ref) {
  if (typeof ref !== 'string') return undefined;
  const m = /\/athletes\/(\d+)/.exec(ref);
  return m ? m[1] : undefined;
}

// headshot.href (or a bare string) → https. Same shape as athlete.js.
function headshotOf(o) {
  return https(o?.headshot?.href || o?.headshot);
}

function positionOf(o) {
  const p = o?.position;
  if (!p || typeof p !== 'object') return undefined;
  return p.abbreviation || p.displayName || undefined;
}

/**
 * Compose canonical TeamLeaders from the CORE leaders doc + a resolved-athlete map.
 * @param {string} league
 * @param {string|number} teamId
 * @param {object} raw       the leaders doc
 * @param {object} athletes  athleteId → resolved athlete doc
 */
export function normalizeTeamLeaders(league, teamId, raw, athletes = {}) {
  const out = { league: String(league), teamId: String(teamId), categories: [] };
  const cats = raw?.categories;
  if (!Array.isArray(cats) || !cats.length) return out;
  const map = athletes && typeof athletes === 'object' ? athletes : {};
  for (const c of cats) {
    if (out.categories.length >= MAX_CATEGORIES) break;
    const leaders = Array.isArray(c?.leaders) ? c.leaders : [];
    const top = leaders[0];
    if (!top) continue;
    const aid = athleteIdFromRef(top?.athlete?.$ref);
    if (!aid) continue;
    const ath = map[aid];
    const name = ath?.displayName || ath?.fullName || ath?.shortName;
    if (!name) continue; // can't show a leader with no resolvable name — drop it
    const dv = top.displayValue != null ? top.displayValue
      : (top.value != null ? top.value : '');
    const row = {
      name: String(c.name || ''),
      label: String(c.shortDisplayName || c.displayName || c.abbreviation || c.name || ''),
      athleteId: String(aid),
      athlete: String(name),
      displayValue: String(dv),
    };
    const pos = positionOf(ath);
    if (pos) row.position = String(pos);
    const hs = headshotOf(ath);
    if (hs) row.headshot = hs;
    out.categories.push(row);
  }
  return out;
}
