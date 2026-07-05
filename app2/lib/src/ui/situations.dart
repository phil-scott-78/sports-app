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
                if (s.outs != null) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    DotRow(filled: s.outs!.clamp(0, 3), total: 3),
                    const SizedBox(width: 6),
                    const Text('OUTS', style: T.captionFaint),
                  ]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
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
              Text(caption, style: T.caption),
            ],
          ),
          if (pos != null) ...[
            const SizedBox(height: 12),
            _FieldBar(
              ballPct: pos.ballPct,
              sticksPct: pos.sticksPct,
              possessionColor: teamColor(poss),
              defenseColor: teamColor(defense),
              redZone: s.isRedZone ?? false,
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
  const _FieldBar({
    required this.ballPct,
    required this.sticksPct,
    required this.possessionColor,
    required this.defenseColor,
    required this.redZone,
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
                Text('first down marker',
                    style: T.captionFaint.copyWith(color: T.gold)),
              ]),
            ),
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

class MatchTimelineCard extends StatelessWidget {
  final Competition comp;
  const MatchTimelineCard(this.comp, {super.key});

  @override
  Widget build(BuildContext context) {
    final total = _regulationMinutes(comp);
    final now = comp.status.live ? _clockMinutes(comp.status.clock) : null;
    final recent = comp.events.reversed.take(3).toList();
    final nowLabel = comp.status.live
        ? (comp.status.shortDetail ?? comp.status.detail)
        : null;

    return V2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const CardLabel('Match timeline'),
            const Spacer(),
            if (nowLabel != null)
              Text(nowLabel, style: T.cardLabel.copyWith(color: T.text)),
          ]),
          const SizedBox(height: 14),
          SizedBox(
            height: 34,
            child: LayoutBuilder(builder: (context, box) {
              final w = box.maxWidth;
              double x(int minute) => w * minute.clamp(0, total) / total;
              return Stack(children: [
                Positioned(
                    left: 0,
                    right: 0,
                    top: 15,
                    child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                            color: T.track,
                            borderRadius: BorderRadius.circular(2)))),
                if (now != null)
                  Positioned(
                      left: 0,
                      top: 15,
                      child: Container(
                          width: x(now),
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
                  if (_clockMinutes(e.clock) != null)
                    Positioned(
                      left: x(_clockMinutes(e.clock)!) -
                          (e.redCard || e.type == 'red-card' ? 5 : 9),
                      top: e.redCard || e.type == 'red-card' ? 10 : 8,
                      child: _marker(e),
                    ),
                if (now != null)
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
                    padding: const EdgeInsets.symmetric(vertical: 3),
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

  Widget _marker(ScoringEvent e, {bool small = false}) {
    if (e.type == 'red-card' || e.redCard) {
      return RedCardGlyph(height: small ? 12 : 14);
    }
    if (e.type == 'yellow-card') {
      return Container(
          width: small ? 8 : 10,
          height: small ? 12 : 14,
          decoration: BoxDecoration(
              color: T.gold, borderRadius: BorderRadius.circular(1.5)));
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
        Expanded(
          child: Text(blockName(c),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.blockName.copyWith(fontSize: 32, color: color)),
        ),
        for (var s = 1; s <= maxSets; s++)
          SizedBox(
            width: 34,
            child: Text(
              _setDisplay(c, s),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'BarlowCondensed',
                fontWeight: FontWeight.w700,
                fontSize: 22,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: _setColor(c, s, current, dim),
              ),
            ),
          ),
      ]),
    );
  }

  String _setDisplay(Competitor c, int set) {
    for (final p in c.periodScores) {
      if (p.period == set) return p.display;
    }
    return '';
  }

  Color _setColor(Competitor c, int set, int current, bool dim) {
    if (set == current) return dim ? T.textDim : T.text;
    for (final p in c.periodScores) {
      if (p.period == set) {
        return p.setWinner == true ? T.textDim : T.textFaint;
      }
    }
    return T.textFaint;
  }
}

// ═══════════════════════════ field leaderboard (golf / racing / athletics) ═══

/// Ordered competitor list for field-layout events. Golf (toPar) gets
/// TODAY-ish coloring (red under par); racing/athletics show the display
/// score (time/laps/points) right-aligned.
class FieldLeaderboard extends StatelessWidget {
  final Competition comp;
  final int maxRows;
  final Set<String> highlightIds;
  const FieldLeaderboard(this.comp,
      {super.key, this.maxRows = 10, this.highlightIds = const {}});

  @override
  Widget build(BuildContext context) {
    final list = List.of(comp.competitors)
      ..sort((a, b) => (a.order ?? 1 << 20).compareTo(b.order ?? 1 << 20));
    final toPar = comp.scoreKind == 'toPar';
    final rows = list.take(maxRows).toList();
    return V2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
                child: Text(
                    comp.competitorKind == 'athlete' ? 'PLAYER' : 'FIELD',
                    style: T.cardLabelFaint)),
            if (toPar) ...[
              const SizedBox(
                  width: 48,
                  child: Text('THRU',
                      textAlign: TextAlign.center, style: T.cardLabelFaint)),
              const SizedBox(
                  width: 52,
                  child: Text('TOTAL',
                      textAlign: TextAlign.right, style: T.cardLabelFaint)),
            ] else
              const Text('', style: T.cardLabelFaint),
          ]),
          const SizedBox(height: 4),
          for (var i = 0; i < rows.length; i++)
            _row(rows[i], i, toPar: toPar),
        ],
      ),
    );
  }

  Widget _row(Competitor c, int i, {required bool toPar}) {
    final first = i == 0;
    final highlight = highlightIds.contains(c.id);
    final scoreColor = toPar && (c.score?.toPar ?? 0) < 0 ? T.underPar : T.text;
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
            width: 48,
            child: Text(_thru(c),
                textAlign: TextAlign.center,
                style: T.statLine.copyWith(color: T.textDim)),
          ),
          SizedBox(
            width: 52,
            child: Text(c.score?.display ?? '',
                textAlign: TextAlign.right,
                style: T.statLineStrong.copyWith(color: scoreColor)),
          ),
        ] else
          Text(c.score?.display ?? '',
              style: T.statLine.copyWith(color: first ? T.text : T.textDim)),
      ]),
    );
    if (!highlight) return row;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          T.gold.withValues(alpha: 0.07),
          T.gold.withValues(alpha: 0.0),
        ]),
      ),
      child: row,
    );
  }

  String _thru(Competitor c) {
    // Current round's holes played; 'F' when the round is done.
    PeriodScore? latest;
    for (final p in c.periodScores) {
      if (p.holesPlayed != null &&
          (latest == null || p.period > latest.period)) {
        latest = p;
      }
    }
    final h = latest?.holesPlayed;
    if (h == null) return '';
    return h >= 18 ? 'F' : '$h';
  }

  String? _flag(Competitor c) {
    final a = c.athletes;
    if (a.isEmpty) return null;
    return a.first.country;
  }
}
