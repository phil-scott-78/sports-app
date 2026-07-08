import 'data/espn_client.dart';
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
import 'data/athlete.dart' as ath;
import 'data/teamleaders.dart' as tl;
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
