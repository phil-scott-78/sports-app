import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import 'widgets.dart';

/// Builds a followed-key → display-name map from the catalog (best-effort).
Map<String, CatalogLeague> _catalogByKey(WidgetRef ref) {
  final out = <String, CatalogLeague>{};
  for (final s in ref.watch(catalogProvider).valueOrNull ?? const <CatalogSport>[]) {
    for (final lg in s.leagues) {
      out[lg.key] = lg;
    }
  }
  return out;
}

/// Manage favorite teams: list current favorites (with remove) + an add flow.
/// Reached from Settings. The cards themselves live atop the Scores tab.
class FavoriteTeamsPage extends ConsumerWidget {
  const FavoriteTeamsPage({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final added = await Navigator.of(context).push<FavoriteTeam>(
        MaterialPageRoute(builder: (_) => const _PickLeaguePage()));
    if (added != null && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Added ${added.name}')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favs = ref.watch(favoriteTeamsProvider);
    final byKey = _catalogByKey(ref);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Favorite teams'),
        actions: [
          IconButton(
            tooltip: 'Add a team',
            icon: const Icon(Icons.add),
            onPressed: () => _add(context, ref),
          ),
        ],
      ),
      body: favs.isEmpty
          ? EmptyState(
              icon: Icons.star_outline,
              title: 'No favorite teams',
              subtitle: 'Add a team to see its live score, last result and next game\non the Scores tab.',
              action: FilledButton(
                onPressed: () => _add(context, ref),
                child: const Text('Add a team'),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(top: 8),
              children: [
                for (final f in favs)
                  ListCard(
                    child: ListTile(
                      leading: Crest(url: f.logo, darkUrl: null, fallback: f.abbr ?? f.name, size: 28),
                      title: Text(f.name),
                      subtitle: Text(byKey[f.league]?.name ?? f.league),
                      trailing: IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () =>
                            ref.read(favoriteTeamsProvider.notifier).remove(f.league, f.teamId),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Step 1 of the add flow: pick a league. Followed leagues first (the likely
/// pick), then the whole catalog grouped by sport — so you can favorite a team in
/// a league you don't follow. Returns the added [FavoriteTeam] up the stack.
class _PickLeaguePage extends ConsumerWidget {
  const _PickLeaguePage();

  Future<void> _pick(BuildContext context, String league, String leagueName) async {
    final added = await Navigator.of(context).push<FavoriteTeam>(
        MaterialPageRoute(builder: (_) => _PickTeamPage(league: league, leagueName: leagueName)));
    if (added != null && context.mounted) Navigator.of(context).pop(added);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final followed = ref.watch(followedProvider);
    final byKey = _catalogByKey(ref);

    return Scaffold(
      appBar: AppBar(title: const Text('Pick a league')),
      body: ref.watch(catalogProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(message: '$e', onRetry: () => ref.invalidate(catalogProvider)),
            data: (sports) {
              final children = <Widget>[];
              ListTile leagueTile(String key, String name, {String? region}) => ListTile(
                    title: Text(name),
                    subtitle: (region != null && region.isNotEmpty) ? Text(region) : null,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _pick(context, key, name),
                  );

              // Only leagues whose ESPN /teams returns a roster can be favorited;
              // individual sports (golf/tennis/MMA/NASCAR) have none, so omit them
              // rather than dead-ending on "No teams found" (F1 keeps its constructors).
              if (followed.isNotEmpty) {
                final tiles = [
                  for (final key in followed)
                    if (byKey[key]?.hasTeams ?? true)
                      leagueTile(key, byKey[key]?.name ?? key, region: byKey[key]?.region),
                ];
                if (tiles.isNotEmpty) {
                  children.add(const SectionHeader('Followed'));
                  children.addAll(tiles);
                }
              }

              for (final s in sports) {
                final tiles = [
                  for (final lg in s.leagues)
                    if (lg.hasTeams) leagueTile(lg.key, lg.name, region: lg.region),
                ];
                if (tiles.isEmpty) continue;
                children.add(SectionHeader(sportLabel(s.sport)));
                children.addAll(tiles);
              }
              return ListView(children: children);
            },
          ),
    );
  }
}

/// Step 2 of the add flow: pick a team from the chosen league (searchable).
/// Adds to [favoriteTeamsProvider] and returns the new [FavoriteTeam].
class _PickTeamPage extends ConsumerStatefulWidget {
  final String league, leagueName;
  const _PickTeamPage({required this.league, required this.leagueName});

  @override
  ConsumerState<_PickTeamPage> createState() => _PickTeamPageState();
}

class _PickTeamPageState extends ConsumerState<_PickTeamPage> {
  String _query = '';

  void _choose(TeamRef t) {
    final fav = FavoriteTeam(
      league: widget.league,
      teamId: t.id,
      name: t.displayName,
      abbr: t.abbreviation,
      logo: t.logo,
    );
    ref.read(favoriteTeamsProvider.notifier).add(fav);
    Navigator.of(context).pop(fav);
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final favs = ref.watch(favoriteTeamsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.leagueName),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search teams',
                isDense: true,
              ),
            ),
          ),
        ),
      ),
      body: ref.watch(teamsProvider(widget.league)).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(
                message: '$e', onRetry: () => ref.invalidate(teamsProvider(widget.league))),
            data: (teams) {
              final list = teams.where((t) {
                if (q.isEmpty) return true;
                return t.displayName.toLowerCase().contains(q) ||
                    (t.abbreviation?.toLowerCase().contains(q) ?? false);
              }).toList();
              if (list.isEmpty) {
                return const EmptyState(
                  icon: Icons.search_off,
                  title: 'No teams found',
                  subtitle: 'Try a different search.',
                );
              }
              return ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final t = list[i];
                  final already =
                      favs.any((f) => f.league == widget.league && f.teamId == t.id);
                  return ListTile(
                    leading: Crest(
                        url: t.logo, darkUrl: t.logoDark, fallback: t.abbreviation ?? t.displayName, size: 28),
                    title: Text(t.displayName),
                    subtitle: t.abbreviation != null ? Text(t.abbreviation!) : null,
                    trailing: already
                        ? Icon(Icons.star, color: BinanceColors.of(context).accent)
                        : const Icon(Icons.add),
                    onTap: already ? () => Navigator.of(context).pop() : () => _choose(t),
                  );
                },
              );
            },
          ),
    );
  }
}
