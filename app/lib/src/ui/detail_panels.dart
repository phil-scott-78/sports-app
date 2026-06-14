import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import 'widgets.dart';

const double _kDiamondTurn = 0.7853981633974483; // 45° in radians

double? _statNum(String? s) {
  if (s == null) return null;
  final m = RegExp(r'-?\d+(\.\d+)?').firstMatch(s);
  return m == null ? null : double.tryParse(m.group(0)!);
}

/// Live "what's happening right now" strip. Baseball: count + outs + base
/// diamond + pitcher/batter + last play. The #1 reason a fan opens a live game.
class LiveSituationStrip extends StatelessWidget {
  final Competition comp;
  const LiveSituationStrip({super.key, required this.comp});

  /// True when there's something worth showing for a live game.
  static bool has(Competition comp) =>
      comp.status.live && (comp.situation?.hasBaseball ?? false);

  @override
  Widget build(BuildContext context) {
    final s = comp.situation;
    if (s == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;

    final count = (s.balls != null && s.strikes != null) ? '${s.balls}-${s.strikes}' : null;
    final outs = s.outsText ?? (s.outs != null ? '${s.outs} Out${s.outs == 1 ? '' : 's'}' : null);

    return DetailPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (count != null) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(count, style: numStyle(size: 26, weight: FontWeight.w800)),
                    if (outs != null)
                      Text(outs, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  ],
                ),
                const SizedBox(width: 16),
              ],
              _BaseDiamond(
                  onFirst: s.onFirst == true,
                  onSecond: s.onSecond == true,
                  onThird: s.onThird == true),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (s.pitcher != null) _kv(context, 'P', s.pitcher!),
                    if (s.batter != null) _kv(context, 'AB', s.batter!),
                  ],
                ),
              ),
            ],
          ),
          if (s.lastPlay != null) ...[
            const SizedBox(height: 8),
            Text(s.lastPlay!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(children: [
        SizedBox(width: 26, child: Text(k, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant))),
        Expanded(
          child: Text(v,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

class _BaseDiamond extends StatelessWidget {
  final bool onFirst, onSecond, onThird;
  const _BaseDiamond({required this.onFirst, required this.onSecond, required this.onThird});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = BinanceColors.of(context).accent;
    Widget base(bool on) => Transform.rotate(
          angle: _kDiamondTurn,
          child: Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              color: on ? accent : Colors.transparent,
              border: Border.all(color: on ? accent : cs.outline, width: 1.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
    return SizedBox(
      width: 48,
      height: 40,
      child: Stack(children: [
        Positioned(top: 0, left: 18, child: base(onSecond)),
        Positioned(top: 13, left: 5, child: base(onThird)),
        Positioned(top: 13, left: 31, child: base(onFirst)),
      ]),
    );
  }
}

/// Per-team statistical leaders, two-up (away | home). Cheap for MLB/NBA/NHL.
class LeadersStrip extends StatelessWidget {
  final Competitor away, home;
  final int max;
  const LeadersStrip({super.key, required this.away, required this.home, this.max = 3});

  static bool has(Competitor a, Competitor b) => a.leaders.isNotEmpty || b.leaders.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DetailPanel(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _col(context, away)),
        Container(width: 1, height: 56, color: cs.outlineVariant.withValues(alpha: 0.4)),
        const SizedBox(width: 12),
        Expanded(child: _col(context, home)),
      ]),
    );
  }

  Widget _col(BuildContext context, Competitor c) {
    final cs = Theme.of(context).colorScheme;
    final leaders = c.leaders.take(max).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(c.abbreviation ?? c.shortName ?? c.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
      const SizedBox(height: 4),
      for (final l in leaders)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 32,
              child: Text(l.label,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (l.athlete != null)
                  Text(l.athlete!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                if (l.display != null)
                  Text(l.display!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: numStyle(size: 11, color: cs.onSurfaceVariant)),
              ]),
            ),
          ]),
        ),
    ]);
  }
}

/// Mirrored two-column team-stat comparison with proportional bars.
class TeamStatComparison extends StatelessWidget {
  final Competitor away, home;
  final List<({String key, String label})> rows;
  const TeamStatComparison({super.key, required this.away, required this.home, required this.rows});

  /// Keep only rows where at least one side has a value.
  static bool has(Competitor a, Competitor b, List<({String key, String label})> rows) =>
      rows.any((r) => a.stats[r.key] != null || b.stats[r.key] != null);

  @override
  Widget build(BuildContext context) {
    final present = rows.where((r) => away.stats[r.key] != null || home.stats[r.key] != null).toList();
    if (present.isEmpty) return const SizedBox.shrink();
    return DetailPanel(
      child: Column(
        children: [
          for (var i = 0; i < present.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            _row(context, present[i]),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, ({String key, String label}) r) {
    final cs = Theme.of(context).colorScheme;
    final aStr = away.stats[r.key] ?? '–';
    final hStr = home.stats[r.key] ?? '–';
    final a = _statNum(aStr) ?? 0;
    final h = _statNum(hStr) ?? 0;
    final total = a + h;
    final aFlex = total <= 0 ? 1 : (a / total * 1000).round().clamp(1, 999);
    final hFlex = total <= 0 ? 1 : (1000 - aFlex).clamp(1, 999);
    Widget num(String s, bool strong) =>
        Text(s, style: numStyle(size: 13, weight: strong ? FontWeight.w800 : FontWeight.w600));
    return Column(children: [
      Row(children: [
        SizedBox(width: 46, child: Align(alignment: Alignment.centerLeft, child: num(aStr, a >= h))),
        Expanded(
          child: Text(r.label,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ),
        SizedBox(width: 46, child: Align(alignment: Alignment.centerRight, child: num(hStr, h >= a))),
      ]),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(2),
        // Neutral comparison — yellow stays scarce; the leading number is already
        // bolded, the bar just shows the split (away solid, home a dim track).
        child: Row(children: [
          Expanded(flex: aFlex, child: Container(height: 5, color: cs.onSurfaceVariant)),
          const SizedBox(width: 2),
          Expanded(flex: hFlex, child: Container(height: 5, color: cs.onSurfaceVariant.withValues(alpha: 0.3))),
        ]),
      ),
    ]);
  }
}

/// Last-5 form pills (W/D/L) for two teams. Soccer / rugby.
class FormStrip extends StatelessWidget {
  final Competitor away, home;
  const FormStrip({super.key, required this.away, required this.home});

  static bool has(Competitor a, Competitor b) =>
      (a.form?.isNotEmpty ?? false) || (b.form?.isNotEmpty ?? false);

  @override
  Widget build(BuildContext context) {
    return DetailPanel(
      child: Column(children: [
        if (away.form?.isNotEmpty ?? false) _teamForm(context, away),
        if ((away.form?.isNotEmpty ?? false) && (home.form?.isNotEmpty ?? false))
          const SizedBox(height: 8),
        if (home.form?.isNotEmpty ?? false) _teamForm(context, home),
      ]),
    );
  }

  Widget _teamForm(BuildContext context, Competitor c) {
    final letters = c.form!.toUpperCase().replaceAll(RegExp(r'[^WDL]'), '').split('');
    final last5 = letters.length > 5 ? letters.sublist(letters.length - 5) : letters;
    return Row(children: [
      Expanded(
        child: Text(c.abbreviation ?? c.shortName ?? c.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ),
      for (final r in last5)
        Padding(padding: const EdgeInsets.only(left: 4), child: _pill(context, r)),
    ]);
  }

  Widget _pill(BuildContext context, String r) {
    final b = BinanceColors.of(context);
    final cs = Theme.of(context).colorScheme;
    final wl = r == 'W' || r == 'L';
    // W/L are the one honest up/down signal — trading green/red fills carrying
    // dark ink (AA in both modes); a draw is a quiet neutral chip.
    final fill = r == 'W' ? b.up : (r == 'L' ? b.down : cs.surfaceContainerHighest);
    final fg = wl ? const Color(0xFF181A20) : cs.onSurfaceVariant;
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(4)),
      child: Text(r, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: fg)),
    );
  }
}

/// Probable starters (pre-game): pitcher / goalie, two-up.
class ProbablesRow extends StatelessWidget {
  final Competitor away, home;
  const ProbablesRow({super.key, required this.away, required this.home});

  static bool has(Competitor a, Competitor b) =>
      a.probables.isNotEmpty || b.probables.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return DetailPanel(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: _col(context, away)),
        const SizedBox(width: 12),
        Expanded(child: _col(context, home)),
      ]),
    );
  }

  Widget _col(BuildContext context, Competitor c) {
    final cs = Theme.of(context).colorScheme;
    if (c.probables.isEmpty) return const SizedBox.shrink();
    final p = c.probables.first;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(c.abbreviation ?? c.shortName ?? c.displayName,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
      const SizedBox(height: 2),
      Text(p.athlete,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      Text(p.role, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
    ]);
  }
}

/// MMA: the whole fight card. One event = many bouts (competitions). Groups by
/// card segment (Main Card / Prelims) when present.
class MmaCardList extends StatelessWidget {
  final List<Competition> bouts;
  const MmaCardList({super.key, required this.bouts});

  @override
  Widget build(BuildContext context) {
    // group by cardSegment preserving order; null segments grouped under ''
    final groups = <String, List<Competition>>{};
    for (final b in bouts) {
      final seg = b.meta?.cardSegment ?? '';
      (groups[seg] ??= []).add(b);
    }
    final children = <Widget>[];
    groups.forEach((seg, list) {
      if (seg.isNotEmpty) children.add(SectionLabel(seg));
      for (final b in list) {
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _Bout(comp: b),
        ));
      }
    });
    return Column(children: children);
  }
}

class _Bout extends StatelessWidget {
  final Competition comp;
  const _Bout({required this.comp});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fighters = comp.competitors.take(2).toList();
    final result = comp.method?.summary ??
        (comp.status.isFinal ? (comp.status.shortDetail ?? 'Final') : comp.status.periodLabel);
    return DetailPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final f in fighters) _fighter(context, f),
        if (result.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(result, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ],
      ]),
    );
  }

  Widget _fighter(BuildContext context, Competitor f) {
    final cs = Theme.of(context).colorScheme;
    final isFinal = comp.status.isFinal;
    final lost = isFinal && f.winner == false;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(
          width: 22,
          child: f.isWinner
              ? Icon(Icons.check_circle, size: 18, color: BinanceColors.of(context).accent)
              : const SizedBox.shrink(),
        ),
        Expanded(
          child: Text(f.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: f.isWinner ? FontWeight.w700 : FontWeight.w500,
                color: lost ? cs.onSurfaceVariant : cs.onSurface,
              )),
        ),
        if (f.records.isNotEmpty)
          Text(f.records.first.summary,
              style: numStyle(size: 11, color: cs.onSurfaceVariant)),
      ]),
    );
  }
}
