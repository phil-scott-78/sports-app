// Copies the locked data model (schema/league-profiles.json) into the app's
// asset bundle. schema/ is the source of truth; the app bundles a byte-identical
// copy so it can resolve league profiles on-device (no worker). Run after any
// edit to the schema registry:
//
//   dart run tool/sync_registry.dart
//
// test/registry_sync_test.dart fails if the two ever drift, so CI catches a
// forgotten sync.
import 'dart:io';

void main() {
  final src = File('../schema/league-profiles.json');
  final dst = File('assets/league-profiles.json');
  if (!src.existsSync()) {
    stderr.writeln('source not found: ${src.path} (run from app/)');
    exit(1);
  }
  dst.writeAsStringSync(src.readAsStringSync());
  stdout.writeln('synced ${src.path} -> ${dst.path} (${dst.lengthSync()} bytes)');
}
