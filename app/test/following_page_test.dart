import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scores/src/providers.dart';
import 'package:scores/src/theme.dart';
import 'package:scores/src/ui/following_page.dart';

Future<SharedPreferences> prefs([Map<String, Object> seed = const {}]) async {
  SharedPreferences.setMockInitialValues(seed);
  return SharedPreferences.getInstance();
}

Widget wrap(Widget child, List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(theme: buildV2Theme(), home: child),
    );

const _cubs =
    '{"league":"baseball/mlb","teamId":"11","name":"Chicago Cubs","color":"cc3433"}';
const _stars =
    '{"league":"hockey/nhl","teamId":"25","name":"Dallas Stars","color":"006847"}';

void main() {
  testWidgets('manage grammar: TEAMS + LEAGUES rows, footer hint, no add tiles',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final p = await prefs({
      'followed': <String>['baseball/mlb'],
      'favoriteTeams': <String>[_cubs, _stars],
    });
    await tester.pumpWidget(wrap(const FollowingPage(), [
      sharedPrefsProvider.overrideWithValue(p),
      catalogProvider.overrideWith((ref) async => []),
    ]));
    await tester.pump();
    await tester.pump();

    expect(find.text('TEAMS'), findsOneWidget);
    expect(find.text('LEAGUES'), findsOneWidget);
    expect(find.text('Chicago Cubs'), findsOneWidget);
    expect(find.text('Dallas Stars'), findsOneWidget);
    // Footer says "team or league" (not "game").
    expect(
        find.text('Long-press any team or league in the app to add it here'),
        findsOneWidget);
    // No explicit add tiles in the manage grammar.
    expect(find.text('Add a team'), findsNothing);
    expect(find.text('Follow a league'), findsNothing);
    // Three-rule drag handles, minus buttons.
    expect(find.text('−'), findsWidgets);
  });

  testWidgets('minus removes a favorite immediately', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final p = await prefs({
      'followed': <String>[],
      'favoriteTeams': <String>[_cubs, _stars],
    });
    await tester.pumpWidget(wrap(const FollowingPage(), [
      sharedPrefsProvider.overrideWithValue(p),
      catalogProvider.overrideWith((ref) async => []),
    ]));
    await tester.pump();
    await tester.pump();

    expect(find.text('Chicago Cubs'), findsOneWidget);
    // The first minus button belongs to the first team (Cubs).
    await tester.tap(find.text('−').first);
    await tester.pumpAndSettle();
    expect(find.text('Chicago Cubs'), findsNothing);
    expect(find.text('Dallas Stars'), findsOneWidget);
  });

  test('reorder persists the stored order (drives feed + favorites order)',
      () async {
    final p = await prefs({
      'favoriteTeams': <String>[_cubs, _stars],
      'followed': <String>['baseball/mlb', 'hockey/nhl', 'soccer/eng.1'],
    });
    final container = ProviderContainer(
      overrides: [sharedPrefsProvider.overrideWithValue(p)],
    );
    addTearDown(container.dispose);

    // Move the first favorite to the end (newIndex is post-removal).
    container.read(favoriteTeamsProvider.notifier).reorder(0, 1);
    expect(container.read(favoriteTeamsProvider).map((f) => f.name).toList(),
        ['Dallas Stars', 'Chicago Cubs']);
    expect(p.getStringList('favoriteTeams')!.first.contains('Dallas Stars'),
        isTrue);

    // Move a followed league to the front.
    container.read(followedProvider.notifier).reorder(2, 0);
    expect(container.read(followedProvider),
        ['soccer/eng.1', 'baseball/mlb', 'hockey/nhl']);
    expect(p.getStringList('followed')!.first, 'soccer/eng.1');
  });
}
