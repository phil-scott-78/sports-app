# ESPN API — racing

> Per-sport slice of the [observed data guide](../index.md): what ESPN actually serves for **racing**, and which endpoint answers each need. Built from 102 real racing responses — OBSERVED live, not documented. Regenerate: `node schema/tools/rollup.mjs`.

## Leagues — 5 in the registry

Competition **shape** drives rendering (see the discriminators in `schema/canonical.ts`): `layout · scoreKind · competitorKind`.

| shape (layout · scoreKind · competitorKind) | leagues | examples |
|---|---|---|
| `field · none · athlete` | 5 | `f1`, `nascar-premier`, `irl`, `nascar-secondary` |

**Crawled for this guide** (2): `racing/f1`, `racing/nascar-premier`. The evidence below is from these leagues; other racing leagues in the registry inherit the same shape.

## Which endpoint to use

URL templates use `racing/nascar-premier` as a representative league. Swap in any league key from the table above.

| need | endpoint | status | URL template | fields |
|---|---|---|---|---|
| Scores & live state | `scoreboard` | ✅ 28/28 | `https://site.api.espn.com/apis/site/v2/sports/racing/nascar-premier/scoreboard` | [guide](../scoreboard.md) |
| Rich game detail | `summary` | ❌ not served | `https://site.api.espn.com/apis/site/v2/sports/racing/nascar-premier/summary?event={eventId}` | [guide](../summary.md) |
| League table | `standings` | ✅ 4/4 | `https://site.api.espn.com/apis/v2/sports/racing/nascar-premier/standings` | [guide](../standings.md) |
| Team directory | `teams` | ✅ 2/2 | `https://site.api.espn.com/apis/site/v2/sports/racing/nascar-premier/teams` | [guide](../teams.md) |
| Roster | `team-roster` | ✅ 2/2 | `https://site.api.espn.com/apis/site/v2/sports/racing/nascar-premier/teams/{teamId}/roster` | [guide](../team-roster.md) |
| Schedule | `team-schedule` | ✅ 1/1 | `https://site.api.espn.com/apis/site/v2/sports/racing/nascar-premier/teams/{teamId}/schedule` | [guide](../team-schedule.md) |
| Team season stats | `team-stats` | ❌ not served | `https://site.api.espn.com/apis/site/v2/sports/racing/nascar-premier/teams/{teamId}/statistics` | [guide](../team-stats.md) |
| News | `news` | ✅ 2/2 | `https://site.api.espn.com/apis/site/v2/sports/racing/nascar-premier/news?limit=5` | [guide](../news.md) |
| Injuries | `injuries` | ✅ 1/1 | `https://site.api.espn.com/apis/site/v2/sports/racing/nascar-premier/teams/{teamId}/injuries` | [guide](../injuries.md) |

- **scoreboard** — The cheap poll — scores, status, line scores, and (situationally) situation, leaders, records, odds. The primary call. College needs `?groups=<id>&limit=400`; `?dates=YYYYMMDD-YYYYMMDD` for a range (cricket: single day only).
- **summary** — One extra fetch when a game is opened — box scores, scoring plays, rosters, penalty shootouts, method of victory. A 404 for the whole sport means this tier does not exist (build detail from the core graph instead). _(every attempt 404/400 — this tier does not exist for the sport)_
- **standings** — ⚠ `apis/v2`, NOT `apis/site/v2` (the site path returns a `{fullViewLink}` stub). Omit `?season=` — ESPN defaults to the current season.
- **teams** — Team ids, names, abbreviations, logos, colors. The id feeds the roster/schedule/stats/injuries calls.
- **team-roster** — Per-team roster with positions and headshots.
- **team-schedule** — Per-team schedule, past results + upcoming fixtures.
- **team-stats** — Per-team season statistics. _(every attempt 404/400 — this tier does not exist for the sport)_
- **news** — Latest articles for the league.
- **injuries** — Per-team injury report.

## Core API — `sports.core.api.espn.com`

34 of the core resource shapes were reachable for racing by following `$ref` links from the league root and its events (full matrix: [index.md](../index.md#core-api-resource-graph)). High-value shapes:

| resource | reachable | what it adds |
|---|---|---|
| `core-competition-statistics` | ✅ | Team box statistics for the game. |
| `core-competitor-statistics` | ✅ | Competitor's game statistics. |
| `core-athlete` | ✅ | Athlete bio / profile. |

## What's sport-specific in the data

Value-bearing fields observed for racing that are **not** near-universal — the sport's fingerprint. **presence** = % of this sport's crawled responses (or parent objects) that carry the field (racing-specific). Field paths, types, and presence are racing-only; the **value/example samples are pooled** across the handful of sports that share a field (a nested `period` may show golf's "18" next to a fight's "1–3"), so read them as shape hints. The full per-sport field tables live in the per-endpoint guides linked above.

### scoreboard

| field | type | presence | values / examples |
|---|---|---|---|
| `events[].circuit.address.city` | string | 100% | values: "Silverstone" (3), "Monte carlo" (1), "Florida" (1), "Melbourne" (1), "Abu dhabi" (1), "Sao paulo" (1), "Singapore" (1), "Monza" (1), "Budapest" (1) |
| `events[].circuit.address.country` | string | 100% | values: "Britain" (3), "Monaco" (1), "USA" (1), "Australia" (1), "United Arab Emirates" (1), "Brazil" (1), "Singapore" (1), "Italy" (1), "Hungary" (1) |
| `events[].circuit.fullName` | string | 100% | values: "Silverstone Circuit" (3), "Circuit de Monaco" (1), "Miami International Autodrome" (1), "Melbourne Grand Prix Circuit" (1), "Yas Marina Circuit" (1), "Autodromo Jose Carlos Pace" (1), "Marina Bay Street Circuit" (1), "Autodromo Nazionale Monza" (1), "Hungaroring" (1) |
| `events[].circuit.id` | str-numeric | 100% | values: "611" (3), "606" (1), "4243" (1), "601" (1), "744" (1), "617" (1), "740" (1), "615" (1), "613" (1) |

## Go deeper

- Full field tables: [scoreboard](../scoreboard.md) · [summary](../summary.md) · [standings](../standings.md) · [teams](../teams.md) · [team-roster](../team-roster.md) · [rankings](../rankings.md)
- Canonical shape, ESPN→canonical mappings, per-league period/OT matrix: `schema/SCHEMA.md`, `schema/canonical.ts`
- Cross-sport support matrix: [index.md](../index.md)
