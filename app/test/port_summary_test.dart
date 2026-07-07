import 'package:flutter_test/flutter_test.dart';
import 'package:scores/src/data/profiles.dart';
import 'package:scores/src/data/summary.dart';
import 'golden_util.dart';

// Phase 2 parity: the Dart summary normalizer (lib/src/data/summary.dart) must
// match the JS output (worker/src/summary.js) for every committed fixture.
void main() {
  late Registry reg;
  setUpAll(() => reg = loadTestRegistry());

  for (final e in goldenIndex().where((e) => e['endpoint'] == 'summary')) {
    final key = e['key'] as String;
    final eventId = e['eventId'] as String;
    test('summary parity: $key/$eventId', () {
      final g = readGolden(e['file'] as String);
      final args = g['args'] as Map<String, dynamic>;
      final got = normalizeSummary(reg, key, args['raw'] as Map);
      expect(canonicalJson(got), canonicalJson(g['output']));
    });
  }
}
