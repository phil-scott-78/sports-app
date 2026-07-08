// §3e / design 9e — the baseball Plays tab is a Scoring|All disclosure feed.
// Scoring is the half-inning scoring cards (=3c); All groups EVERY at-bat into the
// same containers as condensed rows that tap-expand to the pitch sequence, with the
// live at-bat pre-expanded. Driven through the real GameDetailPage (Plays tab).
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

Map<String, dynamic> _comp({bool live = false}) => {
      'id': 'B1',
      'layout': 'headToHead',
      'scoreKind': 'numeric',
      'competitorKind': 'team',
      'status': live
          ? {'phase': 'in', 'live': true, 'ended': false, 'period': 3, 'espnName': 'STATUS_IN_PROGRESS', 'detail': 'Top 3rd'}
          : {'phase': 'final', 'live': false, 'ended': true, 'period': 9, 'espnName': 'STATUS_FINAL', 'detail': 'Final'},
      'periods': {'unit': 'inning', 'regulation': 9, 'played': live ? 3 : 9},
      'competitors': [
        {'kind': 'team', 'id': '20', 'displayName': 'Astros', 'abbreviation': 'HOU', 'homeAway': 'away', 'color': '002D62', 'score': {'display': '1', 'value': 1}},
        {'kind': 'team', 'id': '18', 'displayName': 'Cubs', 'abbreviation': 'CHC', 'homeAway': 'home', 'color': '0E3386', 'score': {'display': '0', 'value': 0}},
      ],
    };

Map<String, dynamic> _scores({bool live = false}) => {
      'sport': 'baseball',
      'league': 'mlb',
      'leagueId': '10',
      'leagueName': 'MLB',
      'season': {'year': 2026, 'type': 2},
      'anyLive': live,
      'events': [
        {
          'id': 'B1',
          'name': 'Astros vs Cubs',
          'shortName': 'HOU v CHC',
          'start': '2026-07-05T00:00:00Z',
          'neutralSite': false,
          'broadcasts': <String>[],
          'notes': <String>[],
          'links': <String, dynamic>{},
          'competitions': [_comp(live: live)],
        },
      ],
    };

// A final game: three completed at-bats across two half-innings; one scored.
GameSummary _finalSummary() => GameSummary.fromJson({
      'eventId': 'B1',
      'live': false,
      'teamStats': <dynamic>[],
      'boxGroups': <dynamic>[],
      'lineups': <dynamic>[],
      'scoringPlays': [
        {'period': 1, 'half': 'top', 'side': 'away', 'teamAbbr': 'HOU', 'text': 'Walker doubled, RBI', 'away': 1, 'home': 0, 'type': 'Double', 'scoring': true},
      ],
      'atBats': [
        {
          'period': 1, 'half': 'top', 'side': 'away', 'teamAbbr': 'HOU',
          'text': 'Altuve struck out looking.', 'outs': 1, 'away': 0, 'home': 0,
          'pitches': [
            {'r': 'strike', 'text': 'Strike 1 Swinging', 'velo': 93},
            {'r': 'foul', 'text': 'Strike 2 Foul', 'velo': 93},
            {'r': 'strike', 'text': 'Strike 3 Looking', 'velo': 79},
          ],
        },
        {
          'period': 1, 'half': 'top', 'side': 'away', 'teamAbbr': 'HOU',
          'text': 'Walker doubled to center, Paredes scored.', 'scoring': true, 'outs': 1, 'away': 1, 'home': 0,
          'pitches': [
            {'r': 'ball', 'text': 'Ball 1', 'velo': 86},
            {'r': 'inplay', 'text': 'Ball In Play', 'velo': 92},
          ],
        },
        {
          'period': 1, 'half': 'bottom', 'side': 'home', 'teamAbbr': 'CHC',
          'text': 'Happ flied out to right.', 'outs': 1, 'away': 1, 'home': 0,
          'pitches': [
            {'r': 'strike', 'text': 'Strike 1 Looking', 'velo': 90},
          ],
        },
      ],
    });

// A live game: a completed at-bat then a live (in-progress) at-bat, 2–2 count.
GameSummary _liveSummary() => GameSummary.fromJson({
      'eventId': 'B1',
      'live': true,
      'teamStats': <dynamic>[],
      'boxGroups': <dynamic>[],
      'lineups': <dynamic>[],
      'scoringPlays': <dynamic>[],
      'atBats': [
        {
          'period': 3, 'half': 'top', 'side': 'away', 'teamAbbr': 'HOU',
          'text': 'Peña singled to left.', 'outs': 0, 'away': 0, 'home': 0,
          'pitches': [
            {'r': 'ball', 'text': 'Ball 1', 'velo': 95},
            {'r': 'inplay', 'text': 'Ball In Play', 'velo': 94},
          ],
        },
        {
          'period': 3, 'half': 'top', 'side': 'away', 'teamAbbr': 'HOU',
          'batter': 'J. Altuve', 'text': '', 'live': true, 'outs': 0, 'away': 0, 'home': 0,
          'balls': 2, 'strikes': 2,
          'pitches': [
            {'r': 'strike', 'text': 'Strike 1 Swinging', 'velo': 93},
            {'r': 'ball', 'text': 'Ball 1', 'velo': 88},
            {'r': 'foul', 'text': 'Strike 2 Foul', 'velo': 90},
            {'r': 'ball', 'text': 'Ball 2', 'velo': 87},
          ],
        },
      ],
    });

Future<void> _pump(WidgetTester tester, {required bool live, required GameSummary summary}) async {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final p = await prefs();
  final scores = ScoresResponse.fromJson(_scores(live: live));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(p),
      leagueScoresProvider.overrideWith((ref, league) async => scores),
      summaryProvider.overrideWith((ref, key) async => summary),
    ],
    child: MaterialApp(
      theme: buildV2Theme(),
      home: GameDetailPage(league: 'baseball/mlb', initialEvent: scores.events.first),
    ),
  ));
  await tester.pump(); // resolve summary future
  await tester.pump();
}

void main() {
  testWidgets('Plays tab: Scoring|All toggle; All rows expand to the pitch sequence',
      (tester) async {
    await _pump(tester, live: false, summary: _finalSummary());

    await tester.tap(find.text('Plays'));
    await tester.pumpAndSettle();

    // The Scoring|All toggle exists; Scoring is the default (half-inning cards).
    expect(find.text('Scoring'), findsWidgets);
    expect(find.text('All'), findsOneWidget);
    expect(find.textContaining('TOP 1'), findsOneWidget);
    expect(find.text('Walker doubled, RBI'), findsOneWidget);

    // Switch to All: every at-bat is a condensed row; the pitch sequence is folded
    // (velocities not yet shown), the pitch count rides the right edge.
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Altuve', findRichText: true), findsWidgets);
    expect(find.textContaining('struck out looking', findRichText: true), findsOneWidget);
    expect(find.text('3 P'), findsOneWidget); // 3 pitches, folded
    expect(find.text('79 MPH'), findsNothing);

    // Tap the strikeout at-bat: the pitch sequence discloses in place.
    await tester.tap(find.textContaining('struck out looking', findRichText: true));
    await tester.pumpAndSettle();
    expect(find.text('Strike 3 Looking'), findsOneWidget);
    expect(find.text('79 MPH'), findsOneWidget);
  });

  testWidgets('Plays tab All view: the live at-bat is pre-expanded with its count',
      (tester) async {
    await _pump(tester, live: true, summary: _liveSummary());

    await tester.tap(find.text('Plays'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();

    // The live at-bat shows the batter, the current count where the pitch count
    // would be, and its pitches WITHOUT a tap (pre-expanded).
    expect(find.textContaining('J. Altuve', findRichText: true), findsOneWidget);
    expect(find.text('2–2'), findsOneWidget); // current count, not a pitch count
    expect(find.text('Strike 2 Foul'), findsOneWidget); // a pitch, already visible
    expect(find.text('90 MPH'), findsOneWidget);
    // The live half-inning header carries the out-count, not a running score.
    expect(find.textContaining('0 OUT'), findsOneWidget);
  });
}
