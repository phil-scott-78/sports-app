import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scores/src/models.dart';
import 'package:scores/src/theme.dart';
import 'package:scores/src/ui/standings_table.dart';

// Soccer qualification bands (§2.7/2.8): the 3px colour band on a row + the tag
// legend under the group card, driven by StandingsRow.note {color, description}.

StandingsRow _row(String name, int rank, {String? color, String? desc}) =>
    StandingsRow.fromJson({
      'team': {'id': '$rank', 'name': name},
      'rank': rank,
      'stats': {'points': '${40 - rank}'},
      if (color != null || desc != null)
        'note': {
          if (color != null) 'color': color,
          if (desc != null) 'description': desc,
        },
    });

Widget _wrap(List<StandingsRow> rows) => MaterialApp(
      theme: buildV2Theme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: StandingsGroupCard(
            name: 'Premier League',
            rows: rows,
            columns: [StandingColumn(key: 'points', label: 'PTS')],
          ),
        ),
      ),
    );

void main() {
  testWidgets('note bands render one legend entry per distinct description',
      (tester) async {
    await tester.pumpWidget(_wrap([
      _row('Arsenal', 1, color: '#81D6AC', desc: 'Champions League'),
      _row('Chelsea', 2, color: '#81D6AC', desc: 'Champions League'),
      _row('Everton', 19, color: '#FF7F84', desc: 'Relegation'),
      _row('Fulham', 10), // no band
    ]));
    await tester.pump();

    // legend dedupes identical descriptions (Champions League appears once)
    expect(find.text('Champions League'), findsOneWidget);
    expect(find.text('Relegation'), findsOneWidget);
  });

  testWidgets('no bands → no legend', (tester) async {
    await tester.pumpWidget(_wrap([
      _row('Arsenal', 1),
      _row('Chelsea', 2),
    ]));
    await tester.pump();

    expect(find.text('Champions League'), findsNothing);
    expect(find.text('Relegation'), findsNothing);
  });

  test('tolerant hex parse: double-hash and bad values', () {
    // The model keeps the raw string; the UI parser tolerates '##c6d1e0'.
    final r = StandingsRow.fromJson({
      'team': {'id': '1', 'name': 'X'},
      'stats': const {},
      'note': {'color': '##c6d1e0', 'description': 'Playoff'},
    });
    expect(r.note?.color, '##c6d1e0');
    expect(r.note?.description, 'Playoff');
  });
}
