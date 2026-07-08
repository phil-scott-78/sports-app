// §7a — the golf event page: a TODAY column (the current round's to-par), and a
// per-round chip nav (Leaderboard + R1..Rn) that swaps the middle column to each
// round's sub-scores. Driven through the real GameDetailPage (field/golf branch).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scores/src/models.dart';
import 'package:scores/src/providers.dart';
import 'package:scores/src/theme.dart';
import 'package:scores/src/ui/game_detail_page.dart';
import 'package:scores/src/ui/golf_scorecard_page.dart';

Future<SharedPreferences> prefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

Map<String, dynamic> _golfer(String id, String name, int order, String total,
        List<Map<String, dynamic>> rounds) =>
    {
      'kind': 'athlete',
      'id': id,
      'displayName': name,
      'shortName': name,
      'order': order,
      'athletes': [
        {'id': id, 'name': name, 'country': 'USA'}
      ],
      'score': {'display': total, 'toPar': int.parse(total)},
      'periodScores': rounds,
    };

Map<String, dynamic> _scores() => {
      'sport': 'golf',
      'league': 'pga',
      'leagueId': '100',
      'leagueName': 'PGA Tour',
      'season': {'year': 2026, 'type': 2},
      'anyLive': true,
      'events': [
        {
          'id': 'G1',
          'name': 'RBC Canadian Open',
          'shortName': 'RBC',
          'start': '2026-07-05T14:00:00Z',
          'neutralSite': false,
          'broadcasts': <String>[],
          'notes': <String>[],
          'links': <String, dynamic>{},
          'competitions': [
            {
              'id': 'G1',
              'layout': 'field',
              'scoreKind': 'toPar',
              'competitorKind': 'athlete',
              'status': {'phase': 'in', 'live': true, 'ended': false, 'period': 2, 'espnName': 'STATUS_IN_PROGRESS', 'detail': 'Round 2'},
              'periods': {'unit': 'hole_rounds', 'regulation': 4, 'played': 2},
              'competitors': [
                _golfer('p1', 'Cauley', 1, '-12', [
                  {'period': 1, 'value': 69, 'display': '-1', 'holesPlayed': 18},
                  {'period': 2, 'value': 66, 'display': '-4', 'holesPlayed': 11},
                ]),
                _golfer('p2', 'Fitzpatrick', 2, '-9', [
                  {'period': 1, 'value': 68, 'display': '-2', 'holesPlayed': 18},
                  {'period': 2, 'value': 67, 'display': '-3', 'holesPlayed': 14},
                ]),
              ],
            },
          ],
        },
      ],
    };

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final p = await prefs();
  final scores = ScoresResponse.fromJson(_scores());
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(p),
      leagueScoresProvider.overrideWith((ref, league) async => scores),
      summaryProvider.overrideWith((ref, key) => Completer<GameSummary>().future),
      // the leader hole strip is lazy; keep it pending (renders nothing) so this
      // test stays about the leaderboard + chips.
      scorecardProvider.overrideWith((ref, key) => Completer<GolfScorecard>().future),
    ],
    child: MaterialApp(
      theme: buildV2Theme(),
      home: GameDetailPage(league: 'golf/pga', initialEvent: scores.events.first),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('golf leaderboard shows TODAY (current round) + per-round chips',
      (tester) async {
    await _pump(tester);

    // The TODAY column exists; the leader's current round (R2) reads -4.
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('TOTAL'), findsOneWidget);
    expect(find.text('-4'), findsOneWidget); // Cauley today
    expect(find.text('-12'), findsOneWidget); // Cauley total
    expect(find.text('11'), findsOneWidget); // THRU (mid-round, not F)

    // Per-round chips are present.
    expect(find.text('Leaderboard'), findsOneWidget);
    expect(find.text('R1'), findsOneWidget); // chip
    expect(find.text('R2'), findsOneWidget);
  });

  testWidgets('selecting a round chip swaps the column to that round’s sub-scores',
      (tester) async {
    await _pump(tester);

    await tester.tap(find.text('R1'));
    await tester.pumpAndSettle();

    // The middle column now reads R1 and shows each golfer's first-round score;
    // the round-2 numbers (-4 / -3) are gone.
    expect(find.text('TODAY'), findsNothing);
    expect(find.text('-1'), findsOneWidget); // Cauley R1
    expect(find.text('-2'), findsOneWidget); // Fitzpatrick R1
    expect(find.text('-4'), findsNothing); // R2 no longer shown
    // R1 was completed → THRU reads F for both.
    expect(find.text('F'), findsWidgets);
  });

  testWidgets('leader hole strip clamps to the current round (no stale R4)',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // A captured scorecard with all FOUR rounds played (as the mock serves for a
    // finished-tournament fixture), but the tournament is live in round 3.
    List<Map<String, dynamic>> holes() => [
          for (var h = 1; h <= 18; h++)
            {'hole': h, 'par': 4, 'strokes': 4, 'scoreType': 'PAR'}
        ];
    final card = GolfScorecard.fromJson({
      'league': 'golf/pga',
      'eventId': 'G1',
      'player': {'id': 'p1', 'name': 'Cauley'},
      'rounds': [
        for (var r = 1; r <= 4; r++) {'round': r, 'holes': holes()},
      ],
    });
    final leader = Competitor.fromJson({
      'kind': 'athlete',
      'id': 'p1',
      'displayName': 'Cauley',
      'shortName': 'Cauley',
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        scorecardProvider.overrideWith((ref, key) async => card),
      ],
      child: MaterialApp(
        theme: buildV2Theme(),
        home: Scaffold(
          body: GolfLeaderStripCard(
            league: 'golf/pga',
            eventId: 'G1',
            leader: leader,
            currentRound: 3, // live round 3 — must not surface round 4
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('R3'), findsOneWidget);
    expect(find.textContaining('R4'), findsNothing);
  });
}
