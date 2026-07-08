import 'data/espn_client.dart';
import 'data/profiles.dart';
import 'data/normalize.dart';
import 'data/summary.dart' as sm;
import 'data/standings.dart' as st;
import 'data/rankings.dart' as rk;
import 'data/scorecard.dart' as sc;
import 'data/team.dart' as tm;
import 'data/teamdetail.dart' as td;
import 'data/overview.dart' as ov;
import 'models.dart';

export 'data/espn_client.dart' show ApiException;

/// The app's data layer. Formerly a thin HTTP client to the Cloudflare worker;
/// now it talks to ESPN directly (via [EspnClient]) and runs the SAME canonical
/// normalizers the worker used to run — ported to Dart under lib/src/data/. The
/// method surface is unchanged, so providers/UI didn't move.
///
/// Parsing + normalization stay on the main isolate on purpose: payloads are
/// small (a league scoreboard ≈45 KB) and the normalizers are pure map work.
class Api {
  /// Optional ESPN-origin override (Settings) — points at the offline mock. Empty
  /// → ESPN direct. (Was the worker base URL; repurposed as the mock override.)
  final String baseUrl;
  final EspnClient _c;

  Api(this.baseUrl) : _c = EspnClient(baseUrl);

  /// Direct-to-ESPN needs no configuration, so the app is always "configured".
  bool get configured => true;

  Registry get _reg => Registry.instance;

  // ---- health ----------------------------------------------------------------
  /// No worker to ping and no server-driven version gate when going direct, so
  /// this returns a healthy stub with a null client gate (→ no update banner).
  Future<HealthInfo> health() async =>
      HealthInfo(ok: true, leagues: _reg.leagues.length, client: null);

  // ---- scores ----------------------------------------------------------------
  Future<ScoresResponse> scores(String league, {String? date}) async {
    final sb = await _c.scoreboard(league, date: date) as Map;
    final extras = await _golfExtras(league, sb);
    return ScoresResponse.fromJson(normalizeScoreboard(_reg, league, sb, extras));
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
    return GameSummary.fromJson(sm.normalizeSummary(_reg, league, raw));
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

  // ---- standings -------------------------------------------------------------
  Future<Standings> standings(String league, {int? season}) async {
    final raw = await _c.standings(league, season: season) as Map;
    final prof = resolve(_reg, league);
    final seasonYear = (raw['season'] is Map ? raw['season']['year'] : null) ?? season;
    return Standings.fromJson({
      'league': league,
      'season': seasonYear,
      'columns': prof['standingsColumns'],
      'groups': st.normalizeStandings(raw),
    });
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
    return tm.normalizeTeams(_reg, league, raw)
        .map((t) => TeamRef.fromJson(t))
        .toList(growable: false);
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
    return TeamCard.fromJson(card);
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
    return TeamDetail.fromJson(data);
  }

  // ---- overview (season-pulse fan-out, capped concurrency) -------------------
  static const _overviewCap = 48;

  Future<Map<String, LeagueStateInfo>> overview({String? priority, int? page, List<String>? keys}) async {
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
      try {
        final sb = await _c.scoreboard(key, ttl: 60);
        final s = ov.classifyLeague(sb, now);
        return MapEntry(key, LeagueStateInfo.fromJson({'key': key, ...s}));
      } catch (_) {
        return MapEntry(key, LeagueStateInfo(key: key, state: 'unknown', detail: '', live: false));
      }
    });
    return {for (final e in results) e.key: e.value};
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
