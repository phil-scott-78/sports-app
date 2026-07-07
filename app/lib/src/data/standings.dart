// standings.dart — Dart port of worker/src/standings.js. ESPN nested standings
// (children[] conferences/groups) → flat { groups: [{ name, rows }] }. Racing
// championship tables ride the same path with athlete-shaped entries. Pure.

import 'util.dart';

List<Map<String, dynamic>> normalizeStandings(dynamic raw) {
  final groups = <Map<String, dynamic>>[];
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
          return pickNN({
            'team': pickNN({
              'id': jsStr(field(who, 'id') ?? ''),
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
