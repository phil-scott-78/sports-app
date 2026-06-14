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
import 'search_page.dart';
import 'widgets.dart';

class ScoresPage extends ConsumerStatefulWidget {
  const ScoresPage({super.key});
  @override
  ConsumerState<ScoresPage> createState() => _ScoresPageState();
}

class _ScoresPageState extends ConsumerState<ScoresPage> with WidgetsBindingObserver {
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
    if (!_foreground || ref.read(tabIndexProvider) != 0 || ref.read(viewDateProvider) != null) {
      _timer?.cancel();
      return;
    }
    final feedLive = ref.read(feedProvider).valueOrNull?.any((f) => f.scores?.anyLive == true) ?? false;
    final favLive = ref.read(favoritesFeedProvider).valueOrNull?.any((f) => f.card?.anyLive == true) ?? false;
    final isLive = live ?? (feedLive || favLive);
    _schedule(isLive ? AppConfig.refreshLive : AppConfig.refreshIdle);
  }

  /// Header title for the viewed day: Today / Yesterday / Tomorrow, else a short
  /// dated label ("Sat, Jun 21"). [anchor] is ESPN's sports day (the device date
  /// until the first today-load captures it).
  String _viewDateTitle(DateTime? view, DateTime anchor) {
    if (view == null) return 'Today';
    // Round elapsed hours so a 23h/25h daylight-saving day can't shift the bucket.
    final diff =
        (DateUtils.dateOnly(view).difference(DateUtils.dateOnly(anchor)).inHours / 24).round();
    if (diff == 0) return 'Today';
    if (diff == -1) return 'Yesterday';
    if (diff == 1) return 'Tomorrow';
    return DateFormat('EEE, MMM d').format(view); // "Sat, Jun 21"
  }

  void _showDateSportSheet(BuildContext context) {
    showBlurredBottomSheet<void>(context: context, child: const _DateSportSheet());
  }

  @override
  Widget build(BuildContext context) {
    final configured = ref.watch(settingsProvider.select((s) => s.baseUrl)).trim().isNotEmpty;
    final view = ref.watch(viewDateProvider);
    final now = DateTime.now();
    final anchor = ref.watch(espnTodayProvider) ?? DateTime(now.year, now.month, now.day);
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
    ref.listen<AsyncValue<List<FavoriteTeamFeed>>>(favoritesFeedProvider, (_, next) {
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
                      style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
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
                    loading: () => const _LoadingList(),
                    error: (e, _) => ListView(children: [
                      const SizedBox(height: 120),
                      ErrorView(message: '$e', onRetry: () => ref.invalidate(feedProvider)),
                    ]),
                    data: (feeds) => _FeedList(feeds: feeds),
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
    final live = feeds.fold<int>(
      0,
      (n, f) => n + (f.scores?.events.where((e) => e.main?.status.live == true).length ?? 0),
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
              style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700)),
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
    final anchor = ref.read(espnTodayProvider) ?? DateTime(now.year, now.month, now.day);
    final selected = view ?? anchor;
    final idx = _past +
        (DateUtils.dateOnly(selected).difference(DateUtils.dateOnly(anchor)).inHours / 24).round();
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
    final anchor = ref.watch(espnTodayProvider) ?? DateTime(now.year, now.month, now.day);
    final selected = view ?? anchor;
    final base = DateUtils.dateOnly(anchor);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: SectionLabel('Date')),
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
                  ref.read(viewDateProvider.notifier).state = isAnchor ? null : day;
                  Navigator.of(context).maybePop();
                },
              );
            },
          ),
        ),
        const SizedBox(height: 18),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: SectionLabel('Sport')),
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
        .fold(0, (n, f) => n + (f.scores?.events.length ?? 0));
    bool liveFor(String sport) => feeds
        .where((f) => (f.scores?.sport ?? f.key.split('/').first) == sport)
        .any((f) => f.scores?.events.any((e) => e.main?.status.live == true) ?? false);

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
    final sub = selected ? cs.surface.withValues(alpha: 0.6) : cs.onSurfaceVariant;
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
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
          if (count != null && count! > 0) ...[
            const SizedBox(width: 7),
            Text('$count',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: sub)),
          ],
        ]),
      ),
    );
  }
}

class _LoadingList extends StatelessWidget {
  const _LoadingList();
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
}

/// The sport family a feed belongs to — its canonical `sport`, falling back to
/// the key prefix ('soccer/fifa.world' → 'soccer') before the feed resolves.
String feedSport(LeagueFeed feed) => feed.scores?.sport ?? feed.key.split('/').first;

/// Builds the league sections (section header + status-sorted [GameCard]s) for a
/// list of feeds, for the Scores slate (any viewed day).
/// [sportFilter] of 'all' keeps every league; otherwise only that sport family.
List<Widget> leagueSections(
  List<LeagueFeed> feeds, {
  String sportFilter = 'all',
  required String noGamesLabel,
}) {
  final out = <Widget>[];
  for (final feed in feeds) {
    if (sportFilter != 'all' && feedSport(feed) != sportFilter) continue;
    final name =
        feed.scores?.leagueName.isNotEmpty == true ? feed.scores!.leagueName : feed.key;
    out.add(_SectionHeader(title: name));
    if (feed.error != null) {
      out.add(_InfoTile(icon: Icons.error_outline, text: feed.error!));
    } else {
      final events = [...(feed.scores?.events ?? <SportEvent>[])]..sort(_byStatusThenTime);
      if (events.isEmpty) {
        out.add(_InfoTile(icon: Icons.event_busy_outlined, text: noGamesLabel));
      } else {
        for (final ev in events) {
          out.add(Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: GameCard(
              event: ev,
              sport: feed.scores!.sport,
              leagueKey: feed.key,
              leagueName: name,
            ),
          ));
        }
      }
    }
  }
  return out;
}

class _FeedList extends ConsumerWidget {
  final List<LeagueFeed> feeds;
  const _FeedList({required this.feeds});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewingToday = ref.watch(viewDateProvider) == null;
    final hasFavs = ref.watch(favoriteTeamsProvider).isNotEmpty;
    // Favorites are a "my teams now" rail — shown only on the today view; a
    // browsed past/future date is a pure league slate.
    final showFavs = hasFavs && viewingToday;
    final filter = ref.watch(sportFilterProvider);

    if (feeds.isEmpty && !showFavs) {
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
        children.add(const _InfoTile(icon: Icons.hourglass_empty, text: 'Loading favorites…'));
      } else if (favData == null && async.hasError) {
        children.add(_InfoTile(icon: Icons.error_outline, text: '${async.error}'));
      } else {
        for (final f in favData ?? const <FavoriteTeamFeed>[]) {
          children.add(Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: FavoriteTeamCard(feed: f),
          ));
        }
      }
    }

    final sections = leagueSections(feeds,
        sportFilter: filter, noGamesLabel: viewingToday ? 'No games today' : 'No games');
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
    return ListView(physics: const AlwaysScrollableScrollPhysics(), children: children);
  }
}

int _statusRank(SportEvent e) {
  switch (e.main?.status.phase) {
    case 'live':
      return 0;
    case 'scheduled':
      return 1;
    case 'final':
      return 3;
    default:
      return 2;
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
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
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
        Expanded(child: Text(text, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13))),
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
  const GameCard({super.key, required this.event, required this.sport, required this.leagueKey, required this.leagueName});

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
            builder: (_) => GameDetailPage(event: event, sport: sport, leagueKey: leagueKey, leagueName: leagueName),
          )),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: comp.isField ? _field(context, comp) : _match(context, comp),
          ),
        ),
      ),
    );
  }

  /// Apple-Sports head-to-head row: each team is a crest with its name in small
  /// print underneath, pinned to the outer edge; the two big scores hug a
  /// centered status/time. One renderer, no per-sport branching — the
  /// discriminators (`scoreKind`, winner flags) decide what each slot reads.
  Widget _match(BuildContext context, Competition comp) {
    final a = comp.home ?? (comp.competitors.isNotEmpty ? comp.competitors[0] : null);
    final b = comp.away ?? (comp.competitors.length > 1 ? comp.competitors[1] : null);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: a == null ? const SizedBox() : _teamBlock(context, comp, a, alignEnd: false)),
        _scoreCluster(context, comp, a, b),
        Expanded(child: b == null ? const SizedBox() : _teamBlock(context, comp, b, alignEnd: true)),
      ],
    );
  }

  /// Outer team column: crest on top, short name in small print under it, record
  /// only on the upcoming slate (Apple shows it just for not-yet-played games).
  /// [alignEnd] mirrors the block for the right-hand team so its crest sits on
  /// the outer edge.
  Widget _teamBlock(BuildContext context, Competition comp, Competitor c, {required bool alignEnd}) {
    final cs = Theme.of(context).colorScheme;
    final dim = comp.status.isFinal && c.winner == false;
    final name = c.shortName?.isNotEmpty == true ? c.shortName! : c.displayName;
    final align = alignEnd ? TextAlign.right : TextAlign.left;
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Crest(url: c.logo, darkUrl: c.logoDark, fallback: c.abbreviation ?? c.displayName, size: 36),
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
  Widget _scoreCluster(BuildContext context, Competition comp, Competitor? a, Competitor? b) {
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
          ? Icon(Icons.check_circle, size: 22, color: BinanceColors.of(context).accent)
          : const SizedBox(width: 22);
    }
    final s = c.score?.display ?? '';
    if (s.isEmpty) return const SizedBox.shrink(); // scheduled → the time carries the row
    final dim = comp.status.isFinal && c.winner == false;
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
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
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
        return 'PENS';
      case 'aggregate':
        return 'AGG';
      case 'draw':
        return 'DRAW';
      case 'method':
        return comp.method?.kind;
      default:
        return null;
    }
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

