# ESPN API — australian-football

> Per-sport slice of the [observed data guide](../index.md): what ESPN actually serves for **australian-football**, and which endpoint answers each need. Built from 93 real australian-football responses — OBSERVED live, not documented. Regenerate: `node schema/tools/rollup.mjs`.

## Leagues — 1 in the registry

Competition **shape** drives rendering (see the discriminators in `schema/canonical.ts`): `layout · scoreKind · competitorKind`.

| shape (layout · scoreKind · competitorKind) | leagues | examples |
|---|---|---|
| `headToHead · numeric · team` | 1 | `afl` |

**Crawled for this guide** (1): `australian-football/afl`. The evidence below is from these leagues; other australian-football leagues in the registry inherit the same shape.

## Which endpoint to use

URL templates use `australian-football/afl` as a representative league. Swap in any league key from the table above.

| need | endpoint | status | URL template | fields |
|---|---|---|---|---|
| Scores & live state | `scoreboard` | ✅ 14/14 | `https://site.api.espn.com/apis/site/v2/sports/australian-football/afl/scoreboard` | [guide](../scoreboard.md) |
| Rich game detail | `summary` | ✅ 4/4 | `https://site.api.espn.com/apis/site/v2/sports/australian-football/afl/summary?event={eventId}` | [guide](../summary.md) |
| League table | `standings` | ✅ 2/2 | `https://site.api.espn.com/apis/v2/sports/australian-football/afl/standings` | [guide](../standings.md) |
| Team directory | `teams` | ✅ 1/1 | `https://site.api.espn.com/apis/site/v2/sports/australian-football/afl/teams` | [guide](../teams.md) |
| Roster | `team-roster` | ✅ 2/2 | `https://site.api.espn.com/apis/site/v2/sports/australian-football/afl/teams/{teamId}/roster` | [guide](../team-roster.md) |
| Schedule | `team-schedule` | ✅ 1/1 | `https://site.api.espn.com/apis/site/v2/sports/australian-football/afl/teams/{teamId}/schedule` | [guide](../team-schedule.md) |
| Team season stats | `team-stats` | ❌ not served | `https://site.api.espn.com/apis/site/v2/sports/australian-football/afl/teams/{teamId}/statistics` | [guide](../team-stats.md) |
| News | `news` | ✅ 1/1 | `https://site.api.espn.com/apis/site/v2/sports/australian-football/afl/news?limit=5` | [guide](../news.md) |
| Injuries | `injuries` | ✅ 1/1 | `https://site.api.espn.com/apis/site/v2/sports/australian-football/afl/teams/{teamId}/injuries` | [guide](../injuries.md) |

- **scoreboard** — The cheap poll — scores, status, line scores, and (situationally) situation, leaders, records, odds. The primary call. College needs `?groups=<id>&limit=400`; `?dates=YYYYMMDD-YYYYMMDD` for a range (cricket: single day only).
- **summary** — One extra fetch when a game is opened — box scores, scoring plays, rosters, penalty shootouts, method of victory. A 404 for the whole sport means this tier does not exist (build detail from the core graph instead).
- **standings** — ⚠ `apis/v2`, NOT `apis/site/v2` (the site path returns a `{fullViewLink}` stub). Omit `?season=` — ESPN defaults to the current season.
- **teams** — Team ids, names, abbreviations, logos, colors. The id feeds the roster/schedule/stats/injuries calls.
- **team-roster** — Per-team roster with positions and headshots.
- **team-schedule** — Per-team schedule, past results + upcoming fixtures.
- **team-stats** — Per-team season statistics. _(every attempt 404/400 — this tier does not exist for the sport)_
- **news** — Latest articles for the league.
- **injuries** — Per-team injury report.

## Core API — `sports.core.api.espn.com`

67 of the core resource shapes were reachable for australian-football by following `$ref` links from the league root and its events (full matrix: [index.md](../index.md#core-api-resource-graph)). High-value shapes:

| resource | reachable | what it adds |
|---|---|---|
| `core-competitor-linescores` | ✅ | Per-period / per-set / per-inning scores — reachable even when the site scoreboard omits them (tennis sets, cricket innings). |
| `core-situation` | ✅ | Live game situation (baseball base/out, gridiron down & distance). |
| `core-plays` | ✅ | Play-by-play feed. |
| `core-competition-plays-id` | ✅ | Individual play detail. |
| `core-competition-statistics` | ✅ | Team box statistics for the game. |
| `core-competitor-roster` | ✅ | Game-day lineup. |
| `core-season-types-id-groups-id-standings` | ✅ | Standings through the core graph (grouped). |
| `core-rankings` | ✅ | Rankings through the core graph. |

## What's sport-specific in the data

Value-bearing fields observed for australian-football that are **not** near-universal — the sport's fingerprint. **presence** = % of this sport's crawled responses (or parent objects) that carry the field (australian-football-specific). Field paths, types, and presence are australian-football-only; the **value/example samples are pooled** across the handful of sports that share a field (a nested `period` may show golf's "18" next to a fight's "1–3"), so read them as shape hints. The full per-sport field tables live in the per-endpoint guides linked above.

### scoreboard

| field | type | presence | values / examples |
|---|---|---|---|
| `events[].weather.conditionId` | string | 100% | values: "Mostly sunny" (3), "Mostly cloudy" (3), "2" (3), "Cloudy" (2), "Sunny" (2), "Mostly clear" (1), "Drizzle" (1), "Partly sunny" (1), "15" (1) |
| `events[].weather.displayValue` | string | 100% | values: "2" (3), "6" (3), "Mostly sunny" (3), "7" (2), "1" (2), "34" (1), "12" (1), "3" (1), "Thunderstorms" (1) |
| `events[].weather.highTemperature` | number | 100% | values: 85 (5), 81 (2), 78 (1), 80 (1), 82 (1), 88 (1), 70 (1), 79 (1), 72 (1), 60 (1), 77 (1), 89 (1) |
| `events[].weather.temperature` | number | 100% | values: 85 (5), 81 (2), 78 (1), 80 (1), 82 (1), 88 (1), 70 (1), 79 (1), 72 (1), 60 (1), 77 (1), 89 (1) |
| `events[].competitions[].leaders[].abbreviation` | string | 100% | values: "RAT" (235), "PYDS" (203), "RYDS" (203), "RECYDS" (203), "G" (78), "D" (78) |
| `events[].competitions[].leaders[].displayName` | string | 100% | values: "MLB Rating" (235), "Passing Leader" (203), "Rushing Leader" (203), "Receiving Leader" (203), "Goals" (78), "Disposals" (78) |
| `events[].competitions[].leaders[].leaders[].displayValue` | string | 100% | e.g. "4 REC, 78 YDS, 1 TD", "8 REC, 96 YDS, 1 TD", "4 REC, 62 YDS", "5 REC, 68 YDS" |
| `events[].competitions[].leaders[].leaders[].team.id` | str-numeric | 100% | e.g. "8", "14", "6", "16" |
| `events[].competitions[].leaders[].leaders[].value` | number | 100% | e.g. 3, 67, 68.25, 69 |
| `events[].competitions[].leaders[].name` | string | 100% | values: "MLBRating" (235), "passingYards" (203), "rushingYards" (203), "receivingYards" (203), "goals" (78), "disposals" (78) |
| `events[].competitions[].leaders[].shortDisplayName` | string | 100% | values: "RAT" (235), "PASS" (203), "RUSH" (203), "REC" (203), "G" (78), "D" (78) |
| `events[].week.number` | number | 100% | e.g. 1, 18, 2, 10 |
| `leagues[].calendar[].entries[].alternateLabel` | string | 100% | e.g. "Week 1", "Week 2", "Week 3", "Week 4" |
| `leagues[].calendar[].value` | str-numeric | 100% | values: "2" (4), "1" (3), "3" (3), "4" (2) |
| `week.number` | number | 100% | e.g. 1, 18, 4, 13 |
| `events[].competitions[].competitors[].leaders[].abbreviation` | string | 100% | values: "RAT" (1372), "Pts" (892), "Reb" (892), "Ast" (892), "G" (553), "AVG" (476), "HR" (476), "RBI" (476), "MLB" (476), "PTS" (389), "A" (375), "D" (174), "REB" (10), "AST" (10) |
| `events[].competitions[].competitors[].leaders[].displayName` | string | 100% | values: "Points" (1271), "Assists" (1267), "MLB Rating" (946), "Rating" (902), "Rebounds" (892), "Goals" (553), "Batting Average" (476), "Home Runs" (476), "Runs Batted In" (476), "Disposals" (174), "Points Per Game" (10), "Rebounds Per Game" (10), "Assists Per Game" (10) |
| `events[].competitions[].competitors[].leaders[].leaders[].displayValue` | string | 100% | e.g. "7", "9", "8", "6" |
| `events[].competitions[].competitors[].leaders[].leaders[].value` | number | 100% | e.g. 7, 9, 8, 6 |
| `events[].competitions[].competitors[].leaders[].name` | string | 100% | values: "points" (1271), "assists" (1267), "MLBRating" (946), "rating" (902), "rebounds" (892), "goals" (553), "avg" (476), "homeRuns" (476), "RBIs" (476), "disposals" (174), "pointsPerGame" (10), "reboundsPerGame" (10), "assistsPerGame" (10) |
| `events[].competitions[].competitors[].leaders[].shortDisplayName` | string | 100% | e.g. "RAT", "Pts", "Reb", "Ast" |
| `leagues[].calendar[].entries[].detail` | string | 100% | e.g. "Aug 6-12", "Aug 13-19", "Aug 20-26", "Sep 9-15" |
| `leagues[].calendar[].entries[].label` | string | 100% | e.g. "Week 1", "Week 2", "Week 3", "Week 4" |
| `leagues[].calendar[].entries[].value` | str-numeric | 100% | e.g. "1", "2", "3", "4" |
| `events[].competitions[].competitors[].leaders[].leaders[].team.id` | str-numeric | 26% | e.g. "18", "16", "17", "5" |

### summary

| field | type | presence | values / examples |
|---|---|---|---|
| `header.competitions[].competitors[].linescores[].behinds` | number | 100% | values: 3 (5), 2 (5), 1 (4), 0 (3), 6 (2), 4 (2), 5 (1), 7 (1), 8 (1) |
| `header.competitions[].competitors[].linescores[].cumulativeBehindsDisplayValue` | str-numeric | 100% | values: "7" (3), "1" (3), "3" (3), "5" (2), "11" (2), "17" (2), "9" (2), "14" (1), "0" (1), "6" (1), "8" (1), "18" (1), "4" (1), "13" (1) |
| `header.competitions[].competitors[].linescores[].cumulativeDisplayValue` | str-numeric | 100% | e.g. "19", "11", "53", "80" |
| `header.competitions[].competitors[].linescores[].cumulativeGoalsDisplayValue` | str-numeric | 100% | values: "8" (3), "2" (3), "5" (3), "11" (2), "14" (2), "9" (2), "10" (2), "12" (2), "1" (1), "7" (1), "17" (1), "19" (1), "3" (1) |
| `header.competitions[].competitors[].linescores[].goals` | number | 100% | values: 3 (7), 2 (6), 1 (3), 6 (2), 8 (2), 5 (2), 4 (1), 0 (1) |
| `header.competitions[].competitors[].linescores[].value` | number | 100% | e.g. 13, 21, 19, 38 |
| `lastTen.freesFor.awayTeamValue` | number | 100% | e.g. 4, 3 |
| `lastTen.freesFor.displayName` | string | 100% | e.g. "Frees For" |
| `lastTen.freesFor.homeTeamValue` | number | 100% | e.g. 6, 7 |
| `lastTen.inside50.awayTeamValue` | number | 100% | e.g. 8 |
| `lastTen.inside50.displayName` | string | 100% | e.g. "Last 10 Inside 50's" |
| `lastTen.inside50.homeTeamValue` | number | 100% | e.g. 2 |
| `lastTen.scores.awayTeamValue` | number | 100% | e.g. 4 |
| `lastTen.scores.displayName` | string | 100% | e.g. "Last 10 Scores" |
| `lastTen.scores.homeTeamValue` | number | 100% | e.g. 6 |
| `rosters[].playerPositions.fieldOrder[].abbreviation` | string | 100% | values: "FB" (2), "HB" (2), "C" (2), "HF" (2), "FF" (2) |
| `rosters[].playerPositions.fieldOrder[].displayName` | string | 100% | values: "Fullbacks" (2), "Half backs" (2), "Centres" (2), "Half forwards" (2), "Full Forwards" (2) |
| `rosters[].playerPositions.fieldOrder[].name` | string | 100% | values: "Fullbacks" (2), "Half backs" (2), "Centres" (2), "Half forwards" (2), "Full Forwards" (2) |
| `rosters[].playerPositions.other[].abbreviation` | string | 100% | e.g. "Fol", "Int" |
| `rosters[].playerPositions.other[].displayName` | string | 100% | e.g. "Followers", "Interchange" |
| `rosters[].playerPositions.other[].name` | string | 100% | e.g. "Followers", "Interchange" |
| `lastTen.freesFor.timeline[]` | str-numeric | — | values: "17" (8), "14" (7), "5" (6), "15" (6), "11" (3) |
| `lastTen.inside50.timeline[]` | str-numeric | — | values: "17" (16), "11" (8), "14" (2), "5" (2), "15" (2) |
| `lastTen.scores.timeline[]` | str-numeric | — | values: "17" (8), "14" (6), "5" (6), "15" (6), "11" (4) |
| `rosters[].playerPositions.fieldOrder[].positions[]` | string | — | values: "BPL" (2), "FB" (2), "BPR" (2), "HBFL" (2), "CHB" (2), "HBFR" (2), "WL" (2), "C" (2), "WR" (2), "HFFL" (2), "CHF" (2), "HFFR" (2), "FPL" (2), "FF" (2), "FPR" (2) |
| `rosters[].playerPositions.other[].positions[]` | string | — | values: "RK" (2), "RR" (2), "R" (2), "INT" (2) |
| `plays[].type.type` | string | 100% | e.g. "goal", "behind", "start-batterpitcher", "ball" |
| `boxscore.players[].statistics[].athletes[].active` | boolean | 100% | values: true (353), false (266) |
| `boxscore.players[].statistics[].athletes[].starter` | boolean | 100% | values: false (416), true (203) |
| `lastFiveGames[].events[].week` | number | 100% | e.g. 12, 14, 13, 17 |
| `leaders[].leaders[].leaders[].athlete.injuries.type.abbreviation` | string | 100% | values: "A" (9), "P" (7), "Q" (6), "O" (3), "DD" (2) |
| `leaders[].leaders[].leaders[].athlete.injuries.type.description` | string | 100% | values: "active" (9), "probable" (7), "questionable" (6), "out" (3), "day-to-day" (2) |
| `leaders[].leaders[].leaders[].athlete.injuries.type.id` | str-numeric | 100% | values: "0" (9), "1" (7), "2" (6), "4" (3), "6" (2) |
| `leaders[].leaders[].leaders[].athlete.injuries.type.name` | string | 100% | values: "INJURY_STATUS_ACTIVE" (9), "INJURY_STATUS_PROBABLE" (7), "INJURY_STATUS_QUESTIONABLE" (6), "INJURY_STATUS_OUT" (3), "INJURY_STATUS_DAYTODAY" (2) |
| `plays[].clock.displayValue` | string | 100% | e.g. "17:49", "9:43", "16:55", "19:58" |
| `rosters[].team.alternateColor` | string | 100% | e.g. "ffffff", "1a1a1a", "003399", "FFFFFF" |
| `lastFiveGames[].displayOrder` | number | 100% | values: 1 (35), 2 (35) |
| `leaders[].leaders[].leaders[].value` | number | 100% | e.g. 3, 1, 2, 10 |
| `plays[].awayScore` | number | 100% | e.g. 0, 2, 6, 4 |
| `plays[].homeScore` | number | 100% | e.g. 0, 2, 1, 3 |
| `plays[].id` | str-numeric | 100% | e.g. "4018599674", "4018599677", "4018599678", "4018599679" |
| `plays[].period.number` | number | 100% | values: 1 (510), 2 (33), 3 (7) |
| `plays[].sequenceNumber` | str-numeric | 100% | e.g. "4", "1", "2", "7" |
| `plays[].team.id` | str-numeric | 100% | e.g. "17", "9", "24", "1" |
| `plays[].text` | string | 100% | e.g. "Pitch 1 : Strike 1 Looking", "Start game", "Top of the 1st inning", "Pitch 1 : Ball 1" |
| `plays[].type.id` | str-numeric | 100% | e.g. "21", "155", "558", "57" |
| `plays[].type.text` | string | 100% | e.g. "Defensive Rebound", "Goal", "JumpShot", "Behind" |
| `boxscore.players[].statistics[].totals[]` | string | — | e.g. "0", "", "2", "3" |
| `boxscore.teams[].statistics[].abbreviation` | string | 100% | e.g. "TECH", "FG%", "3P%", "FT%" |
| `boxscore.teams[].statistics[].displayValue` | str-numeric | 100% | e.g. "0", "2", "1", "3" |
| `boxscore.teams[].statistics[].label` | string | 100% | e.g. "Fouls", "Possession", "Tackles", "Blocked Shots" |
| `gameInfo.venue.address.zipCode` | str-numeric | 100% | e.g. "94103", "33607", "21230", "98134" |
| `injuries[].injuries[].athlete.lastName` | string | 100% | e.g. "Walker", "Quaintance", "Bryant", "Jones Garcia" |
| `injuries[].injuries[].type.abbreviation` | string | 100% | values: "Q" (38), "O" (33), "P" (25), "DD" (19), "IL15" (14), "IL60" (11), "IL10" (9), "BL" (4), "IR" (3), "PL" (2), "SUSP" (2), "DEVLIST" (1) |
| `injuries[].injuries[].type.description` | string | 100% | values: "questionable" (38), "out" (33), "probable" (25), "day-to-day" (19), "15-day IL" (14), "60-day IL" (11), "10-day IL" (9), "Bereavement" (4), "Injured Reserve" (3), "Paternity" (2), "Suspension" (2), "Developmental List" (1) |

## Go deeper

- Full field tables: [scoreboard](../scoreboard.md) · [summary](../summary.md) · [standings](../standings.md) · [teams](../teams.md) · [team-roster](../team-roster.md) · [rankings](../rankings.md)
- Canonical shape, ESPN→canonical mappings, per-league period/OT matrix: `schema/SCHEMA.md`, `schema/canonical.ts`
- Cross-sport support matrix: [index.md](../index.md)
