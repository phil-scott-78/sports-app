import 'dart:convert';
import 'package:flutter/material.dart' show ThemeMode, DateUtils;
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
class Settings {
  final ThemeMode themeMode;
  final String baseUrl;
  const Settings({required this.themeMode, required this.baseUrl});
  Settings copyWith({ThemeMode? themeMode, String? baseUrl}) => Settings(
        themeMode: themeMode ?? this.themeMode,
        baseUrl: baseUrl ?? this.baseUrl,
      );
}

class SettingsNotifier extends Notifier<Settings> {
  @override
  Settings build() {
    final p = ref.read(sharedPrefsProvider);
    return Settings(
      themeMode: ThemeMode.values.firstWhere(
        (m) => m.name == p.getString('themeMode'),
        orElse: () => ThemeMode.dark, // dark by default
      ),
      baseUrl: p.getString('baseUrl') ?? AppConfig.defaultBaseUrl,
    );
  }

  void setThemeMode(ThemeMode m) {
    ref.read(sharedPrefsProvider).setString('themeMode', m.name);
    state = state.copyWith(themeMode: m);
  }

  void setBaseUrl(String url) {
    final v = url.trim();
    ref.read(sharedPrefsProvider).setString('baseUrl', v);
    state = state.copyWith(baseUrl: v);
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, Settings>(SettingsNotifier.new);

/// Active bottom-nav tab (0=Scores). Lets the Scores tab pause its poll timer
/// while the user is on Leagues/Settings (IndexedStack keeps it mounted).
final tabIndexProvider = StateProvider<int>((ref) => 0);

// ---- which day's slate the Scores tab shows ---------------------------------
/// The date the Scores tab is "looking at". `null` = today — ESPN's live default
/// slate, and the only state that polls. A date-only [DateTime] = that specific
/// day's slate (one `dates=YYYYMMDD` fetch). This replaces the old
/// Yesterday/Today/Upcoming modes (and the separate Schedule tab) with a single
/// "viewing a date" concept; the header date sheet writes it, normalizing today
/// back to `null` so the view keeps following ESPN's sports-day rollover.
final viewDateProvider = StateProvider<DateTime?>((ref) => null);

/// ESPN's current "sports day" (date-only), captured from the most recent *today*
/// feed (its `day` field — only while [viewDateProvider] is null, so a browsed day
/// never overwrites it). Null until that first load → callers fall back to the
/// device date. ESPN's default slate doesn't roll at local midnight, so anchoring
/// the date strip to this (not `DateTime.now()`) keeps "today" honest in the
/// post-midnight window.
final espnTodayProvider = StateProvider<DateTime?>((ref) => null);

/// YYYYMMDD for an ESPN `dates=` query.
String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.day.toString().padLeft(2, '0')}';

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

  /// Remove a followed league (explicit — clearer than toggle for a delete button).
  void remove(String key) {
    if (!state.contains(key)) return;
    state = List.of(state)..remove(key);
    _save();
  }

  /// Reorder the followed list (drives the Scores-feed section order). [newIndex]
  /// is the post-removal target, matching ReorderableListView's onReorderItem.
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
/// string-list slot (key 'favoriteTeams'). Order is insertion order. Defaults to
/// empty so the Scores Favorites section stays hidden until the user adds one.
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
}

final favoriteTeamsProvider =
    NotifierProvider<FavoriteTeamsNotifier, List<FavoriteTeam>>(
        FavoriteTeamsNotifier.new);

// ---- api + data -------------------------------------------------------------
final apiProvider = Provider<Api>(
    (ref) => Api(ref.watch(settingsProvider.select((s) => s.baseUrl))));

/// Which sport family the Scores tab is filtered to ('all' = every followed
/// sport). Drives the Header-C sport-filter chip row; the feed itself is fetched
/// whole and filtered client-side so switching chips is instant (no refetch).
final sportFilterProvider = StateProvider<String>((ref) => 'all');

/// The Scores tab feed: every followed league's slate for the day the tab is
/// "looking at" ([viewDateProvider]), fetched in parallel. `null` view → ESPN's
/// default (today) slate; any other day → a single `dates=YYYYMMDD` fetch. A
/// failed league becomes a LeagueFeed.error instead of failing the whole feed.
/// Live polling, the sport chips, and the favorites rail all key off this — but
/// only while the view is today (see ScoresPage).
final feedProvider = FutureProvider<List<LeagueFeed>>((ref) async {
  final api = ref.watch(apiProvider);
  final leagues = ref.watch(followedProvider);
  final view = ref.watch(viewDateProvider);
  // Resolve the viewed day to a `dates` param. `null` (today) — or a pick that
  // lands back on ESPN's current sports day — defers to ESPN's default slate so we
  // get the live games. `read` the anchor (don't subscribe): it's captured on a
  // today-load and must not re-run this fetch for other days.
  String? date;
  if (view != null) {
    final now = DateTime.now();
    final anchor =
        ref.read(espnTodayProvider) ?? DateTime(now.year, now.month, now.day);
    if (!DateUtils.isSameDay(view, anchor)) date = _ymd(view);
  }
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

/// Every team in a league, for the favorites picker. Keyed by league key;
/// server-cached ~1 day, so the picker is cheap. autoDispose: only needed while
/// the picker is open — drop the per-league cache once it closes.
final teamsProvider = FutureProvider.autoDispose.family<List<TeamRef>, String>(
  (ref, league) => ref.watch(apiProvider).teams(league),
);

/// The Favorites section feed: every favorite's card, fetched in parallel. A
/// failed team becomes a FavoriteTeamFeed.error rather than failing the section.
/// Independent of [viewDateProvider] — favorites are "my teams now" (the Scores
/// rail shows them only on the today view).
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

/// Per-league season-pulse states for the Leagues list (worker-computed, keyed
/// by league key). Cached server-side; the app just fetches it when Leagues opens.
final overviewProvider = FutureProvider<Map<String, LeagueStateInfo>>(
    (ref) => ref.watch(apiProvider).overview());

/// One league's scores for a specific day (`date` = YYYYMMDD, or null = ESPN's
/// default slate). Powers the league-detail Schedule tab's date strip.
typedef LeagueDayKey = ({String league, String? date});

/// autoDispose: the schedule strip and game-detail page that read this are
/// transient (a pushed route / a per-day key that changes as you browse) and
/// poll-refresh while mounted, so dropping the cache when nothing listens is the
/// right lifecycle and frees the retained ScoresResponse per day/event opened.
final leagueDayScoresProvider =
    FutureProvider.autoDispose.family<ScoresResponse, LeagueDayKey>(
  (ref, k) => ref.watch(apiProvider).scores(k.league, date: k.date),
);

final standingsProvider = FutureProvider.autoDispose.family<Standings, String>(
  (ref, league) => ref.watch(apiProvider).standings(league),
);

/// Rich game-detail summary (box score, scoring feed, lineups), fetched lazily
/// only when a game detail is opened. Keyed by (league, eventId). autoDispose:
/// without it every game ever opened in a session leaks its ~10KB GameSummary —
/// the detail page re-fetches on mount, so dropping it on pop is lossless.
typedef SummaryKey = ({String league, String eventId});

final summaryProvider =
    FutureProvider.autoDispose.family<GameSummary, SummaryKey>(
  (ref, k) => ref.watch(apiProvider).summary(k.league, k.eventId),
);
