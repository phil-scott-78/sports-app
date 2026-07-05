import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import '../util.dart';
import 'follow_sheet.dart';
import 'game_detail_page.dart';
import 'widgets.dart';

/// One favorite's stacked hero card on the home feed. Detail scales with game
/// state: a live game gets the full situation treatment, an upcoming game a
/// compact one-liner, a finished game the score + Final.
class FavoriteHeroCard extends StatelessWidget {
  final FavoriteTeamFeed feed;
  const FavoriteHeroCard(this.feed, {super.key});

  @override
  Widget build(BuildContext context) {
    final card = feed.card;
    final event = card?.primary;
    final comp = event?.main;

    Widget body;
    if (card == null || event == null || comp == null) {
      body = _ErrorBody(feed);
    } else if (comp.status.live) {
      body = _LiveBody(card, event, comp);
    } else if (card.live == null && card.next != null && event == card.next) {
      body = _UpcomingBody(card, event, comp);
    } else {
      body = _FinalBody(card, event, comp);
    }

    return GestureDetector(
      onTap: event == null || comp == null
          ? null
          : () => openGameDetail(context, feed.fav.league, event),
      onLongPress: () => showTeamFollowSheet(
        context,
        league: feed.fav.league,
        teamId: feed.fav.teamId,
        name: feed.fav.name,
        abbr: feed.fav.abbr,
        subtitle: card?.leagueName,
      ),
      child: V2Card(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
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

  /// Man-advantage / red-card badge next to a side's name, from the cheap
  /// timeline. (PP/bonus aren't on the scoreboard — only what data supports.)
  Widget? _sideBadge(Competition comp, Competitor c) {
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
    if (sit == null) return '';
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
    return sit.lastPlay ?? '';
  }
}

class _UpcomingBody extends StatelessWidget {
  final TeamCard card;
  final SportEvent event;
  final Competition comp;
  const _UpcomingBody(this.card, this.event, this.comp);

  @override
  Widget build(BuildContext context) {
    final away = comp.away, home = comp.home;
    final favSide = _favSide();
    final opp = favSide == home ? away : home;
    final joiner = favSide == home ? 'vs' : 'at';
    Widget sideChip(Competitor? c, {double barH = 18}) => c == null
        ? const SizedBox.shrink()
        : Row(mainAxisSize: MainAxisSize.min, children: [
            ColorBar(teamColor(c), width: 6, height: barH),
            const SizedBox(width: 7),
            Text(c.label, style: T.heroName.copyWith(fontSize: 20)),
          ]);

    final note = _note();
    return Row(children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HeroHeader(
                '${card.team.abbreviation ?? card.team.displayName} · ${_context()}'),
            const SizedBox(height: 8),
            Row(children: [
              sideChip(favSide),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(joiner,
                    style: const TextStyle(fontSize: 12, color: T.textFaint)),
              ),
              sideChip(opp),
            ]),
          ],
        ),
      ),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(startLabel(event.start),
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: T.text)),
        if (note != null) ...[
          const SizedBox(height: 3),
          Text(note,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: T.captionFaint),
        ],
      ]),
    ]);
  }

  Competitor? _favSide() {
    for (final c in comp.competitors) {
      if (c.id == card.team.id) return c;
    }
    return comp.home;
  }

  String _context() {
    final round = comp.meta?.round;
    if (round != null && round.isNotEmpty) return round;
    return card.leagueName;
  }

  String? _note() {
    final probables = [
      ...?comp.away?.probables.map((p) => p.athlete),
      ...?comp.home?.probables.map((p) => p.athlete),
    ];
    if (probables.length == 2) return '${probables[0]} vs ${probables[1]}';
    if (event.notes.isNotEmpty) return event.notes.first;
    return event.venue?.name;
  }
}

class _FinalBody extends StatelessWidget {
  final TeamCard card;
  final SportEvent event;
  final Competition comp;
  const _FinalBody(this.card, this.event, this.comp);

  @override
  Widget build(BuildContext context) {
    final away = comp.away, home = comp.home;
    final lead = leadingSide(comp);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeroHeader(
          '${card.team.abbreviation ?? card.team.displayName} · ${statusLine(comp, event)}',
          right: comp.meta?.seriesSummary,
        ),
        const SizedBox(height: 12),
        if (away != null)
          _HeroScoreRow(away, dim: lead != null && lead != away),
        const SizedBox(height: 8),
        if (home != null)
          _HeroScoreRow(home, dim: lead != null && lead != home),
      ],
    );
  }
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
