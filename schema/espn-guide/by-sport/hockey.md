# ESPN API — hockey

> Per-sport slice of the [observed data guide](../index.md): what ESPN actually serves for **hockey**, and which endpoint answers each need. Built from 117 real hockey responses — OBSERVED live, not documented. Regenerate: `node schema/tools/rollup.mjs`.

## Leagues — 6 in the registry

Competition **shape** drives rendering (see the discriminators in `schema/canonical.ts`): `layout · scoreKind · competitorKind`.

| shape (layout · scoreKind · competitorKind) | leagues | examples |
|---|---|---|
| `headToHead · numeric · team` | 6 | `nhl`, `mens-college-hockey`, `womens-college-hockey`, `hockey-world-cup` |

**Crawled for this guide** (1): `hockey/nhl`. The evidence below is from these leagues; other hockey leagues in the registry inherit the same shape.

## Which endpoint to use

URL templates use `hockey/nhl` as a representative league. Swap in any league key from the table above.

| need | endpoint | status | URL template | fields |
|---|---|---|---|---|
| Scores & live state | `scoreboard` | ✅ 14/14 | `https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/scoreboard` | [guide](../scoreboard.md) |
| Rich game detail | `summary` | ✅ 4/4 | `https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/summary?event={eventId}` | [guide](../summary.md) |
| League table | `standings` | ✅ 2/2 | `https://site.api.espn.com/apis/v2/sports/hockey/nhl/standings` | [guide](../standings.md) |
| Team directory | `teams` | ✅ 1/1 | `https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/teams` | [guide](../teams.md) |
| Roster | `team-roster` | ✅ 2/2 | `https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/teams/{teamId}/roster` | [guide](../team-roster.md) |
| Schedule | `team-schedule` | ✅ 1/1 | `https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/teams/{teamId}/schedule` | [guide](../team-schedule.md) |
| Team season stats | `team-stats` | ✅ 1/1 | `https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/teams/{teamId}/statistics` | [guide](../team-stats.md) |
| News | `news` | ✅ 1/1 | `https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/news?limit=5` | [guide](../news.md) |
| Injuries | `injuries` | ✅ 1/1 | `https://site.api.espn.com/apis/site/v2/sports/hockey/nhl/teams/{teamId}/injuries` | [guide](../injuries.md) |

- **scoreboard** — The cheap poll — scores, status, line scores, and (situationally) situation, leaders, records, odds. The primary call. College needs `?groups=<id>&limit=400`; `?dates=YYYYMMDD-YYYYMMDD` for a range (cricket: single day only).
- **summary** — One extra fetch when a game is opened — box scores, scoring plays, rosters, penalty shootouts, method of victory. A 404 for the whole sport means this tier does not exist (build detail from the core graph instead).
- **standings** — ⚠ `apis/v2`, NOT `apis/site/v2` (the site path returns a `{fullViewLink}` stub). Omit `?season=` — ESPN defaults to the current season.
- **teams** — Team ids, names, abbreviations, logos, colors. The id feeds the roster/schedule/stats/injuries calls.
- **team-roster** — Per-team roster with positions and headshots.
- **team-schedule** — Per-team schedule, past results + upcoming fixtures.
- **team-stats** — Per-team season statistics.
- **news** — Latest articles for the league.
- **injuries** — Per-team injury report.

## Core API — `sports.core.api.espn.com`

90 of the core resource shapes were reachable for hockey by following `$ref` links from the league root and its events (full matrix: [index.md](../index.md#core-api-resource-graph)). High-value shapes:

| resource | reachable | what it adds |
|---|---|---|
| `core-competitor-linescores` | ✅ | Per-period / per-set / per-inning scores — reachable even when the site scoreboard omits them (tennis sets, cricket innings). |
| `core-situation` | ✅ | Live game situation (baseball base/out, gridiron down & distance). |
| `core-plays` | ✅ | Play-by-play feed. |
| `core-competition-plays-id` | ✅ | Individual play detail. |
| `core-odds` | ✅ | Betting lines / odds. |
| `core-competition-odds-id-propBets` | ✅ | Prop bets. |
| `core-competitor-roster` | ✅ | Game-day lineup. |
| `core-competitor-statistics` | ✅ | Competitor's game statistics. |
| `core-season-types-id-groups-id-standings` | ✅ | Standings through the core graph (grouped). |
| `core-season-futures` | ✅ | Season futures (championship odds). |
| `core-competition-officials` | ✅ | Match officials / referees. |

## What's sport-specific in the data

Value-bearing fields observed for hockey that are **not** near-universal — the sport's fingerprint. **presence** = % of this sport's crawled responses (or parent objects) that carry the field (hockey-specific). Field paths, types, and presence are hockey-only; the **value/example samples are pooled** across the handful of sports that share a field (a nested `period` may show golf's "18" next to a fight's "1–3"), so read them as shape hints. The full per-sport field tables live in the per-endpoint guides linked above.

### scoreboard

| field | type | presence | values / examples |
|---|---|---|---|
| `events[].competitions[].competitors[].probables[].status.abbreviation` | string | 100% | values: "Confirmed" (392) |
| `events[].competitions[].competitors[].probables[].status.id` | str-numeric | 100% | values: "102" (392) |
| `events[].competitions[].competitors[].probables[].status.name` | string | 100% | values: "Confirmed" (392) |
| `events[].competitions[].competitors[].probables[].status.type` | string | 100% | values: "confirmed" (392) |
| `events[].competitions[].competitors[].probables[].abbreviation` | string | 100% | values: "SP" (474), "SG" (392) |
| `events[].competitions[].competitors[].probables[].displayName` | string | 100% | values: "Probable Starting Pitcher" (474), "Probable Starting Goalie" (392) |
| `events[].competitions[].competitors[].probables[].name` | string | 100% | values: "probableStartingPitcher" (474), "probableStartingGoalie" (392) |
| `events[].competitions[].competitors[].probables[].playerId` | number | 100% | e.g. 4588165, 2517899, 3942065, 3942459 |
| `events[].competitions[].competitors[].probables[].record` | string | 100% | e.g. "", "(5-4, 3.88)", "(0-0, 2.25)", "(10-4, 1.62)" |
| `events[].competitions[].competitors[].probables[].shortDisplayName` | string | 100% | values: "Starter" (866) |
| `events[].competitions[].status.featuredAthletes[].statistics[].abbreviation` | string | 100% | values: "SV" (1520), "SV%" (977), "+/-" (977), "G" (977), "YTDG" (977), "A" (977), "PTS" (977), "L" (543), "W" (543), "ERA" (543), "E" (543), "H" (244), "R" (244), "AVG" (244) |
| `events[].competitions[].status.featuredAthletes[].statistics[].displayValue` | string | 100% | e.g. "0", "1", ".000", "2" |
| `events[].competitions[].status.featuredAthletes[].statistics[].name` | string | 100% | values: "saves" (1520), "savePct" (977), "plusMinus" (977), "goals" (977), "ytdGoals" (977), "assists" (977), "points" (977), "losses" (543), "wins" (543), "ERA" (543), "errors" (543), "hits" (244), "runs" (244), "avg" (244) |
| `events[].competitions[].series.competitors[].ties` | number | 100% | values: 0 (192) |
| `events[].competitions[].series.competitors[].wins` | number | 100% | values: 0 (49), 1 (46), 2 (44), 4 (27), 3 (26) |
| `events[].competitions[].series.summary` | string | 100% | e.g. "", "Series tied 1-1", "Series tied 3-3", "MIN wins series 4-2" |
| `events[].competitions[].series.type` | string | 100% | values: "playoff" (96) |
| `events[].competitions[].status.featuredAthletes[].abbreviation` | string | 100% | values: "WP" (220), "LP" (220), "FS" (196), "SS" (196), "TS" (196), "L" (195), "W" (194), "S" (103), "POTM" (1), "POTS" (1) |
| `events[].competitions[].status.featuredAthletes[].displayName` | string | 100% | values: "Winning Pitcher" (220), "Losing Pitcher" (220), "First Star" (196), "Second Star" (196), "Third Star" (196), "Losing Goalie" (195), "Winning Goalie" (194), "Saving Pitcher" (103), "Player Of The Match" (1), "Player Of The Series" (1) |
| `events[].competitions[].status.featuredAthletes[].name` | string | 100% | values: "winningPitcher" (220), "losingPitcher" (220), "firstStar" (196), "secondStar" (196), "thirdStar" (196), "losingGoalie" (195), "winningGoalie" (194), "savingPitcher" (103), "playerOfTheMatch" (1), "playerOfTheSeries" (1) |
| `events[].competitions[].status.featuredAthletes[].playerId` | number | 100% | e.g. 4064582, 4697686, 2517899, 4588165 |
| `events[].competitions[].status.featuredAthletes[].shortDisplayName` | string | 100% | values: "Win" (220), "Loss" (220), "First Star" (196), "Second Star" (196), "Third Star" (196), "Losing Goalie" (195), "Winning Goalie" (194), "Save" (103), "POTM" (1), "POTS" (1) |
| `events[].competitions[].status.featuredAthletes[].team.id` | str-numeric | 100% | e.g. "2", "16", "30", "1" |
| `events[].competitions[].competitors[].record` | string | 8% | e.g. "0-1", "2-1", "1-2", "0-2" |
| `events[].competitions[].competitors[].leaders[].abbreviation` | string | 100% | values: "RAT" (1372), "Pts" (892), "Reb" (892), "Ast" (892), "G" (553), "AVG" (476), "HR" (476), "RBI" (476), "MLB" (476), "PTS" (389), "A" (375), "D" (174), "REB" (10), "AST" (10) |
| `events[].competitions[].competitors[].leaders[].displayName` | string | 100% | values: "Points" (1271), "Assists" (1267), "MLB Rating" (946), "Rating" (902), "Rebounds" (892), "Goals" (553), "Batting Average" (476), "Home Runs" (476), "Runs Batted In" (476), "Disposals" (174), "Points Per Game" (10), "Rebounds Per Game" (10), "Assists Per Game" (10) |
| `events[].competitions[].competitors[].leaders[].leaders[].displayValue` | string | 100% | e.g. "7", "9", "8", "6" |
| `events[].competitions[].competitors[].leaders[].leaders[].team.id` | str-numeric | 100% | e.g. "18", "16", "17", "5" |
| `events[].competitions[].competitors[].leaders[].leaders[].value` | number | 100% | e.g. 7, 9, 8, 6 |
| `events[].competitions[].competitors[].leaders[].name` | string | 100% | values: "points" (1271), "assists" (1267), "MLBRating" (946), "rating" (902), "rebounds" (892), "goals" (553), "avg" (476), "homeRuns" (476), "RBIs" (476), "disposals" (174), "pointsPerGame" (10), "reboundsPerGame" (10), "assistsPerGame" (10) |
| `events[].competitions[].competitors[].leaders[].shortDisplayName` | string | 100% | e.g. "RAT", "Pts", "Reb", "Ast" |
| `events[].competitions[].series.competitors[].id` | str-numeric | 100% | e.g. "8", "18", "16", "10" |
| `events[].competitions[].series.completed` | boolean | 100% | values: false (64), true (42) |
| `events[].competitions[].series.title` | string | 100% | values: "Playoff Series" (96), "Quarterfinals" (4), "Round of 16" (4), "Semifinals" (2) |
| `events[].competitions[].series.totalCompetitions` | number | 100% | values: 7 (69), 5 (19), 2 (10), 3 (8) |
| `events[].competitions[].highlights[].geoRestrictions.type` | string | 100% | values: "whitelist" (460) |
| `events[].competitions[].tickets[].numberAvailable` | number | 100% | e.g. 235, 621, 684, 202 |
| `events[].competitions[].tickets[].summary` | string | 100% | e.g. "Tickets as low as $7", "Tickets as low as $32", "Tickets as low as $52", "Tickets as low as $5" |
| `events[].competitions[].venue.address.country` | string | 100% | e.g. "USA", "England", "Spain", "Italy" |
| `events[].competitions[].highlights[].geoRestrictions.countries[]` | string | — | e.g. "PR", "AS", "BI", "AG" |
| `events[].competitions[].competitors[].curatedRank.current` | number | 100% | e.g. 99, 2, 1, 3 |
| `events[].competitions[].competitors[].statistics[].abbreviation` | string | 100% | e.g. "PTS", "REB", "AST", "A" |
| `events[].competitions[].competitors[].statistics[].displayValue` | str-numeric | 100% | e.g. "0", "1", "2", "3" |
| `events[].competitions[].competitors[].statistics[].name` | string | 100% | e.g. "assists", "points", "appearances", "foulsCommitted" |
| `events[].competitions[].status.type.altDetail` | string | 24% | values: "OT" (58), "SO" (17), "2OT" (9), "F/10" (9), "F/11" (5), "3OT" (1), "F/15" (1) |
| `events[].status.type.altDetail` | string | 24% | values: "OT" (58), "SO" (17), "2OT" (9), "F/10" (9), "F/11" (5), "3OT" (1), "F/15" (1) |

### summary

| field | type | presence | values / examples |
|---|---|---|---|
| `boxscore.players[].statistics[].athletes[].athlete.scratched` | boolean | 100% | values: false (114) |
| `goalies.awayTeam.teamId` | str-numeric | 100% | e.g. "10" |
| `goalies.homeTeam.teamId` | str-numeric | 100% | e.g. "21" |
| `header.standings[].id` | str-numeric | 100% | e.g. "37", "9", "1", "10" |
| `header.standings[].link` | string | 100% | e.g. "https://www.espn.com/nhl/team/_/name/vgk/vegas-golden-knights", "https://www.espn.com/nhl/team/_/name/dal/dallas-stars", "https://www.espn.com/nhl/team/_/name/bos/boston-bruins", "https://www.espn.com/nhl/team/_/name/mtl/montreal-canadiens" |
| `header.standings[].stats[].abbreviation` | string | 100% | values: "OTL" (5), "L" (5), "PTS" (5), "W" (5) |
| `header.standings[].stats[].description` | string | 100% | values: "Number of Overtime Losses" (5), "Losses" (5), "Total Points" (5), "Wins" (5) |
| `header.standings[].stats[].displayName` | string | 100% | values: "Overtime Losses" (5), "Losses" (5), "Points" (5), "Wins" (5) |
| `header.standings[].stats[].displayValue` | str-numeric | 100% | e.g. "10", "17", "26", "95" |
| `header.standings[].stats[].name` | string | 100% | values: "otLosses" (5), "losses" (5), "points" (5), "wins" (5) |
| `header.standings[].stats[].shortDisplayName` | string | 100% | values: "OTL" (5), "L" (5), "PTS" (5), "W" (5) |
| `header.standings[].stats[].type` | string | 100% | values: "otlosses" (5), "losses" (5), "points" (5), "wins" (5) |
| `header.standings[].stats[].value` | number | 100% | e.g. 10, 17, 26, 95 |
| `header.standings[].team` | string | 100% | e.g. "Vegas", "Dallas", "Boston", "Montreal" |
| `onIce[].entries[].athleteid` | str-numeric | 100% | e.g. "3069266", "3541", "5428", "3114741" |
| `onIce[].entries[].whereabouts.description` | string | 100% | values: "In Play" (35) |
| `onIce[].entries[].whereabouts.id` | str-numeric | 100% | values: "1" (35) |
| `onIce[].entries[].whereabouts.name` | string | 100% | values: "ROSTER_WHEREABOUTS_IN_PLAY" (35) |
| `onIce[].teamId` | str-numeric | 100% | e.g. "1", "7", "37", "9" |
| `plays[].shotInfo.abbreviation` | string | 100% | e.g. "regular" |
| `plays[].shotInfo.id` | str-numeric | 100% | e.g. "901" |
| `plays[].shotInfo.text` | string | 100% | e.g. "None" |
| `plays[].strength.abbreviation` | string | 100% | values: "even-strength" (63), "short-handed" (4), "power-play" (3) |
| `plays[].strength.id` | str-numeric | 100% | values: "701" (63), "703" (4), "702" (3) |
| `plays[].strength.text` | string | 100% | values: "Even Strength" (63), "Shorthanded" (4), "Power Play" (3) |
| `plays[].participants[].ytdGoals` | number | 53% | values: 0 (19), 1 (10), 5 (6), 3 (5), 2 (4), 9 (4), 4 (4), 16 (3), 29 (2), 14 (2), 10 (1), 40 (1), 34 (1) |
| `plays[].participants[].ytdAssists` | number | 47% | values: 0 (16), 1 (15), 3 (5), 5 (4), 4 (3), 2 (2), 23 (2), 29 (1), 11 (1), 17 (1), 19 (1), 9 (1), 12 (1), 7 (1), 51 (1) |
| `header.competitions[].shotChartAvailable` | boolean | 100% | values: true (15), false (1) |
| `header.competitions[].status.featuredAthletes[].team.nickname` | string | 100% | values: "Bruins" (7), "Golden Knights" (3), "Hurricanes" (2), "Capitals" (2), "Stars" (1), "Australia" (1), "India" (1) |
| `plays[].coordinate.x` | number | 100% | e.g. 25, -214748340, 26, 28 |
| `plays[].coordinate.y` | number | 100% | e.g. 0, -214748365, 2, 1 |
| `plays[].shootingPlay` | boolean | 100% | values: true (217), false (158) |
| `plays[].type.abbreviation` | string | 100% | e.g. "hit", "B", "faceoff", "F" |
| `plays[].participants[].type` | string | 80% | e.g. "pitcher", "batter", "onFirst", "onThird" |
| `header.competitions[].series[].competitors[].ties` | number | 100% | values: 0 (44) |
| `header.competitions[].series[].competitors[].wins` | number | 100% | values: 1 (16), 0 (11), 2 (7), 4 (5), 3 (3), 6 (1), 5 (1) |
| `header.competitions[].series[].description` | string | 100% | values: "Regular Season Series" (11), "Playoff Series" (4), "NBA Finals" (2), "West Finals" (2), "Current Series" (2), "Preseason Series" (1) |
| `header.competitions[].series[].summary` | string | 100% | e.g. "Series tied 1-1", "DAL leads series 1-0", "NY wins series 4-1", "Series tied 2-2" |
| `header.competitions[].series[].type` | string | 100% | values: "season" (13), "playoff" (6), "current" (2), "preseason" (1) |
| `header.competitions[].status.featuredAthletes[].displayName` | string | 100% | values: "Winning Pitcher" (3), "Losing Pitcher" (3), "Winning Goalie" (3), "Losing Goalie" (3), "First Star" (3), "Second Star" (3), "Third Star" (3), "Saving Pitcher" (2), "Player Of The Match" (1), "Player Of The Series" (1) |
| `header.competitions[].status.featuredAthletes[].name` | string | 100% | values: "winningPitcher" (3), "losingPitcher" (3), "winningGoalie" (3), "losingGoalie" (3), "firstStar" (3), "secondStar" (3), "thirdStar" (3), "savingPitcher" (2), "playerOfTheMatch" (1), "playerOfTheSeries" (1) |
| `header.competitions[].status.featuredAthletes[].playerId` | number | 100% | e.g. 3069266, 5080761, 33301, 4917865 |
| `header.competitions[].status.featuredAthletes[].team.id` | str-numeric | 100% | values: "1" (7), "37" (3), "8" (2), "15" (2), "7" (2), "23" (2), "24" (1), "30" (1), "19" (1), "14" (1), "9" (1), "2" (1), "6" (1) |
| `header.competitions[].status.featuredAthletes[].team.name` | string | 100% | values: "Bruins" (7), "Golden Knights" (3), "Brewers" (2), "Braves" (2), "Hurricanes" (2), "Capitals" (2), "Cardinals" (1), "Rays" (1), "Dodgers" (1), "Blue Jays" (1), "Stars" (1), "Australia" (1), "India" (1) |
| `plays[].clock.displayValue` | string | 100% | e.g. "17:49", "9:43", "16:55", "19:58" |
| `plays[].period.displayValue` | string | 100% | values: "1st Quarter" (200), "1st Half" (100), "1st Inning" (100), "1st" (75) |
| `plays[].scoreValue` | number | 100% | values: 0 (382), 2 (53), 3 (24), 1 (16) |
| `plays[].scoringPlay` | boolean | 100% | values: false (405), true (70) |
| `seasonseries[].completed` | boolean | 100% | values: true (13), false (9) |
| `seasonseries[].description` | string | 100% | values: "Regular Season Series" (11), "Playoff Series" (4), "NBA Finals" (2), "West Finals" (2), "Current Series" (2), "Preseason Series" (1) |
| `seasonseries[].events[].competitors[].homeAway` | string | 100% | values: "home" (101), "away" (101) |
| `seasonseries[].events[].competitors[].score` | str-numeric | 100% | e.g. "0", "3", "1", "5" |
| `seasonseries[].events[].competitors[].team.abbreviation` | string | 100% | e.g. "NY", "SA", "STL", "MIL" |
| `seasonseries[].events[].competitors[].team.displayName` | string | 100% | e.g. "San Antonio Spurs", "St. Louis Cardinals", "Milwaukee Brewers", "Toronto Blue Jays" |
| `seasonseries[].events[].competitors[].team.id` | str-numeric | 100% | e.g. "24", "19", "8", "14" |

## Go deeper

- Full field tables: [scoreboard](../scoreboard.md) · [summary](../summary.md) · [standings](../standings.md) · [teams](../teams.md) · [team-roster](../team-roster.md) · [rankings](../rankings.md)
- Canonical shape, ESPN→canonical mappings, per-league period/OT matrix: `schema/SCHEMA.md`, `schema/canonical.ts`
- Cross-sport support matrix: [index.md](../index.md)
