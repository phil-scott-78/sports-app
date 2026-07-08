# ESPN API — football

> Per-sport slice of the [observed data guide](../index.md): what ESPN actually serves for **football**, and which endpoint answers each need. Built from 236 real football responses — OBSERVED live, not documented. Regenerate: `node schema/tools/rollup.mjs`.

## Leagues — 4 in the registry

Competition **shape** drives rendering (see the discriminators in `schema/canonical.ts`): `layout · scoreKind · competitorKind`.

| shape (layout · scoreKind · competitorKind) | leagues | examples |
|---|---|---|
| `headToHead · numeric · team` | 4 | `nfl`, `college-football`, `ufl`, `cfl` |

**Crawled for this guide** (2): `football/college-football`, `football/nfl`. The evidence below is from these leagues; other football leagues in the registry inherit the same shape.

## Which endpoint to use

URL templates use `football/college-football` as a representative league. Swap in any league key from the table above.

| need | endpoint | status | URL template | fields |
|---|---|---|---|---|
| Scores & live state | `scoreboard` | ✅ 28/28 | `https://site.api.espn.com/apis/site/v2/sports/football/college-football/scoreboard` | [guide](../scoreboard.md) |
| Rich game detail | `summary` | ✅ 8/8 | `https://site.api.espn.com/apis/site/v2/sports/football/college-football/summary?event={eventId}` | [guide](../summary.md) |
| League table | `standings` | ✅ 4/4 | `https://site.api.espn.com/apis/v2/sports/football/college-football/standings` | [guide](../standings.md) |
| Team directory | `teams` | ✅ 2/2 | `https://site.api.espn.com/apis/site/v2/sports/football/college-football/teams` | [guide](../teams.md) |
| Roster | `team-roster` | ✅ 4/4 | `https://site.api.espn.com/apis/site/v2/sports/football/college-football/teams/{teamId}/roster` | [guide](../team-roster.md) |
| Schedule | `team-schedule` | ✅ 2/2 | `https://site.api.espn.com/apis/site/v2/sports/football/college-football/teams/{teamId}/schedule` | [guide](../team-schedule.md) |
| Team season stats | `team-stats` | ✅ 1/2 | `https://site.api.espn.com/apis/site/v2/sports/football/college-football/teams/{teamId}/statistics` | [guide](../team-stats.md) |
| Polls / rankings | `rankings` | ✅ 1/1 | `https://site.api.espn.com/apis/site/v2/sports/football/college-football/rankings` | [guide](../rankings.md) |
| News | `news` | ✅ 2/2 | `https://site.api.espn.com/apis/site/v2/sports/football/college-football/news?limit=5` | [guide](../news.md) |
| Injuries | `injuries` | ✅ 2/2 | `https://site.api.espn.com/apis/site/v2/sports/football/college-football/teams/{teamId}/injuries` | [guide](../injuries.md) |

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

119 of the core resource shapes were reachable for football by following `$ref` links from the league root and its events (full matrix: [index.md](../index.md#core-api-resource-graph)). High-value shapes:

| resource | reachable | what it adds |
|---|---|---|
| `core-competitor-linescores` | ✅ | Per-period / per-set / per-inning scores — reachable even when the site scoreboard omits them (tennis sets, cricket innings). |
| `core-situation` | ✅ | Live game situation (baseball base/out, gridiron down & distance). |
| `core-plays` | ✅ | Play-by-play feed. |
| `core-competition-plays-id` | ✅ | Individual play detail. |
| `core-odds` | ✅ | Betting lines / odds. |
| `core-probabilities` | ✅ | Win-probability timeline. |
| `core-predictor` | ✅ | Pre-game matchup prediction. |
| `core-competition-powerindex` | ✅ | Team power-index / matchup metrics. |
| `core-competitor-roster` | ✅ | Game-day lineup. |
| `core-competitor-statistics` | ✅ | Competitor's game statistics. |
| `core-season-types-id-groups-id-standings` | ✅ | Standings through the core graph (grouped). |
| `core-rankings` | ✅ | Rankings through the core graph. |
| `core-season-futures` | ✅ | Season futures (championship odds). |

## What's sport-specific in the data

Value-bearing fields observed for football that are **not** near-universal — the sport's fingerprint. **presence** = % of this sport's crawled responses (or parent objects) that carry the field (football-specific). Field paths, types, and presence are football-only; the **value/example samples are pooled** across the handful of sports that share a field (a nested `period` may show golf's "18" next to a fight's "1–3"), so read them as shape hints. The full per-sport field tables live in the per-endpoint guides linked above.

### scoreboard

| field | type | presence | values / examples |
|---|---|---|---|
| `events[].competitions[].dateValid` | boolean | 50% | values: true (123) |
| `events[].competitions[].status.isTBDFlex` | boolean | 50% | values: false (122) |
| `events[].competitions[].groups.id` | str-numeric | 100% | e.g. "4", "13", "8", "1" |
| `events[].competitions[].groups.isConference` | boolean | 100% | values: true (125) |
| `events[].competitions[].groups.name` | string | 100% | e.g. "Big Ten Conference", "Atlantic Coast Conference", "American Conference", "Metro Atlantic Athletic Conference" |
| `events[].competitions[].groups.shortName` | string | 100% | e.g. "Big Ten", "ACC", "American", "MAAC" |
| `events[].competitions[].competitors[].team.conferenceId` | str-numeric | 50% | e.g. "8", "4", "5", "1" |
| `groups[]` | str-numeric | — | values: "80" (14), "50" (14) |
| `events[].competitions[].leaders[].abbreviation` | string | 100% | values: "RAT" (235), "PYDS" (203), "RYDS" (203), "RECYDS" (203), "G" (78), "D" (78) |
| `events[].competitions[].leaders[].displayName` | string | 100% | values: "MLB Rating" (235), "Passing Leader" (203), "Rushing Leader" (203), "Receiving Leader" (203), "Goals" (78), "Disposals" (78) |
| `events[].competitions[].leaders[].leaders[].displayValue` | string | 100% | e.g. "4 REC, 78 YDS, 1 TD", "8 REC, 96 YDS, 1 TD", "4 REC, 62 YDS", "5 REC, 68 YDS" |
| `events[].competitions[].leaders[].leaders[].team.id` | str-numeric | 100% | e.g. "8", "14", "6", "16" |
| `events[].competitions[].leaders[].leaders[].value` | number | 100% | e.g. 3, 67, 68.25, 69 |
| `events[].competitions[].leaders[].name` | string | 100% | values: "MLBRating" (235), "passingYards" (203), "rushingYards" (203), "receivingYards" (203), "goals" (78), "disposals" (78) |
| `events[].competitions[].leaders[].shortDisplayName` | string | 100% | values: "RAT" (235), "PASS" (203), "RUSH" (203), "REC" (203), "G" (78), "D" (78) |
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
| `events[].week.number` | number | 100% | e.g. 1, 18, 2, 10 |
| `leagues[].calendar[].entries[].alternateLabel` | string | 100% | e.g. "Week 1", "Week 2", "Week 3", "Week 4" |
| `leagues[].calendar[].value` | str-numeric | 100% | values: "2" (4), "1" (3), "3" (3), "4" (2) |
| `week.number` | number | 100% | e.g. 1, 18, 4, 13 |
| `events[].competitions[].odds[].awayTeamOdds.team.abbreviation` | string | 100% | e.g. "CHI", "ARI", "SJSU", "MON" |
| `events[].competitions[].odds[].awayTeamOdds.team.displayName` | string | 100% | e.g. "San José State Spartans", "Chicago Sky", "Monza", "Como" |
| `events[].competitions[].odds[].awayTeamOdds.team.id` | str-numeric | 100% | e.g. "5", "27", "23", "19" |
| `events[].competitions[].odds[].details` | string | 100% | e.g. "PHX -4.5", "MUN -390", "ALA +135", "ATM -350" |
| `events[].competitions[].odds[].homeTeamOdds.team.abbreviation` | string | 100% | e.g. "EMU", "PHX", "INT", "UDI" |
| `events[].competitions[].odds[].homeTeamOdds.team.displayName` | string | 100% | e.g. "Eastern Michigan Eagles", "Phoenix Mercury", "Internazionale", "Udinese" |
| `events[].competitions[].odds[].homeTeamOdds.team.id` | str-numeric | 100% | e.g. "11", "26", "30", "24" |
| `events[].competitions[].odds[].moneyline.away.close.odds` | string | 100% | e.g. "+145", "OFF", "+260", "+550" |
| `events[].competitions[].odds[].moneyline.away.open.odds` | string | 100% | e.g. "OFF", "+260", "+142", "+230" |
| `events[].competitions[].odds[].moneyline.displayName` | string | 100% | values: "Moneyline" (52) |
| `events[].competitions[].odds[].moneyline.home.close.odds` | string | 100% | e.g. "-175", "OFF", "-325", "-245" |
| `events[].competitions[].odds[].moneyline.home.open.odds` | string | 100% | e.g. "OFF", "-325", "-170", "-175" |
| `events[].competitions[].odds[].moneyline.shortDisplayName` | string | 100% | values: "ML" (52) |
| `events[].competitions[].odds[].overUnder` | number | 100% | e.g. 2.5, 3.5, 48.5, 49.5 |
| `events[].competitions[].odds[].pointSpread.away.close.line` | string | 100% | e.g. "+0.5", "+1.5", "+3.5", "+3" |
| `events[].competitions[].odds[].pointSpread.away.close.odds` | string | 100% | e.g. "-110", "+100", "-112", "-108" |
| `events[].competitions[].odds[].pointSpread.away.open.line` | string | 100% | e.g. "+0.5", "+1.5", "+3", "+2.5" |
| `events[].competitions[].odds[].pointSpread.away.open.odds` | string | 100% | e.g. "-110", "-115", "-112", "+100" |
| `events[].competitions[].odds[].pointSpread.displayName` | string | 100% | values: "Spread" (49), "Runline" (3) |
| `events[].competitions[].odds[].pointSpread.home.close.line` | string | 100% | e.g. "-0.5", "-1.5", "-3.5", "-3" |
| `events[].competitions[].odds[].pointSpread.home.close.odds` | string | 100% | e.g. "-110", "-120", "-108", "-112" |
| `events[].competitions[].odds[].pointSpread.home.open.line` | string | 100% | e.g. "-0.5", "-1.5", "-3", "-2.5" |
| `events[].competitions[].odds[].pointSpread.home.open.odds` | string | 100% | e.g. "-110", "-108", "-120", "-105" |
| `events[].competitions[].odds[].pointSpread.shortDisplayName` | string | 100% | values: "Spread" (49), "RL" (3) |
| `events[].competitions[].odds[].provider.id` | str-numeric | 100% | values: "100" (52), "2000" (4) |

### summary

| field | type | presence | values / examples |
|---|---|---|---|
| `boxscore.players[].statistics[].text` | string | 100% | e.g. "NFC Passing", "NFC Rushing", "NFC Receiving", "NFC Fumbles" |
| `boxscore.teams[].statistics[].value` | number \| string | 100% | e.g. "-", 1, 0, 2 |
| `drives.previous[].description` | string | 100% | e.g. "1 play, -1 yard, 0:43", "9 plays, 74 yards, 5:29", "4 plays, 15 yards, 2:07", "11 plays, 69 yards, 5:27" |
| `drives.previous[].displayResult` | string | 100% | values: "Punt" (37), "Touchdown" (24), "Field Goal" (14), "Interception" (11), "Missed FG" (7), "End of Half" (4), "Fumble" (4), "Downs" (2), "Interception Touchdown" (2), "Punt Touchdown" (1), "End Of Half" (1), "End of Game" (1) |
| `drives.previous[].end.clock.displayValue` | string | 100% | e.g. "0:02", "8:10", "0:01", "0:43" |
| `drives.previous[].end.period.number` | number | 100% | values: 2 (37), 4 (31), 1 (21), 3 (19) |
| `drives.previous[].end.period.type` | string | 100% | values: "quarter" (108) |
| `drives.previous[].end.text` | string | 100% | e.g. "MICH 3", "UNT 3", "50", "TULN 3" |
| `drives.previous[].end.yardLine` | number | 100% | e.g. 97, 3, 0, 36 |
| `drives.previous[].id` | str-numeric | 100% | e.g. "4017729691", "4017729692", "4017729693", "4017729694" |
| `drives.previous[].isScore` | boolean | 100% | values: false (67), true (41) |
| `drives.previous[].offensivePlays` | number | 100% | values: 3 (20), 6 (11), 9 (10), 4 (9), 7 (9), 5 (9), 8 (9), 10 (7), 1 (6), 2 (5), 13 (5), 11 (4), 12 (2), 15 (1), 16 (1) |
| `drives.previous[].plays[].awayScore` | number | 100% | values: 7 (226), 0 (137), 17 (104), 14 (89), 16 (65), 9 (46), 27 (45), 3 (41), 20 (41), 6 (37), 21 (31), 10 (22), 13 (17), 24 (6) |
| `drives.previous[].plays[].clock.displayValue` | string | 100% | e.g. "0:00", "15:00", "2:00", "0:26" |
| `drives.previous[].plays[].end.distance` | number | 100% | e.g. 10, 1, 6, 2 |
| `drives.previous[].plays[].end.down` | number | 100% | values: 1 (323), 2 (249), 3 (159), 4 (96), -1 (46), 0 (34) |
| `drives.previous[].plays[].end.team.id` | str-numeric | 100% | values: "27" (105), "11" (105), "130" (105), "2655" (101), "251" (96), "33" (88), "2390" (84), "249" (83), "194" (73), "29" (65) |
| `drives.previous[].plays[].end.yardLine` | number | 100% | e.g. 35, 75, 36, 65 |
| `drives.previous[].plays[].end.yardsToEndzone` | number | 100% | e.g. 0, 65, 75, 64 |
| `drives.previous[].plays[].homeScore` | number | 100% | values: 0 (168), 14 (114), 17 (92), 21 (84), 24 (74), 7 (70), 10 (70), 31 (62), 16 (49), 13 (41), 3 (39), 41 (18), 34 (16), 38 (10) |
| `drives.previous[].plays[].id` | str-numeric | 100% | e.g. "40177296939", "40177296951", "40177296962", "40177296994" |
| `drives.previous[].plays[].isPenalty` | boolean | 100% | values: false (860), true (47) |
| `drives.previous[].plays[].isTurnover` | boolean | 100% | values: false (890), true (17) |
| `drives.previous[].plays[].penalty.status.slug` | string | 100% | values: "accepted" (11) |
| `drives.previous[].plays[].penalty.status.text` | string | 100% | values: "Accepted" (11) |
| `drives.previous[].plays[].penalty.type.slug` | string | 100% | values: "delay-of-game" (3), "false-start" (2), "unnecessary-roughness" (1), "taunting" (1), "illegal-block-above-the-waist" (1), "illegal-contact" (1), "offensive-pass-interference" (1), "defensive-pass-interference" (1) |
| `drives.previous[].plays[].penalty.type.text` | string | 100% | values: "Delay of Game" (3), "False Start" (2), "Unnecessary Roughness" (1), "Taunting" (1), "Illegal Block Above the Waist" (1), "Illegal Contact" (1), "Offensive Pass Interference" (1), "Defensive Pass Interference" (1) |
| `drives.previous[].plays[].penalty.yards` | number | 100% | values: 5 (6), 13 (2), 10 (2), 15 (1) |
| `drives.previous[].plays[].period.number` | number | 100% | values: 2 (268), 4 (230), 1 (205), 3 (204) |
| `drives.previous[].plays[].pointAfterAttempt.abbreviation` | string | 100% | values: "Extra Point Good" (25), "Two Point Pass" (1), "Two Point Rush" (1) |
| `drives.previous[].plays[].pointAfterAttempt.id` | number | 100% | values: 61 (25), 15 (1), 16 (1) |
| `drives.previous[].plays[].pointAfterAttempt.text` | string | 100% | values: "Extra Point Good" (25), "Two Point Pass" (1), "Two Point Rush" (1) |
| `drives.previous[].plays[].pointAfterAttempt.value` | number | 100% | values: 1 (25), 0 (1), 2 (1) |
| `drives.previous[].plays[].priority` | boolean | 100% | values: false (878), true (29) |
| `drives.previous[].plays[].review.type` | string | 100% | e.g. "CHALLENGE" |
| `drives.previous[].plays[].review.upheld` | boolean | 100% | e.g. false |
| `drives.previous[].plays[].scoringPlay` | boolean | 100% | values: false (866), true (41) |
| `drives.previous[].plays[].scoringType.abbreviation` | string | 100% | values: "TD" (27), "FG" (14) |
| `drives.previous[].plays[].scoringType.displayName` | string | 100% | values: "Touchdown" (27), "Field Goal" (14) |
| `drives.previous[].plays[].scoringType.name` | string | 100% | values: "touchdown" (27), "field-goal" (14) |
| `drives.previous[].plays[].sequenceNumber` | str-numeric | 100% | e.g. "3900", "6200", "36200", "38400" |
| `drives.previous[].plays[].start.distance` | number | 100% | e.g. 10, 1, 6, 2 |
| `drives.previous[].plays[].start.down` | number | 100% | values: 1 (375), 2 (251), 3 (162), 4 (92), 0 (23), -1 (4) |
| `drives.previous[].plays[].start.team.id` | str-numeric | 100% | values: "130" (109), "11" (106), "27" (103), "2655" (96), "251" (94), "249" (88), "33" (86), "2390" (81), "194" (76), "29" (65) |
| `drives.previous[].plays[].start.yardLine` | number | 100% | e.g. 35, 65, 75, 36 |
| `drives.previous[].plays[].start.yardsToEndzone` | number | 100% | e.g. 65, 0, 75, 64 |
| `drives.previous[].plays[].statYardage` | number | 100% | e.g. 0, 3, 5, 4 |
| `drives.previous[].plays[].teamParticipants[].id` | str-numeric | 100% | values: "251" (203), "130" (203), "33" (193), "11" (193), "249" (184), "2655" (184), "27" (170), "29" (170), "2390" (157), "194" (157) |
| `drives.previous[].plays[].teamParticipants[].order` | number | 100% | values: 1 (907), 2 (907) |
| `drives.previous[].plays[].text` | string | 100% | e.g. "C.McLaughlin kicks 65 yards from TB 35 to end zone, Touchback to the CAR 35.", "Two-Minute Warning", "END QUARTER 1", "END QUARTER 2" |
| `drives.previous[].plays[].type.id` | str-numeric | 100% | e.g. "5", "24", "3", "53" |
| `drives.previous[].plays[].type.text` | string | 100% | e.g. "Rush", "Pass Reception", "Pass Incompletion", "Kickoff" |
| `drives.previous[].result` | string | 100% | values: "PUNT" (37), "TD" (24), "FG" (14), "INT" (11), "MISSED FG" (7), "END OF HALF" (5), "FUMBLE" (4), "DOWNS" (2), "INT TD" (2), "PUNT TD" (1), "END OF GAME" (1) |
| `drives.previous[].shortDisplayResult` | string | 100% | values: "PUNT" (37), "TD" (24), "FG" (14), "INT" (11), "MISSED FG" (7), "END OF HALF" (5), "FUMBLE" (4), "DOWNS" (2), "INT TD" (2), "PUNT TD" (1), "END OF GAME" (1) |
| `drives.previous[].start.clock.displayValue` | string | 100% | e.g. "15:00", "0:39", "9:31", "7:24" |

## Go deeper

- Full field tables: [scoreboard](../scoreboard.md) · [summary](../summary.md) · [standings](../standings.md) · [teams](../teams.md) · [team-roster](../team-roster.md) · [rankings](../rankings.md)
- Canonical shape, ESPN→canonical mappings, per-league period/OT matrix: `schema/SCHEMA.md`, `schema/canonical.ts`
- Cross-sport support matrix: [index.md](../index.md)
