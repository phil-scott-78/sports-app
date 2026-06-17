import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../config.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import 'poll.dart';
import 'rankings_page.dart';
import 'scores_page.dart' show GameCard;
import 'standings_page.dart';
import 'widgets.dart';

/// Leagues that publish a weekly AP/Coaches poll — the only ones that get a
/// Rankings tab. VERIFIED against live ESPN /rankings (other college sports
/// return no polls), so the tab count is static (no async churn, no wasted fetch).
const _rankedLeagues = {
  'football/college-football',
  'basketball/mens-college-basketball',
  'basketball/womens-college-basketball',
};

/// One league, two tabs: a date-scrollable **Schedule** (recent ← today →
/// upcoming) and the **Standings** table. Reached by tapping a row in the
/// Leagues list; the follow star lives in the app bar (and also stays on the
/// list row). The Schedule reuses the Scores [GameCard] and [DateChip] so the
/// two never drift.
class LeagueDetailPage extends ConsumerWidget {
  final String league;
  final String name;
  const LeagueDetailPage({super.key, required this.league, required this.name});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final followed = ref.watch(followedProvider).contains(league);
    final ranked = _rankedLeagues.contains(league);
    return DefaultTabController(
      length: ranked ? 3 : 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(name),
          actions: [
            IconButton(
              tooltip: followed ? 'Unfollow' : 'Follow',
              icon: Icon(followed ? Icons.star : Icons.star_border,
                  color: followed ? BinanceColors.of(context).accent : null),
              onPressed: () =>
                  ref.read(followedProvider.notifier).toggle(league),
            ),
          ],
          bottom: TabBar(
            labelColor: cs.onSurface,
            unselectedLabelColor: cs.onSurfaceVariant,
            // Neutral underline — the selected tab is structural chrome, not a
            // value moment, so it stays grey; brand yellow is reserved.
            indicatorColor: cs.onSurface,
            tabs: [
              const Tab(text: 'Schedule'),
              const Tab(text: 'Standings'),
              if (ranked) const Tab(text: 'Rankings'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ScheduleTab(league: league, name: name),
            StandingsView(league: league),
            if (ranked) RankingsView(league: league),
          ],
        ),
      ),
    );
  }
}

/// The Schedule tab: a horizontal date strip spanning a window around today, and
/// the league's games for the selected day. Selection is local state (one
/// screen, no need for a global provider); today is the default and is marked.
/// The selected day auto-refreshes when it has a live game (15s) or is today
/// (60s) — but only while foregrounded, on this tab, and at the top of the
/// navigation stack; past/future days and the Standings tab don't poll.
class _ScheduleTab extends ConsumerStatefulWidget {
  final String league;
  final String name;
  const _ScheduleTab({required this.league, required this.name});

  @override
  ConsumerState<_ScheduleTab> createState() => _ScheduleTabState();
}

class _ScheduleTabState extends ConsumerState<_ScheduleTab>
    with AutomaticKeepAliveClientMixin, LifecyclePoll {
  // Window: a week and a half back, three weeks ahead — recent results + the next
  // fixtures, dimming empty days. The strip's ANCHOR jumps a whole offseason to
  // the opener when needed (see _computeFocus), so this window stays modest.
  static const int _past = 10;
  static const int _future = 21;
  static const double _chipExtent = 48 + 6; // chip width + separator

  late final DateTime _today;

  /// The strip's centre. Normally today; in a deep offseason it jumps to the next
  /// game day (e.g. the NFL opener) so the strip lands where the games are.
  late DateTime _anchor;
  late DateTime _selected;
  bool _userPicked = false; // a manual chip tap freezes the auto-focus
  late final ScrollController _strip;
  TabController? _tab;
  bool _onTop = true; // false while a game detail is pushed over this screen

  @override
  bool get wantKeepAlive => true; // keep selection/scroll when switching tabs

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _today = DateTime(n.year, n.month, n.day);
    _anchor = _today;
    _selected = _today;
    // Open with the anchor a couple of chips in from the left (recent days peeking).
    _strip = ScrollController(initialScrollOffset: (_past - 1) * _chipExtent);
    attachPoll();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Pause the poll when the user is on the Standings tab; resume on Schedule.
    final tab = DefaultTabController.of(context);
    if (tab != _tab) {
      _tab?.removeListener(repace);
      _tab = tab;
      _tab?.addListener(repace);
    }
    // Depend on the modal scope so this re-fires when a game detail is pushed
    // over / popped off the schedule (pollInterval()'s gate alone wouldn't).
    _onTop = ModalRoute.of(context)?.isCurrent ?? true;
    repace();
  }

  @override
  void dispose() {
    _tab?.removeListener(repace);
    detachPoll();
    _strip.dispose();
    super.dispose();
  }

  String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}'
      '${d.month.toString().padLeft(2, '0')}'
      '${d.day.toString().padLeft(2, '0')}';

  LeagueDayKey get _key => (league: widget.league, date: _ymd(_selected));

  // Day at [offset] from the anchor, via the constructor (not Duration) so a DST
  // boundary can't drift the midnight across a date line.
  DateTime _dayAt(int offset) =>
      DateTime(_anchor.year, _anchor.month, _anchor.day + offset);

  DateTime _parseYmd(String s) => DateTime(int.parse(s.substring(0, 4)),
      int.parse(s.substring(4, 6)), int.parse(s.substring(6, 8)));

  // The range fetch key for the window centred on [anchor].
  LeagueRangeKey _rangeKey(DateTime anchor) => (
        league: widget.league,
        start: _ymd(DateTime(anchor.year, anchor.month, anchor.day - _past)),
        end: _ymd(DateTime(anchor.year, anchor.month, anchor.day + _future)),
      );

  // The today-centred window — the fixed-key signal the focus decision reads, so
  // it converges to one value and never loops as the anchor moves.
  LeagueRangeKey get _nearKey => _rangeKey(_today);

  /// The day the strip should focus on: today when it has games; else the nearest
  /// upcoming game day within the window; else (deep offseason) the next opener
  /// from ESPN's default slate — which hands back next season's games (NFL in June
  /// → September). Null while the inputs are still loading or nothing's upcoming.
  DateTime? _computeFocus() {
    final near = ref.watch(leagueScheduleDaysProvider(_nearKey)).valueOrNull;
    if (near == null) return null; // wait for the near window
    final todayKey = _ymd(_today);
    if (near.contains(todayKey)) return _today; // games today → stay put
    // YYYYMMDD sorts lexicographically → nearest upcoming game day in the window.
    String? best;
    for (final d in near) {
      if (d.compareTo(todayKey) > 0 &&
          (best == null || d.compareTo(best) < 0)) {
        best = d;
      }
    }
    if (best != null) return _parseYmd(best);
    // The whole window is empty → consult the default (date-less) slate, which in
    // an offseason returns the next opener. Watched ONLY here, so an in-season
    // league never pays for it.
    final slate = ref
        .watch(leagueDayScoresProvider((league: widget.league, date: null)))
        .valueOrNull;
    if (slate == null) return null;
    DateTime? far;
    for (final e in slate.events) {
      final s = e.start;
      if (s == null) continue;
      final day = DateTime(s.year, s.month, s.day);
      if (!day.isBefore(_today) && (far == null || day.isBefore(far))) {
        far = day;
      }
    }
    return far;
  }

  /// Apply the auto-focus unless the user has manually picked a day. The strip
  /// stays today-anchored when the focus day is within the window (it just selects
  /// + scrolls to it); only a deep-offseason focus beyond the window re-anchors the
  /// whole strip there. Deferred past the frame so the setState is legal;
  /// idempotent, so once it settles it stops firing.
  void _maybeAutoFocus() {
    if (_userPicked) return;
    final focus = _computeFocus();
    if (focus == null) return;
    final off = (DateUtils.dateOnly(focus)
                .difference(DateUtils.dateOnly(_today))
                .inHours /
            24)
        .round();
    final newAnchor = (off >= -_past && off <= _future) ? _today : focus;
    if (DateUtils.isSameDay(newAnchor, _anchor) &&
        DateUtils.isSameDay(focus, _selected)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _userPicked) return;
      setState(() {
        _anchor = newAnchor;
        _selected = focus;
      });
      _scrollToSelected();
      repace(); // the selected day changed → re-pace the poll
    });
  }

  void _scrollToSelected() {
    if (!_strip.hasClients) return;
    final days = (DateUtils.dateOnly(_selected)
                .difference(DateUtils.dateOnly(_anchor))
                .inHours /
            24)
        .round();
    final raw = ((_past + days - 2).clamp(0, _past + _future)) * _chipExtent;
    _strip.jumpTo(raw.clamp(0.0, _strip.position.maxScrollExtent));
  }

  // ---- polling --------------------------------------------------------------
  @override
  Duration? pollInterval() {
    if (!mounted || !_onTop) return null; // a game detail is pushed on top
    if ((_tab?.index ?? 0) != 0) return null; // Standings tab is showing
    if (ref.read(settingsProvider).baseUrl.trim().isEmpty) return null;
    final resp = ref.read(leagueDayScoresProvider(_key)).valueOrNull;
    if (resp?.anyLive == true) return AppConfig.refreshLive; // 15s
    if (DateUtils.isSameDay(_selected, _today)) {
      // Near a kickoff today → 30s so a tip-off isn't hidden for a full 60s idle
      // window; otherwise the 60s idle cadence.
      return kickoffSoonMs(resp?.nextStartMs)
          ? AppConfig.refreshNearKickoff
          : AppConfig.refreshIdle;
    }
    return null; // a past/future day with nothing live never changes
  }

  @override
  void onPoll() => ref.invalidate(leagueDayScoresProvider(_key));

  @override
  void onForeground() {
    if (DateUtils.isSameDay(_selected, _today)) {
      onPoll(); // catch up the live day
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAlive
    // Re-pace once a fetch settles: anyLive may have flipped (tip-off / final).
    ref.listen<AsyncValue<ScoresResponse>>(leagueDayScoresProvider(_key),
        (_, next) {
      if (!next.isLoading) repace();
    });
    // Land the strip where the games are (today, the next game day, or — in a
    // deep offseason — the opener months out), unless the user has picked a day.
    _maybeAutoFocus();
    // Empty-day dimming for the visible (anchored) window. Null while loading →
    // nothing dims.
    final daySet =
        ref.watch(leagueScheduleDaysProvider(_rangeKey(_anchor))).valueOrNull;
    return Column(
      children: [
        SizedBox(
          height: 58,
          child: ListView.separated(
            controller: _strip,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            itemCount: _past + 1 + _future,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (context, i) {
              final day = _dayAt(i - _past);
              return DateChip(
                date: day,
                selected: DateUtils.isSameDay(day, _selected),
                isToday: DateUtils.isSameDay(day, _today),
                dimmed: daySet != null && !daySet.contains(_ymd(day)),
                onTap: () {
                  if (!DateUtils.isSameDay(day, _selected)) {
                    setState(() {
                      _selected = day;
                      _userPicked =
                          true; // freeze auto-focus on an explicit pick
                    });
                    repace(); // new day → new cadence (today/live vs static)
                  }
                },
              );
            },
          ),
        ),
        Expanded(child: _dayGames()),
      ],
    );
  }

  Widget _dayGames() {
    final key = _key;
    return ref.watch(leagueDayScoresProvider(key)).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            const SizedBox(height: 80),
            ErrorView(
                message: '$e',
                onRetry: () => ref.invalidate(leagueDayScoresProvider(key))),
          ]),
          data: (resp) {
            final events = [...resp.events]..sort(_byStart);
            if (events.isEmpty) {
              return ListView(children: [
                const SizedBox(height: 80),
                EmptyState(
                  icon: Icons.event_busy_outlined,
                  title: 'No games',
                  subtitle: DateFormat.yMMMMEEEEd().format(_selected),
                ),
              ]);
            }
            return RefreshIndicator(
              onRefresh: () => ref.refresh(leagueDayScoresProvider(key).future),
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: events.length + 1,
                itemBuilder: (context, i) {
                  if (i == events.length) return const SizedBox(height: 12);
                  final ev = events[i];
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: GameCard(
                      event: ev,
                      sport: resp.sport,
                      leagueKey: widget.league,
                      leagueName: resp.leagueName.isNotEmpty
                          ? resp.leagueName
                          : widget.name,
                    ),
                  );
                },
              ),
            );
          },
        );
  }
}

/// Schedule reads chronologically: earliest kickoff first, undated events last.
int _byStart(SportEvent a, SportEvent b) {
  final ta = a.start, tb = b.start;
  if (ta == null && tb == null) return 0;
  if (ta == null) return 1;
  if (tb == null) return -1;
  return ta.compareTo(tb);
}
