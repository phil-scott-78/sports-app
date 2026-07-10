import 'package:flutter_test/flutter_test.dart';
import 'package:scores/src/lead_story.dart';
import 'package:scores/src/models.dart';

// ---- builders ---------------------------------------------------------------

SummaryPlay play(String side, num away, num home, {int? period, String? clock}) =>
    SummaryPlay.fromJson({
      'side': side,
      'away': away,
      'home': home,
      if (period != null) 'period': period,
      if (clock != null) 'clock': clock,
    });

Competition comp({int period = 4, String? clock = '4:12', int? lengthMin = 12}) =>
    Competition.fromJson({
      'id': '1',
      'layout': 'headToHead',
      'scoreKind': 'numeric',
      'competitorKind': 'team',
      'status': {
        'phase': 'in',
        'live': true,
        'ended': false,
        'period': period,
        'periodLabel': '4th Quarter',
        'espnName': 'STATUS_IN_PROGRESS',
        'detail': '',
        if (clock != null) 'clock': clock,
      },
      'periods': {
        'unit': 'quarter',
        'regulation': 4,
        'played': period,
        'isOvertime': false,
        if (lengthMin != null) 'lengthMin': lengthMin,
      },
      'competitors': [
        {
          'kind': 'team',
          'id': '10',
          'displayName': 'Thunder',
          'abbreviation': 'OKC',
          'homeAway': 'home',
        },
        {
          'kind': 'team',
          'id': '20',
          'displayName': 'Cavaliers',
          'abbreviation': 'CLE',
          'homeAway': 'away',
        },
      ],
    });

void main() {
  group('run detection', () {
    test('unanswered run gets the gold callout with its span', () {
      final plays = [
        play('away', 2, 0),
        play('home', 2, 2),
        play('away', 4, 2),
        play('away', 6, 2), // two straight away buckets fence the window
        play('home', 6, 5, period: 4, clock: '6:52'),
        play('home', 6, 7, period: 4, clock: '5:30'),
        play('home', 6, 9, period: 4, clock: '4:40'),
      ];
      final slot = leadSlotFor(comp(), plays)!;
      expect(slot.text, 'OKC 7–0 RUN');
      expect(slot.caption, 'last 2:40'); // 6:52 → 4:12, same quarter
      expect(slot.loud, isTrue);
    });

    test('a small answer keeps the run alive (9–2)', () {
      final plays = [
        play('away', 2, 0),
        play('home', 2, 2),
        play('away', 4, 2),
        play('home', 4, 4),
        play('away', 6, 4),
        play('home', 6, 7, period: 4, clock: '7:10'), // run starts
        play('home', 6, 10, period: 4, clock: '6:20'),
        play('away', 8, 10, period: 4, clock: '5:40'), // the 2-pt answer
        play('home', 8, 13, period: 4, clock: '4:50'),
      ];
      final slot = leadSlotFor(comp(), plays)!;
      expect(slot.text, 'OKC 9–2 RUN');
      expect(slot.caption, 'last 2:58'); // 7:10 → 4:12
      expect(slot.loud, isTrue);
    });

    test('a big answer (>4 pts) kills the run', () {
      final plays = [
        play('away', 2, 0),
        play('home', 2, 2),
        play('away', 4, 2),
        play('home', 4, 4),
        play('home', 4, 7),
        play('home', 4, 10),
        play('away', 9, 10), // 5 straight back — no live run either way
        play('home', 9, 12),
      ];
      final slot = leadSlotFor(comp(), plays);
      expect(slot?.loud ?? false, isFalse);
    });

    test('run spanning a quarter break bridges with the period length', () {
      final plays = [
        play('away', 2, 0),
        play('home', 2, 2),
        play('away', 4, 2),
        play('away', 6, 2),
        play('home', 6, 5, period: 3, clock: '1:00'),
        play('home', 6, 7, period: 4, clock: '11:00'),
        play('home', 6, 9, period: 4, clock: '10:30'),
      ];
      final slot = leadSlotFor(comp(period: 4, clock: '10:00'), plays)!;
      expect(slot.text, 'OKC 7–0 RUN');
      // 1:00 left in Q3 + (12:00 − 10:00) gone in Q4 = 3:00
      expect(slot.caption, 'last 3:00');
    });

    test('missing clocks drop the span, not the callout', () {
      final plays = [
        play('away', 2, 0),
        play('home', 2, 2),
        play('away', 4, 2),
        play('away', 6, 2),
        play('home', 6, 5),
        play('home', 6, 8),
      ];
      final slot = leadSlotFor(comp(), plays)!;
      expect(slot.text, 'OKC 6–0 RUN');
      expect(slot.caption, isNull);
    });
  });

  group('tidbits when no run is on', () {
    test('a back-and-forth game reads lead changes', () {
      final plays = [
        play('home', 0, 2), // home ahead
        play('away', 2, 2), // level
        play('away', 4, 2), // change 1
        play('home', 4, 5), // change 2
        play('away', 7, 5), // change 3
        play('home', 7, 8), // change 4
        play('away', 10, 8), // change 5
      ];
      final slot = leadSlotFor(comp(), plays)!;
      expect(slot.loud, isFalse);
      expect(slot.text, '5 LEAD CHANGES');
      expect(slot.caption, 'tied once');
    });

    test('ties story when the game keeps coming back level', () {
      final plays = [
        play('home', 0, 2),
        play('away', 2, 2), // tie 1
        play('home', 2, 4),
        play('away', 4, 4), // tie 2
        play('home', 4, 6),
        play('away', 6, 6), // tie 3
        play('home', 6, 8),
        play('away', 8, 8), // tie 4
      ];
      final slot = leadSlotFor(comp(), plays)!;
      expect(slot.loud, isFalse);
      expect(slot.text, 'TIED 4 TIMES');
      expect(slot.caption, isNull); // no lead changes to mention
    });

    test('wire to wire in the second half', () {
      final plays = [
        play('home', 0, 2),
        play('home', 0, 4),
        play('away', 2, 4),
        play('home', 2, 6),
        play('away', 4, 6),
        play('home', 4, 8),
        play('away', 6, 8),
        play('home', 6, 10),
        play('away', 8, 10), // trails all game, never level
      ];
      final slot = leadSlotFor(comp(period: 4), plays)!;
      expect(slot.text, 'WIRE TO WIRE');
      expect(slot.caption, 'OKC never trailed');
    });

    test('wire to wire stays quiet before the second half', () {
      final plays = [
        play('home', 0, 2),
        play('home', 0, 4),
        play('away', 2, 4),
        play('home', 2, 6),
        play('away', 4, 6),
        play('home', 4, 8),
        play('away', 6, 8),
        play('home', 6, 10),
        play('away', 8, 10),
      ];
      expect(leadSlotFor(comp(period: 2), plays), isNull);
    });

    test('nothing worth saying → null (clock stands alone)', () {
      final plays = [
        play('home', 0, 3),
        play('away', 4, 3), // change 1
        play('home', 4, 6), // change 2
        play('away', 6, 6), // tie 1
        play('home', 6, 8),
        play('away', 8, 8), // tie 2
        play('home', 8, 10),
      ];
      expect(leadSlotFor(comp(), plays), isNull);
    });

    test('too few scored plays → null', () {
      expect(leadSlotFor(comp(), [play('home', 0, 2), play('home', 0, 4)]),
          isNull);
    });
  });
}
