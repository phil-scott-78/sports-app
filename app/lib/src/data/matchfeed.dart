// matchfeed.dart — Dart port of worker/src/matchfeed.js. Raw CORE plays feed →
// canonical MatchFeed JSON map (schema/canonical.ts). SOCCER ONLY (capability
// hasMatchFeed). Pure; faithful port kept in lock-step with the JS — the
// matchfeed golden suite asserts byte parity.
//
// The core resource is touch-by-touch (every pass/tackle/throw-in) with
// TEAM-RELATIVE pitch coordinates (x 0 = own goal line, 100 = opponent goal
// line; y 0..100 across), passes/shots also carrying where the ball ended
// (fieldPosition2X/Y). Participants are $refs only — athleteId parses out of
// the ref and joins the summary lineups downstream. Paginated and APPEND-ONLY;
// api.dart merges pages before calling this.

import 'util.dart';

num? _numOr(dynamic v) => v is num ? v : null;

final _teamRefRe = RegExp(r'/teams/(\d+)');
final _athleteRefRe = RegExp(r'/athletes/(\d+)');

String? _teamIdFromRef(dynamic ref) => ref is String ? _teamRefRe.firstMatch(ref)?.group(1) : null;
String? _athleteIdFromRef(dynamic ref) => ref is String ? _athleteRefRe.firstMatch(ref)?.group(1) : null;

// raw = the merged core plays doc {count, items[]} (pages merged oldest-first).
// homeId/awayId = the competition's team ids — core plays tag their team as a
// $ref, resolved to a side here.
Map<String, dynamic> normalizeMatchFeed(Map raw, dynamic homeId, dynamic awayId) {
  final items = raw['items'] is List ? raw['items'] as List : const [];
  final home = homeId != null ? jsStr(homeId) : '';
  final away = awayId != null ? jsStr(awayId) : '';
  final plays = <Map<String, dynamic>>[];
  for (final p in items) {
    if (p == null || field(p, 'valid') == false) continue;
    final type = field(field(p, 'type'), 'text');
    if (!truthy(type)) continue;
    final tid = _teamIdFromRef(field(field(p, 'team'), r'$ref'));
    final side = tid != null && tid == home
        ? 'home'
        : tid != null && tid == away
            ? 'away'
            : null;
    plays.add(pickT({
      'id': field(p, 'id') != null ? jsStr(field(p, 'id')) : null,
      'type': type,
      'period': _numOr(field(field(p, 'period'), 'number')),
      'clock': field(field(p, 'clock'), 'displayValue'),
      'sec': _numOr(field(field(p, 'clock'), 'value')),
      'side': side,
      'athleteId': _athleteIdFromRef(field(field(first(field(p, 'participants')), 'athlete'), r'$ref')),
      'shortText': field(p, 'shortText'),
      'text': field(p, 'text'),
      'x': _numOr(field(p, 'fieldPositionX')),
      'y': _numOr(field(p, 'fieldPositionY')),
      'x2': _numOr(field(p, 'fieldPosition2X')),
      'y2': _numOr(field(p, 'fieldPosition2Y')),
      'scoring': field(p, 'scoringPlay') == true ? true : null,
    }, ['id', 'type', 'period', 'clock', 'sec', 'side', 'athleteId', 'shortText', 'text', 'x', 'y', 'x2', 'y2', 'scoring']));
  }
  return {'count': raw['count'] is num ? raw['count'] : plays.length, 'plays': plays};
}
