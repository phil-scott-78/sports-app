import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import 'widgets.dart';

/// Standings: a chip per followed league, group tables in dark cards, the
/// favorite team's row highlighted gold with a star.
class StandingsPage extends ConsumerStatefulWidget {
  const StandingsPage({super.key});
  @override
  ConsumerState<StandingsPage> createState() => _StandingsPageState();
}

class _StandingsPageState extends ConsumerState<StandingsPage> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final leagues = ref.watch(followedProvider);
    final catalog = ref.watch(catalogProvider).valueOrNull;
    if (leagues.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(T.pageMargin),
          child: HintCard('Follow a league to see its standings.'),
        ),
      );
    }
    final selected =
        leagues.contains(_selected) ? _selected! : leagues.first;
    final standings = ref.watch(standingsProvider(selected));

    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(T.pageMargin, 14, T.pageMargin, 0),
          child: Text('STANDINGS', style: T.pageTitle),
        ),
        const SizedBox(height: 14),
        ChipNav(
          items: [for (final k in leagues) _chipLabel(k, catalog)],
          selected: leagues.indexOf(selected),
          onTap: (i) => setState(() => _selected = leagues[i]),
        ),
        const SizedBox(height: 14),
        ...switch (standings) {
          AsyncData(:final value) => _groups(value, selected),
          AsyncError() => [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: T.pageMargin),
                child: HintCard('No standings for this league.'),
              ),
            ],
          _ => [
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child:
                    Center(child: CircularProgressIndicator(color: T.gold)),
              ),
            ],
        },
      ],
    );
  }

  String _chipLabel(String key, List<CatalogSport>? catalog) {
    if (catalog != null) {
      for (final s in catalog) {
        for (final l in s.leagues) {
          if (l.key == key) return l.abbr ?? l.name;
        }
      }
    }
    return key.split('/').last.toUpperCase();
  }

  List<Widget> _groups(Standings standings, String league) {
    if (standings.groups.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: T.pageMargin),
          child: HintCard('No standings right now.'),
        ),
      ];
    }
    final favs = ref.watch(favoriteTeamsProvider);
    final favIds = {
      for (final f in favs)
        if (f.league == league) f.teamId,
    };
    return [
      for (final g in standings.groups)
        Padding(
          padding:
              const EdgeInsets.fromLTRB(T.pageMargin, 0, T.pageMargin, 12),
          child: _GroupCard(
            group: g,
            columns: standings.columns,
            favIds: favIds,
          ),
        ),
    ];
  }
}

class _GroupCard extends StatelessWidget {
  final StandingsGroup group;
  final List<StandingColumn> columns;
  final Set<String> favIds;
  const _GroupCard({
    required this.group,
    required this.columns,
    required this.favIds,
  });

  static const _maxCols = 5;

  @override
  Widget build(BuildContext context) {
    final cols = _effectiveColumns();
    return V2Card(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(children: [
            Expanded(
                child:
                    Text(group.name.toUpperCase(), style: T.cardLabelFaint)),
            for (final c in cols)
              SizedBox(
                width: _colWidth(c.label),
                child: Text(c.label.toUpperCase(),
                    textAlign: TextAlign.right, style: T.cardLabelFaint),
              ),
          ]),
        ),
        const SizedBox(height: 10),
        for (final row in _ranked(group.rows)) _row(row, cols),
      ]),
    );
  }

  /// Payload order isn't guaranteed — sort by rank when present.
  List<StandingsRow> _ranked(List<StandingsRow> rows) {
    if (!rows.any((r) => r.rank != null)) return rows;
    return List.of(rows)
      ..sort((a, b) => (a.rank ?? 1 << 20).compareTo(b.rank ?? 1 << 20));
  }

  List<StandingColumn> _effectiveColumns() {
    if (columns.isNotEmpty) return columns.take(_maxCols).toList();
    if (group.rows.isEmpty) return const [];
    return group.rows.first.stats.keys
        .take(4)
        .map((k) => StandingColumn(key: k, label: k))
        .toList();
  }

  double _colWidth(String label) => label.length >= 4 ? 46 : 38;

  Widget _row(StandingsRow row, List<StandingColumn> cols) {
    final fav = favIds.contains(row.team.id);
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
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
                      fontWeight: fav ? FontWeight.w600 : FontWeight.w400)),
            ),
            if (fav) ...[
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
              style: T.statLine.copyWith(color: _statColor(c, row)),
            ),
          ),
      ]),
    );
    if (!fav) return content;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          T.gold.withValues(alpha: 0.08),
          T.gold.withValues(alpha: 0.0),
        ]),
      ),
      child: content,
    );
  }

  Color _statColor(StandingColumn c, StandingsRow row) {
    final v = row.stats[c.key] ?? '';
    // Streak coloring: W4 green, L2 red.
    if (RegExp(r'^W\d+$').hasMatch(v)) return T.green;
    if (RegExp(r'^L\d+$').hasMatch(v)) return T.live;
    return T.textDim;
  }
}
