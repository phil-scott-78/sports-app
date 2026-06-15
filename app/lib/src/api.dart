import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'models.dart';

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
  final String baseUrl;
  Api(this.baseUrl);

  bool get configured => baseUrl.trim().isNotEmpty;

  Uri _uri(String path, [Map<String, String>? q]) {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base$path')
        .replace(queryParameters: (q != null && q.isNotEmpty) ? q : null);
  }

  Future<dynamic> _get(String path, [Map<String, String>? q]) async {
    if (!configured) throw ApiException(0, 'Set your worker URL in Settings.');
    http.Response r;
    try {
      r = await http.get(_uri(path, q)).timeout(AppConfig.httpTimeout);
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

  Future<ScoresResponse> scores(String league, {String? date}) async {
    final j =
        await _get('/v1/scores/$league', {if (date != null) 'date': date});
    return ScoresResponse.fromJson(Map<String, dynamic>.from(j as Map));
  }

  Future<GameSummary> summary(String league, String eventId) async {
    final j = await _get('/v1/summary/$league/$eventId');
    return GameSummary.fromJson(Map<String, dynamic>.from(j as Map));
  }

  Future<Standings> standings(String league, {int? season}) async {
    final j = await _get(
        '/v1/standings/$league', {if (season != null) 'season': '$season'});
    return Standings.fromJson(Map<String, dynamic>.from(j as Map));
  }

  Future<List<CatalogSport>> catalog() async {
    final j = await _get('/v1/catalog') as List<dynamic>;
    return j
        .map((s) => CatalogSport.fromJson(Map<String, dynamic>.from(s as Map)))
        .toList(growable: false);
  }

  /// Every team in a league — the favorites picker source.
  Future<List<TeamRef>> teams(String league) async {
    final j = Map<String, dynamic>.from(await _get('/v1/teams/$league') as Map);
    return (j['teams'] as List? ?? const [])
        .map((t) => TeamRef.fromJson(Map<String, dynamic>.from(t as Map)))
        .toList(growable: false);
  }

  /// One favorite team's card: live game if any, else last result + next game.
  Future<TeamCard> teamCard(String league, String teamId) async {
    final j = await _get('/v1/team/$league/$teamId');
    return TeamCard.fromJson(Map<String, dynamic>.from(j as Map));
  }

  /// Per-league season-pulse states, keyed by league key, for the Leagues list.
  Future<Map<String, LeagueStateInfo>> overview() async {
    final j = Map<String, dynamic>.from(await _get('/v1/overview') as Map);
    final out = <String, LeagueStateInfo>{};
    for (final e in (j['leagues'] as List? ?? const [])) {
      final info =
          LeagueStateInfo.fromJson(Map<String, dynamic>.from(e as Map));
      out[info.key] = info;
    }
    return out;
  }
}
