// Track-2 overlay merge (fastcast-plan.md Phase 3): mergeFastcastSlate updates
// a canonical normalized scoreboard in place of nothing but what push carries —
// status/score/winner/situation/seriesSummary and the derived decision /
// periods / anyLive / nextStartMs. Dart-only (no JS oracle — downstream of
// canonical); the canonical INPUT here is real normalizeScoreboard output so
// the merge is exercised against the true shape.
import 'package:flutter_test/flutter_test.dart';
import 'package:scores/src/data/fastcast_merge.dart';
import 'package:scores/src/data/normalize.dart';
import 'package:scores/src/data/profiles.dart';
import 'golden_util.dart';

Map<String, dynamic> rawScoreboard() => {
      'leagues': [
        {'slug': 'nba', 'id': '46', 'name': 'NBA'},
      ],
      'events': [
        {
          'id': '1',
          'date': '2026-07-08T19:00Z',
          'name': 'A at B',
          'shortName': 'A @ B',
          'competitions': [
            {
              'id': '1',
              'status': {
                'type': {
                  'name': 'STATUS_IN_PROGRESS',
                  'state': 'in',
                  'detail': '2nd Quarter',
                  'shortDetail': 'Q2 5:00',
                  'altDetail': 'ALT',
                },
                'period': 2,
                'displayClock': '5:00',
              },
              'competitors': [
                {
                  'id': '10',
                  'homeAway': 'home',
                  'score': '30',
                  'team': {'id': '10', 'displayName': 'Home Team'},
                },
                {
                  'id': '11',
                  'homeAway': 'away',
                  'score': '28',
                  'team': {'id': '11', 'displayName': 'Away Team'},
                },
              ],
            },
          ],
        },
        {
          'id': '2',
          'date': '2099-01-01T00:00Z',
          'name': 'C at D',
          'shortName': 'C @ D',
          'competitions': [
            {
              'id': '2',
              'status': {
                'type': {'name': 'STATUS_SCHEDULED', 'state': 'pre'},
                'period': 0,
              },
              'competitors': [
                {'id': '20', 'homeAway': 'home', 'score': '0'},
                {'id': '21', 'homeAway': 'away', 'score': '0'},
              ],
            },
          ],
        },
      ],
    };

Map<String, dynamic> overlayEvent(Map<String, dynamic> patch) => {
      'key': 'basketball/nba',
      'events': [
        {
          'id': '1',
          'status': {
            'phase': 'in',
            'live': true,
            'ended': false,
            'period': 3,
            'periodLabel': 'Q3 8:12',
            'espnName': 'STATUS_IN_PROGRESS',
            'detail': '3rd Quarter',
            'shortDetail': 'Q3 8:12',
            'clock': '8:12',
          },
          'competitors': [
            {'id': '10', 'homeAway': 'home', 'score': {'display': '55', 'value': 55}},
            {'id': '11', 'homeAway': 'away', 'score': {'display': '51', 'value': 51}},
          ],
          ...patch,
        },
      ],
    };

void main() {
  late Registry reg;
  late Map profile;
  setUpAll(() {
    reg = loadTestRegistry();
    profile = resolve(reg, 'basketball/nba');
  });

  Map<String, dynamic> slate() =>
      normalizeScoreboard(reg, 'basketball/nba', rawScoreboard());

  Map comp0(Map<String, dynamic> s) =>
      ((s['events'] as List)[0] as Map)['competitions'][0] as Map;

  test('score/status/clock merge into the matching competition', () {
    final base = slate();
    final merged = mergeFastcastSlate(profile, base, overlayEvent({}));
    final c = comp0(merged);
    expect((c['status'] as Map)['shortDetail'], 'Q3 8:12');
    expect((c['status'] as Map)['clock'], '8:12');
    expect((c['status'] as Map)['period'], 3);
    // altDetail is poll-only — preserved across the pushed status.
    expect((c['status'] as Map)['altDetail'], 'ALT');
    final home = (c['competitors'] as List)
        .firstWhere((x) => (x as Map)['id'] == '10') as Map;
    expect((home['score'] as Map)['display'], '55');
    // The untouched scheduled game is untouched.
    final c2 = ((merged['events'] as List)[1] as Map)['competitions'][0] as Map;
    expect((c2['status'] as Map)['phase'], 'scheduled');
    // The INPUT slate was not mutated.
    expect((comp0(base)['status'] as Map)['period'], 2);
    expect(
        ((comp0(base)['competitors'] as List)[0] as Map)['score']['display'],
        '30');
  });

  test('pushed final recomputes decision + winner; anyLive follows', () {
    final base = slate();
    expect(base['anyLive'], true);
    final merged = mergeFastcastSlate(
        profile,
        base,
        overlayEvent({
          'status': {
            'phase': 'final',
            'live': false,
            'ended': true,
            'period': 4,
            'periodLabel': 'Final',
            'espnName': 'STATUS_FINAL',
            'detail': 'Final',
          },
          'competitors': [
            {'id': '10', 'winner': true, 'score': {'display': '101', 'value': 101}},
            {'id': '11', 'winner': false, 'score': {'display': '99', 'value': 99}},
          ],
        }));
    final c = comp0(merged);
    expect((c['status'] as Map)['ended'], true);
    expect(c['decision'], 'regulation');
    expect(merged['anyLive'], false);
    // The scheduled game (2099) still anchors nextStartMs.
    expect(merged['nextStartMs'], isNotNull);
  });

  test('overtime period bumps periods.played/isOvertime', () {
    final base = slate();
    final merged = mergeFastcastSlate(
        profile,
        base,
        overlayEvent({
          'status': {
            'phase': 'in',
            'live': true,
            'ended': false,
            'period': 5,
            'periodLabel': 'OT',
            'espnName': 'STATUS_IN_PROGRESS',
            'detail': 'Overtime',
          },
        }));
    final periods = comp0(merged)['periods'] as Map;
    expect(periods['played'], 5);
    expect(periods['isOvertime'], true);
  });

  test('situation replaces when pushed, survives when absent; series → meta',
      () {
    final base = slate();
    // Seed a polled situation.
    comp0(base)['situation'] = {'possessionText': 'old'};
    var merged = mergeFastcastSlate(
        profile,
        base,
        overlayEvent({
          'situation': {'balls': 2, 'strikes': 1},
          'seriesSummary': 'Series tied 1-1',
        }));
    expect(comp0(merged)['situation'], {'balls': 2, 'strikes': 1});
    expect((comp0(merged)['meta'] as Map)['seriesSummary'], 'Series tied 1-1');
    // No pushed situation → the polled one is kept.
    merged = mergeFastcastSlate(profile, base, overlayEvent({}));
    expect(comp0(merged)['situation'], {'possessionText': 'old'});
  });

  test('pushed situation keeps the polled onDeck (event docs carry no dueUp)',
      () {
    final base = slate();
    comp0(base)['situation'] = {'balls': 1, 'onDeck': 'B. Lowe'};
    var merged = mergeFastcastSlate(
        profile, base, overlayEvent({'situation': {'balls': 2, 'strikes': 1}}));
    expect(comp0(merged)['situation'],
        {'balls': 2, 'strikes': 1, 'onDeck': 'B. Lowe'});
    // ...but a pushed onDeck (future-proofing) wins over the stale one.
    merged = mergeFastcastSlate(profile, base,
        overlayEvent({'situation': {'balls': 0, 'onDeck': 'K. Stowers'}}));
    expect((comp0(merged)['situation'] as Map)['onDeck'], 'K. Stowers');
  });

  test('unmatched overlay events are ignored', () {
    final base = slate();
    final ov = {
      'key': 'basketball/nba',
      'events': [
        {
          'id': '999',
          'status': {'phase': 'in', 'live': true, 'ended': false, 'period': 1},
        },
      ],
    };
    final merged = mergeFastcastSlate(profile, base, ov);
    expect((comp0(merged)['status'] as Map)['period'], 2);
    expect(merged['anyLive'], base['anyLive']);
  });
}
