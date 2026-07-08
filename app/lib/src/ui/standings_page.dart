import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import '../util.dart';
import 'standings_table.dart';
import 'team_page.dart';
import 'widgets.dart';

/// Which standings lens is showing. The toggle only appears for leagues whose
/// standings carry a conference structure (§8a); soccer-style single tables
/// stay in [division] with no toggle.
enum StandingsView { division, wildCard, league }

/// Standings: a chip per followed league, an optional Division / Wild Card /
/// League view toggle, then group tables in dark cards, the favorite team's row
/// washed gold with a star.
class StandingsPage extends ConsumerStatefulWidget {
  const StandingsPage({super.key});
  @override
  ConsumerState<StandingsPage> createState() => _StandingsPageState();
}

class _StandingsPageState extends ConsumerState<StandingsPage> {
  String? _selected;
  StandingsView _view = StandingsView.division;

  // Ranking precedence for the flattened League view (all descending: higher is
  // better for every key here).
  static const _rankKeys = [
    'winpercent',
    'leaguewinpercent',
    'points',
    'championshippts',
    'wins',
  ];

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
    final selected = leagues.contains(_selected) ? _selected! : leagues.first;
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
        ...switch (standings) {
          AsyncData(:final value) => _content(value, selected),
          AsyncError() => const [
              SizedBox(height: T.gapFirstCard),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: T.pageMargin),
                child: HintCard('No standings for this league.'),
              ),
            ],
          _ => const [
              Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator(color: T.gold)),
              ),
            ],
        },
      ],
    );
  }

  List<Widget> _content(Standings standings, String league) {
    final hasConf = _hasConferenceStructure(standings);
    // Ignore any stale toggle state on a single-table league.
    final view = hasConf ? _view : StandingsView.division;
    return [
      if (hasConf)
        _ViewToggle(
          value: view,
          onChanged: (v) => setState(() => _view = v),
        ),
      const SizedBox(height: T.gapFirstCard),
      ...switch (view) {
        StandingsView.division => _divisionView(standings, league),
        StandingsView.wildCard => _wildCardView(standings, league),
        StandingsView.league => _leagueView(standings, league),
      },
    ];
  }

  /// A conference structure worth a Wild Card / League split: more than one
  /// group, and the rows carry a `playoffSeed` (the US playoff-bracket signal —
  /// soccer tables and round-robin group stages carry neither). Data-driven, no
  /// sport-name branch.
  bool _hasConferenceStructure(Standings s) {
    if (s.groups.length < 2) return false;
    for (final g in s.groups) {
      for (final r in g.rows) {
        if (r.stats.keys.any((k) => k.toLowerCase() == 'playoffseed')) {
          return true;
        }
      }
    }
    return false;
  }

  // ---- views ----------------------------------------------------------------
  List<Widget> _divisionView(Standings standings, String league) {
    if (standings.groups.isEmpty) return _empty();
    final favIds = _favIds(league);
    final onRowTap = _rowTap(league);
    return [
      for (final g in standings.groups)
        Padding(
          padding: const EdgeInsets.fromLTRB(T.pageMargin, 0, T.pageMargin, 12),
          child: StandingsGroupCard(
            name: g.name,
            rows: g.rows,
            columns: standings.columns,
            highlightIds: favIds,
            onRowTap: onRowTap,
          ),
        ),
    ];
  }

  List<Widget> _wildCardView(Standings standings, String league) {
    if (standings.groups.isEmpty) return _empty();
    final favIds = _favIds(league);
    final barColors = _favColors(league);
    final onRowTap = _rowTap(league);
    final cut = _cutCount(standings);
    return [
      for (final g in standings.groups)
        Padding(
          padding: const EdgeInsets.fromLTRB(T.pageMargin, 0, T.pageMargin, 12),
          child: WildCardCard(
            name: g.name,
            rows: _seedOrder(g.rows),
            cutCount: cut,
            highlightIds: favIds,
            barColors: barColors,
            onRowTap: onRowTap,
          ),
        ),
    ];
  }

  List<Widget> _leagueView(Standings standings, String league) {
    final all = [for (final g in standings.groups) ...g.rows];
    if (all.isEmpty) return _empty();
    all.sort((a, b) =>
        (statNum(b, _rankKeys) ?? 0).compareTo(statNum(a, _rankKeys) ?? 0));
    final ranked = [
      for (var i = 0; i < all.length; i++)
        StandingsRow(team: all[i].team, rank: i + 1, stats: all[i].stats),
    ];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(T.pageMargin, 0, T.pageMargin, 12),
        child: StandingsGroupCard(
          name: _leagueName(league, ref.watch(catalogProvider).valueOrNull),
          rows: ranked,
          columns: standings.columns,
          highlightIds: _favIds(league),
          onRowTap: _rowTap(league),
        ),
      ),
    ];
  }

  // ---- shared helpers --------------------------------------------------------
  /// Rows already arrive in ESPN standing order; re-sort by `playoffSeed` only
  /// as a stable safety net (it equals the given order).
  List<StandingsRow> _seedOrder(List<StandingsRow> rows) {
    if (!rows.any((r) =>
        r.stats.keys.any((k) => k.toLowerCase() == 'playoffseed'))) {
      return rows;
    }
    return List.of(rows)
      ..sort((a, b) {
        final sa = statNum(a, ['playoffseed']);
        final sb = statNum(b, ['playoffseed']);
        if (sa != null && sb != null && sa != sb) return sa.compareTo(sb);
        return (statNum(b, _rankKeys) ?? 0).compareTo(statNum(a, _rankKeys) ?? 0);
      });
  }

  /// The playoff cut per conference (§8a). No dedicated wildcard group nor a
  /// per-league profile field exists in the current registry, so this falls
  /// back to the spec default of 3.
  int _cutCount(Standings standings) => 3;

  Set<String> _favIds(String league) {
    final favs = ref.watch(favoriteTeamsProvider);
    return {
      for (final f in favs)
        if (f.league == league) f.teamId,
    };
  }

  Map<String, Color> _favColors(String league) {
    final favs = ref.watch(favoriteTeamsProvider);
    return {
      for (final f in favs)
        if (f.league == league && f.color != null)
          f.teamId: teamColorOf(f.color),
    };
  }

  void Function(StandingsRow)? _rowTap(String league) {
    final catalog = ref.watch(catalogProvider).valueOrNull;
    if (!_hasTeamPage(catalog, league)) return null;
    return (row) => openTeamPage(context, league,
        teamId: row.team.id, name: row.team.name);
  }

  List<Widget> _empty() => const [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: T.pageMargin),
          child: HintCard('No standings right now.'),
        ),
      ];

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

  String _leagueName(String key, List<CatalogSport>? catalog) {
    if (catalog != null) {
      for (final s in catalog) {
        for (final l in s.leagues) {
          if (l.key == key) return l.name;
        }
      }
    }
    return key.split('/').last.toUpperCase();
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

/// The §8a underlined-tab view toggle: active tab is 600 white with a 2px gold
/// underline; the rest recede faint.
class _ViewToggle extends StatelessWidget {
  final StandingsView value;
  final ValueChanged<StandingsView> onChanged;
  const _ViewToggle({required this.value, required this.onChanged});

  static const _labels = {
    StandingsView.division: 'Division',
    StandingsView.wildCard: 'Wild Card',
    StandingsView.league: 'League',
  };

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(T.pageMargin, 12, T.pageMargin, 0),
        child: Row(children: [
          for (final e in _labels.entries) ...[
            _tab(e.value, e.key == value, () => onChanged(e.key)),
            const SizedBox(width: 16),
          ],
        ]),
      );

  Widget _tab(String label, bool active, VoidCallback onTap) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.only(bottom: 6),
          decoration: active
              ? const BoxDecoration(
                  border: Border(bottom: BorderSide(color: T.gold, width: 2)))
              : null,
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? T.text : T.textFaint)),
        ),
      );
}
