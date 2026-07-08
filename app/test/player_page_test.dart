import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scores/src/models.dart';
import 'package:scores/src/providers.dart';
import 'package:scores/src/theme.dart';
import 'package:scores/src/ui/player_page.dart';

/// The player-profile golden carries {args, output}; `output` is the canonical
/// AthleteProfile shape the model parses (a real WNBA fan-out — per-game stats +
/// a 5-game log).
AthleteProfile golden(String path) {
  final j = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  return AthleteProfile.fromJson(
      (j['output'] ?? j) as Map<String, dynamic>);
}

Widget wrap(Widget child, List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(theme: buildV2Theme(), home: child),
    );

void main() {
  const goldenPath =
      'test/fixtures/golden/athlete/basketball__wnba__4433730.json';

  testWidgets('PlayerPage renders identity + per-game grid + game log',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final a = golden(goldenPath);
    await tester.pumpWidget(wrap(
      PlayerPage(
          league: a.league, athleteId: a.id, teamId: a.team?.id),
      [
        athleteProfileProvider.overrideWith((ref, k) async => a),
      ],
    ));
    await tester.pump(); // resolve the profile future

    // compact bar + shouted name
    expect(find.text('PLAYER'), findsOneWidget);
    expect(find.text(a.name.toUpperCase()), findsWidgets);

    // SEASON per-game grid: label + a data-derived column header (basketball → PTS)
    expect(find.text('SEASON · PER GAME'), findsOneWidget);
    expect(find.text('PTS'), findsWidgets);

    // LAST N games card (the fixture serves 5)
    expect(find.text('LAST ${a.lastGames.length} GAMES'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('PlayerPage: identity-only profile renders identity, no cards',
      (tester) async {
    final a = AthleteProfile(
        id: '999', league: 'basketball/nba', name: 'Jane Doe');
    await tester.pumpWidget(wrap(
      const PlayerPage(
          league: 'basketball/nba', athleteId: '999', color: '552583'),
      [
        athleteProfileProvider.overrideWith((ref, k) async => a),
      ],
    ));
    await tester.pump();

    expect(find.text('JANE DOE'), findsWidgets);
    // no stat cards
    expect(find.text('SEASON · PER GAME'), findsNothing);
    expect(find.textContaining('GAMES'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });
}
