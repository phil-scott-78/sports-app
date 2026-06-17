# Normalized sports schema

> The canonical data model every screen and endpoint is built on. Designed from
> **live ESPN responses verified June 2026** and hardened by an adversarial
> verification pass (which caught ~30 hallucinated ids / wrong status names /
> bad field paths — see `.research-digest.md` for the raw evidence).
>
> Three files, one contract:
> - **`canonical.ts`** — the wire types the worker emits and the client consumes.
> - **`league-profiles.json`** — the data-driven league registry (inheritance).
> - **`SCHEMA.md`** (this) — how they fit, the mappings, the quirks, examples.

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
- **soccer decorations** — penalty shootout: `shootoutScore` (number, **from
  `summary`, not scoreboard**); winner set from it, `decision:'shootout'`,
  display `"1-1 (4-3 pens)"`. Two-leg: `aggregateScore` (**STRING** `"8.0"`) +
  `advance`, `decision:'aggregate'`.
- **toPar** (golf) — `score.toPar` from `'-10'|'E'|'+3'`; `score.strokes` only
  via core API. Non-finishers (`STATUS_CUT` overloaded: MC/WD/DQ) sorted last by
  `order`; disambiguate via status description.
- **cricket** — `score.display` is the composite string; real numbers in
  `periodScores[].cricket {runs,wickets,overs,target,reason}`. Winner from
  `meta.cricketSummary`, not run totals.
- **none / racing** — no score. `order`=finish, `startOrder`=grid. DNF = **no
  `order` + sparse stats** (keys absent, not zero).
- **none / MMA** — `winner` + `method` (KO/TKO·Submission·Decision). Method
  **from core API**, not scoreboard. `decision:'method'` (or `'draw'`).

---

## 6. Where the data lives (don't assume scoreboard has it)

| Need | Scoreboard | Summary | Core API |
|---|---|---|---|
| scores, status, line scores | ✅ | header (US only) | ✅ |
| soccer penalty shootout | ❌ | ✅ `gameInfo.*ShootoutScore` | ✅ |
| soccer goal/card events | partial `details[]` | `rosters[].plays[]` | ✅ full feed |
| box scores / plays | ❌ | ✅ (US sports) | ✅ |
| MMA method of victory | ❌ | ✅ | ✅ `status.result` |
| MMA round length | `{periods}` only | — | ✅ `format.clock` |
| golf playoff flag | — | — | ✅ `status.hadPlayoff` |
| golf numeric strokes | ❌ (to-par only) | — | ✅ |
| standings | ❌ (stub) | — | ✅ **`apis/v2/.../standings?season=`** |

> **Trap:** `apis/site/v2/.../standings` returns only a `{fullViewLink}` stub.
> Real standings live at `apis/v2/...` (note: not `site`). Easy to mistake for empty.

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
- **Known-unsupported:** boxing (no ESPN sport — source elsewhere).

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
