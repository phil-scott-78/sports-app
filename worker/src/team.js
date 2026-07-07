// team.js — raw ESPN team endpoints → canonical favorite-team shapes. Pure
// functions (no I/O), like normalize.js, so they run in Node tests and the
// worker alike. Reuses normalize.js's per-event builder so team games are
// normalized through the EXACT same path as the scoreboard — no fork.

import { resolve } from '../../schema/tools/resolve.mjs';
import { normalizeScoreboard, buildEvent, https, darkLogoOf } from './normalize.js';

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

// ---- shared team identity block ---------------------------------------------
// The card/detail identity, built once from the (schedule.team) block so the
// favorite card and the team-detail page can never fork. `t` is the raw ESPN
// team object; VERIFIED (schedule.team): logo is a STRING (not a logos[] array),
// recordSummary + standingSummary are STRINGS ('46-36', '2nd in AL East').
export function teamIdentityOf(profile, t, teamId) {
  t = t || {};
  const light = https(t.logo || t.logos?.[0]?.href);
  const team = {
    id: String(t.id ?? teamId),
    displayName: t.displayName || t.name || '',
    abbreviation: t.abbreviation || undefined,
    record: t.recordSummary || undefined,
    standingSummary: t.standingSummary || undefined, // absent for national teams
  };
  if (light) {
    team.logo = light;
    const d = darkLogoOf(t, light, profile.espnSport);
    if (d) team.logoDark = d;
  }
  if (t.color) team.color = t.color;
  return team;
}

// ---- team card (live / last / next) -----------------------------------------
// ESPN team schedule: { team:{ id, displayName, abbreviation, color, logo,
// recordSummary, standingSummary, ... }, events:[ <scoreboard-shaped events> ] }.
export function normalizeTeamCard(reg, key, teamId, schedule) {
  const profile = resolve(reg, key);

  const team = teamIdentityOf(profile, schedule?.team, teamId);

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

// ---- scoreboard fallback (national teams / tournaments) ----------------------
// ESPN's team-schedule endpoint returns events:[] for national teams and many
// tournament squads (their fixtures live under other ESPN league ids), and a club's
// in-progress game can also lag behind the live scoreboard. So when the schedule
// gave us NO live game, backfill the card from the league scoreboard — the exact
// same canonical slate the Scores feed renders — picking the competition that
// involves this team. Pure: takes the raw scoreboard, returns a patched card.
export function applyScoreboardFallback(reg, key, teamId, card, sb) {
  const norm = normalizeScoreboard(reg, key, sb);
  const id = String(teamId);
  const compFor = ev => ev.competitions.find(c => c.competitors.some(x => x.id === id));
  const mine = norm.events.filter(ev => compFor(ev));
  if (!mine.length) return card;

  let { live, last, next } = card;
  for (const ev of mine) {
    const c = compFor(ev);
    const ms = Date.parse(ev.start) || 0;
    const ph = c.status.phase;
    if (ph === 'live') {
      if (!live || (Date.parse(live.start) || 0) > ms) live = ev;            // earliest-started live
    } else if (c.status.ended || ph === 'final') {
      if (!last || (Date.parse(last.start) || 0) < ms) last = ev;            // most-recent ended
    } else if (ph === 'scheduled') {
      if (!next || (Date.parse(next.start) || 0) > ms) next = ev;            // earliest upcoming
    }
  }

  // Fill team identity from the scoreboard competitor when the (empty) schedule
  // gave us none — otherwise the card header renders blank.
  let team = card.team;
  if (!team.displayName || !team.logo) {
    const ev = live || last || next;
    const me = ev && compFor(ev)?.competitors.find(x => x.id === id);
    if (me) team = {
      ...team,
      displayName: team.displayName || me.displayName,
      abbreviation: team.abbreviation || me.abbreviation,
      logo: team.logo || me.logo,
      logoDark: team.logoDark || me.logoDark,
      color: team.color || me.color,
    };
  }

  return { ...card, team, live, last, next, anyLive: live != null };
}
