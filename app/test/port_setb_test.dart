import 'package:flutter_test/flutter_test.dart';
import 'package:scores/src/data/profiles.dart';
import 'package:scores/src/data/overview.dart';
import 'package:scores/src/data/team.dart';
import 'package:scores/src/data/teamdetail.dart';
import 'package:scores/src/data/summary.dart';
import 'package:scores/src/data/normalize.dart';
import 'golden_util.dart';

// Phase 2 parity for overview classify + the live-captured Set B (team card with
// scoreboard fallback, teamdetail, MMA summary).
void main() {
  late Registry reg;
  setUpAll(() => reg = loadTestRegistry());

  for (final e in goldenIndex().where((e) => e['endpoint'] == 'overview')) {
    test('overview parity: ${e['key']}', () {
      final g = readGolden(e['file'] as String);
      final a = g['args'] as Map;
      final now = DateTime.fromMillisecondsSinceEpoch(a['nowMs'] as int, isUtc: true);
      final got = classifyLeague(a['sb'], now);
      expect(canonicalJson(got), canonicalJson(g['output']));
    });
  }

  for (final e in goldenIndex().where((e) => e['endpoint'] == 'teamCard')) {
    test('teamCard parity: ${e['key']}/${e['teamId']}', () {
      final g = readGolden(e['file'] as String);
      final a = g['args'] as Map;
      var card = normalizeTeamCard(reg, a['key'] as String, a['teamId'], a['schedule']);
      if (card['live'] == null) {
        card = applyScoreboardFallback(reg, a['key'] as String, a['teamId'], card, a['sb'] as Map);
      }
      expect(canonicalJson(card), canonicalJson(g['output']));
    });
  }

  for (final e in goldenIndex().where((e) => e['endpoint'] == 'teamDetail')) {
    test('teamDetail parity: ${e['key']}/${e['teamId']}', () {
      final g = readGolden(e['file'] as String);
      final a = g['args'] as Map;
      final got = normalizeTeamDetail(reg, a['key'] as String, a['teamId'], {
        'schedule': a['schedule'],
        'roster': a['roster'],
        'stats': a['stats'],
        'standingsRaw': a['standingsRaw'],
      });
      expect(canonicalJson(got), canonicalJson(g['output']));
    });
  }

  for (final e in goldenIndex().where((e) => e['endpoint'] == 'mma')) {
    test('mma parity: ${e['key']}/${e['eventId']}', () {
      final g = readGolden(e['file'] as String);
      final a = g['args'] as Map;
      final got = normalizeMmaSummary(a['coreEvent'], a['statuses'] as Map, a['linescores'] as Map);
      expect(canonicalJson(got), canonicalJson(g['output']));
    });
  }

  // Core competition-odds → canonical Odds (the pre-game moneyline enrichment).
  for (final e in goldenIndex().where((e) => e['endpoint'] == 'odds')) {
    test('odds parity: ${e['key']}/${e['eventId']}', () {
      final g = readGolden(e['file'] as String);
      final a = g['args'] as Map;
      final got = normalizeCompetitionOdds(a['raw']);
      expect(canonicalJson(got), canonicalJson(g['output']));
    });
  }
}
