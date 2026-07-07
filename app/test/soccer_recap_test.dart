// Soccer game-detail polish, driven through the real GameDetailPage:
//   - the Timeline tab is the curated event feed (design 9a): goals with the
//     scorer/assist + running score, cards, subs (on·off), grouped under period
//     headers — sourced from the worker's structured `timeline`,
//   - the Recap "Scoring" log shows GOALS ONLY (running score, no cards/subs),
//   - the match-timeline bar renders after full-time (FT), not just live,
//   - a match with no cheap timeline still falls back to the grouped Plays list.
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

Map<String, dynamic> _comp(Object status, {List<Map<String, dynamic>> events = const []}) => {
      'id': 'M1',
      'layout': 'headToHead',
      'scoreKind': 'numeric',
      'competitorKind': 'team',
      'status': status,
      'periods': {'unit': 'half', 'regulation': 2, 'played': 2, 'lengthMin': 45},
      'competitors': [
        {'kind': 'team', 'id': 'ARS', 'displayName': 'Arsenal', 'abbreviation': 'ARS', 'homeAway': 'away', 'score': {'display': '2', 'value': 2}},
        {'kind': 'team', 'id': 'CHE', 'displayName': 'Chelsea', 'abbreviation': 'CHE', 'homeAway': 'home', 'score': {'display': '0', 'value': 0}},
      ],
      if (events.isNotEmpty) 'events': events,
    };

Map<String, dynamic> _scores(Map<String, dynamic> comp) => {
      'sport': 'soccer',
      'league': 'eng.1',
      'leagueId': '700',
      'leagueName': 'Premier League',
      'season': {'year': 2026, 'type': 2},
      'anyLive': false,
      'events': [
        {
          'id': 'M1',
          'name': 'Arsenal vs Chelsea',
          'shortName': 'ARS v CHE',
          'start': '2026-07-05T14:00:00Z',
          'neutralSite': false,
          'broadcasts': <String>[],
          'notes': <String>[],
          'links': <String, dynamic>{},
          'competitions': [comp],
        },
      ],
    };

const _endedStatus = {
  'phase': 'final', 'live': false, 'ended': true, 'period': 2,
  'periodLabel': 'FT', 'espnName': 'STATUS_FULL_TIME', 'detail': 'FT',
};

// A finished ARS 2–0 CHE with a cheap goal/card timeline on the competition.
Map<String, dynamic> endedScores() => _scores(_comp(_endedStatus, events: [
      {'type': 'goal', 'team': 'away', 'clock': "12'", 'athlete': 'Saka', 'detail': 'Goal'},
      {'type': 'goal', 'team': 'away', 'clock': "54'", 'athlete': 'Ødegaard', 'detail': 'Goal'},
      {'type': 'red-card', 'team': 'home', 'clock': "70'", 'detail': 'Red Card', 'flags': {'redCard': true}},
    ]));

Future<void> _pump(WidgetTester tester, Map<String, dynamic> scoresJson, GameSummary summary) async {
  final p = await prefs();
  final scores = ScoresResponse.fromJson(scoresJson);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(p),
      leagueScoresProvider.overrideWith((ref, league) async => scores),
      summaryProvider.overrideWith((ref, key) async => summary),
    ],
    child: MaterialApp(
      theme: buildV2Theme(),
      home: GameDetailPage(league: 'soccer/eng.1', initialEvent: scores.events.first),
    ),
  ));
  await tester.pump();
  await tester.pump();
}

GameSummary _summary(Map<String, dynamic> extra) => GameSummary.fromJson({
      'eventId': 'M1', 'live': false, 'teamStats': <dynamic>[],
      'boxGroups': <dynamic>[], 'lineups': <dynamic>[], 'scoringPlays': <dynamic>[],
      ...extra,
    });

void main() {
  testWidgets('Recap "Scoring" is goals only (running score) + the timeline bar reads FT',
      (tester) async {
    // Summary carries a card + sub in the old scoring feed — they must NOT leak
    // into the goals-only Recap log.
    await _pump(tester, endedScores(), _summary({
      'scoringPlays': [
        {'clock': "70'", 'text': 'Second booking, Chelsea down to ten.', 'type': 'Red Card', 'scoring': false},
      ],
    }));

    expect(find.text('MATCH TIMELINE'), findsOneWidget); // the bar
    expect(find.text('FT'), findsWidgets);

    expect(find.text('SCORING'), findsOneWidget);
    expect(find.text('GOAL — Saka'), findsOneWidget);
    expect(find.text('GOAL — Ødegaard'), findsOneWidget);
    expect(find.text('1–0'), findsOneWidget); // Saka (away) opens the scoring
    expect(find.text('2–0'), findsOneWidget); // Ødegaard doubles it
    expect(find.text('Second booking, Chelsea down to ten.'), findsNothing);
  });

  testWidgets('Timeline tab: rich event feed — goals+assist, subs, cards, half dividers',
      (tester) async {
    await _pump(tester, endedScores(), _summary({
      'timeline': [
        {'t': 13, 'clock': "13'", 'period': 1, 'kind': 'goal', 'side': 'away', 'teamAbbr': 'ARS', 'athlete': 'Saka', 'assist': 'Ødegaard', 'scoring': true},
        {'t': 40, 'clock': "40'", 'period': 1, 'kind': 'yellow-card', 'side': 'home', 'teamAbbr': 'CHE', 'athlete': 'Caicedo'},
        {'t': 54, 'clock': "54'", 'period': 2, 'kind': 'goal', 'side': 'away', 'teamAbbr': 'ARS', 'athlete': 'Ødegaard', 'scoring': true},
        {'t': 70, 'clock': "70'", 'period': 2, 'kind': 'substitution', 'side': 'away', 'teamAbbr': 'ARS', 'athlete': 'Trossard', 'assist': 'Saka'},
        {'t': 75, 'clock': "75'", 'period': 2, 'kind': 'red-card', 'side': 'home', 'teamAbbr': 'CHE', 'athlete': 'James'},
      ],
    }));

    await tester.tap(find.text('Timeline'));
    await tester.pump();

    expect(find.text('GOAL — Saka'), findsOneWidget);
    expect(find.text('Assist: Ødegaard'), findsOneWidget);
    expect(find.text('GOAL — Ødegaard'), findsOneWidget);
    expect(find.text('Substitution — ARS'), findsOneWidget);
    expect(find.text('Trossard on · Saka off'), findsOneWidget);
    expect(find.text('Yellow card — Caicedo'), findsOneWidget);
    expect(find.text('Red card — James'), findsOneWidget);
    // period group headers — now the §9 rule-label divider carrying the running
    // score at the break ('2ND HALF · 2–1'), so match the label as a substring.
    expect(find.textContaining('2ND HALF'), findsOneWidget);
    expect(find.textContaining('1ST HALF'), findsOneWidget);
    expect(find.text('1–0'), findsOneWidget);
    expect(find.text('2–0'), findsOneWidget);
  });

  testWidgets('no cheap timeline → grouped Plays list (whole feed, no 40-cap)',
      (tester) async {
    // A live match with no competition.events: falls back to the grouped Plays
    // card sourced from the commentary feed.
    final live = {'phase': 'live', 'live': true, 'ended': false, 'period': 2, 'detail': "70'"};
    await _pump(tester, _scores(_comp(live)), _summary({
      'live': true,
      'plays': [
        for (var i = 1; i <= 25; i++)
          {'clock': "$i'", 'period': 1, 'periodLabel': '1st Half', 'text': 'H1 play $i'},
        for (var i = 46; i <= 70; i++)
          {'clock': "$i'", 'period': 2, 'periodLabel': '2nd Half', 'text': 'H2 play $i'},
      ],
    }));

    await tester.tap(find.text('Plays'));
    await tester.pump();

    expect(find.text('2ND HALF'), findsOneWidget);
    expect(find.text('1ST HALF'), findsOneWidget);
    // The very first play survives — the old take(40) on the newest-first feed
    // dropped everything past row 40, which included the early first-half plays.
    expect(find.text('H1 play 1'), findsOneWidget);
    expect(find.text('H2 play 46'), findsOneWidget);
  });
}
