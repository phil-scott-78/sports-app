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
import 'package:scores/src/ui/team_page.dart';
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

void main() {
  testWidgets('idle hero card: season line + last + next, taps navigate',
      (tester) async {
    final p = await prefs();
    final card = TeamCard.fromJson(fixture('teamcard_nba.json'));
    await tester.pumpWidget(wrap(FavoriteHeroCard(feedFor(card)),
        navOverrides(p, card)));
    await tester.pump();

    // season line: abbr · record · standingSummary in one text
    expect(find.textContaining('BOS'), findsOneWidget);
    expect(find.textContaining('46-36'), findsOneWidget);
    expect(find.textContaining('2nd in Atlantic'), findsOneWidget);
    // last result row (Final) + next game row (Upcoming)
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('vs PHI'), findsOneWidget); // opponent of the last result

    // tap the season line → team page
    await tester.tap(find.textContaining('2nd in Atlantic'));
    await tester.pumpAndSettle();
    expect(find.byType(TeamPage), findsOneWidget);
  });

  testWidgets('idle hero card: tapping the last result opens its game detail',
      (tester) async {
    final p = await prefs();
    final card = TeamCard.fromJson(fixture('teamcard_nba.json'));
    await tester.pumpWidget(wrap(FavoriteHeroCard(feedFor(card)),
        navOverrides(p, card)));
    await tester.pump();

    await tester.tap(find.text('vs PHI'));
    await tester.pumpAndSettle();
    expect(find.byType(GameDetailPage), findsOneWidget);
  });

  testWidgets('idle hero card: missing standingSummary degrades to record-only',
      (tester) async {
    final p = await prefs();
    final j = fixture('teamcard_nba.json');
    (j['team'] as Map).remove('standingSummary');
    final card = TeamCard.fromJson(j);
    await tester.pumpWidget(wrap(FavoriteHeroCard(feedFor(card)),
        navOverrides(p, card)));
    await tester.pump();

    expect(find.textContaining('46-36'), findsOneWidget);
    expect(find.textContaining('in Atlantic'), findsNothing);
  });

  testWidgets('live hero card renders the live body, not the idle body',
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
    await tester.pumpWidget(wrap(FavoriteHeroCard(feedFor(card)),
        navOverrides(p, card)));
    await tester.pump();

    // live path → a live dot, and NONE of the idle-only affordances
    expect(find.byType(LiveDot), findsWidgets);
    expect(find.text('Upcoming'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
