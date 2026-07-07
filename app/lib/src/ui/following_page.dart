import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import '../util.dart';
import 'add_pages.dart';
import 'explore_page.dart';
import 'league_page.dart';
import 'team_page.dart';
import 'widgets.dart';

/// The Following tab: drag to reorder favorites (their hero-card order) and
/// followed leagues (their feed section order), minus to remove, plus explicit
/// add flows. Long-press anywhere in the app also lands things here.
class FollowingPage extends ConsumerWidget {
  const FollowingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favs = ref.watch(favoriteTeamsProvider);
    final leagues = ref.watch(followedProvider);
    final catalog = ref.watch(catalogProvider).valueOrNull;

    return ListView(
      padding: const EdgeInsets.only(bottom: T.scrollBottom),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(T.pageMargin, 14, T.pageMargin, 0),
          child: Text('FOLLOWING', style: T.pageTitle),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(T.pageMargin, 6, T.pageMargin, 0),
          child: Text('Drag to set the order of your home feed.',
              style: T.caption),
        ),
        _label('Teams'),
        if (favs.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: T.pageMargin),
            child: HintCard('No favorite teams yet.'),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.symmetric(horizontal: T.pageMargin),
            itemCount: favs.length,
            proxyDecorator: _proxyDecorator,
            onReorderItem: (a, b) =>
                ref.read(favoriteTeamsProvider.notifier).reorder(a, b),
            itemBuilder: (context, i) => Padding(
              key: ValueKey(favs[i].id),
              padding: const EdgeInsets.only(bottom: 8),
              child: _FollowRow(
                index: i,
                bar: ColorBar(teamColorOf(favs[i].color),
                    width: 6, height: 22),
                title: favs[i].name,
                subtitle: _leagueName(favs[i].league, catalog),
                onTap: () => openTeamPage(context, favs[i].league,
                    teamId: favs[i].teamId,
                    name: favs[i].name,
                    color: favs[i].color),
                onRemove: () => ref
                    .read(favoriteTeamsProvider.notifier)
                    .remove(favs[i].league, favs[i].teamId),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(T.pageMargin, 0, T.pageMargin, 0),
          child: _AddTile(
            label: 'Add a team',
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AddTeamPage())),
          ),
        ),
        _label('Leagues'),
        if (leagues.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: T.pageMargin),
            child: HintCard('No followed leagues yet.'),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.symmetric(horizontal: T.pageMargin),
            itemCount: leagues.length,
            proxyDecorator: _proxyDecorator,
            onReorderItem: (a, b) =>
                ref.read(followedProvider.notifier).reorder(a, b),
            itemBuilder: (context, i) => Padding(
              key: ValueKey(leagues[i]),
              padding: const EdgeInsets.only(bottom: 8),
              child: _FollowRow(
                index: i,
                title: _leagueName(leagues[i], catalog),
                subtitle: 'All games in feed',
                onTap: () => openLeaguePage(context, leagues[i],
                    name: _leagueName(leagues[i], catalog)),
                onRemove: () =>
                    ref.read(followedProvider.notifier).remove(leagues[i]),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: T.pageMargin),
          child: _AddTile(
            label: 'Follow a league',
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ExplorePage())),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(T.pageMargin, 20, T.pageMargin, 0),
          child: HintCard(
              'Long-press any team or game in the app to add it here'),
        ),
      ],
    );
  }

  Widget _label(String text) => Padding(
        padding: T.sectionHeaderPad,
        child: Text(text.toUpperCase(), style: T.cardLabel),
      );

  Widget _proxyDecorator(Widget child, int index, Animation<double> anim) =>
      AnimatedBuilder(
        animation: anim,
        builder: (context, _) => Transform.rotate(
          angle: -0.012,
          child: Material(
            color: Colors.transparent,
            elevation: 8,
            borderRadius: BorderRadius.circular(T.rowCardRadius),
            shadowColor: Colors.black.withValues(alpha: 0.55),
            child: child,
          ),
        ),
      );

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
}

class _FollowRow extends StatelessWidget {
  final int index;
  final Widget? bar;
  final String title;
  final String subtitle;
  final VoidCallback onRemove;
  final VoidCallback? onTap;
  const _FollowRow({
    required this.index,
    this.bar,
    required this.title,
    required this.subtitle,
    required this.onRemove,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: T.surface,
          borderRadius: BorderRadius.circular(T.rowCardRadius),
        ),
        child: Row(children: [
          GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                  color: T.border, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: const Text('−',
                  style: TextStyle(
                      color: T.live,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      height: 1.1)),
            ),
          ),
          const SizedBox(width: 14),
          if (bar != null) ...[bar!, const SizedBox(width: 14)],
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: T.rowText),
                    Text(subtitle, style: T.captionFaint),
                  ]),
            ),
          ),
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Icon(Icons.drag_handle_rounded,
                  size: 20, color: T.outline),
            ),
          ),
        ]),
      );
}

class _AddTile extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _AddTile({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(T.rowCardRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            border: Border.all(color: T.border, width: 1.5),
            borderRadius: BorderRadius.circular(T.rowCardRadius),
          ),
          child: Row(children: [
            const Icon(Icons.add_rounded, size: 18, color: T.textDim),
            const SizedBox(width: 14),
            Text(label,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: T.textDim)),
          ]),
        ),
      );
}
