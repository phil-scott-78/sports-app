// The stat language: what kind of number a stat is (how to parse and format its
// value), and — separately — whether it is a SHARE of one whole.
//
// The user-facing rule (DESIGN §8/§10): a bar compares two sides of ONE whole —
// a share (possession, time of possession) — and draws as a single full-width
// split bar of two team-color segments. Independent per-team values — counts,
// averages, and percents like FG%/SV% — render as number rows (leader white,
// faint centred label, trailer dim), never as bars. The mirrored center-spine
// bars are the §10 gridiron team-stats card only; this renderer never gauges.
// One renderer ([StatCompareRow]) speaks all of it — both the cheap-scoreboard
// panels and the rich /summary team stats delegate here so the two tiers can
// never drift apart.
//
// Ported from the v1 client, redrawn in the v2 "broadcast dark" tokens
// (T.*, Barlow-condensed tabular numbers).

import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';

/// How a stat value should be READ (parsed and formatted). How it's DRAWN — a
/// split bar vs a plain number row — is decided separately by [StatSpec.share].
enum StatKind {
  /// A counting stat (shots, rebounds, xG "1.8"): a plain number row.
  count,

  /// A percentage (possession 52.4, FG% 38.4, SV% .909). Values ≤ 1 are read as
  /// fractions (ESPN ships goalie save % as ".909"). Independent percents
  /// (FG%/SV%) are number rows; only a [StatSpec.share] percent (possession)
  /// draws the split bar.
  percent,

  /// A 0–1 fraction that *displays* as a percent (rugby possession "0.440"
  /// → shown "44%"). A share when it is possession/territory.
  fraction01,

  /// A made-of-attempts ratio ("4-16", "19/38"): shown raw; magnitude = made/att.
  ratio,

  /// A mm:ss time (time of possession "33:11"): a share, parsed to seconds for
  /// the split-bar widths.
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

  /// True when the two sides sum to one whole — possession %, time of
  /// possession, rugby possession/territory. Drawn as a single full-width split
  /// bar. Everything else is an independent per-team value → a number row, no
  /// bar (DESIGN §8/§10).
  final bool share;
  const StatSpec(this.key, this.label,
      {this.kind = StatKind.count, this.invert = false, this.share = false});
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
/// the sport family (the `sport/league` prefix). ESPN stat abbreviations except
/// rugby, whose abbreviations collide (P is both passes and possession) — there
/// we key by ESPN's unambiguous `name`.
const Map<String, CheapStatPanel> cheapStatPanels = {
  'soccer': CheapStatPanel('Match stats', [
    StatSpec('PP', 'Possession', kind: StatKind.percent, share: true),
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
    StatSpec('possession', 'Possession', kind: StatKind.fraction01, share: true),
    StatSpec('territory', 'Territory', kind: StatKind.fraction01, share: true),
    StatSpec('metres', 'Metres gained'),
    StatSpec('cleanBreaks', 'Clean breaks'),
    StatSpec('tackles', 'Tackles'),
    StatSpec('penaltiesConceded', 'Penalties conceded', invert: true),
  ]),
  'rugby-league': CheapStatPanel('Match stats', [
    StatSpec('possession', 'Possession', kind: StatKind.fraction01, share: true),
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

/// Fill fraction (0–1) of a value against its own 0–100 (or made/att) scale.
/// Retained as a parsing helper (and for the §10 gridiron center-spine card);
/// the general [StatCompareRow] no longer gauges — see the file header.
/// Null when unparseable.
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

/// Infer how to READ a rich /summary team-stat row from its label + a sample
/// value — clock, percent, conversion ratio, or count — and whether it's a
/// SHARE of one whole (possession / time of possession / territory → the split
/// bar). Everything else is an independent per-team number row.
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
  // Time of possession (a clock) and possession/territory shares split one
  // whole between the sides — the one bar. All other rows are number rows.
  final share = kind == StatKind.clock ||
      l.contains('possession') ||
      l.contains('territory');
  return StatSpec(r.label, r.label,
      kind: kind, invert: _invertLabel(l), share: share);
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

/// Barlow-condensed tabular number for a compare row (DESIGN §8/§10): 13px w600,
/// [color] carrying the read — leader white, trailer dim.
TextStyle _numStyle(Color color) => TextStyle(
      fontFamily: 'BarlowCondensed',
      fontFeatures: const [FontFeature.tabularFigures()],
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: color,
    );

/// One away-vs-home stat row: value · centred faint label · value. A SHARE stat
/// ([StatSpec.share] — possession, time of possession, territory) also draws a
/// single full-width split bar in the two team colors beneath; every other stat
/// (counts, and independent percents like FG%/SV%) renders as the number row
/// alone — no bar. The leading side (lower when [StatSpec.invert]) carries the
/// white number; the trailer stays dim. That color asymmetry — leader white,
/// trailer dim — is the read, not weight. The §10 gridiron center-spine mirrored
/// bars are a separate card — this renderer never gauges.
class StatCompareRow extends StatelessWidget {
  final StatSpec spec;
  final String? away, home;

  /// Team colors for the mirrored bars (§8/§10) — the bars carry the identity so
  /// the comparison reads without color-coding the numbers. Default to a neutral
  /// gray when a caller has no team color (keeps the row legible either way).
  final Color awayColor, homeColor;
  const StatCompareRow(
      {super.key,
      required this.spec,
      required this.away,
      required this.home,
      this.awayColor = T.textDim,
      this.homeColor = T.textDim});

  @override
  Widget build(BuildContext context) {
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
        style: _numStyle(strong ? T.text : T.textDim));

    return Column(children: [
      Row(children: [
        // ~40px fixed value columns flanking a centred faint label (DESIGN §8).
        SizedBox(
            width: 40,
            child: Align(
                alignment: Alignment.centerLeft,
                child: num(aText, awayLeads))),
        Expanded(
          child: Text(spec.label.toUpperCase(),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.cardLabelFaint),
        ),
        SizedBox(
            width: 40,
            child: Align(
                alignment: Alignment.centerRight,
                child: num(hText, homeLeads))),
      ]),
      // A share draws the single split bar; independent values are the row alone.
      if (spec.share) ...[
        const SizedBox(height: 6),
        _shareBar(a, h),
      ],
    ]);
  }

  /// The one bar in this renderer: a full-width split of two team-color segments
  /// (2px gap, r4, 8px tall) whose widths are each side's share of the whole —
  /// possession's 55/45, time of possession's clock split. Both segments read
  /// full color; the leader/trailer asymmetry lives in the numbers above.
  Widget _shareBar(double? a, double? h) {
    final av = a ?? 0, hv = h ?? 0;
    final total = av + hv;
    final aFlex = total <= 0 ? 500 : (av / total * 1000).round().clamp(1, 999);
    final hFlex = total <= 0 ? 500 : (1000 - aFlex).clamp(1, 999);
    return ClipRRect(
      key: const ValueKey('statShareBar'),
      borderRadius: BorderRadius.circular(4),
      child: Row(children: [
        Expanded(flex: aFlex, child: Container(height: 8, color: awayColor)),
        const SizedBox(width: 2),
        Expanded(flex: hFlex, child: Container(height: 8, color: homeColor)),
      ]),
    );
  }
}
