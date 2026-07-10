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

  /// When set, each row long-presses into the follow sheet (favorite / team
  /// page / follow league — the app-wide add grammar).
  final void Function(StandingsRow)? onRowLongPress;
  const StandingsGroupCard({
    super.key,
    required this.name,
    required this.rows,
    this.columns = const [],
    this.highlightIds = const {},
    this.onRowTap,
    this.onRowLongPress,
  });

  // §10 promotes ONE key column; the rest recede. 6 allows a US-league table to
  // carry its W/L/PCT/GB plus an L10 (+ DIV) sub-record column without scrolling.
  static const _maxCols = 6;

  @override
  Widget build(BuildContext context) {
    final cols = _effectiveColumns();
    final keyCol = _keyColumn(cols);
    // §3.1: paint a team-color rail when the identity cache knows any team in
    // this group (color-less standings joins the scoreboard's colors by id).
    // All-unknown tables (e.g. unwarmed athlete standings) keep the rail-free
    // layout rather than a column of identical neutral bars.
    final showRail = rows.any((r) => cachedTeamColor(r.team.id) != null);
    return V2Card(
      // §10 data table = T.padTable (14×16), split so the row hairlines + gold
      // wash bleed to the card edge: the card owns the 16 vertical, the header
      // and rows own the 14 horizontal.
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
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
        for (final row in _ranked(rows)) _row(row, cols, keyCol, showRail),
        _legend(rows),
      ]),
    );
  }

  /// Parse an ESPN band hex ('#81D6AC') to a Color; tolerant of the odd
  /// double-hash ('##c6d1e0' → c6d1e0). Null when not a 6-digit hex.
  static Color? _bandColor(String? s) {
    if (s == null) return null;
    final h = s.replaceAll('#', '').trim();
    if (h.length != 6) return null;
    final v = int.tryParse(h, radix: 16);
    return v == null ? null : Color(0xFF000000 | v);
  }

  /// A 3px left color band (§2.7/2.8 cut-line) flush to the card edge, drawn over
  /// the row without shifting its content. No-op when the row has no band.
  Widget _withBand(StandingsRow row, Widget child) {
    final c = _bandColor(row.note?.color);
    if (c == null) return child;
    return Stack(children: [
      child,
      Positioned(
          left: 0, top: 0, bottom: 0, child: Container(width: 3, color: c)),
    ]);
  }

  /// The qualification legend under the table: one entry per DISTINCT band
  /// description (in row order), a color swatch + its tag ('Champions League' /
  /// 'Relegation'). Empty (shrinks away) when no row carries a band.
  Widget _legend(List<StandingsRow> rows) {
    final seen = <String>{};
    final items = <({Color color, String label})>[];
    for (final r in rows) {
      final d = r.note?.description;
      final c = _bandColor(r.note?.color);
      if (d == null || d.isEmpty || c == null || !seen.add(d)) continue;
      items.add((color: c, label: d));
    }
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Wrap(
        spacing: 14,
        runSpacing: 6,
        children: [
          for (final it in items)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 3,
                height: 12,
                decoration: BoxDecoration(
                    color: it.color, borderRadius: BorderRadius.circular(1.5)),
              ),
              const SizedBox(width: 6),
              Text(it.label, style: T.captionFaint),
            ]),
        ],
      ),
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

  double _colWidth(String label) => label.length >= 4 ? 44 : 38;

  Widget _row(StandingsRow row, List<StandingColumn> cols,
      StandingColumn? keyCol, bool showRail) {
    final hi = highlightIds.contains(row.team.id);
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: T.rowVPad),
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
            if (showRail) ...[
              ColorBar(cachedTeamColor(row.team.id) ?? T.border,
                  width: 4, height: 15),
              const SizedBox(width: 9),
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
    final body = _withBand(
      row,
      hi
          ? DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  T.gold.withValues(alpha: 0.08),
                  T.gold.withValues(alpha: 0.0),
                ]),
              ),
              child: content,
            )
          : content,
    );
    if (onRowTap == null && onRowLongPress == null) return body;
    return InkWell(
      onTap: onRowTap == null ? null : () => onRowTap!(row),
      onLongPress: onRowLongPress == null ? null : () => onRowLongPress!(row),
      child: body,
    );
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

/// Read the first stat whose key matches (case-insensitive) one of [keys] and
/// parse it as a number (tolerating a leading '+' and dropping a bare '-'/'—').
/// Shared by the Wild Card cut-math and the League-view ranking. Null → absent.
double? statNum(StandingsRow row, List<String> keys) {
  for (final want in keys) {
    for (final e in row.stats.entries) {
      if (e.key.toLowerCase() != want) continue;
      final raw = e.value.replaceAll('+', '').trim();
      if (raw.isEmpty || raw == '-' || raw == '—') return 0;
      final v = double.tryParse(raw);
      if (v != null) return v;
    }
  }
  return null;
}

/// The Wild Card view of one conference/league child (§8a). The group's teams
/// ranked in standing order with a single red PLAYOFF LINE drawn after the cut,
/// and a games-relative-to-the-line GB column: teams above the line read `+N`
/// green (games clear of the first team out); below read `N` dim (games back of
/// the last team in); the last team in reads an em-dash.
///
/// The default feed carries no division membership, so this is the *conference*
/// playoff cut — the whole child ranked, not a division-leader-excluded wild-card
/// sub-table (that would need a core division fetch; see the standings notes).
class WildCardCard extends StatelessWidget {
  final String name;

  /// Rows in standing order (seed ascending). Not re-sorted here.
  final List<StandingsRow> rows;

  /// Teams above this count are "in"; the line is drawn after it.
  final int cutCount;

  /// Favorite team ids (gold wash + star), and their identity colors for the bar.
  final Set<String> highlightIds;
  final Map<String, Color> barColors;
  final void Function(StandingsRow)? onRowTap;
  final void Function(StandingsRow)? onRowLongPress;

  const WildCardCard({
    super.key,
    required this.name,
    required this.rows,
    required this.cutCount,
    this.highlightIds = const {},
    this.barColors = const {},
    this.onRowTap,
    this.onRowLongPress,
  });

  static const _gbKeys = ['gamesbehind'];

  @override
  Widget build(BuildContext context) {
    // Only draw the line when it falls strictly inside the list.
    final cut = (cutCount > 0 && cutCount < rows.length) ? cutCount : -1;
    final lastInGb = cut > 0 ? (statNum(rows[cut - 1], _gbKeys) ?? 0.0) : 0.0;
    final firstOutGb = cut > 0 ? (statNum(rows[cut], _gbKeys) ?? 0.0) : 0.0;

    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(children: [
          Expanded(child: Text(name.toUpperCase(), style: T.cardLabelFaint)),
          const SizedBox(
            width: 52,
            child: Text('GB',
                textAlign: TextAlign.right, style: T.cardLabelFaint),
          ),
        ]),
      ),
      const SizedBox(height: 10),
    ];
    for (var i = 0; i < rows.length; i++) {
      if (i == cut) {
        children.add(const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: RuleLabelDivider('PLAYOFF LINE', alarm: true),
        ));
      }
      children.add(_row(rows[i], i + 1,
          topBorder: i != 0 && i != cut,
          above: cut < 0 || i < cut,
          lastInGb: lastInGb,
          firstOutGb: firstOutGb,
          hasCut: cut > 0));
    }
    return V2Card(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _row(StandingsRow row, int pos,
      {required bool topBorder,
      required bool above,
      required double lastInGb,
      required double firstOutGb,
      required bool hasCut}) {
    final hi = highlightIds.contains(row.team.id);
    final gb = statNum(row, _gbKeys) ?? 0;
    String gbText;
    Color gbColor;
    if (!hasCut) {
      gbText = _fmt(gb);
      gbColor = T.textDim;
    } else if (above) {
      final d = firstOutGb - gb; // games clear of the first team out
      gbText = d > 0 ? '+${_fmt(d)}' : '—';
      gbColor = d > 0 ? T.green : T.textDim;
    } else {
      final d = gb - lastInGb; // games back of the last team in
      gbText = d > 0 ? _fmt(d) : '—';
      gbColor = T.textDim;
    }

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: T.rowVPad),
      decoration: topBorder
          ? const BoxDecoration(
              border: Border(top: BorderSide(color: T.divider)))
          : null,
      child: Row(children: [
        SizedBox(
          width: 14,
          child: Text('$pos',
              style: const TextStyle(
                  fontFamily: 'BarlowCondensed',
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: T.textDim)),
        ),
        const SizedBox(width: 9),
        // Favorite color (explicit) wins; else the identity cache (§3.1); else a
        // neutral rail.
        ColorBar(
            barColors[row.team.id] ??
                cachedTeamColor(row.team.id) ??
                T.border,
            width: 5,
            height: 16),
        const SizedBox(width: 9),
        Flexible(
          child: Text(row.team.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.listText.copyWith(
                  color: above ? T.text : T.textDim,
                  fontWeight: hi ? FontWeight.w600 : FontWeight.w400)),
        ),
        if (hi) ...[
          const SizedBox(width: 6),
          const Icon(Icons.star_rounded, size: 12, color: T.gold),
        ],
        const SizedBox(width: 6),
        SizedBox(
          width: 52,
          child: Text(gbText,
              textAlign: TextAlign.right,
              style: T.statLine.copyWith(color: gbColor)),
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
    if (onRowTap == null && onRowLongPress == null) return body;
    return InkWell(
      onTap: onRowTap == null ? null : () => onRowTap!(row),
      onLongPress: onRowLongPress == null ? null : () => onRowLongPress!(row),
      child: body,
    );
  }

  static String _fmt(double d) =>
      d == d.roundToDouble() ? d.toInt().toString() : d.toStringAsFixed(1);
}
