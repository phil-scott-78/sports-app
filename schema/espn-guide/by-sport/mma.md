# ESPN API — mma

> Per-sport slice of the [observed data guide](../index.md): what ESPN actually serves for **mma**, and which endpoint answers each need. Built from 94 real mma responses — OBSERVED live, not documented. Regenerate: `node schema/tools/rollup.mjs`.

## Leagues — 14 in the registry

Competition **shape** drives rendering (see the discriminators in `schema/canonical.ts`): `layout · scoreKind · competitorKind`.

| shape (layout · scoreKind · competitorKind) | leagues | examples |
|---|---|---|
| `headToHead · none · athlete` | 14 | `ufc`, `pfl`, `bellator`, `ksw` |

**Crawled for this guide** (2): `mma/pfl`, `mma/ufc`. The evidence below is from these leagues; other mma leagues in the registry inherit the same shape.

## Which endpoint to use

URL templates use `mma/pfl` as a representative league. Swap in any league key from the table above.

| need | endpoint | status | URL template | fields |
|---|---|---|---|---|
| Scores & live state | `scoreboard` | ✅ 28/28 | `https://site.api.espn.com/apis/site/v2/sports/mma/pfl/scoreboard` | [guide](../scoreboard.md) |
| Rich game detail | `summary` | ❌ not served | `https://site.api.espn.com/apis/site/v2/sports/mma/pfl/summary?event={eventId}` | [guide](../summary.md) |
| League table | `standings` | ✅ 4/4 | `https://site.api.espn.com/apis/v2/sports/mma/pfl/standings` | [guide](../standings.md) |
| Team directory | `teams` | ✅ 2/2 | `https://site.api.espn.com/apis/site/v2/sports/mma/pfl/teams` | [guide](../teams.md) |
| Polls / rankings | `rankings` | ✅ 1/1 | `https://site.api.espn.com/apis/site/v2/sports/mma/pfl/rankings` | [guide](../rankings.md) |
| News | `news` | ✅ 2/2 | `https://site.api.espn.com/apis/site/v2/sports/mma/pfl/news?limit=5` | [guide](../news.md) |

- **scoreboard** — The cheap poll — scores, status, line scores, and (situationally) situation, leaders, records, odds. The primary call. College needs `?groups=<id>&limit=400`; `?dates=YYYYMMDD-YYYYMMDD` for a range (cricket: single day only).
- **summary** — One extra fetch when a game is opened — box scores, scoring plays, rosters, penalty shootouts, method of victory. A 404 for the whole sport means this tier does not exist (build detail from the core graph instead). _(every attempt 404/400 — this tier does not exist for the sport)_
- **standings** — ⚠ `apis/v2`, NOT `apis/site/v2` (the site path returns a `{fullViewLink}` stub). Omit `?season=` — ESPN defaults to the current season.
- **teams** — Team ids, names, abbreviations, logos, colors. The id feeds the roster/schedule/stats/injuries calls.
- **rankings** — College polls, ATP/WTA tour rankings, UFC divisional rankings. Only where a poll exists for the league.
- **news** — Latest articles for the league.

## Core API — `sports.core.api.espn.com`

32 of the core resource shapes were reachable for mma by following `$ref` links from the league root and its events (full matrix: [index.md](../index.md#core-api-resource-graph)). High-value shapes:

| resource | reachable | what it adds |
|---|---|---|
| `core-competitor-linescores` | ✅ | Per-period / per-set / per-inning scores — reachable even when the site scoreboard omits them (tennis sets, cricket innings). |
| `core-plays` | ✅ | Play-by-play feed. |
| `core-competition-plays-id` | ✅ | Individual play detail. |
| `core-competitor-statistics` | ✅ | Competitor's game statistics. |
| `core-athlete` | ✅ | Athlete bio / profile. |
| `core-competition-officials` | ✅ | Match officials / referees. |

## What's sport-specific in the data

Value-bearing fields observed for mma that are **not** near-universal — the sport's fingerprint. **presence** = % of this sport's crawled responses (or parent objects) that carry the field (mma-specific). Field paths, types, and presence are mma-only; the **value/example samples are pooled** across the handful of sports that share a field (a nested `period` may show golf's "18" next to a fight's "1–3"), so read them as shape hints. The full per-sport field tables live in the per-endpoint guides linked above.

### scoreboard

| field | type | presence | values / examples |
|---|---|---|---|
| `events[].competitions[].competitors[].athlete.accolades[].id` | str-numeric | 100% | e.g. "711", "380", "477", "478" |
| `events[].competitions[].competitors[].athlete.accolades[].name` | string | 100% | e.g. "UFC Flyweight Title", "UFC Middleweight Title", "UFC Featherweight Title", "UFC Bantamweight Title" |
| `events[].competitions[].competitors[].athlete.accolades[].type` | string | 100% | e.g. "Belt" |
| `events[].competitions[].details[].id` | str-numeric | 100% | e.g. "16158", "16159", "16160", "16157" |
| `events[].venues[].address.city` | string | 100% | values: "Las Vegas" (14), "Dubai" (2), "Cotai" (1), "Perth" (1), "Newark" (1), "Sydney" (1), "Austin" (1), "Rio De Janeiro" (1), "Paris" (1), "Sioux Falls" (1), "Nashville" (1) |
| `events[].venues[].address.country` | string | 100% | values: "USA" (18), "Australia" (2), "United Arab Emirates" (2), "Macau" (1), "Brazil" (1), "France" (1) |
| `events[].venues[].fullName` | string | 100% | values: "Meta APEX" (10), "T-Mobile Arena" (4), "Coca-Cola Arena" (2), "Galaxy Arena" (1), "RAC Arena (AUS)" (1), "Prudential Center" (1), "Qudos Bank Arena" (1), "Moody Center" (1), "Farmasi Arena" (1), "Accor Arena" (1), "Sanford Pentagon" (1), "Bridgestone Arena" (1) |
| `events[].venues[].id` | str-numeric | 100% | values: "6176" (10), "5060" (4), "11174" (2), "10671" (1), "6524" (1), "1826" (1), "5415" (1), "7317" (1), "3155" (1), "10660" (1), "4796" (1), "1834" (1) |
| `leagues[].displayName` | string | 100% | values: "UFC" (14), "PFL" (14) |
| `leagues[].shortName` | string | 100% | values: "UFC" (14), "PFL" (14) |
| `events[].competitions[].status.featured` | boolean | 92% | values: false (251), true (9) |
| `events[].venues[].address.state` | string | 80% | values: "NV" (14), "WA" (1), "NJ" (1), "NSW" (1), "TX" (1), "SD" (1), "TN" (1) |
| `events[].competitions[].venue.address.address1` | string | 36% | values: "3780 South Las Vegas Boulevard" (54), "165 MULBERRY STREET" (13), "2210 W Pentagon Pl" (12), "501 Broadway" (12), "2001 Dedman Drive" (10) |
| `events[].venues[].address.address1` | string | 32% | values: "3780 South Las Vegas Boulevard" (4), "165 MULBERRY STREET" (1), "2001 Dedman Drive" (1), "2210 W Pentagon Pl" (1), "501 Broadway" (1) |
| `events[].competitions[].competitors[].linescores[].linescores[].displayValue` | str-numeric | 100% | e.g. "4", "3", "5", "2" |
| `events[].competitions[].competitors[].linescores[].linescores[].period` | number | 100% | e.g. 18, 1, 2, 3 |
| `events[].competitions[].competitors[].linescores[].linescores[].value` | number | 100% | e.g. 4, 3, 5, 2 |
| `events[].competitions[].details[].type.id` | str-numeric | 100% | e.g. "94", "70", "7", "8" |
| `events[].competitions[].details[].type.text` | string | 100% | e.g. "Yellow Card", "Goal", "player substituted", "substitute on" |
| `events[].competitions[].highlights[].geoRestrictions.type` | string | 100% | values: "whitelist" (460) |
| `events[].competitions[].venue.address.country` | string | 100% | e.g. "USA", "England", "Spain", "Italy" |
| `events[].competitions[].highlights[].geoRestrictions.countries[]` | string | — | e.g. "PR", "AS", "BI", "AG" |

## Go deeper

- Full field tables: [scoreboard](../scoreboard.md) · [summary](../summary.md) · [standings](../standings.md) · [teams](../teams.md) · [team-roster](../team-roster.md) · [rankings](../rankings.md)
- Canonical shape, ESPN→canonical mappings, per-league period/OT matrix: `schema/SCHEMA.md`, `schema/canonical.ts`
- Cross-sport support matrix: [index.md](../index.md)
