// momentum.dart — derived lenses over the soccer core match feed (canonical
// MatchFeed, capability hasMatchFeed). Downstream of canonical like
// situations.dart / marquee.dart: pure data-presence rules, no oracle, no I/O.
// Feeds the momentum chart, the live-pitch pass trail / possession chip /
// restart log, and the shot map. Unit-tested in test/momentum_test.dart.

import 'dart:math' as math;

import 'models.dart';

/// Shot-attempt play types (an open set upstream — match by the known family).
/// 'Save' / 'Assists Shot' are companion events of the same attempt, not shots.
const Set<String> shotTypes = {
  'Goal',
  'Shot On Target',
  'Shot Off Target',
  'Shot Blocked',
  'Penalty - Scored',
  'Penalty - Saved',
  'Penalty - Missed',
  'Own Goal',
};

/// Restart / stoppage play types → the live-pitch state chip + restart log.
const Map<String, String> restartLabels = {
  'Throw In': 'Throw-in',
  'Goal Kick': 'Goal kick',
  'Corner Awarded': 'Corner',
  'Free Kick': 'Free kick',
  'Kickoff': 'Kickoff',
  'Offside': 'Offside',
  'Foul': 'Foul',
  'Handball': 'Handball',
  'Penalty - Scored': 'Penalty',
  'Penalty - Saved': 'Penalty saved',
  'Penalty - Missed': 'Penalty missed',
  'Start Delay': 'Delay',
  'Substitution': 'Substitution',
};

bool isShot(MatchFeedPlay p) => shotTypes.contains(p.type);
bool isRestart(MatchFeedPlay p) => restartLabels.containsKey(p.type);

/// The shot attempts in feed order (oldest first).
List<MatchFeedPlay> matchShots(List<MatchFeedPlay> plays) =>
    plays.where(isShot).toList(growable: false);

/// Stoppages/restarts worth logging (oldest first). Kickoff excluded — it
/// starts play rather than stopping it, and would sit forever in a quiet log.
List<MatchFeedPlay> matchRestarts(List<MatchFeedPlay> plays) => plays
    .where((p) => isRestart(p) && p.type != 'Kickoff')
    .toList(growable: false);

/// One minute-bucket of attacking pressure: [home]/[away] are 0..1, already
/// normalized against the match's loudest minute.
class MomentumBucket {
  final int minute;
  final double home, away;
  const MomentumBucket(this.minute, this.home, this.away);
}

/// Attacking pressure per minute, home above the line / away below (design 9a).
/// A play contributes to its side's minute when it reads as attack: any shot
/// (weight 1.0), a corner (0.5), or open play touched in the attacking third
/// (x ≥ 60 → up to 0.4, scaled by depth). Values normalize to the loudest
/// minute so the chart always fills its height. Returns at least [minMinutes]
/// buckets (KO→FT axis stays full-width mid-match); grows past it for ET.
List<MomentumBucket> momentumBuckets(List<MatchFeedPlay> plays,
    {int minMinutes = 90}) {
  if (plays.isEmpty) return const [];
  final home = <int, double>{}, away = <int, double>{};
  var maxMinute = 0;
  for (final p in plays) {
    if (p.side == null || p.sec == null) continue;
    final m = p.minute;
    if (m > maxMinute) maxMinute = m;
    double w = 0;
    if (isShot(p)) {
      w = 1.0;
    } else if (p.type == 'Corner Awarded') {
      w = 0.5;
    } else if (p.x != null && p.x! >= 60) {
      w = 0.4 * ((p.x! - 60) / 40).clamp(0.0, 1.0);
    }
    if (w <= 0) continue;
    final bucket = p.side == 'home' ? home : away;
    bucket[m] = (bucket[m] ?? 0) + w;
  }
  var peak = 0.0;
  for (final v in home.values) {
    if (v > peak) peak = v;
  }
  for (final v in away.values) {
    if (v > peak) peak = v;
  }
  if (peak <= 0) return const [];
  final total = maxMinute + 1 > minMinutes ? maxMinute + 1 : minMinutes;
  return List.generate(
      total,
      (m) => MomentumBucket(
          m, (home[m] ?? 0) / peak, (away[m] ?? 0) / peak),
      growable: false);
}

/// The trailing possession sequence for the live-pitch pass trail: walks back
/// from the newest play, collecting consecutive same-side plays that carry
/// coordinates, stopping at a side change or a restart boundary (the trail
/// resets when play stops). Oldest first; capped at [cap] points.
List<MatchFeedPlay> trailingPossession(List<MatchFeedPlay> plays,
    {int cap = 6}) {
  final out = <MatchFeedPlay>[];
  String? side;
  for (var i = plays.length - 1; i >= 0; i--) {
    final p = plays[i];
    if (p.x == null || p.side == null) {
      if (out.isEmpty) continue; // trailing coordless noise before the ball
      break;
    }
    side ??= p.side;
    if (p.side != side) break;
    out.add(p);
    if (isRestart(p) && out.length > 1) break; // the restart starts the trail
    if (out.length >= cap) break;
  }
  return out.reversed.toList(growable: false);
}

/// The freshest play that carries a side — the possession chip's source.
MatchFeedPlay? lastSidedPlay(List<MatchFeedPlay> plays) {
  for (var i = plays.length - 1; i >= 0; i--) {
    if (plays[i].side != null) return plays[i];
  }
  return null;
}

/// The possession chip's state text: the restart label while play is stopped
/// ('THROW-IN'), else 'OPEN PLAY'.
String possessionState(MatchFeedPlay p) =>
    (restartLabels[p.type] ?? 'Open play').toUpperCase();

/// Yards from the play's spot to the centre of the goal it attacks. The core
/// feed's coords are team-relative percentages of a ~105×68 m pitch; x 100 is
/// the opponent goal line. Rounded to the nearest yard.
int yardsToGoal(num x, num y) {
  final dxM = (100 - x) * 1.05; // 1 x-unit ≈ 1.05 m
  final dyM = (y - 50) * 0.68; // 1 y-unit ≈ 0.68 m
  final meters = math.sqrt(dxM * dxM + dyM * dyM);
  return (meters * 1.094).round();
}

/// Shot outcome classification for the shot-map legend/detail. One of:
/// 'goal' | 'saved' | 'blocked' | 'off' .
String shotOutcome(MatchFeedPlay p) {
  switch (p.type) {
    case 'Goal':
    case 'Penalty - Scored':
    case 'Own Goal':
      return 'goal';
    case 'Shot On Target':
    case 'Penalty - Saved':
      return 'saved';
    case 'Shot Blocked':
      return 'blocked';
    default:
      return 'off';
  }
}

/// 'Right foot' / 'Left foot' / 'Header' parsed from the shot's prose, else null.
String? shotTechnique(MatchFeedPlay p) {
  final t = (p.text ?? '').toLowerCase();
  if (t.contains('right footed')) return 'Right foot';
  if (t.contains('left footed')) return 'Left foot';
  if (t.contains('header')) return 'Header';
  return null;
}

/// 'Penalty' / 'Free kick' / 'Open play' from the shot's type + prose.
String shotSituation(MatchFeedPlay p) {
  if (p.type.startsWith('Penalty')) return 'Penalty';
  final t = (p.text ?? '').toLowerCase();
  if (t.contains('penalty')) return 'Penalty';
  if (t.contains('free kick')) return 'Free kick';
  if (t.contains('corner')) return 'From corner';
  return 'Open play';
}
