import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scores/src/models.dart';
import 'package:scores/src/ui/stat_specs.dart';

void main() {
  group('stat parsing', () {
    test('percent gauge reads all three ESPN percent dialects', () {
      // soccer possession "52.4", NBA FG% "38.4" → whole-form percents
      expect(gaugeFraction(StatKind.percent, '52.4'), closeTo(0.524, 1e-9));
      expect(gaugeFraction(StatKind.percent, '38.4'), closeTo(0.384, 1e-9));
      // NHL save % ".909" → fraction-form percent
      expect(gaugeFraction(StatKind.percent, '.909'), closeTo(0.909, 1e-9));
    });

    test('fraction01 (rugby possession "0.440") gauges and displays as %', () {
      expect(gaugeFraction(StatKind.fraction01, '0.440'), closeTo(0.44, 1e-9));
      const spec =
          StatSpec('possession', 'Possession', kind: StatKind.fraction01);
      expect(displayValue(spec, '0.440'), '44%');
      expect(displayValue(spec, '0.845'), '84.5%');
    });

    test('whole-form percents get their sign back; fraction-form stay raw', () {
      const poss = StatSpec('PP', 'Possession', kind: StatKind.percent);
      expect(displayValue(poss, '52.4'), '52.4%');
      const sv = StatSpec('SV%', 'Save %', kind: StatKind.percent);
      expect(displayValue(sv, '.909'), '.909');
    });

    test('ratios and clocks parse', () {
      expect(ratioParts('4-16'), (made: 4.0, att: 16.0));
      expect(ratioParts('19/38'), (made: 19.0, att: 38.0));
      expect(gaugeFraction(StatKind.ratio, '4-16'), closeTo(0.25, 1e-9));
      expect(clockSeconds('33:11'), 1991);
      expect(clockSeconds('4-16'), isNull);
    });
  });

  group('rich row classification', () {
    TeamStatRow row(String label, String away, String home) =>
        TeamStatRow(label: label, away: away, home: home);

    test('conversion ratios, clocks, percents and inversions are recognized',
        () {
      expect(classifyRichRow(row('3rd down efficiency', '4-16', '6-15')).kind,
          StatKind.ratio);
      expect(classifyRichRow(row('Possession', '33:11', '26:49')).kind,
          StatKind.clock);
      expect(classifyRichRow(row('Field Goal %', '45.5', '41.2')).kind,
          StatKind.percent);
      // "Penalties 4-25" is count-and-yards, NOT a conversion ratio.
      expect(classifyRichRow(row('Penalties', '4-25', '3-25')).kind,
          StatKind.count);
      expect(classifyRichRow(row('Turnovers', '0', '3')).invert, isTrue);
      expect(classifyRichRow(row('Total Yards', '335', '331')).invert, isFalse);
    });

    test('curation floats the fan-order lead stats, shortest label wins', () {
      final rows = [
        row('1st Downs', '20', '18'),
        row('Passing 1st downs', '11', '14'),
        row('3rd down efficiency', '4-16', '6-15'),
        row('Total Yards', '335', '331'),
        row('Passing', '194', '252'),
        row('Total Drives', '13', '15'),
        row('Turnovers', '0', '3'),
        row('Possession', '33:11', '26:49'),
      ];
      final (:lead, :rest) = curateRichRows(rows, 'football');
      expect(lead.first.label, 'Total Yards');
      // 'passing' picks the plain "Passing" row, not "Passing 1st downs".
      expect(lead.map((r) => r.label), contains('Passing'));
      expect(lead.map((r) => r.label), isNot(contains('Passing 1st downs')));
      expect(rest.map((r) => r.label), contains('Total Drives'));
    });

    test('no keywords → first N rows lead in ESPN order', () {
      final rows = [
        for (var i = 0; i < 12; i++) row('Stat $i', '$i', '$i'),
      ];
      final (:lead, :rest) = curateRichRows(rows, 'tennis', fallbackCap: 8);
      expect(lead.length, 8);
      expect(lead.first.label, 'Stat 0');
      expect(rest.length, 4);
    });
  });

  group('StatCompareRow rendering', () {
    Future<void> pump(WidgetTester tester, List<Widget> rows) =>
        tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Column(mainAxisAlignment: MainAxisAlignment.center, children: rows),
          ),
        ));

    testWidgets('cheap basketball panel restores percent sign + shows counts',
        (tester) async {
      final away = {'FG%': '38.4', 'REB': '47'};
      final home = {'FG%': '35.6', 'REB': '48'};
      final panel = cheapStatPanels['basketball']!;
      await pump(tester, [
        for (final spec in panel.rows)
          if (away[spec.key] != null || home[spec.key] != null)
            StatCompareRow(
                spec: spec, away: away[spec.key], home: home[spec.key]),
      ]);
      expect(find.text('Field goals'), findsOneWidget);
      expect(find.text('38.4%'), findsOneWidget); // sign restored
      expect(find.text('Rebounds'), findsOneWidget);
      expect(find.text('47'), findsOneWidget);
    });

    testWidgets('classified rich ratio row displays raw made-of-attempts',
        (tester) async {
      final r = TeamStatRow(label: '3rd down efficiency', away: '4-16', home: '6-15');
      await pump(tester, [
        StatCompareRow(spec: classifyRichRow(r), away: r.away, home: r.home),
      ]);
      expect(find.text('4-16'), findsOneWidget);
      expect(find.text('6-15'), findsOneWidget);
      expect(find.text('3rd down efficiency'), findsOneWidget);
    });
  });
}
