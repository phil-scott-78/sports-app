import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:scores/src/data/normalize.dart';
import 'package:scores/src/data/summary.dart';
import 'package:scores/src/data/profiles.dart';
import 'golden_util.dart';

// Baseball turn-8 data layer, in lock-step with the JS oracle's assertions in
// worker/test/units.test.mjs:
//  - the CHEAP situation's lastPlay reads the play's own text (never the coarse
//    type.alternativeText "Now at bat" / lingering "Strikeout"), and onDeck is
//    the first dueUp[] batter who isn't already at the plate;
//  - the RICH summary derives "what really was the last play" by walking back
//    past ESPN's start-batterpitcher bookends, and the live at-bat carries the
//    pitcher's game pitch count, runner names, and per-pitch type/zone coords.
// No committed fixture holds a LIVE baseball situation/summary (all captures are
// final games; only the gp capture has coords) — these guide-shaped inputs pin
// the derivation on both sides.
void main() {
  late Registry reg;
  setUpAll(() => reg = loadTestRegistry());

  Map<String, dynamic> scoreboard(String lastPlayText) => {
        'leagues': [
          {'id': '10', 'slug': 'mlb', 'name': '', 'season': {}}
        ],
        'events': [
          {
            'id': '1',
            'date': '2026-07-09T00:00Z',
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
                  'period': 7
                },
                'competitors': [
                  {
                    'id': '15',
                    'homeAway': 'home',
                    'team': {
                      'id': '15',
                      'abbreviation': 'ATL',
                      'displayName': 'Braves',
                      'color': 'ce1141'
                    },
                    'score': '3'
                  },
                  {
                    'id': '23',
                    'homeAway': 'away',
                    'team': {
                      'id': '23',
                      'abbreviation': 'PIT',
                      'displayName': 'Pirates',
                      'color': 'fdb827'
                    },
                    'score': '1'
                  },
                ],
                'situation': {
                  'balls': 1,
                  'strikes': 2,
                  'outs': 1,
                  'batter': {
                    'athlete': {'id': 'b1', 'shortName': 'J. Mangum'}
                  },
                  'pitcher': {
                    'athlete': {'id': 'p1', 'shortName': 'B. Elder'},
                    'summary': '1.2 IP, 2 H, 0 ER'
                  },
                  'dueUp': [
                    {
                      'athlete': {'id': 'b1', 'shortName': 'J. Mangum'}
                    },
                    {
                      'athlete': {'id': 'b2', 'shortName': 'B. Lowe'},
                      'summary': '1-3, K'
                    },
                  ],
                  'lastPlay': {
                    'text': lastPlayText,
                    'type': {
                      'id': '58',
                      'text': 'Start Batter/Pitcher',
                      'type': 'start-batterpitcher',
                      'alternativeText': 'Now at bat'
                    },
                  },
                },
              }
            ],
          }
        ],
      };

  test('cheap situation: lastPlay text preferred, onDeck skips current batter',
      () {
    final sit = (normalizeScoreboard(
            reg, 'baseball/mlb', scoreboard('Jose Soriano pitches to Joc Pederson'))['events']
        as List)[0]['competitions'][0]['situation'] as Map;
    expect(sit['lastPlay'], 'Jose Soriano pitches to Joc Pederson');
    expect(sit['onDeck'], 'B. Lowe');
    // canonical dueUp: the full list in ESPN order, day lines when shipped —
    // byte-parity with the JS oracle's units.test.mjs assertion.
    expect(sit['dueUp'], [
      {'name': 'J. Mangum'},
      {'name': 'B. Lowe', 'line': '1-3, K'},
    ]);
  });

  test('cheap situation: alternativeText only a fallback for empty text', () {
    final sit = (normalizeScoreboard(reg, 'baseball/mlb', scoreboard(''))['events']
        as List)[0]['competitions'][0]['situation'] as Map;
    expect(sit['lastPlay'], 'Now at bat');
  });

  Map<String, dynamic> pitchRow(int n, String atBatId, String text,
          [Map<String, dynamic> extra = const {}]) =>
      {
        'summaryType': 'P',
        'atBatId': atBatId,
        'atBatPitchNumber': n,
        'text': text,
        'participants': [
          {
            'athlete': {'id': 'p1'},
            'type': 'pitcher'
          },
          {
            'athlete': {'id': 'b1'},
            'type': 'batter'
          },
        ],
        'team': {'id': '15'},
        ...extra,
      };

  final finished = [
    {
      'summaryType': 'A',
      'atBatId': 'ab1',
      'text': 'Elder pitches to Neto',
      'team': {'id': '23'},
      'participants': [
        {
          'athlete': {'id': 'p1'},
          'type': 'pitcher'
        },
        {
          'athlete': {'id': 'b1'},
          'type': 'batter'
        },
      ],
    },
    pitchRow(1, 'ab1', 'Pitch 1 : Strike 1 Looking', {
      'pitchType': {'text': 'Curve'},
      'pitchVelocity': 83,
      'pitchCoordinate': {'x': 118, 'y': 181},
    }),
    pitchRow(2, 'ab1', 'Pitch 2 : Ball In Play', {
      'pitchType': {'text': 'Cutter'},
      'pitchVelocity': 90,
    }),
    {
      'summaryType': 'N',
      'atBatId': 'ab1',
      'text': 'Neto doubled to left.',
      'team': {'id': '23'},
      'outs': 1,
    },
    {
      'summaryType': 'A',
      'atBatId': 'ab2',
      'text': 'Elder pitches to Mangum',
      'team': {'id': '23'},
      'participants': [
        {
          'athlete': {'id': 'p1'},
          'type': 'pitcher'
        },
        {
          'athlete': {'id': 'b1'},
          'type': 'batter'
        },
      ],
    },
  ];

  // Round-trip through JSON so lists/maps are dynamically typed exactly as a
  // decoded network payload is (the normalizer's firstWhere/orElse patterns
  // assume List<dynamic>).
  Map<String, dynamic> raw(List plays) => jsonDecode(jsonEncode(_raw(plays)));

  test('summary lastPlay: walks back past the bookend to the real result', () {
    final s = normalizeSummary(reg, 'baseball/mlb', raw(finished));
    expect(s['lastPlay'], {'kind': 'play', 'text': 'Neto doubled to left.'});
  });

  test('summary lastPlay: trailing pitch → kind pitch, live at-bat extras', () {
    final live = [
      ...finished,
      pitchRow(1, 'ab2', 'Pitch 1 : Ball 1', {
        'pitchType': {'text': 'Slider'},
        'pitchVelocity': 85,
        'pitchCoordinate': {'x': 60, 'y': 260},
        'resultCount': {'balls': 1, 'strikes': 0},
        'onSecond': {
          'athlete': {'id': 'r2'}
        },
      }),
    ];
    final s = normalizeSummary(reg, 'baseball/mlb', raw(live));
    expect(s['lastPlay'],
        {'kind': 'pitch', 'text': 'Ball 1', 'type': 'Slider', 'velo': 85});
    final atBats = (s['atBats'] as List).cast<Map>();
    final lv = atBats.firstWhere((a) => a['live'] == true);
    expect(lv['pitchCount'], 3,
        reason: "pitcher's GAME pitch count spans at-bats");
    expect(lv['second'], 'T. Callihan');
    expect(lv.containsKey('first'), isFalse);
    expect(lv.containsKey('third'), isFalse);
    final zp = (lv['pitches'] as List).first as Map;
    expect(zp['type'], 'Slider');
    expect(zp['x'], 60);
    expect(zp['y'], 260);
    final fin = atBats.firstWhere((a) => a['live'] != true);
    expect((fin['pitches'] as List).first['x'], 118);
    expect(fin.containsKey('pitchCount'), isFalse);
  });

  test('live at-bat: runner names ride the header before the first pitch', () {
    // A batter just walked → the fresh at-bat is ONLY its "X pitches to Y"
    // header for a while, and that header carries the on-base state.
    final headerOnly = [
      ...finished.sublist(0, 4),
      {
        'summaryType': 'A',
        'atBatId': 'ab2',
        'text': 'Elder pitches to Mangum',
        'team': {'id': '23'},
        'onFirst': {
          'athlete': {'id': 'r2'}
        },
        'participants': [
          {
            'athlete': {'id': 'p1'},
            'type': 'pitcher'
          },
          {
            'athlete': {'id': 'b1'},
            'type': 'batter'
          },
        ],
      },
    ];
    final s = normalizeSummary(reg, 'baseball/mlb', raw(headerOnly));
    final lv = (s['atBats'] as List)
        .cast<Map>()
        .firstWhere((a) => a['live'] == true);
    expect(lv['first'], 'T. Callihan');
    expect((lv['pitches'] as List), isEmpty);
  });
}

Map<String, dynamic> _raw(List plays) => {
        'header': {
          'id': '9',
          'competitions': [
            {
              'id': '9',
              'status': {
                'type': {'state': 'in'}
              },
              'competitors': [
                {
                  'id': '15',
                  'homeAway': 'home',
                  'team': {'id': '15', 'abbreviation': 'ATL'}
                },
                {
                  'id': '23',
                  'homeAway': 'away',
                  'team': {'id': '23', 'abbreviation': 'PIT'}
                },
              ],
            }
          ],
        },
        'boxscore': {
          'players': [
            {
              'team': {'id': '23'},
              'statistics': [
                {
                  'name': 'batting',
                  'labels': [],
                  'athletes': [
                    {
                      'athlete': {'id': 'b1', 'shortName': 'J. Mangum'},
                      'stats': []
                    },
                    {
                      'athlete': {'id': 'r2', 'shortName': 'T. Callihan'},
                      'stats': []
                    },
                  ],
                }
              ],
            },
            {
              'team': {'id': '15'},
              'statistics': [
                {
                  'name': 'pitching',
                  'labels': [],
                  'athletes': [
                    {
                      'athlete': {'id': 'p1', 'shortName': 'B. Elder'},
                      'stats': []
                    },
                  ],
                }
              ],
            },
          ],
        },
        'plays': plays,
      };
