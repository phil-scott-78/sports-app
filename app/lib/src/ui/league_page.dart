import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import 'league_card.dart';
import 'poll.dart';
import 'widgets.dart';

void openLeaguePage(BuildContext context, String league, {String? name}) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => LeaguePage(league: league, name: name),
  ));
}

/// One league's slate — the same dense rows as a home-feed section, for ANY
/// league (followed or not), with a Follow pill in the header. The browse →
/// follow path: see today's games first, add to the feed if they earn it.
class LeaguePage extends ConsumerStatefulWidget {
  final String league;
  final String? name;
  const LeaguePage({super.key, required this.league, this.name});

  @override
  ConsumerState<LeaguePage> createState() => _LeaguePageState();
}

class _LeaguePageState extends ConsumerState<LeaguePage> with LifecyclePoll {
  // The league page is always today's slate (its own date navigation would
  // duplicate the Scores tab's strip — restraint).
  ScoresKey get _key => (league: widget.league, date: null);

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

  @override
  Duration? pollInterval() {
    final scores = ref.read(leagueScoresProvider(_key)).valueOrNull;
    if (scores == null) return null; // first load in flight
    if (scores.anyLive) return AppConfig.refreshLive;
    if (kickoffSoonMs(scores.nextStartMs)) return AppConfig.refreshNearKickoff;
    return AppConfig.refreshIdle;
  }

  @override
  void onPoll() => ref.invalidate(leagueScoresProvider(_key));

  @override
  void onForeground() => onPoll();

  /// Whether this league has a rankings feed (from the catalog's data-driven
  /// flag: 'polls' college / 'tour' ATP-WTA / 'divisions' UFC). Null-safe on a
  /// missing catalog (offline first paint) → no panel.
  bool get _hasRankings {
    final sports = ref.watch(catalogProvider).valueOrNull ?? const [];
    for (final s in sports) {
      for (final l in s.leagues) {
        if (l.key == widget.league) return l.rankings != null;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(leagueScoresProvider(_key), (_, __) => repace());
    final scores = ref.watch(leagueScoresProvider(_key));
    final followed = ref.watch(followedProvider).contains(widget.league);
    final title =
        (scores.valueOrNull?.leagueName ?? widget.name ?? widget.league)
            .toUpperCase();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: T.scrollBottom),
          children: [
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(6, 6, T.pageMargin, 0),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded,
                      size: 18, color: T.textDim),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.pageTitle.copyWith(fontSize: 24)),
                ),
                const SizedBox(width: 10),
                _FollowPill(
                  following: followed,
                  onTap: () =>
                      ref.read(followedProvider.notifier).toggle(widget.league),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            ...switch (scores) {
              AsyncData(:final value) => [
                  if (value.events.isEmpty)
                    const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: T.pageMargin),
                      child: HintCard('No games today.'),
                    )
                  else ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                          T.pageMargin, 0, T.pageMargin, 6),
                      child: Text(
                        '${value.events.length} game${value.events.length == 1 ? '' : 's'} today',
                        style: T.captionFaint,
                      ),
                    ),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: T.pageMargin),
                      child: LeagueEventsCard(
                          league: widget.league, scores: value),
                    ),
                  ],
                ],
              AsyncError() => const [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: T.pageMargin),
                    child: HintCard('Couldn’t load this league.'),
                  ),
                ],
              _ => const [
                  Padding(
                    padding: EdgeInsets.only(top: 100),
                    child: Center(
                        child: CircularProgressIndicator(color: T.gold)),
                  ),
                ],
            },
            if (_hasRankings) _RankingsSection(widget.league),
          ],
        ),
      ),
    );
  }
}

/// The league's rankings feed — ATP/WTA world rankings, UFC divisions, or the
/// college Top-25 polls, whichever the catalog says this league has. Poll chips
/// switch between lists (UFC ships P4P + every division).
class _RankingsSection extends ConsumerStatefulWidget {
  final String league;
  const _RankingsSection(this.league);

  @override
  ConsumerState<_RankingsSection> createState() => _RankingsSectionState();
}

class _RankingsSectionState extends ConsumerState<_RankingsSection> {
  int _poll = 0;

  @override
  Widget build(BuildContext context) {
    final rankings = ref.watch(rankingsProvider(widget.league)).valueOrNull;
    final polls = rankings?.polls ?? const <Poll>[];
    if (polls.isEmpty) return const SizedBox.shrink();
    final sel = polls[_poll.clamp(0, polls.length - 1)];

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: T.sectionHeaderPad,
        child: Text('RANKINGS', style: T.cardLabelFaint),
      ),
      if (polls.length > 1) ...[
        SizedBox(
          height: 34,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: T.pageMargin),
            scrollDirection: Axis.horizontal,
            itemCount: polls.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => _PollChip(
              label: polls[i].shortName.isNotEmpty
                  ? polls[i].shortName
                  : polls[i].name,
              selected: i == _poll,
              onTap: () => setState(() => _poll = i),
            ),
          ),
        ),
        const SizedBox(height: T.gapFirstCard),
      ],
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: T.pageMargin),
        child: _RankingsCard(sel),
      ),
    ]);
  }
}

class _PollChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PollChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: T.chipPad,
          decoration: BoxDecoration(
            color: selected ? T.invertedBg : T.surface,
            borderRadius: BorderRadius.circular(100),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? T.invertedText : T.textDim)),
        ),
      );
}

class _RankingsCard extends StatelessWidget {
  final Poll poll;
  const _RankingsCard(this.poll);

  static String _points(int p) => p.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');

  @override
  Widget build(BuildContext context) => V2Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: CardLabel(poll.name)),
            if (poll.occurrence != null && poll.occurrence!.isNotEmpty)
              Flexible(
                child: Text(poll.occurrence!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.captionFaint),
              ),
          ]),
          const SizedBox(height: 4),
          for (var i = 0; i < poll.ranks.length; i++) _row(poll.ranks[i], i),
        ]),
      );

  Widget _row(RankEntry r, int i) {
    final first = i == 0;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: i == 0
          ? null
          : const BoxDecoration(
              border: Border(top: BorderSide(color: T.divider))),
      child: Row(children: [
        SizedBox(
          width: 26,
          child: Text(r.champion ? 'C' : '${r.current ?? i + 1}',
              style: TextStyle(
                  fontFamily: 'BarlowCondensed',
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: first || r.champion ? T.gold : T.textDim)),
        ),
        Expanded(
          child: Text.rich(
            TextSpan(
              text: r.name,
              style: T.listText.copyWith(
                  fontWeight: first ? FontWeight.w600 : FontWeight.w400),
              children: [
                if (r.athlete?.country != null)
                  TextSpan(
                      text: '  ${r.athlete!.country}',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          color: T.textFaint)),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (r.trendDir != 'flat')
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(
              r.trendDir == 'up'
                  ? Icons.arrow_drop_up_rounded
                  : Icons.arrow_drop_down_rounded,
              size: 20,
              color: r.trendDir == 'up' ? T.green : T.live,
            ),
          ),
        Text(
          r.points != null ? _points(r.points!) : (r.record ?? ''),
          style: T.statLine.copyWith(color: T.textDim),
        ),
      ]),
    );
  }
}

class _FollowPill extends StatelessWidget {
  final bool following;
  final VoidCallback onTap;
  const _FollowPill({required this.following, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: following ? null : T.invertedBg,
            border:
                following ? Border.all(color: T.border, width: 1.5) : null,
            borderRadius: BorderRadius.circular(100),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (following) ...[
              const Icon(Icons.check_rounded, size: 14, color: T.gold),
              const SizedBox(width: 5),
            ],
            Text(following ? 'Following' : 'Follow',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: following ? T.textDim : T.invertedText)),
          ]),
        ),
      );
}
