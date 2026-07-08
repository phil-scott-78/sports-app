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
  int _playsPeriod = 0; // dense-feed period filter (§4b): 0 = all, else a period #

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
    final initial = widget.initialEvent;
    if (scores != null) {
      // A tennis match is one competition inside its parent tournament event —
      // re-resolve it there (by tournament id → match id) so the live set score
      // refreshes on poll. Ordinary events re-resolve by their own id.
      final tid = initial.tournamentId;
      if (tid != null) {
        for (final e in scores.events) {
          if (e.id != tid) continue;
          for (final c in e.competitions) {
            if (c.id == initial.id) return e.withCompetition(c);
          }
        }
      } else {
        for (final e in scores.events) {
          if (e.id == initial.id) return e;
        }
      }
    }
    return initial;
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
    final tabLabel = chips.isEmpty ? '' : chips[chipIndex];
    // The long play-by-play tabs virtualize (one sliver list of rows); every
    // other tab stays a boxed SliverList of cards. Skip _sections' work when the
    // feed path owns the body.
    final feed = _feedForTab(tabLabel, comp, summary);
    final sections = feed != null
        ? const <Widget>[]
        : _sections(context, event, comp, summary, chips, chipIndex);
    const bodyPadding = EdgeInsets.fromLTRB(
        T.pageMargin, T.gapFirstCard, T.pageMargin, T.scrollBottom);

    // Dense flat feeds (basketball/volleyball — archetype D) get a period filter
    // as a length control; sparse (soccer/hockey) and inning-grouped (baseball)
    // feeds don't (§4b / §9). Gate on density + a non-inning period unit.
    List<int> feedPeriods = const [];
    if (feed != null &&
        feed.events.length > 60 &&
        comp.periods.unit != 'inning') {
      feedPeriods = _feedPeriods(feed.events);
    }
    final showFilter = feedPeriods.length > 1;
    final activePeriod = feedPeriods.contains(_playsPeriod) ? _playsPeriod : 0;
    final feedEvents = feed == null
        ? const <MatchEvent>[]
        : (activePeriod == 0
            ? feed.events
            : feed.events.where((e) => e.period == activePeriod).toList());

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
          if (feed != null) ...[
            if (showFilter)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                      T.pageMargin, T.gapFirstCard, T.pageMargin, 0),
                  child: SegmentedControl(
                    items: [
                      'All',
                      for (final p in feedPeriods) _periodChip(comp, p),
                    ],
                    selected: activePeriod == 0
                        ? 0
                        : feedPeriods.indexOf(activePeriod) + 1,
                    onTap: (i) => setState(
                        () => _playsPeriod = i == 0 ? 0 : feedPeriods[i - 1]),
                  ),
                ),
              ),
            SliverPadding(
              padding: showFilter
                  ? const EdgeInsets.fromLTRB(
                      T.pageMargin, T.gapCard, T.pageMargin, T.scrollBottom)
                  : bodyPadding,
              sliver:
                  ActionFeedSliver(feedEvents, comp, tallyScore: feed.tally),
            ),
          ] else
            SliverPadding(
              padding: bodyPadding,
              sliver: SliverList.separated(
                itemCount: sections.length,
                separatorBuilder: (_, __) => const SizedBox(height: T.gapCard),
                itemBuilder: (_, i) => sections[i],
              ),
            ),
        ],
      ),
    );
  }

  /// The long play-by-play tabs (Plays / Timeline) render through the virtualized
  /// [ActionFeedSliver] instead of a boxed section, so a high-event game builds
  /// only the visible rows. Returns the feed's events (and whether to tally the
  /// running score), or null for tabs that stay boxed sections.
  ({List<MatchEvent> events, bool tally})? _feedForTab(
      String label, Competition comp, GameSummary? summary) {
    if (label == 'Timeline') {
      return (events: _matchTimeline(comp, summary), tally: _sport == 'soccer');
    }
    // Baseball's Plays tab is the grouped at-bat disclosure (design 9e), a boxed
    // section — not the flat virtualized feed — so it routes through _sections.
    if (label == 'Plays' && summary != null && summary.atBats.isEmpty) {
      final plays =
          summary.plays.isNotEmpty ? summary.plays : summary.scoringPlays;
      return (
        events: [for (final p in plays) MatchEvent.fromSummaryPlay(p)],
        tally: false,
      );
    }
    return null;
  }

  /// The distinct periods present in a feed, sorted — the axis of the §4b filter.
  List<int> _feedPeriods(List<MatchEvent> events) {
    final s = <int>{};
    for (final e in events) {
      if (e.period != null) s.add(e.period!);
    }
    return s.toList()..sort();
  }

  /// The filter chip label for a period, by the competition's period unit
  /// (Q1 / P2 / S3 …), OT past regulation — discriminator-driven, not sport name.
  String _periodChip(Competition comp, int p) {
    final reg = comp.periods.regulation;
    if (reg > 0 && p > reg) return p - reg == 1 ? 'OT' : 'OT${p - reg}';
    return switch (comp.periods.unit) {
      'quarter' => 'Q$p',
      'period' => 'P$p',
      'half' => 'H$p',
      'set' => 'S$p',
      _ => '$p',
    };
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
      // Golf (§7a): Leaderboard + a chip per played round (R1..Rn) for the
      // per-round sub-scores. Racing / one-off events keep the single chip.
      if (comp.scoreKind == 'toPar') {
        final rounds = _golfRoundCount(comp);
        if (rounds > 1) {
          return ['Leaderboard', for (var r = 1; r <= rounds; r++) 'R$r'];
        }
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
        (summary.scoringPlays.isNotEmpty ||
            summary.plays.isNotEmpty ||
            summary.atBats.isNotEmpty);
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
      final isGolf = session.scoreKind == 'toPar';
      // chipIndex 0 = Leaderboard (live TODAY column); 1..n = the R{n} chip.
      final golfRound = isGolf && !multiSession && chipIndex > 0 ? chipIndex : null;
      final golfLeader = isGolf ? _fieldLeader(session) : null;
      return [
        if (golf != null) _GolfMetaStrip(session, golf),
        FieldLeaderboard(
          session,
          maxRows: 25,
          round: golfRound,
          // racing shows the entrant's constructor; golf has none.
          showConstructor: !isGolf,
          // golf rows open the hole-by-hole scorecard; racing rows don't
          // (no per-driver endpoint worth the tap).
          onRowTap: isGolf
              ? (c) => openGolfScorecard(
                  context, widget.league, event.id, c,
                  season: season)
              : null,
        ),
        // §7a: the leader's hole-by-hole strip, lazy off the scorecard endpoint —
        // gives a golf fan's glance a shape (birdies/bogeys) the flat table can't.
        // Only on the Leaderboard view (a per-round chip is already round-scoped).
        if (golfLeader != null && golfRound == null)
          GolfLeaderStripCard(
              league: widget.league,
              eventId: event.id,
              leader: golfLeader,
              season: season,
              currentRound: _golfRoundCount(session)),
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
        return [_DrivesFeed(summary!.drives, comp)];
      case 'Timeline':
        // Soccer/rugby: the curated goal/card/sub event feed (design 9a). Renders
        // off the cheap scoreboard timeline immediately, upgrades to the worker's
        // structured feed (subs, assists) when /summary lands.
        return [
          ActionFeed(_matchTimeline(comp, summary), comp,
              tallyScore: _sport == 'soccer'),
        ];
      case 'Plays':
        // Baseball: the design-9e Scoring|All disclosure feed (at-bats grouping
        // into half-inning containers, pitch sequences folded behind a tap).
        if (summary!.atBats.isNotEmpty) {
          return [_BaseballPlaysFeed(summary, comp)];
        }
        // Every other sport's full play-by-play, through the SAME feed grammar
        // (design 9b/9c): grouped by period, scores lifted with the running total.
        final plays =
            summary.plays.isNotEmpty ? summary.plays : summary.scoringPlays;
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
        // Tennis drill-in: the core-competition context (round · court · draw),
        // and — for a finished match — the result note as the loud moment.
        final tennis = _tennisInfo(comp);
        final tennisContext =
            tennis != null && tennis.hasContext ? _TennisContextCard(tennis) : null;
        if (s.live) {
          final situation = situationCardFor(comp);
          final cheap = _cheapPanelFor(comp);
          final leadPlays = _leadPlays(summary);
          final crease = (summary?.cricketInnings.isNotEmpty ?? false)
              ? summary!.cricketInnings.last
              : null;
          // §6: the rich shots-on-goal total supersedes the thin goaltending
          // cheap panel — data-driven (a summary shots total + a cheap panel that
          // isn't the sport's own rich stat story, so soccer/basketball keep
          // theirs). The Now tab was otherwise barren for hockey.
          final shotsStat = _shotsStat(summary);
          final showShots = shotsStat != null && !(cheap?.overlapsRich ?? false);
          // The quiet SCORING card (§6c) supports a Now tab that would otherwise be
          // thin: hockey (shots-pressure card) and gridiron — a down&distance card +
          // win prob is two lonely cards when the situation is sparse (§5a). The
          // scoring data exists (the Drives tab proves it). Data-driven: a shots
          // total (hockey) or drives (gridiron), never a sport-name branch. Sports
          // with a rich Now feed of their own (basketball's lead tracker, the
          // baseball diamond) carry neither and are unaffected.
          final quietScoring = showShots || (summary?.drives.isNotEmpty ?? false);
          final scoringNow = quietScoring
              ? summary!.scoringPlays
                  .where((p) => p.scoring)
                  .toList()
                  .reversed
                  .toList()
              : const <SummaryPlay>[];
          return [
            if (situation != null) situation,
            if (tennisContext != null) tennisContext,
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
            // Match-stats pulse: hockey's §8 shots-pressure card when the summary
            // ships shots, else the cheap scoreboard panel straight off the wire.
            if (showShots)
              _ShotsPressureCard(comp: comp, shots: shotsStat)
            else if (cheap != null)
              _CheapStatsCard(comp: comp, panel: cheap),
            // The quiet scoring summary (design 6c) — hockey's Now was two lonely
            // cards without it.
            if (scoringNow.isNotEmpty) _ScoringSummaryCard(scoringNow),
            _TopPerformersCard(comp),
            if (summary != null && summary.lineups.isNotEmpty)
              _LineupsCard(summary.lineups),
            if (summary != null && summary.seasonSeries != null)
              _SeasonSeriesCard(summary.seasonSeries!),
          ].whereType<Widget>().toList();
        }
        if (s.isScheduled) {
          return [
            if (tennisContext != null) tennisContext,
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
        final shotsStat = _shotsStat(summary);
        final showShots = shotsStat != null && !(cheap?.overlapsRich ?? false);
        final timeline = _matchTimeline(comp, summary);
        final hasGoals = timeline.any((e) => e.isScoring);
        // Non-soccer condensed "who scored" log (soccer/rugby use the timeline
        // goals above): actual scores only, no cap — a >12-run game must not drop
        // its earliest runs. The feed already orders newest-first, and grouping
        // by half-inning (§3c) is the real volume control.
        final scores = summary == null
            ? const <SummaryPlay>[]
            : summary.scoringPlays.where((p) => p.scoring).toList();
        final recap = scores;
        return [
          if (tennisContext != null) tennisContext,
          // A finished tennis match's loud moment is its result note ("Korneeva
          // bt Shubladze 2-6 7-6 (7-2) 6-3") — the one calm sentence (§7).
          if (tennis?.resultLine != null)
            InvertedCard(label: 'Result', text: tennis!.resultLine!),
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
          if (showShots)
            _ShotsPressureCard(comp: comp, shots: shotsStat)
          else if (cheap != null)
            _CheapStatsCard(comp: comp, panel: cheap),
          if (comp.headline != null) _HeadlineCard(comp.headline!),
          _TopPerformersCard(comp),
          if (hasGoals)
            ActionFeed(timeline, comp,
                scoringOnly: true,
                tallyScore: _sport == 'soccer',
                label: 'Scoring')
          else if (recap.isNotEmpty)
            // Baseball (plays carry a half) groups into design-9b half-inning
            // cards; every other sport keeps the flat scoring feed.
            (recap.any((p) => p.half != null)
                ? _HalfInningFeed(recap, comp)
                : ActionFeed(
                    [for (final p in recap) MatchEvent.fromSummaryPlay(p)], comp,
                    scoringOnly: true, label: 'Scoring')),
          if (summary != null && summary.seasonSeries != null)
            _SeasonSeriesCard(summary.seasonSeries!),
          _VenueCard(event, comp: comp, summary: summary),
        ].whereType<Widget>().toList();
    }
  }

  /// The field-event leader — the competitor the leaderboard sorts to the top
  /// (lowest `order`). Drives the §7a golf hole strip.
  Competitor? _fieldLeader(Competition comp) {
    if (comp.competitors.isEmpty) return null;
    return comp.competitors.reduce((a, b) =>
        (a.order ?? 1 << 20) <= (b.order ?? 1 << 20) ? a : b);
  }

  /// How many golf rounds carry data (the highest round with holes played across
  /// the field) — the count of R{n} chips (§7a). 0 before anyone tees off.
  int _golfRoundCount(Competition comp) {
    var max = 0;
    for (final c in comp.competitors) {
      for (final p in c.periodScores) {
        if (p.holesPlayed != null && p.period > max) max = p.period;
      }
    }
    return max;
  }

  /// The rich summary's shots-on-goal team stat (hockey and kin) — the input to
  /// the §8 shots-pressure card. Null when the summary carries no such total.
  TeamStatRow? _shotsStat(GameSummary? summary) {
    if (summary == null) return null;
    for (final r in summary.teamStats) {
      final l = r.label.toLowerCase().trim();
      if (l == 'shots' || l == 'shots on goal' || l == 'sog') return r;
    }
    return null;
  }

  /// Scoring plays that carry a running score — the input to the §8 lead tracker.
  List<SummaryPlay> _leadPlays(GameSummary? summary) => (summary?.scoringPlays ??
          const <SummaryPlay>[])
      .where((p) => p.away != null && p.home != null)
      .toList();

  /// A combat card (MMA/boxing): athletes head-to-head with an undercard of
  /// sibling bouts — dispatched on data, never sport name. A tennis tournament
  /// is also many athlete-vs-athlete competitions, so it's explicitly excluded
  /// (it drills in per match instead); in practice a tennis match reaches detail
  /// already exploded to one competition, but this guards a stray whole-tournament
  /// event too.
  bool _isFightCard(SportEvent event, Competition comp) =>
      event.competitions.length > 1 &&
      !comp.isField &&
      comp.competitorKind == 'athlete' &&
      !event.isTournamentOfMatches;

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

  /// A set-based head-to-head individual match (tennis singles/doubles) — the
  /// discriminator for the rich core-competition drill-in, never a sport name.
  bool _isSetMatch(Competition comp) =>
      comp.periods.unit == 'set' && comp.competitorKind != 'team';

  /// The rich core-competition enrichment for a tennis match (round, court, draw
  /// type, result note), watched lazily. Null until it resolves, or on failure
  /// (offline mock / live 404) — the detail keeps its cheap set grid either way.
  TennisMatchInfo? _tennisInfo(Competition comp) {
    if (!_isSetMatch(comp)) return null;
    final ev = _event;
    final key = (
      league: widget.league,
      eventId: ev.tournamentId ?? ev.id,
      compId: comp.id,
    );
    return ref.watch(tennisMatchProvider(key)).valueOrNull;
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
      padding: const EdgeInsets.symmetric(vertical: 9),
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

/// The tennis match's identity strip, from the core-competition drill-in: the
/// draw type as the card label with the round + court beneath. Court is the
/// datum the cheap scoreboard can't give; the whole card is best-effort and
/// simply absent when the fetch hasn't landed.
class _TennisContextCard extends StatelessWidget {
  final TennisMatchInfo info;
  const _TennisContextCard(this.info);

  @override
  Widget build(BuildContext context) {
    final ctx = info.contextLine;
    return V2Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CardLabel(info.drawType?.toUpperCase() ?? 'MATCH'),
        if (ctx != null) ...[
          const SizedBox(height: 6),
          Text(ctx, style: T.caption),
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
  static const _minCell = 18.0; // inning-cell floor before the pane scrolls
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

    // Fixed-width cell (R/H/E totals + their headers). The innings use
    // [cellText] inside a flex/scroll slot instead, so the nine columns fill the
    // card rather than sitting fixed-width with dead space to the right.
    Widget cell(String s, double w, TextStyle st) =>
        SizedBox(width: w, child: Text(s, textAlign: TextAlign.center, style: st));
    Widget cellText(String s, TextStyle st) => Text(s,
        textAlign: TextAlign.center, maxLines: 1, style: st);

    // §10 semantic inning cell: unplayed → ghost '–', a scoring inning → white,
    // a zero → dim.
    Widget inningCell(Competitor? c, int i) {
      final v = inn(c, i);
      final played = v.isNotEmpty;
      final scoring = played && v != '0';
      return cellText(
          played ? v : '–',
          TextStyle(
              fontSize: 13,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: !played ? T.ghost : (scoring ? T.text : T.textDim)));
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

    // The innings fill the width at nine (each cell 1fr); extras first shrink the
    // cells toward [_minCell], then the innings pane *alone* scrolls while the
    // label and R/H/E columns stay pinned (design 10d).
    return V2Card(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: LayoutBuilder(builder: (context, cons) {
        const gutter = 8.0;
        final avail = cons.maxWidth - (_labelW + gutter + _rW + _heW * 2);
        final needScroll = avail < _minCell * n;

        Widget slot(Widget child) => needScroll
            ? SizedBox(width: _minCell, child: child)
            : Expanded(child: child);

        Widget inningsBand(bool header, Widget Function(int) cellFor) => band(
              Row(
                mainAxisSize:
                    needScroll ? MainAxisSize.min : MainAxisSize.max,
                children: [for (final i in innings) slot(cellFor(i))],
              ),
              header: header,
            );

        final inningsBands = Column(children: [
          inningsBand(true, (i) => cellText('$i', headerStyle)),
          for (final c in [away, home])
            inningsBand(false, (i) => inningCell(c, i)),
        ]);

        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: _labelW, child: labelCol),
          Expanded(
            child: needScroll
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal, child: inningsBands)
                : inningsBands,
          ),
          const SizedBox(width: gutter),
          totalsCol,
        ]);
      }),
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

/// The §8/6c "SHOTS ON GOAL" pressure card — hockey's Now/Recap headline read.
/// Built from the rich /summary "Shots" team stat (the cheap scoreboard carries
/// only goaltending), with the team save % as a quiet footer under a hairline.
/// Data-driven: it renders wherever a summary ships a shots-on-goal total, so
/// lacrosse/water polo would get it too — no sport-name branch. Supersedes the
/// standalone goaltending panel on Now (§1 already retired the mirrored gauge).
class _ShotsPressureCard extends StatelessWidget {
  final Competition comp;
  final TeamStatRow shots;
  const _ShotsPressureCard({required this.comp, required this.shots});

  @override
  Widget build(BuildContext context) {
    final away = comp.away, home = comp.home;
    if (away == null || home == null) return const SizedBox.shrink();
    final a = statNum(shots.away) ?? 0;
    final h = statNum(shots.home) ?? 0;
    final peak = math.max(a, h);

    Widget teamRow(Competitor c, num v) {
      final frac = peak <= 0 ? 0.0 : (v / peak).clamp(0.0, 1.0);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          SizedBox(
              width: 36,
              child:
                  Text(c.label, style: T.statLineStrong.copyWith(fontSize: 15))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: Stack(children: [
                Container(height: 10, color: T.track),
                FractionallySizedBox(
                  widthFactor: frac,
                  child: Container(height: 10, color: teamColor(c)),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
              width: 30,
              child: Text('${v.toInt()}',
                  textAlign: TextAlign.right,
                  style: T.statLineStrong.copyWith(fontSize: 16))),
        ]),
      );
    }

    // Goalie save % rides the cheap scoreboard (not teamStats) — the footer read.
    final svA = away.stats['SV%'], svH = home.stats['SV%'];
    final hasSv =
        (svA != null && svA.isNotEmpty) || (svH != null && svH.isNotEmpty);

    return V2Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const CardLabel('Shots on goal'),
        const SizedBox(height: 10),
        teamRow(away, a),
        teamRow(home, h),
        if (hasSv)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.only(top: 10),
            decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: T.divider))),
            child: Row(children: [
              if (svA != null && svA.isNotEmpty)
                Text('${away.label} $svA SV%', style: T.caption),
              const Spacer(),
              if (svH != null && svH.isNotEmpty)
                Text('${home.label} $svH SV%', style: T.caption),
            ]),
          ),
      ]),
    );
  }
}

/// The design 6c "SCORING" card — quiet rows for the Now scoring summary: a faint
/// period·clock rail and the play prose, no markers or washes (the score block
/// already carries the running total). Newest first, data-driven off scoring
/// plays. The full grammar ([ActionFeed]) is the Timeline/Recap treatment.
class _ScoringSummaryCard extends StatelessWidget {
  final List<SummaryPlay> plays; // newest-first
  const _ScoringSummaryCard(this.plays);

  @override
  Widget build(BuildContext context) {
    if (plays.isEmpty) return const SizedBox.shrink();
    return V2Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const CardLabel('Scoring'),
        const SizedBox(height: 8),
        for (final p in plays)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 44,
                child: Text(
                    [p.periodLabel, p.clock]
                        .whereType<String>()
                        .where((s) => s.isNotEmpty)
                        .join(' ')
                        .toUpperCase(),
                    style: const TextStyle(
                        fontFamily: 'BarlowCondensed',
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: T.textFaint)),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(p.text,
                    style: const TextStyle(
                        fontSize: 13, height: 1.35, color: T.textBody)),
              ),
            ]),
          ),
      ]),
    );
  }
}

/// Design 9b — baseball scoring plays as archetype-B grouped episodes: one card
/// per half-inning (newest first), a both-sides header (`BOTTOM 6 · CUBS` |
/// running score `MIL 4 · CHC 5`) and a team-spine row per scoring play with the
/// running score (scoring team first, latest white). Keyed on (period, half) so a
/// 4-run bottom no longer merges into the top of the same inning (§3c). The §3e
/// all-plays toggle will later mount its disclosure rows on these same containers.
class _HalfInningFeed extends StatelessWidget {
  final List<SummaryPlay> plays; // scoring plays, chronological, carrying period + half
  final Competition comp;
  const _HalfInningFeed(this.plays, this.comp);

  @override
  Widget build(BuildContext context) {
    if (plays.isEmpty) return const SizedBox.shrink();
    final groups = <String, List<SummaryPlay>>{};
    final order = <String>[];
    for (final p in plays) {
      final key = '${p.period ?? 0}:${p.half ?? ''}';
      (groups[key] ??= (() {
        order.add(key);
        return <SummaryPlay>[];
      })())
          .add(p);
    }
    final latest = plays.last; // the freshest scoring play overall
    final ordered = order.reversed.toList(); // newest half-inning first
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < ordered.length; i++) ...[
          if (i > 0) const SizedBox(height: T.gapCard),
          _container(groups[ordered[i]]!, latest),
        ],
      ],
    );
  }

  Widget _container(List<SummaryPlay> rows, SummaryPlay latest) {
    final head = rows.first;
    final inning = head.period ?? 0;
    // top of an inning = away bats, bottom = home bats.
    final batting = head.half == 'top' ? comp.away : comp.home;
    final label = '${head.half == 'bottom' ? 'BOTTOM' : 'TOP'} $inning'
        '${batting?.label.isNotEmpty == true ? ' · ${batting!.label}' : ''}';
    final headerScore = _headerScore(rows.last);
    return V2Card(
      padding: T.padCompact,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label, style: T.cardLabelFaint)),
          if (headerScore != null) Text(headerScore, style: T.cardLabelFaint),
        ]),
        for (var i = 0; i < rows.length; i++) ...[
          if (i == 0)
            const SizedBox(height: 12)
          else
            Container(
                height: 1,
                color: T.divider,
                margin: const EdgeInsets.symmetric(vertical: 10)),
          _row(rows[i], identical(rows[i], latest)),
        ],
      ]),
    );
  }

  Widget _row(SummaryPlay p, bool bright) {
    final color = p.side == 'home'
        ? teamColor(comp.home)
        : (p.side == 'away' ? teamColor(comp.away) : T.textFaint);
    final score = _rowScore(p);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
            width: 5,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(p.text,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                      color: T.text)),
            ),
          ),
        ),
        if (score != null)
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Center(child: RunningScore(score, bright: bright)),
          ),
      ]),
    );
  }

  // Row running score, scoring team first (archetype B: the number that changed
  // leads).
  String? _rowScore(SummaryPlay p) {
    if (p.away == null || p.home == null) return null;
    final a = _fmt(p.away!), h = _fmt(p.home!);
    return p.side == 'home' ? '$h–$a' : '$a–$h';
  }

  // Container header running score: both teams with abbrs, away then home.
  String? _headerScore(SummaryPlay p) {
    if (p.away == null || p.home == null) return null;
    final aw = comp.away?.label ?? '', hm = comp.home?.label ?? '';
    return '$aw ${_fmt(p.away!)} · $hm ${_fmt(p.home!)}';
  }

  String _fmt(num n) => n == n.roundToDouble() ? n.toInt().toString() : '$n';
}

/// The baseball Plays tab (design 9e): ONE tab with a Scoring|All toggle. Scoring
/// is the design-9b half-inning scoring feed (=3c). All groups EVERY at-bat into
/// the same half-inning containers as condensed rows — a 4px team tick, the batter
/// + outcome, the pitch count and a chevron — that tap to expand the pitch sequence
/// (18px muted B/S/F/• dots §2 + description + velocity, in a track inset behind a
/// rail). The live at-bat sits pre-expanded, its current count where the pitch
/// count goes. Containers show the running score (complete) or `N OUT` (live).
class _BaseballPlaysFeed extends StatefulWidget {
  final GameSummary summary;
  final Competition comp;
  const _BaseballPlaysFeed(this.summary, this.comp);
  @override
  State<_BaseballPlaysFeed> createState() => _BaseballPlaysFeedState();
}

class _BaseballPlaysFeedState extends State<_BaseballPlaysFeed> {
  int _view = 0; // 0 = Scoring, 1 = All
  final _expanded = <int>{}; // at-bat indices expanded in the All view

  @override
  void initState() {
    super.initState();
    // The live at-bat opens pre-expanded (design 9e).
    final ab = widget.summary.atBats;
    for (var i = 0; i < ab.length; i++) {
      if (ab[i].live) _expanded.add(i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scoring = widget.summary.scoringPlays.where((p) => p.scoring).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: T.gapCard),
        child: SegmentedControl(
          items: const ['Scoring', 'All'],
          selected: _view,
          onTap: (i) => setState(() => _view = i),
        ),
      ),
      if (_view == 0)
        scoring.isEmpty
            ? _emptyCard('No scoring plays yet.')
            : _HalfInningFeed(scoring, widget.comp)
      else
        _allView(),
    ]);
  }

  Widget _emptyCard(String msg) => V2Card(
      child:
          Text(msg, style: const TextStyle(fontSize: 13, color: T.textFaint)));

  Widget _allView() {
    final ab = widget.summary.atBats;
    if (ab.isEmpty) return _emptyCard('No plays yet.');
    final groups = <String, List<int>>{};
    final order = <String>[];
    for (var i = 0; i < ab.length; i++) {
      final key = '${ab[i].period ?? 0}:${ab[i].half ?? ''}';
      (groups[key] ??= (() {
        order.add(key);
        return <int>[];
      })())
          .add(i);
    }
    final ordered = order.reversed.toList(); // newest half-inning first
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var gi = 0; gi < ordered.length; gi++) ...[
        if (gi > 0) const SizedBox(height: T.gapCard),
        _container(groups[ordered[gi]]!),
      ],
    ]);
  }

  Widget _container(List<int> idxs) {
    final ab = widget.summary.atBats;
    final head = ab[idxs.first];
    final inning = head.period ?? 0;
    // top of an inning = away bats, bottom = home bats.
    final batting = head.half == 'top' ? widget.comp.away : widget.comp.home;
    final label = '${head.half == 'bottom' ? 'BOTTOM' : 'TOP'} $inning'
        '${batting?.label.isNotEmpty == true ? ' · ${batting!.label}' : ''}';
    final state = _containerState(idxs);
    return V2Card(
      padding: T.padCompact,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label, style: T.cardLabelFaint)),
          if (state != null) Text(state, style: T.cardLabelFaint),
        ]),
        for (var j = 0; j < idxs.length; j++) ...[
          if (j == 0)
            const SizedBox(height: 12)
          else
            Container(
                height: 1,
                color: T.track,
                margin: const EdgeInsets.symmetric(vertical: 8)),
          _atBatRow(idxs[j]),
        ],
      ]),
    );
  }

  // Container state (design 9e): the running score for a completed inning (like
  // the Scoring view), or 'N OUT' for the live inning (state over score).
  String? _containerState(List<int> idxs) {
    final ab = widget.summary.atBats;
    final last = ab[idxs.last];
    if (last.live) return last.outs == null ? null : '${last.outs} OUT';
    if (last.away == null || last.home == null) return null;
    final aw = widget.comp.away?.label ?? '', hm = widget.comp.home?.label ?? '';
    return '$aw ${_fmtN(last.away!)} · $hm ${_fmtN(last.home!)}';
  }

  Widget _atBatRow(int i) {
    final a = widget.summary.atBats[i];
    final expanded = _expanded.contains(i);
    final color = a.side == 'home'
        ? teamColor(widget.comp.home)
        : (a.side == 'away' ? teamColor(widget.comp.away) : T.textFaint);
    final canExpand = a.pitches.isNotEmpty;
    // Actor + outcome. Live: the batter's name (no result yet); completed: the
    // result text with its leading last name bolded.
    final String actor, rest;
    if (a.live) {
      actor = a.batter ?? '';
      rest = '';
    } else {
      final sp = a.text.indexOf(' ');
      actor = sp < 0 ? a.text : a.text.substring(0, sp);
      rest = sp < 0 ? '' : a.text.substring(sp + 1);
    }
    // Live: the current count where the pitch count would be (design 9e).
    final count = a.live
        ? (a.balls != null && a.strikes != null
            ? '${a.balls}–${a.strikes}'
            : null)
        : (canExpand ? '${a.pitches.length} P' : null);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InkWell(
        onTap: canExpand
            ? () => setState(
                () => expanded ? _expanded.remove(i) : _expanded.add(i))
            : null,
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Container(
              width: 4,
              height: 16,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: actor,
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: T.text)),
                if (rest.isNotEmpty)
                  TextSpan(
                      text: ' $rest',
                      style: const TextStyle(
                          fontSize: 13.5, height: 1.3, color: T.textDim)),
              ]),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (count != null)
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Text(count,
                  style: const TextStyle(
                      fontFamily: 'BarlowCondensed',
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      fontFeatures: [FontFeature.tabularFigures()],
                      color: T.textFaint)),
            ),
          if (canExpand)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18, color: T.textFaint),
            ),
        ]),
      ),
      if (expanded && canExpand) _pitchSequence(a),
    ]);
  }

  Widget _pitchSequence(AtBat a) => Container(
        margin: const EdgeInsets.only(top: 8, bottom: 2),
        padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
        decoration: BoxDecoration(
            color: T.track, borderRadius: BorderRadius.circular(14)),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 1, color: T.border), // the disclosure rail
            const SizedBox(width: 12),
            Expanded(
              child: Column(children: [
                for (var p = 0; p < a.pitches.length; p++)
                  Padding(
                    padding: EdgeInsets.only(top: p == 0 ? 0 : 8),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _pitchDot(a.pitches[p]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(a.pitches[p].text,
                                style: const TextStyle(
                                    fontSize: 12.5, color: T.textDim)),
                          ),
                          if (a.pitches[p].velo != null)
                            Text('${_fmtN(a.pitches[p].velo!)} MPH',
                                style: const TextStyle(
                                    fontFamily: 'BarlowCondensed',
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                    fontFeatures: [FontFeature.tabularFigures()],
                                    color: T.textFaint)),
                        ]),
                  ),
              ]),
            ),
          ]),
        ),
      );

  Widget _pitchDot(Pitch p) {
    final (Color fill, Color glyph, String letter) = switch (p.r) {
      'ball' => (T.mutedGood, T.mutedGoodGlyph, 'B'),
      'strike' => (T.mutedBad, T.mutedBadGlyph, 'S'),
      'foul' => (T.mutedNeutral, T.mutedNeutralGlyph, 'F'),
      _ => (T.ghost, T.textBody, '•'), // in play / other — neutral contact
    };
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
      child: Text(letter,
          style: TextStyle(
              fontFamily: 'BarlowCondensed',
              fontWeight: FontWeight.w700,
              fontSize: 9,
              color: glyph)),
    );
  }

  String _fmtN(num n) => n == n.roundToDouble() ? n.toInt().toString() : '$n';
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
      padding: T.padTable, // §10 dense table: tighter sides, tables need width
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
          // Every row (no take(12) cap — that hid late substitutes outright).
          for (final r in team.rows) _boxRow(r, cols),
        ],
      ]),
    );
  }

  /// One box row. A substitute (`starter == false`, baseball only) is indented
  /// under the man it replaced, prefixed with ESPN's lineup letter marker (a-, b-)
  /// or a ↳ glyph, and carries its lineup note as an 11px footnote (§3d / §10).
  Widget _boxRow(BoxRow r, List<String> cols) {
    final sub = r.starter == false;
    final marker = _subMarker(r);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: T.divider))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (sub)
            SizedBox(
                width: 16,
                child: Text(marker,
                    style: const TextStyle(fontSize: 12, color: T.textFaint))),
          Expanded(
            child: Text.rich(
              TextSpan(text: r.name, children: [
                if (r.pos != null)
                  TextSpan(
                      text: '  ${r.pos}',
                      style: const TextStyle(fontSize: 11, color: T.textFaint)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.listText
                  .copyWith(fontSize: 13, color: sub ? T.textDim : T.text),
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
        if (r.note != null)
          Padding(
            padding: EdgeInsets.only(left: sub ? 16 : 0, top: 3),
            child: Text(r.note!, style: T.captionFaint),
          ),
      ]),
    );
  }

  /// The lineup letter marker ESPN embeds in the note ('a-walked for…' → 'a-'),
  /// else a ↳ glyph for an unannotated substitute.
  String _subMarker(BoxRow r) {
    final m =
        r.note != null ? RegExp(r'^([A-Za-z])-').firstMatch(r.note!) : null;
    return m != null ? '${m.group(1)}-' : '↳';
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
            // §6 badge geometry (2×6 pad, r4), with a soft gold-tinted fill.
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: T.gold.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(4),
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
/// The gridiron Drives tab (design 9c): ONE tab with a Scoring|All toggle. Drives
/// group into per-quarter cards (newest quarter first). The Scoring view shows the
/// scoring drives — a score-type chip (TD/FG), the scoring play, the drive stat
/// strip (6 PLAYS · 75 YDS · 2:44) and the running score (scoring team first). The
/// All view lists every drive as a condensed row that taps to expand its plays in
/// a track inset — the §3e/9e disclosure move at drive scale (§5b).
class _DrivesFeed extends StatefulWidget {
  final List<DriveSummary> drives; // chronological
  final Competition comp;
  const _DrivesFeed(this.drives, this.comp);
  @override
  State<_DrivesFeed> createState() => _DrivesFeedState();
}

class _DrivesFeedState extends State<_DrivesFeed> {
  int _view = 0; // 0 = Scoring, 1 = All
  final _expanded = <int>{};

  @override
  Widget build(BuildContext context) {
    final drives = widget.drives;
    final byQ = <int, List<int>>{};
    for (var i = 0; i < drives.length; i++) {
      (byQ[drives[i].period ?? 0] ??= <int>[]).add(i);
    }
    final quarters = byQ.keys.toList()..sort((a, b) => b.compareTo(a));
    final latest = drives.length - 1;

    final cards = <Widget>[];
    for (final q in quarters) {
      final idxs = _view == 0
          ? byQ[q]!.where((i) => drives[i].isScore).toList()
          : byQ[q]!;
      if (idxs.isEmpty) continue;
      cards.add(_quarterCard(q, idxs, latest));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: T.gapCard),
        child: SegmentedControl(
          items: const ['Scoring', 'All'],
          selected: _view,
          onTap: (i) => setState(() => _view = i),
        ),
      ),
      if (cards.isEmpty)
        V2Card(
          child: Text(_view == 0 ? 'No scoring drives yet.' : 'No drives yet.',
              style: const TextStyle(fontSize: 13, color: T.textFaint)),
        )
      else
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(height: T.gapCard),
          cards[i],
        ],
    ]);
  }

  Widget _quarterCard(int q, List<int> idxs, int latest) => V2Card(
        padding: T.padCompact,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_quarterLabel(q), style: T.cardLabelFaint),
          const SizedBox(height: 12),
          for (var j = 0; j < idxs.length; j++) ...[
            if (j > 0)
              Container(
                  height: 1,
                  color: T.divider,
                  margin: const EdgeInsets.symmetric(vertical: 12)),
            _view == 0
                ? _scoringRow(idxs[j], idxs[j] == latest)
                : _allRow(idxs[j], idxs[j] == latest),
          ],
        ]),
      );

  Color _sideColor(DriveSummary d) => d.side == 'home'
      ? teamColor(widget.comp.home)
      : (d.side == 'away' ? teamColor(widget.comp.away) : T.textFaint);

  Widget _scoringRow(int i, bool bright) {
    final d = widget.drives[i];
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _scoreChip(d),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_scoringTitle(d),
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                  color: T.text)),
          if (_statStrip(d) != null)
            Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_statStrip(d)!, style: T.captionFaint)),
        ]),
      ),
      if (_runningScore(d) != null)
        Padding(
            padding: const EdgeInsets.only(left: 10),
            child: RunningScore(_runningScore(d)!, bright: bright)),
    ]);
  }

  Widget _allRow(int i, bool bright) {
    final d = widget.drives[i];
    final expanded = _expanded.contains(i);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InkWell(
        onTap: d.plays.isEmpty
            ? null
            : () => setState(
                () => expanded ? _expanded.remove(i) : _expanded.add(i)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          d.isScore ? _scoreChip(d) : _resultLabel(d),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d.teamAbbr ?? '',
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: d.isScore ? T.text : T.textDim)),
              if (_statStrip(d) != null)
                Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(_statStrip(d)!, style: T.captionFaint)),
            ]),
          ),
          if (d.isScore && _runningScore(d) != null)
            Padding(
                padding: const EdgeInsets.only(left: 10),
                child: RunningScore(_runningScore(d)!, bright: bright)),
          if (d.plays.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18, color: T.textFaint),
            ),
        ]),
      ),
      if (expanded) _drivePlays(d),
    ]);
  }

  Widget _drivePlays(DriveSummary d) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
            color: T.track, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final p in d.plays)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                    width: 42,
                    child: Text(p.clock ?? '',
                        style: const TextStyle(
                            fontFamily: 'BarlowCondensed',
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: T.textFaint))),
                const SizedBox(width: 4),
                Expanded(
                    child: Text(p.text,
                        style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: p.scoring ? T.text : T.textDim))),
              ]),
            ),
        ]),
      );

  Widget _scoreChip(DriveSummary d) {
    final c = _sideColor(d);
    return Container(
      width: 36,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: T.border)),
      child: Text(_chipLabel(d.result),
          style: const TextStyle(
              fontFamily: 'BarlowCondensed',
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: T.text)),
    );
  }

  Widget _resultLabel(DriveSummary d) => SizedBox(
        width: 36,
        child: Text(_chipLabel(d.result),
            textAlign: TextAlign.center,
            style: T.statLine.copyWith(fontSize: 12, color: T.textFaint)),
      );

  String _chipLabel(String? result) {
    final r = (result ?? '').toLowerCase();
    if (r.contains('touchdown')) return 'TD';
    if (r.contains('field goal')) return 'FG';
    if (r.contains('safety')) return 'SAF';
    if (r.contains('interception')) return 'INT';
    if (r.contains('fumble')) return 'FUM';
    if (r.contains('downs')) return 'DWN';
    if (r.contains('punt')) return 'PUNT';
    if (r.contains('missed')) return 'MISS';
    if (r.contains('end of')) return 'END';
    final w = (result ?? '').split(' ').first.toUpperCase();
    return w.length > 4 ? w.substring(0, 4) : w;
  }

  String? _statStrip(DriveSummary d) {
    final parts = <String>[
      if (d.playCount != null) '${d.playCount} PLAYS',
      if (d.yards != null) '${d.yards} YDS',
      if (d.timeElapsed != null) d.timeElapsed!,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  String? _runningScore(DriveSummary d) {
    if (d.awayScore == null || d.homeScore == null) return null;
    final a = _fmt(d.awayScore!), h = _fmt(d.homeScore!);
    return d.side == 'home' ? '$h–$a' : '$a–$h';
  }

  String _scoringTitle(DriveSummary d) {
    for (final p in d.plays.reversed) {
      if (p.scoring) return p.text;
    }
    return d.plays.isNotEmpty
        ? d.plays.last.text
        : (d.description ?? d.result ?? '');
  }

  String _fmt(num n) => n == n.roundToDouble() ? n.toInt().toString() : '$n';

  String _quarterLabel(int q) {
    final reg = widget.comp.periods.regulation;
    if (reg > 0 && q > reg) return q - reg == 1 ? 'OVERTIME' : 'OT${q - reg}';
    return switch (q) {
      1 => '1ST QUARTER',
      2 => '2ND QUARTER',
      3 => '3RD QUARTER',
      4 => '4TH QUARTER',
      _ => 'QUARTER $q',
    };
  }
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
      padding: T.padTable, // §10 dense table: tighter sides, tables need width
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
