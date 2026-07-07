import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import 'standings_table.dart';
import 'team_page.dart';
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
      padding: const EdgeInsets.only(bottom: T.scrollBottom),
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
        const SizedBox(height: T.gapFirstCard),
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
    // Rows tap through to a team page — but only where the competitor is a real
    // team (an athlete-shaped racing championship table stays inert).
    final catalog = ref.watch(catalogProvider).valueOrNull;
    final hasTeamPage = _hasTeamPage(catalog, league);
    return [
      for (final g in standings.groups)
        Padding(
          padding:
              const EdgeInsets.fromLTRB(T.pageMargin, 0, T.pageMargin, 12),
          child: StandingsGroupCard(
            name: g.name,
            rows: g.rows,
            columns: standings.columns,
            highlightIds: favIds,
            onRowTap: hasTeamPage
                ? (row) => openTeamPage(context, league,
                    teamId: row.team.id, name: row.team.name)
                : null,
          ),
        ),
    ];
  }

  /// Defaults true when the catalog hasn't loaded (matches CatalogLeague's
  /// old-worker default); false only when a league explicitly isn't team-based.
  bool _hasTeamPage(List<CatalogSport>? catalog, String league) {
    if (catalog == null) return true;
    for (final s in catalog) {
      for (final l in s.leagues) {
        if (l.key == league) return l.hasTeamPage;
      }
    }
    return true;
  }
}
