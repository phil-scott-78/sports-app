# ESPN API — field-hockey

> Per-sport slice of the [observed data guide](../index.md): what ESPN actually serves for **field-hockey**, and which endpoint answers each need. Built from 49 real field-hockey responses — OBSERVED live, not documented. Regenerate: `node schema/tools/rollup.mjs`.

## Leagues — 1 in the registry

Competition **shape** drives rendering (see the discriminators in `schema/canonical.ts`): `layout · scoreKind · competitorKind`.

| shape (layout · scoreKind · competitorKind) | leagues | examples |
|---|---|---|
| `headToHead · numeric · team` | 1 | `womens-college-field-hockey` |

**Crawled for this guide** (1): `field-hockey/womens-college-field-hockey`. The evidence below is from these leagues; other field-hockey leagues in the registry inherit the same shape.

## Which endpoint to use

URL templates use `field-hockey/womens-college-field-hockey` as a representative league. Swap in any league key from the table above.

| need | endpoint | status | URL template | fields |
|---|---|---|---|---|
| Scores & live state | `scoreboard` | ✅ 14/14 | `https://site.api.espn.com/apis/site/v2/sports/field-hockey/womens-college-field-hockey/scoreboard` | [guide](../scoreboard.md) |
| Rich game detail | `summary` | ✅ 3/4 | `https://site.api.espn.com/apis/site/v2/sports/field-hockey/womens-college-field-hockey/summary?event={eventId}` | [guide](../summary.md) |
| League table | `standings` | ✅ 2/2 | `https://site.api.espn.com/apis/v2/sports/field-hockey/womens-college-field-hockey/standings` | [guide](../standings.md) |
| Team directory | `teams` | ✅ 1/1 | `https://site.api.espn.com/apis/site/v2/sports/field-hockey/womens-college-field-hockey/teams` | [guide](../teams.md) |
| News | `news` | ✅ 1/1 | `https://site.api.espn.com/apis/site/v2/sports/field-hockey/womens-college-field-hockey/news?limit=5` | [guide](../news.md) |

- **scoreboard** — The cheap poll — scores, status, line scores, and (situationally) situation, leaders, records, odds. The primary call. College needs `?groups=<id>&limit=400`; `?dates=YYYYMMDD-YYYYMMDD` for a range (cricket: single day only).
- **summary** — One extra fetch when a game is opened — box scores, scoring plays, rosters, penalty shootouts, method of victory. A 404 for the whole sport means this tier does not exist (build detail from the core graph instead).
- **standings** — ⚠ `apis/v2`, NOT `apis/site/v2` (the site path returns a `{fullViewLink}` stub). Omit `?season=` — ESPN defaults to the current season.
- **teams** — Team ids, names, abbreviations, logos, colors. The id feeds the roster/schedule/stats/injuries calls.
- **news** — Latest articles for the league.

## Core API — `sports.core.api.espn.com`

28 of the core resource shapes were reachable for field-hockey by following `$ref` links from the league root and its events (full matrix: [index.md](../index.md#core-api-resource-graph)). High-value shapes:

| resource | reachable | what it adds |
|---|---|---|
| `core-rankings` | ✅ | Rankings through the core graph. |

## What's sport-specific in the data

Value-bearing fields observed for field-hockey that are **not** near-universal — the sport's fingerprint. **presence** = % of this sport's crawled responses (or parent objects) that carry the field (field-hockey-specific). Field paths, types, and presence are field-hockey-only; the **value/example samples are pooled** across the handful of sports that share a field (a nested `period` may show golf's "18" next to a fight's "1–3"), so read them as shape hints. The full per-sport field tables live in the per-endpoint guides linked above.

### scoreboard

| field | type | presence | values / examples |
|---|---|---|---|
| `events[].competitions[].competitors[].curatedRank.current` | number | 100% | e.g. 99, 2, 1, 3 |
| `events[].competitions[].status.type.altDetail` | string | 17% | values: "OT" (58), "SO" (17), "2OT" (9), "F/10" (9), "F/11" (5), "3OT" (1), "F/15" (1) |
| `events[].status.type.altDetail` | string | 17% | values: "OT" (58), "SO" (17), "2OT" (9), "F/10" (9), "F/11" (5), "3OT" (1), "F/15" (1) |

### summary

| field | type | presence | values / examples |
|---|---|---|---|
| `format.shootout.displayName` | string | 100% | e.g. "Penalty Stroke" |
| `format.shootout.periods` | number | 100% | e.g. 1 |
| `format.shootout.slug` | string | 100% | e.g. "penalty-stroke" |
| `format.overtime.periods` | number | 100% | values: 2 (8), 1 (7) |
| `format.suddenDeath.clock` | number | 100% | values: 600 (6), 900 (5), 180 (5), 720 (4) |
| `format.suddenDeath.periods` | number | 100% | values: 0 (9), 2 (8), 1 (7) |
| `format.overtime.clock` | number | 100% | values: 300 (12), 600 (6), 900 (5), 180 (5), 720 (4) |
| `format.overtime.displayName` | string | 100% | values: "Quarter" (24), "sudden-death" (4), "untimed" (4), "Half" (4) |
| `format.overtime.slug` | string | 100% | values: "quarter" (24), "sudden-death" (4), "untimed" (4), "half" (4) |

## Go deeper

- Full field tables: [scoreboard](../scoreboard.md) · [summary](../summary.md) · [standings](../standings.md) · [teams](../teams.md) · [team-roster](../team-roster.md) · [rankings](../rankings.md)
- Canonical shape, ESPN→canonical mappings, per-league period/OT matrix: `schema/SCHEMA.md`, `schema/canonical.ts`
- Cross-sport support matrix: [index.md](../index.md)
