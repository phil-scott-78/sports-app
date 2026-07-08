// Hockey game-detail Now tab (§6 / design 6c), driven through the real
// GameDetailPage: the rich shots-on-goal total drives a SHOTS ON GOAL pressure
// card (with the goalie save % as a footer) that supersedes the thin cheap
// GOALTENDING panel, and a quiet SCORING summary fills what was a barren Now.
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

const _liveStatus = {
  'phase': 'live', 'live': true, 'ended': false, 'period': 3,
  'periodLabel': '3rd', 'espnName': 'STATUS_IN_PROGRESS', 'detail': '3rd Period',
};

Map<String, dynamic> _comp() => {
      'id': 'H1',
      'layout': 'headToHead',
      'scoreKind': 'numeric',
      'competitorKind': 'team',
      'status': _liveStatus,
      'periods': {'unit': 'period', 'regulation': 3, 'played': 3, 'lengthMin': 20},
      'competitors': [
        {'kind': 'team', 'id': 'VGK', 'displayName': 'Golden Knights', 'abbreviation': 'VGK', 'homeAway': 'away', 'color': 'B4975A', 'score': {'display': '2', 'value': 2}, 'stats': {'SV%': '.905', 'SV': '34'}},
        {'kind': 'team', 'id': 'DAL', 'displayName': 'Stars', 'abbreviation': 'DAL', 'homeAway': 'home', 'color': '006847', 'score': {'display': '4', 'value': 4}, 'stats': {'SV%': '.938', 'SV': '23'}},
      ],
    };

Map<String, dynamic> _scores() => {
      'sport': 'hockey',
      'league': 'nhl',
      'leagueId': '90',
      'leagueName': 'NHL',
      'season': {'year': 2026, 'type': 2},
      'anyLive': true,
      'events': [
        {
          'id': 'H1',
          'name': 'Golden Knights vs Stars',
          'shortName': 'VGK v DAL',
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
      'eventId': 'H1',
      'live': true,
      'teamStats': [
        {'label': 'Shots', 'away': '25', 'home': '24'},
        {'label': 'Blocked Shots', 'away': '18', 'home': '12'},
        {'label': 'Faceoff Win Percent', 'away': '41.5', 'home': '58.5'},
      ],
      'scoringPlays': [
        {'period': 1, 'periodLabel': '1st', 'clock': '6:52', 'side': 'away', 'teamAbbr': 'VGK', 'text': 'Pavel Dorofeyev Goal (11) Snap Shot, assists: Jack Eichel (19)', 'away': 1, 'home': 0, 'type': 'Goal', 'scoring': true},
        {'period': 3, 'periodLabel': '3rd', 'clock': '13:49', 'side': 'home', 'teamAbbr': 'DAL', 'text': 'Wyatt Johnston Goal (5) Wrist Shot', 'away': 2, 'home': 4, 'type': 'Goal', 'scoring': true},
      ],
      'boxGroups': <dynamic>[],
      'lineups': <dynamic>[],
    });

void main() {
  testWidgets('hockey Now: shots-pressure card + scoring summary replace the goaltending gauge',
      (tester) async {
    // Now stacks several cards — a tall viewport so they all build (SliverList).
    tester.view.physicalSize = const Size(1200, 2400);
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
        home: GameDetailPage(league: 'hockey/nhl', initialEvent: scores.events.first),
      ),
    ));
    await tester.pump(); // resolve summary future
    await tester.pump();

    // The shots-pressure card, off the rich summary's Shots total…
    expect(find.text('SHOTS ON GOAL'), findsOneWidget);
    expect(find.text('25'), findsWidgets); // away shots
    expect(find.text('24'), findsWidgets); // home shots
    // …with the goalie save % as a footer (from the cheap scoreboard).
    expect(find.textContaining('.938 SV%'), findsOneWidget);

    // The cheap GOALTENDING panel is superseded, not shown alongside.
    expect(find.text('GOALTENDING'), findsNothing);

    // The quiet scoring summary fills the once-barren Now.
    expect(find.text('SCORING'), findsOneWidget);
    expect(find.textContaining('Dorofeyev'), findsOneWidget);
    expect(find.textContaining('Wyatt Johnston'), findsOneWidget);
  });
}
