# Game-Detail Display Spec (ESPN-grounded)

## Intro: two tiers, one philosophy

This is the canonical merge of 11 per-sport expert specs, reconciled against the adversarial verifier (the verifier wins every conflict). It governs the single game-detail screen (`app/lib/src/ui/game_detail_page.dart`, mobile ~390px, dark-first, Material 3, tabular figures).

The product is **restraint**. Every section must earn its place against the test: *"does this help someone check a score in <2 seconds, then put the phone down?"* No news feed, no engagement traps, no AI, no charts-for-charts'-sake. Betting odds ship OFF by default even where the field is cheap. When in doubt, collapse it or cut it.

Work proceeds in two tiers:

- **CHEAP / scoreboard tier (do now).** Data already in the `/scoreboard` response the app polls every cycle. Surfacing it costs ZERO extra network. The normalizer currently *drops* most of it (`competitor.statistics`, `competitor.leaders`, `competitor.probables`, `competition.situation`, `competitor.hits/errors`, `competitor.form`, golf nested hole linescores, tennis `setWinner`, the cricket sub-object never reaches the Flutter model). The cheap pass = carry that data through `normalize.js` -> `canonical.ts` -> `models.dart` and render sport-aware widgets. This is the priority.
- **RICH / summary tier (later).** Data that exists ONLY in `/summary` and needs ONE extra fetch when a game is opened. **The app does not fetch `/summary` today**, so everything in this tier is structurally impossible until a detail-open fetch path exists. That fetch path is itself the first rich-tier task.

A hard correction the verifier surfaced repeatedly: **per-quarter / per-period line scores are NOT cheap for NBA, NFL, or NHL** — in those manifests the period splits live only in `summary.header.competitor.linescores`. They are cheap (in `competitor.linescores`/`periodScores`) only for MLB, golf, tennis, soccer (suppressed), cricket, and rugby. Do not promise a basketball/football/hockey quarter grid in the cheap pass.

---

## Shared component model

Reusable widgets, each serving multiple sports. New widgets live under `app/lib/src/ui/`. Build these once; parameterize by sport/`scoreKind`/`layout`.

- **LineScoreTable (sport-variant, no-scroll, frozen-column).** Replaces today's generic horizontally-scrollable `_LineScoreTable` (which has no frozen team column and a meaningless Total). One widget, three render modes:
  - *baseball mode* — pinned-left team column, horizontally-scrolling inning block in the middle, pinned-right **R / H / E** summary columns (R bold). Innings not yet played render blank, not 0. (MLB)
  - *compact-grid mode* — fixed `[Team | 1 | 2 | … | Total]`, frozen team column, fits 390px with no scroll (≤6 cols). Used for hockey period grid (1/2/3/OT/SO, label OT/SO not 4/5) and rugby half grid (`[Team | 1st | 2nd | Total]`, Total from `competitor.score`, guard the 4-entry anomaly). NBA/NFL grids reuse this widget **but are rich-tier** (data only in summary).
  - *suppressed* — render nothing for soccer, MMA, racing, golf field layout (the leaderboard/grid replaces it).
- **InningsStack (cricket).** Vertical stack of ≤4 innings rows `"<Team> <runs>/<wkts> (<overs> ov)"` + muted state suffix (`all out`/`declared`). No scroll, no frozen column. Distinct enough from LineScoreTable to be its own widget. (Cricket)
- **SetStrip (tennis).** Fixed strip of ≤5 set cells aligned to each player row, frozen name column, set-winner games bolded, tiebreak superscript best-effort. (Tennis)
- **TeamStatComparison.** Two-column mirrored bar: `value | label | value`, ~5–8 rows, better side bolded, tabular figures. Cheap for soccer (possession/shots from `competitor.statistics`); rich for NBA/NFL/NHL/MLB (this-game stats live in `summary.boxscore.teams`). (Soccer cheap; NBA, NFL, NHL, MLB rich)
- **LeadersStrip.** Per-category leader rows, 2-up away|home, name + value. Cheap for MLB/NBA/NHL (`competitor.leaders`); rich for NFL/cricket/soccer/tennis (empty on their scoreboards). (MLB, NBA, NHL cheap; NFL, soccer, cricket, tennis rich)
- **LiveSituationStrip (per-sport content).** Full-width pill under the header, live-only. Content branches: MLB = count + outs + base diamond + pitcher/batter; NFL = down & distance + possession + red zone + timeouts; cricket = derived CRR/RRR/target line. (MLB cheap; NFL needs verification against a live payload; cricket cheap-derived)
- **ScoringFeed.** Vertical timeline of scoring events only (filter to scoring plays), grouped by period/half/inning, team-aligned, running score right. Rich everywhere (needs `/summary` plays/keyEvents/scoringPlays). (MLB, NBA, NFL, NHL, soccer, rugby)
- **BoxScoreTable.** Collapsed-by-default per-player box, frozen name column, compact stat set, away/home sub-tabs. Rich everywhere. (MLB, NBA, NFL, NHL, cricket)
- **LineupsFormation.** Collapsed starting XI/XV + bench, position-sorted lists (pitch graphic is power-user depth, optional). Rich. (Soccer, rugby)
- **CardList (MMA).** Vertical list of bouts, optionally grouped Main Card / Prelims, each bout = two fighter rows (winner bold + check, loser dim) + result chip. Replaces the head-to-head header for MMA. (MMA)
- **FinishGrid (racing).** Ranked classification: `POS | DRIVER | CONSTRUCTOR | TIME/GAP | STATUS`, frozen POS column, graceful degradation to POS+driver when vehicle/stats empty. Plus a SessionSelector chip row (Practice/Qualifying/Race) and a winner/leader hero callout. (Racing)
- **FieldLeaderboard (golf).** Purpose-built leaderboard: `POS | PLAYER | TO-PAR | TODAY | THRU | R1–R4 | TOT`, sticky POS+PLAYER, under-par accent color, `T{order}` ties, dimmed missed-cut tail. Replaces today's order+name+score `_Leaderboard`. (Golf)
- **FormStrip.** Last-5 W/D/L colored pills per team from `competitor.form`. (Soccer, rugby)
- **StatusChip (sport-aware).** Existing chip, extended per sport: MLB `Bot 6th`/`Final/10`; NHL `Final/OT`/`Final/SO`; NFL/NBA `Q3 5:42`/`Final/OT`; rugby `1st/2nd Half` count-up; cricket `Live`/`Stumps`/`Final`; racing flag color + lap count.

---

## Per-sport layouts

Each section tagged `[cheap]`/`[rich]` and must/should/nice. Order = top-to-bottom on screen. Live and final variants noted inline.

### MLB / Baseball — `headToHead`, inning line score + R/H/E

1. **Header / score** `[cheap]` must — big team rows (crest, name, `records` summary `35-35`, score), baseball-aware StatusChip from `status.shortDetail` (`Bot 6th`, `Final/10`). CORRECTION: winner-bolding/loser-dimming relies on `competitor.winner`, which is **summary-only** (not in the scoreboard competitor key list). Cheap path falls back to `order`/score comparison or run-difference at final; treat true winner styling as rich.
2. **LiveSituationStrip** `[cheap]` must, live — `competition.situation.{balls,strikes,outs,onFirst,onSecond,onThird,pitcher,batter,lastPlay}` + `competition.outsText` (note: `outsText` is on `competition`, not inside `situation`). Use `lastPlay.type.text`/`type.alternativeText`/`athletesInvolved` for the richer "what just happened" line. The #1 reason a fan opens a live game.
3. **LineScoreTable (baseball mode)** `[cheap]` must — `competitor.linescores` + `competitor.hits` + `competitor.errors` for R/H/E; pinned team col + pinned R/H/E, innings scroll. Pre-game collapsed/empty; final = the whole story.
4. **Probable pitchers** `[cheap]` should, pre — `competitor.probables` 2-up away|home.
5. **LeadersStrip** `[cheap]` should — `competitor.leaders` (avg/HR/RBI), 2–3 categories max. CORRECTION: `competition.leaders` is only `MLBRating`; source the card from `competitor.leaders` only.
6. **W / L / SV row** `[cheap]` should, final — team-level indicators from `competitor.statistics` (W/L/SV keys). Named pitcher decisions (`W: Chandler (8-3)`) are **rich** (summary boxscore).
7. **TeamStatComparison** `[cheap]` nice — small collapsible, AVG/ERA only (non-redundant with R/H/E), from `competitor.statistics`.
8. **ScoringFeed** `[rich]` should — `plays[]` where `scoringPlay===true`.
9. **BoxScoreTable / Season series / Win probability** `[rich]` nice.
10. **Meta card** `[cheap]` should — venue/broadcasts/notes (already built).

### NBA / Basketball — `headToHead`, quarter grid

1. **Header / score hero** `[cheap]` must — team rows + score + StatusChip (`Final/OT`/`Final/2OT`, drive OT from `summary.format.overtime`). Records cheap (`competitor.records`), emphasize pre/early, fade at final. CORRECTION: `header.competitor.winner` is summary-only.
2. **Playoff series subtitle** `[cheap]` should — `competition.series` + `competition.notes` carry the trigger (zero-network); the human string `Series tied 1-1` is verified only in `summary.seasonseries`, so render from notes if present else rich.
3. **LeadersStrip (PTS/REB/AST)** `[cheap]` must — `competitor.leaders` (pointsPerGame/reboundsPerGame/assistsPerGame). CORRECTION: drop `competition.leaders` (not in scoreboard). 3 rows max.
4. **LineScoreTable (compact-grid, Q1–Q4 + OT + Total)** `[rich]` should — CORRECTION: per-quarter splits are `summary.header.competitor.linescores`, **not** cheap. Re-tiered to rich; do not build in the cheap pass.
5. **TeamStatComparison** `[rich]` should, final — `summary.boxscore.teams` (FG/3PT/FT%/REB/AST/TO). Do NOT use scoreboard `competitor.statistics` (season averages).
6. **BoxScoreTable / ScoringFeed / possession** `[rich]` should/nice.
7. **Meta card** `[cheap]` should — venue/broadcasts/geoBroadcasts.

### NFL / Football — `headToHead`, gridiron clock + chains

1. **Header / score** `[cheap]` must — score + StatusChip. CORRECTION: this manifest was a PRE capture; `linescores`, `possession`, `record`, `winner`, and the `Quarter` format label all appear only under `summary.header.competitor` here. Treat winner/record/quarter-label as rich-or-verify; only venue/broadcasts are confirmed cheap.
2. **LiveSituationStrip** `[cheap-pending-verification]` must, live — `competition.situation.{down,distance,downDistanceText,possession,isRedZone,homeTimeouts,awayTimeouts}`. Documented shape but absent in this pre-game manifest. Verify against a live NFL scoreboard before building; if confirmed live-cheap, this is the marquee element.
3. **Pre-game meta promotion** `[cheap]` should, pre — kickoff time, network, venue into the header for `state=pre` (venue/broadcasts confirmed cheap).
4. **LineScoreTable (compact-grid)** `[rich]` should — quarter splits are `summary.header.competitor.linescores`.
5. **TeamStatComparison** `[rich]` should — `summary.boxscore.teams` (total yards, first downs, 3rd-down eff, TOP, turnovers, penalties), ~6 rows.
6. **LeadersStrip (pass/rush/rec)** `[rich]` should — `summary.boxscore.players` (NFL scoreboard has no `competitor.leaders`). QB line C/ATT-YDS-TD-INT needs boxscore, not `leaders`.
7. **ScoringFeed by drive / BoxScore / win prob / injuries** `[rich]`.
8. **Meta card** `[cheap]` should. (Odds `competition.odds` and `competition.highlights` are cheap but ship OFF / deferred.)

### NHL / Hockey — `headToHead`, period grid

1. **Header / score** `[cheap]` must — score + records (W-L-OTL `39-26-17`) + StatusChip with OT/SO suffix. CORRECTION: `shootoutScore` and `periodScores` do NOT exist in this manifest; only-per-period data is `summary.header.competitor.linescores`. Shootout data is `boxscore.teams.shootoutGoals` (rich). So OT/SO-suffix logic that depends on a shootout score is rich, not cheap; a regulation-vs-`status` OT label may still be cheap if `status` exposes it (verify).
2. **Starting/probable goalies** `[cheap]` should, pre — `competitor.probables` present (cheap), but the field mapping is `name`=label string/`probables:["Carter Hart"]` flat array — read the flat name, show `name + 'G'`.
3. **LeadersStrip (G/A/PTS)** `[cheap]` should — `competitor.leaders` present; CAVEAT sample reads as a SEASON total — label as season or prefer summary for game scope.
4. **LineScoreTable (compact-grid 1/2/3/OT/SO/T)** `[rich]` must — CORRECTION: per-period splits are summary-only; re-tiered rich.
5. **TeamStatComparison (SOG/PP/FO%/hits/PIM)** `[rich]` should — `summary.boxscore.teams` (SOG = `shotsTotal`, not season G). Add `penalties`/`PN` alongside `penaltyMinutes`.
6. **ScoringFeed / three stars / box / onIce / injuries / series** `[rich]`.
7. **Meta card** `[cheap]` should — venue/broadcasts. (Odds cheap, OFF by default.)

### Soccer (World Cup + EPL) — `headToHead`, no line score

1. **Header / score** `[cheap]` must — team rows, `competitor.winner` (Draw when both false), records (W-D-L triple `14-11-13`), StatusChip (`67'`/`HT`/`FT`). CORRECTION: `shootoutScore`/`aggregateScore` are NOT in the scoreboard — penalty `1 (4)` / aggregate cannot be promised at cheap tier; render only a generic decision string until a real source is confirmed.
2. **FormStrip** `[cheap]` should — `competitor.form` (W/D/L dots, newest right).
3. **TeamStatComparison** `[cheap]` must, live — **the flagship cheap win**. `competitor.statistics`: `PP`->Possession, `SHOT`->Shots, `SOG`->Shots on target, `CW`->Corners, `FC`->Fouls. ~5 rows, mirrored bars, no scroll. Show live + final; hide pre.
4. **Round/group/matchday context** `[cheap]` should — `competition.notes`/`altGameNote` (round/leg). World Cup group identity is also in `summary.header.competitor.groups` (rich). Quiet caption near top.
5. **Suppress generic line score** `[cheap]` must — `competition.format` = `{regulation:{periods:2}}`; halves table is meaningless.
6. **ScoringFeed (keyEvents)** `[rich]` should — soccer has NO `plays` array; use `summary.keyEvents` + `summary.commentary`, grouped by half. The single most valuable rich add.
7. **LineupsFormation / full team stats / standings+H2H+last5 / officials / leaders** `[rich]`.
8. **Meta card** `[cheap]` should — venue/broadcasts + `competition.attendance` (cheap, currently unsurfaced). (Odds cheap, OFF by default.)

### Golf — `field` leaderboard

1. **Tournament header** `[cheap]` must — event name + round/status chip + venue line. CORRECTION: status sub-fields (`status.detail/period/periodLabel`) and `event.name`/`venue` are not enumerated in the (thin) golf manifest; treat as derived from the canonical model, not verified scoreboard fields. Par/purse are rich.
2. **FieldLeaderboard** `[cheap]` must — the screen. `competitor.order` (POS, render `T{order}` on ties), athlete name, `competitor.score.display` as TO-PAR lead column with under-par accent, and `competitor.linescores` for R1–R4 (`period`=round, `displayValue`=round to-par, `value`=round strokes), TODAY (linescore where `period==status.period`), THRU (count of nested hole linescores, `F` at 18), TOT (sum of round `value`). Sticky POS+PLAYER; full field, not capped at 40.
3. **Leader emphasis** `[cheap]` should — bold/accent `order==1` row; bold winner at Final.
4. **Cut line / missed-cut tail** `[cheap-derived]` should, live — dim CUT/WD/DQ players into a tail group; derive, don't fabricate a projected line.
5. **Per-player hole detail (expand)** `[cheap]` nice, live — nested `competitor.linescores[].linescores` (per hole). Currently dropped by the normalizer.
6. **Tee times** `[rich]` should, pre.
7. **Meta card** `[cheap]` should — venue/broadcasts/`geoBroadcasts`. Note `competitor.statistics` exists but is empty here.
8. **No `/summary`** — golf summary returned 502; all rich golf claims unverified.

### Tennis — `headToHead` (homeAway meaningless), set-by-set

1. **Match header (two player rows)** `[cheap]` must — seed chip from `competitor.order` (no crest), player name, sets-won tally = count of `linescores[].winner===true`, winner bold. CORRECTION: status sub-states (live/Final/scheduled) are not enumerated; verify. Use `competition.date`/`startDate`/`timeValid` for the pre-match time.
2. **SetStrip** `[cheap]` must — `competitor.linescores[].value` + `.winner`, frozen name col, ≤5 cells, no scroll, set-winner games bold. CORRECTION: `linescores[].tiebreak` is NOT in this manifest — tiebreak superscripts are unverified/best-effort, NOT a confirmed cheap win; gate behind presence check.
3. **Match context line** `[cheap]` should — `competition.round`, `wasSuspended`. Decision text (`ret.`/`w/o`/`def.`) depends on undocumented status sub-fields — verify before mapping.
4. **LiveServeStrip** `[rich]` should, live — not in scoreboard; summary returned HTTP 400 for the sample, so availability uncertain.
5. **Match stats / point-by-point / H2H** `[rich]` nice — `competitor.statistics` is empty `[]`; summary failed. Render nothing rather than zeros.
6. **Meta card** `[cheap]` nice — venue/broadcasts (+ singular `broadcast`).

### MMA / UFC — fight-card list (NOT head-to-head)

1. **Event header** `[cheap]` must — event name + date + single status line. Replace the two-fighter scoreline. CORRECTION: `event.shortName`/`event.start` are mislabeled — competition exposes `date`/`startDate`, not `start`.
2. **CardList (full fight card)** `[cheap]` must — **biggest gap**: iterate `event.competitions` (today only `event.main`/`competitions.first` renders 1 of ~13). Each bout: two fighter rows (name + `competitor.records` `10-5-0`), winner bold + check (reuse `scoreKind=='none'` logic), loser dim. No periodScores line score (suppress). Handle Draw / No Contest (no check).
3. **Card-segment grouping** `[cheap]` should — `cardSegment.description` -> `meta.cardSegment` when present; flat list otherwise (undefined in this sample — degrade gracefully).
4. **Result method per bout** `[cheap-pending-verification]` should, final — `method.{kind,detail,finishRound,finishTime}`. CORRECTION: NO `method` object in this manifest; only `status.detail`/`shortDetail` = `Final`. Probe `competition.details` and core-API status `$ref` (the normalizer's mma decorator reads `status.result`); if unavailable from scoreboard, this is rich.
5. **Featured spotlight** `[cheap-pending-verification]` should — `meta.featured`/`status.featured` NOT in this manifest; fall back to last-in-card-order as main event.
6. **Live bout indicator** `[cheap-pending-verification]` should, live — `Round {status.period} · {status.clock}`; status sub-fields unverified here.
7. **Per-bout timing** `[cheap]` nice — `competition.startDate`/`endDate` (which fight next/when). **Highlights** `[cheap]` nice — `competition.highlights`/`playByPlayAvailable` (deferred).
8. **Judges' scorecards / fighter stats / tale-of-tape** `[rich]`.
9. **Meta card** `[cheap]` nice — venue/broadcasts (NO `notes` key in this manifest).

### Auto Racing (F1 / NASCAR) — `field`, multi-session weekend

1. **Event header** `[cheap]` must — race name + circuit (`circuit` confirmed in event keys; `event.venue` is NOT — use `circuit`) + session status.
2. **SessionSelector** `[cheap]` must — **biggest structural gap**: render ALL `event.competitions` (today `competitions.first` shows one session). Chip row from `competition.type`/`status`/`date`; default to live session, else Race-if-final, else next scheduled.
3. **Winner/podium hero (or leader live)** `[cheap]` should — `competitor.order==1`, athlete name; constructor from `vehicle.manufacturer`. CORRECTION: `vehicle` was `undefined` in this capture and is not a confirmed competitor key — treat constructor/number as aspirational with graceful degradation.
4. **FinishGrid** `[cheap]` must — `competitor.order` + athlete (confirmed); `vehicle.*`, gaps inside `competitor.statistics`, and per-row status guard against empty/undefined (statistics was `[]`). Full field, not capped at 40.
5. **Flag state chip** `[cheap-pending-verification]` med — `meta.flag` is a normalizer/decorator output, NOT a manifest field; surface only if populated.
6. **Grid->finish delta** `[cheap-pending-verification]` nice, final — `competitor.startOrder` not in this capture; show only when present.
7. **Meta card** `[cheap]` should — `circuit`, broadcasts/`geoBroadcasts`, `highlights`, `links`, `startDate`/`endDate`/`timeValid`.
8. **No `/summary`** — racing has no summary endpoint; all racing data is scoreboard-tier or out of scope.

### Cricket — innings-stack

1. **Header / match result line** `[cheap]` must — two teams stacked, each `runs/wickets (overs)` from `competitor.score` + `linescores`, winner bold, StatusChip (`Live`/`Stumps`/`Final`). CORRECTION: `meta.cricketSummary` is NOT in this manifest and the status sub-fields are unenumerated — surface the match-state subtitle from `status.detail` if present; do not promise an authored "need 250 to win" line at cheap tier until a real source is confirmed.
2. **Format badge** `[cheap]` should — from `competition.class` (NOT `meta.cricketClass`, which is a normalizer output). Tells the fan how many innings to expect.
3. **InningsStack** `[cheap]` must — `linescores.{period,runs,wickets,overs,isBatting,description,isCurrent}`. CRITICAL: `PeriodScore.fromJson` in `models.dart` drops the cricket sub-object the normalizer already emits — fix the parse first. ≤4 rows, no scroll, highlight `isCurrent`/`isBatting`, muted `all out`/`declared` suffix from `description`.
4. **Live rate strip** `[cheap-derived]` should, live — CRR = runs/overs. CORRECTION: `linescores.target` is NOT in this manifest, so RRR/target/"runs needed" cannot be promised — render CRR only until target is confirmed in a real payload.
5. **Top performers / full scorecard / series / weather** `[rich]` — `competitor.leaders`/`statistics` empty on cricket scoreboard.
6. **Meta card** `[cheap]` should — venue/broadcasts/notes (`Day N of M` in `notes` matters for Tests). (Odds `competition.odds`, highlights cheap; deferred/OFF.)

### Rugby — two-team-halves

1. **Header / score** `[cheap]` must — score + records + StatusChip. CORRECTION: the `Half` label / count-up clock / `clock=2400` are in `summary.format` only — the scoreboard format is `{regulation:{periods:2}}`. Hardcode half labels and 40:00 count-up rather than claiming them as cheap fields. `records` sample is `WLWWW` (a streak, not a W-L-D record) — do not present it as a season record string.
2. **FormStrip** `[cheap]` should — `competitor.form` (the single best context signal this league returns; stat panels are empty).
3. **LineScoreTable (compact-grid `[Team | 1st | 2nd | Total]`)** `[cheap]` must — `competitor.linescores` by `period` (period1->1st, period2->2nd); Total from `competitor.score`; guard the 4-entry anomaly (drop period>2 with zero value, render extra-time only when non-zero). Frozen team col, no scroll.
4. **Suppress stat panels** — `competitor.statistics` and `summary.boxscore` are empty for this league; do NOT build a stat-comparison block (dead UI).
5. **ScoringFeed** `[rich-uncertain]` should, final — `playByPlayAvailable=true` but no `plays`/`scoringPlays` enumerated; probe scoreboard `competition.details` first, verify summary before building.
6. **Lineups / H2H+last5 / standings / possession** `[rich]`.
7. **Meta card** `[cheap]` should — venue/broadcasts/`geoBroadcasts`/notes; suppress attendance when 0. **Highlights** `[cheap]` nice — `competition.highlights`.

---

## Schema / normalizer changes

All additive, all optional — they only carry cheap-tier scoreboard data the normalizer currently drops. Touch `schema/canonical.ts` (contract), `worker/src/normalize.js` (populate), `app/lib/src/models.dart` (parse).

- **`Competitor.stats?: Record<string,string|number>`** — already in `canonical.ts` but never populated. In `normalize.js`, map `raw.statistics[]` (`{name|abbreviation, value|displayValue}`) into a keyed map. Add a `stats` field + parse to `models.dart`. Serves: MLB (W/L/SV, AVG, ERA), soccer (PP/SHOT/SOG/CW/FC). (Season-average caveat for NBA/NHL — do not present those as game stats.)
- **`Competitor.leaders?: { category: string; value: string; athlete: string }[]`** — new. Populate from `raw.leaders[]` (the rich per-competitor leaders, NOT `competition.leaders`). Serves MLB, NBA, NHL.
- **`Competitor.probables?: { name: string; role?: string }[]`** — new. Populate from `raw.probables` (handle both shapes: `[{name,displayName}]` labels and the flat `["Carter Hart"]` name array). Serves MLB (pitchers), NHL (goalies).
- **`Competitor.hits?: number; errors?: number`** — new. Populate from `raw.hits`/`raw.errors`. Serves MLB R/H/E.
- **`Competitor.form?: string`** — new (e.g. `WLWWW`). Populate from `raw.form`. Serves soccer, rugby.
- **`Competition.situation?: Situation`** — new interface `{ balls?, strikes?, outs?, onFirst?, onSecond?, onThird?, pitcher?, batter?, lastPlay?: { text?, typeText?, altText?, athletes? }, down?, distance?, downDistanceText?, possession?, isRedZone?, homeTimeouts?, awayTimeouts?, outsText? }`. Populate from `competition.situation` (+ `competition.outsText` folded in). Serves MLB live (confirmed) and NFL live (verify against live payload). Render only when `status.live`.
- **`PeriodScore.setWinner`** — already in `canonical.ts`; the normalizer never sets it and `models.dart` never parses it. In `normalize.js` map `linescores[].winner -> setWinner`; add `setWinner` to `PeriodScore.fromJson`. Serves tennis.
- **`PeriodScore.cricket` reaches the client** — `normalize.js` already emits it; `PeriodScore.fromJson` in `models.dart` drops it. Add `cricket: { runs, wickets, overs?, isBatting?, reason? }` to the Dart `PeriodScore`. (Do NOT add `target` — unconfirmed.) Serves cricket InningsStack.
- **Golf nested hole linescores** — `buildCompetitor` maps only top-level rounds. Carry `linescores[].linescores[]` (per hole: `period`=hole, `value`=strokes, `displayValue`=hole to-par) into a nested field on `PeriodScore`. Also set `Score.strokes` for `toPar` scoreKind by summing round `value`s (currently only `toPar` is set, so TOT has no backing). Serves golf THRU + TOT + hole-expand.
- **`Competitor.vehicle`** — already in `canonical.ts`; `normalize.js` already `pick`s it; `models.dart` `Competitor` has NO `vehicle` field, so it's dropped at the app boundary. Add `vehicle` to the Dart model. Serves racing constructor/number (degrade gracefully — empty in capture).
- **MLB `winner`** — note in the contract that `competitor.winner` is summary-only for MLB; cheap-path winner styling must fall back to score/order. No schema change, just a documented caveat so the UI doesn't assume it.

---

## Out of scope for the cheap pass

Everything below waits for a `/summary` detail-open fetch path (which does not exist today and is the first rich-tier task):

- All **ScoringFeed** instances (MLB `plays`, NBA/NFL/NHL `plays`/`scoringPlays`/`drives`, soccer `keyEvents`/`commentary`, rugby — and verify rugby/MMA scoring even exist).
- All **BoxScoreTable** (per-player) and **TeamStatComparison for NBA/NFL/NHL/MLB this-game stats** (`summary.boxscore.teams`/`players`).
- **LineupsFormation** (soccer/rugby `rosters`), **named pitcher decisions** (MLB), **three stars** (NHL), **judges' scorecards / fighter stats** (MMA), **tee times / par / purse / flags-as-graphics** (golf), **live serve indicator + match stats** (tennis).
- **NBA/NFL/NHL per-period line scores** (the quarter/period grid) — summary-only despite being a "must" visually; build the widget now, wire data in the rich pass.
- **Season series / standings / H2H / last-5 / injuries / win probability / officials / weather / possession indicators / news / highlights-as-media / odds** across all sports. Odds ship OFF by default even where the scoreboard field is cheap.
- Anything tagged `[cheap-pending-verification]` above (NFL live situation strip, MMA method/featured/live, racing flag/startOrder, cricket target/cricketSummary, tennis tiebreak/decision text) — confirm the field exists in a real live payload before implementing; if it isn't there, it moves to rich or is cut.

---

## Implemented in this pass (zero-network cheap tier)

All verified with `flutter analyze` (clean), `flutter test` (5/5), and the worker normalizer test (1457/0) against real ESPN data.

- **Data layer** — the normalizer (`worker/src/normalize.js`) now carries the scoreboard fields it was dropping: `hits`, `errors`, `form`, team `stats` (keyed), `leaders`, `probables` on each competitor, and a sport-agnostic `situation` on the competition. Declared in `schema/canonical.ts` and parsed in `app/lib/src/models.dart` (incl. `PeriodScore.cricket`/`setWinner`, new `Leader`/`Probable`/`Situation`/`CricketScore`).
- **MLB R/H/E line score** — new `LineScoreTable` (`score_tables.dart`): frozen team column, innings scroll only on extras, pinned **R/H/E** (R bold), always shows the 9-inning slate. Replaces the generic sideways-scroll grid.
- **Live situation strip** — `LiveSituationStrip`: balls-strikes, outs, base diamond, pitcher/batter, last play (live only).
- **Leaders** — `LeadersStrip`: two-up away|home, from `competitor.leaders` (MLB/NBA/NHL).
- **Team stats** — `TeamStatComparison`: mirrored bars (soccer possession/shots/corners/fouls from `competitor.statistics`).
- **Recent form** — `FormStrip`: last-5 W/D/L pills (soccer/rugby).
- **Probable starters** — `ProbablesRow` (pre-game, MLB/NHL).
- **Cricket innings** — `InningsStack`: runs/wkts (overs) per innings, no scroll.
- **Tennis sets** — `SetStrip`: set-by-set with winning sets bold + sets-won tally.
- **MMA whole card** — `MmaCardList`: every bout (not just one), grouped by card segment, winner/loser styling.

## Remaining cheap-tier backlog (next pass)

- Golf `FieldLeaderboard` (TO-PAR/THRU/R1–R4/TOT) — needs nested per-hole linescores + `Score.strokes` carried through the schema.
- Racing `FinishGrid` + session selector — `vehicle`/constructor is empty in the sampled API; surface POS+driver first, degrade gracefully.
- Sport-aware `StatusChip` polish (OT/SO/half labels) and meta-card additions (attendance≠0, geoBroadcasts, season-series line).
- NBA/NFL/NHL per-quarter/period grids and live down-&-distance: **summary-tier** (data is not in the scoreboard) — unlocked once a detail-open `/summary` fetch exists.

## Appendix A — Ranked cheap-wins backlog (expert panel)

**#1 [shared] Add /summary-independent detail-open scaffolding: replace event.main with full competitions iteration where the sport is multi-competition (MMA card, racing weekend)**
- fields: `event.competitions`, `competition.type`, `competition.status`, `competition.date`
- files: app/lib/src/ui/game_detail_page.dart
- game_detail_page.dart line 14 uses event.main (competitions.first), so MMA renders 1 of ~13 bouts and racing renders 1 of 5 sessions. Branch: MMA -> CardList over all competitions; racing -> SessionSelector + FinishGrid; everyone else keeps single-competition. Pure layout, zero network. Unblocks the two biggest structural gaps.

**#2 [shared] Carry dropped scoreboard fields through the schema: competitor.stats (statistics), leaders, probables, hits, errors, form**
- fields: `competitor.statistics`, `competitor.leaders`, `competitor.probables`, `competitor.hits`, `competitor.errors`, `competitor.form`
- files: worker/src/normalize.js, schema/canonical.ts, app/lib/src/models.dart
- Single plumbing pass that unblocks MLB R/H/E + leaders + probables + W/L/SV, soccer/MLB/NBA/NHL stats, soccer/rugby form, NBA/NHL leaders. stats already in canonical.ts but unpopulated; leaders/probables/hits/errors/form are new optional fields. Map raw.statistics[] -> keyed map; raw.leaders[] (NOT competition.leaders); raw.probables (handle label-shape AND flat name-array shape); raw.hits/errors/form direct.

**#3 [shared] Replace generic horizontal-scroll line score with sport-variant LineScoreTable (frozen team column, no-scroll compact grid, baseball R/H/E mode)**
- fields: `competitor.linescores`, `competitor.score`, `competitor.hits`, `competitor.errors`, `competition.format.regulation.periods`
- files: app/lib/src/ui/game_detail_page.dart, app/lib/src/ui/line_score_table.dart
- New widget file. Modes: baseball (pinned team + pinned R/H/E, innings scroll, blank unplayed innings, R bold); compact-grid (hockey 1/2/3/OT/SO/T, rugby 1st/2nd/Total) frozen team col fits 390px no scroll; suppressed for soccer/MMA/racing/golf. Drives Total from competitor.score (guard rugby 4-entry anomaly). Today's _LineScoreTable has no frozen col and a meaningless Total. NBA/NFL/NHL quarter data is summary-only (rich) — widget ready, data later.

**#4 [mma] Render the whole fight card as CardList (two fighter rows, winner check + loser dim, records, Draw/NC handling, Main Card/Prelims grouping)**
- fields: `event.competitions`, `competitor.athlete`, `competitor.winner`, `competitor.records`, `meta.cardSegment`
- files: app/lib/src/ui/game_detail_page.dart, app/lib/src/ui/card_list.dart
- Reuse scoreKind=='none' check + dim logic. Group by meta.cardSegment when present, flat otherwise (undefined in sample — degrade). Suppress the period line score. Result method line + featured spotlight are pending-verification (status.result/details, not in this manifest) — render status.detail ('Final') for now.

**#5 [golf] Build FieldLeaderboard: POS/PLAYER/TO-PAR/TODAY/THRU/R1-R4/TOT with sticky POS+PLAYER, under-par accent, T{order} ties, dimmed missed-cut tail**
- fields: `competitor.order`, `competitor.score`, `competitor.linescores`, `competitor.linescores.value`, `competitor.linescores.displayValue`, `competitor.linescores.period`, `status.period`
- files: app/lib/src/ui/game_detail_page.dart, app/lib/src/ui/field_leaderboard.dart, worker/src/normalize.js, schema/canonical.ts, app/lib/src/models.dart
- Today's _Leaderboard shows only order+name+score. TODAY = linescore where period==status.period; THRU = count of nested hole linescores ('F' at 18); TOT = sum of round value. Requires carrying nested hole linescores (rank 8) and Score.strokes (sum of round values). Full field, not capped at 40. Ties render T{order}.

**#6 [mlb] LiveSituationStrip (baseball): count + outs + base diamond + pitcher/batter + lastPlay**
- fields: `competition.situation.balls`, `competition.situation.strikes`, `competition.situation.outs`, `competition.situation.onFirst`, `competition.situation.onSecond`, `competition.situation.onThird`, `competition.situation.pitcher`, `competition.situation.batter`, `competition.situation.lastPlay`, `competition.outsText`
- files: worker/src/normalize.js, schema/canonical.ts, app/lib/src/models.dart, app/lib/src/ui/live_situation_strip.dart
- Add Competition.situation interface (additive). outsText is on competition, not situation. Use lastPlay.type.text/alternativeText/athletesInvolved for the 'what just happened' line. Render only when status.live. The #1 reason a fan opens a live MLB game.

**#7 [cricket] Fix PeriodScore.fromJson to carry the cricket sub-object, then render InningsStack (runs/wkts (overs), all out/declared, highlight isCurrent)**
- fields: `competitor.linescores.runs`, `competitor.linescores.wickets`, `competitor.linescores.overs`, `competitor.linescores.isBatting`, `competitor.linescores.description`, `competitor.linescores.isCurrent`
- files: app/lib/src/models.dart, app/lib/src/ui/game_detail_page.dart, app/lib/src/ui/innings_stack.dart
- normalize.js already emits periodScores[].cricket; models.dart PeriodScore.fromJson drops it (reads only period/value/display/tiebreak). Add cricket{runs,wickets,overs,isBatting,reason}. Replace generic table with <=4-row vertical stack, no scroll. Do NOT add target (unconfirmed). Header runs/wkts(overs) depends on this too.

**#8 [golf] Stop dropping golf nested per-hole linescores and populate Score.strokes for toPar (TOT backing + THRU + hole-expand)**
- fields: `competitor.linescores`, `competitor.linescores.linescores`, `competitor.linescores.value`
- files: worker/src/normalize.js, schema/canonical.ts, app/lib/src/models.dart
- normalize.js buildCompetitor maps only top-level rounds (lines ~76-91). Carry linescores[].linescores[] (per hole). buildScore sets only toPar for golf — also sum round values into Score.strokes so the TOT column has data. Prereq for rank 5 THRU/TOT/expand.

**#9 [tennis] Populate setWinner in normalizer + parse it, then render SetStrip (frozen name col, <=5 set cells, set-winner games bold, sets-won tally)**
- fields: `competitor.linescores.value`, `competitor.linescores.winner`, `competitor.winner`
- files: worker/src/normalize.js, app/lib/src/models.dart, app/lib/src/ui/set_strip.dart, app/lib/src/ui/game_detail_page.dart
- setWinner is in canonical.ts but the normalizer never sets it and models.dart never parses it. Map linescores[].winner -> setWinner; add to PeriodScore.fromJson. Sets-won = count of setWinner true. Seed chip from competitor.order (no crest). Tiebreak superscript is pending-verification (tiebreak absent in manifest) — gate behind presence check.

**#10 [soccer] TeamStatComparison from competitor.statistics (Possession/Shots/SOG/Corners/Fouls) + suppress the halves line score**
- fields: `competitor.statistics`, `competition.format`
- files: app/lib/src/ui/game_detail_page.dart, app/lib/src/ui/team_stat_comparison.dart
- Flagship soccer cheap win. Map PP->Possession, SHOT->Shots, SOG->Shots on target, CW->Corners, FC->Fouls. 5 rows, mirrored 2-col bars, no scroll, live+final, hide pre. Suppress generic line score (format periods=2, halves table meaningless). Depends on rank 2 (stats plumbing).

**#11 [shared] LeadersStrip widget (2-up away|home, category/value/athlete) wired for MLB (avg/HR/RBI), NBA (PTS/REB/AST), NHL (G/A/PTS)**
- fields: `competitor.leaders`
- files: app/lib/src/ui/leaders_strip.dart, app/lib/src/ui/game_detail_page.dart
- Depends on rank 2 (leaders plumbing). Cap at 2-3 categories. MLB uses competitor.leaders ONLY (competition.leaders is MLBRating). NHL/NBA scoreboard leaders may be season totals — label accordingly. Drop competition.leaders citations entirely.

**#12 [shared] FormStrip (last-5 W/D/L pills) for soccer and rugby**
- fields: `competitor.form`
- files: app/lib/src/ui/form_strip.dart, app/lib/src/ui/game_detail_page.dart
- Depends on rank 2 (form plumbing). 5 pills newest-on-right (green W / grey D / red L). The single highest-value context signal for rugby (stat panels are empty there).

**#13 [mlb] Probable pitchers (pre) + W/L/SV decision row (final) from probables and team statistics**
- fields: `competitor.probables`, `competitor.statistics`
- files: app/lib/src/ui/game_detail_page.dart
- Depends on rank 2. Probables 2-up away|home pre-game. W/L/SV team-level indicators from statistics at final (named pitcher decisions are rich/summary). Reuse LeadersStrip 2-up layout.

**#14 [racing] FinishGrid + SessionSelector + winner/podium hero, with graceful degradation and full field**
- fields: `competitor.order`, `competitor.athlete`, `competitor.statistics`, `competition.type`, `competition.status`, `circuit`
- files: app/lib/src/ui/game_detail_page.dart, app/lib/src/ui/finish_grid.dart, worker/src/normalize.js, app/lib/src/models.dart
- FinishGrid: POS|DRIVER|CONSTRUCTOR|TIME/GAP|STATUS, frozen POS, degrade to POS+driver when vehicle/statistics empty (both empty/undefined in capture). Add vehicle to models.dart Competitor (already in canonical.ts + emitted by normalize.js, dropped at app boundary). Add circuit read to normalizer/model. flag/startOrder are pending-verification (decorator/absent) — show only when present. Full field, not capped at 40. Depends on rank 1 (session iteration).

**#15 [shared] Sport-aware StatusChip extensions (OT/SO/half/inning/quarter/flag/lap, Final/OT, Bot 6th, FT, Stumps)**
- fields: `status.detail`, `status.shortDetail`, `status.period`, `status.periodLabel`, `competition.format.regulation.periods`
- files: app/lib/src/ui/widgets.dart, app/lib/src/ui/game_detail_page.dart
- Pure status logic, zero network. MLB Bot 6th/Final/10; NHL Final/OT|SO (suffix from status, NOT shootoutScore which is absent); NBA/NFL Q3 5:42/Final/OT; rugby 1st/2nd Half count-up (hardcode 40:00 - Half label is summary-only); cricket Live/Stumps/Final. Verify status sub-fields exist where flagged pending-verification.

**#16 [shared] Meta card cheap additions: attendance (suppress 0), geoBroadcasts, notes surfacing, circuit-over-venue for racing**
- fields: `competition.attendance`, `competition.geoBroadcasts`, `competition.broadcast`, `competition.notes`, `circuit`
- files: app/lib/src/ui/game_detail_page.dart, worker/src/normalize.js, app/lib/src/models.dart
- Soccer/rugby attendance is cheap and currently unsurfaced (suppress when 0). Add geoBroadcasts + singular broadcast (tennis often populates singular only). Surface notes (cricket 'Day N of M'). Racing prefers circuit. Low-effort polish across many sports.


## Appendix B — Observed ESPN mobile ordering (390px, 2026-06-13)

Screenshots in `.scratch/espn/screenshots/`.

Screenshots: espn-mlb-mobile.png, espn-nba-mobile.png, espn-nfl-mobile.png, espn-soccer-mobile.png (project root)

## Universal spine (team sports)
Header(score/status) → [Video Highlights] → [Recap] → **Game/Match Leaders** → **Win Probability / Game Flow** → **Team Stats (comparison)** → [sport modules] → Standings/Series → News → Game Information

Key takeaway: **Leaders** and **Team Stats** sit high on EVERY team-sport page, and both are in the
CHEAP scoreboard tier (competitor.leaders, competitor.statistics) — universal zero-cost wins.

## MLB (gameId 401815738) — Yankees 3-1 Blue Jays
Order: Header → Video Highlights → Recap → HR/scoring plays → **W/L/SV pitcher decisions** → **Line score** → Scoring Summary → Game Odds → Win Probability → Series ("Series tied 1-1") → Game Info
- Line score table headers: `1 2 3 4 5 6 7 8 9 | R | H | E`  (all 9 innings + R/H/E in ONE table, frozen team col)
- Batting box (compact mobile): `hitters | H-AB | R | HR | RBI | AVG`
- Pitching box (compact mobile): `pitchers | IP | H | ER | BB | K | PC-ST | ERA`
- Pitcher decisions row: W (Cruz 4-1), L (Varland 3-2), SV (Bednar 14)

## NBA (gameId 401859966) — Knicks 107-106 Spurs
Order: Header → Highlights → Recap → **Game Leaders** → Probabilities & Game Flow → Shot Chart → **Team Stats** → Matchups → Standings → News → Game Info
- Line score headers: `1 2 3 4 T`
- Standings cols: `W L PCT GB STRK`

## NFL (gameId 401772988) — Seahawks 29-13 Patriots (Super Bowl LX)
Order: Header → **Game Leaders** → Probabilities → **Team Stats** → Standings → News → Game Info
- Line score headers: `1 2 3 4 T`

## Soccer (gameId 760420) — Qatar 1-1 Switzerland (World Cup)
Order: Header → Recap → **Commentary (timeline)** → **Formations & Lineups** → **Match Leaders** → **Team Stats** → **Shot Map** → Game Odds → Head-To-Head → Standings → News → Game Info
- No line-score table (soccer); timeline + lineups + team stats are the core.
- Standings cols: `GP W D L GD P`

---

## Update 2 — both tracks shipped (cheap remainder + the rich /summary tier)

Verified end-to-end: `flutter analyze` clean · `flutter test` 6/6 (incl. a rich-tier render test against a real normalized NFL summary) · worker `node test/normalize.test.mjs` 1457/0 · `node test/summary.test.mjs` 211/0 · live `wrangler dev` serving `/v1/summary/...` 200 OK.

### Track A — remaining cheap (zero-network) wins
- **Golf** `FieldLeaderboard` (`field_leaderboard.dart`): POS (T-ties) · PLAYER (frozen) · TO-PAR (under-par accent) · THRU · TODAY · R1–Rn · TOT. Normalizer now carries per-round `holesPlayed` (THRU) and sums round strokes into `Score.strokes` (TOT).
- **Racing** `FinishGrid` (`finish_grid.dart`): session selector (FP1/Qual/Race via new `Competition.label`) + finishing grid (POS/DRIVER/CONSTRUCTOR/STATUS, constructor column auto-omitted when empty, winner highlight). Replaces showing 1 of 5 sessions.
- **Tennis** set-winner bolding now works (`PeriodScore.setWinner` populated).

### Track B — the rich tier (one extra `/summary` fetch on detail-open)
- **Worker**: new `GET /v1/summary/{sport}/{league}/{eventId}` → `summary.js` normalizes ESPN's summary into a generic `GameSummary` (team-stat comparison, per-player `boxGroups`, scoring/keyEvent feed, per-period `periodLines`, soccer/rugby `lineups`). One generic shape spans every sport. TTL 20s live / 5m final.
- **App**: `Api.summary()`, `summaryProvider` family (lazy, keyed by league+eventId), `GameSummary` models.
- **Widgets**: `BoxScoreTable` (collapsible per-group, frozen name col), `SummaryTeamStats` (mirrored bars), `PeriodLinesGrid` (NBA/NFL quarters, NHL periods incl. OT/SO), `ScoringFeed` (grouped timeline), `LineupsView` (XI + bench + formation).
- **Detail page** is now a `ConsumerWidget`: cheap sections render instantly; a best-effort `_RichDetail` fetches `/summary` and appends the rich sections (sport-gated — e.g. no play-by-play feed for basketball; rich quarter grid only for sports whose scoreboard lacks linescores). Failures stay silent; a skeleton shows while loading.

### Still open (deliberately deferred)
- **Live box-score refresh**: `/summary` is fetched once on open (no 15s polling yet). Add timer-driven `ref.invalidate(summaryProvider(key))` while the game is live.
- **Golf hole-by-hole expand** and **win-probability chart** (betting-adjacent; low glance value) — not built.
- **Home `GameCard`** still shows score only; a live R/H/E or count glance could be added later.
