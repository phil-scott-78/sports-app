# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A fast, calm, glanceable multi-sport scores app (an Apple Sports clone). Three components, one shared contract:

- **`schema/`** — the **locked data model**. The cross-sport canonical contract, a data-driven league registry, and the verification toolkit. This is the source of truth; the worker and app are downstream of it.
- **`worker/`** — a Cloudflare Worker that wraps ESPN's unofficial API, normalizes every sport into the canonical shape, and coalesces all clients into one upstream fetch per league per TTL.
- **`app/`** — a Flutter client that consumes the canonical contract. A **broadcast-dark**, three-tab shell (Scores / Standings / Following), deliberately feature-minimal.

The product thesis is **restraint** (check a score in <2s, then leave). When adding anything, default to cutting.

There is **no monorepo tool** — each component is built/tested independently from its own directory.

## Commands

**Worker** (`cd worker`):
```bash
npm install            # pulls wrangler (the only dependency)
npm test               # offline suites (mock synth + ttl + units, no network) then
                       #   LIVE smoke suites (normalize/summary/overview/team) in order.
                       #   The live suites fetch real ESPN and assert canonical
                       #   invariants (need network). No wrangler/build needed
                       #   (normalizers are pure). Run one suite directly: node
                       #   test/mock.test.mjs (or ttl/units/normalize/summary/overview/team)
npm run dev            # wrangler dev → http://localhost:8787
npm run deploy         # wrangler deploy → <name>.workers.dev
npm run mock           # OFFLINE mock backend: same routes/contract, replays captured
                       #   ESPN fixtures through the REAL normalizers + synthesizes a
                       #   current final+live+scheduled slate for EVERY sport — point the
                       #   app's Settings worker URL at it (10.0.2.2:8787 on Android emu).
                       #   Test every UI state without live data. See worker/mock/README.md.
npm run capture        # (re)capture mock/fixtures/ from live ESPN (network; run rarely)
```

> **Offline mock** (`worker/mock/`, `worker/scripts/`): the way to walk every UI
> permutation without the real-world calendar. `capture-fixtures.mjs` snapshots
> real ESPN per league (committed to `mock/fixtures/`); `synth.mjs` (pure, tested)
> rebases those dates to "now" and converts/fabricates phases so each league always
> has final+live+scheduled (deterministic by event id → no flicker on poll);
> `mock-server.mjs` serves them through the SAME pure normalizers `src/index.js`
> uses. No app changes — it's just another worker URL.

**App** (`cd app`):
```bash
flutter pub get
flutter analyze        # must stay clean
flutter test           # model-parsing + widget tests: home feed, game detail
                       #   (score block / chips / situation card), golf detail →
                       #   scorecard, explore + league page, standings, and the
                       #   data-driven situation dispatch (no network; test/fixtures/)
flutter run            # then set the worker URL via the Settings gear on the Scores tab
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
Every competition carries three discriminators: **`layout`** (`headToHead` | `field`), **`scoreKind`** (`numeric` | `toPar` | `cricket` | `none`), **`competitorKind`** (`team` | `athlete` | `pair`). Both the worker normalizer and the Flutter UI switch on these flags to decide how to read the otherwise-optional fields — never on sport name. Glance widgets read further cheap-scoreboard signals off the same model (playoff series pips from `meta.series`, the cheap goal/card timeline from `competition.events`) without per-sport branching; soccer shows the cheap timeline instantly, then upgrades to the rich `/summary` feed for substitutions. `schema/canonical.ts` is the authoritative wire contract (with inline `// VERIFIED:` / `// QUIRK:` notes); `app/lib/src/models.dart` is a hand-written tolerant mirror of it. Keep all three in sync when the contract changes.

### 3. The worker is a normalization shield + quota coalescer
`worker/src/`:
- `index.js` — the only Worker-runtime code: router + CORS + **Cache API stale-while-revalidate**.
- `espn.js` — the **only** place that talks to ESPN. Swap providers here without touching anything else.
- `normalize.js` / `summary.js` / `standings.js` / `catalog.js` / `overview.js` / `team.js` — **pure** functions (no I/O) so they run identically in Node tests and the Worker.

The route surface (all under `/v1`, all coalesced behind the Cache API): `health`, `catalog` (1h TTL), `overview` (Explore-page season pulse — fans out one cheap scoreboard fetch per league, capped at `OVERVIEW_FETCH_CAP=48` to stay under Cloudflare's 50-subrequest limit, 5m TTL but **1m when any league is live or has a game today**), `scores/{sport}/{league}` (15s live / 5m idle / **30s near a scheduled kickoff**; `?date=` accepts a `YYYYMMDD-YYYYMMDD` range; golf events are enriched with `meta.golf` cut/major/rounds from the core tournament resource — 2 extra subrequests per golf event, best-effort), `summary/{sport}/{league}/{eventId}` (rich detail, 20s live / 5m idle / 30s near kickoff; **MMA is special**: ESPN's site summary 404s for every MMA event, so the worker builds `bouts` — structured method of victory + judge scorecards — from core per-bout status/linescores), `scorecard/{sport}/{league}/{eventId}/{playerId}` (golf hole-by-hole via the web-API playersummary, 60s), `rankings/{sport}/{league}` (college polls / ATP-WTA tours / UFC divisions per the registry `rankingsFeed` flag, 1h), `standings/{sport}/{league}` (1h; **omit `season` upstream unless the client passed one** — ESPN's default IS the current season where `getFullYear()` is wrong mid-year, e.g. NHL is season 2027 in July 2026; racing championships ride this same route with athlete-shaped entries), `teams/{sport}/{league}` (favorites picker, 1-day TTL), `team/{sport}/{league}/{teamId}` (one favorite's live/last/next card, 15s/5m).

Why it survives the free tier: use **Cache API, not KV** (KV's 1k-writes/day cap dies at a 15s refresh; Cache API has no write cap). Serve stale instantly, refresh once in `ctx.waitUntil()` — all users of a league share that single upstream fetch. TTL follows the data (the single source of policy is `ttl.js`): **15s when `anyLive`, 5m when idle** — *but* the idle→live flip would otherwise be hidden for the whole 5m idle window (the tight live TTL can't engage until we've already SEEN a live game), so when a `scheduled` game is within one idle window of kickoff — or just started and ESPN still says `pre` — the idle TTL drops to **30s** (`nextStartMs`, surfaced on the scores/summary payloads, drives this). Debug via the `x-cache: HIT|STALE|MISS|REVALIDATE` response header.

### 4. ESPN data lives in three tiers — don't assume the scoreboard has it
- **scoreboard** (cheap, polled every cycle) → scores, status, line scores, and a lot of context the normalizer surfaces optionally (situation, leaders, probables, hits/errors, form, stats).
- **summary** (rich, one extra fetch when a detail is opened) → box scores, scoring feed, lineups, **soccer penalty shootouts, MMA method of victory**. **Soccer trap:** the match narrative is the summary's `commentary[]` (curated fouls/shots/corners/VAR → canonical `plays`; per-player numbers ride `rosters[].roster[].stats` → `boxGroups`) — `keyEvents[]` is only goals/cards/subs (EMPTY in a 0-0 game), and the core `/plays` resource is touch-by-touch noise (700+ items by halftime, paginated); don't reach for it. Core `situation`/`probabilities`/`statistics` are unsupported for soccer, and the `cdn.espn.com` scoreboard is byte-identical to the site one (verified live 2026-07).
- **core API** (`apis/v2/...`) → standings, golf strokes/playoff flag. **Trap:** standings is `apis/v2/.../standings`, NOT `apis/site/v2/...` (the site path returns a `{fullViewLink}` stub).

The game-detail screen mixes `[cheap]` (scoreboard) and `[rich]` (summary) sections. **Note:** per-quarter/period line scores for NBA/NFL/NHL **are on the cheap scoreboard** (`competitor.linescores`, verified live) — the app renders them via `_LineScoreCard` from the cheap `comp.periodScores` so the grid survives a `/summary` failure, then upgrades to the rich `summary.periodLines` when it arrives (baseball uses `_InningLineScore`). The cheap goal/card timeline (`competition.events`) likewise renders on detail for rugby, while soccer upgrades it to the rich `/summary` feed for substitutions. The summary tier still adds the SO column + per-player box scores.

### 5. Flutter client (`app/lib/src/`)
The **broadcast-dark** client. **Before building or restyling ANY UI — a new screen, a widget, or any color/spacing/type/copy choice — read `app/DESIGN.md` first and assemble from its system; do not design from scratch.** DESIGN.md is the authoritative design spec (tokens, the card grammar, the per-sport delighter catalog, the event-feed archetypes, and the recipe for screens that don't exist yet); `theme.dart` (class `T`) is its code mirror and `app/README.md` is only the short version. A 3-tab `IndexedStack` shell (`ui/app.dart`) — **Scores / Standings / Following** — with Settings (worker URL) and the Explore browser reached as pushed pages from the Scores header, and any league opened via `openLeaguePage(...)`.

State is **Riverpod without codegen** (`providers.dart`): `settingsProvider`, `followedProvider`, `favoriteTeamsProvider`, the home `feedProvider` (followed leagues' slates), `favoritesFeedProvider` (each fav's live/last/next card), `teamsProvider` (favorites picker), `catalogProvider`, `exploreOverviewProvider` (Explore's live/today pulse), `leagueScoresProvider` (one league's slate), `standingsProvider`, and the lazy `summaryProvider` / `rankingsProvider` / `scorecardProvider`. Networking is plain `http` in `api.dart` (the only place the app does I/O); parsing stays on the main isolate (payloads are small — the worker did the heavy lifting). `shared_preferences` holds followed leagues, favorite teams (one JSON blob per slot), + settings.

`config.dart`'s `AppConfig` holds the defaults: default worker URL (the `philco.dev` custom domain; `--dart-define=WORKER_URL=` overrides for dev), first-run followed leagues, and poll cadences (**15s live / 30s near kickoff / 60s idle**, foreground-only). The theme is fixed design tokens (`theme.dart`, class `T`) — no Material seed color. The worker base URL is **user-set in Settings** (emulator → `http://10.0.2.2:8787`); a saved URL always wins over the default.

The game-detail signature is a **data-driven situation card** (`ui/situations.dart`) that dispatches on *data presence*, never sport name: `situation.hasBaseball` → diamond, `hasGridiron` → drive field, `competition.events` → match timeline, cricket target → chase, `layout == 'field'` → leaderboard; nothing applicable → no card.

> **Client stack (actual):** `http` + hand-written tolerant `fromJson` + `FutureProvider`/`StateProvider`/`Notifier` + an `IndexedStack` shell — *not* dio/freezed/go_router/AsyncNotifier.

## Conventions & gotchas

- **Status → phase: branch on `status.type.name`, never on `state` alone** (a postponed game can read `state: 'post'`). One `final` phase comes from many ESPN names (`STATUS_FINAL`, `STATUS_FULL_TIME`, `STATUS_FINAL_PEN`, …). Unknown names pass through as `unknown` — never crash.
- **Scores are STRINGS** in ESPN (`"103"`); `aggregateScore` stays a string in canonical too. `periodScores[].value` is **cumulative** for rugby (period 2 == final) — never sum periods.
- **"Overtime" only means extra play for timed/inning units** — not sets (best-of-5 ≠ OT), MMA rounds, laps, or golf rounds. See `OT_UNITS` in `normalize.js`.
- **JSON import quirk:** the Worker bundle imports `../../schema/league-profiles.json` *without* an import attribute (esbuild/wrangler handles it); the **Node test harness needs `with { type: 'json' }`**. Don't "fix" one to match the other.
- ESPN is **undocumented and unofficial** — endpoints can change without notice. `football-data.org` (free key) is the "go legit" escape hatch; the canonical layer exists so swapping providers is cheap. Run `verify.mjs` on a schedule to catch drift before users do.
- `league-profiles.json` marks `"verifiedIds": false` / `"verifiedIds": true` per league — honesty about what's confirmed against live data. See `schema/SCHEMA.md` §9 for outstanding live-shape re-checks.

## Where to read more (don't duplicate these — they're authoritative)
- `schema/SCHEMA.md` — the canonical model, ESPN→canonical mappings, the per-league period/OT matrix, worked JSON examples.
- `schema/canonical.ts` — the wire types with inline verification/quirk notes.
- `worker/README.md`, `app/README.md`, `schema/tools/README.md` — per-component detail.
- `app/DESIGN.md` — the **design spec**: color/type/spacing tokens, the card grammar, the per-sport delighter catalog, and the recipe for building screens that don't exist yet. **Read it before any UI/UX work** — building or restyling a screen, or touching color/type/spacing/copy (see §5).
