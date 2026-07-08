import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config.dart';
import '../models.dart';
import '../providers.dart';
import '../theme.dart';
import 'league_card.dart';
import 'poll.dart';
import 'widgets.dart';

/// Open a tennis tournament's match list — the drill-in from the Scores list's
/// per-tournament summary row. One ESPN "event" IS a whole tournament (many
/// matches across the singles/doubles draws); this page explodes it into
/// per-match rows grouped by draw round, each tapping into the set-grid detail.
void openTournamentPage(BuildContext context, String league, SportEvent event,
    {String? date}) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) =>
        TournamentPage(league: league, initialEvent: event, date: date),
  ));
}

class TournamentPage extends ConsumerStatefulWidget {
  final String league;
  final SportEvent initialEvent;

  /// The day the tournament came from ('YYYYMMDD'), or null for today —
  /// forwarded so both this page and the matches it opens re-resolve from the
  /// right day's slate.
  final String? date;
  const TournamentPage(
      {super.key,
      required this.league,
      required this.initialEvent,
      this.date});

  @override
  ConsumerState<TournamentPage> createState() => _TournamentPageState();
}

class _TournamentPageState extends ConsumerState<TournamentPage>
    with LifecyclePoll {
  ScoresKey get _key => (league: widget.league, date: widget.date);

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

  /// The freshest version of this tournament from the polled league slate (so
  /// live set scores tick), else the event we were opened with.
  SportEvent get _event {
    final scores = ref.read(leagueScoresProvider(_key)).valueOrNull;
    if (scores != null) {
      for (final e in scores.events) {
        if (e.id == widget.initialEvent.id) return e;
      }
    }
    return widget.initialEvent;
  }

  @override
  Duration? pollInterval() {
    final e = _event;
    if (e.competitions.any((c) => c.status.live)) return AppConfig.refreshLive;
    if (kickoffSoon(e.start)) return AppConfig.refreshNearKickoff;
    return AppConfig.refreshIdle;
  }

  @override
  void onPoll() => ref.invalidate(leagueScoresProvider(_key));

  @override
  void onForeground() => onPoll();

  @override
  Widget build(BuildContext context) {
    ref.listen(leagueScoresProvider(_key), (_, __) => repace());
    ref.watch(leagueScoresProvider(_key));

    final event = _event;
    final groups = _groupByRound(event.matches);

    return Scaffold(
      appBar: subpageBar(context, event.name),
      body: ListView(
        padding: const EdgeInsets.only(bottom: T.scrollBottom),
        children: [
          if (event.venue != null || groups.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(T.pageMargin, 2, T.pageMargin, 0),
              child: Text(
                [
                  '${event.competitions.length} '
                      'match${event.competitions.length == 1 ? '' : 'es'}',
                  if (event.venue != null) event.venue!.name,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: T.captionFaint,
              ),
            ),
          for (final g in groups) ...[
            _RoundLabel(g.label, live: g.hasLive),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: T.pageMargin),
              child: _MatchesCard(
                  league: widget.league, matches: g.matches, date: widget.date),
            ),
          ],
          if (groups.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(
                  T.pageMargin, 24, T.pageMargin, 0),
              child: HintCard('No matches to show yet.'),
            ),
        ],
      ),
    );
  }

  /// Bucket the tournament's matches into `(draw, round)` groups — singles and
  /// doubles are separated even when they share a round name ("Final") — then
  /// order the sections by round depth (Final → Qualifying), singles before
  /// doubles at equal depth.
  List<_RoundGroup> _groupByRound(List<SportEvent> matches) {
    final byKey = <String, _RoundGroup>{};
    final order = <String>[];
    for (final m in matches) {
      final comp = m.main;
      if (comp == null) continue;
      final doubles = _isDoubles(comp);
      final round = comp.meta?.round ?? '';
      final key = '${doubles ? 'D' : 'S'}|$round';
      final g = byKey.putIfAbsent(key, () {
        order.add(key);
        return _RoundGroup(
          label: _sectionLabel(round, doubles),
          rank: tennisRoundRank(round) - (doubles ? 1 : 0),
        );
      });
      g.matches.add(m);
    }
    final groups = order.map((k) => byKey[k]!).toList();
    for (final g in groups) {
      g.matches.sort(_matchOrder);
    }
    groups.sort((a, b) => b.rank.compareTo(a.rank));
    return groups;
  }

  static String _sectionLabel(String round, bool doubles) {
    final base = round.isEmpty ? 'Matches' : round;
    return doubles ? '$base · Doubles' : base;
  }

  /// Within a round: live first, then upcoming (soonest), then completed —
  /// stable by start time inside each phase.
  static int _matchOrder(SportEvent a, SportEvent b) {
    int phase(SportEvent e) {
      final s = e.main!.status;
      if (s.live) return 0;
      if (s.isScheduled) return 1;
      return 2;
    }

    final pa = phase(a), pb = phase(b);
    if (pa != pb) return pa - pb;
    final sa = a.start?.millisecondsSinceEpoch ?? 0;
    final sb = b.start?.millisecondsSinceEpoch ?? 0;
    return sa.compareTo(sb);
  }
}

/// A doubles match: at least one side is a pair of athletes. Discriminator on
/// competitor shape, not sport name.
bool _isDoubles(Competition comp) =>
    comp.competitors.any((c) => c.kind == 'pair' || c.athletes.length >= 2);

class _RoundGroup {
  final String label;
  final int rank;
  final List<SportEvent> matches = [];
  _RoundGroup({required this.label, required this.rank});

  bool get hasLive => matches.any((m) => m.main?.status.live ?? false);
}

/// A round section header — the group label with a live dot when that round has
/// a match in progress.
class _RoundLabel extends StatelessWidget {
  final String text;
  final bool live;
  const _RoundLabel(this.text, {this.live = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: T.sectionHeaderPad,
        child: Row(children: [
          Text(text.toUpperCase(), style: T.cardLabelFaint),
          if (live) ...[
            const SizedBox(width: 8),
            const LiveDot(size: 6),
          ],
        ]),
      );
}

/// One round's matches as a surface card of dense rows — each a
/// single-competition [SportEvent] rendered through the shared [LeagueEventRow],
/// so a tennis match reuses the same h2h/set row grammar and taps into the
/// set-grid detail.
class _MatchesCard extends StatelessWidget {
  final String league;
  final List<SportEvent> matches;
  final String? date;
  const _MatchesCard(
      {required this.league, required this.matches, this.date});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: T.surface,
          borderRadius: BorderRadius.circular(T.rowCardRadius),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < matches.length; i++)
            LeagueEventRow(
              league: league,
              event: matches[i],
              divider: i > 0,
              date: date,
            ),
        ]),
      );
}

// ─────────────────────────── round vocabulary ───────────────────────────
// Tennis draw rounds parsed from ESPN's round.displayName ("Final",
// "Quarterfinals", "Round of 16", "Qualifying 1st Round"). Shared with the
// Scores list's per-tournament summary row.

/// A sortable depth for a draw round — Final highest, qualifying below the main
/// draw. Used to order tournament sections and to pick a tournament's "furthest
/// round" for the summary row.
int tennisRoundRank(String? round) {
  final r = (round ?? '').toLowerCase();
  if (r.isEmpty) return 0;
  final qualifying = r.contains('qualif');
  int base;
  if (r.contains('final') && !r.contains('semi') && !r.contains('quarter')) {
    base = (r.contains('3rd') || r.contains('third')) ? 95 : 100;
  } else if (r.contains('semi')) {
    base = 90;
  } else if (r.contains('quarter')) {
    base = 80;
  } else {
    final ro = RegExp(r'round of (\d+)').firstMatch(r);
    if (ro != null) {
      // deeper "Round of N" = later round = lower depth (R16 > R32 > R64).
      final n = int.tryParse(ro.group(1)!) ?? 64;
      base = 78 - n ~/ 8; // R16→76, R32→74, R64→70, R128→62
    } else {
      final n = RegExp(r'(\d+)').firstMatch(r);
      base = 20 + (n != null ? (int.tryParse(n.group(1)!) ?? 0) : 0);
    }
  }
  // Qualifying always ranks below the main draw, but still ordered internally.
  return qualifying ? base - 200 : base;
}

/// A compact label for a draw round — "Final", "SF", "QF", "R16", "Qual".
/// Qualifying is checked first so "Qualifying Final" reads "Qual", not "Final".
String tennisRoundAbbr(String? round) {
  final r = (round ?? '').toLowerCase();
  if (r.isEmpty) return '';
  if (r.contains('qualif')) return 'Qual';
  if (r.contains('final') && !r.contains('semi') && !r.contains('quarter')) {
    return (r.contains('3rd') || r.contains('third')) ? '3rd Place' : 'Final';
  }
  if (r.contains('semi')) return 'SF';
  if (r.contains('quarter')) return 'QF';
  final ro = RegExp(r'round of (\d+)').firstMatch(r);
  if (ro != null) return 'R${ro.group(1)}';
  final n = RegExp(r'(\d+)').firstMatch(r);
  if (n != null) return 'R${n.group(1)}';
  return round!;
}
