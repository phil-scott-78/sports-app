import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scores/src/models.dart';
import 'package:scores/src/providers.dart';
import 'package:scores/src/theme.dart';
import 'package:scores/src/ui/league_page.dart';
import 'package:scores/src/ui/rankings_page.dart';

Future<SharedPreferences> prefs([Map<String, Object> seed = const {}]) async {
  SharedPreferences.setMockInitialValues(seed);
  return SharedPreferences.getInstance();
}

Widget wrap(Widget child, List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(theme: buildV2Theme(), home: child),
    );

Poll _pollOf(String name, String shortName, String prefix, int count) => Poll(
      name: name,
      shortName: shortName,
      ranks: [
        for (var i = 1; i <= count; i++)
          RankEntry(
            current: i,
            team: RankTeam(id: '$prefix-$i', name: '$prefix $i'),
          ),
      ],
    );

const _league = 'football/college-football';

RankingsResponse _fakeRankings() => RankingsResponse(
      league: _league,
      polls: [
        _pollOf('AP Top 25', 'AP', 'Team', 8),
        _pollOf('Coaches Poll', 'Coaches', 'Coach Team', 3),
      ],
    );

List<CatalogSport> _catalogWithRankings() => [
      CatalogSport.fromJson({
        'sport': 'football',
        'leagues': [
          {
            'key': _league,
            'league': 'college-football',
            'name': 'NCAAF',
            'competitorKind': 'team',
            'rankings': 'polls',
          }
        ],
      }),
    ];

void main() {
  testWidgets('RankingsPage: title off the primary poll, one card per poll',
      (tester) async {
    await tester.pumpWidget(wrap(
      const RankingsPage(league: _league),
      [rankingsProvider.overrideWith((ref, league) async => _fakeRankings())],
    ));
    await tester.pump();

    // header title is the primary (first) poll's own name
    expect(find.text('AP TOP 25'), findsWidgets); // header + card label
    // every poll gets its own card — second poll's label present too
    expect(find.text('COACHES POLL'), findsOneWidget);
    // untruncated: all 8 rows of the first poll render
    for (var i = 1; i <= 8; i++) {
      expect(find.text('Team $i'), findsOneWidget);
    }

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'LeaguePage: rankings teaser shows top 5 + See all, See all pushes the full page',
      (tester) async {
    final p = await prefs();
    final scores = ScoresResponse(
      sport: 'football',
      league: _league,
      leagueId: '',
      leagueName: 'NCAAF',
      season: Season(),
      updated: null,
      anyLive: false,
      events: const [],
    );

    await tester.pumpWidget(wrap(
      const LeaguePage(league: _league),
      [
        sharedPrefsProvider.overrideWithValue(p),
        leagueScoresProvider.overrideWith((ref, key) async => scores),
        catalogProvider.overrideWith((ref) async => _catalogWithRankings()),
        rankingsProvider.overrideWith((ref, league) async => _fakeRankings()),
      ],
    ));
    await tester.pump();
    await tester.pump();

    // compact teaser: top 5 of the primary poll only
    for (var i = 1; i <= 5; i++) {
      expect(find.text('Team $i'), findsOneWidget);
    }
    expect(find.text('Team 6'), findsNothing);
    // the second poll (Coaches) doesn't appear in the teaser at all
    expect(find.text('COACHES POLL'), findsNothing);
    expect(find.text('See all 8'), findsOneWidget);

    await tester.tap(find.text('See all 8'));
    await tester.pumpAndSettle();

    // pushed the full rankings page — every row + every poll now present
    expect(find.byType(RankingsPage), findsOneWidget);
    expect(find.text('Team 6'), findsOneWidget);
    expect(find.text('COACHES POLL'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
