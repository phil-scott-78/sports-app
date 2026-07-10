import 'package:flutter/material.dart';
import '../inning_recap.dart';
import '../lead_story.dart';
import '../models.dart';
import '../theme.dart';
import '../util.dart';
import 'widgets.dart';

/// Sport-specific "situation" cards — the one card on the live detail screen
/// that changes shape per sport. Selection is data-driven (which optional
/// canonical fields are present), never by sport name:
///   situation.hasBaseball  → the batter-vs-pitcher duel (turn 8)
///   situation.hasGridiron  → down & distance + field position bar
///   competition.events     → match timeline (soccer/rugby cheap feed)
///   periodScores(cricket)  → the chase equation
/// Returns null when nothing applies (the detail page just omits the card).
/// [liveAtBat] (baseball, rich tier) upgrades the duel card with the pitcher's
/// game pitch count; everything else on the card is cheap-tier.
/// [recap]/[aiRecap] (baseball, between innings) feed the Due Up card's
/// last-half-inning footer — [aiRecap] (the optional AI sentence) supersedes
/// the deterministic [recap.line] when it has arrived.
/// [leadPlays] (basketball, rich tier) — the summary's scoring plays with
/// running scores — feeds the clock-&-run card's run/tidbit slot.
Widget? situationCardFor(Competition comp,
    {AtBat? liveAtBat,
    InningRecap? recap,
    String? aiRecap,
    List<SummaryPlay> leadPlays = const []}) {
  final sit = comp.situation;
  // Between innings (batter gone, dueUp present) the duel has no subjects —
  // the Due Up card takes the situation slot until the next at-bat starts.
  if (sit != null && sit.isDueUp) {
    return DueUpCard(comp, recap: recap, aiRecap: aiRecap);
  }
  if (sit != null && sit.hasBaseball) {
    return BaseballSituationCard(comp, liveAtBat: liveAtBat);
  }
  if (sit != null && sit.hasGridiron) return GridironSituationCard(comp);
  if (sit != null && sit.hasBonus) {
    return BasketballSituationCard(comp, plays: leadPlays);
  }
  if (sit != null && sit.hasPowerPlay) return PowerPlaySituationCard(comp);
  if (comp.status.live && _cricketChase(comp) != null) {
    return CricketChaseCard(comp);
  }
  if (comp.events.isNotEmpty) return MatchTimelineCard(comp);
  return null;
}

// ═══════════════════════════ baseball ═══════════════════════════

/// Turn 8 (LiveGame.dc.html #8a): the situation card is a DUEL — pitcher and
/// batter face off with their live day-lines, the count as dot groups
/// underneath, and a quiet footer (pitch count · on deck) when the data exists.
/// The diamond moved to [BaseballZoneCard]; everything here is cheap-tier
/// except the pitch count (the rich live at-bat).
class BaseballSituationCard extends StatelessWidget {
  final Competition comp;
  final AtBat? liveAtBat;
  const BaseballSituationCard(this.comp, {this.liveAtBat, super.key});

  @override
  Widget build(BuildContext context) {
    final s = comp.situation!;
    final pitchCount = liveAtBat?.pitchCount;
    final hasDuel = s.pitcher != null || s.batter != null;
    final hasFooter = pitchCount != null || s.onDeck != null;
    return V2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasDuel)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                    child: _dueler('PITCHING', s.pitcher, s.pitcherLine,
                        CrossAxisAlignment.start)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('VS',
                      style: T.statLineStrong.copyWith(color: T.textFaint)),
                ),
                Expanded(
                    child: _dueler('AT BAT', s.batter, s.batterLine,
                        CrossAxisAlignment.end)),
              ],
            ),
          // B/S/O dot groups (§8): balls green, strikes/outs live-red.
          if (s.balls != null || s.strikes != null || s.outs != null)
            Container(
              margin: EdgeInsets.only(top: hasDuel ? 14 : 0),
              padding: EdgeInsets.only(top: hasDuel ? 14 : 0),
              decoration: hasDuel
                  ? const BoxDecoration(
                      border: Border(top: BorderSide(color: T.divider)))
                  : null,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (s.balls != null)
                    _countGroup('BALLS', s.balls!, 3, T.green),
                  if (s.strikes != null)
                    _countGroup('STRIKES', s.strikes!, 2, T.live),
                  if (s.outs != null) _countGroup('OUTS', s.outs!, 3, T.live),
                ],
              ),
            ),
          if (hasFooter)
            Container(
              margin: const EdgeInsets.only(top: 14),
              padding: const EdgeInsets.only(top: 12),
              decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: T.divider))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (pitchCount != null)
                    Row(children: [
                      const Text('Pitch count ', style: T.caption),
                      Text('$pitchCount', style: T.statLine),
                    ]),
                  if (s.onDeck != null)
                    Flexible(
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Text('On deck · ', style: T.caption),
                        Flexible(
                          child: Text(s.onDeck!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: T.rowText.copyWith(fontSize: 13)),
                        ),
                      ]),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// One side of the duel: faint role label, name, day-line.
  Widget _dueler(
          String role, String? name, String? line, CrossAxisAlignment align) =>
      Column(crossAxisAlignment: align, children: [
        Text(role, style: T.cardLabelFaint),
        const SizedBox(height: 4),
        Text(name ?? '—',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: T.rowText),
        if (line != null) ...[
          const SizedBox(height: 4),
          Text(line,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.statLine.copyWith(color: T.textDim, fontSize: 13)),
        ],
      ]);

  /// One count group: label + [filled]-of-[total] 10px dots in [color].
  Widget _countGroup(String label, int filled, int total, Color color) =>
      Row(children: [
        Text(label, style: T.captionFaint),
        const SizedBox(width: 8),
        DotRow(
            filled: filled.clamp(0, total),
            total: total,
            color: color,
            size: 10),
      ]);
}

/// Between innings: the DUE UP card — the next half-inning's batters (cheap
/// `situation.dueUp`, names + day lines), and below a hairline the previous
/// half's story: the optional AI-written sentence when it has arrived, else
/// the deterministic line ('three up, three down' / 'two runs on three hits'). Every element
/// data-gated: no recap → batters only; ESPN ships 1-3 due-up entries.
class DueUpCard extends StatelessWidget {
  final Competition comp;
  final InningRecap? recap;
  final String? aiRecap;
  const DueUpCard(this.comp, {this.recap, this.aiRecap, super.key});

  @override
  Widget build(BuildContext context) {
    final due = comp.situation!.dueUp;
    final recapText = aiRecap ?? recap?.line;
    return V2Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const CardLabel('Due up'),
            // the between-innings beat ('Mid 5th' / 'End 5th'), straight off
            // the cheap status — absent, the label stands alone.
            if (comp.status.shortDetail != null)
              Text(comp.status.shortDetail!, style: T.captionFaint),
          ]),
          const SizedBox(height: 12),
          for (final (i, b) in due.take(3).indexed)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
              child: Row(children: [
                SizedBox(
                    width: 18,
                    child: Text('${i + 1}', style: T.captionFaint)),
                Expanded(
                  child: Text(b.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.rowText),
                ),
                if (b.line != null)
                  Text(b.line!,
                      style: T.statLine.copyWith(
                          color: T.textDim, fontSize: 13)),
              ]),
            ),
          if (recapText != null && recap != null)
            Container(
              margin: const EdgeInsets.only(top: 14),
              padding: const EdgeInsets.only(top: 12),
              width: double.infinity,
              decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: T.divider))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      [
                        recap!.label.toUpperCase(),
                        if (recap!.teamAbbr != null) recap!.teamAbbr!,
                      ].join(' · '),
                      style: T.captionFaint),
                  const SizedBox(height: 4),
                  Text(recapText,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: T.rowText.copyWith(fontSize: 13)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Turn 8: the strike zone + bases card. The zone plot renders ONLY when the
/// live at-bat's pitches carry ESPN's plot coords (live captures only — the
/// design's degrade rule: plain outline + numbered markers, no heat; hide the
/// zone entirely without locations). The diamond + runner names render for any
/// live baseball situation, so the card never loses the cheap-tier baserunners.
class BaseballZoneCard extends StatelessWidget {
  final Competition comp;
  final AtBat? liveAtBat;
  const BaseballZoneCard(this.comp, {this.liveAtBat, super.key});

  /// The plotted subset of the live at-bat's pitches (coords present).
  List<Pitch> get _plotted => [
        for (final p in liveAtBat?.pitches ?? const <Pitch>[])
          if (p.x != null && p.y != null) p
      ];

  @override
  Widget build(BuildContext context) {
    final s = comp.situation!;
    final plotted = _plotted;
    final zone = plotted.isNotEmpty;
    final runners = <(String, String?, bool)>[
      ('1B', liveAtBat?.first, s.onFirst ?? false),
      ('2B', liveAtBat?.second, s.onSecond ?? false),
      ('3B', liveAtBat?.third, s.onThird ?? false),
    ];
    return V2Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          CardLabel(zone ? 'Strike zone' : 'On base'),
          if (zone) const Text("catcher's view", style: T.captionFaint),
        ]),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          if (zone) ...[
            _ZonePlot(pitches: liveAtBat!.pitches, plotted: plotted),
            const SizedBox(width: 18),
          ],
          Expanded(
            child: Column(children: [
              BaseballDiamond(
                onFirst: s.onFirst ?? false,
                onSecond: s.onSecond ?? false,
                onThird: s.onThird ?? false,
                width: 84,
              ),
              const SizedBox(height: 12),
              for (final (base, name, occupied) in runners)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(base, style: T.captionFaint),
                      Flexible(
                        child: Text(
                          name ?? (occupied ? 'on base' : 'empty'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: occupied
                              ? T.rowText.copyWith(fontSize: 13)
                              : T.caption,
                        ),
                      ),
                    ],
                  ),
                ),
            ]),
          ),
        ]),
      ]),
    );
  }
}

/// Marker/badge color for a pitch result: ball green, strike live-red, foul
/// faint, in-play gold — the §2 muted-glyph vocabulary.
Color pitchColor(String r) => switch (r) {
      'ball' => T.green,
      'strike' => T.live,
      'inplay' => T.gold,
      _ => T.textFaint,
    };

/// The glyph a marker's number reads against (dark on the bright fills).
Color _pitchGlyph(String r) =>
    (r == 'ball' || r == 'inplay') ? T.bg : Colors.white;

/// The zone plot: a dark panel, the rulebook zone outline, and one numbered
/// marker per located pitch. ESPN's plot space (catcher's view: x grows RIGHT,
/// y grows DOWN) is NOT isotropic — the zone rect below was fitted empirically
/// from 108 called strikes across the live 2026-07-09 slate (strikes x 84-148 /
/// y 144-193 at the 1%-99% band; balls fan out to x 25-191, y 108-236) and
/// cross-checked pitch-by-pitch against ESPN's own gamecast plot. The data
/// zone maps onto the drawn outline per axis; anything beyond clamps inside
/// the panel so a ball in the dirt still reads as "below the zone".
class _ZonePlot extends StatelessWidget {
  final List<Pitch> pitches; // full sequence (numbering)
  final List<Pitch> plotted; // the located subset
  const _ZonePlot({required this.pitches, required this.plotted});

  static const _w = 150.0, _h = 170.0;

  // the strike zone in ESPN coordinate units (empirical, see class doc)
  static const _zx0 = 84.0, _zx1 = 148.0, _zy0 = 144.0, _zy1 = 193.0;
  // where the outline is drawn in the panel (fractional insets below)
  static const _pxL = _w * .16, _pxR = _w * (1 - .16);
  static const _pyT = _h * .14, _pyB = _h * (1 - .14);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _w,
      height: _h,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
                color: T.track, borderRadius: BorderRadius.circular(8)),
          ),
        ),
        // the zone outline — the empirical data zone maps exactly onto it
        Positioned(
          left: _w * .16,
          right: _w * .16,
          top: _h * .14,
          bottom: _h * .14,
          child: Container(
            decoration: BoxDecoration(
              border:
                  Border.all(color: T.text.withValues(alpha: .55), width: 1.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        for (final p in plotted) _marker(p),
      ]),
    );
  }

  Widget _marker(Pitch p) {
    final n = pitches.indexOf(p) + 1;
    // data zone rect → drawn outline rect, per axis; clamp keeps wild pitches
    // visible just inside the panel edge (marker radius 11).
    final fx = (_pxL + (p.x! - _zx0) / (_zx1 - _zx0) * (_pxR - _pxL))
        .clamp(11.0, _w - 11.0);
    final fy = (_pyT + (p.y! - _zy0) / (_zy1 - _zy0) * (_pyB - _pyT))
        .clamp(11.0, _h - 11.0);
    return Positioned(
      left: fx - 11,
      top: fy - 11,
      child: Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: pitchColor(p.r),
          shape: BoxShape.circle,
          border: Border.all(color: T.surface, width: 2),
        ),
        child: Text('$n',
            style: TextStyle(
                fontFamily: 'BarlowCondensed',
                fontWeight: FontWeight.w700,
                fontSize: 11,
                height: 1,
                color: _pitchGlyph(p.r))),
      ),
    );
  }
}

/// Turn 8: the horizontally scrollable pitch strip — the live at-bat's pitch
/// sequence, latest first, each chip numbered to match the zone markers.
class PitchStripCard extends StatelessWidget {
  final AtBat atBat;
  const PitchStripCard(this.atBat, {super.key});

  @override
  Widget build(BuildContext context) {
    final n = atBat.pitches.length;
    // A challenged call (rare: ABS gives each side two) earns one extra caption
    // line on its chip; the strip grows only when the at-bat carries one.
    final hasChallenge = atBat.pitches.any((p) => p.challenge != null);
    return SizedBox(
      height: hasChallenge ? 126 : 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: n,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final p = atBat.pitches[n - 1 - i]; // latest first
          return Container(
            width: 96,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: T.surface, borderRadius: BorderRadius.circular(16)),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: pitchColor(p.r), shape: BoxShape.circle),
                    child: Text('${n - i}',
                        style: TextStyle(
                            fontFamily: 'BarlowCondensed',
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                            height: 1,
                            color: _pitchGlyph(p.r))),
                  ),
                  const SizedBox(height: 8),
                  Text(p.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.rowText.copyWith(fontSize: 12)),
                  const SizedBox(height: 4),
                  // one line each, ellipsized — a long pitch name
                  // ('Four-seam FB') must never push the mph off the chip.
                  if (p.type != null)
                    Text(p.type!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: T.captionFaint),
                  if (p.velo != null)
                    Text('${p.velo} mph',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: T.captionFaint),
                  // ABS challenge marker: the flipped call gets the caution
                  // pale (§2 muted-pair glyph text); an upheld one stays faint.
                  if (p.challenge != null)
                    Text(p.challenge!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: p.challenge == 'overturned'
                            ? T.captionFaint.copyWith(color: T.mutedNeutralGlyph)
                            : T.captionFaint),
                ]),
          );
        },
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

// ═══════════════════════════ basketball clock & run ══════════════════════════

/// The §8 basketball "clock & run" situation card: big countdown clock +
/// quarter label left; the derived story slot right — a `gold` run callout
/// (`OKC 9–2 RUN` / "last 2:40") when someone's on a run, else a quiet
/// back-and-forth tidbit (`14 LEAD CHANGES` / `TIED 6 TIMES`), else the clock
/// stands alone (lead_story.dart, off the summary's running scores). Footer:
/// the core bonus flag + remaining-timeout dots per side. The design's
/// possession/shot-clock slot is unsourced (ESPN's basketball core situation
/// carries neither — VERIFIED core-situation.md) and omitted. Data-driven:
/// rendered only when `situation.hasBonus`; the loud last play is the detail
/// page's InvertedCard, not duplicated here.
class BasketballSituationCard extends StatelessWidget {
  final Competition comp;
  final List<SummaryPlay> plays; // scoring plays w/ running scores; may be []
  const BasketballSituationCard(this.comp,
      {this.plays = const [], super.key});

  @override
  Widget build(BuildContext context) {
    final sit = comp.situation!;
    final slot = leadSlotFor(comp, plays);
    final clock = comp.status.clock;
    final hasClock = clock != null && clock.isNotEmpty;
    final hasTimeouts = sit.homeTimeouts != null || sit.awayTimeouts != null;
    final bonus = _bonusText(sit);
    return V2Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: hasClock
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(clock,
                        style: T.situationHead.copyWith(fontSize: 34)),
                    if (comp.status.periodLabel.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(comp.status.periodLabel.toUpperCase(),
                          style: T.cardLabelFaint),
                    ],
                  ])
                : const CardLabel('Bonus & timeouts'),
          ),
          if (slot != null)
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(slot.text,
                  style: T.statCallout.copyWith(
                      fontSize: 20, color: slot.loud ? T.gold : T.text)),
              if (slot.caption != null) ...[
                const SizedBox(height: 4),
                Text(slot.caption!, style: T.captionFaint),
              ],
            ]),
        ]),
        if (bonus != null || hasTimeouts) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: T.divider))),
            child: Row(children: [
              if (bonus != null)
                Expanded(
                  child:
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('BONUS', style: T.captionFaint),
                    const SizedBox(height: 5),
                    Text(bonus.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: T.rowText.copyWith(
                            fontSize: 13,
                            color: bonus.inBonus ? T.gold : T.textFaint)),
                  ]),
                )
              else
                const Spacer(),
              if (hasTimeouts)
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  const Text('TIMEOUTS', style: T.captionFaint),
                  const SizedBox(height: 7),
                  Row(children: [
                    _timeouts(comp.away, sit.awayTimeouts),
                    const SizedBox(width: 14),
                    _timeouts(comp.home, sit.homeTimeouts),
                  ]),
                ]),
            ]),
          ),
        ],
      ]),
    );
  }

  /// The footer's bonus read: who's in the bonus (double called out), a faint
  /// 'None' while the core keys are present but nobody's there yet.
  ({String text, bool inBonus})? _bonusText(Situation sit) {
    if (!sit.hasBonus) return null;
    String one(Competitor? c, String? state) {
      final abbr = c?.label ?? '';
      final isDouble = state?.toUpperCase() == 'DOUBLE';
      if (abbr.isEmpty) return isDouble ? 'Double bonus' : 'In bonus';
      return isDouble ? '$abbr double bonus' : '$abbr in bonus';
    }
    final h = sit.homeInBonus, a = sit.awayInBonus;
    if (h && a) return (text: 'Both in bonus', inBonus: true);
    if (h) return (text: one(comp.home, sit.homeBonus), inBonus: true);
    if (a) return (text: one(comp.away, sit.awayBonus), inBonus: true);
    return (text: 'None', inBonus: false);
  }

  Widget _timeouts(Competitor? c, int? n) {
    // Only the REMAINING count is observed (core has no used total), so render
    // that many team-color dots — never fabricate the used seats.
    if (n == null) return const SizedBox.shrink();
    return Row(children: [
      if (c != null)
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Text(c.label,
              style: T.statLine.copyWith(fontSize: 13, color: T.textDim)),
        ),
      DotRow(
          filled: n.clamp(0, 7), total: n.clamp(0, 7), color: teamColor(c), size: 7),
    ]);
  }
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
