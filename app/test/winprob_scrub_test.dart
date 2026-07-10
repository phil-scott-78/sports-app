// The scrubbable win-probability chart: with a full-game arc (wp.points) the
// detail card draws the curve and lets a hold/drag replay any moment — the
// headline % and a period·clock·score caption track the finger, and releasing
// snaps back to the current/final number. Driven through the real
// GameDetailPage (final NBA game → the generic Recap list).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scores/src/models.dart';
import 'package:scores/src/providers.dart';
import 'package:scores/src/theme.dart';
import 'package:scores/src/ui/game_detail_page.dart';

Future<SharedPreferences> prefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

Map<String, dynamic> _comp() => {
      'id': 'W1',
      'layout': 'headToHead',
      'scoreKind': 'numeric',
      'competitorKind': 'team',
      'status': {'phase': 'final', 'live': false, 'ended': true, 'period': 4, 'espnName': 'STATUS_FINAL', 'detail': 'Final'},
      'periods': {'unit': 'quarter', 'regulation': 4, 'played': 4},
      'competitors': [
        {'kind': 'team', 'id': '13', 'displayName': 'Lakers', 'abbreviation': 'LAL', 'homeAway': 'away', 'color': '552583', 'score': {'display': '110', 'value': 110}},
        {'kind': 'team', 'id': '2', 'displayName': 'Celtics', 'abbreviation': 'BOS', 'homeAway': 'home', 'color': '007A33', 'score': {'display': '104', 'value': 104}},
      ],
    };

Map<String, dynamic> _scores() => {
      'sport': 'basketball',
      'league': 'nba',
      'leagueId': '46',
      'leagueName': 'NBA',
      'season': {'year': 2026, 'type': 2},
      'anyLive': false,
      'events': [
        {
          'id': 'W1',
          'name': 'Lakers vs Celtics',
          'shortName': 'LAL v BOS',
          'start': '2026-07-05T00:00:00Z',
          'neutralSite': false,
          'broadcasts': <String>[],
          'notes': <String>[],
          'links': <String, dynamic>{},
          'competitions': [_comp()],
        },
      ],
    };

// A 5-point arc — index 2 (the chart's midpoint) carries full scrub context.
GameSummary _summary() => GameSummary.fromJson({
      'eventId': 'W1',
      'live': false,
      'teamStats': <dynamic>[],
      'boxGroups': <dynamic>[],
      'lineups': <dynamic>[],
      'scoringPlays': <dynamic>[],
      'winProbability': {
        'home': 0,
        'away': 100,
        'points': [
          {'home': 50, 'period': 1, 'periodLabel': '1st Quarter', 'clock': '12:00', 'awayScore': 0, 'homeScore': 0},
          {'home': 40, 'period': 1, 'periodLabel': '1st Quarter', 'clock': '6:00', 'awayScore': 12, 'homeScore': 8},
          {'home': 55, 'period': 2, 'periodLabel': '2nd Quarter', 'clock': '4:12', 'awayScore': 50, 'homeScore': 48},
          {'home': 30, 'period': 3, 'periodLabel': '3rd Quarter', 'clock': '2:00', 'awayScore': 80, 'homeScore': 74},
          {'home': 0, 'period': 4, 'periodLabel': '4th Quarter', 'clock': '0:00', 'awayScore': 110, 'homeScore': 104},
        ],
      },
    });

void main() {
  testWidgets('win-prob card: arc chart scrubs to any moment, release snaps back',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final p = await prefs();
    final scores = ScoresResponse.fromJson(_scores());
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(p),
        leagueScoresProvider.overrideWith((ref, league) async => scores),
        summaryProvider.overrideWith((ref, key) async => _summary()),
      ],
      child: MaterialApp(
        theme: buildV2Theme(),
        home: GameDetailPage(league: 'basketball/nba', initialEvent: scores.events.first),
      ),
    ));
    await tester.pump();
    await tester.pump();

    // Resting: the final number, no scrub caption.
    expect(find.text('LAL 100%'), findsOneWidget);
    expect(find.textContaining('2ND QUARTER'), findsNothing);

    final chart = find.byWidgetPredicate((w) =>
        w is CustomPaint &&
        w.painter.runtimeType.toString() == '_WinProbChartPainter');
    expect(chart, findsOneWidget);
    final rect = tester.getRect(chart);

    // Hold + drag to the chart's midpoint → arc index 2 of 0..4.
    final g = await tester.startGesture(Offset(rect.left + 2, rect.center.dy));
    await g.moveBy(const Offset(30, 0)); // pass the drag slop
    await g.moveTo(Offset(rect.left + rect.width / 2, rect.center.dy));
    await tester.pump();

    // The headline and split bar replay that moment; the caption names it.
    expect(find.text('BOS 55%'), findsOneWidget);
    expect(find.textContaining('2ND QUARTER 4:12'), findsOneWidget);
    expect(find.textContaining('LAL 50–48 BOS'), findsOneWidget);

    // Release → snap back to now/final.
    await g.up();
    await tester.pump();
    expect(find.text('LAL 100%'), findsOneWidget);
    expect(find.textContaining('2ND QUARTER'), findsNothing);
  });

  testWidgets('win-prob card without an arc stays the passive split bar',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final p = await prefs();
    final scores = ScoresResponse.fromJson(_scores());
    final summary = GameSummary.fromJson({
      'eventId': 'W1',
      'live': false,
      'teamStats': <dynamic>[],
      'boxGroups': <dynamic>[],
      'lineups': <dynamic>[],
      'scoringPlays': <dynamic>[],
      'winProbability': {'home': 35, 'away': 65}, // predictor-fallback shape
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(p),
        leagueScoresProvider.overrideWith((ref, league) async => scores),
        summaryProvider.overrideWith((ref, key) async => summary),
      ],
      child: MaterialApp(
        theme: buildV2Theme(),
        home: GameDetailPage(league: 'basketball/nba', initialEvent: scores.events.first),
      ),
    ));
    await tester.pump();
    await tester.pump();

    // No arc → the Recap list shows no win-prob card at all (a foregone 100%
    // single number says nothing post-game), and no chart exists anywhere.
    expect(
        find.byWidgetPredicate((w) =>
            w is CustomPaint &&
            w.painter.runtimeType.toString() == '_WinProbChartPainter'),
        findsNothing);
  });
}
