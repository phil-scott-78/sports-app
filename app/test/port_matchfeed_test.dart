import 'package:flutter_test/flutter_test.dart';
import 'package:scores/src/data/matchfeed.dart';
import 'golden_util.dart';

// Parity for the soccer core match feed (capability hasMatchFeed): the
// touch-by-touch plays resource behind the live-pitch view / shot map /
// momentum chart. Oracle = worker/src/matchfeed.js on the live-captured
// _extra.json matchFeeds fixture.
void main() {
  for (final e in goldenIndex().where((e) => e['endpoint'] == 'matchfeed')) {
    test('matchfeed parity: ${e['key']}/${e['eventId']}', () {
      final g = readGolden(e['file'] as String);
      final a = g['args'] as Map;
      final got = normalizeMatchFeed(a['raw'] as Map, a['homeId'], a['awayId']);
      expect(canonicalJson(got), canonicalJson(g['output']));
    });
  }
}
