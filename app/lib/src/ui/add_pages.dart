import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import '../util.dart';
import 'widgets.dart';

/// Pick a league (that has a roster), then star teams as favorites.
/// (League browsing/following lives in ExplorePage.)
class AddTeamPage extends ConsumerStatefulWidget {
  const AddTeamPage({super.key});
  @override
  ConsumerState<AddTeamPage> createState() => _AddTeamPageState();
}

class _AddTeamPageState extends ConsumerState<AddTeamPage> {
  String? _league;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider).valueOrNull;
    final followed = ref.watch(followedProvider);
    // Leagues with rosters, followed first, then the rest of the catalog.
    final options = <CatalogLeague>[];
    if (catalog != null) {
      final all = [for (final s in catalog) ...s.leagues];
      options.addAll([
        ...all.where((l) => followed.contains(l.key) && l.hasTeams),
        ...all.where((l) => !followed.contains(l.key) && l.hasTeams),
      ]);
    }
    final league = _league ?? (options.isNotEmpty ? options.first.key : null);

    return Scaffold(
      appBar: subpageBar(context, 'Add a team'),
      body: Column(children: [
        if (options.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ChipNav(
              items: [
                for (final l in options.take(12)) l.abbr ?? l.name,
              ],
              selected: options
                  .take(12)
                  .toList()
                  .indexWhere((l) => l.key == league)
                  .clamp(0, 11),
              onTap: (i) => setState(() => _league = options[i].key),
            ),
          ),
        Padding(
          padding:
              const EdgeInsets.fromLTRB(T.pageMargin, 10, T.pageMargin, 4),
          child: V2SearchField(
              hint: 'Search teams',
              onChanged: (q) => setState(() => _query = q.toLowerCase())),
        ),
        if (league != null)
          Expanded(child: _TeamList(league: league, query: _query))
        else
          const Expanded(
              child: Center(child: CircularProgressIndicator(color: T.gold))),
      ]),
    );
  }
}

class _TeamList extends ConsumerWidget {
  final String league;
  final String query;
  const _TeamList({required this.league, required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teams = ref.watch(teamsProvider(league));
    final favs = ref.watch(favoriteTeamsProvider);
    return switch (teams) {
      AsyncData(:final value) => ListView(
          padding: const EdgeInsets.fromLTRB(
              T.pageMargin, 8, T.pageMargin, 28),
          children: [
            for (final t in value)
              if (query.isEmpty ||
                  t.displayName.toLowerCase().contains(query))
                _teamRow(context, ref, t,
                    on: favs.any(
                        (f) => f.league == league && f.teamId == t.id)),
          ],
        ),
      AsyncError() => const Center(
          child: HintCard('No team list for this league.')),
      _ => const Center(child: CircularProgressIndicator(color: T.gold)),
    };
  }

  Widget _teamRow(BuildContext context, WidgetRef ref, TeamRef t,
      {required bool on}) {
    return InkWell(
      onTap: () => ref.read(favoriteTeamsProvider.notifier).toggle(FavoriteTeam(
            league: league,
            teamId: t.id,
            name: t.displayName,
            abbr: t.abbreviation,
            color: t.color,
          )),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: T.divider))),
        child: Row(children: [
          ColorBar(teamColorOf(t.color), width: 6, height: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(t.displayName, style: T.rowText)),
          Icon(
            on ? Icons.star_rounded : Icons.star_border_rounded,
            size: 20,
            color: on ? T.gold : T.outline,
          ),
        ]),
      ),
    );
  }
}
