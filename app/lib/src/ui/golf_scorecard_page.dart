import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import 'widgets.dart';

void openGolfScorecard(
  BuildContext context,
  String league,
  String eventId,
  Competitor competitor, {
  int? season,
}) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => GolfScorecardPage(
      league: league,
      eventId: eventId,
      competitor: competitor,
      season: season,
    ),
  ));
}

/// One golfer's hole-by-hole scorecard: per-round front/back nine grids with
/// birdie/eagle/bogey coloring, front-back-total splits, and — for a round not
/// yet started — the tee time. Lazy fetch on open (60s worker TTL); no polling:
/// a glance page, pull back and reopen for fresh holes.
class GolfScorecardPage extends ConsumerStatefulWidget {
  final String league, eventId;
  final Competitor competitor;
  final int? season;
  const GolfScorecardPage({
    super.key,
    required this.league,
    required this.eventId,
    required this.competitor,
    this.season,
  });

  @override
  ConsumerState<GolfScorecardPage> createState() => _GolfScorecardPageState();
}

class _GolfScorecardPageState extends ConsumerState<GolfScorecardPage> {
  int? _round; // selected round; null → latest played

  ScorecardKey get _key => (
        league: widget.league,
        eventId: widget.eventId,
        playerId: widget.competitor.id,
        season: widget.season,
      );

  @override
  Widget build(BuildContext context) {
    final card = ref.watch(scorecardProvider(_key));
    final c = widget.competitor;
    final title = c.displayName;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, T.pageMargin, 0),
              child: Row(children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded,
                      size: 18, color: T.textDim),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: Text(title.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.pageTitle.copyWith(fontSize: 22)),
                ),
                // position + total from the leaderboard row we came from —
                // instant context while the scorecard loads.
                Text(c.score?.display ?? '',
                    style: T.statLineStrong.copyWith(
                        fontSize: 20,
                        color: (c.score?.toPar ?? 0) < 0 ? T.underPar : T.text)),
              ]),
            ),
            const SizedBox(height: 14),
            ...switch (card) {
              AsyncData(:final value) => _body(value),
              AsyncError() => const [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: T.pageMargin),
                    child: HintCard('Couldn’t load the scorecard.'),
                  ),
                ],
              _ => const [
                  Padding(
                    padding: EdgeInsets.only(top: 100),
                    child: Center(
                        child: CircularProgressIndicator(color: T.gold)),
                  ),
                ],
            },
          ],
        ),
      ),
    );
  }

  List<Widget> _body(GolfScorecard card) {
    final rounds = card.rounds;
    if (rounds.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: T.pageMargin),
          child: HintCard('No rounds yet.'),
        ),
      ];
    }
    // default to the latest round with holes, else the first
    final latestPlayed = rounds.lastWhere((r) => r.played,
        orElse: () => rounds.first);
    final sel = rounds.firstWhere((r) => r.round == _round,
        orElse: () => latestPlayed);

    return [
      // round selector chips (R1 R2 R3 R4)
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: T.pageMargin),
        child: Row(children: [
          for (final r in rounds)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _RoundChip(
                label: 'R${r.round}',
                sub: r.played ? (r.toPar ?? '') : '–',
                selected: r.round == sel.round,
                onTap: () => setState(() => _round = r.round),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: T.pageMargin),
        child: sel.played ? _RoundCard(sel) : _TeeTimeCard(sel),
      ),
      if (card.stats.isNotEmpty) ...[
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: T.pageMargin),
          child: _StatsCard(card.stats),
        ),
      ],
    ];
  }
}

class _RoundChip extends StatelessWidget {
  final String label, sub;
  final bool selected;
  final VoidCallback onTap;
  const _RoundChip(
      {required this.label,
      required this.sub,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            // §6: active = inverted fill; inactive = 1.5px border outline (no fill).
            color: selected ? T.invertedBg : Colors.transparent,
            border:
                selected ? null : Border.all(color: T.border, width: 1.5),
            borderRadius: BorderRadius.circular(100),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? T.invertedText : T.textDim)),
            if (sub.isNotEmpty) ...[
              const SizedBox(width: 5),
              Text(sub,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: selected ? T.invertedLabel : T.textFaint)),
            ],
          ]),
        ),
      );
}

/// The 18-hole grid: two 9-hole banks (OUT / IN), each a hole row, par row and
/// a strokes row colored by score type.
class _RoundCard extends StatelessWidget {
  final ScorecardRound round;
  const _RoundCard(this.round);

  /// The hole currently being played: the first hole with no strokes yet, but
  /// only when the round is genuinely in progress (at least one hole played and
  /// at least one still open). §7.3 — dashed gold = in progress, not empty.
  static int? _currentHole(List<ScorecardHole> holes) {
    final anyPlayed = holes.any((h) => h.strokes != null);
    if (!anyPlayed) return null; // not yet started
    final sorted = [...holes]..sort((a, b) => a.hole.compareTo(b.hole));
    for (final h in sorted) {
      if (h.strokes == null) return h.hole; // first open hole == current
    }
    return null; // every hole played → round complete
  }

  @override
  Widget build(BuildContext context) {
    final front = round.holes.where((h) => h.hole <= 9).toList();
    final back = round.holes.where((h) => h.hole > 9).toList();
    final currentHole = _currentHole(round.holes);
    return V2Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CardLabel('Round ${round.round}'),
          const Spacer(),
          if (round.strokes != null)
            Text(
              '${round.strokes}${round.toPar != null ? '  ·  ${round.toPar}' : ''}',
              style: T.statLineStrong.copyWith(
                  color: (round.toPar ?? '').startsWith('-')
                      ? T.underPar
                      : T.text),
            ),
        ]),
        const SizedBox(height: 6),
        // §8: glyph legend inline in the label — once per card, right-aligned.
        const Align(
          alignment: Alignment.centerRight,
          child: Text('○ birdie · □ bogey · ◎ eagle', style: T.captionFaint),
        ),
        const SizedBox(height: 12),
        if (front.isNotEmpty)
          _NineGrid(
              label: 'OUT',
              holes: front,
              total: round.outScore,
              currentHole: currentHole),
        if (back.isNotEmpty) ...[
          const SizedBox(height: 14),
          _NineGrid(
              label: 'IN',
              holes: back,
              total: round.inScore,
              currentHole: currentHole),
        ],
      ]),
    );
  }
}

/// One score type drives one glyph (§8 golf vocabulary). The ring carries the
/// meaning; the numeral keeps its natural color.
enum _Glyph { eagle, birdie, par, bogey, worse }

class _NineGrid extends StatelessWidget {
  final String label;
  final List<ScorecardHole> holes;
  final int? total;
  final int? currentHole;
  const _NineGrid(
      {required this.label,
      required this.holes,
      this.total,
      this.currentHole});

  /// Classify a played hole: prefer ESPN's `scoreType`, fall back to delta
  /// (strokes − par). Never keys on sport name.
  static _Glyph _classify(ScorecardHole h) {
    switch (h.scoreType?.toUpperCase()) {
      case 'ALBATROSS':
      case 'DOUBLE_EAGLE':
      case 'EAGLE':
        return _Glyph.eagle;
      case 'BIRDIE':
        return _Glyph.birdie;
      case 'PAR':
        return _Glyph.par;
      case 'BOGEY':
        return _Glyph.bogey;
      case 'DOUBLE_BOGEY':
      case 'TRIPLE_BOGEY':
        return _Glyph.worse;
    }
    final d = h.delta;
    if (d == null) return _Glyph.par;
    if (d <= -2) return _Glyph.eagle;
    if (d == -1) return _Glyph.birdie;
    if (d == 0) return _Glyph.par;
    if (d == 1) return _Glyph.bogey;
    return _Glyph.worse;
  }

  // A single ring (circle for birdie, rounded square for bogey) around the
  // numeral. BoxShape.circle forbids borderRadius, so it's set only for the
  // rectangle case.
  static Widget _ring(Widget child,
          {required BoxShape shape, required Color color}) =>
      Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: shape,
          borderRadius: shape == BoxShape.rectangle
              ? BorderRadius.circular(3)
              : null,
          border: Border.all(color: color, width: 1.5),
        ),
        child: child,
      );

  // Eagle+ → double circle ◎: two concentric gold rings.
  static Widget _doubleCircle(Widget child) => Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: T.gold, width: 1.5),
        ),
        child: Container(
          width: 17,
          height: 17,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: T.gold, width: 1.5),
          ),
          child: child,
        ),
      );

  /// The strokes-row cell for one hole: shape-by-score-type glyph, numeral kept
  /// at its natural color (except the gold current hole).
  Widget _strokeCell(ScorecardHole h) {
    // Current hole (in progress) → dashed gold ring, hole number in gold.
    if (currentHole != null && h.hole == currentHole) {
      return Expanded(
        child: SizedBox(
          height: 30,
          child: Center(
            child: DashedRing(
              size: 24,
              color: T.gold,
              child: Text('${h.hole}',
                  style: T.statLineStrong
                      .copyWith(fontSize: 12, color: T.gold)),
            ),
          ),
        ),
      );
    }
    final strokes = h.strokes;
    // Unplayed (and not current) → quiet placeholder dot.
    if (strokes == null) {
      return Expanded(
        child: SizedBox(
          height: 30,
          child: Center(
            child: Text('·',
                style: T.statLineStrong
                    .copyWith(fontSize: 14, color: T.textFaint)),
          ),
        ),
      );
    }
    final glyph = _classify(h);
    // Rings carry meaning → numeral stays natural (dim only for double-bogey+).
    final numeral = Text('$strokes',
        style: T.statLineStrong.copyWith(
            fontSize: 14,
            color: glyph == _Glyph.worse ? T.textDim : T.text));
    final Widget content = switch (glyph) {
      _Glyph.eagle => _doubleCircle(numeral),
      _Glyph.birdie =>
        _ring(numeral, shape: BoxShape.circle, color: T.underPar),
      _Glyph.bogey =>
        _ring(numeral, shape: BoxShape.rectangle, color: T.textFaint),
      _Glyph.par || _Glyph.worse => numeral,
    };
    return Expanded(
      child: SizedBox(height: 30, child: Center(child: content)),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget cell(String s, {TextStyle? style}) => Expanded(
          child: Container(
            height: 26,
            alignment: Alignment.center,
            child: Text(s, style: style ?? T.statLine),
          ),
        );
    return Column(children: [
      Row(children: [
        SizedBox(
            width: 36, child: Text(label, style: T.cardLabelFaint)),
        for (final h in holes)
          cell('${h.hole}',
              style: T.captionFaint.copyWith(fontSize: 10.5)),
        SizedBox(
            width: 34,
            child: Text('TOT',
                textAlign: TextAlign.right,
                style: T.captionFaint.copyWith(fontSize: 10.5))),
      ]),
      const SizedBox(height: 2),
      Row(children: [
        const SizedBox(width: 36, child: Text('PAR', style: T.captionFaint)),
        for (final h in holes)
          cell(h.par?.toString() ?? '',
              style: T.statLine.copyWith(color: T.textFaint)),
        SizedBox(
            width: 34,
            child: Text(
                holes.every((h) => h.par != null)
                    ? '${holes.fold<int>(0, (s, h) => s + h.par!)}'
                    : '',
                textAlign: TextAlign.right,
                style: T.statLine.copyWith(color: T.textFaint))),
      ]),
      const SizedBox(height: 3),
      Row(children: [
        const SizedBox(width: 36),
        for (final h in holes) _strokeCell(h),
        SizedBox(
            width: 34,
            child: Text(total?.toString() ?? '',
                textAlign: TextAlign.right, style: T.statLineStrong)),
      ]),
    ]);
  }
}

/// A round that hasn't started: the pre-round glance is the tee time.
class _TeeTimeCard extends StatelessWidget {
  final ScorecardRound round;
  const _TeeTimeCard(this.round);

  @override
  Widget build(BuildContext context) {
    final t = round.teeTimeLocal;
    final when = t == null
        ? 'TBD'
        : MaterialLocalizations.of(context)
            .formatTimeOfDay(TimeOfDay.fromDateTime(t));
    final bits = [
      if (round.startTee != null && round.startTee != 1)
        'starts hole ${round.startTee}',
      if (round.groupNumber != null) 'group ${round.groupNumber}',
    ].join(' · ');
    return V2Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CardLabel('Round ${round.round} — tee time'),
        const SizedBox(height: 10),
        Text(when,
            style: const TextStyle(
                fontFamily: 'BarlowCondensed',
                fontWeight: FontWeight.w700,
                fontSize: 34,
                color: T.text)),
        if (bits.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(bits, style: T.caption),
        ],
      ]),
    );
  }
}

class _StatsCard extends StatelessWidget {
  final List<ScorecardStat> stats;
  const _StatsCard(this.stats);

  @override
  Widget build(BuildContext context) => V2Card(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const CardLabel('Tournament'),
          const SizedBox(height: 4),
          for (final s in stats)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(children: [
                Expanded(
                    child:
                        Text(s.label, style: T.rowTextDim.copyWith(fontSize: 13))),
                Text(s.value, style: T.statLineStrong),
              ]),
            ),
        ]),
      );
}
