import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scores/src/models.dart';
import 'package:scores/src/theme.dart';
import 'package:scores/src/ui/tournament_page.dart';
import 'golden_util.dart';

/// Widget coverage for the four tournament-view grammars, each driven by a real
/// committed golden (the data agent's canonical output) parsed into a
/// [TournamentResponse] — the same shape the live app hands [TournamentView].
TournamentResponse _load(String file) {
  final g = readGolden('tournament/$file.json');
  final out = (g['output'] as Map).map((k, v) => MapEntry(k.toString(), v));
  return TournamentResponse.fromJson(out);
}

Future<void> _pump(WidgetTester tester, TournamentResponse t) async {
  // A tall/wide surface so the lazy page ListViews render every card (group
  // tables + the knockout scroller / series card all in one frame).
  tester.view.physicalSize = const Size(900, 5200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: buildV2Theme(),
    home: Scaffold(body: TournamentView(response: t)),
  ));
  await tester.pump();
}

void main() {
  loadTestRegistry();

  testWidgets('12a group tables + knockout scroller (World Cup)',
      (tester) async {
    final t = _load('soccer__fifa.world');
    expect(t.groups, isNotEmpty, reason: 'fifa golden carries group tables');
    await _pump(tester, t);

    // shell title + a group letter chip + a group table header + the knockout
    // scroller section — the 12a grammar's distinctive parts.
    expect(find.text('FIFA WORLD CUP'), findsOneWidget);
    expect(find.text('A'), findsOneWidget); // group-letter chip
    expect(find.text('GROUP A'), findsOneWidget); // group table header
    expect(find.text('KNOCKOUT BRACKET'), findsOneWidget);
    expect(find.text('Mexico'), findsWidgets);
  });

  testWidgets('12b draw columns with set scores (Wimbledon)', (tester) async {
    final t = _load('tennis__atp');
    expect(t.rounds, isNotEmpty);
    expect(t.groups, isEmpty);
    await _pump(tester, t);

    expect(find.text('WIMBLEDON'), findsOneWidget);
    expect(find.text("Men's Singles"), findsOneWidget); // dim subtitle
    expect(find.text('FINAL'), findsWidgets); // gold final column header
    expect(find.text('J. Sinner'), findsWidgets); // draw competitor
  });

  testWidgets('12d pools + best-of-3 championship (College World Series)',
      (tester) async {
    final t = _load('baseball__college-baseball');
    expect(t.pools, isNotEmpty);
    expect(t.series, isNotNull);
    await _pump(tester, t);

    expect(find.text('BRACKET 1'), findsOneWidget);
    expect(find.text('BRACKET 2'), findsOneWidget);
    expect(find.textContaining('BEST OF 3'), findsOneWidget);
    expect(find.text('ADVANCES'), findsWidgets);
    expect(find.text('GAME 1'), findsOneWidget);
    expect(find.text('Oklahoma Sooners'), findsWidgets);
  });
}
