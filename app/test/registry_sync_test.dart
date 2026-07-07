import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

// Guard: the bundled asset (assets/league-profiles.json) must stay byte-identical
// to the schema source of truth (schema/league-profiles.json). If this fails, run
// `dart run tool/sync_registry.dart` from app/. See pubspec assets note.
void main() {
  test('bundled registry matches schema source', () {
    final src = File('../schema/league-profiles.json');
    final asset = File('assets/league-profiles.json');
    expect(src.existsSync(), isTrue, reason: 'schema source missing');
    expect(asset.existsSync(), isTrue, reason: 'run tool/sync_registry.dart');
    expect(asset.readAsStringSync(), src.readAsStringSync(),
        reason: 'registry drift — run `dart run tool/sync_registry.dart`');
  });
}
