// Motorsport session coverage: a racing weekend nests its sessions (practice /
// qualifying / race) as sibling competitions. The detail page must open on the
// race, expose every session via the chip nav, and show each entrant's
// constructor — none of which the single-session collapse did.
import 'dart:async';

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

Map<String, dynamic> _driver(
        String name, int order, String make, String result) =>
    {
      'kind': 'athlete',
      'id': name,
      'displayName': name,
      'shortName': name,
      'abbreviation': name.substring(0, 3).toUpperCase(),
      'order': order,
      'score': {'display': result, 'value': order},
      'vehicle': {'manufacturer': make},
    };

Map<String, dynamic> _session(
        String id, String label, List<Map<String, dynamic>> drivers) =>
    {
      'id': id,
      'label': label,
      'layout': 'field',
      'scoreKind': 'time',
      'competitorKind': 'athlete',
      'status': {
        'phase': 'final',
        'live': false,
        'ended': true,
        'espnName': 'STATUS_FINAL',
        'detail': 'Final',
      },
      'periods': {
        'unit': 'laps',
        'regulation': 1,
        'played': 1,
        'isOvertime': false,
      },
      'decision': null,
      'competitors': drivers,
    };

// A three-session weekend. Bearman (a reserve) runs FP1 only, so his presence
// tells the two sessions apart.
Map<String, dynamic> racingScores() => {
      'sport': 'racing',
      'league': 'f1',
      'leagueId': '2022',
      'leagueName': 'Formula 1',
      'season': {'year': 2026, 'type': 2},
      'anyLive': false,
      'events': [
        {
          'id': 'GP1',
          'name': 'British Grand Prix',
          'shortName': 'GBR',
          'start': '2026-07-05T14:00:00Z',
          'neutralSite': false,
          'broadcasts': <String>[],
          'notes': <String>[],
          'links': <String, dynamic>{},
          'competitions': [
            _session('FP1', 'FP1', [
              _driver('Norris', 1, 'McLaren', '1:28.1'),
              _driver('Verstappen', 2, 'Red Bull', '+0.3'),
              _driver('Bearman', 3, 'Haas', '+0.9'),
            ]),
            _session('QUAL', 'Qualifying', [
              _driver('Leclerc', 1, 'Ferrari', '1:26.0'),
              _driver('Verstappen', 2, 'Red Bull', '+0.1'),
              _driver('Norris', 3, 'McLaren', '+0.2'),
            ]),
            _session('RACE', 'Race', [
              _driver('Verstappen', 1, 'Red Bull', 'Winner'),
              _driver('Norris', 2, 'McLaren', '+5.2s'),
              _driver('Leclerc', 3, 'Ferrari', '+8.1s'),
            ]),
          ],
        },
      ],
    };

void main() {
  testWidgets('racing weekend opens on the race, switches sessions, shows constructor',
      (tester) async {
    final p = await prefs();
    final scores = ScoresResponse.fromJson(racingScores());
    final event = scores.events.first;

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(p),
        leagueScoresProvider.overrideWith((ref, league) async => scores),
        summaryProvider
            .overrideWith((ref, key) => Completer<GameSummary>().future),
      ],
      child: MaterialApp(
        theme: buildV2Theme(),
        home: GameDetailPage(league: 'racing/f1', initialEvent: event),
      ),
    ));
    await tester.pump();

    // Every session is reachable from the chip nav.
    expect(find.text('FP1'), findsOneWidget);
    expect(find.text('Qualifying'), findsOneWidget);
    expect(find.text('Race'), findsOneWidget);

    // Opens on the race (not FP1): the winner + constructor column are shown,
    // and the FP1-only reserve driver is absent.
    expect(find.text('CONSTRUCTOR'), findsOneWidget);
    expect(find.text('Red Bull'), findsOneWidget);
    expect(find.textContaining('Verstappen', findRichText: true), findsWidgets);
    expect(find.textContaining('Bearman', findRichText: true), findsNothing);

    // Switching to FP1 swaps the field — the reserve appears.
    await tester.tap(find.text('FP1'));
    await tester.pump();
    expect(find.textContaining('Bearman', findRichText: true), findsOneWidget);
    expect(find.text('Haas'), findsOneWidget);
  });
}
