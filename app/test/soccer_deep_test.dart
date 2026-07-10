// The deep soccer live detail (design LiveGame turns 9–10), driven through the
// real GameDetailPage:
//   - a summary shipping commentary/matchLeaders flips the tab set to
//     Now · Live pitch · Commentary · Lineups · Stats (Box/Leaders retire),
//   - Now carries the momentum chart, the commentary preview and match leaders,
//   - Live pitch renders the possession chip, last touch and restart log,
//   - Lineups renders the formation pitch (formationPlace-gated),
//   - Stats renders the shot map with the selected-shot detail,
//   - a summary WITHOUT the deep modules keeps the old grammar (regression).
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

const _liveStatus = {
  'phase': 'live', 'live': true, 'ended': false, 'period': 1,
  'periodLabel': '1st Half', 'espnName': 'STATUS_FIRST_HALF',
  'detail': "38'", 'clock': "38'",
};

Map<String, dynamic> _comp() => {
      'id': 'C1',
      'layout': 'headToHead',
      'scoreKind': 'numeric',
      'competitorKind': 'team',
      'status': _liveStatus,
      'periods': {'unit': 'half', 'regulation': 2, 'played': 1, 'lengthMin': 45},
      'competitors': [
        {'kind': 'team', 'id': '2869', 'displayName': 'Morocco', 'shortName': 'Morocco', 'abbreviation': 'MAR', 'homeAway': 'away', 'color': 'C8102E', 'score': {'display': '0', 'value': 0}},
        {'kind': 'team', 'id': '478', 'displayName': 'France', 'shortName': 'France', 'abbreviation': 'FRA', 'homeAway': 'home', 'color': '000080', 'score': {'display': '0', 'value': 0}},
      ],
    };

Map<String, dynamic> _scores() => {
      'sport': 'soccer',
      'league': 'fifa.world',
      'leagueId': '606',
      'leagueName': 'FIFA World Cup',
      'season': {'year': 2026, 'type': 1},
      'anyLive': true,
      'events': [
        {
          'id': 'E1',
          'name': 'Morocco at France',
          'shortName': 'MAR @ FRA',
          'start': '2026-07-09T20:00:00Z',
          'neutralSite': true,
          'broadcasts': <String>[],
          'notes': <String>[],
          'links': <String, dynamic>{},
          'competitions': [_comp()],
        },
      ],
    };

/// Eleven placed FRA starters (a plausible 4-2-3-1) + a couple of MAR rows.
List<Map<String, dynamic>> _lineups() => [
      {
        'side': 'home', 'abbr': 'FRA', 'formation': '4-2-3-1',
        'starters': [
          {'id': '1', 'name': 'M. Maignan', 'pos': 'G', 'jersey': '16', 'formationPlace': '1'},
          {'id': '2', 'name': 'J. Koundé', 'pos': 'RB', 'jersey': '5', 'formationPlace': '2'},
          {'id': '3', 'name': 'L. Digne', 'pos': 'LB', 'jersey': '3', 'formationPlace': '3'},
          {'id': '4', 'name': 'D. Upamecano', 'pos': 'CD-R', 'jersey': '4', 'formationPlace': '5'},
          {'id': '5', 'name': 'W. Saliba', 'pos': 'CD-L', 'jersey': '17', 'formationPlace': '6'},
          {'id': '6', 'name': 'A. Rabiot', 'pos': 'LM', 'jersey': '14', 'formationPlace': '4'},
          {'id': '7', 'name': 'M. Koné', 'pos': 'RM', 'jersey': '6', 'formationPlace': '8'},
          {'id': '8', 'name': 'M. Olise', 'pos': 'AM', 'jersey': '11', 'formationPlace': '10'},
          {'id': '9', 'name': 'D. Doué', 'pos': 'AM-L', 'jersey': '20', 'formationPlace': '11'},
          {'id': '10', 'name': 'O. Dembélé', 'pos': 'AM-R', 'jersey': '7', 'formationPlace': '7'},
          {'id': '11', 'name': 'K. Mbappé', 'pos': 'F', 'jersey': '10', 'formationPlace': '9'},
        ],
        'bench': [
          {'id': '12', 'name': 'H. Rayan', 'pos': 'F', 'jersey': '9'},
        ],
      },
      {
        'side': 'away', 'abbr': 'MAR', 'formation': '4-3-3',
        'starters': [
          {'id': '21', 'name': 'Y. Bounou', 'pos': 'G', 'jersey': '1', 'formationPlace': '1'},
          {'id': '22', 'name': 'A. Hakimi', 'pos': 'RB', 'jersey': '2', 'formationPlace': '2'},
          {'id': '23', 'name': 'N. Mazraoui', 'pos': 'LB', 'jersey': '3', 'formationPlace': '3'},
          {'id': '24', 'name': 'I. Diop', 'pos': 'CD-R', 'jersey': '5', 'formationPlace': '5'},
          {'id': '25', 'name': 'N. Aguerd', 'pos': 'CD-L', 'jersey': '6', 'formationPlace': '6'},
          {'id': '26', 'name': 'S. Amrabat', 'pos': 'DM', 'jersey': '4', 'formationPlace': '4'},
          {'id': '27', 'name': 'B. Diaz', 'pos': 'AM', 'jersey': '10', 'formationPlace': '10'},
        ],
        'bench': <Map<String, dynamic>>[],
      },
    ];

GameSummary _deepSummary() => GameSummary.fromJson({
      'eventId': 'E1', 'live': true,
      'teamStats': [
        {'label': 'Possession', 'away': '41.4', 'home': '58.6'},
        {'label': 'Shots on Goal', 'away': '1', 'home': '3'},
      ],
      'boxGroups': <dynamic>[],
      'scoringPlays': <dynamic>[],
      'lineups': _lineups(),
      'commentary': [
        {'period': 1, 'periodLabel': '1st Half', 'clock': "8'", 'text': 'Morocco keep possession at a steady pace.', 'type': 'Possession', 'scoring': false},
        {'period': 1, 'periodLabel': '1st Half', 'clock': "10'", 'text': 'France look to unlock the Morocco defence with patient build-up play.', 'type': 'Attempt Blocked', 'scoring': false, 'side': 'home', 'x': 80.2, 'y': 69.9},
        {'period': 1, 'periodLabel': '1st Half', 'clock': "25'", 'text': 'Penalty saved! Bounou guesses right and keeps out Mbappé.', 'type': 'Penalty - Saved', 'scoring': false, 'side': 'home', 'x': 88.5, 'y': 50},
      ],
      'matchLeaders': [
        {'name': 'totalShots', 'label': 'Total Shots', 'leaders': [
          {'side': 'home', 'teamAbbr': 'FRA', 'id': '10', 'name': 'O. Dembélé', 'jersey': '7', 'pos': 'F', 'value': 3, 'displayValue': '3'},
        ]},
        {'name': 'saves', 'label': 'Saves', 'leaders': [
          {'side': 'away', 'teamAbbr': 'MAR', 'id': '21', 'name': 'Y. Bounou', 'jersey': '1', 'pos': 'G', 'value': 3, 'displayValue': '3'},
        ]},
      ],
    });

MatchFeed _feed() => MatchFeed.fromJson({
      'count': 6,
      'plays': [
        {'id': 'p1', 'type': 'Kickoff', 'period': 1, 'clock': "1'", 'sec': 0, 'side': 'home', 'x': 50, 'y': 50},
        {'id': 'p2', 'type': 'Corner Awarded', 'period': 1, 'clock': "9'", 'sec': 540, 'side': 'home', 'x': 93, 'y': 80},
        {'id': 'p3', 'type': 'Shot Blocked', 'period': 1, 'clock': "10'", 'sec': 600, 'side': 'home', 'athleteId': '9', 'shortText': 'Désiré Doué Shot Blocked', 'text': 'Attempt blocked. Désiré Doué (France) right footed shot from outside the box is blocked.', 'x': 80.2, 'y': 69.9, 'x2': 86.3, 'y2': 63.4},
        {'id': 'p4', 'type': 'Penalty - Saved', 'period': 1, 'clock': "28'", 'sec': 1680, 'side': 'home', 'athleteId': '11', 'shortText': 'Kylian Mbappé Penalty - Saved', 'text': 'Penalty saved. Kylian Mbappé (France) right footed shot saved.', 'x': 88.5, 'y': 50, 'x2': 99.5, 'y2': 50.2},
        {'id': 'p5', 'type': 'Throw In', 'period': 1, 'clock': "36'", 'sec': 2160, 'side': 'away', 'x': 28.7, 'y': 0},
        {'id': 'p6', 'type': 'Pass', 'period': 1, 'clock': "37'", 'sec': 2220, 'side': 'away', 'athleteId': '21', 'shortText': 'Yassine Bounou Pass', 'x': 30, 'y': 40, 'x2': 55, 'y2': 60},
      ],
    });

Future<void> _pump(WidgetTester tester, GameSummary summary,
    {MatchFeed? feed}) async {
  tester.view.physicalSize = const Size(1200, 3600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final p = await prefs();
  final scores = ScoresResponse.fromJson(_scores());
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(p),
      leagueScoresProvider.overrideWith((ref, league) async => scores),
      summaryProvider.overrideWith((ref, key) async => summary),
      matchFeedProvider.overrideWith((ref, key) async => feed),
    ],
    child: MaterialApp(
      theme: buildV2Theme(),
      home: GameDetailPage(
          league: 'soccer/fifa.world', initialEvent: scores.events.first),
    ),
  ));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('deep summary flips the tab set + Now carries the 9a modules',
      (tester) async {
    await _pump(tester, _deepSummary(), feed: _feed());

    // The new grammar's chips…
    for (final chip in ['Now', 'Live pitch', 'Commentary', 'Lineups', 'Stats']) {
      expect(find.text(chip), findsOneWidget, reason: 'chip $chip');
    }
    // …and the retired ones.
    expect(find.text('Box'), findsNothing);
    expect(find.text('Leaders'), findsNothing);
    expect(find.text('Timeline'), findsNothing);

    // Now: momentum + commentary preview + match leaders.
    expect(find.text('MOMENTUM'), findsOneWidget);
    expect(find.text('COMMENTARY'), findsOneWidget);
    expect(find.text('Full commentary'), findsOneWidget);
    expect(find.text('MATCH LEADERS'), findsOneWidget);
    expect(find.text('O. Dembélé'), findsOneWidget);
    expect(find.text('TOTAL SHOTS'), findsOneWidget);
    // The generic cards the deep grammar retires from Now.
    expect(find.text('TOP PERFORMERS'), findsNothing);
  });

  testWidgets('Live pitch tab: possession chip, last touch, restart log',
      (tester) async {
    await _pump(tester, _deepSummary(), feed: _feed());
    await tester.tap(find.text('Live pitch'));
    await tester.pump();

    expect(find.text('LIVE PITCH'), findsOneWidget);
    // Possession chip: MAR has the ball (p6), open play.
    expect(find.text('MAR POSSESSION · OPEN PLAY'), findsOneWidget);
    expect(find.text('LAST TOUCH'), findsOneWidget);
    expect(find.text('RECENT STOPPAGES'), findsOneWidget);
    expect(find.textContaining('Throw-in'), findsOneWidget);
    expect(find.textContaining('Corner'), findsOneWidget);
  });

  testWidgets('Lineups tab: formation pitch renders the placed XI',
      (tester) async {
    await _pump(tester, _deepSummary(), feed: _feed());
    await tester.tap(find.text('Lineups'));
    await tester.pump();

    expect(find.text('FORMATIONS & LINEUPS'), findsOneWidget);
    expect(find.text('FRA · 4-2-3-1'), findsOneWidget);
    expect(find.text('Mbappé'), findsWidgets); // the placed striker dot
    expect(find.text('Maignan'), findsWidgets); // the GK dot
  });

  testWidgets('Stats tab: team stats + the shot map with per-shot detail',
      (tester) async {
    await _pump(tester, _deepSummary(), feed: _feed());
    await tester.tap(find.text('Stats'));
    await tester.pump();

    expect(find.text('TEAM STATS'), findsOneWidget);
    expect(find.text('SHOT MAP'), findsOneWidget);
    // Latest shot selected by default: Mbappé's saved penalty.
    expect(find.textContaining('K. Mbappé'), findsWidgets);
    expect(find.text('SAVED · 28\''), findsOneWidget);
    expect(find.text('Penalty'), findsOneWidget); // SITUATION cell
    expect(find.text('Right foot'), findsOneWidget); // SHOT TYPE cell
    expect(find.text('2 of 2'), findsOneWidget); // pager (2 shots)
    expect(find.text('DISTANCE'), findsOneWidget);
    // No xG anywhere — ESPN serves none.
    expect(find.text('XG'), findsNothing);
  });

  testWidgets('no deep modules → the old grammar stands (regression)',
      (tester) async {
    await _pump(
        tester,
        GameSummary.fromJson({
          'eventId': 'E1', 'live': true,
          'teamStats': [
            {'label': 'Possession', 'away': '41.4', 'home': '58.6'},
          ],
          'boxGroups': <dynamic>[], 'scoringPlays': <dynamic>[],
          'lineups': <dynamic>[],
          'timeline': [
            {'t': 13, 'clock': "13'", 'period': 1, 'kind': 'goal', 'side': 'home', 'teamAbbr': 'FRA', 'athlete': 'Mbappé', 'scoring': true},
          ],
        }));

    expect(find.text('Box'), findsOneWidget);
    expect(find.text('Timeline'), findsOneWidget);
    expect(find.text('Live pitch'), findsNothing);
    expect(find.text('Commentary'), findsNothing);
    expect(find.text('MOMENTUM'), findsNothing);
  });
}
