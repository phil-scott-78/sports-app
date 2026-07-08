import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import 'league_card.dart';
import 'poll.dart';
import 'rankings_page.dart';
import 'tournament_page.dart';
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
                _BracketButton(widget.league, name: title),
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
              // Only reached on a COLD failure — a transient poll error is served
              // from cache (stale-while-revalidate) and keeps the last good slate.
              // So this is the "no cached frame" case: a quiet tap-to-retry.
              AsyncError() => [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: T.pageMargin),
                    child: GestureDetector(
                      onTap: () => ref.invalidate(leagueScoresProvider(_key)),
                      child: const HintCard(
                          'Couldn’t load this league — tap to retry.'),
                    ),
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

/// The league's rankings feed — a compact teaser of the primary poll (ATP/WTA
/// tour, first UFC division, or the top college poll, whichever the catalog
/// says this league has): top 5 rows + a "See all" row that pushes the full
/// [RankingsPage] (every poll/division, untruncated).
class _RankingsSection extends ConsumerWidget {
  final String league;
  const _RankingsSection(this.league);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rankings = ref.watch(rankingsProvider(league)).valueOrNull;
    final polls = rankings?.polls ?? const <Poll>[];
    if (polls.isEmpty) return const SizedBox.shrink();
    final primary = polls.first;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: T.sectionHeaderPad,
        child: Text('RANKINGS', style: T.cardLabelFaint),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: T.pageMargin),
        child: RankingsCard(
          primary,
          maxRows: 5,
          onSeeAll: () =>
              openRankingsPage(context, league, name: primary.name),
        ),
      ),
    ]);
  }
}

/// The header "Bracket" affordance — shown only for leagues that both look like
/// a tournament (cheap profile gate) AND whose tournament data resolves
/// non-empty. Opens the [TournamentPage] for the whole league. Data-gated so it
/// never appears for a plain-table league or an out-of-season cup.
class _BracketButton extends ConsumerWidget {
  final String league;
  final String? name;
  const _BracketButton(this.league, {this.name});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!leagueHasTournamentView(league)) return const SizedBox.shrink();
    final key = (league: league, window: null, grouping: null, eventId: null);
    final t = ref.watch(tournamentProvider(key)).valueOrNull;
    if (t == null || t.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: () => openLeagueTournamentPage(context, league, name: name),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            border: Border.all(color: T.border, width: 1.5),
            borderRadius: BorderRadius.circular(100),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.account_tree_outlined, size: 14, color: T.textDim),
            SizedBox(width: 5),
            Text('Bracket',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: T.textDim)),
          ]),
        ),
      ),
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
