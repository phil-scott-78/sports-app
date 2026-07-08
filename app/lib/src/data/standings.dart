// standings.dart — Dart port of worker/src/standings.js. ESPN nested standings
// (children[] conferences/groups) → flat { groups: [{ name, rows }] }. Racing
// championship tables ride the same path with athlete-shaped entries. Pure.

import 'util.dart';

// ESPN record `type` → the canonical column key merged into a row's stats.
// Mirrors SUBRECORD_TYPES in worker/src/standings.js.
const _subrecordTypes = {
  'lasttengames': 'l10',
  'vsdiv': 'div',
  'intradivision': 'div',
  'vsconf': 'conf',
  'intraleague': 'conf',
  'home': 'home',
  'road': 'away',
};

String? _teamIdFromRef(dynamic ref) {
  if (ref is! String) return null;
  return RegExp(r'/teams/(\d+)').firstMatch(ref)?.group(1);
}

/// One or more CORE group standings-id docs → { teamId: { l10, div, conf, home,
/// away } }. Port of extractGroupRecords in standings.js. Pure.
Map<String, Map<String, String>> extractGroupRecords(dynamic docs) {
  final out = <String, Map<String, String>>{};
  final list = docs is List ? docs : (docs != null ? [docs] : const []);
  for (final doc in list) {
    final standings = field(doc, 'standings');
    if (standings is! List) continue;
    for (final s in standings) {
      final id = _teamIdFromRef(field(field(s, 'team'), '\$ref'));
      if (id == null) continue;
      final bag = out.putIfAbsent(id, () => <String, String>{});
      for (final rec in (field(s, 'records') is List ? field(s, 'records') as List : const [])) {
        final key = _subrecordTypes[field(rec, 'type')];
        if (key == null) continue;
        final summary = field(rec, 'summary') ?? field(rec, 'displayValue');
        if (summary != null && summary != '') bag[key] = jsStr(summary);
      }
    }
  }
  return out;
}

/// [records] (optional) = the extractGroupRecords() map; when passed, each row's
/// stats gets its team's sub-records merged in. Omit → byte-identical to before.
List<Map<String, dynamic>> normalizeStandings(dynamic raw, [Map? records]) {
  final groups = <Map<String, dynamic>>[];
  final recs = records is Map ? records : null;
  void walk(dynamic node) {
    final entries = field(field(node, 'standings'), 'entries');
    if (entries is List && entries.isNotEmpty) {
      groups.add({
        'name': or([field(node, 'name'), field(node, 'abbreviation'), field(node, 'displayName'), '']),
        'rows': entries.map((en) {
          final stats = <String, dynamic>{};
          for (final s in (field(en, 'stats') is List ? field(en, 'stats') as List : const [])) {
            final k = or([field(s, 'name'), field(s, 'type')]);
            if (truthy(k)) stats[k] = field(s, 'displayValue') ?? field(s, 'value');
          }
          final who = field(en, 'team') ?? field(en, 'athlete');
          final id = jsStr(field(who, 'id') ?? '');
          final rec = recs != null ? recs[id] : null;
          if (rec is Map) {
            for (final e in rec.entries) {
              stats[e.key] = e.value;
            }
          }
          return pickNN({
            'team': pickNN({
              'id': id,
              'name': or([field(who, 'displayName'), field(who, 'name'), field(who, 'shortDisplayName'), '']),
              'abbr': field(who, 'abbreviation'),
              'logo': https(field(first(field(who, 'logos')), 'href')),
              'logoDark': darkFromLogos(who),
            }, ['id', 'name', 'abbr', 'logo', 'logoDark']),
            'rank': stats['rank'] != null ? num.tryParse(jsStr(stats['rank'])) : null,
            'stats': stats,
          }, ['team', 'rank', 'stats']);
        }).toList(),
      });
    }
    for (final child in (field(node, 'children') is List ? field(node, 'children') as List : const [])) {
      walk(child);
    }
  }

  walk(raw);
  return groups;
}
