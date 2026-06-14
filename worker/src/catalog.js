// /v1/catalog — the app's data-driven league picker. Derived from the registry
// so adding a league to league-profiles.json automatically surfaces it here,
// no app update needed.

import { leagueKeys } from '../../schema/tools/resolve.mjs';

export function buildCatalog(reg, { priority, sport } = {}) {
  const bySport = {};
  for (const key of leagueKeys(reg, { priority, sport })) {
    const p = reg.leagues[key];
    const [sportKey, league] = key.split('/');
    (bySport[sportKey] ||= []).push({
      key,
      league,
      name: p.name,
      leagueId: p.espnLeagueId,
      abbr: p.abbr,
      region: p.region,
      priority: p.priority,
    });
  }
  return Object.entries(bySport).map(([sport, leagues]) => ({ sport, leagues }));
}
