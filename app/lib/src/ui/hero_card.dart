import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import '../util.dart';
import 'follow_sheet.dart';
import 'game_detail_page.dart';
import 'situations.dart';
import 'widgets.dart';

/// One favorite's stacked hero card on the home feed. Detail scales with game
/// state: a live game gets the full situation treatment; a finished game shows
/// the result with the winner bright; a scheduled game a compact matchup. The
/// whole card taps through to its game; a long-press opens the follow sheet.
class FavoriteHeroCard extends StatelessWidget {
  final FavoriteTeamFeed feed;
  const FavoriteHeroCard(this.feed, {super.key});

  @override
  Widget build(BuildContext context) {
    final card = feed.card;
    final event = card?.primary;
    final comp = event?.main;

    Widget body;
    EdgeInsetsGeometry padding = T.padCompact;
    if (card == null || event == null || comp == null) {
      body = _ErrorBody(feed);
    } else if (comp.status.live) {
      body = _LiveBody(card, event, comp);
    } else if (comp.status.isFinal) {
      body = _FinalBody(card, event, comp);
    } else {
      body = _ScheduledBody(card, event, comp);
      // Compact scheduled card: a touch shorter than the live/final bodies.
      padding = const EdgeInsets.fromLTRB(18, 14, 18, 14);
    }

    return GestureDetector(
      // The whole card opens its game; the inner content is a glance, not a nav.
      onTap: event == null
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
      child: V2Card(padding: padding, bordered: true, child: body),
    );
  }
}

// ═══════════════════════════ shared pieces ═══════════════════════════

/// 'CUBS · BOT 7' header line + right caption (venue / series context).
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
        if (right != null && right!.isNotEmpty)
          Text(right!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.captionFaint),
      ]);
}

/// A full-height matchup row (8×26 bar, Barlow 24/700 tricode, 32/700 score);
/// the trailing side dims when it's behind / lost.
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
      Text(c.score?.display ?? '', style: T.heroScore.copyWith(color: color)),
    ]);
  }
}

/// The hairline-topped footer: a cheap glance line on the left, series pips on
/// the right. Rendered only when there's something to show.
class _HeroFooter extends StatelessWidget {
  final String left;
  final Competition comp;
  const _HeroFooter({required this.left, required this.comp});

  @override
  Widget build(BuildContext context) {
    final series = comp.meta?.series;
    final pips = series != null && series.isPlayoff;
    // Cheap win-prob (basketball only, by DATA presence — never sport name). Give
    // series pips priority; show the win-prob micro-bar only when there are none.
    final winPct = pips ? null : comp.situation?.homeWinPct;
    if (left.isEmpty && !pips && winPct == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.only(top: 12),
      decoration:
          const BoxDecoration(border: Border(top: BorderSide(color: T.divider))),
      child: Row(children: [
        Expanded(
          child: Text(left,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: T.caption),
        ),
        if (pips)
          SeriesPips(series: series, comp: comp)
        else if (winPct != null)
          _WinProbBar(comp: comp, homePct: winPct),
      ]),
    );
  }
}

/// The hero-card footer win-probability micro-bar (DESIGN §7 home feed: 64×5 two
/// team colors) + a Barlow percentage for the favored side. Rendered only when
/// the cheap scoreboard carries [homePct] (basketball) — so it's basketball-only
/// by data, not by a sport-name branch.
class _WinProbBar extends StatelessWidget {
  final Competition comp;
  final int homePct;
  const _WinProbBar({required this.comp, required this.homePct});

  @override
  Widget build(BuildContext context) {
    final home = comp.home, away = comp.away;
    final pct = homePct.clamp(0, 100);
    final homeColor = home != null ? teamColor(home) : T.textDim;
    final awayColor = away != null ? teamColor(away) : T.outline;
    final favHome = pct >= 50;
    final favColor = favHome ? homeColor : awayColor;
    final favPct = favHome ? pct : 100 - pct;
    // Expanded flex must stay ≥ 1 even at a 0/100 shutout.
    final homeFlex = pct < 1 ? 1 : pct;
    final awayFlex = pct > 99 ? 1 : 100 - pct;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(2.5),
        child: SizedBox(
          width: 64,
          height: 5,
          child: Row(children: [
            Expanded(flex: homeFlex, child: ColoredBox(color: homeColor)),
            const SizedBox(width: 2),
            Expanded(flex: awayFlex, child: ColoredBox(color: awayColor)),
          ]),
        ),
      ),
      const SizedBox(width: 8),
      Text('$favPct%',
          style: TextStyle(
              fontFamily: 'BarlowCondensed',
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: favColor,
              fontFeatures: const [FontFeature.tabularFigures()])),
    ]);
  }
}

/// Playoff-series context for the header caption: 'Game 6 · DAL leads 3–2'.
/// Both halves are DERIVED (§ Part I.6): game N = played + 1, the lead phrase
/// from each competitor's win count. Null when there's no live playoff series.
String? _seriesContext(Competition comp) {
  final s = comp.meta?.series;
  if (s == null || !s.isPlayoff) return null;
  final cs = comp.competitors;
  if (cs.length < 2) return comp.meta?.seriesSummary;
  final a = cs[0], b = cs[1];
  final aw = s.wins(a.id), bw = s.wins(b.id);
  final played = aw + bw;
  final gameNo = s.completed ? played : played + 1;
  final String tail;
  if (aw == bw) {
    tail = aw == 0 ? 'Series level' : 'Series tied $aw–$aw';
  } else {
    final lead = aw > bw ? a : b;
    final hi = aw > bw ? aw : bw, lo = aw > bw ? bw : aw;
    tail = '${lead.label} leads $hi–$lo';
  }
  return gameNo > 0 ? 'Game $gameNo · $tail' : tail;
}

/// The best available CHEAP glance line for a competition's footer, tried in
/// order: the live situation (count/outs, down & distance), the soccer/rugby
/// timeline (goal / man-down), the cheap game leaders, then the last-play text.
String _glanceLine(Competition comp) {
  final sit = comp.situation;
  if (sit != null) {
    final bits = <String>[
      if (sit.batter != null) '${sit.batter} up',
      if (sit.balls != null && sit.strikes != null) '${sit.balls}–${sit.strikes}',
      if (sit.outsText != null)
        sit.outsText!
      else if (sit.outs != null)
        '${sit.outs} out',
      if (sit.downDistanceText != null) sit.downDistanceText!,
    ];
    if (bits.isNotEmpty) return bits.take(3).join(' · ');
  }
  // Soccer/rugby (no core situation): lead with the goal — a "10 MEN" badge on
  // the row already flags the man-down.
  final match = matchRowContext(comp, goalFirst: true);
  if (match != null) return match;
  final leaders = _leadersLine(comp);
  if (leaders != null) return leaders;
  return sit?.lastPlay ?? '';
}

/// 'Hintz 12 shots on goal · Oettinger .938' — the top cheap leader from each
/// side. Null when the scoreboard carries no usable leaders.
String? _leadersLine(Competition comp) {
  final parts = <String>[];
  for (final c in comp.competitors) {
    for (final l in c.leaders) {
      final who = l.athlete, val = l.display;
      if (who != null && who.isNotEmpty && val != null && val.isNotEmpty) {
        parts.add('$who $val');
        break;
      }
    }
    if (parts.length >= 2) break;
  }
  return parts.isEmpty ? null : parts.join(' · ');
}

// ═══════════════════════════ live ═══════════════════════════

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
    final diamond = sit != null && sit.hasBaseball
        ? BaseballDiamond(
            onFirst: sit.onFirst ?? false,
            onSecond: sit.onSecond ?? false,
            onThird: sit.onThird ?? false,
            width: 86,
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeroHeader(
          '${card.team.abbreviation ?? card.team.displayName} · '
          '${comp.status.shortDetail ?? comp.status.detail}',
          right: _seriesContext(comp) ?? event.venue?.name ?? '',
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
        _HeroFooter(left: _glanceLine(comp), comp: comp),
      ],
    );
  }

  /// Man-advantage badges next to a side's name, from the cheap scoreboard:
  /// hockey's power play, or soccer's red-card man-down.
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
}

// ═══════════════════════════ final ═══════════════════════════

class _FinalBody extends StatelessWidget {
  final TeamCard card;
  final SportEvent event;
  final Competition comp;
  const _FinalBody(this.card, this.event, this.comp);

  @override
  Widget build(BuildContext context) {
    final away = comp.away, home = comp.home;
    final lead = leadingSide(comp); // finals dim by winner
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeroHeader(
          card.team.abbreviation ?? card.team.displayName,
          right: _seriesContext(comp) ?? event.venue?.name ?? '',
        ),
        const SizedBox(height: 12),
        if (away != null)
          _HeroScoreRow(away, dim: lead != null && lead != away),
        const SizedBox(height: 8),
        if (home != null)
          _HeroScoreRow(home, dim: lead != null && lead != home),
        _HeroFooter(left: statusLine(comp, event), comp: comp),
      ],
    );
  }
}

// ═══════════════════════════ scheduled ═══════════════════════════

class _ScheduledBody extends StatelessWidget {
  final TeamCard card;
  final SportEvent event;
  final Competition comp;
  const _ScheduledBody(this.card, this.event, this.comp);

  @override
  Widget build(BuildContext context) {
    final away = comp.away ??
        (comp.competitors.isNotEmpty ? comp.competitors.first : null);
    final home = comp.home ??
        (comp.competitors.length > 1 ? comp.competitors[1] : null);
    final team = card.team.abbreviation ?? card.team.displayName;
    final context = _contextLabel();
    final label = context == null ? team : '$team · $context';
    final broadcast = comp.broadcast ??
        (event.broadcasts.isNotEmpty ? event.broadcasts.first : null);

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.55,
                  color: T.textDim)),
          const SizedBox(height: 8),
          Row(children: [
            if (away != null) _miniTeam(away),
            if (away != null && home != null) ...[
              const SizedBox(width: 10),
              const Text('vs', style: TextStyle(fontSize: 12, color: T.textFaint)),
              const SizedBox(width: 10),
            ],
            if (home != null) _miniTeam(home),
          ]),
        ]),
      ),
      const SizedBox(width: 12),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(startLabel(event.start),
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: T.text)),
        // NO winner-faces / bracket-forward line here — that's core-only (§2.1).
        if (broadcast != null && broadcast.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(broadcast, style: T.captionFaint),
        ],
      ]),
    ]);
  }

  Widget _miniTeam(Competitor c) => Row(mainAxisSize: MainAxisSize.min, children: [
        ColorBar(teamColor(c), width: 6, height: 18),
        const SizedBox(width: 7),
        Text(c.label, style: T.heroName.copyWith(fontSize: 20)),
      ]);

  /// The scheduled card's context suffix: the round/stage note, else the week
  /// label — whatever the cheap event carries.
  String? _contextLabel() {
    final round = comp.meta?.round;
    if (round != null && round.isNotEmpty) return round;
    if (event.notes.isNotEmpty && event.notes.first.isNotEmpty) {
      return event.notes.first;
    }
    final week = event.weekLabel;
    if (week != null && week.isNotEmpty) return week;
    return null;
  }
}

// ═══════════════════════════ error ═══════════════════════════

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
