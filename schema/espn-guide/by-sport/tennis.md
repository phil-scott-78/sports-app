# ESPN API — tennis

> Per-sport slice of the [observed data guide](../index.md): what ESPN actually serves for **tennis**, and which endpoint answers each need. Built from 112 real tennis responses — OBSERVED live, not documented. Regenerate: `node schema/tools/rollup.mjs`.

## Leagues — 2 in the registry

Competition **shape** drives rendering (see the discriminators in `schema/canonical.ts`): `layout · scoreKind · competitorKind`.

| shape (layout · scoreKind · competitorKind) | leagues | examples |
|---|---|---|
| `headToHead · numeric · athlete` | 2 | `atp`, `wta` |

**Crawled for this guide** (2): `tennis/atp`, `tennis/wta`. The evidence below is from these leagues; other tennis leagues in the registry inherit the same shape.

## Which endpoint to use

URL templates use `tennis/wta` as a representative league. Swap in any league key from the table above.

| need | endpoint | status | URL template | fields |
|---|---|---|---|---|
| Scores & live state | `scoreboard` | ✅ 28/28 | `https://site.api.espn.com/apis/site/v2/sports/tennis/wta/scoreboard` | [guide](../scoreboard.md) |
| Rich game detail | `summary` | ❌ not served | `https://site.api.espn.com/apis/site/v2/sports/tennis/wta/summary?event={eventId}` | [guide](../summary.md) |
| League table | `standings` | ✅ 4/4 | `https://site.api.espn.com/apis/v2/sports/tennis/wta/standings` | [guide](../standings.md) |
| Team directory | `teams` | ✅ 2/2 | `https://site.api.espn.com/apis/site/v2/sports/tennis/wta/teams` | [guide](../teams.md) |
| Polls / rankings | `rankings` | ✅ 2/2 | `https://site.api.espn.com/apis/site/v2/sports/tennis/wta/rankings` | [guide](../rankings.md) |
| News | `news` | ✅ 2/2 | `https://site.api.espn.com/apis/site/v2/sports/tennis/wta/news?limit=5` | [guide](../news.md) |

- **scoreboard** — The cheap poll — scores, status, line scores, and (situationally) situation, leaders, records, odds. The primary call. College needs `?groups=<id>&limit=400`; `?dates=YYYYMMDD-YYYYMMDD` for a range (cricket: single day only).
- **summary** — One extra fetch when a game is opened — box scores, scoring plays, rosters, penalty shootouts, method of victory. A 404 for the whole sport means this tier does not exist (build detail from the core graph instead). _(every attempt 404/400 — this tier does not exist for the sport)_
- **standings** — ⚠ `apis/v2`, NOT `apis/site/v2` (the site path returns a `{fullViewLink}` stub). Omit `?season=` — ESPN defaults to the current season.
- **teams** — Team ids, names, abbreviations, logos, colors. The id feeds the roster/schedule/stats/injuries calls.
- **rankings** — College polls, ATP/WTA tour rankings, UFC divisional rankings. Only where a poll exists for the league.
- **news** — Latest articles for the league.

## Core API — `sports.core.api.espn.com`

37 of the core resource shapes were reachable for tennis by following `$ref` links from the league root and its events (full matrix: [index.md](../index.md#core-api-resource-graph)). High-value shapes:

| resource | reachable | what it adds |
|---|---|---|
| `core-competitor-linescores` | ✅ | Per-period / per-set / per-inning scores — reachable even when the site scoreboard omits them (tennis sets, cricket innings). |
| `core-odds` | ✅ | Betting lines / odds. |
| `core-competitor-roster` | ✅ | Game-day lineup. |
| `core-rankings` | ✅ | Rankings through the core graph. |
| `core-athlete` | ✅ | Athlete bio / profile. |

## What's sport-specific in the data

Value-bearing fields observed for tennis that are **not** near-universal — the sport's fingerprint. **presence** = % of this sport's crawled responses (or parent objects) that carry the field (tennis-specific). Field paths, types, and presence are tennis-only; the **value/example samples are pooled** across the handful of sports that share a field (a nested `period` may show golf's "18" next to a fight's "1–3"), so read them as shape hints. The full per-sport field tables live in the per-endpoint guides linked above.

### scoreboard

| field | type | presence | values / examples |
|---|---|---|---|
| `events[].calendar.timeZone` | string | 100% | values: "America/New_York" (118) |
| `events[].calendar.type` | string | 100% | values: "day" (118) |
| `events[].groupings[].competitions[].broadcast` | string | 100% | values: "" (5920), "ESPN+" (441), "ESPN Unlmtd" (156), "ESPN2" (6), "ESPN" (2), "ESPN/ESPN+" (2) |
| `events[].groupings[].competitions[].competitors[].curatedRank.current` | number | 100% | e.g. 2, 1, 3, 4 |
| `events[].groupings[].competitions[].competitors[].homeAway` | string | 100% | values: "away" (6527), "home" (6527) |
| `events[].groupings[].competitions[].competitors[].id` | string | 100% | e.g. "-4", "-3", "5734", "3568" |
| `events[].groupings[].competitions[].competitors[].linescores[].value` | number | 100% | values: 6 (12130), 7 (3263), 4 (3092), 3 (2984), 2 (2316), 1 (2196), 0 (1345), 5 (1334), 10 (17), 11 (3), 12 (2), 13 (2), 9 (1), 8 (1) |
| `events[].groupings[].competitions[].competitors[].linescores[].winner` | boolean | 100% | values: false (14433), true (14253) |
| `events[].groupings[].competitions[].competitors[].order` | number | 100% | values: 2 (6527), 1 (6527) |
| `events[].groupings[].competitions[].competitors[].roster.athletes[].displayName` | string | 100% | e.g. "Evan King", "Lucas Miedler", "Marcelo Arevalo", "JJ Tracy" |
| `events[].groupings[].competitions[].competitors[].roster.athletes[].fullName` | string | 100% | e.g. "Evan King", "Lucas Miedler", "Marcelo Arevalo", "JJ Tracy" |
| `events[].groupings[].competitions[].competitors[].roster.athletes[].shortName` | string | 100% | e.g. "E. King", "L. Miedler", "M. Arevalo", "J. Tracy" |
| `events[].groupings[].competitions[].competitors[].roster.displayName` | string | 100% | e.g. "Orlando Luz / Rafael Matos", "Marcelo Arevalo / Mate Pavic", "Theo Arribage / Albano Olivetti", "Robert Cash / JJ Tracy" |
| `events[].groupings[].competitions[].competitors[].roster.shortDisplayName` | string | 100% | e.g. "O. Luz / R. Matos", "M. Arevalo / M. Pavic", "T. Arribage / A. Olivetti", "R. Cash / J. Tracy" |
| `events[].groupings[].competitions[].competitors[].type` | string | 100% | values: "athlete" (7744), "team" (5310) |
| `events[].groupings[].competitions[].format.regulation.periods` | number | 100% | values: 3 (4094), 5 (2433) |
| `events[].groupings[].competitions[].id` | str-numeric | 100% | e.g. "178675", "178677", "178684", "178683" |
| `events[].groupings[].competitions[].notes[].text` | string | 100% | e.g. "Irene Burillo (ESP) bt Noma Noha Akugue (GER) 7-5 2-6 6-2", "Moyuka Uchijima (JPN) bt (1) Oleksandra Oliynykova (UKR) 5-7 6-2 7-5", "Miriam Bulgaru (ROM) bt Valeriya Strakhova (UKR) 6-2 6-2", "Leyre Romero Gormaz (ESP) bt (7) Darja Semenistaja (LAT) 6-2 2-6 6-2" |
| `events[].groupings[].competitions[].notes[].type` | string | 100% | values: "event" (6218) |
| `events[].groupings[].competitions[].recent` | boolean | 100% | values: false (6527) |
| `events[].groupings[].competitions[].round.displayName` | string | 100% | values: "Round 1" (3005), "Qualifying 1st Round" (1640), "Qualifying Final" (527), "Round 2" (485), "Quarterfinal" (483), "Semifinal" (227), "Final" (112), "Group Stage" (48) |
| `events[].groupings[].competitions[].round.id` | str-numeric | 100% | values: "1" (3005), "11" (1640), "14" (527), "2" (485), "5" (483), "6" (227), "7" (112), "15" (48) |
| `events[].groupings[].competitions[].status.period` | number | 100% | values: 2 (4006), 3 (2101), 1 (420) |
| `events[].groupings[].competitions[].status.type.completed` | boolean | 100% | values: true (6221), false (306) |
| `events[].groupings[].competitions[].status.type.description` | string | 100% | values: "Final" (6046), "Scheduled" (306), "Retired" (89), "Walkover" (86) |
| `events[].groupings[].competitions[].status.type.detail` | string | 100% | values: "Final" (6046), "M/d - 'TBD'" (226), "Retired" (89), "Walkover" (86), "Wed, July 8th at 5:00 AM EDT" (12), "Wed, July 8th at 6:30 AM EDT" (12), "Wed, July 8th at 8:00 AM EDT" (12), "Wed, July 8th at 9:30 AM EDT" (12), "Wed, July 8th at 11:00 AM EDT" (10), "Wed, July 8th at 2:00 PM EDT" (10), "Wed, July 8th at 5:00 PM EDT" (8), "Wed, July 8th at 12:30 PM EDT" (2), "Wed, July 8th at 3:30 PM EDT" (2) |
| `events[].groupings[].competitions[].status.type.id` | str-numeric | 100% | values: "3" (6046), "1" (306), "38" (89), "40" (86) |
| `events[].groupings[].competitions[].status.type.name` | string | 100% | values: "STATUS_FINAL" (6046), "STATUS_SCHEDULED" (306), "STATUS_RETIRED" (89), "STATUS_WALKOVER" (86) |
| `events[].groupings[].competitions[].status.type.shortDetail` | string | 100% | values: "Final" (6046), "TBD" (226), "Retired" (89), "Walkover" (86), "7/8 - 5:00 AM EDT" (12), "7/8 - 6:30 AM EDT" (12), "7/8 - 8:00 AM EDT" (12), "7/8 - 9:30 AM EDT" (12), "7/8 - 11:00 AM EDT" (10), "7/8 - 2:00 PM EDT" (10), "7/8 - 5:00 PM EDT" (8), "7/8 - 12:30 PM EDT" (2), "7/8 - 3:30 PM EDT" (2) |
| `events[].groupings[].competitions[].status.type.state` | string | 100% | values: "post" (6221), "pre" (306) |
| `events[].groupings[].competitions[].timeValid` | boolean | 100% | values: true (6279), false (248) |
| `events[].groupings[].competitions[].tournamentId` | number | 100% | e.g. 306, 188, 172, 154 |
| `events[].groupings[].competitions[].type.id` | str-numeric | 100% | values: "2" (2465), "4" (1530), "1" (1315), "3" (1037), "6" (180) |
| `events[].groupings[].competitions[].type.slug` | string | 100% | values: "womens-singles" (2465), "womens-doubles" (1530), "mens-singles" (1315), "mens-doubles" (1037), "mixed-doubles" (180) |
| `events[].groupings[].competitions[].type.text` | string | 100% | values: "Women's Singles" (2465), "Women's Doubles" (1530), "Men's Singles" (1315), "Men's Doubles" (1037), "Mixed Doubles" (180) |
| `events[].groupings[].competitions[].venue.court` | string | 100% | e.g. "Court 1", "Center Court", "Court 2", "Court 3" |
| `events[].groupings[].competitions[].venue.fullName` | string | 100% | e.g. "Båstad, Sweden", "Paris, France", "London, Great Britain", "Melbourne, Australia" |
| `events[].groupings[].competitions[].wasSuspended` | boolean | 100% | values: false (6527) |
| `events[].groupings[].grouping.displayName` | string | 100% | values: "Women's Singles" (99), "Women's Doubles" (97), "Men's Singles" (53), "Men's Doubles" (53), "Mixed Doubles" (8) |
| `events[].groupings[].grouping.id` | str-numeric | 100% | values: "2" (99), "4" (97), "1" (53), "3" (53), "6" (8) |
| `events[].groupings[].grouping.slug` | string | 100% | values: "womens-singles" (99), "womens-doubles" (97), "mens-singles" (53), "mens-doubles" (53), "mixed-doubles" (8) |
| `events[].major` | boolean | 100% | values: false (110), true (8) |
| `events[].previousWinners[].athletes[].displayName` | string | 100% | e.g. "Marcel Granollers", "Horacio Zeballos", "Sara Errani", "Marcelo Arevalo" |
| `events[].previousWinners[].athletes[].shortDisplayName` | string | 100% | e.g. "M. Granollers", "H. Zeballos", "S. Errani", "M. Arevalo" |
| `events[].previousWinners[].displayName` | string | 100% | e.g. "Jannik Sinner", "Aryna Sabalenka", "Carlos Alcaraz", "Marcel Granollers / Horacio Zeballos" |
| `events[].previousWinners[].shortDisplayName` | string | 100% | e.g. "J. Sinner", "A. Sabalenka", "C. Alcaraz", "M. Granollers / H. Zeballos" |
| `events[].previousWinners[].type.id` | str-numeric | 100% | values: "2" (77), "1" (52), "4" (35), "3" (33), "6" (8) |
| `events[].previousWinners[].type.slug` | string | 100% | values: "womens-singles" (77), "mens-singles" (52), "womens-doubles" (35), "mens-doubles" (33), "mixed-doubles" (8) |
| `events[].previousWinners[].type.text` | string | 100% | values: "Women's Singles" (77), "Men's Singles" (52), "Women's Doubles" (35), "Men's Doubles" (33), "Mixed Doubles" (8) |
| `events[].groupings[].competitions[].competitors[].winner` | boolean | 95% | values: false (6224), true (6218) |
| `events[].groupings[].competitions[].competitors[].linescores[].tiebreak` | number | 19% | e.g. 7, 10, 5, 4 |
| `events[].venue.displayName` | string | 100% | e.g. "San Siro", "Olimpico", "St. James' Park", "Riyadh Air Metropolitano" |

## Go deeper

- Full field tables: [scoreboard](../scoreboard.md) · [summary](../summary.md) · [standings](../standings.md) · [teams](../teams.md) · [team-roster](../team-roster.md) · [rankings](../rankings.md)
- Canonical shape, ESPN→canonical mappings, per-league period/OT matrix: `schema/SCHEMA.md`, `schema/canonical.ts`
- Cross-sport support matrix: [index.md](../index.md)
