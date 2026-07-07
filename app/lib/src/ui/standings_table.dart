import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import 'widgets.dart';

/// One standings group as a dark card — the group name + a right-aligned stat
/// grid, rows highlighted gold when in [highlightIds] (a favorite, or the team
/// whose page this is). Shared by the Standings tab and the team page so the two
/// render the exact same table shape.
class StandingsGroupCard extends StatelessWidget {
  final String name;
  final List<StandingsRow> rows;
  final List<StandingColumn> columns;
  final Set<String> highlightIds;

  /// When set, each row is tappable (→ the row's team page). Null → inert rows
  /// (athlete-shaped racing tables, or the team page's own standing card).
  final void Function(StandingsRow)? onRowTap;
  const StandingsGroupCard({
    super.key,
    required this.name,
    required this.rows,
    this.columns = const [],
    this.highlightIds = const {},
    this.onRowTap,
  });

  static const _maxCols = 5;

  @override
  Widget build(BuildContext context) {
    final cols = _effectiveColumns();
    final keyCol = _keyColumn(cols);
    return V2Card(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(
                child: Text(name.toUpperCase(), style: T.cardLabelFaint)),
            for (final c in cols)
              SizedBox(
                width: _colWidth(c.label),
                child: Text(c.label.toUpperCase(),
                    textAlign: TextAlign.right,
                    // §10: the one key-stat column's header is white.
                    style: identical(c, keyCol)
                        ? T.cardLabelFaint.copyWith(color: T.text)
                        : T.cardLabelFaint),
              ),
          ]),
        ),
        const SizedBox(height: 10),
        for (final row in _ranked(rows)) _row(row, cols, keyCol),
      ]),
    );
  }

  /// The single promoted "key-stat" column (§10 core rule: every table
  /// highlights exactly one). Picks the first key in this precedence list that
  /// a column matches (case-insensitive) — so a soccer table promotes PTS over
  /// its W column — else falls back to the first column.
  static const _keyStatPrecedence = [
    'points',
    'pts',
    'championshippts',
    'pct',
    'w',
    'wins',
  ];

  StandingColumn? _keyColumn(List<StandingColumn> cols) {
    if (cols.isEmpty) return null;
    for (final key in _keyStatPrecedence) {
      for (final c in cols) {
        if (c.key.toLowerCase() == key) return c;
      }
    }
    return cols.first;
  }

  /// Payload order isn't guaranteed — sort by rank when present.
  List<StandingsRow> _ranked(List<StandingsRow> rows) {
    if (!rows.any((r) => r.rank != null)) return rows;
    return List.of(rows)
      ..sort((a, b) => (a.rank ?? 1 << 20).compareTo(b.rank ?? 1 << 20));
  }

  List<StandingColumn> _effectiveColumns() {
    if (columns.isNotEmpty) return columns.take(_maxCols).toList();
    if (rows.isEmpty) return const [];
    return rows.first.stats.keys
        .take(4)
        .map((k) => StandingColumn(key: k, label: k))
        .toList();
  }

  double _colWidth(String label) => label.length >= 4 ? 46 : 38;

  Widget _row(StandingsRow row, List<StandingColumn> cols,
      StandingColumn? keyCol) {
    final hi = highlightIds.contains(row.team.id);
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: T.divider))),
      child: Row(children: [
        Expanded(
          child: Row(children: [
            if (row.rank != null) ...[
              SizedBox(
                width: 18,
                child: Text('${row.rank}',
                    style: const TextStyle(
                        fontFamily: 'BarlowCondensed',
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: T.textDim)),
              ),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(row.team.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.listText.copyWith(
                      fontWeight: hi ? FontWeight.w600 : FontWeight.w400)),
            ),
            if (hi) ...[
              const SizedBox(width: 6),
              const Icon(Icons.star_rounded, size: 12, color: T.gold),
            ],
          ]),
        ),
        for (final c in cols)
          SizedBox(
            width: _colWidth(c.label),
            child: Text(
              row.stats[c.key] ?? '',
              textAlign: TextAlign.right,
              // §10: the key-stat cell is Barlow 15/700 white (this white wins
              // over dim); every other cell recedes to dim, with semantic
              // green/live surviving for streaks + signed differentials.
              style: identical(c, keyCol)
                  ? T.statLineStrong
                  : T.statLine.copyWith(color: _statColor(c, row)),
            ),
          ),
      ]),
    );
    final body = hi
        ? DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                T.gold.withValues(alpha: 0.08),
                T.gold.withValues(alpha: 0.0),
              ]),
            ),
            child: content,
          )
        : content;
    if (onRowTap == null) return body;
    return InkWell(onTap: () => onRowTap!(row), child: body);
  }

  Color _statColor(StandingColumn c, StandingsRow row) {
    final v = row.stats[c.key] ?? '';
    // Streak coloring: W4 green, L2 red.
    if (RegExp(r'^W\d+$').hasMatch(v)) return T.green;
    if (RegExp(r'^L\d+$').hasMatch(v)) return T.live;
    // §10 signed values: a differential like "+12" / "-7" (goal/run/point
    // diff) reads positive green, negative live; zero stays dim.
    if (RegExp(r'^[+-]\d').hasMatch(v)) {
      return v.startsWith('-') ? T.live : T.green;
    }
    return T.textDim;
  }
}
