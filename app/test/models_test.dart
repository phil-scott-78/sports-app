import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:scores/src/models.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  test('MLB scoreboard parses with live situations intact', () {
    final r = ScoresResponse.fromJson(fixture('mlb.json'));
    expect(r.league, isNotEmpty);
    expect(r.events, isNotEmpty);
    final live = r.events
        .map((e) => e.main)
        .whereType<Competition>()
        .where((c) => c.status.live)
        .toList();
    expect(live, isNotEmpty);
    final sit = live.map((c) => c.situation).whereType<Situation>().first;
    expect(sit.hasBaseball, isTrue);
    expect(sit.outs, isNotNull);
    // Discriminators present on every competition.
    for (final e in r.events) {
      expect(e.main!.layout, anyOf('headToHead', 'field'));
      expect(e.main!.competitorKind, isNotEmpty);
    }
  });

  test('NFL scoreboard parses', () {
    final r = ScoresResponse.fromJson(fixture('nfl.json'));
    expect(r.events, isNotEmpty);
    for (final e in r.events) {
      expect(e.main, isNotNull);
      expect(e.main!.competitors.length, 2);
    }
  });

  test('NFL summary parses into box groups and plays', () {
    final s = GameSummary.fromJson(fixture('summary_nfl.json'));
    expect(s.isEmpty, isFalse);
  });

  test('team card resolves primary event live ?? last ?? next', () {
    final c = TeamCard.fromJson(fixture('teamcard_nba.json'));
    expect(c.live, isNull);
    expect(c.primary, same(c.last));
    expect(c.team.displayName, isNotEmpty);
  });

  test('FavoriteTeam round-trips its cached color', () {
    const f = FavoriteTeam(
        league: 'baseball/mlb',
        teamId: '16',
        name: 'Chicago Cubs',
        abbr: 'CHC',
        color: 'cc3433');
    final back = FavoriteTeam.fromJson(
        jsonDecode(jsonEncode(f.toJson())) as Map<String, dynamic>);
    expect(back.color, 'cc3433');
    expect(back.id, f.id);
  });
}
