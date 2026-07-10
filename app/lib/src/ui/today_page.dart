import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import 'league_card.dart';
import 'league_page.dart';
import 'poll.dart';
import 'widgets.dart';

void openTodayPage(BuildContext context) {
  Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TodayPage()));
}

/// Every league with games on today, followed or not — one section per league,
/// the same dense rows as the home feed. Reached from the home feed's quiet
/// "All games today" row. Which leagues qualify comes from the season pulse
/// (the ~70-league curated set [exploreOverviewProvider] already classifies);
/// each qualifying league's slate is then the ordinary scores fetch, so within
/// the pulse's ttl the slates are cache hits. Sections fill in as slates land —
/// the page never gates on the slowest league.
class TodayPage extends ConsumerStatefulWidget {
  const TodayPage({super.key});
  @override
  ConsumerState<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends ConsumerState<TodayPage> with LifecyclePoll {
  @override
  void initState() {
    super.initState();
    attachPoll();
    WidgetsBinding.instance.addPostFrameCallback((_) => repace());
  }

  @override
  void dispose() {
    detachPoll();
    super.dispose();
  }

  /// Pulse keys with games on today, live leagues first. The pulse is
  /// session-scoped, so this list is stable across the poll loop — only the
  /// slates refresh.
  List<String> _active() {
    final pulse =
        ref.read(exploreOverviewProvider).valueOrNull ?? const <String, LeagueStateInfo>{};
    final keys = [
      for (final info in pulse.values)
        if (info.live || info.state == 'today') info.key,
    ]..sort((a, b) {
        final la = pulse[a]!.live ? 0 : 1;
        final lb = pulse[b]!.live ? 0 : 1;
        return la != lb ? la.compareTo(lb) : a.compareTo(b);
      });
    return keys;
  }

  @override
  Duration? pollInterval() {
    final pulse = ref.read(exploreOverviewProvider).valueOrNull;
    if (pulse == null) return null; // pulse still landing
    final live = [
      for (final k in _active())
        if (ref
                .read(mergedLeagueScoresProvider((league: k, date: null)))
                .valueOrNull
                ?.anyLive ??
            pulse[k]?.live == true)
          k,
    ];
    if (live.isEmpty) return AppConfig.refreshIdle;
    // Every live league push-fed and healthy → the poll is only reconciliation.
    final demoted = live.every((k) {
      final s = ref.read(liveSlateProvider(k));
      return s.hasValue && !s.hasError;
    });
    return demoted ? AppConfig.refreshReconcile : AppConfig.refreshLive;
  }

  @override
  void onPoll() {
    for (final k in _active()) {
      ref.invalidate(leagueScoresProvider((league: k, date: null)));
    }
  }

  @override
  void onForeground() => onPoll();

  @override
  Widget build(BuildContext context) {
    ref.listen(exploreOverviewProvider, (_, __) => repace());
    final pulse = ref.watch(exploreOverviewProvider);
    final active = _active();
    // Re-pace on any active league's slate change — poll rounds AND push
    // overlay emissions / health transitions (repace keeps the running timer
    // when the cadence is unchanged, so this is cheap at push rates).
    for (final k in active) {
      ref.listen(
          mergedLeagueScoresProvider((league: k, date: null)), (_, __) => repace());
    }
    final settled = pulse.valueOrNull != null;
    final liveCount = [
      for (final k in active)
        if (pulse.valueOrNull?[k]?.live == true) k,
    ].length;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: T.scrollBottom),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, T.pageMargin, 0),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded,
                      size: 18, color: T.textDim),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: Text('ALL GAMES',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.pageTitle.copyWith(fontSize: 24)),
                ),
              ]),
            ),
            if (settled && active.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(T.pageMargin, 2, T.pageMargin, 0),
                child: Text(
                  '${active.length} league${active.length == 1 ? '' : 's'} on today'
                  '${liveCount > 0 ? ' · $liveCount live' : ''}',
                  style: T.captionFaint,
                ),
              ),
            if (!settled && active.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 100),
                child: Center(child: CircularProgressIndicator(color: T.gold)),
              )
            else if (settled && active.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(T.pageMargin, 22, T.pageMargin, 0),
                child: HintCard('No games on today across the leagues.'),
              )
            else
              for (final key in active) _LeagueSection(key),
          ],
        ),
      ),
    );
  }
}

/// One league's section: header (name + "See all N", tapping through to the
/// league page) over the shared dense-rows card. Renders nothing until the
/// slate lands, and nothing at all for an empty slate — the pulse said "today"
/// but the day already emptied out; a blank section is noise here (this page
/// lists what's ON, unlike the home feed where a followed league keeps its
/// place).
class _LeagueSection extends ConsumerWidget {
  final String league;
  const _LeagueSection(this.league);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scores = ref
        .watch(mergedLeagueScoresProvider((league: league, date: null)))
        .valueOrNull;
    if (scores == null || scores.events.isEmpty) return const SizedBox.shrink();
    return Column(children: [
      InkWell(
        onTap: () => openLeaguePage(context, league, name: scores.leagueName),
        child: Padding(
          padding: T.sectionHeaderPad,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(scores.leagueName.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.sectionTitle),
              ),
              Text('See all ${scores.events.length}', style: T.captionFaint),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded,
                  size: 16, color: T.textFaint),
            ],
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: T.pageMargin),
        child: LeagueEventsCard(league: league, scores: scores),
      ),
    ]);
  }
}
