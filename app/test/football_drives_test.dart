// §5b / design 9c — the gridiron Drives tab: one tab with a Scoring|All toggle,
// drives grouped into per-quarter cards, score-type chips + running score in the
// Scoring view, and tap-to-expand plays in the All view.
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
      'id': 'F1',
      'layout': 'headToHead',
      'scoreKind': 'numeric',
      'competitorKind': 'team',
      'status': {'phase': 'final', 'live': false, 'ended': true, 'period': 4, 'espnName': 'STATUS_FINAL', 'detail': 'Final'},
      'periods': {'unit': 'quarter', 'regulation': 4, 'played': 4},
      'competitors': [
        {'kind': 'team', 'id': '11', 'displayName': 'Colts', 'abbreviation': 'IND', 'homeAway': 'home', 'color': '002C5F', 'score': {'display': '3', 'value': 3}},
        {'kind': 'team', 'id': '15', 'displayName': 'Dolphins', 'abbreviation': 'MIA', 'homeAway': 'away', 'color': '008E97', 'score': {'display': '7', 'value': 7}},
      ],
    };

Map<String, dynamic> _scores() => {
      'sport': 'football',
      'league': 'nfl',
      'leagueId': '28',
      'leagueName': 'NFL',
      'season': {'year': 2026, 'type': 2},
      'anyLive': false,
      'events': [
        {
          'id': 'F1',
          'name': 'Dolphins vs Colts',
          'shortName': 'MIA v IND',
          'start': '2026-07-05T00:00:00Z',
          'neutralSite': false,
          'broadcasts': <String>[],
          'notes': <String>[],
          'links': <String, dynamic>{},
          'competitions': [_comp()],
        },
      ],
    };

GameSummary _summary() => GameSummary.fromJson({
      'eventId': 'F1',
      'live': false,
      'teamStats': <dynamic>[],
      'boxGroups': <dynamic>[],
      'lineups': <dynamic>[],
      'scoringPlays': <dynamic>[],
      'drives': [
        {'side': 'home', 'teamAbbr': 'IND', 'result': 'Field Goal', 'isScore': true, 'yards': 75, 'playCount': 14, 'period': 1, 'timeElapsed': '6:06', 'awayScore': 0, 'homeScore': 3, 'plays': [{'text': 'FGKICK_GOOD', 'clock': '8:48', 'scoring': true}]},
        {'side': 'away', 'teamAbbr': 'MIA', 'result': 'Punt', 'isScore': false, 'yards': 20, 'playCount': 5, 'period': 1, 'timeElapsed': '2:39', 'plays': [{'text': 'Punt 40 yards', 'clock': '6:12'}]},
        {'side': 'away', 'teamAbbr': 'MIA', 'result': 'Touchdown', 'isScore': true, 'yards': 80, 'playCount': 8, 'period': 2, 'timeElapsed': '3:02', 'awayScore': 7, 'homeScore': 3, 'plays': [{'text': 'TD pass to the corner', 'clock': '11:00', 'scoring': true}]},
      ],
    });

void main() {
  testWidgets('football Drives: Scoring|All toggle, quarter cards, chips, expansion',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
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
        home: GameDetailPage(league: 'football/nfl', initialEvent: scores.events.first),
      ),
    ));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Drives'));
    await tester.pump();

    // Scoring view (default): the toggle, per-quarter cards, chips, running score.
    expect(find.text('Scoring'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('1ST QUARTER'), findsOneWidget);
    expect(find.text('2ND QUARTER'), findsOneWidget);
    expect(find.text('FG'), findsOneWidget);
    expect(find.text('TD'), findsOneWidget);
    expect(find.text('3–0'), findsOneWidget); // FG: home (scoring team) first
    expect(find.text('7–3'), findsOneWidget); // TD: away (scoring team) first
    expect(find.text('FGKICK_GOOD'), findsOneWidget); // the scoring-play title
    // The punt is a non-scoring drive — excluded from the Scoring view.
    expect(find.text('PUNT'), findsNothing);

    // Switch to All: every drive, punt included; the FG's plays are folded.
    await tester.tap(find.text('All'));
    await tester.pump();
    expect(find.text('PUNT'), findsOneWidget);
    expect(find.text('FGKICK_GOOD'), findsNothing); // folded until expanded

    // Tap the FG drive (its IND row) → its plays expand in place.
    await tester.tap(find.text('IND'));
    await tester.pump();
    expect(find.text('FGKICK_GOOD'), findsOneWidget);
  });
}
