# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A fast, calm, glanceable multi-sport scores app (an Apple Sports clone). Two
components, one shared contract:

- **`schema/`** — the **locked data model**. The cross-sport canonical contract, a data-driven league registry, and the verification toolkit. This is the source of truth; the app is downstream of it.
- **`app/`** — a Flutter client that talks to **ESPN's unofficial API directly** and normalizes every sport into the canonical shape **on-device** (`app/lib/src/data/`). A **broadcast-dark**, three-tab shell (Scores / Standings / Following), deliberately feature-minimal.

> **The Cloudflare Worker was removed** (see `drop-the-worker.md`). The app used
> to read a normalized feed from a worker; it now fetches ESPN and runs the SAME
> canonical normalizers, ported to Dart under `app/lib/src/data/`. **`worker/` is
> no longer deployed** — it survives only as OFFLINE TOOLING: the raw-fixture
> capture, the offline mock backend, and the JS normalizers that generate the
> Dart port's golden parity fixtures. There is nothing to deploy but the app.

The product thesis is **restraint** (check a score in <2s, then leave). When adding anything, default to cutting.

There is **no monorepo tool** — each component is built/tested independently from its own directory.

## Commands

**Offline tooling** (`cd worker` — NO deploy; pure Node, no dependencies):
```bash
npm test               # the JS normalizer suites (mock synth + units, then LIVE
                       #   smoke suites normalize/summary/overview/team that fetch
                       #   real ESPN). These test the JS normalizers that serve as
                       #   the golden-parity ORACLE for the Dart port. Run one:
                       #   node test/units.test.mjs (or mock/normalize/summary/…)
npm run mock           # OFFLINE mock backend (scripts/mock-espn-server.mjs): serves
                       #   RAW ESPN shapes on ESPN paths, replaying captured fixtures
                       #   through synth.mjs — the app normalizes them on-device.
                       #   Point Settings → "API base override" at it (10.0.2.2:8787
                       #   on Android emu) to walk every UI state offline.
npm run mock:megaweek  # same backend + the `megaweek` scenario (mock/scenarios.mjs):
                       #   every league lit up LIVE now, championships staged across
                       #   the week — the "biggest week in sports history" demo build.
npm run capture        # (re)capture mock/fixtures/ from live ESPN (network; rare)
npm run capture-extra  # (re)capture the team-schedule/roster/MMA-core fixtures the
                       #   Dart team/teamdetail/MMA goldens need (network; rare)
npm run goldens        # regenerate app/test/fixtures/golden/ from the JS normalizers
                       #   (the parity oracle the Dart port is tested against)
```

> **Offline mock** (`worker/mock/`, `worker/scripts/`): the way to walk every UI
> permutation without the real-world calendar. `capture-fixtures.mjs` snapshots
> real ESPN per league (committed to `mock/fixtures/`); `synth.mjs` (pure, tested)
> rebases those dates to "now" and converts/fabricates phases so each league always
> has final+live+scheduled (deterministic by event id → no flicker on poll);
> `mock-espn-server.mjs` serves the RAW ESPN shapes on ESPN paths. The app's
> `EspnClient` reroutes every ESPN request's origin to this base — no app changes.

**App** (`cd app`):
```bash
flutter pub get
dart run tool/sync_registry.dart  # copy schema/league-profiles.json → assets/ (bundled).
                       #   Run after editing the registry; a guard test fails on drift.
flutter analyze        # must stay clean
flutter test           # model-parsing + widget tests PLUS the port parity suites
                       #   (port_*_test.dart): the Dart normalizers (lib/src/data/)
                       #   must match the JS oracle byte-for-byte on every committed
                       #   golden (test/fixtures/golden/). No network; deterministic.
flutter run            # talks to ESPN directly out of the box (no setup). The
                       #   Settings gear only sets an optional API base override (mock).
```

**Schema tooling** (run from repo root, pure Node, no install):
```bash
node schema/tools/verify.mjs --all      # drift/gap detector vs live ESPN. Exit 1 on CRITICAL → wire to CI/cron.
node schema/tools/verify.mjs --priority v1   # default scope: just the v1 leagues
node schema/tools/probe.mjs soccer/eng.1     # fingerprint one live endpoint
node schema/tools/crawl.mjs                  # crawl real ESPN responses (past year, every sport)
                                             #   → schema/crawl-data/ (raw corpus, gitignored)
node schema/tools/rollup.mjs                 # corpus → schema/espn-guide/ — the OBSERVED field
                                             #   guide (paths/types/presence/enums per endpoint,
                                             #   per-sport support matrix; LLM-consumable, committed).
                                             #   Also emits schema/espn-guide/by-sport/<sport>.md —
                                             #   the reader's entry point: per sport, which endpoint
                                             #   to hit + the sport's distinctive fields.
```
**Which ESPN endpoint serves what, per sport,** is answered by `schema/espn-guide/` (generated by `rollup.mjs`, above). Start at `by-sport/<sport>.md`; drop into `<endpoint>.md` for the full field table; `index.md` is the cross-sport support matrix. The `espn-api` Claude skill (`.claude/skills/espn-api/`) routes ESPN-data questions there. **Read the guide before guessing at ESPN's undocumented endpoints/fields.**

To onboard a new/changed/novel league, use the `onboard-league` workflow (`.claude/workflows/onboard-league.js`) — it probes, classifies, adversarially verifies, and emits a paste-ready registry entry. See `schema/tools/README.md`.

## The big-picture architecture (read these together)

### 1. Three-layer inheritance — adding a league is data, never code
`schema/league-profiles.json` has three tiers resolved by an `extends` chain (nearest value wins, scalars replace, objects shallow-merge):
- **families** (`basketball`, `soccer`, …) → shared defaults
- **profiles** (`soccer.knockout`, `golf.strokeplay`, …) → intermediate variants
- **leagues** (`basketball/nba` → `extends: basketball`) → only the per-league deltas + the verified ESPN id

`schema/tools/resolve.mjs` is the **single resolver** that walks this chain (Node/JS). The app carries a **faithful Dart port**, `app/lib/src/data/profiles.dart` (`resolve` + `leagueKeys` + `buildCatalog`), verified byte-for-byte against the JS via `test/port_phase1_foundation_test.dart`. Both the JS resolver (CLI tools + the golden oracle) and the Dart port must stay in lock-step. **Do not duplicate this logic elsewhere; never special-case by sport name in consuming code.**

To add/modify a league: edit `league-profiles.json` only, then `dart run tool/sync_registry.dart` (re-bundles it as an app asset). The catalog, normalizer behavior, and the app's picker all flow from it automatically.

### 2. Discriminator-driven rendering — one renderer, not per-sport branches
Every competition carries three discriminators: **`layout`** (`headToHead` | `field`), **`scoreKind`** (`numeric` | `toPar` | `cricket` | `none`), **`competitorKind`** (`team` | `athlete` | `pair`). Both the Dart normalizer (`app/lib/src/data/`) and the Flutter UI switch on these flags to decide how to read the otherwise-optional fields — never on sport name. Glance widgets read further cheap-scoreboard signals off the same model (playoff series pips from `meta.series`, the cheap goal/card timeline from `competition.events`) without per-sport branching; soccer shows the cheap timeline instantly, then upgrades to the rich `/summary` feed for substitutions. `schema/canonical.ts` is the authoritative canonical contract (with inline `// VERIFIED:` / `// QUIRK:` notes); the Dart normalizers (`app/lib/src/data/`) emit exactly that shape and `app/lib/src/models.dart` is a hand-written tolerant parser of it. Keep all three in sync when the contract changes.

### 3. The app's data layer is the normalization shield (on-device, was the worker)
`app/lib/src/data/` — the ported normalization layer (see `drop-the-worker.md`):
- `espn_client.dart` — the **only** place that talks to ESPN (the endpoint URLs/hosts live here). A `baseOverride` reroutes every request's origin to the offline mock. Holds a small per-URL response cache + **in-flight coalescing** (overlapping providers share one fetch). Swap providers here without touching anything else.
- `normalize.dart` / `summary.dart` / `standings.dart` / `rankings.dart` / `scorecard.dart` / `team.dart` / `teamdetail.dart` / `overview.dart` / `calendar.dart` — **pure** map→map functions (no I/O). `profiles.dart` carries the registry loader + `resolve`/`leagueKeys`/`buildCatalog` (the catalog is computed on-device, no fetch). Faithful Dart ports of the JS normalizers, verified byte-for-byte against them via the golden suites (`app/test/port_*_test.dart`, oracle = `worker/src/*.js`). `util.dart` carries the JS-parity helpers (truthiness, `||` short-circuit, `parseInt`, the two `pick` variants).
- `api.dart` — composes `espn_client` + the normalizers behind the SAME public method surface the app always used (`scores`/`summary`/`standings`/`catalog`/`teamCard`/`overview`/…), so providers/UI didn't move. Golf `meta.golf` (core tournament fetch, best-effort) and the MMA `bouts` build (ESPN's site summary 404s for MMA → built from core per-bout status/linescores) live here as per-endpoint enrichments. `overview` fans out one cheap scoreboard per league with a concurrency cap of 8, capped at 48 leagues.

The ESPN endpoints `espn_client` hits: scoreboard (`?dates=` accepts a `YYYYMMDD-YYYYMMDD` range), summary, `apis/v2/.../standings` (**omit `season` unless asked** — ESPN's default IS the current season where `getFullYear()` is wrong mid-year, e.g. NHL is season 2027 in July 2026), teams, team schedule/roster/statistics, rankings (college polls / ATP-WTA / UFC divisions per `rankingsFeed`), the core event (golf tournament + MMA bouts), and the web-API golf playersummary.

Freshness policy now lives in the **client poll cadence** (`config.dart`: 15s live / 30s near kickoff / 60s idle, foreground-only; `nextStartMs` on the scores/summary payloads drives the near-kickoff tier) rather than a server TTL — per-device, ESPN's own CDN is the shared cache. There's no cross-client coalescer to worry about: one user polling a handful of leagues is noise to ESPN.

### 4. ESPN data lives in three tiers — don't assume the scoreboard has it
- **scoreboard** (cheap, polled every cycle) → scores, status, line scores, and a lot of context the normalizer surfaces optionally (situation, leaders, probables, hits/errors, form, stats).
- **summary** (rich, one extra fetch when a detail is opened) → box scores, scoring feed, lineups, **soccer penalty shootouts, MMA method of victory**. **Soccer trap:** the match narrative is the summary's `commentary[]` (curated fouls/shots/corners/VAR → canonical `plays`; per-player numbers ride `rosters[].roster[].stats` → `boxGroups`) — `keyEvents[]` is only goals/cards/subs (EMPTY in a 0-0 game), and the core `/plays` resource is touch-by-touch noise (700+ items by halftime, paginated); don't reach for it. Core `situation`/`probabilities`/`statistics` are unsupported for soccer, and the `cdn.espn.com` scoreboard is byte-identical to the site one (verified live 2026-07).
- **core API** (`apis/v2/...`) → standings, golf strokes/playoff flag. **Trap:** standings is `apis/v2/.../standings`, NOT `apis/site/v2/...` (the site path returns a `{fullViewLink}` stub).

The game-detail screen mixes `[cheap]` (scoreboard) and `[rich]` (summary) sections. **Note:** per-quarter/period line scores for NBA/NFL/NHL **are on the cheap scoreboard** (`competitor.linescores`, verified live) — the app renders them via `_LineScoreCard` from the cheap `comp.periodScores` so the grid survives a `/summary` failure, then upgrades to the rich `summary.periodLines` when it arrives (baseball uses `_InningLineScore`). The cheap goal/card timeline (`competition.events`) likewise renders on detail for rugby, while soccer upgrades it to the rich `/summary` feed for substitutions. The summary tier still adds the SO column + per-player box scores.

### 5. Flutter client (`app/lib/src/`)
The **broadcast-dark** client. **Before building or restyling ANY UI — a new screen, a widget, or any color/spacing/type/copy choice — read `app/DESIGN.md` first and assemble from its system; do not design from scratch.** DESIGN.md is the authoritative design spec (tokens, the card grammar, the per-sport delighter catalog, the event-feed archetypes, and the recipe for screens that don't exist yet); `theme.dart` (class `T`) is its code mirror and `app/README.md` is only the short version. A 3-tab `IndexedStack` shell (`ui/app.dart`) — **Scores / Standings / Following** — with Settings (the optional API base override) and the Explore browser reached as pushed pages from the Scores header, and any league opened via `openLeaguePage(...)`.

State is **Riverpod without codegen** (`providers.dart`): `settingsProvider`, `followedProvider`, `favoriteTeamsProvider`, the home `feedProvider` (followed leagues' slates), `favoritesFeedProvider` (each fav's live/last/next card), `teamsProvider` (favorites picker), `catalogProvider`, `exploreOverviewProvider` (Explore's live/today pulse), `leagueScoresProvider` (one league's slate), `standingsProvider`, and the lazy `summaryProvider` / `rankingsProvider` / `scorecardProvider`. All go through `api.dart` (the app's data-layer boundary — see §3); the fetch + normalize both stay on the main isolate (payloads are small, the normalizers are pure map work). `shared_preferences` holds followed leagues, favorite teams (one JSON blob per slot), + settings.

`config.dart`'s `AppConfig` holds the defaults: the API base override (**empty = ESPN direct**; `--dart-define=WORKER_URL=` still names the override for dev against the mock), first-run followed leagues, and poll cadences (**15s live / 30s near kickoff / 60s idle**, foreground-only). The theme is fixed design tokens (`theme.dart`, class `T`) — no Material seed color. The base override is **user-set in Settings** (emulator mock → `http://10.0.2.2:8787`); a saved value always wins, and empty means straight to ESPN. `main()` awaits `Registry.load()` (bundled `league-profiles.json`) before `runApp` so the normalizers can resolve profiles synchronously.

The game-detail signature is a **data-driven situation card** (`ui/situations.dart`) that dispatches on *data presence*, never sport name: `situation.hasBaseball` → diamond, `hasGridiron` → drive field, `competition.events` → match timeline, cricket target → chase, `layout == 'field'` → leaderboard; nothing applicable → no card.

> **Client stack (actual):** `http` + hand-written tolerant `fromJson` + `FutureProvider`/`StateProvider`/`Notifier` + an `IndexedStack` shell — *not* dio/freezed/go_router/AsyncNotifier.

## Conventions & gotchas

- **Status → phase: branch on `status.type.name`, never on `state` alone** (a postponed game can read `state: 'post'`). One `final` phase comes from many ESPN names (`STATUS_FINAL`, `STATUS_FULL_TIME`, `STATUS_FINAL_PEN`, …). Unknown names pass through as `unknown` — never crash.
- **Scores are STRINGS** in ESPN (`"103"`); `aggregateScore` stays a string in canonical too. `periodScores[].value` is **cumulative** for rugby (period 2 == final) — never sum periods.
- **"Overtime" only means extra play for timed/inning units** — not sets (best-of-5 ≠ OT), MMA rounds, laps, or golf rounds. See `OT_UNITS`/`_otUnits` in `app/lib/src/data/normalize.dart` (and its JS oracle `worker/src/normalize.js`).
- **The registry is bundled + resolved on-device:** the app loads `assets/league-profiles.json` (kept byte-identical to `schema/league-profiles.json` by `tool/sync_registry.dart`, guarded by `test/registry_sync_test.dart`). The Node oracle/tooling still imports the schema copy `with { type: 'json' }`. Edit the schema copy, then re-sync.
- ESPN is **undocumented and unofficial** — endpoints can change without notice. `football-data.org` (free key) is the "go legit" escape hatch; the canonical layer exists so swapping providers is cheap. Run `verify.mjs` on a schedule to catch drift before users do.
- `league-profiles.json` marks `"verifiedIds": false` / `"verifiedIds": true` per league — honesty about what's confirmed against live data. See `schema/SCHEMA.md` §9 for outstanding live-shape re-checks.

## Where to read more (don't duplicate these — they're authoritative)
- `schema/SCHEMA.md` — the canonical model, ESPN→canonical mappings, the per-league period/OT matrix, worked JSON examples.
- `schema/canonical.ts` — the canonical types with inline verification/quirk notes.
- `drop-the-worker.md` — the migration that removed the Cloudflare Worker (why + how).
- `app/README.md`, `schema/tools/README.md` — per-component detail; `worker/README.md` covers the surviving offline tooling (mock, fixtures, golden oracle).
- `app/DESIGN.md` — the **design spec**: color/type/spacing tokens, the card grammar, the per-sport delighter catalog, and the recipe for building screens that don't exist yet. **Read it before any UI/UX work** — building or restyling a screen, or touching color/type/spacing/copy (see §5).
