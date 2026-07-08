// espn_client.dart — the ONLY module that knows ESPN URLs/hosts. Port of
// worker/src/espn.js. Swap providers here without touching the normalizers or the
// rest of the app. Adds a per-instance response cache + in-flight coalescing so
// overlapping providers (home feed + league page on the same league) share one
// upstream fetch — the cross-client coalescing the worker did, now per-device.
//
// `baseOverride` (from Settings, optional) reroutes every ESPN request to another
// origin — the offline mock (Phase 4). Empty/null → talk to ESPN directly.

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => status == 0 ? message : 'HTTP $status';
}

// ---- ESPN URL templates (verified hosts; see worker/src/espn.js) ------------
const _scoreboard = 'https://site.api.espn.com/apis/site/v2/sports/{p}/scoreboard';
const _summary = 'https://site.api.espn.com/apis/site/v2/sports/{p}/summary?event={id}';
const _standings = 'https://site.api.espn.com/apis/v2/sports/{p}/standings';
const _teams = 'https://site.api.espn.com/apis/site/v2/sports/{p}/teams';
const _teamSchedule = 'https://site.api.espn.com/apis/site/v2/sports/{p}/teams/{id}/schedule';
const _teamRoster = 'https://site.api.espn.com/apis/site/v2/sports/{p}/teams/{id}/roster';
const _teamStats = 'https://site.api.espn.com/apis/site/v2/sports/{p}/teams/{id}/statistics';
const _rankings = 'https://site.api.espn.com/apis/site/v2/sports/{p}/rankings';
const _coreEvent = 'https://sports.core.api.espn.com/v2/sports/{c}/events/{id}';
const _coreCompetition =
    'https://sports.core.api.espn.com/v2/sports/{c}/events/{id}/competitions/{comp}';
const _coreCompetitionOdds =
    'https://sports.core.api.espn.com/v2/sports/{c}/events/{id}/competitions/{comp}/odds';
const _coreSituation =
    'https://sports.core.api.espn.com/v2/sports/{c}/events/{id}/competitions/{comp}/situation';
const _corePredictor =
    'https://sports.core.api.espn.com/v2/sports/{c}/events/{id}/competitions/{comp}/predictor';
const _coreVenue = 'https://sports.core.api.espn.com/v2/sports/{c}/venues/{id}';
const _coreCircuit = 'https://sports.core.api.espn.com/v2/sports/{c}/circuits/{id}';
const _coreTeam = 'https://sports.core.api.espn.com/v2/sports/{c}/teams/{id}';
const _coreTeamLeaders =
    'https://sports.core.api.espn.com/v2/sports/{c}/seasons/{y}/types/{t}/teams/{id}/leaders';
const _coreGroupStandings =
    'https://sports.core.api.espn.com/v2/sports/{c}/seasons/{y}/types/{t}/groups/{g}/standings/{s}';
const _coreAthlete = 'https://sports.core.api.espn.com/v2/sports/{c}/athletes/{id}';
const _coreAthleteStats =
    'https://sports.core.api.espn.com/v2/sports/{c}/athletes/{id}/statistics';
const _coreAthleteEventLog =
    'https://sports.core.api.espn.com/v2/sports/{c}/athletes/{id}/eventlog';
const _golfPlayerSummary =
    'https://site.web.api.espn.com/apis/site/v2/sports/{p}/leaderboard/{event}/playersummary?season={season}&player={player}';

class _CacheEntry {
  final dynamic json;
  final int expiresMs;
  _CacheEntry(this.json, this.expiresMs);
}

class EspnClient {
  /// Optional origin override (the offline mock). Empty → ESPN direct.
  final String baseOverride;
  EspnClient([this.baseOverride = '']);

  // One reused client → connection pooling/keep-alive (a fresh client per request
  // means a new TLS handshake every call and leaked sockets).
  final http.Client _http = http.Client();
  final Map<String, _CacheEntry> _cache = {};
  final Map<String, Future<dynamic>> _inflight = {};

  void dispose() => _http.close();

  int get _now => DateTime.now().millisecondsSinceEpoch;

  /// Reroute an ESPN URL to the override origin (path + query preserved so the
  /// mock can disambiguate by path). No override → the URL as-is.
  String _route(String url) {
    if (baseOverride.trim().isEmpty) return url;
    final u = Uri.parse(url);
    final b = baseOverride.trim().replaceAll(RegExp(r'/+$'), '');
    return '$b${u.path}${u.hasQuery ? '?${u.query}' : ''}';
  }

  /// GET + decode, with a [ttl]-second reuse window and in-flight coalescing.
  Future<dynamic> _get(String url, {int ttl = 10}) {
    final hit = _cache[url];
    if (hit != null && hit.expiresMs > _now) return Future.value(hit.json);
    final pending = _inflight[url];
    if (pending != null) return pending;
    final fut = _fetch(url).then((json) {
      _cache[url] = _CacheEntry(json, _now + ttl * 1000);
      return json;
    // NOTE the block body: `Map.remove` returns the removed value (this very
    // future), and whenComplete AWAITS a returned Future — an expression body
    // would deadlock the future on itself. Keep this returning void.
    }).whenComplete(() {
      _inflight.remove(url);
    });
    _inflight[url] = fut;
    return fut;
  }

  Future<dynamic> _fetch(String url) async {
    http.Response r;
    try {
      r = await _http.get(Uri.parse(_route(url))).timeout(AppConfig.httpTimeout);
    } catch (_) {
      throw ApiException(0, 'Network error — check your connection.');
    }
    if (r.statusCode != 200) throw ApiException(r.statusCode, 'upstream ${r.statusCode}');
    try {
      return jsonDecode(r.body);
    } catch (_) {
      throw ApiException(0, 'Unexpected response from the server.');
    }
  }

  static String _q(Map<String, String> qs) => qs.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
  static String _corePath(String key) => key.replaceFirst('/', '/leagues/');

  Future<dynamic> scoreboard(String key, {String? date, int ttl = 15}) {
    var url = _scoreboard.replaceFirst('{p}', key);
    final qs = <String, String>{};
    if (date != null) qs['dates'] = date;
    if (key.contains('college')) {
      qs['limit'] = '400';
      if (key.contains('basketball')) qs['groups'] = '50';
      if (key.contains('football')) qs['groups'] = '80';
    }
    if (qs.isNotEmpty) url += '?${_q(qs)}';
    return _get(url, ttl: ttl);
  }

  Future<dynamic> summary(String key, String eventId, {int ttl = 20}) =>
      _get(_summary.replaceFirst('{p}', key).replaceFirst('{id}', eventId), ttl: ttl);

  Future<dynamic> standings(String key, {int? season, int ttl = 1800}) {
    final base = _standings.replaceFirst('{p}', key);
    return _get(season != null ? '$base?season=$season' : base, ttl: ttl);
  }

  Future<dynamic> coreRef(String ref, {int ttl = 30}) =>
      _get(ref.replaceAll('espn.pvt', 'espn.com').replaceFirst(RegExp(r'^http:'), 'https:'), ttl: ttl);

  Future<dynamic> coreEvent(String key, String eventId, {int ttl = 30}) =>
      _get(_coreEvent.replaceFirst('{c}', _corePath(key)).replaceFirst('{id}', eventId), ttl: ttl);

  /// One match's rich core resource (tennis drill-in): round + court + draw type
  /// + the result note, keyed by the parent event id and the competition id.
  Future<dynamic> coreCompetition(String key, String eventId, String compId,
          {int ttl = 60}) =>
      _get(
          _coreCompetition
              .replaceFirst('{c}', _corePath(key))
              .replaceFirst('{id}', eventId)
              .replaceFirst('{comp}', compId),
          ttl: ttl);

  /// The core competition-odds list (`.../competitions/{id}/odds`) — the pre-game
  /// betting line (per-team moneyline) fetched lazily on detail open when the
  /// inline scoreboard line is absent. Cached 5 min: a line barely moves and the
  /// screen only wants a glance.
  Future<dynamic> competitionOdds(String key, String eventId, String compId,
          {int ttl = 300}) =>
      _get(
          _coreCompetitionOdds
              .replaceFirst('{c}', _corePath(key))
              .replaceFirst('{id}', eventId)
              .replaceFirst('{comp}', compId),
          ttl: ttl);

  /// The CORE live situation (`.../competitions/{id}/situation`) — the live
  /// gridiron down/distance, basketball bonus/timeouts, hockey power play the cheap
  /// scoreboard + /summary don't carry. Fetched on detail open only, piggybacking the
  /// summary poll (NOT the scores poll). Short TTL: live state moves every play.
  Future<dynamic> coreSituation(String key, String eventId, String compId,
          {int ttl = 12}) =>
      _get(
          _coreSituation
              .replaceFirst('{c}', _corePath(key))
              .replaceFirst('{id}', eventId)
              .replaceFirst('{comp}', compId),
          ttl: ttl);

  /// The CORE predictor (`.../competitions/{id}/predictor`) — per-side
  /// `gameProjection` win %. The win-probability fallback when /summary carries no
  /// winprobability[] but the league hasWinProb. Detail-open, summary-poll cadence.
  Future<dynamic> corePredictor(String key, String eventId, String compId,
          {int ttl = 20}) =>
      _get(
          _corePredictor
              .replaceFirst('{c}', _corePath(key))
              .replaceFirst('{id}', eventId)
              .replaceFirst('{comp}', compId),
          ttl: ttl);

  /// A stadium's CORE venue resource (`.../venues/{id}`) — the photo + surface/roof
  /// + address for the §2.9 Venue tab. Keyed by the scoreboard `venue.id`. Fetched
  /// once on tab open; cached a day — venue facts barely change.
  Future<dynamic> venue(String key, String venueId, {int ttl = 86400}) =>
      _get(_coreVenue.replaceFirst('{c}', _corePath(key)).replaceFirst('{id}', venueId), ttl: ttl);

  /// An F1 circuit's CORE resource (`.../circuits/{id}`) — the dark track map +
  /// every circuit fact + lap record for the §2.9 Circuit tab. Keyed by the
  /// scoreboard `events[].circuit.id`. Fetched once on tab open; cached a day.
  Future<dynamic> circuit(String key, String circuitId, {int ttl = 86400}) =>
      _get(_coreCircuit.replaceFirst('{c}', _corePath(key)).replaceFirst('{id}', circuitId), ttl: ttl);

  /// A team's CORE resource by id (`.../teams/{id}`) — name/color/logos. Used by
  /// the athlete profile's roster-row path, where the identity row carries no team
  /// color (only the core athlete doc's `team.$ref` does). Cached a day.
  Future<dynamic> coreTeam(String key, String teamId, {int ttl = 86400}) =>
      _get(_coreTeam.replaceFirst('{c}', _corePath(key)).replaceFirst('{id}', teamId), ttl: ttl);

  /// A team's CORE SEASON leaders (`.../seasons/{y}/types/{t}/teams/{id}/leaders`)
  /// — categories[] each with an athlete.$ref the caller resolves. The season
  /// version of the TEAM LEADERS row; fetched once on team-page open. Cached 30 min
  /// (a season leaderboard moves once a game).
  Future<dynamic> coreTeamLeaders(String key, String teamId, int year, int type,
          {int ttl = 1800}) =>
      _get(
          _coreTeamLeaders
              .replaceFirst('{c}', _corePath(key))
              .replaceFirst('{y}', '$year')
              .replaceFirst('{t}', '$type')
              .replaceFirst('{id}', teamId),
          ttl: ttl);

  /// One group's CORE standings-id doc (`.../groups/{g}/standings/{s}`) — the
  /// standings[].records[] (L10 / vs-div / vs-conf sub-records) the site standings
  /// path lacks. Fetched lazily on standings-open, ONLY for leagues whose profile
  /// asks for the sub-record columns (fetch-budget rule). Cached 30 min.
  Future<dynamic> coreGroupStandings(
          String key, int year, int type, String groupId, String standingsId,
          {int ttl = 1800}) =>
      _get(
          _coreGroupStandings
              .replaceFirst('{c}', _corePath(key))
              .replaceFirst('{y}', '$year')
              .replaceFirst('{t}', '$type')
              .replaceFirst('{g}', groupId)
              .replaceFirst('{s}', standingsId),
          ttl: ttl);

  /// The CORE athlete doc (`.../athletes/{id}`) — identity + `team.$ref`. The
  /// fallback identity source when no roster row is in hand. Cached 30 min: bio
  /// fields barely change.
  Future<dynamic> coreAthlete(String key, String athleteId, {int ttl = 1800}) =>
      _get(_coreAthlete.replaceFirst('{c}', _corePath(key)).replaceFirst('{id}', athleteId), ttl: ttl);

  /// The athlete's season stats (`.../athletes/{id}/statistics`) —
  /// splits.categories[].stats[]. Cached 30 min (a season total moves once a game).
  Future<dynamic> coreAthleteStatistics(String key, String athleteId, {int ttl = 1800}) =>
      _get(_coreAthleteStats.replaceFirst('{c}', _corePath(key)).replaceFirst('{id}', athleteId), ttl: ttl);

  /// The athlete's game log (`.../athletes/{id}/eventlog`) — events.items[] of
  /// {event.$ref, statistics.$ref, teamId}. The rows are then a $ref fan-out
  /// (resolved in api.dart, capped + cached). Cached 5 min.
  Future<dynamic> coreAthleteEventLog(String key, String athleteId, {int ttl = 300}) =>
      _get(_coreAthleteEventLog.replaceFirst('{c}', _corePath(key)).replaceFirst('{id}', athleteId), ttl: ttl);

  Future<dynamic> golfPlayerSummary(String key, String eventId, String season, String playerId, {int ttl = 60}) =>
      _get(_golfPlayerSummary
          .replaceFirst('{p}', key)
          .replaceFirst('{event}', eventId)
          .replaceFirst('{season}', season)
          .replaceFirst('{player}', playerId), ttl: ttl);

  Future<dynamic> teams(String key, {int ttl = 86400}) {
    var url = _teams.replaceFirst('{p}', key);
    final qs = <String, String>{};
    if (key.contains('college')) {
      qs['limit'] = '900';
      if (key.contains('basketball')) qs['groups'] = '50';
      if (key.contains('football')) qs['groups'] = '80';
    } else {
      qs['limit'] = '100';
    }
    url += '?${_q(qs)}';
    return _get(url, ttl: ttl);
  }

  Future<dynamic> teamSchedule(String key, String teamId, {int ttl = 300}) =>
      _get(_teamSchedule.replaceFirst('{p}', key).replaceFirst('{id}', teamId), ttl: ttl);

  Future<dynamic> teamRoster(String key, String teamId, {int ttl = 1800}) =>
      _get(_teamRoster.replaceFirst('{p}', key).replaceFirst('{id}', teamId), ttl: ttl);

  Future<dynamic> teamStatistics(String key, String teamId, {int ttl = 1800}) =>
      _get(_teamStats.replaceFirst('{p}', key).replaceFirst('{id}', teamId), ttl: ttl);

  Future<dynamic> rankings(String key, {int ttl = 3600}) =>
      _get(_rankings.replaceFirst('{p}', key), ttl: ttl);
}
