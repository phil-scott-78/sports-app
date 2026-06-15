import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scores/src/models.dart';
import 'package:scores/src/providers.dart';
import 'package:scores/src/theme.dart';
import 'package:scores/src/ui/game_detail_page.dart';
import 'package:scores/src/ui/scores_page.dart';
import 'package:scores/src/ui/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A cricket competitor as the worker emits it: just the composite `score.display`
/// (the overs tag is derived from the string, so no separate field is needed).
Competitor _cric(String display) => Competitor.fromJson({
      'kind': 'team',
      'id': '1',
      'displayName': 'Team',
      'abbreviation': 'TEAM',
      'homeAway': 'home',
      'score': {'display': display},
    });

void main() {
  group('cricketScoreParts peels ESPN composites', () {
    test('limited-overs chase: runs line drops overs + target', () {
      final p = cricketScoreParts(_cric('161/5 (18/20 ov, target 156)'));
      expect(p.runs, '161/5');
      expect(p.overs, '18 ov');
    });

    test('all-out chase with no /wkts on the total', () {
      final p = cricketScoreParts(_cric('106 (17/20 ov, target 171)'));
      expect(p.runs, '106');
      expect(p.overs, '17 ov');
    });

    test('first-innings total with no parenthetical → no overs tag', () {
      final p = cricketScoreParts(_cric('170/6'));
      expect(p.runs, '170/6');
      expect(p.overs, isNull);
    });

    test('two-innings first-class line is kept intact', () {
      final p = cricketScoreParts(_cric('469 & 246/6d'));
      expect(p.runs, '469 & 246/6d');
      expect(p.overs, isNull);
    });

    test('two innings + chase parenthetical: keep both totals, peel the chase', () {
      final p = cricketScoreParts(_cric('263 & 44/1 (15 ov, target 453)'));
      expect(p.runs, '263 & 44/1');
      expect(p.overs, '15 ov');
    });

    test('follow-on marker is stripped with the parenthetical', () {
      final p = cricketScoreParts(_cric('187 & 326/7 (117 ov) (f/o)'));
      expect(p.runs, '187 & 326/7');
      expect(p.overs, '117 ov');
    });

    test('ball-fraction overs keep their decimal', () {
      final p = cricketScoreParts(_cric('268 (99.3 ov)'));
      expect(p.runs, '268');
      expect(p.overs, '99.3 ov');
    });

    test('overs come through as written (no stray .0)', () {
      expect(cricketScoreParts(_cric('44/1 (15 ov)')).overs, '15 ov');
    });

    test('empty / pre-innings score yields a blank runs line for callers to dash', () {
      expect(cricketScoreParts(_cric('')).runs, '');
      expect(cricketScoreParts(Competitor.fromJson(const {'kind': 'team', 'id': '1', 'displayName': 'T'})).runs, '');
    });
  });

  testWidgets('cricket GameCard shows the runs line + overs and never overflows',
      (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final ev = SportEvent.fromJson({
      'id': '1',
      'name': 'Warwickshire v Yorkshire',
      'shortName': 'WAR v YOR',
      'competitions': [
        {
          'id': '1',
          'layout': 'headToHead',
          'scoreKind': 'cricket',
          'competitorKind': 'team',
          'status': {
            'phase': 'live',
            'live': true,
            'ended': false,
            'period': 4,
            'periodLabel': 'Live',
            'espnName': 'STATUS_IN_PROGRESS',
            'detail': 'Live',
          },
          'periods': {'unit': 'over_innings', 'regulation': 2, 'played': 4, 'isOvertime': false},
          'competitors': [
            {
              'kind': 'team', 'id': '20', 'displayName': 'Yorkshire', 'shortName': 'Yorkshire',
              'abbreviation': 'YOR', 'homeAway': 'away',
              'score': {'display': '469 & 246/6d', 'cricket': {'runs': 469}},
            },
            {
              'kind': 'team', 'id': '10', 'displayName': 'Warwickshire', 'shortName': 'Warwickshire',
              'abbreviation': 'WAR', 'homeAway': 'home',
              'score': {'display': '263 & 44/1 (15 ov, target 453)', 'cricket': {'runs': 263, 'overs': 15, 'target': 453}},
            },
          ],
        }
      ],
    });

    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: GameCard(
          event: ev,
          sport: 'cricket',
          leagueKey: 'cricket/8052',
          leagueName: 'County Championship',
        ),
      ),
    ));
    await tester.pump();

    // A RenderFlex overflow would surface here as a thrown exception.
    expect(tester.takeException(), isNull);

    // Clean runs lines render; ESPN's verbose parenthetical does not.
    expect(find.text('469 & 246/6d'), findsOneWidget);
    expect(find.text('263 & 44/1'), findsOneWidget);
    expect(find.text('15 ov'), findsOneWidget);
    expect(find.text('263 & 44/1 (15 ov, target 453)'), findsNothing);
  });

  testWidgets('cricket detail hero does not overflow on a 320px phone', (tester) async {
    // iPhone-SE-class width: a two-innings hero score beside the Crest + FavStar
    // used to overflow _bigRow by 14px until _cricketBigScore became Flexible.
    final ev = _cricketDetailEvent(phase: 'final', winnerHome: true);
    await _pumpCricketDetail(tester, ev, const Size(320, 2400));

    expect(tester.takeException(), isNull, reason: 'no RenderFlex overflow at 320px');
    // The hero shows the clean two-innings runs line.
    expect(find.text('469 & 246/6d'), findsWidgets);
  });

  testWidgets('scheduled cricket shows no phantom Innings panel', (tester) async {
    // Pre-game ESPN seeds score "0" with no periodScores — the Innings panel must
    // stay hidden (no "0/0" phantom, no orphan header) until play starts.
    final ev = _cricketDetailEvent(phase: 'scheduled', seedZero: true);
    await _pumpCricketDetail(tester, ev, const Size(390, 2400));

    expect(tester.takeException(), isNull);
    expect(find.text('Innings'), findsNothing, reason: 'no Innings header pre-game');
  });
}

/// A single-competition cricket event for the detail page. `seedZero` mimics
/// ESPN's pre-game "0" score seed (no periodScores); otherwise a finished
/// two-innings first-class match.
SportEvent _cricketDetailEvent({
  required String phase,
  bool winnerHome = false,
  bool seedZero = false,
}) {
  Map<String, dynamic> comp(String id, String name, String abbr, String ha,
          String display, bool winner) =>
      {
        'kind': 'team', 'id': id, 'displayName': name, 'shortName': name,
        'abbreviation': abbr, 'homeAway': ha, 'winner': winner,
        'score': {'display': display},
      };
  final live = phase == 'live';
  return SportEvent.fromJson({
    'id': '1',
    'name': 'Warwickshire v Yorkshire',
    'shortName': 'WAR v YOR',
    'competitions': [
      {
        'id': '1',
        'layout': 'headToHead',
        'scoreKind': 'cricket',
        'competitorKind': 'team',
        'status': {
          'phase': phase,
          'live': live,
          'ended': phase == 'final',
          'period': seedZero ? 0 : 4,
          'periodLabel': phase == 'final' ? 'Final' : (live ? 'Live' : 'Scheduled'),
          'espnName': phase == 'final' ? 'STATUS_FINAL' : (live ? 'STATUS_IN_PROGRESS' : 'STATUS_SCHEDULED'),
          'detail': '',
        },
        'periods': {'unit': 'over_innings', 'regulation': 2, 'played': seedZero ? 0 : 4, 'isOvertime': false},
        'competitors': [
          comp('20', 'Yorkshire', 'YOR', 'away', seedZero ? '0' : '469 & 246/6d', !winnerHome && !seedZero),
          comp('10', 'Warwickshire', 'WAR', 'home', seedZero ? '0' : '263 & 44/1 (15 ov, target 453)', winnerHome && !seedZero),
        ],
      }
    ],
  });
}

Future<void> _pumpCricketDetail(WidgetTester tester, SportEvent ev, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  // Unmount so the detail page's live-poll timer/observer are disposed.
  addTearDown(() async => tester.pumpWidget(const SizedBox()));
  // Empty baseUrl → rich /summary stays dormant and no live poll is armed.
  SharedPreferences.setMockInitialValues({'baseUrl': ''});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    child: MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: GameDetailPage(
          event: ev, sport: 'cricket', leagueKey: 'cricket/8052', leagueName: 'County Championship'),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 50));
}
