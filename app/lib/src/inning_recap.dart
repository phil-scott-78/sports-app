/// The previous half-inning, summarized — the "what just happened" line under
/// the between-innings Due Up card. Downstream of canonical (like marquee.dart):
/// pure data-presence rules over the rich summary's atBats, no oracle, no I/O.
///
/// The deterministic line is the always-available fallback ('Three up, three down' /
/// 'Two runs on three hits, one stranded'); [texts] carries the half's at-bat result
/// prose so an optional AI recap (data/recap.dart) can write a better sentence
/// from the same facts.
library;

import 'models.dart';

class InningRecap {
  final int period;
  final String half; // 'top' | 'bottom'
  final String? teamAbbr; // the batting side just retired
  final String label; // 'Top 5th'
  final String line; // the deterministic summary
  final List<String> texts; // the at-bat result texts, in order (AI fodder)
  const InningRecap({
    required this.period,
    required this.half,
    this.teamAbbr,
    required this.label,
    required this.line,
    required this.texts,
  });
}

/// The just-completed half-inning's recap, or null when the at-bats can't tell
/// one (no resolved at-bats yet). Callers gate on the between-innings state
/// (situation.isDueUp) — this only answers "what happened in the last half".
InningRecap? previousHalfInningRecap(List<AtBat> atBats) {
  // Resolved at-bats only: a live header ('X pitches to Y', no terminal row)
  // may already exist for the NEXT half — it must not drag the recap forward.
  final resolved = [
    for (final ab in atBats)
      if (!ab.live && ab.text.isNotEmpty && ab.period != null && ab.half != null)
        ab
  ];
  if (resolved.isEmpty) return null;
  final last = resolved.last;
  final group = [
    for (final ab in resolved)
      if (ab.period == last.period && ab.half == last.half) ab
  ];

  // Runs = the batting side's running-total delta across the half. The running
  // score rides each terminal row; "before" is the score on the at-bat just
  // ahead of the group (or 0 at the top of the 1st).
  num? sideScore(AtBat ab) => last.side == 'home' ? ab.home : ab.away;
  final firstIdx = resolved.indexOf(group.first);
  final before = firstIdx > 0 ? sideScore(resolved[firstIdx - 1]) : 0;
  final after = sideScore(last);
  final runs = (after != null && before != null) ? (after - before).toInt() : null;

  // Hits from the result prose — ESPN's MLB texts use past-tense verbs
  // ('Judge doubled to deep right'); 'grounded into double play' has none.
  final hitRe = RegExp(r'\b(singled|doubled|tripled|homered)\b', caseSensitive: false);
  final hits = group.where((ab) => hitRe.hasMatch(ab.text)).length;

  final bf = group.length;
  // Every batter faced ends the half out, scored, or stranded — three outs
  // retire the side, so stranded = BF − 3 − runs (clamped: a mid-at-bat
  // inning-ending caught stealing can skew BF by one).
  final stranded =
      (runs != null && bf >= 3) ? (bf - 3 - runs).clamp(0, 3) : null;

  final line = _line(bf: bf, runs: runs, hits: hits, stranded: stranded);
  return InningRecap(
    period: last.period!,
    half: last.half!,
    teamAbbr: last.teamAbbr,
    label: '${last.half == 'bottom' ? 'Bot' : 'Top'} ${_ordinal(last.period!)}',
    line: line,
    texts: [for (final ab in group) ab.text],
  );
}

String _line({required int bf, int? runs, required int hits, int? stranded}) {
  String n(int v, String unit) => '${_word(v)} $unit${v == 1 ? '' : 's'}';
  // Sentence case, matching the AI recap it stands in for.
  String s(String t) => t[0].toUpperCase() + t.substring(1);
  if (bf == 3 && (runs ?? 0) == 0 && hits == 0) return 'Three up, three down';
  final tail =
      (stranded != null && stranded > 0) ? ', ${_word(stranded)} stranded' : '';
  if (runs != null && runs > 0) {
    return s(hits > 0 ? '${n(runs, 'run')} on ${n(hits, 'hit')}$tail' : '${n(runs, 'run')}$tail');
  }
  if (hits > 0) return s('${n(hits, 'hit')}, no runs$tail');
  return s('no hits, no runs$tail');
}

/// Counts read as words ('two runs on three hits'), the way a broadcast booth
/// says them — digits only past twenty (a half-inning never gets there).
String _word(int v) => (v >= 0 && v < _words.length) ? _words[v] : '$v';

const _words = [
  'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight',
  'nine', 'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen',
  'sixteen', 'seventeen', 'eighteen', 'nineteen', 'twenty', //
];

String _ordinal(int p) {
  if (p % 100 >= 11 && p % 100 <= 13) return '${p}th';
  return switch (p % 10) {
    1 => '${p}st',
    2 => '${p}nd',
    3 => '${p}rd',
    _ => '${p}th',
  };
}
