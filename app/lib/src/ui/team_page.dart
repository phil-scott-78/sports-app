import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import '../util.dart';
import 'follow_sheet.dart';
import 'league_card.dart';
import 'player_page.dart';
import 'poll.dart';
import 'standings_table.dart';
import 'widgets.dart';

/// Open a team's overview page (design 11a–11d). Mirrors [openLeaguePage].
/// `name`/`color` seed the header before the fetch resolves (so a tap from a
/// standings row / hero card renders instantly).
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

/// A team page in the shared overview grammar: identity header + data-driven chip
/// tabs. The default OVERVIEW tab stacks a next-game card, a recent-form card, a
/// team-leaders card, and ONE sport-specific module (probables → else a standings
/// snippet), each gated on data presence — never on league name. The Schedule /
/// Roster / Stats-or-Table tabs carry the deep sections. Missing data renders
/// nothing, cleanly.
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
  int _tab = 0;

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
  // playing, otherwise leave it (schedule/roster/stats are slow-moving).
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
    final leaders = ref.watch(teamLeadersProvider(_key)).valueOrNull;
    final card = ref.watch(teamCardProvider(_key)).valueOrNull;
    final d = detail.valueOrNull;
    final tableStyle = d != null && _isTableStyle(d.standing);

    return Scaffold(
      appBar: overviewBar(context, tableStyle ? 'CLUB' : 'TEAM',
          trailing: _FavStar(
            league: widget.league,
            teamId: widget.teamId,
            team: d?.team,
            seedName: widget.name,
            seedColor: widget.color,
          )),
      body: switch (detail) {
        AsyncData(:final value) => _body(value, card, leaders),
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

  Widget _body(TeamDetail d, TeamCard? card, TeamSeasonLeaders? leaders) {
    final color = teamColorOf(d.team.color ?? widget.color);
    final tableStyle = _isTableStyle(d.standing);

    // Tabs are data-driven: a section's chip appears only when it carries data,
    // and table-style leagues (a points table) label them Fixtures/Squad/Table.
    final tabs = <(String, _Tab)>[('Overview', _Tab.overview)];
    if (d.schedule.isNotEmpty) {
      tabs.add((tableStyle ? 'Fixtures' : 'Schedule', _Tab.schedule));
    }
    if (d.roster.isNotEmpty) {
      tabs.add((tableStyle ? 'Squad' : 'Roster', _Tab.roster));
    }
    if (tableStyle && d.standing != null) {
      tabs.add(('Table', _Tab.table));
    } else if (d.stats.isNotEmpty) {
      tabs.add(('Stats', _Tab.stats));
    }
    final tab = tabs[_tab.clamp(0, tabs.length - 1)].$2;

    return ListView(
      padding: const EdgeInsets.only(bottom: T.scrollBottom),
      children: [
        _IdentityHeader(team: d.team, color: color),
        const SizedBox(height: 6),
        ChipNav(
          items: [for (final t in tabs) t.$1],
          selected: _tab.clamp(0, tabs.length - 1),
          onTap: (i) => setState(() => _tab = i),
        ),
        const SizedBox(height: 8),
        ..._tabBody(tab, d, card, leaders, color, tableStyle),
      ],
    );
  }

  List<Widget> _tabBody(_Tab tab, TeamDetail d, TeamCard? card,
      TeamSeasonLeaders? leaders, Color color, bool tableStyle) {
    switch (tab) {
      case _Tab.schedule:
        return [_ScheduleCard(league: widget.league, schedule: d.schedule)];
      case _Tab.roster:
        return [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: T.pageMargin),
            child: _RosterCard(
                league: widget.league, teamId: widget.teamId, groups: d.roster),
          ),
        ];
      case _Tab.table:
        return [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: T.pageMargin),
            child: StandingsGroupCard(
              name: d.standing!.groupName,
              rows: d.standing!.rows,
              columns: d.standing!.columns,
              highlightIds: {widget.teamId},
              onRowTap: (r) => openTeamPage(context, widget.league,
                  teamId: r.team.id, name: r.team.name),
              onRowLongPress: _standingsLongPress,
            ),
          ),
        ];
      case _Tab.stats:
        return [
          for (final g in d.stats)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  T.pageMargin, 0, T.pageMargin, 12),
              child: _StatsCard(g),
            ),
        ];
      case _Tab.overview:
        return _overview(d, card, leaders, color, tableStyle);
    }
  }

  List<Widget> _overview(TeamDetail d, TeamCard? card,
      TeamSeasonLeaders? leaders, Color color, bool tableStyle) {
    final out = <Widget>[];
    void card_(Widget w) {
      if (out.isNotEmpty) out.add(const SizedBox(height: T.gapCard));
      out.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: T.pageMargin),
        child: w,
      ));
    }

    if (card?.live != null) {
      card_(_liveStrip(card!.live!));
    }
    final next = _nextScheduled(d.schedule);
    if (next != null) {
      final w = _NextGameCard(
          league: widget.league,
          event: next,
          teamId: widget.teamId,
          tableStyle: tableStyle);
      card_(w);
    }
    final form = _FormCard.maybe(d.schedule, widget.teamId);
    if (form != null) card_(form);
    if (leaders != null && leaders.categories.isNotEmpty) {
      card_(_LeadersCard(
          league: widget.league,
          teamId: widget.teamId,
          categories: leaders.categories,
          color: color,
          colorHex: d.team.color ?? widget.color));
    }
    // ONE sport module by data presence: probables (pre-game SP/goalie), else a
    // division/table snippet centred on this team.
    final probables = next != null ? _ProbablesCard.maybe(next) : null;
    if (probables != null) {
      card_(probables);
    } else if (d.standing != null && d.standing!.rows.isNotEmpty) {
      final rows = _neighborRows(d.standing!, widget.teamId);
      card_(StandingsGroupCard(
        name: d.standing!.groupName,
        rows: rows,
        columns: d.standing!.columns,
        highlightIds: {widget.teamId},
        onRowTap: (r) => openTeamPage(context, widget.league,
            teamId: r.team.id, name: r.team.name),
        onRowLongPress: _standingsLongPress,
      ));
    }
    return out;
  }

  /// Long-press a standings row → the follow sheet for that team (the same
  /// add grammar as the home feed rows).
  void _standingsLongPress(StandingsRow r) => showTeamFollowSheet(
        context,
        league: widget.league,
        teamId: r.team.id,
        name: r.team.name,
        abbr: r.team.abbr,
        color: cachedTeamColor(r.team.id),
      );

  Widget _liveStrip(SportEvent event) => Container(
        decoration: BoxDecoration(
          color: T.surface,
          borderRadius: BorderRadius.circular(T.rowCardRadius),
        ),
        clipBehavior: Clip.antiAlias,
        child: LeagueEventRow(
            league: widget.league, event: event, divider: false),
      );
}

enum _Tab { overview, schedule, roster, table, stats }

/// A points-table league (soccer/rugby): its standing is ranked on POINTS, so
/// the tabs read Fixtures/Squad/Table and the form card counts pts/5. Detected
/// from the standing columns, never the sport name.
bool _isTableStyle(TeamStanding? s) =>
    s != null &&
    s.columns.any((c) =>
        c.key.toLowerCase() == 'points' ||
        c.key.toLowerCase() == 'pts' ||
        c.label.toUpperCase() == 'PTS');

/// The first still-scheduled event on the (start-ascending) schedule.
SportEvent? _nextScheduled(List<SportEvent> schedule) {
  for (final e in schedule) {
    if (e.main?.status.isScheduled ?? false) return e;
  }
  return null;
}

/// This team's row ± one neighbour from its standings group (design 11b/11d),
/// rank-sorted when ranks are served, else in payload order.
List<StandingsRow> _neighborRows(TeamStanding s, String teamId) {
  var rows = s.rows;
  if (rows.any((r) => r.rank != null)) {
    rows = List.of(rows)
      ..sort((a, b) => (a.rank ?? 1 << 20).compareTo(b.rank ?? 1 << 20));
  }
  if (rows.length <= 3) return rows;
  final idx = rows.indexWhere((r) => r.team.id == teamId);
  if (idx < 0) return rows.take(3).toList();
  final start = (idx - 1).clamp(0, rows.length - 3);
  return rows.sublist(start, start + 3);
}

// ---- identity header --------------------------------------------------------

/// 80px logo + Barlow-34 stacked name + 'swatch · record · standing' line (11a).
class _IdentityHeader extends StatelessWidget {
  final TeamCardTeam team;
  final Color color;
  const _IdentityHeader({required this.team, required this.color});

  @override
  Widget build(BuildContext context) {
    final parts = <Widget>[];
    void dot() {
      if (parts.isNotEmpty) {
        parts.add(
            const Text('·', style: TextStyle(fontSize: 12.5, color: T.textFaint)));
      }
    }

    if (team.record != null && team.record!.isNotEmpty) {
      dot();
      parts.add(Text(team.record!,
          style: const TextStyle(
              fontSize: 12.5, fontWeight: FontWeight.w600, color: T.text)));
    }
    if (team.standingSummary != null && team.standingSummary!.isNotEmpty) {
      dot();
      parts.add(Flexible(
          child: Text(team.standingSummary!,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: T.caption)));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(T.pageMargin, 8, T.pageMargin, 6),
      child: Row(children: [
        LogoAvatar(
            // Dark-surface logo first (§3.1); cache-join fills it when the team
            // payload shipped no logo but a scoreboard already did.
            url: team.logoDark ?? team.logo ?? cachedTeamLogo(team.id),
            initials: initialsOf(team.displayName),
            color: color,
            teamId: team.id,
            size: 80),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(team.displayName.toUpperCase(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: 'BarlowCondensed',
                        fontWeight: FontWeight.w700,
                        fontSize: 34,
                        height: 0.95,
                        color: T.text)),
                const SizedBox(height: 7),
                Row(children: [
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                        color: color, borderRadius: BorderRadius.circular(3)),
                  ),
                  Expanded(
                    child: Row(children: [
                      for (var i = 0; i < parts.length; i++) ...[
                        if (i > 0) const SizedBox(width: 6),
                        parts[i],
                      ],
                    ]),
                  ),
                ]),
              ]),
        ),
      ]),
    );
  }
}

/// The favorite-team toggle, hoisted into the overview bar's trailing slot.
class _FavStar extends ConsumerWidget {
  final String league, teamId;
  final TeamCardTeam? team;
  final String? seedName, seedColor;
  const _FavStar({
    required this.league,
    required this.teamId,
    this.team,
    this.seedName,
    this.seedColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favs = ref.watch(favoriteTeamsProvider);
    final isFav = favs.any((f) => f.league == league && f.teamId == teamId);
    return IconButton(
      icon: Icon(isFav ? Icons.star_rounded : Icons.star_border_rounded,
          color: isFav ? T.gold : T.textDim, size: 22),
      onPressed: () => ref.read(favoriteTeamsProvider.notifier).toggle(
            FavoriteTeam(
              league: league,
              teamId: teamId,
              name: team?.displayName ?? seedName ?? teamId,
              abbr: team?.abbreviation,
              logo: team?.logo,
              color: team?.color ?? seedColor,
            ),
          ),
    );
  }
}

// ---- overview: next game ----------------------------------------------------

/// NEXT GAME / NEXT FIXTURE (11a–11d): kickoff label, a colour-bar-vs-colour-bar
/// matchup row, then a venue chip + ONE contextual chip (odds → weather → note).
class _NextGameCard extends StatelessWidget {
  final String league;
  final SportEvent event;
  final String teamId;
  final bool tableStyle;
  const _NextGameCard({
    required this.league,
    required this.event,
    required this.teamId,
    required this.tableStyle,
  });

  @override
  Widget build(BuildContext context) {
    final comp = event.main!;
    Competitor? us, them;
    for (final c in comp.competitors) {
      if (c.id == teamId) {
        us = c;
      } else {
        them ??= c;
      }
    }
    us ??= comp.competitors.isNotEmpty ? comp.competitors.first : null;
    if (us == null || them == null) return const SizedBox.shrink();

    final atAway = us.homeAway == 'away';
    final usColor = teamColor(us);
    final themColor = teamColor(them);
    final chips = _contextChips(comp);

    final card = V2Card(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            '${tableStyle ? 'NEXT FIXTURE' : 'NEXT GAME'} · ${_kickoff(event.start)}',
            style: T.cardLabelFaint),
        const SizedBox(height: 12),
        Row(children: [
          _bar(usColor),
          const SizedBox(width: 10),
          Text(us.label.toUpperCase(), style: T.heroName.copyWith(fontSize: 22)),
          const Spacer(),
          Text(atAway ? '@' : 'vs',
              style: const TextStyle(fontSize: 12, color: T.textFaint)),
          const Spacer(),
          Text(them.label.toUpperCase(),
              style: T.heroName.copyWith(fontSize: 22, color: T.textDim)),
          const SizedBox(width: 10),
          _bar(themColor),
        ]),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 8, children: [
            for (final c in chips) _chip(c),
          ]),
        ],
      ]),
    );
    // Same long-press-to-follow grammar as the schedule's game rows.
    if (comp.isField || comp.competitorKind != 'team') return card;
    return GestureDetector(
      onLongPress: () =>
          showGameFollowSheet(context, league: league, comp: comp),
      child: card,
    );
  }

  Widget _bar(Color c) => Container(
      width: 8,
      height: 26,
      decoration:
          BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)));

  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration:
            BoxDecoration(color: T.track, borderRadius: BorderRadius.circular(8)),
        child: Text(text,
            style: const TextStyle(fontSize: 11.5, color: T.textDim)),
      );

  /// Venue first, then exactly one of odds / weather / a note headline.
  List<String> _contextChips(Competition comp) {
    final out = <String>[];
    final venue = event.venue?.name;
    if (venue != null && venue.isNotEmpty) out.add(venue);
    final odds = comp.odds;
    if (odds != null && (odds.details != null || odds.overUnder != null)) {
      out.add(odds.details ?? 'O/U ${odds.overUnder}');
    } else if (event.weather != null && event.weather!.summary.isNotEmpty) {
      out.add(event.weather!.summary);
    } else if (comp.status.live) {
      // A note/headline can be a RESULT RECAP ("Seymore strikes out 12…") that
      // rides along a scheduled event (borrowed offline, or a stale ESPN blurb).
      // A pre/final game must never show it here — only a genuinely live game
      // gets the narrative chip; scheduled games stay on venue/odds/weather.
      final note = event.notes.isNotEmpty
          ? event.notes.first
          : (comp.headline != null && comp.headline!.isNotEmpty
              ? comp.headline!
              : null);
      if (note != null) out.add(note);
    }
    return out;
  }

  String _kickoff(DateTime? start) {
    if (start == null) return 'TBD';
    return startLabel(start).toUpperCase();
  }
}

// ---- overview: form ---------------------------------------------------------

enum _Res { w, l, d }

/// LAST 5 / FORM (11a–11d): W/L(/D) pills derived from the last five completed
/// events (or the competitor's `form` string when served), with a right-side
/// caption — 'Won N of 5' for win-only sports, 'P pts / N' for draws-capable.
class _FormCard extends StatelessWidget {
  final List<_Res> results;
  final bool drawsCapable;
  const _FormCard._(this.results, this.drawsCapable);

  static _FormCard? maybe(List<SportEvent> schedule, String teamId) {
    // Completed events in ascending order, with this team's competitor.
    final completed = <(SportEvent, Competitor)>[];
    for (final e in schedule) {
      final comp = e.main;
      if (comp == null || !comp.status.isFinal) continue;
      Competitor? us;
      for (final c in comp.competitors) {
        if (c.id == teamId) us = c;
      }
      if (us != null) completed.add((e, us));
    }
    if (completed.isEmpty) return null;

    // Prefer an authoritative form string (soccer/rugby) off the latest game.
    final formStr = completed.last.$2.form;
    var drawsCapable = false;
    final results = <_Res>[];
    if (formStr != null && formStr.isNotEmpty) {
      for (final ch in formStr.toUpperCase().split('')) {
        if (ch == 'W') {
          results.add(_Res.w);
        } else if (ch == 'L') {
          results.add(_Res.l);
        } else if (ch == 'D' || ch == 'T') {
          results.add(_Res.d);
        }
      }
      drawsCapable = true;
    } else {
      for (final (_, us) in completed) {
        if (us.winner == true) {
          results.add(_Res.w);
        } else if (us.winner == false) {
          results.add(_Res.l);
        } else {
          results.add(_Res.d); // a final with no winner reads as a draw
        }
      }
    }
    final last5 =
        results.length <= 5 ? results : results.sublist(results.length - 5);
    if (last5.isEmpty) return null;
    if (last5.contains(_Res.d)) drawsCapable = true;
    return _FormCard._(last5, drawsCapable);
  }

  @override
  Widget build(BuildContext context) {
    final w = results.where((r) => r == _Res.w).length;
    final d = results.where((r) => r == _Res.d).length;
    final pts = 3 * w + d;
    final caption = drawsCapable ? '$pts pts / ${results.length}' : 'Won $w of ${results.length}';
    final capColor = drawsCapable ? T.textDim : T.green;
    return V2Card(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Row(children: [
          Text(drawsCapable ? 'FORM' : 'LAST 5', style: T.cardLabelFaint),
          const Spacer(),
          Text(caption,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: capColor)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          for (var i = 0; i < results.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: _pill(results[i])),
          ],
        ]),
      ]),
    );
  }

  Widget _pill(_Res r) {
    final (bg, fg, ch) = switch (r) {
      _Res.w => (T.green.withValues(alpha: 0.16), T.green, 'W'),
      _Res.l => (T.live.withValues(alpha: 0.16), T.live, 'L'),
      _Res.d => (T.textDim.withValues(alpha: 0.16), T.textBody, 'D'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(9)),
      child: Text(ch,
          style: TextStyle(
              fontFamily: 'BarlowCondensed',
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: fg)),
    );
  }
}

// ---- overview: probables ----------------------------------------------------

/// PROBABLE STARTERS (11c): the next game's probable pitchers / goalies, pulled
/// off the scoreboard competitors. Data-gated — absent for most sports/most days.
class _ProbablesCard extends StatelessWidget {
  final List<(Competitor, Probable)> rows;
  const _ProbablesCard._(this.rows);

  static _ProbablesCard? maybe(SportEvent event) {
    final comp = event.main;
    if (comp == null) return null;
    final rows = <(Competitor, Probable)>[];
    for (final c in comp.competitors) {
      for (final p in c.probables) {
        rows.add((c, p));
      }
    }
    return rows.isEmpty ? null : _ProbablesCard._(rows);
  }

  @override
  Widget build(BuildContext context) => V2Card(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 10),
          const CardLabel('Probable starters'),
          const SizedBox(height: 4),
          for (var i = 0; i < rows.length; i++) _row(rows[i], first: i == 0),
          const SizedBox(height: 6),
        ]),
      );

  Widget _row((Competitor, Probable) e, {required bool first}) {
    final (team, p) = e;
    final sub = team.label;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: first
          ? null
          : const BoxDecoration(border: Border(top: BorderSide(color: T.divider))),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.athlete,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: T.listText.copyWith(
                    fontWeight: FontWeight.w600,
                    color: first ? T.text : T.textBody)),
            const SizedBox(height: 2),
            Text(sub.toUpperCase(), style: T.captionFaint),
          ]),
        ),
        if (p.record != null && p.record!.isNotEmpty) ...[
          const SizedBox(width: 10),
          Text(p.record!,
              style: T.statLine.copyWith(
                  color: first ? T.text : T.textDim)),
        ],
      ]),
    );
  }
}

// ---- schedule / stats / leaders / roster (deep tabs) ------------------------

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

/// §10 "Stat tiles": a section label over a 2-column grid of shared [StatTile]s.
class _StatsCard extends StatelessWidget {
  final TeamStatGroup group;
  const _StatsCard(this.group);

  @override
  Widget build(BuildContext context) {
    final stats = group.stats;
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
        rankChip: s.rank != null
            ? SemanticRankChip(label: '#${s.rank}', rank: s.rank!, total: 30)
            : null,
      );
}

/// §2.6 TEAM LEADERS: per-category season leaders. Rows are tappable → the
/// player page.
class _LeadersCard extends StatelessWidget {
  final String league, teamId;
  final List<TeamLeader> categories;
  final Color color;
  final String? colorHex;
  const _LeadersCard({
    required this.league,
    required this.teamId,
    required this.categories,
    required this.color,
    this.colorHex,
  });

  @override
  Widget build(BuildContext context) => V2Card(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(children: [
          const SizedBox(height: 10),
          const Align(
              alignment: Alignment.centerLeft, child: CardLabel('Team leaders')),
          for (var i = 0; i < categories.length; i++)
            _row(context, categories[i], divider: i > 0),
          const SizedBox(height: 4),
        ]),
      );

  Widget _row(BuildContext context, TeamLeader c, {required bool divider}) =>
      InkWell(
        onTap: () => openPlayerPage(context, league,
            athleteId: c.athleteId,
            teamId: teamId,
            name: c.athlete,
            color: colorHex),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: divider
              ? const BoxDecoration(
                  border: Border(top: BorderSide(color: T.divider)))
              : null,
          child: Row(children: [
            LogoAvatar(
                url: c.headshot,
                initials: initialsOf(c.athlete),
                color: color,
                teamId: teamId,
                size: 34),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.athlete,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            T.listText.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 1),
                    Text(
                      c.position != null && c.position!.isNotEmpty
                          ? '${c.label.toUpperCase()}  ·  ${c.position}'
                          : c.label.toUpperCase(),
                      style: T.captionFaint,
                    ),
                  ]),
            ),
            const SizedBox(width: 10),
            Text(c.displayValue,
                style: const TextStyle(
                    fontFamily: 'BarlowCondensed',
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    height: 1.0,
                    color: T.text)),
          ]),
        ),
      );
}

/// Collapsible roster groups; each athlete row is tappable → the player page.
class _RosterCard extends StatefulWidget {
  final String league, teamId;
  final List<RosterGroup> groups;
  const _RosterCard(
      {required this.league, required this.teamId, required this.groups});

  @override
  State<_RosterCard> createState() => _RosterCardState();
}

class _RosterCardState extends State<_RosterCard> {
  late final Set<int> _open;

  @override
  void initState() {
    super.initState();
    _open = {0};
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
          onTap: () =>
              setState(() => open ? _open.remove(i) : _open.add(i)),
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

  Widget _athleteRow(RosterAthlete a, {required bool divider}) => InkWell(
        onTap: () => openPlayerPage(context, widget.league,
            athleteId: a.id, teamId: widget.teamId, name: a.name),
        child: Container(
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
        ),
      );
}
