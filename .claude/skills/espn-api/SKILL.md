---
name: espn-api
description: >-
  Answer "what data does ESPN serve for <sport> and which endpoint do I call" for this repo. Use whenever the task
  touches ESPN's API surface — picking an endpoint (scoreboard / summary / standings / teams / roster / rankings /
  news / core graph), figuring out which fields exist for a sport, whether a tier exists at all (e.g. does MMA/golf
  have a summary?), the URL shape for a league, or normalizing a sport into the canonical model. Triggers: "which ESPN
  endpoint for X", "what does ESPN return for <sport/league>", "how do I get scores/standings/box scores/play-by-play/
  odds for <league>", "is there a summary/rankings feed for <sport>", onboarding or debugging a sport's data. Routes to
  the evidence-based guide under schema/espn-guide/ instead of guessing at undocumented endpoints.
---

# ESPN API guide

This repo fetches ESPN's **unofficial, undocumented** API directly and normalizes every sport on-device
(`app/lib/src/data/`). What ESPN actually serves — per sport, per endpoint, per field — has already been **crawled from
live responses and written up** under `schema/espn-guide/`. Read it; do **not** guess at endpoints or fields from memory.

## Where to look (in order)

1. **Building or answering for ONE sport** → read **`schema/espn-guide/by-sport/<sport>.md`** first. One page: the
   registry leagues + their competition shape, which site endpoints work (and which 404), the reachable core-graph
   resources, and the fields that make that sport distinctive. Sports:
   `australian-football, baseball, basketball, cricket, field-hockey, football, golf, hockey, lacrosse, mma, racing,
   rugby, rugby-league, soccer, tennis, volleyball, water-polo`.
2. **The full field list for one endpoint** (every path, type, presence %, enum values, `$ref` templates) →
   **`schema/espn-guide/<endpoint>.md`** (e.g. `scoreboard.md`, `summary.md`, `standings.md`, `teams.md`,
   `team-roster.md`, `rankings.md`, and the `core-*.md` resource shapes).
3. **"Does sport X have tier Y?" / the cross-sport support matrix / the core-graph breadth table** →
   **`schema/espn-guide/index.md`**. A `—` there means every attempt 404'd — the tier genuinely doesn't exist for
   that sport, which IS the answer.
4. **The canonical target shape + `// VERIFIED:` / `// QUIRK:` notes** → `schema/canonical.ts`; the ESPN→canonical
   mappings, per-league period/OT matrix, worked examples → `schema/SCHEMA.md`.
5. **How the app actually consumes it** (the ported normalizers, the only place that talks to ESPN) →
   `app/lib/src/data/` (`espn_client.dart` = endpoints/hosts; `normalize.dart` / `summary.dart` / … = pure map→map).

## The 30-second model

ESPN exposes data in **three tiers** — don't assume the cheap one has what you want:

- **scoreboard** (`site.api.espn.com/apis/site/v2/sports/<sport>/<league>/scoreboard`) — the cheap poll: scores,
  status, line scores, and situationally situation/leaders/records/odds. The app's primary call.
- **summary** (`…/<league>/summary?event=<id>`) — one extra fetch when a game is opened: box scores, scoring plays,
  rosters, penalty shootouts, method of victory. **A whole-sport 404 means the tier doesn't exist** (golf, mma,
  tennis, racing) — build detail from the core graph instead.
- **core** (`sports.core.api.espn.com/v2/sports/…`) — a HATEOAS graph discovered by following `$ref` links. Holds
  standings, odds, win probability, play-by-play, set/inning line scores — reachable even when the scoreboard omits
  them. The per-sport guide lists which core shapes resolve for that sport.

## Traps (all verified live — see CLAUDE.md §"Conventions & gotchas")

- **Standings is `apis/v2/...`, NOT `apis/site/v2/...`** (the site path returns a `{fullViewLink}` stub). Omit
  `?season=` — ESPN defaults to the current season (which is often next calendar year mid-season).
- **Scores are strings** (`"103"`), and `periodScores[].value` is **cumulative for rugby** (period 2 == final) —
  never sum periods.
- **Status → phase: branch on `status.type.name`, never `state` alone** (a postponed game can read `state:"post"`).
- **Soccer narrative is the summary's `commentary[]`**, not `keyEvents[]` (goals/cards/subs only — empty in a 0-0) and
  not the core `/plays` resource (700+ touch-by-touch items). The cheap goal/card timeline is the scoreboard's raw
  `competitions[].details[]` (normalized to canonical `competition.events`).
- **cricket scoreboard 404s on `?dates=` ranges** — single `YYYYMMDD` or no param only.
- **College** scoreboards need `?groups=<id>&limit=400` (basketball `groups=50`, FBS football `groups=80`).

## Keeping it honest

The guide is generated, not hand-maintained: `node schema/tools/crawl.mjs` (re-crawl live ESPN, gitignored corpus)
then `node schema/tools/rollup.mjs` (rebuild every `.md` + `by-sport/` + `fields.json`). Everything in it was OBSERVED
in real responses — if ESPN drifts, re-crawl and roll up rather than editing the `.md` by hand. To onboard a new or
novel league, use the `onboard-league` workflow.
