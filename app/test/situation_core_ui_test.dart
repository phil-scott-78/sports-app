import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scores/src/models.dart';
import 'package:scores/src/theme.dart';
import 'package:scores/src/ui/situations.dart';

// The detail-open CORE situation UI: the basketball bonus/timeout card and the
// gridiron red-zone flag, plus the merge that folds a summary-borne core situation
// over the (often absent) scoreboard one. Data-presence dispatch, never sport name.

Competition _comp({
  required String scoreKind,
  Situation? situation,
}) =>
    Competition.fromJson({
      'id': '1',
      'layout': 'headToHead',
      'scoreKind': scoreKind,
      'competitorKind': 'team',
      'status': {'phase': 'live', 'live': true, 'period': 3, 'periodLabel': '3rd'},
      'periods': {'unit': 'quarter', 'regulation': 4},
      'competitors': [
        {'id': 'h', 'homeAway': 'home', 'team': {'abbreviation': 'LAL', 'color': '552583'}},
        {'id': 'a', 'homeAway': 'away', 'team': {'abbreviation': 'BOS', 'color': '007A33'}},
      ],
      if (situation != null) 'situation': situation.toJsonForTest(),
    });

extension on Situation {
  // A minimal round-trip map for the fields these tests exercise.
  Map<String, dynamic> toJsonForTest() => {
        if (down != null) 'down': down,
        if (distance != null) 'distance': distance,
        if (isRedZone != null) 'isRedZone': isRedZone,
        if (homeBonus != null) 'homeBonus': homeBonus,
        if (awayBonus != null) 'awayBonus': awayBonus,
        if (homeTimeouts != null) 'homeTimeouts': homeTimeouts,
        if (awayTimeouts != null) 'awayTimeouts': awayTimeouts,
        if (lastPlay != null) 'lastPlay': lastPlay,
      };
}

Future<void> _pump(WidgetTester tester, Widget? card) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildV2Theme(),
    home: Scaffold(body: card ?? const SizedBox()),
  ));
}

void main() {
  testWidgets('basketball bonus card renders bonus flag + timeouts', (tester) async {
    final sit = Situation(homeBonus: 'DOUBLE', awayBonus: 'NONE', homeTimeouts: 2, awayTimeouts: 4);
    final comp = _comp(scoreKind: 'numeric', situation: sit);
    final card = situationCardFor(comp);
    expect(card, isA<BasketballSituationCard>());
    await _pump(tester, card);
    expect(find.text('BONUS & TIMEOUTS'), findsOneWidget); // CardLabel uppercases
    expect(find.text('DOUBLE BONUS'), findsOneWidget); // home in double bonus
    expect(find.textContaining('TO'), findsWidgets); // timeout labels
  });

  testWidgets('NONE bonus for both sides shows no bonus flag', (tester) async {
    final sit = Situation(homeBonus: 'NONE', awayBonus: 'NONE', homeTimeouts: 5, awayTimeouts: 6);
    final card = situationCardFor(_comp(scoreKind: 'numeric', situation: sit));
    expect(card, isA<BasketballSituationCard>()); // still has timeouts to show
    await _pump(tester, card);
    expect(find.text('BONUS'), findsNothing);
    expect(find.text('DOUBLE BONUS'), findsNothing);
  });

  testWidgets('gridiron card shows RED ZONE flag when core isRedZone', (tester) async {
    final sit = Situation(down: 2, distance: 6, isRedZone: true, homeTimeouts: 3, awayTimeouts: 2);
    final comp = _comp(scoreKind: 'numeric', situation: sit);
    final card = situationCardFor(comp);
    expect(card, isA<GridironSituationCard>());
    await _pump(tester, card);
    expect(find.text('2ND & 6'), findsOneWidget);
    expect(find.text('RED ZONE'), findsOneWidget);
  });

  test('summary core situation merges over an absent scoreboard situation', () {
    // Football live game with NO scoreboard situation (the production reality) —
    // the core situation arrives via the summary and lights up the gridiron card.
    final comp = _comp(scoreKind: 'numeric', situation: null);
    expect(comp.situation, isNull);
    final core = Situation(down: 3, distance: 8, isRedZone: false);
    final merged = comp.withSituation((comp.situation ?? core).mergedWith(core));
    expect(merged.situation!.down, 3);
    expect(merged.situation!.hasGridiron, true);
    expect(situationCardFor(merged), isA<GridironSituationCard>());
  });

  test('merge lets core fields win but keeps scoreboard-only fields', () {
    final scoreboard = Situation(lastPlay: 'Tip-off', homeTimeouts: 1);
    final core = Situation(homeBonus: 'ONE', homeTimeouts: 4);
    final merged = scoreboard.mergedWith(core);
    expect(merged.homeBonus, 'ONE'); // added by core
    expect(merged.homeTimeouts, 4); // core wins
    expect(merged.lastPlay, 'Tip-off'); // scoreboard-only survives
    expect(merged.hasBonus, true);
  });
}
