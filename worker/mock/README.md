# Offline mock backend

A way to drive the app through **every UI permutation** — final, live, and
scheduled games for **every** sport — without waiting on the real-world calendar
("is the World Cup on right now?"). Since the app now normalizes on-device, the
mock serves **RAW ESPN shapes on ESPN paths** (it used to serve the worker's
canonical output); the app's `EspnClient` base override reroutes every ESPN
request's origin to it.

How it works, in one line: **capture real ESPN once → replay it, with the dates
rebased to "now" and the missing game-states synthesized.** Real teams, real box
scores, real scoring feeds — just time-shifted so there's always something live,
something final, and something upcoming.

```
scripts/capture-fixtures.mjs   ──(needs net, run occasionally)──▶  mock/fixtures/*.json  (committed)
mock/synth.mjs                 pure: a captured pool ──▶ raw ESPN slate anchored at "now" (final+live+scheduled)
scripts/mock-espn-server.mjs   plain http server: fixture ──▶ synth ──▶ RAW ESPN shapes on ESPN paths
```

The server needs no normalizers (the app runs them) — just `mock/synth.mjs` +
`schema/tools/resolve.mjs`. Golf `meta.golf` and MMA bouts ride the core-API
`$ref` flow: the mock emits `$ref`s whose path points back at itself (`/mock/…`),
and the app's origin-swap resolves them to the mock.

## Use it

```bash
cd worker
npm run mock                 # serves http://localhost:8787  (PORT=9000 npm run mock to change)
```

Then point the Flutter app at it: **Settings → set the API base override**:

- Desktop / iOS simulator / web: `http://localhost:8787`
- **Android emulator: `http://10.0.2.2:8787`** (the emulator's alias for the host)
- A physical device on your LAN: `http://<your-machine-ip>:8787` (the server binds `0.0.0.0`)

Every followed league now shows a mix of **final + live + scheduled** games; the
Leagues list lights up "Live now"; favorites show live/last/next cards; game
detail has real box scores and scoring feeds; standings/teams pickers populate.

## Refresh the fixtures

The data is captured ESPN snapshots, so it ages (rosters, recent results). Re-grab
any time:

```bash
npm run capture                              # every concrete league (~45)
npm run capture -- --priority v1             # just the v1 leagues
npm run capture -- --league baseball/mlb basketball/nba
npm run capture -- --no-summaries            # skip the rich detail tier (smaller/faster)
npm run capture -- --max-summaries 3 --concurrency 6
```

Fixtures land in `mock/fixtures/<sport>__<league>.json` (one slim file per league)
plus `_manifest.json` (a capture report). They're committed so the mock works
offline forever after one capture. ESPN is unofficial — be gentle (the tool
already paces requests + caps concurrency).

## What the synthesizer guarantees (see `synth.mjs`)

- **Always a full slate.** A capture taken at night is all finals; an off-season
  capture (NFL in June) is all scheduled. Either way the today view yields
  final + live + scheduled, converting between phases and fabricating the partial
  scores a target phase needs (deterministically, by event id).
- **Deterministic, current.** Scores/winners are hashed from the event id, so
  polling every 15s never makes a frozen game flicker; only the *dates* track
  `now`, so Yesterday/Today/Upcoming and relative times always read correctly.
- **Discriminator-driven, never sport-name branches.** Live labels, score shapes,
  field-vs-headToHead, and multi-competition cards (a UFC card progresses
  finished → live → upcoming bout; an F1 weekend; a tennis draw) all key off the
  resolved league profile — the same contract the renderers obey.
- **Date browsing works.** `?date=YYYYMMDD` past → finals, future → scheduled;
  `?date=START-END` (the schedule strip) spreads games across the range.

## Caveats (acceptable mock simplifications)

- The live clock is frozen at a representative mid-game point (it doesn't tick).
- For a league that had **no real games** at capture time, scores are fabricated
  (real team identities, plausible-but-invented scorelines).
- Rich `/summary` (box scores) exists only for the events whose summaries were
  captured (a few per league); others degrade to the cheap-tier detail the
  scoreboard already carries — exactly as the app handles a real summary miss.

## Tests

`npm test` runs `test/mock.test.mjs` first (offline, no network): it asserts the
synth invariants on inline fixtures **and** sweeps every captured fixture,
checking each one synthesizes + normalizes into a valid 3-state slate.
