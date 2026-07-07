import 'package:flutter_test/flutter_test.dart';
import 'package:scores/src/data/profiles.dart';
import 'package:scores/src/data/normalize.dart';
import 'golden_util.dart';

// Phase 2 parity: the Dart scoreboard normalizer (lib/src/data/normalize.dart)
// must match the JS output (worker/src/normalize.js) for every committed fixture.
// The one non-deterministic field (`updated`) is blanked on both sides.
void main() {
  late Registry reg;
  setUpAll(() => reg = loadTestRegistry());

  final entries = goldenIndex().where((e) => e['endpoint'] == 'scores');

  for (final e in entries) {
    final file = e['file'] as String;
    final key = e['key'] as String;
    test('scores parity: $key', () {
      final g = readGolden(file);
      final args = g['args'] as Map<String, dynamic>;
      final got = normalizeScoreboard(
          reg, key, args['sb'] as Map, (args['extras'] as Map?)?.cast<String, dynamic>() ?? const {});
      got['updated'] = null; // JS golden already blanked
      final want = Map<String, dynamic>.from(g['output'] as Map);
      want['updated'] = null;
      expect(canonicalJson(got), canonicalJson(want));
    });
  }
}
