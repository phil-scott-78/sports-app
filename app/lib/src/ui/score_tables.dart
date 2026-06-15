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

    // A column body (header over value cells) with NO intrinsic width — the caller
    // either flexes it to fill the row or pins it to a fixed width when scrolling.
    Widget colBody(String head, List<String> vals,
            {bool strong = false, Color? color}) =>
        Column(children: [
          cell(head, head: true),
          for (final v in vals) cell(v, strong: strong, color: color),
        ]);
    Widget fixedCol(String head, List<String> vals,
            {double width = 21, bool strong = false, Color? color}) =>
        SizedBox(
            width: width,
            child: colBody(head, vals, strong: strong, color: color));

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

    // Column header per period: numeric in regulation, then OT/2OT/3OT for extras
    // (grid mode only — baseball extra innings stay numbered). Hockey shootout: the
    // trailing extra of a "Final/SO" game reads "SO".
    final regCount = comp.periods.regulation;
    final soGame = comp.periods.unit == 'period' &&
        RegExp(r'\bSO\b', caseSensitive: false)
            .hasMatch('${comp.status.shortDetail ?? ''} ${comp.status.detail}');
    String colLabel(int i) {
      if (baseball || regCount <= 0 || i <= regCount) return '$i';
      if (soGame && i == cols) return 'SO';
      final extra = i - regCount;
      return extra == 1 ? 'OT' : '${extra}OT';
    }

    // Period region: fill the available width when the columns fit (so a 9-inning
    // / 4-quarter grid spreads across the card instead of hugging the left), else
    // pin each to a minimum and scroll. Baseball's floor is "12 innings fit" — past
    // that, extra innings scroll; grid sports (NBA/WNBA/CBB/hockey) fill to ~8.
    final periodRegion = LayoutBuilder(builder: (ctx, cons) {
      final avail = cons.maxWidth;
      final minW = baseball ? (avail / 12.0) : 28.0;
      final fits = cols * minW <= avail + 0.5;
      final bodies = [
        for (var i = 1; i <= cols; i++)
          colBody(colLabel(i), [for (final c in rows) _periodVal(c, i)]),
      ];
      if (fits) {
        return Row(children: [for (final b in bodies) Expanded(child: b)]);
      }
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final b in bodies) SizedBox(width: minW, child: b),
        ]),
      );
    });

    final accent = BinanceColors.of(context).accent;
    final summary = baseball
        ? Row(children: [
            fixedCol('R', [for (final c in rows) c.score?.display ?? ''],
                width: 24, strong: true, color: accent),
            fixedCol('H', [for (final c in rows) c.hits?.toString() ?? '']),
            fixedCol('E', [for (final c in rows) c.errors?.toString() ?? '']),
          ])
        : fixedCol('T', [for (final c in rows) c.score?.display ?? ''],
            width: 30, strong: true, color: accent);

    return DetailPanel(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Row(children: [
        teamCol,
        Expanded(child: periodRegion),
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

    // ESPN zero-fills each team's linescores with the OTHER team's innings as a
    // {runs:0, wickets:0, isBatting:false} placeholder — drop those phantoms. Then
    // show the real innings in chronological match order (period 1,2,3,4 → A1, B1,
    // A2, B2 / follow-on order), each tagged with its batting team.
    final innings = <(Competitor, PeriodScore)>[];
    for (final c in comp.competitors) {
      for (final p in c.periodScores) {
        final ck = p.cricket;
        if (ck == null) continue;
        final phantom = ck.isBatting != true && (ck.runs ?? 0) == 0 && (ck.wickets ?? 0) == 0;
        if (!phantom) innings.add((c, p));
      }
    }
    innings.sort((a, b) => a.$2.period.compareTo(b.$2.period));

    final lines = <Widget>[];
    if (innings.isEmpty) {
      // No per-innings linescores → fall back to the runs line (composite with
      // ESPN's "(overs, target)" parenthetical peeled off — see cricketScoreParts).
      for (final c in comp.competitors) {
        final parts = cricketScoreParts(c);
        if (parts.runs.isNotEmpty) {
          lines.add(_line(context, c.label, parts.runs, null, c.isWinner));
        }
      }
    } else {
      for (final (c, p) in innings) {
        final ck = p.cricket!;
        final overs = ck.overs == null ? '' : ' (${_overs(ck.overs!)} ov)';
        lines.add(_line(context, c.label, '${ck.rw}$overs', _reasonLabel(ck.reason), c.isWinner,
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

  /// Map ESPN's innings `reason` to a fan-readable tag: only "declared"→"dec" and
  /// "all out" earn a label; the routine "complete"/"target reached" are dropped.
  static String? _reasonLabel(String? reason) {
    switch (reason) {
      case 'declared':
        return 'dec';
      case 'all out':
        return 'all out';
      default:
        return null;
    }
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
