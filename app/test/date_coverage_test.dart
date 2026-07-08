import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scores/src/models.dart';
import 'package:scores/src/providers.dart';
import 'package:scores/src/theme.dart';
import 'package:scores/src/ui/scores_page.dart';
import 'package:scores/src/util.dart';

Future<SharedPreferences> prefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

Widget wrap(Widget child, List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(theme: buildV2Theme(), home: Scaffold(body: child)),
    );

/// The day-number Text color inside a specific date-strip chip.
Color? numColor(WidgetTester t, DateTime d) {
  final f = find.descendant(
    of: find.byKey(ValueKey('daychip-${ymd(d)}')),
    matching: find.text('${d.day}'),
  );
  return t.widget<Text>(f).style?.color;
}

/// The has-games dot color inside a chip (the only circular decoration in it).
Color? dotColor(WidgetTester t, DateTime d) {
  final f = find.descendant(
    of: find.byKey(ValueKey('daychip-${ymd(d)}')),
    matching: find.byWidgetPredicate((w) =>
        w is AnimatedContainer &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).shape == BoxShape.circle),
  );
  return (t.widget<AnimatedContainer>(f).decoration as BoxDecoration).color;
}

ScoresResponse _slate({List<String> calendarDays = const []}) =>
    ScoresResponse.fromJson({
      'league': 'baseball/mlb',
      'leagueName': 'MLB',
      'calendarDays': calendarDays,
    });

void main() {
  final today = DateTime.now();
  final base = DateTime(today.year, today.month, today.day);
  final empty3 = base.add(const Duration(days: 3)); // not in any coverage/hint
  final tomorrow = base.add(const Duration(days: 1));

  testWidgets(
      'landed range scan: dots has-games days, dims a proven-empty day',
      (tester) async {
    final p = await prefs();
    await tester.pumpWidget(wrap(const ScoresPage(), [
      sharedPrefsProvider.overrideWithValue(p),
      // Scan landed: today + tomorrow carry games; every other window day empty.
      homeCoverageProvider.overrideWith((ref) async => {ymd(base), ymd(tomorrow)}),
      feedProvider.overrideWith((ref) async => [LeagueFeed('baseball/mlb', _slate())]),
      favoritesFeedProvider.overrideWith((ref) async => const <FavoriteTeamFeed>[]),
    ]));
    await tester.pump(); // resolve feed + coverage futures

    // Open the date strip.
    await tester.tap(find.text('TODAY'));
    await tester.pumpAndSettle();

    // Today is the SELECTED chip → inverted styling wins, but it still dots.
    expect(numColor(tester, base), T.invertedText);
    expect(dotColor(tester, base), T.invertedLabel);

    // A non-selected has-games day → full-weight number + a neutral dot.
    expect(numColor(tester, tomorrow), T.text);
    expect(dotColor(tester, tomorrow), T.textDim);

    // A proven-empty day → dimmed number + no dot.
    expect(numColor(tester, empty3), T.textFaint);
    expect(dotColor(tester, empty3), Colors.transparent);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'before the scan lands: dots from the calendarDays hint, never dims an '
      'unknown day', (tester) async {
    final p = await prefs();
    final pending = Completer<Set<String>>(); // scan never resolves
    addTearDown(() => pending.complete(const <String>{}));
    await tester.pumpWidget(wrap(const ScoresPage(), [
      sharedPrefsProvider.overrideWithValue(p),
      homeCoverageProvider.overrideWith((ref) => pending.future),
      // Hint says tomorrow has games; today/others are unknown until the scan.
      feedProvider.overrideWith((ref) async =>
          [LeagueFeed('baseball/mlb', _slate(calendarDays: [ymd(tomorrow)]))]),
      favoritesFeedProvider.overrideWith((ref) async => const <FavoriteTeamFeed>[]),
    ]));
    await tester.pump();

    await tester.tap(find.text('TODAY'));
    await tester.pumpAndSettle();

    // Hinted day → dot present (neutral, not today), number full.
    expect(dotColor(tester, tomorrow), T.textDim);
    expect(numColor(tester, tomorrow), T.text);

    // Unknown day (scan pending, not hinted) → NOT dimmed, no dot.
    expect(numColor(tester, empty3), T.text);
    expect(dotColor(tester, empty3), Colors.transparent);

    await tester.pumpWidget(const SizedBox());
  });
}
