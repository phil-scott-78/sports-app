import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../config.dart';
import '../data/fastcast_log.dart';
import '../inning_recap.dart';
import '../models.dart';
import '../momentum.dart';
import '../providers.dart';
import '../theme.dart';
import '../util.dart';
import 'follow_sheet.dart';
import 'golf_scorecard_page.dart';
import 'match_events.dart';
import 'player_page.dart';
import 'poll.dart';
import 'situations.dart';
import 'soccer_live.dart';
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
/// Baseball's derived last-play prose (turn 8): the narrative text, with the
/// pitch name + velocity appended for a mid-at-bat pitch when captured
/// ('Strike 2 Foul — Cutter, 89 mph'). A challenged call appends its ABS
/// outcome ('· call overturned' / '· challenge upheld') — the loud moment IS
/// where the challenge drama lands.
String _lastPlayProse(BaseballLastPlay lp) {
  final extra = [
    if (lp.type != null) lp.type!,
    if (lp.velo != null) '${lp.velo} mph',
  ].join(', ');
  final base = extra.isEmpty ? lp.text : '${lp.text} — $extra';
  return switch (lp.challenge) {
    'overturned' => '$base · call overturned',
    'upheld' => '$base · challenge upheld',
    _ => base,
  };
}

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

  // §4a: stable feed projections so the play list handed to [ActionFeedSliver]
  // keeps its *identity* across setState-only rebuilds (chip / period-filter
  // taps, polls that return the same summary) — that identity is the key the
  // feed's flatten memo (match_events.dart) hits, so a whole game's ~800 plays
  // aren't re-projected and re-sorted every frame. Rebuilt only when the source
  // list identity changes (a fresh /summary).
  List<SummaryPlay>? _playsSrc;
  List<MatchEvent>? _playsEvents;
  List<MatchEvent>? _filterSrc;
  int _filterPeriod = -1;
  List<MatchEvent>? _filterEvents;

  /// Last logged situation-source line (see the 'act sit-source' log) — dedupes
  /// the ~1/s rebuild spam down to actual changes.
  String? _lastSitSource;

  /// The summary's plays projected to [MatchEvent], memoized on the source
  /// list's identity so unrelated rebuilds reuse the projection.
  List<MatchEvent> _projectPlays(List<SummaryPlay> plays) {
    if (!identical(plays, _playsSrc) || _playsEvents == null) {
      _playsSrc = plays;
      _playsEvents = [for (final p in plays) MatchEvent.fromSummaryPlay(p)];
    }
    return _playsEvents!;
  }

  /// The feed narrowed to a single period (the §4b length control), memoized on
  /// (source identity, period) so a stable identity flows to the flatten memo.
  List<MatchEvent> _filterFeed(List<MatchEvent> events, int period) {
    if (period == 0) return events;
    if (identical(events, _filterSrc) &&
        period == _filterPeriod &&
        _filterEvents != null) {
      return _filterEvents!;
    }
    _filterSrc = events;
    _filterPeriod = period;
    return _filterEvents = events.where((e) => e.period == period).toList();
  }

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

  /// The §2.9 tab shape for this event, by DATA PRESENCE (never sport name):
  /// a circuit join id → Circuit; else a stadium venue join id → Venue; neither
  /// → none. Delegates to the pure [venueTabKind] so the branch is unit-testable.
  VenueTabKind _venueTab(SportEvent event, Competition comp) {
    final (venueId, circuitId) = _venueTabIds(event, comp);
    return venueTabKind(venueId: venueId, circuitId: circuitId);
  }

  /// The (venueId, circuitId) join ids the Venue/Circuit tab needs. Sourced from
  /// the canonical event: `competitions[].venue.id` → `event.venue?.id` (the CORE
  /// venues/{id} join) and `events[].circuit.id` → `event.circuit?.id` (the CORE
  /// circuits/{id} join). Either may be null (then [venueTabKind] hides the tab).
  (String?, String?) _venueTabIds(SportEvent event, Competition comp) {
    return (event.venue?.id, event.circuit?.id);
  }

  @override
  void dispose() {
    detachPoll();
    super.dispose();
  }

  SportEvent get _event {
    final scores = ref.read(mergedLeagueScoresProvider(_scoresKey)).valueOrNull;
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
    if (comp.status.live) {
      // Demote to reconciliation when BOTH push tracks are healthy: the gp
      // stream feeds the summary and the event stream feeds the score header
      // (via mergedLeagueScoresProvider) — the poll is only the safety net.
      if (_pushEligible) {
        final slate = ref.read(liveSlateProvider(widget.league));
        final sum = ref.read(liveSummaryProvider(_summaryKey));
        if (slate.hasValue && !slate.hasError && sum.hasValue && !sum.hasError) {
          return AppConfig.refreshReconcile;
        }
      }
      return const Duration(seconds: 20);
    }
    if (comp.status.isScheduled && kickoffSoon(_event.start)) {
      return AppConfig.refreshNearKickoff;
    }
    if (comp.status.ended) return null; // finals don't change
    return AppConfig.refreshIdle;
  }

  /// FastCast Track 1 gate: push-feed the summary only while the game is LIVE
  /// on a fastcast-served league (registry capability, ESPN-direct only). The
  /// scoreboard poll flips this off when the game ends, which tears down the
  /// topic subscription via autoDispose.
  bool get _pushEligible {
    final comp = _event.main;
    return comp != null &&
        comp.status.live &&
        ref.read(apiProvider).liveSummarySupported(widget.league);
  }

  /// The match-feed provider key (soccer core plays): the competition's team
  /// ids ride along because core plays tag teams by $ref only.
  MatchFeedKey _matchFeedKey(SportEvent event, Competition comp) => (
        league: widget.league,
        eventId: event.id,
        compId: comp.id,
        homeId: comp.competitorByHome('home')?.id,
        awayId: comp.competitorByHome('away')?.id,
      );

  @override
  void onPoll() {
    ref.invalidate(leagueScoresProvider(_scoresKey));
    // The soccer match feed re-polls with the page (its immutable pages are
    // cached in Api; a steady-state tick costs one tail request). Live only —
    // a final's feed never changes again.
    final comp = _event.main;
    if (comp != null && comp.status.live && !comp.isField) {
      ref.invalidate(matchFeedProvider(_matchFeedKey(_event, comp)));
    }
    // While the FastCast stream is healthy (has data, no error) the summary is
    // push-fed — skip the 20s re-fetch entirely; polling is only the fallback.
    if (_pushEligible) {
      final push = ref.read(liveSummaryProvider(_summaryKey));
      if (push.hasValue && !push.hasError) {
        FcLog.log('act', 'detail poll: summary push healthy — skip /summary re-fetch');
        return;
      }
      FcLog.log('act', 'detail poll: summary push not healthy — invalidating /summary');
    }
    ref.invalidate(summaryProvider(_summaryKey));
  }

  @override
  Widget build(BuildContext context) {
    // The MERGED slate: poll rounds + push overlay emissions + push-health
    // transitions all land here (repace keeps the running timer when the
    // cadence is unchanged, so ~1/s push rebuilds don't starve reconciliation).
    ref.listen(mergedLeagueScoresProvider(_scoresKey), (_, __) => repace());
    ref.watch(mergedLeagueScoresProvider(_scoresKey));
    if (_pushEligible) {
      // Summary-push health changes the poll cadence too (see pollInterval).
      ref.listen(liveSummaryProvider(_summaryKey), (_, __) => repace());
    }
    // Push replaces poll while healthy: a pushed summary short-circuits the
    // `??` so [summaryProvider] isn't even watched (autoDispose then drops its
    // fetch); any push gap — still connecting, topic 404, socket lost — falls
    // back to the polled summary silently.
    final push =
        _pushEligible ? ref.watch(liveSummaryProvider(_summaryKey)) : null;
    final pushed =
        (push != null && push.hasValue && !push.hasError) ? push.valueOrNull : null;
    final summary =
        pushed ?? ref.watch(summaryProvider(_summaryKey)).valueOrNull;

    final event = _event;
    final comp = event.main;
    if (comp == null) {
      return const Scaffold(body: Center(child: Text('No competition data')));
    }

    // The soccer touch-by-touch match feed (capability hasMatchFeed — Api
    // no-ops every other league without a fetch): the live-pitch / shot-map /
    // momentum source. Not fetched pre-game (empty until kickoff).
    MatchFeed? matchFeed;
    if (!comp.isField && !comp.status.isScheduled) {
      matchFeed = ref
          .watch(matchFeedProvider(_matchFeedKey(event, comp)))
          .valueOrNull;
    }

    final chips = _chipLabels(event, comp, summary, matchFeed);
    final chipIndex = _chip.clamp(0, chips.length - 1);
    final tabLabel = chips.isEmpty ? '' : chips[chipIndex];
    // The long play-by-play tabs virtualize (one sliver list of rows); every
    // other tab stays a boxed SliverList of cards. Skip _sections' work when the
    // feed path owns the body.
    final feed = _feedForTab(tabLabel, comp, summary);
    final sections = feed != null
        ? const <Widget>[]
        : _sections(context, event, comp, summary, chips, chipIndex, matchFeed);
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
    final feedEvents =
        feed == null ? const <MatchEvent>[] : _filterFeed(feed.events, activePeriod);

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
              league: widget.league,
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
      return (events: _projectPlays(plays), tally: false);
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

  /// An innings sport (baseball and kin) — the discriminator for the reorganized
  /// three-tab detail (Now/Recap · Box · Plays) where the venue/series/injury
  /// story lives ON the first page instead of behind extra chips. Data presence
  /// (the period unit), never a sport name.
  bool _isInnings(Competition comp) => comp.periods.unit == 'inning';

  /// The chip labels, with the §2.9 Venue/Circuit tab appended when the event
  /// carries the join id its shape needs (never by sport name — see [_venueTab]).
  /// Innings sports keep exactly their three core tabs (the venue facts render
  /// as first-page cards there, so the extra chip would be a second home).
  List<String> _chipLabels(SportEvent event, Competition comp,
      GameSummary? summary, MatchFeed? matchFeed) {
    final core = _coreChips(event, comp, summary, matchFeed);
    if (_isInnings(comp)) return core;
    return switch (_venueTab(event, comp)) {
      VenueTabKind.circuit => [...core, 'Circuit'],
      VenueTabKind.venue => [...core, 'Venue'],
      VenueTabKind.none => core,
    };
  }

  List<String> _coreChips(SportEvent event, Competition comp,
      GameSummary? summary, MatchFeed? matchFeed) {
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
    // Innings sports (the reorganized baseball detail): exactly Now/Recap ·
    // Box · Plays — the leaders read rides the box tables, the venue/series
    // cards live on the first page.
    if (_isInnings(comp)) {
      return [first, if (hasBox) 'Box', if (hasPlays) 'Plays'];
    }
    // The deep soccer detail (design LiveGame 9–10), gated on the summary
    // actually shipping the deep modules (commentary narrative / match
    // leaders) — data presence, never sport name, so rugby joins the moment
    // its summary carries them and a degraded soccer feed falls back to the
    // generic tab set below. Box/Leaders retire for this grammar: the player
    // tables move onto Lineups, the team stats + shot map onto Stats, the
    // leaders read onto the Now card.
    final soccerDeep = summary != null &&
        (summary.commentary.isNotEmpty || summary.matchLeaders.isNotEmpty);
    if (soccerDeep) {
      final hasShots =
          matchFeed != null && matchShots(matchFeed.plays).isNotEmpty;
      return [
        first,
        // Turn 10: the live field pass — only while the ball is rolling and
        // the core feed is actually serving plays.
        if (s.live && matchFeed != null && matchFeed.plays.isNotEmpty)
          'Live pitch',
        if (summary.commentary.isNotEmpty)
          'Commentary'
        else if (hasTimeline)
          'Timeline',
        if (summary.lineups.isNotEmpty) 'Lineups',
        if (summary.teamStats.isNotEmpty || hasShots) 'Stats',
      ];
    }
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

  /// Foot-link tab switch ('Full commentary' → the Commentary chip). No-op
  /// when the chip isn't present.
  void _switchTab(List<String> chips, String label) {
    final i = chips.indexOf(label);
    if (i >= 0) setState(() => _chip = i);
  }

  List<Widget> _sections(
    BuildContext context,
    SportEvent event,
    Competition comp,
    GameSummary? summary,
    List<String> chips,
    int chipIndex,
    MatchFeed? matchFeed,
  ) {
    // §2.9 Venue/Circuit tab — dispatched before the field/non-field split so it
    // works for a racing weekend (Circuit) and a stadium team game (Venue) alike.
    final selected = chipIndex >= 0 && chipIndex < chips.length ? chips[chipIndex] : '';
    if (selected == 'Circuit') {
      final (_, circuitId) = _venueTabIds(event, comp);
      return [
        CircuitTab(
            league: widget.league, event: event, comp: comp, circuitId: circuitId)
      ];
    }
    if (selected == 'Venue') {
      final (venueId, _) = _venueTabIds(event, comp);
      return [
        VenueTab(
            league: widget.league, event: event, comp: comp, venueId: venueId)
      ];
    }
    if (comp.isField) {
      // On a racing weekend the chip nav picks the session; golf/one-off races
      // stay on their single competition.
      final multiSession = _isMultiSession(event, comp);
      final session = multiSession
          ? event.competitions[chipIndex.clamp(0, event.competitions.length - 1)]
          : comp;
      final golf = session.meta?.golf;
      final season =
          ref.read(mergedLeagueScoresProvider(_scoresKey)).valueOrNull?.season.year;
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
      case 'Live pitch':
        // Turn 10: the live field pass — pitch + trail, the last touch as the
        // quiet sentence, and the restart log. All off the core match feed.
        final plays = matchFeed?.plays ?? const <MatchFeedPlay>[];
        final lineups = summary?.lineups ?? const <Lineup>[];
        return [
          LivePitchCard(comp: comp, plays: plays, lineups: lineups),
          LastTouchCard(plays: plays, lineups: lineups),
          StoppagesCard(comp: comp, plays: plays, lineups: lineups),
        ];
      case 'Commentary':
        return [CommentaryFeedCard(summary!.commentary)];
      case 'Lineups':
        // Formation pitch when every starter carries a placement (design 9b),
        // the plain lists as the reference below, then the per-player tables —
        // the 'Full player stats' the leaders card links to.
        return [
          if (summary!.lineups.any(FormationCard.placeable))
            FormationCard(
                comp: comp, lineups: summary.lineups, league: widget.league),
          _LineupsCard(summary.lineups, league: widget.league),
          for (final g in summary.boxGroups)
            _BoxGroupCard(g, league: widget.league),
        ];
      case 'Stats':
        final shots = matchFeed == null
            ? const <MatchFeedPlay>[]
            : matchShots(matchFeed.plays);
        return [
          if (summary != null && summary.teamStats.isNotEmpty)
            _TeamStatsCard(comp: comp, rows: summary.teamStats, sport: _sport),
          if (shots.isNotEmpty)
            ShotMapCard(
                comp: comp,
                shots: shots,
                lineups: summary?.lineups ?? const <Lineup>[]),
        ];
      case 'Scorecard': // cricket innings scorecard (batting + bowling figures)
        return [
          for (final inn in summary!.cricketInnings) _CricketInningsCard(inn),
        ];
      case 'Box':
        // Innings sports: the newspaper page — line score, the W/L line, the
        // team-tabbed box WITH the agate footnotes (2B:/HR:/Team LOB/RISP…),
        // the scoring summary from the 1st, and the venue footer.
        if (_isInnings(comp)) {
          return [
            if (_hasCheapLines(comp) || summary?.periodLines != null)
              _LineScoreCard(comp: comp, lines: summary?.periodLines),
            if (summary != null && summary.decisions.isNotEmpty)
              _DecisionsCard(summary.decisions, league: widget.league),
            if (summary == null)
              const _LoadingCard()
            else
              _BaseballBox(
                  comp: comp,
                  summary: summary,
                  league: widget.league,
                  showDetails: true),
            ..._baseballScoringCards(comp, summary, lines: false),
            _VenueCard(event,
                comp: comp, summary: summary, includeWeather: false),
          ];
        }
        return [
          if (_hasCheapLines(comp) || summary?.periodLines != null)
            _LineScoreCard(comp: comp, lines: summary?.periodLines),
          if (summary != null && summary.teamStats.isNotEmpty)
            _TeamStatsCard(comp: comp, rows: summary.teamStats, sport: _sport),
          if (summary != null)
            for (final g in summary.boxGroups) _BoxGroupCard(g, league: widget.league),
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
        // into half-inning containers, pitch sequences folded behind a tap),
        // headed by the box grid + the W/L line so the tab opens with the score.
        if (summary!.atBats.isNotEmpty) {
          return [
            if (_hasCheapLines(comp) || summary.periodLines != null)
              _LineScoreCard(comp: comp, lines: summary.periodLines),
            if (summary.decisions.isNotEmpty)
              _DecisionsCard(summary.decisions, league: widget.league),
            _BaseballPlaysFeed(summary, comp),
          ];
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
          // Fold the detail-open CORE situation (gridiron down/distance, basketball
          // bonus/timeouts, hockey power play — merged into the summary payload by
          // api.dart) over the cheap scoreboard situation, so the card upgrades in
          // place. Null-safe: no summary/core situation → the scoreboard one stands.
          //
          // NOTE (logged below): mergedWith gives the CORE fields precedence,
          // including balls/strikes — and core rides the 12s espn_client cache,
          // so on a push-fed slate the count here can trail the (~1s fresh)
          // pushed scoreboard situation. The 'act sit-source' log line is the
          // evidence trail for that.
          final liveComp = summary?.situation != null
              ? comp.withSituation(
                  (comp.situation ?? summary!.situation!).mergedWith(summary!.situation))
              : comp;
          final coreSit = summary?.situation;
          final sitSource = coreSit != null
              ? 'core-over-push (count ${coreSit.balls}-${coreSit.strikes}'
                  ' vs pushed ${comp.situation?.balls}-${comp.situation?.strikes})'
              : 'push/scoreboard only';
          if (sitSource != _lastSitSource) {
            _lastSitSource = sitSource;
            FcLog.log('act', 'detail sit-source: $sitSource');
          }
          // Baseball's rich live at-bat (turn 8): the last atBats entry while
          // it's still unresolved — feeds the duel card's pitch count, the
          // strike-zone card, and the pitch strip. Null for every other sport.
          final liveAtBat =
              (summary != null && summary.atBats.isNotEmpty && summary.atBats.last.live)
                  ? summary.atBats.last
                  : null;
          // Between innings (situation.isDueUp): the Due Up card wants the
          // previous half's story — deterministic off the rich at-bats, with
          // the optional AI sentence (recapProvider, key-gated in Settings)
          // upgrading it in place when it lands.
          final betweenInnings = liveComp.situation?.isDueUp == true;
          final recap = betweenInnings && summary != null
              ? previousHalfInningRecap(summary.atBats)
              : null;
          final aiRecap = recap != null
              ? ref
                  .watch(inningRecapProvider((
                    league: widget.league,
                    eventId: event.id,
                    period: recap.period,
                    half: recap.half,
                  )))
                  .valueOrNull
              : null;
          // Scoring plays with running scores — feed basketball's clock-&-run
          // slot (the situation card) and the §8 lead tracker below it.
          final leadPlays = _leadPlays(summary);
          final situation = situationCardFor(liveComp,
              liveAtBat: liveAtBat,
              recap: recap,
              aiRecap: aiRecap,
              leadPlays: leadPlays);
          // The reorganized innings-sport Now (data-gated on the period unit):
          // the at-bat story (duel → zone/bases → pitch strip → the loud last
          // play), the scoring summary from the 1st, then the deep-dive cards
          // inline — box, win prob, game stats, injuries, series, venue, weather.
          if (_isInnings(comp)) {
            return [
              if (situation != null) situation,
              if (!betweenInnings &&
                  liveComp.situation?.hasBaseball == true &&
                  (liveAtBat != null || liveComp.situation?.onFirst != null))
                BaseballZoneCard(liveComp, liveAtBat: liveAtBat),
              if (liveAtBat != null && liveAtBat.pitches.isNotEmpty)
                PitchStripCard(liveAtBat),
              if (summary?.lastPlay != null)
                InvertedCard(
                    label: summary!.lastPlay!.kind == 'pitch'
                        ? 'Last pitch'
                        : 'Last play',
                    text: _lastPlayProse(summary.lastPlay!))
              else if (liveComp.situation?.lastPlay != null)
                InvertedCard(
                    label: 'Last play', text: liveComp.situation!.lastPlay!),
              ..._baseballScoringCards(comp, summary),
              ..._baseballSupportCards(event, comp, summary, chips),
              if (event.weather != null && event.weather!.summary.isNotEmpty)
                _WeatherCard(event.weather!),
            ];
          }
          final cheap = _cheapPanelFor(comp);
          final crease = (summary?.cricketInnings.isNotEmpty ?? false)
              ? summary!.cricketInnings.last
              : null;
          // The deep soccer Now (design 9a): momentum + commentary preview +
          // match leaders; the team-stat/leader/lineup story moves to its own
          // tabs, so their generic Now cards stand down (data presence).
          final soccerDeep = summary != null &&
              (summary.commentary.isNotEmpty ||
                  summary.matchLeaders.isNotEmpty);
          final momentum = matchFeed != null
              ? momentumBuckets(matchFeed.plays)
              : const <MomentumBucket>[];
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
            // The 9a momentum chart — attacking pressure per minute off the
            // match feed; absent feed → absent card.
            if (momentum.isNotEmpty)
              MomentumCard(comp: comp, buckets: momentum),
            // Turn 8: strike zone (only with pitch locations) + bases, then the
            // pitch-by-pitch strip — baseball's rich Now, gated on data presence.
            // (suppressed between innings — an empty diamond under the Due Up
            // card says nothing; the bases reset with the next half anyway)
            if (!betweenInnings &&
                liveComp.situation?.hasBaseball == true &&
                (liveAtBat != null || liveComp.situation?.onFirst != null))
              BaseballZoneCard(liveComp, liveAtBat: liveAtBat),
            if (liveAtBat != null && liveAtBat.pitches.isNotEmpty)
              PitchStripCard(liveAtBat),
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
            // The one loud moment (§7): baseball's derived "what really was the
            // last play" (rich, walks back past ESPN's next-batter bookends —
            // a groundout reads as the groundout, an inning end as "End of the
            // 3rd inning", never "Now at bat"), else the cheap situation's
            // last-play text, else — for soccer/rugby, which carry no core
            // situation — the freshest event.
            if (summary?.lastPlay != null)
              InvertedCard(
                  label: summary!.lastPlay!.kind == 'pitch'
                      ? 'Last pitch'
                      : 'Last play',
                  text: _lastPlayProse(summary.lastPlay!))
            else if (liveComp.situation?.lastPlay != null)
              InvertedCard(label: 'Last play', text: liveComp.situation!.lastPlay!)
            else if (lastEventLine(comp) != null)
              InvertedCard(label: 'Last event', text: lastEventLine(comp)!),
            // The 9a commentary preview + match leaders (the deep soccer Now).
            if (soccerDeep && summary.commentary.isNotEmpty)
              CommentaryPreviewCard(summary.commentary,
                  onMore: () => _switchTab(chips, 'Commentary')),
            if (soccerDeep && summary.matchLeaders.isNotEmpty)
              MatchLeadersCard(summary.matchLeaders,
                  comp: comp,
                  league: widget.league,
                  onFullStats: () => _switchTab(chips, 'Lineups')),
            // Match-stats pulse: hockey's §8 shots-pressure card when the summary
            // ships shots, else the cheap scoreboard panel straight off the wire.
            // The deep soccer grammar moves this read onto its Stats tab.
            if (showShots)
              _ShotsPressureCard(comp: comp, shots: shotsStat)
            else if (cheap != null && !soccerDeep)
              _CheapStatsCard(comp: comp, panel: cheap),
            // The quiet scoring summary (design 6c) — hockey's Now was two lonely
            // cards without it.
            if (scoringNow.isNotEmpty) _ScoringSummaryCard(scoringNow),
            if (!soccerDeep) _TopPerformersCard(comp),
            if (summary != null && summary.lineups.isNotEmpty && !soccerDeep)
              _LineupsCard(summary.lineups, league: widget.league),
            if (summary != null && summary.seasonSeries != null)
              _SeasonSeriesCard(summary.seasonSeries!),
          ].whereType<Widget>().toList();
        }
        if (s.isScheduled) {
          // Pre-game betting line (§6): the cheap inline scoreboard line if ESPN
          // sent one, else a lazy core competition-odds fetch (per-team moneyline).
          // Gate the fetch to head-to-head team games (odds are priced for
          // baseball/basketball/football/soccer — enforced capability-side in
          // api.dart, which no-ops other sports without a network call).
          final odds = comp.odds ??
              (comp.competitorKind == 'team' && !comp.isField
                  ? ref
                      .watch(oddsProvider((
                        league: widget.league,
                        eventId: event.id,
                        compId: comp.id,
                      )))
                      .valueOrNull
                  : null);
          return [
            if (tennisContext != null) tennisContext,
            if (comp.competitors.any((c) => c.probables.isNotEmpty))
              _ProbablesCard(comp),
            if (odds != null) _OddsCard(comp: comp, odds: odds),
            if (summary != null && summary.lineups.isNotEmpty)
              _LineupsCard(summary.lineups, league: widget.league),
            if (summary != null && summary.recentForm.isNotEmpty)
              _FormCard(summary.recentForm),
            if (summary != null && summary.injuries.isNotEmpty)
              _InjuriesCard(summary.injuries),
            _VenueCard(event, comp: comp, summary: summary),
          ];
        }
        // Recap
        // The reorganized innings-sport recap (user-spec order): line score →
        // the W/L line → the scoring summary from the 1st → the deep-dive cards.
        if (_isInnings(comp)) {
          return [
            if (_hasCheapLines(comp) || summary?.periodLines != null)
              _LineScoreCard(comp: comp, lines: summary?.periodLines),
            if (summary != null && summary.decisions.isNotEmpty)
              _DecisionsCard(summary.decisions, league: widget.league),
            ..._baseballScoringCards(comp, summary, lines: false),
            ..._baseballSupportCards(event, comp, summary, chips),
          ];
        }
        final bout = summary?.boutFor(comp.id);
        final cheap = _cheapPanelFor(comp);
        final shotsStat = _shotsStat(summary);
        final showShots = shotsStat != null && !(cheap?.overlapsRich ?? false);
        final timeline = _matchTimeline(comp, summary);
        // The deep soccer recap: the full-match momentum read + match leaders;
        // team stats live on the Stats tab, the narrative on Commentary.
        final soccerDeep = summary != null &&
            (summary.commentary.isNotEmpty || summary.matchLeaders.isNotEmpty);
        final momentum = matchFeed != null
            ? momentumBuckets(matchFeed.plays)
            : const <MomentumBucket>[];
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
          // The full-match momentum chart (design 9a) — the KO→FT pressure
          // story in one glance; feed-gated like the live version.
          if (momentum.isNotEmpty) MomentumCard(comp: comp, buckets: momentum),
          if (comp.method != null || bout != null)
            _MethodCard(comp: comp, bout: bout),
          if (_isFightCard(event, comp))
            _FightCardCard(league: widget.league, event: event, main: comp),
          if (_leadPlays(summary).length >= 12)
            _LeadTrackerCard(comp: comp, plays: _leadPlays(summary)),
          // Post-game the single win% is a foregone 100 — but the full arc is
          // the game's story, so the scrubbable chart earns a recap slot.
          if ((summary?.winProbability?.points.length ?? 0) >= 2)
            _WinProbCard(comp: comp, wp: summary!.winProbability!),
          if (_hasCheapLines(comp) || summary?.periodLines != null)
            _LineScoreCard(comp: comp, lines: summary?.periodLines),
          if (showShots)
            _ShotsPressureCard(comp: comp, shots: shotsStat)
          else if (cheap != null && !soccerDeep)
            _CheapStatsCard(comp: comp, panel: cheap),
          if (comp.headline != null) _HeadlineCard(comp.headline!),
          if (soccerDeep && summary.matchLeaders.isNotEmpty)
            MatchLeadersCard(summary.matchLeaders,
                comp: comp,
                league: widget.league,
                onFullStats: () => _switchTab(chips, 'Lineups'))
          else
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

  /// The baseball "scoring summary" block (user spec: the box grid + the runs
  /// story starting in the FIRST inning): the line score, then the half-inning
  /// scoring feed in CHRONOLOGICAL order — the one designed exception to §9's
  /// newest-first (this block recaps, the Plays tab still leads with the fresh).
  /// [lines] gates the grid off for pages that already lead with it.
  List<Widget> _baseballScoringCards(Competition comp, GameSummary? summary,
      {bool lines = true}) {
    final scoring = summary == null
        ? const <SummaryPlay>[]
        : summary.scoringPlays.where((p) => p.scoring).toList();
    return [
      if (lines && (_hasCheapLines(comp) || summary?.periodLines != null))
        _LineScoreCard(comp: comp, lines: summary?.periodLines),
      if (scoring.isNotEmpty) _HalfInningFeed(scoring, comp, chronological: true),
    ];
  }

  /// The innings-sport first page's deep-dive tail, shared by Now and Recap:
  /// the Plays link → the team-tabbed box → win probability → the grouped
  /// hitting/pitching game stats → injuries → season series → venue. Every
  /// card data-gated; weather is the live page's own addendum.
  List<Widget> _baseballSupportCards(SportEvent event, Competition comp,
      GameSummary? summary, List<String> chips) {
    final playsAt = chips.indexOf('Plays');
    return [
      if (playsAt >= 0)
        _PlaysLink(onTap: () => setState(() => _chip = playsAt)),
      if (summary != null && summary.boxGroups.isNotEmpty)
        _BaseballBox(comp: comp, summary: summary, league: widget.league),
      if (summary?.winProbability != null)
        _WinProbCard(comp: comp, wp: summary!.winProbability!),
      if (summary != null)
        for (final g in summary.teamGameStats)
          _SummaryStatGroupCard(comp: comp, group: g),
      if (summary != null && summary.injuries.isNotEmpty)
        _InjuriesCard(summary.injuries),
      if (summary != null && summary.seasonSeries != null)
        _SeasonSeriesCard(summary.seasonSeries!),
      _VenueCard(event, comp: comp, summary: summary, includeWeather: false),
    ];
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
  final String league;
  final SportEvent event;
  final Competition comp;
  final List<String> chips;
  final int chipIndex;
  final ValueChanged<int> onChip;

  _HeaderDelegate({
    required this.topPadding,
    required this.league,
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
                child: ClipRect(
                    child: _ExpandedBlock(
                        league: league, event: event, comp: comp)),
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
  final String league;
  final SportEvent event;
  final Competition comp;
  const _ExpandedBlock(
      {required this.league, required this.event, required this.comp});

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
      // Cheap TV/stream label — the terse "where to watch" glance (§6). One dim
      // segment; drops in silently when ESPN sends no broadcast.
      if (comp.broadcast != null) comp.broadcast!,
    ].join(' · ');

    // The header's score block carries the same long-press-to-follow grammar
    // as the feed rows — team-kind head-to-head games only.
    final canFollow = !comp.isField && comp.competitorKind == 'team';
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: canFollow
          ? () => showGameFollowSheet(context, league: league, comp: comp)
          : null,
      child: Padding(
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
      ),
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

/// Win probability. With the full-game arc (`wp.points`, summary-sourced) this
/// is a scrubbable chart: hold/drag across the curve to replay any moment — the
/// headline %, the split bar, and a game-state caption (period · clock · score)
/// track the finger; release snaps back to now. Without an arc (the predictor
/// fallback, or old payloads) it stays the passive label + split bar.
class _WinProbCard extends StatefulWidget {
  final Competition comp;
  final WinProbability wp;
  const _WinProbCard({required this.comp, required this.wp});

  @override
  State<_WinProbCard> createState() => _WinProbCardState();
}

class _WinProbCardState extends State<_WinProbCard> {
  int? _scrub; // selected arc index while touching; null = resting (now/final)

  @override
  Widget build(BuildContext context) {
    final comp = widget.comp, wp = widget.wp;
    final away = comp.away, home = comp.home;
    if (away == null || home == null) return const SizedBox.shrink();
    final points = wp.points;
    final hasArc = points.length >= 2;
    final sel = hasArc && _scrub != null ? points[_scrub!] : null;

    final homePct = sel?.home ?? wp.home;
    final awayPct = sel != null ? 100 - sel.home : wp.away;
    final leader = homePct >= awayPct ? home : away;
    final pct = homePct >= awayPct ? homePct : awayPct;

    return V2Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            const Expanded(child: CardLabel('Win probability')),
            Text('${leader.label} $pct%',
                style: sel != null
                    ? T.statCallout.copyWith(color: T.gold)
                    : T.statCallout),
          ],
        ),
        if (hasArc) ...[
          const SizedBox(height: 10),
          _chart(points, away, home),
          SizedBox(
            height: 18,
            child: sel != null
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_pointCaption(sel, away, home),
                        style: T.caption, maxLines: 1),
                  )
                : null,
          ),
        ] else
          const SizedBox(height: 10),
        SplitBar(
          leftFraction: awayPct / 100,
          left: teamColor(away),
          right: teamColor(home),
        ),
      ]),
    );
  }

  Widget _chart(List<WinProbPoint> points, Competitor away, Competitor home) =>
      LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        void select(Offset local) {
          final i = ((local.dx / w) * (points.length - 1))
              .round()
              .clamp(0, points.length - 1);
          if (i != _scrub) setState(() => _scrub = i);
        }

        void release() => setState(() => _scrub = null);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => select(d.localPosition),
          onTapUp: (_) => release(),
          onTapCancel: release,
          onHorizontalDragStart: (d) => select(d.localPosition),
          onHorizontalDragUpdate: (d) => select(d.localPosition),
          onHorizontalDragEnd: (_) => release(),
          onHorizontalDragCancel: release,
          child: SizedBox(
            height: 72,
            width: double.infinity,
            child: CustomPaint(
              painter: _WinProbChartPainter(
                points: points,
                awayColor: teamColor(away),
                homeColor: teamColor(home),
                scrub: _scrub,
              ),
            ),
          ),
        );
      });

  /// 'TOP 5 · ATL 2–4 DET' / 'Q3 4:12 · LAL 68–71 BOS' — whatever the joined
  /// play carried; a context-less point just reads nothing extra.
  String _pointCaption(WinProbPoint p, Competitor away, Competitor home) {
    final parts = <String>[];
    final rail = [
      if (p.half != null && p.period != null)
        '${p.half == 'top' ? 'Top' : 'Bot'} ${p.period}'
      else if (p.periodLabel != null && p.periodLabel!.isNotEmpty)
        p.periodLabel!
      else if (p.period != null)
        'Period ${p.period}',
      if (p.clock != null && p.clock!.isNotEmpty) p.clock!,
    ].join(' ');
    if (rail.isNotEmpty) parts.add(rail);
    if (p.awayScore != null && p.homeScore != null) {
      parts.add('${away.label} ${p.awayScore!.round()}'
          '–${p.homeScore!.round()} ${home.label}');
    }
    return parts.join(' · ').toUpperCase();
  }
}

/// The win-prob curve: home share up / away share down around a 50% centerline,
/// the stroke wearing each side's color on its half (two clipped passes), faint
/// verticals at period changes, and — while scrubbing — a hairline + gold dot at
/// the selected point (else a dot on the newest point, lead-tracker style).
class _WinProbChartPainter extends CustomPainter {
  final List<WinProbPoint> points;
  final Color awayColor, homeColor;
  final int? scrub;
  _WinProbChartPainter(
      {required this.points,
      required this.awayColor,
      required this.homeColor,
      this.scrub});

  @override
  void paint(Canvas canvas, Size size) {
    final n = points.length;
    final mid = size.height / 2;
    double x(int i) => n == 1 ? 0 : size.width * i / (n - 1);
    double y(int homePct) => size.height * (1 - homePct / 100);

    // period boundaries — the "part of the game" landmarks the scrub needs
    final divPaint = Paint()..color = T.divider..strokeWidth = 1;
    for (var i = 1; i < n; i++) {
      final a = points[i - 1].period, b = points[i].period;
      if (a != null && b != null && a != b) {
        canvas.drawLine(Offset(x(i), 0), Offset(x(i), size.height), divPaint);
      }
    }
    // 50% centerline
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid), divPaint);

    final path = Path()..moveTo(0, y(points.first.home));
    for (var i = 1; i < n; i++) {
      path.lineTo(x(i), y(points[i].home));
    }
    final stroke = Paint()
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    // home color above the line, away color below — each side owns its half
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, -2, size.width, mid));
    canvas.drawPath(path, stroke..color = homeColor);
    canvas.restore();
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, mid, size.width, size.height + 2));
    canvas.drawPath(path, stroke..color = awayColor);
    canvas.restore();

    if (scrub != null) {
      final sx = x(scrub!), sy = y(points[scrub!].home);
      canvas.drawLine(Offset(sx, 0), Offset(sx, size.height),
          Paint()..color = T.textDim..strokeWidth = 1);
      canvas.drawCircle(Offset(sx, sy), 3.5, Paint()..color = T.gold);
    } else {
      final last = points.last.home;
      canvas.drawCircle(Offset(x(n - 1), y(last)), 3,
          Paint()..color = last >= 50 ? homeColor : awayColor);
    }
  }

  @override
  bool shouldRepaint(_WinProbChartPainter old) =>
      old.points != points ||
      old.scrub != scrub ||
      old.awayColor != awayColor ||
      old.homeColor != homeColor;
}

/// The §8 basketball "lead tracker" — a margin polyline over the game's scoring
/// plays, headed by the current leader's margin (the run callout lives on the
/// clock-&-run situation card above). Built entirely client-side from the
/// summary's running scores (no extra fetch). Shown when a game has enough
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

    return V2Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          const Expanded(child: CardLabel('Lead tracker')),
          if (leader != null)
            Text('${leader.label} +${last.abs().round()}',
                style: T.statCallout.copyWith(fontSize: 18))
          else
            Text('TIED', style: T.statCallout.copyWith(fontSize: 18, color: T.textDim)),
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
  // The reorganized baseball first page reads the game start-to-finish
  // ("scores starting in the first"); the Plays tab keeps §9's newest-first.
  final bool chronological;
  const _HalfInningFeed(this.plays, this.comp, {this.chronological = false});

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
    final ordered =
        chronological ? order : order.reversed.toList(); // newest first default
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
                            // ABS challenge suffix: faint, caution pale when
                            // the call was flipped (§2 muted-pair glyph text).
                            child: Text.rich(TextSpan(
                                text: a.pitches[p].text,
                                style: const TextStyle(
                                    fontSize: 12.5, color: T.textDim),
                                children: [
                                  if (a.pitches[p].challenge != null)
                                    TextSpan(
                                        text: ' · ${a.pitches[p].challenge}',
                                        style: TextStyle(
                                            color: a.pitches[p].challenge ==
                                                    'overturned'
                                                ? T.mutedNeutralGlyph
                                                : T.textFaint)),
                                ])),
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
  final String league;
  const _LineupsCard(this.lineups, {required this.league});

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
          _panel(context, ordered[i]),
        ],
      ],
    );
  }

  Widget _panel(BuildContext context, Lineup lineup) {
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
        for (final pl in lineup.starters) _playerRow(context, lineup, pl),
        if (lineup.bench.isNotEmpty) ...[
          const SizedBox(height: 10),
          const CardLabel('Bench'),
          const SizedBox(height: 2),
          for (final pl in lineup.bench) _playerRow(context, lineup, pl, dim: true),
        ],
      ]),
    );
  }

  Widget _playerRow(BuildContext context, Lineup lineup, LineupPlayer pl,
      {bool dim = false}) {
    final row = Padding(
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
              style: TextStyle(fontSize: 14, color: dim ? T.textDim : T.text)),
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
    // Tap through to the player page when the roster carries an athlete id; an
    // idless row stays inert.
    final id = pl.id;
    if (id == null || id.isEmpty) return row;
    return InkWell(
      onTap: () => openPlayerPage(context, league,
          athleteId: id, name: pl.name),
      child: row,
    );
  }
}

class _BoxGroupCard extends StatelessWidget {
  final BoxGroup group;
  final String league;
  // Team-tabbed box (the baseball reorg): render only this side's block — the
  // §10 scope control above the card already names the team.
  final String? side;
  const _BoxGroupCard(this.group, {required this.league, this.side});

  static const _maxCols = 5;

  @override
  Widget build(BuildContext context) {
    final cols = group.columns.take(_maxCols).toList();
    final teams = side == null
        ? group.teams
        : group.teams.where((t) => t.side == side).toList();
    if (teams.isEmpty) return const SizedBox.shrink();
    return V2Card(
      padding: T.padTable, // §10 dense table: tighter sides, tables need width
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CardLabel(group.title),
        for (final team in teams) ...[
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
          for (final r in team.rows) _boxRow(context, r, cols),
        ],
      ]),
    );
  }

  /// One box row. A substitute (`starter == false`, baseball only) is indented
  /// under the man it replaced, prefixed with ESPN's lineup letter marker (a-, b-)
  /// or a ↳ glyph, and carries its lineup note as an 11px footnote (§3d / §10).
  /// Taps through to the player page when the row carries an athlete id.
  Widget _boxRow(BuildContext context, BoxRow r, List<String> cols) {
    final sub = r.starter == false;
    final marker = _subMarker(r);
    final row = Container(
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
    final id = r.id;
    if (id == null || id.isEmpty) return row;
    return InkWell(
      onTap: () => openPlayerPage(context, league,
          athleteId: id, name: r.name),
      child: row,
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

/// The baseball pitcher-decision line (user spec "Win | Loss"): W / L / SV rows
/// off summary.decisions — a tinted role chip (§6 semantic: W green, L live,
/// SV gold), the pitcher (tap → player page), team + season line trailing.
/// Data-gated: ESPN ships featuredAthletes only once there's a decision.
class _DecisionsCard extends StatelessWidget {
  final List<Decision> decisions;
  final String league;
  const _DecisionsCard(this.decisions, {required this.league});

  (String, Color) _chip(String role) => switch (role) {
        'win' => ('W', T.green),
        'loss' => ('L', T.live),
        _ => ('SV', T.gold),
      };

  @override
  Widget build(BuildContext context) => V2Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const CardLabel('Decision'),
          const SizedBox(height: 4),
          for (final d in decisions) _row(context, d),
        ]),
      );

  Widget _row(BuildContext context, Decision d) {
    final (letter, color) = _chip(d.role);
    final trail = [
      if (d.abbr != null) d.abbr!,
      if (d.record != null) d.record!,
      if (d.role == 'save' && d.saves != null) '${d.saves} SV',
    ].join(' · ');
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Container(
          width: 26,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(letter,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(d.name,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: T.rowText),
        ),
        if (trail.isNotEmpty) Text(trail, style: T.caption),
      ]),
    );
    final id = d.id;
    if (id == null || id.isEmpty) return row;
    return InkWell(
      onTap: () =>
          openPlayerPage(context, league, athleteId: id, name: d.name),
      child: row,
    );
  }
}

/// The team-tabbed box score (baseball reorg): one §6/§10 scope control picking
/// the team, then that side's Batting/Pitching player tables — and, on the Box
/// tab ([showDetails]), the team's newspaper agate block beneath.
class _BaseballBox extends StatefulWidget {
  final Competition comp;
  final GameSummary summary;
  final String league;
  final bool showDetails;
  const _BaseballBox(
      {required this.comp,
      required this.summary,
      required this.league,
      this.showDetails = false});

  @override
  State<_BaseballBox> createState() => _BaseballBoxState();
}

class _BaseballBoxState extends State<_BaseballBox> {
  int _side = 0; // 0 = away · 1 = home

  @override
  Widget build(BuildContext context) {
    final away = widget.comp.away, home = widget.comp.home;
    final side = _side == 0 ? 'away' : 'home';
    final details = widget.showDetails
        ? widget.summary.teamDetails.where((t) => t.side == side).toList()
        : const <TeamDetails>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SegmentedControl(
        items: [away?.label ?? 'Away', home?.label ?? 'Home'],
        selected: _side,
        onTap: (i) => setState(() => _side = i),
      ),
      for (final g in widget.summary.boxGroups) ...[
        const SizedBox(height: T.gapCard),
        _BoxGroupCard(g, league: widget.league, side: side),
      ],
      for (final t in details) ...[
        const SizedBox(height: T.gapCard),
        _TeamDetailsCard(t),
      ],
    ]);
  }
}

/// One team's newspaper agate block (summary.teamDetails): BATTING/PITCHING/
/// FIELDING/BASERUNNING sections of '2B: Vierling (12, Lopez)' lines — the §10
/// footer-summary voice given a card of its own.
class _TeamDetailsCard extends StatelessWidget {
  final TeamDetails details;
  const _TeamDetailsCard(this.details);

  @override
  Widget build(BuildContext context) => V2Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CardLabel(
              [if (details.abbr != null) details.abbr!, 'Notes'].join(' ')),
          for (final g in details.groups) ...[
            const SizedBox(height: 12),
            Text(g.title.toUpperCase(), style: T.cardLabelFaint),
            const SizedBox(height: 4),
            for (final r in g.rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text.rich(TextSpan(children: [
                  TextSpan(
                      text: '${r.label}: ',
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: T.textDim)),
                  TextSpan(
                      text: r.value,
                      style: const TextStyle(
                          fontSize: 12.5, height: 1.35, color: T.textBody)),
                ])),
              ),
          ],
        ]),
      );
}

/// One grouped this-game team comparison (summary.teamGameStats): HITTING /
/// PITCHING rows through the same [StatCompareRow] the rich team-stats card
/// uses, so the tiers can't drift. 'Batting' reads as HITTING in the page's
/// voice; every row data-gated.
class _SummaryStatGroupCard extends StatelessWidget {
  final Competition comp;
  final SummaryStatGroup group;
  const _SummaryStatGroupCard({required this.comp, required this.group});

  @override
  Widget build(BuildContext context) {
    final away = comp.away, home = comp.home;
    final present =
        group.rows.where((r) => r.away != null || r.home != null).toList();
    if (present.isEmpty) return const SizedBox.shrink();
    final title =
        group.title.toLowerCase() == 'batting' ? 'Hitting' : group.title;
    return V2Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(away?.label ?? '',
              style: T.cardLabelFaint.copyWith(color: teamColor(away))),
          const Spacer(),
          CardLabel(title),
          const Spacer(),
          Text(home?.label ?? '',
              style: T.cardLabelFaint.copyWith(color: teamColor(home))),
        ]),
        const SizedBox(height: 10),
        for (var i = 0; i < present.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          StatCompareRow(
            spec: classifyRichRow(present[i]),
            away: present[i].away,
            home: present[i].home,
            awayColor: teamColor(away),
            homeColor: teamColor(home),
          ),
        ],
      ]),
    );
  }
}

/// CURRENT WEATHER (live baseball first page): the cheap scoreboard weather —
/// Barlow temperature + condition caption. Indoor/unserved → no card (§11.8).
class _WeatherCard extends StatelessWidget {
  final Weather weather;
  const _WeatherCard(this.weather);

  @override
  Widget build(BuildContext context) {
    final t = weather.temperature;
    final cond = weather.condition;
    return V2Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const CardLabel('Current weather'),
        const SizedBox(height: 6),
        Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              if (t != null)
                Text('${t.round()}°',
                    style: const TextStyle(
                        fontFamily: 'BarlowCondensed',
                        fontWeight: FontWeight.w700,
                        fontSize: 30,
                        height: 1.0,
                        color: T.text,
                        fontFeatures: [FontFeature.tabularFigures()])),
              if (t != null && cond != null && cond.isNotEmpty)
                const SizedBox(width: 10),
              if (cond != null && cond.isNotEmpty)
                Text(cond, style: T.caption),
            ]),
      ]),
    );
  }
}

/// The quiet standing-destination row into the Plays tab ("Full play-by-play")
/// — the home feed's foot-row grammar at detail scale: a plain surface row +
/// chevron, never a gold hint.
class _PlaysLink extends StatelessWidget {
  final VoidCallback onTap;
  const _PlaysLink({required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: T.surface,
        borderRadius: BorderRadius.circular(T.rowCardRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(T.rowCardRadius),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(children: [
              Expanded(child: Text('Full play-by-play', style: T.rowText)),
              Icon(Icons.chevron_right_rounded, size: 18, color: T.textFaint),
            ]),
          ),
        ),
      );
}

/// Pre-game betting line (§6) — the quiet PRE-GAME block: spread/total from the
/// cheap scoreboard line, per-team moneyline when the core enrichment lands.
/// Renders only what ESPN served; the whole card is hidden when odds are absent.
class _OddsCard extends StatelessWidget {
  final Competition comp;
  final Odds odds;
  const _OddsCard({required this.comp, required this.odds});

  static String _trim(num n) =>
      n == n.roundToDouble() ? n.toInt().toString() : n.toString();

  static Widget _stat(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.toUpperCase(), style: T.cardLabelFaint),
          const SizedBox(height: 3),
          Text(value, style: T.statCallout),
        ],
      );

  static Widget _mlChip(String team, String american) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
            color: T.track, borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(team, style: T.captionFaint),
          const SizedBox(width: 7),
          Text(american, style: T.statLine),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final away = comp.away ??
        (comp.competitors.isNotEmpty ? comp.competitors.first : null);
    final home = comp.home ??
        (comp.competitors.length > 1 ? comp.competitors[1] : null);

    // The favorite+line summary (e.g. 'SEA -3.5'); fall back to the bare spread.
    final line = odds.details ??
        (odds.spread != null
            ? (odds.spread! > 0 ? '+${_trim(odds.spread!)}' : _trim(odds.spread!))
            : null);

    final top = <Widget>[
      if (line != null) _stat('Line', line),
      if (odds.overUnder != null) _stat('Total', _trim(odds.overUnder!)),
    ];

    final ml = <Widget>[];
    void chip(String? team, num? v) {
      final m = Odds.moneyline(v);
      if (team != null && m != null) ml.add(_mlChip(team, m));
    }

    chip(away?.label, odds.awayMoneyline);
    if (odds.drawMoneyline != null) chip('Draw', odds.drawMoneyline);
    chip(home?.label, odds.homeMoneyline);

    if (top.isEmpty && ml.isEmpty) return const SizedBox.shrink();
    return V2Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const CardLabel('Pre-game'),
        if (top.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < top.length; i++)
                Padding(
                  padding: EdgeInsets.only(right: i < top.length - 1 ? 32 : 0),
                  child: top[i],
                ),
            ],
          ),
        ],
        if (ml.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: ml),
        ],
        if (odds.provider != null) ...[
          const SizedBox(height: 10),
          Text('via ${odds.provider}', style: T.captionFaint),
        ],
      ]),
    );
  }
}

class _VenueCard extends StatelessWidget {
  final SportEvent event;
  final Competition? comp;
  final GameSummary? summary;
  // The baseball first page carries its own CURRENT WEATHER card — skip the
  // inline weather bit there so the two don't stack the same line.
  final bool includeWeather;
  const _VenueCard(this.event,
      {this.comp, this.summary, this.includeWeather = true});

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
      if (includeWeather &&
          event.weather != null &&
          event.weather!.summary.isNotEmpty)
        event.weather!.summary,
      if (attendance != null) 'Attendance ${_thousands(attendance)}',
      if (officials != null) officials,
      // Prefer the cheap single broadcast label; fall back to the flattened
      // network-name list when the competition didn't carry one.
      if (comp?.broadcast != null)
        comp!.broadcast!
      else if (event.broadcasts.isNotEmpty)
        event.broadcasts.join(' · '),
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

// ═══════════════════════ §2.9 Venue & Circuit tab ═══════════════════════════
// One detail tab, two shapes chosen by DATA PRESENCE (never sport name): a
// racing event with a circuit join id → [CircuitTab] (track map + facts + lap
// record, design 13a); else a stadium with a venue join id → [VenueTab] (photo +
// venue facts, design 14a); neither → no tab. This is the §1 situation-card
// dispatch lifted to a whole tab. The photo/map + fact grid are a single lazy
// CORE fetch on tab-open ([venueFactsProvider] / [circuitFactsProvider]); the
// roof/attendance/weather ride the cheap scoreboard already in hand.

/// Which §2.9 tab an event gets. Pure so the gate is unit-testable.
enum VenueTabKind { none, venue, circuit }

/// The §2.9 gate: a circuit id → Circuit; else a venue id → Venue; else none.
/// (Circuit wins because a racing event also carries a circuit-derived venue.)
VenueTabKind venueTabKind({String? venueId, String? circuitId}) =>
    (circuitId != null && circuitId.isNotEmpty)
        ? VenueTabKind.circuit
        : (venueId != null && venueId.isNotEmpty)
            ? VenueTabKind.venue
            : VenueTabKind.none;

/// One §2.9 fact cell (14a/13a): a faint small-caps label over a Barlow-30 value
/// with an optional small unit suffix (`7.004 KM`). r16, 14×16 pad, on `surface`.
class _FactCell extends StatelessWidget {
  final String label, value;
  final String? unit;
  const _FactCell({required this.label, required this.value, this.unit});

  static const _value = TextStyle(
      fontFamily: 'BarlowCondensed',
      fontWeight: FontWeight.w700,
      fontSize: 30,
      height: 1.0,
      color: T.text,
      fontFeatures: [FontFeature.tabularFigures()]);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
            color: T.surface,
            borderRadius: BorderRadius.circular(T.rowCardRadius)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(), style: T.cardLabelFaint),
          const SizedBox(height: 4),
          RichText(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(style: _value, text: value, children: [
              if (unit != null && unit!.isNotEmpty)
                TextSpan(
                    text: ' ${unit!.toUpperCase()}',
                    style: const TextStyle(
                        fontFamily: 'BarlowCondensed',
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                        color: T.textDim)),
            ]),
          ),
        ]),
      );
}

/// The 2-col fact grid (gap 10): cells flow two-per-row; an odd final cell spans
/// full width. Renders nothing when there are no served cells.
Widget _factGrid(List<Widget> cells) {
  if (cells.isEmpty) return const SizedBox.shrink();
  final rows = <Widget>[];
  for (var i = 0; i < cells.length; i += 2) {
    final right = i + 1 < cells.length ? cells[i + 1] : null;
    if (rows.isNotEmpty) rows.add(const SizedBox(height: 10));
    // IntrinsicHeight so the paired cells share the taller one's height (the
    // grid lives in a vertically-unbounded scroll view, where a bare stretch
    // Row would force an infinite height).
    rows.add(IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: cells[i]),
        if (right != null) ...[
          const SizedBox(width: 10),
          Expanded(child: right),
        ],
      ]),
    ));
  }
  return Column(children: rows);
}

String _thousands(int n) => n
    .toString()
    .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');

/// A measurement value without a trailing `.0` (`44.0` → `44`, `7.004` → `7.004`).
String _trimNum(num v) {
  final s = v.toString();
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

/// A photo/map placeholder well (design 14a/13a): a darker inset with a hint.
Widget _mediaWell(String hint, {double height = 180}) => Container(
      height: height,
      width: double.infinity,
      color: T.bg,
      alignment: Alignment.center,
      child: Text(hint.toUpperCase(), style: T.cardLabelFaint),
    );

/// Render a CDN diagram/photo by extension: `.svg` → [SvgPicture.network] (the
/// dark F1 circuit art is SVG-only; flutter_svg is the one justified dep), else
/// [Image.network]. Both degrade to a placeholder well on load failure.
Widget _networkArt(String href, String hint, {BoxFit fit = BoxFit.cover, double height = 180}) {
  final well = _mediaWell(hint, height: height);
  if (href.toLowerCase().contains('.svg')) {
    return SvgPicture.network(href,
        fit: fit, placeholderBuilder: (_) => well);
  }
  return Image.network(href,
      fit: fit,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => well,
      loadingBuilder: (ctx, child, progress) =>
          progress == null ? child : well);
}

/// The §2.9 Venue tab (design 14a): a photo card, then the served-cell fact grid
/// (surface/roof/attendance/weather), then a TONIGHT card when weather or
/// attendance is present. The photo + surface are the only fields that need the
/// lazy [venueFactsProvider] core fetch; roof/attendance/weather ride the cheap
/// scoreboard, so the tab is useful even before (or without) the facts.
class VenueTab extends ConsumerWidget {
  final String league;
  final SportEvent event;
  final Competition comp;
  final String? venueId;
  const VenueTab({
    super.key,
    required this.league,
    required this.event,
    required this.comp,
    this.venueId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facts = (venueId != null && venueId!.isNotEmpty)
        ? ref
            .watch(venueFactsProvider((league: league, venueId: venueId!)))
            .valueOrNull
        : null;
    final cells = _cells(facts);
    final tonight = _tonight();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _photo(facts),
      if (cells.isNotEmpty) ...[
        const SizedBox(height: T.gapCard),
        _factGrid(cells),
      ],
      if (tonight != null) ...[
        const SizedBox(height: T.gapCard),
        tonight,
      ],
    ]);
  }

  Widget _photo(VenueFacts? f) {
    final photo = f?.photo;
    final addr = _addressLine(f);
    return Container(
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(T.cardRadius),
        border: Border.all(color: T.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 210,
          child: photo != null && photo.isNotEmpty
              ? _networkArt(photo, 'Venue photo', height: 210)
              : _mediaWell('Venue photo', height: 210),
        ),
        if (addr != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Text(addr.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: T.cardLabelFaint.copyWith(color: T.textDim)),
          ),
      ]),
    );
  }

  /// `1060 W ADDISON ST · CHICAGO, IL` — address1 (rarely served) prepended to
  /// the city·state line; the city line alone when address1 is absent.
  String? _addressLine(VenueFacts? f) {
    final loc = (f != null && f.location.isNotEmpty)
        ? f.location
        : (event.venue?.location ?? '');
    final a1 = f?.address1;
    final parts = <String>[
      if (a1 != null && a1.isNotEmpty) a1,
      if (loc.isNotEmpty) loc,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  List<Widget> _cells(VenueFacts? f) {
    final cells = <Widget>[];
    // SURFACE — core `grass` bool only (not on the scoreboard); hide when absent.
    final surf = f?.surface;
    if (surf == 'grass' || surf == 'turf') {
      cells.add(_FactCell(
          label: 'Surface', value: surf == 'grass' ? 'GRASS' : 'TURF'));
    }
    // ROOF — the core `indoor` bool (present-only) preferred; the cheap venue's
    // `indoor` is a reliable signal only when true (it defaults false when the
    // field is absent), so open-air is shown only from the authoritative facts.
    final roof = f?.roof ?? (event.venue?.indoor == true ? 'indoor' : null);
    if (roof == 'indoor' || roof == 'open') {
      cells.add(_FactCell(
          label: 'Roof', value: roof == 'indoor' ? 'INDOOR' : 'OPEN AIR'));
    }
    // ATTENDANCE — cheap `competition.attendance`; 0 = not reported → hide.
    final att = comp.attendance;
    if (att != null && att > 0) {
      cells.add(_FactCell(label: 'Attendance', value: _thousands(att)));
    }
    // WEATHER — cheap event weather (temp + condition), ~1% (baseball/AFL).
    final w = event.weather;
    if (w != null && w.temperature != null) {
      cells.add(_FactCell(
          label: 'Weather',
          value: '${w.temperature!.round()}°',
          unit: w.condition));
    }
    return cells;
  }

  /// TONIGHT card (14a, lifted r20) — weather line + a big attendance figure.
  /// Only when weather or attendance is present. No wind row (NOT OBSERVED).
  Widget? _tonight() {
    final w = event.weather;
    final att = comp.attendance;
    final hasW = w != null && w.summary.isNotEmpty;
    final hasA = att != null && att > 0;
    if (!hasW && !hasA) return null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: T.sheet, borderRadius: BorderRadius.circular(T.cardRadius)),
      child: Row(children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('TONIGHT',
                style: T.cardLabelFaint
                    .copyWith(color: T.textDim, letterSpacing: 0.88)),
            if (hasW) ...[
              const SizedBox(height: 4),
              Text(w.summary,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: T.text)),
            ],
          ]),
        ),
        if (hasA)
          RichText(
            text: TextSpan(
              style: const TextStyle(
                  fontFamily: 'BarlowCondensed',
                  fontWeight: FontWeight.w700,
                  fontSize: 32,
                  height: 1.0,
                  color: T.text,
                  fontFeatures: [FontFeature.tabularFigures()]),
              text: _thousands(att),
              children: const [
                TextSpan(
                    text: ' ATT',
                    style: TextStyle(
                        fontFamily: 'Archivo',
                        fontWeight: FontWeight.w600,
                        fontSize: 17,
                        color: T.textDim)),
              ],
            ),
          ),
      ]),
    );
  }
}

/// The §2.9 Circuit tab (design 13a): a track-map card, then the served-cell fact
/// grid (length/distance/laps/turns), then a LAP RECORD card. Every field is the
/// lazy [circuitFactsProvider] core fetch (F1's `circuits/{id}`); non-F1 racing
/// carries no such resource, so [facts] is null → placeholders. The join id comes
/// from `event.circuit?.id` (see [_GameDetailPageState._venueTabIds]).
class CircuitTab extends ConsumerWidget {
  final String league;
  final SportEvent event;
  final Competition comp;
  final String? circuitId;
  const CircuitTab({
    super.key,
    required this.league,
    required this.event,
    required this.comp,
    this.circuitId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facts = (circuitId != null && circuitId!.isNotEmpty)
        ? ref
            .watch(circuitFactsProvider((league: league, circuitId: circuitId!)))
            .valueOrNull
        : null;
    final cells = _cells(facts);
    final lap = _lapRecord(facts);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _map(facts),
      if (cells.isNotEmpty) ...[
        const SizedBox(height: T.gapCard),
        _factGrid(cells),
      ],
      if (lap != null) ...[
        const SizedBox(height: T.gapCard),
        lap,
      ],
    ]);
  }

  Widget _map(CircuitFacts? f) {
    final diagram = f?.diagram;
    final dir = f?.direction;
    final est = f?.established;
    final hasFooter = (dir != null && dir.isNotEmpty) || est != null;
    return Container(
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(T.cardRadius),
        border: Border.all(color: T.divider),
      ),
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 180,
          child: diagram != null && diagram.isNotEmpty
              ? _networkArt(diagram, 'Circuit map',
                  fit: BoxFit.contain, height: 180)
              : _mediaWell('Circuit map', height: 180),
        ),
        if (hasFooter) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: T.divider))),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (dir != null && dir.isNotEmpty)
                    Text(dir.toUpperCase(),
                        style: T.cardLabelFaint.copyWith(color: T.textDim))
                  else
                    const SizedBox.shrink(),
                  if (est != null)
                    Text('Est. $est', style: T.captionFaint),
                ]),
          ),
        ],
      ]),
    );
  }

  List<Widget> _cells(CircuitFacts? f) {
    if (f == null) return const [];
    final cells = <Widget>[];
    void measure(String label, Measure? m) {
      if (m == null) return;
      final hasVal = m.value != null;
      cells.add(_FactCell(
          label: label,
          value: hasVal ? _trimNum(m.value!) : m.display,
          unit: hasVal ? m.unit : null));
    }

    measure('Circuit length', f.length);
    measure('Race distance', f.distance);
    if (f.laps != null) {
      cells.add(_FactCell(label: 'Laps', value: '${f.laps}'));
    }
    if (f.turns != null) {
      cells.add(_FactCell(label: 'Turns', value: '${f.turns}'));
    }
    return cells;
  }

  /// LAP RECORD card (13a, lifted r20): headshot slot + Barlow-32 time, with the
  /// driver name + year on the right. Only when a fastest-lap time is served.
  Widget? _lapRecord(CircuitFacts? f) {
    final lap = f?.fastestLap;
    if (lap == null || lap.time == null || lap.time!.isEmpty) return null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: T.sheet, borderRadius: BorderRadius.circular(T.cardRadius)),
      child: Row(children: [
        _headshot(lap.driverHeadshot, lap.driverName),
        const SizedBox(width: 14),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('LAP RECORD',
                style: T.cardLabelFaint
                    .copyWith(color: T.textDim, letterSpacing: 0.88)),
            const SizedBox(height: 4),
            Text(lap.time!,
                style: const TextStyle(
                    fontFamily: 'BarlowCondensed',
                    fontWeight: FontWeight.w700,
                    fontSize: 32,
                    height: 1.0,
                    color: T.text,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ]),
        ),
        if (lap.driverName != null || lap.year != null)
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (lap.driverName != null && lap.driverName!.isNotEmpty)
              Text(lap.driverName!,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: T.text)),
            if (lap.year != null) ...[
              const SizedBox(height: 3),
              Text('${lap.year}', style: T.captionFaint),
            ],
          ]),
      ]),
    );
  }

  Widget _headshot(String? url, String? name) {
    final avatar = TintedAvatar(_initials(name), T.track, size: 52);
    if (url == null || url.isEmpty) return ClipOval(child: avatar);
    return ClipOval(
      child: SizedBox(
        width: 52,
        height: 52,
        child: Stack(fit: StackFit.expand, children: [
          avatar,
          Image.network(url,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => const SizedBox.shrink()),
        ]),
      ),
    );
  }

  static String _initials(String? name) {
    final parts = (name ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
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
      width: 34,
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
        width: 34,
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
