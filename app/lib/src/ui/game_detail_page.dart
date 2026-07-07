import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import '../util.dart';
import 'golf_scorecard_page.dart';
import 'match_events.dart';
import 'poll.dart';
import 'situations.dart';
import 'stat_specs.dart';
import 'widgets.dart';

void openGameDetail(BuildContext context, String league, SportEvent event,
    {String? date}) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) =>
        GameDetailPage(league: league, initialEvent: event, date: date),
  ));
}

/// The freshest narrative line for a soccer/rugby live game — composed from the
/// cheap [Competition.events] timeline when there's no core `situation.lastPlay`
/// — so the §7 inverted "loud moment" card isn't absent for the sport.
String? lastEventLine(Competition comp) {
  for (final e in comp.events.reversed) {
    final who = e.athlete;
    if (e.isGoal && (who?.isNotEmpty ?? false)) {
      return 'GOAL — $who${e.clock != null ? ' ${e.clock}' : ''}';
    }
    if ((e.redCard || e.type == 'red-card') && (who?.isNotEmpty ?? false)) {
      return 'RED CARD — $who${e.clock != null ? ' ${e.clock}' : ''}';
    }
  }
  return null;
}

/// Live game detail: giant score block (or event block) that collapses into a
/// sticky scorebug, pinned chip nav, then the card stack — situation card
/// (the sport's flourish), win probability, last play, supporting stats.
class GameDetailPage extends ConsumerStatefulWidget {
  final String league;
  final SportEvent initialEvent;

  /// The day this event came from ('YYYYMMDD'), or null for today. Plumbed so
  /// re-resolution hits the right day's slate when the game was opened from a
  /// past/future date-strip slate; the eventId-keyed [summaryProvider] is
  /// date-independent so it's unaffected.
  final String? date;
  const GameDetailPage(
      {super.key,
      required this.league,
      required this.initialEvent,
      this.date});

  @override
  ConsumerState<GameDetailPage> createState() => _GameDetailPageState();
}

class _GameDetailPageState extends ConsumerState<GameDetailPage>
    with LifecyclePoll {
  int _chip = 0;

  SummaryKey get _summaryKey =>
      (league: widget.league, eventId: widget.initialEvent.id);

  ScoresKey get _scoresKey => (league: widget.league, date: widget.date);

  /// The sport family (the `sport/league` prefix) — the key the curated cheap
  /// panels and rich-stat ordering are looked up by.
  String get _sport => widget.league.split('/').first;

  @override
  void initState() {
    super.initState();
    _chip = _initialChip();
    attachPoll();
    WidgetsBinding.instance.addPostFrameCallback((_) => repace());
  }

  /// A racing weekend nests its sessions (practice/qual/race) as sibling
  /// competitions; open on the one [SportEvent.main] already picks (live → race
  /// → first) rather than always FP1.
  int _initialChip() {
    final e = widget.initialEvent;
    final comp = e.main;
    if (comp != null && _isMultiSession(e, comp)) {
      final idx = e.competitions.indexOf(comp);
      return idx < 0 ? 0 : idx;
    }
    return 0;
  }

  /// True for a multi-session racing weekend (field layout, not golf, >1 comp).
  bool _isMultiSession(SportEvent event, Competition comp) =>
      comp.isField && comp.scoreKind != 'toPar' && event.competitions.length > 1;

  String _sessionLabel(Competition c, int i) {
    final l = c.label;
    return (l != null && l.isNotEmpty) ? l : 'Session ${i + 1}';
  }

  @override
  void dispose() {
    detachPoll();
    super.dispose();
  }

  SportEvent get _event {
    final scores = ref.read(leagueScoresProvider(_scoresKey)).valueOrNull;
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
    ref.invalidate(leagueScoresProvider(_scoresKey));
    ref.invalidate(summaryProvider(_summaryKey));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(leagueScoresProvider(_scoresKey), (_, __) => repace());
    ref.watch(leagueScoresProvider(_scoresKey));
    final summary = ref.watch(summaryProvider(_summaryKey)).valueOrNull;

    final event = _event;
    final comp = event.main;
    if (comp == null) {
      return const Scaffold(body: Center(child: Text('No competition data')));
    }

    final chips = _chipLabels(event, comp, summary);
    final chipIndex = _chip.clamp(0, chips.length - 1);
    final sections =
        _sections(context, event, comp, summary, chips, chipIndex);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _HeaderDelegate(
              // Floor the inset so the top bar keeps breathing room on displays
              // without a status-bar cutout (web/desktop preview) and never jams
              // the back chevron against the top edge.
              topPadding: math.max(MediaQuery.paddingOf(context).top, 16),
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

  List<String> _chipLabels(
      SportEvent event, Competition comp, GameSummary? summary) {
    if (comp.isField) {
      // A racing weekend gets one chip per session (practice/qual/race); a
      // single-session field event (golf, one-off race) keeps a plain chip.
      if (_isMultiSession(event, comp)) {
        return [
          for (var i = 0; i < event.competitions.length; i++)
            _sessionLabel(event.competitions[i], i),
        ];
      }
      return const ['Leaderboard'];
    }
    final s = comp.status;
    final first = s.live ? 'Now' : (s.isScheduled ? 'Preview' : 'Recap');
    final hasBox = comp.competitors.any((c) => c.periodScores.isNotEmpty) ||
        (summary != null &&
            (summary.boxGroups.isNotEmpty ||
                summary.teamStats.isNotEmpty ||
                summary.periodLines != null));
    final hasScorecard =
        summary != null && summary.cricketInnings.isNotEmpty;
    final hasTimeline = _hasMatchTimeline(comp, summary);
    final hasPlays = summary != null &&
        (summary.scoringPlays.isNotEmpty || summary.plays.isNotEmpty);
    final hasDrives = summary != null && summary.drives.isNotEmpty;
    final hasLeaders = comp.competitors.any((c) => c.leaders.isNotEmpty);
    return [
      first,
      if (hasScorecard) 'Scorecard',
      if (hasBox) 'Box',
      if (hasDrives) 'Drives',
      // Soccer/rugby get the curated event feed ('Timeline'); everything else
      // the raw play-by-play ('Plays').
      if (hasTimeline) 'Timeline' else if (hasPlays) 'Plays',
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
      // On a racing weekend the chip nav picks the session; golf/one-off races
      // stay on their single competition.
      final multiSession = _isMultiSession(event, comp);
      final session = multiSession
          ? event.competitions[chipIndex.clamp(0, event.competitions.length - 1)]
          : comp;
      final golf = session.meta?.golf;
      final season =
          ref.read(leagueScoresProvider(_scoresKey)).valueOrNull?.season.year;
      return [
        if (golf != null) _GolfMetaStrip(session, golf),
        FieldLeaderboard(
          session,
          maxRows: 25,
          // racing shows the entrant's constructor; golf has none.
          showConstructor: session.scoreKind != 'toPar',
          // golf rows open the hole-by-hole scorecard; racing rows don't
          // (no per-driver endpoint worth the tap).
          onRowTap: session.scoreKind == 'toPar'
              ? (c) => openGolfScorecard(
                  context, widget.league, event.id, c,
                  season: season)
              : null,
        ),
        if (session.situation?.lastPlay != null)
          InvertedCard(label: 'Latest', text: session.situation!.lastPlay!),
        if (event.notes.isNotEmpty) _NotesCard(event.notes),
      ];
    }
    final label = chips[chipIndex];
    switch (label) {
      case 'Scorecard': // cricket innings scorecard (batting + bowling figures)
        return [
          for (final inn in summary!.cricketInnings) _CricketInningsCard(inn),
        ];
      case 'Box':
        return [
          if (_hasCheapLines(comp) || summary?.periodLines != null)
            _LineScoreCard(comp: comp, lines: summary?.periodLines),
          if (summary != null && summary.teamStats.isNotEmpty)
            _TeamStatsCard(comp: comp, rows: summary.teamStats, sport: _sport),
          if (summary != null)
            for (final g in summary.boxGroups) _BoxGroupCard(g),
          if (summary == null) const _LoadingCard(),
        ];
      case 'Drives':
        return [_DrivesCard(summary!.drives.reversed.toList())];
      case 'Timeline':
        // Soccer/rugby: the curated goal/card/sub event feed (design 9a). Renders
        // off the cheap scoreboard timeline immediately, upgrades to the worker's
        // structured feed (subs, assists) when /summary lands.
        return [
          ActionFeed(_matchTimeline(comp, summary), comp,
              tallyScore: _sport == 'soccer'),
        ];
      case 'Plays':
        // Every other sport's full play-by-play, through the SAME feed grammar
        // (design 9b/9c): grouped by period, scores lifted with the running total.
        final plays = summary!.plays.isNotEmpty
            ? summary.plays
            : summary.scoringPlays;
        return [
          ActionFeed(
              [for (final p in plays) MatchEvent.fromSummaryPlay(p)], comp),
        ];
      case 'Leaders':
        return [
          for (final c in comp.competitors)
            if (c.leaders.isNotEmpty) _SideLeadersCard(c),
        ];
      default: // Now / Preview / Recap
        final s = comp.status;
        if (s.live) {
          final situation = situationCardFor(comp);
          final cheap = _cheapPanelFor(comp);
          final leadPlays = _leadPlays(summary);
          final crease = (summary?.cricketInnings.isNotEmpty ?? false)
              ? summary!.cricketInnings.last
              : null;
          return [
            if (situation != null) situation,
            // Basketball's §8 lead tracker — computed from the summary's running
            // scores (data-driven: only games with a scoring curve draw it).
            if (leadPlays.length >= 12)
              _LeadTrackerCard(comp: comp, plays: leadPlays),
            if (crease != null) _CricketCreaseCard(crease),
            if (_isFightCard(event, comp))
              _FightCardCard(league: widget.league, event: event, main: comp),
            if (summary?.winProbability != null)
              _WinProbCard(comp: comp, wp: summary!.winProbability!),
            // The one loud moment (§7): the core last-play text, or — for
            // soccer/rugby, which carry no core situation — the freshest event.
            if (comp.situation?.lastPlay != null)
              InvertedCard(label: 'Last play', text: comp.situation!.lastPlay!)
            else if (lastEventLine(comp) != null)
              InvertedCard(label: 'Last event', text: lastEventLine(comp)!),
            // Match-stats pulse straight off the scoreboard — no /summary wait.
            if (cheap != null) _CheapStatsCard(comp: comp, panel: cheap),
            _TopPerformersCard(comp),
            if (summary != null && summary.lineups.isNotEmpty)
              _LineupsCard(summary.lineups),
            if (summary != null && summary.seasonSeries != null)
              _SeasonSeriesCard(summary.seasonSeries!),
          ].whereType<Widget>().toList();
        }
        if (s.isScheduled) {
          return [
            if (comp.competitors.any((c) => c.probables.isNotEmpty))
              _ProbablesCard(comp),
            if (summary != null && summary.lineups.isNotEmpty)
              _LineupsCard(summary.lineups),
            if (summary != null && summary.recentForm.isNotEmpty)
              _FormCard(summary.recentForm),
            if (summary != null && summary.injuries.isNotEmpty)
              _InjuriesCard(summary.injuries),
            _VenueCard(event, comp: comp, summary: summary),
          ];
        }
        // Recap
        final bout = summary?.boutFor(comp.id);
        final cheap = _cheapPanelFor(comp);
        final timeline = _matchTimeline(comp, summary);
        final hasGoals = timeline.any((e) => e.isScoring);
        // Non-soccer condensed "who scored" log (soccer/rugby use the timeline
        // goals above): actual scores only, most-recent dozen so a high-scoring
        // sport doesn't turn the recap into a wall — the Plays tab has them all.
        final scores = summary == null
            ? const <SummaryPlay>[]
            : summary.scoringPlays.where((p) => p.scoring).toList();
        final recap = scores.length > 12
            ? scores.sublist(scores.length - 12)
            : scores;
        return [
          // The match timeline reads as well after full-time as it does live —
          // it's the goal/card story of the game at a glance (soccer/rugby).
          if (comp.events.isNotEmpty) MatchTimelineCard(comp),
          if (comp.method != null || bout != null)
            _MethodCard(comp: comp, bout: bout),
          if (_isFightCard(event, comp))
            _FightCardCard(league: widget.league, event: event, main: comp),
          if (_leadPlays(summary).length >= 12)
            _LeadTrackerCard(comp: comp, plays: _leadPlays(summary)),
          if (_hasCheapLines(comp) || summary?.periodLines != null)
            _LineScoreCard(comp: comp, lines: summary?.periodLines),
          if (cheap != null) _CheapStatsCard(comp: comp, panel: cheap),
          if (comp.headline != null) _HeadlineCard(comp.headline!),
          _TopPerformersCard(comp),
          if (hasGoals)
            ActionFeed(timeline, comp,
                scoringOnly: true,
                tallyScore: _sport == 'soccer',
                label: 'Scoring')
          else if (recap.isNotEmpty)
            ActionFeed([for (final p in recap) MatchEvent.fromSummaryPlay(p)],
                comp,
                scoringOnly: true, label: 'Scoring'),
          if (summary != null && summary.seasonSeries != null)
            _SeasonSeriesCard(summary.seasonSeries!),
          _VenueCard(event, comp: comp, summary: summary),
        ].whereType<Widget>().toList();
    }
  }

  /// Scoring plays that carry a running score — the input to the §8 lead tracker.
  List<SummaryPlay> _leadPlays(GameSummary? summary) => (summary?.scoringPlays ??
          const <SummaryPlay>[])
      .where((p) => p.away != null && p.home != null)
      .toList();

  /// A combat card (MMA/boxing): athletes head-to-head with an undercard of
  /// sibling bouts — dispatched on data, never sport name.
  bool _isFightCard(SportEvent event, Competition comp) =>
      event.competitions.length > 1 &&
      !comp.isField &&
      comp.competitorKind == 'athlete';

  // Tennis sets render in the header grid; cricket innings are long composite
  // strings that wreck a numeric table (the Scorecard chip carries the real
  // innings detail instead).
  bool _hasCheapLines(Competition comp) =>
      comp.competitors.any((c) => c.periodScores.isNotEmpty) &&
      comp.periods.unit != 'set' &&
      comp.periods.unit != 'over_innings';

  /// Whether soccer/rugby's curated event feed has anything to show — the cheap
  /// scoreboard timeline (goals + cards) or the worker's richer structured feed.
  bool _hasMatchTimeline(Competition comp, GameSummary? summary) =>
      comp.events.isNotEmpty || (summary?.timeline.isNotEmpty ?? false);

  /// The soccer/rugby event feed for [MatchEventList]: the worker's structured
  /// timeline (subs + assists) when /summary has loaded, else the cheap
  /// scoreboard timeline (goals + cards) projected into the same shape so the tab
  /// renders instantly and then upgrades in place.
  List<MatchEvent> _matchTimeline(Competition comp, GameSummary? summary) {
    if (summary != null && summary.timeline.isNotEmpty) return summary.timeline;
    if (comp.events.isEmpty) return const [];
    String? abbrFor(String? side) => side == 'home'
        ? comp.home?.label
        : (side == 'away' ? comp.away?.label : null);
    return [
      for (final e in comp.events)
        MatchEvent.fromScoringEvent(e, teamAbbr: abbrFor(e.team)),
    ];
  }

  /// This sport's curated cheap-tier stat panel, if it exists and the
  /// scoreboard actually carries its rows for this game.
  CheapStatPanel? _cheapPanelFor(Competition comp) {
    final panel = cheapStatPanels[_sport];
    if (panel == null) return null;
    return _CheapStatsCard.has(comp, panel) ? panel : null;
  }
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

  static const _bugH = 46.0;

  // A single-chip header ('Leaderboard') reserves no chip row — otherwise an
  // empty 50px strip opens a dead gap above field-sport leaderboards.
  double get _chipH => chips.length > 1 ? 50.0 : 0.0;

  // Sized to the actual block content so the pinned chip row sits directly
  // under the score, not floating halfway down to the first card.
  double get _blockH {
    if (comp.isField) return 124;
    if (isSetGrid(comp)) return 158;
    return 186;
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
          // back chevron, always present. left:4 keeps the 48px tap target's
          // hover/splash circle clear of the screen edge.
          Positioned(
            top: topPadding - 2,
            left: 4,
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
    // The MEN badge reads as "down a man RIGHT NOW" — live only.
    if (!comp.status.live) return null;
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

/// The §8 basketball "lead tracker" — a margin polyline over the game's scoring
/// plays, with a recent unanswered-run callout. Built entirely client-side from
/// the summary's running scores (no extra fetch). Shown when a game has enough
/// scoring events to draw a curve (data-driven — selects basketball naturally).
class _LeadTrackerCard extends StatelessWidget {
  final Competition comp;
  final List<SummaryPlay> plays; // scoring plays, oldest→newest, with away/home
  const _LeadTrackerCard({required this.comp, required this.plays});

  @override
  Widget build(BuildContext context) {
    final away = comp.away, home = comp.home;
    final margins = <double>[
      for (final p in plays) ((p.home ?? 0) - (p.away ?? 0)).toDouble(),
    ];
    if (margins.length < 2) return const SizedBox.shrink();
    final last = margins.last;
    final leader = last == 0 ? null : (last > 0 ? home : away);

    // Trailing unanswered run: points by the last-scoring side since the other
    // side last scored.
    int runPts = 0;
    String? runSide;
    for (var i = plays.length - 1; i >= 0; i--) {
      final p = plays[i];
      runSide ??= p.side;
      if (p.side != runSide || p.side == null) break;
      final prevHome = i > 0 ? (plays[i - 1].home ?? 0) : 0;
      final prevAway = i > 0 ? (plays[i - 1].away ?? 0) : 0;
      final pts = (p.side == 'home'
              ? (p.home ?? 0) - prevHome
              : (p.away ?? 0) - prevAway)
          .round();
      if (pts <= 0) break;
      runPts += pts;
    }
    final runTeam = runSide == 'home' ? home : (runSide == 'away' ? away : null);
    final hasRun = runPts >= 6 && runTeam != null;

    return V2Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          const Expanded(child: CardLabel('Lead tracker')),
          if (hasRun)
            Text('${runTeam.label} $runPts–0 RUN',
                style: T.statCallout.copyWith(fontSize: 18, color: T.gold))
          else if (leader != null)
            Text('${leader.label} +${last.abs().round()}',
                style: T.statCallout.copyWith(fontSize: 18)),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          height: 64,
          width: double.infinity,
          child: CustomPaint(
            painter: _LeadTrackerPainter(
              margins: margins,
              awayColor: teamColor(away),
              homeColor: teamColor(home),
            ),
          ),
        ),
      ]),
    );
  }
}

class _LeadTrackerPainter extends CustomPainter {
  final List<double> margins;
  final Color awayColor, homeColor;
  _LeadTrackerPainter(
      {required this.margins, required this.awayColor, required this.homeColor});

  @override
  void paint(Canvas canvas, Size size) {
    final maxAbs = margins.fold<double>(
        1, (m, v) => v.abs() > m ? v.abs() : m);
    // centerline
    final mid = size.height / 2;
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid),
        Paint()..color = T.divider..strokeWidth = 1);
    double x(int i) => margins.length == 1
        ? 0
        : size.width * i / (margins.length - 1);
    double y(double v) => mid - (v / maxAbs) * (mid - 3);
    final path = Path()..moveTo(0, y(margins.first));
    for (var i = 1; i < margins.length; i++) {
      path.lineTo(x(i), y(margins[i]));
    }
    // stroke tinted toward whoever leads at the end (home +ve / away -ve)
    final last = margins.last;
    final stroke = last == 0
        ? T.textDim
        : (last > 0 ? homeColor : awayColor);
    canvas.drawPath(
        path,
        Paint()
          ..color = stroke
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round);
    // endpoint dot
    canvas.drawCircle(
        Offset(x(margins.length - 1), y(last)), 3, Paint()..color = stroke);
  }

  @override
  bool shouldRepaint(_LeadTrackerPainter old) => old.margins != margins;
}

/// The §8 cricket "crease" card — the not-out batters at the wicket, from the
/// latest innings of the summary scorecard (a light, extra-fetch-free read; the
/// ball-by-ball THIS OVER row needs the play-by-play resource we don't fetch).
class _CricketCreaseCard extends StatelessWidget {
  final CricketInningsCard innings;
  const _CricketCreaseCard(this.innings);

  @override
  Widget build(BuildContext context) {
    final notOut = innings.batting
        .where((b) => b.dismissal == null || b.dismissal!.isEmpty)
        .toList();
    if (notOut.isEmpty) return const SizedBox.shrink();
    return V2Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const CardLabel('At the crease'),
        const SizedBox(height: 4),
        for (final b in notOut)
          StatListRow(
            name: b.name,
            emphasized: true,
            stat: [
              if (b.runs != null) b.runs!,
              if (b.balls != null) '(${b.balls})',
            ].join(' '),
          ),
      ]),
    );
  }
}

/// The full fight card (§8 combat): every bout on the card, not just the main
/// event. Fighters + result/method per bout, tapping through to that bout.
class _FightCardCard extends StatelessWidget {
  final String league;
  final SportEvent event;
  final Competition main;
  const _FightCardCard(
      {required this.league, required this.event, required this.main});

  @override
  Widget build(BuildContext context) {
    final bouts = event.competitions;
    if (bouts.length < 2) return const SizedBox.shrink();
    return V2Card(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.only(top: 10),
          child: CardLabel('Fight card'),
        ),
        for (var i = 0; i < bouts.length; i++) _boutRow(bouts[i], i > 0),
      ]),
    );
  }

  Widget _boutRow(Competition bout, bool divider) {
    final cs = bout.competitors;
    final a = cs.isNotEmpty ? cs.first : null;
    final b = cs.length > 1 ? cs[1] : null;
    final result = bout.method?.kind ?? bout.status.shortDetail;
    final wins = cs.where((c) => c.isWinner).toList();
    final winner = wins.isEmpty ? null : wins.first;
    Widget name(Competitor? c) => Text(c?.label ?? 'TBD',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: T.rowText.copyWith(
            color: winner == null || c == winner ? T.text : T.textDim));
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: divider
          ? const BoxDecoration(
              border: Border(top: BorderSide(color: T.divider)))
          : null,
      child: Row(children: [
        Expanded(child: name(a)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Text('vs', style: T.captionFaint),
        ),
        Expanded(child: name(b)),
        if (result != null && result.isNotEmpty) ...[
          const SizedBox(width: 8),
          Text(result.toUpperCase(),
              style: T.cardLabelFaint.copyWith(fontSize: 10)),
        ],
      ]),
    );
  }
}

class _TopPerformersCard extends StatelessWidget {
  final Competition comp;
  const _TopPerformersCard(this.comp);

  @override
  Widget build(BuildContext context) {
    final rows = <({String name, String sub, String stat, Color color})>[];
    for (final c in comp.competitors) {
      if (c.leaders.isEmpty) continue;
      final l = c.leaders.first;
      if (l.athlete == null) continue;
      rows.add((
        name: l.athlete!,
        sub: '${c.label} · ${l.label}',
        stat: l.display ?? '',
        color: teamColor(c),
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
              TintedAvatar(_initials(r.name), r.color, size: 36),
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
    final lead = leadingSide(comp);

    // Baseball reads as the traditional box: a full nine-inning grid (blank
    // future innings) that scrolls horizontally under a pinned team column,
    // with R/H/E totals pinned on the right.
    if (comp.periods.unit == 'inning' &&
        ((away?.periodScores.isNotEmpty ?? false) ||
            (home?.periodScores.isNotEmpty ?? false))) {
      return _InningLineScore(away: away, home: home, lead: lead);
    }

    // Generic per-period grid (quarters/periods): few columns, one total.
    List<String> labels;
    List<String> awayVals, homeVals;
    String awayTotal, homeTotal;
    if ((away?.periodScores.isNotEmpty ?? false) ||
        (home?.periodScores.isNotEmpty ?? false)) {
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

    return V2Card(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(children: [
        row('', labels, 'T', header: true),
        row(away?.label ?? lines?.away.abbr ?? '', awayVals, awayTotal,
            dim: lead != null && lead == home),
        row(home?.label ?? lines?.home.abbr ?? '', homeVals, homeTotal,
            dim: lead != null && lead == away),
      ]),
    );
  }
}

/// Baseball line score. Innings scroll horizontally between a pinned team
/// column and pinned R/H/E totals so the grid holds all nine (plus extras)
/// without squashing, and the totals never scroll out of view.
class _InningLineScore extends StatelessWidget {
  final Competitor? away, home;
  final Competitor? lead;
  const _InningLineScore(
      {required this.away, required this.home, required this.lead});

  static const _labelW = 34.0;
  static const _innW = 24.0;
  static const _rW = 30.0;
  static const _heW = 26.0;
  static const _headH = 28.0;
  static const _rowH = 34.0;

  @override
  Widget build(BuildContext context) {
    final maxPlayed = [
      ...?away?.periodScores.map((p) => p.period),
      ...?home?.periodScores.map((p) => p.period),
    ].fold(0, (a, b) => a > b ? a : b);
    final n = maxPlayed > 9 ? maxPlayed : 9;
    final innings = [for (var i = 1; i <= n; i++) i];

    String inn(Competitor? c, int i) {
      for (final p in c?.periodScores ?? const <PeriodScore>[]) {
        if (p.period == i) return p.display;
      }
      return '';
    }

    final headerStyle = T.statLine.copyWith(fontSize: 12, color: T.textFaint);
    TextStyle valStyle(bool dim) => TextStyle(
        fontSize: 13,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: dim ? T.textFaint : T.textDim);
    bool dimSide(Competitor? c) => lead != null && lead != c;

    // Every band across the three columns shares a height so the rows line up;
    // data rows carry the hairline (the header row does not).
    Widget band(Widget child, {required bool header, Alignment align = Alignment.center}) =>
        Container(
          height: header ? _headH : _rowH,
          alignment: align,
          decoration: header
              ? null
              : const BoxDecoration(
                  border: Border(top: BorderSide(color: T.divider))),
          child: child,
        );

    Widget cell(String s, double w, TextStyle st) =>
        SizedBox(width: w, child: Text(s, textAlign: TextAlign.center, style: st));

    // §10 semantic inning cell: unplayed → ghost '–', a scoring inning → white,
    // a zero → dim.
    Widget inningCell(Competitor? c, int i) {
      final v = inn(c, i);
      final played = v.isNotEmpty;
      final scoring = played && v != '0';
      return cell(
          played ? v : '–',
          _innW,
          TextStyle(
              fontSize: 13,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: !played
                  ? T.ghost
                  : (scoring ? T.text : T.textDim)));
    }

    // pinned team column
    final labelCol = Column(children: [
      band(const SizedBox.shrink(), header: true),
      for (final c in [away, home])
        band(
          Text(c?.label ?? '',
              style: T.rowText.copyWith(
                  fontSize: 13, color: dimSide(c) ? T.textDim : T.text)),
          header: false,
          align: Alignment.centerLeft,
        ),
    ]);

    // scrolling innings
    final inningsCol = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(children: [
        band(
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (final i in innings) cell('$i', _innW, headerStyle),
          ]),
          header: true,
        ),
        for (final c in [away, home])
          band(
            Row(mainAxisSize: MainAxisSize.min, children: [
              for (final i in innings) inningCell(c, i),
            ]),
            header: false,
          ),
      ]),
    );

    // pinned R/H/E totals
    String he(int? v) => v?.toString() ?? '–';
    Widget totalsRow(Competitor? c) {
      final dim = dimSide(c);
      return Row(mainAxisSize: MainAxisSize.min, children: [
        cell(c?.score?.display ?? '', _rW,
            T.rowScore.copyWith(fontSize: 15, color: dim ? T.textDim : T.text)),
        cell(he(c?.hits), _heW, valStyle(dim)),
        cell(he(c?.errors), _heW, valStyle(dim)),
      ]);
    }

    final totalsCol = Column(children: [
      band(
        Row(mainAxisSize: MainAxisSize.min, children: [
          cell('R', _rW, headerStyle),
          cell('H', _heW, headerStyle),
          cell('E', _heW, headerStyle),
        ]),
        header: true,
      ),
      band(totalsRow(away), header: false),
      band(totalsRow(home), header: false),
    ]);

    return V2Card(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: _labelW, child: labelCol),
        Expanded(child: inningsCol),
        totalsCol,
      ]),
    );
  }
}

/// The rich /summary team-stat comparison, organized instead of dumped: the
/// sport's lead stats ([richPriorityKeywords]) surface first in fan order, the
/// long tail waits behind a quiet "All team stats" expander, and every row is
/// drawn by its kind — conversion ratios ("4-16" on 3rd down) and percents as
/// gauges, possession clocks ("33:11") as a share of real time, counts split.
class _TeamStatsCard extends StatefulWidget {
  final Competition comp;
  final List<TeamStatRow> rows;
  final String? sport;
  const _TeamStatsCard({required this.comp, required this.rows, this.sport});

  @override
  State<_TeamStatsCard> createState() => _TeamStatsCardState();
}

class _TeamStatsCardState extends State<_TeamStatsCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final away = widget.comp.away, home = widget.comp.home;
    final present =
        widget.rows.where((r) => r.away != null || r.home != null).toList();
    if (present.isEmpty) return const SizedBox.shrink();

    var (:lead, :rest) = curateRichRows(present, widget.sport);
    // A tail too short to be worth a fold just shows — the expander is for the
    // 20-row firehose, not two stragglers.
    if (rest.length < 3) {
      lead = [...lead, ...rest];
      rest = const [];
    }
    final shown = _expanded ? [...lead, ...rest] : lead;

    return V2Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(away?.label ?? '',
              style: T.cardLabelFaint.copyWith(color: teamColor(away))),
          const Spacer(),
          const CardLabel('Team stats'),
          const Spacer(),
          Text(home?.label ?? '',
              style: T.cardLabelFaint.copyWith(color: teamColor(home))),
        ]),
        const SizedBox(height: 10),
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          StatCompareRow(
            spec: classifyRichRow(shown[i]),
            away: shown[i].away,
            home: shown[i].home,
            awayColor: teamColor(away),
            homeColor: teamColor(home),
          ),
        ],
        if (rest.isNotEmpty)
          Center(
            child: TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18),
              label: Text(
                  _expanded
                      ? 'Key stats only'
                      : 'All team stats (${lead.length + rest.length})',
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600)),
              style: TextButton.styleFrom(foregroundColor: T.textDim),
            ),
          ),
      ]),
    );
  }
}

/// A sport's cheap-tier match-stat panel straight off the scoreboard — the
/// instant possession/shooting read that needs no /summary fetch. Draws each
/// row through the same [StatCompareRow] as the rich panel, so the two tiers
/// can't drift apart.
class _CheapStatsCard extends StatelessWidget {
  final Competition comp;
  final CheapStatPanel panel;
  const _CheapStatsCard({required this.comp, required this.panel});

  /// True when at least one present row has a value on either side.
  static bool has(Competition comp, CheapStatPanel panel) {
    final a = comp.away, b = comp.home;
    if (a == null || b == null) return false;
    return panel.rows.any((r) => a.stats[r.key] != null || b.stats[r.key] != null);
  }

  @override
  Widget build(BuildContext context) {
    final away = comp.away, home = comp.home;
    if (away == null || home == null) return const SizedBox.shrink();
    final present = panel.rows
        .where((r) => away.stats[r.key] != null || home.stats[r.key] != null)
        .toList();
    if (present.isEmpty) return const SizedBox.shrink();
    return V2Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(away.label,
              style: T.cardLabelFaint.copyWith(color: teamColor(away))),
          const Spacer(),
          CardLabel(panel.title),
          const Spacer(),
          Text(home.label,
              style: T.cardLabelFaint.copyWith(color: teamColor(home))),
        ]),
        const SizedBox(height: 10),
        for (var i = 0; i < present.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          StatCompareRow(
            spec: present[i],
            away: away.stats[present[i].key],
            home: home.stats[present[i].key],
            awayColor: teamColor(away),
            homeColor: teamColor(home),
          ),
        ],
      ]),
    );
  }
}

/// Team sheets — starters and bench, one card per side, away then home. Soccer
/// /summary carries these; v2 already parses them into [Lineup], this renders
/// the starting XI (formation header) with a dimmed bench beneath.
class _LineupsCard extends StatelessWidget {
  final List<Lineup> lineups;
  const _LineupsCard(this.lineups);

  @override
  Widget build(BuildContext context) {
    final ordered = [...lineups];
    if (ordered.every((l) => l.side != null)) {
      ordered.sort((a, b) {
        int rank(String? s) => s == 'away' ? 0 : (s == 'home' ? 1 : 2);
        return rank(a.side).compareTo(rank(b.side));
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < ordered.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _panel(ordered[i]),
        ],
      ],
    );
  }

  Widget _panel(Lineup lineup) {
    final hasFormation =
        lineup.formation != null && lineup.formation!.isNotEmpty;
    return V2Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(lineup.abbr ?? '',
              style: T.sectionTitle.copyWith(fontSize: 15, letterSpacing: 0.5)),
          if (hasFormation) ...[
            const SizedBox(width: 8),
            Text(lineup.formation!, style: T.caption),
          ],
        ]),
        const SizedBox(height: 6),
        for (final pl in lineup.starters) _playerRow(pl),
        if (lineup.bench.isNotEmpty) ...[
          const SizedBox(height: 10),
          const CardLabel('Bench'),
          const SizedBox(height: 2),
          for (final pl in lineup.bench) _playerRow(pl, dim: true),
        ],
      ]),
    );
  }

  Widget _playerRow(LineupPlayer pl, {bool dim = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(
            width: 24,
            child: Text(pl.jersey ?? '',
                maxLines: 1, style: T.statLine.copyWith(color: T.textFaint)),
          ),
          Expanded(
            child: Text(pl.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    TextStyle(fontSize: 14, color: dim ? T.textDim : T.text)),
          ),
          if (pl.pos != null && pl.pos!.isNotEmpty)
            SizedBox(
              width: 34,
              child: Text(pl.pos!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 13, color: T.textDim)),
            ),
        ]),
      );
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
  final Competition? comp;
  final GameSummary? summary;
  const _VenueCard(this.event, {this.comp, this.summary});

  static String _thousands(int n) => n.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');

  /// The officials worth a glance: the referee(s) first, capped at two.
  static String? _officialsLine(List<Official> officials) {
    if (officials.isEmpty) return null;
    final sorted = List.of(officials)
      ..sort((a, b) {
        int w(Official o) =>
            (o.role ?? '').toLowerCase().contains('referee') ? 0 : 1;
        return w(a).compareTo(w(b));
      });
    return sorted
        .take(2)
        .map((o) => o.role != null ? '${o.name} (${o.role})' : o.name)
        .join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final v = event.venue;
    // rich-tier attendance first (authoritative), cheap-tier as fallback
    final attendance = summary?.attendance ?? comp?.attendance;
    final officials = _officialsLine(summary?.officials ?? const []);
    final bits = [
      if (v != null) [v.name, v.location].where((s) => s.isNotEmpty).join(' · '),
      if (event.weather != null && event.weather!.summary.isNotEmpty)
        event.weather!.summary,
      if (attendance != null) 'Attendance ${_thousands(attendance)}',
      if (officials != null) officials,
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

/// One quiet ESPN recap line under the final score — a single sentence, not a
/// news feed (the product excludes news; this is the one-line exception).
class _HeadlineCard extends StatelessWidget {
  final String headline;
  const _HeadlineCard(this.headline);

  @override
  Widget build(BuildContext context) => V2Card(
        child: Text(headline,
            style: const TextStyle(
                fontSize: 13.5, height: 1.45, color: T.textBody)),
      );
}

/// The golf tournament context strip: round progress, cut line, major badge.
/// Data from meta.golf (core-enriched, best-effort — absent → no strip).
class _GolfMetaStrip extends StatelessWidget {
  final Competition comp;
  final GolfMeta golf;
  const _GolfMetaStrip(this.comp, this.golf);

  @override
  Widget build(BuildContext context) {
    final r = golf.currentRound;
    final bits = <String>[
      if (!comp.status.ended && r != null) 'Round $r of ${golf.numberOfRounds}',
      if (golf.cutLine != null) golf.cutLine!,
      if (golf.scoringSystem == 'Teamstroke') 'Team event',
      if (golf.hasCut == false && golf.cutRound == 0) 'No cut',
    ];
    if (bits.isEmpty && !golf.major) return const SizedBox.shrink();
    return V2Card(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(children: [
        Expanded(
          child: Text(bits.join('  ·  '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.caption.copyWith(fontSize: 12.5)),
        ),
        if (golf.major)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: T.gold.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text('MAJOR',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: T.gold)),
          ),
      ]),
    );
  }
}

/// MMA method of victory — the cheap-tier scrape (comp.method) upgraded by the
/// structured core result + judge scorecards when the rich tier has them.
class _MethodCard extends StatelessWidget {
  final Competition comp;
  final BoutResult? bout;
  const _MethodCard({required this.comp, this.bout});

  String? _nameFor(String competitorId) {
    for (final c in comp.competitors) {
      if (c.id == competitorId) return c.shortName ?? c.displayName;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final kind = bout?.result ?? comp.method?.kind;
    if (kind == null) return const SizedBox.shrink();
    final round = bout?.round ?? comp.method?.finishRound;
    final clock = bout?.clock ?? comp.method?.finishTime;
    final isDecision = kind.toLowerCase().contains('decision');
    // for a decision the clock is just the round length — drop it
    final when = [
      if (round != null && !isDecision) 'R$round',
      if (clock != null && !isDecision) clock,
    ].join(' · ');
    final judges = bout?.judges ?? const [];
    return V2Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const CardLabel('Method'),
          const Spacer(),
          if (when.isNotEmpty)
            Text(when, style: T.statLine.copyWith(color: T.textDim)),
        ]),
        const SizedBox(height: 8),
        Text(kind,
            style: const TextStyle(
                fontFamily: 'BarlowCondensed',
                fontWeight: FontWeight.w700,
                fontSize: 26,
                color: T.text)),
        if (comp.method?.detail != null) ...[
          const SizedBox(height: 2),
          Text(comp.method!.detail!, style: T.caption),
        ],
        if (judges.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final jd in judges)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                Expanded(
                  child: Text(_nameFor(jd.competitorId) ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.listText),
                ),
                Text(jd.totals.join(' · '),
                    style: T.statLine.copyWith(color: T.textDim)),
                if (jd.total != null) ...[
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 30,
                    child: Text('${jd.total}',
                        textAlign: TextAlign.right, style: T.statLineStrong),
                  ),
                ],
              ]),
            ),
        ],
      ]),
    );
  }
}

/// Gridiron drive-by-drive rows (latest first). The full play feed lives under
/// the Plays chip; this is the between-scores skeleton of the game.
class _DrivesCard extends StatelessWidget {
  final List<DriveSummary> drives;
  const _DrivesCard(this.drives);

  @override
  Widget build(BuildContext context) => V2Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const CardLabel('Drives'),
          const SizedBox(height: 4),
          for (final d in drives.take(40))
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 48,
                  child: Text(d.teamAbbr ?? '',
                      style: T.statLine.copyWith(
                          fontSize: 13, color: T.textFaint)),
                ),
                SizedBox(
                  width: 92,
                  child: Text(d.result ?? '',
                      style: T.statLineStrong.copyWith(
                          fontSize: 13,
                          color: d.isScore ? T.gold : T.text)),
                ),
                Expanded(
                  child: Text(d.description ?? '',
                      style: const TextStyle(
                          fontSize: 13, height: 1.4, color: T.textDim)),
                ),
              ]),
            ),
        ]),
      );
}

/// One innings of the cricket scorecard: batting figures (with dismissals) then
/// the opposing bowling figures. The tables every cricket fan expects.
class _CricketInningsCard extends StatelessWidget {
  final CricketInningsCard innings;
  const _CricketInningsCard(this.innings);

  static String _ordinal(int n) => switch (n) {
        1 => '1st',
        2 => '2nd',
        3 => '3rd',
        _ => '${n}th',
      };

  static const _colW = 30.0;

  Widget _cols(List<String> vals, {TextStyle? style}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final v in vals)
            SizedBox(
              width: _colW,
              child: Text(v,
                  textAlign: TextAlign.right,
                  style: style ?? T.statLine.copyWith(color: T.textDim)),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return V2Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: CardLabel(
                '${innings.battingTeam} — ${_ordinal(innings.innings)} innings'),
          ),
          if (innings.total != null)
            Text(innings.total!,
                style: T.statLineStrong.copyWith(fontSize: 13)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          const Expanded(child: Text('BATTER', style: T.cardLabelFaint)),
          _cols(const ['R', 'B', '4s', '6s'],
              style: T.cardLabelFaint.copyWith(fontSize: 10)),
        ]),
        for (final b in innings.batting)
          Padding(
            padding: const EdgeInsets.only(top: 9),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(b.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: T.listText),
                      if (b.dismissal != null && b.dismissal!.isNotEmpty)
                        Text(b.dismissal!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: T.captionFaint),
                    ]),
              ),
              _cols([
                b.runs ?? '',
                b.balls ?? '',
                b.fours ?? '',
                b.sixes ?? '',
              ]),
            ]),
          ),
        if (innings.extras != null) ...[
          const SizedBox(height: 8),
          Text('Extras ${innings.extras}', style: T.captionFaint),
        ],
        if (innings.bowling.isNotEmpty) ...[
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: Text(
                  'BOWLING${innings.bowlingTeam != null ? ' — ${innings.bowlingTeam!.toUpperCase()}' : ''}',
                  style: T.cardLabelFaint),
            ),
            _cols(const ['O', 'M', 'R', 'W'],
                style: T.cardLabelFaint.copyWith(fontSize: 10)),
          ]),
          for (final bw in innings.bowling)
            Padding(
              padding: const EdgeInsets.only(top: 9),
              child: Row(children: [
                Expanded(
                  child: Text(bw.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.listText),
                ),
                _cols([
                  bw.overs ?? '',
                  bw.maidens ?? '',
                  bw.runs ?? '',
                  bw.wickets ?? '',
                ]),
              ]),
            ),
        ],
      ]),
    );
  }
}
