# ESPN API — baseball

> Per-sport slice of the [observed data guide](../index.md): what ESPN actually serves for **baseball**, and which endpoint answers each need. Built from 147 real baseball responses — OBSERVED live, not documented. Regenerate: `node schema/tools/rollup.mjs`.

## Leagues — 12 in the registry

Competition **shape** drives rendering (see the discriminators in `schema/canonical.ts`): `layout · scoreKind · competitorKind`.

| shape (layout · scoreKind · competitorKind) | leagues | examples |
|---|---|---|
| `headToHead · numeric · team` | 12 | `mlb`, `college-baseball`, `college-softball`, `world-baseball-classic` |

**Crawled for this guide** (1): `baseball/mlb`. The evidence below is from these leagues; other baseball leagues in the registry inherit the same shape.

## Which endpoint to use

URL templates use `baseball/mlb` as a representative league. Swap in any league key from the table above.

| need | endpoint | status | URL template | fields |
|---|---|---|---|---|
| Scores & live state | `scoreboard` | ✅ 14/14 | `https://site.api.espn.com/apis/site/v2/sports/baseball/mlb/scoreboard` | [guide](../scoreboard.md) |
| Rich game detail | `summary` | ✅ 4/4 | `https://site.api.espn.com/apis/site/v2/sports/baseball/mlb/summary?event={eventId}` | [guide](../summary.md) |
| League table | `standings` | ✅ 2/2 | `https://site.api.espn.com/apis/v2/sports/baseball/mlb/standings` | [guide](../standings.md) |
| Team directory | `teams` | ✅ 1/1 | `https://site.api.espn.com/apis/site/v2/sports/baseball/mlb/teams` | [guide](../teams.md) |
| Roster | `team-roster` | ✅ 2/2 | `https://site.api.espn.com/apis/site/v2/sports/baseball/mlb/teams/{teamId}/roster` | [guide](../team-roster.md) |
| Schedule | `team-schedule` | ✅ 1/1 | `https://site.api.espn.com/apis/site/v2/sports/baseball/mlb/teams/{teamId}/schedule` | [guide](../team-schedule.md) |
| Team season stats | `team-stats` | ✅ 1/1 | `https://site.api.espn.com/apis/site/v2/sports/baseball/mlb/teams/{teamId}/statistics` | [guide](../team-stats.md) |
| News | `news` | ✅ 1/1 | `https://site.api.espn.com/apis/site/v2/sports/baseball/mlb/news?limit=5` | [guide](../news.md) |
| Injuries | `injuries` | ✅ 1/1 | `https://site.api.espn.com/apis/site/v2/sports/baseball/mlb/teams/{teamId}/injuries` | [guide](../injuries.md) |

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

120 of the core resource shapes were reachable for baseball by following `$ref` links from the league root and its events (full matrix: [index.md](../index.md#core-api-resource-graph)). High-value shapes:

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

Value-bearing fields observed for baseball that are **not** near-universal — the sport's fingerprint. **presence** = % of this sport's crawled responses (or parent objects) that carry the field (baseball-specific). Field paths, types, and presence are baseball-only; the **value/example samples are pooled** across the handful of sports that share a field (a nested `period` may show golf's "18" next to a fight's "1–3"), so read them as shape hints. The full per-sport field tables live in the per-endpoint guides linked above.

### scoreboard

| field | type | presence | values / examples |
|---|---|---|---|
| `events[].competitions[].competitors[].errors` | number | 100% | values: 0 (282), 1 (139), 2 (45), 3 (9), 4 (1) |
| `events[].competitions[].competitors[].hits` | number | 100% | e.g. 6, 8, 7, 5 |
| `events[].competitions[].competitors[].probables[].statistics[].abbreviation` | string | 100% | values: "SV" (474), "L" (474), "W" (474), "ERA" (474), "E" (467), "H" (56), "R" (56), "AVG" (56) |
| `events[].competitions[].competitors[].probables[].statistics[].displayValue` | str-numeric | 100% | e.g. "0", "1", "2", "3" |
| `events[].competitions[].competitors[].probables[].statistics[].name` | string | 100% | values: "saves" (474), "losses" (474), "wins" (474), "ERA" (474), "errors" (467), "hits" (56), "runs" (56), "avg" (56) |
| `events[].competitions[].odds[].awayTeamOdds.close.pointSpread.alternateDisplayValue` | str-numeric | 100% | e.g. "-0" |
| `events[].competitions[].odds[].awayTeamOdds.close.pointSpread.american` | str-numeric | 100% | e.g. "-0" |
| `events[].competitions[].odds[].homeTeamOdds.close.pointSpread.alternateDisplayValue` | string | 100% | e.g. "+0" |
| `events[].competitions[].odds[].homeTeamOdds.close.pointSpread.american` | string | 100% | e.g. "+0" |
| `events[].competitions[].odds[].homeTeamOdds.close.pointSpread.decimal` | number | 100% | e.g. 0 |
| `events[].competitions[].odds[].homeTeamOdds.close.pointSpread.value` | number | 100% | e.g. 0 |
| `events[].competitions[].situation.balls` | number | 100% | values: 0 (8), 1 (4) |
| `events[].competitions[].situation.batter.period` | number | 100% | values: 7 (3), 6 (2), 5 (2), 4 (1), 2 (1) |
| `events[].competitions[].situation.batter.playerId` | number | 100% | values: 4414531 (1), 5205951 (1), 37537 (1), 31662 (1), 4109223 (1), 33809 (1), 4917927 (1), 31095 (1), 31392 (1) |
| `events[].competitions[].situation.batter.summary` | string | 100% | values: "0-1" (2), "1-3, 2 K" (1), "1-2, K" (1), "1-2" (1), "0-3" (1), "1-1, 2 R, BB" (1), "1-2, SB" (1), "0-1, K" (1) |
| `events[].competitions[].situation.dueUp[].batOrder` | number | 100% | values: 8 (2), 9 (2), 1 (1), 2 (1), 3 (1), 4 (1), 7 (1) |
| `events[].competitions[].situation.dueUp[].period` | number | 100% | values: 4 (3), 7 (3), 3 (3) |
| `events[].competitions[].situation.dueUp[].playerId` | number | 100% | values: 34895 (1), 38905 (1), 4717833 (1), 42796 (1), 41917 (1), 41326 (1), 41610 (1), 36950 (1), 40086 (1) |
| `events[].competitions[].situation.dueUp[].summary` | string | 100% | values: "0-1" (1), "0-0, R, BB" (1), "1-2, K" (1), "0-2, RBI, 2 K" (1), "1-3" (1), "1-3, K" (1), "0-1, K" (1), "1-1, HR, RBI, R" (1), "1-1, R" (1) |
| `events[].competitions[].situation.lastPlay.atBatId` | str-numeric | 100% | values: "4018160550705" (1), "4018160531203" (1), "4018160541202" (1), "4018160581203" (1), "4018160601204" (1), "4018160561006" (1), "4018160570804" (1), "4018160591003" (1), "4018160620503" (1), "4018160630603" (1), "4018160640801" (1), "4018160610306" (1) |
| `events[].competitions[].situation.lastPlay.type.type` | string | 100% | values: "foul-ball" (4), "end-inning" (3), "start-batterpitcher" (3), "strike-looking" (1), "strike-swinging" (1) |
| `events[].competitions[].situation.onFirst` | boolean | 100% | values: false (8), true (4) |
| `events[].competitions[].situation.onSecond` | boolean | 100% | values: false (10), true (2) |
| `events[].competitions[].situation.onThird` | boolean | 100% | values: false (9), true (3) |
| `events[].competitions[].situation.outs` | number | 100% | values: 0 (6), 2 (4), 1 (2) |
| `events[].competitions[].situation.pitcher.period` | number | 100% | values: 7 (3), 6 (2), 5 (2), 4 (1), 2 (1) |
| `events[].competitions[].situation.pitcher.playerId` | number | 100% | values: 41125 (1), 4298378 (1), 5001153 (1), 41310 (1), 42848 (1), 4414528 (1), 42480 (1), 4415836 (1), 40973 (1) |
| `events[].competitions[].situation.pitcher.summary` | string | 100% | values: "0.1 IP, 0 ER, 0 H, 0 BB" (1), "0.1 IP, 0 ER, 0 H, K, 0 BB" (1), "0.2 IP, 0 ER, 4 H, K, 0 BB" (1), "0.0 IP, 0 ER, 0 H, 0 BB" (1), "0.0 IP, ER, 2 H, 0 BB" (1), "5.2 IP, 3 ER, 5 H, 8 K, 0 BB" (1), "3.1 IP, ER, 2 H, 6 K, 0 BB" (1), "4.0 IP, ER, 2 H, 3 K, 0 BB" (1), "1.2 IP, 2 ER, H, 2 BB" (1) |
| `events[].competitions[].situation.strikes` | number | 100% | values: 0 (6), 2 (3), 1 (2), 3 (1) |
| `events[].competitions[].competitors[].probables[].statistics[].rankDisplayValue` | string | 79% | e.g. "Tied-195th", "Tied-519th", "Tied-219th", "Tied-96th" |
| `events[].competitions[].situation.lastPlay.summaryType` | string | 75% | values: "P" (6), "A" (3) |
| `events[].competitions[].situation.lastPlay.type.abbreviation` | string | 50% | e.g. "F", "SL", "SS" |
| `events[].competitions[].situation.lastPlay.type.alternativeText` | string | 42% | e.g. "Now at bat", "Strikeout" |
| `events[].competitions[].outsText` | string | 5% | values: "0 Outs" (6), "2 Outs" (4), "1 Out" (2) |
| `events[].competitions[].competitors[].probables[].abbreviation` | string | 100% | values: "SP" (474), "SG" (392) |
| `events[].competitions[].competitors[].probables[].displayName` | string | 100% | values: "Probable Starting Pitcher" (474), "Probable Starting Goalie" (392) |
| `events[].competitions[].competitors[].probables[].name` | string | 100% | values: "probableStartingPitcher" (474), "probableStartingGoalie" (392) |
| `events[].competitions[].competitors[].probables[].playerId` | number | 100% | e.g. 4588165, 2517899, 3942065, 3942459 |
| `events[].competitions[].competitors[].probables[].record` | string | 100% | e.g. "", "(5-4, 3.88)", "(0-0, 2.25)", "(10-4, 1.62)" |
| `events[].competitions[].competitors[].probables[].shortDisplayName` | string | 100% | values: "Starter" (866) |
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
| `events[].competitions[].status.featuredAthletes[].statistics[].abbreviation` | string | 100% | values: "SV" (1520), "SV%" (977), "+/-" (977), "G" (977), "YTDG" (977), "A" (977), "PTS" (977), "L" (543), "W" (543), "ERA" (543), "E" (543), "H" (244), "R" (244), "AVG" (244) |
| `events[].competitions[].status.featuredAthletes[].statistics[].displayValue` | string | 100% | e.g. "0", "1", ".000", "2" |

### summary

| field | type | presence | values / examples |
|---|---|---|---|
| `boxscore.players[].statistics[].athletes[].atBats[].atBatId` | str-numeric | 100% | e.g. "4018717900001", "4018717900403", "4018717900802", "4018717901203" |
| `boxscore.players[].statistics[].athletes[].atBats[].id` | str-numeric | 100% | e.g. "4018717900001990057", "4018717900403990057", "4018717900802990057", "4018717901203990057" |
| `boxscore.players[].statistics[].athletes[].atBats[].playId` | str-numeric | 100% | e.g. "4018717900001990057", "4018717900403990057", "4018717900802990057", "4018717901203990057" |
| `boxscore.players[].statistics[].athletes[].athlete.positions[].abbreviation` | string | 100% | values: "DH" (51), "PH" (41), "P" (38), "RP" (25), "SS" (24), "LF" (23), "CF" (22), "RF" (22), "3B" (21), "SP" (20), "2B" (19), "1B" (16), "C" (11), "PR" (9) |
| `boxscore.players[].statistics[].athletes[].athlete.positions[].displayName` | string | 100% | values: "Designated Hitter" (51), "Pinch Hitter" (41), "Pitcher" (38), "Relief Pitcher" (25), "Shortstop" (24), "Left Fielder" (23), "Center Fielder" (22), "Right Fielder" (22), "Third Baseman" (21), "Starting Pitcher" (20), "Second Baseman" (19), "First Baseman" (16), "Catcher" (11), "Pinch Runner" (9) |
| `boxscore.players[].statistics[].athletes[].athlete.positions[].id` | str-numeric | 100% | values: "10" (51), "11" (41), "1" (38), "0" (25), "6" (24), "7" (23), "8" (22), "9" (22), "5" (21), "15" (20), "4" (19), "3" (16), "2" (11), "12" (9) |
| `boxscore.players[].statistics[].athletes[].athlete.positions[].leaf` | boolean | 100% | values: true (295), false (47) |
| `boxscore.players[].statistics[].athletes[].athlete.positions[].name` | string | 100% | values: "Designated Hitter" (51), "Pinch Hitter" (41), "Pitcher" (38), "Relief Pitcher" (25), "Shortstop" (24), "Left Field" (23), "Center Field" (22), "Right Field" (22), "Third Base" (21), "Starting Pitcher" (20), "Second Base" (19), "First Base" (16), "Catcher" (11), "Pinch Runner" (9) |
| `boxscore.players[].statistics[].athletes[].batOrder` | number | 100% | values: 0 (35), 9 (13), 2 (12), 5 (12), 1 (11), 4 (11), 6 (11), 7 (11), 3 (10), 8 (9) |
| `boxscore.players[].statistics[].athletes[].notes[].text` | string | 100% | e.g. "B, 1", "H, 2", "H, 1", "a-grounded to shortstop for Bauers in the 7th" |
| `boxscore.players[].statistics[].athletes[].notes[].type` | string | 100% | values: "pitchingDecision" (15), "lineup" (5) |
| `boxscore.players[].statistics[].athletes[].position.abbreviation` | string | 100% | values: "P" (35), "2B" (12), "LF" (11), "C" (11), "1B" (11), "CF" (11), "RF" (11), "DH" (10), "SS" (10), "3B" (10), "PH" (2), "PR" (1) |
| `boxscore.players[].statistics[].athletes[].position.displayName` | string | 100% | values: "Pitcher" (35), "Second Baseman" (12), "Left Fielder" (11), "Catcher" (11), "First Baseman" (11), "Center Fielder" (11), "Right Fielder" (11), "Designated Hitter" (10), "Shortstop" (10), "Third Baseman" (10), "Pinch Hitter" (2), "Pinch Runner" (1) |
| `boxscore.players[].statistics[].athletes[].position.id` | str-numeric | 100% | values: "1" (35), "4" (12), "7" (11), "2" (11), "3" (11), "8" (11), "9" (11), "10" (10), "6" (10), "5" (10), "11" (2), "12" (1) |
| `boxscore.players[].statistics[].athletes[].position.name` | string | 100% | values: "Pitcher" (35), "Second Base" (12), "Left Field" (11), "Catcher" (11), "First Base" (11), "Center Field" (11), "Right Field" (11), "Designated Hitter" (10), "Shortstop" (10), "Third Base" (10), "Pinch Hitter" (2), "Pinch Runner" (1) |
| `boxscore.players[].statistics[].athletes[].positions[].abbreviation` | string | 100% | values: "PH" (5), "DH" (3), "PR" (2), "2B" (2), "P" (2), "1B" (1), "RF" (1), "CF" (1) |
| `boxscore.players[].statistics[].athletes[].positions[].displayName` | string | 100% | values: "Pinch Hitter" (5), "Designated Hitter" (3), "Pinch Runner" (2), "Second Baseman" (2), "Pitcher" (2), "First Baseman" (1), "Right Fielder" (1), "Center Fielder" (1) |
| `boxscore.players[].statistics[].athletes[].positions[].id` | str-numeric | 100% | values: "11" (5), "10" (3), "12" (2), "4" (2), "1" (2), "3" (1), "9" (1), "8" (1) |
| `boxscore.players[].statistics[].athletes[].positions[].name` | string | 100% | values: "Pinch Hitter" (5), "Designated Hitter" (3), "Pinch Runner" (2), "Second Base" (2), "Pitcher" (2), "First Base" (1), "Right Field" (1), "Center Field" (1) |
| `boxscore.players[].statistics[].type` | string | 100% | values: "batting" (8), "pitching" (8) |
| `boxscore.teams[].details[].displayName` | string | 100% | values: "Batting" (8), "Pitching" (8), "Fielding" (5), "Baserunning" (3) |
| `boxscore.teams[].details[].name` | string | 100% | values: "battingDetails" (8), "pitchingDetails" (8), "fieldingDetails" (5), "baserunningDetails" (3) |
| `boxscore.teams[].details[].stats[].abbreviation` | string | 100% | e.g. "Team LOB", "Team RISP", "GS", "RBI" |
| `boxscore.teams[].details[].stats[].displayName` | string | 100% | e.g. "Team Left On Base", "Team Runners Left In Scoring Position", "Game Scores", "Runs Batted In" |
| `boxscore.teams[].details[].stats[].displayValue` | string | 100% | e.g. "5", "Yelich 2 (12, Svanson, Romero); Bauers 2 (15, Zimmermann 2); Ortiz (6, Zimmerman…", "Yelich 2 (30), Ortiz (21), Mitchell (43)", "Mitchell." |
| `boxscore.teams[].details[].stats[].name` | string | 100% | e.g. "teamLOB", "teamRISP", "gameScores", "rbi" |
| `boxscore.teams[].details[].stats[].shortDisplayName` | string | 100% | e.g. "Team LOB", "Team RISP", "GS", "RBI" |
| `gameInfo.weather.conditionId` | string | 100% | e.g. "Cloudy" |
| `gameInfo.weather.gust` | number | 100% | e.g. 5 |
| `gameInfo.weather.highTemperature` | number | 100% | e.g. 78 |
| `gameInfo.weather.lowTemperature` | number | 100% | e.g. 78 |
| `gameInfo.weather.precipitation` | number | 100% | e.g. 42 |
| `gameInfo.weather.temperature` | number | 100% | e.g. 78 |
| `header.competitions[].competitors[].errors` | number | 100% | values: 0 (7), 1 (1) |
| `header.competitions[].competitors[].hits` | number | 100% | values: 5 (2), 10 (1), 6 (1), 14 (1), 11 (1), 3 (1), 2 (1) |
| `header.competitions[].competitors[].linescores[].errors` | number | 100% | values: 0 (64), 1 (1) |
| `header.competitions[].competitors[].linescores[].hits` | number | 100% | values: 0 (26), 1 (24), 2 (13), 3 (2) |
| `header.competitions[].competitors[].probables[].abbreviation` | string | 100% | values: "SP" (8) |
| `header.competitions[].competitors[].probables[].athlete.lastName` | string | 100% | values: "Svanson" (1), "Misiorowski" (1), "Lopez" (1), "Rasmussen" (1), "Scherzer" (1), "Ohtani" (1), "Baz" (1), "Boyd" (1) |
| `header.competitions[].competitors[].probables[].athlete.status.abbreviation` | string | 100% | values: "Active" (7), "15 Day IL" (1) |
| `header.competitions[].competitors[].probables[].athlete.status.id` | str-numeric | 100% | values: "1" (7), "25" (1) |
| `header.competitions[].competitors[].probables[].athlete.status.name` | string | 100% | values: "Active" (7), "15 Day IL" (1) |
| `header.competitions[].competitors[].probables[].athlete.status.type` | string | 100% | values: "active" (7), "15-day-il" (1) |
| `header.competitions[].competitors[].probables[].athlete.throws.abbreviation` | string | 100% | values: "R" (7), "L" (1) |
| `header.competitions[].competitors[].probables[].athlete.throws.displayValue` | string | 100% | values: "Right" (7), "Left" (1) |
| `header.competitions[].competitors[].probables[].athlete.throws.type` | string | 100% | values: "RIGHT" (7), "LEFT" (1) |
| `header.competitions[].competitors[].probables[].displayName` | string | 100% | values: "Probable Starting Pitcher" (8) |
| `header.competitions[].competitors[].probables[].name` | string | 100% | values: "probableStartingPitcher" (8) |
| `header.competitions[].competitors[].probables[].playerId` | number | 100% | values: 4649953 (1), 5080761 (1), 33860 (1), 42584 (1), 28976 (1), 39832 (1), 39639 (1), 34401 (1) |
| `header.competitions[].competitors[].probables[].shortDisplayName` | string | 100% | values: "Starter" (8) |
| `header.competitions[].competitors[].probables[].statistics.splits.categories[].abbreviation` | string | 100% | values: "K" (8), "L" (8), "H" (8), "BB" (8), "HR" (8), "W" (8), "FI" (8), "PI" (8), "ERA" (8), "WHIP" (8) |
| `header.competitions[].competitors[].probables[].statistics.splits.categories[].displayValue` | str-numeric | 100% | e.g. "2", "1", "4", "0" |
| `header.competitions[].competitors[].probables[].statistics.splits.categories[].name` | string | 100% | values: "strikeouts" (8), "losses" (8), "hits" (8), "walks" (8), "homeRuns" (8), "wins" (8), "fullInnings" (8), "partInnings" (8), "ERA" (8), "WHIP" (8) |
| `header.competitions[].competitors[].probables[].statistics.splits.categories[].value` | number | 100% | e.g. 2, 1, 4, 0 |
| `header.competitions[].status.featuredAthletes[].athlete.record` | string | 100% | values: "10-4" (1), "2-2" (1), "4-2" (1), "1-0" (1), "0-1" (1), "0-0" (1), "5-1" (1), "2-1" (1) |

## Go deeper

- Full field tables: [scoreboard](../scoreboard.md) · [summary](../summary.md) · [standings](../standings.md) · [teams](../teams.md) · [team-roster](../team-roster.md) · [rankings](../rankings.md)
- Canonical shape, ESPN→canonical mappings, per-league period/OT matrix: `schema/SCHEMA.md`, `schema/canonical.ts`
- Cross-sport support matrix: [index.md](../index.md)
