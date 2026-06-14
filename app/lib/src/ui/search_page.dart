import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers.dart';
import 'scores_page.dart' show GameCard, feedSport;
import 'widgets.dart';

/// Lightweight team/league search over today's loaded feeds — the Header-C
/// search affordance. No new network call: it filters the already-fetched
/// [feedProvider] events by team or league name. Results reuse [GameCard] so a
/// tap opens the same game detail as the list.
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});
  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _matches(LeagueFeed feed, SportEvent ev, String q) {
    final name = feed.scores?.leagueName ?? feed.key;
    final hay = StringBuffer(name.toLowerCase())..write(' ${ev.name.toLowerCase()}');
    for (final c in ev.main?.competitors ?? const <Competitor>[]) {
      hay
        ..write(' ${c.displayName.toLowerCase()}')
        ..write(' ${(c.shortName ?? '').toLowerCase()}')
        ..write(' ${(c.abbreviation ?? '').toLowerCase()}');
    }
    return hay.toString().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final feeds = ref.watch(feedProvider).valueOrNull ?? const <LeagueFeed>[];
    final q = _q.trim().toLowerCase();

    final results = <Widget>[];
    for (final feed in feeds) {
      final events = feed.scores?.events ?? const <SportEvent>[];
      for (final ev in events) {
        if (q.isNotEmpty && !_matches(feed, ev, q)) continue;
        results.add(Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: GameCard(
            event: ev,
            sport: feed.scores?.sport ?? feedSport(feed),
            leagueKey: feed.key,
            leagueName:
                feed.scores?.leagueName.isNotEmpty == true ? feed.scores!.leagueName : feed.key,
          ),
        ));
      }
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: (v) => setState(() => _q = v),
          decoration: InputDecoration(
            hintText: 'Search teams, leagues…',
            border: InputBorder.none,
            filled: false,
            isDense: true,
            suffixIcon: _q.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () {
                      _controller.clear();
                      setState(() => _q = '');
                    },
                  ),
          ),
        ),
      ),
      body: results.isEmpty
          ? EmptyState(
              icon: q.isEmpty ? Icons.search : Icons.search_off,
              title: q.isEmpty ? 'Search today\'s games' : 'No matches',
              subtitle: q.isEmpty
                  ? 'Find a team or league across today\'s slate.'
                  : 'Try a different team or league name.',
            )
          : ListView(
              padding: const EdgeInsets.only(top: 8),
              children: [...results, const SizedBox(height: 16)],
            ),
    );
  }
}
