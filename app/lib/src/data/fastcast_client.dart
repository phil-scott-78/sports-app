// fastcast_client.dart — the ESPN FastCast push client: the ONLY I/O module
// beside espn_client.dart. The verified protocol lives in fastcast-plan.md; the
// pure patch/normalize layer is fastcast.dart (parity-pinned vs the JS oracle).
//
// Shape: ONE socket total, multiplexing ref-counted topic subscriptions.
//   subscribe → op:"S" ack (rc:404 = topic unserved for this league right now —
//   Phase 0 finding #2 — the consumer silently falls back to polling)
//   → op:"H" names a checkpoint URL (the full current doc, plain GET)
//   → op:"R" (catch-up) / op:"P" (live) frames carry RFC 6902 deltas
//     (base64 + zlib-deflate when ~c:1). Unknown ops (op:"B" exists) are ignored.
//
// Patches COALESCE: one apply + emit per [throttle] window — one deep copy per
// window, not per frame. Batches that touch only unrendered paths (odds churn
// dominates — finding #8) apply silently without re-emitting. mid gaps are NOT
// treated as loss (finding #5: gaps occur on healthy connections); a FAILED
// patch apply is, and triggers a checkpoint refetch (rate-limited).
//
// Every failure degrades to an error event on the topic streams — the
// consumer's signal to fall back to today's polling — never a crash, never a
// user-facing setting. Foreground-only: backgrounding closes the socket;
// resuming reconnects (fresh token per connect — they're short-lived) and
// re-checkpoints every subscribed topic.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import 'fastcast.dart' as fc;
import 'fastcast_log.dart';

const _hostUrl = 'https://fastcast.semfs.engsvc.go.com/public/websockethost';
const _origin = 'https://www.espn.com';
// The upgrade is rejected without a plausible browser UA + Origin (verified).
const _ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

/// Same ≥100KB isolate-decode rule as espn_client — a gp checkpoint runs ~1MB
/// and a jsonDecode that big on the UI isolate janks route pushes.
const int _bigBodyChars = 100 * 1024;

/// Top-level so [compute] can send it to the worker isolate.
dynamic _jsonDecodeIsolate(String body) => jsonDecode(body);

class FastcastError implements Exception {
  final String message;
  FastcastError(this.message);
  @override
  String toString() => 'FastcastError: $message';
}

/// Decode an op:"P"/"R" frame's `pl` → the RFC 6902 ops array + the server's
/// `ts` (epoch ms — the message's upstream age, logged so lag investigations
/// can split "arrived late" from "we sat on it"). `pl` is a JSON string
/// `{ts, "~c", pl}`; `~c:1` → the inner pl is base64 + zlib-deflate
/// (raw-deflate fallback, as observed). ops is null when the frame carries none.
({List<dynamic>? ops, num? ts}) decodeDelta(dynamic pl) {
  dynamic inner = pl;
  if (inner is String) inner = jsonDecode(inner);
  if (inner is! Map) return (ops: null, ts: null);
  dynamic body = inner['pl'];
  final c = inner['~c'];
  final compressed = c == 1 || c == true || c == '1';
  if (compressed && body is String) {
    final raw = base64.decode(body);
    List<int> out;
    try {
      out = ZLibDecoder().convert(raw);
    } catch (_) {
      out = ZLibDecoder(raw: true).convert(raw);
    }
    body = utf8.decode(out);
  }
  final ops = body is String ? jsonDecode(body) : body;
  return (ops: ops is List ? ops : null, ts: inner['ts'] is num ? inner['ts'] as num : null);
}

List<dynamic>? decodeDeltaOps(dynamic pl) => decodeDelta(pl).ops;

/// One live FastCast socket — JSON-text frames in and out. Injectable so the
/// client's whole state machine is testable without a network. The default
/// implementation wraps dart:io [WebSocket] (which answers server pings with
/// pongs automatically, per the protocol's heartbeat).
abstract class FastcastConnection {
  Stream<dynamic> get frames;
  void send(String text);
  Future<void> close();
}

class _WsConnection implements FastcastConnection {
  final WebSocket _ws;

  /// Owns the socket the upgrade was detached from — closed with the socket.
  final HttpClient _client;
  _WsConnection(this._ws, this._client);
  @override
  Stream<dynamic> get frames => _ws;
  @override
  void send(String text) => _ws.add(text);
  @override
  Future<void> close() async {
    try {
      await _ws.close();
    } finally {
      _client.close(force: true);
    }
  }
}

typedef FastcastConnector = Future<FastcastConnection> Function();
typedef JsonFetcher = Future<dynamic> Function(String url);

class _Topic {
  final String name;
  final listeners = <StreamController<dynamic>>[];
  String? checkpointUrl;
  dynamic doc;

  /// Decoded ops awaiting the next coalesced apply.
  final pending = <dynamic>[];

  /// op:"I" heartbeats seen (counted, not line-logged — see fastcast_log.dart).
  int heartbeats = 0;
  Timer? applyTimer;
  Timer? retryTimer;
  Timer? hTimeout;
  int lastApplyMs = 0;
  int lastResyncMs = 0;

  /// Invalidates in-flight checkpoint fetches on disconnect/removal.
  int gen = 0;
  _Topic(this.name);
}

class FastcastClient with WidgetsBindingObserver {
  /// Test seams — null means the real dart:io WebSocket / HTTP implementations.
  final FastcastConnector? _connector;
  final JsonFetcher? _fetchJson;
  final http.Client _http;

  /// Coalescing window: at most one patch-apply + re-emit per topic per window.
  final Duration throttle;

  /// Base reconnect backoff (doubled per attempt, jittered, capped at 60s).
  final Duration reconnectBase;

  /// How long to wait for the op:"H" checkpoint frame after subscribing before
  /// declaring the topic unserved (probe showed silent topics exist).
  final Duration subscribeTimeout;

  static const _maxAttempts = 5;

  FastcastClient({
    FastcastConnector? connector,
    JsonFetcher? fetchJson,
    this.throttle = const Duration(seconds: 1),
    this.reconnectBase = const Duration(seconds: 2),
    this.subscribeTimeout = const Duration(seconds: 15),
    bool watchLifecycle = true,
    http.Client? httpClient,
  })  : _http = httpClient ?? http.Client(),
        _connector = connector,
        _fetchJson = fetchJson,
        _watchLifecycle = watchLifecycle {
    if (watchLifecycle) WidgetsBinding.instance.addObserver(this);
  }

  final bool _watchLifecycle;
  final Map<String, _Topic> _topics = {};
  FastcastConnection? _conn;
  StreamSubscription? _connSub;
  Completer<String>? _cAck;
  String? _sid;
  bool _connecting = false;
  bool _foreground = true;
  bool _disposed = false;
  int _epoch = 0;
  int _attempts = 0;
  int _connectedAtMs = 0;
  Timer? _reconnectTimer;
  final _rand = math.Random();

  int get _nowMs => DateTime.now().millisecondsSinceEpoch;

  // ---- public surface --------------------------------------------------------

  /// The stream of full docs for [topic] — the checkpoint first, then a patched
  /// doc per coalesced batch (≤1 per [throttle]). Ref-counted: the first
  /// listener connects/subscribes, the last one tears the topic down (and the
  /// socket, when no topics remain). Errors mean "push unavailable — fall back
  /// to polling"; the stream stays open (except topic-unserved, which closes)
  /// and data resumes if the connection recovers.
  Stream<dynamic> docs(String topic) {
    late StreamController<dynamic> ctrl;
    ctrl = StreamController<dynamic>(
      onListen: () => _addListener(topic, ctrl),
      onCancel: () => _removeListener(topic, ctrl),
    );
    return ctrl.stream;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_watchLifecycle) WidgetsBinding.instance.removeObserver(this);
    for (final t in List.of(_topics.values)) {
      _removeTopic(t, close: true);
    }
    _dropConn();
    _reconnectTimer?.cancel();
    _http.close();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _setForeground(state == AppLifecycleState.resumed);

  // ---- subscription lifecycle -------------------------------------------------

  void _addListener(String topic, StreamController<dynamic> ctrl) {
    if (_disposed) {
      ctrl.addError(FastcastError('client disposed'));
      ctrl.close();
      return;
    }
    final t = _topics.putIfAbsent(topic, () => _Topic(topic));
    t.listeners.add(ctrl);
    if (t.doc != null) ctrl.add(t.doc);
    if (_conn != null && _sid != null) {
      if (t.listeners.length == 1 && t.doc == null) _sendSubscribe(t);
    } else {
      _attempts = 0; // a fresh subscriber earns a fresh set of attempts
      unawaited(_ensureConnected());
    }
  }

  void _removeListener(String topic, StreamController<dynamic> ctrl) {
    final t = _topics[topic];
    if (t == null) return;
    t.listeners.remove(ctrl);
    if (t.listeners.isEmpty) _removeTopic(t);
  }

  /// NOTE: no unsubscribe op is sent — none is verified to exist. Frames for a
  /// removed topic are ignored; when NO topics remain the socket closes, which
  /// is the common case (one detail screen open at a time).
  void _removeTopic(_Topic t, {bool close = false}) {
    t.gen++;
    t.applyTimer?.cancel();
    t.retryTimer?.cancel();
    t.hTimeout?.cancel();
    if (close) {
      for (final c in List.of(t.listeners)) {
        if (!c.isClosed) c.close();
      }
    }
    _topics.remove(t.name);
    FcLog.log('conn',
        '${t.name} unsubscribed (${t.heartbeats} heartbeat(s) seen)${_topics.isEmpty ? ' — no topics left, closing socket' : ''}');
    if (_topics.isEmpty && !_disposed) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _dropConn();
    }
  }

  // ---- connection state machine ------------------------------------------------

  void _setForeground(bool fg) {
    if (_disposed || fg == _foreground) return;
    FcLog.log('conn', fg ? 'foreground — reconnecting' : 'background — closing socket');
    _foreground = fg;
    if (!fg) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _dropConn();
      for (final t in _topics.values) {
        _resetTopicSession(t);
      }
    } else {
      _attempts = 0;
      unawaited(_ensureConnected());
    }
  }

  /// Drop everything tied to the current socket session; the doc is KEPT (the
  /// UI holds the last state) until the next checkpoint replaces it.
  void _resetTopicSession(_Topic t) {
    t.gen++;
    t.pending.clear();
    t.applyTimer?.cancel();
    t.applyTimer = null;
    t.retryTimer?.cancel();
    t.retryTimer = null;
    t.hTimeout?.cancel();
    t.hTimeout = null;
  }

  Future<void> _ensureConnected() async {
    if (_disposed || !_foreground || _topics.isEmpty) return;
    if (_conn != null || _connecting) return;
    _connecting = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    FcLog.log('conn', 'connecting (${_topics.length} topic(s) waiting)');
    try {
      final conn =
          await (_connector != null ? _connector() : _connectReal());
      if (_disposed || !_foreground || _topics.isEmpty) {
        unawaited(conn.close().catchError((_) {}));
        return;
      }
      final epoch = ++_epoch;
      _conn = conn;
      _connectedAtMs = _nowMs;
      _cAck = Completer<String>();
      _connSub = conn.frames.listen(
        (raw) => _onFrame(epoch, raw),
        onDone: () => _onDisconnect(epoch),
        onError: (_) => _onDisconnect(epoch),
        cancelOnError: true,
      );
      conn.send(jsonEncode({'op': 'C'}));
      _sid = await _cAck!.future.timeout(const Duration(seconds: 10));
      _attempts = 0;
      FcLog.log('conn', 'up sid=$_sid — subscribing ${_topics.length} topic(s)');
      for (final t in _topics.values) {
        _sendSubscribe(t);
      }
    } catch (e) {
      FcLog.log('err', 'connect failed: $e');
      _dropConn();
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  void _dropConn() {
    _connSub?.cancel();
    _connSub = null;
    final c = _conn;
    _conn = null;
    _sid = null;
    _epoch++; // orphan any frames/done from the old socket
    if (c != null) unawaited(c.close().catchError((_) {}));
  }

  void _onDisconnect(int epoch) {
    if (_disposed || epoch != _epoch) return;
    FcLog.log('conn',
        'lost after ${((_nowMs - _connectedAtMs) / 1000).round()}s — listeners fall back to polling');
    _dropConn();
    for (final t in _topics.values) {
      _resetTopicSession(t);
      _error(t, FastcastError('connection lost'));
    }
    if (_foreground && _topics.isNotEmpty) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed || !_foreground || _topics.isEmpty) return;
    _attempts++;
    if (_attempts > _maxAttempts) {
      FcLog.log('conn', 'giving up after $_maxAttempts attempts — polling until resume/reopen');
      return; // give up → consumers stay on polling
    }
    final base = reconnectBase.inMilliseconds * (1 << (_attempts - 1));
    final ms = math.min(60000, base) * (0.75 + _rand.nextDouble() * 0.5);
    FcLog.log('conn', 'reconnect attempt $_attempts in ${ms.round()}ms');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: ms.round()), () {
      _reconnectTimer = null;
      unawaited(_ensureConnected());
    });
  }

  // ---- frames -------------------------------------------------------------------

  void _onFrame(int epoch, dynamic raw) {
    if (_disposed || epoch != _epoch) return;
    Map? msg;
    try {
      final d = raw is String ? jsonDecode(raw) : raw;
      if (d is Map) msg = d;
    } catch (_) {/* non-JSON frame: ignore */}
    if (msg == null) return;
    final op = msg['op'];
    if (op == 'C') {
      final sid = msg['sid'];
      if (sid != null && !(_cAck?.isCompleted ?? true)) {
        _cAck!.complete(sid.toString());
      }
      return;
    }
    final t = _topics[msg['tc']];
    if (t == null) return; // unknown/removed topic — ignore
    if (op == 'I') {
      t.heartbeats++; // per-topic heartbeat (carries a mid) — counted, not logged
      return;
    }
    if (op == 'S') {
      final rc = msg['rc'];
      FcLog.log('frame', '${t.name} S ack rc=$rc');
      if (rc != null && rc != 200 && rc != '200') {
        // rc:404 → the league has no live topic right now (dormant season).
        _fail(t, FastcastError('topic unavailable (rc $rc)'));
      }
      return;
    }
    if (op == 'H') {
      FcLog.log('frame', '${t.name} H mid=${msg['mid']}');
      t.hTimeout?.cancel();
      t.hTimeout = null;
      t.checkpointUrl = msg['pl']?.toString();
      t.pending.clear();
      unawaited(_loadCheckpoint(t));
      return;
    }
    if (op == 'P' || op == 'R') {
      List<dynamic>? ops;
      num? ts;
      try {
        final d = decodeDelta(msg['pl']);
        ops = d.ops;
        ts = d.ts;
      } catch (e) {
        FcLog.log('err', '${t.name} $op mid=${msg['mid']} decode failed: $e');
        /* undecodable frame — the resync path covers real loss */
      }
      if (ops == null) return;
      // ts age = how old the message already was when it reached us (upstream
      // lag); everything after this point is lag WE add.
      final age = ts != null ? _nowMs - ts.toInt() : null;
      FcLog.log('frame',
          '${t.name} $op mid=${msg['mid']} ops=${ops.length}${age != null ? ' age=${age}ms' : ''}');
      t.pending.addAll(ops);
      if (t.doc != null) _scheduleApply(t);
      return;
    }
    FcLog.log('frame', '${t.name} UNKNOWN op=$op — ignored');
  }

  void _sendSubscribe(_Topic t) {
    final c = _conn;
    final sid = _sid;
    if (c == null || sid == null) return;
    FcLog.log('send', 'S ${t.name}');
    c.send(jsonEncode({'op': 'S', 'sid': sid, 'tc': t.name}));
    t.hTimeout?.cancel();
    t.hTimeout = Timer(subscribeTimeout, () {
      FcLog.log('err', '${t.name}: no checkpoint within ${subscribeTimeout.inSeconds}s — topic unserved');
      _fail(t, FastcastError('no checkpoint for ${t.name}'));
    });
  }

  // ---- checkpoint + patch pipeline ----------------------------------------------

  Future<void> _loadCheckpoint(_Topic t) async {
    final url = t.checkpointUrl;
    if (url == null) return;
    final gen = ++t.gen;
    final t0 = _nowMs;
    dynamic doc;
    try {
      doc = await (_fetchJson != null ? _fetchJson(url) : _httpJson(url));
    } catch (e) {
      if (_topics[t.name] != t || t.gen != gen) return;
      FcLog.log('err', '${t.name} checkpoint fetch failed ($e) — retry in 10s, polling meanwhile');
      _error(t, FastcastError('checkpoint fetch failed'));
      t.retryTimer?.cancel();
      t.retryTimer = Timer(const Duration(seconds: 10), () {
        t.retryTimer = null;
        unawaited(_loadCheckpoint(t));
      });
      return;
    }
    if (_topics[t.name] != t || t.gen != gen) return;
    FcLog.log('ckpt',
        '${t.name} checkpoint in ${_nowMs - t0}ms (${doc is Map ? '${doc.length} top-level keys' : doc.runtimeType}, ${t.pending.length} buffered op(s))');
    t.doc = doc;
    // Deltas that raced the snapshot download: apply best-effort — the lenient
    // replace semantics make re-applying already-included ops harmless; a
    // failure right after a fresh checkpoint just means they're stale → drop.
    if (t.pending.isNotEmpty) {
      final r = _applier(t)(t.doc, List.of(t.pending));
      t.pending.clear();
      if ((r['errors'] as List).isEmpty) t.doc = r['doc'];
    }
    t.lastApplyMs = _nowMs;
    _emit(t);
  }

  Map<String, dynamic> Function(dynamic, dynamic) _applier(_Topic t) =>
      t.name.startsWith('event-') ? fc.applyEventOps : fc.applyOps;

  void _scheduleApply(_Topic t) {
    if (t.doc == null || t.pending.isEmpty || t.applyTimer != null) return;
    final wait = throttle.inMilliseconds - (_nowMs - t.lastApplyMs);
    if (wait <= 0) {
      _applyNow(t);
    } else {
      FcLog.log('apply', '${t.name} coalescing — next apply in ${wait}ms');
      t.applyTimer = Timer(Duration(milliseconds: wait), () {
        t.applyTimer = null;
        _applyNow(t);
      });
    }
  }

  void _applyNow(_Topic t) {
    if (t.doc == null || t.pending.isEmpty) return;
    t.lastApplyMs = _nowMs;
    final ops = List.of(t.pending);
    t.pending.clear();
    final r = _applier(t)(t.doc, ops);
    final errors = r['errors'] as List;
    if (errors.isNotEmpty) {
      // A patch that doesn't apply means our doc diverged → resync from the
      // checkpoint. Rate-limited so a bad stream can't thrash (finding #5:
      // don't resync on mid gaps, only on real apply failures).
      final resync = _nowMs - t.lastResyncMs > 10000;
      FcLog.log('err',
          '${t.name} ${errors.length}/${ops.length} op(s) failed (${errors.first})${resync ? ' → resync' : ' → dropped (resynced <10s ago)'}');
      if (resync) {
        t.lastResyncMs = _nowMs;
        unawaited(_loadCheckpoint(t));
      }
      return;
    }
    t.doc = r['doc'];
    if (_anyRendered(ops)) {
      FcLog.log('apply', '${t.name} applied ${ops.length} op(s) → emit');
      _emit(t);
    } else {
      FcLog.log('apply', '${t.name} applied ${ops.length} op(s) → suppressed (odds-only)');
    }
  }

  /// Odds churn dominates patch traffic (finding #8) — a batch that touches
  /// ONLY these subtrees is applied silently without waking the normalizer.
  /// Event-topic paths carry a uid prefix; strip it down to the inner pointer.
  static const _noise = ['/odds', '/pickcenter', '/againstTheSpread'];

  static bool _anyRendered(List ops) {
    for (final o in ops) {
      final path = o is Map ? o['path'] : null;
      if (path is! String) return true;
      var p = path;
      if (!p.startsWith('/')) {
        final i = p.indexOf('/');
        if (i == -1) return true;
        p = p.substring(i);
      }
      if (!_noise.any((n) => p == n || p.startsWith('$n/'))) return true;
    }
    return false;
  }

  void _emit(_Topic t) {
    for (final c in List.of(t.listeners)) {
      if (!c.isClosed) c.add(t.doc);
    }
  }

  /// Non-terminal: push is unavailable right now — consumers fall back to
  /// polling and switch back when data flows again.
  void _error(_Topic t, Object e) {
    for (final c in List.of(t.listeners)) {
      if (!c.isClosed) c.addError(e);
    }
  }

  /// Terminal: the topic is unserved (rc:404 / silent) — error AND close, so
  /// the consumer settles on polling for the rest of this screen's life.
  void _fail(_Topic t, Object e) {
    _error(t, e);
    _removeTopic(t, close: true);
  }

  // ---- default (real) I/O ---------------------------------------------------------

  Future<dynamic> _httpJson(String url) async {
    final r = await _http.get(Uri.parse(url), headers: const {
      'User-Agent': _ua,
      'Origin': _origin,
    }).timeout(AppConfig.httpTimeout);
    if (r.statusCode != 200) {
      throw FastcastError('GET → ${r.statusCode}');
    }
    final body = r.body;
    return body.length >= _bigBodyChars
        ? await compute(_jsonDecodeIsolate, body)
        : jsonDecode(body);
  }

  Future<FastcastConnection> _connectReal() async {
    final host = await _httpJson(_hostUrl);
    final ip = host is Map ? host['ip'] : null;
    final port = host is Map ? host['securePort'] : null;
    final token = host is Map ? host['token'] : null;
    if (ip == null || port == null || token == null) {
      throw FastcastError('bad websockethost response');
    }
    // The host endpoint hands out a raw IP whose cert names the service host,
    // not the IP — accept the mismatch for THIS connection only (same trust
    // decision the recon tooling made; the payload is public score data).
    final hc = HttpClient()
      ..badCertificateCallback = (cert, h, p) => h == ip.toString();
    try {
      return await _upgrade(hc, ip.toString(), port, token.toString())
          .timeout(AppConfig.httpTimeout);
    } catch (_) {
      hc.close(force: true);
      rethrow;
    }
  }

  /// The upgrade is hand-driven rather than left to `WebSocket.connect`:
  /// FastCast/4.1.26 matches request header NAMES case-SENSITIVELY (verified
  /// live 2026-07-09 — lowercase `upgrade` → `{"rc":404,"op":"ERROR"}`;
  /// lowercase `Host`/`Sec-WebSocket-Key`/`Sec-WebSocket-Version` → the server
  /// just hangs). `WebSocket.connect` writes its own headers lowercase with no
  /// way to override, so every connect 404'd. `HttpClient` + `preserveHeaderCase`
  /// gives us the exact casing, and `detachSocket` hands back the post-101
  /// socket WITH any bytes already buffered behind the response.
  Future<FastcastConnection> _upgrade(
      HttpClient hc, String ip, dynamic port, String token) async {
    final nonce = base64.encode(List<int>.generate(16, (_) => _rand.nextInt(256)));
    // Token goes in RAW (verified) — and no permessage-deflate.
    final req = await hc.openUrl(
        'GET',
        Uri.parse('https://$ip:$port/FastcastService/pubsub/profiles/12000'
            '?TrafficManager-Token=$token'))
      ..followRedirects = false
      ..persistentConnection = false;
    req.headers
      ..set('Host', '$ip:$port', preserveHeaderCase: true)
      ..set('Upgrade', 'websocket', preserveHeaderCase: true)
      ..set('Connection', 'Upgrade', preserveHeaderCase: true)
      ..set('Sec-WebSocket-Key', nonce, preserveHeaderCase: true)
      ..set('Sec-WebSocket-Version', '13', preserveHeaderCase: true)
      ..set('Origin', _origin, preserveHeaderCase: true)
      ..set('User-Agent', _ua, preserveHeaderCase: true);
    final res = await req.close();
    if (res.statusCode != HttpStatus.switchingProtocols) {
      await res.drain<void>().catchError((_) {});
      throw FastcastError('upgrade rejected: HTTP ${res.statusCode}');
    }
    final socket = await res.detachSocket();
    return _WsConnection(WebSocket.fromUpgradedSocket(socket, serverSide: false), hc);
  }
}
