import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scores/src/models.dart';
import 'package:scores/src/theme.dart';
import 'package:scores/src/ui/league_card.dart';
import 'package:scores/src/ui/widgets.dart';

// The playoff-series footer strip on a league row (§Part I.6): derived GAME N +
// can-clinch, both computed off the cheap series win counts (no ESPN field).

Map<String, dynamic> _series(
        {required int total, required int okc, required int cle}) =>
    {
      'sport': 'basketball',
      'league': 'nba',
      'leagueId': '46',
      'leagueName': 'NBA',
      'events': [
        {
          'id': 'e1',
          'name': 'Cavaliers at Thunder',
          'shortName': 'CLE @ OKC',
          'start': '2026-06-01T00:00Z',
          'competitions': [
            {
              'id': 'e1',
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
                'detail': '',
              },
              'periods': {
                'unit': 'quarter',
                'regulation': 4,
                'played': 0,
                'isOvertime': false,
              },
              'competitors': [
                {
                  'kind': 'team',
                  'id': 'okc',
                  'displayName': 'Thunder',
                  'abbreviation': 'OKC',
                  'homeAway': 'home',
                  'color': '007ac1',
                },
                {
                  'kind': 'team',
                  'id': 'cle',
                  'displayName': 'Cavaliers',
                  'abbreviation': 'CLE',
                  'homeAway': 'away',
                  'color': '860038',
                },
              ],
              'meta': {
                'round': 'West Finals',
                'seriesSummary': 'OKC leads $okc-$cle',
                'series': {
                  'type': 'playoff',
                  'total': total,
                  'completed': false,
                  'competitors': [
                    {'id': 'okc', 'wins': okc},
                    {'id': 'cle', 'wins': cle},
                  ],
                },
              },
            },
          ],
        }
      ],
    };

  Widget _wrap(Map<String, dynamic> json) => MaterialApp(
        theme: buildV2Theme(),
        home: Scaffold(
          body: LeagueEventsCard(
            league: 'basketball/nba',
            scores: ScoresResponse.fromJson(json),
          ),
        ),
      );

void main() {
  testWidgets('best-of-7 at 3-2: GAME 6 + pips + "can clinch" caption',
      (tester) async {
    await tester.pumpWidget(_wrap(_series(total: 7, okc: 3, cle: 2)));
    await tester.pump();

    expect(find.text('GAME 6'), findsOneWidget); // sum(wins)+1 = 6
    expect(find.byType(SeriesPips), findsOneWidget);
    // leader one win from majority (4) → clinch appended to the lead phrase.
    expect(find.textContaining('OKC leads 3-2'), findsOneWidget);
    expect(find.textContaining('can clinch'), findsOneWidget);
  });

  testWidgets('best-of-7 at 2-1: GAME 4, no clinch yet', (tester) async {
    await tester.pumpWidget(_wrap(_series(total: 7, okc: 2, cle: 1)));
    await tester.pump();

    expect(find.text('GAME 4'), findsOneWidget); // sum(wins)+1 = 4
    expect(find.byType(SeriesPips), findsOneWidget);
    expect(find.textContaining('can clinch'), findsNothing);
  });

  test('SeriesInfo derives game number + clinch off win counts', () {
    SeriesInfo s(int total, int a, int b) => SeriesInfo.fromJson({
          'type': 'playoff',
          'total': total,
          'completed': false,
          'competitors': [
            {'id': 'a', 'wins': a},
            {'id': 'b', 'wins': b},
          ],
        });
    expect(s(7, 3, 2).gameNumber, 6);
    expect(s(7, 3, 2).canClinch, isTrue);
    expect(s(7, 2, 1).canClinch, isFalse);
    // completed series: no forward-looking game number, never "can clinch".
    final done = SeriesInfo.fromJson({
      'type': 'playoff',
      'total': 7,
      'completed': true,
      'competitors': [
        {'id': 'a', 'wins': 4},
        {'id': 'b', 'wins': 2},
      ],
    });
    expect(done.gameNumber, isNull);
    expect(done.canClinch, isFalse);
  });
}
