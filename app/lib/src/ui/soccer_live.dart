// soccer_live.dart — the soccer live-game module set (design LiveGame turns
// 9–10): the momentum chart, commentary preview + full feed, match leaders,
// the Turn-10 live pitch (pass trail / possession chip / restart log), the
// formation pitch, and the clickable shot map. Everything dispatches on DATA
// PRESENCE (a match feed, commentary rows, matchLeaders, formationPlace) —
// never on sport name — so rugby/degraded soccer fall out cleanly.
//
// The pitch green (#15231B) is a deliberate sport-local surface (DESIGN.md §2:
// rare, only where the sport has an iconic physical color — the pitch is it).

import 'package:flutter/material.dart';

import '../models.dart';
import '../momentum.dart';
import '../theme.dart';
import '../util.dart';
import 'player_page.dart';
import 'widgets.dart';

const _pitchBg = Color(0xFF15231B); // the sport-local pitch green
const _pitchLine = Color(0x24EEF1F4); // rgba(238,241,244,.14)

// ---- shared pitch painter -----------------------------------------------------

/// Minimal broadcast pitch: halfway line, centre circle, both penalty boxes.
/// [vertical] draws goal-to-goal top-to-bottom (the formation card); default is
/// left-to-right (live pitch, shot map).
class _PitchPainter extends CustomPainter {
  final bool vertical;
  const _PitchPainter({this.vertical = false});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = _pitchLine
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final w = size.width, h = size.height;
    if (vertical) {
      canvas.drawLine(Offset(0, h / 2), Offset(w, h / 2), p);
      canvas.drawCircle(Offset(w / 2, h / 2), w * 0.13, p);
      final boxW = w * 0.56, boxH = h * 0.14;
      canvas.drawRect(
          Rect.fromLTWH((w - boxW) / 2, 0, boxW, boxH), p);
      canvas.drawRect(
          Rect.fromLTWH((w - boxW) / 2, h - boxH, boxW, boxH), p);
    } else {
      canvas.drawLine(Offset(w / 2, 0), Offset(w / 2, h), p);
      canvas.drawCircle(Offset(w / 2, h / 2), h * 0.17, p);
      final boxW = w * 0.15, boxH = h * 0.52;
      canvas.drawRect(Rect.fromLTWH(0, (h - boxH) / 2, boxW, boxH), p);
      canvas.drawRect(
          Rect.fromLTWH(w - boxW, (h - boxH) / 2, boxW, boxH), p);
    }
  }

  @override
  bool shouldRepaint(covariant _PitchPainter old) => old.vertical != vertical;
}

/// Team-relative canonical coords → horizontal-pitch fractions. Home attacks
/// RIGHT (x as-is); away mirrors both axes so its attacking events read left.
Offset _toPitch(String? side, num x, num y) => side == 'away'
    ? Offset(1 - x / 100, 1 - y / 100)
    : Offset(x / 100, y / 100);

// ---- helpers -------------------------------------------------------------------

LineupPlayer? _lineupPlayer(String? athleteId, List<Lineup> lineups) {
  if (athleteId == null) return null;
  for (final l in lineups) {
    for (final p in [...l.starters, ...l.bench]) {
      if (p.id == athleteId) return p;
    }
  }
  return null;
}

/// 'Jules Koundé Pass' → 'Jules Koundé' (the shortText minus the type suffix).
String? _playerFromShortText(MatchFeedPlay p) {
  final st = p.shortText;
  if (st == null) return null;
  if (st.endsWith(' ${p.type}')) {
    return st.substring(0, st.length - p.type.length - 1);
  }
  return st;
}

String? _playerName(MatchFeedPlay p, List<Lineup> lineups) =>
    _lineupPlayer(p.athleteId, lineups)?.name ?? _playerFromShortText(p);

Competitor? _sideCompetitor(Competition comp, String? side) =>
    side == null ? null : comp.competitorByHome(side);

String _sideName(Competition comp, String? side) {
  final c = _sideCompetitor(comp, side);
  return c?.shortName ?? c?.displayName ?? '';
}

/// The Barlow minute chip that rails the commentary/stoppage rows (34×26 r6).
class _MinuteChip extends StatelessWidget {
  final String text;
  final bool dim;
  const _MinuteChip(this.text, {this.dim = false});
  @override
  Widget build(BuildContext context) => Container(
        width: 36,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: T.track, borderRadius: BorderRadius.circular(6)),
        child: Text(text,
            maxLines: 1,
            style: TextStyle(
                fontFamily: 'BarlowCondensed',
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: dim ? T.textDim : T.text,
                fontFeatures: const [FontFeature.tabularFigures()])),
      );
}

/// The quiet standing-destination foot row inside a card ('Full commentary',
/// 'Full player stats') — a hairline + centered 13/600 dim line, tappable.
class _CardFootLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _CardFootLink(this.label, {required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.only(top: 12),
          decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: T.divider))),
          child: Center(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: T.text)),
          ),
        ),
      );
}

// ---- momentum (design 9a) -------------------------------------------------------

/// MOMENTUM — attacking pressure per minute, home above the line / away below,
/// KO→HT→FT axis, a now-marker while live. Derived from the match feed
/// (momentum.dart); hidden upstream when the feed is absent/quiet.
class MomentumCard extends StatelessWidget {
  final Competition comp;
  final List<MomentumBucket> buckets;
  const MomentumCard({super.key, required this.comp, required this.buckets});

  @override
  Widget build(BuildContext context) {
    if (buckets.isEmpty) return const SizedBox.shrink();
    final home = comp.competitorByHome('home'), away = comp.competitorByHome('away');
    final hColor = teamColor(home), aColor = teamColor(away);
    // Now-marker: the fraction of the axis the match has reached (live only).
    double? nowFrac;
    if (comp.status.live) {
      final m = RegExp(r'^(\d+)').firstMatch(comp.status.clock ?? '');
      if (m != null) {
        nowFrac = (int.parse(m.group(1)!) / buckets.length).clamp(0.0, 1.0);
      }
    }
    Widget legend(Color c, String abbr) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 5),
          Text(abbr, style: T.captionFaint.copyWith(color: T.textDim)),
        ]);
    return V2Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const CardLabel('Momentum'),
          const Spacer(),
          legend(hColor, home?.abbreviation ?? ''),
          const SizedBox(width: 14),
          legend(aColor, away?.abbreviation ?? ''),
        ]),
        const SizedBox(height: 14),
        SizedBox(
          height: 74,
          width: double.infinity,
          child: CustomPaint(
            painter: _MomentumPainter(
                buckets: buckets,
                homeColor: hColor,
                awayColor: aColor,
                nowFrac: nowFrac),
          ),
        ),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('KO', style: T.captionFaint.copyWith(fontSize: 10)),
          Text('HT', style: T.captionFaint.copyWith(fontSize: 10)),
          Text(buckets.length > 91 ? 'ET' : 'FT',
              style: T.captionFaint.copyWith(fontSize: 10)),
        ]),
      ]),
    );
  }
}

class _MomentumPainter extends CustomPainter {
  final List<MomentumBucket> buckets;
  final Color homeColor, awayColor;
  final double? nowFrac;
  const _MomentumPainter(
      {required this.buckets,
      required this.homeColor,
      required this.awayColor,
      this.nowFrac});

  @override
  void paint(Canvas canvas, Size size) {
    // Home band above the midline (2/3 of the height), away below (1/3) —
    // matching the design's asymmetric split favoring the busier band equally
    // would misread; keep it symmetric-enough: 60/40 like the mock (48/22).
    const midFrac = 0.66;
    final mid = size.height * midFrac;
    final n = buckets.length;
    final slot = size.width / n;
    final barW = (slot - 1).clamp(0.5, 6.0);
    final hPaint = Paint()..color = homeColor;
    final aPaint = Paint()..color = awayColor;
    for (var i = 0; i < n; i++) {
      final b = buckets[i];
      final x = i * slot;
      if (b.home > 0) {
        final h = (mid - 2) * b.home;
        canvas.drawRRect(
            RRect.fromRectAndCorners(
                Rect.fromLTWH(x, mid - 2 - h, barW, h),
                topLeft: const Radius.circular(2),
                topRight: const Radius.circular(2)),
            hPaint);
      }
      if (b.away > 0) {
        final h = (size.height - mid - 2) * b.away;
        canvas.drawRRect(
            RRect.fromRectAndCorners(
                Rect.fromLTWH(x, mid + 2, barW, h),
                bottomLeft: const Radius.circular(2),
                bottomRight: const Radius.circular(2)),
            aPaint);
      }
    }
    // The midline.
    canvas.drawRect(
        Rect.fromLTWH(0, mid - 1, size.width, 2), Paint()..color = T.outline);
    // HT tick at the 45' position of the axis.
    final htX = size.width * (45 / n).clamp(0.0, 1.0);
    canvas.drawRect(Rect.fromLTWH(htX, 0, 1, size.height),
        Paint()..color = T.border);
    // Now-marker while live.
    if (nowFrac != null) {
      canvas.drawRect(
          Rect.fromLTWH(size.width * nowFrac! - 0.75, 0, 1.5, size.height),
          Paint()..color = T.border);
    }
  }

  @override
  bool shouldRepaint(covariant _MomentumPainter old) =>
      old.buckets != buckets || old.nowFrac != nowFrac;
}

// ---- commentary (design 9a) -----------------------------------------------------

class _CommentaryRow extends StatelessWidget {
  final SummaryPlay play;
  final bool dim;
  const _CommentaryRow(this.play, {this.dim = false});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _MinuteChip(play.clock ?? '', dim: dim),
          const SizedBox(width: 12),
          Expanded(
            child: Text(play.text,
                style: TextStyle(
                    fontSize: 13,
                    height: 1.55,
                    color: dim ? T.textDim : T.textBody)),
          ),
        ]),
      );
}

/// COMMENTARY (Now tab preview): the freshest three lines + 'Full commentary'.
class CommentaryPreviewCard extends StatelessWidget {
  final List<SummaryPlay> commentary;
  final VoidCallback? onMore;
  const CommentaryPreviewCard(this.commentary, {super.key, this.onMore});

  @override
  Widget build(BuildContext context) {
    if (commentary.isEmpty) return const SizedBox.shrink();
    final latest = commentary.reversed.take(3).toList();
    return V2Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Align(
            alignment: Alignment.centerLeft, child: CardLabel('Commentary')),
        const SizedBox(height: 6),
        for (var i = 0; i < latest.length; i++) ...[
          if (i > 0) const Divider(height: 1, color: T.divider),
          _CommentaryRow(latest[i], dim: i == latest.length - 1),
        ],
        if (onMore != null) _CardFootLink('Full commentary', onTap: onMore!),
      ]),
    );
  }
}

/// COMMENTARY (the full tab): every curated line, newest first, with dim
/// rule-label dividers at the half boundaries (§7.4 at feed scale).
class CommentaryFeedCard extends StatelessWidget {
  final List<SummaryPlay> commentary;
  const CommentaryFeedCard(this.commentary, {super.key});

  @override
  Widget build(BuildContext context) {
    final rows = commentary.reversed.toList();
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) {
        final prev = rows[i - 1];
        if (rows[i].period != null &&
            prev.period != null &&
            rows[i].period != prev.period) {
          // Newest-first: crossing from period N down to N-1 → the divider
          // names the boundary we just scrolled past (HALF TIME between 2 and 1).
          children.add(_RuleLabel(rows[i].period == 1
              ? 'HALF TIME'
              : (rows[i].periodLabel ?? '').toUpperCase()));
        } else {
          children.add(const Divider(height: 1, color: T.divider));
        }
      }
      children.add(_CommentaryRow(rows[i]));
    }
    return V2Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Align(
            alignment: Alignment.centerLeft, child: CardLabel('Commentary')),
        const SizedBox(height: 6),
        ...children,
      ]),
    );
  }
}

/// The dim rule-label divider (§7.4): hairlines flanking a 10/700 letterspaced
/// caption ('HALF TIME').
class _RuleLabel extends StatelessWidget {
  final String label;
  const _RuleLabel(this.label);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          const Expanded(child: Divider(height: 1, color: T.border)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(label,
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: T.textFaint)),
          ),
          const Expanded(child: Divider(height: 1, color: T.border)),
        ]),
      );
}

// ---- match leaders (design 9a) ----------------------------------------------------

/// MATCH LEADERS — one row per category (total shots / accurate passes /
/// defensive interventions / saves), the overall leader across both sides.
/// Rows tap through to the player page; the foot link opens the full player
/// stats (the Lineups tab's box tables).
class MatchLeadersCard extends StatelessWidget {
  final List<MatchLeaderCategory> categories;
  final Competition comp;
  final String league;
  final VoidCallback? onFullStats;
  const MatchLeadersCard(this.categories,
      {super.key, required this.comp, required this.league, this.onFullStats});

  @override
  Widget build(BuildContext context) {
    final rows = [
      for (final c in categories)
        if (c.top != null) (cat: c, leader: c.top!)
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return V2Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Align(
            alignment: Alignment.centerLeft, child: CardLabel('Match leaders')),
        const SizedBox(height: 6),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const Divider(height: 1, color: T.divider),
          _LeaderRow(rows[i].cat, rows[i].leader, comp: comp, league: league),
        ],
        if (onFullStats != null)
          _CardFootLink('Full player stats', onTap: onFullStats!),
      ]),
    );
  }
}

class _LeaderRow extends StatelessWidget {
  final MatchLeaderCategory cat;
  final MatchLeader leader;
  final Competition comp;
  final String league;
  const _LeaderRow(this.cat, this.leader,
      {required this.comp, required this.league});

  @override
  Widget build(BuildContext context) {
    final side = _sideCompetitor(comp, leader.side);
    final caption = [
      if (leader.teamAbbr != null) leader.teamAbbr!,
      if (leader.pos != null) leader.pos!,
    ].join(' · ');
    return InkWell(
      onTap: leader.id == null
          ? null
          : () => openPlayerPage(context, league,
              athleteId: leader.id!, name: leader.name, color: side?.color),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(children: [
          TintedAvatar(leader.name, teamColor(side), size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(leader.name, style: T.rowText),
              if (caption.isNotEmpty)
                Text(caption, style: T.captionFaint),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(leader.displayValue,
                style: const TextStyle(
                    fontFamily: 'BarlowCondensed',
                    fontWeight: FontWeight.w700,
                    fontSize: 22,
                    color: T.text,
                    fontFeatures: [FontFeature.tabularFigures()])),
            Text((cat.label ?? cat.name).toUpperCase(),
                style: const TextStyle(
                    fontSize: 10, letterSpacing: 0.6, color: T.textFaint)),
          ]),
        ]),
      ),
    );
  }
}

// ---- live pitch (design 10a) ------------------------------------------------------

/// LIVE PITCH — who has the ball, the fading pass trail, and the state chip
/// (possession side + open-play/restart label). Data: the trailing possession
/// sequence off the match feed (momentum.dart).
class LivePitchCard extends StatelessWidget {
  final Competition comp;
  final List<MatchFeedPlay> plays;
  final List<Lineup> lineups;
  const LivePitchCard(
      {super.key, required this.comp, required this.plays, required this.lineups});

  @override
  Widget build(BuildContext context) {
    final trail = trailingPossession(plays);
    final last = lastSidedPlay(plays);
    if (last == null) return const SizedBox.shrink();
    final side = trail.isNotEmpty ? trail.last.side : last.side;
    final sideComp = _sideCompetitor(comp, side);
    final color = teamColor(sideComp);
    final abbr = sideComp?.abbreviation ?? '';
    final state = possessionState(last);
    final ballPlay = trail.isNotEmpty ? trail.last : last;
    final ballName = _playerName(ballPlay, lineups);
    // Footer facts: sequence length + where the ball is.
    final passes = trail.where((p) => p.type == 'Pass').length;
    final bx = ballPlay.x2 ?? ballPlay.x;
    final by = ballPlay.y2 ?? ballPlay.y;
    String? ballLine;
    if (bx != null) {
      final oppAbbr = _sideCompetitor(
                  comp, side == 'home' ? 'away' : 'home')
              ?.abbreviation ??
          '';
      final half = bx >= 50 ? '$oppAbbr half' : 'own half';
      ballLine = bx >= 55
          ? 'ball in $half · ${yardsToGoal(bx, by ?? 50)} yds out'
          : 'ball in $half';
    }
    final attackRight = side != 'away';
    return V2Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const CardLabel('Live pitch'),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
                color: T.track, borderRadius: BorderRadius.circular(999)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text('$abbr POSSESSION · $state', style: T.pillText),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            color: _pitchBg,
            child: AspectRatio(
              aspectRatio: 340 / 210,
              child: Stack(children: [
                const Positioned.fill(child: CustomPaint(painter: _PitchPainter())),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _TrailPainter(trail: trail, color: color),
                  ),
                ),
                if (ballName != null && bx != null)
                  _BallLabel(
                      pos: _toPitch(side, bx, by ?? 50), name: ballName),
                Positioned(
                  left: 12,
                  bottom: 8,
                  child: Text(
                      attackRight ? '$abbr attacking →' : '← $abbr attacking',
                      style: T.captionFaint.copyWith(fontSize: 10)),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text.rich(TextSpan(children: [
            TextSpan(
                text: '$passes ${passes == 1 ? 'pass' : 'passes'}',
                style: T.caption.copyWith(
                    color: T.text, fontWeight: FontWeight.w600)),
            const TextSpan(text: ' this sequence', style: T.caption),
          ])),
          if (ballLine != null) Text(ballLine, style: T.caption),
        ]),
      ]),
    );
  }
}

/// The player label riding the ball marker.
class _BallLabel extends StatelessWidget {
  final Offset pos; // 0..1 pitch fractions
  final String name;
  const _BallLabel({required this.pos, required this.name});
  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: LayoutBuilder(
          builder: (context, c) {
            final x = pos.dx * c.maxWidth, y = pos.dy * c.maxHeight;
            // Keep the label inside the pitch: flip side near the right edge.
            final flip = x > c.maxWidth - 76;
            return Stack(children: [
              Positioned(
                left: flip ? null : x + 12,
                right: flip ? (c.maxWidth - x) + 12 : null,
                top: (y - 7).clamp(4.0, c.maxHeight - 18),
                child: Text(name.split(' ').last,
                    style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: T.text)),
              ),
            ]);
          },
        ),
      );
}

class _TrailPainter extends CustomPainter {
  final List<MatchFeedPlay> trail;
  final Color color;
  const _TrailPainter({required this.trail, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (trail.isEmpty) return;
    Offset at(num x, num y, String? side) {
      final f = _toPitch(side, x, y);
      return Offset(f.dx * size.width, f.dy * size.height);
    }

    // Build the point run: each play's spot, plus the final play's end point
    // (a pass in flight draws to where it landed).
    final pts = <Offset>[];
    for (final p in trail) {
      if (p.x != null) pts.add(at(p.x!, p.y ?? 50, p.side));
    }
    final lastPlay = trail.last;
    if (lastPlay.x2 != null) {
      pts.add(at(lastPlay.x2!, lastPlay.y2 ?? 50, lastPlay.side));
    }
    if (pts.isEmpty) return;
    // Fading trail: oldest faintest (design 10a: .3 → .95).
    for (var i = 0; i < pts.length - 1; i++) {
      final t = pts.length == 2 ? 1.0 : i / (pts.length - 2);
      final opacity = 0.3 + 0.65 * t;
      canvas.drawLine(
          pts[i],
          pts[i + 1],
          Paint()
            ..color = color.withValues(alpha: opacity)
            ..strokeWidth = i == pts.length - 2 ? 2.5 : 2);
      canvas.drawCircle(pts[i], 4,
          Paint()..color = color.withValues(alpha: 0.35 + 0.6 * t));
    }
    // The ball: white dot + ring at the newest point.
    final ball = pts.last;
    canvas.drawCircle(
        ball,
        9,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = T.text.withValues(alpha: 0.7));
    canvas.drawCircle(ball, 5, Paint()..color = T.text);
  }

  @override
  bool shouldRepaint(covariant _TrailPainter old) =>
      old.trail != trail || old.color != color;
}

/// LAST TOUCH — the freshest touch as one quiet sentence (shots keep ESPN's
/// rich prose; ordinary touches read '<Player> — <type>').
class LastTouchCard extends StatelessWidget {
  final List<MatchFeedPlay> plays;
  final List<Lineup> lineups;
  const LastTouchCard({super.key, required this.plays, required this.lineups});

  @override
  Widget build(BuildContext context) {
    final last = lastSidedPlay(plays);
    if (last == null) return const SizedBox.shrink();
    String prose;
    if (isShot(last) || last.type == 'Foul' || last.type == 'Save') {
      prose = last.text ?? last.shortText ?? '';
    } else {
      final name = _playerName(last, lineups);
      final label = restartLabels[last.type] ?? last.type;
      prose = name != null ? '$name — ${label.toLowerCase()}.' : label;
    }
    if (prose.isEmpty) return const SizedBox.shrink();
    return V2Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const CardLabel('Last touch'),
        const SizedBox(height: 8),
        Text(prose,
            style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                height: 1.35,
                color: T.text)),
      ]),
    );
  }
}

/// RECENT STOPPAGES — the last three restarts (throw-ins, goal kicks, corners,
/// free kicks), newest first; freshest row white, older dim (design 10a).
class StoppagesCard extends StatelessWidget {
  final Competition comp;
  final List<MatchFeedPlay> plays;
  final List<Lineup> lineups;
  const StoppagesCard(
      {super.key, required this.comp, required this.plays, required this.lineups});

  @override
  Widget build(BuildContext context) {
    final restarts = matchRestarts(plays).reversed.take(3).toList();
    if (restarts.isEmpty) return const SizedBox.shrink();
    return V2Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Align(
            alignment: Alignment.centerLeft,
            child: CardLabel('Recent stoppages')),
        const SizedBox(height: 6),
        for (var i = 0; i < restarts.length; i++) ...[
          if (i > 0) const Divider(height: 1, color: T.divider),
          _StoppageRow(restarts[i], comp: comp, lineups: lineups, dim: i > 0),
        ],
      ]),
    );
  }
}

class _StoppageRow extends StatelessWidget {
  final MatchFeedPlay play;
  final Competition comp;
  final List<Lineup> lineups;
  final bool dim;
  const _StoppageRow(this.play,
      {required this.comp, required this.lineups, required this.dim});

  @override
  Widget build(BuildContext context) {
    final label = restartLabels[play.type] ?? play.type;
    final team = _sideName(comp, play.side);
    final who = _playerName(play, lineups);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        _MinuteChip(play.clock ?? '', dim: dim),
        const SizedBox(width: 12),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: label,
                  style: TextStyle(
                      fontSize: 13, color: dim ? T.textDim : T.text)),
              if (team.isNotEmpty) ...[
                TextSpan(
                    text: ' · ',
                    style: TextStyle(
                        fontSize: 13, color: dim ? T.textDim : T.text)),
                TextSpan(
                    text: team,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: dim ? T.text : T.text)),
              ],
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (who != null)
          Text(who, style: T.captionFaint, maxLines: 1),
      ]),
    );
  }
}

// ---- formations (design 9b) --------------------------------------------------------

/// FORMATIONS & LINEUPS — the vertical formation pitch with a side toggle.
/// Renders ONLY when a side's starters all carry formationPlace (data
/// presence); the plain lineup lists remain the fallback/reference below.
class FormationCard extends StatefulWidget {
  final Competition comp;
  final List<Lineup> lineups;
  final String league;
  const FormationCard(
      {super.key, required this.comp, required this.lineups, required this.league});

  /// Whether [lineup] can draw a pitch: 11 (or at least 7) placed starters.
  static bool placeable(Lineup l) =>
      l.starters.length >= 7 &&
      l.starters.every((p) => p.formationPlace != null);

  @override
  State<FormationCard> createState() => _FormationCardState();
}

class _FormationCardState extends State<FormationCard> {
  int _side = 0;

  @override
  Widget build(BuildContext context) {
    final sides =
        widget.lineups.where(FormationCard.placeable).toList(growable: false);
    if (sides.isEmpty) return const SizedBox.shrink();
    final sel = sides[_side.clamp(0, sides.length - 1)];
    final comp = widget.comp.competitorByHome(sel.side ?? '');
    final color = teamColor(comp);
    return V2Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Align(
            alignment: Alignment.centerLeft,
            child: CardLabel('Formations & lineups')),
        const SizedBox(height: 12),
        if (sides.length > 1)
          SegmentedControl(
            items: [
              for (final l in sides)
                [l.abbr, l.formation].whereType<String>().join(' · '),
            ],
            selected: _side.clamp(0, sides.length - 1),
            onTap: (i) => setState(() => _side = i),
          ),
        if (sides.length > 1) const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            color: _pitchBg,
            child: AspectRatio(
              aspectRatio: 340 / 400,
              child: Stack(children: [
                const Positioned.fill(
                    child: CustomPaint(
                        painter: _PitchPainter(vertical: true))),
                ..._players(sel, color),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  /// Places the XI: GK bottom-centre, then position-family rows upward
  /// (defense → attack); within a row, left-tagged positions left,
  /// right-tagged right. A rendering heuristic over formationPlace + pos —
  /// upstream data stays canonical.
  List<Widget> _players(Lineup l, Color color) {
    final rows = _formationRows(l);
    final out = <Widget>[];
    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      // GK row sits at 90%; outfield rows spread 8%..71% top-down (attack up).
      final y = r == 0
          ? 0.90
          : 0.71 - (r - 1) * (0.63 / (rows.length - 2 <= 0 ? 1 : rows.length - 2));
      for (var i = 0; i < row.length; i++) {
        final x = (i + 1) / (row.length + 1);
        out.add(_PlayerDot(
          player: row[i],
          x: x,
          y: y,
          color: r == 0 ? T.outline : color,
          league: widget.league,
          teamColorHex: widget.comp.competitorByHome(l.side ?? '')?.color,
        ));
      }
    }
    return out;
  }

  /// GK first, then defense→attack rows grouped by position family.
  List<List<LineupPlayer>> _formationRows(Lineup l) {
    final gk = <LineupPlayer>[], d = <LineupPlayer>[], dm = <LineupPlayer>[];
    final m = <LineupPlayer>[], am = <LineupPlayer>[], f = <LineupPlayer>[];
    for (final p in l.starters) {
      final pos = (p.pos ?? '').toUpperCase();
      if (p.formationPlace == '1' || pos == 'G' || pos == 'GK') {
        gk.add(p);
      } else if (pos.startsWith('CD') ||
          pos.endsWith('B') && !pos.startsWith('A')) {
        d.add(p);
      } else if (pos.startsWith('DM')) {
        dm.add(p);
      } else if (pos.startsWith('AM') || pos == 'SS') {
        am.add(p);
      } else if (pos.startsWith('F') ||
          pos.startsWith('CF') ||
          pos.startsWith('ST') ||
          pos.startsWith('W')) {
        f.add(p);
      } else {
        m.add(p);
      }
    }
    int lane(LineupPlayer p) {
      final pos = (p.pos ?? '').toUpperCase();
      // Pure side-backs/wing-backs sit outermost; -L/-R tagged roles inside
      // them; central roles in the middle.
      if (pos == 'LB' || pos == 'LWB') return -2;
      if (pos.contains('L')) return -1;
      if (pos == 'RB' || pos == 'RWB') return 2;
      if (pos.contains('R')) return 1;
      return 0;
    }

    for (final row in [d, dm, m, am, f]) {
      row.sort((a, b) {
        final la = lane(a), lb = lane(b);
        if (la != lb) return la.compareTo(lb);
        return (int.tryParse(a.formationPlace ?? '') ?? 0)
            .compareTo(int.tryParse(b.formationPlace ?? '') ?? 0);
      });
    }
    return [gk, ...[d, dm, m, am, f].where((r) => r.isNotEmpty)];
  }
}

class _PlayerDot extends StatelessWidget {
  final LineupPlayer player;
  final double x, y;
  final Color color;
  final String league;
  final String? teamColorHex;
  const _PlayerDot(
      {required this.player,
      required this.x,
      required this.y,
      required this.color,
      required this.league,
      this.teamColorHex});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment(x * 2 - 1, y * 2 - 1),
        child: InkWell(
          onTap: player.id == null
              ? null
              : () => openPlayerPage(context, league,
                  athleteId: player.id!,
                  name: player.name,
                  color: teamColorHex),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Text(player.jersey ?? '',
                  style: TextStyle(
                      fontFamily: 'BarlowCondensed',
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: onColor(color))),
            ),
            const SizedBox(height: 3),
            Text(player.name.split(' ').last,
                maxLines: 1,
                style: const TextStyle(fontSize: 10.5, color: T.textBody)),
          ]),
        ),
      );
}

// ---- shot map (design 9b) -----------------------------------------------------------

/// SHOT MAP — every attempt plotted at its spot (home attacks right, away
/// mirrored left), colored by outcome, tappable; the selected shot's detail
/// (player, outcome·minute, distance / technique / situation) inset below.
/// No xG — ESPN serves none, so those cells simply don't exist (§11.8).
class ShotMapCard extends StatefulWidget {
  final Competition comp;
  final List<MatchFeedPlay> shots;
  final List<Lineup> lineups;
  const ShotMapCard(
      {super.key, required this.comp, required this.shots, required this.lineups});

  @override
  State<ShotMapCard> createState() => _ShotMapCardState();
}

class _ShotMapCardState extends State<ShotMapCard> {
  int? _sel;

  static const _outcomeColor = {
    'goal': T.green,
    'saved': T.gold,
    'blocked': T.live,
  };
  static const _outcomeLabel = {
    'goal': 'GOAL',
    'saved': 'SAVED',
    'blocked': 'BLOCKED',
    'off': 'OFF TARGET',
  };

  @override
  Widget build(BuildContext context) {
    final shots = widget.shots;
    if (shots.isEmpty) return const SizedBox.shrink();
    final sel = (_sel ?? shots.length - 1).clamp(0, shots.length - 1);
    final outcomes = shots.map(shotOutcome).toSet();
    return V2Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Align(
            alignment: Alignment.centerLeft, child: CardLabel('Shot map')),
        const SizedBox(height: 12),
        // Legend — only the outcomes present (never an empty chip).
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final o in ['goal', 'saved', 'off', 'blocked'])
            if (outcomes.contains(o)) _LegendChip(o, _outcomeColor[o]),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            color: _pitchBg,
            child: AspectRatio(
              aspectRatio: 340 / 190,
              child: LayoutBuilder(
                builder: (context, c) => GestureDetector(
                  onTapUp: (d) => _onTap(d.localPosition,
                      Size(c.maxWidth, c.maxHeight)),
                  child: CustomPaint(
                    size: Size(c.maxWidth, c.maxHeight),
                    painter: _ShotMapPainter(
                      comp: widget.comp,
                      shots: shots,
                      selected: sel,
                      colorOf: (p) =>
                          _outcomeColor[shotOutcome(p)] ?? T.textDim,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _ShotDetail(
          shot: shots[sel],
          index: sel,
          count: shots.length,
          comp: widget.comp,
          lineups: widget.lineups,
          outcomeLabel: _outcomeLabel[shotOutcome(shots[sel])]!,
          outcomeColor: _outcomeColor[shotOutcome(shots[sel])] ?? T.textDim,
          onPrev: sel > 0 ? () => setState(() => _sel = sel - 1) : null,
          onNext: sel < shots.length - 1
              ? () => setState(() => _sel = sel + 1)
              : null,
        ),
      ]),
    );
  }

  void _onTap(Offset local, Size size) {
    var best = -1;
    var bestD = double.infinity;
    for (var i = 0; i < widget.shots.length; i++) {
      final s = widget.shots[i];
      if (s.x == null) continue;
      final f = _toPitch(s.side, s.x!, s.y ?? 50);
      final pt = Offset(f.dx * size.width, f.dy * size.height);
      final d = (pt - local).distance;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    if (best >= 0 && bestD < 28) setState(() => _sel = best);
  }
}

class _LegendChip extends StatelessWidget {
  final String outcome;
  final Color? color;
  const _LegendChip(this.outcome, this.color);
  @override
  Widget build(BuildContext context) {
    final label = const {
      'goal': 'Goal',
      'saved': 'Save',
      'off': 'Off target',
      'blocked': 'Block',
    }[outcome]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: T.border, width: 1.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 8,
          height: 8,
          decoration: color != null
              ? BoxDecoration(color: color, shape: BoxShape.circle)
              : BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: T.textDim, width: 1.5)),
        ),
        const SizedBox(width: 5),
        Text(label, style: T.captionFaint),
      ]),
    );
  }
}

class _ShotMapPainter extends CustomPainter {
  final Competition comp;
  final List<MatchFeedPlay> shots;
  final int selected;
  final Color Function(MatchFeedPlay) colorOf;
  const _ShotMapPainter(
      {required this.comp,
      required this.shots,
      required this.selected,
      required this.colorOf});

  @override
  void paint(Canvas canvas, Size size) {
    const _PitchPainter().paint(canvas, size);
    Offset at(MatchFeedPlay s) {
      final f = _toPitch(s.side, s.x ?? 50, s.y ?? 50);
      return Offset(f.dx * size.width, f.dy * size.height);
    }

    for (var i = 0; i < shots.length; i++) {
      if (i == selected) continue;
      final s = shots[i];
      if (s.x == null) continue;
      final c = colorOf(s);
      final o = shotOutcome(s);
      if (o == 'off') {
        canvas.drawCircle(
            at(s),
            6,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = T.textDim);
      } else {
        canvas.drawCircle(at(s), 7, Paint()..color = c);
        canvas.drawCircle(
            at(s),
            7,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = _pitchBg);
      }
    }
    // Selected: bigger, white ring + halo, and the trajectory when known.
    final s = shots[selected];
    if (s.x == null) return;
    final pt = at(s);
    if (s.x2 != null) {
      final f2 = _toPitch(s.side, s.x2!, s.y2 ?? 50);
      canvas.drawLine(
          pt,
          Offset(f2.dx * size.width, f2.dy * size.height),
          Paint()
            ..color = T.text.withValues(alpha: 0.5)
            ..strokeWidth = 1.5);
    }
    canvas.drawCircle(
        pt, 13, Paint()..color = colorOf(s).withValues(alpha: 0.35));
    canvas.drawCircle(pt, 10, Paint()..color = colorOf(s));
    canvas.drawCircle(
        pt,
        10,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = T.text.withValues(alpha: 0.85));
  }

  @override
  bool shouldRepaint(covariant _ShotMapPainter old) =>
      old.shots != shots || old.selected != selected;
}

class _ShotDetail extends StatelessWidget {
  final MatchFeedPlay shot;
  final int index, count;
  final Competition comp;
  final List<Lineup> lineups;
  final String outcomeLabel;
  final Color outcomeColor;
  final VoidCallback? onPrev, onNext;
  const _ShotDetail(
      {required this.shot,
      required this.index,
      required this.count,
      required this.comp,
      required this.lineups,
      required this.outcomeLabel,
      required this.outcomeColor,
      this.onPrev,
      this.onNext});

  @override
  Widget build(BuildContext context) {
    final player = _lineupPlayer(shot.athleteId, lineups);
    final name = player?.name ?? _playerFromShortText(shot) ?? '';
    final side = _sideCompetitor(comp, shot.side);
    final caption = [
      side?.abbreviation,
      player?.pos,
    ].whereType<String>().join(' · ');
    final technique = shotTechnique(shot);
    final cells = <(String, String)>[
      if (shot.x != null)
        ('${yardsToGoal(shot.x!, shot.y ?? 50)} yds', 'DISTANCE'),
      if (technique != null) (technique, 'SHOT TYPE'),
      (shotSituation(shot), 'SITUATION'),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: T.track, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration:
                BoxDecoration(color: teamColor(side), shape: BoxShape.circle),
            child: Text(player?.jersey ?? '',
                style: TextStyle(
                    fontFamily: 'BarlowCondensed',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: onColor(teamColor(side)))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(TextSpan(children: [
                TextSpan(
                    text: name,
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: T.text)),
                if (caption.isNotEmpty)
                  TextSpan(text: '  $caption', style: T.captionFaint),
              ])),
              const SizedBox(height: 2),
              Text(
                  [outcomeLabel, if (shot.clock != null) shot.clock!]
                      .join(' · '),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: outcomeColor)),
            ]),
          ),
          _PagerArrow(Icons.chevron_left_rounded, onPrev),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('${index + 1} of $count', style: T.captionFaint),
          ),
          _PagerArrow(Icons.chevron_right_rounded, onNext),
        ]),
        if (cells.isNotEmpty) ...[
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.only(top: 12),
            decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: T.border))),
            child: Row(children: [
              for (final (value, label) in cells)
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(value,
                            style: const TextStyle(
                                fontFamily: 'BarlowCondensed',
                                fontWeight: FontWeight.w700,
                                fontSize: 17,
                                color: T.text,
                                fontFeatures: [
                                  FontFeature.tabularFigures()
                                ])),
                        const SizedBox(height: 2),
                        Text(label,
                            style: const TextStyle(
                                fontSize: 10,
                                letterSpacing: 0.5,
                                color: T.textFaint)),
                      ]),
                ),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _PagerArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _PagerArrow(this.icon, this.onTap);
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon,
              size: 20, color: onTap == null ? T.ghost : T.textDim),
        ),
      );
}
