import 'dart:convert';
import 'package:flutter/material.dart' show ThemeMode, DateUtils;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'config.dart';
import 'models.dart';
import 'version.dart';

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

// ---- Leagues-tab season pulse (tiered) --------------------------------------
// The registry has ~245 leagues but a Worker request fans out ≤48 scoreboard
// fetches (Cloudflare's subrequest cap), so the pulse is fetched in curated,
// stable (shared-cache) buckets instead of one impossible all-leagues call.

/// Leagues pinned to the top of the Default & Active tiers: the leagues you
/// follow PLUS the leagues of any team you've favorited. Derived — no fetch.
final pinnedLeaguesProvider = Provider<List<String>>((ref) {
  final out = <String>[];
  final seen = <String>{};
  for (final k in [
    ...ref.watch(followedProvider),
    ...ref.watch(favoriteTeamsProvider).map((f) => f.league),
  ]) {
    if (seen.add(k)) out.add(k);
  }
  return out;
});

/// Default tier pulse: the popular (priority `v1`) leagues — one cheap fetch.
final popularOverviewProvider = FutureProvider<Map<String, LeagueStateInfo>>(
    (ref) => ref.watch(apiProvider).overview(priority: 'v1'));

/// Active tier pulse: the curated `v1`+`v2` set, paged under the 48-cap and
/// merged. Two cache-coalesced fetches; the UI filters to non-offseason states.
final activeOverviewProvider =
    FutureProvider<Map<String, LeagueStateInfo>>((ref) async {
  final api = ref.watch(apiProvider);
  final pages = await Future.wait([
    api.overview(priority: 'v1,v2', page: 0),
    api.overview(priority: 'v1,v2', page: 1),
  ]);
  return {for (final m in pages) ...m};
});

/// Pulse for the pinned leagues themselves (so a pinned league outside the
/// fetched tier — e.g. a followed lower-division side — still gets a dot). One
/// small keyed fetch; refetches when the pinned set changes. Empty → no fetch.
final pinnedOverviewProvider =
    FutureProvider<Map<String, LeagueStateInfo>>((ref) {
  final pinned = ref.watch(pinnedLeaguesProvider);
  if (pinned.isEmpty) return Future.value(const {});
  return ref.watch(apiProvider).overview(keys: pinned.take(48).toList());
});

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

/// College Top-25 polls for a league-detail page (AP/Coaches/CFP). autoDispose:
/// only alive while a college league page is open. Empty polls → no section.
final rankingsProvider =
    FutureProvider.autoDispose.family<RankingsResponse, String>(
  (ref, league) => ref.watch(apiProvider).rankings(league),
);

/// The set of YYYYMMDD days (local-bucketed) that have ≥1 game for a league
/// across a date range — one `dates=START-END` fetch (ESPN accepts the range,
/// the worker forwards it). Powers the league-schedule strip's empty-day dimming
/// and its auto-jump to the next day with games. autoDispose: only alive while a
/// schedule strip is open.
typedef LeagueRangeKey = ({String league, String start, String end});

final leagueScheduleDaysProvider = FutureProvider.autoDispose
    .family<Set<String>, LeagueRangeKey>((ref, k) async {
  final resp = await ref
      .watch(apiProvider)
      .scores(k.league, date: '${k.start}-${k.end}');
  final out = <String>{};
  for (final e in resp.events) {
    final s = e.start;
    if (s != null) out.add(_ymd(s)); // e.start is already local
  }
  return out;
});

/// Rich game-detail summary (box score, scoring feed, lineups), fetched lazily
/// only when a game detail is opened. Keyed by (league, eventId). autoDispose:
/// without it every game ever opened in a session leaks its ~10KB GameSummary —
/// the detail page re-fetches on mount, so dropping it on pop is lossless.
typedef SummaryKey = ({String league, String eventId});

final summaryProvider =
    FutureProvider.autoDispose.family<GameSummary, SummaryKey>(
  (ref, k) => ref.watch(apiProvider).summary(k.league, k.eventId),
);

// ---- update gate (client-version advisory) ----------------------------------
/// Worker health + the advisory client-version gate. The update banner is the
/// only listener; it fetches once on launch. A failure or a gate-less worker
/// surfaces as "no banner" — a health hiccup never blocks the app.
final healthProvider =
    FutureProvider<HealthInfo>((ref) => ref.watch(apiProvider).health());

/// Which update nudge (if any) this build warrants.
enum UpdateTier {
  /// Current build, a dev build, or a gate-less/unreachable worker → show nothing.
  none,

  /// At/above minimum but below recommended → a dismissible "update available".
  soft,

  /// Below minimum → a persistent "no longer supported" bar.
  hard,
}

/// Pure tier computation, separated from the provider so it's testable without
/// the compile-time [kClientVersionCode] (which is 0 under `flutter test`).
/// Fail-open at every step: a dev build (code <= 0), no gate served (old/forked/
/// mock worker), or a missing field → [UpdateTier.none]. Numeric only — never
/// the semver name.
UpdateTier computeUpdateTier(int clientVersionCode, ClientGate? gate) {
  if (clientVersionCode <= 0) return UpdateTier.none; // local/dev build
  if (gate == null) return UpdateTier.none; // fail-open: no gate served
  final min = gate.minVersionCode;
  if (min != null && clientVersionCode < min) return UpdateTier.hard;
  final rec = gate.recommendedVersionCode;
  if (rec != null && clientVersionCode < rec) return UpdateTier.soft;
  return UpdateTier.none;
}

/// Derives the [UpdateTier] from the served gate vs the baked [kClientVersionCode].
final updateTierProvider = Provider<UpdateTier>((ref) => computeUpdateTier(
    kClientVersionCode, ref.watch(healthProvider).valueOrNull?.client));

/// The highest `recommendedVersionCode` the user has dismissed the SOFT banner
/// for — so a soft nudge shows once per release, not every launch. The hard
/// (below-minimum) banner ignores this and always shows. Persisted.
class DismissedUpdateNotifier extends Notifier<int> {
  static const _key = 'dismissedRecommendedVersionCode';

  @override
  int build() => ref.read(sharedPrefsProvider).getInt(_key) ?? 0;

  void dismiss(int recommendedVersionCode) {
    if (recommendedVersionCode <= state) return;
    state = recommendedVersionCode;
    ref.read(sharedPrefsProvider).setInt(_key, recommendedVersionCode);
  }
}

final dismissedUpdateProvider =
    NotifierProvider<DismissedUpdateNotifier, int>(DismissedUpdateNotifier.new);

/// Whether the [UpdateBanner] will actually render — the full visibility decision
/// in one place so the app chrome can reserve space for it (and zero the status-bar
/// inset) ONLY when it shows, leaving the common (no-banner) layout untouched.
/// False unless a gate is served AND this build is below it AND (for the soft
/// tier) the user hasn't already dismissed this release.
final bannerVisibleProvider = Provider<bool>((ref) {
  final tier = ref.watch(updateTierProvider);
  if (tier == UpdateTier.none) return false;
  final gate = ref.watch(healthProvider).valueOrNull?.client;
  if (gate == null) return false; // fail-open
  if (tier == UpdateTier.soft) {
    final rec = gate.recommendedVersionCode ?? 0;
    if (rec > 0 && ref.watch(dismissedUpdateProvider) >= rec) return false;
  }
  return true;
});
