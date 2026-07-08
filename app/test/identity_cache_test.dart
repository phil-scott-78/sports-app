import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scores/src/data/identity_cache.dart';
import 'package:scores/src/models.dart';
import 'package:scores/src/theme.dart';
import 'package:scores/src/util.dart';
import 'package:scores/src/ui/standings_table.dart';
import 'package:scores/src/ui/widgets.dart';

// The team-identity assets cache (§3.1): a session-lived teamId → identity map
// warmed off scoreboard/teams payloads, plus the color-join + a11y helpers the
// color-less screens (standings, brackets) call.

void main() {
  final cache = IdentityCache.instance;
  setUp(cache.clear);

  group('deriveLogoDark', () {
    test('derives the /500-dark/ variant from a 500-px team logo', () {
      expect(
        deriveLogoDark('https://a.espncdn.com/i/teamlogos/nba/500/bos.png'),
        'https://a.espncdn.com/i/teamlogos/nba/500-dark/bos.png',
      );
    });
    test('null when the url is not a recognizable team-logo shape', () {
      expect(deriveLogoDark('https://a.espncdn.com/headshots/x.png'), isNull);
      expect(deriveLogoDark(null), isNull);
    });
  });

  group('put (merge)', () {
    test('non-empty fields never erase an earlier value', () {
      cache.put('7', color: 'cc0000', logo: 'l.png', abbreviation: 'BOS');
      // A color-less source (standings) adds nothing that would wipe color.
      cache.put('7', abbreviation: 'BOS');
      cache.put('7', color: '', logo: ''); // empties are ignored
      final id = cache['7']!;
      expect(id.color, 'cc0000');
      expect(id.logo, 'l.png');
      expect(id.abbreviation, 'BOS');
    });
    test('derives logoDark from the light logo when none supplied', () {
      cache.put('9', logo: 'https://a.espncdn.com/i/teamlogos/nhl/500/bos.png');
      expect(cache['9']!.logoDark, contains('/500-dark/'));
    });
    test('empty / null id is a no-op', () {
      cache.put('', color: 'fff');
      cache.put(null, color: 'fff');
      expect(cache.length, 0);
      expect(cache[null], isNull);
      expect(cache[''], isNull);
    });
  });

  group('warmScoreboard', () {
    test('warms team competitors, skips athletes and pairs', () {
      cache.warmScoreboard({
        'events': [
          {
            'competitions': [
              {
                'competitors': [
                  {'id': '1', 'kind': 'team', 'color': 'cc0000', 'abbreviation': 'BOS'},
                  {'id': '2', 'kind': 'team', 'color': '0000cc', 'logo': 'x.png'},
                  {'id': 'a99', 'kind': 'athlete', 'color': 'ffffff'},
                ],
              },
            ],
          },
        ],
      });
      expect(cache['1']!.color, 'cc0000');
      expect(cache['2']!.color, '0000cc');
      expect(cache['a99'], isNull, reason: 'athletes carry no club identity');
    });
    test('tolerates a malformed payload without throwing', () {
      cache.warmScoreboard(null);
      cache.warmScoreboard({'events': 'nope'});
      cache.warmScoreboard({'events': [<String, dynamic>{}]});
      expect(cache.length, 0);
    });
  });

  group('warmTeams', () {
    test('warms each /teams entry by id', () {
      cache.warmTeams([
        {'id': '5', 'color': '154734', 'abbreviation': 'PHI', 'logo': 'p.png'},
        {'id': '6', 'color': '004c54'},
      ]);
      expect(cache['5']!.color, '154734');
      expect(cache['5']!.abbreviation, 'PHI');
      expect(cache['6']!.color, '004c54');
    });
  });

  group('cachedTeamColor', () {
    test('joins a warmed color; null when unknown', () {
      cache.put('3', color: 'cc0000');
      expect(cachedTeamColor('3'), teamColorOf('cc0000'));
      expect(cachedTeamColor('missing'), isNull);
      expect(cachedTeamColor(null), isNull);
    });
  });

  group('colorsTooClose (a11y)', () {
    test('true for near-identical, false for clearly distinct', () {
      expect(colorsTooClose(const Color(0xFFCC0000), const Color(0xFFCE0402)),
          isTrue);
      expect(colorsTooClose(const Color(0xFFCC0000), const Color(0xFF0000CC)),
          isFalse);
    });
  });

  group('StandingsGroupCard rail (§3.1 consumer)', () {
    StandingsRow row(String id, String name) =>
        StandingsRow.fromJson({'team': {'id': id, 'name': name}, 'stats': {}});

    Widget wrap(Widget child) => MaterialApp(
        theme: buildV2Theme(), home: Scaffold(body: child));

    testWidgets('paints a team-color rail when the cache knows a team',
        (tester) async {
      cache.put('1', color: 'cc0000');
      await tester.pumpWidget(wrap(StandingsGroupCard(
        name: 'AL East',
        rows: [row('1', 'Red Sox'), row('2', 'Yankees')],
      )));
      final bars = tester.widgetList<ColorBar>(find.byType(ColorBar)).toList();
      // Two rows → two rails once the rail is enabled for the group.
      expect(bars.length, 2);
      expect(bars.any((b) => b.color == teamColorOf('cc0000')), isTrue);
      // The unknown team falls back to the neutral rail, not a wrong color.
      expect(bars.any((b) => b.color == T.border), isTrue);
    });

    testWidgets('no rail column when the cache knows none of the teams',
        (tester) async {
      await tester.pumpWidget(wrap(StandingsGroupCard(
        name: 'F1 Drivers',
        rows: [row('d1', 'Verstappen'), row('d2', 'Norris')],
      )));
      expect(find.byType(ColorBar), findsNothing);
    });
  });
}
