import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import '../util.dart';
import 'follow_sheet.dart';
import 'game_detail_page.dart';
import 'situations.dart';
import 'team_page.dart';
import 'widgets.dart';

/// One favorite's stacked hero card on the home feed. A live game gets the full
/// situation treatment (whole card taps through to it); when idle, the card
/// shows a season line + the last result + the next game, each with its own tap
/// target (team page / that game's detail).
class FavoriteHeroCard extends StatelessWidget {
  final FavoriteTeamFeed feed;
  const FavoriteHeroCard(this.feed, {super.key});

  @override
  Widget build(BuildContext context) {
    final card = feed.card;
    final event = card?.primary;
    final comp = event?.main;
    final live = comp != null && comp.status.live;

    Widget body;
    if (card == null || event == null || comp == null) {
      body = _ErrorBody(feed);
    } else if (live) {
      body = _LiveBody(card, event, comp);
    } else {
      body = _IdleBody(league: feed.fav.league, card: card);
    }

    return GestureDetector(
      // Live → the whole card opens the game. Idle → the inner rows own their
      // taps (team page / each game), so the card itself isn't tappable.
      onTap: live ? () => openGameDetail(context, feed.fav.league, event!) : null,
      onLongPress: () => showTeamFollowSheet(
        context,
        league: feed.fav.league,
        teamId: feed.fav.teamId,
        name: feed.fav.name,
        abbr: feed.fav.abbr,
        subtitle: card?.leagueName,
      ),
      child: V2Card(
        padding: T.padCompact,
        bordered: true,
        child: body,
      ),
    );
  }
}

/// 'CUBS · BOT 7' header line + right caption.
class _HeroHeader extends StatelessWidget {
  final String label;
  final String? right;
  final bool live;
  const _HeroHeader(this.label, {this.right, this.live = false});

  @override
  Widget build(BuildContext context) => Row(children: [
        if (live) ...[const LiveDot(), const SizedBox(width: 7)],
        Expanded(
          child: Text(label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.55,
                  color: T.textDim)),
        ),
        if (right != null)
          Text(right!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.captionFaint),
      ]);
}

class _HeroScoreRow extends StatelessWidget {
  final Competitor c;
  final bool dim;
  final Widget? badge;
  const _HeroScoreRow(this.c, {required this.dim, this.badge});

  @override
  Widget build(BuildContext context) {
    final color = dim ? T.textDim : T.text;
    return Row(children: [
      ColorBar(teamColor(c), width: 8, height: 26),
      const SizedBox(width: 10),
      Text(c.label, style: T.heroName.copyWith(color: color)),
      if (badge != null) ...[const SizedBox(width: 10), badge!],
      const Spacer(),
      Text(c.score?.display ?? '',
          style: T.heroScore.copyWith(color: color)),
    ]);
  }
}

class _LiveBody extends StatelessWidget {
  final TeamCard card;
  final SportEvent event;
  final Competition comp;
  const _LiveBody(this.card, this.event, this.comp);

  @override
  Widget build(BuildContext context) {
    final sit = comp.situation;
    final away = comp.away, home = comp.home;
    final lead = leadingSide(comp);
    final series = comp.meta?.series;
    final diamond = sit != null && sit.hasBaseball
        ? BaseballDiamond(
            onFirst: sit.onFirst ?? false,
            onSecond: sit.onSecond ?? false,
            onThird: sit.onThird ?? false,
            width: 86,
          )
        : null;

    final footerLeft = _footerText(comp);
    final headerRight =
        comp.meta?.seriesSummary ?? event.venue?.name ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeroHeader(
          '${card.team.abbreviation ?? card.team.displayName} · ${comp.status.shortDetail ?? comp.status.detail}',
          right: headerRight,
          live: true,
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: Column(children: [
              if (away != null)
                _HeroScoreRow(away,
                    dim: lead != null && lead != away,
                    badge: _sideBadge(comp, away)),
              const SizedBox(height: 8),
              if (home != null)
                _HeroScoreRow(home,
                    dim: lead != null && lead != home,
                    badge: _sideBadge(comp, home)),
            ]),
          ),
          if (diamond != null) ...[const SizedBox(width: 16), diamond],
        ]),
        if (footerLeft.isNotEmpty || series?.isPlayoff == true) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: T.divider))),
            child: Row(children: [
              Expanded(
                child: Text(footerLeft,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.caption),
              ),
              if (series?.isPlayoff == true)
                SeriesPips(series: series!, comp: comp),
            ]),
          ),
        ],
      ],
    );
  }

  /// Man-advantage badges next to a side's name, from the cheap scoreboard:
  /// soccer's red-card man-down, or hockey's power play (§8 glance glyph).
  Widget? _sideBadge(Competition comp, Competitor c) {
    final sit = comp.situation;
    if (sit != null && sit.hasPowerPlay && sit.strengthTeam == c.id) {
      return const TagBadge('PP');
    }
    final side = c == comp.home ? 'home' : 'away';
    final reds = comp.redCardsBySide[side] ?? 0;
    if (reds > 0) {
      return TagBadge(reds > 1 ? '${11 - reds} MEN' : '10 MEN',
          bg: T.live, fg: Colors.white);
    }
    return null;
  }

  String _footerText(Competition comp) {
    final sit = comp.situation;
    if (sit != null) {
      final bits = <String>[
        if (sit.batter != null) '${sit.batter} up',
        if (sit.balls != null && sit.strikes != null)
          '${sit.balls}–${sit.strikes}',
        if (sit.outsText != null)
          sit.outsText!
        else if (sit.outs != null)
          '${sit.outs} out',
        if (sit.downDistanceText != null) sit.downDistanceText!,
      ];
      if (bits.isNotEmpty) return bits.take(3).join(' · ');
    }
    // Soccer/rugby (no core situation): the latest goal, else who's a man down
    // — the "10 MEN" badge already flags the man-down, so lead with the goal.
    return matchRowContext(comp, goalFirst: true) ?? sit?.lastPlay ?? '';
  }
}

/// The idle (not-live) favorite card: a tappable season line (→ team page) over
/// the last result and the next game, each row tapping through to that game.
/// Stays ≤ ~3 glanceable lines; a team with only one of last/next shows one row.
class _IdleBody extends StatelessWidget {
  final String league;
  final TeamCard card;
  const _IdleBody({required this.league, required this.card});

  @override
  Widget build(BuildContext context) {
    final last = card.last, next = card.next;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _seasonHeader(context),
      const SizedBox(height: 12),
      if (last != null) _resultRow(context, last),
      if (last != null && next != null) const SizedBox(height: 8),
      if (next != null) _nextRow(context, next),
    ]);
  }

  /// 'BOS · 46-36 · 2nd in Atlantic' — null segments dropped, long strings
  /// ellipsized. Taps through to the team page.
  Widget _seasonHeader(BuildContext context) {
    final t = card.team;
    final segs = <String>[
      (t.abbreviation ?? t.displayName).toUpperCase(),
      if (t.record != null && t.record!.isNotEmpty) t.record!,
      if (t.standingSummary != null && t.standingSummary!.isNotEmpty)
        t.standingSummary!,
    ];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openTeamPage(context, league,
          teamId: t.id, name: t.displayName, color: t.color),
      child: Row(children: [
        Expanded(
          child: Text(segs.join('  ·  '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: T.textDim)),
        ),
        const Icon(Icons.chevron_right_rounded, size: 16, color: T.textFaint),
      ]),
    );
  }

  Competitor? _favSide(Competition comp) {
    for (final c in comp.competitors) {
      if (c.id == card.team.id) return c;
    }
    return comp.home;
  }

  Competitor? _oppSide(Competition comp, Competitor? fav) {
    for (final c in comp.competitors) {
      if (c != fav) return c;
    }
    return null;
  }

  Widget _resultRow(BuildContext context, SportEvent ev) {
    final comp = ev.main;
    if (comp == null) return const SizedBox.shrink();
    final fav = _favSide(comp);
    final opp = _oppSide(comp, fav);
    final tag = fav?.winner == true
        ? 'W'
        : (opp?.winner == true ? 'L' : 'D');
    final tagColor = fav?.winner == true
        ? T.green
        : (opp?.winner == true ? T.live : T.textFaint);
    final joiner = fav?.homeAway == 'home' ? 'vs' : 'at';
    return _row(
      context: context,
      ev: ev,
      leading: TagBadge(tag, bg: tagColor, fg: Colors.white),
      opponent: '$joiner ${opp?.label ?? ''}',
      trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('${fav?.score?.display ?? ''}–${opp?.score?.display ?? ''}',
            style: T.rowScore.copyWith(fontSize: 17)),
        Text(statusLine(comp, ev), style: T.captionFaint),
      ]),
    );
  }

  Widget _nextRow(BuildContext context, SportEvent ev) {
    final comp = ev.main;
    if (comp == null) return const SizedBox.shrink();
    final fav = _favSide(comp);
    final opp = _oppSide(comp, fav);
    final joiner = fav?.homeAway == 'home' ? 'vs' : 'at';
    return _row(
      context: context,
      ev: ev,
      // Upcoming rows carry no glyph (§5) — the time on the right says it all.
      leading: const SizedBox.shrink(),
      opponent: '$joiner ${opp?.label ?? ''}',
      trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(startLabel(ev.start),
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: T.text)),
        const Text('Upcoming', style: T.captionFaint),
      ]),
    );
  }

  Widget _row({
    required BuildContext context,
    required SportEvent ev,
    required Widget leading,
    required String opponent,
    required Widget trailing,
  }) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => openGameDetail(context, league, ev),
        child: Row(children: [
          SizedBox(width: 26, height: 24, child: Center(child: leading)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(opponent,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: T.heroName.copyWith(fontSize: 19)),
          ),
          const SizedBox(width: 10),
          trailing,
        ]),
      );
}

class _ErrorBody extends StatelessWidget {
  final FavoriteTeamFeed feed;
  const _ErrorBody(this.feed);

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeroHeader(feed.fav.name),
          const SizedBox(height: 8),
          Text(
            feed.error == null ? 'No games nearby.' : 'Couldn’t load.',
            style: T.caption,
          ),
        ],
      );
}
