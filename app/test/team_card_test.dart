import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:scores/src/models.dart';

void main() {
  test('TeamCard.fromJson parses last + next, tolerates null live', () {
    final raw = File('test/fixtures/teamcard_nba.json').readAsStringSync();
    final card = TeamCard.fromJson(jsonDecode(raw) as Map<String, dynamic>);

    expect(card.league, 'basketball/nba');
    expect(card.sport, 'basketball');
    expect(card.leagueName, 'NBA');
    expect(card.team.record, '46-36');
    expect(card.anyLive, isFalse);

    expect(card.live, isNull);
    expect(card.last, isNotNull);
    expect(card.last!.main!.status.isFinal, isTrue);
    // the favorite (id '2') won the last game
    final lastFav = card.last!.main!.competitors.firstWhere((c) => c.id == '2');
    expect(lastFav.isWinner, isTrue);
    expect(lastFav.score!.display, '123');

    expect(card.next, isNotNull);
    expect(card.next!.main!.status.isScheduled, isTrue);

    // live null → primary falls through to last result
    expect(card.primary, same(card.last));
  });

  test('TeamCard.fromJson tolerates an empty/offseason payload', () {
    final card = TeamCard.fromJson({
      'league': 'basketball/nba',
      'sport': 'basketball',
      'leagueName': 'NBA',
      'team': {'id': '2', 'displayName': 'Boston Celtics'},
      'anyLive': false,
    });
    expect(card.live, isNull);
    expect(card.last, isNull);
    expect(card.next, isNull);
    expect(card.primary, isNull);
    expect(card.team.record, isNull);
  });

  test('TeamRef.fromJson parses a picker entry', () {
    final t = TeamRef.fromJson({
      'id': '359',
      'displayName': 'Arsenal',
      'abbreviation': 'ARS',
      'logo': 'https://a.espncdn.com/i/teamlogos/soccer/500/359.png',
    });
    expect(t.id, '359');
    expect(t.displayName, 'Arsenal');
    expect(t.abbreviation, 'ARS');
    expect(t.logoDark, isNull);
  });

  test('FavoriteTeam round-trips through JSON', () {
    const f = FavoriteTeam(
      league: 'basketball/nba',
      teamId: '2',
      name: 'Boston Celtics',
      abbr: 'BOS',
      logo: 'https://x/2.png',
    );
    final back = FavoriteTeam.fromJson(jsonDecode(jsonEncode(f.toJson())) as Map<String, dynamic>);
    expect(back.league, f.league);
    expect(back.teamId, f.teamId);
    expect(back.name, f.name);
    expect(back.abbr, 'BOS');
    expect(back.logo, 'https://x/2.png');
    expect(back.id, 'basketball/nba#2');
  });
}
