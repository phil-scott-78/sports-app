// scorecard.dart — Dart port of worker/src/scorecard.js. Golf hole-by-hole
// player summary → canonical GolfScorecardResponse. Pure.

import 'util.dart';

const _statKeep = {
  'scoreToPar', 'regScore', 'birdies', 'eagles',
  'driveDistAvg', 'driveAccuracyPct', 'greensInRegulationPct', 'puttsPerHole',
};

Map<String, dynamic> normalizeGolfScorecard(String key, dynamic eventId, dynamic playerId, dynamic raw) {
  final prof = field(raw, 'profile') ?? {};
  final player = pickT({
    'id': jsStr(field(prof, 'id') ?? playerId),
    'name': or([field(prof, 'displayName'), field(prof, 'shortName'), '']),
    'headshot': https(or([field(field(prof, 'headshot'), 'href'), field(prof, 'headshot')])),
    'country': or([field(field(prof, 'flag'), 'alt'), field(prof, 'citizenship')]),
  }, ['id', 'name', 'headshot', 'country']);

  final rounds = <Map<String, dynamic>>[];
  for (final r in (field(raw, 'rounds') is List ? field(raw, 'rounds') as List : const [])) {
    final holes = <Map<String, dynamic>>[];
    for (final h in (field(r, 'linescores') is List ? field(r, 'linescores') as List : const [])) {
      final hole = pickT({
        'hole': field(h, 'period') is num ? field(h, 'period') : null,
        'par': field(h, 'par') is num ? field(h, 'par') : null,
        'strokes': field(h, 'value') is num ? field(h, 'value') : null,
        'scoreType': field(field(h, 'scoreType'), 'name'),
      }, ['hole', 'par', 'strokes', 'scoreType']);
      if (hole['hole'] != null) holes.add(hole);
    }
    final round = pickT({
      'round': field(r, 'period') is num ? field(r, 'period') : null,
      'strokes': (field(r, 'value') is num && (field(r, 'value') as num) > 0) ? field(r, 'value') : null,
      'toPar': (field(r, 'displayValue') != null && field(r, 'displayValue') != '-') ? jsStr(field(r, 'displayValue')) : null,
      'outScore': (field(r, 'outScore') is num && (field(r, 'outScore') as num) > 0) ? field(r, 'outScore') : null,
      'inScore': (field(r, 'inScore') is num && (field(r, 'inScore') as num) > 0) ? field(r, 'inScore') : null,
      'teeTime': field(r, 'teeTime'),
      'startTee': field(r, 'startTee') is num ? field(r, 'startTee') : null,
      'groupNumber': field(r, 'groupNumber') is num ? field(r, 'groupNumber') : null,
      'currentPosition': field(r, 'currentPosition') is num ? field(r, 'currentPosition') : null,
    }, ['round', 'strokes', 'toPar', 'outScore', 'inScore', 'teeTime', 'startTee', 'groupNumber', 'currentPosition']);
    round['holes'] = holes;
    if (round['round'] != null) rounds.add(round);
  }

  final stats = (field(raw, 'stats') is List ? field(raw, 'stats') as List : const [])
      .where((s) => _statKeep.contains(field(s, 'name')) && field(s, 'displayValue') != null && field(s, 'displayValue') != '')
      .map((s) => {'name': field(s, 'name'), 'label': or([field(s, 'displayName'), field(s, 'name')]), 'value': jsStr(field(s, 'displayValue'))})
      .toList();

  final out = <String, dynamic>{'league': key, 'eventId': jsStr(eventId), 'player': player, 'rounds': rounds};
  if (stats.isNotEmpty) out['stats'] = stats;
  return out;
}
