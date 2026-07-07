# Drop the Worker: go direct from Flutter to ESPN

Status: **IMPLEMENTED** (2026-07-07). The app talks to ESPN directly and
normalizes on-device (`app/lib/src/data/`), verified against 265 golden-parity
fixtures + a live end-to-end render. The Cloudflare Worker runtime + deploy were
deleted; `worker/` remains as offline tooling (mock, fixtures, golden oracle).
Plan below, as executed.

## The question

Should the Flutter app stop talking to our Cloudflare Worker and hit ESPN's
APIs directly, deleting `worker/` entirely?

## Verified facts (checked live, 2026-07-06)

- All three ESPN hosts the worker uses send `Access-Control-Allow-Origin: *`:
  - `site.api.espn.com` (scoreboard, summary, teams) — also `Allow-Methods` + `Expose-Headers`
  - `sports.core.api.espn.com` (standings, golf, MMA bouts)
  - `site.web.api.espn.com` (golf playersummary/scorecard)

  So **the Flutter web build works direct too** — no CORS blocker anywhere.
- ESPN edge-caches these responses (`Cache-Control: max-age=5` on scoreboard,
  `max-age=600, stale-while-revalidate=7200` on core). Client polling at our
  15s cadence mostly lands on their CDN, not their origin.
- The worker's normalization layer is **~1,900 lines of pure JS** (no I/O):
  `normalize.js` 610, `summary.js` 680, `team.js`+`teamdetail.js` 274,
  `overview.js` 121, `calendar.js` 92, `rankings.js` 78, `ttl.js` 62,
  `scorecard.js` 60, `standings.js` 58, `catalog.js` 39 — plus
  `schema/tools/resolve.mjs` (42 lines). Everything else (`index.js` router +
  Cache API, `espn.js` fetcher) is plumbing that doesn't need porting.

## The rate-limit fear, examined

The stated worry — "our single API making all the requests to ESPN will get us
rate limited" — is actually **backwards in volume but right in spirit**:

- The worker *coalesces*: one upstream fetch per league per TTL regardless of
  user count. It makes **fewer** ESPN requests than N direct clients would.
- But it makes them all from **Cloudflare egress IPs**, which share reputation
  with every scraper on the platform. That's the real (if speculative) risk.
- Direct clients hit ESPN from residential IPs with the exact traffic pattern
  of a browser sitting on espn.com — which is what these APIs serve all day at
  massive scale. One user polling a handful of leagues every 15–60s is noise.

Per-client volume direct: (followed leagues × 1 scoreboard fetch / poll tick)
+ one summary fetch when a detail opens + rare one-offs (standings, teams,
catalog). Single-digit requests per minute. Not a rate-limit story at any
plausible user count for this app.

The one heavy endpoint is **Explore's overview** (today a single worker call
that fans out up to 48 scoreboard fetches server-side). Direct, the device
owns that fan-out — see mitigation in the plan.

## What we'd gain

- **No infra.** No Cloudflare account, no wrangler, no deploy step, no custom
  domain, no `deploy-worker` CI job, no Settings-URL dance on first run.
- **One codebase, one test suite, one language.** Today the canonical shape is
  implemented in JS and mirrored by hand in `models.dart`; every contract
  change touches three files (`canonical.ts`, worker, `models.dart`). After:
  the Dart normalizer *is* the implementation.
- **Fewer moving parts in the request path.** No worker cold starts, no
  stale-while-revalidate subtleties, no `x-cache` debugging.
- Arguably *better* latency: ESPN's CDN is closer to the user than
  user → Cloudflare → ESPN → Cloudflare → user on a cache MISS.

## What we'd lose (and how much it hurts)

| Loss | Severity | Notes |
|---|---|---|
| Server-side fix for ESPN drift | **The big one** | Today an ESPN shape change is fixed with `wrangler deploy` in minutes. Direct, every fix is an app release. Mitigated by: `verify.mjs` cron still catches drift early; tolerant parsing already absorbs most wobble; for a personal/sideloaded app, releases are cheap. Worst case, the worker is one `git revert` away. |
| Cross-client upstream coalescing | Low | Only matters at user counts this app doesn't have. ESPN's own CDN is the coalescer now. |
| Overview as one cheap call | Medium | Device must fan out ~48 fetches. Mitigate: concurrency-cap (6–8 in flight), fetch followed leagues first and stream results into the UI, cache hard (5m). Still ~48 small gzipped responses ≈ a single image's worth of bytes. |
| MMA / golf enrichment cost | Low | MMA summary = N core fetches per event; golf = +2 per event. Same fetches the worker does today, now per-device. Fine at our scale. |
| Provider-swap cheapness | Low–medium | The escape hatch survives **if** we keep the canonical boundary in Dart: one `espn_client.dart` doing I/O, normalizers behind it, UI never sees ESPN shapes. Swapping providers becomes an app release instead of a worker deploy — acceptable. |
| Offline mock via "just another URL" | None if we adapt | `synth.mjs` rebases **raw ESPN fixtures** *before* normalization, so the mock server can serve raw ESPN-shaped responses instead of canonical ones. The Settings URL field becomes an "API base override" pointed at the mock. Same workflow. |

## Decision

**Do it.** The two facts that could have killed it (CORS, rate limiting) both
clear. The remaining cost is a one-time mechanical port of ~1,900 lines of
pure JS to Dart — de-riskable with a golden-parity harness (below) — traded
for permanently deleting an entire deployment surface. The product thesis is
restraint; the architecture should match.

Non-negotiable invariant: **the canonical model stays.** `schema/` remains the
source of truth; the app keeps its discriminator-driven rendering; ESPN shapes
never leak past the normalizer. We are moving the shield into the app, not
removing it.

## Plan

### Phase 0 — Golden-parity harness (do this first; it de-risks everything)

1. Script (Node, lives in `schema/tools/` or `worker/scripts/`): run every
   committed raw fixture in `worker/mock/fixtures/` through the **existing JS
   normalizers** and write the canonical JSON outputs to
   `app/test/fixtures/golden/` (one pair per league × endpoint: raw in,
   canonical out).
2. These goldens are the port's acceptance test: the Dart normalizers must
   produce deep-equal output for every pair. Commit the goldens; the generator
   script can die with the worker.

### Phase 1 — Port the shared foundation

3. Bundle `schema/league-profiles.json` as a Flutter asset.
4. Port `resolve.mjs` (42 lines) → `lib/src/data/profiles.dart`. Port
   `catalog.js` (39 lines) on top of it — the catalog is now computed locally,
   no fetch at all.

### Phase 2 — Port the normalizers (the bulk)

5. `normalize.js` → `lib/src/data/normalize.dart`, emitting the **same
   canonical JSON maps** the worker emits today, fed into the existing
   `models.dart` `fromJson` parsers. Deliberately keep the JSON intermediate:
   `models.dart`, every widget test, and `test/fixtures/` all keep working
   untouched, and `canonical.ts` stays meaningful. (Fusing normalizer → model
   objects directly is a later optimization, probably never worth it.)
6. Then `summary.js`, `standings.js`, `team.js`/`teamdetail.js`,
   `rankings.js`, `scorecard.js`, `overview.js`, `calendar.js` — each landing
   only when its golden pairs pass. Preserve the hard-won quirks as they move
   (they're commented in the JS): status-name-not-state phase mapping, string
   scores, cumulative rugby periods, `OT_UNITS`, MMA bout reconstruction,
   soccer `commentary[]`-not-`keyEvents[]`, core-not-site standings path,
   season-param omission.

### Phase 3 — The Dart ESPN client + client-side TTL

7. `espn.js` → `lib/src/data/espn_client.dart`: the **only** module that knows
   ESPN URLs/hosts. Configurable base override (for the mock). `api.dart`'s
   public surface (`fetchScores`, `fetchSummary`, …) keeps its signatures but
   now composes `espn_client` + normalizers instead of calling the worker.
8. Port `ttl.js` into a small in-memory response cache inside the client:
   15s live / 5m idle / 30s near kickoff (`nextStartMs` logic comes along),
   so overlapping providers (home feed + league page on the same league)
   share one fetch per window — the coalescing survives, per-device.
9. Overview: port the fan-out with a concurrency cap (6–8), followed-leagues
   first, results streamed into `exploreOverviewProvider` as they land.

### Phase 4 — Mock server keeps working

10. Add a raw mode to `worker/mock/mock-server.mjs` (or move it to
    `schema/tools/mock/`): serve synth'd **raw ESPN** responses (synth already
    operates pre-normalization) on ESPN-shaped paths. Settings' URL field
    becomes "API base override" → point it at the mock. Every UI-state
    walkthrough works exactly as before.

### Phase 5 — Delete and document

11. Cut the app over (remove worker URL default/plumbing; Settings keeps only
    the mock override, tucked away). Delete `worker/src`, `wrangler`, the
    deploy CI job. Keep `worker/mock` + fixtures wherever the mock landed.
12. Update `CLAUDE.md`, `app/README.md`, `schema/SCHEMA.md` §consumers,
    `canonical.ts` header (it now documents the app's internal boundary, not
    a wire contract). Keep `verify.mjs` on cron — it's now the *only* early
    warning for ESPN drift, and drift now costs an app release.

### Sequencing note

Phases 0–2 are pure addition — the app keeps using the worker while the Dart
normalizers grow behind the golden harness. The cutover (Phase 3→5) is one
PR at the end. No big-bang risk.

## Open questions (none blocking)

- Does the Play Store / App Store care about shipping calls to an unofficial
  API? (No different from today — the traffic just moves from our domain to
  ESPN's — but worth a moment's thought before a store release.)
- `football-data.org` escape hatch: unchanged in principle (swap inside
  `espn_client.dart` + normalizers), but now costs a release. Accepted above.
