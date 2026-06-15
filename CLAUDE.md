# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A fast, calm, glanceable multi-sport scores app (an Apple Sports clone). Three components, one shared contract:

- **`schema/`** — the **locked data model**. The cross-sport canonical contract, a data-driven league registry, and the verification toolkit. This is the source of truth; the worker and app are downstream of it.
- **`worker/`** — a Cloudflare Worker that wraps ESPN's unofficial API, normalizes every sport into the canonical shape, and coalesces all clients into one upstream fetch per league per TTL.
- **`app/`** — a Flutter client that consumes the canonical contract. Three tabs (Scores / Leagues / Settings), dark by default, deliberately feature-minimal.

The product thesis is **restraint** (check a score in <2s, then leave). When adding anything, apply the test in `SPEC.md` §1; default to cutting.

There is **no git repo** here and **no monorepo tool** — each component is built/tested independently from its own directory.

## Commands

**Worker** (`cd worker`):
```bash
npm install            # pulls wrangler (the only dependency)
npm test               # runs normalize + summary + overview + team suites in order
                       #   → LIVE smoke test: fetches real ESPN, asserts canonical
                       #     invariants. Needs network. No wrangler/build needed
                       #     (the normalizers are pure). Run a single suite directly:
                       #     node test/normalize.test.mjs   (or summary/overview/team)
npm run dev            # wrangler dev → http://localhost:8787
npm run deploy         # wrangler deploy → <name>.workers.dev
```

**App** (`cd app`):
```bash
flutter pub get
flutter analyze        # must stay clean
flutter test           # model-parsing + widget tests: detail page, leagues page,
                       # scores smoke, team card (no network; uses test/fixtures/)
flutter run            # then set the worker URL in the Settings tab (see below)
```

**Schema tooling** (run from repo root, pure Node, no install):
```bash
node schema/tools/verify.mjs --all      # drift/gap detector vs live ESPN. Exit 1 on CRITICAL → wire to CI/cron.
node schema/tools/verify.mjs --priority v1   # default scope: just the v1 leagues
node schema/tools/probe.mjs soccer/eng.1     # fingerprint one live endpoint
```
To onboard a new/changed/novel league, use the `onboard-league` workflow (`.claude/workflows/onboard-league.js`) — it probes, classifies, adversarially verifies, and emits a paste-ready registry entry. See `schema/tools/README.md`.

## The big-picture architecture (read these together)

### 1. Three-layer inheritance — adding a league is data, never code
`schema/league-profiles.json` has three tiers resolved by an `extends` chain (nearest value wins, scalars replace, objects shallow-merge):
- **families** (`basketball`, `soccer`, …) → shared defaults
- **profiles** (`soccer.knockout`, `golf.strokeplay`, …) → intermediate variants
- **leagues** (`basketball/nba` → `extends: basketball`) → only the per-league deltas + the verified ESPN id

`schema/tools/resolve.mjs` is the **single resolver** that walks this chain. It is imported by **both** the worker (`normalize.js`, `summary.js`, `catalog.js`) **and** the CLI tools — by design, so the "resolve a league's config" rule never forks. It is pure (no node builtins) specifically so it bundles into the Worker. **Do not duplicate this logic; never special-case by sport name in consuming code.**

To add/modify a league: edit `league-profiles.json` only. The worker's catalog endpoint, normalizer behavior, and the app's picker all flow from it automatically.

### 2. Discriminator-driven rendering — one renderer, not per-sport branches
Every competition carries three discriminators: **`layout`** (`headToHead` | `field`), **`scoreKind`** (`numeric` | `toPar` | `cricket` | `none`), **`competitorKind`** (`team` | `athlete` | `pair`). Both the worker normalizer and the Flutter UI switch on these flags to decide how to read the otherwise-optional fields — never on sport name. `schema/canonical.ts` is the authoritative wire contract (with inline `// VERIFIED:` / `// QUIRK:` notes); `app/lib/src/models.dart` is a hand-written tolerant mirror of it. Keep all three in sync when the contract changes.

### 3. The worker is a normalization shield + quota coalescer
`worker/src/`:
- `index.js` — the only Worker-runtime code: router + CORS + **Cache API stale-while-revalidate**.
- `espn.js` — the **only** place that talks to ESPN. Swap providers here without touching anything else.
- `normalize.js` / `summary.js` / `standings.js` / `catalog.js` / `overview.js` / `team.js` — **pure** functions (no I/O) so they run identically in Node tests and the Worker.

The route surface (all under `/v1`, all coalesced behind the Cache API): `health`, `catalog` (1h TTL), `overview` (Leagues-list season pulse — fans out one cheap scoreboard fetch per league, capped at `OVERVIEW_FETCH_CAP=48` to stay under Cloudflare's 50-subrequest limit, 5m TTL but **1m when any league is live or has a game today**), `scores/{sport}/{league}` (15s live / 5m idle / **30s near a scheduled kickoff**), `summary/{sport}/{league}/{eventId}` (rich detail, 20s live / 5m idle / 30s near kickoff), `standings/{sport}/{league}` (1h), `teams/{sport}/{league}` (favorites picker, 1-day TTL), `team/{sport}/{league}/{teamId}` (one favorite's live/last/next card, 15s/5m).

Why it survives the free tier (see `SPEC.md` §11): use **Cache API, not KV** (KV's 1k-writes/day cap dies at a 15s refresh; Cache API has no write cap). Serve stale instantly, refresh once in `ctx.waitUntil()` — all users of a league share that single upstream fetch. TTL follows the data (the single source of policy is `ttl.js`): **15s when `anyLive`, 5m when idle** — *but* the idle→live flip would otherwise be hidden for the whole 5m idle window (the tight live TTL can't engage until we've already SEEN a live game), so when a `scheduled` game is within one idle window of kickoff — or just started and ESPN still says `pre` — the idle TTL drops to **30s** (`nextStartMs`, surfaced on the scores/summary payloads, drives this). Debug via the `x-cache: HIT|STALE|MISS|REVALIDATE` response header.

### 4. ESPN data lives in three tiers — don't assume the scoreboard has it
- **scoreboard** (cheap, polled every cycle) → scores, status, line scores, and a lot of context the normalizer surfaces optionally (situation, leaders, probables, hits/errors, form, stats).
- **summary** (rich, one extra fetch when a detail is opened) → box scores, scoring feed, lineups, **soccer penalty shootouts, MMA method of victory**.
- **core API** (`apis/v2/...`) → standings, golf strokes/playoff flag. **Trap:** standings is `apis/v2/.../standings`, NOT `apis/site/v2/...` (the site path returns a `{fullViewLink}` stub).

`DISPLAY-SPEC.md` governs the game-detail screen and tags every section `[cheap]` (scoreboard) vs `[rich]` (summary). **Note:** per-quarter/period line scores for NBA/NFL/NHL **are on the cheap scoreboard** (`competitor.linescores`, verified live) — the app renders them via `LineScoreTable` from `comp.periodScores` so the grid survives a `/summary` failure, and the rich summary `PeriodLinesGrid` stands down when the cheap grid rendered (see `game_detail_page._addScoreGrid`). The summary tier still adds the SO column + per-player box scores.

### 5. Flutter client (`app/lib/src/`)
State is **Riverpod without codegen** (`providers.dart`: settings, followed leagues, favorite teams, the parallel home `feedProvider`, the parallel `favoritesFeedProvider` (each fav's live/last/next card), the `teamsProvider` favorites picker, catalog, the Leagues-list `overviewProvider` season-pulse, standings, lazy summary). Networking is plain `http` in `api.dart` (the only place the app does I/O); parsing stays on the main isolate on purpose (payloads are small, the worker did the heavy lifting). `shared_preferences` holds followed leagues, favorite teams (one JSON blob per slot), + settings. Defaults (seed color, default worker URL, first-run followed leagues, poll cadences, `upcomingDays`) live in `config.dart`'s `AppConfig`. The worker base URL is **user-set in Settings** (not hardcoded; emulator → `http://10.0.2.2:8787`). Refresh is lifecycle-aware: poll 15s only when a followed game is live and the app is foregrounded, 60s idle, stop in background.

> ⚠️ **SPEC.md §10 describes the *planned* client stack (dio, freezed, go_router, AsyncNotifier) — the *actual* app uses none of those.** It's `http` + hand-written tolerant `fromJson` + `FutureProvider`/`Notifier` + an `IndexedStack` shell. Trust the code over SPEC §10.

## Conventions & gotchas

- **Status → phase: branch on `status.type.name`, never on `state` alone** (a postponed game can read `state: 'post'`). One `final` phase comes from many ESPN names (`STATUS_FINAL`, `STATUS_FULL_TIME`, `STATUS_FINAL_PEN`, …). Unknown names pass through as `unknown` — never crash.
- **Scores are STRINGS** in ESPN (`"103"`); `aggregateScore` stays a string in canonical too. `periodScores[].value` is **cumulative** for rugby (period 2 == final) — never sum periods.
- **"Overtime" only means extra play for timed/inning units** — not sets (best-of-5 ≠ OT), MMA rounds, laps, or golf rounds. See `OT_UNITS` in `normalize.js`.
- **JSON import quirk:** the Worker bundle imports `../../schema/league-profiles.json` *without* an import attribute (esbuild/wrangler handles it); the **Node test harness needs `with { type: 'json' }`**. Don't "fix" one to match the other.
- ESPN is **undocumented and unofficial** — endpoints can change without notice. `football-data.org` (free key) is the "go legit" escape hatch; the canonical layer exists so swapping providers is cheap. Run `verify.mjs` on a schedule to catch drift before users do.
- `league-profiles.json` marks `"verifiedIds": false` / `"verifiedIds": true` per league — honesty about what's confirmed against live data. See `schema/SCHEMA.md` §9 for outstanding live-shape re-checks.

## Where to read more (don't duplicate these — they're authoritative)
- `SPEC.md` — product vision, locked decisions, scope by version, build order.
- `schema/SCHEMA.md` — the canonical model, ESPN→canonical mappings, the per-league period/OT matrix, worked JSON examples.
- `schema/canonical.ts` — the wire types with inline verification/quirk notes.
- `DISPLAY-SPEC.md` — the game-detail screen spec, cheap-vs-rich per sport.
- `worker/README.md`, `app/README.md`, `schema/tools/README.md` — per-component detail.
