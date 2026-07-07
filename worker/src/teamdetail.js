// teamdetail.js — the RICH tier for a team (the /v1/teamdetail route), mirroring
// the scoreboard-vs-summary split for games: the lean /v1/team card is what the
// home feed polls; this is the one-off, slow-moving detail a team page opens.
// Pure (no I/O), like team.js/normalize.js, so it runs in Node tests + the worker
// alike. The schedule reuses the SAME buildEvent() the scoreboard does, and the
// standing reuses normalizeStandings() — team card, detail, and standings never
// fork. Roster/stats discriminate STRUCTURALLY, never on sport name.

import { resolve } from '../../schema/tools/resolve.mjs';
import { buildEvent, https } from './normalize.js';
import { normalizeStandings } from './standings.js';
import { teamIdentityOf } from './team.js';

const titleCase = (s) =>
  String(s || '').replace(/\b\w/g, (c) => c.toUpperCase());

// ---- roster ------------------------------------------------------------------
// VERIFIED 2026-07: ESPN returns EITHER a flat `athletes[]` (NBA/MLB/NHL) OR a
// grouped `athletes[{position, items:[…]}]` (NFL by offense/defense/specialTeam,
// soccer by position group). Discriminate by the presence of `items[]` — never by
// sport name. Anything unrecognized degrades to one "Roster" group / [].
function mapAthlete(a) {
  const o = {
    id: String(a.id ?? ''),
    name: a.displayName || a.fullName || a.shortName || '',
  };
  if (a.jersey != null && a.jersey !== '') o.jersey = String(a.jersey);
  if (a.position?.abbreviation) o.position = a.position.abbreviation;
  const hs = https(a.headshot?.href || a.headshot);
  if (hs) o.headshot = hs;
  return o;
}

function buildRoster(roster) {
  const athletes = roster?.athletes;
  if (!Array.isArray(athletes) || !athletes.length) return [];
  const grouped = athletes.some((e) => Array.isArray(e.items));
  if (grouped) {
    return athletes
      .filter((g) => Array.isArray(g.items) && g.items.length)
      .map((g) => ({
        name: titleCase(g.position || g.name || 'Group'),
        athletes: g.items.map(mapAthlete).filter((a) => a.id),
      }))
      .filter((g) => g.athletes.length);
  }
  return [{ name: 'Roster', athletes: athletes.map(mapAthlete).filter((a) => a.id) }];
}

// ---- season stats ------------------------------------------------------------
// results.stats.categories[] → TeamStatGroup[]. When the family curates
// `teamStatKeys` (registry), collapse to ONE ordered group of just those keys
// (mirrors standingsColumns curation); else keep the natural categories, capped.
// VERIFIED 2026-07: values arrive as strings/numbers; EPL ships an empty
// `results:{}` in the offseason → [].
function mapStat(s) {
  const value = s.displayValue ?? (s.value != null ? String(s.value) : undefined);
  if (value == null) return null;
  const o = {
    name: s.name || s.abbreviation || '',
    label: s.shortDisplayName || s.displayName || s.name || '',
    value: String(value),
  };
  if (s.abbreviation) o.abbr = s.abbreviation;
  if (typeof s.rank === 'number') o.rank = s.rank;
  return o;
}

function buildStats(profile, stats) {
  const cats = stats?.results?.stats?.categories;
  if (!Array.isArray(cats) || !cats.length) return [];
  const keys = profile.teamStatKeys;
  if (Array.isArray(keys) && keys.length) {
    const byName = {};
    for (const c of cats) for (const s of c.stats || []) {
      if (s?.name && byName[s.name] == null) byName[s.name] = s;
    }
    const picked = keys.map((k) => byName[k]).filter(Boolean).map(mapStat).filter(Boolean);
    return picked.length ? [{ name: 'Season', stats: picked }] : [];
  }
  return cats
    .map((c) => ({
      name: c.displayName || c.name || '',
      stats: (c.stats || []).slice(0, 8).map(mapStat).filter(Boolean),
    }))
    .filter((g) => g.stats.length);
}

// ---- standing (this team's group only) --------------------------------------
// Run the shared standings normalizer, then pluck the group that contains this
// teamId → { groupName, rows }. Omitted when the team isn't found (a national
// team, or an athlete-shaped racing table where no team id matches — but team
// pages are gated on competitorKind==='team' upstream anyway).
function pluckStanding(profile, standingsRaw, teamId) {
  if (!standingsRaw) return undefined;
  const groups = normalizeStandings(standingsRaw);
  const id = String(teamId);
  for (const g of groups) {
    if (g.rows.some((r) => r.team.id === id)) {
      // carry the family's preferred columns (as /v1/standings does) so the team
      // page renders W/L/PCT labels, not raw ESPN stat keys — no extra fetch.
      return { groupName: g.name, columns: profile.standingsColumns || null, rows: g.rows };
    }
  }
  return undefined;
}

// ---- top level ---------------------------------------------------------------
export function normalizeTeamDetail(reg, key, teamId, parts = {}) {
  const { schedule, roster, stats, standingsRaw } = parts;
  const profile = resolve(reg, key);
  const team = teamIdentityOf(profile, schedule?.team, teamId);

  // Full season schedule, normalized through the SAME builder as the scoreboard,
  // start-ascending so the client can slice "last N / next N".
  const events = (schedule?.events || []).map((e) => buildEvent(profile, e));
  events.sort((a, b) => (Date.parse(a.start) || 0) - (Date.parse(b.start) || 0));

  const out = {
    league: key,
    sport: profile.espnSport,
    leagueName: profile.name || key.split('/')[1] || '',
    team,
    schedule: events,
    roster: buildRoster(roster),
    stats: buildStats(profile, stats),
  };
  const standing = pluckStanding(profile, standingsRaw, teamId);
  if (standing) out.standing = standing;
  return out;
}
