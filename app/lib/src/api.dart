import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'models.dart';
import 'version.dart';

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => status == 0 ? message : 'HTTP $status';
}

/// Talks to the Cloudflare worker. The only place the app does networking.
///
/// Parsing stays on the main isolate on purpose: payloads are small (a league
/// scoreboard ≈45 KB / ~0.5 ms to parse, a summary ≈10 KB) so the worker has
/// already done the heavy normalization. `compute()` here would cost more in
/// isolate-spawn + result-copy than it saves. (The real main-thread cost was
/// image decoding — see Crest.)
class Api {
  /// The contract major-version prefix. `/v1` is a contract NAME, not a build
  /// number — it absorbs additive change (new fields/enums/sports/routes) forever
  /// because the parser is tolerant. Centralized here so cutting over to a future
  /// `/v2` (only ever on a breaking reshape) is a one-line change; every method
  /// below passes a version-less path. See schema/SCHEMA.md §11.
  static const String apiPrefix = '/v1';

  final String baseUrl;
  Api(this.baseUrl);

  bool get configured => baseUrl.trim().isNotEmpty;

  Uri _uri(String path, [Map<String, String>? q]) {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base$apiPrefix$path')
        .replace(queryParameters: (q != null && q.isNotEmpty) ? q : null);
  }

  Future<dynamic> _get(String path, [Map<String, String>? q]) async {
    if (!configured) throw ApiException(0, 'Set your worker URL in Settings.');
    http.Response r;
    try {
      // Tell the worker which build is calling — pure telemetry (logged, never a
      // cache-key dimension or a routing input). Lets us watch the real version
      // spread in `wrangler tail` before raising the update gate.
      r = await http.get(_uri(path, q), headers: {
        'x-scores-client': '$kClientVersionCode $kClientVersionName',
      }).timeout(AppConfig.httpTimeout);
    } catch (e) {
      throw ApiException(
          0, 'Network error — check the worker URL and your connection.');
    }
    if (r.statusCode != 200) throw ApiException(r.statusCode, r.body);
    // Decode inside the boundary: a 200 with a non-JSON body (a CDN/edge HTML
    // error page, an empty/truncated payload) would otherwise throw a raw
    // FormatException straight into the UI instead of a friendly message.
    try {
      return jsonDecode(r.body);
    } catch (_) {
      throw ApiException(0, 'Unexpected response from the server.');
    }
  }

  /// Worker liveness + the advisory client-version gate (see [HealthInfo]).
  /// Fetched once on launch to drive the update banner. A worker that omits the
  /// `client` block (an old build, a fork, or the offline mock) yields a null
  /// gate → no banner shown (fail-open).
  Future<HealthInfo> health() async {
    final j = await _get('/health');
    return HealthInfo.fromJson(Map<String, dynamic>.from(j as Map));
  }

  Future<ScoresResponse> scores(String league, {String? date}) async {
    final j = await _get('/scores/$league', {if (date != null) 'date': date});
    return ScoresResponse.fromJson(Map<String, dynamic>.from(j as Map));
  }

  Future<GameSummary> summary(String league, String eventId) async {
    final j = await _get('/summary/$league/$eventId');
    return GameSummary.fromJson(Map<String, dynamic>.from(j as Map));
  }

  Future<Standings> standings(String league, {int? season}) async {
    final j = await _get(
        '/standings/$league', {if (season != null) 'season': '$season'});
    return Standings.fromJson(Map<String, dynamic>.from(j as Map));
  }

  /// Rankings feed: college Top-25 polls (AP/Coaches/CFP), ATP/WTA world
  /// rankings, or UFC divisions — whatever the league's catalog `rankings` flag
  /// says it has. Empty `polls` when none (offseason / plain pro league).
  Future<RankingsResponse> rankings(String league) async {
    final j = await _get('/rankings/$league');
    return RankingsResponse.fromJson(Map<String, dynamic>.from(j as Map));
  }

  /// Golf hole-by-hole scorecard for one leaderboard row. [season] should be the
  /// scores payload's season year (golf seasons are calendar-aligned, so the
  /// worker's current-year fallback is safe when omitted).
  Future<GolfScorecard> scorecard(
      String league, String eventId, String playerId,
      {int? season}) async {
    final j = await _get('/scorecard/$league/$eventId/$playerId',
        {if (season != null) 'season': '$season'});
    return GolfScorecard.fromJson(Map<String, dynamic>.from(j as Map));
  }

  Future<List<CatalogSport>> catalog() async {
    final j = await _get('/catalog') as List<dynamic>;
    return j
        .map((s) => CatalogSport.fromJson(Map<String, dynamic>.from(s as Map)))
        .toList(growable: false);
  }

  /// Every team in a league — the favorites picker source.
  Future<List<TeamRef>> teams(String league) async {
    final j = Map<String, dynamic>.from(await _get('/teams/$league') as Map);
    return (j['teams'] as List? ?? const [])
        .map((t) => TeamRef.fromJson(Map<String, dynamic>.from(t as Map)))
        .toList(growable: false);
  }

  /// One favorite team's card: live game if any, else last result + next game.
  Future<TeamCard> teamCard(String league, String teamId) async {
    final j = await _get('/team/$league/$teamId');
    return TeamCard.fromJson(Map<String, dynamic>.from(j as Map));
  }

  /// One team's rich detail page: full-season schedule + roster + season stats +
  /// standings group. Lazy (fetched when the team page opens).
  Future<TeamDetail> teamDetail(String league, String teamId) async {
    final j = await _get('/teamdetail/$league/$teamId');
    return TeamDetail.fromJson(Map<String, dynamic>.from(j as Map));
  }

  /// Per-league season-pulse states, keyed by league key, for the Leagues list.
  /// Selects WHICH leagues three ways (the tiered Leagues view):
  /// - [priority]: a tier set, e.g. 'v1' or 'v1,v2' (the curated Default/Active tiers)
  /// - [page]: slice of that set (the worker caps each request at ~48 leagues)
  /// - [keys]: an explicit league-key set (pinned/followed leagues); overrides priority
  /// Stable params → the worker shares one cached fan-out across all clients.
  Future<Map<String, LeagueStateInfo>> overview(
      {String? priority, int? page, List<String>? keys}) async {
    final q = <String, String>{
      if (priority != null) 'priority': priority,
      if (page != null) 'page': '$page',
      if (keys != null && keys.isNotEmpty) 'keys': keys.join(','),
    };
    final j = Map<String, dynamic>.from(await _get('/overview', q) as Map);
    final out = <String, LeagueStateInfo>{};
    for (final e in (j['leagues'] as List? ?? const [])) {
      final info =
          LeagueStateInfo.fromJson(Map<String, dynamic>.from(e as Map));
      out[info.key] = info;
    }
    return out;
  }
}
