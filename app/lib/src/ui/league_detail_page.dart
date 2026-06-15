import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../config.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import 'poll.dart';
import 'scores_page.dart' show GameCard;
import 'standings_page.dart';
import 'widgets.dart';

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
    return DefaultTabController(
      length: 2,
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
            tabs: const [Tab(text: 'Schedule'), Tab(text: 'Standings')],
          ),
        ),
        body: TabBarView(
          children: [
            _ScheduleTab(league: league, name: name),
            StandingsView(league: league),
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
  // Window: a week back, two weeks ahead — enough to see recent results and the
  // next fixtures for weekly leagues without an unbounded list.
  static const int _past = 7;
  static const int _future = 14;
  static const double _chipExtent = 48 + 6; // chip width + separator

  late final DateTime _today;
  late DateTime _selected;
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
    _selected = _today;
    // Open with today a couple of chips in from the left (recent days peeking).
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
              final day = _today.add(Duration(days: i - _past));
              return DateChip(
                date: day,
                selected: DateUtils.isSameDay(day, _selected),
                isToday: DateUtils.isSameDay(day, _today),
                onTap: () {
                  if (!DateUtils.isSameDay(day, _selected)) {
                    setState(() => _selected = day);
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
