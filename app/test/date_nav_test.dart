import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scores/src/models.dart';
import 'package:scores/src/providers.dart';
import 'package:scores/src/theme.dart';
import 'package:scores/src/ui/hero_card.dart';
import 'package:scores/src/ui/scores_page.dart';
import 'package:scores/src/util.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

Future<SharedPreferences> prefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

Widget wrap(Widget child, List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(theme: buildV2Theme(), home: Scaffold(body: child)),
    );

void main() {
  testWidgets(
      'date strip: tap TODAY → strip; pick a past day → heroes hidden, '
      'feed refetched with date, BACK TO TODAY shown; reset restores', (tester) async {
    final p = await prefs();
    final mlb = ScoresResponse.fromJson(fixture('mlb.json'));

    await tester.pumpWidget(wrap(const ScoresPage(), [
      sharedPrefsProvider.overrideWithValue(p),
      // The feed reads homeDateProvider: today → the MLB slate; any picked day →
      // an empty slate. Proves the feed refetches keyed on the date.
      feedProvider.overrideWith((ref) async {
        final date = ref.watch(homeDateProvider);
        return date == null
            ? [LeagueFeed('baseball/mlb', mlb)]
            : const <LeagueFeed>[];
      }),
      favoritesFeedProvider.overrideWith((ref) async => [
            FavoriteTeamFeed(
              const FavoriteTeam(
                  league: 'basketball/nba', teamId: '5', name: 'Cavaliers'),
              TeamCard.fromJson(fixture('teamcard_nba.json')),
            ),
          ]),
    ]));
    await tester.pump(); // resolve the feed/favorites futures

    // --- today: title, hero card, and the league section all present ---
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.byType(FavoriteHeroCard), findsOneWidget);
    expect(find.text(mlb.leagueName.toUpperCase()), findsOneWidget);

    // --- tap the title → the date strip pops down ---
    await tester.tap(find.text('TODAY'));
    await tester.pumpAndSettle();
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final ydChip = find.byKey(ValueKey('daychip-${ymd(yesterday)}'));
    expect(ydChip, findsOneWidget);

    // --- pick yesterday ---
    await tester.tap(ydChip);
    await tester.pump(); // apply the state change
    await tester.pump(); // resolve the refetched (empty) feed

    // heroes are now-anchored → hidden on a dated slate
    expect(find.byType(FavoriteHeroCard), findsNothing);
    // BACK TO TODAY pill + relative title appear
    expect(find.text('BACK TO TODAY'), findsOneWidget);
    expect(find.text('YESTERDAY'), findsOneWidget);
    // the refetched empty slate → the dated empty hint
    expect(find.textContaining('No games on this day'), findsOneWidget);
    expect(find.text(mlb.leagueName.toUpperCase()), findsNothing);

    // --- back to today restores everything ---
    await tester.tap(find.text('BACK TO TODAY'));
    await tester.pump();
    await tester.pump();
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.byType(FavoriteHeroCard), findsOneWidget);
    expect(find.text(mlb.leagueName.toUpperCase()), findsOneWidget);

    // Tear down before any poll timer fires.
    await tester.pumpWidget(const SizedBox());
  });

  test('ymd / parseYmd round-trip + relative day titles', () {
    final d = DateTime(2026, 7, 6);
    expect(ymd(d), '20260706');
    expect(parseYmd('20260706'), d);
    expect(parseYmd('bad'), isNull);
    final now = DateTime.now();
    expect(dayTitle(now), 'TODAY');
    expect(dayTitle(now.subtract(const Duration(days: 1))), 'YESTERDAY');
    expect(dayTitle(now.add(const Duration(days: 1))), 'TOMORROW');
  });
}
