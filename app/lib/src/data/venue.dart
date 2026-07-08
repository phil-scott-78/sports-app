// venue.dart — Dart port of worker/src/venue.js. The Venue & Circuit "facts" tier
// (canonical VenueFacts / CircuitFacts; SCORES-APP-BUILD-SPEC §2.9). Pure map→map,
// verified byte-for-byte against the JS oracle via test/port_venue_test.dart.
//
// Two shapes, chosen by data presence (never sport name), exactly as the tab
// dispatches: stadium → core venues/{id} → [normalizeVenueFacts]; F1 circuit →
// core circuits/{id} (+ resolved fastestLapDriver) → [normalizeCircuitFacts].
// Every path is OBSERVED in schema/espn-guide/core-venues-id.md /
// core-circuits-id.md; NOT-OBSERVED facts (stadium capacity/opened, wind) are
// omitted, never faked (ledger #24–#25).

import 'util.dart';

num? _numOrU(dynamic v) => (v is num && v.isFinite) ? v : null;

// images[]/diagrams[] → [{href, rel}] (drop always-"" alt + fixed CDN dims).
List<Map<String, dynamic>>? _mapMedia(dynamic arr) {
  if (arr is! List) return null;
  final out = <Map<String, dynamic>>[];
  for (final m in arr) {
    final href = field(m, 'href');
    if (href is! String) continue;
    final rel = field(m, 'rel');
    out.add({
      'href': https(href),
      'rel': rel is List ? [for (final r in rel) if (r is String) r] : <String>[],
    });
  }
  return out.isEmpty ? null : out;
}

// Pick one href by ordered rel-token preference; within a rel prefer .svg over
// .jpg. Falls back to the first media href when no token matches.
String? _pickByRel(List<Map<String, dynamic>>? media, List<String> order) {
  if (media == null || media.isEmpty) return null;
  for (final tok in order) {
    final hits = media.where((m) => (m['rel'] as List).contains(tok)).toList();
    if (hits.isEmpty) continue;
    final svg = hits.firstWhere(
        (m) => RegExp(r'\.svg(\?|$)', caseSensitive: false).hasMatch(m['href'] as String),
        orElse: () => hits.first);
    return svg['href'] as String;
  }
  return media.first['href'] as String;
}

// "7.004 km" → {value: 7.004, unit: 'km', display: '7.004 km'}. null/empty → null.
Map<String, dynamic>? _parseMeasure(dynamic s) {
  if (s is! String || s.trim().isEmpty) return null;
  final display = s.trim();
  final out = <String, dynamic>{'display': display};
  final m = RegExp(r'^([\d.]+)\s*(.*)$').firstMatch(display);
  if (m != null) {
    final value = double.tryParse(m.group(1)!);
    if (value != null && value.isFinite) out['value'] = value;
    final unit = (m.group(2) ?? '').trim();
    if (unit.isNotEmpty) out['unit'] = unit;
  }
  return out;
}

/// Stadium facts (core venues/{id}). grass → surface, indoor → roof, address,
/// images (+ preferred photo). Non-F1 racing degrades to length(mi)/turns here.
Map<String, dynamic>? normalizeVenueFacts(dynamic raw) {
  if (raw is! Map || raw['id'] == null) return null;
  final a = raw['address'] is Map ? raw['address'] as Map : const {};
  final images = _mapMedia(raw['images']);
  final out = <String, dynamic>{
    'id': raw['id'].toString(),
    'name': or([raw['fullName'], raw['shortName'], '']),
    ...pickNN(
        {'city': a['city'], 'state': a['state'], 'country': a['country'], 'address1': a['address1']},
        ['city', 'state', 'country', 'address1']),
  };
  if (images != null) {
    out['images'] = images;
    final photo = _pickByRel(images, ['day', 'full', 'interior']);
    if (photo != null) out['photo'] = photo;
  }
  if (raw['grass'] is bool) out['surface'] = raw['grass'] == true ? 'grass' : 'turf';
  if (raw['indoor'] is bool) out['roof'] = raw['indoor'] == true ? 'indoor' : 'open';
  final length = _numOrU(raw['length']);
  if (length != null) out['length'] = length;
  final turns = _numOrU(raw['turns']);
  if (turns != null) out['turns'] = turns;
  return out;
}

// Resolved fastestLapDriver.$ref athlete → {name, headshot?}.
Map<String, dynamic>? _buildDriver(dynamic driver) {
  if (driver is! Map) return null;
  final name = or([driver['displayName'], driver['fullName'], driver['shortName'], null]);
  if (name == null) return null;
  final out = <String, dynamic>{'name': name.toString()};
  final hs = https(field(driver['headshot'], 'href') ?? driver['headshot']);
  if (hs != null) out['headshot'] = hs;
  return out;
}

/// F1 circuit facts (core circuits/{id}). [driver] is the pre-resolved
/// fastestLapDriver athlete doc (caller follows the $ref once, cached).
Map<String, dynamic>? normalizeCircuitFacts(dynamic raw, dynamic driver) {
  if (raw is! Map || raw['id'] == null) return null;
  final a = raw['address'] is Map ? raw['address'] as Map : const {};
  final diagrams = _mapMedia(raw['diagrams']);
  final out = <String, dynamic>{
    'id': raw['id'].toString(),
    'name': or([raw['fullName'], '']),
    ...pickNN({'city': a['city'], 'country': a['country']}, ['city', 'country']),
  };
  if (diagrams != null) {
    out['diagrams'] = diagrams;
    final diagram = _pickByRel(diagrams, ['circuit-dark', 'circuit', 'day-dark', 'day']);
    if (diagram != null) out['diagram'] = diagram;
  }
  if (raw['direction'] is String && (raw['direction'] as String).isNotEmpty) {
    out['direction'] = raw['direction'];
  }
  final established = _numOrU(raw['established']);
  if (established != null) out['established'] = established;
  final length = _parseMeasure(raw['length']);
  if (length != null) out['length'] = length;
  final distance = _parseMeasure(raw['distance']);
  if (distance != null) out['distance'] = distance;
  final laps = _numOrU(raw['laps']);
  if (laps != null) out['laps'] = laps;
  final turns = _numOrU(raw['turns']);
  if (turns != null) out['turns'] = turns;
  final lap = <String, dynamic>{};
  if (raw['fastestLapTime'] is String && (raw['fastestLapTime'] as String).isNotEmpty) {
    lap['time'] = raw['fastestLapTime'];
  }
  final year = _numOrU(raw['fastestLapYear']);
  if (year != null) lap['year'] = year;
  final drv = _buildDriver(driver);
  if (drv != null) lap['driver'] = drv;
  if (lap.isNotEmpty) out['fastestLap'] = lap;
  return out;
}
