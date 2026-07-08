// §5a — the gridiron Now tab must not collapse to two lonely cards when the live
// situation is sparse. Even with only a down&distance headline, the scoring feed
// (data the Drives tab also uses) renders as a supporting SCORING card.
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

// A live gridiron game whose situation is DELIBERATELY thin — only a
// down&distance headline, no possession/spot, no last play. The pre-§5a Now tab
// rendered just this headline plus win prob.
Map<String, dynamic> _comp() => {
      'id': 'F1',
      'layout': 'headToHead',
      'scoreKind': 'numeric',
      'competitorKind': 'team',
      'status': {'phase': 'in', 'live': true, 'ended': false, 'period': 3, 'espnName': 'STATUS_IN_PROGRESS', 'detail': '3rd Quarter'},
      'periods': {'unit': 'quarter', 'regulation': 4, 'played': 3},
      'situation': {'downDistanceText': '1st & 10'},
      'competitors': [
        {'kind': 'team', 'id': '11', 'displayName': 'Hoosiers', 'abbreviation': 'IU', 'homeAway': 'home', 'color': '990000', 'score': {'display': '10', 'value': 10}},
        {'kind': 'team', 'id': '15', 'displayName': 'Hurricanes', 'abbreviation': 'MIA', 'homeAway': 'away', 'color': 'F47321', 'score': {'display': '7', 'value': 7}},
      ],
    };

Map<String, dynamic> _scores() => {
      'sport': 'football',
      'league': 'college-football',
      'leagueId': '23',
      'leagueName': 'NCAAF',
      'season': {'year': 2026, 'type': 2},
      'anyLive': true,
      'events': [
        {
          'id': 'F1',
          'name': 'Miami vs Indiana',
          'shortName': 'MIA v IU',
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
      'live': true,
      'teamStats': <dynamic>[],
      'boxGroups': <dynamic>[],
      'lineups': <dynamic>[],
      'scoringPlays': [
        {'period': 1, 'clock': '2:42', 'side': 'home', 'teamAbbr': 'IU', 'text': 'Radicic 34 Yd Field Goal', 'away': 0, 'home': 3, 'type': 'Field Goal', 'scoring': true},
        {'period': 2, 'clock': '9:10', 'side': 'away', 'teamAbbr': 'MIA', 'text': 'Restrepo 12 Yd pass from Van Dyke', 'away': 7, 'home': 3, 'type': 'Passing Touchdown', 'scoring': true},
      ],
      // Drives are what mark this as a gridiron feed (the §5a gate is data-driven).
      'drives': [
        {'side': 'home', 'teamAbbr': 'IU', 'result': 'Field Goal', 'isScore': true, 'yards': 60, 'playCount': 10, 'period': 1, 'awayScore': 0, 'homeScore': 3},
      ],
    });

void main() {
  testWidgets('gridiron Now surfaces the scoring feed when the situation is sparse',
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
        home: GameDetailPage(league: 'football/college-football', initialEvent: scores.events.first),
      ),
    ));
    await tester.pump(); // resolve summary future
    await tester.pump();

    // The Now tab is the default. The quiet SCORING card renders both scores —
    // the screen is no longer just a down&distance headline + win prob.
    expect(find.text('Radicic 34 Yd Field Goal'), findsOneWidget);
    expect(find.text('Restrepo 12 Yd pass from Van Dyke'), findsOneWidget);
  });
}
