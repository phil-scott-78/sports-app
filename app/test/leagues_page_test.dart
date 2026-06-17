import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scores/src/models.dart';
import 'package:scores/src/providers.dart';
import 'package:scores/src/theme.dart';
import 'package:scores/src/ui/league_detail_page.dart';
import 'package:scores/src/ui/leagues_page.dart';
import 'package:scores/src/ui/scores_page.dart' show GameCard;
import 'package:scores/src/ui/widgets.dart' show LiveDot;
import 'package:shared_preferences/shared_preferences.dart';

List<CatalogSport> _catalog() => [
      CatalogSport.fromJson({
        'sport': 'basketball',
        'leagues': [
          {'key': 'basketball/nba', 'league': 'nba', 'name': 'NBA', 'region': 'USA', 'priority': 'v1'}
        ],
      })
    ];

ScoresResponse _resp() => ScoresResponse.fromJson({
      'sport': 'basketball', 'league': 'nba', 'leagueId': '46', 'leagueName': 'NBA', 'anyLive': false,
      'events': [
        {
          'id': '1', 'name': 'Away at Home', 'shortName': 'AWY @ HOM',
          'start': DateTime.now().toUtc().toIso8601String(),
          'competitions': [
            {
              'id': '1', 'layout': 'headToHead', 'scoreKind': 'numeric', 'competitorKind': 'team',
              'status': {'phase': 'scheduled', 'live': false, 'ended': false, 'period': 0, 'periodLabel': '', 'espnName': 'STATUS_SCHEDULED', 'detail': ''},
              'periods': {'unit': 'quarter', 'regulation': 4, 'played': 0, 'isOvertime': false},
              'competitors': [
                {'kind': 'team', 'id': '10', 'displayName': 'Home', 'abbreviation': 'HOM', 'homeAway': 'home'},
                {'kind': 'team', 'id': '20', 'displayName': 'Away', 'abbreviation': 'AWY', 'homeAway': 'away'},
              ],
            }
          ],
        }
      ],
    });

ScoresResponse _liveResp(int homeScore) => ScoresResponse.fromJson({
      'sport': 'basketball', 'league': 'nba', 'leagueId': '46', 'leagueName': 'NBA', 'anyLive': true,
      'events': [
        {
          'id': '1', 'name': 'Away at Home', 'shortName': 'AWY @ HOM',
          'start': DateTime.now().toUtc().toIso8601String(),
          'competitions': [
            {
              'id': '1', 'layout': 'headToHead', 'scoreKind': 'numeric', 'competitorKind': 'team',
              'status': {'phase': 'live', 'live': true, 'ended': false, 'period': 3, 'periodLabel': '3rd 7:12', 'espnName': 'STATUS_IN_PROGRESS', 'detail': ''},
              'periods': {'unit': 'quarter', 'regulation': 4, 'played': 3, 'isOvertime': false},
              'competitors': [
                {'kind': 'team', 'id': '10', 'displayName': 'Home', 'abbreviation': 'HOM', 'homeAway': 'home', 'score': {'display': '$homeScore', 'value': homeScore}},
                {'kind': 'team', 'id': '20', 'displayName': 'Away', 'abbreviation': 'AWY', 'homeAway': 'away', 'score': {'display': '80', 'value': 80}},
              ],
            }
          ],
        }
      ],
    });

Standings _standings() => Standings.fromJson({
      'league': 'basketball/nba', 'season': 2026,
      'groups': [
        {'name': 'East', 'rows': [{'team': {'id': '10', 'name': 'Home', 'abbr': 'HOM'}, 'rank': 1, 'stats': {'wins': '50', 'losses': '20'}}]}
      ],
    });

Future<void> _pump(WidgetTester tester, LeagueStateInfo state) async {
  SharedPreferences.setMockInitialValues({'baseUrl': 'https://w.example', 'followed': <String>[]});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      catalogProvider.overrideWith((ref) async => _catalog()),
      // Default tier reads the popular (v1) pulse; pinned is empty here.
      popularOverviewProvider.overrideWith((ref) async => {'basketball/nba': state}),
      pinnedOverviewProvider
          .overrideWith((ref) async => const <String, LeagueStateInfo>{}),
      leagueDayScoresProvider.overrideWith((ref, key) async => _resp()),
      standingsProvider.overrideWith((ref, league) async => _standings()),
    ],
    child: MaterialApp(theme: buildTheme(Brightness.dark), home: const LeaguesPage()),
  ));
  await tester.pump(const Duration(milliseconds: 50)); // resolve catalog + overview
}

void main() {
  testWidgets('row shows the pulse caption and opens the Schedule|Standings detail', (tester) async {
    // 'today' => a static dot (no repeating animation), so pumpAndSettle is safe.
    await _pump(tester, LeagueStateInfo(key: 'basketball/nba', state: 'today', detail: 'Games today', live: false));

    expect(find.text('NBA'), findsOneWidget);
    expect(find.text('USA · Games today'), findsOneWidget);

    await tester.tap(find.text('NBA'));
    await tester.pumpAndSettle();

    // Tabbed detail: Schedule (with the league's game card) + Standings.
    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('Standings'), findsOneWidget);
    expect(find.byType(GameCard), findsWidgets);

    await tester.tap(find.text('Standings'));
    await tester.pumpAndSettle();
    expect(find.text('East'), findsOneWidget);

    // Unmount so the Schedule tab's live-poll timer is disposed.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the Schedule tab auto-refreshes a live day on the 15s beat', (tester) async {
    var homeScore = 88;
    SharedPreferences.setMockInitialValues({'baseUrl': 'https://w.example', 'followed': <String>[]});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      standingsProvider.overrideWith((ref, league) async => _standings()),
      // Re-read on every (re)build of the provider — invalidation picks up the new score.
      leagueDayScoresProvider.overrideWith((ref, key) async => _liveResp(homeScore)),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: const LeagueDetailPage(league: 'basketball/nba', name: 'NBA'),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50)); // resolve the initial fetch
    expect(find.text('88'), findsWidgets);

    // The live score ticks; advancing past the 15s live cadence must re-fetch it.
    homeScore = 91;
    await tester.pump(const Duration(seconds: 16)); // fires the poll timer → invalidate
    await tester.pump(const Duration(milliseconds: 50)); // resolve the refetch + rebuild
    expect(find.text('91'), findsWidgets, reason: 'poll pulled the updated score');
    expect(find.text('88'), findsNothing, reason: 'stale score replaced');

    await tester.pumpWidget(const SizedBox()); // dispose the poll timer
  });

  testWidgets('a live league shows a pulsing dot and "Live now"', (tester) async {
    await _pump(tester, LeagueStateInfo(key: 'basketball/nba', state: 'live', detail: 'Live now', live: true));

    expect(find.text('USA · Live now'), findsOneWidget);
    expect(find.byType(LiveDot), findsOneWidget);

    // Unmount so the LiveDot's repeating ticker is disposed (no pending-frame nag).
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tiers filter the catalog: Default=v1, All=everything, Active=in-season', (tester) async {
    final catalog = [
      CatalogSport.fromJson({'sport': 'basketball', 'leagues': [
        {'key': 'basketball/nba', 'league': 'nba', 'name': 'NBA', 'region': 'USA', 'priority': 'v1'},
      ]}),
      CatalogSport.fromJson({'sport': 'soccer', 'leagues': [
        {'key': 'soccer/eng.2', 'league': 'eng.2', 'name': 'Championship', 'region': 'England', 'priority': 'v2'},
        {'key': 'soccer/cyp.1', 'league': 'cyp.1', 'name': 'Cypriot First Division', 'region': 'Cyprus', 'priority': 'v3'},
      ]}),
    ];
    // NBA is on today; the Championship (v2) is offseason → not "active".
    final active = <String, LeagueStateInfo>{
      'basketball/nba': LeagueStateInfo(key: 'basketball/nba', state: 'today', detail: 'Games today', live: false),
      'soccer/eng.2': LeagueStateInfo(key: 'soccer/eng.2', state: 'offseason', detail: 'Returns Aug 9', live: false),
    };
    SharedPreferences.setMockInitialValues({'baseUrl': 'https://w.example', 'followed': <String>[]});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        catalogProvider.overrideWith((ref) async => catalog),
        popularOverviewProvider.overrideWith((ref) async => {'basketball/nba': active['basketball/nba']!}),
        activeOverviewProvider.overrideWith((ref) async => active),
        pinnedOverviewProvider.overrideWith((ref) async => const <String, LeagueStateInfo>{}),
      ],
      child: MaterialApp(theme: buildTheme(Brightness.dark), home: const LeaguesPage()),
    ));
    await tester.pump(const Duration(milliseconds: 50));

    // Default (lands): only v1.
    expect(find.text('NBA'), findsOneWidget);
    expect(find.text('Championship'), findsNothing);
    expect(find.text('Cypriot First Division'), findsNothing);

    // All: everything.
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.text('NBA'), findsOneWidget);
    expect(find.text('Championship'), findsOneWidget);
    expect(find.text('Cypriot First Division'), findsOneWidget);

    // Active: v1+v2 that are in-season → NBA only (Championship is offseason; v3 out of scope).
    await tester.tap(find.text('Active'));
    await tester.pumpAndSettle(); // resolves the Active tier's (late-watched) pulse
    expect(find.text('NBA'), findsOneWidget);
    expect(find.text('Championship'), findsNothing);
    expect(find.text('Cypriot First Division'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a followed league pins to the top even when its tier would hide it', (tester) async {
    final catalog = [
      CatalogSport.fromJson({'sport': 'soccer', 'leagues': [
        {'key': 'soccer/cyp.1', 'league': 'cyp.1', 'name': 'Cypriot First Division', 'region': 'Cyprus', 'priority': 'v3'},
      ]}),
    ];
    SharedPreferences.setMockInitialValues({'baseUrl': 'https://w.example', 'followed': ['soccer/cyp.1']});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        catalogProvider.overrideWith((ref) async => catalog),
        popularOverviewProvider.overrideWith((ref) async => const <String, LeagueStateInfo>{}),
        pinnedOverviewProvider.overrideWith((ref) async =>
            {'soccer/cyp.1': LeagueStateInfo(key: 'soccer/cyp.1', state: 'today', detail: 'Games today', live: false)}),
      ],
      child: MaterialApp(theme: buildTheme(Brightness.dark), home: const LeaguesPage()),
    ));
    await tester.pump(const Duration(milliseconds: 50));

    // A v3 league is hidden in Default — but following it pins it to the top.
    expect(find.text('Pinned'), findsOneWidget);
    expect(find.text('Cypriot First Division'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
