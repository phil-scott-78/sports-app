import 'package:flutter/foundation.dart' show kIsWeb;

import 'data/espn_client.dart';
import 'data/fastcast.dart' as fcst;
import 'data/fastcast_client.dart';
import 'data/fastcast_log.dart';
import 'data/fastcast_merge.dart';
import 'data/identity_cache.dart';
import 'data/profiles.dart';
import 'data/normalize.dart';
import 'data/calendar.dart' as cal;
import 'data/summary.dart' as sm;
import 'data/standings.dart' as st;
import 'data/rankings.dart' as rk;
import 'data/scorecard.dart' as sc;
import 'data/team.dart' as tm;
import 'data/teamdetail.dart' as td;
import 'data/overview.dart' as ov;
import 'data/venue.dart' as vn;
import 'data/matchfeed.dart' as mf;
import 'data/athlete.dart' as ath;
import 'data/teamleaders.dart' as tl;
import 'data/tournament.dart' as tn;
import 'marquee.dart';
import 'models.dart';

export 'data/espn_client.dart' show ApiException;

/// Aggregate freshness of a set of scoreboards — the input to the Scores
/// header's dim "Updated …" line. [stale] is true when the slate is being served
/// from cache after a failed refetch (offline / 5xx / timeout); [lastUpdated] is
/// the most recent successful scoreboard fetch among the leagues.
class FeedFreshness {
  final bool stale;
  final DateTime? lastUpdated;
  const FeedFreshness({required this.stale, this.lastUpdated});
}

/// The app's data layer. Formerly a thin HTTP client to the Cloudflare worker;
/// now it talks to ESPN directly (via [EspnClient]) and runs the SAME canonical
/// normalizers the worker used to run — ported to Dart under lib/src/data/. The
/// method surface is unchanged, so providers/UI didn't move.
///
/// Normalization stays on the main isolate on purpose: payloads are mostly
/// small (a league scoreboard ≈45 KB) and the normalizers are pure map work.
/// The exception is the JSON *decode* of big bodies (college scoreboards,
/// teams, rich summaries) — [EspnClient] offloads those to a background
/// isolate so they can't jank the UI.
class Api {
  /// Optional ESPN-origin override (Settings) — points at the offline mock. Empty
  /// → ESPN direct. (Was the worker base URL; repurposed as the mock override.)
  final String baseUrl;
  final EspnClient _c;

  /// The shared FastCast push client (ONE socket app-wide, injected by
  /// [apiProvider] so it survives an [Api] rebuild). Null → push disabled,
  /// everything polls exactly as before.
  final FastcastClient? _fastcast;

  /// [client] is injectable for tests (offline mock / stale-while-revalidate
  /// checks); production always builds one from [baseUrl].
  Api(this.baseUrl, [EspnClient? client, FastcastClient? fastcast])
      : _c = client ?? EspnClient(baseUrl),
        _fastcast = fastcast;

  /// Direct-to-ESPN needs no configuration, so the app is always "configured".
  bool get configured => true;

  Registry get _reg => Registry.instance;

  // ---- health ----------------------------------------------------------------
  /// No worker to ping and no server-driven version gate when going direct, so
  /// this returns a healthy stub with a null client gate (→ no update banner).
  Future<HealthInfo> health() async =>
      HealthInfo(ok: true, leagues: _reg.leagues.length, client: null);

  // ---- scores ----------------------------------------------------------------
  /// The last raw + normalized TODAY scoreboard per league. The norm is the
  /// slate the fastcast overlay merges over ([mergeSlate]); the raw reference
  /// doubles as a re-normalize skip — an espn_client cache hit returns the
  /// IDENTICAL map, so the canonical output can't differ (a push-driven
  /// provider re-run then costs a map lookup, not a full re-normalize).
  final Map<String, Map> _lastRawSb = {};
  final Map<String, Map<String, dynamic>> _lastNorm = {};

  Future<ScoresResponse> scores(String league, {String? date}) async {
    final sb = await _c.scoreboard(league, date: date) as Map;
    final extras = await _golfExtras(league, sb);
    Map<String, dynamic> norm;
    if (date == null &&
        extras.isEmpty &&
        identical(sb, _lastRawSb[league]) &&
        _lastNorm[league] != null) {
      norm = _lastNorm[league]!;
    } else {
      norm = normalizeScoreboard(_reg, league, sb, extras);
    }
    if (date == null) {
      _lastRawSb[league] = sb;
      _lastNorm[league] = norm;
    }
    // Warm the identity cache off every scoreboard (the color/logo source
    // color-less screens — standings, brackets — join against). §3.1.
    IdentityCache.instance.warmScoreboard(norm);
    return ScoresResponse.fromJson(norm);
  }

  /// Aggregate freshness of [leagues]' scoreboards at [date] — drives the Scores
  /// header's stale line. Reads the freshness [EspnClient] recorded for each
  /// league's last scoreboard fetch; a league not yet fetched contributes
  /// nothing. `stale` is true when ANY of them is being served from an expired
  /// cache; `lastUpdated` is the newest successful fetch among them.
  FeedFreshness feedFreshness(List<String> leagues, {String? date}) {
    var stale = false;
    int? newest;
    for (final key in leagues) {
      final f = _c.scoreboardFreshness(key, date: date);
      if (f == null) continue;
      if (f.stale) stale = true;
      if (newest == null || f.fetchedAtMs > newest) newest = f.fetchedAtMs;
    }
    return FeedFreshness(
      stale: stale,
      lastUpdated:
          newest == null ? null : DateTime.fromMillisecondsSinceEpoch(newest),
    );
  }

  /// Golf meta (cut/major/rounds → meta.golf) rides the CORE tournament resource,
  /// not the scoreboard — fetch it per event (≤3, best-effort). Mirrors the
  /// worker's golfExtras().
  Future<Map<String, dynamic>> _golfExtras(String league, Map sb) async {
    final prof = resolve(_reg, league);
    if (prof['espnSport'] != 'golf' || prof['layout'] != 'field') return const {};
    final ids = (sb['events'] is List ? sb['events'] as List : const [])
        .map((e) => (e as Map)['id'])
        .where((id) => id != null)
        .take(3)
        .toList();
    if (ids.isEmpty) return const {};
    final tournaments = <String, dynamic>{};
    await Future.wait(ids.map((id) async {
      try {
        final ev = await _c.coreEvent(league, id.toString());
        final ref = (ev is Map) ? (ev['tournament'] is Map ? ev['tournament']['\$ref'] : null) : null;
        if (ref != null) tournaments[id.toString()] = await _c.coreRef(ref.toString());
      } catch (_) {/* meta optional */}
    }));
    return tournaments.isNotEmpty ? {'golfTournaments': tournaments} : const {};
  }

  // ---- date-strip coverage (has-games dots) ----------------------------------
  /// Which LOCAL days in [start]..[end] ('YYYYMMDD') carry >=1 real game across
  /// [leagues] — the date-strip's per-day has-games dots. ONE wide
  /// `?dates=start-end` RANGE scoreboard per league (the cheapest scan that works
  /// everywhere), read for ACTUAL events (the `leagues[].calendar[]` hint is
  /// sparse for MLB → we cross-check events before a day can dim). Cheap tier,
  /// fetched ONCE per strip window and cached ~30 min in [EspnClient] — this
  /// NEVER rides the scores poll loop. Per-league best-effort: a failed league
  /// (offseason 404 / offline) simply contributes no days. Concurrency-capped.
  Future<Set<String>> coverage(List<String> leagues, String start, String end) async {
    if (leagues.isEmpty) return const <String>{};
    final range = '$start-$end';
    final sets = await _pool<String, Set<String>>(leagues.toList(), 6, (key) async {
      try {
        final sb = await _c.scoreboard(key, date: range, ttl: 1800);
        return cal.coverageDaysLocal(sb);
      } catch (_) {
        return <String>{};
      }
    });
    return {for (final s in sets) ...s};
  }

  // ---- summary ---------------------------------------------------------------
  Future<GameSummary> summary(String league, String eventId) async {
    final sport = resolve(_reg, league)['espnSport'];
    if (sport == 'mma') {
      return GameSummary.fromJson(await _mmaSummary(league, eventId));
    }
    // Tennis /summary is DEAD — ESPN 400s for every event/competition id
    // permutation (verified 2026-07; see the tennis rankingsNote in
    // league-profiles). Skip the always-failing fetch: the match's whole story
    // is the cheap-tier set grid + situation card. Returning an empty summary
    // keeps the detail screen on its set-grid path with no network churn.
    if (sport == 'tennis') {
      return GameSummary.fromJson(const <String, dynamic>{});
    }
    final raw = await _c.summary(league, eventId) as Map;
    final out = sm.normalizeSummary(_reg, league, raw);
    await _enrichLiveDetail(league, eventId, raw, out);
    return GameSummary.fromJson(out);
  }

  /// Detail-open CORE enrichments merged into the summary payload — piggybacking
  /// the summary poll, never the scores poll (fetch-budget rule). Two lazy,
  /// capability-gated, best-effort fetches, only while the game is LIVE:
  ///   1. core `situation` → the live gridiron down/distance, basketball
  ///      bonus/timeouts, hockey power play the summary can't carry
  ///      (`hasCoreSituation`). situation.lastPlay.$ref is resolved for the text.
  ///   2. core `predictor` → win probability, ONLY when the summary had none but
  ///      the league `hasWinProb` (the winprobability[] fallback).
  /// Any failure (offseason 404, offline) leaves the summary exactly as normalized.
  Future<void> _enrichLiveDetail(
      String league, String eventId, Map raw, Map<String, dynamic> out) async {
    if (out['live'] != true) return;
    final prof = resolve(_reg, league);
    // The core paths key on the COMPETITION id (≠ event id for some sports).
    final comps = (raw['header'] is Map) ? (raw['header'] as Map)['competitions'] : null;
    final comp0 = comps is List && comps.isNotEmpty ? comps.first : null;
    final compId = (comp0 is Map ? comp0['id'] : null)?.toString() ?? eventId;
    await Future.wait([
      if (hasCapability(prof, 'hasCoreSituation'))
        () async {
          try {
            final rawSit = await _c.coreSituation(league, eventId, compId);
            // Best-effort resolve the last-play text behind situation.lastPlay.$ref.
            String? lastPlayText;
            final lpRef = (rawSit is Map && rawSit['lastPlay'] is Map)
                ? (rawSit['lastPlay'] as Map)['\$ref']
                : null;
            if (lpRef is String) {
              try {
                final play = await _c.coreRef(lpRef);
                final t = (play is Map) ? play['text'] : null;
                if (t is String) lastPlayText = t;
              } catch (_) {/* text optional */}
            }
            final sit = sm.buildCoreSituation(rawSit, lastPlayText);
            if (sit != null) out['situation'] = sit;
          } catch (_) {/* situation optional */}
        }(),
      if (out['winProbability'] == null && hasCapability(prof, 'hasWinProb'))
        () async {
          try {
            final pred = await _c.corePredictor(league, eventId, compId);
            final wp = sm.winProbabilityFromPredictor(pred);
            if (wp != null) out['winProbability'] = wp;
          } catch (_) {/* win prob optional */}
        }(),
    ]);
  }

  // ---- fastcast live push (Track 1 game detail + Track 2 slate overlay) -------
  /// The shared push gate: false on WEB (the FastCast socket is dart:io, and a
  /// browser can't send the Origin/UA headers the upgrade requires — web polls,
  /// full stop), when no push client was injected, when an API base override is
  /// set (mock mode — everything must poll through the mock), when no registry
  /// is loaded yet (widget tests — evaluated synchronously from builds), or
  /// when the league's family isn't fastcast-served (registry capability).
  bool _fastcastReady(String league) {
    if (kIsWeb) return false;
    if (_fastcast == null || baseUrl.trim().isNotEmpty) return false;
    if (!Registry.loaded) return false;
    return hasCapability(resolve(_reg, league), 'fastcast');
  }

  /// Whether a LIVE game's detail in [league] can be push-fed (Track 1). On
  /// top of [_fastcastReady]: the sport's summary must be the normal
  /// normalizeSummary shape — MMA's is built from CORE and tennis has none, so
  /// the gp doc can't feed them.
  bool liveSummarySupported(String league) {
    if (!_fastcastReady(league)) return false;
    final sport = resolve(_reg, league)['espnSport'];
    return sport != 'mma' && sport != 'tennis';
  }

  /// Whether [league]'s TODAY slate can take the push overlay (Track 2). Any
  /// fastcast-served family qualifies — the overlay is sport-generic (status/
  /// score/situation via the same builders as the scoreboard normalizer).
  bool liveSlateSupported(String league) => _fastcastReady(league);

  /// The Track-2 slate overlay stream: subscribe `event-{sport}-{league}` and
  /// normalize each (coalesced, ≤1/s) doc through `normalizeFastcastSlate`.
  /// Emissions are PARTIAL per-event updates to merge over the last polled
  /// slate ([mergeSlate]) — never a scoreboard replacement. Errors mean "push
  /// unavailable, keep polling"; rc:404 (dormant league) ends the stream.
  Stream<Map<String, dynamic>> liveSlate(String league) async* {
    final parts = league.split('/');
    await for (final doc in _fastcast!.docs('event-${parts[0]}-${parts[1]}')) {
      Map<String, dynamic>? ov;
      try {
        ov = fcst.normalizeFastcastSlate(_reg, league, doc);
      } catch (e) {
        FcLog.log('err', 'overlay $league normalize failed: $e — frame skipped');
      }
      if (ov != null) {
        final events = ov['events'] as List;
        final live = events
            .where((e) => ((e as Map)['status'] as Map)['live'] == true)
            .length;
        FcLog.log('overlay', '$league → ${events.length} event(s), $live live');
        yield ov;
      }
    }
  }

  /// The latest push [overlay] merged over the last polled TODAY slate — a
  /// pure in-memory join (no fetch, no re-normalize; see fastcast_merge.dart).
  /// Null when no slate has been polled yet this session (nothing to merge
  /// over) or the merge fails — callers fall back to the polled response.
  ScoresResponse? mergeSlate(String league, Map<String, dynamic> overlay) {
    final norm = _lastNorm[league];
    if (norm == null) {
      FcLog.log('merge', '$league: no polled slate yet — overlay held');
      return null;
    }
    try {
      final t0 = DateTime.now().millisecondsSinceEpoch;
      final merged = ScoresResponse.fromJson(
          mergeFastcastSlate(resolve(_reg, league), norm, overlay));
      FcLog.log('merge',
          '$league overlay merged over polled slate (${DateTime.now().millisecondsSinceEpoch - t0}ms)');
      return merged;
    } catch (e) {
      FcLog.log('err', '$league merge failed: $e — serving polled slate');
      return null;
    }
  }

  /// The push-fed live game detail: subscribe `gp-{sport}-{league}-{eventId}`,
  /// normalize each (throttled, coalesced) doc through the SAME
  /// `normalizeSummary` the polled path uses — the gp checkpoint is verified
  /// shape-identical to site /summary. The live CORE enrichments
  /// ([_enrichLiveDetail]) ride each emission but are rate-limited by the
  /// espn_client cache TTLs, so push doesn't multiply their fetch cost. Stream
  /// errors mean "push unavailable" — the caller's cue to keep polling; data
  /// resumes automatically when the socket recovers.
  Stream<GameSummary> liveSummary(String league, String eventId) async* {
    final parts = league.split('/');
    final topic = 'gp-${parts[0]}-${parts[1]}-$eventId';
    await for (final doc in _fastcast!.docs(topic)) {
      if (doc is! Map) continue;
      try {
        final t0 = DateTime.now().millisecondsSinceEpoch;
        final out = sm.normalizeSummary(_reg, league, doc);
        await _enrichLiveDetail(league, eventId, doc, out);
        FcLog.log('emit',
            '$topic → summary (normalize+enrich ${DateTime.now().millisecondsSinceEpoch - t0}ms)');
        yield GameSummary.fromJson(out);
      } catch (e) {
        // A doc that fails to normalize is skipped; the client's resync path
        // covers real divergence, and the consumer still has its last value.
        FcLog.log('err', '$topic normalizeSummary failed: $e — frame skipped');
      }
    }
  }

  /// The rich per-match tennis resource — ESPN's core competition (the drill-in
  /// the site /summary can't give). `eventId` is the parent tournament event id,
  /// `compId` the match id. Best-effort: a failure (offline mock, live 404)
  /// yields null and the detail keeps its cheap set grid.
  Future<TennisMatchInfo?> tennisMatchInfo(
      String league, String eventId, String compId) async {
    try {
      final c = await _c.coreCompetition(league, eventId, compId) as Map;
      Map? sub(dynamic x) => x is Map ? x : null;
      String? firstNote() {
        final notes = c['notes'];
        if (notes is List) {
          for (final n in notes) {
            final t = sub(n)?['text'];
            if (t is String && t.trim().isNotEmpty) return t.trim();
          }
        }
        return null;
      }

      final info = TennisMatchInfo.fromJson({
        'drawType': sub(c['type'])?['text'],
        'round': sub(c['round'])?['description'],
        'roundAbbr': sub(c['round'])?['abbreviation'],
        'court': sub(c['court'])?['description'],
        'resultLine': firstNote(),
      });
      return info.isEmpty ? null : info;
    } catch (_) {
      return null; // enrichment only
    }
  }

  /// MMA: ESPN's site /summary 404s for every event, so the rich tier is built
  /// from the CORE event — per-bout status refs + judge linescore refs (decisions
  /// only). Mirrors the worker's mmaSummary().
  Future<Map<String, dynamic>> _mmaSummary(String league, String eventId) async {
    final core = await _c.coreEvent(league, eventId) as Map;
    final comps = core['competitions'] is List ? core['competitions'] as List : const [];
    final statuses = <String, dynamic>{};
    await Future.wait(comps.map((c) async {
      final ref = (c as Map)['status'] is Map ? c['status']['\$ref'] : null;
      if (c['id'] == null || ref == null) return;
      try {
        statuses[c['id'].toString()] = await _c.coreRef(ref.toString());
      } catch (_) {/* bout unresolved */}
    }));
    final linescores = <String, dynamic>{};
    final futs = <Future>[];
    for (final c in comps) {
      final st0 = statuses[(c as Map)['id'].toString()];
      final resName = (st0 is Map && st0['result'] is Map)
          ? '${st0['result']['name'] ?? ''}${st0['result']['displayName'] ?? ''}'
          : '';
      if (!RegExp('decision', caseSensitive: false).hasMatch(resName)) continue;
      for (final comp in (c['competitors'] is List ? c['competitors'] as List : const [])) {
        final ref = (comp as Map)['linescores'] is Map ? comp['linescores']['\$ref'] : null;
        if (ref == null) continue;
        futs.add(() async {
          try {
            linescores['${c['id']}/${comp['id']}'] = await _c.coreRef(ref.toString());
          } catch (_) {/* judges optional */}
        }());
      }
    }
    await Future.wait(futs);
    return sm.normalizeMmaSummary(core, statuses, linescores);
  }

  /// Pre-game betting line from the CORE competition-odds list — the lazy
  /// detail-open enrichment when the cheap scoreboard carried no inline odds.
  /// Capability-gated (baseball/basketball/football/soccer) so no wasted fetch on
  /// a sport ESPN never prices; best-effort (null on 404/offline/no line). Cached
  /// in [EspnClient]. Only meaningful for a SCHEDULED event.
  Future<Odds?> competitionOdds(
      String league, String eventId, String compId) async {
    if (!hasCapability(resolve(_reg, league), 'hasOdds')) return null;
    try {
      final raw = await _c.competitionOdds(league, eventId, compId);
      final o = normalizeCompetitionOdds(raw);
      return o == null ? null : Odds.fromJson(o);
    } catch (_) {
      return null; // enrichment only
    }
  }

  // ---- match feed (soccer core plays) -----------------------------------------
  /// The core plays feed is APPEND-ONLY with a fixed page size (oldest first),
  /// so every page except the tail is immutable — cache full pages per
  /// (league,event) for the session and refetch ONLY the tail each poll. The
  /// probe starts at the last-seen tail page, so a steady-state live poll costs
  /// one request (+1 whenever the feed spills onto a new page).
  static const int _mfLimit = 300;
  final Map<String, int> _mfTailPage = {}; // 'league|event' → last-seen pageCount
  final Map<String, List> _mfPages = {}; // 'league|event|page' → immutable items

  /// The soccer touch-by-touch match feed (capability hasMatchFeed) — the
  /// live-pitch view / shot map / momentum source. [homeId]/[awayId] are the
  /// competition's team ids (core plays tag teams by $ref only). Best-effort:
  /// null when the league has no feed / offline / 404.
  Future<MatchFeed?> matchFeed(String league, String eventId, String compId,
      {String? homeId, String? awayId}) async {
    if (!hasCapability(resolve(_reg, league), 'hasMatchFeed')) return null;
    try {
      final ek = '$league|$eventId';
      // A finished match's feed is bounded; keep the page cache from growing
      // across many opened matches (session-scoped, ~90 KB per full page).
      if (_mfPages.length > 40) {
        _mfPages.clear();
        _mfTailPage.clear();
      }
      Future<Map> fetchPage(int page) async =>
          await _c.corePlays(league, eventId, compId, limit: _mfLimit, page: page) as Map;
      int pageCountOf(Map doc) =>
          doc['pageCount'] is num ? (doc['pageCount'] as num).toInt() : 1;

      // Probe the last-known tail; follow the feed if it spilled onto new pages.
      final probedPage = _mfTailPage[ek] ?? 1;
      var tail = await fetchPage(probedPage);
      var pageCount = pageCountOf(tail);
      if (pageCount != probedPage) {
        if (pageCount > probedPage &&
            (tail['items'] as List? ?? const []).length >= _mfLimit) {
          _mfPages['$ek|$probedPage'] = tail['items'] as List; // now immutable
        }
        tail = await fetchPage(pageCount);
        pageCount = pageCountOf(tail);
      }
      _mfTailPage[ek] = pageCount;

      // Assemble: immutable pages 1..N-1 (cache, fetch any missing) + the tail.
      final items = [];
      for (var p = 1; p < pageCount; p++) {
        var pg = _mfPages['$ek|$p'];
        if (pg == null) {
          pg = (await fetchPage(p))['items'] as List? ?? const [];
          if (pg.length >= _mfLimit) _mfPages['$ek|$p'] = pg;
        }
        items.addAll(pg);
      }
      items.addAll(tail['items'] as List? ?? const []);
      final norm = mf.normalizeMatchFeed(
          {'count': tail['count'], 'items': items}, homeId, awayId);
      final feed = MatchFeed.fromJson(norm);
      return feed.plays.isEmpty ? null : feed;
    } catch (_) {
      return null; // enrichment only — the detail renders without the feed
    }
  }

  // ---- venue & circuit facts (§2.9 detail tab) -------------------------------
  /// Stadium facts for the Venue tab — one lazy CORE `venues/{id}` fetch keyed by
  /// the scoreboard `competitions[].venue.id`. On-tab-open only (never the scores
  /// poll); cached a day in [EspnClient]; best-effort (null on 404/offline). The
  /// cheap header (name/city/roof) is already in hand — this adds the photo,
  /// surface, and address the scoreboard doesn't carry.
  Future<VenueFacts?> venueFacts(String league, String venueId) async {
    try {
      final raw = await _c.venue(league, venueId);
      final v = vn.normalizeVenueFacts(raw);
      return v == null ? null : VenueFacts.fromJson(v);
    } catch (_) {
      return null; // facts optional — the tab degrades to the cheap header
    }
  }

  /// F1 circuit facts for the Circuit tab — one lazy CORE `circuits/{id}` fetch
  /// keyed by the scoreboard `events[].circuit.id`, plus ONE cached `$ref`
  /// fan-out to resolve the lap-record driver. On-tab-open only; cached a day;
  /// best-effort. Non-F1 racing has no circuits resource → use [venueFacts]
  /// (length/turns) instead.
  Future<CircuitFacts?> circuitFacts(String league, String circuitId) async {
    try {
      final raw = await _c.circuit(league, circuitId) as Map;
      dynamic driver;
      final ref = (raw['fastestLapDriver'] is Map)
          ? (raw['fastestLapDriver'] as Map)['\$ref']
          : null;
      if (ref is String) {
        try {
          driver = await _c.coreRef(ref);
        } catch (_) {/* driver identity optional */}
      }
      final c = vn.normalizeCircuitFacts(raw, driver);
      return c == null ? null : CircuitFacts.fromJson(c);
    } catch (_) {
      return null; // facts optional
    }
  }

  // ---- athlete / player profile (§2.6 "Player rows") -------------------------
  /// How many game-log rows to resolve, and the in-flight cap for that fan-out.
  static const _athleteGameCap = 5; // most-recent N (keep small — this is on-open)
  static const _athleteGameConc = 6;

  /// A player profile — identity + season stats + a last-N game log. ALL of it is
  /// CORE-tier and lazy (on player-row open), NEVER on the cheap scoreboard poll.
  ///
  /// Identity prefers the ROSTER ROW when [teamId] is known (denser, single-call —
  /// and teamDetail already fetched that roster, so the espn_client cache serves it
  /// free); else the core `athletes/{id}` doc. Team name+color needs a `team.$ref`
  /// resolve either way (the roster row carries no color). Season stats + eventlog
  /// are best-effort — a failure yields a partial (identity-only) profile, not an
  /// error. Every fetch is cached in [EspnClient]; past games are immutable so a
  /// re-open is free. Returns null only when even identity can't be established.
  Future<AthleteProfile?> athleteProfile(String league, String athleteId, {String? teamId}) async {
    Map? identity;
    String? teamRef;
    if (teamId != null) {
      try {
        identity = _rosterRow(await _c.teamRoster(league, teamId), athleteId);
      } catch (_) {/* fall through to the core athlete doc */}
    }
    if (identity == null) {
      try {
        final a = await _c.coreAthlete(league, athleteId);
        if (a is Map) {
          identity = a;
          final ref = a['team'] is Map ? (a['team'] as Map)['\$ref'] : null;
          if (ref is String) teamRef = ref;
        }
      } catch (_) {/* identity best-effort — but the profile needs at least this */}
    }
    if (identity == null) return null;

    // team (name+color+logo): the core athlete's team.$ref, else built from teamId.
    Future<dynamic> teamFut;
    if (teamRef != null) {
      teamFut = _c.coreRef(teamRef, ttl: 86400).then<dynamic>((v) => v).catchError((_) => null);
    } else if (teamId != null) {
      teamFut = _c.coreTeam(league, teamId).then<dynamic>((v) => v).catchError((_) => null);
    } else {
      teamFut = Future.value(null);
    }
    final statsFut =
        _c.coreAthleteStatistics(league, athleteId).then<dynamic>((v) => v).catchError((_) => null);
    final elFut =
        _c.coreAthleteEventLog(league, athleteId).then<dynamic>((v) => v).catchError((_) => null);
    final rest = await Future.wait([teamFut, statsFut, elFut]);

    final games = await _resolveGameLog(rest[2]);
    return AthleteProfile.fromJson(ath.normalizeAthleteProfile(league, athleteId, {
      'identity': identity,
      'team': rest[0],
      'statistics': rest[1],
      'games': games,
    }));
  }

  /// Find one athlete's row in a team roster (grouped OR flat — mirrors teamdetail).
  Map? _rosterRow(dynamic roster, String athleteId) {
    final athletes = (roster is Map) ? roster['athletes'] : null;
    if (athletes is! List) return null;
    final grouped = athletes.any((e) => e is Map && e['items'] is List);
    final rows = grouped
        ? athletes.expand((g) => (g is Map && g['items'] is List) ? (g['items'] as List) : const [])
        : athletes;
    for (final r in rows) {
      if (r is Map && r['id']?.toString() == athleteId) return r;
    }
    return null;
  }

  /// Resolve the last-N game log from a raw eventlog. THE N+1 COST LIVES HERE:
  /// eventlog.items[] can be 25+ rows; we keep only the most-recent [_athleteGameCap]
  /// PLAYED ones and resolve each row's `event.$ref` (trimmed to date/matchup) +
  /// `statistics.$ref` (the per-game line) — up to 2 fetches/row — through a pool of
  /// [_athleteGameConc]. Every resolve is cached in espn_client (immutable past
  /// games → a re-open is free). eventId is lifted from the ref so a row survives a
  /// failed event resolve. Any failure just drops that field/row — never throws.
  Future<List<Map<String, dynamic>>> _resolveGameLog(dynamic eventlog) async {
    final events = (eventlog is Map) ? eventlog['events'] : null;
    final items = (events is Map) ? events['items'] : null;
    if (items is! List || items.isEmpty) return const [];
    // eventlog lists oldest→newest within the page → take the TAIL, reverse to
    // most-recent-first. `played` filters scheduled/DNP stubs.
    final played = items.where((e) => e is Map && e['played'] == true).toList();
    final recent = (played.length > _athleteGameCap
            ? played.sublist(played.length - _athleteGameCap)
            : played)
        .reversed
        .toList();
    final rows = await _pool<dynamic, Map<String, dynamic>>(recent, _athleteGameConc, (it) async {
      final m = it as Map;
      final row = <String, dynamic>{};
      final evRef = m['event'] is Map ? (m['event'] as Map)['\$ref'] : null;
      if (evRef is String) {
        final id = RegExp(r'/events/(\d+)').firstMatch(evRef)?.group(1);
        if (id != null) row['eventId'] = id;
        try {
          row['event'] = await _c.coreRef(evRef, ttl: 3600);
        } catch (_) {/* row keeps its id */}
      }
      if (m['teamId'] != null) row['teamId'] = m['teamId'];
      final stRef = m['statistics'] is Map ? (m['statistics'] as Map)['\$ref'] : null;
      if (stRef is String) {
        try {
          row['statistics'] = await _c.coreRef(stRef, ttl: 3600);
        } catch (_) {/* per-game line optional */}
      }
      return row;
    });
    return rows.where((r) => r['eventId'] != null).toList();
  }

  // ---- standings -------------------------------------------------------------
  /// The canonical column keys that live ONLY on the CORE group standings-id doc
  /// (L10 + division/conference/home/away sub-records), not the site path.
  static const _subRecordKeys = {'l10', 'div', 'conf', 'home', 'away'};

  Future<Standings> standings(String league, {int? season}) async {
    final raw = await _c.standings(league, season: season) as Map;
    final prof = resolve(_reg, league);
    final seasonYear = (raw['season'] is Map ? raw['season']['year'] : null) ?? season;
    // Sub-records (L10/DIV/CONF): only when the league profile asks for a sub-record
    // column — otherwise never spend the fan-out (fetch-budget rule). Best-effort;
    // any failure leaves the site-standings shape untouched.
    Map? records;
    final cols = prof['standingsColumns'];
    final wantsSub = cols is List &&
        cols.any((c) => c is Map && _subRecordKeys.contains(c['key']));
    if (wantsSub) {
      records = await _fetchStandingsRecords(league, raw).catchError((_) => null);
    }
    return Standings.fromJson({
      'league': league,
      'season': seasonYear,
      'columns': prof['standingsColumns'],
      'groups': st.normalizeStandings(raw, records),
    });
  }

  /// Fan out the CORE group standings-id docs behind the site standings and reduce
  /// them to a { teamId: {l10,div,conf,home,away} } map. Discovery is all off the
  /// site standings raw (season year + each group id/seasonType/standingsId); the
  /// fetch is per-group, capped, best-effort. Returns null when nothing resolves.
  Future<Map?> _fetchStandingsRecords(String league, Map raw) async {
    final year = (raw['season'] is Map ? raw['season']['year'] : null);
    final groups = <Map<String, dynamic>>[];
    final seen = <String>{};
    void walk(dynamic node) {
      if (node is Map) {
        final s = node['standings'];
        final entries = s is Map ? s['entries'] : null;
        final gid = node['id'];
        if (s is Map && entries is List && entries.isNotEmpty && gid != null) {
          final key = gid.toString();
          if (seen.add(key)) {
            groups.add({
              'g': key,
              't': s['seasonType'],
              's': (s['id'] ?? '0').toString(),
              'y': s['season'] ?? year,
            });
          }
        }
        final children = node['children'];
        if (children is List) {
          for (final c in children) {
            walk(c);
          }
        }
      }
    }

    walk(raw);
    if (groups.isEmpty) return null;
    // Cap the fan-out (e.g. NFL = 8 divisions); each is best-effort.
    final selected = groups.take(12).toList();
    final docs = await _pool<Map<String, dynamic>, dynamic>(selected, 6, (g) async {
      final y = g['y'], t = g['t'];
      if (y == null || t == null) return null;
      try {
        return await _c.coreGroupStandings(
            league, (y as num).toInt(), (t as num).toInt(),
            g['g'] as String, g['s'] as String);
      } catch (_) {
        return null;
      }
    });
    final map = st.extractGroupRecords(docs.where((d) => d != null).toList());
    return map.isEmpty ? null : map;
  }

  // ---- team season leaders (§2.6 TEAM LEADERS row) ---------------------------
  /// How many leader categories to surface, and the athlete-resolve concurrency.
  static const _leaderCategoryCap = 6;
  static const _leaderConc = 6;

  /// A team's SEASON leaders — the top player per stat category. CORE-tier + lazy
  /// (team-page open), NEVER the cheap scoreboard poll. The season year rides the
  /// team schedule (already fetched by teamDetail → cache hit); season type = 2
  /// (regular season). The category fan-out is capped and each unique athlete.$ref
  /// resolved ONCE (cached). Best-effort: a failure (offseason 404, offline) yields
  /// an empty leaders block, not an error.
  Future<TeamSeasonLeaders> teamLeaders(String league, String teamId) async {
    final empty = TeamSeasonLeaders.fromJson({'league': league, 'teamId': teamId, 'categories': const []});
    int? year;
    try {
      final sched = await _c.teamSchedule(league, teamId);
      year = (sched is Map && sched['season'] is Map)
          ? (sched['season']['year'] as num?)?.toInt()
          : null;
      year ??= (sched is Map && sched['requestedSeason'] is Map)
          ? (sched['requestedSeason']['year'] as num?)?.toInt()
          : null;
    } catch (_) {/* fall back to the calendar year below */}
    year ??= DateTime.now().year;
    dynamic raw;
    try {
      raw = await _c.coreTeamLeaders(league, teamId, year, 2);
    } catch (_) {
      return empty; // no leaders doc (offseason / unsupported)
    }
    // Cap the categories BEFORE resolving athletes (the fan-out budget), then
    // resolve each UNIQUE athlete.$ref once through a small pool.
    final cats = (raw is Map && raw['categories'] is List)
        ? (raw['categories'] as List).take(_leaderCategoryCap).toList()
        : const [];
    final refs = <String, String>{}; // athleteId → ref
    for (final c in cats) {
      final leaders = (c is Map && c['leaders'] is List) ? c['leaders'] as List : const [];
      if (leaders.isEmpty) continue;
      final ref = (leaders.first is Map && (leaders.first as Map)['athlete'] is Map)
          ? (leaders.first as Map)['athlete']['\$ref']
          : null;
      final id = tl.athleteIdFromRef(ref);
      if (id != null && ref is String) refs.putIfAbsent(id, () => ref);
    }
    final entries = refs.entries.toList();
    final resolved = await _pool<MapEntry<String, String>, MapEntry<String, dynamic>>(
        entries, _leaderConc, (e) async {
      try {
        return MapEntry(e.key, await _c.coreRef(e.value, ttl: 1800));
      } catch (_) {
        return MapEntry(e.key, null);
      }
    });
    final athletes = {for (final e in resolved) if (e.value != null) e.key: e.value};
    return TeamSeasonLeaders.fromJson(
        tl.normalizeTeamLeaders(league, teamId, raw, athletes));
  }

  // ---- tournament (§2.7 — groups / draw / bracket / pools+series) -------------
  /// One canonical [TournamentResponse] for a tournament page — a PUSHED-PAGE
  /// fetch, never the scores poll. One (range) scoreboard is the structure
  /// source: [window] is a 'YYYYMMDD[-YYYYMMDD]' override; absent, the profile's
  /// `tournamentWindowDays` hint (soccer.knockout, college-baseball) widens
  /// today to a ±days range that spans the whole competition from any date
  /// inside it — no hint → the plain (today) scoreboard, which for tennis
  /// already carries the ENTIRE draw (verified 2026-07). When the profile says
  /// group tables exist (`tournamentGroups`) the standings ride along
  /// (best-effort). [grouping]/[eventId] select a tennis draw (default: the
  /// major event, first grouping). Both fetches are cached in [EspnClient].
  Future<TournamentResponse> tournament(String league,
      {String? window, String? grouping, String? eventId}) async {
    final prof = resolve(_reg, league);
    var range = window;
    final days = prof['tournamentWindowDays'];
    if (range == null && days is num && days > 0) {
      String ymd(DateTime d) => '${d.year}'
          '${d.month.toString().padLeft(2, '0')}'
          '${d.day.toString().padLeft(2, '0')}';
      final now = DateTime.now();
      final span = Duration(days: days.toInt());
      range = '${ymd(now.subtract(span))}-${ymd(now.add(span))}';
    }
    final sb = await _c.scoreboard(league, date: range, ttl: 120);
    dynamic standingsRaw;
    if (prof['tournamentGroups'] == true) {
      try {
        standingsRaw = await _c.standings(league);
      } catch (_) {/* group tables optional — knockout still renders */}
    }
    return TournamentResponse.fromJson(tn.normalizeTournament(_reg, league, {
      'scoreboards': [sb],
      if (standingsRaw != null) 'standings': standingsRaw,
      if (grouping != null) 'grouping': grouping,
      if (eventId != null) 'eventId': eventId,
    }));
  }

  // ---- rankings --------------------------------------------------------------
  Future<RankingsResponse> rankings(String league) async {
    final raw = await _c.rankings(league);
    return RankingsResponse.fromJson({'league': league, ...rk.normalizeRankings(raw)});
  }

  // ---- scorecard -------------------------------------------------------------
  Future<GolfScorecard> scorecard(String league, String eventId, String playerId, {int? season}) async {
    final s = (season ?? DateTime.now().year).toString();
    final raw = await _c.golfPlayerSummary(league, eventId, s, playerId);
    return GolfScorecard.fromJson(sc.normalizeGolfScorecard(league, eventId, playerId, raw));
  }

  // ---- catalog (computed locally — no fetch) ---------------------------------
  Future<List<CatalogSport>> catalog() async =>
      buildCatalog(_reg).map((s) => CatalogSport.fromJson(s)).toList(growable: false);

  // ---- teams -----------------------------------------------------------------
  Future<List<TeamRef>> teams(String league) async {
    final raw = await _c.teams(league);
    final norm = tm.normalizeTeams(_reg, league, raw);
    IdentityCache.instance.warmTeams(norm); // §3.1 identity warm-up
    return norm.map((t) => TeamRef.fromJson(t)).toList(growable: false);
  }

  // ---- team card -------------------------------------------------------------
  Future<TeamCard> teamCard(String league, String teamId) async {
    final schedule = await _c.teamSchedule(league, teamId);
    var card = tm.normalizeTeamCard(_reg, league, teamId, schedule);
    if (card['live'] == null) {
      try {
        final sb = await _c.scoreboard(league) as Map;
        card = tm.applyScoreboardFallback(_reg, league, teamId, card, sb);
      } catch (_) {/* scoreboard optional — keep schedule-only card */}
    }
    _warmTeamBlock(card['team']);
    return TeamCard.fromJson(card);
  }

  /// Warm the identity cache with a normalized `team` block (teamCard/teamDetail
  /// carry the followed team's id + color + logo/logoDark — §3.1).
  void _warmTeamBlock(dynamic team) {
    if (team is! Map) return;
    IdentityCache.instance.put(
      team['id']?.toString(),
      logo: team['logo']?.toString(),
      logoDark: team['logoDark']?.toString(),
      color: team['color']?.toString(),
      abbreviation: team['abbreviation']?.toString(),
    );
  }

  // ---- team detail -----------------------------------------------------------
  Future<TeamDetail> teamDetail(String league, String teamId) async {
    final schedule = await _c.teamSchedule(league, teamId);
    final rest = await Future.wait([
      _c.teamRoster(league, teamId).then<dynamic>((v) => v).catchError((_) => null),
      _c.teamStatistics(league, teamId).then<dynamic>((v) => v).catchError((_) => null),
      _c.standings(league).then<dynamic>((v) => v).catchError((_) => null),
    ]);
    final data = td.normalizeTeamDetail(_reg, league, teamId, {
      'schedule': schedule,
      'roster': rest[0],
      'stats': rest[1],
      'standingsRaw': rest[2],
    });
    _warmTeamBlock(data['team']);
    // The schedule carries every opponent's competitors (color/logo) — warm them
    // too so this team's standings group can paint each rival's rail (§3.1).
    IdentityCache.instance.warmScoreboard({'events': data['schedule']});
    return TeamDetail.fromJson(data);
  }

  // ---- overview (season-pulse fan-out, capped concurrency) -------------------
  static const _overviewCap = 48;

  /// [onResult] (optional) fires as EACH league classifies — Explore streams the
  /// pulse in incrementally instead of waiting for the slowest of the fan-out.
  Future<Map<String, LeagueStateInfo>> overview(
      {String? priority,
      int? page,
      List<String>? keys,
      void Function(String key, LeagueStateInfo info)? onResult}) async {
    List<String> selected;
    if (keys != null && keys.isNotEmpty) {
      selected = keys.toSet().where((k) => _reg.leagues.containsKey(k)).take(_overviewCap).toList();
    } else {
      final all = leagueKeys(_reg,
          priority: priority?.split(',').map((s) => s.trim()).toList());
      final p = (page ?? 0) < 0 ? 0 : (page ?? 0);
      selected = all.skip(p * _overviewCap).take(_overviewCap).toList();
    }
    final now = DateTime.now();
    final results = await _pool<String, MapEntry<String, LeagueStateInfo>>(selected, 8, (key) async {
      LeagueStateInfo info;
      try {
        final sb = await _c.scoreboard(key, ttl: 60);
        final s = ov.classifyLeague(sb, now);
        info = LeagueStateInfo.fromJson({'key': key, ...s});
      } catch (_) {
        info = LeagueStateInfo(key: key, state: 'unknown', detail: '', live: false);
      }
      onResult?.call(key, info);
      return MapEntry(key, info);
    });
    return {for (final e in results) e.key: e.value};
  }

  /// The Explore pulse's FAST first pass: ONE merged `<sport>/all` scoreboard
  /// per capable sport (capability `hasAllScoreboard` — soccer, rugby,
  /// rugby-league, tennis, golf, mma) classifies every league with a game in
  /// the slate as live/today in a single round-trip, instead of
  /// fetch-completion order across the ~70-league fan-out. Positive states
  /// only — the merged feed carries no per-league season/calendar, so the
  /// per-league [overview] supplies captions (and refinements) behind it.
  /// Best-effort per sport: a failed merged fetch just means that sport waits
  /// for the fan-out.
  Future<void> overviewMergedFirst(
      {String? priority,
      required void Function(String key, LeagueStateInfo info) onResult}) async {
    final all = leagueKeys(_reg,
        priority: priority?.split(',').map((s) => s.trim()).toList());
    // sport → espnLeagueId → league key, capable sports only.
    final bySport = <String, Map<String, String>>{};
    for (final key in all) {
      final prof = resolve(_reg, key);
      if (!hasCapability(prof, 'hasAllScoreboard')) continue;
      final id = prof['espnLeagueId']?.toString() ?? '';
      if (id.isEmpty) continue;
      bySport.putIfAbsent(key.split('/').first, () => {})[id] = key;
    }
    final now = DateTime.now();
    await Future.wait(bySport.entries.map((e) async {
      try {
        final sb = await _c.scoreboard('${e.key}/all', ttl: 60, limit: 400);
        ov.classifyMergedSlate(sb, now).forEach((id, s) {
          final league = e.value[id];
          if (league != null) {
            onResult(league,
                LeagueStateInfo.fromJson({'key': league, ...s as Map}));
          }
        });
      } catch (_) {
        // best-effort — the per-league fan-out covers this sport.
      }
    }));
  }

  // ---- big games (home-feed marquee scan) ------------------------------------
  /// The scan set is the FLAGSHIP tier only (priority v1, ~15 leagues) minus
  /// what's already followed — a deliberately small fetch budget, not the
  /// pulse's ~70-league fan-out. Pool cap stays low so the scan never crowds
  /// the followed feed's own fetches.
  static const _bigGamesConc = 4;

  /// Today's marquee games across the flagship leagues the user does NOT
  /// follow — the home feed's BIG GAMES section (see marquee.dart for the
  /// ranking rules). Cheap-tier scoreboards at ttl 60 (same tier/TTL as the
  /// Explore pulse, so the two share cache entries); per-league best-effort —
  /// a failed league contributes nothing. Returns at most [cap] games, biggest
  /// first; empty on an ordinary day (the section hides).
  Future<List<BigGame>> bigGames(
      {required List<String> exclude, int cap = 3}) async {
    final candidates = leagueKeys(_reg, priority: const ['v1'])
        .where((k) => !exclude.contains(k))
        .toList();
    if (candidates.isEmpty) return const [];
    final now = DateTime.now();
    final lists =
        await _pool<String, List<BigGame>>(candidates, _bigGamesConc, (key) async {
      try {
        final sb = await _c.scoreboard(key, ttl: 60) as Map;
        final norm = normalizeScoreboard(_reg, key, sb, const {});
        IdentityCache.instance.warmScoreboard(norm); // §3.1 — rows need colors
        return pickBigGames(key, ScoresResponse.fromJson(norm), now: now);
      } catch (_) {
        return const <BigGame>[]; // best-effort — a failed league is no news
      }
    });
    return topBigGames(lists.expand((l) => l), cap: cap);
  }

  /// Run [fn] over [items] with at most [n] in flight (order-preserving output).
  Future<List<R>> _pool<T, R>(List<T> items, int n, Future<R> Function(T) fn) async {
    final out = List<R?>.filled(items.length, null);
    var i = 0;
    Future<void> worker() async {
      while (i < items.length) {
        final idx = i++;
        out[idx] = await fn(items[idx]);
      }
    }

    await Future.wait(List.generate(n < items.length ? n : items.length, (_) => worker()));
    return out.cast<R>();
  }
}
