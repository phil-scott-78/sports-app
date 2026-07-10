import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scores/src/api.dart';
import 'package:scores/src/marquee.dart';
import 'package:scores/src/models.dart';
import 'package:scores/src/providers.dart';
import 'package:scores/src/theme.dart';
import 'package:scores/src/ui/scores_page.dart';
import 'package:scores/src/ui/today_page.dart';

// The two home-feed discovery paths: the BIG GAMES section (marquee games from
// unfollowed flagship leagues) and the "All games today" row → TodayPage
// (every league on today, one section per league).

Future<SharedPreferences> prefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

Widget wrap(Widget child, List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(theme: buildV2Theme(), home: Scaffold(body: child)),
    );

Map<String, dynamic> _eventJson(
        {String id = 'g1', bool live = false, String? round,
        Map<String, dynamic>? series}) =>
    {
      'id': id,
      'name': 'Cavaliers at Thunder',
      'shortName': 'CLE @ OKC',
      'start': '2026-06-01T00:00Z',
      'competitions': [
        {
          'id': id,
          'layout': 'headToHead',
          'scoreKind': 'numeric',
          'competitorKind': 'team',
          'status': {
            'phase': live ? 'live' : 'scheduled',
            'live': live,
            'ended': false,
            'period': live ? 3 : 0,
            'periodLabel': live ? 'Q3' : '',
            'espnName': live ? 'STATUS_IN_PROGRESS' : 'STATUS_SCHEDULED',
            'detail': live ? 'Q3 4:12' : '7:30 PM',
          },
          'periods': {
            'unit': 'quarter',
            'regulation': 4,
            'played': live ? 3 : 0,
            'isOvertime': false,
          },
          'competitors': [
            {
              'kind': 'team',
              'id': 'cle',
              'displayName': 'Cavaliers',
              'abbreviation': 'CLE',
              'homeAway': 'away',
              'color': '860038',
              if (live) 'score': {'value': 88, 'display': '88'},
            },
            {
              'kind': 'team',
              'id': 'okc',
              'displayName': 'Thunder',
              'abbreviation': 'OKC',
              'homeAway': 'home',
              'color': '007ac1',
              if (live) 'score': {'value': 92, 'display': '92'},
            },
          ],
          'meta': {
            if (round != null) 'round': round,
            if (series != null) 'series': series,
          },
        },
      ],
    };

ScoresResponse _slate(String key, String name,
        {List<Map<String, dynamic>> events = const []}) =>
    ScoresResponse.fromJson({
      'league': key,
      'leagueName': name,
      'events': events,
    });

BigGame _bigGame() => marqueeOf(
      'basketball/nba',
      'NBA',
      SportEvent.fromJson(_eventJson(
        live: true,
        round: 'West Finals',
        series: {
          'type': 'playoff',
          'total': 7,
          'completed': false,
          'competitors': [
            {'id': 'okc', 'wins': 3},
            {'id': 'cle', 'wins': 2},
          ],
        },
      )),
    )!;

List<Override> _homeOverrides(SharedPreferences p, List<BigGame> bigs) => [
      sharedPrefsProvider.overrideWithValue(p),
      feedProvider.overrideWith((ref) async =>
          [LeagueFeed('baseball/mlb', _slate('baseball/mlb', 'MLB'))]),
      favoritesFeedProvider
          .overrideWith((ref) async => const <FavoriteTeamFeed>[]),
      feedFreshnessProvider
          .overrideWith((ref) => const FeedFreshness(stale: false)),
      bigGamesProvider.overrideWith((ref) async => bigs),
      homeCoverageProvider.overrideWith((ref) async => const <String>{}),
    ];

void main() {
  testWidgets('BIG GAMES: a marquee game from an unfollowed league surfaces',
      (tester) async {
    final p = await prefs();
    await tester
        .pumpWidget(wrap(const ScoresPage(), _homeOverrides(p, [_bigGame()])));
    await tester.pump();
    await tester.pump();

    expect(find.text('BIG GAMES'), findsOneWidget);
    // The row tags its league/stakes and shows the game itself.
    expect(find.text('NBA · WEST FINALS'), findsOneWidget);
    expect(find.text('OKC'), findsOneWidget);
    expect(find.text('92'), findsOneWidget);
  });

  testWidgets('BIG GAMES: absent on an ordinary day', (tester) async {
    final p = await prefs();
    await tester
        .pumpWidget(wrap(const ScoresPage(), _homeOverrides(p, const [])));
    await tester.pump();
    await tester.pump();

    expect(find.text('BIG GAMES'), findsNothing);
    // The all-games row is a standing destination — present regardless.
    expect(find.text('All games today'), findsOneWidget);
  });

  testWidgets('All games today → TodayPage lists every on-today league',
      (tester) async {
    final p = await prefs();
    final pulse = {
      'basketball/nba': LeagueStateInfo.fromJson({
        'key': 'basketball/nba',
        'state': 'live',
        'detail': 'Live now',
        'live': true,
      }),
      'hockey/nhl': LeagueStateInfo.fromJson({
        'key': 'hockey/nhl',
        'state': 'today',
        'detail': 'Games today',
        'live': false,
      }),
      // Offseason league — must NOT get a section.
      'football/nfl': LeagueStateInfo.fromJson({
        'key': 'football/nfl',
        'state': 'offseason',
        'detail': 'Returns Sep 10',
        'live': false,
      }),
    };
    await tester.pumpWidget(wrap(const ScoresPage(), [
      ..._homeOverrides(p, const []),
      exploreOverviewProvider.overrideWith((ref) => Stream.value(pulse)),
      leagueScoresProvider.overrideWith((ref, k) async => _slate(
            k.league,
            k.league == 'basketball/nba' ? 'NBA' : 'NHL',
            events: [
              _eventJson(id: '${k.league}-1', live: k.league == 'basketball/nba')
            ],
          )),
    ]));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('All games today'));
    await tester.pumpAndSettle();

    expect(find.text('ALL GAMES'), findsOneWidget);
    expect(find.text('2 leagues on today · 1 live'), findsOneWidget);
    // Live league sorts first; both sections render; offseason league doesn't.
    expect(find.text('NBA'), findsOneWidget);
    expect(find.text('NHL'), findsOneWidget);
    expect(find.text('See all 1'), findsNWidgets(2));

    // Section header taps through to the league page.
    expect(find.byType(TodayPage), findsOneWidget);
  });
}
