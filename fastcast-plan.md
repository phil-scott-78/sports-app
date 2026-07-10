# FastCast: live push for scores + game detail

Replace "poll faster" with ESPN's own push layer. FastCast is the unauthenticated
websocket pub/sub behind espn.com's Gamecast and scoreboards: subscribe to a topic,
fetch a full JSON snapshot ("checkpoint"), then apply a stream of RFC 6902 JSON
Patch deltas. We verified all of this live (2026-07-08) from this machine; the
protocol facts below are observed, not guessed.

## Verified protocol (don't re-derive; do re-verify anything marked open)

1. `GET https://fastcast.semfs.engsvc.go.com/public/websockethost` → `{ip, securePort, token}`.
   No cookies/account/API key. Token is short-lived — fetch a fresh one per connect.
2. Connect `wss://{ip}:{securePort}/FastcastService/pubsub/profiles/12000?TrafficManager-Token={token}`
   — token goes in **raw, unencoded**. Server rejects the upgrade without a plausible
   `Origin: https://www.espn.com` + browser `User-Agent` (Node's built-in WebSocket
   can't send them). Don't negotiate permessage-deflate; it works without it.
   **Fastcast/4.1.26 matches request header NAMES case-SENSITIVELY** (verified live
   2026-07-09, bisected header-by-header): lowercase `upgrade` → `{"rc":404,
   "op":"ERROR"}`; lowercase `Host` / `Sec-WebSocket-Key` / `Sec-WebSocket-Version`
   → the server hangs. `Connection`/`Origin`/`User-Agent` are case-insensitive.
   So `WebSocket.connect` is unusable (it writes its own headers lowercase, no
   override) — `fastcast_client.dart` drives the upgrade via `HttpClient` with
   `set(..., preserveHeaderCase: true)`, then `detachSocket()` →
   `WebSocket.fromUpgradedSocket`. Keep the casing exact if you touch it.
3. Send `{"op":"C"}` → `{"rc":200,"hbi":30,"op":"C","sid":"..."}`. Server pings; answer
   pongs. `hbi` = heartbeat interval seconds.
4. Subscribe: `{"op":"S","sid":sid,"tc":"<topic>"}`. One socket multiplexes all topics.
5. First message per topic: `{"op":"H","pl":"<https checkpoint URL on fcast.espncdn.com>","mid":N}`
   → plain GET returns the full current doc (~340KB league doc, ~886KB gamepackage).
6. Deltas: `op:"P"` or `"R"` messages; `pl` is a JSON string `{ts, "~c", pl}`. `~c:1` →
   inner `pl` is base64 + zlib-deflate; `~c:0` → plain. Decoded payload is an RFC 6902
   patch array. Apply in `mid` order; a `mid` gap means you missed messages → refetch
   checkpoint (or trigger one reconciliation poll). Never crash on a bad path — resync.
7. Topics: `gp-{sport}-{league}-{eventId}` (the gamepackage doc for one game) and
   `event-{sport}-{league}` (the league slate). Also `event-topevents` (cross-league).

Quirks (both observed live):
- `event-*` patch paths are **uid-prefixed, not standard pointers**:
  `s:1~l:10~e:401816076~c:401816076/situation/balls` — resolve the event by uid inside
  the doc, then apply the remainder as a pointer within it. `gp-*` uses standard
  root-relative paths.
- gp docs contain intra-doc refs as values (`{"$ref":"#/plays/499"}` in `atBats`).
  Store verbatim; confirm `normalizeSummary` never dereferences them.

Measured rates: `event-basketball-wnba` with one live game ≈ 0.2 frames/s, ~150 B/s.
The firehose is only the `gp-*` topic (boxscore stat churn) — subscribe to it only
while a detail screen is open.

## The design: two tracks

**Track 1 — live game detail (do first; biggest payoff, least risk).**
Verified: the `gp-*` checkpoint is **shape-identical to `site/v2/summary`** (same 22
top-level keys, same nested shapes). So when a live game's detail opens: subscribe
`gp-...`, fetch checkpoint (this REPLACES the summary fetch; ≥100KB isolate-decode
rule applies), apply patches, re-run the existing `normalizeSummary` on a throttle
(coalesce, re-emit ≤1/s). Zero new normalizers. Unsubscribe on close.

**Track 2 — slate overlay (scores tab / home feed).**
The `event-*` doc is NOT the scoreboard shape (events flattened: no `competitions[]`,
team merged into competitor, no linescores/leaders/probables). It cannot replace the
scoreboard — it's an **overlay**: one new pure normalizer (`fastcastSlate`) emits
per-event partial updates (score, phase from `fullStatus.type.name` — the normal
status object, so house phase-branching rules hold — clock, status detail, situation,
`seriesSummary`), merged over the last polled canonical slate in the provider. The
scoreboard poll survives, demoted to slow reconciliation (~120–300s while the socket
is healthy) + an immediate refetch on reconnect/mid-gap.

Fallback model: when the socket is unavailable (mock mode, background, errors),
everything silently reverts to today's polling. No new settings. Foreground-only,
same lifecycle as polling. The offline mock needs nothing for v1.

## Components (follow the house pattern — JS oracle + Dart port in lockstep)

- `worker/src/fastcast.js` — pure: `applyOps(doc, ops)` (standard RFC 6902),
  `applyEventOps(doc, ops)` (uid-prefixed variant), `normalizeFastcastSlate(doc, profile)`.
- `worker/scripts/capture-fastcast.mjs` — record `{checkpoint, frames[]}` per topic to
  `worker/mock/fixtures/fastcast/` (committed). Streams are replayable → extend
  `gen-goldens.mjs` to emit staged snapshots + normalized outputs to
  `app/test/fixtures/golden/fastcast/`.
- `app/lib/src/data/fastcast.dart` — faithful port, byte-for-byte parity via a new
  `app/test/port_fastcast_test.dart` replaying the same fixtures.
- `app/lib/src/data/fastcast_client.dart` — the only new I/O, beside `espn_client.dart`:
  handshake, socket, C/S ops, pong, inflate, ref-counted topic subscriptions,
  mid-gap detection, reconnect (fresh token, jittered backoff), foreground-only.
- `api.dart` — `liveSummary(sport, league, eventId)` and `liveSlate(leagueKey)` streams;
  `providers.dart` sources `summaryProvider` / merges into `leagueScoresProvider` +
  `feedProvider` when healthy.
- Registry: `capabilities.fastcast` per family/league, set only after the topic is
  verified to exist (normal `extends` resolution, `hasCapability` gate).

## Phases (each lands green: analyze + tests + parity)

0. **Recon + capture** — ✅ DONE 2026-07-08 (verified green: worker npm test,
   flutter analyze + test all pass; goldens regenerated for the registry change).
   See "Phase 0 findings" below — read them before Phase 1/2; several change the
   design assumptions (topic dynamism, mid gaps, no soccer goal timeline).
1. **Pure layer** — ✅ DONE 2026-07-08 (verified green: worker npm test incl. the
   new `test/fastcast.test.mjs` 46/46, flutter analyze clean, flutter test 471/471
   incl. `port_fastcast_test.dart` 5/5 byte-for-byte). See "Phase 1 notes" below.
2. **Live game detail** — ✅ DONE 2026-07-08 (verified green: flutter analyze
   clean, flutter test 479/479 incl. the new client state-machine + wiring
   suites, worker npm test all pass). See "Phase 2 notes" below.
3. **Slate overlay** — ✅ DONE 2026-07-09 (verified green: flutter analyze
   clean, flutter test 486/486 incl. the new merge + slate-provider suites,
   worker npm test all pass). See "Phase 3 notes" below.
4. **Optional**: hand-rolled ws replay endpoint in the offline mock (pure Node, no
   deps — we already hand-rolled the client side) so megaweek demos push.

Working probe scripts from the recon session (handshake/framing/decode reference,
rewrite as proper tooling): they live in the session scratchpad, but everything they
proved is written down above; the framing is standard ws (client-masked frames,
pong replies), the decode is `JSON.parse` → base64 → `inflate` → `JSON.parse`.

## Phase 0 findings (recon + capture, all observed live 2026-07-08)

Tooling landed: `worker/scripts/capture-fastcast.mjs` — hand-rolled ws client
(pure Node, no deps): `--probe [--topic ...|--priority v1]` for topic existence,
`--capture <topic...> [--duration s]` records `{checkpoint, frames[]}` to
`worker/mock/fixtures/fastcast/` (committed). Reuse its socket/decode code as the
reference when writing `fastcast_client.dart`.

1. **Topic naming is the registry slug verbatim** — dots and numeric ids fine
   (`event-soccer-usa.1`, `event-soccer-fifa.world`, `event-cricket-8053` all
   exist). No id-based or escaped variant needed.
2. **Topics are DYNAMIC: they exist only while the league is in season/active.**
   All big-5 European soccer topics 404'd in July while `usa.1`/`fifa.world`
   existed. The subscribe ack itself is the existence signal: `{"op":"S","rc":200}`
   → topic live (an `op:"H"` follows); `rc:404` → no topic. So
   `capabilities.fastcast` means "family is fastcast-served"; the CLIENT must
   treat rc:404 as a silent per-league fallback to polling, and may retry later
   (a dormant league's topic can appear when its season starts).
3. **`capabilities.fastcast` set** (family level, normal extends merge) on:
   soccer, football, basketball, baseball, hockey, golf, tennis, mma, racing,
   cricket — each verified via an in-season league answering with an H checkpoint.
   NOT set: rugby (couldn't verify — probed league dormant), rugby-league
   (`event-rugby-league-3` 404'd with NRL mid-season → genuinely unserved).
   SCHEMA.md §2a table has the row; registry synced; goldens regenerated.
4. **Soccer's event doc does NOT carry the goal timeline** — finished World Cup
   events have only score/status/clock/form/odds/competitors, no scorers or
   keyEvents. Track 2's overlay supplies score/phase/clock/situation only; the
   cheap goal/card timeline stays with the scoreboard poll (`competition.events`).
5. **mid gaps occur on a healthy connection** (event-baseball-mlb delivered
   ...303, 305... with 304 never sent, repeatedly). mid is NOT strictly
   contiguous per topic — a naive "gap → resync" will thrash. Phase 2 must
   verify the real gap semantics (likely: only treat as a miss if a P patch
   fails to apply, or track gaps only across reconnects) before wiring resync.
6. **After H, expect `op:"R"` frames** (replay/catch-up deltas bridging the
   checkpoint to now) before live `op:"P"` frames; decode identically. Unknown
   topicless frames exist too (`{"op":"B"}` observed) — ignore unknown ops.
7. Fixtures captured (committed): `event-baseball-mlb` (live slate, 20 patch
   frames), `event-basketball-wnba` (live game), `event-soccer-usa.1` (all
   pregame), `event-soccer-fifa.world` (all post), `gp-baseball-mlb-401816076`
   (993KB checkpoint + live patches). gp checkpoint has 21 top-level keys
   (boxscore/plays/playsMap/atBats/winprobability/header/rosters/... — the
   summary shape; count varies by sport, don't assert 22).
8. **Odds churn dominates event-\* patches** (moneyline/spread/total on every
   frame; situation/score are the minority) — the "filter patch batches that
   only touch unrendered paths" guardrail is load-bearing, not optional.
9. Uid-prefixed event paths confirmed: `<uid-with-~>/situation/balls`,
   `<uid>/odds/...`; the uid segment is the event's full `s:1~l:10~e:...~c:...`
   uid, resolve to the event then apply the remainder as a standard pointer.

## Phase 1 notes (pure layer, landed 2026-07-08)

What exists now (JS oracle ⇄ Dart port, in lockstep like every other normalizer):

- `worker/src/fastcast.js` + `app/lib/src/data/fastcast.dart`:
  `applyOps(doc, ops)` (standard RFC 6902, gp-* topics), `applyEventOps(doc,
  ops)` (uid-prefixed event-* variant), `normalizeFastcastSlate(reg, key, doc)`
  (the Track-2 overlay). Both appliers deep-copy the input and return
  `{doc, errors}` — they NEVER throw; non-empty `errors` = caller resyncs.
  Semantics chosen (both sides, parity-pinned): `replace` is lenient
  (set-semantics — FastCast replaces paths it never added; strict RFC existence
  checks would spray resyncs); `test` failure is recorded but doesn't abort the
  batch; root-path ops are rejected (docs are replaced via checkpoint, not
  patched at root). The uid segment of an event path is split on '/' BEFORE
  RFC 6901 unescaping (uids contain literal '~').
- Overlay shape emitted per event: `{id, uid?, status{phase/live/ended/period/
  periodLabel/espnName/detail/shortDetail?/clock?}, competitors[{id, homeAway?,
  score(buildScore canonical), winner?}], situation?, seriesSummary?}` — field
  names + derivations mirror `buildCompetition` exactly (same displayClock
  '0:00' suppression, phase from `fullStatus.type` via `statusToPhase`).
  `buildScore`/`buildSituation` are now EXPORTED from normalize.js / public in
  normalize.dart and reused (the fastcast event's `situation` is
  scoreboard-shaped; event-level `outsText` passes through it).
- `worker/test/fastcast.test.mjs` (46 asserts, in `npm test` chain): op
  coverage, escapes, bad-path resilience, uid resolution, synthetic slate
  normalization (incl. the postponed-beats-state guard), and full replay of
  every committed capture (all 5 replay with ZERO patch errors — the observed
  mid gaps did NOT produce unappliable patches, supporting the "don't thrash on
  mid gaps" note in Phase 0 finding #5).
- Goldens: `gen-goldens.mjs` replays `mock/fixtures/fastcast/` → golden
  `fastcast/<topic>.json` = `{args: whole capture, output: {finalDoc, errors,
  slates?}}` where `slates` (event topics) is the overlay at the checkpoint and
  after EVERY frame. `port_fastcast_test.dart` replays the same and matches
  byte-for-byte. NOTE: golden key derivation `topic.replace(/^event-/,'')
  .replace('-','/')` is fine for every current capture but would mis-split a
  future `event-rugby-league-*` capture — fix there if rugby-league ever gains
  fastcast.

Phase 2 pointers: `fastcast_client.dart` should reuse the handshake/framing/
decode reference in `worker/scripts/capture-fastcast.mjs` (hand-rolled, working).
The subscribe ack `rc` (200/404) is the topic-existence signal (finding #2);
`op:"R"` frames follow H before live `op:"P"`s and decode identically; ignore
unknown ops (`op:"B"` exists). Dart-side inflate: `ZLibCodec` handles the
zlib-deflate payloads (`~c:1` → base64 → inflate → JSON). The gp checkpoint is
summary-shaped (verified again on the live capture: 21 top-level keys, `$ref`
values in `atBats` stored verbatim and normalizeSummary never dereferences
them) — feed it straight to `normalizeSummary`, ≥100KB isolate-decode rule
applies to the checkpoint GET.

## Phase 2 notes (live game detail, landed 2026-07-08)

What exists now:

- `app/lib/src/data/fastcast_client.dart` — the push client (the only new I/O
  beside espn_client). ONE socket, ref-counted topics via
  `docs(topic) → Stream<doc>`; dart:io `WebSocket.connect` with Origin/browser-UA
  headers, `customClient` with a badCertificateCallback pinned to the handed-out
  IP (the LB cert names the service host, not the IP — same trust call as the
  recon tooling), compression OFF, token raw in the query. dart:io answers
  server pings automatically. Key semantics (all unit-tested with injected
  fakes, `test/fastcast_client_test.dart`):
  - Patches COALESCE: ops accumulate and apply ONCE per 1s throttle window —
    one `applyOps` deep-copy per window, not per frame. Batches touching only
    `/odds|/pickcenter|/againstTheSpread` (uid prefix stripped first, so it'll
    hold for event-* too) apply silently without re-emitting.
  - mid is IGNORED entirely (finding #5); a failed patch APPLY triggers a
    checkpoint refetch, rate-limited to 1/10s so a bad stream can't thrash.
  - rc:404 or no-H-within-15s → error + CLOSE the topic stream (terminal:
    league unserved → consumer settles on polling). Disconnect → error WITHOUT
    close (fallback signal), then reconnect (fresh token, jittered exponential
    backoff, gives up after 5 attempts until a new subscribe/foreground).
  - Foreground-only via its own WidgetsBindingObserver (constructor flag
    `watchLifecycle: false` in tests); backgrounding closes the socket, resume
    reconnects + re-checkpoints. No unsubscribe op is sent (none verified);
    topic removal just ignores frames, and the socket closes when NO topics
    remain (the common single-detail case).
  - Checkpoint GET does the ≥100KB isolate-decode (own `compute` path).
- `Api(baseUrl, [espnClient, fastcastClient])` — third optional arg; the client
  is created ONCE in `fastcastClientProvider` and injected by `apiProvider`, so
  a Settings change rebuilds Api without dropping the socket.
  `liveSummarySupported(league)`: false when no client injected, base override
  set (mock mode polls), registry not loaded (widget tests), sport is
  mma/tennis (bespoke summary paths), or no `fastcast` capability.
  `liveSummary(league, eventId)` (async*): subscribes `gp-{sport}-{slug}-{id}`,
  runs each emitted doc through the SAME `normalizeSummary`, and re-runs
  `_enrichLiveDetail` per emission — the espn_client cache TTLs (situation 12s,
  predictor 20s) rate-limit those CORE fetches, so push doesn't multiply them.
- `liveSummaryProvider` (StreamProvider.autoDispose.family, providers.dart) +
  the detail page: `_pushEligible` = live && supported; while the push value is
  healthy (`hasValue && !hasError`) it short-circuits `??` so summaryProvider
  is NOT watched and `onPoll` skips the summary invalidation (the 20s re-fetch
  dies while push is up). Any push gap → the polled path resumes silently, and
  switches back on the next emission. The scoreboard poll (leagueScores) is
  UNTOUCHED — it still flips status/eligibility and feeds the header.
- **No push on WEB, by design** (`kIsWeb` short-circuits `_fastcastReady`,
  2026-07-09): the socket is dart:io (stubbed on web — `Platform._version`
  throws at runtime), and a browser can't send the Origin/UA headers the
  upgrade requires anyway. Web silently polls; push needs a native target
  (windows/android/ios/macos).
- Honesty notes: the FIRST /summary fetch still happens on open (the page
  watches summaryProvider until the checkpoint lands — instant first paint,
  one redundant ~summary-sized fetch); push replaces the POLL, not the first
  fetch. And a long-open detail whose socket gave up (5 attempts) stays on
  polling until backgrounded/reopened — acceptable v1.

Phase 3 pointers: the client already routes `event-*` topics to `applyEventOps`
and the noise filter already strips uid prefixes — `docs('event-...')` works
today; what's missing is the api/provider merge (`liveSlate` over
`normalizeFastcastSlate` merged into leagueScores/feed) + poll demotion
(~120–300s reconciliation while healthy) and an `Api`-level topic-health signal
the Scores tab can read (the detail page pattern — AsyncValue health — should
generalize). Note rc:404 currently CLOSES the stream; for slates you may want a
retry-later (dormant league's topic appears at season start, finding #2).

## Phase 3 notes (slate overlay, landed 2026-07-09)

What exists now:

- `app/lib/src/data/fastcast_merge.dart` — `mergeFastcastSlate(profile, slate,
  overlay)`: the Track-2 join. Dart-only, NO JS oracle (downstream of canonical,
  like marquee.dart — both inputs are already-normalized; there is no
  worker-side merge). Unit-tested against REAL `normalizeScoreboard` output
  (`test/fastcast_merge_test.dart`). Semantics: match a competition by comp id
  (event-id fallback for single-comp events; multi-comp events — racing,
  tennis draws — only merge on an exact comp-id hit); replace status
  (preserving poll-only `altDetail`), score/winner by competitor id, situation
  (KEPT when the overlay omits one — some event docs never carry it),
  seriesSummary → meta; recompute `decision` (normalize.dart's `decide` +
  `otUnits` are now PUBLIC for this), bump `periods.played`/`isOvertime`, and
  refresh top-level `anyLive`/`nextStartMs` (they drive poll cadence). New
  events on ESPN's slate arrive ONLY via the reconciliation poll — the merge
  never inserts.
- `Api`: `liveSlateSupported` (the shared `_fastcastReady` gate — capability +
  ESPN-direct + registry loaded; no sport exclusions), `liveSlate(league)`
  (subscribes `event-{sport}-{slug}`, emits `normalizeFastcastSlate` maps),
  `mergeSlate(league, overlay)` (pure in-memory join over `_lastNorm`, the last
  polled TODAY norm now cached per league in `scores()` — which also SKIPS
  re-normalizing when the espn_client cache returned the identical raw map).
- Providers — the load-bearing shape: `liveSlateProvider` (StreamProvider
  family) + **synchronous merged layers** `mergedFeedProvider` /
  `mergedLeagueScoresProvider` over the untouched poll providers. UI watches
  the merged ones; `invalidate`/`.future` still target the raw ones. DO NOT
  make the Future providers watch the overlay directly: each push emission
  would re-run them and any run >15s after the last fetch re-hits the network
  (espn ttl) — push would then INCREASE fetches. The sync layer is what makes
  demotion real. Overlay errors (`hasError`) skip the merge → polled data
  serves; recovery re-merges automatically.
- Poll demotion (`AppConfig.refreshReconcile` = 180s): scores tab, league page,
  today page, and game detail all demote their LIVE cadence to reconciliation
  when every live league in view is push-healthy (detail additionally requires
  the gp summary stream healthy). Favorite hero cards and BIG GAMES are
  poll-only — any live one blocks the scores tab's demotion. Push death →
  merged providers change → repace → cadence snaps back; the next poll
  refetches (cache long-expired at 180s).
- `LifecyclePoll.repace` now KEEPS the running timer when the cadence is
  unchanged — push emissions call repace ~1/s via data listeners, and the old
  cancel-and-recreate would have reset the 180s reconciliation timer forever
  (it would never fire). Watch for this if adding new repace call sites.
- End-to-end test `test/fastcast_slate_provider_test.dart`: fake socket →
  event checkpoint → liveSlateProvider → mergedLeagueScoresProvider serves the
  pushed score/clock over the mocked polled slate; plus the rc:404 fallback.

Known limits (deliberate, v1): topics are subscribed per watched league while
screens are open (idle in-season leagues included — traffic is noise-filtered
and tiny); an rc:404 (dormant) league stays on polling for the life of the
screen (no retry-later); overlay never inserts events; teamCard (hero cards) is
not push-fed. Soccer's goal timeline stays with the scoreboard poll (finding
#4).

Phase 4 pointers (optional mock replay): the offline mock would need a ws
endpoint replaying `mock/fixtures/fastcast/` — BUT the client is gated OFF in
mock mode (`baseUrl` override → `_fastcastReady` false). To demo push against
the mock you'd need: (1) a `FastcastClient(connector:, fetchJson:)` pointed at
the mock's host/ws/checkpoint endpoints (the seams already exist), and (2) the
gate relaxed when the override serves fastcast — worth doing only if megaweek
demos need live flips. The hand-rolled ws FRAME writer already exists in
capture-fastcast.mjs (encodeFrame/drain) — the mock server needs the server
side (unmasked frames out, masked frames in, no deflate).

## Protocol soak (monitor-fastcast.mjs, started 2026-07-09)

Tooling: `worker/scripts/monitor-fastcast.mjs` — a days-long protocol monitor.
Subscribes the v1 event topics (+`event-topevents`, + auto-discovered gp topics
for live games), maintains live docs with the ORACLE appliers, and records
every deviation as a signature with up to 6 context-rich samples →
`worker/monitor/summary.json` (rewritten each minute) + `events.jsonl`
(gitignored). Restart-safe (merges prior counts). The shared ws client now
lives in `worker/scripts/fastcast-ws.mjs` (extracted from capture-fastcast.mjs;
both import it). Re-probes rc:404 topics every 6h (finding #2's retry-later
question). Run: `node scripts/monitor-fastcast.mjs [--hours 72]`.

Findings from the first minutes (2026-07-09, live MLB):

- **`op:"I"` exists** — `{"op":"I","pl":"0","mid":N,"tc":topic}`, regular per
  topic, and it CONSUMES a mid. This almost certainly explains Phase 0 finding
  #5's "mid gaps on a healthy connection": the gaps were `I` frames we ignored.
  The app client's "ignore unknown ops + ignore mids" design handles it
  correctly by construction; treat `I` as a per-topic heartbeat.
- **`move` and `copy` RFC ops occur in the wild** (gp topic, R and P frames) —
  the appliers' full RFC 6902 support is load-bearing, not defensive.
- **Post-checkpoint apply-errors are real but explainable**: the R replay
  bridging a checkpoint can race a NEWER snapshot (remove/replace of an
  already-gone `pickcenter …/link` key), and steady-state odds-path errors of
  the same shape appear too — supporting the app client's lenient-replace +
  drop-raced-pending + rate-limited-resync choices. Watch the soak's
  steady-state `apply-error` (vs `apply-error-postsync`) counts to see whether
  real divergence ever hits RENDERED paths (everything seen so far is odds).

Product guardrails: restraint still rules. The win is "the score flips the moment it
happens" on screens the user already looks at — not new UI. Filter patch batches that
touch only paths we don't render (odds churn) before re-normalizing; throttle
re-emits; one socket total.
