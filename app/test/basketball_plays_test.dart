// §4b / design 9d — the basketball Plays feed: a period (quarter) filter as a
// length control, the resolved actor bolded in each row, and timeouts rendered as
// rule-label dividers. NBA is off-season so the mock has no participants/timeouts;
// this drives synthetic plays through the real GameDetailPage.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scores/src/models.dart';
import 'package:scores/src/providers.dart';
import 'package:scores/src/theme.dart';
import 'package:scores/src/ui/game_detail_page.dart';
import 'package:scores/src/ui/match_events.dart';

Future<SharedPreferences> prefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

Map<String, dynamic> _comp() => {
      'id': 'K1',
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
          'id': 'K1',
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

List<Map<String, dynamic>> _plays() {
  final out = <Map<String, dynamic>>[];
  for (var q = 1; q <= 4; q++) {
    for (var i = 0; i < 16; i++) {
      final away = i % 2 == 0;
      out.add({
        'period': q,
        'clock': '${11 - (i % 12)}:00',
        'side': away ? 'away' : 'home',
        'teamAbbr': away ? 'LAL' : 'BOS',
        'actor': away ? 'L. James' : 'J. Tatum',
        'text': '${away ? 'LeBron James' : 'Jayson Tatum'} makes ${10 + i}-foot jumper',
        'away': q * 20 + i,
        'home': q * 20 + i - 3,
        'scoring': i % 3 == 0,
      });
    }
  }
  // a timeout in Q2 (renders as a divider), and unique per-quarter markers so the
  // filter's effect is observable.
  out.add({'period': 2, 'clock': '4:01', 'teamAbbr': 'LAL', 'text': 'Los Angeles Lakers Full timeout', 'scoring': false});
  out.add({'period': 1, 'text': 'ZZ_Q1_ONLY', 'scoring': false});
  out.add({'period': 4, 'text': 'ZZ_Q4_ONLY', 'scoring': false});
  return out;
}

GameSummary _summary() => GameSummary.fromJson({
      'eventId': 'K1',
      'live': false,
      'teamStats': <dynamic>[],
      'boxGroups': <dynamic>[],
      'lineups': <dynamic>[],
      'scoringPlays': <dynamic>[],
      'plays': _plays(),
    });

void main() {
  testWidgets('basketball Plays: quarter filter + bold actor + timeout divider',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
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

    await tester.tap(find.text('Plays'));
    await tester.pump();

    // The quarter filter (a dense feed spanning 4 quarters).
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Q1'), findsOneWidget);
    expect(find.text('Q4'), findsOneWidget);
    // The actor is bolded (a RichText span) in the rows.
    expect(find.textContaining('L. James', findRichText: true), findsWidgets);
    // The timeout renders as a divider carrying its label.
    expect(find.textContaining('TIMEOUT'), findsOneWidget);
    // Both quarters' unique markers are present in the unfiltered view.
    expect(find.text('ZZ_Q1_ONLY'), findsOneWidget);
    expect(find.text('ZZ_Q4_ONLY'), findsOneWidget);

    // Filter to Q1 → the Q4-only marker drops out, the Q1-only one stays.
    await tester.tap(find.text('Q1'));
    await tester.pump();
    expect(find.text('ZZ_Q1_ONLY'), findsOneWidget);
    expect(find.text('ZZ_Q4_ONLY'), findsNothing);
  });

  // §9d signal-row discipline + persistent score column, exercised on the dense
  // feed directly. Three plays in one quarter: an ordinary go-ahead basket
  // (2–0), a miss, then a basket that flips the lead (2–4 → a §9 signal row).
  testWidgets('dense feed: quiet ordinary scoring row, persistent column, loud signal row',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final comp = Competition.fromJson(_comp());
    final events = [
      for (final p in const [
        {'period': 1, 'clock': '11:00', 'side': 'away', 'teamAbbr': 'LAL', 'text': 'James makes layup', 'away': 2, 'home': 0, 'scoring': true},
        {'period': 1, 'clock': '10:30', 'side': 'home', 'teamAbbr': 'BOS', 'text': 'Tatum misses jumper', 'scoring': false},
        {'period': 1, 'clock': '10:00', 'side': 'home', 'teamAbbr': 'BOS', 'text': 'Brown makes three', 'away': 2, 'home': 4, 'scoring': true},
      ])
        MatchEvent.fromSummaryPlay(SummaryPlay.fromJson(p)),
    ];

    await tester.pumpWidget(MaterialApp(
      theme: buildV2Theme(),
      home: Scaffold(body: SingleChildScrollView(child: ActionFeed(events, comp))),
    ));
    await tester.pump();

    // Persistent column: the 2–0 running score shows on BOTH the go-ahead basket
    // AND the following (non-scoring) miss — the tally is carried forward.
    expect(find.text('2–0'), findsNWidgets(2));
    // …and both are QUIET: Barlow 14/600 in textFaint (no signal emphasis).
    for (final t in tester.widgetList<Text>(find.text('2–0'))) {
      expect(t.style!.fontWeight, FontWeight.w600);
      expect(t.style!.color, T.textFaint);
      expect(t.style!.fontSize, 14);
    }

    // The lead-flipping basket is the one signal row: white 700 score + LEAD pill.
    expect(find.text('2–4'), findsOneWidget);
    final signalScore = tester.widget<Text>(find.text('2–4'));
    expect(signalScore.style!.fontWeight, FontWeight.w700);
    expect(signalScore.style!.color, T.text);
    expect(find.text('LEAD'), findsOneWidget);
  });
}
