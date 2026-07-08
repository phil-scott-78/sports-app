import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scores/src/models.dart';
import 'package:scores/src/theme.dart';
import 'package:scores/src/ui/situations.dart';

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

    // Hockey power play — dispatched on situation.powerPlay/strength (Track B).
    final hockey = Competition.fromJson({
      'id': '5',
      'layout': 'headToHead',
      'scoreKind': 'numeric',
      'competitorKind': 'team',
      'status': {'phase': 'in', 'live': true, 'ended': false},
      'periods': {'unit': 'period', 'regulation': 3, 'played': 2},
      'competitors': [
        {'kind': 'team', 'id': '17', 'abbreviation': 'CAR', 'homeAway': 'home'},
        {'kind': 'team', 'id': '22', 'abbreviation': 'VGK', 'homeAway': 'away'},
      ],
      'situation': {
        'powerPlay': true,
        'strength': 'power-play',
        'strengthTeam': '17',
      },
    });
    expect(situationCardFor(hockey).runtimeType.toString(),
        'PowerPlaySituationCard');

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

  group('MatchTimelineCard Now-card curation (design 6a)', () {
    // A live 2nd-half soccer match with a busy timeline: seven goals and a red
    // card plus a yellow, chronological (oldest first) as the cheap feed ships.
    Competition timeline(List<Map<String, dynamic>> events,
            {bool live = true}) =>
        Competition.fromJson({
          'id': 'T1',
          'layout': 'headToHead',
          'scoreKind': 'numeric',
          'competitorKind': 'team',
          'status': {
            'phase': live ? 'in' : 'final',
            'live': live,
            'ended': !live,
            'period': 2,
            'detail': live ? "62'" : 'FT',
          },
          'periods': {
            'unit': 'half',
            'regulation': 2,
            'played': 2,
            'lengthMin': 45,
          },
          'competitors': [
            {'kind': 'team', 'id': 'a', 'abbreviation': 'ARS', 'homeAway': 'away'},
            {'kind': 'team', 'id': 'h', 'abbreviation': 'CHE', 'homeAway': 'home'},
          ],
          'events': events,
        });

    Map<String, dynamic> goal(int min, String who) => {
          'type': 'goal',
          'team': 'away',
          'clock': "$min'",
          'athlete': who,
          'detail': 'Goal',
        };

    Future<void> pump(WidgetTester tester, Competition comp) =>
        tester.pumpWidget(MaterialApp(
          theme: buildV2Theme(),
          home: Scaffold(body: MatchTimelineCard(comp)),
        ));

    testWidgets(
        'lists ALL goals + red cards newest-first, caps at 5, drops yellows',
        (tester) async {
      final comp = timeline([
        goal(10, 'Ten'),
        goal(20, 'Twenty'),
        {'type': 'yellow-card', 'team': 'home', 'clock': "25'", 'athlete': 'Booked'},
        goal(30, 'Thirty'),
        goal(40, 'Forty'),
        goal(50, 'Fifty'),
        goal(60, 'Sixty'),
        {'type': 'red-card', 'team': 'home', 'clock': "70'", 'athlete': 'Sent', 'detail': 'Red Card'},
      ]);
      await pump(tester, comp);

      // Signal events newest-first, capped at 5: red(70), 60, 50, 40, 30.
      expect(find.text('Sent — Red Card'), findsOneWidget);
      expect(find.text('Sixty — Goal'), findsOneWidget);
      expect(find.text('Thirty — Goal'), findsOneWidget);
      // The two oldest goals fall past the cap of 5; the yellow is not a signal.
      expect(find.text('Twenty — Goal'), findsNothing);
      expect(find.text('Ten — Goal'), findsNothing);
      expect(find.text('Booked — yellow-card'), findsNothing);

      // Newest first: the 70' red card sits above the 30' goal.
      final redY = tester.getTopLeft(find.text('Sent — Red Card')).dy;
      final oldGoalY = tester.getTopLeft(find.text('Thirty — Goal')).dy;
      expect(redY, lessThan(oldGoalY));
    });

    testWidgets('falls back to the last 3 events when nothing signal-worthy',
        (tester) async {
      // Only yellow cards (no goals, no reds) → the tail-of-3 fallback.
      final comp = timeline([
        for (var i = 1; i <= 6; i++)
          {'type': 'yellow-card', 'team': 'home', 'clock': "${i * 10}'", 'athlete': 'Y$i'},
      ]);
      await pump(tester, comp);
      expect(find.text('Y6 — yellow-card'), findsOneWidget);
      expect(find.text('Y5 — yellow-card'), findsOneWidget);
      expect(find.text('Y4 — yellow-card'), findsOneWidget);
      // Only the last 3 — earlier bookings stay on the rail, not in the list.
      expect(find.text('Y3 — yellow-card'), findsNothing);
    });

    testWidgets('stoppage-time markers clamp onto the rail, never past the edge',
        (tester) async {
      // A goal at 90'+8 — its minute (98) is past regulation (90). The rail
      // marker must clamp into the last sliver, not hang off the right edge.
      final comp = timeline([goal(30, 'Early'), {
        'type': 'goal',
        'team': 'away',
        'clock': "90'+8",
        'athlete': 'Late',
        'detail': 'Goal',
      }]);
      await pump(tester, comp);

      final track =
          tester.getRect(find.byKey(const ValueKey('timelineTrack')));
      final markerRect =
          tester.getRect(find.byKey(const ValueKey("railMarker:90'+8")));
      // Fully on the rail: right edge at/inside the track, pushed to the end.
      expect(markerRect.right, lessThanOrEqualTo(track.right + 0.5));
      expect(markerRect.left, greaterThan(track.center.dx));
    });
  });

  group('matchRowContext (home-feed soccer context off the cheap timeline)', () {
    Competition soccer(List<Map<String, dynamic>> events) =>
        Competition.fromJson({
          'id': '9',
          'layout': 'headToHead',
          'scoreKind': 'numeric',
          'competitorKind': 'team',
          'status': {'phase': 'in', 'live': true, 'ended': false},
          'periods': {'unit': 'half', 'regulation': 2, 'played': 2},
          'competitors': [
            {'kind': 'team', 'id': 'e', 'abbreviation': 'ENG', 'homeAway': 'away'},
            {'kind': 'team', 'id': 'n', 'abbreviation': 'NED', 'homeAway': 'home'},
          ],
          'events': events,
        });

    test('leads with man-down; goalFirst prefers the latest goal', () {
      final comp = soccer([
        {'type': 'goal', 'team': 'away', 'clock': "31'", 'athlete': 'Gakpo'},
        {
          'type': 'red-card',
          'team': 'home',
          'clock': "68'",
          'flags': {'redCard': true},
        },
      ]);
      expect(matchRowContext(comp), 'NED down to 10');
      expect(matchRowContext(comp, goalFirst: true), "Gakpo 31'");
    });

    test('falls back to the latest goal when no cards', () {
      final comp = soccer([
        {'type': 'goal', 'team': 'away', 'clock': "31'", 'athlete': 'Gakpo'},
      ]);
      expect(matchRowContext(comp), "Gakpo 31'");
    });

    test('null when the timeline is empty', () {
      expect(matchRowContext(soccer([])), isNull);
    });
  });
}
