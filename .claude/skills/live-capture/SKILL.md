---
name: live-capture
description: >-
  Capture ESPN's live-gated data while a game is actually in progress — snapshot loops for the
  summary/scoreboard/core-plays/situation tiers, then turn the snapshots into committed fixtures + regenerated
  goldens. Use whenever a notable game is live (or about to be) and we want its data: the user pastes an ESPN
  URL ("here's the game"), names a matchup ("France-Morocco is live, grab it"), says "capture tonight's game /
  what's live right now", or a feature needs live-only shapes (core situation, mid-match plays feed, in-progress
  summaries) that CANNOT be recaptured after full time. Also the recipe for probing a new sport's live surface
  (does its plays feed carry coordinates?).
---

# Live capture — grab it while it's live

ESPN's most valuable shapes are **perishable**: the core `situation`/`predictor` 404 unless the
game is in progress, mid-match summaries (a 0-0 with a live clock, a half-full plays feed, live
leaders) can never be recaptured, and offseason scoreboards replay stale slates for months. When
something big is live, **start capturing FIRST, decide what to build second.** A snapshot loop
costs nothing; a missed window costs the fixture forever.

## 1. Resolve the target

Accept any of: an ESPN URL, a "league/event" pair, a matchup name, or "whatever is live".

- **ESPN URLs** carry the event id as `gameId` (and usually name the sport in the path):
  `espn.com/soccer/match/_/gameId/760510/...` → sport `soccer`, event `760510`.
  League slug is NOT always in the URL — get it from the merged scoreboard (below) or the page path.
- **Matchup / "what's live"**: hit the merged pulse first —
  `site.api.espn.com/apis/site/v2/sports/<sport>/all/scoreboard` (capability `hasAllScoreboard`:
  soccer/rugby/rugby-league/tennis/golf/mma; events carry their league as the uid's `l:<id>`,
  match against the registry's `espnLeagueId`) — else per-league scoreboards for the v1 leagues.
- From the scoreboard event, record: **league key** (`soccer/fifa.world`), **eventId**,
  **competitionId** (usually = eventId), **homeId/awayId** (competitor team ids — core plays tag
  teams by `$ref` only, you need these for side attribution), and kickoff time.

## 2. What to snapshot — `npm run capture:live` does all of it

The whole loop is a repo command (`worker/scripts/capture-live.mjs`):

```bash
cd worker
npm run capture:live -- <sport/league>                 # auto-picks the live (else next) event
npm run capture:live -- baseball/mlb --event 401816120 # pin a specific game
#   [--interval <s>]  cadence, default 120   [--out <dir>]  default mock/live-capture/<league>__<event>/
```

One process per game (run each `run_in_background: true` so the harness notifies on exit). It
snapshots every cycle into gitignored `worker/mock/live-capture/…` and exits on
`status.type.state == 'post'` (state, NEVER play-text heuristics — "End Regular Time" fires at 90'
even when extra time follows) with two settled final passes. What each cycle grabs:

| Resource | URL shape | Cadence | Why live-only |
|---|---|---|---|
| site summary | `apis/site/v2/sports/{league}/summary?event={id}` | 90–120s | live leaders / commentary-in-progress / live clock states are unrecapturable |
| scoreboard | `apis/site/v2/sports/{league}/scoreboard` | with summary | live situation/odds ride it |
| core plays (ALL pages) | `sports.core.api.espn.com/v2/sports/{sport}/leagues/{lg}/events/{id}/competitions/{cid}/plays?limit=300[&page=N]` | 3min | append-only; grows all match; the coordinate source (SCHEMA.md §2b) |
| core situation + predictor | `.../competitions/{cid}/situation` / `predictor` | 60–90s | **404 unless in-progress** (capability `hasCoreSituation`/`hasWinProb` sports). NOTE: for basketball the predictor is a STATIC pregame model (VERIFIED live 2026-07-09, WNBA: `teamPredWinpct` never moved all game) — the live win-prob timeline is the summary's `winprobability[]` + the scoreboard's `lastPlay.probability`; don't expect a predictor timeline |
| core odds | `.../competitions/{cid}/odds` | once, PRE-game | lines vanish/settle at kickoff |

The script skips byte-identical payloads (pregame and halftime cycles repeat verbatim), so a
snapshot on disk always means something moved. Grab a **final** snapshot after `post` (suffix
`_final_`), and keep the mid-match series — mid states are fixtures too (a live 0-0, a half-full
feed); final-only fixtures bias tests toward completed games.

## 3. Turn snapshots into fixtures + goldens

The committed pipeline (fixture → JS oracle → golden → Dart parity test):

1. **Summary** → `worker/mock/fixtures/<sport>__<league>.json` `summaries[eventId]`, trimmed with
   the same logic as `capture-fixtures.mjs trimSummary`. **THE TRIMMER IS PART OF THE CONTRACT
   CHAIN** — if a normalizer reads a new raw field, `trimSummary` must keep it or the golden
   silently loses it (this bit twice on 2026-07-09: `leaders`, `fieldPositionX/Y`).
2. **Core plays** → `worker/mock/fixtures/_extra.json` `matchFeeds[]` as
   `{key, eventId, homeId, awayId, raw:{count, items}}`, items slimmed like
   `capture-extra.mjs slimMatchFeedPlay`. For future recapture: `npm run capture-extra --
   --only matchfeeds` (LIVE-best — run it during a big match). **SOCCER ONLY** —
   `matchfeed.js` reads `fieldPositionX/Y`; basketball core plays use `coordinate{x,y}`,
   so promoting them there yields a coord-less golden. A basketball shot chart needs its
   own capability + normalizer first; until then keep basketball core-plays snapshots on
   disk only.
   **Core situation + predictor** → `_extra.json` `situation[]` as `{key, eventId,
   competitionId, shortName, situation, lastPlayText, predictor}` (the `captureSituation`
   shape; `lastPlayText` = the resolved `situation.lastPlay.$ref` text — the same-cycle
   scoreboard's `situation.lastPlay.text` is that play). gen-goldens emits the
   situationCore + winprob goldens from it.
3. Regenerate: `cd worker && node scripts/gen-goldens.mjs`, then verify **offline** suites
   (`node test/units.test.mjs`, `node test/mock.test.mjs`) and `cd app && flutter test`.
4. A one-off injector script (scratchpad) is fine for step 1–2 — see the 2026-07-09 session's
   `inject-fixtures.mjs` pattern: keep trim/slim logic mirrored from the capture scripts. Prefer
   `snap_*_final_*` for feeds whose value is completeness (core plays, box scores) — but prefer a
   MID-GAME snapshot when the live state itself is the prize: the final summary is stable and
   recapturable any time, while a live clock + partial winprobability[] + in-bonus situation can
   never be captured again (the WNBA 401857051 fixture commits the mid-Q4 event + summary for
   exactly this reason).

## 4. Probing a NEW sport's live surface (while it's live)

- Does the plays feed exist / carry coordinates? → check SCHEMA.md **§2b** first (probed matrix);
  re-probe in-season blanks (NHL!) with
  `node schema/tools/probe-plays-coords.mjs <sport/league> [YYYYMMDD]` — it unions play keys,
  flags coordinate fields, filters sentinels (basketball's `-214748340` = "no coord"), and calls
  out inconclusive offseason results.
- **Calibrate before rendering**: verify orientation from KNOWN-location events (goal kicks →
  team-relative x≈2–5; penalty spot x≈88.5; centre jump / face-off dots / centre bounce
  elsewhere). Record the finding in SCHEMA.md §2b.
- Live-gated tiers to try while you can: core `situation`, `predictor`, `probabilities`,
  per-competition `odds` movement, the fastcast topics (`worker/scripts/capture-fastcast.mjs --probe`).

## 5. Verify against the live game

Golden parity proves the port is faithful, not that the interpretation is right (a formation can
render mirrored with every test green). While the game is still on, run the app
(`flutter run -d <emulator>`) and eyeball the new surface against reality — then once more after
full time for the final/recap states.

## Cross-references

- Endpoint/field questions → the `espn-api` skill → `schema/espn-guide/`.
- Coordinate matrix + calibration rule → `schema/SCHEMA.md` §2b.
- The capability gates (`hasMatchFeed`, `hasCoreSituation`, …) → `schema/SCHEMA.md` §2a.
- Worked example (FRA–MAR World Cup QF, 2026-07-09): capability `hasMatchFeed`, canonical
  `MatchFeed`, `worker/src/matchfeed.js` + `app/lib/src/data/matchfeed.dart`, fixtures in
  `_extra.json matchFeeds` + `soccer__fifa.world.json summaries['760510']`.
- Worked example (WNBA SEA–ATL, 2026-07-09, event 401857051): the LIVE mid-Q4 scoreboard
  event (cheap `situation.lastPlay.probability.homeWinPercentage` — SCHEMA.md §10f) +
  mid-game summary → `basketball__wnba.json`; CORE situation (DOUBLE bonus + timeouts) +
  predictor → `_extra.json situation[]` (the situationCore/winprob goldens). Fallout fix:
  the predictor fallback gained `teamPredWinpct` (summary.js/.dart) — WNBA predictors carry
  no `gameProjection`.
