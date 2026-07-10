# Broadcast Dark — the design spec

The brand system for the Scores app, distilled from the Claude Design exploration
(*Sports App Explorations.dc.html*, turns 1–10; the chosen direction is 1a's dark
palette + 1c's card grammar, merged in turn 2). This document is the reference an
agent should read **before building any screen**: it defines the tokens, the
grammar, and the per-sport flourishes so new screens can be assembled from the
system instead of designed from scratch.

Code mirror: `lib/src/theme.dart` (class `T`) holds these tokens as Dart
constants; `lib/src/ui/widgets.dart` holds the shared components. If this file
and `theme.dart` disagree, fix the drift — this file is the intent, `theme.dart`
is the implementation.

Units: the exploration is CSS px on a 428px-wide phone. Flutter logical pixels
map 1:1 — use the numbers as-is.

---

## 1. Principles

1. **Broadcast dark.** The app looks like a stadium scoreboard shot at night:
   near-black surfaces, white tabular numerals, one hot accent. Dark is the only
   theme; there is no light mode.
2. **Neutral chrome, team-color accents.** The UI itself is colorless. Team
   identity enters *only* as data-driven color: a vertical bar beside the name,
   a dot on a timeline, a fill in a bar chart. **Never a logo, never colored
   text.**
3. **One grammar, many sports.** Every screen type has a fixed anatomy. Only the
   *situation card* and the *row glyph* change shape per sport — and they
   dispatch on data presence (`hasBaseball`, `events`, `layout == 'field'`),
   never on sport name.
4. **Glanceable in two seconds.** Score and state read first (biggest, whitest);
   context second (dim); chrome last (faint). If an element doesn't help the
   2-second read, cut it.
5. **One loud moment per screen.** Exactly one inverted light card (LAST PLAY /
   LAST SHOT / RACE CALL) per screen. Everything else stays quiet so it can shout.

---

## 2. Color

### Surfaces

| Token (`T.`) | Hex | Use |
|---|---|---|
| `bg` | `#111318` | Page background |
| `surface` | `#1A1E25` | Cards, status-pill container |
| `sheet` | `#1D222A` | Bottom sheets |
| `navBg` | `#15181E` | Bottom nav bar |
| `track` | `#22272F` | Progress-bar tracks, empty bases, ball circles |
| `dragSurface` | `#242B36` | Lifted (mid-drag) row |

### Strokes

| Token | Hex | Use |
|---|---|---|
| `divider` | `#262C35` | 1px hairlines between rows inside a card |
| `border` | `#2A303A` | Chip outlines (1.5px), score-block rules (2px), inactive pips |
| `outline` | `#414A55` | Dashed "pending/empty" markers, empty diamond bases |
| `fieldLine` | `#232933` | Yard/period gridlines on `bg`-adjacent fields (use `#2C333D` when the field sits on a `track` fill) |
| `diamondLine` | `#333A44` | Baseball diamond basepaths |

### Text ramp

| Token | Hex | Use |
|---|---|---|
| `text` | `#EEF1F4` | Primary: winner's score/name, active values, page titles |
| `textDim` | `#9AA3AD` | Secondary: loser/trailing side, card labels, captions |
| `textFaint` | `#6C7480` | Tertiary: units, column headers, hints, timestamps |
| `textBody` | `#C8CFD6` | Play-feed prose (between primary and dim) |
| `ghost` | `#3D434D` | Below-faint: unplayed/inapplicable table cells (`–` innings). |

The winner/leader is always `text` weight 600–700; the loser/trailer is always
`textDim` regular weight. That asymmetry — not color — is how a result reads
at a glance.

### Accents

| Token | Hex | Use |
|---|---|---|
| `live` | `#E5484D` | Live dot, red cards, "10 MEN" badge, wickets, cut lines, losing streaks |
| `gold` | `#FFC52F` | Occupied bases, power-play badge, favorite star, first-down marker, leader rank, yellow cards, run callouts, WR-pace marker, current-hole ring |
| `green` | `#3FA96B` | Winning streaks, boundary balls (4/6), under-record pace, "+GB" safety |
| `underPar` | `#F26D6D` | Golf red numbers (under par) — softer than `live`, never used for alarm |
| `silver` | `#B9BFC7` | Silver medal counts |
| `bronze` | `#B07A4A` | Bronze medal counts |

One sport-local accent exists: **tennis-ball chartreuse `#C9E04A`** for the
serve dot and SET/BREAK POINT callout. Treat sport-local accents as rare and
deliberate — propose them only when the sport has an iconic physical color
(the tennis ball) and no existing accent fits.

### Muted glyph fills (high-frequency classification dots)

When a *wall* of colored glyphs classifies repeated micro-events (pitch
results, ball-by-ball outcomes), the loud accents would scream. Use the muted
pairs — dark fill + matching pale glyph text (18px circle, 9/700 letter):

| Meaning | Fill | Glyph text |
|---|---|---|
| Ball / safe / positive | `#2F6B3F` | `#C9E5CF` |
| Strike / out / negative | `#7A3038` | `#F0CDD1` |
| Foul / neutral / caution | `#6B5B2A` | `#EADFB8` |

The loud accents (`live`, `gold`, `green`) stay reserved for one-per-view
signal moments.

### Inverted card (the loud moment)

| Token | Hex |
|---|---|
| `invertedBg` | `#EEF1F4` |
| `invertedText` | `#111318` |
| `invertedLabel` | `#6C7480` |

### Team colors

Come from data (`FavoriteTeam.color` / competitor color), applied only to
**shapes**: bars, dots, pips, chart fills, badge chips. Never to text, never as
a card background. Washes derived from a team color use 7–8% alpha (see §7).
`util.dart` has the legibility helper if a team color needs adjusting against
`surface`.

---

## 3. Typography

Two voices, both bundled in `assets/fonts/`:

- **Barlow Condensed (600/700)** — the *scoreboard voice*. Team names, scores,
  clocks, ranks, stat numbers, section headers, page titles. **Always
  `tabularFigures`** so live numbers never shimmy.
- **Archivo (400–700)** — the *copy voice*. Labels, captions, prose, row text,
  buttons. It is the app-wide default; Barlow is opt-in per style.

The exploration's rejected light-editorial direction used Source Serif 4 — the
serif is **not** part of the brand; don't reintroduce it.

### Scale — scoreboard voice (Barlow Condensed, tabular)

| Style (`T.`) | Size/weight | Where |
|---|---|---|
| `blockScore` | 52/700 | Giant score block score |
| `blockName` | 40/700 | Giant score block team name; event title (THE OPEN CHAMPIONSHIP) |
| — | 44/700 | Cricket compound score (`168/6`) — one step down so it fits |
| — | 34/700 | Big clock (PP remaining, quarter clock) |
| `heroScore` | 32/700 | Hero favorite card score |
| `pageTitle` | 30/700 | Page titles: TODAY, STANDINGS, FOLLOWING |
| — | 26/700 | Compact scorebug abbrs on list-tab screens; big to-par total |
| `situationHead` / `statCallout` | 24/700 | Situation headline ("3RD & 4", "2–1 COUNT", "27 OFF 22"); stat callout ("CHC 68%") |
| `heroName` | 24/700 | Hero favorite card team abbr |
| — | 20–22/700 | Sub-callouts (OKC 9–2 RUN), tennis set digits, following-row abbrs |
| `bugScore` | 19/700 | Sticky scorebug `ABBR 4` |
| `rowScore` | 17/700 | Dense-row score; running score in event feeds (18) |
| `statLineStrong` | 16/700 | Top-performer stat line |
| `sectionTitle` | 16/700 +1.3ls | League section headers (MLB, WORLD CUP · ROUND OF 16) |
| `statLine` | 14/600 | Table numbers, batter lines, splits, time-rail minutes |
| — | 13/600–700 | Rank numbers, play-feed period tags (B7, Q3) |

### Scale — copy voice (Archivo)

| Style (`T.`) | Size/weight | Where |
|---|---|---|
| `invertedProse` | 17/600, lh 1.35 | The one loud sentence on the inverted card |
| — | 15/600 | Sheet titles, favorite-card team names when spelled out |
| `rowText` / `rowTextDim` | 14/600 · 14/400 | Dense-row team text (winner/loser), event titles |
| `listText` | 13.5/400 | Table row names (standings, leaderboards) |
| — | 13/400 | Chip labels, body copy, stat rows |
| `caption` | 12/400 | Venue lines, sub-descriptions |
| `cardLabel` | 12/600 +0.72ls | UPPERCASE card labels (WIN PROBABILITY, MATCH TIMELINE) |
| `captionFaint` | 11/400 | Sub-captions, footnotes |
| `cardLabelFaint` | 11/600 +0.66ls | UPPERCASE column headers, group labels (NL CENTRAL) |
| `pillText` | 11/600 +0.44ls | Status pill text (BOT 7 · 2 OUT) |
| — | 10/400–700 | Axis labels (KO · HT · 90′), tiny legends; 10/700 +0.1em for rule labels (HALF TIME · 1–1) |

### Rules

- Numbers that update live are **always** Barlow Condensed + tabular figures.
- UPPERCASE happens only in the label tier (10–12px, 600, letterspaced) and in
  Barlow display text (which is naturally set caps in the score block).
- Letter-spacing bands: pills 0.04em · badges 0.05em · labels 0.06em · section
  headers 0.08em · period-rule labels 0.1em. Body text is never letterspaced.

---

## 4. Spacing & shape

| Constant | Value |
|---|---|
| Page margin | 20 (both sides, everywhere) |
| Card radius | 20 (detail cards), 16 (dense feed/list cards, following rows) |
| Sheet radius | 24 top corners |
| Pill/chip radius | 999 (fully round) |
| Card padding | 18 (detail), 14–16 (compact cards), 12×14 (dense rows) |
| Card-to-card gap | 12 (14 for the first card after the chip nav) |
| Section header | 22 top / 6 bottom padding |
| Score-block row | 10 vertical padding, 2px bottom rule (`border`) |
| Chip nav | 8 gap; chips 8×16 pad (7×14 when pinned/condensed) |
| Bottom nav | 10 top / 8 bottom padding, 1px top `divider`, icons 22×22 |
| In-card row | 8–9 vertical padding, 1px `divider` between rows |
| Bottom of scroll | 28 margin after the last card |

These live as tokens in `theme.dart` (class `T`): `gapCard` (12), `gapFirstCard`
(14), `scrollBottom` (28), `chipGap` (8), `rowVPad` (9), `sectionHeaderPad`
(22/6), `chipPad`, `padCompact` (16×18), `padDenseRow` (12×14), `padTable`
(14×16). **Use the token, not a raw literal** — a hand-typed `18`/`22`/`12`
is how per-screen drift creeps back in. Padding pairs read `A×B` =
**horizontal×vertical** (e.g. `padTable` 14×16 = 14 sides / 16 top-bottom — the
tighter horizontal is deliberate, "tables need width").

Team color bar sizes (width×height, radius):

| Context | Bar |
|---|---|
| Giant score block | 12×44 r3 |
| Hero favorite card | 8×26 r2 |
| Compact scorebug | 8×22–30 r2 |
| Following row | 6×22 r2 |
| Dense league row / tables | 5×16 r2 |
| Race/lane rows | 6×16 r2 |

Elevation: essentially none. Cards are flat fills on `bg` — separation comes
from surface contrast, not shadow. The only shadows in the system: the bottom
sheet (`0 -12 40 rgba(0,0,0,.5)`) and a mid-drag row (`0 14 32 rgba(0,0,0,.55)`
plus ~1° rotation). Never shadow a resting card.

---

## 5. The card grammar (screen anatomies)

### Game detail (the hero screen)

Top to bottom — this order is fixed:

1. **Status pill row** — pill (live dot + phase, e.g. `BOT 7 · 2 OUT`) left,
   venue/context caption right.
2. **Giant score block** — one row per side: team bar (12×44) + Barlow 40 name +
   Barlow 52 score, 2px `border` rule under each row. Leader white, trailer dim.
   Possession/serve marker sits inline after the name (arrow glyph or serve dot).
   Badges (`POWER PLAY`, `10 MEN`) sit inline after the name too.
   *Field/athlete sports swap this for an **event block**: Barlow 40 event title
   + caption (e.g. THE OPEN CHAMPIONSHIP · "Moving day · wind 18 mph").*
3. **Chip nav** — horizontal pills. Active chip = inverted (`invertedBg` bg,
   `invertedText` text, 600). Inactive = 1.5px `border` outline, `textDim` text.
   Tab names are per-sport data, not per-sport code (Now/Plays/Box/Leaders,
   Now/Timeline/Stats/Lineups, Leaderboard/Following/Course/Tee times…). **Tabs
   are data-gated** — never render a chip for absent data. Golf shows
   `Leaderboard` always, plus a per-round chip (`R1 R2 R3 …`) for each round that
   has scores — a round chip swaps the leaderboard's middle column to that round's
   sub-scores; `Course` / `Tee times` appear only when the core feed carries them.
4. **Situation card** — the sport's flourish (§8). The only per-sport shape.
5. **Win probability card** — label + `statCallout` right; 12px two-segment
   rounded bar in team colors with a 2px gap. When the summary ships the
   full-game arc (`winProbability.points`, ≥2) the card grows a **scrubbable
   72px curve** between label and bar: home share up / away share down around
   a 50% `divider` centerline, the stroke wearing each side's color on its
   half, faint verticals at period changes. Hold/drag replays any moment —
   the callout % (gold while scrubbing), the split bar, and a reserved
   `caption` line (`2ND QUARTER 4:12 · LAL 50–48 BOS`) track the finger;
   release snaps back to now. No arc (predictor fallback) → the passive
   two-line card unchanged. On the generic Recap the card appears **only**
   with an arc (a foregone single 100% says nothing post-game).
6. **Inverted LAST PLAY card** — the loud moment (§7).
7. **Supporting cards** — scoring feed, top performers, drive log, serve stats…
   each a quiet `surface` card with an UPPERCASE `cardLabel`.

**On scroll** the score block collapses into a **sticky scorebug**: one line —
`bar + ABBR 4` pairs (Barlow 19), a mini glyph (mini diamond / possession arrow),
phase caption, live dot — with the chip nav pinned beneath (condensed chips).
`bg` background, 1px `divider` bottom border.

### Venue / Circuit tab

A data-gated chip appended to game detail's chip nav (`venueTabKind`, §2.9): a
stadium event with a venue join id gets **Venue**, a circuit-joined racing
event gets **Circuit**; neither → no chip added. Two shapes, same skeleton —
photo/map card → fact grid → a lifted `sheet` summary card:

- **Venue** (design 14a): 210px photo (or media-well placeholder) in a
  `divider`-bordered `surface` card, address caption below; fact grid of
  served cells only (Surface `GRASS`/`TURF`, Roof `INDOOR`/`OPEN AIR`,
  Attendance, Weather — the cheap fields render instantly, Surface/Roof
  upgrade from the lazy core venue-facts fetch); a `sheet` r20 **TONIGHT**
  card (weather line + Barlow 32 attendance figure) only when either exists.
- **Circuit** (design 13a): 180px track-diagram card with a
  direction/established footer; fact grid (Circuit length, Race distance,
  Laps, Turns) entirely from the lazy circuit-facts core fetch (F1 only —
  other racing has no such resource, so the tab is placeholders); a `sheet`
  r20 **LAP RECORD** card (headshot + Barlow 32 time + driver/year) only when
  a fastest lap is served.

Every cell/card that ESPN doesn't serve is omitted, never rendered empty
(§11.8).

### Team & player overview

The shared overview grammar (design 11a–11e) behind both the team page and
the player page — identity header, one contextual card, then data-gated
modules:

- **Identity header**: 80px (team) / 92px (player) logo avatar (dark logo,
  falling back to color-tinted initials) + Barlow 34/30 stacked name (2 lines
  max) + a `color` dot + middot-joined caption (record · standing, or
  jersey · position · team). A trailing gold star toggles favorite (team page
  only).
- **NEXT GAME / NEXT FIXTURE card**: label + kickoff time, a bar-vs-bar
  matchup row (8×26 bars, Barlow 22, trailing side dim), then a venue chip +
  exactly ONE contextual chip (odds → weather → note headline, in that
  order — never more than one).
- **FORM / LAST 5 card**: up to five `green`/`live`/dim W-L(-D) pills over a
  caption (`Won 4 of 5` for win-only sports, `10 pts / 5` for draws-capable) —
  sourced from the competitor's served `form` string when present, else
  derived from the last five completed results.
- **Team leaders card**: per-category season leaders, tappable rows → the
  athlete's player page.
- **Per-game stat grid** (player, 11e): 4-column grid, Barlow 26 values over
  faint letterspaced labels — the stat set is a cross-sport priority list,
  never a per-sport branch.

An identity-only profile (stats/games not yet resolved) renders the header
and nothing else — never a placeholder card.

### Home feed (TODAY)

1. Header: `pageTitle` "TODAY" + date caption; two 36px circle icon buttons right.
2. **Stacked favorite hero cards** — every favorite gets a full-width card
   (radius 20, padding 16×18, 1px `divider` border). Detail scales with state:
   - **Live**: status line (dot + `CUBS · BOT 7`) → abbr+score rows → sport
     glyph on the right (mini diamond, PP badge…) → footer strip under a
     hairline: one-line situation + win-prob micro-bar (64×5) or series pips.
   - **Upcoming**: single compact row — matchup + time + one context line
     ("Winner faces FRA/ESP"). No glyph.
   - **Final**: compact like upcoming; winner white, loser dim, `Final` caption.
3. **BIG GAMES** (occasional) — one `sectionTitle` header + one radius-16 card
   of dense rows for today's marquee games from flagship leagues the user does
   NOT follow (their own leagues already have sections). Membership is
   data-presence rules (`lib/src/marquee.dart`): a playoff series, a postseason
   slate, finals/championship copy, a ranked-vs-ranked matchup, a golf major —
   never league name. Each row is the standard dense row with one extra
   `cardLabelFaint` tag line naming its league/stakes (`NBA · WEST FINALS`).
   Qualification is now-anchored: only games on today/yesterday (or live right
   now — multi-day field events) count, because ESPN's offseason scoreboards
   replay the last played slate for months (the April championship must not
   resurface in July). Capped at 3; on an ordinary day the section does not
   exist — that absence is the restraint.
4. **League sections** — `sectionTitle` header (+ optional faint action right:
   "See all 15") over one radius-16 card of dense rows separated by hairlines.
5. **Foot row** — a quiet surface-card row ("All games today" + chevron) into
   the all-games page: every league on today, followed or not, one home-feed
   league section per league (live leagues first). A plain surface row, not
   the gold/dashed hint treatment — it's a standing destination, not a
   "nothing here" nudge. Today-only (like the hero cards).

**Dense row anatomy**: left = two stacked team lines (5×16 bar, 14px name,
Barlow 17 score, possession arrow if relevant); right = status stack (live dot +
phase 12px over one faint context line 11px — `2 out · 2–1`, `3rd & 4 · OU 22`,
`NED down to 10`). A row may hang one glyph strip below it (drive field bar,
series pips) inside the same row card. An optional `cardLabelFaint` tag line
above the body (BIG GAMES rows) is the one sanctioned addition.

### Standings / tables

League chips (same chip pattern) → optional sub-tabs (underline style: 2px gold
underline on active, dim text inactive) → one card per group. Tables are CSS-grid
rows: `cardLabelFaint` column headers, `listText` names, Barlow 14 numbers.
Favorite row gets the gold wash + ★. Streaks: `green` W / `live` L. Playoff cut
line: dashed rule label row (§7). Racing championships and golf leaderboards
reuse this table pattern with rank + athlete rows. The full dense-table grammar
(key-stat column, section rows, semantic cells) lives in §10.

Conference leagues add a **Division / Wild Card / League** underlined-tab
toggle (§8a) above the tables — same underline style as the sub-tabs above,
gold active / dim inactive. **Division** (default) is the group-table view
above; **Wild Card** re-ranks one conference flat in standing order with a
single dashed-`live` **PLAYOFF LINE** divider drawn after the cut and a
games-from-the-line GB column (`+N` `green` above the line, `N` dim below,
the last team in reads an em-dash); **League** flattens every group into one
ranked table. The toggle appears only when a league's standings carry a
conference structure — single-table leagues (soccer) never show it.

### Following / management lists

Header: `pageTitle` "FOLLOWING" + a 36px circle **+** button (opens Explore —
the one discoverable add affordance) + a faint "Drag to set the order of your
home feed" caption. **Long-press-anywhere stays the primary add grammar** —
there is no per-row add button. Two sections, **Teams** then **Leagues**
(`cardLabel` header each, shown only when non-empty) — the stored order IS
the home feed's section order. Radius-16 row cards, 8 gap. Row: minus circle
(22px, `border` bg, `live` glyph) + team bar + name/league + trailing drag
handle (three 16×2 lines, `outline`; `textDim` when active). Drop target =
1.5px dashed `border` empty slot. Dragged row = `dragSurface`, shadow, slight
rotation. Footer hint card = dashed border, centered faint caption
("Long-press any team or league in the app to add it here").

### Bottom sheet (long-press follow)

`sheet` bg, 24 top radius, 36×4 grab handle (`outline`). Header row: 44px circle
avatar (dark team-tinted bg + 2px team-color ring + Barlow abbr) + name/record.
Action rows separated by hairlines: 22px leading glyph (gold ★ for the primary
action) + title + faint description.

### Event list / plays tab

Compact scorebug at top (bars 8×30, Barlow 26 abbrs, Barlow 30 combined score
between them, leader white / trailer dim, status pill right — it starts compact,
no collapse) → chip nav → optional filter control → the feed. The feed's shape
is **chosen per sport by the event-feed framework in §9**: four archetypes
(sparse timeline / grouped episodes / scoring episodes / dense play-by-play)
selected by event density, container structure, and the sport's signal event.

### Tournament shell + bracket grammars

One constant shell — crest + title + chip strip — whose body swaps between
four grammars purely on DATA PRESENCE, never tournament name:

- **12a — groups + knockout scroller**: a table per group (rank, P, GD, PTS)
  with a **dashed green cut-line** drawn after the qualifying rank — distinct
  from §7's dashed-`live` cut line: this one marks advancement, not
  elimination, and carries no label — plus a legend of distinct qualification
  bands below the table (the note-band pattern, §10); a horizontal knockout
  scroller beneath, one column per round, each a stack of matchup cards, the
  final round's label picked out in `gold`.
- **12b / 12c — single-elim draw / seeded region bracket**: the same
  round-column scroller, with a region-chip strip (12c) filtering to one
  bracket when the field has named regions — a seed column and region tag
  render only when the data carries seeds/regions.
- **12d — pools + championship series**: a `W–L` + `STATUS` table per pool
  (`ADVANCES` green / `OUT` `live` / `ALIVE` dim), plus a gold-outlined
  championship SERIES card — bar-vs-bar matchup, win count, and a row of
  per-game result chips (scoreline or date, the winner's abbr picked out).

The matchup card is the shared unit across 12a–12c: two competitor rows, a
seed column when seeds exist, set/game scores when sets exist, else a plain
score or start date.

---

## 6. Component states

- **Chips**: active = inverted; inactive = outline + dim. Never a colored chip.
- **Pills (status)**: `surface` bg on the page; borderless dot+text when inside
  a card header.
- **Badges**: tiny 10/700 letterspaced chips, 4px radius, 2×6 padding. Gold bg +
  `invertedText` for advantage (`POWER PLAY`, `PP 1:24`); `live` bg + white for
  alarm (`10 MEN`); team-color bg + 1px `border` for score-type chips (TD/FG).
- **Tinted signal pills** (inline in feed rows and dividers): 10/700 +0.05em,
  r999, 1×7 padding; bg = the signal's color at ~20–25% alpha composited on
  `surface`; text white, or the signal color's pale tint for a softer read
  (`BREAK` = `#1C3A2A`/`#8FD6AE` or `#3D2A1A`/`#E8B48C` by player color).
  Team color for `LEAD`, gold for `SET POINT` / `SAFETY CAR` (`#3D3517` + white).
  The same recipe makes **team-tinted avatars**: 38px circle (or 44px r12
  square on a team page header, solid team color there), Barlow initials/abbr.
- **Semantic rank chips** (tinted-pill recipe, colored by *goodness*, not
  value): good third = green pair `#1C3A2A`/`#8FD6AE`; middle = neutral
  `#2A303A`/`textDim`; bottom third = red pair `#3D2024`/`#E8A0A6`. A 24th-rank
  turnover number is red even though the number is small — the chip judges,
  the number reports.
- **NOW pill**: the quietest live marker — 9/700, `track` bg, `textDim` text,
  inline after a table name (the pitcher currently in the game). Use where a
  gold wash would be too loud.
- **Toggles/segmented**: container `surface` r12 p4; active segment `border` fill
  r9, 12.5/600; inactive `textDim`.
- **Icon buttons**: 36px circle, `surface` fill.
- **Bottom nav**: 3 items, icon + 11px label; active = white icon + 600 label,
  inactive = `border`-colored icon + faint label.

---

## 7. Signature moves (brand-level delighters)

These recur on every screen and are what makes the app feel like itself:

1. **The inverted card.** One per screen, `invertedBg`, carrying the freshest
   narrative line (LAST PLAY / LAST EVENT / LAST BALL / LAST SHOT / RACE CALL).
   `invertedLabel` UPPERCASE label + 17/600 Archivo prose. It is the only light
   surface in the app.
2. **Team-color wash for "you are here".** Highlighted rows (favorite team, the
   followed golfer, the at-bat batter, a goal row) get
   `linear-gradient(90deg, rgba(<color>, .07–.08), transparent)` and bleed
   edge-to-edge (negative margin to the card edge, padding restored). Gold wash
   = favorite; team-color wash = that team's moment.
3. **Dashed = not yet.** Anything pending, empty, or upcoming is a 1.5px dashed
   `outline` shape: the missing skater in 5v4 dots, balls remaining this over,
   the un-clinched series pip, the drop slot mid-drag, the current golf hole
   (dashed **gold** ring — in progress, not empty). Solid = happened.
4. **The cut line.** Qualification boundaries are a 2px dashed `live` rule with
   a centered 10/700 letterspaced label (PLAYOFF LINE). Same pattern in dim
   (`border` + `textFaint`) marks period breaks in feeds (HALF TIME · 1–1,
   KICKOFF · 4:00 PM).
5. **Running score after every scoring event** — Barlow 18/700 tabular at the
   row's right edge; current/latest is white, older ones dim. (Dense feeds
   invert this: a faint score on *every* row, turning white only at lead
   changes — see §9.)
6. **Live dot.** 6–7px `live` circle; precedes every live phase text. The dot,
   not the word "LIVE", is the signal (pill text may still say LIVE for events).
7. **Middot microcopy.** Context lines are terse fragments joined by ` · `:
   `Suzuki up · 2–1 · 2 out`, `Game 6 · DAL leads 3–2`, `Par 5 · 547 yds ·
   2nd shot, 231 to the pin`. Soccer minutes use the prime (73′), scores the
   en-dash (2–1), prose the em-dash ("Happ singles to right — Hoerner scores").
   Numerals over words, always.

---

## 8. Sport delighters — the situation-card & glyph catalog

Per principle 3: the *shape* below is chosen by **data presence**, never sport
name (`situation.hasBaseball` → the duel, `hasGridiron` → drive field,
`competition.events` → timeline, cricket target → chase, `layout == 'field'` →
leaderboard). Reuse these; when a new sport appears, compose a new one from the
same vocabulary (§11 checklist).

### Home-feed hero card — the three-body rule

Every favorite's stacked hero card (§5 Home feed) picks exactly one of three
bodies by game state — never a fourth: **Live** (status line + live dot →
two score rows, 8×26 bars, Barlow 24 name / 32 score, trailing side dim →
a footer glance line), **Final** (the same score rows, no live dot, a
`Final` status caption), **Scheduled** (compact: one row, mini 6×18 bars,
`vs`/`@` between abbrs, start time + at most one broadcast line — no sport
glyph). Detail scales down with certainty: Live carries the full treatment
(sport glyph, badges, footer), Scheduled carries almost none.

The footer (Live/Final only) hangs one of two mutually exclusive glances,
series pips taking priority: **series pips** (below, "Playoff series") when
the competition is a live/decided series, else a **win-probability
micro-bar** — a 64×5 two-team-color bar (the §5 game-detail win-prob card's
recipe, hero-scaled down) + a Barlow 13 percentage for the favored side,
shown only when the cheap scoreboard carries a win pct (basketball, by data
presence — never a sport-name check). A man-advantage badge (gold `PP` chip,
or a `live`-red `10 MEN`/`N MEN` chip) rides inline after a side's name in
the Live body — the §6 tinted-badge recipe at hero-card scale.

### Baseball — the duel, the zone, the strip (LiveGame turn 8)
- **Situation card — the duel**: pitcher and batter face off — left `PITCHING`
  / right `AT BAT` (`cardLabelFaint` role, `rowText` name, dim Barlow day-line
  `1.2 IP · 2 H · 0 ER` / `1-1, .318 AVG`), a faint `VS` between; below a
  hairline, the count as three spread dot groups (10px: balls `green`,
  strikes + outs `live`); a quiet footer row (`Pitch count 40` — rich live
  at-bat only — and `On deck · B. Lowe` from the cheap `situation.onDeck`).
  Every element data-gated; the card renders duel-less (count only) pre-pitch.
- **Due Up card (between innings)**: when ESPN drops the batter/pitcher and
  `situation.dueUp` lists the NEXT half's batters (`situation.isDueUp` — data
  presence, never sport name), the duel yields to `DUE UP` — label row with the
  faint between-innings beat (`Mid 5th`, cheap `status.shortDetail`), then up
  to three rows: faint index, batter name (`rowText`), right-aligned dim day
  line (`1-3, K`). Below a hairline, the previous half's story: faint caption
  `TOP 5TH · PIT` + one line — the on-device AI sentence when the device
  carries a local model (Gemini Nano via `scores/recap`; cached one inference
  per half-inning), else the deterministic line computed from the rich at-bats
  (`three up, three down` / `two runs on three hits, one stranded`; `inning_recap.dart`). The
  zone/bases card is suppressed between innings (an empty diamond says
  nothing); no recap data → batters only.
- **Strike zone + bases card**: the plot renders ONLY when the live at-bat's
  pitches carry ESPN's zone coords (live feeds only — the turn-8 degrade rule:
  plain outline + numbered markers, no heat; hide the zone without locations).
  150×170 `track` panel, zone outline (16%/14% inset, 1.5px white-55) that the
  EMPIRICAL data zone maps onto — ESPN's plot space is non-isotropic, zone
  x∈[~84,148] / y∈[~144,193] fitted from a full slate of called strikes and
  cross-checked against ESPN's gamecast plot (markers beyond it clamp inside
  the panel, so a ball in the dirt reads "below the zone") — 22px numbered
  markers colored by pitch result (`green` ball / `live` strike / `textFaint`
  foul / `gold` in play, 2px `surface` ring), numbers keyed to the pitch strip. Right column: the SVG diamond (viewBox
  `0 0 128 112`; basepaths 3px `diamondLine`; bases = 18×18 r3 rects rotated
  45°; occupied `gold`, empty `track` + 2.5px `outline` stroke) over 1B/2B/3B
  rows — resolved runner names (`rowText` 13) or `on base`/`empty` captions.
- **Pitch strip**: a horizontally scrollable row of 96px radius-16 `surface`
  chips, LATEST FIRST — numbered result dot, the pitch outcome (`Strike 2
  Foul`), faint pitch name + `91 mph`.
- **ABS challenge (`Pitch.challenge`)**: one loud moment, quiet everywhere
  else. The pitch's dot/count already carry the FINAL ruling (ESPN's type.text
  leads with it), so the marker only says "this call was challenged": the strip
  chip and the All-plays pitch row gain a terse lowercase suffix — `overturned`
  in the caution muted-pair pale `#EADFB8` (an officiating flip, not scoring —
  never gold), `upheld` plain `textFaint`; the last-play card appends the prose
  (`· call overturned` / `· challenge upheld`) — that inverted card IS the
  challenge's loud moment. The zone plot is deliberately unchanged (its marker
  color is already the truth). No situation-card badge (per-pitch history, not
  current state), no challenges-remaining counter (ESPN doesn't serve it).
- **Last play — the loud moment**: the inverted card reads the summary's
  DERIVED `lastPlay` first (kind `pitch` → label `LAST PITCH`, prose `Strike 2
  Foul — Cutter, 89 mph`; kind `play` → `LAST PLAY`, the real at-bat result or
  `End of the 3rd inning` — never ESPN's "Now at bat" bookend), falling back
  to the cheap situation text.
- **Glance glyph**: mini diamond (viewBox `0 0 26 22`, three 7×7 r1.5 rotated
  rects) — in rows and the collapsed scorebug. Phase text `Bot 7`.
- **Feed**: archetype B by half-inning (§9); stat strip `412 FT · 104.6 MPH ·
  2 OUT`. *All plays* is the designed disclosure mode (§9): condensed at-bat
  rows (4px tick, `Happ strikes out swinging`, faint `5 P` pitch count,
  chevron) expanding in place to the pitch sequence — 18px muted-fill B/S/F
  dots (§2) + description + velocity, indented behind a 1px rail; the live
  at-bat sits pre-expanded in a `track` inset card with its current count.
- **Detail organization (the baseball reorg)**: an innings sport (dispatch:
  `periods.unit == 'inning'`, never sport name) keeps exactly THREE tabs —
  **Now/Recap · Box · Plays** (no Leaders, no Venue chip; that story moves onto
  the first page). The first page is deliberately redundant with the deep tabs —
  check-a-score-and-leave, everything one scroll away:
  - **Now (live)**: the at-bat story (duel → zone/bases → pitch strip → the
    loud LAST PLAY) → scoring summary (line score + the half-inning feed in
    CHRONOLOGICAL order, "scores starting in the first" — the one designed
    exception to §9's newest-first; the Plays tab keeps newest-first) → a quiet
    "Full play-by-play" foot-row link into the Plays tab → the team-tabbed box
    → win probability → HITTING / PITCHING game-stat cards (`teamGameStats`) →
    key absences → season series → game info → CURRENT WEATHER (cheap
    `event.weather`, absent indoors).
  - **Recap (final)**: line score → **DECISION** card (`summary.decisions`:
    W green / L live / SV gold tinted chips + record, rows tap to the player
    page) → chronological scoring summary → the same deep-dive tail (link, box,
    win prob, stats, injuries, series, venue — no weather).
  - **Plays**: line score + DECISION on top of the §9 Scoring|All disclosure feed.
- **Box tab** (§10, designed): line score by inning — scoring innings white,
  zeros dim, unplayed `–` in `ghost`, current inning a `track` chip with `•`,
  R/H/E columns with R highlighted — then the DECISION card, a **team scope
  toggle** (away | home segmented control) over that side's batting/pitching
  tables (H and K the key columns, position tags inline, NOW pill on the active
  pitcher), the selected team's **newspaper agate block** (`teamDetails`:
  BATTING/PITCHING/FIELDING/BASERUNNING sections of `2B: Vierling (12, Lopez)` /
  `Team LOB: 7` / RISP lines — §10's footer-summary voice as a card), the
  chronological scoring summary, and the game-info footer. **Width rule:** the
  nine inning columns flex to fill the card (`44px label + 9×1fr + R/H/E fixed`),
  so a 9-inning grid never leaves dead space. Extra innings first *shrink* the
  cells toward an ~18px floor, then the innings pane *alone* scrolls
  horizontally — the label column and R/H/E stay pinned.

### Football (gridiron) — the drive field
- **Situation card**: down-&-distance headline (`3RD & 4`) + spot caption; field
  = 56px r8 `#161A20` strip, 10 gridline segments (`fieldLine`), end zone tinted
  in defense color at 50% alpha, drive extent tinted in offense color at ~22%
  alpha, 3px scrimmage line in team color, 2px first-down marker in `gold`;
  footer: drive stats left, gold "4 yds to the sticks" right.
- **Glance glyph**: a 14px-tall version of the same field bar hangs under the
  row (fill alpha .28). Possession arrow (SVG `M8 5L0 0v10z`) after the abbr.
- **Feed grouping**: scoring by quarter; TD/FG chip = 34×24 r6 team-color fill +
  1px `border`, Barlow 12/700.
- **Stats tab** (§10, designed): center-spine mirrored team-color bars per
  stat (total/passing/rushing yards, 3rd down, turnovers, penalties,
  possession), team-colored legend header, key-players QB-duel strip.

### Basketball — clock & run
- **Situation card**: big clock (Barlow 34) + quarter label left; `gold` run
  callout right (`OKC 9–2 RUN` / "last 2:40") derived from the summary's
  running scores (`lead_story.dart`: the window extends back while the answer
  stays ≤4 pts, qualifies at ≥6 for and 3× the answer). A run won't always be
  on — the slot degrades to a quiet white tidbit for a back-and-forth game
  (`14 LEAD CHANGES` / `TIED 6 TIMES` / a second-half `WIRE TO WIRE`), else
  stays empty and the clock stands alone. Footer row: bonus flag (`gold` text
  when in bonus) + timeout dots (7px, team color, remaining only — ESPN's core
  situation carries no used total, and no possession/shot clock either, so the
  design's possession slot is unsourced and omitted).
- **Lead tracker card**: 64px polyline (2.5px team-color stroke, endpoint dot),
  centerline 1px `divider`, Q1–Q4 axis labels 10px faint; header right = the
  leader's margin (`OKC +4` — the run callout lives on the situation card).
- **Glance**: possession arrow after abbr; series pips row when playoff.
- **Feed**: archetype D dense play-by-play (§9) — one-line rows, persistent
  score column, LEAD badge on lead changes, quarter filter.
- **Box / Leaders tabs** (§10, designed): box score with STARTERS/BENCH
  sections, PTS as the key column, signed +/− cells, team switch, shooting
  footer line; Leaders = head-to-head category cards with gap bars and
  team-tinted initial avatars. Team page = stat tiles with semantic rank
  chips + player-averages table (PPG key column).

### Hockey — the power play
- **Situation card**: `POWER PLAY` headline in `gold` + penalty caption; right:
  Barlow 34 countdown + REMAINING label; 8px gold progress bar on `track`;
  footer: skater dots (11px team-color circles, the missing man dashed
  `outline`) around Barlow `5 v 4`, shots-this-PP caption right.
- **Shots pressure card**: per-team 10px rounded bars in team colors on `track`,
  Barlow totals right; goalie SV% footer under a hairline.
- **Glance**: `PP 1:24` gold badge inline after the abbr.

### Soccer — the match timeline
- **Situation card**: MATCH TIMELINE label + white minute right; horizontal rail
  (4px `track`, elapsed portion `#3A4250`), HT tick at 50%, event markers placed
  by minute — goals 18px team-color dots with 2px `bg` ring, cards 10×14 r2
  rects (`gold`/`live`), now-marker 2.5px white; KO/HT/90′ axis. Recent-event
  rows below a hairline.
- **The deep soccer detail (LiveGame turns 9–10)** — activates when the summary
  ships the deep modules (`commentary`/`matchLeaders` — data presence, never
  sport name); the tab set becomes **Now · Live pitch (live only) · Commentary ·
  Lineups · Stats** and Box/Leaders retire (player tables move onto Lineups,
  team stats + shot map onto Stats, the leaders read onto Now). All pitch
  surfaces use the one sanctioned sport-local surface, **pitch green `#15231B`**
  with `rgba(238,241,244,.14)` lines (iconic physical color, like the tennis
  ball). Pitch coords are team-relative (x 0 = own goal, 100 = opponent goal):
  home plots attacking RIGHT, away mirrors both axes.
  - **Momentum card (9a)**: attacking pressure per minute — home bars above a
    2px `outline` midline, away below, team-color fills, HT tick + a `border`
    now-marker while live, KO/HT/FT faint axis. Derived from the core match
    feed (`momentum.dart`: shots 1.0, corners 0.5, deep open play ≤0.4,
    normalized to the loudest minute); absent feed → absent card.
  - **Commentary**: the Now tab previews the freshest three lines (minute chip
    34×26 r6 `track` + Barlow 14/700, prose 13/1.55 `textBody`, oldest row dim)
    over a quiet 'Full commentary' foot link; the Commentary tab is the full
    curated feed newest-first with dim rule-label dividers at half boundaries.
  - **Match leaders (9a)**: one row per served category (total shots / accurate
    passes / defensive interventions / saves) — 36px team-tinted avatar, name +
    `FRA · FW` caption, Barlow 22 value over a 10px letterspaced category label;
    the overall leader across sides (compare numeric values). Rows tap to the
    player page; 'Full player stats' foot link jumps to Lineups.
  - **Live pitch (10a, live only)**: LIVE PITCH label + a `track` possession
    chip (8px side-color dot + `FRA POSSESSION · OPEN PLAY`/restart label);
    horizontal pitch with the trailing possession sequence as a fading
    team-color trail (opacity .3→.95, 4px waypoint dots), the ball a white
    dot + ring with the holder's surname label, an `ABBR attacking →` caption;
    footer: `N passes this sequence` + `ball in MAR half · 22 yds out`. Below,
    a quiet **LAST TOUCH** card (17/600 prose — shots keep ESPN's sentence,
    ordinary touches read `Player — type`) and **RECENT STOPPAGES** (last three
    restarts: minute chip, `Throw-in · France`, taker name faint right).
  - **Formation pitch (9b)**: FORMATIONS & LINEUPS card with a per-side
    segmented toggle (`FRA · 4-2-3-1`); vertical pitch, GK bottom (32px
    `outline` circle), outfield rows defense→attack upward, 32px team-color
    jersey-number circles + 10.5px surname below. Renders ONLY when a side's
    starters all carry `formationPlace`; the plain lineup lists remain the
    reference below, then the per-player box tables.
  - **Shot map (9b)**: outcome legend chips (only outcomes present — Goal
    `green` / Save `gold` / Off target `textDim` ring / Block `live`), shots
    plotted at their spots (selected = enlarged, white ring + halo + the
    trajectory line to the end coords), tap = nearest-dot hit test; a `track`
    r14 detail inset — jersey circle, name + side·pos, outcome·minute in the
    outcome color, `‹ N of M ›` pager, and a DISTANCE / SHOT TYPE / SITUATION
    cell row (distance computed from coords; technique/situation parsed from
    the prose). **No xG cells — ESPN serves none** (§11.8: omit, never empty).
- **Score block extras**: `10 MEN` red badge; aggregate/pens in dim parens after
  the score (`1 (4)`).
- **Stats card**: possession split bar (two team-color segments, 2px gap) +
  SHOTS/xG/CORNERS rows (Barlow numbers flanking a faint centered label).
  **The bar rule** (applies everywhere stats compare): a bar compares two sides
  of *one whole* — a possession split, a share-of-total. Independent per-team
  values — counts, averages, and percents like FG% / SV% / faceoff% — render as
  **number rows** (leader value white 600 in a fixed column, centered faint
  letterspaced label, trailer dim), never as bars or mirrored half-gauges. The
  only bars beyond the share split are the §10 center-spine mirrored bars, which
  are the team-stats comparison card alone.
- **Feed glyphs** (time-rail): goal = filled team dot (+GOAL row gets the team
  wash); yellow/red card = small rect; sub = `track` circle with team ring;
  VAR = outlined square.
- **Glance**: minute with prime (73′), red-card rect + "NED down to 10" caption.

### Tennis — the set grid
- **Score block variant**: grid — name + serve dot (9px `#C9E04A`) | one Barlow
  22 column per set (won = white, lost = faint, current = white) | current game
  points Barlow 26 (server's in ball-chartreuse).
- **Situation card**: `SET POINT` headline in `#C9E04A` + serving caption;
  right: 52px `track` circle holding a 16px ball-color dot; footer: THIS GAME
  point dots (8px, colored by point winner), BREAKS · SET 3, MATCH TIME.
- **Stats**: ACES / 1ST SERVE / BREAK POINTS / WINNERS rows, names as
  `cardLabelFaint` header row.
- **Feed**: archetype B with sets as containers (§9) — game rows (`Alcaraz
  breaks to 15` / `Sinner holds to 30`, 5×15 spine bar in the game winner's
  color, running games score right), BREAK tinted badges, the live set
  outlined with a white `SET 3 · LIVE` header, finished sets dim with result +
  duration (`SET 2 · SINNER 7–6 (7–4)` · `58 MIN`), stale sets collapsed to
  their header. Scorebug shows sets won (`1–1`), current set in the pill.

### Volleyball — the rally log
- **Feed** (the designed surface): archetype D with the merged rally-score
  rail (§9) — `24–22` rail (Barlow 14/600, white on signal rows), 4px team
  tick, one-line rally results (`Lucarelli cross-court kill`, `Michieletto
  service ace, deep line`), gold-tinted `SET POINT` badge, set filter, timeout
  dividers carrying the score (`ITALY TIMEOUT · 22–21`).
- **Scorebug**: sets won as the score (`BRA 2–1 ITA`), current set in the pill
  (`SET 4`).
- **Situation card / glance** (not yet designed): derive from the tennis set
  grid + the set-point callout vocabulary — set dots, serving-team marker,
  current set score as the headline.

### Cricket — the chase
- **Score block variant**: compound scores Barlow 44 (`168/6`), overs (`16.2`)
  as Barlow 18 dim beside the batting side's score.
- **Situation card**: chase equation headline (`27 OFF 22`) + rates caption
  (`req. 7.36 · current 8.69`); THIS OVER ball row — 28px circles: dot ball
  `track`+dim numeral, boundary `green`+dark numeral, wicket `live`+white W,
  remaining dashed `outline`.
- **Crease card**: batter rows with `*` for on strike, Barlow `58 (39) · 148.7`
  stat lines; bowler row with figures `3.2–0–24–2`.

### Golf — circle & square
- **Event block** (no team rows): tournament title Barlow 40 + narrative caption.
- **Leaderboard table**: rank (leader `gold`), name + faint country, TODAY and
  TOTAL in **`underPar` red for under par** (E/over stay dim), THRU column
  (`F` = finished). Followed player = gold wash + "following" tag.
- **Hole-by-hole strip**: 30px cells — birdie = 1.5px `underPar` circle ring,
  bogey = 1.5px `textFaint` square ring, eagle = double circle ◎, par = bare
  numeral, current hole = dashed `gold` ring with the hole number in gold.
  Legend inline in the label: `○ birdie · □ bogey · ◎ eagle`.

### Racing / Olympics — lanes & pace
- **Event block**: event title Barlow 40 (`MEN'S 200M FREESTYLE`) + phase pill
  (`LIVE · LAP 3 OF 4`).
- **Situation card**: ranked lane rows — rank (leader gold), lane label faint,
  country-color bar, name + faint country code, leader's split then `+0.31`
  gaps (Barlow tabular).
- **Record pace card**: label + `green` callout (`0.28 UNDER WR`); 12px bar,
  `green` fill vs a 2.5px `gold` WR marker line; faint axis captions.
- **Medal table rows**: country bar + name + gold/silver/bronze counts colored
  `gold`/`silver`/`bronze`.
- **Feed** (motorsport, designed): archetype A on a lap rail (§9) — `L 46`
  rail, driver-team-colored glyphs (filled dot = pass, team ring = pit stop /
  fastest lap, faint ring = incident), signal rows washed for passes
  (`Verstappen passes Norris — LEAD`), flag-phase dividers with status
  swatches (`GREEN FLAG · LAP 41`; safety car elevates to a gold-tinted pill).
  Scorebug = leader + gap (`VER +2.8s NOR`), lap count in the pill.

### Playoff series (any sport)
- **Series pips**: 8px circles, one per game, filled in the *winner's* team
  color; unplayed = 1.5px `outline` ring. Caption: `GAME 6` label + `OKC leads
  3–2 · can clinch`.

### Not yet designed (derive from the vocabulary above)
- **F1/motorsport situation card**: lap counter, gaps, pit/tyre status → event
  block + lane rows + a pit badge (gold badge pattern). The race-log *feed* is
  designed — see the racing Feed entry above.
- **Combat sports**: round scorecards → grouped cards per round (feed-group
  pattern) + judge table (table pattern).
- **Volleyball situation card / glance** — see the volleyball entry above.

---

## 9. Event feeds — organizing scoring & key events for any sport

The Plays/Timeline tab is where sports differ most, so it gets its own
framework. Eight treatments are designed (exploration turn 9: soccer, baseball
scoring + all-plays, football, basketball, volleyball, tennis, racing) and they
span the whole decision space — **classify a sport by answering three
questions, then build the matching archetype**. Don't invent a fifth shape; if
a sport seems to need one, it's almost always a composition of these (see
*Composing*, below).

### The three questions

1. **How often does something noteworthy happen?**
   Count key events per match. **≲20** → every event earns a full two-line row
   (A). **20–60, or bursty** → group them into containers and default-filter to
   scoring (B/C). **≳60, seconds apart** → one-line rows with a persistent
   score column; only state changes get loud (D).
2. **Does the sport have a native container between match and event?**
   Half-inning, over, drive, quarter, round, end, set, game, hole. **Yes** →
   one card per container (B/C). **No — play just flows on a clock** → a
   continuous rail (A/D).
3. **What is the signal event?**
   Pick exactly ONE loud row type per sport: the goal (A), the scoring play
   (B), the scoring drive (C), the lead change (D). It gets the team wash, the
   white running score, and (if any) the badge/chip. Everything else stays
   quiet. If everything is highlighted, nothing is.

### Archetype A — sparse timeline *(designed: soccer, racing)*

Continuous-clock sports where every key event deserves a full row.

- One `surface` card (r20, padding 6×18), rows newest-first, hairline
  `divider` between.
- Row: **time rail** column (Barlow 14/600, dim, ~32 wide) → **event glyph**
  (the sport's vocabulary: goal = 16px filled team-color dot; card = 11×15 r2
  rect in `gold`/`live`; sub = 14px `track` circle with 2px team ring; VAR =
  14px outlined square) → two-line body (title 14/600, detail 12 dim).
- **Signal rows** (goals): title 14/700 (`GOAL — Kane`), team wash bleeding
  edge-to-edge, running score Barlow 18/700 at the right (latest white, older
  dim), time white.
- Period breaks are rule-label dividers: `HALF TIME · 1–1`, `KICKOFF · 4:00 PM`.
- **Racing variant (designed)**: the rail is the lap (`L 46`, ~38 wide); glyphs
  wear the *driver's team color* — filled 16px dot = position change (the
  signal), 14px `track` circle with a 2px team ring = pit stop / fastest lap,
  `textFaint` ring = incident (neutral). Signal rows (passes for position) take
  the team wash + 700 title (`Norris passes Leclerc — P2`); the detail line
  carries the how and the gap (`DRS into Turn 1 · now chasing Verstappen, gap
  2.8s`).
- **Dividers can carry phase status**: an 8px square swatch in the flag color
  (`GREEN FLAG · LAP 41`); when the phase compromises play, the label elevates
  into a gold-tinted pill (`SAFETY CAR · LAP 38`) — the divider itself warns.

### Archetype B — grouped episodes *(designed: baseball, tennis)*

Sports whose clock IS a structure — the container is the story unit.

- One card per container (r20, padding 16×18, 12 gap), newest container first.
- Container header: `cardLabelFaint` both sides — context left
  (`BOTTOM 6 · CUBS`), running score right (`MIL 4 · CHC 5`).
- Row: 5px team-color spine bar (full row height, r2) → title 14/700
  (`Suzuki homers (18)`) → detail 12 dim → optional **stat strip** (11 faint
  tabular, 14 gap: `412 FT · 104.6 MPH · 2 OUT`) → running score Barlow 18/700
  right (latest white). Multiple rows in one container split on a hairline +
  14 padding.
- Volume control: **Scoring/All segmented toggle** above the feed — scoring is
  the default; "All" exists for the reader who wants everything (see
  *Progressive disclosure* for what All looks like).
- **Container lifecycle (designed in tennis)**: the in-progress container gets
  a 1px `border` outline and a *white* header label (`SET 3 · LIVE`) with the
  live sub-score right (`ALCARAZ 4–3`); completed containers go dim, result in
  the header (`SET 2 · SINNER 7–6 (7–4)`), summary right (`58 MIN` /
  `0 RUNS · 1 HIT`); stale containers **collapse to their header row** with a
  chevron — history is one tap away, not one scroll away.
- **Tennis variant (designed)**: containers = sets, rows = games (`Alcaraz
  breaks to 15`, `Sinner holds to 30`), 5×15 spine bar in the game winner's
  color, detail = how it ended (`Two aces · saved 1 break point`), running
  games score Barlow 18 right. Signal = the break, wearing a team-tinted
  `BREAK` badge (§6). No rail column at all — in a sport without a clock, the
  running score IS the temporal address.

### Archetype C — scoring episodes *(designed: football)*

Archetype B's layout where the container is the *period* and each row is a
scoring possession that carries its episode summary.

- Container = quarter card, header `3RD QUARTER`.
- Row: **score-type chip** (34×24 r6, team-color fill + 1px `border`, Barlow
  12/700: `TD`, `FG`) → title = the scoring play (`Moore 43-yd pass from
  Williams`) → detail = conversion + game clock (`Santos kick good · 8:51`) →
  stat strip = the episode (`6 PLAYS · 75 YDS · 2:44`) → running score right.
- Use when scoring is the terminal act of a possession worth summarizing.

### Archetype D — dense play-by-play *(designed: basketball, volleyball)*

The density stress test — an event every few seconds. Rows compress to one
line; the score column is persistent; only state changes shout.

- One `surface` card, tighter padding (4×16); rows 10 vertical padding with
  hairlines in **`track`** (`#22272F`) — one step subtler than `divider`,
  because there are ten times as many of them.
- Row, one line (13/1.35): time rail (Barlow 13/600 dim, ~34 wide) → **team
  tick** 4×16 r2 (the 5px spine bar, density-compressed) → `**Actor**` 600
  white + action 400 dim + parenthetical faint (`(James assist)`, `(3rd)`) →
  **persistent score column** (~46 wide, right-aligned, Barlow 14/600
  `textFaint` on every row, fixed header order).
- **Signal rows** (lead changes): team wash at .10–.12 alpha (denser rows and
  dark team colors need more than the usual .07–.08), actor 700, score white
  700, and a `LEAD` badge — 10/700 +0.05em pill (1×7 padding, r999), team
  color at ~20–25% alpha composited on `surface`, white text.
- Stoppages use the rule-label divider at any scale: `LAKERS TIMEOUT · 4:01`.
- Length control: **period filter** segmented control (Q1 Q2 Q3 Q4) — played
  periods `textDim`, active segment `border` fill, future periods `textFaint`.
- **When the score is the clock, merge the columns (designed in volleyball)**:
  rally-scoring sports put the running score *in the rail* (Barlow 14/600,
  ~44 wide, dim; white 700 on signal rows) and drop the trailing score column —
  `24–22 · tick · Lucarelli cross-court kill`. The set filter replaces the
  quarter filter; timeout dividers carry the score at stoppage
  (`ITALY TIMEOUT · 22–21`); signal = set/match point, gold-tinted badge.

### Progressive disclosure — the third density control *(designed: baseball all-plays)*

When "everything" is genuinely everything (pitch-by-pitch, ball-by-ball),
don't render it — **fold it**:

- The All-plays toggle switches the feed to **condensed one-line rows** inside
  the same containers: 4px tick, actor 600 + outcome dim (`Happ strikes out
  swinging`), a faint Barlow count right (`5 P`), an 11px `textFaint` chevron.
  Container headers swap the running score for container state (`1 OUT`,
  `0 RUNS · 1 HIT`).
- **Tap expands in place** (chevron flips): the row becomes a `track` r14
  inset card (padding 12×14, bleeding 4px past the row edge) holding the
  sub-sequence, indented behind a 1px `border` rail — pitch rows = 18px
  muted-fill result dot (§2) + description dim + velocity Barlow 12 faint
  right.
- Containers use the same move at their own scale (tennis's finished set 1
  collapses to its header). **Disclosure over pagination, always**: the feed
  never says "show more" — it folds.

### Shared rules (all archetypes)

- **Newest first, always.** The freshest event is the reason the user opened
  the tab.
- **The rail shows the sport's native temporal address**: match minute (`73′`),
  countdown clock (`2:41`), inning tag (`B7`), over.ball (`16.2`), lap (`L 46`),
  round. A sport with no clock uses its sequence unit — or the running score
  itself (rally sports merge rail and score; tennis drops the rail entirely
  because containers + running score already address every row).
- **The scorebug adapts to what "the score" means**: team sports show the
  combined score (`87–84`); set sports show the match score with the current
  set in the pill (`ALCARAZ 1–1 SINNER` · `SET 3`); races show leader + gap
  (`VER +2.8s NOR`, the gap Barlow 22 dim) with the lap in the pill
  (`LAP 47/58`).
- **Running-score orientation**: rail feeds (A/D) keep the header's fixed
  order — a persistent column must be stable. Grouped feeds (B/C) lead with
  the scoring team — the number that just changed comes first.
- **Filters** (both are the §6 segmented control): a *content* toggle
  (Scoring/All) when volume is the problem; a *period* filter (Q1–Q4) when
  length is the problem. Never both unless the sport truly needs both.
- **Breaks in play** at any scale — period, timeout, rain delay, innings
  break, flag phase — are the dim rule-label divider, never a card of their
  own. Dividers carry the game state at the break (`ITALY TIMEOUT · 22–21`),
  may carry an 8px status swatch (flag color), and elevate to a gold-tinted
  pill only when the phase compromises play (safety car, weather delay).

### The density dial

As events-per-match rises, compress in this order (never skip ahead of need):

| Sparse → | → Dense |
|---|---|
| Two-line row (title + detail) | One line, detail inline as faint parenthetical |
| 5px spine bar | 4px tick |
| `divider` hairlines | `track` hairlines |
| Running score on scoring rows only, 18/700 | Faint score column on every row, 14/600 |
| Every event rendered | Signal events highlighted, the rest is texture |
| Sub-events inline | Sub-events folded behind an in-place expand (disclosure) |

### Assignments — pick, don't redesign

| Sport | Archetype | Container | Rail unit | Signal (the loud row) |
|---|---|---|---|---|
| Soccer ✓ | A | — | minute (73′) | goal |
| Racing / F1 ✓ | A | — (flag phases as dividers) | lap (L 46) | pass for position |
| Hockey | A | — | period + clock | goal (penalties quiet rows) |
| Rugby | A | — | minute | try / red card |
| Lacrosse / field hockey / water polo | A | — | period + clock | goal |
| Baseball ✓ | B (+ disclosure for All plays) | half-inning | inning tag (B7) | scoring play |
| Tennis ✓ | B | set (live outlined; stale collapsed) | — (running score is the address) | break of serve (BREAK badge) |
| Cricket | B | over (T20) / innings (Tests) | over.ball (16.2) | wicket & boundary (+ disclosure per over) |
| MMA / boxing | B | round | round + clock | knockdown / finish (+ judge table per round) |
| Football (gridiron) ✓ | C | quarter | drive clock | scoring drive (TD/FG chip) |
| Aussie rules / rugby league | C | quarter/half | clock | scoring possession |
| Basketball ✓ | D | quarter (as filter) | countdown clock | lead change (LEAD badge) |
| Volleyball ✓ | D | set (as filter) | rally score (merged rail) | set/match point (badge) |
| Handball | D | half (as filter) | clock | lead change |
| Table tennis / badminton | D | game (as filter) | rally score (merged rail) | game point |
| Golf | — | *no feed* — golf's event history is the scorecard grid (§8), per player, not a stream | | |

✓ = designed in the exploration. Unmarked rows are extrapolations — sound
defaults, but fair game to refine when that sport gets designed.

**Until a sport's feed archetype is built, its Now tab carries the story with
supporting cards.** Hockey's archetype-A feed is unbuilt, so the hockey Now tab
leads with the §8 **shots-pressure card** (shots bars + goalie SV% footer) and a
quiet **SCORING card** (design 6c: a faint period·clock rail + play prose) built
from the summary's scoring plays — otherwise it was two lonely cards. The same
quiet SCORING supporting card appears on the **gridiron Now** when its
down-&-distance situation is sparse (the drive-log lives in full on the Drives
tab, but the Now must never collapse to just a headline + win-prob bar). Dispatch
these on data presence — a shots total, drives — never sport name.

### Composing

Archetypes nest and controls transfer. Baseball's All-plays view (designed) is
B containers holding D-density rows with disclosure. Football's All-plays would
be the same: C containers per drive, D rows, expandable where a play has
sub-detail (penalties, measurements). Cricket's over-by-over = B containers per
over holding the ball-circle vocabulary from §8, wicket rows expanding to the
dismissal. When a new sport resists classification, compose — don't invent.

---

## 10. Data-dump screens — dense tables that stay scannable

Box scores, leaders, season stats, line scores, team comparisons (exploration
turn 10). The point of these screens is *everything at once* — the grammar's
job is to keep a wall of numbers glanceable. One idea does most of the work:
**every table highlights exactly one key-stat column per context**; everything
else recedes.

### The table grammar

- Card r20, padding 14×16 (tighter than the standard 18 — tables need width).
- CSS-grid columns: name column `1fr` (13/600, `nowrap` + ellipsis — the name
  yields, numbers never do), then fixed narrow right-aligned stat columns
  (26–44 wide, 2px gap). Inline tags ride the name (position `2B` 11 faint,
  NOW pill).
- Header row: 10/700 +0.06em `textFaint` — except the **key-stat column
  header, which is white** (PTS, H, K, PPG per context).
- Cells: 13 tabular `textDim` — except the **key-stat cell: Barlow 15/700
  white**. One white column; if two columns feel key, pick one.
- **Section label rows inside one table** (STARTERS / BENCH / CUBS PITCHING):
  header-row styling, bounded by `divider` rules; row hairlines *within* a
  section are `track`, section boundaries are `divider`.
- Rows 9–10 vertical padding. **Totals row**: name 700 (`TEAM`), values 600
  white, key stat Barlow 15/700, no bottom border.
- **Footer summary line**: 11 `textFaint` tabular, middot-joined, above a
  `divider` (`FG 34/71 · 47.9% · 3PT 11/28 · FT 8/10 · TO 9`) — the stats that
  didn't earn a column.
- **Substitution rows** (composed from the grammar; baseball box): a replacement
  player renders **indented** in the man-he-replaced's slot, its name prefixed by
  ESPN's letter marker (`a-`, `b-`), with the lineup note as an 11px `textFaint`
  footnote line beneath the row (`a-doubled to left for Caissie in the 7th`).
  Never truncate the batting order — late substitutes must all show.

### Semantic cells

Numbers carry meaning through color, sparingly:

- **Signed values**: positive `green`, negative `live`, zero `textDim` (the
  +/− column). (The exploration wobbles between `#3BA86F` and `#3FA96B` —
  `green` is the token; use it.)
- **Did/didn't**: scoring innings white, zero innings dim.
- **Not yet**: unplayed cells are `–` in `ghost` (§2).
- **Live here**: the current inning cell is a `track` r4 chip holding a `•`;
  the active pitcher gets the NOW pill (§6). Quieter than a wash — tables are
  too dense for washes.

### Qualification note-bands + legend

Rows that carry an ESPN qualification note (Champions League, Relegation,
knockout-advance…) get a 3px left color band — parsed from the note's hex,
flush to the card edge, content unshifted — instead of a text label on every
row. A single **legend** renders once below the table: a 3×12 swatch + the
note's description, one entry per distinct band in row order, so the color
coding is decoded once per card, not repeated per row. Shrinks away entirely
when no row carries a note. Used by soccer/tournament group standings; the
tournament group's dashed cut-line (§5 Tournament shell, §7 the cut line) is
the same idea taken one step further — a rule instead of a swatch, for the
one boundary that matters most.

### Scope controls

Segmented controls (§6) above the table. Two axes sit side by side, 8 gap:
team switch + split switch (`Cubs | Brewers` · `Batting | Pitching`). The
table never scrolls horizontally — scope controls exist so it doesn't have to.

### Comparison patterns

- **Head-to-head leaders** (per-category cards): UPPERCASE category label; the
  leader's row on top (name 13.5/700, context detail 11 faint — `10/16 FG ·
  2/4 3PT`, `4 offensive`), value Barlow 26/700 white right (runner-up dim);
  between them the **gap bar** — 5px `track`, two team-color segments growing
  from opposite edges, widths proportional to the values. Team-tinted initial
  avatars (§6), 38px.
- **Center-spine mirrored bars** (team stats): the *only* sanctioned mirrored-bar
  treatment — independent per-team values in every other surface are number rows
  (§8 "the bar rule"), never gauges. Per stat — value Barlow 17/700
  at both edges (both white; the bars carry the comparison), label 11 dim
  centered; beneath, two half-width 5px r3 team-color bars growing outward-in
  toward a 3px center gap. The card's header row doubles as the legend:
  `PACKERS · TEAM STATS · BEARS` with the team names in their team colors —
  **the one sanctioned use of team-colored text**, label tier only, and only
  where the text is itself the legend for team-colored marks.
- **Stat tiles** (season stats): 2-col grid, 10 gap; tile = `track` r14,
  padding 12×14; value Barlow 24/700 tabular, semantic rank chip (§6) top
  right, label 11 dim below. Tiles for the headline numbers, a table for the
  rest.
- **Key-players strip**: 2-col grid of `track` r14 tiles (name 12.5/700 +
  stat line 11 dim tabular) under a `divider` — the QB-duel footer.

### Screen anatomies

- **In-game tabs** (Box / Leaders / Stats): compact scorebug → chip nav →
  scope controls → table/comparison cards.
- **Team page** (season stats): identity header — 44px r12 *solid* team-color
  square with Barlow abbr (badge-scale identity fill, sanctioned like TD/FG
  chips) + Barlow 24 team name + record caption (`41–24 · 3rd West ·
  2025–26`) → chip nav (Games / Stats / Roster / Schedule) → stat tiles →
  player-averages table.
- Sport dispatch stays data-driven: line score (innings/periods) renders when
  `periodScores` exist; batting/pitching splits when the box has them; the
  grammar itself never branches on sport name.

---

## 11. Building a screen that doesn't exist yet — the recipe

1. Pick the **anatomy** from §5 that matches the screen type. Do not invent a
   new anatomy; if none fits, compose sections from §5 in the fixed order
   (identity block → chip nav → flourish → supporting cards).
2. Every card: `surface`, radius 20, padding 18, UPPERCASE `cardLabel`, hairline
   `divider` between internal rows.
3. Numbers → Barlow Condensed tabular. Words → Archivo. Labels → uppercase
   letterspaced dim.
4. Team identity → bars/dots/fills only (§2 team colors, §4 bar sizes).
5. Winner/leader = white + 600–700; everyone else dim. Live = the red dot.
6. New sport flourish: dispatch on a data field, then build from the vocabulary —
   rails, lane rows, dot/pip sequences, tinted field strips, chase equations,
   grouped feed cards, dashed-pending markers. Check §8 for the closest cousin
   and match its density. For a plays/timeline tab, classify the sport with
   §9's three questions and build that archetype — check the assignments table
   first; most sports are already placed. For box scores, stats tabs, and any
   wall of numbers, use the §10 table grammar (one key-stat column, semantic
   cells, scope controls).
7. At most one inverted card. If the screen has no narrative moment, it has no
   inverted card.
8. Empty/hint states: dashed-border card, centered faint caption.
9. Before shipping, do the 2-second test: score/state biggest and whitest,
   context dim, chrome faint, anything else cut.

## 12. Motion (recommended defaults — the exploration is static)

Match the calm: fast fades and small slides (150–250ms, standard ease-out), no
bounce, no hero transitions. The score-block → scorebug collapse tracks scroll
position directly (not time-based). Live-updating numbers may tick with a quick
fade; the live dot may pulse gently (2s cycle) but never blink. Drag states per
§5 Following. Android predictive back is already wired in `buildV2Theme()`.

## 13. Never

- No logos, no team-colored text (one exception: §10 comparison headers, where
  the label *is* the legend for team-colored bars), no colored card backgrounds.
- No light mode, no Material seed-color theming, no default-blue anything.
- No shadows on resting cards; no borders thicker than 2px except color bars.
- No sport-name branches in rendering code — data presence only.
- No second inverted card, no second accent competing with gold.
- No proportional figures where a number can change while you watch.
- No banner headlines, no exclamation points — the inverted card whispers one
  good sentence.
