import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scores/src/models.dart';
import 'package:scores/src/providers.dart';
import 'package:scores/src/theme.dart';
import 'package:scores/src/ui/game_detail_page.dart';

// UI parity for the broadcast badge + pre-game odds block (spec §3.4 / §2.6 /
// Part I §6). A scheduled competition carrying an inline scoreboard line + a
// broadcast label must render the PRE-GAME card (spread/total + per-team
// moneyline) and surface the TV label in the hero header — data-driven, hidden
// cleanly when absent.

Map<String, dynamic> _scheduledMlb({Map<String, dynamic>? odds, String? broadcast}) => {
      'sport': 'baseball',
      'league': 'baseball/mlb',
      'leagueId': '10',
      'leagueName': 'MLB',
      'season': {'year': 2026},
      'anyLive': false,
      'events': [
        {
          'id': '99',
          'name': 'Blue Jays at Giants',
          'shortName': 'TOR @ SF',
          'start': '2026-07-20T23:00:00Z',
          'neutralSite': false,
          'venue': {'name': 'Oracle Park', 'city': 'San Francisco'},
          'broadcasts': const <String>[],
          'notes': const <String>[],
          'links': const <String, dynamic>{},
          'competitions': [
            {
              'id': '99',
              'layout': 'headToHead',
              'scoreKind': 'numeric',
              'competitorKind': 'team',
              'status': {
                'phase': 'scheduled',
                'live': false,
                'ended': false,
                'period': 0,
                'periodLabel': '',
                'espnName': 'STATUS_SCHEDULED',
                'detail': '7:00 PM',
                'shortDetail': '7:00 PM',
              },
              'periods': {'unit': 'inning', 'regulation': 9, 'played': 0, 'isOvertime': false},
              'decision': null,
              'competitors': [
                {'kind': 'team', 'id': '10', 'displayName': 'Blue Jays', 'shortName': 'Blue Jays', 'abbreviation': 'TOR', 'homeAway': 'away'},
                {'kind': 'team', 'id': '20', 'displayName': 'Giants', 'shortName': 'Giants', 'abbreviation': 'SF', 'homeAway': 'home'},
              ],
              if (broadcast != null) 'broadcast': broadcast,
              if (odds != null) 'odds': odds,
            },
          ],
        },
      ],
    };

Future<void> _pumpDetail(WidgetTester tester, ScoresResponse scores) async {
  SharedPreferences.setMockInitialValues({});
  final p = await SharedPreferences.getInstance();
  final event = scores.events.first;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(p),
      leagueScoresProvider.overrideWith((ref, key) async => scores),
      summaryProvider.overrideWith((ref, key) async =>
          GameSummary.fromJson(const <String, dynamic>{})),
      // A scheduled game with no inline odds would hit this; return null (the
      // capability-gated best-effort path). Present-odds cases never reach it.
      oddsProvider.overrideWith((ref, key) async => null),
    ],
    child: MaterialApp(
      theme: buildV2Theme(),
      home: GameDetailPage(league: 'baseball/mlb', initialEvent: event),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('pre-game odds card renders spread, total, and moneyline chips',
      (tester) async {
    final scores = ScoresResponse.fromJson(_scheduledMlb(
      broadcast: 'MLB.TV/TBS',
      odds: {
        'details': 'SF -122',
        'spread': 1.5,
        'overUnder': 7,
        'homeMoneyline': 101,
        'awayMoneyline': -122,
        'provider': 'DraftKings',
      },
    ));
    await _pumpDetail(tester, scores);

    // The PRE-GAME block, its favorite+line summary, the total, and the book.
    expect(find.text('PRE-GAME'), findsOneWidget);
    expect(find.text('SF -122'), findsOneWidget);
    expect(find.text('7'), findsWidgets); // total value
    expect(find.text('via DraftKings'), findsOneWidget);
    // Per-team moneyline chips (core-only value made visible on this line).
    expect(find.text('+101'), findsOneWidget); // home
    expect(find.text('-122'), findsOneWidget); // away
    // Broadcast label surfaced in the hero header caption.
    expect(find.textContaining('MLB.TV/TBS'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('no odds served → no pre-game card, and the read stays clean',
      (tester) async {
    final scores = ScoresResponse.fromJson(_scheduledMlb(broadcast: 'ESPN'));
    await _pumpDetail(tester, scores);

    expect(find.text('PRE-GAME'), findsNothing);
    expect(find.text('via DraftKings'), findsNothing);
    // Broadcast still shows even without odds.
    expect(find.textContaining('ESPN'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
  });
}
