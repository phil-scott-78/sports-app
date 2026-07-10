import 'package:flutter_test/flutter_test.dart';
import 'package:scores/src/models.dart';
import 'package:scores/src/momentum.dart';

MatchFeedPlay p(String type,
        {String? side,
        num? sec,
        num? x,
        num? y,
        num? x2,
        String? id,
        String? text,
        String? shortText}) =>
    MatchFeedPlay(
        id: id ?? 'x',
        type: type,
        side: side,
        sec: sec,
        x: x,
        y: y,
        x2: x2,
        text: text,
        shortText: shortText);

void main() {
  group('momentumBuckets', () {
    test('shots weigh 1.0, normalize to the loudest minute', () {
      final b = momentumBuckets([
        p('Shot On Target', side: 'home', sec: 65, x: 90),
        p('Shot Off Target', side: 'home', sec: 70, x: 88),
        p('Shot Blocked', side: 'away', sec: 130, x: 85),
      ]);
      expect(b.length, 90); // KO→FT axis stays full-width
      // minute 1 has two home shots → the peak; minute 2 one away shot.
      expect(b[1].home, 1.0);
      expect(b[2].away, 0.5);
      expect(b[2].home, 0.0);
    });

    test('deep open play counts, own-half possession does not', () {
      final b = momentumBuckets([
        p('Pass', side: 'home', sec: 30, x: 95), // deep attack
        p('Pass', side: 'home', sec: 30, x: 30), // own half — no pressure
        p('Shot On Target', side: 'away', sec: 90, x: 80),
      ]);
      expect(b[0].home, greaterThan(0));
      expect(b[0].home, lessThan(1.0)); // a deep pass never outweighs a shot
      expect(b[1].away, 1.0);
    });

    test('empty/quiet feeds produce no chart', () {
      expect(momentumBuckets(const []), isEmpty);
      expect(momentumBuckets([p('Pass', side: 'home', sec: 10, x: 20)]),
          isEmpty);
    });

    test('extra time grows the axis past 90', () {
      final b = momentumBuckets(
          [p('Goal', side: 'home', sec: 100 * 60 + 30, x: 95)]);
      expect(b.length, 101);
    });
  });

  group('trailingPossession', () {
    test('collects consecutive same-side coordful plays, newest last', () {
      final plays = [
        p('Pass', id: 'a', side: 'away', sec: 10, x: 40, y: 50),
        p('Pass', id: 'b', side: 'home', sec: 20, x: 50, y: 40),
        p('Pass', id: 'c', side: 'home', sec: 25, x: 60, y: 30),
        p('Cross', id: 'd', side: 'home', sec: 30, x: 80, y: 20, x2: 92),
      ];
      final trail = trailingPossession(plays);
      expect(trail.map((e) => e.id), ['b', 'c', 'd']);
    });

    test('a side change breaks the trail', () {
      final trail = trailingPossession([
        p('Pass', id: 'a', side: 'home', sec: 10, x: 40),
        p('Interception', id: 'b', side: 'away', sec: 12, x: 55),
        p('Pass', id: 'c', side: 'away', sec: 15, x: 60),
      ]);
      expect(trail.map((e) => e.id), ['b', 'c']);
    });
  });

  group('shot lenses', () {
    test('matchShots filters the shot family only', () {
      final shots = matchShots([
        p('Pass', side: 'home'),
        p('Goal', side: 'home'),
        p('Penalty - Saved', side: 'home'),
        p('Save', side: 'away'), // keeper event, not an attempt
        p('Assists Shot', side: 'home'), // companion event, not an attempt
      ]);
      expect(shots.map((s) => s.type), ['Goal', 'Penalty - Saved']);
    });

    test('shotOutcome buckets the family', () {
      expect(shotOutcome(p('Goal')), 'goal');
      expect(shotOutcome(p('Penalty - Saved')), 'saved');
      expect(shotOutcome(p('Shot Blocked')), 'blocked');
      expect(shotOutcome(p('Shot Off Target')), 'off');
    });

    test('technique and situation parse from prose', () {
      final shot = p('Shot Blocked',
          text:
              'Attempt blocked. Désiré Doué (France) right footed shot from outside the box is blocked.');
      expect(shotTechnique(shot), 'Right foot');
      expect(shotSituation(shot), 'Open play');
      expect(shotSituation(p('Penalty - Saved', text: 'Penalty saved.')),
          'Penalty');
    });

    test('yardsToGoal: the penalty spot reads ~12-13 yds', () {
      // ESPN pins penalties at x≈88.5, y≈50 → 12 yds in reality.
      final yds = yardsToGoal(88.5, 50);
      expect(yds, inInclusiveRange(11, 14));
    });
  });

  group('restarts', () {
    test('matchRestarts excludes kickoff, keeps throw-ins/corners', () {
      final r = matchRestarts([
        p('Kickoff', side: 'home'),
        p('Throw In', side: 'home'),
        p('Corner Awarded', side: 'away'),
        p('Pass', side: 'home'),
      ]);
      expect(r.map((e) => e.type), ['Throw In', 'Corner Awarded']);
    });

    test('possessionState flips between restart label and open play', () {
      expect(possessionState(p('Throw In')), 'THROW-IN');
      expect(possessionState(p('Pass')), 'OPEN PLAY');
    });
  });
}
