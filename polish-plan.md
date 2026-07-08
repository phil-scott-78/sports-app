# polish-plan.md — realigning the app with the design exploration

Research-and-plan document for the UI/UX drift found while clicking through the app
against the mock backend. Every finding below was verified two ways: the current
rendering was screenshotted from a live `flutter run -d web-server` build pointed at
`npm run mock`, and the intended rendering was read from the **source HTML of the
Claude Design exploration** (project `Sports App Design Concept`, file
`Sports App Explorations.dc.html` — the same artifact DESIGN.md was distilled from).
Design specs are embedded inline below so this plan is self-contained.

Design option IDs referenced: **6a** soccer detail · **6c** hockey detail · **7a** golf
detail · **9b** baseball scoring by half-inning · **9c** football scoring by quarter ·
**9d** basketball dense play-by-play · **9e** baseball "All plays" disclosure ·
**10d** baseball line score + splits.

---

## Ground rules for the implementer

1. **Read `app/DESIGN.md` first** (per CLAUDE.md §5). Use `theme.dart` (`T.`) tokens,
   never raw literals.
2. **The Dart normalizers are golden-tested against the JS oracle.** Any change to
   `app/lib/src/data/summary.dart` (or normalize.dart etc.) MUST be mirrored in
   `worker/src/summary.js` (or the matching oracle file), then regenerate goldens
   (`cd worker && npm run goldens`) and keep `flutter test` (the `port_*_test.dart`
   parity suites) byte-for-byte green. Never change one side alone.
3. **No sport-name branches in rendering code** — extend the data-driven dispatch
   (`StatKind`, `layout`, data presence) instead.
4. Canonical contract changes ripple three ways: `schema/canonical.ts` (types + notes),
   the JS oracle, the Dart normalizer + `models.dart` parser. Keep all in sync.
5. Several bugs are **partly mock-data artifacts** — each is flagged below. Fix the
   tooling (workstream 8) alongside the UI so the fix is actually verifiable offline.
6. Verify like this plan was researched: run the mock, run the web build, walk the
   screens with Playwright, compare against the specs quoted below.

---

## 1. Soccer — Match Stats card renders percent/count treatments inverted

**Symptom (verified):** Possession (55.3% / 44.7%) draws as two independent
half-gauges with a dead gap in the middle; Shots / On target / Corners / Fouls draw
as full-width split bars. The design wants the opposite emphasis: possession is the
ONE bar (it's a share of 100%), counts are plain number rows with no bar.

**Root cause:** `app/lib/src/ui/stat_specs.dart` — `StatCompareRow._bar`
(≈lines 370–426) branches on `gaugeFraction(spec.kind, …)` (≈126–144):
non-null for `percent`/`fraction01`/`ratio` → mirrored half-gauges; null for
`count`/`clock` → full-width share split bar. So *all* percents become gauges and
*all* counts become split bars. Both the cheap panel (`_CheapStatsCard`,
`game_detail_page.dart` ≈1360–1405, keys from `cheapStatPanels['soccer']`,
stat_specs.dart ≈65–71) and the rich `_TeamStatsCard` (≈1285–1354 via
`classifyRichRow`) flow through the same renderer, so both are wrong.

**Design spec (6a, exact):**

- Possession row: labels line (`58%` w600 white · `POSSESSION` 11px letterspaced
  faint · `42%` dim), then an **8px-tall full-width split bar**: two team-color
  segments with a **2px gap**, widths = the two percentages, radius 4.
- Count/decimal rows (SHOTS, EXPECTED GOALS, CORNERS): one line each, **no bar** —
  leader value 13px w600 white left (fixed ~40px column), centered 11px
  letterspaced `textFaint` label, trailer value dim right. (DESIGN.md §8 calls
  these "Barlow numbers flanking a faint centered label".)

**Fix direction:**
- Add a *share* concept to the kind system: e.g. `StatKind.sharePercent` (or a
  `share: true` flag on `StatSpec`) for stats whose two sides sum to a whole —
  possession is the only current member. `sharePercent` → the full split bar.
- `count` (and decimal counts like xG) → plain number row, **no bar at all**.
- Independent percents (FG%, SV%, faceoff %) keep a comparison treatment but NOT
  full-width gauges — see workstream 6 (they become number rows too; the §10
  center-spine mirrored bars remain the *gridiron team-stats card* treatment only).
- Update `cheapStatPanels['soccer']` (`PP` → share) and `classifyRichRow` so rich
  soccer stats (possession key `possessionPct`) classify the same way.
- This is UI-layer only — no normalizer/golden impact.

---

## 2. Soccer — timeline "only shows from 56' on"

**What's actually true (verified):** The **Timeline tab** for a game with a captured
summary shows the full match (MAR–CAN renders rows down to 20'; 1ST HALF divider
present). Two real defects produce the reported symptom:

1. **The Now-tab MATCH TIMELINE card lists only the last 3 events.**
   `app/lib/src/ui/situations.dart` ≈443: `comp.events.reversed.take(3)`. In a
   3-goal second half every legible row is late-game; the early match exists only
   as unlabeled dots on the rail. Design 6a shows a *curated* list (the red card at
   68', the goal at 31') — the signal events, not "last N of anything".
2. **Games without a rich summary fall back to the cheap `comp.events` feed, which
   is goals+cards only** (`normalize.dart` `_buildScoringEvents` ≈437–472 filters
   `_scoringEventType == 'other'` out). A match whose first goal/card came at 56'
   shows literally nothing before 56'. In the mock, any soccer event without a
   captured summary gets the minimal envelope (`worker/mock/synth.mjs`
   `synthSummary`) → the Timeline tab itself degrades to the cheap feed.
   (The eng.1 fixture's Brentford–Liverpool game has its first cheap event at 58' —
   almost certainly the exact game behind this bug report.)

**Fix direction:**
- Now-card list: curate instead of tail — show **all goals and red cards** (newest
  first, cap ~5), fall back to last-3 if none. Keep the rail plotting everything.
  Clamp marker positions for stoppage-time minutes (90'+8 currently lands at/over
  the right edge).
- Timeline tab: prefer `summary.timeline` (rich, from kickoff) whenever the summary
  loaded; today that's already the case — the gap is mock coverage, so fix via
  workstream 8 (capture summaries for more soccer events) rather than app code.
- No normalizer change needed.

---

## 3. Baseball

### 3a. Line score should fill the card at 9 innings, shrink-then-scroll for extras

**Root cause:** `_InningLineScore` (`game_detail_page.dart` ≈1142–1278) hard-codes
`_innW = 24.0` per inning cell inside a `SingleChildScrollView` row: at 9 innings
the grid is a fixed 216px left-aligned in a wider viewport (dead space right, as
screenshotted); extras overflow into scroll with no shrink step.

**Design spec (10d, exact):** card padding 14×16 (`T.padTable`), CSS grid
`44px repeat(9, 1fr) 8px 26px 26px 22px` — label column fixed, **innings are
`1fr` and share the full remaining width**, 8px gutter, then R/H/E fixed columns
(R header + cells white/key, H/E dim). Cell semantics already implemented (scoring
inning white, 0 dim, `–` ghost, current inning `track` chip with `•`) — keep them.

**Fix direction:** when `innings <= 9`, lay the inning cells out with
`Expanded`/flex so they fill the width (drop the scroll view); when `> 9`, first
shrink toward a min cell width (~18px), and only past that put the innings pane
(alone — label + R/H/E stay pinned) in horizontal scroll. `LayoutBuilder` on the
card width chooses the mode.

### 3b. Scoring feed drops the earliest runs

**Root cause (two-part):**
1. **UI truncation:** `game_detail_page.dart` ≈362–367 keeps the **last 12**
   scoring plays (`scores.sublist(scores.length - 12)`) — a >12-score game loses
   its first runs. The normalizers are innocent (they cap at the *first* 120).
2. **Mock coverage:** the specific KC/PHI game has **no captured summary** in
   `worker/mock/fixtures/baseball__mlb.json` (only PIT/MIA `401815752` and BAL/SD
   `401815754` have one) → synth serves the empty envelope → no scoring plays at
   all. Workstream 8.

**Fix:** delete the last-12 cap (grouping by inning, 3c, is the volume control).

### 3c. Scoring plays grouped by half-inning (design 9b)

**Current:** one flat `ActionFeed` card with dashed `RuleLabelDivider`s per inning
number ("9TH INNING · 4–2") — both halves of an inning merge, markers are `ColorBar`
glyphs + gradient washes, no stat strip.

**Design spec (9b, exact):** one **card per half-inning** (r20, padding 16×18,
12 gap, newest first). Container header `cardLabelFaint` both sides:
`BOTTOM 6 · CUBS` left, running score `MIL 4 · CHC 5` right. Row anatomy:
**5px full-height team-color spine bar** (r2) → title 14/700 (`Suzuki homers (18)`)
→ detail 12 dim lh1.5 (`2-run shot to left-center off Megill · Happ scores`) →
optional stat strip 11px faint tabular, 14 gap (`412 FT · 104.6 MPH · 2 OUT`) →
running score Barlow 18/700 right, **latest white, older dim, scoring team's number
first**. Multiple rows in one container split on a hairline + 14px padding.

**Data gap (normalizer change — lockstep with oracle + goldens):** ESPN plays carry
`period: { type: "Top"|"Bottom", number, displayValue }` but `_mapPlay`
(`summary.dart` ≈134–147; `worker/src/summary.js` `mapPlay`) drops `period.type`.
Carry it (e.g. canonical `play.half: 'top'|'bottom'` or fold into `periodLabel`
as "Top 2nd") so the feed can key containers on `(period, half)`. `side` (away=top)
can serve as an interim key, but carrying the real field is the honest fix and also
fixes `periodLabel` ("2nd Inning" → "Top 2nd").

### 3d. Box score: substitution indicators + footnotes

**Verified in raw fixture data:** each `boxscore.players[].statistics[].athletes[]`
row has `starter` (bool), `batOrder`, `position.abbreviation`, and
`notes: [{type:'lineup', text:'a-doubled to left for Caissie in the 7th'}]` — the
exact "walked for Thomas in the 7th" footnote requested. The normalizer discards
all of it (`_buildBoxGroups`, `summary.dart` ≈92–122 reads only name/pos/stats;
same in `worker/src/summary.js`), `BoxRow` (`models.dart` ≈1719–1729) has no
fields for it, and `_BoxGroupCard` (`game_detail_page.dart` ≈1487–1547) even
truncates to `rows.take(12)` — hiding late substitutes outright.

**Fix direction (full pipeline, lockstep):**
- Normalizer + canonical + `BoxRow`: add `starter: bool`, `note: String?`
  (first lineup note's text is enough).
- UI (extends the §10 table grammar — also a DESIGN.md addition, workstream 9):
  non-starter batting rows render **indented** (their `batOrder` slot) with the
  name prefixed by the ESPN letter marker already embedded in the note (`a-`, `b-`)
  or a `↳` glyph; the note text renders as an 11px `textFaint` footnote line under
  the row (or collected under the table above the totals, matching ESPN's
  convention — implementer's choice, but IN the card).
- Remove `take(12)`.

### 3e. All plays — the designed disclosure mode (design 9e)

**Current:** the Plays tab is one flat feed; no Scoring/All toggle exists anywhere
(`SegmentedToggle`/`SegmentedControl` exists in `widgets.dart` but is unused here).

**Design spec (9e, exact):**
- **Scoring plays | All plays** segmented toggle (§6 style: container `surface`
  r12 p4, active segment `border` fill r9, 12.5/600) above the feed; Scoring is
  the default view (= 3c).
- All view: same half-inning containers, header swaps running score for container
  state (`1 OUT` live, `0 RUNS · 1 HIT` complete). Rows are **condensed one-liners**:
  4×16 tick in team color → `Happ` 600 + `strikes out swinging` dim (13.5px) →
  faint Barlow `5 P` pitch count → 11px chevron `▾`. Row hairlines in `track`.
- **Tap expands in place**: the row becomes a `track` (#22272f) r14 inset card
  (padding 12×14, bleeding 4px past the row edge) holding the pitch sequence
  indented behind a 1px rail: per pitch an **18px muted-fill circle** (Ball
  `#2F6B3F`/`#C9E5CF`, Strike `#7A3038`/`#F0CDD1`, Foul `#6B5B2A`/`#EADFB8`,
  9/700 letter) + description dim + velocity Barlow 12 faint right (`94.8 MPH`).
- The **live at-bat sits pre-expanded** at the top of its container with the
  current count where the pitch-count would be (`2–2`) and the chevron flipped.

**Data reality:** ESPN's MLB summary carries at-bat/pitch detail, but the mock
fixtures don't — `capture-fixtures.mjs:200` keeps only `scoringPlay===true` rows
(see workstream 8). Implement against live ESPN, verify pitch fields there
(`plays[].pitches` / per-pitch play rows + `atBatId` — confirm the actual shape
before building the normalizer), and extend the canonical play with an optional
pitch-sequence field (lockstep with oracle + goldens). If pitch data turns out
unavailable per-play, ship the condensed-row + container layer anyway (it stands
alone) and leave rows chevron-less.

---

## 4. Basketball

### 4a. Plays list is slow — not virtualized

**Root cause:** the page scaffold is a `CustomScrollView` but the whole feed is ONE
sliver child: `ActionFeed.build` (`ui/match_events.dart` ≈37–133) materializes
every row into a single `Column` inside a `Container`. Up to 800 plays
(`summary.dart` cap) built eagerly. Worse, `build` re-sorts and re-tallies the full
list on every rebuild, and the summary provider re-polls every ~20s live — the
whole feed rebuilds each poll.

**Fix direction:**
- Have the Plays tab emit **slivers**: flatten (header/divider/row) into an
  indexable list once, render via `SliverList.builder` inside the page's existing
  `CustomScrollView` (`_sections` will need a sliver-aware path for this tab; other
  tabs can keep boxed sections).
- Hoist the sort/tally/grouping out of `build` (compute in the provider layer or
  memoize on the plays list identity).
- The quarter filter (4b) is also a length control: with a period filter active the
  row count drops ~4×.

### 4b. Plays grouping & styling vs design 9d

**Current vs spec:** quarter dividers exist; missing are the quarter filter,
timeout dividers, actor-only emphasis, and signal-row discipline (today every row
gets a team wash + white bold line — in the design, ordinary rows are quiet).

**Design spec (9d, exact):**
- **Quarter filter** segmented control above the feed (`Q1 Q2 Q3 Q4` — played
  quarters dim text, active `border`-fill segment, future quarters faint).
- One `surface` card, padding 4×16; rows 10px vpad, hairlines in **`track`**.
- Row, one line 13px/1.35: clock rail Barlow 13/600 dim ~34 wide → **4×16 r2 team
  tick** → `Jokić` **600 white** + `misses turnaround jumper` **400 dim** +
  parenthetical faint (`(James assist)`, `(3rd)`) → persistent score column ~46
  wide right-aligned Barlow 14/600 `textFaint`, fixed header order.
- **Signal rows only** (lead changes): team wash at .10–.12 alpha edge-to-edge,
  actor 700, clock white, score white 700, `LEAD` tinted pill (10/700 +0.05em,
  r999, 1×7 pad, team color ~20–25% alpha on `surface`).
- **Timeout divider:** centered 10/700 +0.1em faint label between hairline
  segments — `LAKERS TIMEOUT · 4:01` — as a row inside the card, not a card.

**Data gaps:**
- **Actor:** canonical `SummaryPlay` has no participants — `_mapPlay` drops
  ESPN's `participants[].athlete.id` (present on every NBA play row in the
  fixture, id only). Normalizer change (lockstep): carry the first participant's
  athlete id + resolve display name against the summary's boxscore athletes (the
  oracle does the same); fall back to prefix-matching `text` when unresolved. If
  neither yields a name, render the whole line dim — per the bug report, only
  highlight the actor "if we have the data".
- **Timeouts:** ESPN play type text `Timeout` exists live; the mock strips
  non-scoring plays (workstream 8). Dispatch the divider on play `type`
  matching timeout, using `text` as the label + clock.

---

## 5. College football

### 5a. "Now" is barren

**Verified:** live CFB (MIA–IU, Q3) shows only a bare `1ST & 3` headline card and a
WIN PROBABILITY bar. No drive-field graphic, no LAST PLAY, no stats, no scoring.

**Root causes:**
- **Mock:** the synth promotes a game to `in` but the scoreboard event carries **no
  `situation`** beyond down/distance text and the live summary is a rebased post
  summary — so `situation.lastPlay` (inverted card), possession, spot, etc. are
  absent. Workstream 8: teach `worker/mock/synth.mjs` to fabricate a plausible
  gridiron `situation` (possession, down/distance, yardline, lastPlay text) for
  live football events, deterministic by event id.
- **App:** `GridironSituationCard` renders a degraded headline-only card when only
  `downDistanceText` is present — acceptable — but the Now tab composes *nothing
  else* when situation/lastPlay are thin. Make Now resilient: when live but the
  situation is sparse, still show the scoring feed (data exists — the Drives tab
  proves it) and the cheap stats card, so the screen is never two lonely cards.
  (DESIGN §5 order: situation → win prob → inverted → supporting cards; the
  supporting cards are the fix.)

### 5b. Drives tab → Scoring | All filter (design 9c)

**Current:** `_DrivesCard` (`game_detail_page.dart` ≈1866–1901) is a flat 3-column
text list (abbr · result · "N plays, X yards, T") — no quarter grouping, no chips,
no running score, no expansion.

**Product decision (per the bug report):** keep ONE **Drives** tab with a
**Scoring | All** segmented toggle rather than the design's separate Scoring tab.

**Design spec (9c, exact) — the Scoring view:**
- One card per quarter (r20, 16×18, 12 gap, newest first), header `cardLabelFaint`
  `3RD QUARTER`.
- Row: **score-type chip** 34×24 r6, team-color fill + 1px `border`, Barlow 12/700
  (`TD`, `FG`) → title 14/700 = the scoring play (`Moore 43-yd pass from
  Williams`) → detail 12 dim (`Santos kick good · 8:51`) → **drive stat strip**
  11px faint tabular 14 gap (`6 PLAYS · 75 YDS · 2:44`) → running score Barlow
  18/700 right (scoring team first, latest white, older dim).
- **The All view:** same quarter containers listing EVERY drive as a condensed row —
  result chip/label (`Punt`, `TD`, `FG`, `INT`, `Missed FG`; non-scoring results
  as quiet text, scoring keep the chip) + drive summary + stat strip — with
  **tap-to-expand** revealing the drive's plays in a `track` inset (the 9e
  disclosure move at drive scale; DESIGN §9 "Composing" names exactly this).

**Data gap (normalizer, lockstep):** `_buildDrives` (`summary.dart` ≈439–455)
keeps `side/teamAbbr/description/result/isScore/yards/playCount` but drops
`timeElapsed` (the `2:44`), the drive's **period/quarter**, the **running score**,
and the per-drive `plays[]` (verified present in the raw fixture). Extend
`DriveSummary` with `timeElapsed`, `period`, `awayScore/homeScore` (score after
the drive — derive from the scoring play or ESPN's drive end data), and a slim
per-drive plays list (text + clock + down/distance). Note `capture-fixtures.mjs`
already keeps slimmed nested drive plays, so the mock can exercise the expansion.

---

## 6. Hockey — comparison rows + the missing cards

**Verified:** the NHL Now tab is just a GOALTENDING card (Save % as a near-full
mirrored gauge, Saves as a split bar), Top Performers, Season series. No shots, no
scoring feed, no last play.

**Design spec (6c, exact):**
- **SHOTS ON GOAL card** (the §8 "shots pressure" card): per team a row —
  abbr Barlow 15/700 (34 wide) → **10px r5 rounded bar on `track`**, fill =
  team color, width proportional to shots (leader ~80%) → total Barlow 16/700
  right. Footer under a hairline, 12px dim: `Oettinger .938 SV%` · `Hill .905 SV%`.
- **SCORING card**: quiet rows — rail Barlow 13/600 faint 44 wide (`2ND 4:12`) +
  13px `textBody` prose (`Hintz (24) — snap shot, assists Robertson, Heiskanen`).
- LAST PLAY inverted card when a narrative line exists.
- (The POWER PLAY situation card is already specced in DESIGN.md §8 — separate
  concern, only renders when PP data is present.)

**Root causes & fix:**
- `cheapStatPanels['hockey']` (stat_specs.dart ≈79–82) has only `SV%`/`SV` — and
  the cheap scoreboard genuinely carries only goaltending numbers. But the RICH
  summary has `shotsTotal`, hits, PP%, faceoff% (`richPriorityKeywords['hockey']`
  exists, only surfaces in the Box tab).
- Build the shots-pressure card off `summary.teamStats` (shots + SV%) and place it
  on Now/Recap; render goaltending's SV% as the card's footer, not a standalone
  gauge. Kill the standalone Goaltending card on Now (Box tab can keep the full
  table).
- Add the Scoring card on Now from `summary.scoringPlays` (data exists — mock
  fixture has an NHL summary).
- **Renderer rule (ties to workstream 1):** independent percents (`SV%`) stop
  being full-width gauges; as plain compare rows they render numbers-only. The
  mirrored-gauge treatment should no longer be reachable outside the §10
  team-stats comparison card.

---

## 7. Golf — make the event page worth a golf fan's glance

**Verified:** the golf detail is a bare rank/THRU/TOTAL list, no chip nav, plus a
synth inconsistency (pill `ROUND 3`, meta strip `Round 4 of 4`, every player
`THRU F`).

**Design spec (7a, exact):**
- **Event block**: Barlow 40 title + 13px dim narrative caption (`Moving day ·
  wind 18 mph off the coast`) — caption is data-gated; omit when absent.
- **Leaderboard table**, grid `24px 1fr 48px 48px 52px`: rank (leader `gold`,
  rest dim) · name 13.5 (+11px faint country) · **TODAY** Barlow 14/600 centered,
  `underPar` red when under, dim otherwise · **THRU** dim centered (`14`, `F`) ·
  **TOTAL** Barlow 17/700 right, `underPar` red. Followed player row: **gold wash**
  (7–8% alpha edge-to-edge) + `· following` tag appended to the country text,
  name 600.
- **Followed player hole-by-hole card**: header `ÅBERG · HOLE 13` Barlow 24/700 +
  detail caption (`Par 5 · 547 yds · 2nd shot, 231 to the pin`) + to-par Barlow
  26/700 right; below a hairline, the **hole strip** (30px cells: birdie
  `underPar` circle ring, bogey faint square ring, eagle ◎, current hole dashed
  gold ring, legend inline in the label).
- **LAST SHOT** inverted card (data-gated).
- **COURSE · TOUGHEST TODAY** card: hole rows + `+0.42 avg` (data-gated —
  probably unavailable; skip unless the core event feed provides it).

**What the data supports today (verified in fixture + models):**
- **TODAY column** — derivable from the latest `linescores` entry per competitor.
  Currently unrendered. Do it.
- **Followed-player gold wash + tag** — `FieldLeaderboard` already supports
  `highlightIds` (`situations.dart` ≈777, 921–931); the golf branch just passes
  none (`game_detail_page.dart` ≈247). Wire followed athletes in + append the
  `following` tag. (If athlete-following isn't a feature yet, hold the hook.)
- **Hole-by-hole strip** — already built on the drill-down
  (`golf_scorecard_page.dart`); surface a compact strip card on the event page for
  the leader (or followed player when set), lazy via the existing
  `scorecardProvider`.
- **Chip nav** — golf currently renders none. At minimum `Leaderboard` +
  per-round sub-scores; `Course`/`Tee times` only if the core feed carries them
  (don't fabricate tabs for absent data).
- Narrative caption / weather: absent in data (`event.weather = NONE`) — omit
  gracefully, render when present.
- **Mock fix (workstream 8):** align synth's live-golf state — current round in
  the pill vs `GolfMeta.currentRound` vs THRU should agree (live golf should show
  a mid-round leaderboard with varying THRU, current-hole dashed ring).

---

## 8. Mock & fixture tooling (enables verifying all of the above offline)

The bug list was filed against the mock, and several "app bugs" are half
fixture-coverage gaps. Without these, none of the plays-feed work is verifiable
offline:

1. **Stop stripping non-scoring plays for flagship fixtures.**
   `worker/scripts/capture-fixtures.mjs:200` keeps only `scoringPlay===true`.
   Keep the FULL `plays[]` (incl. timeouts, pitch rows/participants) for at least
   one summary per league family — NBA (timeouts, participants), MLB (pitch
   sequence), NHL. Re-run `npm run capture`. Watch fixture size; slim fields, not
   rows (extend `slimPlay`'s picked keys instead of filtering rows).
2. **Capture more summaries per league** so more scoreboard events open rich
   (today MLB has 2 of 14; KC/PHI opens empty). Either capture more, or make
   `synth.mjs` map summary-less events onto a captured summary from the same
   league (deterministic by event id) instead of the empty envelope — the
   cheaper, calendar-proof fix.
3. **Fabricate a gridiron `situation`** on synth-live football events
   (possession, down/distance/spot text, lastPlay) so the CFB/NFL Now tab is
   walkable offline.
4. **Fix synth-live golf**: consistent current round (pill == meta), non-final
   THRU values, a current hole.
5. These are offline-tooling changes only — no goldens impact unless a normalizer
   changes; `npm test` (mock + units suites) must stay green.

---

## 9. DESIGN.md updates (the doc drifted less than the code — but patch these)

1. **§8 Soccer / §10 semantic cells — the share-vs-independent percent rule.**
   Today the doc implies possession's split bar, but nothing forbids gauge bars
   elsewhere. Add an explicit rule: *"A bar compares two sides of one whole
   (possession split, share-of-total). Independent per-team values — counts,
   averages, percents like FG%/SV% — render as number rows (leader white 600,
   centered faint label, trailer dim), never as bars. The center-spine mirrored
   bars are the §10 team-stats comparison card only."*
2. **§8 Baseball box tab — line-score width rule** (from 10d): *"the 9 inning
   columns flex to fill the card (`44px + 9×1fr + R/H/E fixed`); extra innings
   first shrink the cells, then the innings pane alone scrolls; label and R/H/E
   stay pinned."*
3. **§10 table grammar — substitution rows** (new, composed from the grammar):
   *"Replacement players render indented under the man they replaced, with
   ESPN's letter marker (`a-`), and the lineup note as an 11px `textFaint`
   footnote line."*
4. **§9 assignments table — hockey row**: note the Now tab's supporting cards
   (shots pressure + scoring rows per 6c), since hockey's feed archetype (A) is
   otherwise unbuilt.
5. Note in §5 chip-nav that golf's tabs are data-gated (Leaderboard always;
   Course/Tee times only when the feed carries them).

---

## Suggested sequencing

| Phase | Items | Risk |
|---|---|---|
| 1. UI-only quick wins | 1 (soccer stats), 2 (timeline card curation), 3a (line score), 3b UI cap, 4a (virtualization), 6 (hockey cards from existing summary data) | No goldens impact; each independently shippable |
| 2. Tooling | 8 (fixtures/synth) | Unblocks verification of phase 3 |
| 3. Normalizer + UI pairs | 3c (half-inning), 3d (box subs), 4b (participants/timeouts), 5b (drives) | Lockstep JS oracle + Dart + goldens each time |
| 4. Bigger compositions | 3e (all-plays disclosure), 5a (CFB Now resilience), 7 (golf page) | Builds on 2+3 |
| 5. Docs | 9 (DESIGN.md) | Alongside whichever phase lands the pattern |

**Verification checklist per phase:** `flutter analyze` clean · `flutter test`
(incl. `port_*` parity) green · `cd worker && npm test` green · goldens
regenerated when the oracle changed · walk the affected screens on the web build
against `npm run mock` (Playwright: enable Flutter a11y via the
`flt-semantics-placeholder` click, then drive by role/name) · DESIGN.md §11
2-second test on every touched screen.
