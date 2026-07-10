// Track-2 provider wiring end-to-end (fastcast-plan.md Phase 3): a fake
// FastCast socket serves an event-* checkpoint; liveSlateProvider normalizes
// it and mergedLeagueScoresProvider serves the polled slate WITH the pushed
// score/status merged in — no UI, real Api + providers.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scores/src/api.dart';
import 'package:scores/src/data/espn_client.dart';
import 'package:scores/src/data/fastcast_client.dart';
import 'package:scores/src/data/fastcast_log.dart';
import 'package:scores/src/providers.dart';
import 'golden_util.dart';

class FakeConn implements FastcastConnection {
  final _frames = StreamController<dynamic>();
  final Map<String, String> topicCheckpoint;
  FakeConn(this.topicCheckpoint);
  @override
  Stream<dynamic> get frames => _frames.stream;
  @override
  void send(String text) {
    final m = jsonDecode(text) as Map<String, dynamic>;
    if (m['op'] == 'C') _push({'op': 'C', 'rc': 200, 'sid': 's1'});
    if (m['op'] == 'S') {
      final tc = m['tc'] as String;
      final rc = topicCheckpoint.containsKey(tc) ? 200 : 404;
      _push({'op': 'S', 'rc': rc, 'tc': tc});
      if (rc == 200) _push({'op': 'H', 'pl': topicCheckpoint[tc], 'mid': 1, 'tc': tc});
    }
  }

  void _push(Map<String, dynamic> m) {
    if (!_frames.isClosed) _frames.add(jsonEncode(m));
  }

  @override
  Future<void> close() async {
    if (!_frames.isClosed) await _frames.close();
  }
}

void main() {
  FcLog.enabled = false; // keep the debug mirror out of test output
  setUpAll(loadTestRegistry);

  test('mergedLeagueScoresProvider serves the polled slate with push merged in',
      () async {
    // The polled scoreboard: one live NBA game, home 30 – away 28 in Q2.
    final mockHttp = MockClient((req) async {
      if (req.url.path.contains('/basketball/nba/scoreboard')) {
        return http.Response(
            jsonEncode({
              'leagues': [
                {'slug': 'nba', 'id': '46', 'name': 'NBA'},
              ],
              'events': [
                {
                  'id': '1',
                  'date': '2026-07-08T19:00Z',
                  'competitions': [
                    {
                      'id': '1',
                      'status': {
                        'type': {
                          'name': 'STATUS_IN_PROGRESS',
                          'state': 'in',
                          'shortDetail': 'Q2 5:00',
                        },
                        'period': 2,
                        'displayClock': '5:00',
                      },
                      'competitors': [
                        {'id': '10', 'homeAway': 'home', 'score': '30'},
                        {'id': '11', 'homeAway': 'away', 'score': '28'},
                      ],
                    },
                  ],
                },
              ],
            }),
            200);
      }
      return http.Response('nope', 404);
    });
    // The pushed event doc: the same game, now 55–51 in Q3.
    final eventDoc = {
      'sports': [
        {
          'leagues': [
            {
              'slug': 'nba',
              'id': '46',
              'events': [
                {
                  'id': '1',
                  'uid': 's:40~l:46~e:1',
                  'fullStatus': {
                    'type': {
                      'name': 'STATUS_IN_PROGRESS',
                      'state': 'in',
                      'shortDetail': 'Q3 8:12',
                      'detail': '3rd Quarter',
                    },
                    'period': 3,
                    'displayClock': '8:12',
                  },
                  'competitors': [
                    {'id': '10', 'homeAway': 'home', 'score': '55'},
                    {'id': '11', 'homeAway': 'away', 'score': '51'},
                  ],
                },
              ],
            },
          ],
        },
      ],
    };
    final conn = FakeConn({'event-basketball-nba': 'http://cp/nba'});
    final fastcast = FastcastClient(
      connector: () async => conn,
      fetchJson: (url) async => jsonDecode(jsonEncode(eventDoc)),
      throttle: Duration.zero,
      watchLifecycle: false,
    );
    final api = Api('', EspnClient('', mockHttp), fastcast);
    final container = ProviderContainer(overrides: [
      apiProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
    addTearDown(fastcast.dispose);

    const key = (league: 'basketball/nba', date: null);
    // Keep the merged provider (and its overlay subscription) alive.
    final sub = container.listen(mergedLeagueScoresProvider(key), (_, __) {});
    // The polled base lands first…
    final base = await container.read(leagueScoresProvider(key).future);
    expect(base.events.first.main!.competitors.first.score?.display,
        anyOf('30', '28'));
    // …then the push overlay flows through the socket → overlay → merge.
    await pumpEventQueue(times: 40);
    final merged = sub.read().valueOrNull;
    expect(merged, isNotNull);
    final comp = merged!.events.first.main!;
    expect(comp.status.shortDetail, 'Q3 8:12');
    expect(comp.status.clock, '8:12');
    final scores = {
      for (final c in comp.competitors) c.id: c.score?.display,
    };
    expect(scores['10'], '55');
    expect(scores['11'], '51');
  });

  test('a league without push (rc:404 topic) keeps serving the polled slate',
      () async {
    final mockHttp = MockClient((req) async {
      if (req.url.path.contains('/baseball/mlb/scoreboard')) {
        return http.Response(
            jsonEncode({
              'leagues': [
                {'slug': 'mlb', 'id': '10', 'name': 'MLB'},
              ],
              'events': [
                {
                  'id': '9',
                  'date': '2026-07-08T19:00Z',
                  'competitions': [
                    {
                      'id': '9',
                      'status': {
                        'type': {'name': 'STATUS_IN_PROGRESS', 'state': 'in'},
                        'period': 4,
                      },
                      'competitors': [
                        {'id': '1', 'homeAway': 'home', 'score': '2'},
                        {'id': '2', 'homeAway': 'away', 'score': '1'},
                      ],
                    },
                  ],
                },
              ],
            }),
            200);
      }
      return http.Response('nope', 404);
    });
    final conn = FakeConn(const {}); // every topic answers rc:404
    final fastcast = FastcastClient(
      connector: () async => conn,
      fetchJson: (url) async => throw FastcastError('no checkpoints'),
      throttle: Duration.zero,
      watchLifecycle: false,
    );
    final api = Api('', EspnClient('', mockHttp), fastcast);
    final container = ProviderContainer(overrides: [
      apiProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
    addTearDown(fastcast.dispose);

    const key = (league: 'baseball/mlb', date: null);
    final sub = container.listen(mergedLeagueScoresProvider(key), (_, __) {});
    await container.read(leagueScoresProvider(key).future);
    await pumpEventQueue(times: 40);
    final merged = sub.read().valueOrNull;
    expect(merged, isNotNull);
    expect(merged!.events.first.main!.competitors.map((c) => c.score?.display),
        containsAll(['2', '1']));
  });
}
