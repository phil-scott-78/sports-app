import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scores/src/data/recap.dart';

// The on-device recap client (data/recap.dart): the `scores/recap`
// MethodChannel wrapper. Availability gates every inference; per-half-inning
// caching means a 15s poll never re-asks about the same half; every failure
// path answers null so the deterministic line stands.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('scores/recap');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('unavailable device (or no handler at all) → null, no crash', () async {
    // No mock handler = MissingPluginException, the web/desktop/test reality.
    final client = RecapClient();
    expect(
        await client.inningRecap(
            cacheKey: 'k', label: 'Top 5th', texts: const ['Cruz singled.']),
        isNull);
  });

  test('available device: summarize round-trip, one inference per half',
      () async {
    var summarizeCalls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'available':
          return true;
        case 'summarize':
          summarizeCalls++;
          final prompt =
              (call.arguments as Map)['prompt'] as String;
          expect(prompt, contains('Top 5th · PIT'));
          expect(prompt, contains('- Cruz singled.'));
          return 'Pirates plate two on three straight hits.\n';
      }
      return null;
    });
    final client = RecapClient();
    final first = await client.inningRecap(
        cacheKey: 'mlb|1|5|top',
        label: 'Top 5th · PIT',
        texts: const ['Cruz singled.']);
    expect(first, 'Pirates plate two on three straight hits.');
    // Same key again (the poll re-ran the provider) → cached, no second call.
    await client.inningRecap(
        cacheKey: 'mlb|1|5|top',
        label: 'Top 5th · PIT',
        texts: const ['Cruz singled.']);
    expect(summarizeCalls, 1);
  });

  test('model reports unavailable → null without a summarize call', () async {
    var summarized = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'available') return false;
      summarized = true;
      return 'nope';
    });
    final client = RecapClient();
    expect(
        await client.inningRecap(
            cacheKey: 'k', label: 'Top 5th', texts: const ['x']),
        isNull);
    expect(summarized, isFalse);
  });

  test('empty texts → null without touching the channel', () async {
    final client = RecapClient();
    expect(
        await client.inningRecap(cacheKey: 'k', label: 'Top 5th', texts: const []),
        isNull);
  });
}
