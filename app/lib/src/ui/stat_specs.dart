// The stat language: what kind of number a stat is, and therefore how it's
// drawn. The user-facing rule this encodes: a PERCENTAGE is a gauge against
// 0–100 (each side fills its own half toward the centre), a COUNT is a share
// of the game's total (one split bar), a RATIO ("4-16" third downs) is a
// conversion gauge, and a CLOCK ("33:11" possession) is a share of real time.
// One renderer ([StatCompareRow]) speaks all four — both the cheap-scoreboard
// panels and the rich /summary team stats delegate here so the two tiers can
// never drift apart.

import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';

/// How a stat value should be read — and therefore drawn.
enum StatKind {
  /// A counting stat (shots, rebounds): one bar split by share of the total.
  count,

  /// A percentage (possession 52.4, FG% 38.4, SV% .909): mirrored gauges,
  /// each side filled to its own value of a 0–100 scale. Values ≤ 1 are read
  /// as fractions (ESPN ships goalie save % as ".909").
  percent,

  /// A 0–1 fraction that *displays* as a percent (rugby possession "0.440"
  /// → shown "44%"). Same gauge as [percent].
  fraction01,

  /// A made-of-attempts ratio ("4-16", "19/38"): gauge filled to made/att.
  ratio,

  /// A mm:ss time (possession "33:11"): share-of-total on parsed seconds.
  clock,
}

/// One row of a cheap-scoreboard team-stat panel: which key to read off
/// `competitor.stats`, the fan-facing label, how to draw it, and whether
/// lower is better ([invert] — fouls, penalties conceded).
class StatSpec {
  final String key;
  final String label;
  final StatKind kind;
  final bool invert;
  const StatSpec(this.key, this.label,
      {this.kind = StatKind.count, this.invert = false});
}

/// A sport's curated cheap-tier stat panel: the section title a fan of that
/// sport expects, the rows worth showing, and whether the rich /summary team
/// stats would just repeat it ([overlapsRich] → the rich section stands down).
class CheapStatPanel {
  final String title;
  final List<StatSpec> rows;
  final bool overlapsRich;
  const CheapStatPanel(this.title, this.rows, {this.overlapsRich = false});
}

/// Per-sport cheap panels, verified against live scoreboard payloads. Keys are
/// ESPN stat abbreviations except rugby, whose abbreviations collide (P is both
/// passes and possession) — there we key by ESPN's unambiguous `name`.
const Map<String, CheapStatPanel> cheapStatPanels = {
  'soccer': CheapStatPanel('Match stats', [
    StatSpec('PP', 'Possession', kind: StatKind.percent),
    StatSpec('SHOT', 'Shots'),
    StatSpec('SOG', 'On target'),
    StatSpec('CW', 'Corners'),
    StatSpec('FC', 'Fouls', invert: true),
  ], overlapsRich: true),
  'basketball': CheapStatPanel('Team stats', [
    StatSpec('FG%', 'Field goals', kind: StatKind.percent),
    StatSpec('3P%', 'Three pointers', kind: StatKind.percent),
    StatSpec('FT%', 'Free throws', kind: StatKind.percent),
    StatSpec('REB', 'Rebounds'),
    StatSpec('AST', 'Assists'),
  ], overlapsRich: true),
  'hockey': CheapStatPanel('Goaltending', [
    StatSpec('SV%', 'Save %', kind: StatKind.percent),
    StatSpec('SV', 'Saves'),
  ]),
  'rugby': CheapStatPanel('Match stats', [
    StatSpec('possession', 'Possession', kind: StatKind.fraction01),
    StatSpec('territory', 'Territory', kind: StatKind.fraction01),
    StatSpec('metres', 'Metres gained'),
    StatSpec('cleanBreaks', 'Clean breaks'),
    StatSpec('tackles', 'Tackles'),
    StatSpec('penaltiesConceded', 'Penalties conceded', invert: true),
  ]),
  'rugby-league': CheapStatPanel('Match stats', [
    StatSpec('possession', 'Possession', kind: StatKind.fraction01),
    StatSpec('metres', 'Metres gained'),
    StatSpec('cleanBreaks', 'Clean breaks'),
    StatSpec('tackles', 'Tackles'),
    StatSpec('penaltiesConceded', 'Penalties conceded', invert: true),
  ]),
};

// ---- parsing ----------------------------------------------------------------

/// Leading numeric in a stat string ("12-24 (50%)" → 12, ".909" → 0.909).
double? statNum(String? s) {
  if (s == null) return null;
  final m = RegExp(r'-?\d*\.?\d+').firstMatch(s);
  return m == null ? null : double.tryParse(m.group(0)!);
}

/// "33:11" → seconds (1991); null when not a mm:ss clock.
double? clockSeconds(String? s) {
  if (s == null) return null;
  final m = RegExp(r'^(\d{1,3}):(\d{2})$').firstMatch(s.trim());
  if (m == null) return null;
  return int.parse(m.group(1)!) * 60.0 + int.parse(m.group(2)!);
}

/// "4-16" / "19/38" → (made: 4, att: 16); null when not a plain a-b / a/b pair.
({double made, double att})? ratioParts(String? s) {
  if (s == null) return null;
  final m = RegExp(r'^(\d+)\s*[-/]\s*(\d+)$').firstMatch(s.trim());
  if (m == null) return null;
  return (made: double.parse(m.group(1)!), att: double.parse(m.group(2)!));
}

/// Gauge fill (0–1) for one side of a row, by kind. Null when unparseable.
double? gaugeFraction(StatKind kind, String? raw) {
  switch (kind) {
    case StatKind.percent:
      final v = statNum(raw);
      if (v == null) return null;
      // ESPN ships some percents as fractions (SV% ".909") — read ≤1 as 0–1.
      return (v <= 1.0 ? v : v / 100).clamp(0.0, 1.0);
    case StatKind.fraction01:
      final v = statNum(raw);
      return v?.clamp(0.0, 1.0);
    case StatKind.ratio:
      final r = ratioParts(raw);
      if (r == null) return null;
      return r.att <= 0 ? 0 : (r.made / r.att).clamp(0.0, 1.0);
    case StatKind.count:
    case StatKind.clock:
      return null; // share-of-total; no per-side gauge
  }
}

/// Comparable magnitude for "who leads" and share splits, by kind.
double? compareValue(StatKind kind, String? raw) {
  if (kind == StatKind.clock) return clockSeconds(raw);
  if (kind == StatKind.ratio) {
    final r = ratioParts(raw);
    return r == null ? null : (r.att <= 0 ? 0 : r.made / r.att);
  }
  return statNum(raw);
}

/// The fan-facing value text. Fractions display as percents ("0.440" → "44%");
/// bare percents get their sign back ("52.4" → "52.4%") unless the label
/// already says % (FG% 38.4 stays "38.4", goalie ".909" stays as fans read it).
String displayValue(StatSpec spec, String? raw) {
  if (raw == null || raw.isEmpty) return '–';
  switch (spec.kind) {
    case StatKind.fraction01:
      final v = statNum(raw);
      if (v == null || v > 1.0) return raw;
      final pct = v * 100;
      return pct == pct.roundToDouble()
          ? '${pct.round()}%'
          : '${pct.toStringAsFixed(1)}%';
    case StatKind.percent:
      final v = statNum(raw);
      // Fraction-form percents (".909") read as-is; whole-form get the sign
      // when the label doesn't already carry it.
      if (v == null || v <= 1.0 || spec.label.contains('%')) return raw;
      return raw.endsWith('%') ? raw : '$raw%';
    default:
      return raw;
  }
}

// ---- rich /summary row classification ----------------------------------------

/// Labels where a "a-b" value really is made-of-attempts (vs. "4-25 penalties"
/// which is count-and-yards).
bool _ratioLabel(String l) =>
    l.contains('efficiency') ||
    l.contains('comp/att') ||
    l.contains('red zone') ||
    l.contains('made');

/// Stats where FEWER is better — the lower side reads as the leader.
bool _invertLabel(String l) =>
    l.contains('turnover') ||
    l.contains('penalt') ||
    l.contains('foul') ||
    l.contains('interception') ||
    l.contains('fumble') ||
    l.contains('sack') ||
    l.contains('error') ||
    l.contains('conceded') ||
    l.contains('giveaway');

/// Infer how to draw a rich /summary team-stat row from its label + a sample
/// value: clock times share, percents gauge, conversion ratios gauge, counts
/// split — so "3rd down efficiency 4-16" stops rendering like "Shots 13".
StatSpec classifyRichRow(TeamStatRow r) {
  final l = r.label.toLowerCase();
  final sample = (r.away?.isNotEmpty == true ? r.away : r.home) ?? '';
  StatKind kind = StatKind.count;
  if (clockSeconds(sample) != null) {
    kind = StatKind.clock;
  } else if (l.contains('%') ||
      l.contains('pct') ||
      l.contains('percent') ||
      sample.endsWith('%')) {
    kind = StatKind.percent;
  } else if (_ratioLabel(l) && ratioParts(sample) != null) {
    kind = StatKind.ratio;
  }
  return StatSpec(r.label, r.label, kind: kind, invert: _invertLabel(l));
}

/// Per-sport "lead stats" for the rich team-stat panel — the rows a fan of that
/// sport scans first, surfaced in this order; everything else waits behind the
/// expander. Matched as case-insensitive label substrings (shortest match wins
/// so 'passing' picks "Passing", not "Passing 1st downs").
const Map<String, List<String>> richPriorityKeywords = {
  'football': [
    'total yards',
    'passing',
    'rushing',
    '3rd down',
    'turnovers',
    'possession',
    'red zone',
    'penalties',
  ],
  'basketball': [
    'field goal',
    'three point',
    '3-pt',
    'free throw',
    'rebounds',
    'assists',
    'turnovers',
    'points in paint',
  ],
  'hockey': [
    'shots',
    'power play',
    'faceoff',
    'penalty',
    'hits',
    'blocked',
    'giveaways',
    'takeaways',
  ],
  'baseball': [
    'hits',
    'runs',
    'errors',
    'home runs',
    'strikeouts',
    'left on base',
  ],
};

/// Split rich rows into (lead, rest) using the sport's priority keywords. With
/// no keywords (or no matches) the first [fallbackCap] rows lead in ESPN order.
({List<TeamStatRow> lead, List<TeamStatRow> rest}) curateRichRows(
    List<TeamStatRow> rows, String? sport,
    {int fallbackCap = 8}) {
  final keywords = richPriorityKeywords[sport] ?? const <String>[];
  final lead = <TeamStatRow>[];
  final picked = <TeamStatRow>{};
  for (final kw in keywords) {
    TeamStatRow? best;
    for (final r in rows) {
      if (picked.contains(r)) continue;
      if (!r.label.toLowerCase().contains(kw)) continue;
      if (best == null || r.label.length < best.label.length) best = r;
    }
    if (best != null) {
      lead.add(best);
      picked.add(best);
    }
  }
  if (lead.isEmpty) {
    lead.addAll(rows.take(fallbackCap));
    picked.addAll(lead);
  }
  final rest = [
    for (final r in rows)
      if (!picked.contains(r)) r,
  ];
  return (lead: lead, rest: rest);
}

// ---- the one comparison-row renderer -----------------------------------------

/// One mirrored away-vs-home stat row: value · centred label · value over a
/// kind-aware bar. Counts and clocks split one bar by share; percentages and
/// conversion ratios render as mirrored gauges filling from the centre out, so
/// 52% possession no longer draws identically to 5 corners. The leading side
/// (lower when [StatSpec.invert]) carries the bold number and the solid bar.
class StatCompareRow extends StatelessWidget {
  final StatSpec spec;
  final String? away, home;
  const StatCompareRow(
      {super.key, required this.spec, required this.away, required this.home});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final aText = displayValue(spec, away);
    final hText = displayValue(spec, home);
    final a = compareValue(spec.kind, away);
    final h = compareValue(spec.kind, home);
    // Leader = bigger (smaller when inverted); a tie or unknown bolds both.
    final tie = a == null || h == null || a == h;
    final awayLeads = tie || (spec.invert ? a <= h : a >= h);
    final homeLeads = tie || (spec.invert ? h <= a : h >= a);

    Widget num(String s, bool strong) => Text(s,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: numStyle(
            size: 13, weight: strong ? FontWeight.w800 : FontWeight.w600));

    return Column(children: [
      Row(children: [
        SizedBox(
            width: 52,
            child: Align(
                alignment: Alignment.centerLeft,
                child: num(aText, awayLeads))),
        Expanded(
          child: Text(spec.label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ),
        SizedBox(
            width: 52,
            child: Align(
                alignment: Alignment.centerRight,
                child: num(hText, homeLeads))),
      ]),
      const SizedBox(height: 4),
      _bar(context, a, h, awayLeads, homeLeads),
    ]);
  }

  Widget _bar(BuildContext context, double? a, double? h, bool awayLeads,
      bool homeLeads) {
    final cs = Theme.of(context).colorScheme;
    final solid = cs.onSurfaceVariant;
    final dim = cs.onSurfaceVariant.withValues(alpha: 0.3);

    final aFrac = gaugeFraction(spec.kind, away);
    final hFrac = gaugeFraction(spec.kind, home);
    if (aFrac != null || hFrac != null) {
      // Mirrored gauges: each side fills from the centre toward its own edge,
      // scaled to its absolute value — 50/50 possession reads symmetric, a .909
      // save night fills nine tenths of its half.
      Widget half(double? frac, bool leads, bool alignRight) => Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: Stack(children: [
                Container(height: 5, color: cs.surfaceContainerHighest),
                Align(
                  alignment: alignRight
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: (frac ?? 0).clamp(0.0, 1.0),
                    child:
                        Container(height: 5, color: leads ? solid : dim),
                  ),
                ),
              ]),
            ),
          );
      return Row(children: [
        half(aFrac, awayLeads, true),
        const SizedBox(width: 2),
        half(hFrac, homeLeads, false),
      ]);
    }

    // Share-of-total split (counts, possession clocks).
    final av = a ?? 0, hv = h ?? 0;
    final total = av + hv;
    final aFlex = total <= 0 ? 500 : (av / total * 1000).round().clamp(1, 999);
    final hFlex = total <= 0 ? 500 : (1000 - aFlex).clamp(1, 999);
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: Row(children: [
        Expanded(
            flex: aFlex,
            child: Container(height: 5, color: awayLeads ? solid : dim)),
        const SizedBox(width: 2),
        Expanded(
            flex: hFlex,
            child: Container(height: 5, color: homeLeads ? solid : dim)),
      ]),
    );
  }
}
