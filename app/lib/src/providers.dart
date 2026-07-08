import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'config.dart';
import 'models.dart';

/// Overridden in main() with the loaded instance.
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
      'sharedPrefsProvider must be overridden in main()'),
);

// ---- settings ---------------------------------------------------------------
/// v2 is dark-only by design, so settings is just the worker base URL.
class Settings {
  final String baseUrl;
  const Settings({required this.baseUrl});
  Settings copyWith({String? baseUrl}) =>
      Settings(baseUrl: baseUrl ?? this.baseUrl);
}

class SettingsNotifier extends Notifier<Settings> {
  @override
  Settings build() {
    final p = ref.read(sharedPrefsProvider);
    return Settings(baseUrl: p.getString('baseUrl') ?? AppConfig.defaultBaseUrl);
  }

  void setBaseUrl(String url) {
    final v = url.trim();
    ref.read(sharedPrefsProvider).setString('baseUrl', v);
    state = state.copyWith(baseUrl: v);
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, Settings>(SettingsNotifier.new);

/// Active bottom-nav tab (0=Scores, 1=Standings, 2=Following). Lets the Scores
/// tab pause its poll timer while the user is elsewhere (IndexedStack keeps it
/// mounted).
final tabIndexProvider = StateProvider<int>((ref) => 0);

/// The day the Scores home feed is showing, as ESPN's 'YYYYMMDD', or **null =
/// today**. Kept null for "today" on purpose: the request URL stays
/// parameterless so every client shares the worker's hot cache. Set by the
/// date-strip; the feed watches it and the poll pauses when it's non-null (a
/// past/future slate is static).
final homeDateProvider = StateProvider<String?>((ref) => null);

// ---- followed leagues -------------------------------------------------------
class FollowedNotifier extends Notifier<List<String>> {
  @override
  List<String> build() {
    final p = ref.read(sharedPrefsProvider);
    return p.getStringList('followed') ?? List.of(AppConfig.defaultFollowed);
  }

  void _save() =>
      ref.read(sharedPrefsProvider).setStringList('followed', state);

  bool isFollowed(String key) => state.contains(key);

  void toggle(String key) {
    state = state.contains(key)
        ? (List.of(state)..remove(key))
        : (List.of(state)..add(key));
    _save();
  }

  void remove(String key) {
    if (!state.contains(key)) return;
    state = List.of(state)..remove(key);
    _save();
  }

  /// Reorder the followed list (drives the feed section order). [newIndex] is
  /// the post-removal target, matching ReorderableListView's onReorder.
  void reorder(int oldIndex, int newIndex) {
    final list = List.of(state);
    list.insert(newIndex, list.removeAt(oldIndex));
    state = list;
    _save();
  }
}

final followedProvider =
    NotifierProvider<FollowedNotifier, List<String>>(FollowedNotifier.new);

// ---- favorite teams ---------------------------------------------------------
/// User's favorite teams, persisted as one JSON entry per shared_preferences
/// string-list slot (key 'favoriteTeams'). Order is the home-feed hero-card
/// order (drag to reorder in Following).
class FavoriteTeamsNotifier extends Notifier<List<FavoriteTeam>> {
  static const _key = 'favoriteTeams';

  @override
  List<FavoriteTeam> build() {
    final raw = ref.read(sharedPrefsProvider).getStringList(_key) ?? const [];
    final out = <FavoriteTeam>[];
    for (final s in raw) {
      try {
        out.add(FavoriteTeam.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {
        // skip a corrupt entry rather than failing the whole list
      }
    }
    return out;
  }

  void _save() => ref
      .read(sharedPrefsProvider)
      .setStringList(_key, state.map((f) => jsonEncode(f.toJson())).toList());

  bool contains(String league, String teamId) =>
      state.any((f) => f.league == league && f.teamId == teamId);

  void add(FavoriteTeam f) {
    if (contains(f.league, f.teamId)) return; // dedupe by (league, teamId)
    state = [...state, f];
    _save();
  }

  void remove(String league, String teamId) {
    state = state
        .where((f) => !(f.league == league && f.teamId == teamId))
        .toList();
    _save();
  }

  void toggle(FavoriteTeam f) =>
      contains(f.league, f.teamId) ? remove(f.league, f.teamId) : add(f);

  void reorder(int oldIndex, int newIndex) {
    final list = List.of(state);
    list.insert(newIndex, list.removeAt(oldIndex));
    state = list;
    _save();
  }
}

final favoriteTeamsProvider =
    NotifierProvider<FavoriteTeamsNotifier, List<FavoriteTeam>>(
        FavoriteTeamsNotifier.new);

// ---- api + data -------------------------------------------------------------
final apiProvider = Provider<Api>(
    (ref) => Api(ref.watch(settingsProvider.select((s) => s.baseUrl))));

/// The home feed: every followed league's today slate, fetched in parallel. A
/// failed league becomes a LeagueFeed.error instead of failing the whole feed.
final feedProvider = FutureProvider<List<LeagueFeed>>((ref) async {
  final api = ref.watch(apiProvider);
  final leagues = ref.watch(followedProvider);
  // null = today (parameterless URL → shared hot cache); a picked day passes date.
  final date = ref.watch(homeDateProvider);
  return Future.wait(leagues.map((key) async {
    try {
      return LeagueFeed(key, await api.scores(key, date: date));
    } catch (e) {
      return LeagueFeed(key, null, error: e.toString());
    }
  }));
});

final catalogProvider = FutureProvider<List<CatalogSport>>(
    (ref) => ref.watch(apiProvider).catalog());

/// Every team in a league, for the favorites picker. autoDispose: only needed
/// while the picker is open.
final teamsProvider = FutureProvider.autoDispose.family<List<TeamRef>, String>(
  (ref, league) => ref.watch(apiProvider).teams(league),
);

/// Identity key for the team-scoped providers below (team ids repeat across
/// leagues, so always scope by both).
typedef TeamKey = ({String league, String teamId});

/// One team's live/last/next card — used on the team page's live strip. (The
/// home Favorites section reaches teamCard through [favoritesFeedProvider]; this
/// exposes it directly for a team page whose team may not be a favorite.)
/// autoDispose: alive only while the page is open; polled 15s when live.
final teamCardProvider =
    FutureProvider.autoDispose.family<TeamCard, TeamKey>(
  (ref, k) => ref.watch(apiProvider).teamCard(k.league, k.teamId),
);

/// One team's rich detail (schedule/roster/stats/standing). Lazy + autoDispose:
/// only alive while the team page is open; the worker caches it 30m.
final teamDetailProvider =
    FutureProvider.autoDispose.family<TeamDetail, TeamKey>(
  (ref, k) => ref.watch(apiProvider).teamDetail(k.league, k.teamId),
);

/// The stacked hero cards: every favorite's live/last/next card, in parallel.
/// A failed team degrades to an error card, never breaks the stack.
final favoritesFeedProvider =
    FutureProvider<List<FavoriteTeamFeed>>((ref) async {
  final api = ref.watch(apiProvider);
  final favs = ref.watch(favoriteTeamsProvider);
  return Future.wait(favs.map((f) async {
    try {
      return FavoriteTeamFeed(f, await api.teamCard(f.league, f.teamId));
    } catch (e) {
      return FavoriteTeamFeed(f, null, error: e.toString());
    }
  }));
});

/// Season pulse for the curated league set — powers the Explore browser's
/// LIVE NOW / ON TODAY sections and the per-league captions. Two coalesced
/// worker pages (v1+v2 tiers) merged; a pulse failure degrades to an empty
/// map so the catalog list still renders.
final exploreOverviewProvider =
    FutureProvider<Map<String, LeagueStateInfo>>((ref) async {
  final api = ref.watch(apiProvider);
  try {
    final pages = await Future.wait([
      api.overview(priority: 'v1,v2', page: 0),
      api.overview(priority: 'v1,v2', page: 1),
    ]);
    return {for (final m in pages) ...m};
  } catch (_) {
    return const {};
  }
});

/// One league's slate for a specific day (null date = today), independent of the
/// followed feed — the detail page polls this so a game opened from a favorite
/// card (league not followed) still refreshes, and a game opened from a past/
/// future day re-resolves from that day's slate. Keyed by (league, date) so
/// today's parameterless fetch shares the hot cache while a dated fetch caches
/// separately. autoDispose: alive only while a detail/league page is open.
typedef ScoresKey = ({String league, String? date});

final leagueScoresProvider =
    FutureProvider.autoDispose.family<ScoresResponse, ScoresKey>(
  (ref, k) => ref.watch(apiProvider).scores(k.league, date: k.date),
);

final standingsProvider = FutureProvider.autoDispose.family<Standings, String>(
  (ref, league) => ref.watch(apiProvider).standings(league),
);

/// Rich game-detail summary, fetched lazily when a detail opens. autoDispose:
/// the detail page re-fetches on mount, so dropping it on pop is lossless.
typedef SummaryKey = ({String league, String eventId});

final summaryProvider =
    FutureProvider.autoDispose.family<GameSummary, SummaryKey>(
  (ref, k) => ref.watch(apiProvider).summary(k.league, k.eventId),
);

/// The rich per-match tennis resource (ESPN core competition), fetched lazily
/// when a tennis match detail opens. `eventId` is the parent tournament event
/// id, `compId` the match id. autoDispose + best-effort (null on failure).
typedef TennisMatchKey = ({String league, String eventId, String compId});

final tennisMatchProvider =
    FutureProvider.autoDispose.family<TennisMatchInfo?, TennisMatchKey>(
  (ref, k) =>
      ref.watch(apiProvider).tennisMatchInfo(k.league, k.eventId, k.compId),
);

/// Rankings feed for a league page (college polls / ATP-WTA / UFC divisions).
/// Lazy + autoDispose: only alive while that league page is open; the worker
/// caches it for an hour, so re-fetch-on-open is cheap.
final rankingsProvider =
    FutureProvider.autoDispose.family<RankingsResponse, String>(
  (ref, league) => ref.watch(apiProvider).rankings(league),
);

/// Golf hole-by-hole scorecard, fetched when a leaderboard row is tapped.
typedef ScorecardKey = ({
  String league,
  String eventId,
  String playerId,
  int? season,
});

final scorecardProvider =
    FutureProvider.autoDispose.family<GolfScorecard, ScorecardKey>(
  (ref, k) => ref
      .watch(apiProvider)
      .scorecard(k.league, k.eventId, k.playerId, season: k.season),
);
