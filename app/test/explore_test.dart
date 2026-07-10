import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scores/src/models.dart';
import 'package:scores/src/providers.dart';
import 'package:scores/src/theme.dart';
import 'package:scores/src/ui/explore_page.dart';
import 'package:scores/src/ui/league_page.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

Future<SharedPreferences> prefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

final _catalog = [
  CatalogSport.fromJson({
    'sport': 'hockey',
    'leagues': [
      {'key': 'hockey/nhl', 'league': 'nhl', 'name': 'NHL', 'abbr': 'NHL'},
    ],
  }),
  CatalogSport.fromJson({
    'sport': 'rugby',
    'leagues': [
      {
        'key': 'rugby/premiership',
        'league': 'premiership',
        'name': 'Premiership Rugby',
        'region': 'England',
      },
    ],
  }),
  CatalogSport.fromJson({
    'sport': 'baseball',
    'leagues': [
      // Followed by default → must NOT appear in the discovery sections.
      {'key': 'baseball/mlb', 'league': 'mlb', 'name': 'MLB', 'abbr': 'MLB'},
    ],
  }),
];

final _overview = {
  'hockey/nhl': LeagueStateInfo.fromJson(
      {'key': 'hockey/nhl', 'state': 'live', 'detail': 'Live now', 'live': true}),
  'rugby/premiership': LeagueStateInfo.fromJson({
    'key': 'rugby/premiership',
    'state': 'today',
    'detail': '3 games today',
    'live': false,
  }),
  'baseball/mlb': LeagueStateInfo.fromJson({
    'key': 'baseball/mlb',
    'state': 'live',
    'detail': 'Live now',
    'live': true,
  }),
};

void main() {
  testWidgets('explore surfaces unfollowed live/today leagues with pulse',
      (tester) async {
    final p = await prefs(); // default followed includes baseball/mlb
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(p),
        catalogProvider.overrideWith((ref) async => _catalog),
        exploreOverviewProvider.overrideWith((ref) => Stream.value(_overview)),
      ],
      child: MaterialApp(theme: buildV2Theme(), home: const ExplorePage()),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('LIVE NOW'), findsOneWidget);
    expect(find.text('ON TODAY'), findsOneWidget);
    // NHL is live: once in LIVE NOW, once in its sport group.
    expect(find.text('NHL'), findsNWidgets(2));
    expect(find.text('3 games today'), findsNWidgets(2));
    // Followed MLB appears only in its sport group (below the fold), never
    // in the discovery sections above it.
    await tester.dragUntilVisible(
        find.text('MLB'), find.byType(ListView), const Offset(0, -200));
    expect(find.text('MLB'), findsOneWidget);
  });

  testWidgets('league page renders a slate with a follow pill',
      (tester) async {
    final p = await prefs();
    final mlb = ScoresResponse.fromJson(fixture('mlb.json'));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(p),
        leagueScoresProvider.overrideWith((ref, league) async => mlb),
      ],
      child: MaterialApp(
        theme: buildV2Theme(),
        home: const LeaguePage(league: 'hockey/nhl', name: 'NHL'),
      ),
    ));
    await tester.pump();
    await tester.pump();
    // Title resolves from the payload; pill reflects not-followed.
    expect(find.text(mlb.leagueName.toUpperCase()), findsOneWidget);
    expect(find.text('Follow'), findsOneWidget);
    expect(find.textContaining('games today'), findsOneWidget);
    // Tapping the pill follows the league.
    await tester.tap(find.text('Follow'));
    await tester.pump();
    expect(find.text('Following'), findsOneWidget);
    expect(p.getStringList('followed'), contains('hockey/nhl'));
    // Tear down before the poll timer fires.
    await tester.pumpWidget(const SizedBox());
  });
}
