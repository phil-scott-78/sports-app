import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import '../util.dart';
import 'widgets.dart';

/// Searchable catalog list — toggle followed leagues.
class AddLeaguePage extends ConsumerStatefulWidget {
  const AddLeaguePage({super.key});
  @override
  ConsumerState<AddLeaguePage> createState() => _AddLeaguePageState();
}

class _AddLeaguePageState extends ConsumerState<AddLeaguePage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    final followed = ref.watch(followedProvider);

    return Scaffold(
      appBar: _bar(context, 'FOLLOW A LEAGUE'),
      body: switch (catalog) {
        AsyncData(:final value) => Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  T.pageMargin, 8, T.pageMargin, 4),
              child: _SearchField(
                  hint: 'Search leagues',
                  onChanged: (q) =>
                      setState(() => _query = q.toLowerCase())),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 28),
                children: [
                  for (final sport in value)
                    ..._sportSection(sport, followed),
                ],
              ),
            ),
          ]),
        AsyncError() => const Center(
            child: Padding(
              padding: EdgeInsets.all(T.pageMargin),
              child: HintCard('Couldn’t load the league catalog.'),
            ),
          ),
        _ => const Center(child: CircularProgressIndicator(color: T.gold)),
      },
    );
  }

  List<Widget> _sportSection(CatalogSport sport, List<String> followed) {
    final leagues = sport.leagues
        .where((l) =>
            _query.isEmpty ||
            l.name.toLowerCase().contains(_query) ||
            (l.abbr ?? '').toLowerCase().contains(_query))
        .toList();
    if (leagues.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(T.pageMargin, 18, T.pageMargin, 6),
        child: Text(sport.sport.toUpperCase(), style: T.cardLabel),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: T.pageMargin),
        child: V2Card(
          radius: T.rowCardRadius,
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (var i = 0; i < leagues.length; i++)
              _leagueRow(leagues[i], followed, divider: i > 0),
          ]),
        ),
      ),
    ];
  }

  Widget _leagueRow(CatalogLeague l, List<String> followed,
      {required bool divider}) {
    final on = followed.contains(l.key);
    return InkWell(
      onTap: () => ref.read(followedProvider.notifier).toggle(l.key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: divider
            ? const BoxDecoration(
                border: Border(top: BorderSide(color: T.divider)))
            : null,
        child: Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.name, style: T.rowText),
              if (l.region != null) Text(l.region!, style: T.captionFaint),
            ]),
          ),
          Icon(
            on ? Icons.check_circle_rounded : Icons.add_circle_outline,
            size: 20,
            color: on ? T.gold : T.outline,
          ),
        ]),
      ),
    );
  }
}

/// Pick a league (that has a roster), then star teams.
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
      bool hasTeams(CatalogLeague l) => l.hasTeams;
      options.addAll([
        ...all.where((l) => followed.contains(l.key) && hasTeams(l)),
        ...all.where((l) => !followed.contains(l.key) && hasTeams(l)),
      ]);
    }
    final league = _league ??
        (options.isNotEmpty ? options.first.key : null);

    return Scaffold(
      appBar: _bar(context, 'ADD A TEAM'),
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
          child: _SearchField(
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

PreferredSizeWidget _bar(BuildContext context, String title) => AppBar(
      backgroundColor: T.bg,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded,
            size: 18, color: T.textDim),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: Text(title,
          style: T.pageTitle.copyWith(fontSize: 22)),
      centerTitle: false,
    );

class _SearchField extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  const _SearchField({required this.hint, required this.onChanged});

  @override
  Widget build(BuildContext context) => TextField(
        onChanged: onChanged,
        style: const TextStyle(fontSize: 14, color: T.text),
        cursorColor: T.gold,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 14, color: T.textFaint),
          prefixIcon:
              const Icon(Icons.search_rounded, size: 18, color: T.textFaint),
          filled: true,
          fillColor: T.surface,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      );
}
