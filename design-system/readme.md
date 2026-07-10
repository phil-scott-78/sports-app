# Broadcast Dark — Sports App design system

The design system of the Scores app (an Apple Sports-style multi-sport scores
client), exported from its codebase. This project is the **iteration surface**:
edit cards here, and the changes sync back to the app repo's `design-system/`
directory, whose spec (`DESIGN.md`, included at the root here) and code mirror
(`app/lib/src/theme.dart`, class `T`) are kept in lock-step.

## What's here

- `DESIGN.md` — the authoritative spec: tokens, the card grammar, the
  per-sport delighter catalog, the event-feed framework, the table grammar,
  and the recipe for screens that don't exist yet. **Read it before designing
  anything.**
- `tokens/tokens.css` — the tokens as CSS custom properties + base classes.
  Every preview card inlines this block verbatim (cards are self-contained).
- `guidelines/` — foundation cards: colors, typography, spacing & shape,
  voice & microcopy.
- `components/` — the shared grammar: chips/pills/badges, score block &
  scorebug, dense rows, home hero cards, the inverted card, win probability &
  series pips, the table grammar, comparison patterns, bottom sheet,
  following-list rows.
- `situations/` — the per-sport situation-card catalog (baseball, gridiron,
  basketball, hockey, soccer, tennis, cricket, golf, racing/Olympics). Shapes
  dispatch on data presence, never sport name.
- `feeds/` — the four event-feed archetypes (sparse timeline, grouped
  episodes, scoring episodes, dense play-by-play + disclosure).
- `screens/` — full 428px screens assembled from the system: home feed,
  standings, following, baseball + soccer game detail, team page, tournament.

## The rules that make it this brand

Dark only (`#111318` / `#1A1E25`). Barlow Condensed 600/700 tabular for
anything numeric or structural; Archivo for everything read. Team identity is
color on shapes — vertical bars, dots, pips, fills — never a logo, never
colored text. Winner white and bold, trailer dim: that asymmetry is how a
result reads. One inverted light card per screen, maximum. Dashed = not yet.
Terse middot copy (`Suzuki up · 2–1 · 2 out`), en-dash scores, soccer primes,
no emoji (★ only), no exclamation points.

## Editing conventions

Every card is a self-contained HTML file whose first line is the
`<!-- @dsCard group="…" name="…" subtitle="…" -->` marker the Design System
pane indexes. Keep cards self-contained (tokens inlined, Google Fonts link
only, no JS, no images — diagrams are inline SVG/CSS shapes). Full authoring
rules: `_shared/CONVENTIONS.md`. If you change a token value, change it in
`tokens/tokens.css` AND in the affected cards' inlined copies — the sync back
to the repo will reconcile `theme.dart`.
