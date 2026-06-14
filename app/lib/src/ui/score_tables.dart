import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import 'widgets.dart';

// Away on top, home on bottom — the universal box-score convention.
List<Competitor> _awayHome(Competition comp) {
  final away = comp.away, home = comp.home;
  if (away != null && home != null) return [away, home];
  return comp.competitors.take(2).toList();
}

String _periodVal(Competitor c, int period) {
  for (final p in c.periodScores) {
    if (p.period == period) {
      return p.display.isNotEmpty ? p.display : '${p.value ?? ''}';
    }
  }
  return ''; // unplayed inning renders blank, not 0
}

int _maxPeriod(Competition comp) => comp.competitors.fold<int>(
      0,
      (m, c) => c.periodScores.fold<int>(m, (mm, p) => p.period > mm ? p.period : mm),
    );

/// Line score with a frozen team column and pinned summary columns.
///
/// - baseball mode: innings (1..9, extra innings scroll) + pinned **R / H / E**.
/// - grid mode: periods + Total, frozen team column, fits 390px (ready for the
///   summary-tier quarter/period splits of NBA/NFL/NHL).
class LineScoreTable extends StatelessWidget {
  final Competition comp;
  final bool baseball;
  const LineScoreTable({super.key, required this.comp, this.baseball = false});

  @override
  Widget build(BuildContext context) {
    final rows = _awayHome(comp);
    if (rows.length < 2) return const SizedBox.shrink();
    final maxP = _maxPeriod(comp);
    if (maxP == 0) return const SizedBox.shrink();
    // baseball always shows the full regulation slate (9), extras extend it.
    final cols = (baseball && comp.periods.regulation > maxP)
        ? comp.periods.regulation
        : maxP;
    final cs = Theme.of(context).colorScheme;

    Widget cell(String text, {bool head = false, bool strong = false, Color? color}) =>
        SizedBox(
          height: head ? 22 : 28,
          child: Center(
            child: Text(
              text,
              maxLines: 1,
              style: numStyle(
                size: head ? 11 : 14,
                weight: strong
                    ? FontWeight.w800
                    : (head ? FontWeight.w600 : FontWeight.w500),
                color: color ?? (head ? cs.onSurfaceVariant : cs.onSurface),
              ),
            ),
          ),
        );

    Widget column(String head, List<String> vals,
            {double width = 21, bool strong = false, Color? color}) =>
        SizedBox(
          width: width,
          child: Column(children: [
            cell(head, head: true),
            for (final v in vals) cell(v, strong: strong, color: color),
          ]),
        );

    final teamCol = SizedBox(
      width: 52,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        cell('', head: true),
        for (final c in rows)
          SizedBox(
            height: 28,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(c.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ),
      ]),
    );

    final periodCols = Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 1; i <= cols; i++)
        column('$i', [for (final c in rows) _periodVal(c, i)]),
    ]);

    final accent = BinanceColors.of(context).accent;
    final summary = baseball
        ? Row(children: [
            column('R', [for (final c in rows) c.score?.display ?? ''],
                width: 24, strong: true, color: accent),
            column('H', [for (final c in rows) c.hits?.toString() ?? '']),
            column('E', [for (final c in rows) c.errors?.toString() ?? '']),
          ])
        : column('T', [for (final c in rows) c.score?.display ?? ''],
            width: 30, strong: true, color: accent);

    return DetailPanel(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Row(children: [
        teamCol,
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: periodCols,
          ),
        ),
        const SizedBox(width: 4),
        summary,
      ]),
    );
  }
}

/// Cricket: a vertical stack of innings as `runs/wkts (overs)`, the way the
/// score is actually read. No horizontal scroll, no frozen column.
class InningsStack extends StatelessWidget {
  final Competition comp;
  const InningsStack({super.key, required this.comp});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lines = <Widget>[];
    for (final c in comp.competitors) {
      final innings = c.periodScores.where((p) => p.cricket != null).toList();
      if (innings.isEmpty) {
        // fall back to the composite score string when per-innings is absent
        if (c.score?.display.isNotEmpty == true) {
          lines.add(_line(context, c.label, c.score!.display, null, c.isWinner));
        }
        continue;
      }
      for (final p in innings) {
        final ck = p.cricket!;
        final overs = ck.overs == null ? '' : ' (${_overs(ck.overs!)} ov)';
        final reason = ck.allOut == true
            ? 'all out'
            : ck.declared == true
                ? 'dec'
                : ck.reason;
        lines.add(_line(context, c.label, '${ck.rw}$overs', reason, c.isWinner,
            batting: ck.isBatting == true));
      }
    }
    if (lines.isEmpty) return const SizedBox.shrink();
    return DetailPanel(
      child: Column(children: [
        for (var i = 0; i < lines.length; i++) ...[
          if (i > 0) Divider(height: 12, color: cs.outlineVariant.withValues(alpha: 0.4)),
          lines[i],
        ],
      ]),
    );
  }

  static String _overs(num o) => o == o.roundToDouble() ? o.toInt().toString() : o.toString();

  Widget _line(BuildContext context, String team, String rw, String? note, bool winner,
      {bool batting = false}) {
    final cs = Theme.of(context).colorScheme;
    return Row(children: [
      if (batting)
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Icon(Icons.sports_cricket, size: 14, color: BinanceColors.of(context).accent),
        ),
      Expanded(
        child: Text(team,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontWeight: winner ? FontWeight.w700 : FontWeight.w500, fontSize: 14)),
      ),
      if (note != null && note.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text(note, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ),
      Text(rw, style: numStyle(size: 15, weight: FontWeight.w800)),
    ]);
  }
}

/// Tennis: set-by-set scoreline with a frozen name column, winning sets bold,
/// and a sets-won tally on the right.
class SetStrip extends StatelessWidget {
  final Competition comp;
  const SetStrip({super.key, required this.comp});

  @override
  Widget build(BuildContext context) {
    final rows = comp.competitors.take(2).toList();
    if (rows.length < 2) return const SizedBox.shrink();
    final maxP = _maxPeriod(comp);
    if (maxP == 0) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;

    int setsWon(Competitor c) =>
        c.periodScores.where((p) => p.setWinner == true).length;

    Widget setCell(Competitor c, int set) {
      PeriodScore? ps;
      for (final p in c.periodScores) {
        if (p.period == set) ps = p;
      }
      final games = ps == null ? '' : (ps.value?.toInt().toString() ?? ps.display);
      final won = ps?.setWinner == true;
      return SizedBox(
        width: 24,
        child: Center(
          child: Text(games,
              style: numStyle(
                size: 15,
                weight: won ? FontWeight.w800 : FontWeight.w500,
                color: won ? cs.onSurface : cs.onSurfaceVariant,
              )),
        ),
      );
    }

    Widget row(Competitor c) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Expanded(
              child: Text(c.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontWeight: c.isWinner ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 14)),
            ),
            for (var s = 1; s <= maxP; s++) setCell(c, s),
            const SizedBox(width: 6),
            SizedBox(
              width: 20,
              child: Center(
                child: Text('${setsWon(c)}',
                    style: numStyle(size: 15, weight: FontWeight.w800)),
              ),
            ),
          ]),
        );

    return DetailPanel(
      child: Column(children: [row(rows[0]), row(rows[1])]),
    );
  }
}
