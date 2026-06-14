// team.js — raw ESPN team endpoints → canonical favorite-team shapes. Pure
// functions (no I/O), like normalize.js, so they run in Node tests and the
// worker alike. Reuses normalize.js's per-event builder so team games are
// normalized through the EXACT same path as the scoreboard — no fork.

import { resolve } from '../../schema/tools/resolve.mjs';
import { buildEvent, https, darkLogoOf } from './normalize.js';

// ---- teams list (the favorites picker) --------------------------------------
// ESPN: { sports:[{ leagues:[{ teams:[{ team:{...} }] }] }] }
export function normalizeTeams(reg, key, raw) {
  const profile = resolve(reg, key);
  const teams = raw?.sports?.[0]?.leagues?.[0]?.teams ?? [];
  return teams
    .map(({ team: t }) => {
      if (!t) return null;
      const light = https(t.logo || t.logos?.[0]?.href);
      const out = {
        id: String(t.id ?? ''),
        displayName: t.displayName || t.name || t.shortDisplayName || '',
        abbreviation: t.abbreviation || undefined,
      };
      if (light) {
        out.logo = light;
        const d = darkLogoOf(t, light, profile.espnSport); // logos[] may carry an explicit dark rel
        if (d) out.logoDark = d;
      }
      if (t.color) out.color = t.color;
      return out;
    })
    .filter(t => t && t.id)
    .sort((a, b) => a.displayName.localeCompare(b.displayName));
}

// ---- team card (live / last / next) -----------------------------------------
// ESPN team schedule: { team:{ id, displayName, abbreviation, color, logo,
// recordSummary, ... }, events:[ <scoreboard-shaped events> ] }.
export function normalizeTeamCard(reg, key, teamId, schedule) {
  const profile = resolve(reg, key);

  // identity — schedule.team carries logo as a STRING and recordSummary as a STRING
  const t = schedule?.team || {};
  const light = https(t.logo || t.logos?.[0]?.href);
  const team = {
    id: String(t.id ?? teamId),
    displayName: t.displayName || t.name || '',
    abbreviation: t.abbreviation || undefined,
    record: t.recordSummary || undefined,
  };
  if (light) {
    team.logo = light;
    const d = darkLogoOf(t, light, profile.espnSport);
    if (d) team.logoDark = d;
  }
  if (t.color) team.color = t.color;

  // every scheduled event normalized through the shared builder
  const events = (schedule?.events || []).map(e => buildEvent(profile, e));

  let live = null, last = null, next = null;
  for (const ev of events) {
    const c = ev.competitions[0];
    if (!c) continue;
    const ms = Date.parse(ev.start) || 0;
    const ph = c.status.phase;
    if (ph === 'live') {
      if (!live || (Date.parse(live.start) || 0) > ms) live = ev;     // earliest-started live
    } else if (c.status.ended || ph === 'final') {
      if (!last || (Date.parse(last.start) || 0) < ms) last = ev;     // most-recent ended
    } else if (ph === 'scheduled') {
      if (!next || (Date.parse(next.start) || 0) > ms) next = ev;     // earliest upcoming
    }
    // postponed / canceled / suspended / unknown → not surfaced
  }

  return {
    league: key,
    sport: profile.espnSport,
    leagueName: profile.name || key.split('/')[1] || '',
    team,
    live,
    last,
    next,
    anyLive: live != null,
  };
}
