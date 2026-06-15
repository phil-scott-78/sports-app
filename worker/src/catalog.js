// /v1/catalog — the app's data-driven league picker. Derived from the registry
// so adding a league to league-profiles.json automatically surfaces it here,
// no app update needed.

import { leagueKeys, resolve } from '../../schema/tools/resolve.mjs';

export function buildCatalog(reg, { priority, sport } = {}) {
  const bySport = {};
  for (const key of leagueKeys(reg, { priority, sport })) {
    const p = reg.leagues[key];
    const prof = resolve(reg, key);
    const [sportKey, league] = key.split('/');
    // Whether ESPN's /teams returns a roster for this league — drives the favorites
    // picker (individual sports like golf/tennis/MMA return []; F1 is the exception,
    // it returns its constructors). Default to "team sports have teams", overridable
    // per-league via a `hasTeams` flag in the registry (e.g. racing/f1: true).
    const hasTeams = prof.hasTeams != null ? !!prof.hasTeams : prof.competitorKind === 'team';
    (bySport[sportKey] ||= []).push({
      key,
      league,
      name: p.name,
      leagueId: p.espnLeagueId,
      abbr: p.abbr,
      region: p.region,
      priority: p.priority,
      hasTeams,
    });
  }
  return Object.entries(bySport).map(([sport, leagues]) => ({ sport, leagues }));
}
