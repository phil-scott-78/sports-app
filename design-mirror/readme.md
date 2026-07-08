# Sports App Design System

A dark, score-first mobile sports app design system, extracted from the screen library in this project (an unbranded concept — no company identity, no logo). It covers live scores, game detail, box scores, standings, timelines, tournaments, and racing/circuit views across MLB, NBA, NFL/CFB, NHL, soccer, tennis, golf, cricket, and F1.

## Sources

- The screen library in this same project: `Index.dc.html` (manifest), `HomeFeed.dc.html`, `LiveGame.dc.html`, `EventList.dc.html`, `BoxScore.dc.html`, `TeamPlayer.dc.html`, `Tournaments.dc.html`, `Standings.dc.html`, `Circuit.dc.html`. These remain the ground truth for full-screen grammar.
- No external brand, Figma, or codebase was provided. There is **no logo** — render nothing where a mark would go, or plain type.

## Content fundamentals

- **Terse, telegraphic copy.** Fragments, not sentences: "Suzuki up · 2–1 · 2 out", "Palmer on · Foden off". Middle-dot (`·`) separators everywhere.
- **Sports vernacular, no explanation**: "BOT 7", "3RD & 4", "PP 1:24", "thru 12", "W4". The reader is assumed fluent.
- **Sentence case for body/metadata, UPPERCASE for structure** (screen titles, section headers, table headers, card labels like "LAST PLAY", "WIN PROBABILITY").
- Numbers use **en-dashes** (87–84, 2–1) and **tabular numerals**. Prime mark for soccer minutes (73′).
- The only editorializing is one bold line: "Wingo over the middle for 9 — dragged down at the 22."
- **No emoji.** The single ★ glyph marks favorites.
- Voice: neutral scoreboard. No "you/we", no exclamation points.

## Visual foundations

- **Dark only.** Cool blue-cast ink ramp: screen `#111318` → card `#1a1e25` → lifted `#1e232c`. Full ramp + semantics in `tokens/colors.css`.
- **Neutral chrome, team-color content.** The app itself owns only red (live/loss), green (win), yellow (accent). All other color comes from team brand colors, applied as **vertical bars** (5×16 → 12×44) — the system's stand-in for logos.
- **Type:** Barlow Condensed 600/700 for anything numeric or structural (scores, teams, titles, section headers); Archivo for everything read. Two fonts, no more. `tokens/typography.css`.
- **Cards** are the atomic layout unit: `#1a1e25`, radius 20 (detail) / 16 (lists), 1px `#262c35` border only on hero/map cards, hairline internal dividers. No shadows, no gradients as decoration.
- **Tints, not fills**: highlighted rows (favorite team, scoring play) use a left→right fade of the team color at ~7-8% (`linear-gradient(90deg, rgba(c,.07), transparent)`).
- **Spacing:** 20px screen gutter, 18px card padding, 10–12px card stack, 22px above section headers. `tokens/spacing.css`.
- **Radii:** 20 / 16 / 12 / pill / 24 sheet. Bars 2px.
- **States:** active chip inverts to white-on-dark; segmented thumb is `#2a303a`; no hover system (touch-first). Dim = trailing/losing (`--text-secondary` on names AND scores).
- **Layout:** sticky bottom nav on `#15181e` with top hairline; bottom sheets `#1d222a`, radius 24 top, heavy shadow + `--scrim`.
- **Motion:** essentially none defined; the one pattern used is 250–300ms ease on expand/collapse (max-height + opacity) and transform on carets.
- **Imagery:** none. Diagrams (base diamond, drive field, track map) are flat inline shapes on `--surface-inset` wells. Team logos/headshots are `image-slot` drop targets, circle-masked.

## Iconography

- **No icon set is defined.** Screens use neutral placeholder squares (22×22, radius 6) in the nav and circles (36px) in headers — these are intentional placeholders, kept in `BottomNav`.
- Semantic marks are drawn geometry, not icons: live dot (6px red), possession wedge (triangle), booking cards (11×15 rects), series dots, base diamonds (rotated rects). Keep these as shapes.
- ★ (U+2605) is the only unicode-as-icon usage (favorite).
- When productionizing, pick a round, geometric stroke set and swap the placeholder squares; flag this choice with the design owner.

## Index

- `styles.css` — global entry; imports everything in `tokens/`.
- `tokens/` — `colors.css`, `typography.css`, `spacing.css`, `fonts.css` (Google Fonts: Barlow Condensed, Archivo — hosted, not local binaries).
- `components/`
  - `core/` — Card, SectionHeader, StatusPill, ChipNav, SegmentedControl, StatCell
  - `scores/` — TeamMark, ScoreRow, Scorebug, SeriesDots, WinProbBar
  - `feed/` — TimelineRow, DividerLabel
  - `navigation/` — BottomNav
- `guidelines/` — foundation specimen cards (colors, type, spacing).
- `ui_kits/mobile/` — interactive home feed + standings composed from the library.
- `*.dc.html` (root) — the original screen explorations; richest reference for full-screen grammar (drive fields, brackets, box-score tables, bottom sheets).
- `SKILL.md` — agent skill entry point.

## Intentional additions

None — every component maps to a repeated pattern in the screen library. The `image-slot` drop-target and Android frame used by the source screens are project utilities, not design-system components.
