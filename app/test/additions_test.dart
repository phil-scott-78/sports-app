// Tests for the 2026-07 data additions: golf meta + scorecards, cricket innings,
// MMA structured results, gridiron drives, gameInfo, and the rankings feeds.
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
import 'package:scores/src/ui/league_page.dart';

Future<SharedPreferences> prefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

// ---- inline canonical payloads ------------------------------------------------

Map<String, dynamic> golfScores({bool live = true}) => {
      'sport': 'golf',
      'league': 'pga',
      'leagueId': '1106',
      'leagueName': 'PGA Tour',
      'season': {'year': 2026, 'type': 2},
      'anyLive': live,
      'events': [
        {
          'id': 'G1',
          'name': 'John Deere Classic',
          'shortName': 'JDC',
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
              'status': {
                'phase': live ? 'live' : 'final',
                'live': live,
                'ended': !live,
                'period': 3,
                'periodLabel': 'Round 3',
                'espnName': live ? 'STATUS_IN_PROGRESS' : 'STATUS_FINAL',
                'detail': live ? 'Round 3' : 'Final',
              },
              'periods': {
                'unit': 'hole_rounds',
                'regulation': 4,
                'played': 3,
                'isOvertime': false,
              },
              'decision': null,
              'meta': {
                'golf': {
                  'numberOfRounds': 4,
                  'currentRound': 3,
                  'cutRound': 2,
                  'cutScore': -3,
                  'cutCount': 79,
                  'major': true,
                  'scoringSystem': 'Medal',
                },
              },
              'competitors': [
                {
                  'kind': 'athlete',
                  'id': '4690755',
                  'displayName': 'Chris Gotterup',
                  'athletes': [
                    {'id': '4690755', 'name': 'Chris Gotterup', 'country': 'USA'},
                  ],
                  'order': 1,
                  'score': {'display': '-20', 'toPar': -20},
                  'periodScores': [
                    {'period': 1, 'value': 66, 'display': '-5', 'holesPlayed': 18},
                    {'period': 2, 'value': 68, 'display': '-3', 'holesPlayed': 18},
                    {'period': 3, 'value': 64, 'display': '-7', 'holesPlayed': 12},
                  ],
                },
                {
                  'kind': 'athlete',
                  'id': '9037',
                  'displayName': 'Davis Thompson',
                  'athletes': [
                    {'id': '9037', 'name': 'Davis Thompson', 'country': 'USA'},
                  ],
                  'order': 2,
                  'score': {'display': '-17', 'toPar': -17},
                },
              ],
            },
          ],
        },
      ],
    };

Map<String, dynamic> scorecardJson() => {
      'league': 'golf/pga',
      'eventId': 'G1',
      'player': {'id': '4690755', 'name': 'Chris Gotterup'},
      'rounds': [
        {
          'round': 1,
          'strokes': 66,
          'toPar': '-5',
          'outScore': 32,
          'inScore': 34,
          'teeTime': '2026-07-02T17:45Z',
          'startTee': 1,
          'groupNumber': 30,
          'holes': [
            for (var h = 1; h <= 18; h++)
              {
                'hole': h,
                'par': 4,
                'strokes': h == 1 ? 3 : 4,
                'scoreType': h == 1 ? 'BIRDIE' : 'PAR',
              },
          ],
        },
        {
          'round': 4,
          'teeTime': '2026-07-05T18:10Z',
          'startTee': 10,
          'groupNumber': 5,
          'holes': <dynamic>[],
        },
      ],
      'stats': [
        {'name': 'scoreToPar', 'label': 'Score To Par', 'value': '-20'},
      ],
    };

void main() {
  group('models', () {
    test('GolfMeta parses and formats the cut line', () {
      final scores = ScoresResponse.fromJson(golfScores());
      final golf = scores.events.first.competitions.first.meta!.golf!;
      expect(golf.numberOfRounds, 4);
      expect(golf.currentRound, 3);
      expect(golf.major, isTrue);
      expect(golf.hasCut, isTrue);
      expect(golf.cutLine, 'Cut −3 · 79 made');
    });

    test('cheap passthroughs parse (attendance/headline/conference/suspended)',
        () {
      final comp = Competition.fromJson({
        'id': '1',
        'layout': 'headToHead',
        'scoreKind': 'numeric',
        'competitorKind': 'team',
        'status': {'phase': 'final', 'live': false, 'ended': true},
        'periods': {'unit': 'inning', 'regulation': 9, 'played': 9},
        'competitors': <dynamic>[],
        'attendance': 41234,
        'headline': "Judge's 3 HR carry Yankees",
        'conferenceGame': true,
        'wasSuspended': true,
      });
      expect(comp.attendance, 41234);
      expect(comp.headline, contains('Judge'));
      expect(comp.conferenceGame, isTrue);
      expect(comp.wasSuspended, isTrue);
    });

    test('GameSummary parses drives, cricket innings, bouts, gameInfo', () {
      final s = GameSummary.fromJson({
        'eventId': 'E',
        'live': false,
        'teamStats': <dynamic>[],
        'boxGroups': <dynamic>[],
        'scoringPlays': <dynamic>[],
        'lineups': <dynamic>[],
        'attendance': 70823,
        'officials': [
          {'name': 'Shawn Smith', 'role': 'Referee'},
        ],
        'drives': [
          {
            'side': 'away',
            'teamAbbr': 'SEA',
            'description': '8 plays, 51 yards, 3:02',
            'result': 'Field Goal',
            'isScore': true,
            'yards': 51,
            'playCount': 8,
          },
        ],
        'cricketInnings': [
          {
            'innings': 1,
            'battingTeam': 'Australia',
            'total': '241 (4 wkts; 43 ovs)',
            'extras': '(b 5, lb 2, w 11)',
            'batting': [
              {
                'name': 'DA Warner',
                'dismissal': 'caught',
                'runs': '7',
                'balls': '3',
                'fours': '1',
                'sixes': '0',
              },
            ],
            'bowlingTeam': 'India',
            'bowling': [
              {
                'name': 'JJ Bumrah',
                'overs': '9.0',
                'maidens': '2',
                'runs': '43',
                'wickets': '2',
                'economy': '4.77',
              },
            ],
          },
        ],
        'bouts': [
          {
            'id': 'b1',
            'result': 'Decision - Split',
            'shortResult': 'S Dec',
            'round': 3,
            'clock': '5:00',
            'judges': [
              {
                'competitorId': 'f1',
                'total': 85,
                'totals': [28, 28, 29],
              },
              {
                'competitorId': 'f2',
                'total': 86,
                'totals': [29, 29, 28],
              },
            ],
          },
        ],
      });
      expect(s.attendance, 70823);
      expect(s.officials.single.role, 'Referee');
      expect(s.drives.single.isScore, isTrue);
      expect(s.cricketInnings.single.batting.single.name, 'DA Warner');
      expect(s.cricketInnings.single.bowling.single.economy, '4.77');
      expect(s.boutFor('b1')!.judges.first.totals, [28, 28, 29]);
      expect(s.boutFor('nope'), isNull);
      expect(s.isEmpty, isFalse); // the new blocks count as content
    });

    test('GolfScorecard parses rounds/holes and pre-round tee time', () {
      final sc = GolfScorecard.fromJson(scorecardJson());
      expect(sc.player.name, 'Chris Gotterup');
      expect(sc.rounds.first.played, isTrue);
      expect(sc.rounds.first.holes.first.scoreType, 'BIRDIE');
      expect(sc.rounds.first.holes.first.delta, -1);
      expect(sc.rounds.last.played, isFalse);
      expect(sc.rounds.last.teeTimeLocal, isNotNull);
    });

    test('RankEntry carries athlete OR team, points/record/champion', () {
      final r = RankingsResponse.fromJson({
        'league': 'tennis/atp',
        'polls': [
          {
            'name': 'ATP',
            'shortName': 'ATP',
            'ranks': [
              {
                'current': 1,
                'points': 13450,
                'trend': '-',
                'athlete': {'id': '3623', 'name': 'Jannik Sinner'},
              },
              {
                'current': 1,
                'record': '21-4-0',
                'champion': true,
                'athlete': {'id': '3088812', 'name': 'Kamaru Usman'},
              },
            ],
          },
        ],
      });
      final ranks = r.polls.single.ranks;
      expect(ranks.first.athlete!.name, 'Jannik Sinner');
      expect(ranks.first.points, 13450);
      expect(ranks.first.team, isNull);
      expect(ranks.last.champion, isTrue);
      expect(ranks.last.name, 'Kamaru Usman');
    });
  });

  group('widgets', () {
    testWidgets('golf detail shows the meta strip and opens a scorecard on tap',
        (tester) async {
      final p = await prefs();
      final scores = ScoresResponse.fromJson(golfScores());
      final event = scores.events.first;
      final scorecard = GolfScorecard.fromJson(scorecardJson());
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(p),
          leagueScoresProvider.overrideWith((ref, league) async => scores),
          summaryProvider.overrideWith(
              (ref, key) => Completer<GameSummary>().future),
          scorecardProvider.overrideWith((ref, key) async => scorecard),
        ],
        child: MaterialApp(
          theme: buildV2Theme(),
          home: GameDetailPage(league: 'golf/pga', initialEvent: event),
        ),
      ));
      await tester.pump();
      // meta strip: round progress + cut line + major badge
      expect(find.textContaining('Round 3 of 4'), findsOneWidget);
      expect(find.textContaining('Cut −3'), findsOneWidget);
      expect(find.text('MAJOR'), findsOneWidget);
      // tap the leader row → scorecard page (leaderboard names are Text.rich)
      await tester.tap(
          find.textContaining('Chris Gotterup', findRichText: true).first);
      await tester.pumpAndSettle();
      expect(find.byType(GolfScorecardPage), findsOneWidget);
      expect(find.text('R1'), findsOneWidget);
      expect(find.text('OUT'), findsOneWidget);
      expect(find.text('IN'), findsOneWidget);
      // pre-start round chip exists too
      expect(find.text('R4'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('cricket detail gets a Scorecard chip with batting + bowling',
        (tester) async {
      final p = await prefs();
      final scores = ScoresResponse.fromJson({
        'sport': 'cricket',
        'league': '8048',
        'leagueId': '8048',
        'leagueName': 'IPL',
        'season': {'year': 2026, 'type': 2},
        'anyLive': false,
        'events': [
          {
            'id': 'C1',
            'name': 'IND v AUS',
            'shortName': 'IND v AUS',
            'start': '2026-07-04T09:00:00Z',
            'neutralSite': false,
            'broadcasts': <String>[],
            'notes': <String>[],
            'links': <String, dynamic>{},
            'competitions': [
              {
                'id': 'C1',
                'layout': 'headToHead',
                'scoreKind': 'cricket',
                'competitorKind': 'team',
                'status': {
                  'phase': 'final',
                  'live': false,
                  'ended': true,
                  'period': 2,
                  'periodLabel': 'RESULT',
                  'espnName': 'STATUS_FINAL',
                  'detail': 'RESULT',
                },
                'periods': {
                  'unit': 'over_innings',
                  'regulation': 2,
                  'played': 2,
                  'isOvertime': false,
                },
                'decision': null,
                'competitors': [
                  {
                    'kind': 'team',
                    'id': '6',
                    'displayName': 'India',
                    'homeAway': 'home',
                    'score': {'display': '240'},
                  },
                  {
                    'kind': 'team',
                    'id': '2',
                    'displayName': 'Australia',
                    'homeAway': 'away',
                    'winner': true,
                    'score': {'display': '241/4 (43 ov)'},
                  },
                ],
              },
            ],
          },
        ],
      });
      final summary = GameSummary.fromJson({
        'eventId': 'C1',
        'live': false,
        'teamStats': <dynamic>[],
        'boxGroups': <dynamic>[],
        'scoringPlays': <dynamic>[],
        'lineups': <dynamic>[],
        'cricketInnings': [
          {
            'innings': 1,
            'battingTeam': 'Australia',
            'total': '241 (4 wkts; 43 ovs)',
            'batting': [
              {'name': 'TM Head', 'dismissal': 'caught', 'runs': '137'},
            ],
            'bowlingTeam': 'India',
            'bowling': [
              {'name': 'JJ Bumrah', 'overs': '9.0', 'wickets': '2'},
            ],
          },
        ],
      });
      final event = scores.events.first;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(p),
          leagueScoresProvider.overrideWith((ref, league) async => scores),
          summaryProvider.overrideWith((ref, key) async => summary),
        ],
        child: MaterialApp(
          theme: buildV2Theme(),
          home: GameDetailPage(league: 'cricket/8048', initialEvent: event),
        ),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.text('Scorecard'), findsOneWidget);
      await tester.tap(find.text('Scorecard'));
      await tester.pump();
      expect(find.text('TM Head'), findsOneWidget);
      expect(find.text('JJ Bumrah'), findsOneWidget);
      expect(find.textContaining('AUSTRALIA — 1ST INNINGS'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('MMA final bout renders the method card with judge scores',
        (tester) async {
      final p = await prefs();
      final scores = ScoresResponse.fromJson({
        'sport': 'mma',
        'league': 'ufc',
        'leagueId': '3321',
        'leagueName': 'UFC',
        'season': {'year': 2026, 'type': 2},
        'anyLive': false,
        'events': [
          {
            'id': 'M1',
            'name': 'UFC Fight Night',
            'shortName': 'UFC',
            'start': '2026-06-28T22:00:00Z',
            'neutralSite': false,
            'broadcasts': <String>[],
            'notes': <String>[],
            'links': <String, dynamic>{},
            'competitions': [
              {
                'id': 'b1',
                'layout': 'headToHead',
                'scoreKind': 'none',
                'competitorKind': 'athlete',
                'label': 'Welterweight',
                'status': {
                  'phase': 'final',
                  'live': false,
                  'ended': true,
                  'period': 3,
                  'periodLabel': 'Final',
                  'espnName': 'STATUS_FINAL',
                  'detail': 'Final',
                },
                'periods': {
                  'unit': 'round',
                  'regulation': 3,
                  'played': 3,
                  'isOvertime': false,
                },
                'decision': 'method',
                'method': {'kind': 'Decision'},
                'competitors': [
                  {
                    'kind': 'athlete',
                    'id': 'f1',
                    'displayName': 'Fighter One',
                    'winner': false,
                    'athletes': [
                      {'id': 'f1', 'name': 'Fighter One'},
                    ],
                  },
                  {
                    'kind': 'athlete',
                    'id': 'f2',
                    'displayName': 'Fighter Two',
                    'winner': true,
                    'athletes': [
                      {'id': 'f2', 'name': 'Fighter Two'},
                    ],
                  },
                ],
              },
            ],
          },
        ],
      });
      final summary = GameSummary.fromJson({
        'eventId': 'M1',
        'live': false,
        'teamStats': <dynamic>[],
        'boxGroups': <dynamic>[],
        'scoringPlays': <dynamic>[],
        'lineups': <dynamic>[],
        'bouts': [
          {
            'id': 'b1',
            'result': 'Decision - Split',
            'shortResult': 'S Dec',
            'round': 3,
            'clock': '5:00',
            'judges': [
              {
                'competitorId': 'f1',
                'total': 85,
                'totals': [28, 28, 29],
              },
              {
                'competitorId': 'f2',
                'total': 86,
                'totals': [29, 29, 28],
              },
            ],
          },
        ],
      });
      final event = scores.events.first;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(p),
          leagueScoresProvider.overrideWith((ref, league) async => scores),
          summaryProvider.overrideWith((ref, key) async => summary),
        ],
        child: MaterialApp(
          theme: buildV2Theme(),
          home: GameDetailPage(league: 'mma/ufc', initialEvent: event),
        ),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.text('METHOD'), findsOneWidget);
      expect(find.text('Decision - Split'), findsOneWidget);
      expect(find.text('28 · 28 · 29'), findsOneWidget);
      expect(find.text('86'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('league page shows the rankings panel for a tour league',
        (tester) async {
      final p = await prefs();
      final rankings = RankingsResponse.fromJson({
        'league': 'tennis/atp',
        'polls': [
          {
            'name': 'ATP',
            'shortName': 'ATP',
            'ranks': [
              {
                'current': 1,
                'points': 13450,
                'trend': '-',
                'athlete': {'id': '3623', 'name': 'Jannik Sinner'},
              },
              {
                'current': 2,
                'points': 9460,
                'trend': '+1',
                'athlete': {'id': '3782', 'name': 'Carlos Alcaraz'},
              },
            ],
          },
        ],
      });
      final scores = ScoresResponse.fromJson({
        'sport': 'tennis',
        'league': 'atp',
        'leagueId': '851',
        'leagueName': 'ATP Tour',
        'season': {'year': 2026, 'type': 2},
        'anyLive': false,
        'events': <dynamic>[],
      });
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(p),
          leagueScoresProvider.overrideWith((ref, league) async => scores),
          rankingsProvider.overrideWith((ref, league) async => rankings),
          catalogProvider.overrideWith((ref) async => [
                CatalogSport(sport: 'tennis', leagues: [
                  CatalogLeague(
                    key: 'tennis/atp',
                    league: 'atp',
                    name: 'ATP Tour',
                    hasTeams: false,
                    rankings: 'tour',
                  ),
                ]),
              ]),
        ],
        child: MaterialApp(
          theme: buildV2Theme(),
          home: const LeaguePage(league: 'tennis/atp'),
        ),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.text('RANKINGS'), findsOneWidget);
      expect(find.textContaining('Jannik Sinner', findRichText: true),
          findsOneWidget);
      expect(find.text('13,450'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
