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

Future<void> _pump(WidgetTester tester, {required String phase, required DateTime start}) async {
  SharedPreferences.setMockInitialValues({'baseUrl': 'https://w.example', 'followed': <String>['basketball/nba']});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      // Scores defaults to the today view — no date set to override.
      feedProvider.overrideWith((ref) async => [LeagueFeed('basketball/nba', _feed(phase: phase, start: start))]),
    ],
    child: MaterialApp(theme: buildTheme(Brightness.dark), home: const ScoresPage()),
  ));
  await tester.pump(const Duration(milliseconds: 50)); // resolve the async feed
}

/// Unmount so ScoresPage.dispose() cancels its poll timer (no pending-timer fail).
Future<void> _teardown(WidgetTester tester) => tester.pumpWidget(const SizedBox());

void main() {
  testWidgets('shows the "Today" date title + chevron and a winner-wash card', (tester) async {
    // A final game: the wash is reserved for finals and shades from the winner.
    await _pump(tester, phase: 'final', start: DateTime.now());

    // The header reads the viewed day (today by default) and carries the dropdown
    // chevron; the sport chips no longer live on the bar (they're in the sheet).
    expect(find.text('Today'), findsOneWidget);
    expect(find.byIcon(Icons.expand_more), findsOneWidget);
    expect(find.text('All'), findsNothing, reason: 'sport chips moved into the date sheet');
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
    await _pump(tester, phase: 'scheduled', start: todayAt7);

    // DateFormat.jm() formats 19:00 as "7:00 PM" (note: intl/CLDR uses a narrow
    // no-break space before the day-period, so compare against its own output).
    expect(find.text('6/13 - 7:00 PM EDT'), findsNothing, reason: 'the dated ESPN label must be replaced');
    expect(find.text(DateFormat.jm().format(todayAt7)), findsOneWidget, reason: 'today => time only');

    await _teardown(tester);
  });

  testWidgets('the date sheet exposes the sport chips; tapping one narrows the slate', (tester) async {
    SharedPreferences.setMockInitialValues({
      'baseUrl': 'https://w.example',
      'followed': <String>['basketball/nba', 'baseball/mlb'],
    });
    final prefs = await SharedPreferences.getInstance();
    final mlb = ScoresResponse.fromJson({
      'sport': 'baseball', 'league': 'mlb', 'leagueId': '10', 'leagueName': 'MLB', 'anyLive': false,
      'events': <dynamic>[],
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        feedProvider.overrideWith((ref) async => [
              LeagueFeed('basketball/nba', _feed(phase: 'final', start: DateTime.now())),
              LeagueFeed('baseball/mlb', mlb),
            ]),
      ],
      child: MaterialApp(theme: buildTheme(Brightness.dark), home: const ScoresPage()),
    ));
    await tester.pump(const Duration(milliseconds: 50));

    // The slate shows the NBA section; no chips on the bar yet.
    expect(find.text('NBA'), findsOneWidget);
    expect(find.byType(GameCard), findsOneWidget);

    // Open the date + sport sheet from the title, then tap the Baseball chip.
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(find.text('All'), findsOneWidget, reason: 'sport chips live in the sheet now');
    await tester.tap(find.text('Baseball'));
    await tester.pump();

    // The NBA section (behind the sheet) drops out — Baseball has no games.
    expect(find.text('NBA'), findsNothing);
    expect(find.byType(GameCard), findsNothing);

    // The active filter is named in the title so it isn't silently hidden once
    // the sheet is dismissed.
    expect(find.text('Today  ·  Baseball'), findsOneWidget);

    await tester.pumpAndSettle();
    await _teardown(tester);
  });

  testWidgets('picking a future day in the sheet sets the view date + dated title', (tester) async {
    SharedPreferences.setMockInitialValues({'baseUrl': 'https://w.example', 'followed': <String>['basketball/nba']});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      // The feed ignores the date here; we only assert the view-date wiring.
      feedProvider.overrideWith((ref) async =>
          [LeagueFeed('basketball/nba', _feed(phase: 'scheduled', start: DateTime.now()))]),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildTheme(Brightness.dark), home: const ScoresPage()),
    ));
    await tester.pump(const Duration(milliseconds: 50));

    expect(container.read(viewDateProvider), isNull, reason: 'defaults to the today view');

    // Open the sheet and tap the +3 day's chip. The anchor falls back to the
    // device date (no today-feed `day` captured in this fixture).
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();

    final today = DateUtils.dateOnly(DateTime.now());
    final plus3 = today.add(const Duration(days: 3));
    await tester.tap(find.text('${plus3.day}').first);
    await tester.pumpAndSettle();

    expect(container.read(viewDateProvider), plus3, reason: 'tapping a future chip stores that date');
    // The header title reflects the picked day (no longer "Today").
    expect(find.text(DateFormat('EEE, MMM d').format(plus3)), findsWidgets);
    // Picking a day is terminal: the sheet dismisses so the slate is visible
    // (the sport chips that live only in the sheet are gone).
    expect(find.text('All'), findsNothing, reason: 'picking a day dismisses the date sheet');

    await tester.pumpAndSettle();
    await _teardown(tester);
  });
}
