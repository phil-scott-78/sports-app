// rankings.dart — Dart port of worker/src/rankings.js. ESPN rankings → compact
// polls list (college polls / ATP-WTA tours / UFC divisions). Pure. Entries carry
// EITHER team OR athlete, never both.

import 'util.dart';

Map<String, dynamic> _teamOf(dynamic t) {
  t ??= {};
  final logo = https(or([field(first(field(t, 'logos')), 'href'), field(t, 'logo')]));
  final joined = [field(t, 'location'), field(t, 'name')].where((v) => truthy(v)).join(' ');
  final name = or([field(t, 'displayName'), joined, field(t, 'nickname'), field(t, 'shortDisplayName'), field(t, 'abbreviation'), '']);
  return pickT({
    'id': jsStr(field(t, 'id') ?? ''),
    'name': name,
    'abbr': field(t, 'abbreviation'),
    'logo': logo,
    'logoDark': darkFromLogos(t),
    'color': field(t, 'color'),
  }, ['id', 'name', 'abbr', 'logo', 'logoDark', 'color']);
}

Map<String, dynamic> _athleteOf(dynamic a) {
  a ??= {};
  return pickT({
    'id': jsStr(field(a, 'id') ?? ''),
    'name': or([field(a, 'displayName'), field(a, 'shortname'), field(a, 'fullName'), '']),
    'country': or([field(field(a, 'flag'), 'alt'), field(a, 'citizenship')]),
    'headshot': https(or([field(field(a, 'headshot'), 'href'), field(a, 'headshot')])),
  }, ['id', 'name', 'country', 'headshot']);
}

Map<String, dynamic> normalizeRankings(dynamic raw) {
  String occOf(dynamic p) {
    final o = or([field(field(p, 'occurrence'), 'displayValue'), field(p, 'shortHeadline'), '']);
    return (o as String).length <= 40 ? o : '';
  }

  final polls = (field(raw, 'rankings') is List ? field(raw, 'rankings') as List : const [])
      .map((p) => {
            'name': or([field(p, 'name'), field(p, 'shortName'), '']),
            'shortName': or([field(p, 'shortName'), field(p, 'name'), '']),
            'occurrence': occOf(p),
            'ranks': (field(p, 'ranks') is List ? (field(p, 'ranks') as List) : const [])
                .take(25)
                .map((r) {
                  final e = pickT({
                    'current': field(r, 'current') is num ? field(r, 'current') : null,
                    'previous': field(r, 'previous') is num ? field(r, 'previous') : null,
                    'trend': field(r, 'trend'),
                    'record': field(r, 'recordSummary'),
                    'points': field(r, 'points') is num ? field(r, 'points') : null,
                    'champion': field(r, 'hasAccolade') == true ? true : null,
                  }, ['current', 'previous', 'trend', 'record', 'points', 'champion']);
                  if (field(r, 'team') != null) {
                    e['team'] = _teamOf(field(r, 'team'));
                  } else if (field(r, 'athlete') != null) {
                    e['athlete'] = _athleteOf(field(r, 'athlete'));
                  }
                  return e;
                })
                .where((e) => truthy(field(e['team'], 'name')) || truthy(field(e['athlete'], 'name')))
                .toList(),
          })
      .where((p) => (p['ranks'] as List).isNotEmpty)
      .toList();
  return {'polls': polls};
}
