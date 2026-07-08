// Tennis coverage: an ESPN tennis "event" is a whole tournament nesting a draw
// of matches (singles + doubles). The Scores list must summarise it as one
// tournament row that drills into the matches — NOT collapse to one match, and
// never misread the draw as an MMA/boxing fight card. Each match opens the
// set-grid detail.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scores/src/models.dart';
import 'package:scores/src/providers.dart';
import 'package:scores/src/theme.dart';
import 'package:scores/src/ui/game_detail_page.dart';
import 'package:scores/src/ui/league_card.dart';
import 'package:scores/src/ui/situations.dart';
import 'package:scores/src/ui/tournament_page.dart';

Future<SharedPreferences> prefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

Map<String, dynamic> _set(int period, String display,
        {bool? setWinner, num? tiebreak}) =>
    {
      'period': period,
      'display': display,
      if (setWinner != null) 'setWinner': setWinner,
      if (tiebreak != null) 'tiebreak': tiebreak,
    };

Map<String, dynamic> _player(String name,
        {String? sets,
        bool? winner,
        bool? serving,
        List<Map<String, dynamic>> setScores = const []}) =>
    {
      'kind': 'athlete',
      'id': name,
      'displayName': name,
      'athletes': [
        {'id': name, 'name': name}
      ],
      if (sets != null) 'score': {'display': sets, 'value': int.parse(sets)},
      if (winner != null) 'winner': winner,
      if (serving != null) 'serving': serving,
      'periodScores': setScores,
    };

Map<String, dynamic> _pair(String id, String a, String b) => {
      'kind': 'pair',
      'id': id,
      'displayName': '${a.split(' ').last} / ${b.split(' ').last}',
      'athletes': [
        {'id': a, 'name': a},
        {'id': b, 'name': b},
      ],
      'periodScores': const <Map<String, dynamic>>[],
    };

Map<String, dynamic> _match(
        String id, String round, String phase, List<Map<String, dynamic>> players) =>
    {
      'id': id,
      'layout': 'headToHead',
      'scoreKind': 'numeric',
      'competitorKind': 'athlete',
      'status': {
        'phase': phase,
        'live': phase == 'live',
        'ended': phase == 'final',
        'espnName': phase == 'final'
            ? 'STATUS_FINAL'
            : (phase == 'live' ? 'STATUS_IN_PROGRESS' : 'STATUS_SCHEDULED'),
        'detail': phase == 'final' ? 'Final' : (phase == 'live' ? 'Set 2' : '9:00 AM'),
        'period': phase == 'scheduled' ? 0 : 2,
      },
      'periods': {
        'unit': 'set',
        'regulation': 3,
        'played': phase == 'scheduled' ? 0 : 2,
        'isOvertime': false,
      },
      'decision': null,
      'meta': {'round': round},
      'competitors': players,
    };

/// A tennis tournament with a small cross-round draw: a live singles Final, two
/// completed Semifinals, a completed Quarterfinal, and a scheduled Doubles
/// Final.
Map<String, dynamic> tennisScores() => {
      'sport': 'tennis',
      'league': 'atp',
      'leagueId': '851',
      'leagueName': 'ATP Tour',
      'season': {'year': 2026, 'type': 2},
      'anyLive': true,
      'events': [
        {
          'id': 'T1',
          'name': 'Terra Wortmann Open',
          'shortName': 'Terra Wortmann Open',
          'start': '2026-07-05T09:00:00Z',
          'neutralSite': false,
          'broadcasts': <String>[],
          'notes': <String>[],
          'links': <String, dynamic>{},
          'venue': {'name': 'Halle'},
          'competitions': [
            _match('m-final', 'Final', 'live', [
              _player('Carlos Alcaraz',
                  sets: '1',
                  serving: true,
                  setScores: [_set(1, '6', setWinner: true), _set(2, '4')]),
              _player('Jannik Sinner',
                  sets: '1',
                  setScores: [_set(1, '4'), _set(2, '6', setWinner: true)]),
            ]),
            _match('m-sf1', 'Semifinals', 'final', [
              _player('Carlos Alcaraz', sets: '2', winner: true),
              _player('Alexander Zverev', sets: '0'),
            ]),
            _match('m-sf2', 'Semifinals', 'final', [
              _player('Jannik Sinner', sets: '2', winner: true),
              _player('Holger Rune', sets: '1'),
            ]),
            _match('m-qf1', 'Quarterfinals', 'final', [
              _player('Daniil Medvedev', sets: '2', winner: true),
              _player('Tommy Paul', sets: '0'),
            ]),
            _match('m-dfinal', 'Final', 'scheduled', [
              _pair('p1', 'Rohan Bopanna', 'Matthew Ebden'),
              _pair('p2', 'Kevin Krawietz', 'Tim Puetz'),
            ]),
          ],
        },
      ],
    };

Widget _app(SharedPreferences p, ScoresResponse scores, Widget home) =>
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(p),
        leagueScoresProvider.overrideWith((ref, key) async => scores),
        summaryProvider
            .overrideWith((ref, key) => Completer<GameSummary>().future),
        // The rich core-competition enrichment is best-effort and lazy; stub it
        // to null so widget tests never reach the network.
        tennisMatchProvider.overrideWith((ref, key) async => null),
      ],
      child: MaterialApp(theme: buildV2Theme(), home: home),
    );

void main() {
  test('isTournamentOfMatches: tennis tournament yes; MMA card + single match no',
      () {
    final scores = ScoresResponse.fromJson(tennisScores());
    final tourney = scores.events.first;
    expect(tourney.isTournamentOfMatches, isTrue);

    // A single-match event (one competition) is NOT a tournament row.
    final single = tourney.matches.first;
    expect(single.competitions.length, 1);
    expect(single.isTournamentOfMatches, isFalse);

    // MMA is round-based head-to-head athletes — must not be mistaken for a
    // tennis tournament.
    final mma = SportEvent.fromJson(_mmaEventJson());
    expect(mma.competitions.length, greaterThan(1));
    expect(mma.isTournamentOfMatches, isFalse);
  });

  test('matches explosion: unique match ids, retained tournament id', () {
    final tourney = ScoresResponse.fromJson(tennisScores()).events.first;
    final matches = tourney.matches;
    expect(matches.length, tourney.competitions.length);
    // Each match is one competition, re-ided to the match, carrying the parent.
    for (final m in matches) {
      expect(m.competitions.length, 1);
      expect(m.id, m.competitions.first.id);
      expect(m.tournamentId, 'T1');
    }
    expect(matches.map((m) => m.id).toSet().length, matches.length);
  });

  testWidgets('Scores list shows a tournament summary row that drills in',
      (tester) async {
    final p = await prefs();
    final scores = ScoresResponse.fromJson(tennisScores());

    await tester.pumpWidget(_app(
      p,
      scores,
      Scaffold(
        body: SingleChildScrollView(
          child: LeagueEventsCard(league: 'tennis/atp', scores: scores),
        ),
      ),
    ));
    await tester.pump();

    // One calm tournament row, not five collapsed matches, not a fight card.
    expect(find.text('Terra Wortmann Open'), findsOneWidget);
    expect(find.text('1 live'), findsOneWidget);
    expect(find.text('Fight card'), findsNothing);

    // Tapping the row opens the tournament page (round sections appear).
    await tester.tap(find.text('Terra Wortmann Open'));
    await tester.pumpAndSettle();
    expect(find.text('SEMIFINALS'), findsOneWidget);
    expect(find.text('QUARTERFINALS'), findsOneWidget);
    // Singles + doubles finals are separated even though both are "Final".
    expect(find.text('FINAL'), findsOneWidget);
    expect(find.text('FINAL · DOUBLES'), findsOneWidget);
  });

  testWidgets('Tournament page opens a match into the set-grid detail (no fight card)',
      (tester) async {
    final p = await prefs();
    final scores = ScoresResponse.fromJson(tennisScores());
    final tourney = scores.events.first;

    await tester.pumpWidget(_app(
      p,
      scores,
      TournamentPage(league: 'tennis/atp', initialEvent: tourney),
    ));
    await tester.pump();

    // Matches are listed by their players.
    expect(find.text('Daniil Medvedev'), findsOneWidget);
    expect(find.text('Holger Rune'), findsOneWidget);

    // Open the live Final (the first "Carlos Alcaraz" row sits in the Final).
    await tester.tap(find.text('Carlos Alcaraz').first);
    await tester.pumpAndSettle();

    // The set grid — uppercased block names — renders; no MMA fight card.
    expect(find.text('CARLOS ALCARAZ'), findsOneWidget);
    expect(find.text('JANNIK SINNER'), findsOneWidget);
    expect(find.text('Fight card'), findsNothing);
  });

  testWidgets('regression: the whole tournament event never renders a fight card',
      (tester) async {
    final p = await prefs();
    final scores = ScoresResponse.fromJson(tennisScores());
    final tourney = scores.events.first;

    await tester.pumpWidget(_app(
      p,
      scores,
      GameDetailPage(league: 'tennis/atp', initialEvent: tourney),
    ));
    await tester.pump();

    expect(find.text('Fight card'), findsNothing);
  });

  testWidgets('set grid shows the loser\'s tiebreak points as a superscript',
      (tester) async {
    final comp = Competition.fromJson(_match('m', 'Final', 'final', [
      _player('Iga Swiatek', sets: '2', winner: true, setScores: [
        _set(1, '6', setWinner: true),
        _set(2, '7', setWinner: true, tiebreak: 7),
      ]),
      _player('Coco Gauff', sets: '0', setScores: [
        _set(1, '3', setWinner: false),
        // lost the breaker 7–5 → the cell reads 6⁵ (setWinner:false as ESPN sends)
        _set(2, '6', setWinner: false, tiebreak: 5),
      ]),
    ]));

    await tester.pumpWidget(MaterialApp(
      theme: buildV2Theme(),
      home: Scaffold(body: SetGridBlock(comp)),
    ));
    await tester.pump();

    // Only the set LOSER's tiebreak (5) is shown, as its own (superscript) cell.
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('rich tennis detail: draw type, court, and the result note render',
      (tester) async {
    final p = await prefs();
    final scores = ScoresResponse.fromJson({
      'sport': 'tennis',
      'league': 'wta',
      'leagueId': '900',
      'leagueName': 'WTA Tour',
      'season': {'year': 2026, 'type': 2},
      'anyLive': false,
      'events': [
        {
          'id': '188-2026',
          'name': 'Wimbledon',
          'shortName': 'Wimbledon',
          'start': '2026-07-11T15:00:00Z',
          'neutralSite': false,
          'broadcasts': <String>[],
          'notes': <String>[],
          'links': <String, dynamic>{},
          'competitions': [
            _match('180004', 'Quarterfinal', 'final', [
              _player('Iga Swiatek', sets: '2', winner: true, setScores: [
                _set(1, '6', setWinner: true),
                _set(2, '6', setWinner: true),
              ]),
              _player('Coco Gauff', sets: '0', setScores: [
                _set(1, '3'),
                _set(2, '4'),
              ]),
            ]),
          ],
        },
      ],
    });
    final event = scores.events.first; // a single, addressable tennis match
    final info = TennisMatchInfo(
      drawType: "Women's Singles",
      round: 'Quarterfinal',
      court: 'Court 2 Roehampton',
      resultLine: 'Swiatek bt Gauff 6-3 6-4',
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(p),
        leagueScoresProvider.overrideWith((ref, key) async => scores),
        summaryProvider
            .overrideWith((ref, key) => Completer<GameSummary>().future),
        tennisMatchProvider.overrideWith((ref, key) async => info),
      ],
      child: MaterialApp(
        theme: buildV2Theme(),
        home: GameDetailPage(league: 'tennis/wta', initialEvent: event),
      ),
    ));
    await tester.pump(); // build
    await tester.pump(); // resolve tennisMatchProvider

    expect(find.text("WOMEN'S SINGLES"), findsOneWidget);
    expect(find.text('Quarterfinal · Court 2 Roehampton'), findsOneWidget);
    expect(find.text('Swiatek bt Gauff 6-3 6-4'), findsOneWidget);
  });
}

Map<String, dynamic> _mmaEventJson() => {
      'id': 'UFC1',
      'name': 'UFC 300',
      'shortName': 'UFC 300',
      'start': '2026-07-05T22:00:00Z',
      'neutralSite': false,
      'broadcasts': <String>[],
      'notes': <String>[],
      'links': <String, dynamic>{},
      'competitions': [
        for (var i = 0; i < 3; i++)
          {
            'id': 'bout$i',
            'layout': 'headToHead',
            'scoreKind': 'numeric',
            'competitorKind': 'athlete',
            'status': {'phase': 'final', 'live': false, 'ended': true},
            'periods': {
              'unit': 'round',
              'regulation': 3,
              'played': 3,
              'isOvertime': false
            },
            'decision': null,
            'competitors': [
              _player('Fighter ${i}A', sets: '1'),
              _player('Fighter ${i}B', sets: '0'),
            ],
          },
      ],
    };
