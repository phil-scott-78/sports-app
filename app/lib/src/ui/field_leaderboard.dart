import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import 'widgets.dart';

/// Golf leaderboard for a `field` competition: a frozen POS + PLAYER block on
/// the left, then a horizontally scrollable run of TO PAR | THRU | TODAY |
/// R1..Rn | TOT. Tuned for a 390px phone, dark-first, glance-first.
///
/// Row heights are fixed (header + rows) so the frozen columns and the
/// scrollable columns line up exactly — same idiom as [LineScoreTable].
class FieldLeaderboard extends StatelessWidget {
  final Competition comp;
  const FieldLeaderboard({super.key, required this.comp});

  // A round's score for a given period, or null when the player hasn't a line.
  PeriodScore? _round(Competitor c, int period) {
    for (final p in c.periodScores) {
      if (p.period == period) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final players = comp.competitors.take(120).toList();
    if (players.isEmpty) return const SizedBox.shrink();

    // Highest round number seen across the whole field → R1..Rn columns.
    final maxRound = players.fold<int>(
      0,
      (m, c) => c.periodScores.fold<int>(m, (mm, p) => p.period > mm ? p.period : mm),
    );

    // Ties: an order shared by more than one competitor renders as 'T{order}'.
    final orderCounts = <int, int>{};
    for (final c in players) {
      final o = c.order;
      if (o != null) orderCounts[o] = (orderCounts[o] ?? 0) + 1;
    }

    final curPeriod = comp.status.period;

    // ---- shared cell builders (fixed heights keep frozen/scroll aligned) ----
    const double headH = 20;
    const double rowH = 30;

    Widget headCell(String text, double width, {Alignment align = Alignment.center}) =>
        SizedBox(
          width: width,
          height: headH,
          child: Align(
            alignment: align,
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: numStyle(size: 11, weight: FontWeight.w600, color: cs.onSurfaceVariant),
            ),
          ),
        );

    Widget valCell(
      String text,
      double width, {
      Alignment align = Alignment.center,
      bool bold = false,
      Color? color,
    }) =>
        SizedBox(
          width: width,
          height: rowH,
          child: Align(
            alignment: align,
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: numStyle(
                size: 13,
                weight: bold ? FontWeight.w800 : FontWeight.w500,
                color: color ?? cs.onSurface,
              ),
            ),
          ),
        );

    // ---- frozen POS column --------------------------------------------------
    const double posW = 34;
    String posText(Competitor c) {
      final o = c.order;
      if (o == null) return '';
      final tied = (orderCounts[o] ?? 0) > 1;
      return tied ? 'T$o' : '$o';
    }

    final posColumn = SizedBox(
      width: posW,
      child: Column(
        children: [
          headCell('POS', posW, align: Alignment.centerLeft),
          for (final c in players)
            valCell(posText(c), posW,
                align: Alignment.centerLeft, color: cs.onSurfaceVariant),
        ],
      ),
    );

    // ---- frozen PLAYER column ----------------------------------------------
    const double playerW = 116;
    Widget playerCell(Competitor c) => SizedBox(
          width: playerW,
          height: rowH,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              c.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );

    final playerColumn = SizedBox(
      width: playerW,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          headCell('PLAYER', playerW, align: Alignment.centerLeft),
          for (final c in players) playerCell(c),
        ],
      ),
    );

    // ---- scrollable numeric columns ----------------------------------------
    Widget numColumn(
      String head,
      List<Widget> cells, {
      required double width,
    }) =>
        SizedBox(
          width: width,
          child: Column(
            children: [
              headCell(head, width),
              ...cells,
            ],
          ),
        );

    // TO PAR — the leader(s) carry the yellow accent; bold for everyone.
    const double toParW = 52;
    final toParCol = numColumn(
      'TO PAR',
      [
        for (final c in players)
          () {
            final d = c.score?.display ?? '';
            // Yellow stays scarce: only the leader(s) carry the accent; the rest
            // of the under-par column reads in confident body.
            final isLeader = c.order == 1;
            return valCell(d, toParW,
                bold: true, color: isLeader ? BinanceColors.of(context).accent : cs.onSurface);
          }(),
      ],
      width: toParW,
    );

    // THRU — holes done in the current round while live, else 'F'; '-' if none.
    const double thruW = 40;
    final thruCol = numColumn(
      'THRU',
      [
        for (final c in players)
          () {
            final r = _round(c, curPeriod);
            if (r == null) return valCell('-', thruW, color: cs.onSurfaceVariant);
            final hp = r.holesPlayed;
            final thru = (comp.status.live && hp != null && hp < 18) ? '$hp' : 'F';
            return valCell(thru, thruW,
                color: thru == 'F' ? cs.onSurfaceVariant : cs.onSurface);
          }(),
      ],
      width: thruW,
    );

    // TODAY — current round's to-par display.
    const double todayW = 48;
    final todayCol = numColumn(
      'TODAY',
      [
        for (final c in players)
          valCell(_round(c, curPeriod)?.display ?? '-', todayW),
      ],
      width: todayW,
    );

    // R1..Rn — each round's to-par display, blank when the player has no line.
    const double roundW = 40;
    final roundCols = <Widget>[
      for (var r = 1; r <= maxRound; r++)
        numColumn(
          'R$r',
          [
            for (final c in players)
              valCell(_round(c, r)?.display ?? '', roundW,
                  color: cs.onSurfaceVariant),
          ],
          width: roundW,
        ),
    ];

    // TOT — total strokes.
    const double totW = 46;
    final totCol = numColumn(
      'TOT',
      [
        for (final c in players)
          valCell(c.score?.strokes?.toInt().toString() ?? '', totW, bold: true),
      ],
      width: totW,
    );

    final scrollBlock = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        toParCol,
        thruCol,
        todayCol,
        ...roundCols,
        totCol,
      ],
    );

    final table = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        posColumn,
        playerColumn,
        const SizedBox(width: 4),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: scrollBlock,
          ),
        ),
      ],
    );

    return DetailPanel(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
      child: comp.meta?.hadPlayoff == true
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('PLAYOFF',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                          color: cs.onSurfaceVariant)),
                ),
              ),
              table,
            ])
          : table,
    );
  }
}
