import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scores/src/inning_recap.dart';
import 'package:scores/src/models.dart';
import 'package:scores/src/theme.dart';
import 'package:scores/src/ui/situations.dart';
import 'package:scores/src/ui/widgets.dart';

// The turn-8 baseball Now cards (design-mirror/LiveGame.dc.html #8a):
//  - the DUEL situation card (pitcher vs batter, count dot groups, footer with
//    the rich pitch count + cheap on-deck);
//  - the strike-zone + bases card (zone only with pitch locations — the
//    design's degrade rule — bases always for a live baseball situation);
//  - the horizontally scrollable pitch strip.
// All data-presence gated, never sport-name.

Competition _comp(Map<String, dynamic> situation) => Competition.fromJson({
      'id': '1',
      'layout': 'headToHead',
      'scoreKind': 'numeric',
      'competitorKind': 'team',
      'status': {'phase': 'live', 'live': true, 'period': 2},
      'periods': {'unit': 'inning', 'regulation': 9, 'played': 2},
      'competitors': [
        {
          'id': '15',
          'homeAway': 'home',
          'team': {'abbreviation': 'ATL', 'color': 'ce1141'}
        },
        {
          'id': '23',
          'homeAway': 'away',
          'team': {'abbreviation': 'PIT', 'color': 'fdb827'}
        },
      ],
      'situation': situation,
    });

final _situation = {
  'balls': 1,
  'strikes': 2,
  'outs': 1,
  'onFirst': false,
  'onSecond': true,
  'onThird': true,
  'pitcher': 'B. Elder',
  'pitcherLine': '1.2 IP · 2 H · 0 ER',
  'batter': 'J. Mangum',
  'batterLine': '1-1, .318 AVG',
  'onDeck': 'B. Lowe',
};

AtBat _liveAtBat({bool coords = true}) => AtBat.fromJson({
      'live': true,
      'batter': 'J. Mangum',
      'balls': 1,
      'strikes': 2,
      'pitchCount': 40,
      'second': 'T. Callihan',
      'third': 'N. Gonzales',
      'pitches': [
        {
          'r': 'strike',
          'text': 'Strike 1 Swinging',
          'velo': 82,
          'type': 'Slider',
          if (coords) 'x': 118,
          if (coords) 'y': 181,
        },
        {
          'r': 'ball',
          'text': 'Ball 1',
          'velo': 85,
          'type': 'Slider',
          if (coords) 'x': 60,
          if (coords) 'y': 260,
        },
        {
          'r': 'foul',
          'text': 'Strike 2 Foul',
          'velo': 91,
          'type': 'Cutter',
          if (coords) 'x': 140,
          if (coords) 'y': 150,
        },
      ],
    });

Future<void> _pump(WidgetTester tester, Widget card) async {
  await tester.pumpWidget(MaterialApp(
    theme: buildV2Theme(),
    home: Scaffold(body: SingleChildScrollView(child: card)),
  ));
}

void main() {
  testWidgets('duel card: pitcher vs batter, count groups, footer',
      (tester) async {
    final card =
        situationCardFor(_comp(_situation), liveAtBat: _liveAtBat());
    expect(card, isA<BaseballSituationCard>());
    await _pump(tester, card!);
    expect(find.text('PITCHING'), findsOneWidget);
    expect(find.text('AT BAT'), findsOneWidget);
    expect(find.text('B. Elder'), findsOneWidget);
    expect(find.text('J. Mangum'), findsOneWidget);
    expect(find.text('1.2 IP · 2 H · 0 ER'), findsOneWidget);
    expect(find.text('BALLS'), findsOneWidget);
    expect(find.text('STRIKES'), findsOneWidget);
    expect(find.text('OUTS'), findsOneWidget);
    // footer: rich pitch count + cheap on deck
    expect(find.text('40'), findsOneWidget);
    expect(find.text('B. Lowe'), findsOneWidget);
  });

  testWidgets('duel card degrades: no rich at-bat → no pitch count row',
      (tester) async {
    final sit = Map<String, dynamic>.from(_situation)..remove('onDeck');
    final card = situationCardFor(_comp(sit));
    await _pump(tester, card!);
    expect(find.textContaining('Pitch count'), findsNothing);
    expect(find.textContaining('On deck'), findsNothing);
    expect(find.text('PITCHING'), findsOneWidget); // duel still renders
  });

  testWidgets('zone card: outline + numbered markers with coords, runner names',
      (tester) async {
    final card = BaseballZoneCard(_comp(_situation), liveAtBat: _liveAtBat());
    await _pump(tester, card);
    expect(find.text('STRIKE ZONE'), findsOneWidget); // CardLabel uppercases
    expect(find.text("catcher's view"), findsOneWidget);
    // markers numbered 1..3 (the strip shares the numbering)
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    // bases: diamond + resolved runner names, 1B empty
    expect(find.byType(BaseballDiamond), findsOneWidget);
    expect(find.text('T. Callihan'), findsOneWidget);
    expect(find.text('N. Gonzales'), findsOneWidget);
    expect(find.text('empty'), findsOneWidget);
  });

  testWidgets('zone card degrades without pitch locations: bases only',
      (tester) async {
    final card = BaseballZoneCard(_comp(_situation),
        liveAtBat: _liveAtBat(coords: false));
    await _pump(tester, card);
    expect(find.text('STRIKE ZONE'), findsNothing);
    expect(find.text("catcher's view"), findsNothing);
    expect(find.text('ON BASE'), findsOneWidget);
    expect(find.byType(BaseballDiamond), findsOneWidget);
    expect(find.text('T. Callihan'), findsOneWidget);
  });

  testWidgets('zone card without rich at-bat: cheap bases still render',
      (tester) async {
    final card = BaseballZoneCard(_comp(_situation));
    await _pump(tester, card);
    expect(find.text('ON BASE'), findsOneWidget);
    // occupied bases without resolved names fall back to 'on base'
    expect(find.text('on base'), findsNWidgets(2));
    expect(find.text('empty'), findsOneWidget);
  });

  testWidgets(
      'zone calibration: markers match ESPN gamecast placement '
      '(live 2026-07-09 Yarbrough→Vilade at-bat)', (tester) async {
    // Real coords from the live game the calibration was checked against:
    // 1 ball (152,153) → just OUTSIDE the right zone edge, upper region;
    // 2 strike looking (134,161) → INSIDE, upper right-of-center;
    // 3 ball (114,224) → BELOW the zone, near center.
    final ab = AtBat.fromJson({
      'live': true,
      'pitches': [
        {'r': 'ball', 'text': 'Ball 1', 'x': 152, 'y': 153},
        {'r': 'strike', 'text': 'Strike 1 Looking', 'x': 134, 'y': 161},
        {'r': 'ball', 'text': 'Ball 2', 'x': 114, 'y': 224},
      ],
    });
    await _pump(tester, BaseballZoneCard(_comp(_situation), liveAtBat: ab));
    // The drawn outline rect (150×170 panel; 16%/14% insets) in panel space.
    const zl = 150 * .16, zr = 150 * .84, zt = 170 * .14, zb = 170 * .86;
    // Marker centers relative to the 150×170 zone-plot panel's top-left.
    final plotTopLeft = tester.getTopLeft(find.byWidgetPredicate(
        (w) => w is SizedBox && w.width == 150 && w.height == 170));
    Offset rel(String s) => tester.getCenter(find.text(s)) - plotTopLeft;
    final p1 = rel('1'), p2 = rel('2'), p3 = rel('3');
    // 1: outside the right edge, vertically inside the zone
    expect(p1.dx, greaterThan(zr));
    expect(p1.dy, inInclusiveRange(zt, zb));
    // 2: inside the zone, right of center
    expect(p2.dx, inInclusiveRange(zl, zr));
    expect(p2.dx, greaterThan(75)); // right of panel center
    expect(p2.dy, inInclusiveRange(zt, zb));
    // 3: below the zone bottom, near horizontal center
    expect(p3.dy, greaterThan(zb));
    expect(p3.dx, inInclusiveRange(zl, zr));
  });

  testWidgets('due up card: between innings the duel yields to the next batters',
      (tester) async {
    // Between innings ESPN drops batter/pitcher and dueUp lists the NEXT
    // half's batters (data presence, never a sport-name branch).
    final comp = Competition.fromJson({
      'id': '1',
      'layout': 'headToHead',
      'scoreKind': 'numeric',
      'competitorKind': 'team',
      'status': {
        'phase': 'live',
        'live': true,
        'period': 5,
        'shortDetail': 'Mid 5th',
      },
      'periods': {'unit': 'inning', 'regulation': 9, 'played': 5},
      'competitors': [
        {'id': '15', 'homeAway': 'home', 'team': {'abbreviation': 'ATL'}},
        {'id': '23', 'homeAway': 'away', 'team': {'abbreviation': 'PIT'}},
      ],
      'situation': {
        'balls': 0,
        'strikes': 0,
        'outs': 0,
        'dueUp': [
          {'name': 'D. Swanson', 'line': '1-3, K'},
          {'name': 'M. Amaya', 'line': '0-2'},
          {'name': 'P. Crow-Armstrong'},
        ],
      },
    });
    const recap = InningRecap(
      period: 5,
      half: 'top',
      teamAbbr: 'PIT',
      label: 'Top 5th',
      line: 'two runs on three hits',
      texts: [],
    );
    final card = situationCardFor(comp, recap: recap);
    expect(card, isA<DueUpCard>());
    await _pump(tester, card!);
    expect(find.text('DUE UP'), findsOneWidget); // CardLabel uppercases
    expect(find.text('Mid 5th'), findsOneWidget);
    expect(find.text('D. Swanson'), findsOneWidget);
    expect(find.text('1-3, K'), findsOneWidget);
    expect(find.text('P. Crow-Armstrong'), findsOneWidget);
    // the previous half's deterministic footer
    expect(find.text('TOP 5TH · PIT'), findsOneWidget);
    expect(find.text('two runs on three hits'), findsOneWidget);

    // The AI sentence supersedes the deterministic line when it has arrived.
    await _pump(
        tester,
        situationCardFor(comp,
            recap: recap, aiRecap: 'Pirates strike for two on three straight hits.')!);
    expect(find.text('two runs on three hits'), findsNothing);
    expect(find.text('Pirates strike for two on three straight hits.'),
        findsOneWidget);
  });

  testWidgets('due up card: mid at-bat (batter present) keeps the duel',
      (tester) async {
    // dueUp leads with the CURRENT batter mid at-bat — the duel stays.
    final sit = Map<String, dynamic>.from(_situation)
      ..['dueUp'] = [
        {'name': 'J. Mangum'},
        {'name': 'B. Lowe', 'line': '1-3, K'},
      ];
    final card = situationCardFor(_comp(sit));
    expect(card, isA<BaseballSituationCard>());
  });

  testWidgets('pitch strip: latest first, type + velocity', (tester) async {
    await _pump(tester, PitchStripCard(_liveAtBat()));
    expect(find.text('Strike 2 Foul'), findsOneWidget); // pitch 3, leftmost
    // pitch name + velocity are separate single-line texts so a long name
    // ('Four-seam FB') can never push the mph off the chip
    expect(find.text('Cutter'), findsOneWidget);
    expect(find.text('91 mph'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    // leftmost chip is the LATEST pitch (n=3)
    final three = tester.getTopLeft(find.text('3'));
    final one = tester.getTopLeft(find.text('1'));
    expect(three.dx, lessThan(one.dx));
  });
}
