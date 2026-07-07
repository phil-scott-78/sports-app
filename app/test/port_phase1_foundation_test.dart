import 'package:flutter_test/flutter_test.dart';
import 'package:scores/src/data/profiles.dart';
import 'golden_util.dart';

// Phase 1 parity: the Dart port of resolve.mjs + catalog.js (lib/src/data/
// profiles.dart) must match the JS reference dumps (test/fixtures/golden/meta/).
void main() {
  late Registry reg;
  setUpAll(() => reg = loadTestRegistry());

  test('resolve() matches JS for every concrete league', () {
    final golden = readGoldenJson('meta/resolve.json') as Map<String, dynamic>;
    for (final key in golden.keys) {
      expect(canonicalJson(resolve(reg, key)), canonicalJson(golden[key]),
          reason: 'resolve mismatch for $key');
    }
  });

  test('leagueKeys() matches JS across filters', () {
    final g = readGoldenJson('meta/leagueKeys.json') as Map<String, dynamic>;
    expect(leagueKeys(reg), g['all']);
    expect(leagueKeys(reg, priority: 'v1'), g['v1']);
    expect(leagueKeys(reg, priority: ['v1', 'v2']), g['v1v2']);
    expect(leagueKeys(reg, sport: 'soccer'), g['soccer']);
  });

  test('buildCatalog() matches JS (unfiltered + v1)', () {
    expect(canonicalJson(buildCatalog(reg)),
        canonicalJson(readGoldenJson('meta/catalog.json')));
    expect(canonicalJson(buildCatalog(reg, priority: 'v1')),
        canonicalJson(readGoldenJson('meta/catalog_v1.json')));
  });
}
