# ESPN API — cricket

> Per-sport slice of the [observed data guide](../index.md): what ESPN actually serves for **cricket**, and which endpoint answers each need. Built from 18 real cricket responses — OBSERVED live, not documented. Regenerate: `node schema/tools/rollup.mjs`.

## Leagues — 17 in the registry

Competition **shape** drives rendering (see the discriminators in `schema/canonical.ts`): `layout · scoreKind · competitorKind`.

| shape (layout · scoreKind · competitorKind) | leagues | examples |
|---|---|---|
| `headToHead · cricket · team` | 17 | `8048`, `8634`, `8052`, `8044` |

**Crawled for this guide** (1): `cricket/8039`. The evidence below is from these leagues; other cricket leagues in the registry inherit the same shape.

## Which endpoint to use

URL templates use `cricket/8039` as a representative league. Swap in any league key from the table above.

| need | endpoint | status | URL template | fields |
|---|---|---|---|---|
| Scores & live state | `scoreboard` | ✅ 14/14 | `https://site.api.espn.com/apis/site/v2/sports/cricket/8039/scoreboard` | [guide](../scoreboard.md) |
| Rich game detail | `summary` | ✅ 1/1 | `https://site.api.espn.com/apis/site/v2/sports/cricket/8039/summary?event={eventId}` | [guide](../summary.md) |
| League table | `standings` | ✅ 2/2 | `https://site.api.espn.com/apis/v2/sports/cricket/8039/standings` | [guide](../standings.md) |
| Team directory | `teams` | ❌ not served | `https://site.api.espn.com/apis/site/v2/sports/cricket/8039/teams` | [guide](../teams.md) |
| News | `news` | ✅ 1/1 | `https://site.api.espn.com/apis/site/v2/sports/cricket/8039/news?limit=5` | [guide](../news.md) |

- **scoreboard** — The cheap poll — scores, status, line scores, and (situationally) situation, leaders, records, odds. The primary call. College needs `?groups=<id>&limit=400`; `?dates=YYYYMMDD-YYYYMMDD` for a range (cricket: single day only).
- **summary** — One extra fetch when a game is opened — box scores, scoring plays, rosters, penalty shootouts, method of victory. A 404 for the whole sport means this tier does not exist (build detail from the core graph instead).
- **standings** — ⚠ `apis/v2`, NOT `apis/site/v2` (the site path returns a `{fullViewLink}` stub). Omit `?season=` — ESPN defaults to the current season.
- **teams** — Team ids, names, abbreviations, logos, colors. The id feeds the roster/schedule/stats/injuries calls. _(every attempt 404/400 — this tier does not exist for the sport)_
- **news** — Latest articles for the league.

## Core API — `sports.core.api.espn.com`

0 of the core resource shapes were reachable for cricket by following `$ref` links from the league root and its events (full matrix: [index.md](../index.md#core-api-resource-graph)). High-value shapes:

| resource | reachable | what it adds |
|---|---|---|

## What's sport-specific in the data

Value-bearing fields observed for cricket that are **not** near-universal — the sport's fingerprint. **presence** = % of this sport's crawled responses (or parent objects) that carry the field (cricket-specific). Field paths, types, and presence are cricket-only; the **value/example samples are pooled** across the handful of sports that share a field (a nested `period` may show golf's "18" next to a fight's "1–3"), so read them as shape hints. The full per-sport field tables live in the per-endpoint guides linked above.

### scoreboard

| field | type | presence | values / examples |
|---|---|---|---|
| `events[].competitions[].class.eventType` | string | 100% | e.g. "ODI" |
| `events[].competitions[].class.generalClassCard` | string | 100% | e.g. "ODI" |
| `events[].competitions[].class.generalClassId` | str-numeric | 100% | e.g. "5" |
| `events[].competitions[].class.internationalClassId` | str-numeric | 100% | e.g. "2" |
| `events[].competitions[].class.name` | string | 100% | e.g. "One-Day Internationals" |
| `events[].competitions[].competitors[].linescores[].description` | string | 100% | e.g. "all out", "target reached" |
| `events[].competitions[].competitors[].linescores[].isBatting` | boolean | 100% | e.g. true, false |
| `events[].competitions[].competitors[].linescores[].isCurrent` | number | 100% | e.g. 0, 1 |
| `events[].competitions[].competitors[].linescores[].overs` | number | 100% | e.g. 50, 43 |
| `events[].competitions[].competitors[].linescores[].runs` | number | 100% | e.g. 0, 240, 241 |
| `events[].competitions[].competitors[].linescores[].wickets` | number | 100% | e.g. 0, 10, 4 |
| `events[].competitions[].competitors[].team.countryCode` | string | 100% | e.g. "IN", "AU" |
| `events[].competitions[].description` | string | 100% | e.g. "Final" |
| `events[].competitions[].fastcastAvailable` | boolean | 100% | e.g. false |
| `events[].competitions[].shortDescription` | string | 100% | e.g. "Final,  (D/N) at Ahmedabad" |
| `events[].competitions[].status.featuredAthletes[].athlete.name` | string | 100% | e.g. "Travis Head", "Virat Kohli" |
| `events[].competitions[].status.summary` | string | 100% | e.g. "Australia won by 6 wkts (42b rem)" |
| `events[].competitions[].venue.address.summary` | string | 100% | e.g. "" |
| `events[].competitions[].venue.capacity` | number | 100% | e.g. 132000 |
| `events[].description` | string | 100% | e.g. "Final (D/N), ICC Cricket World Cup at Ahmedabad, Nov 19 2023" |
| `events[].status.summary` | string | 100% | e.g. "Australia won by 6 wkts (42b rem)" |
| `leagues[].mappings.contentlink` | str-numeric | 100% | values: "8039" (14) |
| `leagues[].mappings.cricinfo` | number | 100% | values: 1367856 (14) |
| `standings[].stats[].abbreviation` | string | 100% | e.g. "R", "PT" |
| `standings[].stats[].description` | string | 100% | e.g. "Rank", "Number of points awarded." |
| `standings[].stats[].displayName` | string | 100% | e.g. "rank", "Points" |
| `standings[].stats[].displayValue` | str-numeric | 100% | e.g. "1", "18", "3", "14" |
| `standings[].stats[].name` | string | 100% | e.g. "rank", "matchPoints" |
| `standings[].stats[].shortDisplayName` | string | 100% | e.g. "R", "Pts" |
| `standings[].stats[].type` | string | 100% | e.g. "rank", "matchpoints" |
| `standings[].stats[].value` | number | 100% | e.g. 1, 18, 3, 14 |
| `standings[].team.abbreviation` | string | 100% | e.g. "IND", "AUS" |
| `standings[].team.displayName` | string | 100% | e.g. "India", "Australia" |
| `standings[].team.id` | str-numeric | 100% | e.g. "6", "2" |
| `standings[].team.isActive` | boolean | 100% | e.g. true |
| `standings[].team.isNational` | boolean | 100% | e.g. true |
| `standings[].team.location` | string | 100% | e.g. "India", "Australia" |
| `standings[].team.name` | string | 100% | e.g. "India", "Australia" |
| `standings[].team.shortDisplayName` | string | 100% | e.g. "IND", "AUS" |
| `teams[].abbreviation` | string | 100% | values: "AFG" (14), "AUS" (14), "BAN" (14), "ENG" (14), "IND" (14), "NED" (14), "NZ" (14), "PAK" (14), "SA" (14), "SL" (14) |
| `teams[].displayName` | string | 100% | values: "Afghanistan" (14), "Australia" (14), "Bangladesh" (14), "England" (14), "India" (14), "Netherlands" (14), "New Zealand" (14), "Pakistan" (14), "South Africa" (14), "Sri Lanka" (14) |
| `teams[].id` | str-numeric | 100% | values: "40" (14), "2" (14), "25" (14), "1" (14), "6" (14), "15" (14), "5" (14), "7" (14), "3" (14), "8" (14) |
| `teams[].location` | string | 100% | values: "Afghanistan" (14), "Australia" (14), "Bangladesh" (14), "England" (14), "India" (14), "Netherlands" (14), "New Zealand" (14), "Pakistan" (14), "South Africa" (14), "Sri Lanka" (14) |
| `teams[].name` | string | 100% | values: "Afghanistan" (14), "Australia" (14), "Bangladesh" (14), "England" (14), "India" (14), "Netherlands" (14), "New Zealand" (14), "Pakistan" (14), "South Africa" (14), "Sri Lanka" (14) |
| `teams[].nickname` | string | 100% | values: "Afghanistan" (14), "Australia" (14), "Bangladesh" (14), "England" (14), "India" (14), "Netherlands" (14), "New Zealand" (14), "Pakistan" (14), "South Africa" (14), "Sri Lanka" (14) |
| `teams[].shortDisplayName` | string | 100% | values: "AFG" (14), "AUS" (14), "BAN" (14), "ENG" (14), "IND" (14), "NED" (14), "NZ" (14), "PAK" (14), "SA" (14), "SL" (14) |
| `leagues[].classId[]` | number | — | values: 2 (14) |
| `events[].competitions[].status.featuredAthletes[].abbreviation` | string | 100% | values: "WP" (220), "LP" (220), "FS" (196), "SS" (196), "TS" (196), "L" (195), "W" (194), "S" (103), "POTM" (1), "POTS" (1) |
| `events[].competitions[].status.featuredAthletes[].displayName` | string | 100% | values: "Winning Pitcher" (220), "Losing Pitcher" (220), "First Star" (196), "Second Star" (196), "Third Star" (196), "Losing Goalie" (195), "Winning Goalie" (194), "Saving Pitcher" (103), "Player Of The Match" (1), "Player Of The Series" (1) |
| `events[].competitions[].status.featuredAthletes[].name` | string | 100% | values: "winningPitcher" (220), "losingPitcher" (220), "firstStar" (196), "secondStar" (196), "thirdStar" (196), "losingGoalie" (195), "winningGoalie" (194), "savingPitcher" (103), "playerOfTheMatch" (1), "playerOfTheSeries" (1) |
| `events[].competitions[].status.featuredAthletes[].playerId` | number | 100% | e.g. 4064582, 4697686, 2517899, 4588165 |
| `events[].competitions[].status.featuredAthletes[].shortDisplayName` | string | 100% | values: "Win" (220), "Loss" (220), "First Star" (196), "Second Star" (196), "Third Star" (196), "Losing Goalie" (195), "Winning Goalie" (194), "Save" (103), "POTM" (1), "POTS" (1) |
| `events[].competitions[].status.featuredAthletes[].team.id` | str-numeric | 100% | e.g. "2", "16", "30", "1" |
| `events[].competitions[].venue.address.country` | string | 100% | e.g. "USA", "England", "Spain", "Italy" |

### summary

| field | type | presence | values / examples |
|---|---|---|---|
| `article.authors[].displayName` | string | 100% | e.g. "Andrew Miller" |
| `article.authors[].slug` | string | 100% | e.g. "andrew-miller" |
| `article.authors[].sourceLine` | string | 100% | e.g. "UK editor, ESPNcricinfo" |
| `article.categories[].athlete.description` | string | 100% | e.g. "Travis Head", "Marnus Labuschagne" |
| `article.categories[].contributor.description` | string | 100% | e.g. "Andrew Miller" |
| `article.categories[].contributor.id` | number | 100% | e.g. 3003 |
| `article.eventId` | number | 100% | e.g. 1384439 |
| `article.eventIdStr` | str-numeric | 100% | e.g. "1384439" |
| `article.feedDisplayType` | string | 100% | e.g. "Default" |
| `article.related[].byline` | string | 100% | e.g. "Osman Samiuddin", "ESPNcricinfo staff", "Sidharth Monga", "Sruthi Ravindranath" |
| `article.related[].headline` | string | 100% | e.g. "Advance Australia, inevitably", "Australia player reactions: 'I think this is bigger than 2015'", "Australia's irrepressible trio of quicks cement their legacy", "Cummins pleased Australia 'saved the best for last'" |
| `article.related[].id` | number | 100% | e.g. 38937428, 38935241, 38938823, 38935800 |
| `article.related[].isLiveBlog` | boolean | 100% | e.g. false |
| `article.related[].linkText` | string | 100% | e.g. "Advance Australia, inevitably", "Australia player reactions: 'I think this is bigger than 2015'", "Australia's irrepressible trio of quicks cement their legacy", "Cummins pleased Australia 'saved the best for last'" |
| `article.related[].premium` | boolean | 100% | e.g. false |
| `article.related[].publishedkey` | string | 100% | e.g. "cricket-1409794", "cricket-1409729", "cricket-1409797", "cricket-1409761" |
| `article.related[].source` | string | 100% | e.g. "" |
| `article.related[].title` | string | 100% | e.g. "ICC Cricket World Cup 2023 - Final - Osman Samiuddin on Australia's inevitable a…", "ICC Cricket World Cup 2023 final - Australia player reactions after beating Indi…", "ICC Cricket World Cup 2023 - Final - Sidharth Monga Australia's irrepressible tr…", "ICC Cricket World Cup 2023 final - Pat Cummins glad Australia 'saved the best fo…" |
| `article.related[].type` | string | 100% | e.g. "HeadlineNews", "Story" |
| `article.root` | string | 100% | e.g. "cricket" |
| `gameInfo.venue.address.summary` | string | 100% | e.g. "" |
| `gameInfo.venue.capacity` | number | 100% | e.g. 132000 |
| `header.competitions[].class.eventType` | string | 100% | e.g. "ODI" |
| `header.competitions[].class.generalClassCard` | string | 100% | e.g. "ODI" |
| `header.competitions[].class.generalClassId` | str-numeric | 100% | e.g. "5" |
| `header.competitions[].class.internationalClassId` | str-numeric | 100% | e.g. "2" |
| `header.competitions[].class.name` | string | 100% | e.g. "One-Day Internationals" |
| `header.competitions[].commentaries.{key}.awayScore` | string | 100% | values: "231/3" (6), "230/3" (4), "226/3" (2), "233/3" (1), "237/3" (1), "238/3" (1), "239/3" (1), "239/4" (1), "241/4" (1) |
| `header.competitions[].commentaries.{key}.batsman.athlete.firstName` | string | 100% | values: "Marnus" (11), "Travis" (6), "Glenn" (1) |
| `header.competitions[].commentaries.{key}.batsman.athlete.lastName` | string | 100% | values: "Labuschagne" (11), "Head" (6), "Maxwell" (1) |
| `header.competitions[].commentaries.{key}.batsman.athlete.name` | string | 100% | values: "Marnus Labuschagne" (11), "Travis Head" (6), "Glenn Maxwell" (1) |
| `header.competitions[].commentaries.{key}.batsman.faced` | number | 100% | e.g. 115, 100, 101, 102 |
| `header.competitions[].commentaries.{key}.batsman.fours` | number | 100% | values: 4 (10), 14 (3), 15 (3), 3 (1), 0 (1) |
| `header.competitions[].commentaries.{key}.batsman.runs` | number | 100% | values: 0 (10), 1 (4), 4 (2), 2 (2) |
| `header.competitions[].commentaries.{key}.batsman.sixes` | number | 100% | values: 0 (12), 4 (6) |
| `header.competitions[].commentaries.{key}.batsman.team.abbreviation` | string | 100% | values: "AUS" (18) |
| `header.competitions[].commentaries.{key}.batsman.team.id` | str-numeric | 100% | values: "2" (18) |
| `header.competitions[].commentaries.{key}.batsman.team.name` | string | 100% | values: "Australia" (18) |
| `header.competitions[].commentaries.{key}.batsman.totalRuns` | number | 100% | values: 57 (9), 137 (2), 129 (1), 53 (1), 130 (1), 132 (1), 136 (1), 58 (1), 2 (1) |
| `header.competitions[].commentaries.{key}.bbbTimestamp` | number | 100% | e.g. 1700408296000, 1700408324000, 1700408364000, 1700408406000 |
| `header.competitions[].commentaries.{key}.boundary` | boolean | 100% | values: false (16), true (2) |
| `header.competitions[].commentaries.{key}.bowler.athlete.firstName` | string | 100% | values: "Mohammed" (12), "Jasprit" (6) |
| `header.competitions[].commentaries.{key}.bowler.athlete.lastName` | string | 100% | values: "Siraj" (12), "Bumrah" (6) |
| `header.competitions[].commentaries.{key}.bowler.athlete.name` | string | 100% | values: "Mohammed Siraj" (12), "Jasprit Bumrah" (6) |
| `header.competitions[].commentaries.{key}.bowler.balls` | number | 100% | e.g. 31, 32, 33, 34 |
| `header.competitions[].commentaries.{key}.bowler.conceded` | number | 100% | values: 43 (8), 35 (4), 31 (2), 37 (1), 41 (1), 42 (1), 45 (1) |
| `header.competitions[].commentaries.{key}.bowler.maidens` | number | 100% | values: 0 (12), 2 (6) |
| `header.competitions[].commentaries.{key}.bowler.overs` | number | 100% | e.g. 5.1, 5.2, 5.3, 5.4 |
| `header.competitions[].commentaries.{key}.bowler.team.abbreviation` | string | 100% | values: "IND" (18) |
| `header.competitions[].commentaries.{key}.bowler.team.id` | str-numeric | 100% | values: "6" (18) |
| `header.competitions[].commentaries.{key}.bowler.team.name` | string | 100% | values: "India" (18) |
| `header.competitions[].commentaries.{key}.bowler.wickets` | number | 100% | values: 0 (10), 2 (6), 1 (2) |
| `header.competitions[].commentaries.{key}.dismissal.batsman.athlete.name` | string | 100% | values: "Marnus Labuschagne" (11), "Travis Head" (6), "Glenn Maxwell" (1) |
| `header.competitions[].commentaries.{key}.dismissal.dismissal` | boolean | 100% | values: false (17), true (1) |
| `header.competitions[].commentaries.{key}.dismissal.text` | string | 100% | values: "" (17), "TM Head c Shubman Gill b Mohammed Siraj 137 (166m 120b 15x4 4x6) SR: 114.16" (1) |

## Go deeper

- Full field tables: [scoreboard](../scoreboard.md) · [summary](../summary.md) · [standings](../standings.md) · [teams](../teams.md) · [team-roster](../team-roster.md) · [rankings](../rankings.md)
- Canonical shape, ESPN→canonical mappings, per-league period/OT matrix: `schema/SCHEMA.md`, `schema/canonical.ts`
- Cross-sport support matrix: [index.md](../index.md)
