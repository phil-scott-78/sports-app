# sports-scores worker

Cloudflare Worker that wraps ESPN's unofficial API, **normalizes every sport to
the canonical contract** (`schema/canonical.ts`), and **coalesces all clients
into one upstream fetch per league per TTL** via the Cache API. Free-tier-shaped:
no KV/DO writes, no build step, ~zero cost.

## Endpoints

| Route | Returns | Cache TTL |
|---|---|---|
| `GET /v1/health` | `{ ok, leagues, updated }` | 60s |
| `GET /v1/catalog?priority=v1&sport=soccer` | sports → leagues (the app's picker) | 1h |
| `GET /v1/overview?priority=v1&sport=soccer` | `{ updated, leagues: [{ key, state, detail, live }] }` — per-league season pulse | 5m (**1m** when any league is live/today) |
| `GET /v1/scores/{sport}/{league}?date=YYYYMMDD` (or `YYYYMMDD-YYYYMMDD` range) | canonical `ScoresResponse` — golf events also carry `meta.golf` (cut line/major/rounds, enriched from the core tournament resource) | **15s live / 5m idle / 30s near kickoff** |
| `GET /v1/summary/{sport}/{league}/{eventId}` | rich `GameSummary` (box score, scoring feed, lineups, gridiron `drives`+full plays, soccer full feed from `commentary[]` + player box groups from roster stats, cricket `cricketInnings` scorecard, `attendance`/`officials`; MMA gets `bouts` — structured method + judge scorecards, built from core resources since ESPN's site summary 404s for MMA) | **20s live / 5m idle / 30s near kickoff** |
| `GET /v1/scorecard/{sport}/{league}/{eventId}/{playerId}?season=YYYY` | golf hole-by-hole `GolfScorecardResponse` (per-hole strokes/par/scoreType, tee times) | 60s |
| `GET /v1/rankings/{sport}/{league}` | `{ polls }` — college AP/Coaches/CFP, ATP/WTA world rankings, UFC divisions (see registry `rankingsFeed`) | 1h |
| `GET /v1/standings/{sport}/{league}?season=YYYY` | `{ groups: [{ name, rows }] }` — includes racing championships (F1 drivers/constructors, NASCAR points). **No `season` → ESPN's current season** (passing `getFullYear()` is wrong mid-year for cross-year leagues) | 1h |

`overview` fans out one cheap scoreboard fetch per league and classifies each into
`state ∈ live|today|upcoming|recent|offseason|unknown` (see `overview.js`) — the
whole pass is coalesced behind the Cache API, so the Leagues list resolves from one
shared refresh per TTL, not N fetches per client. The fan-out spends one subrequest
per league; Cloudflare caps an invocation at 50, so growth past ~48 leagues needs
chunking or a `?priority` scope.

`{sport}/{league}` is any key in `schema/league-profiles.json` (e.g.
`soccer/fifa.world`, `basketball/nba`, `golf/pga`). Unknown leagues → 404 with a
hint to `/v1/catalog`.

```bash
curl .../v1/scores/baseball/mlb
curl .../v1/scores/basketball/nba?date=20250101
curl .../v1/standings/soccer/eng.1?season=2025
```

## Architecture

```
src/
  index.js      router + CORS + Cache-API stale-while-revalidate  (the only Worker-runtime code)
  espn.js       upstream fetchers (the ONLY place that talks to ESPN — swap providers here;
                site API + core API [golf meta, MMA bouts] + the one web-API golf scorecard)
  normalize.js  raw ESPN → canonical (pure; driven by the resolved league profile)
  summary.js    raw /summary → GameSummary (pure; incl. drives, cricket matchcards, MMA core bouts)
  scorecard.js  golf playersummary → GolfScorecardResponse (pure)
  standings.js  ESPN standings → { groups, rows } (team- AND athlete-shaped entries)
  rankings.js   polls / tour rankings / UFC divisions → { polls }
  catalog.js    registry → catalog
  overview.js   raw scoreboard → season-pulse state (pure; calendar + season window)
  ttl.js        cache-lifetime policy (pure; kickoff-aware idle TTL)
imports:
  ../../schema/league-profiles.json   (bundled into the worker)
  ../../schema/tools/resolve.mjs      (shared inheritance resolver — same one the CLI tools use)
```

**Why it survives the free tier** (see `../schema/SCHEMA.md` §6):
- **Cache API + stale-while-revalidate.** A stale response is served instantly
  while one background refresh (`ctx.waitUntil`) hits ESPN. All users of a league
  share that single fetch → ~4 upstream calls/min/league regardless of traffic.
- **No KV/DO writes** (their free write quota dies at a 15s refresh). Cache API
  has no write cap.
- **TTL follows the data** (policy lives in `ttl.js`): `15s` when any game is
  live, `5m` when idle — the worker reads `anyLive` from its own normalized
  payload. The catch: before kickoff a game reads `scheduled`, so a naive idle
  TTL would cache "not started" for the full 5m and hide the idle→live flip (the
  live TTL can't help — it only engages once we've already seen a live game). So
  when a `scheduled` game is within one idle window of kickoff (or just started
  and ESPN still says `pre`), the idle TTL drops to `30s`. The payloads surface
  `nextStartMs` (soonest scheduled kickoff) to drive this.
- Response headers expose `x-cache: HIT|STALE|MISS|REVALIDATE` for debugging.

The normalizer is **profile-driven**: adding a league is a `league-profiles.json`
entry, never code here. Period structure, score kind, layout, and edge-case
handling all flow from the resolved profile.

## Develop / test / deploy

```bash
npm install            # pulls wrangler
npm test               # mock synth (offline) + live smoke test of the normalizer (no wrangler needed)
npm run dev            # wrangler dev — local worker at http://localhost:8787
npm run deploy         # wrangler deploy — to <name>.workers.dev (free)
npm run mock           # OFFLINE mock backend (same routes, replays captured ESPN) — see mock/README.md
npm run capture        # (re)capture the fixtures the mock replays (needs network)
```

### Offline mock (test every UI state without live data)

`npm run mock` serves the **same routes + canonical contract** at
`http://localhost:8787`, but offline — it replays captured ESPN fixtures through
the real normalizers and synthesizes a current **final + live + scheduled** slate
for *every* sport, so you can walk every UI permutation without depending on the
real-world calendar. Point the app at it (Settings → worker URL;
`10.0.2.2:8787` on the Android emulator). Full details + how to refresh the
fixtures: **`mock/README.md`**.

`npm test` runs `test/mock.test.mjs` (offline) then `test/normalize.test.mjs`, which fetches real ESPN scoreboards
and asserts canonical invariants (valid phase, 2-vs-N competitors by layout,
numeric scores parsed, period-driven overtime, F1 multi-competition, tennis
groupings). It needs only Node — the normalizer is pure, so no build/deploy to
validate logic.

## Keeping it correct over time

The Worker shares its resolver and registry with the verification toolkit in
`../schema/tools/`. Run `node ../schema/tools/verify.mjs --all` (CI/cron) to catch
ESPN drift before it reaches users; use the `onboard-league` workflow to add new
leagues. See `../schema/tools/README.md`.

## Not yet (v1.1+)

- Edge full coverage for the long-tail individual sports (golf cut metadata,
  racing DNF sparse-stats) beyond what the scoreboard/summary expose.
- Push (v2): a cron worker diffing scores → FCM (separate from this read path).
