import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import 'follow_sheet.dart';
import 'player_page.dart';
import 'team_page.dart';
import 'widgets.dart';

/// Open the full rankings page for [league] — every poll/division the feed
/// carries (college Top-25 polls / ATP-WTA tour / UFC divisions), each a full
/// [RankingsCard]. Pushed from the league page's compact teaser ("See all").
/// `name` seeds the header before the fetch resolves (mirrors [openTeamPage]).
void openRankingsPage(BuildContext context, String league, {String? name}) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => RankingsPage(league: league, name: name),
  ));
}

/// The full rankings feed for one league. One [RankingsCard] per poll,
/// stacked — no picker needed at full-page width; the league page's teaser
/// is the compact, single-poll view. Title comes off the primary poll's own
/// name (AP Top 25 / ATP Rankings / …), falling back to the seeded [name]
/// while the fetch is in flight.
class RankingsPage extends ConsumerWidget {
  final String league;
  final String? name;
  const RankingsPage({super.key, required this.league, this.name});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rankings = ref.watch(rankingsProvider(league));
    final polls = rankings.valueOrNull?.polls ?? const <Poll>[];
    final title = polls.isNotEmpty
        ? polls.first.name.toUpperCase()
        : (name?.toUpperCase() ?? 'RANKINGS');

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
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.pageTitle.copyWith(fontSize: 24)),
                ),
              ]),
            ),
            const SizedBox(height: T.gapFirstCard),
            ...switch (rankings) {
              AsyncData(:final value) => [
                  if (value.polls.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: T.pageMargin),
                      child: HintCard('No rankings right now.'),
                    )
                  else
                    for (var i = 0; i < value.polls.length; i++)
                      Padding(
                        padding: EdgeInsets.fromLTRB(T.pageMargin,
                            i == 0 ? 0 : T.gapCard, T.pageMargin, 0),
                        child: RankingsCard(value.polls[i], league: league),
                      ),
                ],
              AsyncError() => const [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: T.pageMargin),
                    child: HintCard('Couldn’t load rankings.'),
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
          ],
        ),
      ),
    );
  }
}

/// One poll/division: `CardLabel` name + occurrence header, then rank rows
/// (rank number, name, movement caret, record/points). Shared by the full
/// [RankingsPage] (one per poll, untruncated) and the league page's compact
/// teaser (pass [maxRows] + [onSeeAll] for a trailing "See all" row).
class RankingsCard extends StatelessWidget {
  final Poll poll;

  /// When set, rank rows become actionable: tap opens the entry's team/player
  /// page, long-press on a team entry opens the follow sheet. Null → inert
  /// rows (widget tests, contexts without a league key).
  final String? league;
  final int? maxRows;
  final VoidCallback? onSeeAll;
  const RankingsCard(this.poll,
      {super.key, this.league, this.maxRows, this.onSeeAll});

  static String _points(int p) => p.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');

  @override
  Widget build(BuildContext context) {
    final truncated = maxRows != null && poll.ranks.length > maxRows!;
    final shown =
        truncated ? poll.ranks.take(maxRows!).toList() : poll.ranks;
    return V2Card(
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
        for (var i = 0; i < shown.length; i++) _row(context, shown[i], i),
        if (truncated) _seeAllRow(),
      ]),
    );
  }

  Widget _row(BuildContext context, RankEntry r, int i) {
    final first = i == 0;
    final body = Container(
      padding: const EdgeInsets.symmetric(vertical: T.rowVPad),
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
    if (league == null) return body;
    final team = r.team;
    final athlete = r.athlete;
    if (team != null) {
      return InkWell(
        onTap: () => openTeamPage(context, league!,
            teamId: team.id, name: team.name, color: team.color),
        onLongPress: () => showTeamFollowSheet(
          context,
          league: league!,
          teamId: team.id,
          name: team.name,
          abbr: team.abbr,
          colorHex: team.color,
          record: r.record,
        ),
        child: body,
      );
    }
    if (athlete != null) {
      return InkWell(
        onTap: () =>
            openPlayerPage(context, league!, athleteId: athlete.id, name: athlete.name),
        child: body,
      );
    }
    return body;
  }

  Widget _seeAllRow() => GestureDetector(
        onTap: onSeeAll,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: T.rowVPad),
          decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: T.divider))),
          child: Row(children: [
            Expanded(
              child: Text('See all ${poll.ranks.length}',
                  style: T.listText.copyWith(
                      color: T.textDim, fontWeight: FontWeight.w600)),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: T.textFaint),
          ]),
        ),
      );
}
