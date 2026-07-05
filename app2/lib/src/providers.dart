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
  return Future.wait(leagues.map((key) async {
    try {
      return LeagueFeed(key, await api.scores(key));
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

/// One league's live slate, independent of the followed feed — the detail page
/// polls this so a game opened from a favorite card (league not followed)
/// still refreshes. autoDispose: alive only while a detail is open.
final leagueScoresProvider =
    FutureProvider.autoDispose.family<ScoresResponse, String>(
  (ref, league) => ref.watch(apiProvider).scores(league),
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
