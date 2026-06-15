---
version: 2
name: scores-design-language
description: >
  The design language of the Scores app: a calm, glanceable, greyscale-first
  system. A near-black canvas holds flat blocks separated by 1px hairlines —
  no shadows, no atmospheric depth. Hierarchy is carried by weight, size, and
  two-tier muting, NOT by color. Color enters only when the data earns it:
  team color washes a result the moment it is final. A single scarce yellow
  (#FCD535) is reserved for functional interactive moments (the one primary
  action, selection, focus) — never as brand voltage or decoration. Trading
  green/red are strictly up/down semantics. Numbers run IBM Plex tabular so
  scores never reflow. Derived from a Binance trading-platform analysis (see
  Lineage), but evolved away from its yellow-centric brand model.

# Resolved against the live code (theme.dart + scores_page.dart GameCard, the
# gold standard). The widget names below are the real ones; the token values
# below are the ones actually used on screen, harvested from app/lib/src.

colors:
  # canvas / surface ladder (dark — the showcase mode)
  canvas-dark:        "#0b0e11"   # page floor, near-black warm tint (cs.surface)
  surface-card-dark:  "#1e2329"   # flat card / panel fill   (surfaceContainerLow)
  surface-elevated:   "#2b3139"   # nested fill, selected pill, badge, hairline
  card-border:        "#2b3139"   # the 1px hairline (BinanceColors.cardBorder)
  # text (two-tier muting does the hierarchy work)
  body-on-dark:       "#eaecef"   # primary running text   (onSurface) — not pure white
  muted-strong:       "#929aa5"   # emphasized secondary    (onSurfaceVariant, dark)
  muted:              "#707a8a"   # captions, column heads, dim hairlines only
  slate:              "#5e6673"   # neutral counterpart to accent (mirrored bars)
  # light mode (transactional surfaces flip; same scarce accent rules)
  canvas-light:       "#ffffff"
  surface-card-light: "#fafafa"
  ink:                "#181a20"   # strongest text on light (also onPrimary)
  hairline-light:     "#eaecef"
  # the scarce functional accent
  accent-dark:        "#fcd535"   # yellow — ONLY on the dark canvas
  accent-light:       "#181a20"   # ink — the accent on light (yellow-on-white is illegible)
  accent-fill:        "#fcd535"   # filled CTA stays true yellow in BOTH modes (cs.primary)
  on-accent:          "#181a20"   # black on yellow — the one signature pairing
  # semantics (never surfaces, never decoration)
  up:                 "#0ecb81"   # trading green — gain / today-pulse / batting
  down:               "#f6465d"   # trading red  — loss / live pulse (cs.error)
  focus:              "#3b82f6"   # input focus ring only

typography:
  # Two families, split by function. Copy = Inter (kSans). Numbers = IBM Plex
  # (kNumFont) ALWAYS via numStyle() with tabular figures so digits don't reflow.
  families:
    sans: "Inter"            # kSans — every label, title, body
    num:  "IBMPlexSans"      # kNumFont — every score, clock, stat, count, %
  # Real on-screen scale (mobile). Roles, not marketing display sizes.
  scale:
    appbar-title:   { size: 22, weight: 700, tracking: -0.2 }   # the only big copy
    page-title:     { size: 18-20, weight: 700 }                 # detail header / field title
    card-title:     { size: 15, weight: 700 }                    # favorite/field card heading
    row-title:      { size: 14, weight: 600 }                    # list-row primary line
    section-header: { size: 14, weight: 700, role: titleSmall }  # group header (_SectionHeader)
    body:           { size: 13, weight: 400-500 }                # secondary / running
    label:          { size: 12, weight: 500 }                    # captions, meta
    column-header:  { size: 11, weight: 600-700, muted: true }   # table column heads
    micro-badge:    { size: 10, weight: 700, tracking: 0.3 }     # OT / PENS / AGG chips
  numbers:
    score-hero:     { size: 28, weight: 700-800 }   # GameCard score (winner 800)
    score-detail:   { size: 18-22, weight: 700 }    # detail header score
    stat:           { size: 13-14, weight: 500 }    # table / box-score cells
    micro:          { size: 11-12, weight: 500 }    # line scores, splits
  # DEPRECATED one-offs to normalize away: 12.5 → 12 or 13; 13.5 → 13 or 14.

rounded:   # nothing larger than 12; no pills anywhere
  micro:   2    # mirror stat bars, line-score micro cells
  badge:   4    # decision badges, W/L form pills
  control: 6    # buttons, chips, segmented control, status chip, live pill
  input:   8    # text fields, the date-mode pill, search
  card:    12   # cards, panels, dialogs — the only "container" radius

spacing:   # base 2; the app lives in 2..16, reserves 24/32 for empty-state breathing
  hair:    2    # micro gaps, tight chip padding
  tight:   4    # label → value, intra-row
  snug:    6    # crest → name, chip gaps
  gap:     8    # between stacked cards, standard small gap
  step:    10
  group:   12   # card gutter (inset from screen edge), between groups
  card-pad: 14  # interior padding of a card/panel
  block:   16   # between major blocks/panels, text gutter
  roomy:   24   # empty-state / setup-prompt breathing
  open:    32   # empty-state outer padding

gutters:
  text:    16   # section headers, info tiles, page copy indent from edge
  card:    12   # cards inset 4px wider than text — a deliberate Apple-Sports trait
  card-gap: 8   # vertical gap between stacked cards

# Real components (the actual widgets — see Components section for full specs):
#   GameCard, FavoriteTeamCard, DetailPanel, ListCard(proposed), SectionHeader,
#   StatusChip, LiveDot, Crest, DecisionBadge, score-cluster, team-color wash.
---

## Overview

The Scores app is **greyscale-first**. The entire interface is built from a
near-black canvas (`canvas-dark`, #0b0e11) carrying flat blocks
(`surface-card-dark`, #1e2329) separated by **1px hairlines** (`card-border`,
#2b3139). There are **no shadows and no atmospheric depth** — elevation is a
surface step plus a hairline, nothing more.

The thing that makes the app feel finished is **restraint**: hierarchy is
carried by **weight, size, and two-tier muting**, almost never by color. In a
game card the winner reads stronger because its score is heavier (w800 vs w700)
and the loser is *dimmed* to the muted text tone — not because anything is
tinted. This is the whole personality of the score screen, and it is the model
every other screen should follow.

Color is **earned, not decorative**. It enters in exactly two disciplined ways:

1. **Team color** — the expressive layer. When a game goes final, the winning
   team's color washes the card at very low alpha (a sheen, not a fill). This is
   the app's one moment of life, and it is tied strictly to *a result being in*.
2. **A single scarce yellow** (#fcd535) — the functional layer. Demoted from the
   source system's "brand voltage." Here it marks only **interactive intent**:
   the one primary action on a screen, a selected control, a focus/progress
   state. It never decorates, never marks "value," never headlines.

> **The shift from v1.** The original (Binance-derived) doc made yellow "the
> single brand color that does all the brand voltage." This version demotes it.
> Yellow is now just *where you'd tap*. The expressive accent is team color; the
> structure is greyscale + spacing + hairlines. If you're reaching for yellow to
> make something look important, you've made a mistake — use weight, size, a
> hairline, or (if a result is in) team color instead.

**Key characteristics:**
- Greyscale substrate; hierarchy by weight/size/muting, not color.
- Flat blocks + 1px hairlines; zero shadow; `surfaceTint` always transparent.
- Team color earned only on final results, low-alpha, directional.
- Yellow scarce and functional: one primary action, selection, focus.
- Trading green/red are up/down semantics only — never a surface, never "success/error" chrome.
- Numbers always IBM Plex tabular via `numStyle()`; copy always Inter.
- Radius tops out at 12 (cards); no pills. Spacing lives in 2..16.

---

## Colors

### The greyscale substrate (does 95% of the work)

| Role | Token (dark) | Hex | ColorScheme slot |
|---|---|---|---|
| Page floor | `canvas-dark` | #0b0e11 | `surface` |
| Card / panel | `surface-card-dark` | #1e2329 | `surfaceContainerLow` |
| Nested / selected pill / badge fill | `surface-elevated` | #2b3139 | `surfaceContainerHigh(est)` |
| Hairline (card border, divider) | `card-border` | #2b3139 | `BinanceColors.cardBorder` / `outlineVariant` |
| Primary text | `body-on-dark` | #eaecef | `onSurface` |
| Secondary / muted text | `muted-strong` | #929aa5 | `onSurfaceVariant` |
| Captions, column heads, dim hairlines | `muted` | #707a8a | `outline` |

**Two-tier muting is the core technique.** Primary entity → `onSurface`.
Secondary/caption, *and any losing/dimmed entity* → `onSurfaceVariant`. The
losing team's name and score both drop to `onSurfaceVariant`; the winner stays
`onSurface` and goes heavier. Never invent grey hex values — these two tiers +
the canvas ladder cover everything.

### Team color — the earned, expressive accent

The only color that carries meaning about the *content*. Sourced per-competitor
from ESPN (`color` / `altColor`). Rules:

- **Only on final results.** A live or scheduled game stays pure greyscale.
- **Only as a low-alpha wash**, never a fill: `0.10` on light, `0.16` on dark.
- **Directional**: the wash originates from the winning team's corner (home →
  top-left, away → bottom-right, matching crest positions); a draw tints from
  both corners toward a neutral center.
- **Luminance-guarded**: if a team's primary color is too near the canvas to
  register (near-black on dark, near-white on light) fall back to its
  `altColor`; if neither registers, the card stays plain greyscale.

This is implemented today in `scores_page.dart` `_cardGradient` / `_tintColor` —
treat that as the reference for any future team-color use (e.g. a detail header).

### The scarce functional yellow

`accent` is **mode-aware**: true yellow (#fcd535) on the dark canvas, ink
(#181a20) on light — so it never becomes illegible yellow-on-white. Read it via
`BinanceColors.of(context).accent`; **never hardcode `Color(0xFFFCD535)`** in a
screen. Filled CTAs are the one exception: the `FilledButton` keeps the *true*
yellow fill (`cs.primary`) + black text (`on-accent`) in both modes — the one
signature pairing.

**Legitimate uses (the whole list):**
- the single primary action on a screen (`FilledButton`),
- the selected state of a control (segmented button, chip, switch-on, nav glyph),
- focus ring is the blue `focus` (#3b82f6); progress / cursor use `accent`,
- a pure-binary winner mark where there's no score to embolden (the MMA win check).

**Never:** section headers, generic leading icons, dividers, decision badges,
"this looks important" emphasis, body text, or marking a value/winner that a
score already carries (use weight there, not yellow).

### Semantics — up / down only

`up` (#0ecb81) and `down` (#f6465d / `cs.error`) are **price-direction signals**:
gains/losses, the live pulse dot, an active "batting" marker. Applied as **text
or icon color, or a small fill** — never a card surface, never repurposed as
generic success/error chrome.

---

## Typography

Two families, split by function — this split is not optional:

- **Inter** (`kSans`) — every label, title, and body string. It's the theme
  default `fontFamily`, so plain `Text` already gets it; explicit styles must
  not switch families.
- **IBM Plex Sans** (`kNumFont`) — every number: scores, clocks, stats, counts,
  percentages. Always through `numStyle(size:, weight:, color:)`, which pins
  `tabularFigures` so digits never change width as they tick. A score in a plain
  `TextStyle` is a bug: it'll reflow and read "marketing," not "scoreboard."

### Scale (real, mobile)

| Role | Size | Weight | Notes |
|---|---|---|---|
| App-bar title | 22 | 700 | tracking −0.2; the only large copy |
| Page / field title | 18–20 | 700 | detail header, field-sport event name |
| Card title | 15 | 700 | favorite / field card heading |
| Row title | 14 | 600 | list-row primary line |
| **Section header** | ~14 (`titleSmall`) | 700 | neutral `onSurface` — see below |
| Body / secondary | 13 | 400–500 | `onSurfaceVariant` |
| Label / caption | 12 | 500 | meta |
| Column header | 11 | 600–700 | muted, table heads |
| Micro badge | 10 | 700 | OT / PENS / AGG, tracking 0.3 |

Numbers: hero score **28** (winner w800 / loser w700), detail score **18–22**,
table stats **13–14**, micro line-scores **11–12**.

**Normalize the strays:** `12.5` and `13.5` appear as one-offs (date segment,
center status, a couple of cells). Round them to the scale (`12`/`13`/`14`)
unless there's a measured reason — they read as accidental, not intentional.

### Section header — the one canonical pattern (currently forked 3 ways)

The gold standard is `_SectionHeader` in `scores_page.dart`:

```dart
Padding(
  padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
  child: Text(title, style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
)
```

Small, bold, **neutral `onSurface`** — *not* tracked-uppercase, *not* muted, and
not a large display size. It must be **promoted into `widgets.dart` and reused**.
Today three voices coexist and should collapse into this one:

1. ✅ `_SectionHeader` — canonical (`16,18,16,8`).
2. ⚠️ Inline `Padding+Text` copies with `(16,16,16,4)` — Leagues, Standings,
   Add-leagues, Favorite-teams, summary period headers. Same style, drifted
   padding. → use the canonical widget.
3. ⚠️ All-caps tracked muted `_Label` (Settings) / `SectionLabel` (widgets).
   This is a *column-label* voice, distinct from a section header. Either
   rename it `ColumnLabel` and keep it strictly for in-table column heads, or
   fold it into `_SectionHeader`. Pick one; don't let both read as "section title."

---

## Spacing & Rhythm

The app's whole calmness comes from consistent spacing. Base unit is **2px**;
real layouts live in **2 / 4 / 6 / 8 / 10 / 12 / 14 / 16**, reserving **24 / 32**
for empty-state breathing only. Memorize the *semantic* assignments — reach for
the role, not a raw number:

| Role | Value | Where |
|---|---|---|
| `hair` | 2 | micro gaps; mirror stat-bar height; tight chip padding |
| `tight` | 4 | label → value; intra-row nudges |
| `snug` | 6 | crest → name; chip-to-chip |
| `card-gap` | 8 | vertical gap between stacked cards; standard small gap |
| `group` | 12 | **card gutter** (inset from screen edge); gap between groups |
| `card-pad` | 14 | **interior padding** of a card / panel |
| `block` | 16 | between major blocks/panels; **text gutter** |
| `roomy` / `open` | 24 / 32 | empty-state + setup-prompt only |

### The two-gutter rule (a deliberate Apple-Sports trait)

- **Text gutter = 16.** Section headers, info tiles, and page copy indent 16 from
  the screen edge.
- **Card gutter = 12.** Cards inset 12 — so cards sit **4px wider** than the text
  above them. This is intentional (it makes cards feel like they belong to the
  surface, not boxed-in copy). Keep it consistent: a card list is
  `EdgeInsets.fromLTRB(12, 0, 12, 8)` per card.

### Vertical rhythm

- **Between detail panels:** `16` (`SizedBox(height: 16)` — the dominant beat on
  the game-detail screen).
- **Between cards in a feed:** `8` (bottom padding on each card).
- **Section header:** `18` above / `8` below (the canonical `(16,18,16,8)`).
- **Inside a card:** `14` all around; internal stacks step `4`–`8`.
- **Crest → name → record:** `6` then `2`.

### Card interior — the single inconsistency to resolve

`GameCard` and `FavoriteTeamCard` pad **14**; the game-detail body pads **16**.
Pick **14** as the card-interior standard (it's the score-screen value and the
more common one) and let **16** stay the *between-block* beat. Don't mix 14 and
16 as interior padding within the same surface.

### Whitespace philosophy

Calm, not airy. The app trusts hairlines and the surface step to separate
content, so gaps stay small (8–16) and *uniform*. Inconsistent gaps are what
make a screen feel "off" even when colors are right — a 4px drift in a section
header is visible. When in doubt, match the score screen's exact numbers.

---

## Elevation & Surfaces

**Flat. Always.** No `BoxShadow`, no `elevation > 0`, no glassmorphism. Depth is
expressed two ways only:

1. **Surface step** — `canvas (#0b0e11)` → `card (#1e2329)` → `elevated
   (#2b3139)`. The ~12-step lightness jump from canvas to card *is* the elevation
   boundary.
2. **1px hairline** — every card/panel carries
   `BorderSide(color: BinanceColors.of(context).cardBorder, width: 1)`.

| Level | Treatment | Use |
|---|---|---|
| Flat | no border, no shadow | app bar, nav, page sections |
| Hairline | 1px `card-border` | dividers, table row rules, input borders |
| Card | `surfaceContainerLow` + 1px hairline + radius 12 | **every** card / panel |
| Selected/nested | `surfaceContainerHigh(est)` fill | selected pill, badge, nested block |
| Focus | 2px `focus` (#3b82f6) ring | input focus only |

> **`surfaceTint` must stay transparent.** The theme already kills the M3 purple
> elevation tint on AppBar / NavigationBar / Dialog. **Any inline `Material` you
> create yourself** (e.g. a drag proxy, a custom sheet) must set
> `surfaceTintColor: Colors.transparent` *and* the 1px hairline — otherwise it
> reintroduces the tint and floats off-language. (This is exactly the
> `manage_leagues` drag-proxy bug.)

### The flat-card recipe (memorize — it's the gold standard)

```dart
Material(
  color: cs.surfaceContainerLow,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(12),
    side: BorderSide(color: BinanceColors.of(context).cardBorder, width: 1),
  ),
  clipBehavior: Clip.antiAlias,
  child: /* InkWell → Padding(14) → content */,
)
```

Every list row, table group, and panel that wants to read as "a thing" uses
this. A bare `ListTile` or a naked `DataTable` on the scaffold floor is the #1
tell that a screen fell off the language.

---

## Shapes

Radius scale — nothing above 12, no pills:

| Token | Value | Use |
|---|---|---|
| `micro` | 2 | mirror stat bars, line-score micro cells |
| `badge` | 4 | decision badges (OT/PENS/AGG), W/L form pills |
| `control` | 6 | buttons, chips, segmented control, status chip, live pill |
| `input` | 8 | text fields, the date-mode pill, search |
| `card` | 12 | cards, panels, dialogs |

Crests/avatars are the only circles. No `rounded.pill` / `9999` anywhere — the
source system's pill CTA does not exist here.

---

## Components (the real widgets)

- **`GameCard`** *(gold standard, `scores_page.dart`)* — flat card; head-to-head
  row = crest + short name (outer edges) flanking a centered score-cluster
  (`28` tabular scores hugging a `12.5→13` status). Winner heavier; loser dimmed.
  Final games get the team-color wash. Field sports render a leader line instead.
- **`FavoriteTeamCard`** — the "my team now" card; same flat surface, 14 padding.
- **`DetailPanel`** *(`widgets.dart`)* — the universal game-detail container:
  flat `surfaceContainerLow`, 1px hairline, radius 12. Every detail section
  (box score, scoring feed, leaders, standings, leaderboards) lives in one.
- **`ListCard`** *(to add)* — the flat-card recipe wrapping a list row, so
  Leagues / Add-leagues / Manage-leagues / Settings rows read like the score
  screen instead of bare `ListTile`s. This is the single biggest consistency win.
- **`SectionHeader`** *(promote from `scores_page`)* — the one group-title voice.
- **`StatusChip` / `LiveDot`** — status pill (radius 6); the live state is a
  pulsing `cs.error` dot + high-contrast clock. Reused as the season-pulse dot.
- **`Crest`** — team logo with abbreviation fallback; mode-aware (`logoDark`).
- **`DecisionBadge` (`_Badge`)** — neutral context tag: `surfaceContainerHighest`
  fill, radius 4, `10/700` `onSurfaceVariant`. Never yellow, never green/red.
- **Buttons** — primary action = `FilledButton` (yellow fill, black text, radius
  6). Secondary = `TextButton`/`OutlinedButton` in neutral `onSurfaceVariant`.
  **Do not use `FilledButton.tonal`** for a primary action — it renders muted
  grey and drops the one functional-accent moment a screen has.
- **Inputs** — lean on `inputDecorationTheme` (filled `surfaceContainerHigh`,
  radius 8, blue focus ring). **Dialogs** — lean on `dialogTheme` (radius 12,
  transparent tint). Don't hand-roll either with M3 defaults.
- **NavigationBar** — canvas floor, transparent tint, `surfaceContainerHigh`
  selection pill, `accent` glyph on the selected icon. Delegated entirely to the
  theme; never set inline nav colors.

---

## Do's and Don'ts

### Do
- Build hierarchy from **weight, size, and two-tier muting** before reaching for
  any color. Dim the loser to `onSurfaceVariant`; embolden the winner.
- Wrap every "thing" (row, group, panel) in the **flat-card recipe**
  (`surfaceContainerLow` + 1px `cardBorder` + radius 12, no shadow).
- Reserve **team color** for final results, as a low-alpha directional wash.
- Reserve **yellow** for the one primary action / selection / focus, via
  `BinanceColors.of(context).accent` (or `cs.primary` for the filled CTA).
- Route **every number** through `numStyle()` (IBM Plex tabular).
- Use the **canonical `_SectionHeader`** for every group title.
- Match the **score screen's exact spacing numbers** — 14 card padding, 12 card
  gutter, 16 text gutter / panel gap, 8 inter-card gap.

### Don't
- Don't use yellow to mark a winner/value a **score already carries** — use
  weight. Don't put yellow on a section header, a leading icon, or a divider.
- Don't hardcode `Color(0xFFFCD535)` (or `0xFF181A20`, etc.) — use the token.
- Don't use trading green/red as a **card/banner surface** or as generic
  success/error. They are up/down text/icon signals only.
- Don't leave a **bare `ListTile` or naked `DataTable`** on the scaffold floor —
  wrap it in the flat-card recipe.
- Don't use `FilledButton.tonal` for a primary action (the grey-CTA bug).
- Don't add a **shadow, an `elevation`, or an M3 surface tint** — depth is the
  surface step + hairline. Inline `Material` must set `surfaceTintColor:
  transparent`.
- Don't introduce **large/pill radii** (>12) or **display headlines** for group
  labels.
- Don't let a **4px spacing drift** stand — it's visible. Normalize to the scale.

---

## Lineage

This system is **derived from** a Binance trading-platform UI analysis — that's
where the near-black canvas, the flat-block + hairline elevation model, the
IBM-Plex-for-numbers split, and the original yellow accent came from. The full
source analysis has since been distilled into this document; the standalone
source dump was removed once the design stabilized.

The app has since evolved away from the source's *yellow-centric brand model*.
What survives is the **structure** (greyscale, flatness, hairlines, tabular
numbers, scarce accent). What changed is the **expressive layer**: a marketing
site sells with a brand color; a scores app should disappear and let the *teams'*
colors — and the score itself — be the only thing that's loud. Hence the demoted
yellow and the elevated team-color wash.

The code still carries the lineage in its names (`BinanceColors`, `_yellow`).
That naming is cosmetic; renaming it is optional and out of scope here.

## Open decisions

- **Yellow's fate.** This doc keeps yellow as the scarce *functional* accent
  (CTA / selection / focus). The alternative is removing it entirely in favor of
  a neutral interactive accent (e.g. `body-on-dark` for selection, ink CTAs) so
  the app is purely greyscale + team color. Kept yellow for now because it's a
  single recognizable "tap here" signal and preserves the existing theme
  infra — revisit if it still feels too loud once the spacing/consistency pass
  lands.
- **Team color, expanded.** The wash is currently final-cards-only. Candidate
  extensions (low-alpha, same discipline): the game-detail header, the favorite
  card. Decide per-surface; never make it a fill.
- **Two-gutter rule.** 16 text / 12 card is documented as intentional. If it
  ever reads as misalignment rather than breathing room, unify to a single 16
  gutter — but change it everywhere at once.
