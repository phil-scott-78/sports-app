import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import '../util.dart';
import 'follow_sheet.dart';
import 'game_detail_page.dart';
import 'hero_card.dart';
import 'poll.dart';
import 'settings_page.dart';
import 'widgets.dart';

/// The home feed: TODAY header, stacked favorite hero cards, then one dense
/// section per followed league.
class ScoresPage extends ConsumerStatefulWidget {
  const ScoresPage({super.key});
  @override
  ConsumerState<ScoresPage> createState() => _ScoresPageState();
}

class _ScoresPageState extends ConsumerState<ScoresPage> with LifecyclePoll {
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
    if (ref.read(tabIndexProvider) != 0) return null;
    final feeds = ref.read(feedProvider).valueOrNull;
    final favs = ref.read(favoritesFeedProvider).valueOrNull;
    final anyLive = (feeds ?? []).any((f) => f.scores?.anyLive == true) ||
        (favs ?? []).any((f) => f.card?.anyLive == true);
    if (anyLive) return AppConfig.refreshLive;
    final soon = (feeds ?? [])
        .any((f) => kickoffSoonMs(f.scores?.nextStartMs));
    if (soon) return AppConfig.refreshNearKickoff;
    return AppConfig.refreshIdle;
  }

  @override
  void onPoll() {
    ref.invalidate(feedProvider);
    ref.invalidate(favoritesFeedProvider);
  }

  @override
  void onForeground() => onPoll();

  @override
  Widget build(BuildContext context) {
    // Re-pace whenever the data (live state) or active tab changes.
    ref.listen(feedProvider, (_, __) => repace());
    ref.listen(tabIndexProvider, (_, __) => repace());

    final feeds = ref.watch(feedProvider);
    final favs = ref.watch(favoritesFeedProvider);

    return RefreshIndicator(
      color: T.gold,
      backgroundColor: T.surface,
      onRefresh: () async {
        onPoll();
        await ref.read(feedProvider.future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          const _TodayHeader(),
          ...switch (favs) {
            AsyncData(:final value) => [
                for (final f in value)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        T.pageMargin, 10, T.pageMargin, 0),
                    child: FavoriteHeroCard(f),
                  ),
              ],
            _ => const <Widget>[],
          },
          ...switch (feeds) {
            AsyncData(:final value) => _leagueSections(value),
            AsyncError(:final error) => [_feedError('$error')],
            _ => [
                if (feeds.valueOrNull == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 120),
                    child: Center(
                        child: CircularProgressIndicator(color: T.gold)),
                  ),
              ],
          },
        ],
      ),
    );
  }

  List<Widget> _leagueSections(List<LeagueFeed> feeds) {
    final out = <Widget>[];
    var empty = true;
    for (final f in feeds) {
      final scores = f.scores;
      if (scores == null) {
        out.add(_leagueErrorSection(f));
        continue;
      }
      if (scores.events.isEmpty) continue;
      empty = false;
      out.add(_SectionHeader(scores));
      out.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: T.pageMargin),
        child: _LeagueCard(feed: f),
      ));
    }
    if (out.isEmpty || empty && out.length < feeds.length) {
      if (out.isEmpty) {
        out.add(const Padding(
          padding: EdgeInsets.fromLTRB(T.pageMargin, 24, T.pageMargin, 0),
          child: HintCard(
              'No games today in your leagues.\nManage what you follow in the Following tab.'),
        ));
      }
    }
    return out;
  }

  Widget _leagueErrorSection(LeagueFeed f) => Padding(
        padding: const EdgeInsets.fromLTRB(T.pageMargin, 22, T.pageMargin, 0),
        child: V2Card(
          radius: T.rowCardRadius,
          padding: const EdgeInsets.all(14),
          child: Text('${f.key} — couldn’t load',
              style: T.caption.copyWith(color: T.textFaint)),
        ),
      );

  Widget _feedError(String message) => Padding(
        padding: const EdgeInsets.fromLTRB(T.pageMargin, 24, T.pageMargin, 0),
        child: HintCard(message),
      );
}

class _TodayHeader extends ConsumerWidget {
  const _TodayHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
        padding: const EdgeInsets.fromLTRB(T.pageMargin, 14, T.pageMargin, 0),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('TODAY', style: T.pageTitle),
              const SizedBox(height: 3),
              Text(todayLabel(DateTime.now()), style: T.caption),
            ]),
          ),
          _CircleButton(
            icon: Icons.settings_outlined,
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsPage())),
          ),
        ]),
      );
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration:
              const BoxDecoration(color: T.surface, shape: BoxShape.circle),
          child: Icon(icon, size: 18, color: T.textDim),
        ),
      );
}

class _SectionHeader extends StatelessWidget {
  final ScoresResponse scores;
  const _SectionHeader(this.scores);

  @override
  Widget build(BuildContext context) {
    var title = scores.leagueName.toUpperCase();
    // Tack the round onto tournament headers ('WORLD CUP · ROUND OF 16').
    final rounds = scores.events
        .map((e) => e.main?.meta?.round)
        .whereType<String>()
        .toSet();
    if (rounds.length == 1) title = '$title · ${rounds.first.toUpperCase()}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(T.pageMargin, 22, T.pageMargin, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: T.sectionTitle),
          ),
          Text('${scores.events.length} game${scores.events.length == 1 ? '' : 's'}',
              style: T.captionFaint),
        ],
      ),
    );
  }
}

class _LeagueCard extends StatelessWidget {
  final LeagueFeed feed;
  const _LeagueCard({required this.feed});

  @override
  Widget build(BuildContext context) {
    final scores = feed.scores!;
    final events = scores.events;
    return Container(
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(T.rowCardRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (var i = 0; i < events.length; i++)
          _EventRow(
            league: feed.key,
            event: events[i],
            divider: i > 0,
          ),
      ]),
    );
  }
}

/// One dense row in a league card: two team lines + status column, plus the
/// cheap live extras the scoreboard already carries (mini diamond, possession,
/// red cards, series pips, shootout).
class _EventRow extends ConsumerWidget {
  final String league;
  final SportEvent event;
  final bool divider;
  const _EventRow({
    required this.league,
    required this.event,
    required this.divider,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comp = event.main;
    if (comp == null) return const SizedBox.shrink();
    final body = comp.isField ? _fieldRow(comp) : _h2hRow(comp);
    final series = comp.meta?.series;

    return InkWell(
      onTap: () => openGameDetail(context, league, event),
      onLongPress: comp.isField || comp.competitorKind != 'team'
          ? null
          : () => showGameFollowSheet(context, league: league, comp: comp),
      child: Container(
        decoration: divider
            ? const BoxDecoration(
                border: Border(top: BorderSide(color: T.divider)))
            : null,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: body,
          ),
          if (series != null && series.isPlayoff)
            Container(
              padding: const EdgeInsets.fromLTRB(14, 9, 14, 12),
              decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: T.divider))),
              child: Row(children: [
                if (comp.meta?.round != null) ...[
                  Text(comp.meta!.round!.toUpperCase(),
                      style: T.cardLabelFaint.copyWith(fontSize: 11)),
                  const SizedBox(width: 8),
                ],
                SeriesPips(series: series, comp: comp),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(comp.meta?.seriesSummary ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.captionFaint),
                ),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _h2hRow(Competition comp) {
    final away = comp.away ??
        (comp.competitors.isNotEmpty ? comp.competitors.first : null);
    final home = comp.home ??
        (comp.competitors.length > 1 ? comp.competitors[1] : null);
    final lead = leadingSide(comp);
    return Row(children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (away != null)
              _teamLine(comp, away, dim: lead != null && lead != away),
            const SizedBox(height: 5),
            if (home != null)
              _teamLine(comp, home, dim: lead != null && lead != home),
          ],
        ),
      ),
      const SizedBox(width: 10),
      _StatusColumn(event: event, comp: comp),
    ]);
  }

  Widget _teamLine(Competition comp, Competitor c, {required bool dim}) {
    final showScore =
        !comp.status.isScheduled && (c.score?.display.isNotEmpty ?? false);
    final textColor = dim ? T.textDim : T.text;
    final side = c == comp.home ? 'home' : 'away';
    final reds = comp.redCardsBySide[side] ?? 0;
    final possession = comp.status.live &&
        comp.situation?.possession != null &&
        comp.situation!.possession == c.id;
    return Row(children: [
      ColorBar(teamColor(c)),
      const SizedBox(width: 8),
      Flexible(
        child: Text(
          c.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 14,
              fontWeight: dim ? FontWeight.w400 : FontWeight.w600,
              color: textColor),
        ),
      ),
      if (c.rank != null) ...[
        const SizedBox(width: 5),
        Text('${c.rank}', style: T.captionFaint.copyWith(fontSize: 10)),
      ],
      if (showScore) ...[
        const SizedBox(width: 8),
        Text.rich(
          TextSpan(
            text: c.score!.display,
            children: [
              if (c.shootoutScore != null)
                TextSpan(
                    text: ' (${c.shootoutScore!.toStringAsFixed(0)})',
                    style: TextStyle(
                        fontSize: 13,
                        color: dim ? T.textDim : T.textDim)),
            ],
          ),
          style: T.rowScore.copyWith(color: textColor),
        ),
      ],
      if (possession) ...[
        const SizedBox(width: 6),
        const PossessionArrow(color: T.textDim, size: 10),
      ],
      if (reds > 0) ...[
        const SizedBox(width: 6),
        const RedCardGlyph(height: 10),
      ],
    ]);
  }

  /// Field events (golf, racing, athletics) get a single title line + leader.
  Widget _fieldRow(Competition comp) {
    final sorted = List.of(comp.competitors)
      ..sort((a, b) => (a.order ?? 1 << 20).compareTo(b.order ?? 1 << 20));
    final leader = sorted.isEmpty ? null : sorted.first;
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(event.shortName.isNotEmpty ? event.shortName : event.name,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: T.rowText),
          if (leader != null) ...[
            const SizedBox(height: 4),
            Text(
              '${leader.shortName ?? leader.displayName}'
              '${leader.score != null ? ' · ${leader.score!.display}' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.captionFaint,
            ),
          ],
        ]),
      ),
      const SizedBox(width: 10),
      _StatusColumn(event: event, comp: comp),
    ]);
  }
}

class _StatusColumn extends StatelessWidget {
  final SportEvent event;
  final Competition comp;
  const _StatusColumn({required this.event, required this.comp});

  @override
  Widget build(BuildContext context) {
    final s = comp.status;
    final sit = comp.situation;
    final mini = s.live && sit != null && sit.hasBaseball
        ? MiniDiamond(
            onFirst: sit.onFirst ?? false,
            onSecond: sit.onSecond ?? false,
            onThird: sit.onThird ?? false,
          )
        : null;

    final context2 = _contextLine();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (mini != null) ...[mini, const SizedBox(width: 10)],
      Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (s.live) ...[const LiveDot(), const SizedBox(width: 6)],
            Text(statusLine(comp, event),
                style: TextStyle(
                    fontSize: 12,
                    color: s.isFinal || s.isScheduled ? T.textFaint : T.text)),
          ]),
          if (context2 != null) ...[
            const SizedBox(height: 2),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(context2,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.captionFaint),
            ),
          ],
        ],
      ),
    ]);
  }

  String? _contextLine() {
    final s = comp.status;
    final sit = comp.situation;
    if (s.live && sit != null) {
      final bits = <String>[
        if (sit.outs != null) '${sit.outs} out',
        if (sit.balls != null && sit.strikes != null)
          '${sit.balls}–${sit.strikes}',
        if (sit.downDistanceText != null) sit.downDistanceText!,
      ];
      if (bits.isNotEmpty) return bits.take(2).join(' · ');
    }
    if (s.isScheduled) {
      final probables = [
        ...?comp.away?.probables.map((p) => p.athlete.split(' ').last),
        ...?comp.home?.probables.map((p) => p.athlete.split(' ').last),
      ];
      if (probables.length == 2) {
        return '${probables[0]} vs ${probables[1]}';
      }
      if (event.broadcasts.isNotEmpty) return event.broadcasts.first;
    }
    if (s.isFinal && comp.competitors.any((c) => c.advance == true)) {
      final adv = comp.competitors.firstWhere((c) => c.advance == true);
      return '${adv.label} advance';
    }
    return null;
  }
}
