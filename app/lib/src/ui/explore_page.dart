import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import 'league_page.dart';
import 'widgets.dart';

/// The league browser: what's on right now across every league, followed or
/// not. LIVE NOW and ON TODAY surface leagues you don't follow (your own are
/// already on the home feed); below, the full catalog grouped by sport with
/// season-pulse captions. Tap a league to see its slate, follow it from
/// there — or toggle follow directly on the row.
class ExplorePage extends ConsumerStatefulWidget {
  const ExplorePage({super.key});
  @override
  ConsumerState<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends ConsumerState<ExplorePage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    final overview =
        ref.watch(exploreOverviewProvider).valueOrNull ?? const {};
    final followed = ref.watch(followedProvider);

    return Scaffold(
      appBar: subpageBar(context, 'Explore'),
      body: switch (catalog) {
        AsyncData(:final value) => Column(children: [
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(T.pageMargin, 8, T.pageMargin, 4),
              child: V2SearchField(
                  hint: 'Search leagues',
                  onChanged: (q) => setState(() => _query = q.toLowerCase())),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 28),
                children: _query.isEmpty
                    ? _browse(value, overview, followed)
                    : _searchResults(value, overview, followed),
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

  List<Widget> _browse(
    List<CatalogSport> catalog,
    Map<String, LeagueStateInfo> overview,
    List<String> followed,
  ) {
    final byKey = {
      for (final s in catalog)
        for (final l in s.leagues) l.key: l,
    };
    // Discovery sections: pulse states for leagues NOT already in the feed.
    final live = <CatalogLeague>[];
    final today = <CatalogLeague>[];
    for (final info in overview.values) {
      final l = byKey[info.key];
      if (l == null || followed.contains(l.key)) continue;
      if (info.live) {
        live.add(l);
      } else if (info.state == 'today') {
        today.add(l);
      }
    }
    return [
      if (live.isNotEmpty) ...[
        _label('Live now'),
        _card([for (final l in live) _row(l, overview[l.key], followed)]),
      ],
      if (today.isNotEmpty) ...[
        _label('On today'),
        _card([for (final l in today) _row(l, overview[l.key], followed)]),
      ],
      for (final sport in catalog)
        if (sport.leagues.isNotEmpty) ...[
          _label(sport.sport),
          _card([
            for (final l in sport.leagues) _row(l, overview[l.key], followed)
          ]),
        ],
    ];
  }

  List<Widget> _searchResults(
    List<CatalogSport> catalog,
    Map<String, LeagueStateInfo> overview,
    List<String> followed,
  ) {
    final hits = <CatalogLeague>[
      for (final s in catalog)
        for (final l in s.leagues)
          if (l.name.toLowerCase().contains(_query) ||
              (l.abbr ?? '').toLowerCase().contains(_query) ||
              (l.region ?? '').toLowerCase().contains(_query))
            l,
    ];
    if (hits.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.all(T.pageMargin),
          child: HintCard('No leagues match.'),
        ),
      ];
    }
    return [
      const SizedBox(height: 10),
      _card([for (final l in hits) _row(l, overview[l.key], followed)]),
    ];
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(T.pageMargin, 18, T.pageMargin, 6),
        // §3/§5 section headers speak the Barlow scoreboard voice, not copy voice.
        child: Text(text.toUpperCase(), style: T.sectionTitle),
      );

  Widget _card(List<Widget> rows) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: T.pageMargin),
        child: Container(
          decoration: BoxDecoration(
            color: T.surface,
            borderRadius: BorderRadius.circular(T.rowCardRadius),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (var i = 0; i < rows.length; i++)
              i == 0
                  ? rows[i]
                  : DecoratedBox(
                      decoration: const BoxDecoration(
                          border:
                              Border(top: BorderSide(color: T.divider))),
                      child: rows[i],
                    ),
          ]),
        ),
      );

  Widget _row(
      CatalogLeague l, LeagueStateInfo? info, List<String> followed) {
    final on = followed.contains(l.key);
    final caption = info != null && info.detail.isNotEmpty
        ? info.detail
        : (l.region ?? '');
    return InkWell(
      onTap: () => openLeaguePage(context, l.key, name: l.name),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 11, 8, 11),
        child: Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.rowText),
              if (caption.isNotEmpty)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  if (info?.live == true) ...[
                    const LiveDot(),
                    const SizedBox(width: 5),
                  ],
                  Flexible(
                    child: Text(caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: info?.live == true
                            ? T.captionFaint.copyWith(color: T.textDim)
                            : T.captionFaint),
                  ),
                ]),
            ]),
          ),
          IconButton(
            onPressed: () =>
                ref.read(followedProvider.notifier).toggle(l.key),
            icon: Icon(
              on ? Icons.check_circle_rounded : Icons.add_circle_outline,
              size: 20,
              color: on ? T.gold : T.outline,
            ),
          ),
        ]),
      ),
    );
  }
}
