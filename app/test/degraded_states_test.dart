import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scores/src/api.dart';
import 'package:scores/src/data/espn_client.dart';
import 'package:scores/src/models.dart';
import 'package:scores/src/providers.dart';
import 'package:scores/src/theme.dart';
import 'package:scores/src/ui/player_page.dart';
import 'package:scores/src/ui/scores_page.dart';
import 'package:scores/src/ui/widgets.dart';
import 'package:scores/src/util.dart';

Future<SharedPreferences> prefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

Widget wrap(Widget child, List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(theme: buildV2Theme(), home: Scaffold(body: child)),
    );

/// A valid empty (offseason / no-games) slate — an empty `events[]` is NOT an
/// error.
ScoresResponse emptySlate(String key, String name) =>
    ScoresResponse.fromJson({'league': key, 'leagueName': name, 'events': []});

void main() {
  // ───────────────────────── STALE / OFFLINE (espn_client) ─────────────────
  group('stale-while-revalidate (EspnClient)', () {
    test('serves the last-good body flagged stale when a refetch fails', () async {
      var calls = 0;
      final mock = MockClient((req) async {
        calls++;
        if (calls == 1) return http.Response('{"n":1}', 200);
        return http.Response('upstream boom', 500);
      });
      final c = EspnClient('', mock);

      // ttl 0 → the entry expires immediately, so every call refetches.
      final first = await c.scoreboard('basketball/nba', ttl: 0);
      expect((first as Map)['n'], 1);
      expect(c.scoreboardFreshness('basketball/nba')!.stale, isFalse);

      // Refetch 500s → the last-good body is served, flagged stale (not blanked).
      final second = await c.scoreboard('basketball/nba', ttl: 0);
      expect((second as Map)['n'], 1, reason: 'served from cache');
      expect(c.scoreboardFreshness('basketball/nba')!.stale, isTrue);
      expect(calls, 2, reason: 'the refetch was actually attempted');
    });

    test('a successful refetch clears the stale flag', () async {
      var calls = 0;
      final mock = MockClient((req) async {
        calls++;
        if (calls == 2) return http.Response('down', 503);
        return http.Response('{"n":$calls}', 200);
      });
      final c = EspnClient('', mock);
      await c.scoreboard('baseball/mlb', ttl: 0); // ok
      await c.scoreboard('baseball/mlb', ttl: 0); // 503 → stale
      expect(c.scoreboardFreshness('baseball/mlb')!.stale, isTrue);
      await c.scoreboard('baseball/mlb', ttl: 0); // ok again → fresh
      expect(c.scoreboardFreshness('baseball/mlb')!.stale, isFalse);
    });

    test('a cold failure (nothing cached) still throws', () async {
      final mock = MockClient((req) async => http.Response('boom', 500));
      final c = EspnClient('', mock);
      await expectLater(
          c.scoreboard('basketball/nba'), throwsA(isA<ApiException>()));
    });
  });

  // ───────────────────────── freshness aggregate (Api) ─────────────────────
  test('Api.feedFreshness reports stale when any followed league is stale', () async {
    var nba = 0;
    final mock = MockClient((req) async {
      final u = req.url.toString();
      if (u.contains('basketball/nba')) {
        nba++;
        return nba == 1
            ? http.Response('{"events":[]}', 200)
            : http.Response('boom', 500);
      }
      return http.Response('{"events":[]}', 200); // mlb always ok
    });
    final client = EspnClient('', mock);
    final api = Api('', client);

    await client.scoreboard('basketball/nba', ttl: 0);
    await client.scoreboard('baseball/mlb', ttl: 0);
    var fr = api.feedFreshness(['basketball/nba', 'baseball/mlb']);
    expect(fr.stale, isFalse);
    expect(fr.lastUpdated, isNotNull);

    await client.scoreboard('basketball/nba', ttl: 0); // 500 → stale
    fr = api.feedFreshness(['basketball/nba', 'baseball/mlb']);
    expect(fr.stale, isTrue);
  });

  // ───────────────────────── OFFSEASON / NO GAMES (Scores) ─────────────────
  testWidgets(
      'empty followed league keeps its header with a terse "No games" line',
      (tester) async {
    final p = await prefs();
    await tester.pumpWidget(wrap(const ScoresPage(), [
      sharedPrefsProvider.overrideWithValue(p),
      homeCoverageProvider.overrideWith((ref) async => const <String>{}),
      feedProvider.overrideWith(
          (ref) async => [LeagueFeed('basketball/nba', emptySlate('basketball/nba', 'NBA'))]),
      favoritesFeedProvider.overrideWith((ref) async => const <FavoriteTeamFeed>[]),
    ]));
    await tester.pump(); // resolve feed + coverage

    // The header stays (tappable to the league page) with a "No games" caption.
    expect(find.text('NBA'), findsOneWidget);
    expect(find.text('No games'), findsOneWidget);
    // No hint fires because the coverage scan knows no other day.
    expect(find.textContaining('Next games'), findsNothing);

    await tester.pumpWidget(const SizedBox()); // stop the poll timer
  });

  testWidgets(
      'wholly empty day offers the nearest day with games; tapping moves the strip',
      (tester) async {
    final p = await prefs();
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    await tester.pumpWidget(wrap(const ScoresPage(), [
      sharedPrefsProvider.overrideWithValue(p),
      // The scan knows tomorrow carries games.
      homeCoverageProvider.overrideWith((ref) async => {ymd(tomorrow)}),
      feedProvider.overrideWith(
          (ref) async => [LeagueFeed('basketball/nba', emptySlate('basketball/nba', 'NBA'))]),
      favoritesFeedProvider.overrideWith((ref) async => const <FavoriteTeamFeed>[]),
    ]));
    await tester.pump(); // feed
    await tester.pump(); // coverage lands

    final hint = find.textContaining('Next games');
    expect(hint, findsOneWidget);

    await tester.tap(hint);
    await tester.pump(); // apply date state
    await tester.pump(); // rebuild

    // The strip moved to tomorrow (relative title flips).
    expect(find.text('TOMORROW'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  // ───────────────────────── STALE header line (Scores) ────────────────────
  List<Override> scoresOverrides(SharedPreferences p, FeedFreshness fresh) => [
        sharedPrefsProvider.overrideWithValue(p),
        homeCoverageProvider.overrideWith((ref) async => const <String>{}),
        feedProvider.overrideWith((ref) async =>
            [LeagueFeed('basketball/nba', emptySlate('basketball/nba', 'NBA'))]),
        favoritesFeedProvider
            .overrideWith((ref) async => const <FavoriteTeamFeed>[]),
        feedFreshnessProvider.overrideWith((ref) => fresh),
      ];

  testWidgets('no "Updated" line during normal (fresh) operation',
      (tester) async {
    final p = await prefs();
    await tester.pumpWidget(wrap(
        const ScoresPage(), scoresOverrides(p, const FeedFreshness(stale: false))));
    await tester.pump();
    expect(find.textContaining('Updated'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a stale feed shows the dim "Updated <time>" line', (tester) async {
    final p = await prefs();
    await tester.pumpWidget(wrap(
        const ScoresPage(),
        scoresOverrides(
            p, FeedFreshness(stale: true, lastUpdated: DateTime(2026, 7, 8, 17, 4)))));
    await tester.pump();
    expect(find.textContaining('Updated'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  // ───────────────────────── PLAYER page failed fetch ──────────────────────
  group('PlayerPage degraded fetch', () {
    const key = (league: 'baseball/mlb', athleteId: '4414531', teamId: null);

    testWidgets(
        'a failed profile fetch with a seeded name shows a "no stats" hint (not a bare identity)',
        (tester) async {
      await tester.pumpWidget(wrap(
        const PlayerPage(
            league: 'baseball/mlb', athleteId: '4414531', name: 'Zack Greinke'),
        [
          athleteProfileProvider(key)
              .overrideWith((ref) => Future<AthleteProfile?>.error(
                  ApiException(404, 'athletes/4414531'))),
        ],
      ));
      await tester.pump(); // seed identity paints
      await tester.pump(); // future rejects → error state lands

      // The seeded identity still paints (name shouts uppercase in the block)…
      expect(find.text('ZACK GREINKE'), findsOneWidget);
      // …and a terse hint fires instead of leaving a bare, broken-looking screen.
      expect(find.byType(HintCard), findsOneWidget);
      expect(find.textContaining('stats'), findsOneWidget);
    });

    testWidgets('a failed fetch with NO seed shows the full "couldn’t load" card',
        (tester) async {
      await tester.pumpWidget(wrap(
        const PlayerPage(league: 'baseball/mlb', athleteId: '4414531'),
        [
          athleteProfileProvider(key)
              .overrideWith((ref) => Future<AthleteProfile?>.error(
                  ApiException(404, 'athletes/4414531'))),
        ],
      ));
      await tester.pump();
      await tester.pump();
      expect(find.byType(HintCard), findsOneWidget);
    });
  });
}
