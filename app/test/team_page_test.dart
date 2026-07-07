import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scores/src/models.dart';
import 'package:scores/src/providers.dart';
import 'package:scores/src/theme.dart';
import 'package:scores/src/ui/standings_page.dart';
import 'package:scores/src/ui/team_page.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

Future<SharedPreferences> prefs([Map<String, Object> seed = const {}]) async {
  SharedPreferences.setMockInitialValues(seed);
  return SharedPreferences.getInstance();
}

Widget wrap(Widget child, List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(theme: buildV2Theme(), home: child),
    );

void main() {
  test('TeamDetail parses the fixture (identity, schedule, roster, stats, standing)',
      () {
    final d = TeamDetail.fromJson(fixture('teamdetail_nba.json'));
    expect(d.team.displayName, isNotEmpty);
    expect(d.schedule, isNotEmpty);
    // schedule is start-ascending
    for (var i = 1; i < d.schedule.length; i++) {
      final a = d.schedule[i - 1].start, b = d.schedule[i].start;
      if (a != null && b != null) expect(b.isBefore(a), isFalse);
    }
    expect(d.roster, isNotEmpty);
    expect(d.roster.first.athletes, isNotEmpty);
    expect(d.roster.first.athletes.first.name, isNotEmpty);
    expect(d.stats, isNotEmpty);
    expect(d.stats.first.stats, isNotEmpty);
    expect(d.stats.first.stats.first.value, isA<String>());
    expect(d.standing, isNotNull);
    expect(d.standing!.rows, isNotEmpty);
    expect(d.standing!.columns, isNotEmpty);
    // the team's own row is present in its standing group
    expect(d.standing!.rows.any((r) => r.team.id == d.team.id), isTrue);
  });

  testWidgets('TeamPage renders every section', (tester) async {
    // Tall window so the whole single-scroll page lays out (roster is deep).
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final p = await prefs();
    final d = TeamDetail.fromJson(fixture('teamdetail_nba.json'));
    await tester.pumpWidget(wrap(
      TeamPage(
          league: d.league, teamId: d.team.id, name: d.team.displayName),
      [
        sharedPrefsProvider.overrideWithValue(p),
        teamDetailProvider.overrideWith((ref, k) async => d),
        teamCardProvider.overrideWith((ref, k) async => TeamCard(
              league: d.league,
              sport: d.sport,
              leagueName: d.leagueName,
              team: d.team,
              anyLive: false,
            )),
      ],
    ));
    await tester.pump(); // resolve the detail future

    // app bar shouts the name
    expect(find.text(d.team.displayName.toUpperCase()), findsWidgets);
    // every section label present
    expect(find.text('SCHEDULE'), findsOneWidget);
    expect(find.text('STANDING'), findsOneWidget);
    expect(find.text('SEASON STATS'), findsOneWidget);
    expect(find.text('ROSTER'), findsOneWidget);
    // standing group name + a roster athlete render
    expect(find.text(d.standing!.groupName.toUpperCase()), findsWidgets);
    expect(find.text(d.roster.first.athletes.first.name), findsWidgets);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('standings rows: athlete league → tap is inert (no team page)',
      (tester) async {
    final p = await prefs({'followed': <String>['racing/f1']});
    final standings = Standings.fromJson({
      'league': 'racing/f1',
      'columns': [
        {'key': 'championshipPts', 'label': 'PTS'}
      ],
      'groups': [
        {
          'name': 'Driver Standings',
          'rows': [
            {
              'team': {'id': '5829', 'name': 'Kimi Antonelli'},
              'rank': 1,
              'stats': {'championshipPts': '179'},
            },
          ],
        },
      ],
    });
    final catalog = [
      CatalogSport.fromJson({
        'sport': 'racing',
        'leagues': [
          {
            'key': 'racing/f1',
            'league': 'f1',
            'name': 'Formula 1',
            'competitorKind': 'athlete',
          }
        ],
      }),
    ];
    await tester.pumpWidget(wrap(const Scaffold(body: StandingsPage()), [
      sharedPrefsProvider.overrideWithValue(p),
      standingsProvider.overrideWith((ref, key) async => standings),
      catalogProvider.overrideWith((ref) async => catalog),
    ]));
    await tester.pump();
    await tester.pump();

    expect(find.text('Kimi Antonelli'), findsOneWidget);
    await tester.tap(find.text('Kimi Antonelli'));
    await tester.pumpAndSettle();
    // athlete catalog → row is inert, no navigation
    expect(find.byType(TeamPage), findsNothing);
  });

  testWidgets('standings rows: team league → tap opens the team page',
      (tester) async {
    final p = await prefs({'followed': <String>['basketball/nba']});
    final d = TeamDetail.fromJson(fixture('teamdetail_nba.json'));
    final standings = Standings.fromJson({
      'league': 'basketball/nba',
      'columns': [
        {'key': 'wins', 'label': 'W'},
        {'key': 'losses', 'label': 'L'},
      ],
      'groups': [
        {
          'name': 'Eastern Conference',
          'rows': [
            {
              'team': {'id': '1', 'name': 'Atlanta Hawks'},
              'rank': 1,
              'stats': {'wins': '50', 'losses': '32'},
            },
          ],
        },
      ],
    });
    final catalog = [
      CatalogSport.fromJson({
        'sport': 'basketball',
        'leagues': [
          {
            'key': 'basketball/nba',
            'league': 'nba',
            'name': 'NBA',
            'competitorKind': 'team',
          }
        ],
      }),
    ];
    await tester.pumpWidget(wrap(const Scaffold(body: StandingsPage()), [
      sharedPrefsProvider.overrideWithValue(p),
      standingsProvider.overrideWith((ref, key) async => standings),
      catalogProvider.overrideWith((ref) async => catalog),
      teamDetailProvider.overrideWith((ref, k) async => d),
      teamCardProvider.overrideWith((ref, k) async => TeamCard(
            league: d.league,
            sport: d.sport,
            leagueName: d.leagueName,
            team: d.team,
            anyLive: false,
          )),
    ]));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Atlanta Hawks'));
    await tester.pumpAndSettle();
    // team catalog → the row navigates to a team page
    expect(find.byType(TeamPage), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
