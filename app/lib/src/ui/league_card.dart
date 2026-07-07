import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import '../util.dart';
import 'follow_sheet.dart';
import 'game_detail_page.dart';
import 'situations.dart';
import 'widgets.dart';

/// One league's slate as a dense card of game rows — shared by the home feed
/// sections and the league page.
class LeagueEventsCard extends StatelessWidget {
  final String league;
  final ScoresResponse scores;

  /// The day this slate came from ('YYYYMMDD'), or null for today — forwarded to
  /// game detail so a past/future game re-resolves from its own day's slate.
  final String? date;
  const LeagueEventsCard(
      {super.key, required this.league, required this.scores, this.date});

  @override
  Widget build(BuildContext context) {
    final events = scores.events;
    return Container(
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(T.rowCardRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (var i = 0; i < events.length; i++)
          LeagueEventRow(
            league: league,
            event: events[i],
            divider: i > 0,
            date: date,
          ),
      ]),
    );
  }
}

/// One dense row in a league card: two team lines + status column, plus the
/// cheap live extras the scoreboard already carries (mini diamond, possession,
/// red cards, series pips, shootout).
class LeagueEventRow extends StatelessWidget {
  final String league;
  final SportEvent event;
  final bool divider;
  final String? date;
  const LeagueEventRow({
    super.key,
    required this.league,
    required this.event,
    required this.divider,
    this.date,
  });

  @override
  Widget build(BuildContext context) {
    final comp = event.main;
    if (comp == null) return const SizedBox.shrink();
    final body = comp.isField ? _fieldRow(comp) : _h2hRow(comp);
    final series = comp.meta?.series;

    return InkWell(
      onTap: () => openGameDetail(context, league, event, date: date),
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
            padding: T.padDenseRow,
            child: body,
          ),
          if (series != null && series.isPlayoff)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 14),
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
    // A 2-row table with an intrinsic-width label column: Flutter sizes that
    // column to the wider abbreviation, so both scores start in the same column
    // and line up — 'SD 5' over 'BAL 2' instead of two ragged columns. (Doing
    // this by measuring text is unreliable while the web font is still loading.)
    return Row(children: [
      Expanded(
        child: Table(
          columnWidths: const {
            0: IntrinsicColumnWidth(),
            1: FlexColumnWidth(),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            if (away != null)
              _teamRow(comp, away, dim: lead != null && lead != away),
            if (away != null && home != null)
              const TableRow(children: [
                SizedBox(height: 5),
                SizedBox(height: 5),
              ]),
            if (home != null)
              _teamRow(comp, home, dim: lead != null && lead != home),
          ],
        ),
      ),
      const SizedBox(width: 10),
      _StatusColumn(event: event, comp: comp),
    ]);
  }

  TableRow _teamRow(Competition comp, Competitor c, {required bool dim}) {
    final showScore =
        !comp.status.isScheduled && (c.score?.display.isNotEmpty ?? false);
    final textColor = dim ? T.textDim : T.text;
    final side = c == comp.home ? 'home' : 'away';
    // Cards are a live/for-the-record signal — never on a scheduled row (a
    // stale timeline on a not-yet-started fixture must not paint a red card).
    final reds = comp.status.isScheduled ? 0 : comp.redCardsBySide[side] ?? 0;
    final possession = comp.status.live &&
        comp.situation?.possession != null &&
        comp.situation!.possession == c.id;
    final powerPlay = comp.status.live &&
        (comp.situation?.hasPowerPlay ?? false) &&
        comp.situation?.strengthTeam == c.id;
    return TableRow(children: [
      // col 0 — color bar + label (intrinsic; shared width across both rows).
      // The trailing 8px is the gap to the score and rides in the column width.
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
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
        ]),
      ),
      // col 1 — rank, score, and the cheap live badges, hugging the label.
      Row(children: [
        if (c.rank != null) ...[
          Text('${c.rank}', style: T.captionFaint.copyWith(fontSize: 10)),
          const SizedBox(width: 5),
        ],
        if (showScore)
          Text.rich(
            TextSpan(
              text: c.score!.display,
              children: [
                if (c.shootoutScore != null)
                  TextSpan(
                      text: ' (${c.shootoutScore!.toStringAsFixed(0)})',
                      style: const TextStyle(fontSize: 13, color: T.textDim)),
              ],
            ),
            style: T.rowScore.copyWith(color: textColor),
          ),
        if (possession) ...[
          const SizedBox(width: 6),
          const PossessionArrow(color: T.textDim, size: 10),
        ],
        if (reds > 0) ...[
          const SizedBox(width: 6),
          const RedCardGlyph(height: 10),
        ],
        if (powerPlay) ...[
          const SizedBox(width: 6),
          const TagBadge('PP'),
        ],
      ]),
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
    if (s.live) {
      if (sit != null) {
        final bits = <String>[
          if (sit.outs != null) '${sit.outs} out',
          if (sit.balls != null && sit.strikes != null)
            '${sit.balls}–${sit.strikes}',
          if (sit.downDistanceText != null) sit.downDistanceText!,
        ];
        if (bits.isNotEmpty) return bits.take(2).join(' · ');
      }
      // Soccer/rugby: man-down or the latest goal, off the cheap timeline.
      final match = matchRowContext(comp);
      if (match != null) return match;
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
