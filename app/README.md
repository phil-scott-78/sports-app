# Scores — Flutter client

The **broadcast-dark** Flutter client, implementing the design language from the
Claude Design exploration (*Sports App Explorations.dc.html*, turns 2–8). Same
worker, same canonical contract.

## The design language

Full spec in [`DESIGN.md`](DESIGN.md) — tokens, card grammar, per-sport
delighter catalog, and the recipe for building screens that don't exist yet.
The short version:

- **Palette**: `#111318` page, `#1A1E25` cards (20px radius), one inverted
  light card per screen (LAST PLAY) as the loud moment. Team identity is a
  **color bar**, never a logo.
- **Type**: Barlow Condensed 700 for everything scoreboard (team names,
  scores, clocks, stat lines — always tabular), Archivo for copy. Both
  bundled in `assets/fonts/`.
- **Grammar** (game detail): giant score block (collapses into a sticky
  scorebug on scroll) → pinned chip nav → *situation card* (the sport's
  flourish) → win probability → inverted last play → supporting stats.

## Structure

```
lib/src/
  models.dart      # canonical-contract mirror (+ FavoriteTeam.color)
  api.dart         # worker client (the only place the app does I/O)
  config.dart      # defaults; WORKER_URL dart-define override for dev
  providers.dart   # Riverpod: settings, followed, favorites, feed, standings, summary
  theme.dart       # the design tokens (class T) — colors, type styles
  util.dart        # team-color legibility, time/status formatting
  ui/
    app.dart             # MaterialApp + 3-tab shell (Scores / Standings / Following)
    scores_page.dart     # TODAY feed: hero cards + dense league sections
    hero_card.dart       # stacked favorite cards (live / upcoming / final states)
    league_card.dart     # one league's slate as dense rows (feed + league page)
    game_detail_page.dart# collapsing header + chip-nav sections
    situations.dart      # data-driven sport situation cards (see below)
    explore_page.dart    # league browser: LIVE NOW / ON TODAY pulse + catalog
    league_page.dart     # any league's slate + Follow pill + rankings panel
                         #   (ATP/WTA points, UFC divisions, college polls —
                         #   shown when the catalog's `rankings` flag is set)
    golf_scorecard_page.dart # hole-by-hole scorecard (leaderboard row tap):
                         #   round chips, OUT/IN nine grids colored by scoreType,
                         #   pre-round tee time, tournament stat line
    standings_page.dart  # league chips + group tables, favorite highlighted
                         #   (racing championships ride the same tables)
    following_page.dart  # drag-to-reorder favorites & leagues
    follow_sheet.dart    # long-press bottom sheet (add from anywhere)
    add_pages.dart       # team picker (league browsing lives in explore_page)
    settings_page.dart   # worker URL
    widgets.dart         # design system: cards, chips, pips, diamond, bars
    poll.dart            # lifecycle-aware polling mixin
```

## Conventions carried over from v1

- **Never branch on sport name.** Situation cards dispatch on *data
  presence*: `situation.hasBaseball` → diamond card, `situation.hasGridiron`
  → drive field (position parsed from `downDistanceText`), `competition.events`
  → match timeline, cricket `periodScores` with a target → chase card,
  `layout == 'field'` → leaderboard. Nothing applicable → no card.
  The 2026-07 additions follow the same rule: `meta.golf` → cut-line strip,
  `summary.cricketInnings` → Scorecard chip, `summary.drives` → Drives chip,
  `comp.method`/`summary.bouts` → method card with judge scorecards,
  `summary.attendance`/`officials` → Game info rows, `comp.headline` → one
  quiet recap line.
- Scores are strings; status branches on `phase`; tolerant parsing never throws.
- Poll cadence: 15s live / 30s near kickoff / 60s idle, foreground only
  (mirrors the worker's TTLs).

## Run

```bash
flutter pub get
flutter analyze          # must stay clean
flutter test             # model parsing + situation dispatch + widget smoke
flutter run              # Android; set worker URL in Settings (gear on TODAY)

# against the offline mock (walk every UI state):
#   (cd ../worker && npm run mock)
flutter run --dart-define=WORKER_URL=http://10.0.2.2:8787   # Android emulator
flutter run -d chrome --dart-define=WORKER_URL=http://localhost:8787
```
