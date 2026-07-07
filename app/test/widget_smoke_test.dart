import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scores/src/models.dart';
import 'package:scores/src/providers.dart';
import 'package:scores/src/theme.dart';
import 'package:scores/src/ui/game_detail_page.dart';
import 'package:scores/src/ui/scores_page.dart';
import 'package:scores/src/ui/standings_page.dart';
import 'package:scores/src/ui/widgets.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

Future<SharedPreferences> prefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

Widget wrap(Widget child, List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(theme: buildV2Theme(), home: Scaffold(body: child)),
    );

void main() {
  testWidgets('home feed renders league sections with live rows',
      (tester) async {
    final p = await prefs();
    final mlb = ScoresResponse.fromJson(fixture('mlb.json'));
    await tester.pumpWidget(wrap(const ScoresPage(), [
      sharedPrefsProvider.overrideWithValue(p),
      feedProvider
          .overrideWith((ref) async => [LeagueFeed('baseball/mlb', mlb)]),
      favoritesFeedProvider.overrideWith((ref) async => [
            FavoriteTeamFeed(
              const FavoriteTeam(
                  league: 'basketball/nba', teamId: '5', name: 'Cavaliers'),
              TeamCard.fromJson(fixture('teamcard_nba.json')),
            ),
          ]),
    ]));
    await tester.pump(); // resolve futures
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text(mlb.leagueName.toUpperCase()), findsOneWidget);
    // A live baseball row shows the mini diamond.
    expect(find.byType(MiniDiamond), findsWidgets);
    // Tear down before the poll timer fires.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('game detail shows score block, chips, and situation card',
      (tester) async {
    final p = await prefs();
    final mlb = ScoresResponse.fromJson(fixture('mlb.json'));
    final live = mlb.events.firstWhere((e) =>
        e.main!.status.live && (e.main!.situation?.hasBaseball ?? false));
    final summary = GameSummary.fromJson(fixture('summary_nfl.json'));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(p),
        leagueScoresProvider.overrideWith((ref, league) async => mlb),
        summaryProvider.overrideWith((ref, key) async => summary),
      ],
      child: MaterialApp(
        theme: buildV2Theme(),
        home: GameDetailPage(league: 'baseball/mlb', initialEvent: live),
      ),
    ));
    await tester.pump();
    // Giant score block: both team names, shouted.
    final comp = live.main!;
    for (final c in comp.competitors) {
      expect(
        find.textContaining((c.shortName ?? c.displayName).toUpperCase()),
        findsWidgets,
      );
    }
    // Chip nav present with the live-phase chip.
    expect(find.text('Now'), findsOneWidget);
    // Baseball situation card: the diamond.
    expect(find.byType(BaseballDiamond), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('standings renders groups with favorite highlight',
      (tester) async {
    final p = await prefs();
    final standings = Standings.fromJson({
      'league': 'baseball/mlb',
      'columns': [
        {'key': 'wins', 'label': 'W'},
        {'key': 'losses', 'label': 'L'},
        {'key': 'streak', 'label': 'STRK'},
      ],
      'groups': [
        {
          'name': 'NL Central',
          'rows': [
            {
              'team': {'id': '16', 'name': 'Cubs'},
              'rank': 1,
              'stats': {'wins': '52', 'losses': '34', 'streak': 'W4'},
            },
            {
              'team': {'id': '8', 'name': 'Brewers'},
              'rank': 2,
              'stats': {'wins': '50', 'losses': '37', 'streak': 'L1'},
            },
          ],
        },
      ],
    });
    await tester.pumpWidget(wrap(const StandingsPage(), [
      sharedPrefsProvider.overrideWithValue(p),
      standingsProvider.overrideWith((ref, league) async => standings),
      catalogProvider.overrideWith((ref) async => []),
    ]));
    // First frame kicks off async loads; settle a few frames.
    await tester.pump();
    await tester.pump();
    expect(find.text('STANDINGS'), findsOneWidget);
    expect(find.text('NL CENTRAL'), findsOneWidget);
    expect(find.text('Cubs'), findsOneWidget);
    expect(find.text('W4'), findsOneWidget);
  });
}
