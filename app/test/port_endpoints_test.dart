import 'package:flutter_test/flutter_test.dart';
import 'package:scores/src/data/profiles.dart';
import 'package:scores/src/data/standings.dart';
import 'package:scores/src/data/rankings.dart';
import 'package:scores/src/data/scorecard.dart';
import 'package:scores/src/data/team.dart';
import 'golden_util.dart';

// Phase 2 parity for the smaller normalizers: standings / rankings / scorecard /
// teams. Each must match the JS output for every committed fixture.
void main() {
  late Registry reg;
  setUpAll(() => reg = loadTestRegistry());

  for (final e in goldenIndex().where((e) => e['endpoint'] == 'standings')) {
    test('standings parity: ${e['key']}', () {
      final g = readGolden(e['file'] as String);
      final got = normalizeStandings((g['args'] as Map)['raw']);
      expect(canonicalJson(got), canonicalJson(g['output']));
    });
  }

  for (final e in goldenIndex().where((e) => e['endpoint'] == 'rankings')) {
    test('rankings parity: ${e['key']}', () {
      final g = readGolden(e['file'] as String);
      final got = normalizeRankings((g['args'] as Map)['raw']);
      expect(canonicalJson(got), canonicalJson(g['output']));
    });
  }

  for (final e in goldenIndex().where((e) => e['endpoint'] == 'scorecard')) {
    test('scorecard parity: ${e['key']}/${e['eventId']}/${e['playerId']}', () {
      final g = readGolden(e['file'] as String);
      final a = g['args'] as Map;
      final got = normalizeGolfScorecard(a['key'] as String, a['eventId'], a['playerId'], a['raw']);
      expect(canonicalJson(got), canonicalJson(g['output']));
    });
  }

  for (final e in goldenIndex().where((e) => e['endpoint'] == 'teams')) {
    test('teams parity: ${e['key']}', () {
      final g = readGolden(e['file'] as String);
      final a = g['args'] as Map;
      final got = normalizeTeams(reg, a['key'] as String, a['raw']);
      expect(canonicalJson(got), canonicalJson(g['output']));
    });
  }
}
