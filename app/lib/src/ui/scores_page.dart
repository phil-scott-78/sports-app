import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../config.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import 'favorite_team_card.dart';
import 'game_detail_page.dart';
import 'poll.dart';
import 'search_page.dart';
import 'widgets.dart';

class ScoresPage extends ConsumerStatefulWidget {
  const ScoresPage({super.key});
  @override
  ConsumerState<ScoresPage> createState() => _ScoresPageState();
}

class _ScoresPageState extends ConsumerState<ScoresPage>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _schedule(AppConfig.refreshIdle);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      // Catch up only when Scores is the visible tab; otherwise the tab-switch
      // listener handles the refetch on return (don't fetch behind other tabs).
      if (ref.read(tabIndexProvider) == 0) _refreshAll();
      _repace();
    } else {
      _timer?.cancel(); // don't poll in the background (battery)
    }
  }

  void _schedule(Duration d) {
    _timer?.cancel();
    _timer = Timer.periodic(d, (_) => _refreshAll());
  }

  /// Refresh both the league feed and the favorites feed — they share the poll
  /// beat and the foreground/tab catch-ups.
  void _refreshAll() {
    ref.invalidate(feedProvider);
    ref.invalidate(favoritesFeedProvider);
  }

  /// Anchor the date strip's math to ESPN's reported sports day, captured from
  /// the Scores feed. Only the *today* view (a `date:null` fetch) carries ESPN's
  /// current `day`; a browsed date echoes the requested day, so we never let it
  /// overwrite the anchor.
  void _captureEspnToday(List<LeagueFeed>? feeds) {
    if (feeds == null || ref.read(viewDateProvider) != null) return;
    for (final f in feeds) {
      final d = f.scores?.day;
      if (d == null || d.isEmpty) continue;
      final parsed = DateTime.tryParse(d);
      if (parsed == null) continue;
      final dateOnly = DateTime(parsed.year, parsed.month, parsed.day);
      if (ref.read(espnTodayProvider) != dateOnly) {
        ref.read(espnTodayProvider.notifier).state = dateOnly;
      }
      return;
    }
  }

  /// Single source of truth for the poll cadence: only the foregrounded, on-tab
  /// Scores slate ticks (live → 15s, else 60s); everything else cancels the
  /// timer. A browsed past/future day is static, so we poll only the *today*
  /// view ([viewDateProvider] == null). Gating on [_foreground] here is what
  /// stops an in-flight fetch that resolves *after* the app is backgrounded from
  /// re-arming a rogue timer.
  void _repace({bool? live}) {
    if (!_foreground ||
        ref.read(tabIndexProvider) != 0 ||
        ref.read(viewDateProvider) != null) {
      _timer?.cancel();
      return;
    }
    final feeds = ref.read(feedProvider).valueOrNull;
    final feedLive = feeds?.any((f) => f.scores?.anyLive == true) ?? false;
    final favLive = ref
            .read(favoritesFeedProvider)
            .valueOrNull
            ?.any((f) => f.card?.anyLive == true) ??
        false;
    final isLive = live ?? (feedLive || favLive);
    if (isLive) {
      _schedule(AppConfig.refreshLive);
      return;
    }
    // Nothing live, but if a scheduled game is near kickoff drop to 30s so the
    // idle→live flip is caught promptly instead of being hidden for a full 60s
    // idle window (mirrors the worker's near-kickoff TTL — see ttl.js).
    final soon =
        feeds?.any((f) => kickoffSoonMs(f.scores?.nextStartMs)) ?? false;
    _schedule(soon ? AppConfig.refreshNearKickoff : AppConfig.refreshIdle);
  }

  /// Header title for the viewed day: Today / Yesterday / Tomorrow, else a short
  /// dated label ("Sat, Jun 21"). [anchor] is ESPN's sports day (the device date
  /// until the first today-load captures it).
  String _viewDateTitle(DateTime? view, DateTime anchor) {
    if (view == null) return 'Today';
    // Round elapsed hours so a 23h/25h daylight-saving day can't shift the bucket.
    final diff = (DateUtils.dateOnly(view)
                .difference(DateUtils.dateOnly(anchor))
                .inHours /
            24)
        .round();
    if (diff == 0) return 'Today';
    if (diff == -1) return 'Yesterday';
    if (diff == 1) return 'Tomorrow';
    return DateFormat('EEE, MMM d').format(view); // "Sat, Jun 21"
  }

  void _showDateSportSheet(BuildContext context) {
    showBlurredBottomSheet<void>(
        context: context, child: const _DateSportSheet());
  }

  @override
  Widget build(BuildContext context) {
    final configured =
        ref.watch(settingsProvider.select((s) => s.baseUrl)).trim().isNotEmpty;
    final view = ref.watch(viewDateProvider);
    final now = DateTime.now();
    final anchor =
        ref.watch(espnTodayProvider) ?? DateTime(now.year, now.month, now.day);
    final filter = ref.watch(sportFilterProvider);
    final cs = Theme.of(context).colorScheme;

    // Re-pace polling once a fetch settles: fast when anything is live. Skip the
    // intermediate loading emission (it carries the stale previous value and
    // would needlessly re-anchor the timer's countdown on every refresh).
    ref.listen<AsyncValue<List<LeagueFeed>>>(feedProvider, (_, next) {
      if (next.isLoading) return;
      _captureEspnToday(next.valueOrNull);
      _repace(); // re-reads both feed + favorites for the live decision
    });
    ref.listen<AsyncValue<List<FavoriteTeamFeed>>>(favoritesFeedProvider,
        (_, next) {
      if (next.isLoading) return;
      _repace();
    });

    // Switching the viewed date re-fetches (feedProvider watches it); cancel the
    // poll at once for a static past/future day, re-arm on return to today.
    ref.listen<DateTime?>(viewDateProvider, (_, __) => _repace());

    // Pause polling while the user is on another tab (IndexedStack keeps this
    // page mounted); catch up and resume on return.
    ref.listen<int>(tabIndexProvider, (_, next) {
      if (next == 0) _refreshAll();
      _repace();
    });

    return Scaffold(
      // A compact date title (the day you're "looking at") that opens the date +
      // sport sheet, with a live-count chip + search alongside.
      appBar: AppBar(
        titleSpacing: 16,
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: configured ? () => _showDateSportSheet(context) : null,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              // The viewed day, plus the active sport filter as a muted qualifier
              // so a non-"All" filter is never hidden once the sheet is dismissed.
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: _viewDateTitle(view, anchor)),
                  if (filter != 'all')
                    TextSpan(
                      text: '  ·  ${sportLabel(filter)}',
                      style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600),
                    ),
                ]),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 3),
            const Icon(Icons.expand_more, size: 22, color: Color(0xFF8A9199)),
          ]),
        ),
        actions: [
          const _LiveCountChip(),
          IconButton(
            tooltip: 'Search',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SearchPage()),
            ),
            icon: const Icon(Icons.search),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: !configured
          ? const SetupPrompt()
          : RefreshIndicator(
              onRefresh: () => Future.wait([
                ref.refresh(feedProvider.future),
                ref.refresh(favoritesFeedProvider.future),
              ]),
              child: ref.watch(feedProvider).when(
                    // Keep the prior slate on a poll-driven reload — the bespoke
                    // timer invalidates (not refreshes) the feed, so without this
                    // every 15s/60s tick flashed the whole list to a spinner.
                    skipLoadingOnReload: true,
                    loading: () => const _LoadingList(),
                    error: (e, _) => ListView(children: [
                      const SizedBox(height: 120),
                      ErrorView(
                          message: '$e',
                          onRetry: () => ref.invalidate(feedProvider)),
                    ]),
                    data: (_) => const _FeedList(),
                  ),
            ),
    );
  }
}

/// Total live games today, as a green dot + count chip in the header. Hidden
/// when nothing is live. Reads the same feed the list renders from.
class _LiveCountChip extends ConsumerWidget {
  const _LiveCountChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feeds = ref.watch(feedProvider).valueOrNull ?? const <LeagueFeed>[];
    // Count live COMPETITIONS, not events — a tennis tournament is one event with
    // many concurrent live matches, and a racing weekend nests its sessions.
    final live = feeds.fold<int>(
      0,
      (n, f) =>
          n +
          (f.scores?.events.fold<int>(
                0,
                (m, e) => m + e.competitions.where((c) => c.status.live).length,
              ) ??
              0),
    );
    if (live == 0) return const SizedBox.shrink();
    final c = BinanceColors.of(context).live;
    return Center(
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          LiveDot(color: c),
          const SizedBox(width: 6),
          Text('$live',
              style: TextStyle(
                  color: c, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

/// The header date sheet — one combined panel (Apple-Sports style) opened by the
/// "Today ⌄" title, holding the day strip over the sport filter. Picking a day
/// drives [viewDateProvider] (today normalizes back to null); the chips drive
/// [sportFilterProvider]. Both apply live; the user dismisses to see the slate.
class _DateSportSheet extends ConsumerStatefulWidget {
  const _DateSportSheet();
  @override
  ConsumerState<_DateSportSheet> createState() => _DateSportSheetState();
}

class _DateSportSheetState extends ConsumerState<_DateSportSheet> {
  // Browse window: a week back, two weeks ahead — recent results + the next
  // fixtures for weekly leagues (NFL), without an unbounded list. Mirrors the
  // league-detail Schedule strip.
  static const int _past = 7;
  static const int _future = 14;
  static const double _chipExtent = 48 + 8; // DateChip width + separator

  late final ScrollController _strip;

  @override
  void initState() {
    super.initState();
    final view = ref.read(viewDateProvider);
    final now = DateTime.now();
    final anchor =
        ref.read(espnTodayProvider) ?? DateTime(now.year, now.month, now.day);
    final selected = view ?? anchor;
    final idx = _past +
        (DateUtils.dateOnly(selected)
                    .difference(DateUtils.dateOnly(anchor))
                    .inHours /
                24)
            .round();
    // Open with the selected day a couple chips in from the left (recent days peeking).
    _strip = ScrollController(
      initialScrollOffset: ((idx - 2).clamp(0, _past + _future)) * _chipExtent,
    );
  }

  @override
  void dispose() {
    _strip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(viewDateProvider);
    final now = DateTime.now();
    final anchor =
        ref.watch(espnTodayProvider) ?? DateTime(now.year, now.month, now.day);
    final selected = view ?? anchor;
    final base = DateUtils.dateOnly(anchor);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: SectionLabel('Date')),
        SizedBox(
          height: 64,
          child: ListView.separated(
            controller: _strip,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _past + 1 + _future,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final day = base.add(Duration(days: i - _past));
              final isAnchor = DateUtils.isSameDay(day, anchor);
              return DateChip(
                date: day,
                selected: DateUtils.isSameDay(day, selected),
                isToday: isAnchor,
                // Today normalizes to null so the view keeps following ESPN's
                // sports-day rollover; any other day stores its absolute date.
                // Picking a day is the sheet's terminal action — apply it and
                // dismiss so the user lands straight on that day's slate (the
                // sport chips below stay put; they filter live without closing).
                onTap: () {
                  ref.read(viewDateProvider.notifier).state =
                      isAnchor ? null : day;
                  Navigator.of(context).maybePop();
                },
              );
            },
          ),
        ),
        const SizedBox(height: 18),
        const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: SectionLabel('Sport')),
        const _SheetSportChips(),
        const SizedBox(height: 20),
      ],
    );
  }
}

/// The sport-filter chip row, folded into the header date sheet: "All" plus one
/// chip per followed sport family. Chips carry today's per-sport game count and a
/// green dot when that sport has a live game; the selection ([sportFilterProvider])
/// filters the slate client-side (no refetch).
class _SheetSportChips extends ConsumerWidget {
  const _SheetSportChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final followed = ref.watch(followedProvider);
    final feeds = ref.watch(feedProvider).valueOrNull ?? const <LeagueFeed>[];
    final selected = ref.watch(sportFilterProvider);

    // Distinct sports in followed order (derived from the key prefix so the chips
    // don't pop in only after the feed resolves).
    final sports = <String>[];
    for (final key in followed) {
      final s = key.split('/').first;
      if (s.isNotEmpty && !sports.contains(s)) sports.add(s);
    }

    int countFor(String sport) => feeds
        .where((f) => (f.scores?.sport ?? f.key.split('/').first) == sport)
        .fold(
            0,
            (n, f) =>
                n +
                _displayEvents(f.scores?.events ?? const <SportEvent>[])
                    .length);
    bool liveFor(String sport) => feeds
        .where((f) => (f.scores?.sport ?? f.key.split('/').first) == sport)
        .any((f) =>
            f.scores?.events
                .any((e) => e.competitions.any((c) => c.status.live)) ??
            false);

    final chips = <Widget>[
      _SportChip(
        icon: Icons.apps,
        label: 'All',
        selected: selected == 'all',
        onTap: () => ref.read(sportFilterProvider.notifier).state = 'all',
      ),
      for (final s in sports)
        _SportChip(
          icon: sportIcon(s),
          label: sportLabel(s),
          count: countFor(s),
          live: liveFor(s),
          selected: selected == s,
          onTap: () => ref.read(sportFilterProvider.notifier).state = s,
        ),
    ];

    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => chips[i],
      ),
    );
  }
}

class _SportChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final int? count;
  final bool live;
  final bool selected;
  final VoidCallback onTap;
  const _SportChip({
    required this.icon,
    required this.label,
    this.count,
    this.live = false,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ext = BinanceColors.of(context);
    // Selected = light fill / dark text (design .fchip.on); else surface + hairline.
    final bg = selected ? cs.onSurface : cs.surfaceContainerHigh;
    final fg = selected ? cs.surface : cs.onSurface;
    final sub =
        selected ? cs.surface.withValues(alpha: 0.6) : cs.onSurfaceVariant;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: selected ? null : Border.all(color: ext.cardBorder),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (live && !selected) ...[
            LiveDot(color: ext.live),
            const SizedBox(width: 7),
          ] else ...[
            Icon(icon, size: 17, color: sub),
            const SizedBox(width: 7),
          ],
          Text(label,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
          if (count != null && count! > 0) ...[
            const SizedBox(width: 7),
            Text('$count',
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: sub)),
          ],
        ]),
      ),
    );
  }
}

class _LoadingList extends StatelessWidget {
  const _LoadingList();
  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

/// The sport family a feed belongs to — its canonical `sport`, falling back to
/// the key prefix ('soccer/fifa.world' → 'soccer') before the feed resolves.
String feedSport(LeagueFeed feed) =>
    feed.scores?.sport ?? feed.key.split('/').first;

/// A multi-competition event that should render one card PER competition — a
/// tennis tournament nests all its matches under one ESPN event. Gated on the
/// data shape (numeric score + athlete/pair competitor), NOT layout, so MMA
/// (scoreKind none) and racing (field) keep their single-card treatment.
bool _explodes(SportEvent e) {
  if (e.competitions.length < 2) return false;
  final c = e.competitions.first;
  return c.scoreKind == 'numeric' &&
      (c.competitorKind == 'athlete' || c.competitorKind == 'pair');
}

/// The renderable events for a slate: most yield themselves; a tennis tournament
/// yields one synthetic single-match event per competition.
List<SportEvent> _displayEvents(Iterable<SportEvent> events) {
  final out = <SportEvent>[];
  for (final e in events) {
    if (_explodes(e)) {
      for (final c in e.competitions) {
        out.add(e.withCompetition(c));
      }
    } else {
      out.add(e);
    }
  }
  return out;
}

/// A feed with its renderable events pre-exploded (tennis tournaments fanned to
/// one match each) and status-sorted. The explode + sort allocates synthetic
/// events and runs a full comparison, so it's computed once per fetch via
/// [_displayFeedsProvider] rather than inside [leagueSections] on every rebuild
/// (the live poll would otherwise re-run it for every league each 15s tick).
typedef DisplayFeed = ({
  LeagueFeed feed,
  bool exploded,
  List<SportEvent> events
});

/// The Scores slate, with each league's display events exploded + sorted once
/// per fetch. Selecting on `valueOrNull` means a reload that retains the same
/// data (Riverpod keeps the previous list instance) doesn't recompute.
final _displayFeedsProvider = Provider<List<DisplayFeed>>((ref) {
  final feeds = ref.watch(feedProvider.select((a) => a.valueOrNull)) ??
      const <LeagueFeed>[];
  return [
    for (final feed in feeds)
      (
        feed: feed,
        exploded: (feed.scores?.events ?? const <SportEvent>[]).any(_explodes),
        events: _displayEvents(feed.scores?.events ?? const <SportEvent>[])
          ..sort(_byStatusThenTime),
      ),
  ];
});

/// Builds the league sections (section header + status-sorted [GameCard]s) for a
/// list of pre-computed [DisplayFeed]s, for the Scores slate (any viewed day).
/// [sportFilter] of 'all' keeps every league; otherwise only that sport family.
List<Widget> leagueSections(
  List<DisplayFeed> feeds, {
  String sportFilter = 'all',
  required String noGamesLabel,
}) {
  final out = <Widget>[];
  for (final df in feeds) {
    final feed = df.feed;
    if (sportFilter != 'all' && feedSport(feed) != sportFilter) continue;
    final name = feed.scores?.leagueName.isNotEmpty == true
        ? feed.scores!.leagueName
        : feed.key;
    out.add(_SectionHeader(title: name));
    if (feed.error != null) {
      out.add(_InfoTile(icon: Icons.error_outline, text: feed.error!));
    } else {
      final events = df.events;
      if (events.isEmpty) {
        out.add(_InfoTile(icon: Icons.event_busy_outlined, text: noGamesLabel));
      } else {
        // A tennis tournament can nest 100s of matches — cap the (live→scheduled→
        // final sorted) slate so the calm feed isn't flooded, noting the remainder.
        const cap = 30;
        final shown = df.exploded && events.length > cap
            ? events.take(cap).toList()
            : events;
        for (final ev in shown) {
          out.add(Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            // RepaintBoundary isolates a card's repaint (incl. its live-dot
            // animation) from its neighbours; the stable key lets Flutter reuse
            // the element/render objects across poll ticks instead of rebuilding
            // every card from scratch when the feed re-resolves.
            child: RepaintBoundary(
              child: GameCard(
                key: ValueKey('${feed.key}:${ev.id}:${ev.main?.id ?? ''}'),
                event: ev,
                sport: feed.scores!.sport,
                leagueKey: feed.key,
                leagueName: name,
                focusCompetitionId: df.exploded ? ev.main?.id : null,
              ),
            ),
          ));
        }
        if (shown.length < events.length) {
          out.add(_InfoTile(
              icon: Icons.more_horiz,
              text: '+${events.length - shown.length} more matches'));
        }
      }
    }
  }
  return out;
}

class _FeedList extends ConsumerWidget {
  const _FeedList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayFeeds = ref.watch(_displayFeedsProvider);
    final viewingToday = ref.watch(viewDateProvider) == null;
    final hasFavs = ref.watch(favoriteTeamsProvider).isNotEmpty;
    // Favorites are a "my teams now" rail — shown only on the today view; a
    // browsed past/future date is a pure league slate.
    final showFavs = hasFavs && viewingToday;
    final filter = ref.watch(sportFilterProvider);

    if (displayFeeds.isEmpty && !showFavs) {
      return ListView(children: const [
        SizedBox(height: 100),
        EmptyState(
          icon: Icons.star_outline,
          title: 'No leagues followed',
          subtitle: 'Add some from the Leagues tab.',
        ),
      ]);
    }

    final children = <Widget>[];

    // Favorites pinned at the top — "my teams now", cross-sport (not filtered).
    if (showFavs) {
      children.add(const _SectionHeader(title: 'Favorites'));
      final async = ref.watch(favoritesFeedProvider);
      final favData = async.valueOrNull;
      if (favData == null && async.isLoading) {
        children.add(const _InfoTile(
            icon: Icons.hourglass_empty, text: 'Loading favorites…'));
      } else if (favData == null && async.hasError) {
        children
            .add(_InfoTile(icon: Icons.error_outline, text: '${async.error}'));
      } else {
        for (final f in favData ?? const <FavoriteTeamFeed>[]) {
          children.add(Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: RepaintBoundary(
              child:
                  FavoriteTeamCard(key: ValueKey('fav:${f.fav.id}'), feed: f),
            ),
          ));
        }
      }
    }

    final sections = leagueSections(displayFeeds,
        sportFilter: filter,
        noGamesLabel: viewingToday ? 'No games today' : 'No games');
    if (sections.isEmpty && filter != 'all') {
      children.add(const Padding(
        padding: EdgeInsets.only(top: 24),
        child: EmptyState(
          icon: Icons.event_busy_outlined,
          title: 'No games',
          subtitle: 'Nothing in this sport right now.',
        ),
      ));
    } else {
      children.addAll(sections);
    }
    children.add(const SizedBox(height: kFloatingNavInset));
    // ListView.builder so off-screen sections/cards aren't mounted, laid out, or
    // painted — only the viewport (+ cache extent) is built, even though the
    // `children` descriptors are assembled up front.
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: children.length,
      itemBuilder: (_, i) => children[i],
    );
  }
}

int _statusRank(SportEvent e) {
  switch (e.main?.status.phase) {
    case 'live':
      return 0;
    case 'scheduled':
      return 1;
    case 'final':
      return 2;
    // postponed / canceled / abandoned / suspended / unknown are terminal-but-not-
    // played — sort them BELOW finals (they were ranked above before).
    default:
      return 3;
  }
}

int _byStatusThenTime(SportEvent a, SportEvent b) {
  final r = _statusRank(a) - _statusRank(b);
  if (r != 0) return r;
  final ta = a.start, tb = b.start;
  if (ta != null && tb != null) return ta.compareTo(tb);
  return 0;
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
        child: Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      );
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoTile({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(children: [
        Icon(icon, size: 18, color: cs.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
            child: Text(text,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13))),
      ]),
    );
  }
}

// ---- game card --------------------------------------------------------------
class GameCard extends StatelessWidget {
  final SportEvent event;
  final String sport;
  final String leagueKey;
  final String leagueName;

  /// When this card is one match of an exploded tennis tournament, the id of the
  /// competition to keep in focus after the detail page re-fetches the (full) event.
  final String? focusCompetitionId;
  const GameCard({
    super.key,
    required this.event,
    required this.sport,
    required this.leagueKey,
    required this.leagueName,
    this.focusCompetitionId,
  });

  @override
  Widget build(BuildContext context) {
    final comp = event.main;
    if (comp == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: BinanceColors.of(context).cardBorder, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      // A subtle winner-color wash on final cards (borrowed from Apple Sports).
      // `Ink` paints the gradient *into* the Material, so the InkWell's tap
      // ripple still renders on top of it (a DecoratedBox child would mute the
      // splash). Null gradient → plain surface for non-final/field/color-less.
      child: Ink(
        decoration: BoxDecoration(gradient: winnerWashGradient(context, comp)),
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => GameDetailPage(
                event: event,
                sport: sport,
                leagueKey: leagueKey,
                leagueName: leagueName,
                focusCompetitionId: focusCompetitionId),
          )),
          // Collapse the row into one screen-reader label ("Live. Lakers 103.
          // Celtics 99. 3rd 8:39") — otherwise the crests/scores/status read as
          // scattered fragments and live/winner state (color-only visually) is
          // lost. The InkWell above keeps the tap/button affordance.
          child: Semantics(
            label: _semanticLabel(comp),
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child:
                  comp.isField ? _field(context, comp) : _match(context, comp),
            ),
          ),
        ),
      ),
    );
  }

  /// One spoken label for the whole card. Mirrors what the row shows so a screen
  /// reader hears the score in one node, including the live/winner state that is
  /// otherwise carried only by color.
  String _semanticLabel(Competition comp) {
    if (comp.isField) {
      final leader =
          comp.competitors.isNotEmpty ? comp.competitors.first : null;
      final title = event.shortName.isNotEmpty ? event.shortName : event.name;
      final lead = leader != null ? ', leader ${leader.displayName}' : '';
      return '$title$lead. ${statusLabel(comp.status, event.start)}';
    }
    final a = comp.away ??
        (comp.competitors.isNotEmpty ? comp.competitors.first : null);
    final b =
        comp.home ?? (comp.competitors.length > 1 ? comp.competitors[1] : null);
    String side(Competitor? c) {
      if (c == null) return '';
      final name =
          c.shortName?.isNotEmpty == true ? c.shortName! : c.displayName;
      if (comp.scoreKind == 'none') return c.isWinner ? '$name, winner' : name;
      // Cricket: speak the clean runs line, not ESPN's verbose "(18/20 ov, target…)".
      final score = comp.scoreKind == 'cricket'
          ? cricketScoreParts(c).runs
          : (c.score?.display ?? '');
      return score.isEmpty ? name : '$name $score';
    }

    final prefix = comp.status.live ? 'Live. ' : '';
    return '$prefix${side(a)}. ${side(b)}. ${statusLabel(comp.status, event.start)}';
  }

  /// Apple-Sports head-to-head row: each team is a crest with its name in small
  /// print underneath, pinned to the outer edge; the two big scores hug a
  /// centered status/time. One renderer, no per-sport branching — the
  /// discriminators (`scoreKind`, winner flags) decide what each slot reads.
  Widget _match(BuildContext context, Competition comp) {
    // Away on the left, home on the right — the universal ESPN/Apple convention,
    // matching the line-score grid below (which is away-first). See winnerWashGradient.
    final a =
        comp.away ?? (comp.competitors.isNotEmpty ? comp.competitors[0] : null);
    final b =
        comp.home ?? (comp.competitors.length > 1 ? comp.competitors[1] : null);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
            child: a == null
                ? const SizedBox()
                : _teamBlock(context, comp, a, alignEnd: false)),
        _scoreCluster(context, comp, a, b),
        Expanded(
            child: b == null
                ? const SizedBox()
                : _teamBlock(context, comp, b, alignEnd: true)),
      ],
    );
  }

  /// Outer team column: crest on top, short name in small print under it, record
  /// only on the upcoming slate (Apple shows it just for not-yet-played games).
  /// [alignEnd] mirrors the block for the right-hand team so its crest sits on
  /// the outer edge.
  Widget _teamBlock(BuildContext context, Competition comp, Competitor c,
      {required bool alignEnd}) {
    final cs = Theme.of(context).colorScheme;
    final dim = comp.status.isFinal && c.winner == false;
    final name = c.shortName?.isNotEmpty == true ? c.shortName! : c.displayName;
    final align = alignEnd ? TextAlign.right : TextAlign.left;
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Crest(
            url: c.logo,
            darkUrl: c.logoDark,
            fallback: c.abbreviation ?? c.displayName,
            size: 36),
        const SizedBox(height: 6),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: align,
          style: TextStyle(
            fontSize: 13,
            fontWeight: c.isWinner ? FontWeight.w700 : FontWeight.w600,
            color: dim ? cs.onSurfaceVariant : cs.onSurface,
          ),
        ),
        if (c.recordSummary != null && comp.status.isScheduled)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              c.recordSummary!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: align,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ),
      ],
    );
  }

  /// The centre column: big left score · status/time · big right score. The
  /// scores flank a status that stays put so the whole list reads as aligned
  /// columns down the slate.
  Widget _scoreCluster(
      BuildContext context, Competition comp, Competitor? a, Competitor? b) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (a != null) _score(context, comp, a),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 78),
          child: _centerStatus(context, comp),
        ),
        const SizedBox(width: 8),
        if (b != null) _score(context, comp, b),
      ],
    );
  }

  Widget _score(BuildContext context, Competition comp, Competitor c) {
    final cs = Theme.of(context).colorScheme;
    if (comp.scoreKind == 'none') {
      // MMA and friends: a winner check, never a number.
      return c.isWinner
          ? Icon(Icons.check_circle,
              size: 22, color: BinanceColors.of(context).accent)
          : const SizedBox(width: 22);
    }
    // Scheduled games seed score "0" in ESPN — show nothing, the time carries the row.
    if (comp.status.isScheduled) return const SizedBox.shrink();
    final dim = comp.status.isFinal && c.winner == false;
    // Cricket: ESPN's score is a long composite ("161/5 (18/20 ov, target 156)").
    // Show the runs/wickets line on its own (parenthetical peeled off so it fits
    // the slot built for "103") with the overs as a compact tempo tag underneath —
    // the chase target + per-innings detail live one tap away in the Innings panel.
    if (comp.scoreKind == 'cricket') {
      final parts = cricketScoreParts(c);
      if (parts.runs.isEmpty) return const SizedBox.shrink();
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 90),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              parts.runs,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: numStyle(
                size: 16,
                weight: c.isWinner ? FontWeight.w800 : FontWeight.w600,
                color: dim ? cs.onSurfaceVariant : cs.onSurface,
              ),
            ),
            if (parts.overs != null)
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  parts.overs!,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      );
    }
    var s = c.score?.display ?? '';
    if (s.isEmpty) {
      // Tennis & co. carry no aggregate score, but per-set winners exist → show the
      // sets-won tally once a set is decided (else the status/time carries the row).
      if (c.periodScores.any((p) => p.setWinner != null)) {
        s = '${c.periodScores.where((p) => p.setWinner == true).length}';
      } else {
        return const SizedBox.shrink();
      }
    }
    return Text(
      s,
      style: numStyle(
        size: 28,
        weight: c.isWinner ? FontWeight.w800 : FontWeight.w700,
        color: dim ? cs.onSurfaceVariant : cs.onSurface,
      ),
    );
  }

  /// Centred status: a live game keeps the brand's pulsing red dot beside a
  /// high-contrast clock; final/scheduled sit muted. OT/PENS/AGG/DRAW tags tuck
  /// underneath.
  Widget _centerStatus(BuildContext context, Competition comp) {
    final cs = Theme.of(context).colorScheme;
    final live = comp.status.live;
    final badge = _decisionBadge(comp);
    final label = Text(
      statusLabel(comp.status, event.start),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 12.5,
        height: 1.15,
        fontWeight: FontWeight.w600,
        color: live ? cs.onSurface : cs.onSurfaceVariant,
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (live)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              LiveDot(color: BinanceColors.of(context).live),
              const SizedBox(width: 5),
              Flexible(child: label),
            ],
          )
        else
          label,
        if (badge != null) ...[
          const SizedBox(height: 4),
          _Badge(text: badge),
        ],
      ],
    );
  }

  Widget _field(BuildContext context, Competition comp) {
    final cs = Theme.of(context).colorScheme;
    final leader = comp.competitors.isNotEmpty ? comp.competitors.first : null;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(event.shortName.isNotEmpty ? event.shortName : event.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              if (leader != null)
                Text(
                  'Leader: ${leader.displayName}${leader.score?.display.isNotEmpty == true ? '  ${leader.score!.display}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
              Text('${comp.competitors.length} competitors',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        StatusChip(status: comp.status, startTime: event.start),
      ],
    );
  }

  String? _decisionBadge(Competition comp) {
    switch (comp.decision) {
      case 'overtime':
        return comp.status.altDetail ?? 'OT';
      case 'shootout':
        return _pairBadge(comp, 'PENS', (c) => c.shootoutScore);
      case 'aggregate':
        return _pairBadge(
            comp, 'Agg', (c) => num.tryParse(c.aggregateScore ?? ''));
      case 'draw':
        return 'DRAW';
      case 'method':
        return comp.method?.kind;
      default:
        return null;
    }
  }

  /// "PENS 4-3" / "Agg 7-5" — the tally that actually decided it, winner-first.
  /// Falls back to the bare label when both numbers aren't present.
  String _pairBadge(
      Competition comp, String label, num? Function(Competitor) val) {
    final vals = comp.competitors.map(val).whereType<num>().toList();
    if (vals.length < 2) return label;
    vals.sort((a, b) => b.compareTo(a));
    String fmt(num n) => n == n.roundToDouble() ? n.toInt().toString() : '$n';
    return '$label ${fmt(vals[0])}-${fmt(vals[1])}';
  }
}

class _Badge extends StatelessWidget {
  final String text;
  const _Badge({required this.text});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Neutral label — OT / PENS / AGG / DRAW are context tags, not brand moments,
    // so they stay muted; yellow is reserved for winner/value emphasis.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
            color: cs.onSurfaceVariant,
          )),
    );
  }
}
