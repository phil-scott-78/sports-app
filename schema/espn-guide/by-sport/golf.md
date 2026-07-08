# ESPN API — golf

> Per-sport slice of the [observed data guide](../index.md): what ESPN actually serves for **golf**, and which endpoint answers each need. Built from 127 real golf responses — OBSERVED live, not documented. Regenerate: `node schema/tools/rollup.mjs`.

## Leagues — 9 in the registry

Competition **shape** drives rendering (see the discriminators in `schema/canonical.ts`): `layout · scoreKind · competitorKind`.

| shape (layout · scoreKind · competitorKind) | leagues | examples |
|---|---|---|
| `field · toPar · athlete` | 8 | `pga`, `lpga`, `eur`, `champions-tour` |
| `headToHead · numeric · team` | 1 | `tgl` |

**Crawled for this guide** (2): `golf/lpga`, `golf/pga`. The evidence below is from these leagues; other golf leagues in the registry inherit the same shape.

## Which endpoint to use

URL templates use `golf/lpga` as a representative league. Swap in any league key from the table above.

| need | endpoint | status | URL template | fields |
|---|---|---|---|---|
| Scores & live state | `scoreboard` | ✅ 28/28 | `https://site.api.espn.com/apis/site/v2/sports/golf/lpga/scoreboard` | [guide](../scoreboard.md) |
| Rich game detail | `summary` | ❌ not served | `https://site.api.espn.com/apis/site/v2/sports/golf/lpga/summary?event={eventId}` | [guide](../summary.md) |
| League table | `standings` | ✅ 4/4 | `https://site.api.espn.com/apis/v2/sports/golf/lpga/standings` | [guide](../standings.md) |
| Team directory | `teams` | ✅ 2/2 | `https://site.api.espn.com/apis/site/v2/sports/golf/lpga/teams` | [guide](../teams.md) |
| News | `news` | ✅ 2/2 | `https://site.api.espn.com/apis/site/v2/sports/golf/lpga/news?limit=5` | [guide](../news.md) |
| Hole-by-hole | `golf-playersummary` | ✅ 2/2 | `https://site.web.api.espn.com/apis/site/v2/sports/golf/lpga/leaderboard/{eventId}/playersummary?player={athleteId}` | [guide](../golf-playersummary.md) |

- **scoreboard** — The cheap poll — scores, status, line scores, and (situationally) situation, leaders, records, odds. The primary call. College needs `?groups=<id>&limit=400`; `?dates=YYYYMMDD-YYYYMMDD` for a range (cricket: single day only).
- **summary** — One extra fetch when a game is opened — box scores, scoring plays, rosters, penalty shootouts, method of victory. A 404 for the whole sport means this tier does not exist (build detail from the core graph instead). _(every attempt 404/400 — this tier does not exist for the sport)_
- **standings** — ⚠ `apis/v2`, NOT `apis/site/v2` (the site path returns a `{fullViewLink}` stub). Omit `?season=` — ESPN defaults to the current season.
- **teams** — Team ids, names, abbreviations, logos, colors. The id feeds the roster/schedule/stats/injuries calls.
- **news** — Latest articles for the league.
- **golf-playersummary** — Golf only — per-player hole-by-hole scoring (web host, not the site host).

## Core API — `sports.core.api.espn.com`

44 of the core resource shapes were reachable for golf by following `$ref` links from the league root and its events (full matrix: [index.md](../index.md#core-api-resource-graph)). High-value shapes:

| resource | reachable | what it adds |
|---|---|---|
| `core-competitor-linescores` | ✅ | Per-period / per-set / per-inning scores — reachable even when the site scoreboard omits them (tennis sets, cricket innings). |
| `core-competitor-statistics` | ✅ | Competitor's game statistics. |

## What's sport-specific in the data

Value-bearing fields observed for golf that are **not** near-universal — the sport's fingerprint. **presence** = % of this sport's crawled responses (or parent objects) that carry the field (golf-specific). Field paths, types, and presence are golf-only; the **value/example samples are pooled** across the handful of sports that share a field (a nested `period` may show golf's "18" next to a fight's "1–3"), so read them as shape hints. The full per-sport field tables live in the per-endpoint guides linked above.

### scoreboard

| field | type | presence | values / examples |
|---|---|---|---|
| `events[].competitions[].competitors[].linescores[].linescores[].scoreType.displayValue` | string | 100% | values: "E" (28907), "-1" (11706), "+1" (4871), "+2" (594), "-2" (344), "+3" (27), "-3" (4), "+5" (3), "OTHER" (1) |
| `events[].competitions[].competitors[].linescores[].statistics.categories[].stats[].displayValue` | string | 100% | e.g. "0", "0.0", "1", "3" |
| `leagues[].calendar[].id` | str-numeric | 100% | e.g. "401811927", "401811930", "401811931", "401811934" |
| `events[].competitions[].competitors[].linescores[].statistics.categories[].stats[].value` | number | 86% | e.g. 0, 1, 2, 3 |
| `events[].competitions[].competitors[].linescores[].linescores[].displayValue` | str-numeric | 100% | e.g. "4", "3", "5", "2" |
| `events[].competitions[].competitors[].linescores[].linescores[].period` | number | 100% | e.g. 18, 1, 2, 3 |
| `events[].competitions[].competitors[].linescores[].linescores[].value` | number | 100% | e.g. 4, 3, 5, 2 |

## Go deeper

- Full field tables: [scoreboard](../scoreboard.md) · [summary](../summary.md) · [standings](../standings.md) · [teams](../teams.md) · [team-roster](../team-roster.md) · [rankings](../rankings.md)
- Canonical shape, ESPN→canonical mappings, per-league period/OT matrix: `schema/SCHEMA.md`, `schema/canonical.ts`
- Cross-sport support matrix: [index.md](../index.md)
