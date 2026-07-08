// athlete.dart — Dart port of worker/src/athlete.js. The athlete/player profile
// tier (canonical AthleteProfile; SCORES-APP-BUILD-SPEC §2.6). Pure map→map,
// verified byte-for-byte against the JS oracle via test/port_athlete_test.dart.
//
// The RICH, lazy, on-open detail for one player — identity + season stats + a
// last-N game log. NEVER on the cheap scoreboard poll: the caller (api.dart) does
// the CORE fetches + the $ref fan-out and hands this normalizer the pre-resolved
// raws; this file only shapes them. Every path is OBSERVED in the espn-guide
// core-athletes pages + a live probe (MLB/WNBA, 2026-07); not-observed fields are
// omitted, never faked. See the JS oracle header for the full input contract.

import 'util.dart';

// Dark-mode logo: explicit 'dark' rel, else the /500/→/500-dark/ derivation. Same
// rule as standings/rankings — util.dart's darkFromLogos is the shared port.
String? _darkLogoOf(dynamic team) => darkFromLogos(team);

// headshot.href (or bare string) → https.
String? _headshotOf(dynamic o) => https(field(field(o, 'headshot'), 'href') ?? field(o, 'headshot'));

// position.abbreviation (preferred) falling back to displayName.
String? _positionOf(dynamic o) {
  final p = field(o, 'position');
  if (p is! Map) return null;
  final abbr = p['abbreviation'];
  if (abbr != null && abbr != '') return abbr.toString();
  final dn = p['displayName'];
  if (dn != null && dn != '') return dn.toString();
  return null;
}

// splits.categories[] → compact [{name, displayName?, stats:[cell]}]. Shared by
// season totals and the per-game line. Drops `description`; keeps only cells with a
// name + displayValue. Empty categories dropped; null when nothing survives.
List<Map<String, dynamic>>? _buildStatCategories(dynamic statsDoc) {
  final cats = field(field(statsDoc, 'splits'), 'categories');
  if (cats is! List || cats.isEmpty) return null;
  final out = <Map<String, dynamic>>[];
  for (final c in cats) {
    final rawStats = field(c, 'stats');
    final cells = <Map<String, dynamic>>[];
    for (final s in rawStats is List ? rawStats : const []) {
      if (s is! Map) continue;
      final name = s['name'];
      if (name == null || name == '' || s['displayValue'] == null) continue;
      final cell = <String, dynamic>{
        'name': name.toString(),
        'displayValue': s['displayValue'].toString(),
      };
      if (s['abbreviation'] != null && s['abbreviation'] != '') cell['abbreviation'] = s['abbreviation'].toString();
      if (s['displayName'] != null && s['displayName'] != '') cell['displayName'] = s['displayName'].toString();
      if (s['shortDisplayName'] != null && s['shortDisplayName'] != '') cell['shortDisplayName'] = s['shortDisplayName'].toString();
      final v = s['value'];
      if (v is num && v.isFinite) cell['value'] = v;
      cells.add(cell);
    }
    if (cells.isEmpty) continue;
    final cat = <String, dynamic>{
      'name': or([field(c, 'name'), field(c, 'abbreviation'), '']).toString(),
      'stats': cells,
    };
    final dn = field(c, 'displayName');
    if (dn != null && dn != '') cat['displayName'] = dn.toString();
    out.add(cat);
  }
  return out.isEmpty ? null : out;
}

// One last-N row from a resolved eventlog item {eventId, teamId, event, statistics}.
Map<String, dynamic>? _buildGameRow(dynamic g) {
  if (g is! Map || g['eventId'] == null) return null;
  final row = <String, dynamic>{'eventId': g['eventId'].toString()};
  final ev = g['event'];
  if (ev is Map) {
    if (ev['date'] is String && (ev['date'] as String).isNotEmpty) row['date'] = ev['date'];
    if (ev['name'] is String && (ev['name'] as String).isNotEmpty) row['name'] = ev['name'];
    if (ev['shortName'] is String && (ev['shortName'] as String).isNotEmpty) row['shortName'] = ev['shortName'];
  }
  if (g['teamId'] != null && g['teamId'] != '') row['teamId'] = g['teamId'].toString();
  final stats = _buildStatCategories(g['statistics']);
  if (stats != null) row['stats'] = stats;
  return row;
}

// team.$ref doc → the athlete's team block. null-safe.
Map<String, dynamic>? _buildTeam(dynamic team) {
  if (team is! Map || team['id'] == null) return null;
  final out = <String, dynamic>{
    'id': team['id'].toString(),
    'name': or([team['displayName'], team['name'], team['shortDisplayName'], '']),
  };
  if (truthy(team['abbreviation'])) out['abbr'] = team['abbreviation'].toString();
  if (truthy(team['color'])) out['color'] = team['color'].toString();
  final logo = https(field(first(field(team, 'logos')), 'href'));
  if (logo != null) out['logo'] = logo;
  final dark = _darkLogoOf(team);
  if (dark != null) out['logoDark'] = dark;
  return out;
}

/// Compose a canonical AthleteProfile from the pre-resolved CORE inputs.
/// [parts] = {identity, team, statistics, games}.
Map<String, dynamic> normalizeAthleteProfile(
    String league, String athleteId, Map<String, dynamic> parts) {
  final identity = parts['identity'];
  final idn = identity is Map ? identity : const {};
  final out = <String, dynamic>{
    'id': (idn['id'] ?? athleteId).toString(),
    'league': league,
    'name': or([idn['displayName'], idn['fullName'], idn['shortName'], '']),
  };
  if (truthy(idn['shortName'])) out['shortName'] = idn['shortName'].toString();
  if (idn['jersey'] != null && idn['jersey'] != '') out['jersey'] = idn['jersey'].toString();
  final pos = _positionOf(idn);
  if (pos != null) out['position'] = pos;
  final hs = _headshotOf(idn);
  if (hs != null) out['headshot'] = hs;
  final age = idn['age'];
  if (age is num && age.isFinite) out['age'] = age;
  if (idn['displayHeight'] is String && (idn['displayHeight'] as String).isNotEmpty) {
    out['height'] = idn['displayHeight'];
  }
  if (idn['displayWeight'] is String && (idn['displayWeight'] as String).isNotEmpty) {
    out['weight'] = idn['displayWeight'];
  }

  final tm = _buildTeam(parts['team']);
  if (tm != null) out['team'] = tm;

  final stats = _buildStatCategories(parts['statistics']);
  if (stats != null) out['stats'] = stats;

  final games = parts['games'];
  if (games is List && games.isNotEmpty) {
    final rows = <Map<String, dynamic>>[];
    for (final g in games) {
      final r = _buildGameRow(g);
      if (r != null) rows.add(r);
    }
    if (rows.isNotEmpty) out['lastGames'] = rows;
  }
  return out;
}
