import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scores/src/models.dart';
import 'package:scores/src/providers.dart';
import 'package:scores/src/theme.dart';
import 'package:scores/src/ui/standings_page.dart';

Future<SharedPreferences> prefs([Map<String, Object> seed = const {}]) async {
  SharedPreferences.setMockInitialValues(seed);
  return SharedPreferences.getInstance();
}

Widget wrap(Widget child, List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(theme: buildV2Theme(), home: Scaffold(body: child)),
    );

/// A 2-conference standings with playoffSeed + gamesBehind — the shape the §8a
/// toggle + Wild Card cut are computed from.
Standings _conferenceStandings() => Standings.fromJson({
      'league': 'baseball/mlb',
      'columns': [
        {'key': 'wins', 'label': 'W'},
        {'key': 'losses', 'label': 'L'},
        {'key': 'winPercent', 'label': 'PCT'},
        {'key': 'gamesBehind', 'label': 'GB'},
      ],
      'groups': [
        {
          'name': 'American League',
          'rows': [
            for (final t in const [
              ['1', 'Rays', 1, '-', '0.600'],
              ['2', 'Yankees', 2, '2', '0.560'],
              ['3', 'Jays', 3, '4', '0.520'],
              ['4', 'Sox', 4, '6', '0.480'],
              ['5', 'Os', 5, '8', '0.440'],
            ])
              {
                'team': {'id': t[0], 'name': t[1]},
                'stats': {
                  'playoffSeed': '${t[2]}',
                  'gamesBehind': t[3],
                  'winPercent': t[4],
                  'wins': '50',
                  'losses': '40',
                },
              },
          ],
        },
        {
          'name': 'National League',
          'rows': [
            for (final t in const [
              ['11', 'Cubs', 1, '-', '0.700'],
              ['12', 'Brewers', 2, '3', '0.640'],
              ['13', 'Reds', 3, '5', '0.590'],
              ['14', 'Cards', 4, '7', '0.500'],
            ])
              {
                'team': {'id': t[0], 'name': t[1]},
                'stats': {
                  'playoffSeed': '${t[2]}',
                  'gamesBehind': t[3],
                  'winPercent': t[4],
                  'wins': '52',
                  'losses': '38',
                },
              },
          ],
        },
      ],
    });

/// A soccer-style single table — no playoffSeed, one group.
Standings _singleTable() => Standings.fromJson({
      'league': 'soccer/eng.1',
      'columns': [
        {'key': 'points', 'label': 'PTS'},
      ],
      'groups': [
        {
          'name': 'Premier League',
          'rows': [
            {
              'team': {'id': '1', 'name': 'Arsenal'},
              'rank': 1,
              'stats': {'points': '80'},
            },
            {
              'team': {'id': '2', 'name': 'Chelsea'},
              'rank': 2,
              'stats': {'points': '75'},
            },
          ],
        },
      ],
    });

void main() {
  testWidgets('conference standings show the Division/Wild Card/League toggle',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final p = await prefs({'followed': <String>['baseball/mlb']});
    await tester.pumpWidget(wrap(const StandingsPage(), [
      sharedPrefsProvider.overrideWithValue(p),
      standingsProvider.overrideWith((ref, l) async => _conferenceStandings()),
      catalogProvider.overrideWith((ref) async => <CatalogSport>[]),
    ]));
    await tester.pump();
    await tester.pump();

    expect(find.text('Division'), findsOneWidget);
    expect(find.text('Wild Card'), findsOneWidget);
    expect(find.text('League'), findsOneWidget);
    // Division view is the default: grouped cards.
    expect(find.text('AMERICAN LEAGUE'), findsOneWidget);
    expect(find.text('NATIONAL LEAGUE'), findsOneWidget);
  });

  testWidgets('single-table league hides the toggle', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final p = await prefs({'followed': <String>['soccer/eng.1']});
    await tester.pumpWidget(wrap(const StandingsPage(), [
      sharedPrefsProvider.overrideWithValue(p),
      standingsProvider.overrideWith((ref, l) async => _singleTable()),
      catalogProvider.overrideWith((ref) async => <CatalogSport>[]),
    ]));
    await tester.pump();
    await tester.pump();

    expect(find.text('Wild Card'), findsNothing);
    expect(find.text('PREMIER LEAGUE'), findsOneWidget);
  });

  testWidgets('Wild Card view draws the PLAYOFF LINE and GB deltas',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final p = await prefs({'followed': <String>['baseball/mlb']});
    await tester.pumpWidget(wrap(const StandingsPage(), [
      sharedPrefsProvider.overrideWithValue(p),
      standingsProvider.overrideWith((ref, l) async => _conferenceStandings()),
      catalogProvider.overrideWith((ref) async => <CatalogSport>[]),
    ]));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Wild Card'));
    await tester.pumpAndSettle();

    // Cut at 3 → a line per conference (2 groups).
    expect(find.text('PLAYOFF LINE'), findsNWidgets(2));
    // AL: firstOut (Sox) gb=6 → seed1 (Rays, gb 0) reads +6; seed3 (Jays, gb 4)
    // reads +2; lastIn is Jays. First team out (Sox, gb 6) reads 6-4 = 2.
    expect(find.text('+6'), findsOneWidget);
    expect(find.text('+2'), findsWidgets); // AL Jays; also possibly others
    expect(find.text('Sox'), findsOneWidget);
  });

  testWidgets('League view flattens both conferences into one ranked table',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final p = await prefs({'followed': <String>['baseball/mlb']});
    await tester.pumpWidget(wrap(const StandingsPage(), [
      sharedPrefsProvider.overrideWithValue(p),
      standingsProvider.overrideWith((ref, l) async => _conferenceStandings()),
      catalogProvider.overrideWith((ref) async => <CatalogSport>[]),
    ]));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('League'));
    await tester.pumpAndSettle();

    // One flattened table: both conferences' teams present, group headers gone.
    expect(find.text('AMERICAN LEAGUE'), findsNothing);
    expect(find.text('NATIONAL LEAGUE'), findsNothing);
    expect(find.text('Cubs'), findsOneWidget); // NL
    expect(find.text('Rays'), findsOneWidget); // AL
    // Top of the flattened table is the highest winPercent (Cubs, 0.700).
    expect(find.text('Cubs'), findsOneWidget);
  });

  testWidgets('favorite team row is starred in the Division view',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final p = await prefs({
      'followed': <String>['baseball/mlb'],
      'favoriteTeams': <String>[
        '{"league":"baseball/mlb","teamId":"11","name":"Cubs","color":"cc3433"}'
      ],
    });
    await tester.pumpWidget(wrap(const StandingsPage(), [
      sharedPrefsProvider.overrideWithValue(p),
      standingsProvider.overrideWith((ref, l) async => _conferenceStandings()),
      catalogProvider.overrideWith((ref) async => <CatalogSport>[]),
    ]));
    await tester.pump();
    await tester.pump();

    expect(find.byIcon(Icons.star_rounded), findsWidgets);
  });
}
