import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scores/src/models.dart';
import 'package:scores/src/providers.dart';
import 'package:scores/src/ui/detail_panels.dart';
import 'package:scores/src/ui/game_detail_page.dart';
import 'package:scores/src/ui/scoring_timeline.dart';
import 'package:scores/src/ui/series_pips.dart';
import 'package:scores/src/ui/summary_feed.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A basketball playoff event carrying a structured series + per-period nothing.
ScoresResponse _seriesResp() => ScoresResponse.fromJson({
      'sport': 'basketball', 'league': 'nba', 'leagueId': '46', 'leagueName': 'NBA', 'anyLive': false,
      'events': [
        {
          'id': '1', 'name': 'Away at Home', 'shortName': 'AWY @ HOM',
          'start': '2026-06-13T00:00:00Z',
          'competitions': [
            {
              'id': '1', 'layout': 'headToHead', 'scoreKind': 'numeric', 'competitorKind': 'team',
              'status': {'phase': 'final', 'live': false, 'ended': true, 'period': 4, 'periodLabel': 'Final', 'espnName': 'STATUS_FINAL', 'detail': 'Final'},
              'periods': {'unit': 'quarter', 'regulation': 4, 'played': 4, 'isOvertime': false},
              'meta': {
                'round': 'NBA Finals - Game 6',
                'seriesSummary': 'HOM leads series 3-2',
                'series': {
                  'type': 'playoff', 'total': 7, 'completed': false,
                  'competitors': [
                    {'id': '10', 'wins': 3},
                    {'id': '20', 'wins': 2},
                  ],
                },
              },
              'competitors': [
                {'kind': 'team', 'id': '10', 'displayName': 'Home', 'abbreviation': 'HOM', 'homeAway': 'home', 'winner': true, 'score': {'display': '101', 'value': 101}},
                {'kind': 'team', 'id': '20', 'displayName': 'Away', 'abbreviation': 'AWY', 'homeAway': 'away', 'winner': false, 'score': {'display': '99', 'value': 99}},
              ],
            }
          ],
        }
      ],
    });

/// A finished NHL game where ESPN gave the away team leaders but (when
/// [homeLeaders] is false) omitted the home team's — the real quirk that left
/// VGK blank in the 2026 Cup final.
ScoresResponse _leadersResp({required bool homeLeaders}) =>
    ScoresResponse.fromJson({
      'sport': 'hockey', 'league': 'nhl', 'leagueId': '90', 'leagueName': 'NHL',
      'anyLive': false,
      'events': [
        {
          'id': '1', 'name': 'Away at Home', 'shortName': 'AWY @ HOM',
          'start': '2026-06-13T00:00:00Z',
          'competitions': [
            {
              'id': '1', 'layout': 'headToHead', 'scoreKind': 'numeric',
              'competitorKind': 'team',
              'status': {'phase': 'final', 'live': false, 'ended': true, 'period': 3, 'periodLabel': 'Final', 'espnName': 'STATUS_FINAL', 'detail': 'Final'},
              'periods': {'unit': 'period', 'regulation': 3, 'played': 3, 'isOvertime': false},
              'competitors': [
                {
                  'kind': 'team', 'id': 'a', 'displayName': 'Away', 'abbreviation': 'CAR', 'homeAway': 'away', 'winner': true,
                  'score': {'display': '5', 'value': 5},
                  'leaders': [
                    {'name': 'goals', 'label': 'Goals', 'athlete': 'J. Blake', 'display': '1'},
                    {'name': 'assists', 'label': 'Assists', 'athlete': 'S. Aho', 'display': '2'},
                    {'name': 'points', 'label': 'Points', 'athlete': 'S. Jarvis', 'display': '2'},
                  ],
                },
                {
                  'kind': 'team', 'id': 'h', 'displayName': 'Home', 'abbreviation': 'VGK', 'homeAway': 'home', 'winner': false,
                  'score': {'display': '1', 'value': 1},
                  if (homeLeaders)
                    'leaders': [
                      {'name': 'goals', 'label': 'Goals', 'athlete': 'S. Theodore', 'display': '1'},
                      {'name': 'assists', 'label': 'Assists', 'athlete': 'B. McNabb', 'display': '1'},
                      {'name': 'points', 'label': 'Points', 'athlete': 'J. Eichel', 'display': '1'},
                    ],
                },
              ],
            }
          ],
        }
      ],
    });

/// A finished soccer match carrying a cheap goal/card timeline.
ScoresResponse _soccerResp() => ScoresResponse.fromJson({
      'sport': 'soccer', 'league': 'usa.1', 'leagueId': '770', 'leagueName': 'MLS', 'anyLive': false,
      'events': [
        {
          'id': '1', 'name': 'Away at Home', 'shortName': 'AWY @ HOM',
          'start': '2026-05-24T00:00:00Z',
          'competitions': [
            {
              'id': '1', 'layout': 'headToHead', 'scoreKind': 'numeric', 'competitorKind': 'team',
              'status': {'phase': 'final', 'live': false, 'ended': true, 'period': 2, 'periodLabel': 'FT', 'espnName': 'STATUS_FULL_TIME', 'detail': 'FT'},
              'periods': {'unit': 'half', 'regulation': 2, 'played': 2, 'isOvertime': false},
              'competitors': [
                {'kind': 'team', 'id': 'h', 'displayName': 'Home', 'abbreviation': 'HOM', 'homeAway': 'home', 'winner': true, 'score': {'display': '2', 'value': 2}},
                {'kind': 'team', 'id': 'a', 'displayName': 'Away', 'abbreviation': 'AWY', 'homeAway': 'away', 'winner': false, 'score': {'display': '1', 'value': 1}},
              ],
              'events': [
                {'type': 'goal', 'team': 'home', 'clock': "24'", 'athlete': 'S. Bangoura', 'detail': 'Goal', 'scoreValue': 1},
                {'type': 'yellow-card', 'team': 'away', 'clock': "31'", 'athlete': 'J. Doe', 'detail': 'Yellow Card'},
                {'type': 'red-card', 'team': 'away', 'clock': "60'", 'athlete': 'R. Roe', 'detail': 'Red Card', 'flags': {'redCard': true}},
                {'type': 'goal', 'team': 'home', 'clock': "77'", 'athlete': 'D. Rossi', 'detail': 'Goal', 'scoreValue': 1},
              ],
            }
          ],
        }
      ],
    });

Future<void> _pump(WidgetTester tester, SportEvent ev,
    {required String sport, required String leagueKey, required String leagueName}) async {
  tester.view.physicalSize = const Size(400, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async => tester.pumpWidget(const SizedBox()));
  SharedPreferences.setMockInitialValues({'baseUrl': ''}); // rich tier dormant
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    child: MaterialApp(
      home: GameDetailPage(event: ev, sport: sport, leagueKey: leagueKey, leagueName: leagueName),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('parsing', () {
    test('SeriesInfo: wins-by-id + clinch number', () {
      final c = _seriesResp().events.first.main!;
      final s = c.meta!.series!;
      expect(s.isPlayoff, isTrue);
      expect(s.total, 7);
      expect(s.gamesToWin, 4); // best-of-7 → first to 4
      expect(s.wins('10'), 3);
      expect(s.wins('20'), 2);
    });

    test('ScoringEvent: timeline + red cards by side', () {
      final c = _soccerResp().events.first.main!;
      expect(c.events, hasLength(4));
      expect(c.events.where((e) => e.isGoal), hasLength(2));
      expect(c.events.firstWhere((e) => e.type == 'red-card').redCard, isTrue);
      expect(c.redCardsBySide['away'], 1);
      expect(c.redCardsBySide['home'], isNull);
    });

    test('Situation matchup lines, Probable record/confirmed, Weather, weekLabel', () {
      final c = Competition.fromJson({
        'id': '1', 'layout': 'headToHead', 'scoreKind': 'numeric', 'competitorKind': 'team',
        'status': {'phase': 'live'}, 'periods': {'unit': 'inning'},
        'situation': {'pitcher': 'T. Kahnle', 'pitcherLine': '0.2 IP, 0 ER', 'batter': 'J. Pederson', 'batterLine': '0-0'},
        'competitors': [
          {'kind': 'team', 'id': '1', 'displayName': 'X', 'probables': [
            {'role': 'Starter', 'athlete': 'C. Early', 'record': '(5-4, 3.30)'},
            {'role': 'Starter', 'athlete': 'C. Hart', 'confirmed': true},
          ]},
        ],
      });
      expect(c.situation!.pitcherLine, '0.2 IP, 0 ER');
      expect(c.situation!.batterLine, '0-0');
      expect(c.competitors.first.probables[0].record, '(5-4, 3.30)');
      expect(c.competitors.first.probables[1].confirmed, isTrue);

      final ev = SportEvent.fromJson({
        'id': '1', 'name': 'n', 'shortName': 's', 'weekLabel': 'Round 15',
        'weather': {'temperature': 77, 'condition': 'Cloudy'},
        'competitions': const [],
      });
      expect(ev.weekLabel, 'Round 15');
      expect(ev.weather!.summary, '77° · Cloudy');
    });
  });

  testWidgets('playoff detail renders the series pips + round/summary context',
      (tester) async {
    final ev = _seriesResp().events.first;
    await _pump(tester, ev, sport: 'basketball', leagueKey: 'basketball/nba', leagueName: 'NBA');
    expect(find.byType(SeriesPips), findsOneWidget);
    // The round headline + series prose now lead the hero (once — not also at the
    // bottom in the meta card).
    expect(find.text('NBA Finals - Game 6'), findsOneWidget);
    expect(find.text('HOM leads series 3-2'), findsOneWidget);
  });

  testWidgets('leaders: one side omitted renders a single roomy column',
      (tester) async {
    final ev = _leadersResp(homeLeaders: false).events.first;
    await _pump(tester, ev, sport: 'hockey', leagueKey: 'hockey/nhl', leagueName: 'NHL');
    expect(find.byType(LeadersStrip), findsOneWidget);
    expect(find.text('ASSISTS'), findsOneWidget); // label gets real width now
    expect(find.text('S. Aho'), findsOneWidget); // away assists leader shows
    expect(find.text('S. Theodore'), findsNothing); // home reported none
  });

  testWidgets('leaders: both sides renders category-aligned rows',
      (tester) async {
    final ev = _leadersResp(homeLeaders: true).events.first;
    await _pump(tester, ev, sport: 'hockey', leagueKey: 'hockey/nhl', leagueName: 'NHL');
    expect(find.byType(LeadersStrip), findsOneWidget);
    expect(find.text('GOALS'), findsOneWidget); // centered category label
    expect(find.text('J. Blake'), findsOneWidget); // away leader
    expect(find.text('S. Theodore'), findsOneWidget); // home leader
  });

  testWidgets('soccer detail renders the cheap goal/card timeline with scorers', (tester) async {
    final ev = _soccerResp().events.first;
    await _pump(tester, ev, sport: 'soccer', leagueKey: 'soccer/usa.1', leagueName: 'MLS');
    expect(find.byType(ScoringTimeline), findsOneWidget);
    // standardized on the shared center-spine visual (same as baseball/etc.)
    expect(find.byType(ScoringFeed), findsOneWidget);
    expect(find.text('Timeline'), findsOneWidget);
    expect(find.text('S. Bangoura'), findsOneWidget);
    expect(find.text('D. Rossi'), findsOneWidget);
  });
}
