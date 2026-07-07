// teamdetail.dart — Dart port of worker/src/teamdetail.js. The RICH tier for a
// team page: full-season schedule + roster + season stats + this team's standings
// group. Reuses buildEvent + normalizeStandings + teamIdentityOf so card, detail,
// and standings never fork. Roster/stats discriminate STRUCTURALLY, never by sport.

import 'profiles.dart';
import 'util.dart';
import 'normalize.dart';
import 'standings.dart';
import 'team.dart';

String _titleCase(dynamic s) =>
    jsStr(s).replaceAllMapped(RegExp(r'\b\w'), (m) => m.group(0)!.toUpperCase());

// ---- roster -----------------------------------------------------------------
Map<String, dynamic> _mapAthlete(dynamic a) {
  final o = <String, dynamic>{
    'id': jsStr(field(a, 'id') ?? ''),
    'name': or([field(a, 'displayName'), field(a, 'fullName'), field(a, 'shortName'), '']),
  };
  if (field(a, 'jersey') != null && field(a, 'jersey') != '') o['jersey'] = jsStr(field(a, 'jersey'));
  if (field(field(a, 'position'), 'abbreviation') != null) o['position'] = field(field(a, 'position'), 'abbreviation');
  final hs = https(or([field(field(a, 'headshot'), 'href'), field(a, 'headshot')]));
  if (hs != null) o['headshot'] = hs;
  return o;
}

List<Map<String, dynamic>> _buildRoster(dynamic roster) {
  final athletes = field(roster, 'athletes');
  if (athletes is! List || athletes.isEmpty) return [];
  final grouped = athletes.any((e) => field(e, 'items') is List);
  if (grouped) {
    return athletes
        .where((g) => field(g, 'items') is List && (field(g, 'items') as List).isNotEmpty)
        .map((g) => {
              'name': _titleCase(or([field(g, 'position'), field(g, 'name'), 'Group'])),
              'athletes': (field(g, 'items') as List).map(_mapAthlete).where((a) => truthy(a['id'])).toList(),
            })
        .where((g) => (g['athletes'] as List).isNotEmpty)
        .toList();
  }
  return [
    {'name': 'Roster', 'athletes': athletes.map(_mapAthlete).where((a) => truthy(a['id'])).toList()}
  ];
}

// ---- season stats -----------------------------------------------------------
Map<String, dynamic>? _mapStat(dynamic s) {
  final value = field(s, 'displayValue') ?? (field(s, 'value') != null ? jsStr(field(s, 'value')) : null);
  if (value == null) return null;
  final o = <String, dynamic>{
    'name': or([field(s, 'name'), field(s, 'abbreviation'), '']),
    'label': or([field(s, 'shortDisplayName'), field(s, 'displayName'), field(s, 'name'), '']),
    'value': jsStr(value),
  };
  if (truthy(field(s, 'abbreviation'))) o['abbr'] = field(s, 'abbreviation');
  if (field(s, 'rank') is num) o['rank'] = field(s, 'rank');
  return o;
}

List<Map<String, dynamic>> _buildStats(Map profile, dynamic stats) {
  final cats = field(field(field(stats, 'results'), 'stats'), 'categories');
  if (cats is! List || cats.isEmpty) return [];
  final keys = profile['teamStatKeys'];
  if (keys is List && keys.isNotEmpty) {
    final byName = <String, dynamic>{};
    for (final c in cats) {
      for (final s in (field(c, 'stats') is List ? field(c, 'stats') as List : const [])) {
        final n = field(s, 'name');
        if (n != null && byName[n] == null) byName[n] = s;
      }
    }
    final picked = keys.map((k) => byName[k]).where((s) => s != null).map(_mapStat).where((s) => s != null).cast<Map<String, dynamic>>().toList();
    return picked.isNotEmpty ? [{'name': 'Season', 'stats': picked}] : [];
  }
  return cats
      .map((c) => {
            'name': or([field(c, 'displayName'), field(c, 'name'), '']),
            'stats': (field(c, 'stats') is List ? (field(c, 'stats') as List).take(8) : const []).map(_mapStat).where((s) => s != null).cast<Map<String, dynamic>>().toList(),
          })
      .where((g) => (g['stats'] as List).isNotEmpty)
      .toList();
}

// ---- standing (this team's group only) --------------------------------------
Map<String, dynamic>? _pluckStanding(Map profile, dynamic standingsRaw, dynamic teamId) {
  if (standingsRaw == null) return null;
  final groups = normalizeStandings(standingsRaw);
  final id = jsStr(teamId);
  for (final g in groups) {
    if ((g['rows'] as List).any((r) => field(field(r, 'team'), 'id') == id)) {
      return {'groupName': g['name'], 'columns': profile['standingsColumns'], 'rows': g['rows']};
    }
  }
  return null;
}

// ---- top level --------------------------------------------------------------
Map<String, dynamic> normalizeTeamDetail(Registry reg, String key, dynamic teamId, [Map parts = const {}]) {
  final schedule = parts['schedule'];
  final roster = parts['roster'];
  final stats = parts['stats'];
  final standingsRaw = parts['standingsRaw'];
  final profile = resolve(reg, key);
  final team = teamIdentityOf(profile, field(schedule, 'team'), teamId);

  final events = (field(schedule, 'events') is List ? field(schedule, 'events') as List : const [])
      .map((e) => buildEvent(profile, e as Map))
      .toList();
  events.sort((a, b) {
    final da = DateTime.tryParse(jsStr(a['start']))?.millisecondsSinceEpoch ?? 0;
    final db = DateTime.tryParse(jsStr(b['start']))?.millisecondsSinceEpoch ?? 0;
    return da.compareTo(db);
  });

  final out = <String, dynamic>{
    'league': key,
    'sport': profile['espnSport'],
    'leagueName': or([profile['name'], key.split('/').length > 1 ? key.split('/')[1] : null, '']),
    'team': team,
    'schedule': events,
    'roster': _buildRoster(roster),
    'stats': _buildStats(profile, stats),
  };
  final standing = _pluckStanding(profile, standingsRaw, teamId);
  if (standing != null) out['standing'] = standing;
  return out;
}
