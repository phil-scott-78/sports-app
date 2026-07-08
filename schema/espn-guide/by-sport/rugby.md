# ESPN API — rugby

> Per-sport slice of the [observed data guide](../index.md): what ESPN actually serves for **rugby**, and which endpoint answers each need. Built from 137 real rugby responses — OBSERVED live, not documented. Regenerate: `node schema/tools/rollup.mjs`.

## Leagues — 26 in the registry

Competition **shape** drives rendering (see the discriminators in `schema/canonical.ts`): `layout · scoreKind · competitorKind`.

| shape (layout · scoreKind · competitorKind) | leagues | examples |
|---|---|---|
| `headToHead · numeric · team` | 26 | `180659`, `164205`, `242041`, `270559` |

**Crawled for this guide** (2): `rugby/164205`, `rugby/180659`. The evidence below is from these leagues; other rugby leagues in the registry inherit the same shape.

## Which endpoint to use

URL templates use `rugby/164205` as a representative league. Swap in any league key from the table above.

| need | endpoint | status | URL template | fields |
|---|---|---|---|---|
| Scores & live state | `scoreboard` | ✅ 28/28 | `https://site.api.espn.com/apis/site/v2/sports/rugby/164205/scoreboard` | [guide](../scoreboard.md) |
| Rich game detail | `summary` | ✅ 6/6 | `https://site.api.espn.com/apis/site/v2/sports/rugby/164205/summary?event={eventId}` | [guide](../summary.md) |
| League table | `standings` | ✅ 4/4 | `https://site.api.espn.com/apis/v2/sports/rugby/164205/standings` | [guide](../standings.md) |
| Team directory | `teams` | ✅ 2/2 | `https://site.api.espn.com/apis/site/v2/sports/rugby/164205/teams` | [guide](../teams.md) |
| Roster | `team-roster` | ✅ 4/4 | `https://site.api.espn.com/apis/site/v2/sports/rugby/164205/teams/{teamId}/roster` | [guide](../team-roster.md) |
| Schedule | `team-schedule` | ❌ not served | `https://site.api.espn.com/apis/site/v2/sports/rugby/164205/teams/{teamId}/schedule` | [guide](../team-schedule.md) |
| Team season stats | `team-stats` | ❌ not served | `https://site.api.espn.com/apis/site/v2/sports/rugby/164205/teams/{teamId}/statistics` | [guide](../team-stats.md) |
| News | `news` | ✅ 2/2 | `https://site.api.espn.com/apis/site/v2/sports/rugby/164205/news?limit=5` | [guide](../news.md) |
| Injuries | `injuries` | ✅ 2/2 | `https://site.api.espn.com/apis/site/v2/sports/rugby/164205/teams/{teamId}/injuries` | [guide](../injuries.md) |

- **scoreboard** — The cheap poll — scores, status, line scores, and (situationally) situation, leaders, records, odds. The primary call. College needs `?groups=<id>&limit=400`; `?dates=YYYYMMDD-YYYYMMDD` for a range (cricket: single day only).
- **summary** — One extra fetch when a game is opened — box scores, scoring plays, rosters, penalty shootouts, method of victory. A 404 for the whole sport means this tier does not exist (build detail from the core graph instead).
- **standings** — ⚠ `apis/v2`, NOT `apis/site/v2` (the site path returns a `{fullViewLink}` stub). Omit `?season=` — ESPN defaults to the current season.
- **teams** — Team ids, names, abbreviations, logos, colors. The id feeds the roster/schedule/stats/injuries calls.
- **team-roster** — Per-team roster with positions and headshots.
- **team-schedule** — Per-team schedule, past results + upcoming fixtures. _(every attempt 404/400 — this tier does not exist for the sport)_
- **team-stats** — Per-team season statistics. _(every attempt 404/400 — this tier does not exist for the sport)_
- **news** — Latest articles for the league.
- **injuries** — Per-team injury report.

## Core API — `sports.core.api.espn.com`

53 of the core resource shapes were reachable for rugby by following `$ref` links from the league root and its events (full matrix: [index.md](../index.md#core-api-resource-graph)). High-value shapes:

| resource | reachable | what it adds |
|---|---|---|
| `core-competitor-linescores` | ✅ | Per-period / per-set / per-inning scores — reachable even when the site scoreboard omits them (tennis sets, cricket innings). |
| `core-situation` | ✅ | Live game situation (baseball base/out, gridiron down & distance). |
| `core-plays` | ✅ | Play-by-play feed. |
| `core-competition-plays-id` | ✅ | Individual play detail. |
| `core-odds` | ✅ | Betting lines / odds. |
| `core-competitor-roster` | ✅ | Game-day lineup. |
| `core-competitor-statistics` | ✅ | Competitor's game statistics. |
| `core-rankings` | ✅ | Rankings through the core graph. |
| `core-athlete` | ✅ | Athlete bio / profile. |

## What's sport-specific in the data

Value-bearing fields observed for rugby that are **not** near-universal — the sport's fingerprint. **presence** = % of this sport's crawled responses (or parent objects) that carry the field (rugby-specific). Field paths, types, and presence are rugby-only; the **value/example samples are pooled** across the handful of sports that share a field (a nested `period` may show golf's "18" next to a fight's "1–3"), so read them as shape hints. The full per-sport field tables live in the per-endpoint guides linked above.

### scoreboard

| field | type | presence | values / examples |
|---|---|---|---|
| `leagues[].isClubCompetition` | boolean | 100% | values: true (28), false (14) |
| `events[].competitions[].details[].athletesInvolved[].position` | string | 96% | e.g. "SUB", "F", "LM", "RM" |
| `events[].competitions[].competitors[].form` | string | 100% | e.g. "WLLLW", "LWLWW", "LLLLL", "LWWLL" |
| `events[].competitions[].details[].athletesInvolved[].displayName` | string | 100% | e.g. "Tijjani Noslin", "Jérémy Doku", "Kingsley Ehizibue", "Matteo Politano" |
| `events[].competitions[].details[].athletesInvolved[].fullName` | string | 100% | e.g. "Tijjani Noslin", "Jérémy Doku", "Kingsley Ehizibue", "Matteo Politano" |
| `events[].competitions[].details[].athletesInvolved[].id` | str-numeric | 100% | e.g. "323113", "283672", "212476", "188306" |
| `events[].competitions[].details[].athletesInvolved[].shortName` | string | 100% | e.g. "T. Noslin", "J. Doku", "K. Ehizibue", "M. Politano" |
| `events[].competitions[].details[].clock.displayValue` | string | 100% | e.g. "29'", "50'", "26'", "25'" |
| `events[].competitions[].details[].clock.value` | number | 100% | e.g. 5400, 2700, 4375, 2393 |
| `events[].competitions[].details[].team.id` | str-numeric | 100% | e.g. "289203", "289199", "289196", "289195" |
| `events[].competitions[].details[].type.id` | str-numeric | 100% | e.g. "94", "70", "7", "8" |
| `events[].competitions[].details[].type.text` | string | 100% | e.g. "Yellow Card", "Goal", "player substituted", "substitute on" |
| `events[].competitions[].competitors[].statistics[].abbreviation` | string | 100% | e.g. "PTS", "REB", "AST", "A" |
| `events[].competitions[].competitors[].statistics[].displayValue` | str-numeric | 100% | e.g. "0", "1", "2", "3" |
| `events[].competitions[].competitors[].statistics[].name` | string | 100% | e.g. "assists", "points", "appearances", "foulsCommitted" |

### summary

| field | type | presence | values / examples |
|---|---|---|---|
| `boxscore.players[].statistics[].athletes[].athlete.nickname` | string | 14% | e.g. "Stuart", "Jamison", "Josh", "Jack" |
| `boxscore.players[].statistics[].abbreviation` | string | 100% | values: "gen" (14) |
| `boxscore.players[].statistics[].athletes[].athlete.displayHeight` | string | 100% | e.g. "6' 0"", "6' 2"", "6' 3"", "5' 10"" |
| `boxscore.players[].statistics[].athletes[].athlete.displayWeight` | string | 100% | e.g. "231 lbs", "211 lbs", "242 lbs", "238 lbs" |
| `boxscore.players[].statistics[].athletes[].athlete.height` | number | 100% | e.g. 72.04724409448819, 72.83464566929133, 74.01574803149606, 75.19685039370079 |
| `boxscore.players[].statistics[].athletes[].athlete.linked` | boolean | 100% | values: true (316) |
| `boxscore.players[].statistics[].athletes[].athlete.slug` | string | 100% | e.g. "jack-crowley", "joe-mccarthy", "jamie-osborne", "michael-milne" |
| `boxscore.players[].statistics[].athletes[].athlete.status.abbreviation` | string | 100% | values: "Active" (254), "Inactive" (1) |
| `boxscore.players[].statistics[].athletes[].athlete.status.id` | str-numeric | 100% | values: "1" (254), "2" (1) |
| `boxscore.players[].statistics[].athletes[].athlete.status.name` | string | 100% | values: "Active" (254), "Inactive" (1) |
| `boxscore.players[].statistics[].athletes[].athlete.status.type` | string | 100% | values: "active" (254), "inactive" (1) |
| `boxscore.players[].statistics[].athletes[].athlete.type` | string | 100% | values: "rugby" (184), "rugby-league" (132) |
| `boxscore.players[].statistics[].athletes[].athlete.weight` | number | 100% | e.g. 231.48537529412147, 211.64377169748246, 242.50848840336533, 238.0992431596678 |
| `boxscore.players[].statistics[].athletes[].statistics[].abbreviation` | string | 100% | values: "gen" (316) |
| `boxscore.players[].statistics[].athletes[].statistics[].displayName` | string | 100% | values: "General" (316) |
| `boxscore.players[].statistics[].athletes[].statistics[].name` | string | 100% | values: "general" (316) |
| `boxscore.players[].statistics[].athletes[].statistics[].shortDisplayName` | string | 100% | values: "General" (316) |
| `boxscore.players[].statistics[].athletes[].statistics[].stats[].abbreviation` | string | 100% | e.g. "T", "MT", "P", "CB" |
| `boxscore.players[].statistics[].athletes[].statistics[].stats[].description` | string | 100% | e.g. "", "Clean Breaks", "Conversion Goals", "Drop Goals Converted" |
| `boxscore.players[].statistics[].athletes[].statistics[].stats[].displayName` | string | 100% | e.g. "Clean Breaks", "Conversion Goals", "Drop Goals Converted", "Kicks" |
| `boxscore.players[].statistics[].athletes[].statistics[].stats[].displayValue` | str-numeric | 100% | e.g. "0", "1", "0.000", "2" |
| `boxscore.players[].statistics[].athletes[].statistics[].stats[].name` | string | 100% | e.g. "cleanBreaks", "conversionGoals", "dropGoalsConverted", "kicks" |
| `boxscore.players[].statistics[].athletes[].statistics[].stats[].shortDisplayName` | string | 100% | e.g. "T", "MT", "P", "CB" |
| `boxscore.players[].statistics[].athletes[].statistics[].stats[].type` | string | 100% | e.g. "kicks", "metres", "offload", "passes" |
| `boxscore.players[].statistics[].athletes[].statistics[].stats[].value` | number | 100% | e.g. 0, 1, 2, 3 |
| `boxscore.players[].statistics[].athletes[].statistics[].summary` | string | 100% | values: "" (316) |
| `boxscore.players[].statistics[].displayName` | string | 100% | values: "General" (14) |
| `boxscore.players[].statistics[].shortDisplayName` | string | 100% | values: "General" (14) |
| `boxscore.players[].statistics[].summary` | string | 100% | values: "" (14) |
| `boxscore.teams[].statistics[].shortDisplayName` | string | 100% | values: "General" (14) |
| `boxscore.teams[].statistics[].stats[].type` | string | 100% | e.g. "kicks", "metres", "offload", "passes" |
| `boxscore.teams[].statistics[].summary` | string | 100% | values: "" (14) |
| `hasOdds` | boolean | 100% | values: false (28), true (6) |
| `header.competitions[].details[].awayScore` | number | 100% | e.g. 0, 10, 4, 27 |
| `header.competitions[].details[].homeScore` | number | 100% | e.g. 19, 12, 6, 17 |
| `header.competitions[].details[].period.number` | number | 100% | values: 1 (97), 2 (78) |
| `header.competitions[].details[].sequenceNumber` | str-numeric | 100% | values: "0" (175) |
| `header.competitions[].details[].type.id` | str-numeric | 100% | values: "7" (52), "8" (47), "1" (38), "2" (29), "5" (4), "3" (4), "4" (1) |
| `header.competitions[].details[].type.text` | string | 100% | values: "player substituted" (52), "substitute on" (47), "try" (38), "conversion" (29), "yellow card" (4), "penalty goal" (4), "drop goal" (1) |
| `rosters[].roster[].stats[].type` | string | 100% | e.g. "metres", "offload", "passes", "points" |
| `standings.children[].shortName` | string | 100% | values: "Six Nations" (4), "Round-Robin" (4), "Pool A" (2), "Pool B" (2), "Pool C" (2), "Pool D" (2) |
| `standings.children[].standings.seasonDisplayName` | str-numeric | 100% | values: "2026" (8), "2023" (8) |
| `standings.season.displayName` | str-numeric | 100% | values: "2027" (6), "2026" (4) |
| `boxscore.players[].statistics[].athletes[].athlete.birthPlace.country` | string | 49% | values: "Australia" (63), "Ireland" (23), "New Zealand" (20), "Wales" (20), "England" (15), "Scotland" (13), "France" (6), "Italy" (5), "South Africa" (2), "Canada" (1), "New Caledonia" (1), "Papua New Guinea" (1), "Tonga" (1), "Fiji" (1) |
| `boxscore.players[].statistics[].athletes[].athlete.birthPlace.city` | string | 34% | e.g. "Sydney", "Dublin", "Auckland", "Swansea" |
| `boxscore.players[].statistics[].athletes[].athlete.firstName` | string | 100% | e.g. "Jack", "Ryan", "Joe", "Anthony" |
| `boxscore.teams[].statistics[].displayName` | string | 100% | values: "General" (14), "Batting" (8), "Pitching" (8), "Fielding" (8), "Records" (8) |
| `boxscore.teams[].statistics[].stats[].abbreviation` | string | 100% | e.g. "P", "R", "MT", "GP" |
| `boxscore.teams[].statistics[].stats[].description` | string | 100% | e.g. "Games Played", "The number of games played by a team.", "Clean Breaks", "Conversion Goals" |
| `boxscore.teams[].statistics[].stats[].displayName` | string | 100% | e.g. "Runs", "Games Played", "Team Games Played", "Hits" |
| `boxscore.teams[].statistics[].stats[].displayValue` | str-numeric | 100% | e.g. "0", "1", "5", "3" |
| `boxscore.teams[].statistics[].stats[].name` | string | 100% | e.g. "runs", "gamesPlayed", "teamGamesPlayed", "hits" |
| `boxscore.teams[].statistics[].stats[].shortDisplayName` | string | 100% | e.g. "P", "R", "MT", "GP" |
| `boxscore.teams[].statistics[].stats[].value` | number | 100% | e.g. 0, 1, 5, 3 |
| `header.competitions[].competitors[].form` | string | 100% | e.g. "WWWWW", "WWLLL", "LLLLL", "WWWDD" |

## Go deeper

- Full field tables: [scoreboard](../scoreboard.md) · [summary](../summary.md) · [standings](../standings.md) · [teams](../teams.md) · [team-roster](../team-roster.md) · [rankings](../rankings.md)
- Canonical shape, ESPN→canonical mappings, per-league period/OT matrix: `schema/SCHEMA.md`, `schema/canonical.ts`
- Cross-sport support matrix: [index.md](../index.md)
