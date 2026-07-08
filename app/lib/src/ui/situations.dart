import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import '../util.dart';
import 'widgets.dart';

/// Sport-specific "situation" cards — the one card on the live detail screen
/// that changes shape per sport. Selection is data-driven (which optional
/// canonical fields are present), never by sport name:
///   situation.hasBaseball  → count + diamond + outs
///   situation.hasGridiron  → down & distance + field position bar
///   competition.events     → match timeline (soccer/rugby cheap feed)
///   periodScores(cricket)  → the chase equation
/// Returns null when nothing applies (the detail page just omits the card).
Widget? situationCardFor(Competition comp) {
  final sit = comp.situation;
  if (sit != null && sit.hasBaseball) return BaseballSituationCard(comp);
  if (sit != null && sit.hasGridiron) return GridironSituationCard(comp);
  if (sit != null && sit.hasBonus) return BasketballSituationCard(comp);
  if (sit != null && sit.hasPowerPlay) return PowerPlaySituationCard(comp);
  if (comp.status.live && _cricketChase(comp) != null) {
    return CricketChaseCard(comp);
  }
  if (comp.events.isNotEmpty) return MatchTimelineCard(comp);
  return null;
}

// ═══════════════════════════ baseball ═══════════════════════════

class BaseballSituationCard extends StatelessWidget {
  final Competition comp;
  const BaseballSituationCard(this.comp, {super.key});

  @override
  Widget build(BuildContext context) {
    final s = comp.situation!;
    final count = (s.balls != null && s.strikes != null)
        ? '${s.balls}–${s.strikes} COUNT'
        : (s.outsText ?? '').toUpperCase();
    final context2 = <String>[
      if (s.batter != null) '${s.batter} up',
      if (s.batterLine != null) s.batterLine!,
      if (s.pitcher != null) '${s.pitcher} pitching',
      if (s.pitcherLine != null) s.pitcherLine!,
    ];
    return V2Card(
      child: Row(
        children: [
          BaseballDiamond(
            onFirst: s.onFirst ?? false,
            onSecond: s.onSecond ?? false,
            onThird: s.onThird ?? false,
            width: 110,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (count.isNotEmpty)
                  Text(count, style: T.situationHead.copyWith(fontSize: 22)),
                if (context2.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(context2.take(2).join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, height: 1.4, color: T.textDim)),
                ],
                // B/S/O dot rows (§8): balls green, strikes live, outs white.
                if (s.balls != null) _countRow('BALLS', s.balls!, 3, T.green),
                if (s.strikes != null)
                  _countRow('STRIKES', s.strikes!, 2, T.live),
                if (s.outs != null) _countRow('OUTS', s.outs!, 3, T.text),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One §8 count row: a label + [filled]-of-[total] 9px dots in [color].
  Widget _countRow(String label, int filled, int total, Color color) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(children: [
          DotRow(
              filled: filled.clamp(0, total),
              total: total,
              color: color,
              size: 9),
          const SizedBox(width: 8),
          Text(label, style: T.captionFaint),
        ]),
      );
}

// ═══════════════════════════ gridiron ═══════════════════════════

/// Field position parsed out of ESPN's downDistanceText
/// ('3rd & 4 at OU 22'): percent from the possessing team's own goal.
({double ballPct, double? sticksPct})? fieldPosition(Competition comp) {
  final s = comp.situation;
  final text = s?.downDistanceText;
  if (s == null || text == null) return null;
  final m = RegExp(r'at\s+([A-Z][A-Z&.\-]*)\s+(\d{1,2})\b').firstMatch(text);
  if (m == null) return null;
  final sideAbbr = m.group(1)!;
  final yard = int.parse(m.group(2)!);
  if (yard > 50) return null;
  // Whose side of the field? Match the abbr against the possessing team.
  final poss = possessingTeam(comp);
  if (poss?.abbreviation == null) return null;
  final ownSide = poss!.abbreviation!.toUpperCase() == sideAbbr.toUpperCase();
  final ballPct = ownSide ? yard.toDouble() : (100 - yard).toDouble();
  final dist = s.distance;
  final sticks = dist == null ? null : (ballPct + dist).clamp(0.0, 100.0);
  return (ballPct: ballPct, sticksPct: sticks);
}

/// The competitor whose team id matches situation.possession.
Competitor? possessingTeam(Competition comp) {
  final id = comp.situation?.possession;
  if (id == null) return null;
  for (final c in comp.competitors) {
    if (c.id == id) return c;
  }
  return null;
}

class GridironSituationCard extends StatelessWidget {
  final Competition comp;
  const GridironSituationCard(this.comp, {super.key});

  static const _ordinals = ['1ST', '2ND', '3RD', '4TH'];

  @override
  Widget build(BuildContext context) {
    final s = comp.situation!;
    final poss = possessingTeam(comp);
    final pos = fieldPosition(comp);
    final defense = comp.competitors
        .where((c) => c.id != poss?.id)
        .cast<Competitor?>()
        .firstWhere((_) => true, orElse: () => null);

    String headline;
    if (s.down != null && s.down! >= 1 && s.down! <= 4 && s.distance != null) {
      headline = '${_ordinals[s.down! - 1]} & ${s.distance}';
    } else {
      headline = (s.downDistanceText ?? '').toUpperCase();
    }
    // 'at OU 22 · TEX ball'
    final at = RegExp(r'\bat\s+.+$').firstMatch(s.downDistanceText ?? '');
    final caption = [
      if (at != null) at.group(0)!,
      if (poss?.abbreviation != null) '${poss!.abbreviation} ball',
    ].join(' · ');

    return V2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text(headline, style: T.situationHead)),
              // Core-situation red-zone flag: loud when the spot-parse field bar
              // can't render (core carries no downDistanceText), a quiet accent
              // when it can. Data-driven on situation.isRedZone.
              if (s.isRedZone == true) ...[
                const _RedZoneChip(),
                const SizedBox(width: 10),
              ],
              if (caption.isNotEmpty) Text(caption, style: T.caption),
            ],
          ),
          if (pos != null) ...[
            const SizedBox(height: 14),
            _FieldBar(
              ballPct: pos.ballPct,
              sticksPct: pos.sticksPct,
              possessionColor: teamColor(poss),
              defenseColor: teamColor(defense),
              redZone: s.isRedZone ?? false,
              yardsToGo: s.distance,
            ),
          ],
          if (s.homeTimeouts != null || s.awayTimeouts != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.only(top: 12),
              decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: T.divider))),
              child: Row(children: [
                const Text('TIMEOUTS', style: T.captionFaint),
                const Spacer(),
                _timeouts(comp.away, s.awayTimeouts),
                const SizedBox(width: 14),
                _timeouts(comp.home, s.homeTimeouts),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _timeouts(Competitor? c, int? n) => Row(children: [
        if (c != null)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(c.label,
                style: T.statLine.copyWith(fontSize: 13, color: T.textDim)),
          ),
        DotRow(filled: (n ?? 0).clamp(0, 3), total: 3, color: teamColor(c), size: 7),
      ]);
}

class _FieldBar extends StatelessWidget {
  final double ballPct;
  final double? sticksPct;
  final Color possessionColor, defenseColor;
  final bool redZone;
  final int? yardsToGo;
  const _FieldBar({
    required this.ballPct,
    required this.sticksPct,
    required this.possessionColor,
    required this.defenseColor,
    required this.redZone,
    this.yardsToGo,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 56,
              child: LayoutBuilder(builder: (context, box) {
                final w = box.maxWidth;
                return Stack(children: [
                  Container(color: const Color(0xFF161A20)),
                  // yard gridlines every 10%
                  for (var i = 1; i < 10; i++)
                    Positioned(
                        left: w * i / 10,
                        top: 0,
                        bottom: 0,
                        child: Container(width: 1, color: T.fieldLine)),
                  // defended endzone
                  Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      width: w * 0.09,
                      child: Container(
                          color: defenseColor
                              .withValues(alpha: redZone ? 0.7 : 0.5))),
                  // territory gained up to the ball
                  Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: w * ballPct / 100,
                      child: Container(
                          color: possessionColor.withValues(alpha: 0.22))),
                  Positioned(
                      left: w * ballPct / 100 - 1.5,
                      top: 0,
                      bottom: 0,
                      child: Container(width: 3, color: possessionColor)),
                  if (sticksPct != null)
                    Positioned(
                        left: w * sticksPct! / 100 - 1,
                        top: 0,
                        bottom: 0,
                        child: Container(width: 2, color: T.gold)),
                ]);
              }),
            ),
          ),
          if (sticksPct != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                const Spacer(),
                Text(
                    yardsToGo != null
                        ? '$yardsToGo yds to the sticks'
                        : 'first-down marker',
                    style: T.captionFaint.copyWith(color: T.gold)),
              ]),
            ),
        ],
      );
}

/// The §8 gridiron red-zone flag — a small `live`-red pill. Rendered beside the
/// down&distance headline when core `situation.isRedZone` is set (the one spot
/// signal the core tier carries when it has no down-distance text to draw a bar).
class _RedZoneChip extends StatelessWidget {
  const _RedZoneChip();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: T.live.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text('RED ZONE',
            style: T.captionFaint.copyWith(
                color: T.live, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
      );
}

// ═══════════════════════════ basketball bonus & timeouts ═════════════════════

/// The §8 basketball footer as its own card — the bonus/timeout state ESPN keeps
/// on the CORE situation (never the scoreboard), surfaced on detail open. Per side:
/// the team, a `gold` BONUS / DOUBLE BONUS flag when in the bonus, and the
/// remaining-timeout dots. Data-driven: rendered only when `situation.hasBonus`.
class BasketballSituationCard extends StatelessWidget {
  final Competition comp;
  const BasketballSituationCard(this.comp, {super.key});

  static String? _bonusLabel(String? state) {
    if (state == null) return null;
    final s = state.toUpperCase();
    if (s == 'NONE') return null;
    if (s == 'DOUBLE') return 'DOUBLE BONUS';
    return 'BONUS';
  }

  @override
  Widget build(BuildContext context) {
    final sit = comp.situation!;
    return V2Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const CardLabel('Bonus & timeouts'),
        const SizedBox(height: 12),
        _sideRow(comp.away, _bonusLabel(sit.awayBonus), sit.awayTimeouts),
        const SizedBox(height: 10),
        _sideRow(comp.home, _bonusLabel(sit.homeBonus), sit.homeTimeouts),
        if (sit.lastPlay != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: T.divider))),
            child: Text(sit.lastPlay!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13, height: 1.4, color: T.textDim)),
          ),
        ],
      ]),
    );
  }

  Widget _sideRow(Competitor? c, String? bonus, int? timeouts) => Row(children: [
        ColorBar(teamColor(c), width: 4, height: 20, radius: 2),
        const SizedBox(width: 10),
        Text(c?.label ?? '',
            style: T.statLine.copyWith(fontSize: 14, color: T.text)),
        if (bonus != null) ...[
          const SizedBox(width: 10),
          Text(bonus,
              style: T.captionFaint
                  .copyWith(color: T.gold, fontWeight: FontWeight.w700)),
        ],
        const Spacer(),
        if (timeouts != null) ...[
          // Only the REMAINING count is observed (core has no used total), so
          // render that many team-color dots — never fabricate the used seats.
          DotRow(
              filled: timeouts.clamp(0, 7),
              total: timeouts.clamp(0, 7),
              color: teamColor(c),
              size: 7),
          const SizedBox(width: 8),
          Text('${timeouts.clamp(0, 9)} TO', style: T.captionFaint),
        ],
      ]);
}

// ═══════════════════════════ hockey power play ═══════════════════════════════

/// The §8 hockey power-play card. ESPN exposes the power-play state + the side on
/// the man advantage (situation.strength/strengthTeam), but NO running penalty
/// countdown — so this shows strength + which team + the skater dots, and omits
/// the (unsourceable) countdown clock. One-man advantage (5v4) is the standard
/// power play and the only strength ESPN's cheap tier distinguishes.
class PowerPlaySituationCard extends StatelessWidget {
  final Competition comp;
  const PowerPlaySituationCard(this.comp, {super.key});

  @override
  Widget build(BuildContext context) {
    final sit = comp.situation!;
    Competitor? pp;
    for (final c in comp.competitors) {
      if (c.id == sit.strengthTeam) pp = c;
    }
    final other = pp == null
        ? null
        : comp.competitors
            .cast<Competitor?>()
            .firstWhere((c) => c?.id != pp!.id, orElse: () => null);
    final ppColor = teamColor(pp);
    final otherColor = teamColor(other);
    final shortHanded = sit.strength == 'short-handed';
    return V2Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('POWER PLAY',
              style: T.situationHead.copyWith(color: T.gold)),
          const Spacer(),
          if (pp != null)
            Text('${pp.label} ADVANTAGE', style: T.cardLabelFaint),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          _SkaterDots(color: ppColor, skaters: 5),
          const SizedBox(width: 12),
          const Text('5', style: T.statCallout),
          Text('  v  ', style: T.statCallout.copyWith(color: T.textDim)),
          Text('4', style: T.statCallout.copyWith(color: T.textDim)),
          const SizedBox(width: 12),
          // the penalised side skates a man short — the box seat is dashed.
          _SkaterDots(color: otherColor, skaters: 4, penaltyBox: true),
        ]),
        if (sit.lastPlay != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: T.divider))),
            child: Text(
                shortHanded
                    ? 'Shorthanded · ${sit.lastPlay}'
                    : sit.lastPlay!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13, height: 1.4, color: T.textDim)),
          ),
        ],
      ]),
    );
  }
}

/// A row of on-ice skater dots (§8 hockey): [skaters] filled team-color circles,
/// plus a dashed "penalty box" seat when the side is a man short.
class _SkaterDots extends StatelessWidget {
  final Color color;
  final int skaters;
  final bool penaltyBox;
  const _SkaterDots(
      {required this.color, required this.skaters, this.penaltyBox = false});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < skaters; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Container(
                width: 11,
                height: 11,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle)),
          ],
          if (penaltyBox) ...[
            const SizedBox(width: 4),
            const DashedRing(size: 11, color: T.outline),
          ],
        ],
      );
}

// ═══════════════════════════ match timeline (soccer/rugby) ═══════════════════

/// Parse a soccer clock ("45'+2'", "73'") to minutes, tolerant of stoppage.
int? _clockMinutes(String? clock) {
  if (clock == null) return null;
  final m = RegExp(r'^(\d+)').firstMatch(clock.trim());
  if (m == null) return null;
  var min = int.parse(m.group(1)!);
  final plus = RegExp(r"\+\s*(\d+)").firstMatch(clock);
  if (plus != null) min += int.parse(plus.group(1)!);
  return min;
}

/// A one-line soccer/rugby context for dense rows and hero footers, read off the
/// cheap [Competition.events] timeline (no /summary needed): who's a man down,
/// or the latest goal. Null when the timeline carries neither. [goalFirst] flips
/// the preference — the hero card already shows a "10 MEN" badge, so its footer
/// leads with the goal instead.
String? matchRowContext(Competition comp, {bool goalFirst = false}) {
  if (comp.events.isEmpty) return null;

  String? manDown() {
    final reds = comp.redCardsBySide;
    if (reds.isEmpty) return null;
    // The side carrying the most red cards is the one down a player.
    final worst = reds.entries.reduce((a, b) => b.value > a.value ? b : a);
    final side = worst.key == 'home' ? comp.home : comp.away;
    final abbr = side?.label ?? worst.key.toUpperCase();
    return '$abbr down to ${11 - worst.value}';
  }

  String? lastGoal() {
    for (final e in comp.events.reversed) {
      if (e.isGoal && (e.athlete?.isNotEmpty ?? false)) {
        return e.clock != null ? '${e.athlete} ${e.clock}' : e.athlete;
      }
    }
    return null;
  }

  return goalFirst ? (lastGoal() ?? manDown()) : (manDown() ?? lastGoal());
}

class MatchTimelineCard extends StatelessWidget {
  final Competition comp;
  const MatchTimelineCard(this.comp, {super.key});

  @override
  Widget build(BuildContext context) {
    final total = _regulationMinutes(comp);
    final live = comp.status.live;
    final now = live ? _clockMinutes(comp.status.clock) : null;
    final recent = _curatedRecent();
    final rightLabel = live
        ? (comp.status.shortDetail ?? comp.status.detail)
        : (comp.status.ended ? 'FT' : null);
    // How much of the bar is "played": the live clock position, or a full bar
    // at full-time — so the timeline reads as a finished story on the Recap,
    // not markers floating on an empty track.
    final double? progress = live
        ? (now == null ? null : now.clamp(0, total) / total)
        : (comp.status.ended ? 1.0 : null);

    return V2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const CardLabel('Match timeline'),
            const Spacer(),
            if (rightLabel != null)
              Text(rightLabel, style: T.cardLabel.copyWith(color: T.text)),
          ]),
          const SizedBox(height: 14),
          SizedBox(
            height: 34,
            child: LayoutBuilder(builder: (context, box) {
              final w = box.maxWidth;
              double x(int minute) => w * minute.clamp(0, total) / total;
              // Keep every marker fully on the rail — stoppage-time minutes
              // (90'+8) clamp into the last sliver instead of hanging off the
              // right edge (x() already clamps the minute; this clamps the glyph).
              Positioned markerAt(ScoringEvent e) {
                final isRed = e.redCard || e.type == 'red-card';
                final hw = isRed ? 5.0 : 9.0;
                final left =
                    (x(_clockMinutes(e.clock)!) - hw).clamp(0.0, w - hw * 2);
                return Positioned(
                  left: left,
                  top: isRed ? 10 : 8,
                  child: KeyedSubtree(
                      key: ValueKey('railMarker:${e.clock}'),
                      child: _marker(e)),
                );
              }

              return Stack(children: [
                Positioned(
                    left: 0,
                    right: 0,
                    top: 15,
                    child: Container(
                        key: const ValueKey('timelineTrack'),
                        height: 4,
                        decoration: BoxDecoration(
                            color: T.track,
                            borderRadius: BorderRadius.circular(2)))),
                if (progress != null)
                  Positioned(
                      left: 0,
                      top: 15,
                      child: Container(
                          width: w * progress,
                          height: 4,
                          decoration: BoxDecoration(
                              color: const Color(0xFF3A4250),
                              borderRadius: BorderRadius.circular(2)))),
                // halftime tick
                Positioned(
                    left: w / 2,
                    top: 9,
                    bottom: 9,
                    child: Container(width: 1.5, color: T.outline)),
                for (final e in comp.events)
                  if (_clockMinutes(e.clock) != null) markerAt(e),
                if (live && now != null)
                  Positioned(
                      left: x(now) - 1.25,
                      top: 5,
                      bottom: 5,
                      child: Container(width: 2.5, color: T.text)),
              ]);
            }),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('KO', style: T.captionFaint.copyWith(fontSize: 10)),
              Text('HT', style: T.captionFaint.copyWith(fontSize: 10)),
              Text("$total′", style: T.captionFaint.copyWith(fontSize: 10)),
            ],
          ),
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.only(top: 12),
              decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: T.divider))),
              child: Column(children: [
                for (final e in recent)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(children: [
                      SizedBox(
                          width: 30,
                          child: Text(e.clock ?? '',
                              style: T.statLine
                                  .copyWith(fontSize: 12, color: T.textFaint))),
                      _marker(e, small: true),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(_eventText(e),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontSize: 12, color: T.textDim)),
                      ),
                    ]),
                  ),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  int _regulationMinutes(Competition comp) {
    final p = comp.periods;
    final len = p.lengthMin ?? 45;
    final reg = p.regulation > 0 ? p.regulation : 2;
    final total = len * reg;
    return total > 0 ? total : 90;
  }

  /// The recent-event rows below the rail: the signal events — goals and red
  /// cards — newest first, capped, so a three-goal second half doesn't bury the
  /// early match (design 6a curates, it doesn't tail). Falls back to the last
  /// three events when nothing signal-worthy has happened yet. The rail above
  /// still plots every event.
  List<ScoringEvent> _curatedRecent() {
    final signal = [
      for (final e in comp.events.reversed)
        if (e.isGoal || e.redCard || e.type == 'red-card') e,
    ];
    if (signal.isNotEmpty) return signal.take(5).toList();
    return comp.events.reversed.take(3).toList();
  }

  Widget _marker(ScoringEvent e, {bool small = false}) {
    if (e.type == 'red-card' || e.redCard) {
      return RedCardGlyph(height: small ? 12 : 14);
    }
    if (e.type == 'yellow-card') {
      return Container(
          width: small ? 8 : 10,
          height: small ? 12 : 14,
          decoration: BoxDecoration(
              color: T.gold, borderRadius: BorderRadius.circular(2)));
    }
    final side = e.team == 'home' ? comp.home : comp.away;
    return Container(
      width: small ? 12 : 18,
      height: small ? 12 : 18,
      decoration: BoxDecoration(
        color: teamColor(side),
        shape: BoxShape.circle,
        border: small ? null : Border.all(color: T.bg, width: 2),
      ),
    );
  }

  String _eventText(ScoringEvent e) {
    final what = e.detail == null || e.detail!.isEmpty ? e.type : e.detail!;
    final who = e.athlete;
    if (who == null || who.isEmpty) return what;
    return '$who — $what';
  }
}

// ═══════════════════════════ cricket ═══════════════════════════

/// The chase numbers, when the second innings is underway with a target:
/// runs needed + balls remaining + required rate.
({int need, int? ballsLeft, String? reqRate})? _cricketChase(Competition comp) {
  if (comp.scoreKind != 'cricket') return null;
  for (final c in comp.competitors) {
    for (final p in c.periodScores) {
      final ck = p.cricket;
      if (ck?.isBatting == true && ck?.target != null && ck?.runs != null) {
        final need = (ck!.target! - ck.runs!).toInt();
        if (need <= 0) return null;
        int? ballsLeft;
        String? reqRate;
        final overs = ck.overs;
        // Only T20/ODI (limited overs) can know balls left; tests/first-class
        // can't, so those just show runs needed.
        final limit = _oversLimit(comp);
        if (overs != null && limit != null) {
          final ballsBowled = (overs.floor() * 6 + ((overs * 10) % 10)).round();
          ballsLeft = limit * 6 - ballsBowled;
          if (ballsLeft > 0) {
            reqRate = (need * 6 / ballsLeft).toStringAsFixed(2);
          }
        }
        return (need: need, ballsLeft: ballsLeft, reqRate: reqRate);
      }
    }
  }
  return null;
}

int? _oversLimit(Competition comp) {
  final cls = comp.meta?.cricketClass?.toLowerCase() ?? '';
  if (cls.contains('t20')) return 20;
  if (cls.contains('odi') || cls.contains('one day')) return 50;
  return null;
}

class CricketChaseCard extends StatelessWidget {
  final Competition comp;
  const CricketChaseCard(this.comp, {super.key});

  @override
  Widget build(BuildContext context) {
    final chase = _cricketChase(comp)!;
    final headline = chase.ballsLeft != null && chase.ballsLeft! > 0
        ? '${chase.need} OFF ${chase.ballsLeft}'
        : '${chase.need} TO WIN';
    final sub = comp.meta?.cricketSummary ??
        (chase.reqRate != null ? 'req. ${chase.reqRate}' : '');
    return V2Card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(headline, style: T.situationHead),
          const Spacer(),
          Flexible(
              child: Text(sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.caption)),
        ],
      ),
    );
  }
}

// ═══════════════════════════ tennis set grid ═══════════════════════════

/// Whether this competition's score block should be a per-set grid.
bool isSetGrid(Competition comp) =>
    comp.periods.unit == 'set' &&
    comp.competitors.any((c) => c.periodScores.isNotEmpty);

/// The tennis score block: one row per side — name, per-set numbers, then the
/// match sets total. Replaces the giant score block on detail.
class SetGridBlock extends StatelessWidget {
  final Competition comp;
  const SetGridBlock(this.comp, {super.key});

  @override
  Widget build(BuildContext context) {
    final cs = comp.competitors;
    if (cs.length < 2) return const SizedBox.shrink();
    final maxSets =
        cs.map((c) => c.periodScores.length).fold(0, (a, b) => a > b ? a : b);
    final lead = leadingSide(comp);
    return Column(children: [
      for (final c in cs) _row(c, maxSets, dim: lead != null && lead != c),
    ]);
  }

  Widget _row(Competitor c, int maxSets, {required bool dim}) {
    final color = dim ? T.textDim : T.text;
    final current = comp.status.live ? comp.periods.played : -1;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: T.border, width: 2))),
      child: Row(children: [
        ColorBar(teamColor(c), width: 12, height: 38, radius: 3),
        const SizedBox(width: 12),
        Flexible(
          child: Text(blockName(c),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.blockName.copyWith(fontSize: 32, color: color)),
        ),
        // serve dot (§8 tennis): the ball-chartreuse marker on the server.
        if (c.serving == true) ...[
          const SizedBox(width: 10),
          Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(
                  color: T.serveBall, shape: BoxShape.circle)),
        ],
        const Spacer(),
        for (var s = 1; s <= maxSets; s++) _setCell(c, s, current, dim),
        // the match sets total (§8 tennis / volleyball "sets won as the score").
        if ((c.score?.display ?? '').isNotEmpty)
          SizedBox(
            width: 40,
            child: Text(c.score!.display,
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontFamily: 'BarlowCondensed',
                    fontWeight: FontWeight.w700,
                    fontSize: 26,
                    height: 1.0,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: color)),
          ),
      ]),
    );
  }

  PeriodScore? _psFor(Competitor c, int set) {
    for (final p in c.periodScores) {
      if (p.period == set) return p;
    }
    return null;
  }

  /// One set column for a player: the games total, with the tiebreak points
  /// riding the set LOSER's cell as a superscript — `6⁴` reads "lost the
  /// breaker 7–4", reconstructing broadcast's `7-6⁽⁴⁾`. (Tiebreak lives on both
  /// sides in the data; only the loser shows it, per convention.)
  Widget _setCell(Competitor c, int set, int current, bool dim) {
    final ps = _psFor(c, set);
    final color = _setColor(c, set, current, dim);
    final base = TextStyle(
      fontFamily: 'BarlowCondensed',
      fontWeight: FontWeight.w700,
      fontSize: 22,
      fontFeatures: const [FontFeature.tabularFigures()],
      color: color,
    );
    final tb = (ps != null && ps.tiebreak != null && ps.setWinner == false)
        ? ps.tiebreak!.round().toString()
        : null;
    return SizedBox(
      width: 30,
      child: Text.rich(
        TextSpan(
          text: ps?.display ?? '',
          style: base,
          children: [
            if (tb != null)
              WidgetSpan(
                alignment: PlaceholderAlignment.top,
                child: Transform.translate(
                  offset: const Offset(1, -1),
                  child: Text(tb,
                      style: base.copyWith(fontSize: 11, color: T.textFaint)),
                ),
              ),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Color _setColor(Competitor c, int set, int current, bool dim) {
    // §8: won sets white, lost sets faint, the current set white.
    if (set == current) return T.text;
    for (final p in c.periodScores) {
      if (p.period == set) {
        return p.setWinner == true ? T.text : T.textFaint;
      }
    }
    return T.textFaint;
  }
}

// ═══════════════════════════ field leaderboard (golf / racing / athletics) ═══

/// Ordered competitor list for field-layout events. Golf (toPar) gets
/// TODAY-ish coloring (red under par); racing/athletics show the display
/// score (time/laps/points) right-aligned. [onRowTap] (golf detail) opens the
/// player's hole-by-hole scorecard.
class FieldLeaderboard extends StatelessWidget {
  final Competition comp;
  final int maxRows;
  final Set<String> highlightIds;
  final void Function(Competitor)? onRowTap;

  /// Racing: show each entrant's constructor/manufacturer between name and
  /// result (dropped when the field carries none). Ignored for golf.
  final bool showConstructor;

  /// Golf (§7a per-round chip): a specific round to read the middle column from —
  /// its header becomes `R{n}` and the value is that round's to-par/holes. Null →
  /// the live TODAY column (the current round).
  final int? round;
  const FieldLeaderboard(this.comp,
      {super.key,
      this.maxRows = 10,
      this.highlightIds = const {},
      this.onRowTap,
      this.showConstructor = false,
      this.round});

  static String _constructor(Competitor c) {
    final v = c.vehicle;
    if (v == null) return '';
    return v.manufacturer ?? v.team ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final list = List.of(comp.competitors)
      ..sort((a, b) => (a.order ?? 1 << 20).compareTo(b.order ?? 1 << 20));
    final toPar = comp.scoreKind == 'toPar';
    final rows = list.take(maxRows).toList();
    final hasConstructor =
        showConstructor && !toPar && rows.any((c) => _constructor(c).isNotEmpty);
    return V2Card(
      padding: T.padTable, // §10 leaderboard table: tighter sides, tables need width
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
                child: Text(
                    comp.competitorKind == 'athlete' ? 'PLAYER' : 'FIELD',
                    style: T.cardLabelFaint)),
            if (toPar) ...[
              // TODAY (§7a): the current round's to-par — under par reads red.
              // A per-round chip relabels it R{n} and reads that round instead.
              SizedBox(
                  width: 44,
                  child: Text(round == null ? 'TODAY' : 'R$round',
                      textAlign: TextAlign.center, style: T.cardLabelFaint)),
              const SizedBox(
                  width: 40,
                  child: Text('THRU',
                      textAlign: TextAlign.center, style: T.cardLabelFaint)),
              // TOTAL is the key-stat column (§10) — its header reads white.
              SizedBox(
                  width: 48,
                  child: Text('TOTAL',
                      textAlign: TextAlign.right,
                      style: T.cardLabelFaint.copyWith(color: T.text))),
            ] else if (hasConstructor) ...[
              const SizedBox(
                  width: 88,
                  child: Text('CONSTRUCTOR', style: T.cardLabelFaint)),
              const SizedBox(
                  width: 56,
                  child: Text('TIME',
                      textAlign: TextAlign.right, style: T.cardLabelFaint)),
            ] else
              const Text('', style: T.cardLabelFaint),
          ]),
          const SizedBox(height: 4),
          for (var i = 0; i < rows.length; i++)
            _row(rows[i], i, toPar: toPar, hasConstructor: hasConstructor),
        ],
      ),
    );
  }

  Widget _row(Competitor c, int i,
      {required bool toPar, bool hasConstructor = false}) {
    final first = i == 0;
    final highlight = highlightIds.contains(c.id);
    // §8 golf: under par → red; even/over par stay dim (only the leaders, who are
    // under par, get the loud color).
    final scoreColor =
        toPar ? ((c.score?.toPar ?? 0) < 0 ? T.underPar : T.textDim) : T.text;
    final row = Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: T.divider))),
      child: Row(children: [
        SizedBox(
          width: 24,
          child: Text('${c.rank ?? c.order ?? i + 1}',
              style: TextStyle(
                  fontFamily: 'BarlowCondensed',
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: first ? T.gold : T.textDim)),
        ),
        Expanded(
          child: Text.rich(
            TextSpan(
              text: c.shortName ?? c.displayName,
              style: T.listText.copyWith(
                  fontWeight: first || highlight
                      ? FontWeight.w600
                      : FontWeight.w400),
              children: [
                if (_flag(c) != null)
                  TextSpan(
                      text: '  ${_flag(c)}',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          color: T.textFaint)),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (toPar) ...[
          SizedBox(
            width: 44,
            child: Text(_today(c),
                textAlign: TextAlign.center,
                style: T.statLine.copyWith(
                    color: _today(c).startsWith('-') ? T.underPar : T.textDim)),
          ),
          SizedBox(
            width: 40,
            child: Text(_thru(c),
                textAlign: TextAlign.center,
                style: T.statLine.copyWith(color: T.textDim)),
          ),
          SizedBox(
            width: 48,
            child: Text(c.score?.display ?? '',
                textAlign: TextAlign.right,
                style: T.statLineStrong.copyWith(color: scoreColor)),
          ),
        ] else if (hasConstructor) ...[
          SizedBox(
            width: 88,
            child: Text(_constructor(c),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: T.listText.copyWith(fontSize: 13, color: T.textDim)),
          ),
          SizedBox(
            width: 56,
            child: Text(c.score?.display ?? '',
                textAlign: TextAlign.right,
                style: T.statLine.copyWith(color: first ? T.text : T.textDim)),
          ),
        ] else
          Text(c.score?.display ?? '',
              style: T.statLine.copyWith(color: first ? T.text : T.textDim)),
      ]),
    );
    Widget out = row;
    if (highlight) {
      out = DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            T.gold.withValues(alpha: 0.07),
            T.gold.withValues(alpha: 0.0),
          ]),
        ),
        child: out,
      );
    }
    if (onRowTap != null) {
      out = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onRowTap!(c),
        child: out,
      );
    }
    return out;
  }

  // The linescore the middle column reads: an explicit [round] when a per-round
  // chip is active, else the current round (highest period with holes played).
  PeriodScore? _roundScore(Competitor c) {
    PeriodScore? latest;
    for (final p in c.periodScores) {
      if (round != null) {
        if (p.period == round) return p;
      } else if (p.holesPlayed != null &&
          (latest == null || p.period > latest.period)) {
        latest = p;
      }
    }
    return latest;
  }

  String _thru(Competitor c) {
    // The round's holes played; 'F' when the round is done.
    final h = _roundScore(c)?.holesPlayed;
    if (h == null) return '';
    return h >= 18 ? 'F' : '$h';
  }

  String _today(Competitor c) {
    // The round's to-par ('-3', 'E', '+1') — §7a TODAY / R{n} column.
    return _roundScore(c)?.display ?? '';
  }

  String? _flag(Competitor c) {
    final a = c.athletes;
    if (a.isEmpty) return null;
    return a.first.country;
  }
}
