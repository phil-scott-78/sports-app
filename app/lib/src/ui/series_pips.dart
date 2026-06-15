import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';

/// A glanceable playoff-series state: each side's won games as filled pips out of
/// the clinch number (best-of-N). Reads "who's about to advance" faster than the
/// prose "CAR leads series 3-2". CHEAP — from competition.series (scoreboard),
/// which we used to flatten to a string and discard. Away-left / home-right to
/// match the card + hero order.
class SeriesPips extends StatelessWidget {
  final Competition comp;

  /// dense = the compact card strip; otherwise the roomier detail-hero variant.
  final bool dense;
  const SeriesPips({super.key, required this.comp, this.dense = false});

  static bool has(Competition comp) => comp.meta?.series?.isPlayoff ?? false;

  @override
  Widget build(BuildContext context) {
    final s = comp.meta?.series;
    if (s == null || !s.isPlayoff) return const SizedBox.shrink();
    final a =
        comp.away ?? (comp.competitors.isNotEmpty ? comp.competitors.first : null);
    final b =
        comp.home ?? (comp.competitors.length > 1 ? comp.competitors[1] : null);
    if (a == null || b == null) return const SizedBox.shrink();

    final need = s.gamesToWin;
    final aWins = s.wins(a.id);
    final bWins = s.wins(b.id);
    final cs = Theme.of(context).colorScheme;
    final ext = BinanceColors.of(context);
    // The side that clinched gets the warm victor accent (a value moment); the
    // rest stays neutral so filled-vs-empty carries the read.
    final aFill = (s.completed && aWins >= need) ? ext.victor : cs.onSurface;
    final bFill = (s.completed && bWins >= need) ? ext.victor : cs.onSurface;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(a.label, style: _abbr(cs, aWins >= bWins)),
        SizedBox(width: dense ? 6 : 8),
        _pips(context, aWins, need, aFill),
        SizedBox(width: dense ? 10 : 14),
        _pips(context, bWins, need, bFill, fillFromRight: true),
        SizedBox(width: dense ? 6 : 8),
        Text(b.label, style: _abbr(cs, bWins >= aWins)),
      ],
    );
  }

  TextStyle _abbr(ColorScheme cs, bool leads) => TextStyle(
        fontSize: dense ? 10.5 : 12,
        fontWeight: leads ? FontWeight.w800 : FontWeight.w600,
        color: cs.onSurfaceVariant,
      );

  /// `need` dots, `wins` of them filled. By default filled dots sit on the left
  /// (toward a left-hand abbr); [fillFromRight] mirrors them for the right team
  /// so each side's filled pips hug its own abbreviation.
  Widget _pips(BuildContext context, int wins, int need, Color fill,
      {bool fillFromRight = false}) {
    final cs = Theme.of(context).colorScheme;
    final d = dense ? 5.0 : 7.0;
    final dots = [
      for (var i = 0; i < need; i++)
        Padding(
          padding: EdgeInsets.symmetric(horizontal: dense ? 1.5 : 2),
          child: Container(
            width: d,
            height: d,
            decoration: BoxDecoration(
              color: (i < wins) ? fill : Colors.transparent,
              shape: BoxShape.circle,
              border: (i < wins) ? null : Border.all(color: cs.outline, width: 1),
            ),
          ),
        ),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: fillFromRight ? dots.reversed.toList() : dots,
    );
  }
}
