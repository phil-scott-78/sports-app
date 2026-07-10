import 'package:flutter_test/flutter_test.dart';
import 'package:scores/src/data/summary.dart';
import 'golden_util.dart';

// Parity for the detail-open CORE enrichments (lib/src/data/summary.dart:
// buildCoreSituation + winProbabilityFromPredictor) against the JS oracle
// (worker/src/summary.js). Football/NBA/NHL are OFFSEASON as of 2026-07, so no
// live gridiron/basketball core situation is capturable — there is no fabricated
// golden. Instead these assert the SAME guide-shaped expectations the JS unit
// suite pins (worker/test/units.test.mjs), which mirror schema/espn-guide/
// core-situation.md + core-predictor.md exactly. If a real capture is ever added
// (gen-goldens emits endpoints 'situationCore'/'winprob'), the golden loop below
// verifies byte parity automatically.
void main() {
  setUpAll(loadTestRegistry);

  // ---- captured goldens, when any exist (real ESPN shapes) -------------------
  for (final e in goldenIndex().where((e) => e['endpoint'] == 'situationCore')) {
    final g = readGolden(e['file'] as String);
    final args = g['args'] as Map<String, dynamic>;
    test('core-situation parity: ${e['key']}/${e['eventId']}', () {
      final got = buildCoreSituation(args['raw'], args['lastPlayText'] as String?);
      expect(canonicalJson(got), canonicalJson(g['output']));
    });
  }
  for (final e in goldenIndex().where((e) => e['endpoint'] == 'winprob')) {
    final g = readGolden(e['file'] as String);
    final args = g['args'] as Map<String, dynamic>;
    test('predictor win-prob parity: ${e['key']}/${e['eventId']}', () {
      final got = winProbabilityFromPredictor(args['raw']);
      expect(canonicalJson(got), canonicalJson(g['output']));
    });
  }

  // ---- guide-shaped parity (no live capture) ---------------------------------
  group('buildCoreSituation (guide shapes)', () {
    test('football: down/distance/yardLine/timeouts, no downDistanceText', () {
      final c = buildCoreSituation({
        '\$ref': 'http://sports.core.api.espn.com/.../situation?lang=en',
        'down': 2, 'distance': 10, 'yardLine': 45, 'isRedZone': false,
        'homeTimeouts': 3, 'awayTimeouts': 2,
        'lastPlay': {'\$ref': 'http://sports.core.api.espn.com/.../plays/401'},
      }, 'Pass complete for a first down')!;
      expect(c['down'], 2);
      expect(c['distance'], 10);
      expect(c['yardLine'], 45);
      expect(c['isRedZone'], false);
      expect(c['homeTimeouts'], 3);
      expect(c['awayTimeouts'], 2);
      expect(c['lastPlay'], 'Pass complete for a first down');
      expect(c.containsKey('downDistanceText'), false);
      expect(c.containsKey('possession'), false);
    });

    test('basketball: bonusState + object timeouts → remaining number', () {
      final c = buildCoreSituation({
        'homeFouls': {'bonusState': 'DOUBLE', 'teamFouls': 19, 'teamFoulsCurrent': 5, 'foulsToGive': 0},
        'awayFouls': {'bonusState': 'NONE', 'teamFouls': 3, 'teamFoulsCurrent': 3, 'foulsToGive': 2},
        'homeTimeouts': {'timeoutsCurrent': 0, 'timeoutsRemainingCurrent': 2},
        'awayTimeouts': {'timeoutsCurrent': 0, 'timeoutsRemainingCurrent': 4},
      })!;
      expect(c['homeBonus'], 'DOUBLE');
      expect(c['awayBonus'], 'NONE');
      expect(c['homeTimeouts'], 2);
      expect(c['awayTimeouts'], 4);
      expect(c.containsKey('down'), false);
    });

    test('hockey: powerPlay/emptyNet booleans', () {
      final c = buildCoreSituation({'powerPlay': true, 'emptyNet': false})!;
      expect(c['powerPlay'], true);
      expect(c['emptyNet'], false);
    });

    test('baseball: count + baserunners', () {
      final c = buildCoreSituation({
        'balls': 2, 'strikes': 1, 'outs': 0,
        'onFirst': true, 'onSecond': false, 'onThird': false,
      })!;
      expect(c['balls'], 2);
      expect(c['strikes'], 1);
      expect(c['outs'], 0);
      expect(c['onFirst'], true);
    });

    test('degenerate inputs → null', () {
      expect(buildCoreSituation(null), isNull);
      expect(buildCoreSituation(<String, dynamic>{}), isNull);
    });
  });

  group('winProbabilityFromPredictor (guide shapes)', () {
    test('home gameProjection → rounded, away derived to sum 100', () {
      final wp = winProbabilityFromPredictor({
        'homeTeam': {
          'statistics': [
            {'name': 'gameProjection', 'displayName': 'WIN PROB', 'value': 36.47643417, 'displayValue': '36.5'},
            {'name': 'teamChanceLoss', 'value': 63.5, 'displayValue': '63.5'},
          ]
        },
        'awayTeam': {
          'statistics': [
            {'name': 'gameProjection', 'value': 63.523565829999995, 'displayValue': '63.5'},
          ]
        },
      })!;
      expect(wp['home'], 36);
      expect(wp['away'], 64);
    });

    test('away-only → home derived', () {
      final wp = winProbabilityFromPredictor({
        'awayTeam': {
          'statistics': [
            {'name': 'gameProjection', 'value': 70},
          ]
        },
      });
      expect(wp, {'home': 30, 'away': 70});
    });

    test('no data → null', () {
      expect(winProbabilityFromPredictor(null), isNull);
      expect(winProbabilityFromPredictor(<String, dynamic>{}), isNull);
    });

    // teamPredWinpct fallback — VERIFIED live 2026-07-09 (WNBA): the in-game
    // predictor carries NO gameProjection, only teamPredWinpct (+ matchupQuality/
    // teamPredPtDiff). gameProjection still wins when both are present.
    test('teamPredWinpct fallback when gameProjection absent', () {
      final wp = winProbabilityFromPredictor({
        'homeTeam': {
          'statistics': [
            {'name': 'matchupQuality', 'value': 32.3974},
            {'name': 'teamPredWinpct', 'value': 83.27, 'displayValue': '83.3'},
          ]
        },
        'awayTeam': {
          'statistics': [
            {'name': 'teamPredWinpct', 'value': 16.73, 'displayValue': '16.7'},
          ]
        },
      });
      expect(wp, {'home': 83, 'away': 17});
    });

    test('gameProjection preferred over teamPredWinpct', () {
      final wp = winProbabilityFromPredictor({
        'homeTeam': {
          'statistics': [
            {'name': 'teamPredWinpct', 'value': 90},
            {'name': 'gameProjection', 'value': 40},
          ]
        },
      });
      expect(wp!['home'], 40);
    });
  });
}
