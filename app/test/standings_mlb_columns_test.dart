import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scores/src/models.dart';
import 'package:scores/src/theme.dart';
import 'package:scores/src/ui/standings_table.dart';

// Regression (Phase-6 walk): the MLB Division view rendered only ~2 of its 6
// values — a well-formed row must fill W / L / PCT (L10 / DIV may be blank
// off-season). Guards the column-key → stats join for the baseball/mlb columns.

// The baseball/mlb standingsColumns from schema/league-profiles.json.
final _mlbColumns = [
  StandingColumn(key: 'wins', label: 'W'),
  StandingColumn(key: 'losses', label: 'L'),
  StandingColumn(key: 'winPercent', label: 'PCT'),
  StandingColumn(key: 'gamesBehind', label: 'GB'),
  StandingColumn(key: 'l10', label: 'L10'),
  StandingColumn(key: 'div', label: 'DIV'),
];

// A golden-shaped MLB division row (the shape a complete/repaired standings entry
// carries — cf. the NBA/NFL/college-baseball goldens, which all ship wins +
// winPercent). L10 / DIV omitted to model the off-season sub-record gap.
StandingsRow _mlbRow() => StandingsRow.fromJson({
      'team': {'id': '30', 'name': 'Tampa Bay Rays', 'abbr': 'TB'},
      'rank': 1,
      'stats': {
        'wins': '53',
        'losses': '36',
        'winPercent': '0.596',
        'gamesBehind': '-',
      },
    });

Widget _wrap() => MaterialApp(
      theme: buildV2Theme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: StandingsGroupCard(
            name: 'AL East',
            rows: [_mlbRow()],
            columns: _mlbColumns,
          ),
        ),
      ),
    );

void main() {
  testWidgets('MLB division row renders W, L, PCT (+ GB), off-season L10/DIV blank',
      (tester) async {
    await tester.pumpWidget(_wrap());

    // The team + the three core values that were blank in the walk must all show.
    expect(find.text('Tampa Bay Rays'), findsOneWidget);
    expect(find.text('53'), findsOneWidget); // W
    expect(find.text('36'), findsOneWidget); // L
    expect(find.text('0.596'), findsOneWidget); // PCT
    expect(find.text('-'), findsOneWidget); // GB

    // All six headers are present (the table shows the full column set).
    for (final label in ['W', 'L', 'PCT', 'GB', 'L10', 'DIV']) {
      expect(find.text(label), findsOneWidget, reason: 'missing $label header');
    }
  });
}
