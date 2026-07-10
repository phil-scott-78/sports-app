// fastcast.dart — faithful Dart port of worker/src/fastcast.js (the FastCast
// pure layer: RFC 6902 application + the uid-prefixed event variant + the
// Track-2 slate overlay normalizer). Byte-for-byte parity with the JS oracle is
// pinned by test/port_fastcast_test.dart replaying the captured push streams
// (test/fixtures/golden/fastcast/). See fastcast-plan.md for the protocol.
//
// Resilience rule (protocol): NEVER throw on a bad patch — apply what resolves,
// report what didn't. Both appliers return {'doc':..., 'errors': [...]}; a
// non-empty errors list is the caller's signal to resync. Inputs are deep-copied,
// never mutated.

import 'profiles.dart';
import 'normalize.dart' show statusToPhase, buildScore, buildSituation;
import 'util.dart';

dynamic _deepCopy(dynamic v) {
  if (v is List) return v.map(_deepCopy).toList();
  if (v is Map) return {for (final k in v.keys) k: _deepCopy(v[k])};
  return v;
}

// RFC 6901 pointer segment unescape (~1 → /, ~0 → ~; order matters).
String _unescapeSeg(String s) => s.replaceAll('~1', '/').replaceAll('~0', '~');

List<String> _segsOf(String path) {
  if (path == '') return [];
  return path.split('/').skip(1).map(_unescapeSeg).toList();
}

final _digits = RegExp(r'^\d+$');

// Walk to the PARENT of the pointer target. Returns (parent, key) or an error string.
dynamic _walk(dynamic root, List<String> segs) {
  dynamic node = root;
  for (var i = 0; i < segs.length - 1; i++) {
    final seg = segs[i];
    if (node is List) {
      final idx = _digits.hasMatch(seg) ? int.parse(seg) : -1;
      if (idx < 0 || idx >= node.length) return "no such index '$seg'";
      node = node[idx];
    } else if (node is Map) {
      if (!node.containsKey(seg)) return "no such key '$seg'";
      node = node[seg];
    } else {
      return "not a container at '$seg'";
    }
  }
  return (node, segs[segs.length - 1]);
}

// Read the value at segs (for move/copy). Returns (value,) or an error string.
dynamic _readAt(dynamic root, List<String> segs) {
  if (segs.isEmpty) return (root,);
  final w = _walk(root, segs);
  if (w is String) return w;
  final (parent, key) = w as (dynamic, String);
  if (parent is List) {
    final idx = _digits.hasMatch(key) ? int.parse(key) : -1;
    if (idx < 0 || idx >= parent.length) return "no such index '$key'";
    return (parent[idx],);
  }
  if (parent is Map) {
    if (!parent.containsKey(key)) return "no such key '$key'";
    return (parent[key],);
  }
  return "not a container at '$key'";
}

bool _deepEqual(dynamic a, dynamic b) {
  if (identical(a, b)) return true;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEqual(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !_deepEqual(a[k], b[k])) return false;
    }
    return true;
  }
  return a == b;
}

// Apply ONE op at segs within root. Returns null (ok) or an error string.
// `replace` is deliberately lenient (set semantics) — mirrors the JS oracle.
String? _applyAt(dynamic root, String op, List<String> segs, [dynamic value]) {
  if (segs.isEmpty) return 'root op unsupported';
  final w = _walk(root, segs);
  if (w is String) return w;
  final (parent, key) = w as (dynamic, String);
  if (parent is List) {
    if (op == 'add' && key == '-') {
      parent.add(value);
      return null;
    }
    final idx = _digits.hasMatch(key) ? int.parse(key) : -1;
    if (idx < 0) return "bad array index '$key'";
    if (op == 'add') {
      if (idx > parent.length) return "index '$key' out of range";
      parent.insert(idx, value);
      return null;
    }
    if (idx >= parent.length) return "no such index '$key'";
    if (op == 'remove') {
      parent.removeAt(idx);
      return null;
    }
    if (op == 'replace') {
      parent[idx] = value;
      return null;
    }
    if (op == 'test') return _deepEqual(parent[idx], value) ? null : 'test failed';
    return "unsupported op '$op'";
  }
  if (parent is Map) {
    if (op == 'add' || op == 'replace') {
      parent[key] = value;
      return null;
    }
    if (op == 'remove') {
      if (!parent.containsKey(key)) return "no such key '$key'";
      parent.remove(key);
      return null;
    }
    if (op == 'test') return _deepEqual(parent[key], value) ? null : 'test failed';
    return "unsupported op '$op'";
  }
  return "not a container at '$key'";
}

// Shared driver: `locate(root, path)` maps an op's path to (root, segs) or an
// error string — the only difference between the standard and event variants.
Map<String, dynamic> _applyWith(
    dynamic doc, dynamic ops, dynamic Function(dynamic root, String path) locate) {
  final out = _deepCopy(doc);
  final errors = <String>[];
  final list = ops is List ? ops : const [];
  for (var i = 0; i < list.length; i++) {
    final o = list[i] is Map ? list[i] as Map : const {};
    final op = o['op'];
    final path = o['path'];
    void failWith(String why) => errors.add('$i:$op $path: $why');
    if (path is! String) {
      failWith('no path');
      continue;
    }
    final loc = locate(out, path);
    if (loc is String) {
      failWith(loc);
      continue;
    }
    final (locRoot, locSegs) = loc as (dynamic, List<String>);
    if (op == 'add' || op == 'replace' || op == 'test') {
      final err = _applyAt(locRoot, op as String, locSegs, _deepCopy(o['value']));
      if (err != null) failWith(err);
    } else if (op == 'remove') {
      final err = _applyAt(locRoot, 'remove', locSegs);
      if (err != null) failWith(err);
    } else if (op == 'move' || op == 'copy') {
      final from = o['from'];
      if (from is! String) {
        failWith('no from');
        continue;
      }
      final fromLoc = locate(out, from);
      if (fromLoc is String) {
        failWith(fromLoc);
        continue;
      }
      final (fromRoot, fromSegs) = fromLoc as (dynamic, List<String>);
      final r = _readAt(fromRoot, fromSegs);
      if (r is String) {
        failWith(r);
        continue;
      }
      final val = _deepCopy((r as (dynamic,)).$1);
      if (op == 'move') {
        final err = _applyAt(fromRoot, 'remove', fromSegs);
        if (err != null) {
          failWith(err);
          continue;
        }
      }
      final err = _applyAt(locRoot, 'add', locSegs, val);
      if (err != null) failWith(err);
    } else {
      failWith("unsupported op '$op'");
    }
  }
  return {'doc': out, 'errors': errors};
}

/// Standard RFC 6902 patch (gp-* topics use root-relative paths).
/// Returns `{'doc': patched, 'errors': [String]}` — never throws.
Map<String, dynamic> applyOps(dynamic doc, dynamic ops) =>
    _applyWith(doc, ops, (root, path) => path == '' || path.startsWith('/')
        ? (root, _segsOf(path))
        : "non-rooted path '$path'");

dynamic _findEventByUid(dynamic doc, String uid) {
  for (final sport in (field(doc, 'sports') is List ? field(doc, 'sports') as List : const [])) {
    for (final lg in (field(sport, 'leagues') is List ? field(sport, 'leagues') as List : const [])) {
      for (final ev in (field(lg, 'events') is List ? field(lg, 'events') as List : const [])) {
        if (field(ev, 'uid') == uid) return ev;
      }
    }
  }
  return null;
}

/// event-* topic patch: paths are `<uid>/<pointer...>` where `<uid>` is the raw
/// event uid (contains '~' and ':' — literal, NOT RFC 6901-escaped; split on '/'
/// BEFORE unescaping). A root-relative path ('/x' or '') applies standardly.
Map<String, dynamic> applyEventOps(dynamic doc, dynamic ops) =>
    _applyWith(doc, ops, (root, path) {
      if (path == '' || path.startsWith('/')) return (root, _segsOf(path));
      final slash = path.indexOf('/');
      final uid = slash == -1 ? path : path.substring(0, slash);
      final rest = slash == -1 ? '' : path.substring(slash);
      final ev = _findEventByUid(root, uid);
      if (ev == null) return "no event with uid '$uid'";
      if (rest == '') return 'bare uid path';
      return (ev, _segsOf(rest));
    });

/// The event-* doc → per-event PARTIAL updates (Track 2 overlay): score, phase
/// (from `fullStatus.type` — the normal status object, house phase rules hold),
/// clock, detail, situation, seriesSummary. Merged over the last polled
/// canonical slate by the provider; never a scoreboard replacement.
Map<String, dynamic> normalizeFastcastSlate(Registry reg, String key, dynamic doc) {
  final profile = resolve(reg, key);
  final wantId = profile['espnLeagueId']?.toString();
  final slug = key.split('/')[1];
  Map? league;
  for (final sport in (field(doc, 'sports') is List ? field(doc, 'sports') as List : const [])) {
    for (final lg in (field(sport, 'leagues') is List ? field(sport, 'leagues') as List : const [])) {
      if (jsStr(field(lg, 'id') ?? '') == wantId || field(lg, 'slug') == slug) {
        league = lg as Map;
        break;
      }
    }
    if (league != null) break;
  }
  final events = <Map<String, dynamic>>[];
  for (final ev in (field(league, 'events') is List ? field(league, 'events') as List : const [])) {
    final st = ev['fullStatus'] is Map ? ev['fullStatus'] as Map : const {};
    final type = st['type'] is Map ? st['type'] as Map : const {};
    final ph = statusToPhase(type);
    final e = <String, dynamic>{
      'id': jsStr(ev['id'] ?? ''),
      'status': {
        'phase': ph['phase'], 'live': ph['live'], 'ended': ph['ended'],
        'period': st['period'] is num ? st['period'] : 0,
        'periodLabel': or([type['shortDetail'], type['detail'], type['description'], '']),
        'espnName': or([type['name'], '']), 'detail': or([type['detail'], '']),
      },
      'competitors': [
        for (final c in (ev['competitors'] is List ? ev['competitors'] as List : const []))
          (() {
            final out = <String, dynamic>{'id': jsStr(field(c, 'id') ?? '')};
            if (truthy(field(c, 'homeAway'))) out['homeAway'] = field(c, 'homeAway');
            if (field(c, 'score') != null) out['score'] = buildScore(profile['scoreKind'], field(c, 'score'));
            if (field(c, 'winner') is bool) out['winner'] = field(c, 'winner');
            return out;
          })(),
      ],
    };
    if (truthy(ev['uid'])) e['uid'] = ev['uid'];
    if (truthy(type['shortDetail'])) (e['status'] as Map)['shortDetail'] = type['shortDetail'];
    if (ph['live'] == true && truthy(st['displayClock']) && st['displayClock'] != '0:00') {
      (e['status'] as Map)['clock'] = st['displayClock'];
    }
    // situation is scoreboard-shaped on the fastcast event (outsText rides the
    // event, not the situation) — reuse the scoreboard builder verbatim.
    final situation = buildSituation({'situation': ev['situation'], 'outsText': ev['outsText']});
    if (situation != null) e['situation'] = situation;
    if (truthy(ev['seriesSummary'])) e['seriesSummary'] = ev['seriesSummary'];
    events.add(e);
  }
  return {'key': key, 'events': events};
}
