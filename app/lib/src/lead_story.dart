import 'models.dart';

/// The §8 basketball "clock & run" right-hand slot — what the situation card
/// says beside the big clock. Derived entirely client-side from the summary's
/// scoring plays (running scores, oldest→newest); downstream of canonical like
/// marquee.dart / momentum.dart: data-presence rules only, no oracle.
///
/// Priority: a live scoring run (`OKC 9–2 RUN` / "last 2:40", gold). A run
/// won't always be on — in a back-and-forth game the slot degrades to a quiet
/// tidbit instead: lead changes, ties, or a late wire-to-wire note. Null when
/// the story so far says nothing worth a callout (the clock stands alone).
class LeadSlot {
  final String text; // 'OKC 9–2 RUN' / '14 LEAD CHANGES'
  final String? caption; // 'last 2:40' / 'tied 6 times'

  /// True for the run callout (the §2 `gold` "run callouts" token); the
  /// back-and-forth tidbits stay quiet white.
  final bool loud;
  const LeadSlot(this.text, this.caption, {this.loud = false});
}

/// [plays] is the summary's scoring feed oldest→newest; rows without a running
/// score are ignored, and fewer than four scored rows is too early to say
/// anything.
LeadSlot? leadSlotFor(Competition comp, List<SummaryPlay> plays) {
  final usable = <SummaryPlay>[
    for (final p in plays)
      if (p.home != null && p.away != null) p
  ];
  if (usable.length < 4) return null;

  final run = _currentRun(usable);
  if (run != null) {
    final team = run.side == 'home' ? comp.home : comp.away;
    if (team != null) {
      final sec = _runSeconds(comp, usable[run.start]);
      return LeadSlot(
        '${team.label} ${run.pf}–${run.pa} RUN',
        sec == null ? null : 'last ${_mmss(sec)}',
        loud: true,
      );
    }
  }

  // The back-and-forth ledger off the margin sequence: a lead change is the
  // leader's sign flipping (through a tie or not); a tie is the game coming
  // back level after someone led.
  var lastSign = 0, leadChanges = 0, ties = 0;
  for (final p in usable) {
    final m = p.home! - p.away!;
    final sign = m == 0 ? 0 : (m > 0 ? 1 : -1);
    if (sign == 0) {
      if (lastSign != 0) ties++;
    } else {
      if (lastSign != 0 && sign != lastSign) leadChanges++;
      lastSign = sign;
    }
  }
  if (leadChanges >= 4) {
    return LeadSlot('$leadChanges LEAD CHANGES',
        ties == 0 ? null : (ties == 1 ? 'tied once' : 'tied $ties times'));
  }
  if (ties >= 3) {
    return LeadSlot(
        'TIED $ties TIMES', leadChanges > 0 ? '$leadChanges lead changes' : null);
  }
  // Wire to wire: one side has led since the first score (never trailed,
  // never even tied) — only worth saying once the game is past halfway.
  final last = usable.last.home! - usable.last.away!;
  if (leadChanges == 0 &&
      ties == 0 &&
      last != 0 &&
      comp.status.period * 2 > comp.periods.regulation) {
    final leader = last > 0 ? comp.home : comp.away;
    if (leader != null) {
      return LeadSlot('WIRE TO WIRE', '${leader.label} never trailed');
    }
  }
  return null;
}

/// The broadcast-style current run, anchored to the newest play: walking back,
/// one side's points [pf] against the other's answer [pa]. The window keeps
/// extending while the answer stays small (≤4 pts — a 9–2 run survives a free
/// throw pair); a prefix qualifies when it starts with the run team's own
/// bucket (a run starts with your score), pf ≥ 6, and pf ≥ 3×pa. The deepest
/// qualifying prefix wins (the biggest honest claim); at most one side can
/// qualify in practice, ties breaking toward the bigger run.
({String side, int pf, int pa, int start})? _currentRun(
    List<SummaryPlay> plays) {
  ({String side, int pf, int pa, int start})? best;
  for (final side in const ['home', 'away']) {
    var pf = 0, pa = 0;
    ({String side, int pf, int pa, int start})? cand;
    for (var i = plays.length - 1; i >= 0; i--) {
      final p = plays[i];
      if (p.side != 'home' && p.side != 'away') break;
      final prevHome = i > 0 ? plays[i - 1].home! : 0;
      final prevAway = i > 0 ? plays[i - 1].away! : 0;
      final pts =
          (p.side == 'home' ? p.home! - prevHome : p.away! - prevAway).round();
      if (pts <= 0) break; // running score went sideways — don't guess
      if (p.side == side) {
        pf += pts;
      } else {
        pa += pts;
        if (pa > 4) break; // the answer is real — no live run for this side
      }
      if (p.side == side && pf >= 6 && pf >= 3 * pa) {
        cand = (side: side, pf: pf, pa: pa, start: i);
      }
    }
    if (cand != null && (best == null || cand.pf > best.pf)) best = cand;
  }
  return best;
}

/// "4:12" / "45.3" → whole seconds remaining (basketball clocks count down).
int? _clockSeconds(String? clock) {
  if (clock == null) return null;
  final t = clock.trim();
  final m = RegExp(r'^(\d+):(\d{1,2})(?:\.\d+)?$').firstMatch(t);
  if (m != null) return int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
  final s = double.tryParse(t);
  return s?.floor();
}

String _mmss(int sec) =>
    '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';

/// Elapsed seconds from the run's first play to now. Countdown clocks: within
/// one period it's a plain difference; one quarter boundary is bridged with
/// the registry period length. OT periods run a different length, so anything
/// further back (or into OT) is omitted rather than guessed.
int? _runSeconds(Competition comp, SummaryPlay first) {
  final now = _clockSeconds(comp.status.clock);
  final start = _clockSeconds(first.clock);
  final pNow = comp.status.period, pStart = first.period;
  if (now == null || start == null || pStart == null || pNow < pStart) {
    return null;
  }
  if (pNow == pStart) return start > now ? start - now : null;
  final len = comp.periods.lengthMin;
  if (len == null || pNow - pStart > 1 || pNow > comp.periods.regulation) {
    return null;
  }
  final sec = start + (len * 60 - now);
  return sec > 0 ? sec : null;
}
