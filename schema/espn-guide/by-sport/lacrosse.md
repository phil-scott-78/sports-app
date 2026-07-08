# ESPN API — lacrosse

> Per-sport slice of the [observed data guide](../index.md): what ESPN actually serves for **lacrosse**, and which endpoint answers each need. Built from 130 real lacrosse responses — OBSERVED live, not documented. Regenerate: `node schema/tools/rollup.mjs`.

## Leagues — 4 in the registry

Competition **shape** drives rendering (see the discriminators in `schema/canonical.ts`): `layout · scoreKind · competitorKind`.

| shape (layout · scoreKind · competitorKind) | leagues | examples |
|---|---|---|
| `headToHead · numeric · team` | 4 | `pll`, `nll`, `mens-college-lacrosse`, `womens-college-lacrosse` |

**Crawled for this guide** (2): `lacrosse/nll`, `lacrosse/pll`. The evidence below is from these leagues; other lacrosse leagues in the registry inherit the same shape.

## Which endpoint to use

URL templates use `lacrosse/nll` as a representative league. Swap in any league key from the table above.

| need | endpoint | status | URL template | fields |
|---|---|---|---|---|
| Scores & live state | `scoreboard` | ✅ 28/28 | `https://site.api.espn.com/apis/site/v2/sports/lacrosse/nll/scoreboard` | [guide](../scoreboard.md) |
| Rich game detail | `summary` | ✅ 8/8 | `https://site.api.espn.com/apis/site/v2/sports/lacrosse/nll/summary?event={eventId}` | [guide](../summary.md) |
| League table | `standings` | ✅ 4/4 | `https://site.api.espn.com/apis/v2/sports/lacrosse/nll/standings` | [guide](../standings.md) |
| Team directory | `teams` | ✅ 2/2 | `https://site.api.espn.com/apis/site/v2/sports/lacrosse/nll/teams` | [guide](../teams.md) |
| Roster | `team-roster` | ✅ 4/4 | `https://site.api.espn.com/apis/site/v2/sports/lacrosse/nll/teams/{teamId}/roster` | [guide](../team-roster.md) |
| Schedule | `team-schedule` | ✅ 2/2 | `https://site.api.espn.com/apis/site/v2/sports/lacrosse/nll/teams/{teamId}/schedule` | [guide](../team-schedule.md) |
| Team season stats | `team-stats` | ❌ not served | `https://site.api.espn.com/apis/site/v2/sports/lacrosse/nll/teams/{teamId}/statistics` | [guide](../team-stats.md) |
| News | `news` | ✅ 2/2 | `https://site.api.espn.com/apis/site/v2/sports/lacrosse/nll/news?limit=5` | [guide](../news.md) |
| Injuries | `injuries` | ✅ 2/2 | `https://site.api.espn.com/apis/site/v2/sports/lacrosse/nll/teams/{teamId}/injuries` | [guide](../injuries.md) |

- **scoreboard** — The cheap poll — scores, status, line scores, and (situationally) situation, leaders, records, odds. The primary call. College needs `?groups=<id>&limit=400`; `?dates=YYYYMMDD-YYYYMMDD` for a range (cricket: single day only).
- **summary** — One extra fetch when a game is opened — box scores, scoring plays, rosters, penalty shootouts, method of victory. A 404 for the whole sport means this tier does not exist (build detail from the core graph instead).
- **standings** — ⚠ `apis/v2`, NOT `apis/site/v2` (the site path returns a `{fullViewLink}` stub). Omit `?season=` — ESPN defaults to the current season.
- **teams** — Team ids, names, abbreviations, logos, colors. The id feeds the roster/schedule/stats/injuries calls.
- **team-roster** — Per-team roster with positions and headshots.
- **team-schedule** — Per-team schedule, past results + upcoming fixtures.
- **team-stats** — Per-team season statistics. _(every attempt 404/400 — this tier does not exist for the sport)_
- **news** — Latest articles for the league.
- **injuries** — Per-team injury report.

## Core API — `sports.core.api.espn.com`

41 of the core resource shapes were reachable for lacrosse by following `$ref` links from the league root and its events (full matrix: [index.md](../index.md#core-api-resource-graph)). High-value shapes:

| resource | reachable | what it adds |
|---|---|---|
| `core-competitor-linescores` | ✅ | Per-period / per-set / per-inning scores — reachable even when the site scoreboard omits them (tennis sets, cricket innings). |
| `core-season-types-id-groups-id-standings` | ✅ | Standings through the core graph (grouped). |
| `core-rankings` | ✅ | Rankings through the core graph. |

## What's sport-specific in the data

Value-bearing fields observed for lacrosse that are **not** near-universal — the sport's fingerprint. **presence** = % of this sport's crawled responses (or parent objects) that carry the field (lacrosse-specific). Field paths, types, and presence are lacrosse-only; the **value/example samples are pooled** across the handful of sports that share a field (a nested `period` may show golf's "18" next to a fight's "1–3"), so read them as shape hints. The full per-sport field tables live in the per-endpoint guides linked above.

### scoreboard

| field | type | presence | values / examples |
|---|---|---|---|
| `events[].competitions[].highlights[].geoRestrictions.type` | string | 100% | values: "whitelist" (460) |
| `events[].competitions[].highlights[].geoRestrictions.countries[]` | string | — | e.g. "PR", "AS", "BI", "AG" |
| `events[].competitions[].status.type.altDetail` | string | 3% | values: "OT" (58), "SO" (17), "2OT" (9), "F/10" (9), "F/11" (5), "3OT" (1), "F/15" (1) |
| `events[].status.type.altDetail` | string | 3% | values: "OT" (58), "SO" (17), "2OT" (9), "F/10" (9), "F/11" (5), "3OT" (1), "F/15" (1) |

### summary

| field | type | presence | values / examples |
|---|---|---|---|
| `format.suddenDeath.clock` | number | 100% | values: 600 (6), 900 (5), 180 (5), 720 (4) |
| `format.suddenDeath.periods` | number | 100% | values: 0 (9), 2 (8), 1 (7) |
| `format.overtime.periods` | number | 50% | values: 2 (8), 1 (7) |
| `format.overtime.clock` | number | 100% | values: 300 (12), 600 (6), 900 (5), 180 (5), 720 (4) |
| `format.overtime.displayName` | string | 100% | values: "Quarter" (24), "sudden-death" (4), "untimed" (4), "Half" (4) |
| `format.overtime.slug` | string | 100% | values: "quarter" (24), "sudden-death" (4), "untimed" (4), "half" (4) |
| `news.articles[].categories[].event.description` | string | 100% | e.g. "India v Australia", "Colombia @ Switzerland", "Seattle Storm @ Los Angeles Sparks", "Connecticut Sun @ Minnesota Lynx" |
| `news.articles[].categories[].event.id` | number | 100% | e.g. 1384439, 760508, 401857045, 401857044 |
| `news.articles[].categories[].event.league` | string | 100% | values: "wnba" (36), "world cup" (25), "nll" (20), "mens-college-volleyball" (20), "pll" (16), "fifa.world" (12), "womens-college-volleyball" (4), "mlb" (2) |
| `news.articles[].categories[].event.sport` | string | 100% | values: "basketball" (36), "lacrosse" (36), "cricket" (25), "volleyball" (24), "soccer" (12), "baseball" (2) |
| `boxscore.players[].team.alternateColor` | string | 67% | e.g. "000000", "ffffff", "da291c", "a8adb4" |
| `news.articles[].categories[].eventId` | number | 6% | e.g. 1384439, 760508, 401857045, 401857044 |

## Go deeper

- Full field tables: [scoreboard](../scoreboard.md) · [summary](../summary.md) · [standings](../standings.md) · [teams](../teams.md) · [team-roster](../team-roster.md) · [rankings](../rankings.md)
- Canonical shape, ESPN→canonical mappings, per-league period/OT matrix: `schema/SCHEMA.md`, `schema/canonical.ts`
- Cross-sport support matrix: [index.md](../index.md)
