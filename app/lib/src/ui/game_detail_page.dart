import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../config.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import 'box_score.dart';
import 'detail_panels.dart';
import 'field_leaderboard.dart';
import 'finish_grid.dart';
import 'poll.dart';
import 'score_tables.dart';
import 'summary_feed.dart';
import 'widgets.dart';

/// Soccer team-stat rows (cheap: scoreboard competitor.statistics by ESPN abbr).
/// Fouls is [invert]ed — fewer is better, so the lower side reads as the leader.
const List<({String key, String label, bool invert})> _soccerStatRows = [
  (key: 'PP', label: 'Possession %', invert: false),
  (key: 'SHOT', label: 'Shots', invert: false),
  (key: 'SOG', label: 'Shots on target', invert: false),
  (key: 'CW', label: 'Corners', invert: false),
  (key: 'FC', label: 'Fouls', invert: true),
];

// Sports whose per-period split is summary-only (scoreboard has no linescores).
const _richPeriodSports = {'basketball', 'football', 'hockey'};
// Sports where a scoring/timeline feed reads well (NOT basketball — too many).
const _scoringFeedSports = {'baseball', 'football', 'hockey', 'soccer', 'rugby'};

class GameDetailPage extends ConsumerStatefulWidget {
  final SportEvent event;
  final String sport;
  final String leagueKey; // 'baseball/mlb' — for the rich /summary fetch
  final String leagueName;
  const GameDetailPage({
    super.key,
    required this.event,
    required this.sport,
    required this.leagueKey,
    required this.leagueName,
  });

  @override
  ConsumerState<GameDetailPage> createState() => _GameDetailPageState();
}

/// Live while the game is: the cheap header/score are re-derived from a poll of
/// the league's scoreboard for the event's day (15s live / 60s pre-game), and
/// the rich /summary section re-fetches on the same beat. A scheduled game that
/// hasn't started yet polls slowly; any final stops. Falls back to the snapshot
/// the caller passed when the league isn't configured or the event has no date.
class _GameDetailPageState extends ConsumerState<GameDetailPage> with LifecyclePoll {
  bool _onTop = true; // false while another route is pushed over this one
  final ScrollController _scroll = ScrollController();
  bool _showMini = false; // the sticky mini-scoreline appears past this scroll

  @override
  void initState() {
    super.initState();
    attachPoll();
    _scroll.addListener(() {
      final show = _scroll.hasClients && _scroll.offset > 140;
      if (show != _showMini) setState(() => _showMini = show);
    });
    // pollInterval reads context (ModalRoute); pace after the first frame lands.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) repace();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Depend on the modal scope so this fires (and re-paces) when a route is
    // pushed over / popped off this one — pollInterval()'s gate alone wouldn't.
    _onTop = ModalRoute.of(context)?.isCurrent ?? true;
    repace();
  }

  @override
  void dispose() {
    _scroll.dispose();
    detachPoll();
    super.dispose();
  }

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}'
      '${d.month.toString().padLeft(2, '0')}'
      '${d.day.toString().padLeft(2, '0')}';

  /// The (league, day) to poll for a fresh copy of this event. A game happening
  /// *today* uses ESPN's default slate (date:null) so it shares the home feed's
  /// upstream cache entry instead of opening a second one; any other day uses an
  /// explicit YYYYMMDD. Null when the worker isn't configured or the event has no
  /// start — then the passed-in snapshot is all we have.
  ///
  /// (ESPN buckets days in US-Eastern; far from ET a near-midnight game can land
  /// on the adjacent day and the lookup miss, leaving the snapshot in place — the
  /// app's documented ET limitation, accepted rather than shipping a tz database.)
  LeagueDayKey? _liveKey() {
    final configured = ref.read(settingsProvider).baseUrl.trim().isNotEmpty;
    final start = widget.event.start;
    if (!configured || start == null) return null;
    final date = DateUtils.isSameDay(start, DateTime.now()) ? null : _ymd(start);
    return (league: widget.leagueKey, date: date);
  }

  /// The freshest copy of this event from the polled day (matched by id), or the
  /// snapshot when the fetch is loading/errored/missing it.
  SportEvent _pick(ScoresResponse? resp) {
    if (resp != null) {
      for (final e in resp.events) {
        if (e.id == widget.event.id) return e;
      }
    }
    return widget.event;
  }

  @override
  Duration? pollInterval() {
    if (!mounted || !_onTop) return null;
    final key = _liveKey();
    if (key == null) return null;
    // Read status fresh from the provider (not a build-time cache) so a re-pace
    // from the settle-listener can't arm the wrong cadence on stale state.
    final status = _pick(ref.read(leagueDayScoresProvider(key)).valueOrNull).main?.status;
    if (status?.live == true) return AppConfig.refreshLive; // 15s
    if (status?.isScheduled == true) return AppConfig.refreshIdle; // 60s — may tip off
    return null; // final / unknown → stop
  }

  @override
  void onPoll() {
    final key = _liveKey();
    if (key != null) ref.invalidate(leagueDayScoresProvider(key));
    ref.invalidate(summaryProvider((league: widget.leagueKey, eventId: widget.event.id)));
  }

  @override
  void onForeground() {
    final key = _liveKey();
    final status = _pick(key == null ? null : ref.read(leagueDayScoresProvider(key)).valueOrNull).main?.status;
    if (status?.live == true || status?.isScheduled == true) onPoll(); // catch up on resume
  }

  @override
  Widget build(BuildContext context) {
    final key = _liveKey();
    SportEvent ev = widget.event;
    if (key != null) {
      // Re-pace when the polled day settles (status may have flipped to final).
      ref.listen<AsyncValue<ScoresResponse>>(leagueDayScoresProvider(key), (_, next) {
        if (!next.isLoading) repace();
      });
      // valueOrNull keeps the previous value across a reload (Riverpod copies it),
      // so the header doesn't flicker; null on error/first-load → snapshot. The
      // silent fallback is intentional — the snapshot already answered the score.
      ev = _pick(ref.watch(leagueDayScoresProvider(key)).valueOrNull);
    }
    final comp = ev.main;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.leagueName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.1)),
            if (ev.start != null)
              Text(
                DateFormat.MMMEd().format(ev.start!.toLocal()),
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
      body: Stack(
        children: [
          ListView(
            controller: _scroll,
            padding: const EdgeInsets.all(16),
            children: _body(context, ev),
          ),
          if (comp != null && !comp.isField)
            _MiniScoreline(comp: comp, startTime: ev.start, show: _showMini),
        ],
      ),
    );
  }

  List<Widget> _body(BuildContext context, SportEvent event) {
    final sport = widget.sport;
    // MMA: an event is a whole card of bouts — show them all, not just one.
    if (sport == 'mma' && event.competitions.length > 1) {
      return [
        MmaCardList(bouts: event.competitions),
        const SizedBox(height: 8),
        _MetaCard(event: event, comp: event.main),
      ];
    }

    final comp = event.main;
    if (comp == null) {
      return const [EmptyState(icon: Icons.info_outline, title: 'No detail available')];
    }

    // Field sports (golf, racing): a purpose-built leaderboard / finish grid.
    if (comp.isField) {
      return [
        _Header(event: event, comp: comp, leagueKey: widget.leagueKey),
        const SizedBox(height: 16),
        if (sport == 'racing')
          FinishGrid(sessions: event.competitions)
        else
          FieldLeaderboard(comp: comp),
        const SizedBox(height: 16),
        _MetaCard(event: event, comp: comp),
      ];
    }

    // Head-to-head team sports: cheap sections, then the rich /summary section.
    final out = <Widget>[
      _Header(event: event, comp: comp, leagueKey: widget.leagueKey),
      const SizedBox(height: 16),
    ];
    if (comp.method != null) out.add(_MethodCard(method: comp.method!));

    if (LiveSituationStrip.has(comp)) {
      out.addAll([
        const SectionLabel('Now batting'),
        LiveSituationStrip(comp: comp),
        const SizedBox(height: 16),
      ]);
    }

    final away = comp.away ?? (comp.competitors.isNotEmpty ? comp.competitors[0] : null);
    final home = comp.home ?? (comp.competitors.length > 1 ? comp.competitors[1] : null);

    _addScoreGrid(out, comp);

    if (comp.status.isScheduled && away != null && home != null && ProbablesRow.has(away, home)) {
      out.addAll([
        const SectionLabel('Probable starters'),
        ProbablesRow(away: away, home: home),
        const SizedBox(height: 16),
      ]);
    }

    if (away != null && home != null && LeadersStrip.has(away, home)) {
      out.addAll([
        const SectionLabel('Leaders'),
        LeadersStrip(away: away, home: home),
        const SizedBox(height: 16),
      ]);
    }

    if (sport == 'soccer' &&
        away != null &&
        home != null &&
        TeamStatComparison.has(away, home, _soccerStatRows)) {
      out.addAll([
        const SectionLabel('Team stats'),
        TeamStatComparison(away: away, home: home, rows: _soccerStatRows),
        const SizedBox(height: 16),
      ]);
    }

    if (away != null && home != null && FormStrip.has(away, home)) {
      out.addAll([
        const SectionLabel('Recent form'),
        FormStrip(away: away, home: home),
        const SizedBox(height: 16),
      ]);
    }

    // The rich tier: a separate /summary fetch, lazy + best-effort.
    final liveClock = comp.status.live
        ? (comp.status.clock?.isNotEmpty == true ? comp.status.clock! : comp.status.periodLabel)
        : null;
    out.add(_RichDetail(
        leagueKey: widget.leagueKey, eventId: event.id, sport: sport, liveClock: liveClock));

    out.add(_MetaCard(event: event, comp: comp));
    return out;
  }

  void _addScoreGrid(List<Widget> out, Competition comp) {
    void add(String label, Widget w) =>
        out.addAll([SectionLabel(label), w, const SizedBox(height: 16)]);

    final hasPeriods = comp.competitors.any((c) => c.periodScores.isNotEmpty);
    switch (widget.sport) {
      case 'baseball':
        if (hasPeriods || comp.competitors.any((c) => c.hasRHE)) {
          add('Line score', LineScoreTable(comp: comp, baseball: true));
        }
      case 'cricket':
        add('Innings', InningsStack(comp: comp));
      case 'tennis':
        if (hasPeriods) add('Sets', SetStrip(comp: comp));
      case 'soccer':
      case 'mma':
      case 'racing':
      case 'golf':
      case 'rugby':
        break;
      default:
        // basketball/football/hockey carry their per-period split in the rich
        // (summary) tier — _RichDetail renders it as 'Line score'. WNBA's
        // scoreboard *also* ships linescores, which would render a second,
        // duplicate 'Line score' here; so defer those sports to the rich grid.
        if (!_richPeriodSports.contains(widget.sport) &&
            comp.competitors.any((c) => c.periodScores.length > 1)) {
          add('Line score', LineScoreTable(comp: comp, baseball: false));
        }
    }
  }
}

/// The rich game-detail section: box score, scoring feed, team stats, lineups,
/// summary-tier period grid. Fetched lazily from /summary; failures stay quiet
/// (the cheap sections above already answered "what's the score").
class _RichDetail extends ConsumerWidget {
  final String leagueKey, eventId, sport;
  final String? liveClock; // non-null on a live game → "NOW" marker in the timeline
  const _RichDetail(
      {required this.leagueKey, required this.eventId, required this.sport, this.liveClock});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configured = ref.watch(settingsProvider.select((s) => s.baseUrl)).trim().isNotEmpty;
    if (!configured) return const SizedBox.shrink();
    final async = ref.watch(summaryProvider((league: leagueKey, eventId: eventId)));
    return async.when(
      // Keep the rendered box score on a poll-driven reload instead of blinking
      // back to the skeleton every cadence — only the first load shows it.
      skipLoadingOnReload: true,
      loading: () => const _RichSkeleton(),
      error: (_, __) => const SizedBox.shrink(),
      data: (s) => s.isEmpty ? const SizedBox.shrink() : _sections(context, s),
    );
  }

  Widget _sections(BuildContext context, GameSummary s) {
    final out = <Widget>[];
    void add(String label, Widget w) =>
        out.addAll([SectionLabel(label), w, const SizedBox(height: 16)]);

    if (_richPeriodSports.contains(sport) && s.periodLines != null) {
      add('Line score', PeriodLinesGrid(lines: s.periodLines!));
    }
    if (sport != 'soccer' && s.teamStats.isNotEmpty) {
      add('Team stats', SummaryTeamStats(rows: s.teamStats));
    }
    if (_scoringFeedSports.contains(sport) && s.scoringPlays.isNotEmpty) {
      add(sport == 'soccer' ? 'Timeline' : 'Scoring',
          ScoringFeed(plays: s.scoringPlays, sport: sport, nowLabel: liveClock));
    }
    if (s.boxGroups.isNotEmpty) {
      add('Box score', BoxScoreTable(groups: s.boxGroups));
    }
    if (s.lineups.isNotEmpty) {
      add('Lineups', LineupsView(lineups: s.lineups));
    }
    if (out.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: out);
  }
}

class _RichSkeleton extends StatelessWidget {
  const _RichSkeleton();
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget bar(double w) => Container(
          width: w,
          height: 12,
          margin: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionLabel('Box score'),
      DetailPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          bar(140),
          bar(double.infinity),
          bar(double.infinity),
          bar(220),
        ]),
      ),
      const SizedBox(height: 16),
    ]);
  }
}

class _Header extends StatelessWidget {
  final SportEvent event;
  final Competition comp;
  final String leagueKey;
  const _Header({required this.event, required this.comp, required this.leagueKey});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (comp.isField) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(event.name, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          StatusChip(status: comp.status, startTime: event.start),
        ],
      );
    }
    final a = comp.home ?? (comp.competitors.isNotEmpty ? comp.competitors[0] : null);
    final b = comp.away ?? (comp.competitors.length > 1 ? comp.competitors[1] : null);
    // Team-color victor wash on a final result (winner emphasis stays team-color);
    // shared with the scores-list card so the two never drift.
    return Container(
      decoration: BoxDecoration(
        gradient: winnerWashGradient(context, comp),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 16),
      child: Column(
        children: [
          Center(child: StatusChip(status: comp.status, startTime: event.start)),
          const SizedBox(height: 16),
          if (a != null) _bigRow(context, comp, a),
          const SizedBox(height: 14),
          if (b != null) _bigRow(context, comp, b),
          if (comp.decision != null && comp.decision != 'regulation') ...[
            const SizedBox(height: 12),
            Text(_decisionText(comp),
                style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }

  Widget _bigRow(BuildContext context, Competition comp, Competitor c) {
    final cs = Theme.of(context).colorScheme;
    final dim = comp.status.isFinal && c.winner == false;
    return Row(
      children: [
        Crest(url: c.logo, darkUrl: c.logoDark, fallback: c.abbreviation ?? c.displayName, size: 40),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: c.isWinner ? FontWeight.w700 : FontWeight.w500,
                    color: dim ? cs.onSurfaceVariant : cs.onSurface,
                  )),
              if (c.recordSummary != null)
                Text(c.recordSummary!, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        if (comp.scoreKind == 'none')
          (c.isWinner
              ? Icon(Icons.check_circle, color: BinanceColors.of(context).accent)
              : const SizedBox.shrink())
        else
          Text(
            c.score?.display.isNotEmpty == true ? c.score!.display : '–',
            style: numStyle(
              size: 36,
              weight: FontWeight.w800,
              letterSpacing: -0.5,
              color: dim ? cs.onSurfaceVariant : cs.onSurface,
            ),
          ),
        // Favorite this team (team sports only — not athletes/pairs).
        if (c.kind == 'team') ...[
          const SizedBox(width: 4),
          _FavStar(leagueKey: leagueKey, competitor: c),
        ],
      ],
    );
  }

  String _decisionText(Competition comp) {
    switch (comp.decision) {
      case 'overtime':
        return 'After overtime';
      case 'shootout':
        return 'Decided on penalties';
      case 'aggregate':
        return 'Decided on aggregate';
      case 'draw':
        return 'Draw';
      case 'method':
        return comp.method?.summary ?? 'Decision';
      default:
        return comp.decision ?? '';
    }
  }
}

class _MethodCard extends StatelessWidget {
  final Method method;
  const _MethodCard({required this.method});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: DetailPanel(
          child: Row(children: [
            const Icon(Icons.sports_mma),
            const SizedBox(width: 12),
            Expanded(child: Text(method.summary)),
          ]),
        ),
      );
}

class _MetaCard extends StatelessWidget {
  final SportEvent event;
  final Competition? comp;
  const _MetaCard({required this.event, required this.comp});
  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    void add(IconData icon, String text) {
      if (text.trim().isEmpty) return;
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ]),
      ));
    }

    if (event.venue != null) {
      add(Icons.stadium_outlined,
          [event.venue!.name, event.venue!.location].where((s) => s.isNotEmpty).join(' · '));
    }
    if (event.broadcasts.isNotEmpty) add(Icons.tv_outlined, event.broadcasts.join(', '));
    for (final n in event.notes) {
      add(Icons.info_outline, n);
    }
    if (comp?.meta?.cricketSummary != null) {
      add(Icons.sports_cricket_outlined, comp!.meta!.cricketSummary!);
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return DetailPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows));
  }
}

/// Star toggle for favoriting a team straight from the game detail. Writes the
/// same [favoriteTeamsProvider] the Settings manager uses.
class _FavStar extends ConsumerWidget {
  final String leagueKey;
  final Competitor competitor;
  const _FavStar({required this.leagueKey, required this.competitor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFav = ref.watch(favoriteTeamsProvider
        .select((favs) => favs.any((f) => f.league == leagueKey && f.teamId == competitor.id)));
    return IconButton(
      tooltip: isFav ? 'Unfavorite' : 'Favorite',
      icon: Icon(isFav ? Icons.star : Icons.star_border,
          color: isFav ? BinanceColors.of(context).victor : null),
      onPressed: () => ref.read(favoriteTeamsProvider.notifier).toggle(FavoriteTeam(
            league: leagueKey,
            teamId: competitor.id,
            name: competitor.displayName,
            abbr: competitor.abbreviation,
            logo: competitor.logo,
          )),
    );
  }
}

/// Sticky mini-scoreline that slides in from the top once the hero scrolls out of
/// view, so the score stays glanceable while reading the timeline/stats below.
class _MiniScoreline extends StatelessWidget {
  final Competition comp;
  final DateTime? startTime;
  final bool show;
  const _MiniScoreline({required this.comp, required this.startTime, required this.show});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ext = BinanceColors.of(context);
    final home = comp.home ?? (comp.competitors.isNotEmpty ? comp.competitors.first : null);
    final away = comp.away ?? (comp.competitors.length > 1 ? comp.competitors[1] : null);
    if (home == null || away == null) return const SizedBox.shrink();
    final sched = comp.status.isScheduled;
    final live = comp.status.live;

    String sc(Competitor c) =>
        sched ? '–' : (c.score?.display.isNotEmpty == true ? c.score!.display : '–');
    String abbr(Competitor c) => c.abbreviation ?? c.shortName ?? c.displayName;
    Widget crest(Competitor c) =>
        Crest(url: c.logo, darkUrl: c.logoDark, fallback: abbr(c), size: 22);
    Widget name(Competitor c) => Text(abbr(c),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface));

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !show,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          offset: show ? Offset.zero : const Offset(0, -1),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: show ? 1 : 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: 0.97),
                border: Border(bottom: BorderSide(color: ext.cardBorder)),
              ),
              child: Row(children: [
                crest(home),
                const SizedBox(width: 8),
                name(home),
                const SizedBox(width: 10),
                Text(sc(home), style: numStyle(size: 15, weight: FontWeight.w800)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text('–', style: TextStyle(color: cs.onSurfaceVariant)),
                ),
                Text(sc(away), style: numStyle(size: 15, weight: FontWeight.w800)),
                const SizedBox(width: 10),
                name(away),
                const SizedBox(width: 8),
                crest(away),
                if (live) ...[
                  const Spacer(),
                  StatusChip(status: comp.status, startTime: startTime),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
