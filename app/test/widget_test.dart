import 'package:flutter_test/flutter_test.dart';
import 'package:scores/src/models.dart';

void main() {
  test('parses a scores response, detects overtime and winner', () {
    final json = {
      'sport': 'basketball',
      'league': 'nba',
      'leagueId': '46',
      'leagueName': 'NBA',
      'anyLive': false,
      'updated': '2026-06-13T00:00:00Z',
      'season': {'year': 2026, 'type': 2},
      'events': [
        {
          'id': '1',
          'name': 'Team A at Team B',
          'shortName': 'A @ B',
          'start': '2026-06-13T00:00:00Z',
          'competitions': [
            {
              'id': '1',
              'layout': 'headToHead',
              'scoreKind': 'numeric',
              'competitorKind': 'team',
              'status': {
                'phase': 'final',
                'ended': true,
                'live': false,
                'period': 5,
                'periodLabel': 'Final/OT',
                'espnName': 'STATUS_FINAL',
                'detail': 'Final/OT',
              },
              'periods': {'unit': 'quarter', 'regulation': 4, 'played': 5, 'isOvertime': true},
              'decision': 'overtime',
              'competitors': [
                {'kind': 'team', 'id': '10', 'displayName': 'Team A', 'homeAway': 'home', 'winner': true, 'score': {'display': '120', 'value': 120}},
                {'kind': 'team', 'id': '20', 'displayName': 'Team B', 'homeAway': 'away', 'winner': false, 'score': {'display': '118', 'value': 118}},
              ],
            }
          ],
        }
      ],
    };

    final r = ScoresResponse.fromJson(json);
    expect(r.leagueId, '46');
    expect(r.anyLive, isFalse);
    expect(r.events, hasLength(1));

    final c = r.events.first.main!;
    expect(c.periods.isOvertime, isTrue);
    expect(c.decision, 'overtime');
    expect(c.home!.score!.value, 120);
    expect(c.home!.isWinner, isTrue);
    expect(c.away!.isWinner, isFalse);
  });

  test('field sport parses with many competitors and to-par scores', () {
    final json = {
      'sport': 'golf',
      'league': 'pga',
      'leagueId': '1106',
      'leagueName': 'PGA Tour',
      'anyLive': true,
      'events': [
        {
          'id': 't1',
          'name': 'Open',
          'shortName': 'Open',
          'competitions': [
            {
              'id': 't1',
              'layout': 'field',
              'scoreKind': 'toPar',
              'competitorKind': 'athlete',
              'status': {'phase': 'live', 'live': true, 'ended': false, 'period': 3, 'periodLabel': 'Round 3'},
              'periods': {'unit': 'hole_rounds', 'regulation': 4, 'played': 3, 'isOvertime': false},
              'competitors': [
                {'kind': 'athlete', 'id': '1', 'displayName': 'Leader', 'order': 1, 'score': {'display': '-11', 'toPar': -11}},
                {'kind': 'athlete', 'id': '2', 'displayName': 'Chaser', 'order': 2, 'score': {'display': '-9', 'toPar': -9}},
              ],
            }
          ],
        }
      ],
    };
    final c = ScoresResponse.fromJson(json).events.first.main!;
    expect(c.isField, isTrue);
    expect(c.competitors.first.order, 1);
    expect(c.competitors.first.score!.toPar, -11);
  });
}
