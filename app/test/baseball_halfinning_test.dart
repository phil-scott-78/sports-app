// §3c / design 9b — baseball scoring plays group into per-half-inning cards
// (keyed on period + half), so a multi-run bottom no longer merges into the top
// of the same inning. Driven through the real GameDetailPage (Recap tab).
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

Map<String, dynamic> _comp() => {
      'id': 'B1',
      'layout': 'headToHead',
      'scoreKind': 'numeric',
      'competitorKind': 'team',
      'status': {'phase': 'final', 'live': false, 'ended': true, 'period': 9, 'espnName': 'STATUS_FINAL', 'detail': 'Final'},
      'periods': {'unit': 'inning', 'regulation': 9, 'played': 9},
      'competitors': [
        {'kind': 'team', 'id': '20', 'displayName': 'Astros', 'abbreviation': 'HOU', 'homeAway': 'away', 'color': '002D62', 'score': {'display': '1', 'value': 1}},
        {'kind': 'team', 'id': '18', 'displayName': 'Cubs', 'abbreviation': 'CHC', 'homeAway': 'home', 'color': '0E3386', 'score': {'display': '5', 'value': 5}},
      ],
    };

Map<String, dynamic> _scores() => {
      'sport': 'baseball',
      'league': 'mlb',
      'leagueId': '10',
      'leagueName': 'MLB',
      'season': {'year': 2026, 'type': 2},
      'anyLive': false,
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
          'competitions': [_comp()],
        },
      ],
    };

GameSummary _summary() => GameSummary.fromJson({
      'eventId': 'B1',
      'live': false,
      'teamStats': <dynamic>[],
      'boxGroups': [
        {
          'title': 'Batting',
          'columns': ['AB', 'R', 'H', 'RBI', 'K'],
          'teams': [
            {
              'side': 'home',
              'abbr': 'CHC',
              'rows': [
                {'name': 'K. Schwarber', 'pos': 'DH', 'stats': ['4', '1', '2', '1', '1'], 'starter': true},
                {'name': 'J. Crawford', 'pos': 'CF', 'stats': ['1', '0', '0', '0', '1'], 'starter': false, 'note': 'a-struck out swinging for Schwarber in the 8th'},
              ],
            },
          ],
        },
      ],
      'lineups': <dynamic>[],
      'scoringPlays': [
        {'period': 1, 'half': 'top', 'side': 'away', 'teamAbbr': 'HOU', 'text': 'Altuve homers (12)', 'away': 1, 'home': 0, 'type': 'Home Run', 'scoring': true},
        {'period': 6, 'half': 'bottom', 'side': 'home', 'teamAbbr': 'CHC', 'text': 'Suzuki homers (18)', 'away': 1, 'home': 2, 'type': 'Home Run', 'scoring': true},
        {'period': 6, 'half': 'bottom', 'side': 'home', 'teamAbbr': 'CHC', 'text': 'Happ doubles, 2 RBI', 'away': 1, 'home': 4, 'type': 'Double', 'scoring': true},
        {'period': 8, 'half': 'bottom', 'side': 'home', 'teamAbbr': 'CHC', 'text': 'Hoerner singles, RBI', 'away': 1, 'home': 5, 'type': 'Single', 'scoring': true},
      ],
    });

void main() {
  testWidgets('baseball Recap groups scoring plays into per-half-inning cards',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2800);
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
        home: GameDetailPage(league: 'baseball/mlb', initialEvent: scores.events.first),
      ),
    ));
    await tester.pump(); // resolve summary future
    await tester.pump();

    // The top of the 1st and the bottom of the 6th are DISTINCT containers —
    // the old flat feed merged both halves under one "6TH INNING" divider.
    expect(find.textContaining('TOP 1'), findsOneWidget);
    expect(find.textContaining('BOTTOM 6'), findsOneWidget);
    expect(find.textContaining('BOTTOM 8'), findsOneWidget);
    // The bottom-6 card carries BOTH of its scoring plays.
    expect(find.text('Suzuki homers (18)'), findsOneWidget);
    expect(find.text('Happ doubles, 2 RBI'), findsOneWidget);
    expect(find.text('Altuve homers (12)'), findsOneWidget);
    // Row running score leads with the scoring team (home) — Happ makes it 4–1.
    expect(find.text('4–1'), findsOneWidget);
    // Container header shows the running score at the end of the half-inning.
    expect(find.textContaining('CHC 4'), findsWidgets);
  });

  testWidgets('baseball Box indents substitutes with the letter marker + footnote',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2800);
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
        home: GameDetailPage(league: 'baseball/mlb', initialEvent: scores.events.first),
      ),
    ));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Box'));
    await tester.pump();

    expect(find.textContaining('K. Schwarber', findRichText: true), findsOneWidget);
    expect(find.textContaining('J. Crawford', findRichText: true), findsOneWidget); // the sub
    // The lineup note renders as a footnote, and the letter marker prefixes the sub.
    expect(find.text('a-struck out swinging for Schwarber in the 8th'), findsOneWidget);
    expect(find.text('a-'), findsOneWidget);
  });
}
