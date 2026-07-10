import 'models.dart';

/// The "big games" ranker: which of today's events, across leagues the user
/// does NOT follow, are marquee enough to earn a place on the home feed.
///
/// Pure functions over the CANONICAL model — this is downstream presentation
/// logic (like the situation-card dispatch), not a normalizer, so it has no JS
/// oracle. Every rule keys on data presence (a playoff series, a postseason
/// slate, a finals note, two ranked sides, a golf major), never on sport or
/// league name. The bar is deliberately high: on an ordinary day the section
/// is absent — that absence is the restraint. Qualification is also
/// NOW-ANCHORED ([isCurrentGame]): only games on today/yesterday (or live
/// right now) count, because ESPN's offseason scoreboards keep replaying the
/// last played slate for months.

/// One qualifying marquee event from an unfollowed league.
class BigGame {
  /// Registry key ('basketball/nba') — the row's detail/league routing.
  final String league;
  final String leagueName;
  final SportEvent event;

  /// Terse qualifier for the row's tag line ('West Finals', 'Top-10 matchup').
  final String reason;

  /// Rule weight — the cross-league sort key. Higher = bigger.
  final int weight;
  const BigGame({
    required this.league,
    required this.leagueName,
    required this.event,
    required this.reason,
    required this.weight,
  });

  /// The row's tag line: 'NBA · WEST FINALS'. When the reason already names the
  /// league (ESPN notes like 'NBA Finals'), the prefix is dropped — 'NBA · NBA
  /// FINALS' would read stuttered.
  String get tagLine {
    final r = reason.toUpperCase();
    final l = leagueName.toUpperCase();
    return l.isEmpty || r.contains(l) ? r : '$l · $r';
  }
}

/// Only weights at or above this qualify. Quarterfinals and single-ranked
/// matchups score below it on purpose.
const int marqueeBar = 60;

/// Rank one event (null = ordinary, not big). [seasonType] is the slate's
/// ESPN season type (3 = postseason).
BigGame? marqueeOf(String league, String leagueName, SportEvent event,
    {int? seasonType}) {
  final comp = event.main;
  // A tournament-of-matches (tennis draw) summarizes as a league row, not a
  // single game — out of scope for a per-game marquee.
  if (comp == null || event.isTournamentOfMatches) return null;

  var weight = 0;
  var reason = '';
  void consider(int w, String r) {
    if (w > weight && r.trim().isNotEmpty) {
      weight = w;
      reason = r.trim();
    }
  }

  // 1. What ESPN calls the game — round + notes copy is the strongest signal.
  //    'Championship'/'Final(s)'/'Super Bowl' → top tier; semifinals a step
  //    down; quarterfinals score below the bar (deliberate).
  final labels = <String>[
    if (comp.meta?.round != null) comp.meta!.round!,
    ...event.notes,
  ];
  for (final label in labels) {
    final t = label.toLowerCase();
    if (t.contains('semifinal') || t.contains('semi-final')) {
      consider(70, label);
    } else if (t.contains('quarterfinal') || t.contains('quarter-final')) {
      consider(50, label); // below the bar — kept for the max() bookkeeping
    } else if (RegExp(r'\bfinals?\b').hasMatch(t) ||
        t.contains('championship') ||
        t.contains('super bowl')) {
      consider(100, label);
    }
  }

  // 2. A structured playoff series (NBA/NHL/MLB) — a potential clincher
  //    outranks an ordinary series game.
  final series = comp.meta?.series;
  if (series != null && series.isPlayoff) {
    consider(series.canClinch ? 90 : 80, comp.meta?.round ?? 'Playoffs');
  }

  // 3. A postseason slate (season.type 3): every game is an elimination-stakes
  //    game even without a best-of series (NFL rounds, cup knockouts).
  if (seasonType == 3) {
    consider(80, comp.meta?.round ?? event.weekLabel ?? 'Playoffs');
  }

  // 4. Ranked vs ranked (college polls; competitor.rank is curated, 99→null).
  final ranks = [
    for (final c in comp.competitors)
      if (c.rank != null) c.rank!,
  ];
  if (comp.competitors.length >= 2 && ranks.length == comp.competitors.length) {
    final worst = ranks.reduce((a, b) => a > b ? a : b);
    if (worst <= 10) {
      consider(75, 'Top-10 matchup');
    } else if (worst <= 25) {
      consider(62, 'Ranked matchup');
    }
  }

  // 5. A golf major (meta.golf rides the core enrichment when fetched).
  if (comp.meta?.golf?.major == true) consider(80, 'Major');

  if (weight < marqueeBar) return null;
  return BigGame(
    league: league,
    leagueName: leagueName,
    event: event,
    reason: reason,
    weight: weight,
  );
}

/// Whether [e] is happening NOW-ish: live right now (a live event is current
/// whatever its start date — multi-day field events like a golf major start
/// days before they finish), else started today or yesterday in local time.
/// This is the stale-slate gate: ESPN's OFFSEASON scoreboards replay the last
/// played slate for months (the April NCAA championship still rides the July
/// scoreboard), and a months-old final must never resurface as a "big game".
bool isCurrentGame(SportEvent e, DateTime now) {
  if (e.main?.status.live == true) return true;
  final s = e.start;
  if (s == null) return false;
  final delta = DateTime(s.year, s.month, s.day)
      .difference(DateTime(now.year, now.month, now.day))
      .inDays;
  return delta == 0 || delta == -1;
}

/// Every qualifying event in one league's slate — big AND current ([now]
/// anchors the today/yesterday recency gate).
List<BigGame> pickBigGames(String league, ScoresResponse scores,
        {required DateTime now}) =>
    [
      for (final e in scores.events)
        if (isCurrentGame(e, now))
          if (marqueeOf(league, scores.leagueName, e,
                  seasonType: scores.season.type)
              case final BigGame b)
            b,
    ];

/// Cross-league order: biggest first; within a weight, live before not, then
/// by start time. Capped — the section never becomes a second feed.
List<BigGame> topBigGames(Iterable<BigGame> all, {int cap = 3}) {
  int phase(BigGame b) => b.event.main?.status.live == true ? 0 : 1;
  final sorted = all.toList()
    ..sort((a, b) {
      final w = b.weight.compareTo(a.weight);
      if (w != 0) return w;
      final p = phase(a).compareTo(phase(b));
      if (p != 0) return p;
      final sa = a.event.start, sb = b.event.start;
      if (sa == null || sb == null) return 0;
      return sa.compareTo(sb);
    });
  return sorted.take(cap).toList();
}
