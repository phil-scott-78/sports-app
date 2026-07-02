import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import 'stat_specs.dart';
import 'widgets.dart';

/// The rich /summary team-stat comparison, organized instead of dumped: the
/// sport's lead stats (see [richPriorityKeywords]) surface first in fan order,
/// the long tail waits behind a quiet "All team stats" expander, and every row
/// is drawn by its kind — conversion ratios ("4-16 on 3rd down") and percents
/// as gauges, possession clocks ("33:11") as a share of real time, counts as a
/// split bar. Values arrive pre-split as [TeamStatRow.away] / [TeamStatRow.home].
class SummaryTeamStats extends StatefulWidget {
  final List<TeamStatRow> rows;
  final String? sport;
  const SummaryTeamStats({super.key, required this.rows, this.sport});

  @override
  State<SummaryTeamStats> createState() => _SummaryTeamStatsState();
}

class _SummaryTeamStatsState extends State<SummaryTeamStats> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final present =
        widget.rows.where((r) => r.away != null || r.home != null).toList();
    if (present.isEmpty) return const SizedBox.shrink();

    var (:lead, :rest) = curateRichRows(present, widget.sport);
    // A tail too short to be worth a fold just shows — the expander is for the
    // 20-row firehose, not two stragglers.
    if (rest.length < 3) {
      lead = [...lead, ...rest];
      rest = const [];
    }
    final shown = _expanded ? [...lead, ...rest] : lead;

    return DetailPanel(
      child: Column(
        children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            StatCompareRow(
              spec: classifyRichRow(shown[i]),
              away: shown[i].away,
              home: shown[i].home,
            ),
          ],
          if (rest.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18),
                label: Text(
                    _expanded
                        ? 'Key stats only'
                        : 'All team stats (${lead.length + rest.length})',
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600)),
                style:
                    TextButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
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

  static const double _kHeadHeight = 24;
  static const double _kRowHeight = 30;

  // Expand the first group AND any pitching group — for baseball the pitching
  // lines are the story, so they shouldn't start collapsed behind the batting box.
  bool _expand(BoxGroup g, int i) =>
      i == 0 || g.title.toLowerCase().contains('pitch');

  // Content-sized column widths (tabular figures → ~8px/char), with a sensible
  // floor + cap, computed across BOTH teams so the away/home rows stay aligned.
  double _colWidth(BoxGroup g, int c) {
    var maxLen = c < g.columns.length ? g.columns[c].length : 0;
    for (final t in g.teams) {
      for (final r in t.rows) {
        final s = c < r.stats.length ? r.stats[c] : '';
        if (s.length > maxLen) maxLen = s.length;
      }
    }
    return (maxLen * 8.0 + 16).clamp(38.0, 120.0);
  }

  double _nameWidth(BoxGroup g) {
    var maxLen = 8;
    for (final t in g.teams) {
      for (final r in t.rows) {
        final l = r.name.length + ((r.pos?.isNotEmpty ?? false) ? r.pos!.length + 1 : 0);
        if (l > maxLen) maxLen = l;
      }
    }
    return (maxLen * 7.3 + 20).clamp(100.0, 168.0);
  }

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
              child: _group(context, groups[i], _expand(groups[i], i), cs),
            ),
          ],
        ],
      ),
    );
  }

  Widget _group(BuildContext context, BoxGroup group, bool expanded,
      ColorScheme cs) {
    final nameWidth = _nameWidth(group);
    final statWidths = [for (var c = 0; c < group.columns.length; c++) _colWidth(group, c)];
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
          _team(context, group, group.teams[t], t > 0, cs, nameWidth, statWidths),
      ],
    );
  }

  Widget _team(BuildContext context, BoxGroup group, BoxTeam team, bool gap,
      ColorScheme cs, double nameWidth, List<double> statWidths) {
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
          _nameColumn(context, team, cs, nameWidth),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _statColumns(context, group, team, cs, statWidths),
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

  Widget _nameColumn(
      BuildContext context, BoxTeam team, ColorScheme cs, double nameWidth) {
    return SizedBox(
      width: nameWidth,
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
      ColorScheme cs, List<double> statWidths) {
    Widget statColumn(int col) {
      return SizedBox(
        width: col < statWidths.length ? statWidths[col] : 44,
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
