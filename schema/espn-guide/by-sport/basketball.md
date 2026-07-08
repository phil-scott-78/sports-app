# ESPN API — basketball

> Per-sport slice of the [observed data guide](../index.md): what ESPN actually serves for **basketball**, and which endpoint answers each need. Built from 398 real basketball responses — OBSERVED live, not documented. Regenerate: `node schema/tools/rollup.mjs`.

## Leagues — 15 in the registry

Competition **shape** drives rendering (see the discriminators in `schema/canonical.ts`): `layout · scoreKind · competitorKind`.

| shape (layout · scoreKind · competitorKind) | leagues | examples |
|---|---|---|
| `headToHead · numeric · team` | 15 | `nba`, `wnba`, `mens-college-basketball`, `womens-college-basketball` |

**Crawled for this guide** (3): `basketball/mens-college-basketball`, `basketball/nba`, `basketball/wnba`. The evidence below is from these leagues; other basketball leagues in the registry inherit the same shape.

## Which endpoint to use

URL templates use `basketball/mens-college-basketball` as a representative league. Swap in any league key from the table above.

| need | endpoint | status | URL template | fields |
|---|---|---|---|---|
| Scores & live state | `scoreboard` | ✅ 42/42 | `https://site.api.espn.com/apis/site/v2/sports/basketball/mens-college-basketball/scoreboard` | [guide](../scoreboard.md) |
| Rich game detail | `summary` | ✅ 12/12 | `https://site.api.espn.com/apis/site/v2/sports/basketball/mens-college-basketball/summary?event={eventId}` | [guide](../summary.md) |
| League table | `standings` | ✅ 6/6 | `https://site.api.espn.com/apis/v2/sports/basketball/mens-college-basketball/standings` | [guide](../standings.md) |
| Team directory | `teams` | ✅ 3/3 | `https://site.api.espn.com/apis/site/v2/sports/basketball/mens-college-basketball/teams` | [guide](../teams.md) |
| Roster | `team-roster` | ✅ 6/6 | `https://site.api.espn.com/apis/site/v2/sports/basketball/mens-college-basketball/teams/{teamId}/roster` | [guide](../team-roster.md) |
| Schedule | `team-schedule` | ✅ 3/3 | `https://site.api.espn.com/apis/site/v2/sports/basketball/mens-college-basketball/teams/{teamId}/schedule` | [guide](../team-schedule.md) |
| Team season stats | `team-stats` | ✅ 3/3 | `https://site.api.espn.com/apis/site/v2/sports/basketball/mens-college-basketball/teams/{teamId}/statistics` | [guide](../team-stats.md) |
| Polls / rankings | `rankings` | ✅ 1/1 | `https://site.api.espn.com/apis/site/v2/sports/basketball/mens-college-basketball/rankings` | [guide](../rankings.md) |
| News | `news` | ✅ 3/3 | `https://site.api.espn.com/apis/site/v2/sports/basketball/mens-college-basketball/news?limit=5` | [guide](../news.md) |
| Injuries | `injuries` | ✅ 3/3 | `https://site.api.espn.com/apis/site/v2/sports/basketball/mens-college-basketball/teams/{teamId}/injuries` | [guide](../injuries.md) |

- **scoreboard** — The cheap poll — scores, status, line scores, and (situationally) situation, leaders, records, odds. The primary call. College needs `?groups=<id>&limit=400`; `?dates=YYYYMMDD-YYYYMMDD` for a range (cricket: single day only).
- **summary** — One extra fetch when a game is opened — box scores, scoring plays, rosters, penalty shootouts, method of victory. A 404 for the whole sport means this tier does not exist (build detail from the core graph instead).
- **standings** — ⚠ `apis/v2`, NOT `apis/site/v2` (the site path returns a `{fullViewLink}` stub). Omit `?season=` — ESPN defaults to the current season.
- **teams** — Team ids, names, abbreviations, logos, colors. The id feeds the roster/schedule/stats/injuries calls.
- **team-roster** — Per-team roster with positions and headshots.
- **team-schedule** — Per-team schedule, past results + upcoming fixtures.
- **team-stats** — Per-team season statistics.
- **rankings** — College polls, ATP/WTA tour rankings, UFC divisional rankings. Only where a poll exists for the league.
- **news** — Latest articles for the league.
- **injuries** — Per-team injury report.

## Core API — `sports.core.api.espn.com`

129 of the core resource shapes were reachable for basketball by following `$ref` links from the league root and its events (full matrix: [index.md](../index.md#core-api-resource-graph)). High-value shapes:

| resource | reachable | what it adds |
|---|---|---|
| `core-competitor-linescores` | ✅ | Per-period / per-set / per-inning scores — reachable even when the site scoreboard omits them (tennis sets, cricket innings). |
| `core-situation` | ✅ | Live game situation (baseball base/out, gridiron down & distance). |
| `core-plays` | ✅ | Play-by-play feed. |
| `core-competition-plays-id` | ✅ | Individual play detail. |
| `core-odds` | ✅ | Betting lines / odds. |
| `core-competition-odds-id-propBets` | ✅ | Prop bets. |
| `core-probabilities` | ✅ | Win-probability timeline. |
| `core-predictor` | ✅ | Pre-game matchup prediction. |
| `core-competition-powerindex` | ✅ | Team power-index / matchup metrics. |
| `core-competitor-roster` | ✅ | Game-day lineup. |
| `core-competitor-statistics` | ✅ | Competitor's game statistics. |
| `core-season-types-id-groups-id-standings` | ✅ | Standings through the core graph (grouped). |
| `core-rankings` | ✅ | Rankings through the core graph. |
| `core-season-futures` | ✅ | Season futures (championship odds). |
| `core-competition-officials` | ✅ | Match officials / referees. |

## What's sport-specific in the data

Value-bearing fields observed for basketball that are **not** near-universal — the sport's fingerprint. **presence** = % of this sport's crawled responses (or parent objects) that carry the field (basketball-specific). Field paths, types, and presence are basketball-only; the **value/example samples are pooled** across the handful of sports that share a field (a nested `period` may show golf's "18" next to a fight's "1–3"), so read them as shape hints. The full per-sport field tables live in the per-endpoint guides linked above.

### scoreboard

| field | type | presence | values / examples |
|---|---|---|---|
| `events[].competitions[].situation.lastPlay.probability.awayWinPercentage` | number | 100% | e.g. 0.667, 0.696 |
| `events[].competitions[].situation.lastPlay.probability.homeWinPercentage` | number | 100% | e.g. 0.333, 0.304 |
| `events[].competitions[].situation.lastPlay.probability.tiePercentage` | number | 100% | e.g. 0 |
| `eventsDate.seasonType` | number | 100% | e.g. 3 |
| `events[].competitions[].tournamentId` | number | 3% | values: 161 (7), 22 (4), 21 (3) |
| `events[].competitions[].groups.id` | str-numeric | 100% | e.g. "4", "13", "8", "1" |
| `events[].competitions[].groups.isConference` | boolean | 100% | values: true (125) |
| `events[].competitions[].groups.name` | string | 100% | e.g. "Big Ten Conference", "Atlantic Coast Conference", "American Conference", "Metro Atlantic Athletic Conference" |
| `events[].competitions[].groups.shortName` | string | 100% | e.g. "Big Ten", "ACC", "American", "MAAC" |
| `events[].competitions[].situation.lastPlay.athletesInvolved[].displayName` | string | 100% | e.g. "Azzi Fudd", "Awak Kuier", "Edmundo Sosa", "Kyle Manzardo" |
| `events[].competitions[].situation.lastPlay.athletesInvolved[].fullName` | string | 100% | e.g. "Azzi Fudd", "Awak Kuier", "Edmundo Sosa", "Kyle Manzardo" |
| `events[].competitions[].situation.lastPlay.athletesInvolved[].id` | str-numeric | 100% | e.g. "4433790", "4790266", "33809", "4917927" |
| `events[].competitions[].situation.lastPlay.athletesInvolved[].jersey` | str-numeric | 100% | e.g. "35", "34", "33", "9" |
| `events[].competitions[].situation.lastPlay.athletesInvolved[].position` | string | 100% | e.g. "G", "F", "2B", "1B" |
| `events[].competitions[].situation.lastPlay.athletesInvolved[].shortName` | string | 100% | e.g. "A. Fudd", "A. Kuier", "E. Sosa", "K. Manzardo" |
| `events[].competitions[].situation.lastPlay.athletesInvolved[].team.id` | str-numeric | 100% | e.g. "3", "22", "5" |
| `events[].competitions[].situation.lastPlay.id` | str-numeric | 100% | values: "401857046215" (1), "401857046220" (1), "4018160550799990058" (1), "4018160531203020021" (1), "4018160541202050021" (1), "4018160581203030021" (1), "4018160601299990058" (1), "4018160561006010001" (1), "4018160570804050021" (1), "4018160591003030036" (1), "4018160620599990058" (1), "4018160630603040037" (1), "4018160640801010001" (1), "4018160610306010001" (1) |
| `events[].competitions[].situation.lastPlay.scoreValue` | number | 100% | values: 0 (14) |
| `events[].competitions[].situation.lastPlay.team.id` | str-numeric | 100% | values: "3" (2), "1" (1), "6" (1), "23" (1), "30" (1), "12" (1), "18" (1), "21" (1), "17" (1), "4" (1), "9" (1), "8" (1), "13" (1) |
| `events[].competitions[].situation.lastPlay.text` | string | 100% | values: "Pitch 4 : Strike 2 Foul" (2), "Azzi Fudd enters the game for Aziaha James" (1), "Awak Kuier shooting foul" (1), "End of the 4th inning" (1), "Pitch 1 : Strike 1 Foul" (1), "Pitch 2 : Strike 2 Foul" (1), "Middle of the 7th inning" (1), "Justin Lawrence pitches to Jose Altuve" (1), "Pitch 2 : Strike 1 Looking" (1), "End of the 3rd inning" (1), "Pitch 3 : Strike 2 Swinging" (1), "Hunter Dobbins pitches to Gary Sanchez" (1), "Jose Soriano pitches to Joc Pederson" (1) |
| `events[].competitions[].situation.lastPlay.type.id` | str-numeric | 100% | values: "21" (4), "58" (3), "1" (3), "584" (1), "44" (1), "36" (1), "37" (1) |
| `events[].competitions[].situation.lastPlay.type.text` | string | 100% | values: "Foul Ball" (4), "End Inning" (3), "Start Batter/Pitcher" (3), "Substitution" (1), "Shooting Foul" (1), "Strike Looking" (1), "Strike Swinging" (1) |
| `events[].competitions[].competitors[].team.conferenceId` | str-numeric | 24% | e.g. "8", "4", "5", "1" |
| `events[].competitions[].competitors[].statistics[].rankDisplayValue` | string | 1% | e.g. "1st", "12th", "11th", "13th" |
| `groups[]` | str-numeric | — | values: "80" (14), "50" (14) |
| `events[].competitions[].odds[].awayTeamOdds.favorite` | boolean | 100% | values: false (29), true (10) |
| `events[].competitions[].odds[].awayTeamOdds.favoriteAtOpen` | boolean | 100% | values: false (30), true (9) |
| `events[].competitions[].odds[].awayTeamOdds.team.name` | string | 100% | e.g. "Spartans", "Sky", "Patriots", "49ers" |
| `events[].competitions[].odds[].awayTeamOdds.underdog` | boolean | 100% | values: true (29), false (10) |
| `events[].competitions[].odds[].footer.disclaimer` | string | 100% | values: "GAMBLING PROBLEM? CALL 1-800-GAMBLER or 1-800-MY-RESET, (800) 327-5050 or visit …" (39) |
| `events[].competitions[].odds[].header.text` | string | 100% | values: "Game Odds" (39) |
| `events[].competitions[].odds[].homeTeamOdds.favorite` | boolean | 100% | values: true (29), false (10) |
| `events[].competitions[].odds[].homeTeamOdds.favoriteAtOpen` | boolean | 100% | values: true (30), false (9) |
| `events[].competitions[].odds[].homeTeamOdds.team.name` | string | 100% | e.g. "Eagles", "Giants", "Mercury", "Seahawks" |
| `events[].competitions[].odds[].homeTeamOdds.underdog` | boolean | 100% | values: false (29), true (10) |
| `events[].competitions[].odds[].spread` | number | 100% | e.g. -3.5, -3, 1.5, -7.5 |
| `events[].competitions[].series.competitors[].ties` | number | 100% | values: 0 (192) |
| `events[].competitions[].series.competitors[].wins` | number | 100% | values: 0 (49), 1 (46), 2 (44), 4 (27), 3 (26) |
| `events[].competitions[].series.summary` | string | 100% | e.g. "", "Series tied 1-1", "Series tied 3-3", "MIN wins series 4-2" |
| `events[].competitions[].series.type` | string | 100% | values: "playoff" (96) |
| `events[].competitions[].competitors[].record` | string | 8% | e.g. "0-1", "2-1", "1-2", "0-2" |
| `events[].competitions[].competitors[].leaders[].abbreviation` | string | 100% | values: "RAT" (1372), "Pts" (892), "Reb" (892), "Ast" (892), "G" (553), "AVG" (476), "HR" (476), "RBI" (476), "MLB" (476), "PTS" (389), "A" (375), "D" (174), "REB" (10), "AST" (10) |
| `events[].competitions[].competitors[].leaders[].displayName` | string | 100% | values: "Points" (1271), "Assists" (1267), "MLB Rating" (946), "Rating" (902), "Rebounds" (892), "Goals" (553), "Batting Average" (476), "Home Runs" (476), "Runs Batted In" (476), "Disposals" (174), "Points Per Game" (10), "Rebounds Per Game" (10), "Assists Per Game" (10) |
| `events[].competitions[].competitors[].leaders[].leaders[].displayValue` | string | 100% | e.g. "7", "9", "8", "6" |
| `events[].competitions[].competitors[].leaders[].leaders[].team.id` | str-numeric | 100% | e.g. "18", "16", "17", "5" |
| `events[].competitions[].competitors[].leaders[].leaders[].value` | number | 100% | e.g. 7, 9, 8, 6 |
| `events[].competitions[].competitors[].leaders[].name` | string | 100% | values: "points" (1271), "assists" (1267), "MLBRating" (946), "rating" (902), "rebounds" (892), "goals" (553), "avg" (476), "homeRuns" (476), "RBIs" (476), "disposals" (174), "pointsPerGame" (10), "reboundsPerGame" (10), "assistsPerGame" (10) |
| `events[].competitions[].competitors[].leaders[].shortDisplayName` | string | 100% | e.g. "RAT", "Pts", "Reb", "Ast" |
| `events[].competitions[].odds[].awayTeamOdds.team.abbreviation` | string | 100% | e.g. "CHI", "ARI", "SJSU", "MON" |
| `events[].competitions[].odds[].awayTeamOdds.team.displayName` | string | 100% | e.g. "San José State Spartans", "Chicago Sky", "Monza", "Como" |
| `events[].competitions[].odds[].awayTeamOdds.team.id` | str-numeric | 100% | e.g. "5", "27", "23", "19" |
| `events[].competitions[].odds[].details` | string | 100% | e.g. "PHX -4.5", "MUN -390", "ALA +135", "ATM -350" |
| `events[].competitions[].odds[].homeTeamOdds.team.abbreviation` | string | 100% | e.g. "EMU", "PHX", "INT", "UDI" |
| `events[].competitions[].odds[].homeTeamOdds.team.displayName` | string | 100% | e.g. "Eastern Michigan Eagles", "Phoenix Mercury", "Internazionale", "Udinese" |
| `events[].competitions[].odds[].homeTeamOdds.team.id` | str-numeric | 100% | e.g. "11", "26", "30", "24" |

### summary

| field | type | presence | values / examples |
|---|---|---|---|
| `boxscore.players[].statistics[].athletes[].didNotPlay` | boolean | 100% | values: false (238), true (96) |
| `boxscore.players[].statistics[].athletes[].ejected` | boolean | 100% | values: false (334) |
| `header.competitions[].competitors[].fouls.bonusState` | string | 100% | e.g. "NONE" |
| `header.competitions[].competitors[].fouls.foulsToGive` | number | 100% | e.g. 2, 1 |
| `header.competitions[].competitors[].fouls.teamFouls` | number | 100% | e.g. 5, 4 |
| `header.competitions[].competitors[].fouls.teamFoulsCurrent` | number | 100% | e.g. 2, 3 |
| `header.competitions[].competitors[].team.groups.isConference` | boolean | 100% | values: true (8) |
| `header.competitions[].competitors[].team.groups.parent.id` | str-numeric | 100% | values: "50" (8) |
| `header.competitions[].competitors[].team.groups.parent.name` | string | 100% | values: "NCAA Division I" (8) |
| `header.competitions[].competitors[].team.groups.parent.slug` | string | 100% | values: "ncaa-division-i" (8) |
| `header.competitions[].competitors[].team.groups.slug` | string | 100% | values: "big-ten-conference" (5), "big-east-conference" (1), "big-12-conference" (1), "southeastern-conference" (1) |
| `header.competitions[].groups.midsizeName` | string | 100% | e.g. "Big Ten" |
| `header.competitions[].groups.shortName` | string | 100% | e.g. "Big Ten" |
| `header.competitions[].possessionArrowAvailable` | boolean | 100% | values: false (12) |
| `header.competitions[].timeoutsAvailable` | boolean | 100% | values: true (8), false (4) |
| `news.articles[].categories[].series.description` | string | 100% | e.g. "NBA Today" |
| `plays[].pointsAttempted` | number | 100% | values: 0 (158), 2 (81), 3 (42), 1 (19) |
| `plays[].shortDescription` | string | 100% | values: "Rebound" (68), "+2 Points" (43), "Missed FG" (38), "Missed 3PT" (31), "Foul" (29), "Turnover" (24), "Jump Ball" (20), "+1 Point" (15), "Substitution" (12), "+3 Points" (11), "Missed FT" (4), "Steal" (2), "Challenge" (1), "Violation" (1), "Blocked Shot" (1) |
| `boxscore.players[].statistics[].athletes[].reason` | string | 63% | values: "COACH'S DECISION" (209) |
| `header.competitions[].tournamentId` | number | 17% | e.g. 22, 161 |
| `header.competitions[].competitors[].timeoutsRemaining` | number | 8% | e.g. 4, 5 |
| `header.competitions[].competitors[].timeoutsUsed` | number | 8% | e.g. 1, 0 |
| `header.competitions[].status.type.statusSecondary` | string | 8% | e.g. "2nd" |
| `seasonseries[].events[].statusType.statusSecondary` | string | 2% | e.g. "2nd" |
| `header.competitions[].competitors[].team.groups.id` | str-numeric | 100% | values: "7" (5), "5" (2), "1" (2), "151" (2), "4" (2), "8" (2), "23" (1) |
| `header.competitions[].groups.abbreviation` | string | 100% | values: "2000/2001" (12), "2001-2002" (4), "2001/2002" (4), "Group 1" (4), "B" (2), "big10" (2), "A" (1), "H" (1) |
| `header.competitions[].groups.id` | str-numeric | 100% | values: "1" (25), "2" (2), "7" (2), "8" (1) |
| `header.competitions[].groups.name` | string | 100% | values: "English Premiership 2001-2002" (4), "2000/2001 Italian Serie A " (4), "German Bundesliga 2000/2001" (4), "2000/2001 Spanish Primera División " (4), "French Ligue 1 2001/2002" (4), "Group 1" (4), "Group B" (2), "Big Ten Conference" (2), "Group A" (1), "Group H" (1) |
| `header.competitions[].shotChartAvailable` | boolean | 100% | values: true (15), false (1) |
| `leaders[].leaders[].leaders[].athlete.injuries.details.fantasyStatus.abbreviation` | string | 100% | values: "QUESTIONABLE" (5), "OUT" (3), "GTD" (2) |
| `leaders[].leaders[].leaders[].athlete.injuries.details.fantasyStatus.description` | string | 100% | values: "QUESTIONABLE" (5), "OUT" (3), "GTD" (2) |
| `leaders[].leaders[].leaders[].athlete.injuries.details.fantasyStatus.displayDescription` | string | 100% | values: "Questionable" (4), "Out" (3), "GTD" (2) |
| `leaders[].leaders[].leaders[].athlete.injuries.details.returnDate` | string | 100% | values: "2026-08-01" (3), "2026-07-01" (2), "2026-10-01" (2), "2026-07-09" (2), "2026-07-08" (1) |
| `leaders[].leaders[].leaders[].athlete.injuries.details.type` | string | 100% | values: "Wrist" (2), "Leg" (2), "Shoulder" (1), "Ankle" (1), "Elbow" (1), "Achilles" (1), "Foot" (1), "Back" (1) |
| `leaders[].leaders[].leaders[].athlete.injuries.status` | string | 100% | values: "Active" (9), "Questionable" (5), "Out" (3), "Day-To-Day" (2) |
| `leaders[].leaders[].leaders[].statistics[].abbreviation` | string | 100% | e.g. "SHOT", "SOG", "AC.PASS", "PASS" |
| `leaders[].leaders[].leaders[].statistics[].description` | string | 100% | e.g. "The number of shots attempted.", "The number of shots that are on goal.", "The number of passes completed.", "The number of passes attempted." |
| `leaders[].leaders[].leaders[].statistics[].displayName` | string | 100% | e.g. "Shots", "Shots On Goal", "Accurate Passes", "Passes" |
| `leaders[].leaders[].leaders[].statistics[].displayValue` | str-numeric | 100% | e.g. "1", "2", "3", "0" |
| `leaders[].leaders[].leaders[].statistics[].name` | string | 100% | e.g. "totalShots", "shotsOnTarget", "accuratePasses", "totalPasses" |
| `leaders[].leaders[].leaders[].statistics[].shortDisplayName` | string | 100% | e.g. "SHOT", "SOG", "ACPASS", "PASS" |
| `leaders[].leaders[].leaders[].statistics[].value` | number | 100% | e.g. 1, 2, 3, 0 |
| `pickcenter[].moneyline.away.live.odds` | string | 100% | e.g. "+100", "-144" |
| `pickcenter[].moneyline.home.live.odds` | string | 100% | e.g. "-130", "+111" |
| `pickcenter[].pointSpread.away.live.line` | string | 100% | e.g. "+1.5", "-1.5" |
| `pickcenter[].pointSpread.away.live.odds` | string | 100% | e.g. "-120", "+132" |
| `pickcenter[].pointSpread.home.live.line` | string | 100% | e.g. "-1.5", "+1.5" |
| `pickcenter[].pointSpread.home.live.odds` | str-numeric | 100% | e.g. "-110", "-173" |
| `pickcenter[].total.over.live.line` | string | 100% | e.g. "o169.5", "o6.5" |
| `pickcenter[].total.over.live.odds` | str-numeric | 100% | e.g. "-120", "-145" |
| `pickcenter[].total.under.live.line` | string | 100% | e.g. "u169.5", "u6.5" |
| `pickcenter[].total.under.live.odds` | string | 100% | e.g. "-110", "+111" |
| `plays[].coordinate.x` | number | 100% | e.g. 25, -214748340, 26, 28 |
| `plays[].coordinate.y` | number | 100% | e.g. 0, -214748365, 2, 1 |
| `plays[].shootingPlay` | boolean | 100% | values: true (217), false (158) |

## Go deeper

- Full field tables: [scoreboard](../scoreboard.md) · [summary](../summary.md) · [standings](../standings.md) · [teams](../teams.md) · [team-roster](../team-roster.md) · [rankings](../rankings.md)
- Canonical shape, ESPN→canonical mappings, per-league period/OT matrix: `schema/SCHEMA.md`, `schema/canonical.ts`
- Cross-sport support matrix: [index.md](../index.md)
