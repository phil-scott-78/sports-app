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
   Now/Timeline/Stats/Lineups, Leaderboard/Following/Course/Tee times…).
4. **Situation card** — the sport's flourish (§8). The only per-sport shape.
5. **Win probability card** — label + `statCallout` right; 12px two-segment
   rounded bar in team colors with a 2px gap.
6. **Inverted LAST PLAY card** — the loud moment (§7).
7. **Supporting cards** — scoring feed, top performers, drive log, serve stats…
   each a quiet `surface` card with an UPPERCASE `cardLabel`.

**On scroll** the score block collapses into a **sticky scorebug**: one line —
`bar + ABBR 4` pairs (Barlow 19), a mini glyph (mini diamond / possession arrow),
phase caption, live dot — with the chip nav pinned beneath (condensed chips).
`bg` background, 1px `divider` bottom border.

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
3. **League sections** — `sectionTitle` header (+ optional faint action right:
   "See all 15") over one radius-16 card of dense rows separated by hairlines.

**Dense row anatomy**: left = two stacked team lines (5×16 bar, 14px name,
Barlow 17 score, possession arrow if relevant); right = status stack (live dot +
phase 12px over one faint context line 11px — `2 out · 2–1`, `3rd & 4 · OU 22`,
`NED down to 10`). A row may hang one glyph strip below it (drive field bar,
series pips) inside the same row card.

### Standings / tables

League chips (same chip pattern) → optional sub-tabs (underline style: 2px gold
underline on active, dim text inactive) → one card per group. Tables are CSS-grid
rows: `cardLabelFaint` column headers, `listText` names, Barlow 14 numbers.
Favorite row gets the gold wash + ★. Streaks: `green` W / `live` L. Playoff cut
line: dashed rule label row (§7). Racing championships and golf leaderboards
reuse this table pattern with rank + athlete rows. The full dense-table grammar
(key-stat column, section rows, semantic cells) lives in §10.

### Following / management lists

Radius-16 row cards, 8 gap. Row: minus circle (22px, `track` bg, `live` glyph) +
team bar + name/league + trailing drag handle (three 16×2 lines, `outline`;
`textDim` when active). Drop target = 1.5px dashed `border` empty slot. Dragged
row = `dragSurface`, shadow, slight rotation. Footer hint card = dashed border,
centered faint caption ("Long-press any team or league in the app to add it here").

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
name (`situation.hasBaseball` → diamond, `hasGridiron` → drive field,
`competition.events` → timeline, cricket target → chase, `layout == 'field'` →
leaderboard). Reuse these; when a new sport appears, compose a new one from the
same vocabulary (§11 checklist).

### Baseball — the diamond
- **Situation card**: SVG diamond left (viewBox `0 0 128 112`; basepaths 3px
  `diamondLine`; bases = 18×18 r3 rects rotated 45° at (112,54)/(64,12)/(16,54),
  home 16×16 at (64,98); occupied = `gold` fill, empty = `track` fill + 2.5px
  `outline` stroke) + right column: count headline (`2–1 COUNT`), dim narrative
  line, B/S/O dot rows (9px dots: balls `green`, strikes `live`, outs white).
- **Glance glyph**: mini diamond (viewBox `0 0 26 22`, three 7×7 r1.5 rotated
  rects) — in rows and the collapsed scorebug. Phase text `Bot 7`.
- **Feed**: archetype B by half-inning (§9); stat strip `412 FT · 104.6 MPH ·
  2 OUT`. *All plays* is the designed disclosure mode (§9): condensed at-bat
  rows (4px tick, `Happ strikes out swinging`, faint `5 P` pitch count,
  chevron) expanding in place to the pitch sequence — 18px muted-fill B/S/F
  dots (§2) + description + velocity, indented behind a 1px rail; the live
  at-bat sits pre-expanded in a `track` inset card with its current count.
- **Box tab** (§10, designed): line score by inning — scoring innings white,
  zeros dim, unplayed `–` in `ghost`, current inning a `track` chip with `•`,
  R/H/E columns with R highlighted — then dual scope toggles (team | split)
  over batting/pitching tables (H and K the key columns, position tags inline,
  NOW pill on the active pitcher).

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
  callout right (`OKC 9–2 RUN` / "last 2:40"); footer row: possession arrow +
  "14 on clock", bonus flag (`gold` text when in bonus), timeout dots (7px,
  team color = remaining, `border` = used).
- **Lead tracker card**: 64px polyline (2.5px team-color stroke, endpoint dot),
  centerline 1px `divider`, Q1–Q4 axis labels 10px faint.
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
- **Score block extras**: `10 MEN` red badge; aggregate/pens in dim parens after
  the score (`1 (4)`).
- **Stats card**: possession split bar (two team-color segments, 2px gap) +
  SHOTS/xG/CORNERS rows (Barlow numbers flanking a faint centered label).
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
- **Center-spine mirrored bars** (team stats): per stat — value Barlow 17/700
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
