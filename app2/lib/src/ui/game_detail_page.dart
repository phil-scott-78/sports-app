import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import '../util.dart';
import 'poll.dart';
import 'situations.dart';
import 'widgets.dart';

void openGameDetail(BuildContext context, String league, SportEvent event) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => GameDetailPage(league: league, initialEvent: event),
  ));
}

/// Live game detail: giant score block (or event block) that collapses into a
/// sticky scorebug, pinned chip nav, then the card stack — situation card
/// (the sport's flourish), win probability, last play, supporting stats.
class GameDetailPage extends ConsumerStatefulWidget {
  final String league;
  final SportEvent initialEvent;
  const GameDetailPage(
      {super.key, required this.league, required this.initialEvent});

  @override
  ConsumerState<GameDetailPage> createState() => _GameDetailPageState();
}

class _GameDetailPageState extends ConsumerState<GameDetailPage>
    with LifecyclePoll {
  int _chip = 0;

  SummaryKey get _summaryKey =>
      (league: widget.league, eventId: widget.initialEvent.id);

  @override
  void initState() {
    super.initState();
    attachPoll();
    WidgetsBinding.instance.addPostFrameCallback((_) => repace());
  }

  @override
  void dispose() {
    detachPoll();
    super.dispose();
  }

  SportEvent get _event {
    final scores = ref.read(leagueScoresProvider(widget.league)).valueOrNull;
    if (scores != null) {
      for (final e in scores.events) {
        if (e.id == widget.initialEvent.id) return e;
      }
    }
    return widget.initialEvent;
  }

  @override
  Duration? pollInterval() {
    final comp = _event.main;
    if (comp == null) return null;
    if (comp.status.live) return const Duration(seconds: 20);
    if (comp.status.isScheduled && kickoffSoon(_event.start)) {
      return AppConfig.refreshNearKickoff;
    }
    if (comp.status.ended) return null; // finals don't change
    return AppConfig.refreshIdle;
  }

  @override
  void onPoll() {
    ref.invalidate(leagueScoresProvider(widget.league));
    ref.invalidate(summaryProvider(_summaryKey));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(leagueScoresProvider(widget.league), (_, __) => repace());
    ref.watch(leagueScoresProvider(widget.league));
    final summary = ref.watch(summaryProvider(_summaryKey)).valueOrNull;

    final event = _event;
    final comp = event.main;
    if (comp == null) {
      return const Scaffold(body: Center(child: Text('No competition data')));
    }

    final chips = _chipLabels(comp, summary);
    final chipIndex = _chip.clamp(0, chips.length - 1);
    final sections =
        _sections(context, event, comp, summary, chips, chipIndex);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _HeaderDelegate(
              topPadding: MediaQuery.paddingOf(context).top,
              event: event,
              comp: comp,
              chips: chips,
              chipIndex: chipIndex,
              onChip: (i) => setState(() => _chip = i),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
                T.pageMargin, 2, T.pageMargin, 28),
            sliver: SliverList.separated(
              itemCount: sections.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => sections[i],
            ),
          ),
        ],
      ),
    );
  }

  List<String> _chipLabels(Competition comp, GameSummary? summary) {
    if (comp.isField) return const ['Leaderboard'];
    final s = comp.status;
    final first = s.live ? 'Now' : (s.isScheduled ? 'Preview' : 'Recap');
    final hasBox = comp.competitors.any((c) => c.periodScores.isNotEmpty) ||
        (summary != null &&
            (summary.boxGroups.isNotEmpty ||
                summary.teamStats.isNotEmpty ||
                summary.periodLines != null));
    final hasPlays = summary != null &&
        (summary.scoringPlays.isNotEmpty || summary.plays.isNotEmpty);
    final hasLeaders = comp.competitors.any((c) => c.leaders.isNotEmpty);
    return [
      first,
      if (hasBox) 'Box',
      if (hasPlays) 'Plays',
      if (hasLeaders) 'Leaders',
    ];
  }

  List<Widget> _sections(
    BuildContext context,
    SportEvent event,
    Competition comp,
    GameSummary? summary,
    List<String> chips,
    int chipIndex,
  ) {
    if (comp.isField) {
      return [
        FieldLeaderboard(comp, maxRows: 25),
        if (comp.situation?.lastPlay != null)
          InvertedCard(label: 'Latest', text: comp.situation!.lastPlay!),
        if (event.notes.isNotEmpty) _NotesCard(event.notes),
      ];
    }
    final label = chips[chipIndex];
    switch (label) {
      case 'Box':
        return [
          if (_hasCheapLines(comp) || summary?.periodLines != null)
            _LineScoreCard(comp: comp, lines: summary?.periodLines),
          if (summary != null && summary.teamStats.isNotEmpty)
            _TeamStatsCard(comp: comp, rows: summary.teamStats),
          if (summary != null)
            for (final g in summary.boxGroups) _BoxGroupCard(g),
          if (summary == null) const _LoadingCard(),
        ];
      case 'Plays':
        final plays = summary!.scoringPlays.isNotEmpty
            ? summary.scoringPlays
            : summary.plays;
        return [_PlaysCard(plays.reversed.toList())];
      case 'Leaders':
        return [
          for (final c in comp.competitors)
            if (c.leaders.isNotEmpty) _SideLeadersCard(c),
        ];
      default: // Now / Preview / Recap
        final s = comp.status;
        if (s.live) {
          final situation = situationCardFor(comp);
          return [
            if (situation != null) situation,
            if (summary?.winProbability != null)
              _WinProbCard(comp: comp, wp: summary!.winProbability!),
            if (comp.situation?.lastPlay != null)
              InvertedCard(label: 'Last play', text: comp.situation!.lastPlay!),
            _TopPerformersCard(comp),
            if (summary != null && summary.seasonSeries != null)
              _SeasonSeriesCard(summary.seasonSeries!),
          ].whereType<Widget>().toList();
        }
        if (s.isScheduled) {
          return [
            if (comp.competitors.any((c) => c.probables.isNotEmpty))
              _ProbablesCard(comp),
            if (summary != null && summary.recentForm.isNotEmpty)
              _FormCard(summary.recentForm),
            if (summary != null && summary.injuries.isNotEmpty)
              _InjuriesCard(summary.injuries),
            _VenueCard(event),
          ];
        }
        // Recap
        return [
          if (_hasCheapLines(comp) || summary?.periodLines != null)
            _LineScoreCard(comp: comp, lines: summary?.periodLines),
          _TopPerformersCard(comp),
          if (summary != null && summary.scoringPlays.isNotEmpty)
            _PlaysCard(summary.scoringPlays.reversed.take(6).toList(),
                label: 'Scoring'),
          if (summary != null && summary.seasonSeries != null)
            _SeasonSeriesCard(summary.seasonSeries!),
        ].whereType<Widget>().toList();
    }
  }

  bool _hasCheapLines(Competition comp) =>
      comp.competitors.any((c) => c.periodScores.isNotEmpty) &&
      comp.periods.unit != 'set';
}

// ═══════════════════════════ collapsing header ═══════════════════════════

class _HeaderDelegate extends SliverPersistentHeaderDelegate {
  final double topPadding;
  final SportEvent event;
  final Competition comp;
  final List<String> chips;
  final int chipIndex;
  final ValueChanged<int> onChip;

  _HeaderDelegate({
    required this.topPadding,
    required this.event,
    required this.comp,
    required this.chips,
    required this.chipIndex,
    required this.onChip,
  });

  static const _chipH = 50.0;
  static const _bugH = 46.0;

  double get _blockH {
    if (comp.isField) return 148;
    if (isSetGrid(comp)) return 186;
    return 200;
  }

  @override
  double get minExtent => topPadding + _bugH + _chipH;

  @override
  double get maxExtent {
    final expanded = topPadding + _blockH + _chipH;
    return expanded > minExtent ? expanded : minExtent;
  }

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final range = (maxExtent - minExtent).clamp(1.0, double.infinity);
    final t = (shrinkOffset / range).clamp(0.0, 1.0);
    return Container(
      color: T.bg,
      child: Stack(
        children: [
          // expanded block, fading out
          Positioned(
            top: topPadding - shrinkOffset,
            left: 0,
            right: 0,
            height: _blockH,
            child: IgnorePointer(
              ignoring: t > 0.5,
              child: Opacity(
                opacity: (1 - t * 1.6).clamp(0.0, 1.0),
                child: ClipRect(child: _ExpandedBlock(event: event, comp: comp)),
              ),
            ),
          ),
          // condensed scorebug, fading in
          Positioned(
            top: topPadding,
            left: 0,
            right: 0,
            height: _bugH,
            child: IgnorePointer(
              ignoring: t < 0.7,
              child: Opacity(
                opacity: ((t - 0.55) / 0.45).clamp(0.0, 1.0),
                child: _CollapsedBug(event: event, comp: comp),
              ),
            ),
          ),
          // pinned chip nav (+ its hairline when collapsed)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: _chipH,
            child: Container(
              alignment: Alignment.topLeft,
              padding: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: T.bg,
                border: t > 0.95
                    ? const Border(bottom: BorderSide(color: T.divider))
                    : null,
              ),
              child: chips.length > 1
                  ? ChipNav(items: chips, selected: chipIndex, onTap: onChip)
                  : const SizedBox.shrink(),
            ),
          ),
          // back chevron, always present
          Positioned(
            top: topPadding - 4,
            left: 6,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  size: 18, color: T.textDim),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_HeaderDelegate old) =>
      old.comp != comp ||
      old.chipIndex != chipIndex ||
      old.chips.length != chips.length ||
      old.topPadding != topPadding;
}

class _ExpandedBlock extends StatelessWidget {
  final SportEvent event;
  final Competition comp;
  const _ExpandedBlock({required this.event, required this.comp});

  @override
  Widget build(BuildContext context) {
    final lead = leadingSide(comp);
    final away = comp.away ??
        (comp.competitors.isNotEmpty ? comp.competitors.first : null);
    final home = comp.home ??
        (comp.competitors.length > 1 ? comp.competitors[1] : null);

    Widget block;
    if (comp.isField) {
      block = Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: T.border, width: 2))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(event.name.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: T.blockName.copyWith(fontSize: 34, height: 1.05)),
          const SizedBox(height: 6),
          Text(
            [
              if (comp.meta?.round != null) comp.meta!.round!,
              if (event.venue != null) event.venue!.name,
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: T.textDim),
          ),
        ]),
      );
    } else if (isSetGrid(comp)) {
      block = SetGridBlock(comp);
    } else {
      final showScore = !comp.status.isScheduled;
      block = Column(children: [
        if (away != null)
          ScoreBlockRow(away,
              dim: lead != null && lead != away,
              possession: _hasPossession(away),
              showScore: showScore,
              badge: _badge(away)),
        if (home != null)
          ScoreBlockRow(home,
              dim: lead != null && lead != home,
              possession: _hasPossession(home),
              showScore: showScore,
              badge: _badge(home)),
      ]);
    }

    final contextLine = [
      if (comp.meta?.seriesSummary != null)
        comp.meta!.seriesSummary!
      else if (comp.meta?.round != null)
        comp.meta!.round!
      else if (event.venue != null)
        event.venue!.name,
    ].join();

    return Padding(
      padding: const EdgeInsets.fromLTRB(T.pageMargin, 6, T.pageMargin, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          // room for the back chevron on the left
          padding: const EdgeInsets.only(left: 34),
          child: Row(children: [
            StatusPill(_pillText(), live: comp.status.live),
            const Spacer(),
            Flexible(
              child: Text(contextLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.caption),
            ),
          ]),
        ),
        const SizedBox(height: 4),
        block,
      ]),
    );
  }

  String _pillText() {
    final s = comp.status;
    if (s.live) return s.shortDetail ?? s.detail;
    if (s.isScheduled) return startLabel(event.start);
    return s.shortDetail ?? s.detail;
  }

  bool _hasPossession(Competitor c) =>
      comp.status.live && comp.situation?.possession == c.id;

  Widget? _badge(Competitor c) {
    final side = c == comp.home ? 'home' : 'away';
    final reds = comp.redCardsBySide[side] ?? 0;
    if (reds > 0) {
      return TagBadge(reds > 1 ? '${11 - reds} MEN' : '10 MEN',
          bg: T.live, fg: Colors.white);
    }
    return null;
  }
}

class _CollapsedBug extends StatelessWidget {
  final SportEvent event;
  final Competition comp;
  const _CollapsedBug({required this.event, required this.comp});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(48, 0, T.pageMargin, 0),
        alignment: Alignment.center,
        child: comp.isField
            ? Row(children: [
                Expanded(
                  child: Text(event.shortName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.bugScore),
                ),
                Text(comp.status.shortDetail ?? comp.status.detail,
                    style: T.caption),
                if (comp.status.live) ...[
                  const SizedBox(width: 8),
                  const LiveDot(size: 7),
                ],
              ])
            : Scorebug(comp),
      );
}

// ═══════════════════════════ detail cards ═══════════════════════════

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();
  @override
  Widget build(BuildContext context) => const V2Card(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(10),
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: T.gold),
            ),
          ),
        ),
      );
}

class _WinProbCard extends StatelessWidget {
  final Competition comp;
  final WinProbability wp;
  const _WinProbCard({required this.comp, required this.wp});

  @override
  Widget build(BuildContext context) {
    final away = comp.away, home = comp.home;
    if (away == null || home == null) return const SizedBox.shrink();
    final leader = wp.home >= wp.away ? home : away;
    final pct = wp.home >= wp.away ? wp.home : wp.away;
    return V2Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            const Expanded(child: CardLabel('Win probability')),
            Text('${leader.label} $pct%', style: T.statCallout),
          ],
        ),
        const SizedBox(height: 10),
        SplitBar(
          leftFraction: wp.away / 100,
          left: teamColor(away),
          right: teamColor(home),
        ),
      ]),
    );
  }
}

class _TopPerformersCard extends StatelessWidget {
  final Competition comp;
  const _TopPerformersCard(this.comp);

  @override
  Widget build(BuildContext context) {
    final rows = <({String name, String sub, String stat})>[];
    for (final c in comp.competitors) {
      if (c.leaders.isEmpty) continue;
      final l = c.leaders.first;
      if (l.athlete == null) continue;
      rows.add((
        name: l.athlete!,
        sub: '${c.label} · ${l.label}',
        stat: l.display ?? '',
      ));
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return V2Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const CardLabel('Top performers'),
        const SizedBox(height: 4),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(children: [
              Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                      color: T.border, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Text(_initials(r.name),
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: T.textDim))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.name, style: T.rowText),
                      Text(r.sub, style: T.caption),
                    ]),
              ),
              Text(r.stat, style: T.statLineStrong),
            ]),
          ),
      ]),
    );
  }

  String _initials(String name) {
    final parts = name.split(RegExp(r'[\s.]+')).where((p) => p.isNotEmpty);
    return parts.map((p) => p[0]).take(2).join().toUpperCase();
  }
}

class _SideLeadersCard extends StatelessWidget {
  final Competitor c;
  const _SideLeadersCard(this.c);

  @override
  Widget build(BuildContext context) => V2Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CardLabel(c.shortName ?? c.displayName),
          const SizedBox(height: 4),
          for (final l in c.leaders)
            StatListRow(
              name: l.athlete ?? '',
              detail: l.label,
              stat: l.display ?? '',
            ),
        ]),
      );
}

class _LineScoreCard extends StatelessWidget {
  final Competition comp;
  final PeriodLines? lines;
  const _LineScoreCard({required this.comp, this.lines});

  @override
  Widget build(BuildContext context) {
    // Prefer the cheap scoreboard linescore (survives a /summary failure);
    // fall back to the rich periodLines.
    final away = comp.away ??
        (comp.competitors.isNotEmpty ? comp.competitors.first : null);
    final home = comp.home ??
        (comp.competitors.length > 1 ? comp.competitors[1] : null);
    List<String> labels;
    List<String> awayVals, homeVals;
    String awayTotal, homeTotal;
    if (away != null && away.periodScores.isNotEmpty ||
        home != null && home.periodScores.isNotEmpty) {
      final n = [
        ...?away?.periodScores.map((p) => p.period),
        ...?home?.periodScores.map((p) => p.period),
      ].fold(0, (a, b) => a > b ? a : b);
      labels = [for (var i = 1; i <= n; i++) '$i'];
      String val(Competitor? c, int period) {
        for (final p in c?.periodScores ?? const <PeriodScore>[]) {
          if (p.period == period) return p.display;
        }
        return '–';
      }

      awayVals = [for (var i = 1; i <= n; i++) val(away, i)];
      homeVals = [for (var i = 1; i <= n; i++) val(home, i)];
      awayTotal = away?.score?.display ?? '';
      homeTotal = home?.score?.display ?? '';
    } else if (lines != null) {
      labels = lines!.labels;
      awayVals = lines!.away.values;
      homeVals = lines!.home.values;
      awayTotal = lines!.away.total ?? '';
      homeTotal = lines!.home.total ?? '';
    } else {
      return const SizedBox.shrink();
    }

    Widget row(String abbr, List<String> vals, String total,
        {bool dim = false, bool header = false}) {
      final style = header
          ? T.statLine.copyWith(fontSize: 13, color: T.textFaint)
          : TextStyle(
              fontSize: 13,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: dim ? T.textFaint : T.textDim);
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: header
            ? null
            : const BoxDecoration(
                border: Border(top: BorderSide(color: T.divider))),
        child: Row(children: [
          SizedBox(
              width: 48,
              child: Text(abbr,
                  style: header
                      ? style
                      : T.rowText.copyWith(
                          fontSize: 13,
                          color: dim ? T.textDim : T.text))),
          for (final v in vals)
            Expanded(child: Text(v, textAlign: TextAlign.center, style: style)),
          SizedBox(
            width: 36,
            child: Text(total,
                textAlign: TextAlign.right,
                style: header
                    ? style.copyWith(color: T.textDim)
                    : T.rowScore.copyWith(fontSize: 15)),
          ),
        ]),
      );
    }

    final lead = leadingSide(comp);
    final totalLabel = switch (comp.periods.unit) {
      'inning' => 'R',
      _ => 'T',
    };
    return V2Card(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(children: [
        row('', labels, totalLabel, header: true),
        row(away?.label ?? lines?.away.abbr ?? '', awayVals, awayTotal,
            dim: lead != null && lead == home),
        row(home?.label ?? lines?.home.abbr ?? '', homeVals, homeTotal,
            dim: lead != null && lead == away),
      ]),
    );
  }
}

class _TeamStatsCard extends StatelessWidget {
  final Competition comp;
  final List<TeamStatRow> rows;
  const _TeamStatsCard({required this.comp, required this.rows});

  @override
  Widget build(BuildContext context) {
    final away = comp.away, home = comp.home;
    return V2Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(away?.label ?? '', style: T.cardLabelFaint),
          const Spacer(),
          const CardLabel('Team stats'),
          const Spacer(),
          Text(home?.label ?? '', style: T.cardLabelFaint),
        ]),
        const SizedBox(height: 6),
        for (final r in rows.take(10))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              SizedBox(
                  width: 52,
                  child: Text(r.away ?? '',
                      style: T.rowText.copyWith(fontSize: 13))),
              Expanded(
                child: Text(r.label.toUpperCase(),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.captionFaint.copyWith(letterSpacing: 0.5)),
              ),
              SizedBox(
                width: 52,
                child: Text(r.home ?? '',
                    textAlign: TextAlign.right,
                    style: T.rowTextDim.copyWith(fontSize: 13)),
              ),
            ]),
          ),
      ]),
    );
  }
}

class _BoxGroupCard extends StatelessWidget {
  final BoxGroup group;
  const _BoxGroupCard(this.group);

  static const _maxCols = 5;

  @override
  Widget build(BuildContext context) {
    final cols = group.columns.take(_maxCols).toList();
    return V2Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CardLabel(group.title),
        for (final team in group.teams) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child:
                    Text(team.abbr ?? team.side ?? '', style: T.cardLabelFaint)),
            for (final c in cols)
              SizedBox(
                  width: 38,
                  child: Text(c,
                      textAlign: TextAlign.right, style: T.cardLabelFaint)),
          ]),
          for (final r in team.rows.take(12))
            Container(
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: T.divider))),
              child: Row(children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(text: r.name, children: [
                      if (r.pos != null)
                        TextSpan(
                            text: '  ${r.pos}',
                            style: const TextStyle(
                                fontSize: 11, color: T.textFaint)),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.listText.copyWith(fontSize: 13),
                  ),
                ),
                for (var i = 0; i < cols.length; i++)
                  SizedBox(
                    width: 38,
                    child: Text(
                      i < r.stats.length ? r.stats[i] : '',
                      textAlign: TextAlign.right,
                      style: T.statLine.copyWith(color: T.textDim),
                    ),
                  ),
              ]),
            ),
        ],
      ]),
    );
  }
}

class _PlaysCard extends StatelessWidget {
  final List<SummaryPlay> plays;
  final String label;
  const _PlaysCard(this.plays, {this.label = 'Plays'});

  @override
  Widget build(BuildContext context) => V2Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CardLabel(label),
          const SizedBox(height: 4),
          for (final p in plays.take(40))
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 48,
                  child: Text(
                    p.clock ?? p.periodLabel ?? '',
                    style: T.statLine.copyWith(
                        fontSize: 13, color: T.textFaint),
                  ),
                ),
                Expanded(
                  child: Text(p.text,
                      style: const TextStyle(
                          fontSize: 13, height: 1.4, color: T.textBody)),
                ),
                if (p.away != null && p.home != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text('${p.away}–${p.home}',
                        style:
                            T.statLine.copyWith(color: T.textDim)),
                  ),
              ]),
            ),
        ]),
      );
}

class _ProbablesCard extends StatelessWidget {
  final Competition comp;
  const _ProbablesCard(this.comp);

  @override
  Widget build(BuildContext context) => V2Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const CardLabel('Probables'),
          const SizedBox(height: 4),
          for (final c in comp.competitors)
            for (final p in c.probables)
              StatListRow(
                name: p.athlete,
                detail: [c.label, if (p.record != null) p.record!].join(' · '),
                stat: p.role.toUpperCase(),
              ),
        ]),
      );
}

class _FormCard extends StatelessWidget {
  final List<SideForm> form;
  const _FormCard(this.form);

  @override
  Widget build(BuildContext context) => V2Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const CardLabel('Recent form'),
          const SizedBox(height: 10),
          for (final f in form)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                SizedBox(
                    width: 52,
                    child: Text(f.abbr ?? f.side ?? '',
                        style: T.rowText.copyWith(fontSize: 13))),
                for (final ch in f.form.characters)
                  Padding(
                    padding: const EdgeInsets.only(right: 5),
                    child: Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: ch == 'W'
                            ? T.green.withValues(alpha: 0.18)
                            : ch == 'L'
                                ? T.live.withValues(alpha: 0.16)
                                : T.track,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(ch,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: ch == 'W'
                                  ? T.green
                                  : ch == 'L'
                                      ? T.live
                                      : T.textDim)),
                    ),
                  ),
              ]),
            ),
        ]),
      );
}

class _InjuriesCard extends StatelessWidget {
  final List<TeamInjuries> injuries;
  const _InjuriesCard(this.injuries);

  @override
  Widget build(BuildContext context) => V2Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const CardLabel('Key absences'),
          const SizedBox(height: 4),
          for (final t in injuries)
            for (final i in t.items.take(4))
              StatListRow(
                name: i.name,
                detail: [t.abbr ?? '', if (i.pos != null) i.pos!]
                    .where((s) => s.isNotEmpty)
                    .join(' · '),
                stat: i.line,
              ),
        ]),
      );
}

class _SeasonSeriesCard extends StatelessWidget {
  final SeasonSeries series;
  const _SeasonSeriesCard(this.series);

  @override
  Widget build(BuildContext context) => V2Card(
        child: Row(children: [
          const CardLabel('Season series'),
          const Spacer(),
          Flexible(
            child: Text(series.summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: T.rowText.copyWith(fontSize: 13)),
          ),
        ]),
      );
}

class _VenueCard extends StatelessWidget {
  final SportEvent event;
  const _VenueCard(this.event);

  @override
  Widget build(BuildContext context) {
    final v = event.venue;
    final bits = [
      if (v != null) [v.name, v.location].where((s) => s.isNotEmpty).join(' · '),
      if (event.weather != null && event.weather!.summary.isNotEmpty)
        event.weather!.summary,
      if (event.broadcasts.isNotEmpty) event.broadcasts.join(' · '),
    ];
    if (bits.isEmpty) return const SizedBox.shrink();
    return V2Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const CardLabel('Game info'),
        const SizedBox(height: 8),
        for (final b in bits)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(b, style: T.caption.copyWith(height: 1.4)),
          ),
      ]),
    );
  }
}

class _NotesCard extends StatelessWidget {
  final List<String> notes;
  const _NotesCard(this.notes);

  @override
  Widget build(BuildContext context) => V2Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final n in notes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(n, style: T.caption.copyWith(height: 1.4)),
            ),
        ]),
      );
}
