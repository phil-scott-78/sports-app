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
      comp.status.live &&
      ((comp.situation?.hasBaseball ?? false) ||
          (comp.situation?.hasGridiron ?? false));

  @override
  Widget build(BuildContext context) {
    final s = comp.situation;
    if (s == null) return const SizedBox.shrink();
    if (s.hasBaseball) return _baseball(context, s);
    if (s.hasGridiron) return _gridiron(context, s);
    return const SizedBox.shrink();
  }

  static String _ordinalDown(int d) => d == 1
      ? '1st'
      : d == 2
          ? '2nd'
          : d == 3
              ? '3rd'
              : '${d}th';

  /// Gridiron live strip: down & distance, possession, red-zone, last play.
  Widget _gridiron(BuildContext context, Situation s) {
    final cs = Theme.of(context).colorScheme;
    final ext = BinanceColors.of(context);
    // Resolve the possession team-id to its abbreviation against the competitors.
    String? posAbbr;
    if (s.possession != null) {
      for (final c in comp.competitors) {
        if (c.id == s.possession) {
          posAbbr = c.abbreviation ?? c.shortName ?? c.displayName;
          break;
        }
      }
    }
    final dd = s.downDistanceText ??
        (s.down != null && s.distance != null
            ? '${_ordinalDown(s.down!)} & ${s.distance}'
            : null);
    return DetailPanel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (dd != null)
            Expanded(
              child: Text(dd,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: numStyle(size: 20, weight: FontWeight.w800)),
            )
          else
            const Spacer(),
          if (posAbbr != null) ...[
            Icon(Icons.sports_football, size: 15, color: cs.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(posAbbr,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ],
          if (s.isRedZone == true) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: ext.live.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('RED ZONE',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                      color: ext.live)),
            ),
          ],
        ]),
        if (s.lastPlay != null) ...[
          const SizedBox(height: 8),
          Text(s.lastPlay!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ],
      ]),
    );
  }

  Widget _baseball(BuildContext context, Situation s) {
    final cs = Theme.of(context).colorScheme;

    final count = (s.balls != null && s.strikes != null)
        ? '${s.balls}-${s.strikes}'
        : null;
    final outs = s.outsText ??
        (s.outs != null ? '${s.outs} Out${s.outs == 1 ? '' : 's'}' : null);

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
                    Text(count,
                        style: numStyle(size: 26, weight: FontWeight.w800)),
                    if (outs != null)
                      Text(outs,
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant)),
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
                    if (s.pitcher != null)
                      _role(context, 'P', s.pitcher!, s.pitcherLine),
                    if (s.pitcher != null && s.batter != null)
                      const SizedBox(height: 5),
                    if (s.batter != null)
                      _role(context, 'AB', s.batter!, s.batterLine),
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

  /// A role line: 'P'/'AB' tag + name, with the live stat line ('0.2 IP, 0 ER',
  /// the batter's day) dim beneath it — the matchup read, not just the names.
  Widget _role(BuildContext context, String k, String name, String? line) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        SizedBox(
            width: 26,
            child: Text(k,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant))),
        Expanded(
          child: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ]),
      if (line != null && line.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(left: 26, top: 1),
          child: Text(line,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: numStyle(size: 11, color: cs.onSurfaceVariant)),
        ),
    ]);
  }
}

class _BaseDiamond extends StatelessWidget {
  final bool onFirst, onSecond, onThird;
  const _BaseDiamond(
      {required this.onFirst, required this.onSecond, required this.onThird});

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

/// Per-team statistical leaders (cheap: MLB/NBA/NHL scoreboard). When both sides
/// report leaders they read as category-aligned rows (away · CATEGORY · home) so
/// a label like "Assists" gets real width instead of a cramped 32px gutter; when
/// only one side reported them — ESPN routinely omits the loser on a final — it
/// falls back to a single roomy column rather than a lopsided half-empty pair.
class LeadersStrip extends StatelessWidget {
  final Competitor away, home;
  final int max;
  const LeadersStrip(
      {super.key, required this.away, required this.home, this.max = 3});

  static bool has(Competitor a, Competitor b) =>
      a.leaders.isNotEmpty || b.leaders.isNotEmpty;

  static const double _labelW = 84;

  @override
  Widget build(BuildContext context) {
    final a = away.leaders.take(max).toList();
    final h = home.leaders.take(max).toList();
    if (a.isEmpty && h.isEmpty) return const SizedBox.shrink();
    if (a.isEmpty || h.isEmpty) {
      final side = a.isNotEmpty ? away : home;
      return DetailPanel(child: _single(context, side, a.isNotEmpty ? a : h));
    }
    return DetailPanel(child: _compare(context, a, h));
  }

  /// Both sides: a header of the two abbreviations, then one row per stat
  /// category (union by `name`, away order first), each side's leader hugging its
  /// edge around the centered category label.
  Widget _compare(BuildContext context, List<Leader> a, List<Leader> h) {
    final cs = Theme.of(context).colorScheme;
    final am = {for (final l in a) l.name: l};
    final hm = {for (final l in h) l.name: l};
    final all = [...a, ...h];
    final order = <String>[];
    for (final l in all) {
      if (!order.contains(l.name)) order.add(l.name);
    }
    final labelFor = {for (final l in all) l.name: l.label};

    Widget head(Competitor c, bool end) => Text(
          c.abbreviation ?? c.shortName ?? c.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: end ? TextAlign.right : TextAlign.left,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        );

    return Column(children: [
      Row(children: [
        Expanded(child: head(away, false)),
        const SizedBox(width: _labelW),
        Expanded(child: head(home, true)),
      ]),
      const SizedBox(height: 6),
      for (var i = 0; i < order.length; i++) ...[
        if (i > 0)
          Divider(height: 14, color: cs.outlineVariant.withValues(alpha: 0.3)),
        _cmpRow(context, labelFor[order[i]] ?? order[i], am[order[i]],
            hm[order[i]]),
      ],
    ]);
  }

  Widget _cmpRow(BuildContext context, String label, Leader? a, Leader? h) {
    final cs = Theme.of(context).colorScheme;
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Expanded(child: _leaderCell(context, a, end: false)),
      SizedBox(
        width: _labelW,
        child: Text(label.toUpperCase(),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: cs.onSurfaceVariant)),
      ),
      Expanded(child: _leaderCell(context, h, end: true)),
    ]);
  }

  /// One side's leader for a category — athlete over value, hugging its edge.
  /// "—" when that side reported no leader for this category.
  Widget _leaderCell(BuildContext context, Leader? l, {required bool end}) {
    final cs = Theme.of(context).colorScheme;
    final ta = end ? TextAlign.right : TextAlign.left;
    if (l == null || (l.athlete == null && l.display == null)) {
      return Align(
        alignment: end ? Alignment.centerRight : Alignment.centerLeft,
        child: Text('—', style: TextStyle(color: cs.onSurfaceVariant)),
      );
    }
    return Column(
      crossAxisAlignment:
          end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (l.athlete != null)
          Text(l.athlete!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: ta,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        if (l.display != null)
          Text(l.display!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: ta,
              style: numStyle(
                  size: 12,
                  weight: FontWeight.w800,
                  color: BinanceColors.of(context).accent)),
      ],
    );
  }

  /// Only one side reported leaders: a single roomy column — abbr header, then
  /// "CATEGORY  athlete  value" rows with the label given real width.
  Widget _single(BuildContext context, Competitor c, List<Leader> leaders) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(c.abbreviation ?? c.shortName ?? c.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
      const SizedBox(height: 6),
      for (var i = 0; i < leaders.length; i++) ...[
        if (i > 0)
          Divider(height: 14, color: cs.outlineVariant.withValues(alpha: 0.3)),
        _singleRow(context, leaders[i]),
      ],
    ]);
  }

  Widget _singleRow(BuildContext context, Leader l) {
    final cs = Theme.of(context).colorScheme;
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      SizedBox(
        width: 76,
        child: Text(l.label.toUpperCase(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: cs.onSurfaceVariant)),
      ),
      Expanded(
        child: Text(l.athlete ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ),
      if (l.display != null) ...[
        const SizedBox(width: 8),
        Text(l.display!,
            style: numStyle(
                size: 13,
                weight: FontWeight.w800,
                color: BinanceColors.of(context).accent)),
      ],
    ]);
  }
}

/// Mirrored two-column team-stat comparison with proportional bars. A row may be
/// [invert]ed (lower is better, e.g. Fouls) so the *smaller* side reads as the
/// leader — bolded number + the solid bar segment.
class TeamStatComparison extends StatelessWidget {
  final Competitor away, home;
  final List<({String key, String label, bool invert})> rows;
  const TeamStatComparison(
      {super.key, required this.away, required this.home, required this.rows});

  /// Keep only rows where at least one side has a value.
  static bool has(Competitor a, Competitor b,
          List<({String key, String label, bool invert})> rows) =>
      rows.any((r) => a.stats[r.key] != null || b.stats[r.key] != null);

  @override
  Widget build(BuildContext context) {
    final present = rows
        .where((r) => away.stats[r.key] != null || home.stats[r.key] != null)
        .toList();
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

  Widget _row(
      BuildContext context, ({String key, String label, bool invert}) r) {
    final cs = Theme.of(context).colorScheme;
    final aStr = away.stats[r.key] ?? '–';
    final hStr = home.stats[r.key] ?? '–';
    final a = _statNum(aStr) ?? 0;
    final h = _statNum(hStr) ?? 0;
    final total = a + h;
    final aFlex = total <= 0 ? 1 : (a / total * 1000).round().clamp(1, 999);
    final hFlex = total <= 0 ? 1 : (1000 - aFlex).clamp(1, 999);
    // The "leader" is the bigger side, or the smaller when the stat is inverted.
    final tie = a == h;
    final awayLeads = tie || (r.invert ? a <= h : a >= h);
    final homeLeads = tie || (r.invert ? h <= a : h >= a);
    Widget num(String s, bool strong) => Text(s,
        style: numStyle(
            size: 13, weight: strong ? FontWeight.w800 : FontWeight.w600));
    final solid = cs.onSurfaceVariant;
    final dim = cs.onSurfaceVariant.withValues(alpha: 0.3);
    return Column(children: [
      Row(children: [
        SizedBox(
            width: 46,
            child: Align(
                alignment: Alignment.centerLeft, child: num(aStr, awayLeads))),
        Expanded(
          child: Text(r.label,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ),
        SizedBox(
            width: 46,
            child: Align(
                alignment: Alignment.centerRight, child: num(hStr, homeLeads))),
      ]),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(2),
        // Neutral comparison — the leader's segment is solid, the trailing side a
        // dim track (so an inverted stat highlights the lower value correctly).
        child: Row(children: [
          Expanded(
              flex: aFlex,
              child: Container(height: 5, color: awayLeads ? solid : dim)),
          const SizedBox(width: 2),
          Expanded(
              flex: hFlex,
              child: Container(height: 5, color: homeLeads ? solid : dim)),
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
        if ((away.form?.isNotEmpty ?? false) &&
            (home.form?.isNotEmpty ?? false))
          const SizedBox(height: 8),
        if (home.form?.isNotEmpty ?? false) _teamForm(context, home),
      ]),
    );
  }

  Widget _teamForm(BuildContext context, Competitor c) {
    final letters =
        c.form!.toUpperCase().replaceAll(RegExp(r'[^WDL]'), '').split('');
    final last5 =
        letters.length > 5 ? letters.sublist(letters.length - 5) : letters;
    return Row(children: [
      Expanded(
        child: Text(c.abbreviation ?? c.shortName ?? c.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ),
      for (final r in last5)
        Padding(
            padding: const EdgeInsets.only(left: 4), child: _pill(context, r)),
    ]);
  }

  Widget _pill(BuildContext context, String r) {
    final b = BinanceColors.of(context);
    // The design's muted W/L/D form tones (near-monochrome system) — a quiet
    // chip per result, white glyph; not the trading green/red.
    final fill = r == 'W' ? b.formWin : (r == 'L' ? b.formLoss : b.formDraw);
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration:
          BoxDecoration(color: fill, borderRadius: BorderRadius.circular(5)),
      child: Text(r,
          style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: Colors.white)),
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
    // Sub-line: the season line ('(5-4, 3.30)') when present, else the role; a
    // confirmed starter (NHL goalie) is flagged so a locked matchup reads as such.
    final sub = [
      (p.record != null && p.record!.isNotEmpty) ? p.record! : p.role,
      if (p.confirmed) 'Confirmed',
    ].join(' · ');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(c.abbreviation ?? c.shortName ?? c.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
      const SizedBox(height: 2),
      Text(p.athlete,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      Text(sub,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: numStyle(size: 11, color: cs.onSurfaceVariant)),
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
        (comp.status.isFinal
            ? (comp.status.shortDetail ?? 'Final')
            : comp.status.periodLabel);
    return DetailPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Weight class — the only thing that tells otherwise-identical bouts apart.
        if (comp.label != null && comp.label!.isNotEmpty) ...[
          Text(comp.label!.toUpperCase(),
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: cs.onSurfaceVariant)),
          const SizedBox(height: 4),
        ],
        for (final f in fighters) _fighter(context, f),
        if (result.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(result,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
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
              ? Icon(Icons.check_circle,
                  size: 18, color: BinanceColors.of(context).accent)
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
