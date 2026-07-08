# ESPN API — water-polo

> Per-sport slice of the [observed data guide](../index.md): what ESPN actually serves for **water-polo**, and which endpoint answers each need. Built from 95 real water-polo responses — OBSERVED live, not documented. Regenerate: `node schema/tools/rollup.mjs`.

## Leagues — 2 in the registry

Competition **shape** drives rendering (see the discriminators in `schema/canonical.ts`): `layout · scoreKind · competitorKind`.

| shape (layout · scoreKind · competitorKind) | leagues | examples |
|---|---|---|
| `headToHead · numeric · team` | 2 | `mens-college-water-polo`, `womens-college-water-polo` |

**Crawled for this guide** (2): `water-polo/mens-college-water-polo`, `water-polo/womens-college-water-polo`. The evidence below is from these leagues; other water-polo leagues in the registry inherit the same shape.

## Which endpoint to use

URL templates use `water-polo/womens-college-water-polo` as a representative league. Swap in any league key from the table above.

| need | endpoint | status | URL template | fields |
|---|---|---|---|---|
| Scores & live state | `scoreboard` | ✅ 28/28 | `https://site.api.espn.com/apis/site/v2/sports/water-polo/womens-college-water-polo/scoreboard` | [guide](../scoreboard.md) |
| Rich game detail | `summary` | ✅ 5/5 | `https://site.api.espn.com/apis/site/v2/sports/water-polo/womens-college-water-polo/summary?event={eventId}` | [guide](../summary.md) |
| League table | `standings` | ✅ 4/4 | `https://site.api.espn.com/apis/v2/sports/water-polo/womens-college-water-polo/standings` | [guide](../standings.md) |
| Team directory | `teams` | ✅ 2/2 | `https://site.api.espn.com/apis/site/v2/sports/water-polo/womens-college-water-polo/teams` | [guide](../teams.md) |
| News | `news` | ✅ 2/2 | `https://site.api.espn.com/apis/site/v2/sports/water-polo/womens-college-water-polo/news?limit=5` | [guide](../news.md) |

- **scoreboard** — The cheap poll — scores, status, line scores, and (situationally) situation, leaders, records, odds. The primary call. College needs `?groups=<id>&limit=400`; `?dates=YYYYMMDD-YYYYMMDD` for a range (cricket: single day only).
- **summary** — One extra fetch when a game is opened — box scores, scoring plays, rosters, penalty shootouts, method of victory. A 404 for the whole sport means this tier does not exist (build detail from the core graph instead).
- **standings** — ⚠ `apis/v2`, NOT `apis/site/v2` (the site path returns a `{fullViewLink}` stub). Omit `?season=` — ESPN defaults to the current season.
- **teams** — Team ids, names, abbreviations, logos, colors. The id feeds the roster/schedule/stats/injuries calls.
- **news** — Latest articles for the league.

## Core API — `sports.core.api.espn.com`

28 of the core resource shapes were reachable for water-polo by following `$ref` links from the league root and its events (full matrix: [index.md](../index.md#core-api-resource-graph)). High-value shapes:

| resource | reachable | what it adds |
|---|---|---|
| `core-competitor-linescores` | ✅ | Per-period / per-set / per-inning scores — reachable even when the site scoreboard omits them (tennis sets, cricket innings). |
| `core-rankings` | ✅ | Rankings through the core graph. |

## What's sport-specific in the data

Value-bearing fields observed for water-polo that are **not** near-universal — the sport's fingerprint. **presence** = % of this sport's crawled responses (or parent objects) that carry the field (water-polo-specific). Field paths, types, and presence are water-polo-only; the **value/example samples are pooled** across the handful of sports that share a field (a nested `period` may show golf's "18" next to a fight's "1–3"), so read them as shape hints. The full per-sport field tables live in the per-endpoint guides linked above.

### scoreboard

| field | type | presence | values / examples |
|---|---|---|---|
| `events[].competitions[].competitors[].curatedRank.current` | number | 100% | e.g. 99, 2, 1, 3 |

### summary

| field | type | presence | values / examples |
|---|---|---|---|
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
