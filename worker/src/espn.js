// Upstream fetchers. The ONLY place that talks to ESPN — swap providers here
// without touching the normalizer or the rest of the worker.

const SCOREBOARD = 'https://site.api.espn.com/apis/site/v2/sports/{p}/scoreboard';
const SUMMARY = 'https://site.api.espn.com/apis/site/v2/sports/{p}/summary?event={id}';
// NOTE apis/v2 (not apis/site/v2) — the site path returns only a fullViewLink stub.
const STANDINGS = 'https://site.api.espn.com/apis/v2/sports/{p}/standings';
const TEAMS = 'https://site.api.espn.com/apis/site/v2/sports/{p}/teams';
const TEAM_SCHEDULE = 'https://site.api.espn.com/apis/site/v2/sports/{p}/teams/{id}/schedule';
const RANKINGS = 'https://site.api.espn.com/apis/site/v2/sports/{p}/rankings';

const HEADERS = { 'user-agent': 'sports-scores-worker (+cloudflare)' };

async function get(url) {
  const r = await fetch(url, { headers: HEADERS });
  if (!r.ok) {
    const e = new Error(`upstream ${r.status} for ${url}`);
    e.status = r.status;
    throw e;
  }
  return r.json();
}

/** Scoreboard for a league. Adds the college groups/limit params the API needs. */
export function fetchScoreboard(key, date) {
  let url = SCOREBOARD.replace('{p}', key);
  const qs = new URLSearchParams();
  if (date) qs.set('dates', date);
  if (key.includes('college')) {
    qs.set('limit', '400');
    if (key.includes('basketball')) qs.set('groups', '50'); // all Division I
    if (key.includes('football')) qs.set('groups', '80');   // FBS
  }
  const q = qs.toString();
  if (q) url += '?' + q;
  return get(url);
}

export function fetchSummary(key, eventId) {
  return get(SUMMARY.replace('{p}', key).replace('{id}', eventId));
}

export function fetchStandings(key, season) {
  return get(`${STANDINGS.replace('{p}', key)}?season=${season}`);
}

/** Every team in a league — backs the favorites picker. ESPN paginates this, so
 * widen the limit to pull the whole list in one page (college needs the same
 * groups/limit widening the scoreboard does). */
export function fetchTeams(key) {
  let url = TEAMS.replace('{p}', key);
  const qs = new URLSearchParams();
  if (key.includes('college')) {
    qs.set('limit', '900'); // FBS ~130, D-I hoops ~360 — one page covers either
    if (key.includes('basketball')) qs.set('groups', '50');
    if (key.includes('football')) qs.set('groups', '80');
  } else {
    qs.set('limit', '100'); // pro leagues ≤ ~32 — one page
  }
  url += '?' + qs.toString();
  return get(url);
}

/** One team's season schedule (played + upcoming). Defaults to the current
 * season — exactly what "previous/next game" needs. */
export function fetchTeamSchedule(key, teamId) {
  return get(TEAM_SCHEDULE.replace('{p}', key).replace('{id}', String(teamId)));
}

/** College polls (AP / Coaches / CFP). Defaults to the current week's rankings. */
export function fetchRankings(key) {
  return get(RANKINGS.replace('{p}', key));
}
