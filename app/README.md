# Scores (Flutter app)

A fast, calm, glanceable multi-sport scores app. Material 3, dark by default,
three tabs, no engagement bait — it consumes the canonical contract served by
the Cloudflare worker in `../worker`.

## Run it

```bash
flutter pub get
flutter run          # on a connected device/emulator
```

Then **set your worker URL** in the **Settings** tab (the app shows a setup
prompt until you do):
- Deployed worker (recommended): `https://sports-scores.<you>.workers.dev`
- Local worker on an **emulator** (`cd ../worker && npm run dev`): `http://10.0.2.2:8787`
  - cleartext `http://` to localhost works in **debug** builds; for a physical
    device, deploy the worker (https) instead.

First launch follows World Cup, MLB, and the NBA; add/remove leagues in the
**Leagues** tab (tap ★).

## What it does (v1)

- **Scores tab** — your followed leagues, today's games, live games pinned and
  red-chipped, scores updating in place. Polls every 15s when something is live
  and 60s when idle, and **stops polling in the background** (battery). Pull to
  refresh. Tap a game for detail.
- **Game detail** — big matchup, line-score table, records, venue/broadcast;
  leaderboard for golf/racing; method of victory for MMA.
- **Leagues tab** — browse the worker's catalog, ★ to follow, tap for standings.
- **Settings** — worker URL, theme (system/light/dark), betting-odds toggle
  (off by default, on purpose).

Works across every family the worker serves (team sports, golf/racing
leaderboards, tennis, MMA, cricket/rugby) because it renders off the canonical
discriminators (`layout` / `scoreKind` / `competitorKind`), not per-sport code.

## Architecture

```
lib/
  main.dart                 # boot: load SharedPreferences, ProviderScope
  src/
    config.dart  theme.dart  models.dart   # constants, M3 theme, canonical mirror
    api.dart                                # http client → worker
    providers.dart                          # Riverpod: settings, followed, feed, catalog, overview, standings
    ui/ app.dart home_shell.dart widgets.dart
        scores_page.dart game_detail_page.dart
        leagues_page.dart league_detail_page.dart standings_page.dart settings_page.dart
        # game-detail rendering (rich tier):
        detail_panels.dart box_score.dart score_tables.dart
        field_leaderboard.dart finish_grid.dart summary_feed.dart
        stat_specs.dart       # the stat language: kinds, per-sport panels, one row renderer
```

- **Stat language (`ui/stat_specs.dart`):** every team-stat row declares a
  *kind* and is drawn accordingly — percents (all three ESPN dialects: `52.4`,
  `.909`, `0.440`) as centre-out gauges against 0–100, conversion ratios
  (`4-16` on 3rd down) as made-of-attempts gauges, possession clocks (`33:11`)
  and counting stats as share-of-total splits. Per-sport cheap panels
  (`cheapStatPanels`: soccer match stats, basketball shooting, hockey
  goaltending, rugby possession/territory) render straight off the scoreboard;
  the rich `/summary` team stats are curated per sport (lead stats first, the
  firehose behind an "All team stats" expander). The game-detail section order
  is phase-aware: scheduled leads with the matchup, live with the pulse, final
  with the numbers.

- **State:** Riverpod (no codegen). The home feed is a `FutureProvider` over
  followed leagues; the Scores page drives adaptive refresh + lifecycle pausing.
- **Models:** hand-written tolerant `fromJson` mirroring `../schema/canonical.ts`
  (missing fields never throw). Covered by `test/widget_test.dart`.
- **Deps:** `flutter_riverpod`, `http`, `shared_preferences` — deliberately lean.

## Test / analyze

```bash
flutter analyze     # clean
flutter test        # model parsing (overtime detection, field sports, …)
```

## Not yet (v1.1+)

- Material You dynamic color (drop-in: add `dynamic_color` and seed from
  `CorePalette`).
- Push notifications (v2 — needs the worker's cron+FCM path).
