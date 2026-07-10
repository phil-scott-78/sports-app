import 'package:flutter_test/flutter_test.dart';
import 'package:scores/src/marquee.dart';
import 'package:scores/src/models.dart';

// The big-games ranker (marquee.dart): data-presence rules over the canonical
// model — playoff series, postseason slates, finals/championship copy, ranked
// matchups — with a deliberately high bar (ordinary games return null).

Map<String, dynamic> _event({
  String id = 'e1',
  String phase = 'scheduled',
  bool live = false,
  String? round,
  List<String> notes = const [],
  String? weekLabel,
  Map<String, dynamic>? series,
  int? awayRank,
  int? homeRank,
  String start = '2026-06-01T00:00Z',
}) =>
    {
      'id': id,
      'name': 'Cavaliers at Thunder',
      'shortName': 'CLE @ OKC',
      'start': start,
      'notes': notes,
      if (weekLabel != null) 'weekLabel': weekLabel,
      'competitions': [
        {
          'id': id,
          'layout': 'headToHead',
          'scoreKind': 'numeric',
          'competitorKind': 'team',
          'status': {
            'phase': phase,
            'live': live,
            'ended': phase == 'final',
            'period': live ? 2 : 0,
            'periodLabel': '',
            'espnName': live ? 'STATUS_IN_PROGRESS' : 'STATUS_SCHEDULED',
            'detail': '',
          },
          'periods': {
            'unit': 'quarter',
            'regulation': 4,
            'played': 0,
            'isOvertime': false,
          },
          'competitors': [
            {
              'kind': 'team',
              'id': 'cle',
              'displayName': 'Cavaliers',
              'abbreviation': 'CLE',
              'homeAway': 'away',
              if (awayRank != null) 'rank': awayRank,
            },
            {
              'kind': 'team',
              'id': 'okc',
              'displayName': 'Thunder',
              'abbreviation': 'OKC',
              'homeAway': 'home',
              if (homeRank != null) 'rank': homeRank,
            },
          ],
          'meta': {
            if (round != null) 'round': round,
            if (series != null) 'series': series,
          },
        },
      ],
    };

SportEvent _parse(Map<String, dynamic> j) => SportEvent.fromJson(j);

Map<String, dynamic> _playoffSeries({int okc = 2, int cle = 2, int total = 7}) =>
    {
      'type': 'playoff',
      'total': total,
      'completed': false,
      'competitors': [
        {'id': 'okc', 'wins': okc},
        {'id': 'cle', 'wins': cle},
      ],
    };

void main() {
  group('marqueeOf', () {
    test('an ordinary game is not big', () {
      expect(marqueeOf('basketball/nba', 'NBA', _parse(_event())), isNull);
    });

    test('a playoff series game qualifies, a clincher outranks it', () {
      final plain = marqueeOf('basketball/nba', 'NBA',
          _parse(_event(round: 'West Semis', series: _playoffSeries(okc: 1, cle: 1))));
      expect(plain, isNotNull);
      expect(plain!.reason, 'West Semis');

      final clinch = marqueeOf('basketball/nba', 'NBA',
          _parse(_event(round: 'West Semis', series: _playoffSeries(okc: 3, cle: 1))));
      expect(clinch!.weight, greaterThan(plain.weight));
    });

    test('finals/championship copy is the top tier', () {
      final finals = marqueeOf('basketball/nba', 'NBA',
          _parse(_event(notes: ['NBA Finals - Game 5'])));
      expect(finals, isNotNull);
      expect(finals!.weight, 100);
      expect(finals.reason, 'NBA Finals - Game 5');

      final championship = marqueeOf('football/college-football', 'NCAAF',
          _parse(_event(notes: ['CFP National Championship'])));
      expect(championship!.weight, 100);

      final superBowl = marqueeOf(
          'football/nfl', 'NFL', _parse(_event(notes: ['Super Bowl LXI'])));
      expect(superBowl!.weight, 100);
    });

    test('semifinals clear the bar, quarterfinals do not', () {
      expect(
          marqueeOf('soccer/fifa.world', 'FIFA World Cup',
              _parse(_event(round: 'Semifinals'))),
          isNotNull);
      expect(
          marqueeOf('soccer/fifa.world', 'FIFA World Cup',
              _parse(_event(round: 'Quarterfinals'))),
          isNull);
    });

    test('a postseason slate makes every game an elimination game', () {
      final b = marqueeOf('football/nfl', 'NFL',
          _parse(_event(weekLabel: 'Divisional Round')),
          seasonType: 3);
      expect(b, isNotNull);
      expect(b!.reason, 'Divisional Round');
      // The same game in the regular season is nothing.
      expect(
          marqueeOf('football/nfl', 'NFL',
              _parse(_event(weekLabel: 'Divisional Round')),
              seasonType: 2),
          isNull);
    });

    test('ranked vs ranked: both top-10 beats both top-25; one ranked is nothing',
        () {
      final top10 = marqueeOf('football/college-football', 'NCAAF',
          _parse(_event(awayRank: 3, homeRank: 7)));
      expect(top10, isNotNull);
      expect(top10!.reason, 'Top-10 matchup');

      final top25 = marqueeOf('football/college-football', 'NCAAF',
          _parse(_event(awayRank: 3, homeRank: 22)));
      expect(top25, isNotNull);
      expect(top25!.weight, lessThan(top10.weight));

      expect(
          marqueeOf('football/college-football', 'NCAAF',
              _parse(_event(awayRank: 3))),
          isNull);
    });

    test('tagLine drops a stuttering league prefix', () {
      final finals = marqueeOf('basketball/nba', 'NBA',
          _parse(_event(notes: ['NBA Finals - Game 5'])))!;
      expect(finals.tagLine, 'NBA FINALS - GAME 5');
      final semis = marqueeOf('soccer/fifa.world', 'FIFA World Cup',
          _parse(_event(round: 'Semifinals')))!;
      expect(semis.tagLine, 'FIFA WORLD CUP · SEMIFINALS');
    });
  });

  group('pickBigGames + topBigGames', () {
    // A fixed "now" + LOCAL iso starts (no Z) so the today/yesterday recency
    // math is deterministic in any timezone.
    final now = DateTime(2026, 7, 8, 21);
    String at(DateTime d) => d.toIso8601String();

    test('reads the slate season type and skips ordinary events', () {
      final scores = ScoresResponse.fromJson({
        'league': 'football/nfl',
        'leagueName': 'NFL',
        'season': {'type': 3},
        'events': [
          _event(id: 'a', weekLabel: 'Wild Card', start: at(DateTime(2026, 7, 8, 19))),
        ],
      });
      final picked = pickBigGames('football/nfl', scores, now: now);
      expect(picked, hasLength(1));
      expect(picked.first.reason, 'Wild Card');

      final regular = ScoresResponse.fromJson({
        'league': 'football/nfl',
        'leagueName': 'NFL',
        'season': {'type': 2},
        'events': [
          _event(id: 'a', weekLabel: 'Week 5', start: at(DateTime(2026, 7, 8, 19))),
        ],
      });
      expect(pickBigGames('football/nfl', regular, now: now), isEmpty);
    });

    test(
        'recency gate: today/yesterday qualify, a months-old offseason replay '
        'does not, live always does', () {
      // ESPN's offseason scoreboard keeps replaying the last played slate —
      // the April championship must NOT resurface as a July "big game".
      final scores = ScoresResponse.fromJson({
        'league': 'basketball/mens-college-basketball',
        'leagueName': 'NCAAM',
        'events': [
          _event(
              id: 'stale',
              phase: 'final',
              notes: ['NCAA Championship'],
              start: at(DateTime(2026, 4, 6, 21))),
          _event(
              id: 'today',
              notes: ['NCAA Championship'],
              start: at(DateTime(2026, 7, 8, 19))),
          _event(
              id: 'yday',
              phase: 'final',
              notes: ['NCAA Championship'],
              start: at(DateTime(2026, 7, 7, 20))),
          // A live multi-day event (golf-major shape): current whatever its start.
          _event(
              id: 'live-old',
              phase: 'live',
              live: true,
              notes: ['NCAA Championship'],
              start: at(DateTime(2026, 7, 4, 10))),
        ],
      });
      final ids = pickBigGames('basketball/mens-college-basketball', scores,
              now: now)
          .map((b) => b.event.id)
          .toList();
      expect(ids, containsAll(['today', 'yday', 'live-old']));
      expect(ids, isNot(contains('stale')));
    });

    test('sorts biggest first, live before scheduled within a weight, and caps',
        () {
      BigGame big(String id, {String? round, List<String> notes = const [],
              bool live = false, Map<String, dynamic>? series}) =>
          marqueeOf('basketball/nba', 'NBA',
              _parse(_event(
                  id: id,
                  round: round,
                  notes: notes,
                  live: live,
                  phase: live ? 'live' : 'scheduled',
                  series: series)))!;

      final finals = big('finals', notes: ['NBA Finals - Game 5']);
      final playoffLive =
          big('p-live', round: 'West Semis', live: true, series: _playoffSeries());
      final playoffSched =
          big('p-sched', round: 'East Semis', series: _playoffSeries());

      final top = topBigGames([playoffSched, finals, playoffLive], cap: 2);
      expect(top.map((b) => b.event.id), ['finals', 'p-live']);
    });
  });
}
