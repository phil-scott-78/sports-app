// The unified action feed (design turn 9) is now the ONE way every sport renders
// a play list. This drives a basketball game through the real GameDetailPage to
// prove the generic play-by-play path: grouped by period under a header, the
// carried running score lifted onto scoring plays, non-scoring plays still shown.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scores/src/models.dart';
import 'package:scores/src/providers.dart';
import 'package:scores/src/theme.dart';
import 'package:scores/src/ui/game_detail_page.dart';
import 'package:scores/src/ui/match_events.dart';
import 'package:scores/src/ui/widgets.dart';

Future<SharedPreferences> prefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

Map<String, dynamic> nbaScores() => {
      'sport': 'basketball',
      'league': 'nba',
      'leagueId': '46',
      'leagueName': 'NBA',
      'season': {'year': 2026, 'type': 2},
      'anyLive': true,
      'events': [
        {
          'id': 'G1',
          'name': 'Thunder vs Cavaliers',
          'shortName': 'OKC v CLE',
          'start': '2026-07-05T00:00:00Z',
          'neutralSite': false,
          'broadcasts': <String>[],
          'notes': <String>[],
          'links': <String, dynamic>{},
          'competitions': [
            {
              'id': 'G1',
              'layout': 'headToHead',
              'scoreKind': 'numeric',
              'competitorKind': 'team',
              'status': {'phase': 'live', 'live': true, 'ended': false, 'period': 2, 'detail': 'Q2 5:00'},
              'periods': {'unit': 'quarter', 'regulation': 4, 'played': 2},
              'competitors': [
                {'kind': 'team', 'id': 'OKC', 'displayName': 'Thunder', 'abbreviation': 'OKC', 'homeAway': 'away', 'score': {'display': '20', 'value': 20}},
                {'kind': 'team', 'id': 'CLE', 'displayName': 'Cavaliers', 'abbreviation': 'CLE', 'homeAway': 'home', 'score': {'display': '18', 'value': 18}},
              ],
            },
          ],
        },
      ],
    };

void main() {
  testWidgets('generic play-by-play renders through the unified feed, grouped by quarter',
      (tester) async {
    final p = await prefs();
    final scores = ScoresResponse.fromJson(nbaScores());
    final summary = GameSummary.fromJson({
      'eventId': 'G1', 'live': true, 'teamStats': <dynamic>[],
      'boxGroups': <dynamic>[], 'lineups': <dynamic>[], 'scoringPlays': <dynamic>[],
      // No periodLabel — exercises the unit-based header fallback (NFL omits it).
      'plays': [
        {'period': 1, 'clock': '10:32', 'side': 'away', 'teamAbbr': 'OKC', 'text': 'SGA makes 25-foot three point jumper', 'away': 3, 'home': 0, 'scoring': true},
        {'period': 1, 'clock': '9:58', 'side': 'home', 'teamAbbr': 'CLE', 'text': 'Mitchell misses driving layup', 'scoring': false},
        {'period': 2, 'clock': '5:12', 'side': 'home', 'teamAbbr': 'CLE', 'text': 'Mobley makes two point dunk', 'away': 3, 'home': 2, 'scoring': true},
      ],
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(p),
        leagueScoresProvider.overrideWith((ref, league) async => scores),
        summaryProvider.overrideWith((ref, key) async => summary),
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

    // Grouped under period headers (now the §9 rule-label divider, which carries
    // the container's running score — 'NTH QUARTER · away–home'), newest first.
    expect(find.textContaining('1ST QUARTER'), findsOneWidget);
    expect(find.textContaining('2ND QUARTER'), findsOneWidget);
    // Scoring AND non-scoring plays both render (full feed).
    expect(find.text('SGA makes 25-foot three point jumper'), findsOneWidget);
    expect(find.text('Mitchell misses driving layup'), findsOneWidget);
    expect(find.text('Mobley makes two point dunk'), findsOneWidget);
    // Carried running score is lifted onto the scoring plays (away–home). §9d's
    // persistent column also carries 3–0 forward onto the following (non-scoring)
    // miss row, so it renders on both the basket and the quiet row after it.
    expect(find.text('3–0'), findsNWidgets(2));
    expect(find.text('3–2'), findsOneWidget);
  });

  // Regression: an NBA coach's challenge whose text merely *mentions* a timeout
  // ("...retain their timeout") must NOT collapse into a one-line timeout divider
  // (a divider uppercases the whole text and can't wrap → it overflowed the row on
  // a phone). A genuine "Full timeout" still becomes a divider.
  testWidgets('challenge that mentions a timeout stays a wrapping row (not a divider)',
      (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final comp = Competition.fromJson({
      'id': 'C1', 'layout': 'headToHead', 'scoreKind': 'numeric', 'competitorKind': 'team',
      'status': {'phase': 'final', 'live': false, 'ended': true, 'period': 4, 'detail': 'Final'},
      'periods': {'unit': 'quarter', 'regulation': 4, 'played': 4},
      'competitors': [
        {'kind': 'team', 'id': '24', 'displayName': 'Spurs', 'abbreviation': 'SA', 'homeAway': 'away', 'color': '000000', 'score': {'display': '82', 'value': 82}},
        {'kind': 'team', 'id': '18', 'displayName': 'Knicks', 'abbreviation': 'NY', 'homeAway': 'home', 'color': '006BB6', 'score': {'display': '99', 'value': 99}},
      ],
    });
    const challengeText =
        "(04:42) [Spurs] COACH'S CHALLENGE (CALL OVERTURNED) [Spurs] retain their timeout";
    final events = [
      MatchEvent.fromSummaryPlay(SummaryPlay.fromJson(const {
        'period': 4, 'clock': '4:42', 'side': 'away', 'teamAbbr': 'SA',
        'text': challengeText, 'scoring': false,
      })),
      MatchEvent.fromSummaryPlay(SummaryPlay.fromJson(const {
        'period': 4, 'clock': '4:01', 'side': 'home', 'teamAbbr': 'NY',
        'text': 'New York Knicks Full timeout', 'scoring': false,
      })),
    ];

    await tester.pumpWidget(MaterialApp(
      theme: buildV2Theme(),
      home: Scaffold(body: SingleChildScrollView(child: ActionFeed(events, comp))),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    // The challenge shows as a normal row → its text keeps original case.
    expect(find.textContaining('retain their timeout'), findsOneWidget);
    // …and is NOT uppercased into a divider label.
    expect(find.textContaining('RETAIN THEIR TIMEOUT'), findsNothing);
    // The genuine timeout DID collapse into a rule-label divider ('...TIMEOUT · 4:01').
    expect(find.textContaining('FULL TIMEOUT'), findsOneWidget);
  });

  // §4a regression: the Plays tab renders through the virtualized
  // [ActionFeedSliver] (a SliverList.builder inside the page CustomScrollView),
  // NOT a boxed [ActionFeed] Column that materializes every row. A big game's
  // off-screen plays must not be built — the flatten is memoized and only the
  // visible slice is realized.
  testWidgets('Plays tab virtualizes: off-screen plays are not built',
      (tester) async {
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final p = await prefs();
    final scores = ScoresResponse.fromJson(nbaScores());
    // 4 quarters × 50 plays — well past the >60 threshold and far taller than
    // one viewport, so the bottom (oldest, Q1) plays fall outside the sliver's
    // build + cache window.
    final plays = <Map<String, dynamic>>[
      for (var period = 1; period <= 4; period++)
        for (var i = 0; i < 50; i++)
          {
            'period': period,
            'clock': '10:00',
            'side': i.isEven ? 'away' : 'home',
            'teamAbbr': i.isEven ? 'OKC' : 'CLE',
            'text': 'P${period}_$i action',
            'scoring': false,
          },
    ];
    final summary = GameSummary.fromJson({
      'eventId': 'G1', 'live': true, 'teamStats': <dynamic>[],
      'boxGroups': <dynamic>[], 'lineups': <dynamic>[],
      'scoringPlays': <dynamic>[], 'plays': plays,
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(p),
        leagueScoresProvider.overrideWith((ref, league) async => scores),
        summaryProvider.overrideWith((ref, key) async => summary),
      ],
      child: MaterialApp(
        theme: buildV2Theme(),
        home: GameDetailPage(
            league: 'basketball/nba', initialEvent: scores.events.first),
      ),
    ));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Plays'));
    await tester.pump();

    // The virtualized sliver path owns the body — not a mounted boxed feed.
    expect(find.byType(ActionFeedSliver), findsOneWidget);
    expect(find.byType(ActionFeed), findsNothing);
    // Newest period first: the 4th-quarter header sits at the top and builds…
    expect(find.textContaining('4TH QUARTER'), findsOneWidget);
    // …while the very last row (oldest Q1 play) is off-screen and NOT built.
    expect(find.text('P1_0 action'), findsNothing);
  });

  testWidgets('RuleLabelDivider ellipsizes an over-long label instead of overflowing',
      (tester) async {
    tester.view.physicalSize = const Size(320, 200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Column(children: [
          RuleLabelDivider(
              "(04:42) [SPURS] COACH'S CHALLENGE (CALL OVERTURNED) [SPURS] RETAIN THEIR TIMEOUT · 4:42"),
          RuleLabelDivider('3RD QUARTER · 68–61'),
        ]),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    // A short label is untouched (renders in full).
    expect(find.text('3RD QUARTER · 68–61'), findsOneWidget);
  });
}
