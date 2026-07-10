// FastCast Track-1 wiring (fastcast-plan.md Phase 2): Api.liveSummary feeds the
// pushed gp doc — which is /summary-shaped — through the SAME normalizeSummary
// as the polled path, and Api.liveSummarySupported gates push by registry
// capability / mock mode / bespoke-summary sports.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scores/src/api.dart';
import 'package:scores/src/data/espn_client.dart';
import 'package:scores/src/data/fastcast_client.dart';
import 'package:scores/src/data/fastcast_log.dart';
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
      _push({'op': 'S', 'rc': 200, 'tc': tc});
      final cp = topicCheckpoint[tc];
      if (cp != null) _push({'op': 'H', 'pl': cp, 'mid': 1, 'tc': tc});
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

  test('liveSummarySupported: capability + mock-mode + bespoke-sport gates', () {
    final fc = FastcastClient(
        connector: () async => throw FastcastError('unused'),
        watchLifecycle: false);
    final api = Api('', null, fc);
    expect(api.liveSummarySupported('baseball/mlb'), isTrue);
    expect(api.liveSummarySupported('basketball/nba'), isTrue);
    // MMA/tennis summaries are bespoke (CORE-built / absent) — never push-fed.
    expect(api.liveSummarySupported('mma/ufc'), isFalse);
    expect(api.liveSummarySupported('tennis/atp'), isFalse);
    // No push client injected → polling only.
    expect(Api('').liveSummarySupported('baseball/mlb'), isFalse);
    // Mock mode (base override set) → polling only, through the mock.
    expect(Api('http://10.0.2.2:8787', null, fc)
        .liveSummarySupported('baseball/mlb'), isFalse);
    fc.dispose();
  });

  test('liveSummary: gp checkpoint normalizes through normalizeSummary', () async {
    // A minimal /summary-shaped gp doc — enough for normalizeSummary to emit a
    // real payload (boxscore team stats + header status).
    final gpDoc = {
      'header': {
        'id': '401',
        'competitions': [
          {
            'id': '401',
            'status': {
              'type': {'name': 'STATUS_IN_PROGRESS', 'state': 'in'},
              'period': 3,
            },
          },
        ],
      },
      'boxscore': {
        'teams': [
          {
            'team': {'id': '10', 'displayName': 'Yankees'},
            'homeAway': 'away',
            'statistics': [
              {'name': 'hits', 'displayValue': '7', 'label': 'Hits'},
            ],
          },
          {
            'team': {'id': '9', 'displayName': 'Red Sox'},
            'homeAway': 'home',
            'statistics': [
              {'name': 'hits', 'displayValue': '4', 'label': 'Hits'},
            ],
          },
        ],
      },
    };
    final conn = FakeConn({'gp-baseball-mlb-401': 'http://cp/gp'});
    final fc = FastcastClient(
      connector: () async => conn,
      fetchJson: (url) async => jsonDecode(jsonEncode(gpDoc)),
      throttle: Duration.zero,
      watchLifecycle: false,
    );
    // Mocked EspnClient: the live CORE enrichments that ride each emission
    // (situation/predictor) must never reach a real network from a test.
    final espn =
        EspnClient('', MockClient((req) async => http.Response('nope', 404)));
    final api = Api('', espn, fc);
    final summary = await api.liveSummary('baseball/mlb', '401').first;
    expect(summary.live, isTrue);
    expect(summary.teamStats, isNotEmpty);
    fc.dispose();
  });
}
