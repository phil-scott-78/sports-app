# ESPN API — soccer

> Per-sport slice of the [observed data guide](../index.md): what ESPN actually serves for **soccer**, and which endpoint answers each need. Built from 754 real soccer responses — OBSERVED live, not documented. Regenerate: `node schema/tools/rollup.mjs`.

## Leagues — 122 in the registry

Competition **shape** drives rendering (see the discriminators in `schema/canonical.ts`): `layout · scoreKind · competitorKind`.

| shape (layout · scoreKind · competitorKind) | leagues | examples |
|---|---|---|
| `headToHead · numeric · team` | 122 | `eng.1`, `esp.1`, `ger.1`, `ita.1` |

**Crawled for this guide** (7): `soccer/eng.1`, `soccer/esp.1`, `soccer/fifa.world`, `soccer/fra.1`, `soccer/ger.1`, `soccer/ita.1`, `soccer/uefa.champions`. The evidence below is from these leagues; other soccer leagues in the registry inherit the same shape.

## Which endpoint to use

URL templates use `soccer/fifa.world` as a representative league. Swap in any league key from the table above.

| need | endpoint | status | URL template | fields |
|---|---|---|---|---|
| Scores & live state | `scoreboard` | ✅ 98/98 | `https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/scoreboard` | [guide](../scoreboard.md) |
| Rich game detail | `summary` | ✅ 28/28 | `https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/summary?event={eventId}` | [guide](../summary.md) |
| League table | `standings` | ✅ 14/14 | `https://site.api.espn.com/apis/v2/sports/soccer/fifa.world/standings` | [guide](../standings.md) |
| Team directory | `teams` | ✅ 7/7 | `https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/teams` | [guide](../teams.md) |
| Roster | `team-roster` | ✅ 14/14 | `https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/teams/{teamId}/roster` | [guide](../team-roster.md) |
| Schedule | `team-schedule` | ✅ 7/7 | `https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/teams/{teamId}/schedule` | [guide](../team-schedule.md) |
| Team season stats | `team-stats` | ✅ 7/7 | `https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/teams/{teamId}/statistics` | [guide](../team-stats.md) |
| News | `news` | ✅ 7/7 | `https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/news?limit=5` | [guide](../news.md) |
| Injuries | `injuries` | ✅ 7/7 | `https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/teams/{teamId}/injuries` | [guide](../injuries.md) |

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

91 of the core resource shapes were reachable for soccer by following `$ref` links from the league root and its events (full matrix: [index.md](../index.md#core-api-resource-graph)). High-value shapes:

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
| `core-competition-commentaries` | ✅ | Text commentary stream. |
| `core-rankings` | ✅ | Rankings through the core graph. |
| `core-competition-officials` | ✅ | Match officials / referees. |

## What's sport-specific in the data

Value-bearing fields observed for soccer that are **not** near-universal — the sport's fingerprint. **presence** = % of this sport's crawled responses (or parent objects) that carry the field (soccer-specific). Field paths, types, and presence are soccer-only; the **value/example samples are pooled** across the handful of sports that share a field (a nested `period` may show golf's "18" next to a fight's "1–3"), so read them as shape hints. The full per-sport field tables live in the per-endpoint guides linked above.

### scoreboard

| field | type | presence | values / examples |
|---|---|---|---|
| `events[].competitions[].altGameNote` | string | 100% | values: "English Premier League" (124), "Serie A" (122), "LALIGA" (122), "Ligue 1" (97), "Bundesliga" (92), "UEFA Champions League, League Phase" (36), "FIFA World Cup, Round of 32" (15), "FIFA World Cup, Round of 16" (10), "UEFA Champions League, Quarterfinals" (4), "UEFA Champions League, Round of 16" (4), "UEFA Champions League, Final" (2), "UEFA Champions League, Semifinals" (2) |
| `events[].competitions[].details[].athletesInvolved[].jersey` | str-numeric | 100% | e.g. "10", "9", "7", "19" |
| `events[].competitions[].details[].athletesInvolved[].team.id` | str-numeric | 100% | e.g. "132", "367", "359", "382" |
| `events[].competitions[].details[].ownGoal` | boolean | 100% | values: false (4276), true (41) |
| `events[].competitions[].details[].penaltyKick` | boolean | 100% | values: false (4114), true (203) |
| `events[].competitions[].details[].redCard` | boolean | 100% | values: false (4183), true (134) |
| `events[].competitions[].details[].scoreValue` | number | 100% | values: 0 (2595), 1 (1722) |
| `events[].competitions[].details[].scoringPlay` | boolean | 100% | values: false (2595), true (1722) |
| `events[].competitions[].details[].shootout` | boolean | 100% | values: false (4271), true (46) |
| `events[].competitions[].details[].yellowCard` | boolean | 100% | values: true (2461), false (1856) |
| `events[].competitions[].leg.displayValue` | string | 100% | values: "1st Leg" (8), "2nd Leg" (2) |
| `events[].competitions[].leg.value` | number | 100% | values: 1 (8), 2 (2) |
| `events[].competitions[].notes[].text` | string | 100% | values: "1st Leg" (8), "Paris Saint-Germain win 4-3 on penalties" (2), "Switzerland advance 4-3 on penalties" (2), "Paraguay advance 4-3 on penalties" (1), "Morocco advance 3-2 on penalties" (1), "Egypt advance 4-2 on penalties" (1), "2nd Leg - Arsenal advance 2-1 on aggregate" (1), "2nd Leg - Paris Saint-Germain advance 6-5 on aggregate" (1) |
| `events[].competitions[].odds[].awayTeamOdds.handicap` | number | 100% | e.g. 0 |
| `events[].competitions[].odds[].awayTeamOdds.summary` | string | 100% | e.g. "4/5", "11/1", "9/5" |
| `events[].competitions[].odds[].awayTeamOdds.value` | number | 100% | e.g. 1.8, 12, 2.8 |
| `events[].competitions[].odds[].homeTeamOdds.handicap` | number | 100% | e.g. 0 |
| `events[].competitions[].odds[].homeTeamOdds.summary` | string | 100% | e.g. "2/9", "16/5", "15/4", "6/4" |
| `events[].competitions[].odds[].homeTeamOdds.value` | number | 100% | e.g. 1.222, 4.2, 4.75, 2.5 |
| `events[].competitions[].odds[].moneyline.draw.close.odds` | string | 100% | values: "+390" (2), "+220" (2), "+500" (1), "+180" (1), "+425" (1), "+240" (1), "+210" (1), "+225" (1), "+250" (1), "+650" (1), "+330" (1) |
| `events[].competitions[].odds[].moneyline.draw.open.odds` | string | 100% | values: "+425" (2), "+330" (2), "+220" (2), "+180" (1), "+240" (1), "+210" (1), "+225" (1), "+250" (1), "+390" (1), "+700" (1) |
| `events[].competitions[].playByPlayAthletes` | boolean | 100% | values: true (630) |
| `events[].competitions[].series.competitors[].winner` | boolean | 100% | values: false (18), true (2) |
| `events[].competitions[].odds[].drawOdds.moneyLine` | number | 76% | values: 390 (2), 220 (2), 500 (1), 180 (1), 425 (1), 240 (1), 210 (1), 225 (1), 250 (1), 650 (1), 330 (1) |
| `events[].competitions[].odds[].drawOdds.handicap` | number | 24% | e.g. 0 |
| `events[].competitions[].odds[].drawOdds.summary` | string | 24% | e.g. "5/1", "5/2", "23/10", "21/10" |
| `events[].competitions[].odds[].drawOdds.value` | number | 24% | e.g. 6, 3.5, 3.3, 3.1 |
| `events[].competitions[].series.competitors[].aggregateScore` | number | 20% | e.g. 2, 1, 5, 6 |
| `events[].competitions[].competitors[].advance` | boolean | 9% | values: true (55), false (55) |
| `events[].competitions[].competitors[].shootoutScore` | number | 1% | values: 4 (6), 3 (6), 2 (2) |
| `events[].competitions[].competitors[].aggregateScore` | number | 0% | e.g. 2, 1, 5, 6 |
| `events[].competitions[].details[].athletesInvolved[].position` | string | 100% | e.g. "SUB", "F", "LM", "RM" |
| `events[].competitions[].wasSuspended` | boolean | 100% | values: false (867), true (1) |
| `events[].venue.displayName` | string | 100% | e.g. "San Siro", "Olimpico", "St. James' Park", "Riyadh Air Metropolitano" |
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
| `events[].competitions[].odds[].awayTeamOdds.team.abbreviation` | string | 100% | e.g. "CHI", "ARI", "SJSU", "MON" |
| `events[].competitions[].odds[].awayTeamOdds.team.displayName` | string | 100% | e.g. "San José State Spartans", "Chicago Sky", "Monza", "Como" |
| `events[].competitions[].odds[].awayTeamOdds.team.id` | str-numeric | 100% | e.g. "5", "27", "23", "19" |
| `events[].competitions[].odds[].homeTeamOdds.team.abbreviation` | string | 100% | e.g. "EMU", "PHX", "INT", "UDI" |
| `events[].competitions[].odds[].homeTeamOdds.team.displayName` | string | 100% | e.g. "Eastern Michigan Eagles", "Phoenix Mercury", "Internazionale", "Udinese" |
| `events[].competitions[].odds[].homeTeamOdds.team.id` | str-numeric | 100% | e.g. "11", "26", "30", "24" |
| `events[].competitions[].odds[].moneyline.away.close.odds` | string | 100% | e.g. "+145", "OFF", "+260", "+550" |
| `events[].competitions[].odds[].moneyline.away.open.odds` | string | 100% | e.g. "OFF", "+260", "+142", "+230" |
| `events[].competitions[].odds[].moneyline.displayName` | string | 100% | values: "Moneyline" (52) |
| `events[].competitions[].odds[].moneyline.home.close.odds` | string | 100% | e.g. "-175", "OFF", "-325", "-245" |
| `events[].competitions[].odds[].moneyline.home.open.odds` | string | 100% | e.g. "OFF", "-325", "-170", "-175" |

### summary

| field | type | presence | values / examples |
|---|---|---|---|
| `boxscore.form[].displayOrder` | number | 100% | values: 1 (28), 2 (28) |
| `boxscore.form[].events[].atVs` | string | 100% | values: "@" (141), "vs" (139) |
| `boxscore.form[].events[].awayAggregateScore` | str-numeric | 100% | values: "0" (265), "1" (4), "2" (3), "3" (2), "6" (2), "4" (2), "5" (1), "7" (1) |
| `boxscore.form[].events[].awayShootoutScore` | str-numeric | 100% | values: "0" (275), "4" (4), "3" (1) |
| `boxscore.form[].events[].awayTeamId` | str-numeric | 100% | e.g. "359", "1068", "132", "176" |
| `boxscore.form[].events[].awayTeamScore` | str-numeric | 100% | values: "1" (100), "0" (83), "2" (65), "3" (22), "4" (9), "6" (1) |
| `boxscore.form[].events[].competitionName` | string | 100% | e.g. "2025-26 Ligue 1", "2025-26 LALIGA", "2025-26 English Premier League", "2025-26 German Bundesliga" |
| `boxscore.form[].events[].gameResult` | string | 100% | values: "W" (126), "L" (83), "D" (71) |
| `boxscore.form[].events[].homeAggregateScore` | str-numeric | 100% | values: "0" (265), "2" (5), "5" (3), "1" (3), "4" (1), "6" (1), "8" (1), "10" (1) |
| `boxscore.form[].events[].homeShootoutScore` | str-numeric | 100% | values: "0" (275), "2" (3), "4" (1), "3" (1) |
| `boxscore.form[].events[].homeTeamId` | str-numeric | 100% | e.g. "132", "359", "160", "371" |
| `boxscore.form[].events[].homeTeamScore` | str-numeric | 100% | values: "1" (85), "2" (63), "0" (59), "3" (45), "4" (16), "5" (9), "7" (2), "6" (1) |
| `boxscore.form[].events[].id` | str-numeric | 100% | e.g. "401862896", "746676", "401864079", "740907" |
| `boxscore.form[].events[].leagueAbbreviation` | string | 100% | e.g. "Ligue 1", "LALIGA", "Premier League", "Bundesliga" |
| `boxscore.form[].events[].leagueName` | string | 100% | e.g. "French Ligue 1", "Spanish LALIGA", "English Premier League", "German Bundesliga" |
| `boxscore.form[].events[].opponent.abbreviation` | string | 100% | e.g. "PAR", "WOL", "B04", "ELC" |
| `boxscore.form[].events[].opponent.displayName` | string | 100% | e.g. "Wolverhampton Wanderers", "Bayer Leverkusen", "Elche", "West Ham United" |
| `boxscore.form[].events[].opponent.id` | str-numeric | 100% | e.g. "380", "131", "3751", "371" |
| `boxscore.form[].events[].score` | string | 100% | e.g. "2-1", "1-0", "1-1", "2-0" |
| `boxscore.form[].team.abbreviation` | string | 100% | e.g. "ARS", "MUN", "MON", "UDI" |
| `boxscore.form[].team.displayName` | string | 100% | e.g. "Arsenal", "Bayern Munich", "Udinese", "Atlético Madrid" |
| `boxscore.form[].team.id` | str-numeric | 100% | e.g. "359", "132", "118", "1068" |
| `boxscore.teams[].team.uniform.color` | string | 100% | e.g. "FF0000", "FFFFFF", "000000", "003399" |
| `boxscore.teams[].team.uniform.type` | string | 100% | values: "home" (29), "away" (7), "third" (6) |
| `commentary[].play.clock.displayValue` | string | 100% | e.g. "5'", "14'", "23'", "21'" |
| `commentary[].play.clock.value` | number | 100% | e.g. 0, 621, 295, 119 |
| `commentary[].play.id` | str-numeric | 100% | e.g. "47594969", "47594998", "47595015", "47595046" |
| `commentary[].play.period.number` | number | 100% | values: 1 (460) |
| `commentary[].play.source.description` | string | 100% | values: "SA.ENVOY" (460) |
| `commentary[].play.source.id` | str-numeric | 100% | values: "38" (460) |
| `commentary[].play.team.displayName` | string | 100% | e.g. "Bayern Munich", "Arsenal", "Paris Saint-Germain", "Argentina" |
| `commentary[].play.text` | string | 100% | e.g. "First Half begins.", "Foul by William Osula (Newcastle United).", "Delay over. They are ready to continue.", "Foul by Ilyas Ansah (1. FC Union Berlin)." |
| `commentary[].play.type.id` | str-numeric | 100% | e.g. "66", "117", "95", "135" |
| `commentary[].play.type.text` | string | 100% | e.g. "Foul", "Shot Off Target", "Corner Awarded", "Shot Blocked" |
| `commentary[].play.type.type` | string | 100% | e.g. "foul", "shot-off-target", "corner-awarded", "shot-blocked" |
| `commentary[].sequence` | number | 100% | e.g. 0, 1, 2, 3 |
| `commentary[].text` | string | 100% | e.g. "Lineups are announced and players are warming up.", "First Half begins.", "Delay over. They are ready to continue.", "Delay in match for a drinks break." |
| `commentary[].time.displayValue` | string | 100% | e.g. "", "21'", "5'", "14'" |
| `commentary[].time.value` | number | 100% | e.g. 0, 621, 119, 295 |
| `header.competitions[].altGameNote` | string | 100% | values: "Premier League" (4), "Serie A" (4), "Bundesliga" (4), "LALIGA" (4), "Ligue 1" (4), "FIFA World Cup, Round of 16" (2), "FIFA World Cup, Round of 32" (2), "UEFA Champions League, Final" (1), "UEFA Champions League, Semifinals" (1), "UEFA Champions League, Quarterfinals" (1), "UEFA Champions League, Round of 16" (1) |
| `header.competitions[].competitors[].team.groups.name` | string | 100% | values: "Final" (8), "FIFA World Cup" (8), "English Premier League 2025-2026" (6), "2025-26 German Bundesliga" (6), "French Ligue 1 2025-26" (6), "2025-2026 Italian Serie A" (4), "2026-2027 Italian Serie A" (4), "2025-26 LALIGA" (4), "2026-27 LALIGA" (4), "2026-27 English Premier League" (2), "2026-27 German Bundesliga" (2), "French Ligue 1 2026-27" (2) |
| `header.competitions[].details[].ownGoal` | boolean | 100% | values: false (63), true (1) |
| `header.competitions[].details[].penaltyKick` | boolean | 100% | values: false (62), true (2) |
| `header.competitions[].details[].redCard` | boolean | 100% | values: false (63), true (1) |
| `header.competitions[].details[].scoringPlay` | boolean | 100% | values: true (63), false (1) |
| `header.competitions[].details[].team.location` | string | 100% | e.g. "Bayern Munich", "Villarreal", "Leeds United", "Brentford" |
| `header.competitions[].isFinal` | boolean | 100% | values: false (27), true (1) |
| `header.competitions[].isThirdPlace` | boolean | 100% | values: false (28) |
| `header.competitions[].leg.displayValue` | string | 100% | e.g. "1st Leg", "2nd Leg" |
| `header.competitions[].leg.value` | number | 100% | e.g. 1, 2 |
| `header.competitions[].notes[].type` | string | 100% | values: "event" (6), "event-ingest-note" (5) |
| `header.competitions[].series[].competitors[].aggregateScore` | number | 100% | e.g. 1, 2, 0 |
| `header.competitions[].series[].leg` | number | 100% | e.g. 1, 2 |
| `header.competitions[].shotMapAvailable` | boolean | 100% | values: false (17), true (11) |
| `header.linksv4[].text` | string | 100% | values: "Gamecast" (28), "Commentary" (21), "Recap" (13), "Videos" (10), "Team Stats" (4), "Player Stats" (4), "Bracket" (4) |

## Go deeper

- Full field tables: [scoreboard](../scoreboard.md) · [summary](../summary.md) · [standings](../standings.md) · [teams](../teams.md) · [team-roster](../team-roster.md) · [rankings](../rankings.md)
- Canonical shape, ESPN→canonical mappings, per-league period/OT matrix: `schema/SCHEMA.md`, `schema/canonical.ts`
- Cross-sport support matrix: [index.md](../index.md)
