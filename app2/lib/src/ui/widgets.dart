import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import '../util.dart';

// ═══════════════════════════ containers ═══════════════════════════

/// The standard dark card (bg #1A1E25, radius 20, padding 18).
class V2Card extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final bool bordered;
  const V2Card({
    super.key,
    required this.child,
    this.padding,
    this.radius = T.cardRadius,
    this.bordered = false,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding ?? T.cardPad,
        decoration: BoxDecoration(
          color: T.surface,
          borderRadius: BorderRadius.circular(radius),
          border: bordered ? Border.all(color: T.divider) : null,
        ),
        child: child,
      );
}

/// The inverted light card — LAST PLAY / LAST BALL / RACE CALL. The one loud
/// moment on an otherwise dark screen.
class InvertedCard extends StatelessWidget {
  final String label;
  final String text;
  const InvertedCard({super.key, required this.label, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: T.cardPad,
        decoration: BoxDecoration(
          color: T.invertedBg,
          borderRadius: BorderRadius.circular(T.cardRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(),
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.88,
                    color: T.invertedLabel)),
            const SizedBox(height: 8),
            Text(text, style: T.invertedProse),
          ],
        ),
      );
}

/// Small-caps label at the top of a card ('WIN PROBABILITY').
class CardLabel extends StatelessWidget {
  final String text;
  const CardLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: T.cardLabel);
}

/// Dashed-border hint card ('Long-press any team to add it here').
class HintCard extends StatelessWidget {
  final String text;
  const HintCard(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: T.border, width: 1.5),
          borderRadius: BorderRadius.circular(T.rowCardRadius),
        ),
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: T.textFaint)),
      );
}

// ═══════════════════════════ atoms ═══════════════════════════

/// The 6px live dot.
class LiveDot extends StatelessWidget {
  final double size;
  const LiveDot({super.key, this.size = 6});
  @override
  Widget build(BuildContext context) => Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: T.live, shape: BoxShape.circle));
}

/// Status pill — dark rounded pill, optional live dot ('BOT 7 · 2 OUT').
class StatusPill extends StatelessWidget {
  final String text;
  final bool live;
  const StatusPill(this.text, {super.key, this.live = false});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
            color: T.surface, borderRadius: BorderRadius.circular(100)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (live) ...[const LiveDot(), const SizedBox(width: 7)],
          Text(text.toUpperCase(), style: T.pillText),
        ]),
      );
}

/// Rounded team-color identity bar. The design's signature glyph.
class ColorBar extends StatelessWidget {
  final Color color;
  final double width, height, radius;
  const ColorBar(this.color,
      {super.key, this.width = 5, this.height = 16, this.radius = 2});
  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(radius)),
      );
}

/// Small solid tag badge ('PP 1:24', '10 MEN').
class TagBadge extends StatelessWidget {
  final String text;
  final Color bg, fg;
  const TagBadge(this.text,
      {super.key, this.bg = T.gold, this.fg = T.invertedText});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: fg)),
      );
}

/// Possession triangle (points toward the score, i.e. right-to-left row flow).
class PossessionArrow extends StatelessWidget {
  final Color color;
  final double size;
  const PossessionArrow({super.key, this.color = T.textDim, this.size = 10});
  @override
  Widget build(BuildContext context) => CustomPaint(
      size: Size(size * 0.8, size), painter: _TrianglePainter(color));
}

class _TrianglePainter extends CustomPainter {
  final Color color;
  _TrianglePainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()
      ..moveTo(size.width, size.height / 2)
      ..lineTo(0, 0)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TrianglePainter old) => old.color != color;
}

/// Tiny red-card glyph (a vertical red rectangle).
class RedCardGlyph extends StatelessWidget {
  final double height;
  const RedCardGlyph({super.key, this.height = 10});
  @override
  Widget build(BuildContext context) => Container(
        width: height * 0.7,
        height: height,
        decoration: BoxDecoration(
            color: T.live, borderRadius: BorderRadius.circular(1.5)),
      );
}

// ═══════════════════════════ chip nav ═══════════════════════════

/// Horizontal pill chips — selected chip is inverted (light on dark).
class ChipNav extends StatelessWidget {
  final List<String> items;
  final int selected;
  final ValueChanged<int> onTap;
  final EdgeInsetsGeometry padding;
  const ChipNav({
    super.key,
    required this.items,
    required this.selected,
    required this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: T.pageMargin),
  });

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: padding,
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              _Chip(
                  label: items[i],
                  selected: i == selected,
                  onTap: () => onTap(i)),
            ]
          ],
        ),
      );
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? T.invertedBg : null,
            border: selected ? null : Border.all(color: T.border, width: 1.5),
            borderRadius: BorderRadius.circular(100),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? T.invertedText : T.textDim)),
        ),
      );
}

// ═══════════════════════════ score block ═══════════════════════════

/// One row of the giant score block: color bar, shouting team name, score.
/// The trailing side dims when [dim] (the side that's behind / lost).
class ScoreBlockRow extends StatelessWidget {
  final Competitor competitor;
  final bool dim;
  final bool possession;
  final bool showScore;
  final Widget? badge;
  const ScoreBlockRow(this.competitor,
      {super.key,
      this.dim = false,
      this.possession = false,
      this.showScore = true,
      this.badge});

  @override
  Widget build(BuildContext context) {
    final color = dim ? T.textDim : T.text;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: T.border, width: 2))),
      child: Row(
        children: [
          ColorBar(teamColor(competitor), width: 12, height: 44, radius: 3),
          const SizedBox(width: 12),
          Flexible(
            // Long names (SOUTH AFRICA) scale down rather than truncate.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(blockName(competitor),
                  maxLines: 1, style: T.blockName.copyWith(color: color)),
            ),
          ),
          if (badge != null) ...[const SizedBox(width: 10), badge!],
          if (possession) ...[
            const SizedBox(width: 10),
            PossessionArrow(color: color, size: 12),
          ],
          const Spacer(),
          if (showScore) _score(color),
        ],
      ),
    );
  }

  Widget _score(Color color) {
    final display = competitor.score?.display ?? '';
    final so = competitor.shootoutScore;
    // Long cricket-style scores ('168/6') shrink a step so the row holds.
    final style = T.blockScore
        .copyWith(color: color, fontSize: display.length > 3 ? 44 : 52);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(display, style: style),
        if (so != null)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text('(${so.toStringAsFixed(0)})',
                style: T.statLineStrong.copyWith(color: T.textDim)),
          ),
      ],
    );
  }
}

/// The condensed one-line scorebug ('MIL 4  CHC 5 · Bot 7').
class Scorebug extends StatelessWidget {
  final Competition comp;
  const Scorebug(this.comp, {super.key});

  @override
  Widget build(BuildContext context) {
    final away = comp.away ?? (comp.competitors.isNotEmpty ? comp.competitors.first : null);
    final home = comp.home ??
        (comp.competitors.length > 1 ? comp.competitors[1] : null);
    Widget side(Competitor? c) {
      if (c == null) return const SizedBox.shrink();
      final leading = _leadingSide(comp);
      final dim = leading != null && leading != c;
      final score = comp.status.isScheduled ? '' : c.score?.display ?? '';
      return Row(mainAxisSize: MainAxisSize.min, children: [
        ColorBar(teamColor(c), width: 8, height: 22),
        const SizedBox(width: 7),
        Text('${c.label} $score'.trim(),
            style: T.bugScore.copyWith(color: dim ? T.textDim : T.text)),
      ]);
    }

    return Row(children: [
      side(away),
      const SizedBox(width: 12),
      side(home),
      const Spacer(),
      Text(comp.status.shortDetail ?? comp.status.detail, style: T.caption),
      if (comp.status.live) ...[
        const SizedBox(width: 8),
        const LiveDot(size: 7),
      ],
    ]);
  }
}

/// The side currently ahead (for dimming the trailing side), or null when tied
/// or scores aren't numeric. Finals dim by `winner` instead.
Competitor? _leadingSide(Competition comp) {
  final cs = comp.competitors;
  if (cs.length != 2) return null;
  if (comp.status.isFinal) {
    for (final c in cs) {
      if (c.isWinner) return c;
    }
    return null;
  }
  final a = cs[0].score?.value, b = cs[1].score?.value;
  if (a == null || b == null || a == b) return null;
  return a > b ? cs[0] : cs[1];
}

Competitor? leadingSide(Competition comp) => _leadingSide(comp);

// ═══════════════════════════ bars & pips ═══════════════════════════

/// Two-color proportional bar (win probability, possession).
class SplitBar extends StatelessWidget {
  final double leftFraction;
  final Color left, right;
  final double height;
  const SplitBar({
    super.key,
    required this.leftFraction,
    required this.left,
    required this.right,
    this.height = 12,
  });

  @override
  Widget build(BuildContext context) {
    final f = leftFraction.clamp(0.02, 0.98);
    return SizedBox(
      height: height,
      child: Row(children: [
        Expanded(
          flex: (f * 1000).round(),
          child: Container(
              decoration: BoxDecoration(
                  color: left,
                  borderRadius: BorderRadius.circular(height / 2))),
        ),
        const SizedBox(width: 2),
        Expanded(
          flex: ((1 - f) * 1000).round(),
          child: Container(
              decoration: BoxDecoration(
                  color: right,
                  borderRadius: BorderRadius.circular(height / 2))),
        ),
      ]),
    );
  }
}

/// Playoff-series pips: one dot per game in team colors, hollow for unplayed.
class SeriesPips extends StatelessWidget {
  final SeriesInfo series;
  final Competition comp;
  final double size;
  const SeriesPips({super.key, required this.series, required this.comp, this.size = 8});

  @override
  Widget build(BuildContext context) {
    final cs = comp.competitors;
    if (cs.length < 2) return const SizedBox.shrink();
    final a = cs[0], b = cs[1];
    final aWins = series.wins(a.id), bWins = series.wins(b.id);
    final played = aWins + bWins;
    final total = series.total ?? played;
    // Alternate colors in win order isn't knowable; show a's wins then b's,
    // then hollow dots for the games left in a possible full series.
    final dots = <Widget>[
      for (var i = 0; i < aWins; i++) _dot(teamColor(a)),
      for (var i = 0; i < bWins; i++) _dot(teamColor(b)),
      for (var i = played; i < total; i++) _hollow(),
    ];
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < dots.length; i++) ...[
        if (i > 0) const SizedBox(width: 3),
        dots[i],
      ]
    ]);
  }

  Widget _dot(Color c) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle));

  Widget _hollow() => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: T.outline, width: 1.5)),
      );
}

/// N filled dots out of [total] ('OUTS' dots, timeouts).
class DotRow extends StatelessWidget {
  final int filled, total;
  final Color color;
  final double size;
  const DotRow({
    super.key,
    required this.filled,
    required this.total,
    this.color = T.text,
    this.size = 10,
  });

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < total; i++) ...[
            if (i > 0) const SizedBox(width: 5),
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                  color: i < filled ? color : T.border,
                  shape: BoxShape.circle),
            ),
          ]
        ],
      );
}

// ═══════════════════════════ baseball diamond ═══════════════════════════

/// The bases diamond, in the design's 128×112 geometry: outlined diamond path,
/// gold squares for occupied bases, dark squares for empty, home plate small.
class BaseballDiamond extends StatelessWidget {
  final bool onFirst, onSecond, onThird;
  final double width;
  const BaseballDiamond({
    super.key,
    required this.onFirst,
    required this.onSecond,
    required this.onThird,
    this.width = 110,
  });

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(width, width * 112 / 128),
        painter: _DiamondPainter(onFirst, onSecond, onThird),
      );
}

class _DiamondPainter extends CustomPainter {
  final bool on1, on2, on3;
  _DiamondPainter(this.on1, this.on2, this.on3);

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 128, sy = size.height / 112;
    Offset pt(double x, double y) => Offset(x * sx, y * sy);
    final home = pt(64, 98), first = pt(112, 54), second = pt(64, 12), third = pt(16, 54);

    final line = Paint()
      ..color = T.diamondLine
      ..strokeWidth = 3 * sx
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(home.dx, home.dy)
      ..lineTo(first.dx, first.dy)
      ..lineTo(second.dx, second.dy)
      ..lineTo(third.dx, third.dy)
      ..close();
    canvas.drawPath(path, line);

    void base(Offset c, bool occupied, double side) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(0.785398); // 45°
      final r = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: side, height: side),
          Radius.circular(3 * sx));
      if (occupied) {
        canvas.drawRRect(r, Paint()..color = T.gold);
      } else {
        canvas.drawRRect(r, Paint()..color = T.track);
        canvas.drawRRect(
            r,
            Paint()
              ..color = T.outline
              ..strokeWidth = 2.5 * sx
              ..style = PaintingStyle.stroke);
      }
      canvas.restore();
    }

    base(first, on1, 18 * sx);
    base(second, on2, 18 * sx);
    base(third, on3, 18 * sx);
    base(home, false, 16 * sx); // home plate, never "occupied"
  }

  @override
  bool shouldRepaint(_DiamondPainter old) =>
      old.on1 != on1 || old.on2 != on2 || old.on3 != on3;
}

/// The tiny 3-base diamond used inline in rows/scorebugs (26×22 geometry).
class MiniDiamond extends StatelessWidget {
  final bool onFirst, onSecond, onThird;
  final double width;
  const MiniDiamond({
    super.key,
    required this.onFirst,
    required this.onSecond,
    required this.onThird,
    this.width = 24,
  });

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(width, width * 22 / 26),
        painter: _MiniDiamondPainter(onFirst, onSecond, onThird),
      );
}

class _MiniDiamondPainter extends CustomPainter {
  final bool on1, on2, on3;
  _MiniDiamondPainter(this.on1, this.on2, this.on3);

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 26, sy = size.height / 22;
    void base(double cx, double cy, bool occupied) {
      canvas.save();
      canvas.translate(cx * sx, cy * sy);
      canvas.rotate(0.785398);
      final r = RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset.zero, width: 7 * sx, height: 7 * sx),
          Radius.circular(1.5 * sx));
      if (occupied) {
        canvas.drawRRect(r, Paint()..color = T.gold);
      } else {
        canvas.drawRRect(
            r,
            Paint()
              ..color = T.outline
              ..strokeWidth = 1.5 * sx
              ..style = PaintingStyle.stroke);
      }
      canvas.restore();
    }

    base(21.5, 10.5, on1); // first
    base(13, 4.5, on2); // second
    base(4.5, 10.5, on3); // third
  }

  @override
  bool shouldRepaint(_MiniDiamondPainter old) =>
      old.on1 != on1 || old.on2 != on2 || old.on3 != on3;
}

// ═══════════════════════════ list rows ═══════════════════════════

/// A key–value stat row inside a card ('Hoerner 2B    4 2 0' style):
/// name (+detail) left, condensed stat line right.
class StatListRow extends StatelessWidget {
  final String name;
  final String? detail;
  final String stat;
  final bool emphasized;
  final bool topDivider;
  const StatListRow({
    super.key,
    required this.name,
    this.detail,
    required this.stat,
    this.emphasized = false,
    this.topDivider = true,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: topDivider
            ? const BoxDecoration(
                border: Border(top: BorderSide(color: T.divider)))
            : null,
        child: Row(children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                text: name,
                style: T.listText.copyWith(
                    fontWeight:
                        emphasized ? FontWeight.w600 : FontWeight.w400),
                children: [
                  if (detail != null && detail!.isNotEmpty)
                    TextSpan(
                        text: '  $detail',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: T.textFaint)),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(stat,
              style: T.statLine
                  .copyWith(color: emphasized ? T.text : T.textDim)),
        ]),
      );
}

// ═══════════════════════════ crest circle ═══════════════════════════

/// A team identity circle: color ring + abbreviation. No network images —
/// the color bar system is the app's identity language.
class CrestCircle extends StatelessWidget {
  final String abbr;
  final Color color;
  final double size;
  const CrestCircle({super.key, required this.abbr, required this.color, this.size = 44});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: T.track,
          border: Border.all(color: color, width: 2),
        ),
        alignment: Alignment.center,
        child: Text(abbr.toUpperCase(),
            style: TextStyle(
                fontFamily: 'BarlowCondensed',
                fontWeight: FontWeight.w700,
                fontSize: size * 0.32,
                color: T.text)),
      );
}
