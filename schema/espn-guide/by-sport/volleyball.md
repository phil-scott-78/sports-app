# ESPN API — volleyball

> Per-sport slice of the [observed data guide](../index.md): what ESPN actually serves for **volleyball**, and which endpoint answers each need. Built from 173 real volleyball responses — OBSERVED live, not documented. Regenerate: `node schema/tools/rollup.mjs`.

## Leagues — 2 in the registry

Competition **shape** drives rendering (see the discriminators in `schema/canonical.ts`): `layout · scoreKind · competitorKind`.

| shape (layout · scoreKind · competitorKind) | leagues | examples |
|---|---|---|
| `headToHead · numeric · team` | 2 | `womens-college-volleyball`, `mens-college-volleyball` |

**Crawled for this guide** (2): `volleyball/mens-college-volleyball`, `volleyball/womens-college-volleyball`. The evidence below is from these leagues; other volleyball leagues in the registry inherit the same shape.

## Which endpoint to use

URL templates use `volleyball/womens-college-volleyball` as a representative league. Swap in any league key from the table above.

| need | endpoint | status | URL template | fields |
|---|---|---|---|---|
| Scores & live state | `scoreboard` | ✅ 27/28 | `https://site.api.espn.com/apis/site/v2/sports/volleyball/womens-college-volleyball/scoreboard` | [guide](../scoreboard.md) |
| Rich game detail | `summary` | ✅ 8/8 | `https://site.api.espn.com/apis/site/v2/sports/volleyball/womens-college-volleyball/summary?event={eventId}` | [guide](../summary.md) |
| League table | `standings` | ✅ 4/4 | `https://site.api.espn.com/apis/v2/sports/volleyball/womens-college-volleyball/standings` | [guide](../standings.md) |
| Team directory | `teams` | ✅ 2/2 | `https://site.api.espn.com/apis/site/v2/sports/volleyball/womens-college-volleyball/teams` | [guide](../teams.md) |
| Roster | `team-roster` | ✅ 4/4 | `https://site.api.espn.com/apis/site/v2/sports/volleyball/womens-college-volleyball/teams/{teamId}/roster` | [guide](../team-roster.md) |
| Schedule | `team-schedule` | ✅ 2/2 | `https://site.api.espn.com/apis/site/v2/sports/volleyball/womens-college-volleyball/teams/{teamId}/schedule` | [guide](../team-schedule.md) |
| Team season stats | `team-stats` | ❌ not served | `https://site.api.espn.com/apis/site/v2/sports/volleyball/womens-college-volleyball/teams/{teamId}/statistics` | [guide](../team-stats.md) |
| News | `news` | ✅ 2/2 | `https://site.api.espn.com/apis/site/v2/sports/volleyball/womens-college-volleyball/news?limit=5` | [guide](../news.md) |
| Injuries | `injuries` | ✅ 2/2 | `https://site.api.espn.com/apis/site/v2/sports/volleyball/womens-college-volleyball/teams/{teamId}/injuries` | [guide](../injuries.md) |

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

66 of the core resource shapes were reachable for volleyball by following `$ref` links from the league root and its events (full matrix: [index.md](../index.md#core-api-resource-graph)). High-value shapes:

| resource | reachable | what it adds |
|---|---|---|
| `core-competitor-linescores` | ✅ | Per-period / per-set / per-inning scores — reachable even when the site scoreboard omits them (tennis sets, cricket innings). |
| `core-situation` | ✅ | Live game situation (baseball base/out, gridiron down & distance). |
| `core-season-types-id-groups-id-standings` | ✅ | Standings through the core graph (grouped). |
| `core-rankings` | ✅ | Rankings through the core graph. |

## What's sport-specific in the data

Value-bearing fields observed for volleyball that are **not** near-universal — the sport's fingerprint. **presence** = % of this sport's crawled responses (or parent objects) that carry the field (volleyball-specific). Field paths, types, and presence are volleyball-only; the **value/example samples are pooled** across the handful of sports that share a field (a nested `period` may show golf's "18" next to a fight's "1–3"), so read them as shape hints. The full per-sport field tables live in the per-endpoint guides linked above.

### scoreboard

| field | type | presence | values / examples |
|---|---|---|---|
| `events[].competitions[].competitors[].linescores[].winner` | boolean | 100% | values: true (664), false (664) |
| `events[].competitions[].competitors[].ranks[].headline` | string | 100% | values: "2025 AVCA Division I Women's Top 25 Poll: Week 16" (21), "2026 AVCA Division I Men's Top 15 Coaches' Poll: Week 18" (20), "2026 AVCA Division I Men's Top 15 Coaches' Poll: Week 14" (12), "2026 AVCA Division I Men's Top 15 Coaches' Poll: Week 5" (11), "2026 AVCA Division I Men's Top 15 Coaches' Poll: Week 10" (9), "2026 AVCA Division I Men's Top 15 Coaches' Poll: Week 1" (3), "2025 AVCA Division I Women's Top 25 Poll: Week 3" (3), "2026 AVCA Division I Men's Top 15 Coaches' Poll: Week 9" (2), "2025 AVCA Division I Women's Top 25 Poll: Week 7" (2) |
| `events[].competitions[].competitors[].ranks[].name` | string | 100% | values: "AVCA Division I Men's Top 15 Coaches' Poll" (57), "AVCA Division I Women's Top 25 Poll" (26) |
| `events[].competitions[].competitors[].ranks[].rank.current` | number | 100% | e.g. 2, 7, 19, 12 |
| `events[].competitions[].competitors[].ranks[].rank.previous` | number | 100% | e.g. 9, 7, 16, 11 |
| `events[].competitions[].competitors[].ranks[].rank.record.summary` | string | 100% | e.g. "21-9", "22-8", "0-0", "26-5" |
| `events[].competitions[].competitors[].ranks[].shortHeadline` | string | 100% | values: "2025 AVCA Poll: Week 16" (21), "2026 AVCA Poll: Week 18" (20), "2026 AVCA Poll: Week 14" (12), "2026 AVCA Poll: Week 5" (11), "2026 AVCA Poll: Week 10" (9), "2026 AVCA Poll: Week 1" (3), "2025 AVCA Poll: Week 3" (3), "2026 AVCA Poll: Week 9" (2), "2025 AVCA Poll: Week 7" (2) |
| `events[].competitions[].competitors[].ranks[].shortName` | string | 100% | values: "AVCA Poll" (83) |
| `events[].competitions[].competitors[].ranks[].type` | string | 100% | values: "ap" (83) |
| `events[].competitions[].competitors[].curatedRank.current` | number | 100% | e.g. 99, 2, 1, 3 |

### summary

| field | type | presence | values / examples |
|---|---|---|---|
| `header.competitions[].competitors[].rank` | number | 50% | values: 2 (4), 24 (2), 13 (2), 1 (2), 8 (2), 10 (1), 20 (1), 18 (1), 6 (1), 12 (1), 21 (1) |
| `header.week` | number | 100% | values: 18 (9), 1 (8), 17 (3), 4 (2), 27 (2), 16 (2), 2 (1), 15 (1) |
| `news.articles[].categories[].event.description` | string | 100% | e.g. "India v Australia", "Colombia @ Switzerland", "Seattle Storm @ Los Angeles Sparks", "Connecticut Sun @ Minnesota Lynx" |
| `news.articles[].categories[].event.id` | number | 100% | e.g. 1384439, 760508, 401857045, 401857044 |
| `news.articles[].categories[].event.league` | string | 100% | values: "wnba" (36), "world cup" (25), "nll" (20), "mens-college-volleyball" (20), "pll" (16), "fifa.world" (12), "womens-college-volleyball" (4), "mlb" (2) |
| `news.articles[].categories[].event.sport` | string | 100% | values: "basketball" (36), "lacrosse" (36), "cricket" (25), "volleyball" (24), "soccer" (12), "baseball" (2) |
| `boxscore.players[].team.alternateColor` | string | 83% | e.g. "000000", "ffffff", "da291c", "a8adb4" |
| `news.articles[].categories[].eventId` | number | 4% | e.g. 1384439, 760508, 401857045, 401857044 |

## Go deeper

- Full field tables: [scoreboard](../scoreboard.md) · [summary](../summary.md) · [standings](../standings.md) · [teams](../teams.md) · [team-roster](../team-roster.md) · [rankings](../rankings.md)
- Canonical shape, ESPN→canonical mappings, per-league period/OT matrix: `schema/SCHEMA.md`, `schema/canonical.ts`
- Cross-sport support matrix: [index.md](../index.md)
