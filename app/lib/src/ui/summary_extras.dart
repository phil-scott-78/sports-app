// Detail-page widgets for the /summary enrichments that ride the same payload we
// already fetch: a passive win-probability bar, a pre-game "key absences" list, a
// one-line season series, and the expand-to-view full play-by-play. All calm and
// optional — each caller gates on presence so an absent field shows nothing.

import 'package:flutter/material.dart';
import '../models.dart';
import 'summary_feed.dart';
import 'widgets.dart';

/// Parse an ESPN bare-hex team color ('1d428a' or '#1d428a') to a Color; null if
/// unusable so the caller can fall back to a theme color.
Color? hexColor(String? s) {
  if (s == null) return null;
  var h = s.trim().replaceAll('#', '');
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

/// A passive two-sided win-probability bar (ESPN analytic — not a betting line).
/// One stacked bar split away|home with the % on each end. Rendered only on a
/// LIVE game (the meaningful case); pre-game has no arc, a final is already decided.
class WinProbBar extends StatelessWidget {
  final WinProbability wp;
  final String awayAbbr, homeAbbr;
  final String? awayColor, homeColor;
  const WinProbBar({
    super.key,
    required this.wp,
    required this.awayAbbr,
    required this.homeAbbr,
    this.awayColor,
    this.homeColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final aCol = hexColor(awayColor) ?? cs.primary;
    final hCol = hexColor(homeColor) ?? cs.tertiary;
    final aw = wp.away.clamp(0, 100);
    final hm = wp.home.clamp(0, 100);
    // Flex weights; guard the degenerate 0/0 so the Row still lays out.
    final aFlex = (aw == 0 && hm == 0) ? 1 : aw;
    final hFlex = (aw == 0 && hm == 0) ? 1 : hm;
    // The favoured side reads stronger; the trailing side steps back — the
    // glance answers "who's winning this" before the numbers do.
    Widget end(String abbr, int pct, Color col, bool right, bool leads) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!right) ...[
              _dot(col),
              const SizedBox(width: 6)
            ],
            Text(right ? '$pct%  $abbr' : '$abbr  $pct%',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: leads ? FontWeight.w800 : FontWeight.w600,
                    color: leads ? cs.onSurface : cs.onSurfaceVariant)),
            if (right) ...[const SizedBox(width: 6), _dot(col)],
          ],
        );
    return DetailPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              end(awayAbbr, aw, aCol, false, aw >= hm),
              end(homeAbbr, hm, hCol, true, hm >= aw),
            ],
          ),
          const SizedBox(height: 8),
          Stack(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 8,
                child: Row(children: [
                  Expanded(flex: aFlex, child: ColoredBox(color: aCol)),
                  Expanded(flex: hFlex, child: ColoredBox(color: hCol)),
                ]),
              ),
            ),
            // Hairline tick at 50% — the coin-flip mark the arc is read against.
            Positioned.fill(
              child: Center(
                child: Container(width: 2, color: cs.surface),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _dot(Color c) => Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle));
}

/// Pre-game "key absences" — the structured injury list from /summary (comments
/// dropped upstream). Compact: a few names per side, "+N more" beyond a cap.
class KeyAbsences extends StatelessWidget {
  final List<TeamInjuries> injuries;
  static const int _cap = 4;
  const KeyAbsences({super.key, required this.injuries});

  static bool has(List<TeamInjuries> inj) =>
      inj.any((t) => t.items.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final blocks = injuries.where((t) => t.items.isNotEmpty).toList();
    return DetailPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var b = 0; b < blocks.length; b++) ...[
            if (b > 0) const SizedBox(height: 10),
            Text(blocks[b].abbr ?? '',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            for (final it in blocks[b].items.take(_cap))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        [it.name, if (it.pos != null) '(${it.pos})']
                            .join(' '),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(it.line,
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            if (blocks[b].items.length > _cap)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('+${blocks[b].items.length - _cap} more',
                    style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                        fontStyle: FontStyle.italic)),
              ),
          ],
        ],
      ),
    );
  }
}

/// The season head-to-head as one quiet line ('Series tied 1-1').
class SeasonSeriesLine extends StatelessWidget {
  final SeasonSeries series;
  const SeasonSeriesLine({super.key, required this.series});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DetailPanel(
      child: Row(children: [
        Icon(Icons.compare_arrows, size: 16, color: cs.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
            child: Text(series.summary,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

/// The scoring feed by default with a tap-to-expand into the FULL play-by-play.
/// Keeps the glance calm (only scoring shows) while the firehose is one tap away.
class ExpandablePlayByPlay extends StatefulWidget {
  final List<SummaryPlay> scoring; // condensed (default)
  final List<SummaryPlay> all; // full PBP (revealed on expand)
  final String sport;
  final String? nowLabel;
  const ExpandablePlayByPlay({
    super.key,
    required this.scoring,
    required this.all,
    required this.sport,
    this.nowLabel,
  });

  @override
  State<ExpandablePlayByPlay> createState() => _ExpandablePlayByPlayState();
}

class _ExpandablePlayByPlayState extends State<ExpandablePlayByPlay> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final plays = _expanded ? widget.all : widget.scoring;
    // When there's no condensed layer (basketball: every score is a basket), the
    // button toggles the full feed outright rather than "scoring ↔ all".
    final hasCondensed = widget.scoring.isNotEmpty;
    final label = _expanded
        ? (hasCondensed ? 'Show scoring only' : 'Hide play-by-play')
        : (hasCondensed ? 'Show all plays' : 'Show play-by-play');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (plays.isNotEmpty)
          ScoringFeed(plays: plays, sport: widget.sport, nowLabel: widget.nowLabel),
        SizedBox(height: plays.isNotEmpty ? 6 : 0),
        Align(
          alignment: Alignment.center,
          child: TextButton.icon(
            onPressed: () => setState(() => _expanded = !_expanded),
            icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                size: 18),
            label: Text(label,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            style: TextButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
