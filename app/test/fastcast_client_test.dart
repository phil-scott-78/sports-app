// FastCast client state-machine tests (fastcast-plan.md Phase 2). The socket
// and checkpoint GET are injected fakes, so the whole flow — C handshake, S
// subscribe, H checkpoint, coalesced P/R patch application, rc:404 fallback,
// resync-on-apply-failure, disconnect → reconnect — runs without a network.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scores/src/data/fastcast_client.dart';
import 'package:scores/src/data/fastcast_log.dart';

/// A scripted FastCast server on the other end of a fake socket: acks the C
/// handshake, acks each S per [topicRc], and follows a 200 with an H frame
/// naming the topic's checkpoint URL (when one is scripted).
class FakeConn implements FastcastConnection {
  final _frames = StreamController<dynamic>();
  final sent = <Map<String, dynamic>>[];
  final Map<String, int> topicRc;
  final Map<String, String> topicCheckpoint;
  bool closed = false;

  FakeConn({this.topicRc = const {}, this.topicCheckpoint = const {}});

  @override
  Stream<dynamic> get frames => _frames.stream;

  @override
  void send(String text) {
    final m = jsonDecode(text) as Map<String, dynamic>;
    sent.add(m);
    if (m['op'] == 'C') push({'op': 'C', 'rc': 200, 'sid': 's1', 'hbi': 30});
    if (m['op'] == 'S') {
      final tc = m['tc'] as String;
      final rc = topicRc[tc] ?? 200;
      push({'op': 'S', 'rc': rc, 'tc': tc});
      final cp = topicCheckpoint[tc];
      if (rc == 200 && cp != null) push({'op': 'H', 'pl': cp, 'mid': 1, 'tc': tc});
    }
  }

  void push(Map<String, dynamic> m) {
    if (!_frames.isClosed) _frames.add(jsonEncode(m));
  }

  /// Simulate the server dropping the connection.
  Future<void> drop() => _frames.close();

  @override
  Future<void> close() async {
    closed = true;
    if (!_frames.isClosed) await _frames.close();
  }
}

FastcastClient makeClient({
  required List<FakeConn> conns,
  required Map<String, dynamic> checkpoints,
  List<String>? fetched,
}) =>
    FastcastClient(
      connector: () async {
        if (conns.isEmpty) throw FastcastError('no more conns scripted');
        return conns.removeAt(0);
      },
      fetchJson: (url) async {
        fetched?.add(url);
        if (!checkpoints.containsKey(url)) throw FastcastError('404');
        // jsonDecode(jsonEncode()) so each fetch returns a FRESH tree (a real
        // GET never aliases a previous doc).
        return jsonDecode(jsonEncode(checkpoints[url]));
      },
      throttle: Duration.zero,
      reconnectBase: const Duration(milliseconds: 5),
      subscribeTimeout: const Duration(milliseconds: 300),
      watchLifecycle: false,
    );

String deltaPl(List ops, {bool compress = false}) {
  if (!compress) return jsonEncode({'ts': 1, '~c': 0, 'pl': ops});
  final deflated = ZLibEncoder().convert(utf8.encode(jsonEncode(ops)));
  return jsonEncode({'ts': 1, '~c': 1, 'pl': base64.encode(deflated)});
}

void main() {
  FcLog.enabled = false; // keep the debug mirror out of test output
  const topic = 'gp-baseball-mlb-401';

  test('decodeDeltaOps: plain and zlib-compressed payloads', () {
    final ops = [
      {'op': 'replace', 'path': '/x', 'value': 2},
    ];
    expect(decodeDeltaOps(deltaPl(ops)), ops);
    expect(decodeDeltaOps(deltaPl(ops, compress: true)), ops);
    // A frame with no ops payload decodes to null (ignored upstream).
    expect(decodeDeltaOps(jsonEncode({'ts': 1})), null);
  });

  test('subscribe → handshake → checkpoint → coalesced patches', () async {
    final conn = FakeConn(topicCheckpoint: {topic: 'http://cp/1'});
    final c = makeClient(conns: [conn], checkpoints: {
      'http://cp/1': {
        'header': {'id': '401'},
        'plays': <dynamic>[],
      },
    });
    final docs = <dynamic>[];
    final sub = c.docs(topic).listen(docs.add);
    await pumpEventQueue();

    // Handshake + subscribe went out; the checkpoint is the first emission.
    expect(conn.sent.first['op'], 'C');
    expect(conn.sent.any((m) => m['op'] == 'S' && m['tc'] == topic), isTrue);
    expect(docs, hasLength(1));
    expect((docs[0] as Map)['header'], {'id': '401'});

    // A live patch frame lands and is applied.
    conn.push({
      'op': 'P',
      'tc': topic,
      'mid': 2,
      'pl': deltaPl([
        {'op': 'add', 'path': '/plays/-', 'value': {'text': 'Home run!'}},
      ]),
    });
    await pumpEventQueue();
    expect(docs, hasLength(2));
    expect((docs[1] as Map)['plays'], [
      {'text': 'Home run!'},
    ]);

    // A noise-only batch (odds churn) is applied but NOT re-emitted.
    conn.push({
      'op': 'P',
      'tc': topic,
      'mid': 3,
      'pl': deltaPl([
        {'op': 'add', 'path': '/pickcenter', 'value': {'spread': -3}},
      ]),
    });
    await pumpEventQueue();
    expect(docs, hasLength(2));
    // …but the doc did take it: the next rendered patch emits both changes.
    conn.push({
      'op': 'P',
      'tc': topic,
      'mid': 4,
      'pl': deltaPl([
        {'op': 'replace', 'path': '/header/id', 'value': '401x'},
      ]),
    });
    await pumpEventQueue();
    expect(docs, hasLength(3));
    expect((docs[2] as Map)['pickcenter'], {'spread': -3});
    expect(((docs[2] as Map)['header'] as Map)['id'], '401x');

    // Last listener gone → socket torn down.
    await sub.cancel();
    await pumpEventQueue();
    expect(conn.closed, isTrue);
    c.dispose();
  });

  test('rc:404 subscribe ack → error + done (topic unserved)', () async {
    final conn = FakeConn(topicRc: {topic: 404});
    final c = makeClient(conns: [conn], checkpoints: {});
    final errors = <Object>[];
    var done = false;
    c.docs(topic).listen((_) {}, onError: errors.add, onDone: () => done = true);
    await pumpEventQueue();
    expect(errors, hasLength(1));
    expect(errors.single, isA<FastcastError>());
    expect(done, isTrue);
    // Topic removal was the last one → socket closed.
    expect(conn.closed, isTrue);
    c.dispose();
  });

  test('silent topic (no H) → error + done after subscribeTimeout', () async {
    final conn = FakeConn(); // acks S with rc 200 but never sends H
    final c = makeClient(conns: [conn], checkpoints: {});
    final errors = <Object>[];
    var done = false;
    c.docs(topic).listen((_) {}, onError: errors.add, onDone: () => done = true);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(errors, hasLength(1));
    expect(done, isTrue);
    c.dispose();
  });

  test('patch apply failure → resync refetches the checkpoint', () async {
    final conn = FakeConn(topicCheckpoint: {topic: 'http://cp/1'});
    final fetched = <String>[];
    final c = makeClient(
      conns: [conn],
      fetched: fetched,
      checkpoints: {
        'http://cp/1': {
          'a': {'b': 1},
        },
      },
    );
    final docs = <dynamic>[];
    final sub = c.docs(topic).listen(docs.add);
    await pumpEventQueue();
    expect(docs, hasLength(1));

    // An op whose PARENT path doesn't exist → apply error → checkpoint refetch.
    conn.push({
      'op': 'P',
      'tc': topic,
      'mid': 2,
      'pl': deltaPl([
        {'op': 'replace', 'path': '/nope/deep/x', 'value': 1},
      ]),
    });
    await pumpEventQueue();
    expect(fetched, hasLength(2)); // initial + resync
    expect(docs, hasLength(2)); // the resynced doc re-emits
    expect((docs[1] as Map)['a'], {'b': 1});
    await sub.cancel();
    c.dispose();
  });

  test('disconnect → error to listeners → reconnect resubscribes fresh', () async {
    final conn1 = FakeConn(topicCheckpoint: {topic: 'http://cp/1'});
    final conn2 = FakeConn(topicCheckpoint: {topic: 'http://cp/2'});
    final c = makeClient(conns: [conn1, conn2], checkpoints: {
      'http://cp/1': {'v': 1},
      'http://cp/2': {'v': 2},
    });
    final docs = <dynamic>[];
    final errors = <Object>[];
    final sub = c.docs(topic).listen(docs.add, onError: errors.add);
    await pumpEventQueue();
    expect(docs, hasLength(1));
    expect((docs[0] as Map)['v'], 1);

    await conn1.drop(); // server drops the socket
    await Future<void>.delayed(const Duration(milliseconds: 50));
    // Listeners were told (fallback-to-polling signal), then the reconnect
    // re-handshook, re-subscribed, and delivered a fresh checkpoint.
    expect(errors, isNotEmpty);
    expect(conn2.sent.any((m) => m['op'] == 'S' && m['tc'] == topic), isTrue);
    expect(docs, hasLength(2));
    expect((docs[1] as Map)['v'], 2);
    await sub.cancel();
    c.dispose();
  });
}
