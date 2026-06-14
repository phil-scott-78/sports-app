import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import 'widgets.dart';

/// The standings table for a league, with no Scaffold of its own so it embeds as
/// a tab inside [LeagueDetailPage] (and could stand alone under any AppBar).
class StandingsView extends ConsumerWidget {
  final String league;
  const StandingsView({super.key, required this.league});

  // stat columns to show, in priority order (only those present are shown)
  static const _preferred = <String, String>{
    'gamesPlayed': 'GP',
    'wins': 'W',
    'losses': 'L',
    'ties': 'D',
    'otLosses': 'OTL',
    'points': 'PTS',
    'winPercent': 'PCT',
    'gamesBehind': 'GB',
    'pointDifferential': 'DIFF',
    'streak': 'STRK',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(standingsProvider(league)).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorView(message: '$e', onRetry: () => ref.invalidate(standingsProvider(league))),
          data: (standings) {
            if (standings.groups.isEmpty) {
              return const EmptyState(icon: Icons.table_chart_outlined, title: 'No standings');
            }
            final children = <Widget>[];
            for (final g in standings.groups) {
              if (g.name.isNotEmpty) children.add(SectionHeader(g.name));
              children.add(ListCard(child: _GroupTable(group: g, columns: _columnsFor(g))));
            }
            return ListView(children: children);
          },
        );
  }

  List<MapEntry<String, String>> _columnsFor(StandingsGroup g) {
    final present = <String>{};
    for (final r in g.rows) {
      present.addAll(r.stats.keys);
    }
    final cols = _preferred.entries.where((e) => present.contains(e.key)).take(5).toList();
    return cols;
  }
}

class _GroupTable extends StatelessWidget {
  final StandingsGroup group;
  final List<MapEntry<String, String>> columns;
  const _GroupTable({required this.group, required this.columns});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 36,
        dataRowMinHeight: 40,
        dataRowMaxHeight: 48,
        columns: [
          const DataColumn(label: Text('#')),
          const DataColumn(label: Text('Team')),
          for (final c in columns) DataColumn(label: Text(c.value)),
        ],
        rows: [
          for (var i = 0; i < group.rows.length; i++)
            DataRow(cells: [
              DataCell(Text('${group.rows[i].rank ?? i + 1}',
                  style: numStyle(size: 13, color: cs.onSurfaceVariant))),
              DataCell(Row(children: [
                Crest(url: group.rows[i].team.logo, darkUrl: group.rows[i].team.logoDark, fallback: group.rows[i].team.abbr ?? group.rows[i].team.name, size: 20),
                const SizedBox(width: 8),
                Text(group.rows[i].team.abbr ?? group.rows[i].team.name),
              ])),
              for (final c in columns)
                DataCell(Text(group.rows[i].stats[c.key] ?? '', style: numStyle(size: 13))),
            ]),
        ],
      ),
    );
  }
}
