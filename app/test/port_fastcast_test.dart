import 'package:flutter_test/flutter_test.dart';
import 'package:scores/src/data/fastcast.dart';
import 'package:scores/src/data/profiles.dart';
import 'golden_util.dart';

// FastCast pure-layer parity (fastcast-plan.md Phase 1): replay each captured
// push stream (checkpoint + patch frames) through the Dart appliers and slate
// normalizer, and match the JS oracle's goldens byte-for-byte — the final doc,
// the per-frame error lists (empty on the live captures), and, for event-*
// topics, the staged overlay after the checkpoint and after every frame.
void main() {
  late Registry reg;
  setUpAll(() => reg = loadTestRegistry());

  for (final e in goldenIndex().where((e) => e['endpoint'] == 'fastcast')) {
    test('fastcast parity: ${e['key']}', () {
      final g = readGolden(e['file'] as String);
      final a = g['args'] as Map;
      final out = g['output'] as Map;
      final topic = a['topic'] as String;
      final isGp = topic.startsWith('gp-');
      final key = a['key'] as String?;

      dynamic doc = a['checkpoint'];
      final errors = <String>[];
      final slates = <dynamic>[
        if (key != null) normalizeFastcastSlate(reg, key, doc),
      ];
      for (final frame in a['frames'] as List) {
        final ops = (frame as Map)['ops'];
        if (ops == null) continue;
        final r = isGp ? applyOps(doc, ops) : applyEventOps(doc, ops);
        doc = r['doc'];
        errors.addAll((r['errors'] as List).cast<String>());
        if (key != null) slates.add(normalizeFastcastSlate(reg, key, doc));
      }

      expect(canonicalJson(doc), canonicalJson(out['finalDoc']));
      expect(canonicalJson(errors), canonicalJson(out['errors']));
      if (key != null) {
        expect(canonicalJson(slates), canonicalJson(out['slates']));
      }
    });
  }
}
