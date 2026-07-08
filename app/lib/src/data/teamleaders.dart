// teamleaders.dart — Dart port of worker/src/teamleaders.js. The TEAM LEADERS tier
// (§2.6): a team's per-category season top player. Pure map→map. The caller (api.dart)
// fetches the CORE leaders doc, caps the fan-out, and resolves each unique
// athlete.$ref ONCE; this shapes the resolved raws. Verified byte-for-byte against
// the JS oracle via the golden parity suite.

import 'util.dart';

const _maxCategories = 6;

/// athlete id from a `.../athletes/{id}?...` $ref (the key the caller resolves by).
String? athleteIdFromRef(dynamic ref) {
  if (ref is! String) return null;
  final m = RegExp(r'/athletes/(\d+)').firstMatch(ref);
  return m?.group(1);
}

String? _headshotOf(dynamic o) =>
    https(or([field(field(o, 'headshot'), 'href'), field(o, 'headshot')]));

String? _positionOf(dynamic o) {
  final p = field(o, 'position');
  if (p is! Map) return null;
  final v = or([field(p, 'abbreviation'), field(p, 'displayName')]);
  return truthy(v) ? jsStr(v) : null;
}

Map<String, dynamic> normalizeTeamLeaders(
    String league, dynamic teamId, dynamic raw,
    [Map athletes = const {}]) {
  final out = <String, dynamic>{
    'league': jsStr(league),
    'teamId': jsStr(teamId),
    'categories': <Map<String, dynamic>>[],
  };
  final cats = field(raw, 'categories');
  if (cats is! List || cats.isEmpty) return out;
  final list = out['categories'] as List<Map<String, dynamic>>;
  for (final c in cats) {
    if (list.length >= _maxCategories) break;
    final leaders = field(c, 'leaders');
    final top = (leaders is List && leaders.isNotEmpty) ? leaders.first : null;
    if (top == null) continue;
    final aid = athleteIdFromRef(field(field(top, 'athlete'), '\$ref'));
    if (aid == null) continue;
    final ath = athletes[aid];
    final name = or([field(ath, 'displayName'), field(ath, 'fullName'), field(ath, 'shortName')]);
    if (!truthy(name)) continue; // no resolvable name → drop
    final dv = field(top, 'displayValue') ?? field(top, 'value') ?? '';
    final row = <String, dynamic>{
      'name': jsStr(or([field(c, 'name'), ''])),
      'label': jsStr(or([
        field(c, 'shortDisplayName'),
        field(c, 'displayName'),
        field(c, 'abbreviation'),
        field(c, 'name'),
        ''
      ])),
      'athleteId': jsStr(aid),
      'athlete': jsStr(name),
      'displayValue': jsStr(dv),
    };
    final pos = _positionOf(ath);
    if (pos != null) row['position'] = pos;
    final hs = _headshotOf(ath);
    if (hs != null) row['headshot'] = hs;
    list.add(row);
  }
  return out;
}
