import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers.dart';
import 'add_leagues_page.dart';
import 'widgets.dart';

/// Reorder + remove the leagues you follow. The followed-list order drives the
/// Scores feed, so dragging here re-orders the home tab. Reached from Settings.
class ManageLeaguesPage extends ConsumerWidget {
  const ManageLeaguesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final followed = ref.watch(followedProvider);
    // Catalog is best-effort: map followed keys → display names; fall back to the
    // raw key if it hasn't loaded or the league isn't in the catalog. Reorder /
    // remove never depend on the catalog, so a catalog error doesn't block them.
    final byKey = <String, CatalogLeague>{};
    for (final s in ref.watch(catalogProvider).valueOrNull ?? const <CatalogSport>[]) {
      for (final lg in s.leagues) {
        byKey[lg.key] = lg;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage leagues'),
        actions: [
          IconButton(
            tooltip: 'Add leagues',
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AddLeaguesPage())),
          ),
        ],
      ),
      body: followed.isEmpty
          ? EmptyState(
              icon: Icons.emoji_events_outlined,
              title: 'No leagues followed',
              subtitle: 'Add leagues to see their scores on the Scores tab.',
              action: FilledButton(
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AddLeaguesPage())),
                child: const Text('Add leagues'),
              ),
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              buildDefaultDragHandles: false,
              itemCount: followed.length,
              onReorderItem: (o, n) => ref.read(followedProvider.notifier).reorder(o, n),
              // The row is already a flat ListCard (its own surface + hairline),
              // so the drag proxy stays a transparent Material — no second
              // surface, no M3 elevation tint to reintroduce.
              proxyDecorator: (child, index, animation) =>
                  Material(type: MaterialType.transparency, child: child),
              itemBuilder: (context, i) {
                final key = followed[i];
                final lg = byKey[key];
                final region = lg?.region;
                return ListCard(
                  key: ValueKey(key),
                  child: ListTile(
                    title: Text(lg?.name ?? key),
                    subtitle: (region != null && region.isNotEmpty) ? Text(region) : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Remove',
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () => ref.read(followedProvider.notifier).remove(key),
                        ),
                        ReorderableDragStartListener(
                          index: i,
                          child: Icon(Icons.drag_handle,
                              color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
