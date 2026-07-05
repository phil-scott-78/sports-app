import 'package:flutter_test/flutter_test.dart';
import 'package:scores_v2/src/models.dart';
import 'package:scores_v2/src/ui/situations.dart';

Competition gridiron({
  required String downDistanceText,
  required String possessionId,
  int? down,
  int? distance,
}) =>
    Competition.fromJson({
      'id': '1',
      'layout': 'headToHead',
      'scoreKind': 'numeric',
      'competitorKind': 'team',
      'status': {'phase': 'in', 'live': true, 'ended': false},
      'periods': {'unit': 'quarter', 'regulation': 4, 'played': 3},
      'competitors': [
        {
          'kind': 'team',
          'id': '201',
          'displayName': 'Oklahoma Sooners',
          'abbreviation': 'OU',
          'homeAway': 'away',
        },
        {
          'kind': 'team',
          'id': '251',
          'displayName': 'Texas Longhorns',
          'abbreviation': 'TEX',
          'homeAway': 'home',
        },
      ],
      'situation': {
        'downDistanceText': downDistanceText,
        'possession': possessionId,
        if (down != null) 'down': down,
        if (distance != null) 'distance': distance,
      },
    });

void main() {
  test('field position: ball in opponent territory', () {
    // TEX has the ball at the OU 22 → 78% of the way to the OU goal line.
    final comp = gridiron(
        downDistanceText: '3rd & 4 at OU 22',
        possessionId: '251',
        down: 3,
        distance: 4);
    final pos = fieldPosition(comp)!;
    expect(pos.ballPct, 78);
    expect(pos.sticksPct, 82);
  });

  test('field position: ball in own territory', () {
    final comp = gridiron(
        downDistanceText: '1st & 10 at TEX 25',
        possessionId: '251',
        down: 1,
        distance: 10);
    final pos = fieldPosition(comp)!;
    expect(pos.ballPct, 25);
    expect(pos.sticksPct, 35);
  });

  test('field position: unparseable text degrades to null, card still builds',
      () {
    final comp = gridiron(
        downDistanceText: '3rd & Goal', possessionId: '251', down: 3);
    expect(fieldPosition(comp), isNull);
    expect(situationCardFor(comp), isNotNull); // gridiron card, no field bar
  });

  test('situation dispatch is data-driven', () {
    final baseball = Competition.fromJson({
      'id': '2',
      'layout': 'headToHead',
      'scoreKind': 'numeric',
      'competitorKind': 'team',
      'status': {'phase': 'in', 'live': true, 'ended': false},
      'periods': {'unit': 'inning', 'regulation': 9, 'played': 7},
      'competitors': [],
      'situation': {'balls': 2, 'strikes': 1, 'outs': 2, 'onFirst': true},
    });
    expect(situationCardFor(baseball).runtimeType.toString(),
        'BaseballSituationCard');

    final soccer = Competition.fromJson({
      'id': '3',
      'layout': 'headToHead',
      'scoreKind': 'numeric',
      'competitorKind': 'team',
      'status': {'phase': 'in', 'live': true, 'ended': false},
      'periods': {'unit': 'half', 'regulation': 2, 'played': 2, 'lengthMin': 45},
      'competitors': [],
      'events': [
        {'type': 'goal', 'team': 'home', 'clock': "31'", 'athlete': 'Gakpo'},
      ],
    });
    expect(situationCardFor(soccer).runtimeType.toString(),
        'MatchTimelineCard');

    final idle = Competition.fromJson({
      'id': '4',
      'layout': 'headToHead',
      'scoreKind': 'numeric',
      'competitorKind': 'team',
      'status': {'phase': 'scheduled', 'live': false, 'ended': false},
      'periods': {'unit': 'quarter', 'regulation': 4, 'played': 0},
      'competitors': [],
    });
    expect(situationCardFor(idle), isNull);
  });
}
