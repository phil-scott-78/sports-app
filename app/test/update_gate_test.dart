import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scores/src/models.dart';
import 'package:scores/src/providers.dart';
import 'package:scores/src/theme.dart';
import 'package:scores/src/ui/update_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';

ClientGate _gate({int? min, int? rec, String? latest = '0.3.1'}) => ClientGate(
      minVersionCode: min,
      recommendedVersionCode: rec,
      latestVersionName: latest,
      downloadUrl: 'https://github.com/phil-scott-78/sports-app/releases/latest',
    );

void main() {
  group('HealthInfo / ClientGate parsing is tolerant + fails open', () {
    test('full client block parses every field', () {
      final h = HealthInfo.fromJson({
        'ok': true,
        'leagues': 41,
        'client': {
          'minVersionCode': 10,
          'recommendedVersionCode': 42,
          'latestVersionName': '0.3.1',
          'downloadUrl': 'https://example/releases/latest',
        },
      });
      expect(h.ok, isTrue);
      expect(h.leagues, 41);
      expect(h.client!.minVersionCode, 10);
      expect(h.client!.recommendedVersionCode, 42);
      expect(h.client!.latestVersionName, '0.3.1');
      expect(h.client!.downloadUrl, 'https://example/releases/latest');
    });

    test('an ABSENT client block → null gate (fail-open: old/forked/mock worker)',
        () {
      final h = HealthInfo.fromJson({'ok': true, 'leagues': 41});
      expect(h.client, isNull);
    });

    test('an explicit null client → null gate', () {
      final h = HealthInfo.fromJson({'ok': true, 'leagues': 41, 'client': null});
      expect(h.client, isNull);
    });

    test('a partial client block leaves missing fields null (not zero)', () {
      final h = HealthInfo.fromJson({
        'ok': true,
        'leagues': 0,
        'client': {'recommendedVersionCode': 42},
      });
      expect(h.client!.minVersionCode, isNull); // not 0 — "no minimum required"
      expect(h.client!.recommendedVersionCode, 42);
    });
  });

  group('computeUpdateTier', () {
    test('dev build (code 0) never nags, even with a real gate', () {
      expect(computeUpdateTier(0, _gate(min: 10, rec: 42)), UpdateTier.none);
    });

    test('no gate served → none (fail-open)', () {
      expect(computeUpdateTier(42, null), UpdateTier.none);
    });

    test('gate with all-null fields → none (fail-open)', () {
      expect(computeUpdateTier(42, _gate()), UpdateTier.none);
    });

    test('below minimum → hard', () {
      expect(computeUpdateTier(5, _gate(min: 10, rec: 20)), UpdateTier.hard);
    });

    test('at/above min but below recommended → soft', () {
      expect(computeUpdateTier(15, _gate(min: 10, rec: 20)), UpdateTier.soft);
      expect(computeUpdateTier(10, _gate(min: 10, rec: 20)), UpdateTier.soft);
    });

    test('at/above recommended → none', () {
      expect(computeUpdateTier(20, _gate(min: 10, rec: 20)), UpdateTier.none);
      expect(computeUpdateTier(99, _gate(min: 10, rec: 20)), UpdateTier.none);
    });

    test('recommended-only gate (no minimum) below rec → soft', () {
      expect(computeUpdateTier(15, _gate(rec: 20)), UpdateTier.soft);
    });

    test('minimum-only gate, above it but no recommended → none', () {
      expect(computeUpdateTier(15, _gate(min: 10)), UpdateTier.none);
    });
  });

  group('UpdateBanner widget', () {
    Future<void> pump(
      WidgetTester tester, {
      required UpdateTier tier,
      ClientGate? gate,
      int dismissed = 0,
    }) async {
      SharedPreferences.setMockInitialValues(
          {if (dismissed > 0) 'dismissedRecommendedVersionCode': dismissed});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          updateTierProvider.overrideWithValue(tier),
          healthProvider.overrideWith(
              (ref) async => HealthInfo(ok: true, leagues: 1, client: gate)),
        ],
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: const Scaffold(body: UpdateBanner()),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 10)); // resolve health future
    }

    testWidgets('none → renders nothing', (tester) async {
      await pump(tester, tier: UpdateTier.none, gate: _gate(min: 10, rec: 42));
      expect(find.textContaining('Update'), findsNothing);
      expect(find.textContaining('supported'), findsNothing);
    });

    testWidgets('soft → dismissible "update available" with the latest version',
        (tester) async {
      await pump(tester, tier: UpdateTier.soft, gate: _gate(rec: 42));
      expect(find.text('Update available — v0.3.1'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget); // dismissible
    });

    testWidgets('hard → persistent "no longer supported", NOT dismissible',
        (tester) async {
      await pump(tester, tier: UpdateTier.hard, gate: _gate(min: 99));
      expect(find.textContaining('no longer supported'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsNothing); // no dismiss
    });

    testWidgets('soft already dismissed for this recommended → hidden',
        (tester) async {
      await pump(tester,
          tier: UpdateTier.soft, gate: _gate(rec: 42), dismissed: 42);
      expect(find.textContaining('Update available'), findsNothing);
    });

    testWidgets('tapping dismiss hides the soft banner', (tester) async {
      await pump(tester, tier: UpdateTier.soft, gate: _gate(rec: 42));
      expect(find.text('Update available — v0.3.1'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      expect(find.textContaining('Update available'), findsNothing);
    });

    testWidgets('tier soft but no gate served → hidden (fail-open guard)',
        (tester) async {
      await pump(tester, tier: UpdateTier.soft, gate: null);
      expect(find.textContaining('Update'), findsNothing);
    });
  });
}
