import 'package:flutter_test/flutter_test.dart';
import 'package:scores/src/data/normalize.dart';
import 'package:scores/src/data/profiles.dart';
import 'package:scores/src/models.dart';
import 'golden_util.dart';

// Cheap basketball win probability (schema/espn-guide/scoreboard.md — the
// scoreboard's situation.lastPlay.probability, basketball-only ~14%). No live
// basketball game was capturable at build time (NBA offseason 2026-07), so this
// guide-shaped input pins the Dart normalizer in lock-step with the JS oracle's
// assertion in worker/test/units.test.mjs.
void main() {
  late Registry reg;
  setUpAll(() => reg = loadTestRegistry());

  Map<String, dynamic> scoreboard(Map<String, dynamic> situation) => {
        'leagues': [
          {'id': '46', 'slug': 'nba', 'name': '', 'season': {}}
        ],
        'events': [
          {
            'id': '1',
            'date': '2026-06-01T00:00Z',
            'name': 'A v B',
            'shortName': 'A v B',
            'competitions': [
              {
                'id': '1',
                'status': {
                  'type': {
                    'name': 'STATUS_IN_PROGRESS',
                    'state': 'in',
                    'completed': false
                  },
                  'period': 3,
                  'displayClock': '5:00'
                },
                'competitors': [
                  {
                    'id': '1',
                    'homeAway': 'home',
                    'team': {
                      'id': '1',
                      'abbreviation': 'OKC',
                      'displayName': 'Thunder',
                      'color': '007ac1'
                    },
                    'score': '78'
                  },
                  {
                    'id': '2',
                    'homeAway': 'away',
                    'team': {
                      'id': '2',
                      'abbreviation': 'IND',
                      'displayName': 'Pacers',
                      'color': '002d62'
                    },
                    'score': '74'
                  },
                ],
                'situation': situation,
              }
            ],
          }
        ],
      };

  Map situationMap(Map<String, dynamic> situation) => (normalizeScoreboard(
              reg, 'basketball/nba', scoreboard(situation))['events'] as List)[0]
          ['competitions'][0]['situation'] as Map? ??
      const {};

  test('homeWinPct = round(homeWinPercentage * 100)', () {
    final s = situationMap({
      'lastPlay': {
        'text': 'Jump shot',
        'probability': {
          'homeWinPercentage': 0.696,
          'awayWinPercentage': 0.304,
          'tiePercentage': 0
        }
      }
    });
    expect(s['homeWinPct'], 70);
    expect(s['lastPlay'], 'Jump shot');
  });

  test('no lastPlay.probability → homeWinPct omitted', () {
    final s = situationMap({
      'lastPlay': {'text': 'Jump shot'}
    });
    expect(s.containsKey('homeWinPct'), isFalse);
  });

  test('Situation model parses homeWinPct', () {
    final sit = Situation.fromJson({'homeWinPct': 62});
    expect(sit.homeWinPct, 62);
    expect(Situation.fromJson({}).homeWinPct, isNull);
  });
}
