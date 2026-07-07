import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import '../util.dart';
import 'league_card.dart';
import 'poll.dart';
import 'standings_table.dart';
import 'widgets.dart';

/// Open a team's detail page (schedule / roster / season stats / standing).
/// Mirrors [openLeaguePage]. `name`/`color` seed the header before the fetch
/// resolves (so a tap from a standings row / hero card renders instantly).
void openTeamPage(
  BuildContext context,
  String league, {
  required String teamId,
  String? name,
  String? color,
}) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => TeamPage(
        league: league, teamId: teamId, name: name, color: color),
  ));
}

/// A team page: identity header + a live/next strip (polled while live) over a
/// single scroll of Schedule / Standing / Season stats / Roster cards. No chip
/// nav — restraint. Missing sections render nothing.
class TeamPage extends ConsumerStatefulWidget {
  final String league, teamId;
  final String? name, color;
  const TeamPage({
    super.key,
    required this.league,
    required this.teamId,
    this.name,
    this.color,
  });

  @override
  ConsumerState<TeamPage> createState() => _TeamPageState();
}

class _TeamPageState extends ConsumerState<TeamPage> with LifecyclePoll {
  TeamKey get _key => (league: widget.league, teamId: widget.teamId);

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

  // Only the live/next card needs refreshing — poll 15s while the team is
  // playing, otherwise leave it (the schedule/roster/stats are slow-moving and
  // ride the worker's 30m cache).
  @override
  Duration? pollInterval() {
    final card = ref.read(teamCardProvider(_key)).valueOrNull;
    return card?.anyLive == true ? AppConfig.refreshLive : null;
  }

  @override
  void onPoll() => ref.invalidate(teamCardProvider(_key));

  @override
  void onForeground() => onPoll();

  @override
  Widget build(BuildContext context) {
    ref.listen(teamCardProvider(_key), (_, __) => repace());
    final detail = ref.watch(teamDetailProvider(_key));
    final card = ref.watch(teamCardProvider(_key)).valueOrNull;
    final title =
        detail.valueOrNull?.team.displayName ?? widget.name ?? widget.teamId;

    return Scaffold(
      appBar: subpageBar(context, title),
      body: switch (detail) {
        AsyncData(:final value) => _body(value, card),
        AsyncError() => const Padding(
            padding: EdgeInsets.all(T.pageMargin),
            child: HintCard('Couldn’t load this team.'),
          ),
        _ => const Padding(
            padding: EdgeInsets.only(top: 100),
            child: Center(child: CircularProgressIndicator(color: T.gold)),
          ),
      },
    );
  }

  Widget _body(TeamDetail d, TeamCard? card) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        _IdentityHeader(
          league: widget.league,
          teamId: widget.teamId,
          team: d.team,
          seedColor: widget.color,
        ),
        if (card?.live != null)
          _LiveStrip(league: widget.league, event: card!.live!),
        if (d.schedule.isNotEmpty) ...[
          const _SectionLabel('Schedule'),
          _ScheduleCard(league: widget.league, schedule: d.schedule),
        ],
        if (d.standing != null) ...[
          const _SectionLabel('Standing'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: T.pageMargin),
            child: StandingsGroupCard(
              name: d.standing!.groupName,
              rows: d.standing!.rows,
              columns: d.standing!.columns,
              highlightIds: {widget.teamId},
            ),
          ),
        ],
        if (d.stats.isNotEmpty) ...[
          const _SectionLabel('Season stats'),
          for (final g in d.stats)
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(T.pageMargin, 0, T.pageMargin, 12),
              child: _StatsCard(g),
            ),
        ],
        if (d.roster.isNotEmpty) ...[
          const _SectionLabel('Roster'),
          Padding(
            padding:
                const EdgeInsets.fromLTRB(T.pageMargin, 0, T.pageMargin, 0),
            child: _RosterCard(d.roster),
          ),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(T.pageMargin, 22, T.pageMargin, 8),
        child: Text(text.toUpperCase(), style: T.cardLabelFaint),
      );
}

/// Crest + name + 'record · standing' line, with a favorite toggle star.
class _IdentityHeader extends ConsumerWidget {
  final String league, teamId;
  final TeamCardTeam team;
  final String? seedColor;
  const _IdentityHeader({
    required this.league,
    required this.teamId,
    required this.team,
    this.seedColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favs = ref.watch(favoriteTeamsProvider);
    final isFav =
        favs.any((f) => f.league == league && f.teamId == teamId);
    final sub = [
      if (team.record != null) team.record!,
      if (team.standingSummary != null) team.standingSummary!,
    ].join('  ·  ');
    final abbr =
        team.abbreviation ?? (team.displayName.split(' ').last);
    return Padding(
      padding: const EdgeInsets.fromLTRB(T.pageMargin, 6, T.pageMargin, 2),
      child: Row(children: [
        // §10 team-page identity: a 44px r12 SOLID team-color square with a
        // Barlow abbr (badge-scale identity fill), not a ring circle.
        SquareCrest(
            abbr: abbr, color: teamColorOf(team.color ?? seedColor), size: 44),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // §10/§3 scoreboard voice: Barlow Condensed 24, not Archivo.
                Text(team.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: 'BarlowCondensed',
                        fontWeight: FontWeight.w700,
                        fontSize: 24,
                        height: 1.0,
                        color: T.text)),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(sub,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: T.caption),
                ],
              ]),
        ),
        IconButton(
          icon: Icon(isFav ? Icons.star_rounded : Icons.star_border_rounded,
              color: isFav ? T.gold : T.textDim, size: 24),
          onPressed: () => ref.read(favoriteTeamsProvider.notifier).toggle(
                FavoriteTeam(
                  league: league,
                  teamId: teamId,
                  name: team.displayName,
                  abbr: team.abbreviation,
                  logo: team.logo,
                  color: team.color ?? seedColor,
                ),
              ),
        ),
      ]),
    );
  }
}

/// The team's live game, straight from the (polled) team card.
class _LiveStrip extends StatelessWidget {
  final String league;
  final SportEvent event;
  const _LiveStrip({required this.league, required this.event});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(T.pageMargin, 12, T.pageMargin, 0),
        child: Container(
          decoration: BoxDecoration(
            color: T.surface,
            borderRadius: BorderRadius.circular(T.rowCardRadius),
          ),
          clipBehavior: Clip.antiAlias,
          child: LeagueEventRow(league: league, event: event, divider: false),
        ),
      );
}

/// Last games + next games as dense rows (reusing the feed row idiom), with a
/// quiet expander for the full season.
class _ScheduleCard extends StatefulWidget {
  final String league;
  final List<SportEvent> schedule; // start-ascending
  const _ScheduleCard({required this.league, required this.schedule});

  @override
  State<_ScheduleCard> createState() => _ScheduleCardState();
}

class _ScheduleCardState extends State<_ScheduleCard> {
  bool _expanded = false;
  static const _recent = 5, _ahead = 5;

  @override
  Widget build(BuildContext context) {
    final all = widget.schedule;
    final upcoming =
        all.where((e) => e.main?.status.isScheduled ?? false).toList();
    // played/live/postponed — everything not still-scheduled, ascending
    final past =
        all.where((e) => !(e.main?.status.isScheduled ?? false)).toList();
    final recent =
        past.length <= _recent ? past : past.sublist(past.length - _recent);
    final shown = _expanded ? all : [...recent, ...upcoming.take(_ahead)];
    final canExpand = shown.length < all.length || _expanded;

    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: T.pageMargin),
        child: Container(
          decoration: BoxDecoration(
            color: T.surface,
            borderRadius: BorderRadius.circular(T.rowCardRadius),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (var i = 0; i < shown.length; i++)
              LeagueEventRow(
                  league: widget.league, event: shown[i], divider: i > 0),
          ]),
        ),
      ),
      if (canExpand)
        TextButton.icon(
          onPressed: () => setState(() => _expanded = !_expanded),
          icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more,
              size: 18),
          label: Text(_expanded ? 'Recent & upcoming' : 'Full season',
              style:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          style: TextButton.styleFrom(foregroundColor: T.textDim),
        ),
    ]);
  }
}

/// §10 "Stat tiles": a section label over a 2-column grid (10px gap) of shared
/// [StatTile]s — track-r14 tiles with a Barlow-24 value, a dim label, and an
/// optional semantic rank chip. Replaces the old name/value list rows.
class _StatsCard extends StatelessWidget {
  final TeamStatGroup group;
  const _StatsCard(this.group);

  @override
  Widget build(BuildContext context) {
    final stats = group.stats;
    // 2-col grid: pair the stats up so each tile takes ~half width with a 10px
    // gap. An odd trailing stat pads with a spacer so it stays half-width.
    final rows = <Widget>[];
    for (var i = 0; i < stats.length; i += 2) {
      if (i > 0) rows.add(const SizedBox(height: 10));
      final left = _tile(stats[i]);
      final right = i + 1 < stats.length ? _tile(stats[i + 1]) : null;
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left),
          const SizedBox(width: 10),
          Expanded(child: right ?? const SizedBox.shrink()),
        ],
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      CardLabel(group.name),
      const SizedBox(height: 8),
      ...rows,
    ]);
  }

  Widget _tile(TeamStatItem s) => StatTile(
        value: s.value,
        label: s.label,
        // The model carries no league size, so default to 30 — the chip colors
        // by goodness thirds, so an exact denominator isn't needed to place a
        // rank in the good/middle/bottom band.
        rankChip: s.rank != null
            ? SemanticRankChip(label: '#${s.rank}', rank: s.rank!, total: 30)
            : null,
      );
}

/// Collapsible roster groups. A single flat group shows expanded; position-
/// grouped rosters open on the first group and toggle the rest.
class _RosterCard extends StatefulWidget {
  final List<RosterGroup> groups;
  const _RosterCard(this.groups);

  @override
  State<_RosterCard> createState() => _RosterCardState();
}

class _RosterCardState extends State<_RosterCard> {
  late final Set<int> _open;

  @override
  void initState() {
    super.initState();
    // single group → open; multiple → open the first only.
    _open = widget.groups.length == 1 ? {0} : {0};
  }

  @override
  Widget build(BuildContext context) => V2Card(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        child: Column(children: [
          for (var i = 0; i < widget.groups.length; i++)
            _group(i, widget.groups[i], first: i == 0),
        ]),
      );

  Widget _group(int i, RosterGroup g, {required bool first}) {
    final open = _open.contains(i);
    final single = widget.groups.length == 1;
    return Column(children: [
      if (!single)
        InkWell(
          onTap: () => setState(
              () => open ? _open.remove(i) : _open.add(i)),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: first
                ? null
                : const BoxDecoration(
                    border: Border(top: BorderSide(color: T.divider))),
            child: Row(children: [
              Expanded(child: Text(g.name.toUpperCase(), style: T.cardLabel)),
              Text('${g.athletes.length}', style: T.captionFaint),
              const SizedBox(width: 6),
              Icon(open ? Icons.expand_less : Icons.expand_more,
                  size: 18, color: T.textDim),
            ]),
          ),
        ),
      if (open || single)
        Column(children: [
          if (single) const SizedBox(height: 8),
          for (var k = 0; k < g.athletes.length; k++)
            _athleteRow(g.athletes[k], divider: k > 0 || (!single)),
          const SizedBox(height: 6),
        ]),
    ]);
  }

  Widget _athleteRow(RosterAthlete a, {required bool divider}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: divider
            ? const BoxDecoration(
                border: Border(top: BorderSide(color: T.divider)))
            : null,
        child: Row(children: [
          SizedBox(
            width: 30,
            child: Text(a.jersey ?? '',
                style: T.statLine.copyWith(color: T.textFaint)),
          ),
          Expanded(
            child: Text(a.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: T.listText),
          ),
          if (a.position != null && a.position!.isNotEmpty)
            Text(a.position!,
                style: const TextStyle(fontSize: 13, color: T.textDim)),
        ]),
      );
}
