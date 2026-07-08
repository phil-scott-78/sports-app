# rework-plan.md — the master plan: spec + design → app

Execution plan for the full rework driven by `SCORES-APP-BUILD-SPEC.md` (the 9-screen
data-contract spec) and `polish-plan.md` (the 9 verified drift workstreams). This file
is the cross-session anchor: phases, owners, file ownership, and verification gates.

**Design ground truth:** `design-mirror/` holds files pulled from the Claude Design
project `8c0e9190` ("Sports App Design Concept"). Screen `.dc.html` files are mirrored
lazily as phases need them (only the orchestrator session can fetch them). Already
mirrored: `Index.dc.html`, `Venue.dc.html`, `SKILL.md`, `readme.md`. Remaining:
HomeFeed, LiveGame, EventList, BoxScore, TeamPlayer, Tournaments, Standings, Circuit.
`app/DESIGN.md` remains the authoritative distilled spec — read it first for ANY UI work.

**Current-state inventory (verified 2026-07-08):**
- Screens that exist and look complete: Scores feed, game detail (3,054-line mega
  screen), event feeds, box tables, team page, standings, following, golf scorecard,
  explore, settings, league page (rankings inline).
- Missing entirely: bracket/tournament-tree UI (tournament_page.dart is a flat tennis
  match list), player/athlete profile page, venue/circuit tab, standalone rankings page.
- Data layer missing: core `situation` (live football down/distance, NBA bonus/TO,
  hockey PP), core `predictor`/`probabilities`, odds (zero references), core
  venues/circuits docs, athlete statistics/eventlog, core team leaders, calendar
  `ondays`/range-scan date dots, broadcast/TV badge (cheap, unmapped).
- No capability-flag system — all gating is ad-hoc data-presence at the UI layer.
- Test surface: strong JS-parity goldens (271 fixtures), modest widget tests, no
  rendered-UI goldens.

## Invariants (every phase, every agent)

1. Read `app/DESIGN.md` before any UI change; use `T.` tokens, never literals.
2. Dart normalizers are golden-tested against the JS oracle (`worker/src/*.js`).
   Any normalizer change = mirror in the oracle + `cd worker && npm run goldens` +
   `flutter test` parity suites byte-for-byte green. Never change one side alone.
3. Canonical contract changes ripple three ways: `schema/canonical.ts`, JS oracle,
   Dart normalizer + `models.dart`. Keep all in sync.
4. No sport-name branches in consuming code — discriminators + data presence +
   capability flags only.
5. Registry edits go to `schema/league-profiles.json`, then
   `dart run tool/sync_registry.dart`.
6. Gate per phase: `flutter analyze` clean · `flutter test` green ·
   `cd worker && npm test` green · walk affected screens against `npm run mock`.

## Phases

### Phase 0+1 — Foundations + UI quick wins (RUNNING FIRST, one workflow)
| Track | Items | Files owned | Model |
|---|---|---|---|
| A stats+situations | polish 1 (share-vs-independent percent StatKind rework), polish 2 (Now-tab timeline curation + stoppage clamp) | `app/lib/src/ui/stat_specs.dart`, `app/lib/src/ui/situations.dart` + their tests | opus |
| B game-detail | polish 3a (line-score flex), 3b (drop last-12 cap), 6 (hockey shots-pressure + scoring cards), then 4a (plays virtualization, also `match_events.dart`) | `app/lib/src/ui/game_detail_page.dart`, `app/lib/src/ui/match_events.dart` + tests | opus |
| C tooling | polish 8 (capture full plays, summary coverage mapping, synth gridiron situation, synth golf consistency) | `worker/scripts/`, `worker/mock/` | sonnet |
| D capability flags | spec Part I §5: `capabilities{}` per family/profile in the registry (hasSummaryTier, hasSituation, hasWinProb, hasScoringPlaysArray, hasPlaysFeed, hasCommentary, hasForm, hasPowerPlay, hasLineScores, hasSeeds, hasWeather, rankingsFeed exists) resolved via the extends chain; accessors both sides; goldens regenerated | `schema/league-profiles.json`, `app/lib/src/data/profiles.dart`, `schema/tools/resolve.mjs` (if needed), goldens | fable (inherit) |
Then: verify gate → fix loop → orchestrator review + commit checkpoint.

### Phase 2 — Normalizer+UI lockstep pairs (polish 3c, 3d, 4b, 5b)
Half-inning grouping (`play.half`), box-score substitution rows + notes, play
participants + timeout dividers, drives extension (timeElapsed/period/running
score/per-drive plays) + Scoring|All drives UI. Each is JS oracle + Dart + goldens
lockstep. Sequential-ish on `summary.js`/`summary.dart`; UI fan-out after.

### Phase 3 — Bigger compositions (polish 3e, 5a, 7)
Baseball all-plays disclosure (pitch sequence — verify live shape first), CFB Now
resilience, golf event page (TODAY column, chip nav, hole strip, followed wash).

### Phase 4 — New data capabilities (spec Part II/V; all lockstep with new oracle files + captured fixtures + goldens)
- core `situation` on detail open (football down/distance, NBA bonus/TO, hockey PP)
- core `predictor`/`probabilities` win-prob fallback; odds (scoreboard inline + core on detail)
- broadcast badge (cheap, near-free) on rows/hero
- venues/circuits core docs (feeds Phase 5 venue/circuit tab)
- athlete statistics/eventlog (feeds player page)
- team leaders core endpoint; standings L10/DIV core records
- date-strip has-games dots (range-scan or ondays, per-league calendar mode quirk)

### Phase 5 — New screens (design-mirror file fetched per screen)
1. Venue/Circuit tab (spec 2.9; `Venue.dc.html` 14a mirrored, `Circuit.dc.html` 13a) — smallest, first
2. Player overview page (spec 2.6; `TeamPlayer.dc.html`)
3. Standalone rankings page (promote inline section)
4. Standings upgrades: wild-card view, playoff cut line, follow sheet polish (`Standings.dc.html`)
5. Home feed heroes/refinements (`HomeFeed.dc.html`)
6. Tournaments: 4 bracket grammars (spec 2.7; `Tournaments.dc.html`) — biggest, last

### Phase 6 — Cross-cutting closeout
Degraded-state matrix (spec §3.6), assets/identity cache + logoDark, DESIGN.md
patches (polish 9 + new patterns landed), gaps-ledger honesty pass (hide, don't
fake: capacity/opened/wind, xG, tennis live points…), final verification sweep +
CLAUDE.md updates.

## Status log
- 2026-07-08: plan created; Phase 0+1 workflow launched.
- 2026-07-08: Phase 0+1 COMPLETE, gate fully green (flutter analyze clean, flutter
  test 348/348 incl. parity suites, worker offline + live suites pass). Notes:
  much of polish phase 1 was already in baseline d55a531; the workflow landed the
  deltas — stat-row typography to exact §8 spec, timeline curation tests, feed
  flatten memoization (§4a), synth borrowed-summary rebase + fresh MLB capture
  (full pitch-level plays[]), capabilities{} registry table + SCHEMA.md §2a +
  hasCapability() accessor + regenerated meta/resolve.json golden.
  DEFERRED: NBA/NHL fixture re-capture (offseason — capture blocked as risky;
  re-run when in season; code path already correct).
  DISCOVERY: Phase 2's normalizer side (play.half, actor/participants,
  starter/note box rows, extended drives) is ALSO already in baseline — auditing
  what actually remains before launching Phase 2.
- 2026-07-08: AUDIT RESULT — polish-plan phases 2+3 are ~done in baseline:
  3c/3d/3e/5a/5b/9 all DONE (strict, file:line-verified). Remainder: 4b
  signal-row discipline + persistent score column (folded into Phase 4 workflow),
  drives chip 34×24 nit, golf followed-player wash + '· following' tag (deferred
  to Phase 5 player/athlete-following work), 3c stat strip (data-gated absent —
  acceptable). Tasks #2/#3 updated accordingly.
- 2026-07-08: Phase 4 workflow launched (phase4-data-capabilities): sequential
  full-stack chain — broadcast+odds, core situation+win-prob fallback (+ offline
  mock coverage), venues/circuits docs, athlete profile data, team leaders +
  standings sub-records, calendar dots — plus the parallel 4b UI fix. Lockstep
  protocol enforced per item; offseason capture limits flagged (goldens only from
  real captures; gridiron/hockey live shapes unit-tested from the guide).
- 2026-07-08: Core situation + win-prob fallback LANDED (build-spec §2.2 / Part I §3
  fetch-budget / Part V core list). New capability `hasCoreSituation` (football,
  basketball, hockey). Lockstep: canonical.ts Situation +yardLine/homeBonus/awayBonus
  +WinProbability predictor note → summary.js `buildCoreSituation`/
  `winProbabilityFromPredictor` (exported, wired into gen-goldens) → summary.dart
  port → models.dart (Situation merge + Competition.withSituation + GameSummary
  .situation) → espn_client.coreSituation/corePredictor → api.dart `_enrichLiveDetail`
  (merges core situation + win-prob fallback into the summary payload on the SUMMARY
  poll, not the scores poll; capability-gated, live-only, best-effort). UI:
  GridironSituationCard RED ZONE chip, new BasketballSituationCard (bonus/timeout
  chips), hockey PP fed by core `powerPlay` via the merge — all data-presence
  dispatch. Offline mock: synth `synthCoreSituation`/`synthCorePredictor`/
  `synthCorePlayText` + mock-server core-situation/predictor/coreplay routes
  (deterministic by event id) → CFB/NBA/NHL detail walkable offline. Gate green:
  flutter analyze clean, flutter test 368/368 (incl. new port_situation_core +
  situation_core_ui suites), worker units 151/151 + mock 214/214.
  TODO (offseason capture): `node scripts/capture-extra.mjs --only situation`
  found NO live football/NBA/NHL (nor MLB/WNBA — daytime) games on 2026-07-08, so
  `situationCore`/`winprob` goldens are 0 — normalizer parity is currently pinned by
  guide-shaped unit tests (worker/test/units.test.mjs + app port_situation_core).
  RE-RUN the situation capture when a gridiron/basketball/hockey game is LIVE (and an
  MLB/WNBA game in-progress in the evening) to land real byte-parity goldens; the
  capture + gen-goldens + port-test loop is already wired to pick them up.
