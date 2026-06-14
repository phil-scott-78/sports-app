import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import 'widgets.dart';

/// Leading numeric in a stat string (e.g. "12-24 (50%)" -> 12), or null.
double? _statNum(String? s) {
  if (s == null) return null;
  final m = RegExp(r'-?\d+(\.\d+)?').firstMatch(s);
  return m == null ? null : double.tryParse(m.group(0)!);
}

/// Mirrored two-column team-stat comparison with proportional bars.
///
/// Like [TeamStatComparison] in detail_panels.dart, but values arrive
/// pre-split as [TeamStatRow.away] / [TeamStatRow.home].
class SummaryTeamStats extends StatelessWidget {
  final List<TeamStatRow> rows;
  const SummaryTeamStats({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    final present =
        rows.where((r) => r.away != null || r.home != null).toList();
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

  Widget _row(BuildContext context, TeamStatRow r) {
    final cs = Theme.of(context).colorScheme;
    final aStr = r.away ?? '–';
    final hStr = r.home ?? '–';
    final aNum = _statNum(r.away);
    final hNum = _statNum(r.home);
    final a = aNum ?? 0;
    final h = hNum ?? 0;
    final total = a + h;
    // Both non-numeric -> split 50/50.
    final int aFlex;
    final int hFlex;
    if (aNum == null && hNum == null) {
      aFlex = 500;
      hFlex = 500;
    } else if (total <= 0) {
      aFlex = 1;
      hFlex = 1;
    } else {
      aFlex = (a / total * 1000).round().clamp(1, 999);
      hFlex = (1000 - aFlex).clamp(1, 999);
    }
    Widget num(String s, bool strong) => Text(
          s,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: numStyle(size: 13, weight: strong ? FontWeight.w800 : FontWeight.w600),
        );
    return Column(children: [
      Row(children: [
        SizedBox(
          width: 46,
          child: Align(
            alignment: Alignment.centerLeft,
            child: num(aStr, a >= h),
          ),
        ),
        Expanded(
          child: Text(
            r.label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ),
        SizedBox(
          width: 46,
          child: Align(
            alignment: Alignment.centerRight,
            child: num(hStr, h >= a),
          ),
        ),
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

/// Compact period grid: frozen team column, period headers, away/home value
/// rows, and a pinned-right TOTAL column. Fits 390px without scroll for up to
/// six periods; beyond that the middle scrolls while team + total stay pinned.
class PeriodLinesGrid extends StatelessWidget {
  final PeriodLines lines;
  const PeriodLinesGrid({super.key, required this.lines});

  @override
  Widget build(BuildContext context) {
    final labels = lines.labels;
    if (labels.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final scrolls = labels.length > 6;

    Widget headCell(String text) => SizedBox(
          height: 22,
          child: Center(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        );

    Widget valueCell(String text, {bool strong = false, Color? color}) =>
        SizedBox(
          height: 28,
          child: Center(
            child: Text(
              text,
              maxLines: 1,
              style: numStyle(
                size: 14,
                weight: strong ? FontWeight.w800 : FontWeight.w500,
                color: color ?? cs.onSurface,
              ),
            ),
          ),
        );

    // The stacked head + away/home cells for one column. No intrinsic width: the
    // caller pins it (when scrolling) or lets it flex to fill the row.
    Widget colBody(String head, List<String> vals,
            {bool strong = false, Color? color}) =>
        Column(children: [
          headCell(head),
          for (final v in vals) valueCell(v, strong: strong, color: color),
        ]);

    final teamCol = SizedBox(
      width: 52,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 22),
        for (final abbr in [lines.away.abbr ?? '', lines.home.abbr ?? ''])
          SizedBox(
            height: 28,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                abbr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
          ),
      ]),
    );

    String away(int i) =>
        i < lines.away.values.length ? lines.away.values[i] : '';
    String home(int i) =>
        i < lines.home.values.length ? lines.home.values[i] : '';

    final periodBodies = [
      for (var i = 0; i < labels.length; i++)
        colBody(labels[i], [away(i), home(i)]),
    ];

    // Always 'T' (the game total). `unit` is the period noun ("quarter"), which
    // truncated to "qua…" when misused as this header.
    final totalCol = SizedBox(
      width: 34,
      child: colBody(
        'T',
        [lines.away.total ?? '', lines.home.total ?? ''],
        strong: true,
        color: BinanceColors.of(context).accent,
      ),
    );

    // ≤6 periods (NBA/NFL quarters, NHL periods): flex the columns so the grid
    // fills the card width instead of hugging the left with dead space. Beyond
    // six, pin them to a fixed width and scroll the middle horizontally.
    final Widget periods = scrolls
        ? SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (final b in periodBodies) SizedBox(width: 28, child: b),
            ]),
          )
        : Row(children: [for (final b in periodBodies) Expanded(child: b)]);

    return DetailPanel(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Row(children: [
        teamCol,
        Expanded(child: periods),
        const SizedBox(width: 4),
        totalCol,
      ]),
    );
  }
}

/// Per-player box score. Each [BoxGroup] is an expandable section with a frozen
/// player-name column and a horizontally scrollable stat region, so the name
/// column always lines up with the scrolled rows (fixed cell heights).
class BoxScoreTable extends StatelessWidget {
  final List<BoxGroup> groups;
  const BoxScoreTable({super.key, required this.groups});

  static const double _kNameWidth = 132;
  static const double _kStatWidth = 44;
  static const double _kHeadHeight = 24;
  static const double _kRowHeight = 30;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Theme(
      // Drop the default ExpansionTile dividers for a cleaner dark section.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Column(
        children: [
          for (var i = 0; i < groups.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            DetailPanel(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: _group(context, groups[i], i == 0, cs),
            ),
          ],
        ],
      ),
    );
  }

  Widget _group(BuildContext context, BoxGroup group, bool expanded,
      ColorScheme cs) {
    return ExpansionTile(
      initiallyExpanded: expanded,
      tilePadding: const EdgeInsets.symmetric(horizontal: 10),
      childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      shape: const Border(),
      collapsedShape: const Border(),
      title: Text(
        group.title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      children: [
        for (var t = 0; t < group.teams.length; t++)
          _team(context, group, group.teams[t], t > 0, cs),
      ],
    );
  }

  Widget _team(BuildContext context, BoxGroup group, BoxTeam team,
      bool gap, ColorScheme cs) {
    final sub = _subHeader(team);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (gap) const SizedBox(height: 10),
        if (sub != null) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              sub,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _nameColumn(context, team, cs),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _statColumns(context, group, team, cs),
            ),
          ),
        ]),
      ],
    );
  }

  String? _subHeader(BoxTeam team) {
    if (team.side == null) return team.abbr;
    final suffix = team.side == 'home' ? ' (home)' : ' (away)';
    return '${team.abbr ?? ''}$suffix';
  }

  Widget _nameColumn(BuildContext context, BoxTeam team, ColorScheme cs) {
    return SizedBox(
      width: _kNameWidth,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: _kHeadHeight),
        for (final row in team.rows)
          SizedBox(
            height: _kRowHeight,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Row(children: [
                Flexible(
                  child: Text(
                    row.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (row.pos != null && row.pos!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      row.pos!,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 10,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _statColumns(BuildContext context, BoxGroup group, BoxTeam team,
      ColorScheme cs) {
    Widget statColumn(int col) {
      return SizedBox(
        width: _kStatWidth,
        child: Column(children: [
          SizedBox(
            height: _kHeadHeight,
            child: Center(
              child: Text(
                col < group.columns.length ? group.columns[col] : '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
          for (final row in team.rows)
            SizedBox(
              height: _kRowHeight,
              child: Center(
                child: Text(
                  col < row.stats.length ? row.stats[col] : '',
                  maxLines: 1,
                  style: numStyle(size: 12, weight: FontWeight.w500, color: cs.onSurface),
                ),
              ),
            ),
        ]),
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var c = 0; c < group.columns.length; c++) statColumn(c),
    ]);
  }
}
