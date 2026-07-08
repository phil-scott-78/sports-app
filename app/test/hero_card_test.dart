import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scores/src/models.dart';
import 'package:scores/src/providers.dart';
import 'package:scores/src/theme.dart';
import 'package:scores/src/ui/game_detail_page.dart';
import 'package:scores/src/ui/hero_card.dart';
import 'package:scores/src/ui/widgets.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

Future<SharedPreferences> prefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

Widget wrap(Widget child, List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
          theme: buildV2Theme(),
          home: Scaffold(body: Center(child: child))),
    );

FavoriteTeamFeed feedFor(TeamCard card) => FavoriteTeamFeed(
      FavoriteTeam(
        league: card.league,
        teamId: card.team.id,
        name: card.team.displayName,
        color: card.team.color,
      ),
      card,
    );

// Offline overrides for the pages a tap navigates to.
List<Override> navOverrides(SharedPreferences p, TeamCard card) => [
      sharedPrefsProvider.overrideWithValue(p),
      teamDetailProvider.overrideWith(
          (ref, k) async => TeamDetail.fromJson(fixture('teamdetail_nba.json'))),
      teamCardProvider.overrideWith((ref, k) async => card),
      leagueScoresProvider.overrideWith((ref, k) async => throw 'offline'),
      summaryProvider.overrideWith((ref, k) async => throw 'offline'),
    ];

/// A live NBA playoff card carrying a structured series (drives the derived
/// 'Game N · X leads' header + the series pips).
TeamCard seriesLiveCard() => TeamCard.fromJson({
      'league': 'basketball/nba',
      'sport': 'basketball',
      'leagueName': 'NBA',
      'team': {'id': 'okc', 'displayName': 'Thunder', 'abbreviation': 'OKC'},
      'live': {
        'id': 'e1',
        'name': 'Cavaliers at Thunder',
        'shortName': 'CLE @ OKC',
        'start': '2026-06-01T00:00Z',
        'competitions': [
          {
            'id': 'e1',
            'layout': 'headToHead',
            'scoreKind': 'numeric',
            'competitorKind': 'team',
            'status': {
              'phase': 'live',
              'live': true,
              'ended': false,
              'period': 4,
              'periodLabel': 'Q4',
              'espnName': 'STATUS_IN_PROGRESS',
              'detail': 'Q4 4:12',
              'shortDetail': 'Q4 4:12',
            },
            'periods': {
              'unit': 'quarter',
              'regulation': 4,
              'played': 4,
              'isOvertime': false,
            },
            'competitors': [
              {
                'kind': 'team',
                'id': 'okc',
                'displayName': 'Thunder',
                'abbreviation': 'OKC',
                'homeAway': 'home',
                'score': {'display': '88', 'value': 88},
              },
              {
                'kind': 'team',
                'id': 'cle',
                'displayName': 'Cavaliers',
                'abbreviation': 'CLE',
                'homeAway': 'away',
                'score': {'display': '84', 'value': 84},
              },
            ],
            'meta': {
              'series': {
                'type': 'playoff',
                'total': 7,
                'completed': false,
                'competitors': [
                  {'id': 'okc', 'wins': 3},
                  {'id': 'cle', 'wins': 2},
                ],
              },
            },
          },
        ],
      },
      'anyLive': true,
    });

/// A live NBA card carrying a cheap scoreboard win probability (no series) —
/// drives the hero-footer win-prob micro-bar (basketball-only, by data presence).
TeamCard winProbLiveCard() => TeamCard.fromJson({
      'league': 'basketball/nba',
      'sport': 'basketball',
      'leagueName': 'NBA',
      'team': {'id': 'okc', 'displayName': 'Thunder', 'abbreviation': 'OKC'},
      'live': {
        'id': 'e2',
        'name': 'Pacers at Thunder',
        'shortName': 'IND @ OKC',
        'start': '2026-06-01T00:00Z',
        'competitions': [
          {
            'id': 'e2',
            'layout': 'headToHead',
            'scoreKind': 'numeric',
            'competitorKind': 'team',
            'status': {
              'phase': 'live',
              'live': true,
              'ended': false,
              'period': 4,
              'periodLabel': 'Q4',
              'detail': 'Q4 3:00',
              'shortDetail': 'Q4 3:00',
              'espnName': 'STATUS_IN_PROGRESS',
            },
            'periods': {
              'unit': 'quarter',
              'regulation': 4,
              'played': 4,
              'isOvertime': false,
            },
            'competitors': [
              {
                'kind': 'team',
                'id': 'okc',
                'displayName': 'Thunder',
                'abbreviation': 'OKC',
                'homeAway': 'home',
                'color': '007ac1',
                'score': {'display': '92', 'value': 92},
              },
              {
                'kind': 'team',
                'id': 'ind',
                'displayName': 'Pacers',
                'abbreviation': 'IND',
                'homeAway': 'away',
                'color': '002d62',
                'score': {'display': '88', 'value': 88},
              },
            ],
            'situation': {'lastPlay': 'Jump shot good', 'homeWinPct': 62},
          },
        ],
      },
      'anyLive': true,
    });

void main() {
  testWidgets('live hero footer lights the win-prob bar when homeWinPct present',
      (tester) async {
    final p = await prefs();
    final card = winProbLiveCard();
    await tester.pumpWidget(
        wrap(FavoriteHeroCard(feedFor(card)), navOverrides(p, card)));
    await tester.pump();

    // favored side (home 62%) percentage in the footer micro-bar
    expect(find.text('62%'), findsOneWidget);
    expect(find.byType(SeriesPips), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('final hero card: score rows + Final, winner bright, taps to detail',
      (tester) async {
    final p = await prefs();
    // teamcard_nba's primary is its last game (a final) → the final body.
    final card = TeamCard.fromJson(fixture('teamcard_nba.json'));
    await tester.pumpWidget(
        wrap(FavoriteHeroCard(feedFor(card)), navOverrides(p, card)));
    await tester.pump();

    // score rows + the Final footer; none of the scheduled/live affordances
    expect(find.text('123'), findsOneWidget); // BOS (winner)
    expect(find.text('91'), findsOneWidget); // PHI (loser)
    expect(find.text('Final'), findsOneWidget);
    expect(find.byType(LiveDot), findsNothing);
    expect(find.text('Upcoming'), findsNothing);

    // the whole card taps through to the game detail
    await tester.tap(find.text('123'));
    await tester.pumpAndSettle();
    expect(find.byType(GameDetailPage), findsOneWidget);
  });

  testWidgets('scheduled hero card: compact matchup + kickoff, no live/final',
      (tester) async {
    final p = await prefs();
    // Strip live+last so the next (scheduled) game is the primary event.
    final j = fixture('teamcard_nba.json');
    j['live'] = null;
    j['last'] = null;
    final card = TeamCard.fromJson(j);
    await tester.pumpWidget(
        wrap(FavoriteHeroCard(feedFor(card)), navOverrides(p, card)));
    await tester.pump();

    // compact matchup: both tricodes present, no score/Final/live dot
    expect(find.text('ATL'), findsOneWidget); // away
    expect(find.text('vs'), findsOneWidget);
    expect(find.byType(LiveDot), findsNothing);
    expect(find.text('Final'), findsNothing);

    await tester.tap(find.text('ATL'));
    await tester.pumpAndSettle();
    expect(find.byType(GameDetailPage), findsOneWidget);
  });

  testWidgets('live hero card renders the live body with the live dot',
      (tester) async {
    final p = await prefs();
    final mlb = ScoresResponse.fromJson(fixture('mlb.json'));
    final liveEv = mlb.events.firstWhere((e) => e.main!.status.live);
    final t = liveEv.main!.competitors.first;
    final card = TeamCard(
      league: 'baseball/mlb',
      sport: 'baseball',
      leagueName: 'MLB',
      team: TeamCardTeam(
        id: t.id,
        displayName: t.displayName,
        abbreviation: t.abbreviation,
        color: t.color,
      ),
      live: liveEv,
      anyLive: true,
    );
    await tester.pumpWidget(
        wrap(FavoriteHeroCard(feedFor(card)), navOverrides(p, card)));
    await tester.pump();

    expect(find.byType(LiveDot), findsWidgets);
    expect(find.text('Upcoming'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'live playoff hero: derives "Game N · leads" header + renders series pips',
      (tester) async {
    final p = await prefs();
    final card = seriesLiveCard();
    await tester.pumpWidget(
        wrap(FavoriteHeroCard(feedFor(card)), navOverrides(p, card)));
    await tester.pump();

    // 3+2 games played → Game 6; OKC (3) leads CLE (2).
    expect(find.textContaining('Game 6'), findsOneWidget);
    expect(find.textContaining('OKC leads 3'), findsOneWidget);
    expect(find.byType(SeriesPips), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('error hero card: shows the team name + a calm message',
      (tester) async {
    final p = await prefs();
    final feed = FavoriteTeamFeed(
      const FavoriteTeam(
          league: 'basketball/nba', teamId: '2', name: 'Celtics'),
      null,
      error: 'boom',
    );
    await tester.pumpWidget(wrap(FavoriteHeroCard(feed), [
      sharedPrefsProvider.overrideWithValue(p),
    ]));
    await tester.pump();

    expect(find.textContaining('CELTICS'), findsOneWidget);
    expect(find.textContaining('load'), findsOneWidget);
  });
}
