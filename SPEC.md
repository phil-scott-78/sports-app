# Sports App — Design Spec

> A fast, calm, glanceable scores app. Stolen, with pride, from Apple's Sports app and
> [this Slate piece](https://slate.com/technology/2026/06/fifa-world-cup-apple-app-sports.html).
> The product *is* restraint: check a score in under two seconds, then leave.

Status: **draft** · Last updated: 2026-06-13

> **Data model is locked first** (you asked for this). The normalized
> cross-sport schema — verified against the live ESPN API across all sport
> families — lives in **`schema/`**: `canonical.ts` (the wire contract),
> `league-profiles.json` (the data-driven league registry / inheritance), and
> `schema/SCHEMA.md` (the design, mappings, and per-league period matrix). The
> sections below assume that contract.

---

## 1. Vision & principles

The article praises one thing: an app that does scores exceptionally well and refuses to do
anything else. No news feed, no chatbot, no streaming guide, no ads, no engagement traps.
Speed is the feature. We copy that.

Every proposed feature must pass: **"Does this help someone check a score in under two
seconds and then put the phone down?"** If not, it's cut or deferred.

1. **Glance-first** — home answers "what's the score" with zero taps for followed teams.
2. **No dark patterns** — no infinite feed, no algorithmic "for you", no ads, no AI.
3. **You curate it** — follow leagues/teams; everything else stays hidden.
4. **Fast > complete** — 6 data points instantly beats 60 slowly.
5. **Calm by default** — betting odds toggle exists but ships **OFF** (as the article praises).

## 2. Locked decisions

| Decision | Choice | Rationale |
|---|---|---|
| Client framework | **Flutter** | One Dart codebase; best-in-class Material 3 / Material You on Android; free. |
| Launch scope | **Multi-sport** (Apple-style) | Soccer + NBA/NFL/MLB/NHL. Tennis/golf are a stretch within v1 (bespoke parsers). |
| Push notifications | **v2** | Ship polling-only first; add FCM + cron-diff once core is solid. |
| Backend | **Cloudflare Worker** | Free tier; acts as cache + normalization shield over a free data API. |
| Primary data source | **ESPN unofficial JSON** | No key, no quota, consistent multi-sport scoreboard shape. |
| Data backstop | **football-data.org** (free key) | Legit, documented soccer fallback if ESPN's undocumented API breaks. |

## 3. Scope by version

**v1 — the thing that's actually good**
- Home / "My Scores": followed leagues + teams; today's games; live scores update in place.
- Game detail: score, status/clock, lineups/box score where available, event timeline
  (goals/cards/subs for soccer; scoring plays for others).
- League standings / table.
- Manage favorites: browse sports → leagues → star teams.
- Dark mode + Material You, pull-to-refresh, betting-odds toggle (default OFF).
- Team sports first (soccer, NBA, NFL, MLB, NHL). **Tennis/golf land later in v1** — they need
  bespoke parsers (match/leaderboard shapes, not team-vs-team).

**v2**
- Goal/result push notifications (FCM) + Android ongoing "live" notification (Live Activity analog).
- Home-screen widget.

**v3**
- Head-to-head & deeper stats, schedules, calendar sync, more leagues.

## 4. Information architecture

Three tabs. That's the whole app.

```
Bottom nav:
  ⚽ Scores   → followed games today (live pinned top) → Game Detail
  📊 Leagues  → standings/table + browse to add favorites
  ⚙ Settings → theme, odds toggle, refresh cadence, about
```

No home feed, no profile tab, no notifications inbox.

### Screens
- **Scores (home):** grouped by league; live games pinned and visually distinct; each card shows
  crests, abbreviations, big tabular score, status/clock. Empty state → "Add favorites".
- **Game detail:** hero score; status/clock; tabs for Timeline · Lineups · Stats (only tabs with
  data render). Odds row hidden unless toggle on.
- **Leagues:** pick a sport → league → standings table; star teams from here.
- **Settings:** theme (system/dark/light), betting odds toggle, refresh cadence, data source/about.

## 5. Visual language

- **Material 3 / Material You** so it's native on modern Android (dynamic color from wallpaper,
  proper elevation/motion). On iOS it reads as a clean Material app — acceptable for v1.
- **Dark theme default** — scores get checked on a couch in a dark room.
- **Tabular figures** for scores so digits don't jump; oversized score type; small crests.
- **Status color:** live = single accent pulse (not red-everything); final = muted; upcoming = time only.
- **Loading:** skeleton shimmer, never a blank spinner. Pull-to-refresh + silent background refresh.

## 6. Architecture

```
Flutter app (polls 15s, ONLY when a followed game is live + app foregrounded)
        │  GET /v1/scores/{sport}/{league}
        ▼
Cloudflare Worker
  ├─ Cache API (caches.default), TTL 15s live / 5m idle, stale-while-revalidate
  └─ on miss/stale → fetch upstream, normalize to canonical JSON
        │  (1 upstream call per league per TTL, shared by ALL users)
        ▼
ESPN unofficial JSON   (primary)   ·   football-data.org (soccer backstop)
```

The Worker's real job isn't "wrap an API" — it's **(a)** shield a free quota from your users by
coalescing all clients into one upstream fetch per TTL, and **(b)** normalize every sport/provider
into one canonical shape so the app never sees upstream differences and providers are swappable.

## 7. Data sources

**Primary — ESPN unofficial site API** (no key, no documented quota; verified
across all families June 2026). 148 leagues / 13 sports catalogued — see
`schema/league-profiles.json`.
```
scoreboard  https://site.api.espn.com/apis/site/v2/sports/{sport}/{league}/scoreboard
summary     https://site.api.espn.com/apis/site/v2/sports/{sport}/{league}/summary?event={id}
standings   https://site.api.espn.com/apis/v2/sports/{sport}/{league}/standings?season={year}
            ⚠️ apis/v2 — NOT apis/site/v2 (that returns only a {fullViewLink} stub)
```
Team sports share one scoreboard shape → one normalizer; individual sports
(tennis/golf/racing/MMA) and cricket/rugby get bespoke parsers. Status maps via
`status.type.{state,completed,name}` → our `Phase` (branch on `name`, not
`state`). Some data hides outside the scoreboard — soccer penalty shootouts and
MMA method of victory live in `summary`/core API. Full mappings in `schema/SCHEMA.md`.

**Backstop — football-data.org** (free key, 10 req/min): documented, legit, covers World Cup +
major soccer leagues. Used if ESPN breaks or for verification.

> ⚠️ **Honesty about ESPN:** it's undocumented and unofficial — endpoints can change without
> notice and logos/marks are ESPN/club trademarks. Fine for a personal/hobby app; the
> football-data.org key is our "go legit" escape hatch. Keep the canonical layer so swapping is cheap.

## 8. Canonical data model (Worker output)

One shape for all sports/providers. `events` and `boxscore` are sport-flavored but optional.

```jsonc
{
  "sport": "soccer", "league": "fifa.world",
  "updated": "2026-06-13T18:00:05Z",
  "anyLive": true,                       // lets the client decide poll cadence
  "games": [{
    "id": "401773456",
    "status": "live",                    // pre | live | final
    "clock": "67'",                      // minute / period+clock / inning, sport-flavored
    "startTime": "2026-06-13T17:00:00Z",
    "home": { "name": "Brazil", "short": "BRA", "crest": "https://…", "score": 2 },
    "away": { "name": "Spain", "short": "ESP", "crest": "https://…", "score": 1 },
    "events": [ { "min": 12, "type": "goal", "team": "home", "player": "…" } ],
    "odds": null                          // populated only when available
  }]
}
```

Plus a static catalog endpoint `GET /v1/catalog` listing supported sports → leagues (so the app's
"browse" UI is data-driven and you add leagues without shipping an app update).

## 9. Worker design

**Endpoints**
- `GET /v1/scores/{sport}/{league}` → canonical JSON above.
- `GET /v1/standings/{sport}/{league}` → table.
- `GET /v1/catalog` → supported sports/leagues (cacheable for hours).
- (v2) `POST /v1/register` → store FCM token + favorites for push.

**Caching (the part that makes "broke" work)**
- Use **Cache API** (`caches.default`), NOT KV — KV's 1k writes/day cap dies at 15s refresh; Cache
  API has no write cap.
- TTL: **15s when `anyLive`**, **5 min when idle** (saves upstream calls overnight/off-season).
- **stale-while-revalidate:** serve cached instantly, refresh in `ctx.waitUntil()` → feels instant,
  hides upstream latency, matches the whole "fast" thesis.
- Set permissive CORS (only needed if we ever ship a web/PWA build; harmless for native).

```js
// sketch
export default {
  async fetch(req, env, ctx) {
    const key = new Request(new URL(req.url).toString(), req);
    const cache = caches.default;
    let res = await cache.match(key);
    if (res && fresh(res)) return res;                 // hot path: instant
    const fetchFresh = async () => {
      const data = normalize(await fetchUpstream(req)); // ESPN → canonical
      const r = json(data, { ttl: data.anyLive ? 15 : 300 });
      ctx.waitUntil(cache.put(key, r.clone()));
      return r;
    };
    if (res) { ctx.waitUntil(fetchFresh()); return res; } // stale-while-revalidate
    return fetchFresh();                                   // cold miss
  }
}
```

## 10. Client architecture (Flutter)

- **State:** Riverpod (`AsyncNotifier` per league with a timer-driven auto-refresh).
- **HTTP:** `dio`. **Models:** `freezed` + `json_serializable` for the canonical types.
- **Routing:** `go_router` (3 tabs + detail).
- **Local persistence:** `shared_preferences` (favorites, settings) — small, no DB needed v1.

```
lib/
  main.dart
  app.dart                 # theme (M3, dynamic color), router
  core/
    api_client.dart        # dio + base URL of the Worker
    models/                # freezed canonical models (Game, Team, Event, …)
    favorites.dart         # shared_prefs-backed store
  features/
    scores/                # home: providers + cards + game_detail
    leagues/               # standings + browse/add favorites
    settings/
```

**Refresh policy (battery + quota friendly)**
- Poll **15s only when** a followed game is `live` **and** app is foregrounded.
- No live games → fetch on open + every 60s.
- Backgrounded → stop polling (v2 push covers this).

## 11. Free-tier reality check

| Limit | Free tier | Our usage | Verdict |
|---|---|---|---|
| Worker requests | 100k/day | ~48k/day @ 100 concurrent live users | ✅ scales with users; mitigations below |
| KV writes | 1k/day | 5,760/day if used for refresh | ❌ **don't** — use Cache API |
| Cron granularity | 1 min min. | can't do 15s | ⚠️ refresh is read-triggered, not cron |
| Cron triggers | free | v2 push diffing | ✅ |
| ESPN API | undocumented | coalesced via cache | ⚠️ unofficial; football-data.org backstop |

**Worker-budget mitigations if users grow:** put the Worker on a custom domain with Cache Rules so
repeat edge hits serve without invoking the Worker; widen idle TTL; cap poll rate client-side.

## 12. The only real cost wall

Everything above is free. The costs are distribution, not infra:
- **Google Play:** $25 one-time. (Or sideload / GitHub Releases APK while broke.)
- **Apple App Store:** $99/yr — the real wall. Ship Android first; iOS when it's worth it.

## 13. Build order

1. **Worker first** (testable in isolation): `/v1/catalog` + `/v1/scores/soccer/fifa.world` with
   ESPN normalize + Cache API + SWR. Verify with curl.
2. Add NBA/NFL/MLB/NHL leagues to the normalizer + catalog.
3. **Flutter shell:** 3 tabs, M3 theme, dio client pointed at the Worker.
4. Scores home + game detail (timeline/lineups where present).
5. Favorites (browse → star) + standings.
6. Settings (theme, odds toggle off by default), polish: skeletons, pull-to-refresh, empty states.
7. Tennis/golf parsers (bespoke shapes) — finishes v1 multi-sport.
8. **v2:** FCM push + cron score-diff; widget.

## 14. Open questions

- Exact v1 league list — `schema/league-profiles.json` tags every league `v1`/
  `v2`/`v3`; confirm the v1 cut (currently: World Cup + UCL + top-5 European
  leagues + NFL/NCAAF + NBA/WNBA/NCAAM + MLB + NHL).
- ~~Fill the registry id gaps~~ ✅ done — all concrete league ids fetched &
  verified live (2026-06-13). Remaining gaps are *live-shape* re-checks for
  out-of-season sports, not ids — see `schema/SCHEMA.md` §9.
- Do we need offline cache of last-known scores, or is "fetch on open" enough for v1?
- App name + icon.
