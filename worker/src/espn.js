// Upstream fetchers. The ONLY place that talks to ESPN — swap providers here
// without touching the normalizer or the rest of the worker.

const SCOREBOARD = 'https://site.api.espn.com/apis/site/v2/sports/{p}/scoreboard';
const SUMMARY = 'https://site.api.espn.com/apis/site/v2/sports/{p}/summary?event={id}';
// NOTE apis/v2 (not apis/site/v2) — the site path returns only a fullViewLink stub.
const STANDINGS = 'https://site.api.espn.com/apis/v2/sports/{p}/standings';
const TEAMS = 'https://site.api.espn.com/apis/site/v2/sports/{p}/teams';
const TEAM_SCHEDULE = 'https://site.api.espn.com/apis/site/v2/sports/{p}/teams/{id}/schedule';
const TEAM_ROSTER = 'https://site.api.espn.com/apis/site/v2/sports/{p}/teams/{id}/roster';
const TEAM_STATS = 'https://site.api.espn.com/apis/site/v2/sports/{p}/teams/{id}/statistics';
const RANKINGS = 'https://site.api.espn.com/apis/site/v2/sports/{p}/rankings';
// Core API ({c} = 'golf/leagues/pga'): golf tournament meta + MMA bout statuses.
const CORE_EVENT = 'https://sports.core.api.espn.com/v2/sports/{c}/events/{id}';
// The one web-host endpoint: golf hole-by-hole (VERIFIED 2026-07 — no site twin).
const GOLF_PLAYER_SUMMARY = 'https://site.web.api.espn.com/apis/site/v2/sports/{p}/leaderboard/{event}/playersummary?season={season}&player={player}';

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

/** Standings. OMIT `season` and ESPN returns the CURRENT season — which is what
 * we want by default: `getFullYear()` is wrong mid-year for cross-year leagues
 * (VERIFIED 2026-07: in July 2026 the NHL current season is 2027). Only pass a
 * season when the client explicitly asked for one. */
export function fetchStandings(key, season) {
  const base = STANDINGS.replace('{p}', key);
  return get(season ? `${base}?season=${season}` : base);
}

const corePath = key => key.replace('/', '/leagues/');

/** Follow a core-API $ref. QUIRK: refs sometimes point at the internal
 * `sports.core.api.espn.pvt` host — rewrite to `.com` and force https. */
export function fetchCoreRef(ref) {
  return get(String(ref).replace('espn.pvt', 'espn.com').replace(/^http:/, 'https:'));
}

/** Core event resource. Golf: carries tournament.$ref (cut/major/rounds meta —
 * NOT on the site scoreboard). MMA: the bout list with per-bout status/linescore
 * $refs (the site /summary 404s for MMA, so the rich tier is built from these). */
export function fetchCoreEvent(key, eventId) {
  return get(CORE_EVENT.replace('{c}', corePath(key)).replace('{id}', String(eventId)));
}

/** Golf hole-by-hole player summary (per-hole strokes/par/scoreType, front/back
 * splits, pre-round tee time). Golf seasons are calendar-aligned, so callers may
 * safely default `season` to the current year. */
export function fetchGolfPlayerSummary(key, eventId, season, playerId) {
  return get(GOLF_PLAYER_SUMMARY
    .replace('{p}', key)
    .replace('{event}', String(eventId))
    .replace('{season}', String(season))
    .replace('{player}', String(playerId)));
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

/** One team's roster. VERIFIED 2026-07 (NFL/NBA/MLB/NHL/EPL/college): two
 * shapes, discriminable structurally — a flat `athletes[]` (NBA), or grouped
 * `athletes[{position, items:[…]}]` (NFL/soccer). Backs the team page. */
export function fetchTeamRoster(key, teamId) {
  return get(TEAM_ROSTER.replace('{p}', key).replace('{id}', String(teamId)));
}

/** One team's season statistics. VERIFIED 2026-07: defaults to the CURRENT
 * season (no getFullYear() trap — unlike standings), returns
 * `results.stats.categories[]`; soccer/EPL returns an empty `results:{}` in the
 * offseason, so the caller must tolerate zero categories. */
export function fetchTeamStatistics(key, teamId) {
  return get(TEAM_STATS.replace('{p}', key).replace('{id}', String(teamId)));
}

/** College polls (AP / Coaches / CFP). Defaults to the current week's rankings. */
export function fetchRankings(key) {
  return get(RANKINGS.replace('{p}', key));
}
