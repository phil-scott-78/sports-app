import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scores/src/models.dart';
import 'package:scores/src/providers.dart';
import 'package:scores/src/ui/game_detail_page.dart';
import 'package:scores/src/ui/score_tables.dart';
import 'package:scores/src/ui/detail_panels.dart';
import 'package:scores/src/ui/box_score.dart';
import 'package:scores/src/ui/summary_feed.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Loads the canonical MLB response normalized from real ESPN data
/// (see .scratch/gen-fixture.mjs).
ScoresResponse _loadMlb() {
  final raw = File('test/fixtures/mlb.json').readAsStringSync();
  return ScoresResponse.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

Future<void> _pumpDetail(WidgetTester tester, SportEvent ev) async {
  tester.view.physicalSize = const Size(400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  // Unmount so the detail page's live-poll timer/observer are disposed.
  addTearDown(() async => tester.pumpWidget(const SizedBox()));
  // Empty baseUrl → the rich /summary section stays dormant; cheap sections render.
  // (Explicit '' since a fresh install now defaults to AppConfig.defaultBaseUrl.)
  SharedPreferences.setMockInitialValues({'baseUrl': ''});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    child: MaterialApp(
      home: GameDetailPage(event: ev, sport: 'baseball', leagueKey: 'baseball/mlb', leagueName: 'MLB'),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 50));
}

ScoresResponse _liveEventResp(int homeScore) => ScoresResponse.fromJson({
      'sport': 'basketball', 'league': 'nba', 'leagueId': '46', 'leagueName': 'NBA', 'anyLive': true,
      'events': [
        {
          'id': '1', 'name': 'Away at Home', 'shortName': 'AWY @ HOM',
          'start': DateTime.now().toUtc().toIso8601String(),
          'competitions': [
            {
              'id': '1', 'layout': 'headToHead', 'scoreKind': 'numeric', 'competitorKind': 'team',
              'status': {'phase': 'live', 'live': true, 'ended': false, 'period': 3, 'periodLabel': '3rd 7:12', 'espnName': 'STATUS_IN_PROGRESS', 'detail': ''},
              'periods': {'unit': 'quarter', 'regulation': 4, 'played': 3, 'isOvertime': false},
              'competitors': [
                {'kind': 'team', 'id': '10', 'displayName': 'Home', 'abbreviation': 'HOM', 'homeAway': 'home', 'score': {'display': '$homeScore', 'value': homeScore}},
                {'kind': 'team', 'id': '20', 'displayName': 'Away', 'abbreviation': 'AWY', 'homeAway': 'away', 'score': {'display': '80', 'value': 80}},
              ],
            }
          ],
        }
      ],
    });

void main() {
  test('normalizer carries the cheap-tier fields into the model', () {
    final r = _loadMlb();
    expect(r.events, isNotEmpty);
    final c = r.events.first.main!;
    final any = c.competitors.first;
    expect(any.hits, isNotNull, reason: 'R/H/E hits parsed');
    expect(any.errors, isNotNull, reason: 'R/H/E errors parsed');
    expect(any.leaders, isNotEmpty, reason: 'leaders parsed');
    expect(any.stats, isNotEmpty, reason: 'team stat line parsed');
  });

  testWidgets('baseball detail shows the R/H/E line score', (tester) async {
    final r = _loadMlb();
    final ev = r.events.firstWhere((e) => e.main!.competitors.any((c) => c.hits != null));
    await _pumpDetail(tester, ev);

    expect(find.text('Line score'), findsOneWidget);
    expect(find.byType(LineScoreTable), findsOneWidget);
    // R / H / E summary headers are present in the table.
    expect(find.text('R'), findsWidgets);
    expect(find.text('H'), findsWidgets);
    expect(find.text('E'), findsWidgets);
  });

  testWidgets('live baseball detail shows the situation strip and leaders', (tester) async {
    final r = _loadMlb();
    final live = r.events.firstWhere(
      (e) => e.main!.status.live && (e.main!.situation?.hasBaseball ?? false),
    );
    await _pumpDetail(tester, live);

    expect(find.byType(LiveSituationStrip), findsOneWidget);
    expect(find.text('Now batting'), findsOneWidget);
    expect(find.byType(LeadersStrip), findsOneWidget);
    expect(find.text('Leaders'), findsOneWidget);
  });

  testWidgets('game detail live-updates its header score on the poll beat', (tester) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var score = 88;
    SharedPreferences.setMockInitialValues({'baseUrl': 'https://w.example'});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      // A today/live game → detail polls the (league, null) key; ignore it and
      // serve the current score, which the timer-driven invalidation re-reads.
      leagueDayScoresProvider.overrideWith((ref, key) async => _liveEventResp(score)),
    ]);
    addTearDown(container.dispose);

    final ev = _liveEventResp(88).events.first;
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: GameDetailPage(event: ev, sport: 'basketball', leagueKey: 'basketball/nba', leagueName: 'NBA'),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50)); // resolve the initial poll
    expect(find.text('88'), findsWidgets);

    score = 91; // the live game ticks
    await tester.pump(const Duration(seconds: 16)); // fires the 15s live poll → invalidate
    await tester.pump(const Duration(milliseconds: 50)); // resolve + rebuild header
    expect(find.text('91'), findsWidgets, reason: 'header re-derived from the polled day');
    expect(find.text('88'), findsNothing);

    await tester.pumpWidget(const SizedBox()); // dispose the poll timer
  });

  testWidgets('rich /summary section renders box score, scoring, period grid & team stats', (tester) async {
    final scores = ScoresResponse.fromJson(
        jsonDecode(File('test/fixtures/nfl.json').readAsStringSync()) as Map<String, dynamic>);
    final ev = scores.events.first;
    final summary = GameSummary.fromJson(
        jsonDecode(File('test/fixtures/summary_nfl.json').readAsStringSync()) as Map<String, dynamic>);

    tester.view.physicalSize = const Size(400, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async => tester.pumpWidget(const SizedBox()));

    SharedPreferences.setMockInitialValues({'baseUrl': 'https://w.example'});
    final prefs = await SharedPreferences.getInstance();
    const key = (league: 'football/nfl', eventId: '401772988');

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        summaryProvider(key).overrideWith((ref) => summary),
      ],
      child: const SizedBox(),
    ));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        summaryProvider(key).overrideWith((ref) => summary),
      ],
      child: MaterialApp(
        home: GameDetailPage(event: ev, sport: 'football', leagueKey: 'football/nfl', leagueName: 'NFL'),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(PeriodLinesGrid), findsOneWidget, reason: 'NFL quarter grid (summary tier)');
    expect(find.byType(SummaryTeamStats), findsOneWidget);
    expect(find.byType(ScoringFeed), findsOneWidget);
    expect(find.byType(BoxScoreTable), findsOneWidget);
    expect(find.text('Box score'), findsOneWidget);
  });
}
