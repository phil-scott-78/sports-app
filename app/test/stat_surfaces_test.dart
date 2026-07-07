// The ported team-stat surfaces, driven through the real GameDetailPage:
//   - the cheap-tier "Match stats" panel off the scoreboard (live 'Now' view),
//   - team sheets (lineups) that v2 already parsed but never rendered,
//   - the rich /summary team-stat card with its "All team stats" expander.
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

Map<String, dynamic> _team(String abbr, String ha, String score,
        Map<String, String> stats) =>
    {
      'kind': 'team',
      'id': abbr,
      'displayName': abbr,
      'abbreviation': abbr,
      'homeAway': ha,
      'score': {'display': score, 'value': int.parse(score)},
      'stats': stats,
    };

Map<String, dynamic> soccerScores() => {
      'sport': 'soccer',
      'league': 'eng.1',
      'leagueId': '700',
      'leagueName': 'Premier League',
      'season': {'year': 2026, 'type': 2},
      'anyLive': true,
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
          'competitions': [
            {
              'id': 'M1',
              'layout': 'headToHead',
              'scoreKind': 'numeric',
              'competitorKind': 'team',
              'status': {
                'phase': 'live',
                'live': true,
                'ended': false,
                'period': 2,
                'periodLabel': "2nd Half",
                'espnName': 'STATUS_IN_PROGRESS',
                'detail': "62'",
              },
              'periods': {
                'unit': 'half',
                'regulation': 2,
                'played': 2,
                'isOvertime': false,
              },
              'decision': null,
              'competitors': [
                _team('ARS', 'away', '1',
                    {'PP': '58.0', 'SHOT': '11', 'SOG': '5', 'CW': '6'}),
                _team('CHE', 'home', '0',
                    {'PP': '42.0', 'SHOT': '7', 'SOG': '2', 'CW': '3'}),
              ],
            },
          ],
        },
      ],
    };

// A rich summary: 12 team-stat rows (soccer has no priority keywords, so the
// first 8 lead and the last 4 fold), plus two team sheets.
GameSummary soccerSummary() => GameSummary.fromJson({
      'eventId': 'M1',
      'live': true,
      'teamStats': [
        for (var i = 1; i <= 12; i++)
          {
            'label': 'Stat${i.toString().padLeft(2, '0')}',
            'away': '$i',
            'home': '${13 - i}',
          },
      ],
      'boxGroups': <dynamic>[],
      'scoringPlays': <dynamic>[],
      'lineups': [
        {
          'side': 'away',
          'abbr': 'ARS',
          'formation': '4-3-3',
          'starters': [
            {'name': 'Raya', 'pos': 'G', 'jersey': '1'},
            {'name': 'Saka', 'pos': 'F', 'jersey': '7'},
          ],
          'bench': [
            {'name': 'Trossard', 'pos': 'F', 'jersey': '19'},
          ],
        },
        {
          'side': 'home',
          'abbr': 'CHE',
          'formation': '4-2-3-1',
          'starters': [
            {'name': 'Sanchez', 'pos': 'G', 'jersey': '1'},
          ],
          'bench': <dynamic>[],
        },
      ],
    });

void main() {
  testWidgets('live soccer shows cheap match-stats + lineups; Box has rich stats + expander',
      (tester) async {
    final p = await prefs();
    final scores = ScoresResponse.fromJson(soccerScores());
    final event = scores.events.first;
    final summary = soccerSummary();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(p),
        leagueScoresProvider.overrideWith((ref, league) async => scores),
        summaryProvider.overrideWith((ref, key) async => summary),
      ],
      child: MaterialApp(
        theme: buildV2Theme(),
        home: GameDetailPage(league: 'soccer/eng.1', initialEvent: event),
      ),
    ));
    await tester.pump(); // resolve summary future
    await tester.pump();

    // 'Now' view: the cheap match-stats panel off the scoreboard...
    expect(find.text('MATCH STATS'), findsOneWidget);
    expect(find.text('Possession'), findsOneWidget);
    expect(find.text('58.0%'), findsOneWidget); // whole-form percent signed
    // ...and the team sheets that v2 now renders.
    expect(find.text('4-3-3'), findsOneWidget);
    expect(find.text('Saka'), findsOneWidget);
    expect(find.text('BENCH'), findsOneWidget); // CardLabel upper-cases
    // rich team stats are NOT on the 'Now' view.
    expect(find.text('TEAM STATS'), findsNothing);

    // Switch to the Box view: rich team stats, curated with a folded tail.
    await tester.tap(find.text('Box'));
    await tester.pump();
    expect(find.text('TEAM STATS'), findsOneWidget);
    expect(find.text('Stat01'), findsOneWidget);
    expect(find.text('Stat12'), findsNothing); // folded away
    final expander = find.text('All team stats (12)');
    await tester.ensureVisible(expander);
    await tester.pump();
    await tester.tap(expander);
    await tester.pump();
    expect(find.text('Stat12'), findsOneWidget);
  });

  testWidgets(
      'soccer Plays chip shows the FULL commentary feed (not just the scoring feed); '
      'Box gets the roster-derived player groups', (tester) async {
    final p = await prefs();
    final scores = ScoresResponse.fromJson(soccerScores());
    final event = scores.events.first;
    // The worker ships BOTH: the condensed goal/card/sub timeline (scoringPlays)
    // and the full commentary narrative (plays). The Plays chip must prefer the
    // full feed — a 0-0 half has an empty timeline but a rich narrative.
    final summary = GameSummary.fromJson({
      'eventId': 'M1',
      'live': true,
      'teamStats': <dynamic>[],
      'scoringPlays': [
        {'clock': "12'", 'text': 'Goal! Arsenal 1, Chelsea 0.', 'type': 'Goal'},
      ],
      'plays': [
        {'text': 'First Half begins.', 'period': 1, 'type': 'Kickoff'},
        {
          'clock': "9'",
          'side': 'away',
          'teamAbbr': 'ARS',
          'text': 'Foul by Saka (Arsenal).',
          'type': 'Foul',
        },
        {
          'clock': "12'",
          'text': 'Goal! Arsenal 1, Chelsea 0.',
          'type': 'Goal - Header',
          'away': 1,
          'home': 0,
        },
      ],
      'boxGroups': [
        {
          'title': 'Players',
          'columns': ['G', 'A', 'SH', 'ST', 'YC'],
          'teams': [
            {
              'side': 'away',
              'abbr': 'ARS',
              'rows': [
                {
                  'name': 'Saka',
                  'pos': 'RW',
                  'stats': ['1', '0', '2', '1', '0'],
                },
              ],
            },
          ],
        },
        {
          'title': 'Goalkeepers',
          'columns': ['SHF', 'SV', 'GA'],
          'teams': [
            {
              'side': 'home',
              'abbr': 'CHE',
              'rows': [
                {
                  'name': 'Sanchez',
                  'pos': 'G',
                  'stats': ['4', '3', '1'],
                },
              ],
            },
          ],
        },
      ],
      'lineups': <dynamic>[],
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(p),
        leagueScoresProvider.overrideWith((ref, league) async => scores),
        summaryProvider.overrideWith((ref, key) async => summary),
      ],
      child: MaterialApp(
        theme: buildV2Theme(),
        home: GameDetailPage(league: 'soccer/eng.1', initialEvent: event),
      ),
    ));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Plays'));
    await tester.pump();
    // Full narrative, newest first — the foul only exists in the full feed.
    expect(find.text('Foul by Saka (Arsenal).'), findsOneWidget);
    expect(find.text('First Half begins.'), findsOneWidget);
    expect(find.text('Goal! Arsenal 1, Chelsea 0.'), findsOneWidget);

    await tester.tap(find.text('Box'));
    await tester.pump();
    expect(find.text('PLAYERS'), findsOneWidget); // CardLabel upper-cases
    expect(find.text('GOALKEEPERS'), findsOneWidget);
    expect(find.textContaining('Saka'), findsWidgets);
    expect(find.text('SV'), findsOneWidget);
  });
}
