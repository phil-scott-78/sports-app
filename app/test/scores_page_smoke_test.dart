import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:scores/src/models.dart';
import 'package:scores/src/providers.dart';
import 'package:scores/src/theme.dart';
import 'package:scores/src/ui/scores_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One NBA league feed with a single head-to-head game. Team colors are set so
/// the card-gradient path is exercised; HOM's primary is black ('000000') to
/// exercise the altColor fallback. `phase` toggles scheduled vs final.
ScoresResponse _feed({required String phase, required DateTime start}) =>
    ScoresResponse.fromJson({
      'sport': 'basketball',
      'league': 'nba',
      'leagueId': '46',
      'leagueName': 'NBA',
      'anyLive': false,
      'events': [
        {
          'id': '1',
          'name': 'Away at Home',
          'shortName': 'AWY @ HOM',
          'start': start.toUtc().toIso8601String(),
          'competitions': [
            {
              'id': '1',
              'layout': 'headToHead',
              'scoreKind': 'numeric',
              'competitorKind': 'team',
              'status': {
                'phase': phase,
                'live': false,
                'ended': phase == 'final',
                'period': 4,
                // ESPN's dated label — the thing the fix must override for today.
                'periodLabel': '6/13 - 7:00 PM EDT',
                'espnName': phase == 'final' ? 'STATUS_FINAL' : 'STATUS_SCHEDULED',
                'detail': 'detail',
              },
              'periods': {'unit': 'quarter', 'regulation': 4, 'played': 4, 'isOvertime': false},
              'competitors': [
                {'kind': 'team', 'id': '10', 'displayName': 'Home', 'abbreviation': 'HOM', 'homeAway': 'home', 'color': '000000', 'altColor': 'c8102e', 'winner': phase == 'final', 'score': {'display': '100', 'value': 100}},
                {'kind': 'team', 'id': '20', 'displayName': 'Away', 'abbreviation': 'AWY', 'homeAway': 'away', 'color': '1d428a', 'winner': false, 'score': {'display': '98', 'value': 98}},
              ],
            }
          ],
        }
      ],
    });

Future<void> _pump(WidgetTester tester, {required ScoreDate mode, required String phase, required DateTime start}) async {
  SharedPreferences.setMockInitialValues({'baseUrl': 'https://w.example', 'followed': <String>['basketball/nba']});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      dateModeProvider.overrideWith((ref) => mode),
      feedProvider.overrideWith((ref) async => [LeagueFeed('basketball/nba', _feed(phase: phase, start: start))]),
    ],
    child: MaterialApp(theme: buildTheme(Brightness.dark), home: const ScoresPage()),
  ));
  await tester.pump(const Duration(milliseconds: 50)); // resolve the async feed
}

/// Unmount so ScoresPage.dispose() cancels its poll timer (no pending-timer fail).
Future<void> _teardown(WidgetTester tester) => tester.pumpWidget(const SizedBox());

void main() {
  testWidgets('renders the Yesterday/Today/Upcoming bar and a winner-wash card', (tester) async {
    // A final game: the wash is reserved for finals and shades from the winner.
    await _pump(tester, mode: ScoreDate.today, phase: 'final', start: DateTime.now());

    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.byType(GameCard), findsOneWidget);

    // The card paints the winner-color wash via Ink(decoration:) so the tap
    // ripple renders over it.
    final gradients = tester
        .widgetList<Ink>(find.descendant(of: find.byType(GameCard), matching: find.byType(Ink)))
        .map((i) => i.decoration)
        .whereType<BoxDecoration>()
        .where((b) => b.gradient is LinearGradient)
        .toList();
    expect(gradients, isNotEmpty, reason: 'a final head-to-head card carries a winner-color gradient');

    await _teardown(tester);
  });

  testWidgets('a game starting today shows a clock time, not ESPN\'s dated label', (tester) async {
    final todayAt7 = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 19, 0);
    await _pump(tester, mode: ScoreDate.today, phase: 'scheduled', start: todayAt7);

    // DateFormat.jm() formats 19:00 as "7:00 PM" (note: intl/CLDR uses a narrow
    // no-break space before the day-period, so compare against its own output).
    expect(find.text('6/13 - 7:00 PM EDT'), findsNothing, reason: 'the dated ESPN label must be replaced');
    expect(find.text(DateFormat.jm().format(todayAt7)), findsOneWidget, reason: 'today => time only');

    await _teardown(tester);
  });

  testWidgets('Upcoming reveals a date strip; tapping a day re-selects it', (tester) async {
    SharedPreferences.setMockInitialValues({'baseUrl': 'https://w.example', 'followed': <String>['basketball/nba']});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      dateModeProvider.overrideWith((ref) => ScoreDate.upcoming),
      // Feed is static here — we're exercising the strip + selection, not a fetch.
      feedProvider.overrideWith((ref) async =>
          [LeagueFeed('basketball/nba', _feed(phase: 'scheduled', start: DateTime.now().add(const Duration(days: 2))))]),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildTheme(Brightness.dark), home: const ScoresPage()),
    ));
    await tester.pump(const Duration(milliseconds: 50));

    final today = DateUtils.dateOnly(DateTime.now());
    final tomorrow = today.add(const Duration(days: 1));
    final plus3 = today.add(const Duration(days: 3));

    // The strip shows weekday chips; it defaults to tomorrow (offset 1).
    expect(find.text(DateFormat.E().format(tomorrow).toUpperCase()), findsOneWidget);
    expect(container.read(upcomingOffsetProvider), 1, reason: 'Upcoming defaults to tomorrow (+1)');

    // Tap the +3 day's chip → its offset becomes the selected fetch day.
    await tester.tap(find.text('${plus3.day}').first);
    await tester.pump();
    expect(container.read(upcomingOffsetProvider), 3, reason: 'tapping the +3 chip selects offset 3');

    await _teardown(tester);
  });

  testWidgets('Upcoming empty state reads "No upcoming games"', (tester) async {
    SharedPreferences.setMockInitialValues({'baseUrl': 'https://w.example', 'followed': <String>['basketball/nba']});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        dateModeProvider.overrideWith((ref) => ScoreDate.upcoming),
        feedProvider.overrideWith((ref) async => [
              LeagueFeed('basketball/nba', ScoresResponse.fromJson({
                'sport': 'basketball', 'league': 'nba', 'leagueId': '46', 'leagueName': 'NBA',
                'anyLive': false, 'events': <dynamic>[],
              })),
            ]),
      ],
      child: MaterialApp(theme: buildTheme(Brightness.dark), home: const ScoresPage()),
    ));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('No upcoming games'), findsOneWidget);

    await _teardown(tester);
  });
}
