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
    // Carried running score is lifted onto the scoring plays (away–home).
    expect(find.text('3–0'), findsOneWidget);
    expect(find.text('3–2'), findsOneWidget);
  });
}
