# Normalized sports schema

> The canonical data model every screen is built on. Designed from **live ESPN
> responses verified June 2026** and hardened by an adversarial verification pass
> (which caught ~30 hallucinated ids / wrong status names / bad field paths — see
> `.research-digest.md` for the raw evidence).
>
> Three files, one contract:
> - **`canonical.ts`** — the canonical types the normalizers emit and the UI consumes.
> - **`league-profiles.json`** — the data-driven league registry (inheritance).
> - **`SCHEMA.md`** (this) — how they fit, the mappings, the quirks, examples.
>
> **Note on producer:** this doc predates `drop-the-worker.md` and still says
> "the worker" and names `/v1/…` routes + `worker/src/*.js`. The **canonical shape
> is unchanged** — only the producer moved: the normalizers now run **on-device**
> in `app/lib/src/data/` (faithful Dart ports of those same `worker/src/*.js`,
> which survive as the golden-parity oracle). Read "the worker emits X on `/v1/Y`"
> as "the app builds X via `api.dart`'s `Y(...)`". ESPN→canonical mappings + quirks
> below are all still accurate.

---

## 1. The three-layer model

You asked for "a generic format for all sports, then a generalized baseball one,
then inherited NBA/WNBA/CBB/WCBB-style differences." That's exactly the shape:

```
                ┌─────────────────────────────────────────┐
   LAYER 1      │  Universal contract (canonical.ts)        │
   the shape    │  Event → Competition → Competitor         │
                │  + 3 discriminators: layout, scoreKind,   │
                │    competitorKind                         │
                └─────────────────────────────────────────┘
                                  ▲ instantiated by
                ┌─────────────────────────────────────────┐
   LAYER 2      │  Family profiles (league-profiles.json)   │
   the defaults │  soccer · football · basketball · baseball│
                │  hockey · tennis · golf · racing · mma ·  │
                │  cricket · rugby · rugby-league           │
                │  → period unit, OT model, score kind,     │
                │    where edge data lives                  │
                └─────────────────────────────────────────┘
                                  ▲ extends
                ┌─────────────────────────────────────────┐
   LAYER 3      │  League overrides (league-profiles.json)  │
   the deltas   │  nba(4×12) wnba(4×10) ncaam(2×20)         │
                │  ncaaw(4×10) · mlb(9) softball(7) ·       │
                │  champions-tour(3 rounds) · …             │
                │  → only the fields that differ + the      │
                │    VERIFIED league id                     │
                └─────────────────────────────────────────┘
```

Layer 1 is **types** (rarely changes). Layers 2–3 are **data** — adding a league
is a JSON entry, never new code. A league resolves by walking its `extends`
chain (`basketball/nba → basketball`), nearest value wins.

**Why discriminators instead of a class-per-sport hierarchy:** the client and
worker stay simple (one `Competition` renderer, one parser switch) and the wire
format is uniform/cacheable. The "inheritance" lives in the profile data, where
it belongs, not in a type tree you'd have to redeploy to extend.

### The canonical basketball example (the one you flagged)

| League | `periodUnit` | `regulation` | `lengthMin` | id | ranking |
|---|---|---|---|---|---|
| `basketball/nba`   | quarter | 4 | **12** | 46 | none |
| `basketball/wnba`  | quarter | 4 | **10** | 59 | none |
| `basketball/mens-college-basketball`   | **half** | **2** | **20** | 41 | curatedRank |
| `basketball/womens-college-basketball` | quarter | 4 | **10** | 54 | curatedRank |

All four `extends: "basketball"` and inherit `scoreKind:numeric`,
`layout:headToHead`, `competitorKind:team`, 5-min unlimited OT, and OT detection
by `period > regulation`. They override only unit/count/length/id/ranking.
NCAAW = quarters (since 2015-16) was the single most error-prone assumption;
**verified true against the 2025 title game** (4 linescores, status.period=4).

---

## 2. Reading a competition (the discriminator decision table)

A consumer never special-cases by sport name. It reads three flags:

| `layout` | `scoreKind` | `competitorKind` | Examples | How to render |
|---|---|---|---|---|
| headToHead | numeric | team | soccer, football, basketball, baseball, hockey, rugby | 2 sides, big score, home/away |
| headToHead | numeric | athlete | tennis | 2 players, set scores; **ignore homeAway** |
| headToHead | cricket | team | cricket | 2 sides, composite score string |
| headToHead | none | athlete | MMA bout | 2 fighters, winner+method, no score |
| field | toPar | athlete/pair | golf | leaderboard, to-par, sorted by `order` |
| field | none | athlete | racing | grid, sorted by `order`, no score |

`competitorKind: 'pair'` (tennis/golf doubles) carries `athletes[2]`; everything
else carries `athletes[1]` (athlete) or team identity (team).

### 2a. Capability flags (`capabilities{}`) — the render-or-hide gate

The three discriminators pick the *renderer*; they do **not** say which optional
datum a sport actually serves. That is the `capabilities{}` object on each
**family** in `league-profiles.json`, resolved through the same `extends` chain
as everything else (objects shallow-merge, so a league override **adds** flags
without restating the family's — e.g. `basketball/mens-college-basketball` adds
`hasSeeds` on top of the basketball family's four). **Omit-means-false:** read
`capabilities.flag == true` and hide the element cleanly otherwise — never an
empty chip. Every flag below was verified against observed presence in
`schema/espn-guide/` (crawl 2026-07-08), not documentation.

| Flag | True for (families; + league overrides) | Gates | Evidence (espn-guide) |
|---|---|---|---|
| `hasSummaryTier` | all except golf / mma / racing / tennis | Box / Plays / Stats chips; the whole rich detail | summary endpoint `—` (404) for exactly those four sports |
| `hasSituation` | baseball, basketball | bases/count/outs, bonus — the cheap live glance | scoreboard `competitions[].situation` observed only for those two |
| `hasCoreSituation` | football, basketball, hockey | the detail-open CORE `situation` fetch (gridiron down/distance/yardLine/isRedZone, basketball `homeFouls.bonusState`+timeouts, hockey `powerPlay`/`emptyNet`) — merged over the scoreboard situation | core `events/{id}/competitions/{id}/situation` (`schema/espn-guide/core-situation.md`). QUIRK: football carries NO `downDistanceText`/`possession` here (scoreboard-only) → the down&distance chip renders, not the field bar |
| `hasWinProb` | baseball, basketball, football | the win-probability bar; ALSO the detail-open CORE `predictor` fallback when `/summary` has no `winprobability[]` (reads each side's `gameProjection`) | summary `winprobability[]`; core `predictor` (`schema/espn-guide/core-predictor.md`) |
| `hasScoringPlaysArray` | football | the `scoringPlays[]` feed shape (others derive from `plays[]`/`keyEvents[]`) | summary `scoringPlays[]` football-only |
| `hasPlaysFeed` | australian-football, baseball, basketball, hockey | dense play-by-play tab | summary `plays[]` |
| `hasCommentary` | soccer, cricket | soccer narrative / cricket ball-by-ball | soccer: summary `commentary[]`; cricket: summary `header.competitions[].commentaries.{key}` (different path, same gate) |
| `hasForm` | soccer, rugby, rugby-league | the `WLWWL` form string | scoreboard `competitors[].form` |
| `hasPowerPlay` | hockey | PP badge/clock | summary `plays[].strength` (`power-play`/`short-handed`) |
| `hasSeeds` | tennis; + `basketball/{mens,womens}-college-basketball` | bracket seed badges | core `competitors[].tournamentMatchup.seed` (NCAA tournament); tennis groupings `curatedRank` |
| `hasWeather` | baseball, australian-football | weather chip (~1% of events: outdoor + game-day) | scoreboard `events[].weather` |

Two capability-shaped keys **predate** this object and stay top-level (do NOT
duplicate them into `capabilities{}`): **`hasLineScores`** (the per-period grid)
and **`rankingsFeed`** (`polls` / `tour` / `divisions` — the standalone rankings
page). Known tension left as-is: the crawl observed scoreboard `linescores` for
field-hockey and mma where the registry's live-probed `hasLineScores:false`
stands — re-probe before flipping those.

Consumers: JS resolves via `schema/tools/resolve.mjs`; the Dart port exposes
`hasCapability(profile, flag)` in `app/lib/src/data/profiles.dart`.

---

## 3. Universal envelope mapping (ESPN → canonical)

All sports share this spine (verified across soccer/NBA/NFL/MLB/NHL):

| Canonical | ESPN raw path | Notes |
|---|---|---|
| `event.id` | `events[].id` | string; feeds `summary?event=` |
| `event.start` | `events[].date` | **always UTC `Z`** — always pass explicit `?dates=`, convert locally |
| `competition.competitors[]` | `events[].competitions[0].competitors[]` | `competitions` is an array but ~always length 1 (except F1) |
| `competitor.homeAway` | `…competitors[].homeAway` | meaningless for tennis/MMA |
| `competitor.score.display` | `…competitors[].score` | **a STRING** (`"103"`) |
| `competitor.periodScores[]` | `…competitors[].linescores[]` | `{value:number, displayValue:string, period:int}`; **absent in soccer** |
| `status.phase` | derived from `…status.type.{state,completed,name}` | branch on `name`, not `state` (postponed can read state=`post`) |
| `status.period` | `…status.type`'s `status.period` | raw int, **no unit** — label via profile `periodMap` |
| `season.type` | `events[].season.type` | **open enum**: 1/2/3/4 **and 6=championship-series** |

**Status normalization (one map for all sports):** `state==='in'` → `live`;
`state==='post' && completed` → `final`; otherwise branch on `type.name`
(`STATUS_POSTPONED`/`STATUS_CANCELED`/`STATUS_SUSPENDED`/`STATUS_ABANDONED`/
`STATUS_FORFEIT` → matching `Phase`); unknown name with `pre` → `scheduled`,
else → `unknown` (pass through, never crash).

A single `final` Phase legitimately comes from many names:
`STATUS_FINAL`(3), `STATUS_FULL_TIME`(28), `STATUS_FINAL_AET`(45),
`STATUS_FINAL_PEN`(47), `STATUS_RETIRED`(38).

---

## 4. Period / OT structure — all leagues (the critical matrix)

This is the heart of "dial in all the leagues." `regulation`/`unit` come from
the profile; `played`/`isOvertime` are reconciled with live data.

| League | unit × reg × len | Overtime model | OT signal |
|---|---|---|---|
| Soccer domestic | half × 2 × 45 | none (draw stands) | n/a — max period 2 |
| Soccer knockout | half × 2 × 45 | AET p4 → pens p5 | period 4/5; `STATUS_FINAL_AET`/`_PEN` |
| NFL | quarter × 4 × 15 | 1 timed period (p5), reg can tie | period>4 / altDetail 'OT' |
| NCAAF | quarter × 4 × 15 | untimed alt-possession, multi-OT, never ties | period>4 (NOT detail string) |
| CFL / UFL | quarter × 4 × 15 | alt-possession, can tie | period>4 |
| NBA | quarter × 4 × 12 | 5-min unlimited | period>4 |
| WNBA / NCAAW | quarter × 4 × 10 | 5-min unlimited | period>4 |
| NCAAM | **half × 2 × 20** | 5-min unlimited | **period>2** |
| MLB / college baseball | inning × 9 × — | extra innings | max(period)>9 → 'Final/11' |
| College softball | **inning × 7 × —** | extra innings | max(period)>7 |
| NHL (reg) | period × 3 × 20 | 3-on-3 OT p4 → **shootout p5** | p4=OT, p5=SO ('Final/SO') |
| NHL (playoff) | period × 3 × 20 | unlimited 20-min, no SO | p5+ = 2OT |
| College hockey | period × 3 × 20 | OT, **ties possible** | p4; W-L-T records |
| Tennis | set × **3 or 5** × — | none (best-of) | **derive best-of from gender+major+singles, NOT format.periods** |
| Golf | round × 4 (or **3** Champions) × — | sudden-death playoff | `status.hadPlayoff` / period>numberOfRounds |
| Racing | lap × 0 × — | none (NASCAR GWC = more laps) | n/a |
| MMA | round × **3 or 5 per bout** × 5 | none | read per-bout `format.periods` |
| Cricket | innings × **2 (limited) or 4 (Test)** | super over → extra periods | read `class.generalClassCard` per match |
| Rugby (union) | half × 2 × 40 | knockout: 2×10 ET + kicks | period>2 |
| Rugby league (NRL) | half × 2 × 40 | golden point 2×5 | period>2; detail 'Final' not 'FT' |
| Australian football (AFL) | quarter × 4 × 20 | rare finals ET | period>4. score=TOTAL points; linescores **non-cumulative** (sum quarters). clock counts **up** (can read >20:00 from time-on) |
| Lacrosse (PLL/NLL/NCAA) | quarter × 4 × 15 | sudden-death OT p5 | period>4; detail 'Final/OT'. linescores **per-period** (sum = total) |
| Volleyball (NCAA/FIVB) | **set × 5 × —** | none (best-of-5) | n/a — `set` not an OT unit; periodScores = per-set points, match score = sets won |
| Water polo (NCAA) | quarter × 4 × 8 | none/ET | period>4 |
| Field hockey (NCAA W) | quarter × 4 × — | OT + penalty strokes | thin feed: no linescores; OT/SO via `status.type.detail` |

---

## 5. Score & outcome mapping (per `scoreKind`)

- **numeric** — `score.value = parseInt(competitors[].score)`. `decision` from
  period/status (regulation/overtime/draw).
- **soccer decorations** — penalty shootout: `shootoutScore` (number). Source
  RECONCILED 2026-07: the normalizer reads a scoreboard `competitor.shootoutScore`
  when present AND the summary carries `gameInfo.*ShootoutScore`; neither could be
  re-verified live in July (no shootout in window) — treat scoreboard as primary,
  gameInfo as the documented fallback (§9 re-check). Winner set from it,
  `decision:'shootout'`, display `"1-1 (4-3 pens)"`. Two-leg: `aggregateScore`
  (**STRING** `"8.0"`) + `advance`, `decision:'aggregate'`.
- **toPar** (golf) — `score.toPar` from `'-10'|'E'|'+3'`; `score.strokes` is
  DERIVED (sum of completed-round linescore values — see normalize.js), no core
  fetch. Non-finishers: VERIFIED 2026-07 **no MC/WD/DQ label survives on any live
  endpoint** (cut players are removed from later-round scoreboards; competitor
  `status` absent) — render the cut LINE from `meta.golf` instead.
- **cricket** — `score.display` is the composite string; real numbers in
  `periodScores[].cricket {runs,wickets,overs,target,reason}`. Winner from
  `meta.cricketSummary`, not run totals. The full scorecard (batting/bowling
  figures) is the summary tier's `cricketInnings` (from `matchcards`).
- **none / racing** — no score. `order`=finish, `startOrder`=grid. DNF = **no
  `order` + sparse stats** (keys absent, not zero). Championship tables come from
  the ordinary standings path (athlete-shaped entries — see §6).
- **none / MMA** — `winner` + `method` (KO/TKO·Submission·Decision). Cheap tier
  scrapes method from scoreboard `details[]` ("Unofficial Winner …", 'Kotko'
  un-mangled); rich tier upgrades it structurally via `GameSummary.bouts` (core
  per-bout `status.result` + judge scorecards). `decision:'method'` (or `'draw'`).

---

## 6. Where the data lives (don't assume scoreboard has it)

| Need | Scoreboard | Summary | Core / Web API |
|---|---|---|---|
| scores, status, line scores | ✅ | header (US only) | ✅ |
| soccer penalty shootout | `competitor.shootoutScore` (unverified live) | `gameInfo.*ShootoutScore` | ✅ |
| soccer goal/card events | partial `details[]` | `keyEvents[]` | ✅ full feed |
| box scores / plays | ❌ | ✅ (US sports) | ✅ |
| NFL/CFB drive-by-drive | ❌ | ✅ `drives.previous[]` (VERIFIED 2026-07) | — |
| attendance / officials | `competitions[].attendance` | ✅ `gameInfo` (VERIFIED 2026-07) | — |
| cricket full scorecard | ❌ | ✅ `matchcards[]` (VERIFIED 2026-07 on the SAME site summary) | — |
| tennis match stats | ❌ | ❌ **summary is DEAD for tennis — 400 on every id permutation (2026-07)** | ❌ (also 400/404) |
| MMA method of victory | `details[]` text scrape | ❌ **site summary 404s for ALL MMA events (2026-07)** | ✅ `status.result` per bout |
| MMA judge scorecards | ❌ | ❌ | ✅ competitor `linescores` per bout |
| MMA round length | `{periods}` only | — | ✅ `format.clock` |
| golf playoff flag | — | — | ✅ `status.hadPlayoff` |
| golf cut/major/rounds (`meta.golf`) | ❌ (no `tournament` object) | — | ✅ event → `tournament.$ref` → `tournaments/{id}/seasons/{yyyy}` (VERIFIED 2026-07) |
| golf hole-by-hole + tee times | per-hole values only (no par/scoreType) | — | ✅ web `leaderboard/{event}/playersummary` (VERIFIED 2026-07) |
| tennis/UFC rankings | ❌ | — | ✅ **site** `.../rankings` (same endpoint as college polls; athlete-shaped) |
| standings (incl. racing) | ❌ (stub) | — | ✅ **`apis/v2/.../standings`** — F1/NASCAR entries are ATHLETE-shaped |

> **Trap:** `apis/site/v2/.../standings` returns only a `{fullViewLink}` stub.
> Real standings live at `apis/v2/...` (note: not `site`). Easy to mistake for empty.
>
> **Trap (2026-07):** omit `?season=` and ESPN returns the CURRENT season — which
> is what you want. Passing `getFullYear()` is WRONG mid-year for cross-year
> leagues (in July 2026 the NHL current season is `2027`). The worker now only
> forwards an explicit client `?season=`.
>
> **Trap:** core `$ref` URLs sometimes point at `sports.core.api.espn.pvt` —
> rewrite `.pvt` → `.com` before following (worker/src/espn.js does).

---

## 7. Canonical JSON examples

**Soccer knockout decided on penalties** (the soccer worst case):
```json
{ "sport":"soccer","league":"uefa.champions","leagueId":"775",
  "events":[{ "id":"401862897","name":"Arsenal at PSG","start":"2026-05-30T19:00Z",
    "competitions":[{ "layout":"headToHead","scoreKind":"numeric","competitorKind":"team",
      "status":{"phase":"final","ended":true,"period":5,"periodLabel":"FT-Pens","espnName":"STATUS_FINAL_PEN","detail":"FT-Pens"},
      "periods":{"unit":"half","regulation":2,"played":5,"isOvertime":true},
      "decision":"shootout",
      "competitors":[
        {"kind":"team","id":"160","displayName":"PSG","homeAway":"home","score":{"display":"1","value":1},"shootoutScore":4,"winner":true},
        {"kind":"team","id":"359","displayName":"Arsenal","homeAway":"away","score":{"display":"1","value":1},"shootoutScore":3,"winner":false}
      ]}]}]}
```

**Basketball, double-OT** (period-driven, league-agnostic):
```json
{ "layout":"headToHead","scoreKind":"numeric","competitorKind":"team",
  "status":{"phase":"final","ended":true,"period":6,"periodLabel":"Final/2OT","altDetail":"2OT","espnName":"STATUS_FINAL"},
  "periods":{"unit":"quarter","regulation":4,"played":6,"isOvertime":true,"lengthMin":12},
  "decision":"overtime",
  "competitors":[{"kind":"team","displayName":"Heat","homeAway":"away","score":{"value":138},
    "periodScores":[{"period":1,"value":28},{"period":5,"value":12},{"period":6,"value":11}],"winner":true}, "..."]}
```

**Baseball, extra innings + walk-off** (`played>regulation`, partial bottom):
```json
{ "scoreKind":"numeric","status":{"phase":"final","ended":true,"period":11,"periodLabel":"Final/11","espnName":"STATUS_FINAL"},
  "periods":{"unit":"inning","regulation":9,"played":11,"isOvertime":true},"decision":"overtime",
  "competitors":[{"displayName":"Dodgers","homeAway":"home","score":{"value":6},"winner":true,
    "stats":{"hits":12,"errors":0}}, "..."]}
```

**Golf leaderboard** (`field` + `toPar`, playoff via `hadPlayoff`):
```json
{ "layout":"field","scoreKind":"toPar","competitorKind":"athlete",
  "status":{"phase":"final","period":4,"periodLabel":"Final"},
  "meta":{"hadPlayoff":true,"golf":{"numberOfRounds":4,"cutRound":2,"cutScore":-2,"major":true,"scoringSystem":"Medal"}},
  "competitors":[
    {"kind":"athlete","athletes":[{"id":"1","name":"S. Scheffler"}],"order":1,"score":{"display":"-12","toPar":-12,"strokes":276},"winner":true},
    {"kind":"athlete","athletes":[{"id":"9","name":"A. Smith"}],"order":99,"score":{"display":"+2","toPar":2}}
  ]}
```

**F1 (multi-competition event):**
```json
{ "sport":"racing","league":"f1","leagueId":"2030",
  "events":[{"id":"600057435","name":"Spanish Grand Prix",
    "competitions":[
      {"id":"...","layout":"field","scoreKind":"none","meta":{"round":"Race","flag":"CHECKER"},
       "competitors":[{"kind":"athlete","athletes":[{"name":"M. Verstappen"}],"order":1,"startOrder":1,"vehicle":{"number":"1","team":"Red Bull"},"winner":true}, "..."]},
      {"id":"...","meta":{"round":"Qualifying"},"competitors":["..."]}
    ]}]}
```

**MMA bout** (`none` score, method from core):
```json
{ "layout":"headToHead","scoreKind":"none","competitorKind":"athlete",
  "status":{"phase":"final","ended":true,"period":1,"periodLabel":"Round 1"},
  "decision":"method","method":{"kind":"KO/TKO","detail":"Punches","target":"head","finishRound":1,"finishTime":"4:59"},
  "meta":{"cardSegment":"Main Card","featured":true},
  "competitors":[{"kind":"athlete","athletes":[{"name":"Fighter A"}],"order":1,"winner":true,"records":[{"type":"total","summary":"22-1-0"}]}, "..."]}
```

**Cricket** (composite score, numbers in periodScores):
```json
{ "scoreKind":"cricket","status":{"phase":"final","period":2,"periodLabel":"Final"},
  "meta":{"cricketClass":"Twenty20","cricketSummary":"RCB won by 5 wkts (12b rem)"},
  "competitors":[
    {"displayName":"PBKS","score":{"display":"155/8 (20 ov)","cricket":{"runs":155,"wickets":8,"overs":20}},
     "periodScores":[{"period":1,"value":155,"cricket":{"runs":155,"wickets":8,"overs":20,"isBatting":false,"reason":"complete"}}]},
    {"displayName":"RCB","winner":true,"score":{"display":"161/5 (18/20 ov, target 156)","cricket":{"runs":161,"wickets":5,"overs":18,"target":156}}}
  ]}
```

> **Rugby reminder:** `periodScores[].value` is **cumulative** — period 2 == final
> score, period 1 == score at half. Never sum them. (Verified Six Nations,
> Super Rugby, NRL.)

---

## 8. Worker normalization pipeline

```
fetch raw  ──►  pick family normalizer (by espnPath)  ──►  resolve league profile
   │                                                              │
   └── shared: statusToPhase(), periodLabel(profile, period), parseScore(scoreKind)
                                                                  │
   ◄── emit ScoresResponse (canonical) ◄── per-family: decision, decorations, events, meta
```

- **Shared** across all families: status→phase, period→label (via profile
  `periodMap`/`unit`), competitor identity, score parse by `scoreKind`,
  `anyLive` rollup, HTTPS-forcing logos.
- **Per family** (~10 small functions): how `decision` is computed, which
  decorations to attach (shootout/aggregate/method/cut), event-timeline mapping,
  and second fetches when needed (soccer pens, MMA method → `summary`/core).
- Profiles drive the rest, so a new league = JSON only.

---

## 9. Verification status (be honest about gaps)

`league-profiles.json` marks `"verifiedIds": false` on everything not confirmed
against the live API. Outstanding before relying on them:

- **League ids — RESOLVED** (fetched live 2026-06-13): Serie A `730`, Ligue 1
  `710`, Europa `776`, NFL `28` (uid `s:20~l:28`), NHL `90` / men's-college `91`
  / women's-college `92`, UFC `3321` / PFL `3347` / Bellator `3323`. Every
  concrete league now carries a verified id; only the dynamic buckets
  (`soccer/_other`, `cricket/_tours`) read their id from JSON at runtime.
- **Unverified-vs-live shapes** (re-fetch when in season): NFL regular-season
  tie; CFL live `situation` (`?dates=` returns stale 2023 data — needs core API);
  NHL playoff multi-OT period numbering; live in-progress detail strings for
  tennis/racing/MMA (none were live at capture); cricket Test 4-innings & super
  over; hockey `plays[]` type-id taxonomy (do NOT assert 506-509).
- **2026-07 re-checks pending:** soccer shootout source (scoreboard
  `competitor.shootoutScore` vs summary `gameInfo.*ShootoutScore` — no shootout
  occurred in the probe window; verify at the next WC/cup knockout decided on
  pens); LIV 54-hole/Teamstroke live shape (scoreboard verified, event was
  pre-start); MMA judge-linescores official names (officials are `$ref`s — we
  ship totals only); NCAAW `/rankings` availability (docs matrix says absent,
  route will just return empty polls).
- **Team surfaces — RESOLVED** (probed live 2026-07-06, see §10b): `/teams/{id}/
  roster` (two shapes), `/teams/{id}/statistics` (current-season default; EPL
  empty in offseason), `schedule.team.standingSummary`. Dead end confirmed:
  `common/v3 .../statistics` 404s.
- **Known-unsupported:** boxing (no ESPN sport — source elsewhere); tennis match
  stats (every summary/statistics endpoint 400s — VERIFIED 2026-07, see §6).
- **In-season re-captures pending** (code-complete, guide/unit-shape-tested
  only — no live-shape golden yet; see `rework-plan.md`'s Deferred ledger for
  the app-side detail): NBA/NHL full-plays fixture re-capture (offseason
  now — re-run `capture-extra.mjs` in-season, Oct 2026); `situationCore` /
  `winprob` core-fetch goldens (0 today — capture during a live MLB/WNBA game,
  any evening this week; gridiron/basketball/hockey wait for their own
  season); the basketball cheap win-prob field (`situation.homeWinPercentage`)
  needs a live close NBA/WNBA game to verify byte-for-byte, not just
  unit-shape; March Madness structured seeds/regions (`capabilities.hasSeeds`
  resolves via core `tournamentMatchup.seed` for NCAAM/NCAAW, but no captured
  shape has real seeds/regions populated — capture March 2027).

These are *data* gaps, not *design* gaps — the contract already models all of
them; the registry just needs the confirmed values filled in.

---

## 10. 2026-06 additions (data we now surface)

New canonical fields — all **additive** (older clients ignore them), all sourced
from payloads we already fetch unless noted. See `canonical.ts` for the authoritative
shapes + inline QUIRKs.

- **`ScoresResponse.calendarDays` / `seasonWindow`** — ESPN's season skeleton from
  `leagues[0].calendar`, **free** (same scoreboard payload; `worker/src/calendar.js`
  is the single home, shared with `overview.js`). QUIRK (verified): density is NOT
  uniform — NBA/NHL/soccer ship a dense one-per-game-day list, but **MLB ships a
  sparse season-boundary calendar** (48 entries: ST start / All-Star break / season
  end). Treat as a hint, never an exhaustive game-day set; the Schedule strip still
  derives precise in-window days from a range fetch.
- **`GameSummary` enrichments** (ride the one `/summary` fetch — zero extra cost):
  `seasonSeries` (H2H), `recentForm` (last-5, newest last), `injuries` (structured;
  comments dropped), `winProbability` (single current/final %, **NBA/NFL/MLB only** —
  NHL/soccer omit it; an ESPN analytic, not a betting line), and `plays` (the FULL
  play-by-play; the detail page shows the condensed `scoringPlays` and expands into
  this).
- **`RankingsResponse`** — new `GET /v1/rankings/{sport}/{league}` (college AP/Coaches/
  CFP). Lazy, 1h TTL, never in the overview fan-out. Distinct from the per-team
  `curatedRank` already on the scoreboard.

Registry expansion (ids fetched live 2026-06-15): **5 new families** (australian-
football, lacrosse, volleyball [set-based], water-polo, field-hockey) + **~198 league
entries** (soccer +112, rugby +22, cricket +14, mma +11, basketball +10, baseball +9,
golf +5, lacrosse +4, hockey/racing/volleyball/water-polo/AFL/field-hockey). Ephemeral
slugs (qualifiers, friendlies, youth, bilateral cricket tours) stay on the
`soccer/_other` / `cricket/_tours` catch-alls. NOTE the overview fan-out cap
(`OVERVIEW_FETCH_CAP=48`) means only the first 48 leagues get a season-pulse in the
unfiltered `/v1/overview`; page by `?sport`/`?priority` to pulse the rest.

---

## 10a. 2026-07 additions (the docs-audit round)

All **additive**; every claim below was probed against live ESPN 2026-07-05
before implementation (John Deere Classic live, Wimbledon live, World Cup live).

**Cheap tier (scoreboard fields we downloaded and dropped):**
- `Competition.attendance` / `headline` / `conferenceGame` / `wasSuspended` —
  straight passthroughs, emitted only when present.
- `Competition.broadcast` — a single terse TV/stream label (all sports):
  `competitions[].broadcast` (100%, e.g. `MLB.TV/TBS`, `ESPN`; often an empty
  string → fall back to the national `geoBroadcasts[].media.shortName`). One dim
  line on the detail hero + Game-info card. Near-free.
- `Competition.odds` (`Odds`) — the pre-game betting line. The inline scoreboard
  `odds[]` (~8% presence, near game time) gives spread/total; the per-team
  moneyline (`homeMoneyline`/`awayMoneyline`, soccer `drawMoneyline`) is CORE-only
  — the detail screen fetches `.../competitions/{id}/odds` lazily on open when the
  inline line is absent (`normalizeCompetitionOdds`, capability-gated to
  baseball/basketball/football/soccer via `capabilities.hasOdds`). Same canonical
  `Odds` shape from both sources; omitted cleanly when nothing is served.
- `meta.golf` (**GolfMeta implemented at last** — it had been declared in
  canonical.ts with no producer): the scores route enriches golf events from the
  CORE tournament resource (2 extra fetches per golf event, best-effort;
  `{major, scoringSystem, numberOfRounds, currentRound, cutRound, cutScore,
  cutCount}` verified live). Drives the leaderboard cut line + major badge.

**Rich tier (`GameSummary`):**
- `attendance` + `officials[]` — summary `gameInfo` (venue was already surfaced).
- `drives[]` + gridiron `plays` — NFL/CFB finally get play-feed parity: the
  summary's `drives.previous[]` was always there; we flatten its nested plays
  into the standard `plays` feed and ship compact per-drive rows alongside.
- `cricketInnings[]` — the real cricket scorecard (batting + bowling figures per
  innings) from `matchcards[]`, which rides the SAME site summary we always
  fetched (our fixture trimming had hidden it). Partnerships cards dropped.
- `bouts[]` — MMA structured results. The site summary 404s for MMA, so the
  worker builds the rich tier from the core event's per-bout `status` (result
  displayName/short) + per-competitor `linescores` (judge totals, decisions only).
- `BoxRow.id` + `LineupPlayer.id` — the CORE `athletes/{id}` join, from the
  summary's `boxscore` athlete id (box rows) and `rosters[].roster[].athlete.id`
  (soccer/rugby lineups). Non-null makes the row tap through to the player page;
  omitted when ESPN ships no athlete id (the row stays inert).

**New endpoint:**
- `GET /v1/scorecard/{sport}/{league}/{eventId}/{playerId}[?season=]` — golf
  hole-by-hole (web `playersummary`): per-hole strokes/par/scoreType, front/back
  splits, live position, and pre-round tee time/group. Lazy (row tap), 60s TTL.

**Rankings generalized:** `rankingsFeed` registry flag ('polls' | 'tour' |
'divisions') → the SAME `/v1/rankings` route now serves ATP/WTA world rankings
(points) and UFC divisional/P4P lists (records, champion flag) — the site
rankings endpoint handles all three; entries carry `team` OR `athlete`.

**Standings:** racing works through the ordinary path (F1 Drivers/Constructors,
NASCAR flat; athlete-shaped entries now normalized). Season default REMOVED —
ESPN's own current-season default is correct where `getFullYear()` was wrong
(NHL in July). `?date=YYYYMMDD-YYYYMMDD` range fetches verified working on the
scoreboard and pass through `/v1/scores` unchanged.

**Probed and rejected (do not re-attempt without a fresh probe):** tennis match
stats (all endpoints 400), golf MC/WD/DQ labels (no source), site MMA summary
(404 for every event), core racing `rankings` (empty), dedicated golf
leaderboard endpoints (404). Gambling/odds excluded by product decision.

---

## 10b. Team-surface additions (date nav + team pages)

All **additive**; endpoints probed against live ESPN 2026-07-06 before build.

**Long-TTL past days (F1):** `?date=` on `/v1/scores` already passed through and
cached per-URL; a fully-past dated slate is now cached **6h** (`TTL.pastDay`) not
5m, since it's immutable. `pastDatedTtl()` (in `ttl.js`) takes the range END,
compares against **ET-today** (`Intl.DateTimeFormat('en-CA', America/New_York)`),
and is guarded by `anyLive===false` (a suspended game keeps the tight cadence).
Not infinite: SWR + late stat corrections argue for a bound.

**`TeamCardResponse.team.standingSummary`** — `schedule.team.standingSummary`
(VERIFIED 2026-07: `'2nd in AL East'`, a STRING). Was already on the payload
`/v1/team` fetches → the enriched-card season line costs **zero** subrequests.
Absent for national teams.

**New `GET /v1/teamdetail/{sport}/{league}/{teamId}`** (`TeamDetailResponse`) —
the rich team page. 4 subrequests (schedule required + roster/stats/standings
best-effort), coalesced behind a 30m TTL. Probed live 2026-07-06:
- **roster** — `site/v2 .../teams/{id}/roster` works for NFL/NBA/MLB/NHL/EPL/
  college. **Two shapes, discriminated STRUCTURALLY** (never by sport name):
  entries with `items[]` = position-group buckets (NFL offense/defense/
  specialTeam, soccer by position); a flat `athletes[]` = one `'Roster'` group.
- **stats** — `site/v2 .../teams/{id}/statistics` → `results.stats.categories[]`,
  and **defaults to the current season** (no `getFullYear()` trap — unlike
  standings). **EPL returns an empty `results:{}`** in the offseason → stats must
  be omittable (`[]`). Curated per family via registry `teamStatKeys` (mirrors
  `standingsColumns`) → one ordered `'Season'` group; else natural categories,
  capped ~8. `common/v3 .../statistics` **404s — dead, do not use.**
- **standing** — the team's own group plucked from the shared `normalizeStandings`
  output; omitted when the team id isn't found (national team / athlete-shaped
  racing table). Team pages are gated to `competitorKind==='team'` (added to the
  catalog — `hasTeams` is the wrong gate, it's true for F1 constructors).

**`StandingsResponse` gap closed:** the standings shape shipped in
`worker/src/standings.js` + `models.dart` but was undeclared in `canonical.ts`;
now declared retroactively (racing's athlete-shaped rows noted as a QUIRK).

---

## 10c. Venue & Circuit facts (the §2.9 detail tab)

Additive; a LAZY, on-tab-open tier (`worker/src/venue.js`, ported to
`app/lib/src/data/venue.dart`) that turns the id the cheap scoreboard already
carries into the photo/track-map + fact grid. **One tab, two shapes, dispatched
by data presence (never sport name):** `events[].circuit` present → **CircuitFacts**;
else `competitions[].venue.id` present → **VenueFacts**; neither → hide the tab.
Every path OBSERVED in `espn-guide/core-venues-id.md` / `core-circuits-id.md`.

- **`VenueFacts`** — one CORE `venues/{id}` fetch (join on `competitions[].venue.id`).
  `fullName`→name, `address.{city,state,country,address1}`, `images[]` (rel
  `day`/`full`/`interior`; `photo` picks day>full>interior), **`grass` bool→`surface`**
  (`'grass'|'turf'`), **`indoor` bool→`roof`** (`'open'|'indoor'`). Non-F1 racing
  (NASCAR ovals) degrade here: `length` (miles, number) + `turns`. **NOT OBSERVED,
  omitted never faked:** capacity (cricket-only ~1%), opened/est. year (circuits-only).
- **`CircuitFacts`** — one CORE `circuits/{id}` fetch (join on `events[].circuit.id`),
  F1 only, every field 100%. `diagrams[]` + `diagram` (dark track map: rel
  `circuit-dark`>`circuit`>`day-dark`>`day`, svg preferred), `direction`,
  `established`, `length`/`distance` (**STRING** `"7.004 km"` → `Measure{value,unit,
  display}`), `laps`, `turns`, and `fastestLap{time,year,driver}` — the driver is
  resolved from `fastestLapDriver.$ref` in ONE cached fan-out (→ `{name, headshot}`).
- **Cost:** both are on-tab-open only (never the scores poll), cached a day in
  `EspnClient`, best-effort (null on 404/offline → the tab keeps the cheap header).
  Goldens: `app/test/fixtures/golden/{venue,circuit}/` from stable pinned venue ids
  + the Spa circuit capture; parity in `app/test/port_venue_test.dart`.
- **The join ids ride the CHEAP scoreboard:** `Venue.id` (from `competitions[].venue.id`,
  str-numeric 100% where a venue is present) and the new `SportEvent.circuit`
  `{id,fullName,city?,country?}` (from `events[].circuit`, all 100% for racing —
  emitted alongside the legacy venue name/address fold) are what gate the tab.

## 10d. Athlete / player profile (the §2.6 "Player rows")

Additive; a LAZY, on-open tier (`worker/src/athlete.js`, ported to
`app/lib/src/data/athlete.dart`) feeding the Phase 5 player page. All CORE-tier +
fanned-out ($ref resolves) → **NEVER on the cheap scoreboard poll**; fetched only
when a player row is opened, cached in `EspnClient`. Every path OBSERVED in
`espn-guide/core-athletes-id.md` / `-statistics.md` / `-eventlog.md` + a live probe
(MLB/WNBA, 2026-07). `api.dart`'s `athleteProfile(league, id, {teamId})` does the
fetches + the fan-out; the normalizer is pure map→map over the pre-resolved raws.

- **`AthleteProfile`** = identity + `team` + `stats` + `lastGames`.
  - **Identity** rides the ROSTER ROW when `teamId` is known (denser, single-call —
    teamDetail already fetched that roster) OR the core `athletes/{id}` doc; both
    share `{displayName, shortName, jersey, position{}, headshot{}, age,
    displayHeight, displayWeight}`. `position` prefers `abbreviation`; headshot
    forced https. `age`/`height`/`weight` are ESPN's display values (~56–67% — omit
    when absent).
  - **`team`** (name+color+logo+`logoDark`) needs a `team.$ref` resolve either way
    (the roster row carries no color) — from the core athlete's ref, else built from
    `teamId`. Dark logo = explicit `dark` rel, else `/500/`→`/500-dark/` derivation.
  - **`stats`** = `athletes/{id}/statistics` `splits.categories[].stats[]` → compact
    `{name, abbreviation?, displayName?, shortDisplayName?, value?, displayValue}`
    (verbose `description` dropped; nameless/no-value cells filtered). Category set
    is sport-specific (Pitching/Fielding · Offensive/Defensive/General) — read by
    `name`, never sport-branched. **QUIRK:** per-game stat NAMES are inferred in the
    guide → bound to whatever the split actually carries, never fabricated.
  - **`lastGames`** = `athletes/{id}/eventlog` `events.items[]` — the most-recent
    PLAYED N (cap 5), each row a 1–2 `$ref` fan-out: `event.$ref`→`{date, name,
    shortName}`, `statistics.$ref`→the per-game line (same category shape). `teamId`
    is inline. A row survives an unresolved event on its `eventId` alone.
- **Cost:** on-open only; the eventlog fan-out is capped (5 rows × ≤2 fetches) +
  concurrency-pooled + cached (immutable past games → a re-open is free) — the cap
  lives in `api.dart` `_athleteGameCap`/`_athleteGameConc`. Best-effort: a
  stats/eventlog failure yields a valid identity-only partial profile. Goldens:
  `app/test/fixtures/golden/athlete/` (MLB roster-row + WNBA core-athlete identity
  paths); parity in `app/test/port_athlete_test.dart`; degraded/partial paths in
  `worker/test/units.test.mjs`.

---

## 10e. Team leaders + standings sub-records (§2.6 TEAM LEADERS · §2.8 L10/DIV/CONF)

Two additive CORE-tier, lazy, capability/profile-gated enrichments. Both are pure
map→map (`worker/src/teamleaders.js` + the `standings.js` extension, ported to
`app/lib/src/data/`); `api.dart` does the fetch + `$ref` fan-out. Neither ever rides
the cheap scoreboard poll.

- **`TeamLeaders`** (§2.6, `teamleaders.js` → `teamleaders.dart`) — a team's SEASON
  leaders, the top player per category. Source: CORE `…/seasons/{y}/types/2/teams/
  {id}/leaders` → `categories[].leaders[0].athlete.$ref` (OBSERVED 100% across 8
  sports in `espn-guide/core-season-types-id-teams-id-leaders.md`). `api.dart`'s
  `teamLeaders(league, teamId)` reads the season year off the (cached) team schedule,
  caps to **6 categories**, resolves each UNIQUE athlete `$ref` ONCE (name/position/
  headshot), and hands the resolved map to the normalizer. A category whose top
  leader can't be resolved is DROPPED (never faked). The cheaper per-GAME glance
  remains the scoreboard's `competitors[].leaders` (already surfaced inline).
- **Standings sub-records** (§2.8) — L10 + division/conference records are **NOT on
  the site standings**; they ride the CORE group standings-id doc
  (`…/types/{t}/groups/{g}/standings/{s}` → `standings[].records[]`). `standings.js`
  gains `extractGroupRecords(docs)` → `{ teamId: {l10,div,conf,home,away} }` and a
  second (optional) arg to `normalizeStandings(raw, records)` that MERGES those keys
  into each row's `stats` (omit it → byte-identical to before; every prior golden
  unchanged). **QUIRK (VERIFIED live 2026-07):** the record `type` vocabulary depends
  on the group level — a CONFERENCE group (NBA/WNBA) emits `vsdiv`/`vsconf`; a LEAGUE
  group (MLB AL/NL) emits `intradivision`/`intraleague` for the same idea — both fold
  onto `div`/`conf`. `lasttengames`→`l10`, `home`→`home`, `road`→`away`.
  - **Fetch-budget gate:** `api.dart`'s `standings()` fans out the group docs ONLY
    when the league profile's `standingsColumns` lists a sub-record key
    (`l10`/`div`/`conf`/`home`/`away`) — otherwise never spends the calls. Group ids /
    seasonType / standingsId are discovered off the site standings raw; the fan-out is
    capped (12) + concurrency-pooled + best-effort. Sub-record columns were added to
    the US v1 leagues (MLB/NBA/WNBA/NHL/NFL); read by stable `stats[].name`, never
    sport-name.
- **Goldens:** `app/test/fixtures/golden/teamLeaders/` + `standingsRecords/` (MLB +
  WNBA, live-captured 2026-07); parity in `app/test/port_endpoints_test.dart`. Capture
  extends `worker/scripts/capture-extra.mjs` (`--only leaders standingsRecords`),
  size-trimmed to the fields under test (real captures, nothing fabricated).

---

## 10f. Cheap win-prob + soccer standings bands (§2.7/2.8)

Two additive fields, both surfaced purely by DATA PRESENCE (no sport-name branch):

- **`Situation.homeWinPct`** (`normalize.js`/`.dart` `buildSituation`) — the CHEAP
  scoreboard win probability. Source: `competitions[].situation.lastPlay.probability.
  homeWinPercentage` (0-1), stored as a **0-100 rounded int** for the HOME side.
  **VERIFIED basketball-only (~14%, `schema/espn-guide/scoreboard.md`)** — absent for
  every other sport, so the hero-card footer's two-colour win-prob micro-bar renders on
  presence alone. Distinct from the rich `summary.winprobability[]` timeline and the
  CORE `predictor` fallback (both detail-open). No LIVE basketball game was capturable
  at build time (NBA offseason / no live WNBA slate 2026-07), so the normalizer is
  pinned by guide-shaped unit tests (`worker/test/units.test.mjs` + `app/test/
  win_prob_test.dart`), not a fixture golden — no committed scoreboard fixture carries
  the field, so every existing golden is unchanged.
- **`StandingsRow.note` `{color?, description?}`** (`standings.js`/`.dart`) — the
  qualification BAND: an ESPN hex `color` cut-line swatch + a `description` tag
  ('Champions League' / 'Relegation' / 'Advance to Round of 32' / 'Eliminated').
  Source: `children[].standings.entries[].note`. **VERIFIED soccer-only (~12%,
  `schema/espn-guide/standings.md`)**; kept tolerantly, absent otherwise (`rank` is
  dropped — redundant with the row rank). The client draws a 3px left colour band on
  the row + a legend grouping identical descriptions under the group card.
  - **Goldens:** the committed per-league soccer fixtures were captured band-less, so a
    FRESH capture (`capture-extra.mjs --only standingsNotes`: eng.1 / uefa.champions /
    fifa.world, trimmed) feeds `app/test/fixtures/golden/standings/*__notes.json`,
    covered for free by the existing `standings` parity loop in `port_endpoints_test.dart`.
    (The fifa.world team-detail golden also gained real group bands — the same
    `normalizeStandings` shield behind the team page.)

---

## 10g. Tournament layer (§2.7 — groups · draw · bracket · pools+series)

**`TournamentResponse`** (`canonical.ts`; oracle `worker/src/tournament.js`, port
`app/lib/src/data/tournament.dart`, parity `port_tournament_test.dart`) — ONE
canonical shape for the four tournament grammars, built ENTIRELY from
already-fetchable tiers: a `?dates=` **range scoreboard** (the structure source)
plus the league **standings** when the profile says group tables exist. Everything
below `title` is optional-by-default; the UI renders what is present.

- **Round labels** — three observed sources, first classifiable wins: tennis
  `round.displayName` (ONE day fetch returns the ENTIRE pre-created Wimbledon
  draw, VERIFIED 2026-07), `notes[].headline` (`'East 1st Round - Game 6'`, CWS),
  soccer `altGameNote` (`'FIFA World Cup, Round of 16'`, VERIFIED live 2026-07).
  All normalize onto one canonical round key (`roundOf128…final`); unknown labels
  pass through as a `round: null` bucket — never a crash. Ordinal labels
  (`'Round 4'`) refine to `roundOfN` by bucket size ONLY when sourced from
  `round.displayName` (a complete draw); headline-sourced ordinals may be a
  partial slate → they stay `null` with the label intact.
- **Seeds** — ONLY where `curatedRank` IS the seed: `competitorKind == 'athlete'`
  (tennis; 99 = unseeded → omitted). Team `curatedRank` is a poll rank; NCAA
  seeds are the per-event CORE `tournamentMatchup` — a documented hook, never
  fanned out in the normalizer.
- **Bracket linkage** — `winnerAdvancesTo` is core-only, so `advancesTo` is
  derived on the cheap path: a DECIDED matchup links to the earliest later
  matchup **in a different round** containing its winner (real ids only).
  Undecided slots have no forward link — the `'Winner E1/F2'` placeholder is a
  spec §2.7 gap the UI composes only where this field allows.
- **CWS pools** — RECONSTRUCTED (no ESPN standings doc): pool membership by game
  connectivity, W–L from pool games, status `eliminated` (2 pool losses) /
  `advances` (series participant or `'advances to Championship'` headline winner)
  / `alive`. Championship = the cheap scoreboard `series` block (best-of-N).
- **Registry hints** (profile-level, §2.7): `tournamentGroups` (soccer.knockout —
  also fetch standings for group tables + qualification bands) and
  `tournamentWindowDays` (soccer.knockout ±45, college-baseball ±14 — the ±days
  range that spans the competition from any date inside it).
- **Goldens** — REAL captures (`capture-extra.mjs --only tournaments`, 2026-07-08):
  the 2026 World Cup (12 groups + knockout incl. the live QF window), the full
  2026 Wimbledon draw (qualifying→final, seeds/sets/TBD slots), and the 2026 CWS
  (two pools + best-of-3 series). March Madness is off-season/uncapturable → its
  headline grammar is pinned by guide-shaped unit tests (`units.test.mjs`).

`api.dart tournament(league, {window, grouping, eventId})` is a **pushed-page
fetch, never the poll**: one cached range scoreboard (window from the hint or the
override) + best-effort standings, fed to the normalizer.

---

## 11. Versioning, backward-compatibility & app updates

The contract is versioned as a **discipline, not a protocol**. The Flutter client
parses tolerantly (`models.dart`: unknown keys ignored, missing fields defaulted,
every discriminator stored as a pass-through string), so an **already-installed
APK keeps working when the worker adds to a payload** — no coordinated rollout.
`/v1` is therefore a contract *name*, not a build number; it absorbs change
additively, indefinitely.

### The one rule that keeps old apps alive
The worker normalizers may **add** to a payload freely, but must **never reshape an
existing field in place** — new meaning goes in a **new** field.

**Additive (ship anytime on `/v1`, no version bump, no coordination):**
- a new optional field (top-level or nested) on any payload;
- a new enum / discriminator value on a pass-through string (`layout`, `scoreKind`,
  `competitorKind`, `phase`, `decision`, overview `state`, …) — old apps fail the
  `== known` check and fall through to a default render (the "unknown passes
  through, never crash" contract);
- a new league in `league-profiles.json` (pure data → `resolve.mjs` → catalog);
- a new route under `/v1` (old apps never call it);
- dropping an *optional* field (old apps guard with null/`const []`/`''`).

**Breaking (requires minting `/v2`) — the three verified traps the tolerant
parser does NOT catch:**
1. **Type change** of an existing field (e.g. a string score → number/object):
   `_int`/`_num` return null, `_str` returns `''` — the value silently *vanishes*.
2. **Count/order change of positionally-zipped parallel arrays** a renderer indexes
   without bounds-checking — `BoxGroup.columns`↔`BoxRow.stats`,
   `PeriodLines.labels`↔`SidePeriods.values`. These `RangeError` / mis-align at
   *render* time, invisible to both the parser and the update gate.
3. **Renaming a map key** the app indexes by (ESPN stat abbreviations in
   `Competitor.stats` / `StandingsRow.stats`) — old apps silently show nothing.

Litmus: *"would a v0.1.0 APK I can't update throw, mis-align, or silently blank a
value? → breaking, mint `/v2`; else add a field."*

**The machine guard for this human rule:** `app/test/detail_page_test.dart` and
`team_card_test.dart` re-parse **and re-render** the committed `test/fixtures/`
(canonical worker output). A careless reshape of a positionally-zipped grid trips
them in CI. Keep those fixtures; treat a change that forces editing them as a
breaking-change signal.

### Minting `/v2` (deferred — only when a breaking change forces it)
`/v1` and `/v2` do **not** coexist today: `worker/src/index.js` hard-rejects any
prefix that isn't `'v1'`. When forced: change that gate to a small dispatch
(`{v1:1, v2:2}[v]`); add a pure `shapeForMajor(major, canonicalObj)` that projects
the single canonical object down to the v1 wire shape at the final `json()` step
(never fork `resolve.mjs`/the normalizers); flip `Api.apiPrefix` (`app/lib/src/api.dart`)
to `/v2` (one line — every method passes a version-less path). The Cache API keys
off the full URL, so the two majors never collide and one `wrangler deploy` ships
both. **Bias hard toward ten additive fields over one `/v2`.**

### Client version signal (telemetry only)
The app sends `X-Scores-Client: <versionCode> <versionName>` on every request
(`api.dart` `_get`), sourced from compile-time consts (`app/lib/src/version.dart`)
baked by `--dart-define` in `release.yml` — the `CLIENT_VERSION_CODE` is the same
`github.run_number` that becomes the APK's `versionCode`, so reported == installed.
The worker only `console.log`s it (visible in `wrangler tail` / observability); it
is **never** a routing input or a cache-key dimension. A local `flutter run`
reports `0 dev`.

### Update warning (sideloaded APK — signal + link, never force)
There is no Play Store auto-update, so the worker can only advise. The
`/v1/health` response carries an advisory **`client` gate** echoed from the
registry's top-level `client` block (`league-profiles.json`):

```json
"client": {
  "minVersionCode": 0, "recommendedVersionCode": 0,
  "latestVersionName": "0.1.0",
  "downloadUrl": "https://github.com/phil-scott-78/sports-app/releases/latest"
}
```

The app (`updateTierProvider` → `UpdateBanner`) compares its baked `versionCode`:
at/above recommended → nothing; `[min, recommended)` → a dismissible "update
available" nudge (once per release); below `min` → a persistent "no longer
supported" bar. Tapping opens GitHub Releases. **Fail-open is load-bearing:** an
absent `client` block (old worker, a fork, or the offline `npm run mock` server)
parses to a null gate → no banner. `0/0` ships the gate fully inert. Internal
`_`-prefixed keys (e.g. `_doc`) are stripped on the wire (`worker/src/client.js`).

### Release ritual (automated by `.github/workflows/release.yml`)
Tag and push `vX.Y.Z` (`git tag v0.3.1 && git push origin v0.3.1`). The workflow runs
two jobs in order:
1. **`build`** — builds + publishes the signed APK to GitHub Releases (`versionName`
   = the tag, `versionCode` = `github.run_number`; the SAME run number is baked into
   the app via `--dart-define`, so what the app reports == what's installed).
2. **`deploy-worker`** (`needs: build` — runs only after the Release is live) — runs
   the offline worker tests, then **injects `recommendedVersionCode = run_number` and
   `latestVersionName = tag`** into the bundled registry and `wrangler deploy`s. The
   injection is ephemeral (CI's checkout only) — it is **not** committed.

One tag ships both halves in the right order, no manual gate edit. Because the
advertised `recommendedVersionCode` equals the APK's `versionCode`, the just-shipped
build never nags itself and every older install gets the soft "update available".
**`minVersionCode` is never auto-bumped** — retiring an old build (the persistent
banner) is a deliberate commit to `league-profiles.json`. The committed
`recommendedVersionCode` is only the baseline a manual `wrangler deploy` would use.

Required repo secrets: `CLOUDFLARE_API_TOKEN` (the "Edit Cloudflare Workers" token
template, scoped to the `philco.dev` zone) + `CLOUDFLARE_ACCOUNT_ID`, alongside the
APK signing secrets (`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS`).

### Origin (effectively irreversible once an APK ships)
The app's baked default origin is a **stable custom domain**
(`api.scores.philco.dev`, `config.dart`), deliberately not the `*.workers.dev`
name — a sideloaded APK can't be force-migrated, so renaming the origin would
orphan every install. Point the domain at the worker (uncomment the
`custom_domain` route in `worker/wrangler.toml`) before the first release tag.
