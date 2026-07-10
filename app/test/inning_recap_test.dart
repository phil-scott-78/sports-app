import 'package:flutter_test/flutter_test.dart';
import 'package:scores/src/inning_recap.dart';
import 'package:scores/src/models.dart';

// The deterministic previous-half-inning recap (inning_recap.dart): pure
// data-presence rules over the rich summary's atBats — the always-available
// fallback line under the between-innings Due Up card.

AtBat _ab({
  int period = 5,
  String half = 'top',
  String side = 'away',
  String teamAbbr = 'PIT',
  String text = '',
  num? away,
  num? home,
  bool live = false,
}) =>
    AtBat.fromJson({
      'period': period,
      'half': half,
      'side': side,
      'teamAbbr': teamAbbr,
      'text': text,
      if (away != null) 'away': away,
      if (home != null) 'home': home,
      if (live) 'live': true,
    });

void main() {
  test('3 up, 3 down: three batters, no hits, no runs', () {
    final r = previousHalfInningRecap([
      _ab(text: 'Cruz struck out swinging.', away: 0, home: 0),
      _ab(text: 'Reynolds flied out to center.', away: 0, home: 0),
      _ab(text: 'McCutchen grounded out to short.', away: 0, home: 0),
    ]);
    expect(r, isNotNull);
    expect(r!.line, 'Three up, three down');
    expect(r.label, 'Top 5th');
    expect(r.teamAbbr, 'PIT');
    expect(r.texts, hasLength(3));
  });

  test('runs on hits, stranded from the BF − outs − runs identity', () {
    // 5 batters faced, 2 runs (0 → 2), 3 hits → 0 stranded? 5-3-2=0. Add a
    // walk: 6 BF, 2 runs → 1 stranded.
    final r = previousHalfInningRecap([
      _ab(text: 'Cruz singled to left.', away: 0),
      _ab(text: 'Reynolds walked.', away: 0),
      _ab(text: 'McCutchen doubled to deep right, Cruz scored.', away: 1),
      _ab(text: 'Hayes hit a sacrifice fly to center, Reynolds scored.', away: 2),
      _ab(text: 'Suwinski struck out swinging.', away: 2),
      _ab(text: 'Bae popped out to first.', away: 2),
    ]);
    expect(r!.line, 'Two runs on two hits, one stranded');
  });

  test('hits without runs', () {
    final r = previousHalfInningRecap([
      _ab(text: 'Cruz singled to center.', away: 0),
      _ab(text: 'Reynolds grounded into double play.', away: 0),
      _ab(text: 'McCutchen tripled to deep center.', away: 0),
      _ab(text: 'Hayes lined out to third.', away: 0),
    ]);
    // 4 BF, 0 runs, 2 hits ("double play" is not a hit), 1 stranded (4-3-0)
    expect(r!.line, 'Two hits, no runs, one stranded');
  });

  test('runs computed for the HOME half off the home running total', () {
    final r = previousHalfInningRecap([
      // previous half (top 4, away bats) sets the "before" anchor
      _ab(period: 4, half: 'top', side: 'away', text: 'Cruz struck out.', away: 1, home: 3),
      _ab(period: 4, half: 'bottom', side: 'home', teamAbbr: 'ATL', text: 'Acuna homered to left.', away: 1, home: 4),
      _ab(period: 4, half: 'bottom', side: 'home', teamAbbr: 'ATL', text: 'Albies flied out.', away: 1, home: 4),
      _ab(period: 4, half: 'bottom', side: 'home', teamAbbr: 'ATL', text: 'Riley struck out.', away: 1, home: 4),
      _ab(period: 4, half: 'bottom', side: 'home', teamAbbr: 'ATL', text: 'Olson grounded out.', away: 1, home: 4),
    ]);
    expect(r!.label, 'Bot 4th');
    expect(r.teamAbbr, 'ATL');
    expect(r.line, 'One run on one hit');
  });

  test('live at-bats are excluded — the next half never drags the recap forward', () {
    final r = previousHalfInningRecap([
      _ab(period: 5, half: 'top', text: 'Cruz struck out.', away: 0, home: 0),
      _ab(period: 5, half: 'top', text: 'Reynolds flied out.', away: 0, home: 0),
      _ab(period: 5, half: 'top', text: 'McCutchen grounded out.', away: 0, home: 0),
      // the NEXT half's live header (no terminal text yet)
      _ab(period: 5, half: 'bottom', side: 'home', teamAbbr: 'ATL', live: true),
    ]);
    expect(r!.half, 'top');
    expect(r.line, 'Three up, three down');
  });

  test('null when nothing is resolved yet', () {
    expect(previousHalfInningRecap(const []), isNull);
    expect(previousHalfInningRecap([_ab(live: true)]), isNull);
  });

  test('ordinal labels', () {
    String label(int p) => previousHalfInningRecap(
        [_ab(period: p, text: 'Cruz struck out.', away: 0, home: 0)])!.label;
    expect(label(1), 'Top 1st');
    expect(label(2), 'Top 2nd');
    expect(label(3), 'Top 3rd');
    expect(label(11), 'Top 11th');
    expect(label(12), 'Top 12th');
  });
}
