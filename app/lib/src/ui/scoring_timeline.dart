import 'package:flutter/material.dart';
import '../models.dart';
import 'summary_feed.dart';

/// The cheap goal/card timeline (soccer/rugby) from `competition.events` — the
/// scoreboard `details[]` feed, no /summary fetch. Renders through the SAME
/// center-spine [ScoringFeed] used for the rich tier, so every sport's timeline
/// reads identically (home left / away right around a vertical rail). This widget
/// just adapts our cheap [ScoringEvent]s into the shared [SummaryPlay] shape.
class ScoringTimeline extends StatelessWidget {
  final Competition comp;
  final String? sport;
  final String? nowLabel; // live → "LIVE · clock" marker leads the rail
  const ScoringTimeline(
      {super.key, required this.comp, this.sport, this.nowLabel});

  static bool has(Competition comp) =>
      comp.events.any((e) => e.isGoal || e.isCard || e.type == 'score');

  @override
  Widget build(BuildContext context) {
    final plays = _plays();
    if (plays.isEmpty) return const SizedBox.shrink();
    return ScoringFeed(plays: plays, sport: sport, nowLabel: nowLabel);
  }

  /// Adapt the cheap events into [SummaryPlay]s, computing a running scoreline as
  /// we go (a goal credits its side; an own-goal credits the opponent).
  List<SummaryPlay> _plays() {
    final out = <SummaryPlay>[];
    var away = 0, home = 0;
    for (final e in comp.events) {
      final isScore = e.isGoal || e.type == 'score';
      if (!isScore && !e.isCard) continue; // keep goals/tries + cards
      final abbr =
          e.team == null ? null : comp.competitorByHome(e.team!)?.label;
      final annot =
          e.ownGoal ? ' (OG)' : (e.penalty && e.isGoal ? ' (PEN)' : '');
      final name = '${e.athlete ?? e.detail ?? ''}$annot'.trim();
      num? a, h;
      if (isScore) {
        final credit = e.ownGoal
            ? (e.team == 'home' ? 'away' : (e.team == 'away' ? 'home' : null))
            : e.team;
        final inc = (e.scoreValue ?? 1).toInt();
        if (credit == 'home') {
          home += inc;
        } else if (credit == 'away') {
          away += inc;
        }
        a = away;
        h = home;
      }
      final type = e.type == 'red-card'
          ? 'Red Card'
          : (e.type == 'yellow-card' ? 'Yellow Card' : 'Goal');
      out.add(SummaryPlay(
        period: e.period,
        clock: e.clock,
        side: e.team,
        teamAbbr: abbr,
        type: type,
        text: name.isEmpty ? type : name,
        away: a,
        home: h,
      ));
    }
    return out;
  }
}
