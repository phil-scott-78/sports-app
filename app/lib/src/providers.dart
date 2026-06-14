import 'dart:convert';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'config.dart';
import 'models.dart';

/// Overridden in main() with the loaded instance.
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPrefsProvider must be overridden in main()'),
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

final settingsProvider = NotifierProvider<SettingsNotifier, Settings>(SettingsNotifier.new);

/// Active bottom-nav tab (0=Scores). Lets the Scores tab pause its poll timer
/// while the user is on Leagues/Settings (IndexedStack keeps it mounted).
final tabIndexProvider = StateProvider<int>((ref) => 0);

// ---- which day's slate the Scores tab shows ---------------------------------
/// Yesterday / Today / Upcoming, à la Apple Sports.
enum ScoreDate { yesterday, today, upcoming }

final dateModeProvider = StateProvider<ScoreDate>((ref) => ScoreDate.today);

/// ESPN's current "sports day" (date-only), captured from the most recent Today
/// feed (its `day` field). Null until that first load → callers fall back to the
/// device date. ESPN's default slate doesn't roll at local midnight, so anchoring
/// Yesterday/Upcoming to this (not `DateTime.now()`) stops the day modes from
/// overlapping in the post-midnight window.
final espnTodayProvider = StateProvider<DateTime?>((ref) => null);

/// How many days ahead of today the Upcoming slate is showing — 1 is tomorrow
/// (the first chip in the date strip), up to [AppConfig.upcomingDays]. Stored as
/// a relative offset, *not* an absolute date, on purpose: the strip is always
/// "today + offset", so the selection stays valid and visibly highlighted across
/// a midnight rollover (an absolute date would silently fall out of the strip's
/// live range and keep fetching an unhighlighted day).
final upcomingOffsetProvider = StateProvider<int>((ref) => 1);

/// The ESPN `dates` query a mode maps to (`null` = today's default scoreboard).
/// Yesterday is the day before [anchor]; Upcoming is a single chosen future day
/// ([upcoming], defaulting to anchor+1) — the user picks it from the date strip,
/// so we fetch just that one day rather than a whole week's worth of games.
///
/// [anchor] should be ESPN's reported sports day ([espnTodayProvider]) when known,
/// falling back to the device date. Today (`null`) defers to ESPN's own current
/// slate, which it buckets in US-Eastern and does NOT roll at local midnight;
/// anchoring the offsets to that same day is what keeps Today/Yesterday from
/// overlapping (and Upcoming from skipping a day) in the post-midnight window.
String? espnDateParam(ScoreDate mode, DateTime anchor, {DateTime? upcoming}) {
  String ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}'
      '${d.month.toString().padLeft(2, '0')}'
      '${d.day.toString().padLeft(2, '0')}';
  switch (mode) {
    case ScoreDate.today:
      return null;
    case ScoreDate.yesterday:
      return ymd(anchor.subtract(const Duration(days: 1)));
    case ScoreDate.upcoming:
      return ymd(upcoming ?? anchor.add(const Duration(days: 1)));
  }
}

// ---- followed leagues -------------------------------------------------------
class FollowedNotifier extends Notifier<List<String>> {
  @override
  List<String> build() {
    final p = ref.read(sharedPrefsProvider);
    return p.getStringList('followed') ?? List.of(AppConfig.defaultFollowed);
  }

  void _save() => ref.read(sharedPrefsProvider).setStringList('followed', state);

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

final followedProvider = NotifierProvider<FollowedNotifier, List<String>>(FollowedNotifier.new);

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
    state = state.where((f) => !(f.league == league && f.teamId == teamId)).toList();
    _save();
  }

  void toggle(FavoriteTeam f) =>
      contains(f.league, f.teamId) ? remove(f.league, f.teamId) : add(f);
}

final favoriteTeamsProvider =
    NotifierProvider<FavoriteTeamsNotifier, List<FavoriteTeam>>(FavoriteTeamsNotifier.new);

// ---- api + data -------------------------------------------------------------
final apiProvider = Provider<Api>((ref) => Api(ref.watch(settingsProvider.select((s) => s.baseUrl))));

/// The home feed: every followed league's scores, fetched in parallel. A failed
/// league becomes a LeagueFeed.error instead of failing the whole feed.
final feedProvider = FutureProvider<List<LeagueFeed>>((ref) async {
  final api = ref.watch(apiProvider);
  final leagues = ref.watch(followedProvider);
  final mode = ref.watch(dateModeProvider);
  // Anchor day math to ESPN's reported sports day when known (captured on the last
  // Today load), else the device date. `read` (not `watch`): the anchor only
  // updates during Today loads, and switching to Yesterday/Upcoming re-runs this
  // via the watched mode/offset — so it always reads the latest anchor.
  final now = DateTime.now();
  final anchor = ref.read(espnTodayProvider) ?? DateTime(now.year, now.month, now.day);
  // Resolve the picked offset to an absolute day at fetch time, and only subscribe
  // to it in Upcoming mode so changing the day never triggers a needless refetch
  // of the Today/Yesterday slate.
  DateTime? upcomingDay;
  if (mode == ScoreDate.upcoming) {
    upcomingDay = anchor.add(Duration(days: ref.watch(upcomingOffsetProvider)));
  }
  final date = espnDateParam(mode, anchor, upcoming: upcomingDay);
  return Future.wait(leagues.map((key) async {
    try {
      return LeagueFeed(key, await api.scores(key, date: date));
    } catch (e) {
      return LeagueFeed(key, null, error: e.toString());
    }
  }));
});

final catalogProvider = FutureProvider<List<CatalogSport>>((ref) => ref.watch(apiProvider).catalog());

/// Every team in a league, for the favorites picker. Keyed by league key;
/// server-cached ~1 day, so the picker is cheap.
final teamsProvider = FutureProvider.family<List<TeamRef>, String>(
  (ref, league) => ref.watch(apiProvider).teams(league),
);

/// The Favorites section feed: every favorite's card, fetched in parallel. A
/// failed team becomes a FavoriteTeamFeed.error rather than failing the section.
/// Independent of [dateModeProvider] — favorites are "my teams now".
final favoritesFeedProvider = FutureProvider<List<FavoriteTeamFeed>>((ref) async {
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
final overviewProvider =
    FutureProvider<Map<String, LeagueStateInfo>>((ref) => ref.watch(apiProvider).overview());

/// One league's scores for a specific day (`date` = YYYYMMDD, or null = ESPN's
/// default slate). Powers the league-detail Schedule tab's date strip.
typedef LeagueDayKey = ({String league, String? date});

final leagueDayScoresProvider = FutureProvider.family<ScoresResponse, LeagueDayKey>(
  (ref, k) => ref.watch(apiProvider).scores(k.league, date: k.date),
);

final standingsProvider = FutureProvider.family<Standings, String>(
  (ref, league) => ref.watch(apiProvider).standings(league),
);

/// Rich game-detail summary (box score, scoring feed, lineups), fetched lazily
/// only when a game detail is opened. Keyed by (league, eventId).
typedef SummaryKey = ({String league, String eventId});

final summaryProvider = FutureProvider.family<GameSummary, SummaryKey>(
  (ref, k) => ref.watch(apiProvider).summary(k.league, k.eventId),
);
