import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../theme.dart';
import 'widgets.dart';

/// Browse the full catalog and follow/unfollow leagues. Writes the same
/// [followedProvider] the Leagues-tab star uses, so the two stay in sync. New
/// follows append to the end of the followed list (reorder on Manage leagues).
class AddLeaguesPage extends ConsumerStatefulWidget {
  const AddLeaguesPage({super.key});

  @override
  ConsumerState<AddLeaguesPage> createState() => _AddLeaguesPageState();
}

class _AddLeaguesPageState extends ConsumerState<AddLeaguesPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final followed = ref.watch(followedProvider);
    final q = _query.trim().toLowerCase();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add leagues'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search leagues',
                isDense: true,
              ),
            ),
          ),
        ),
      ),
      body: ref.watch(catalogProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(message: '$e', onRetry: () => ref.invalidate(catalogProvider)),
            data: (sports) {
              final children = <Widget>[];
              for (final s in sports) {
                final leagues = s.leagues.where((lg) {
                  if (q.isEmpty) return true;
                  return lg.name.toLowerCase().contains(q) ||
                      (lg.region?.toLowerCase().contains(q) ?? false);
                }).toList();
                if (leagues.isEmpty) continue;
                children.add(SectionHeader(sportLabel(s.sport)));
                for (final lg in leagues) {
                  final isFollowed = followed.contains(lg.key);
                  final region = lg.region;
                  children.add(ListCard(
                    child: ListTile(
                      title: Text(lg.name),
                      subtitle: (region != null && region.isNotEmpty) ? Text(region) : null,
                      trailing: IconButton(
                        tooltip: isFollowed ? 'Unfollow' : 'Follow',
                        icon: Icon(isFollowed ? Icons.star : Icons.star_border,
                            color: isFollowed ? BinanceColors.of(context).accent : null),
                        onPressed: () => ref.read(followedProvider.notifier).toggle(lg.key),
                      ),
                    ),
                  ));
                }
              }
              if (children.isEmpty) {
                return const EmptyState(
                  icon: Icons.search_off,
                  title: 'No leagues found',
                  subtitle: 'Try a different search.',
                );
              }
              return ListView(children: children);
            },
          ),
    );
  }
}
