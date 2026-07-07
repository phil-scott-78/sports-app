import 'package:flutter/material.dart';
import '../models.dart';
import '../theme.dart';
import '../util.dart';
import 'widgets.dart';

/// The one way the app renders a list of in-game action — the Timeline/Plays tab
/// and every scoring recap, for EVERY sport (design turn 9). One grammar:
/// reverse-chronological, grouped by period under a header carrying the running
/// score, each row a time gutter + a team-colour marker + copy, and scoring rows
/// lifting with a team-colour wash and the running score.
///
/// Two row flavours share that grammar:
///  - soccer/rugby carry structured [MatchEvent]s (kind = goal/card/sub/…), which
///    compose a headline ("GOAL — Kane") and a typed marker;
///  - every other sport projects its play-by-play ([SummaryPlay] → kind
///    `score`/`play`), rendering the play text with a team-colour marker.
///
/// [scoringOnly] is the condensed recap log (scores only). [tallyScore] derives
/// the running score by counting (soccer, where ESPN ships none); generic feeds
/// carry it per play, so it's shown regardless.
class ActionFeed extends StatelessWidget {
  final Competition comp;
  final List<MatchEvent> events;
  final bool scoringOnly;
  final bool tallyScore;
  final String? label;
  const ActionFeed(
    this.events,
    this.comp, {
    super.key,
    this.scoringOnly = false,
    this.tallyScore = false,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final list = events
        .where((e) => scoringOnly ? e.isScoring : e.kind != 'other')
        .toList();
    if (list.isEmpty) return scoringOnly ? const SizedBox.shrink() : _empty();

    // Chronological: by period, then minute when known (soccer), else feed order.
    final keyed = [for (var i = 0; i < list.length; i++) (list[i], i)];
    keyed.sort((a, b) {
      final pd = _period(a.$1) - _period(b.$1);
      if (pd != 0) return pd;
      final ta = a.$1.t, tb = b.$1.t;
      if (ta != null && tb != null && ta != tb) return ta - tb;
      return a.$2 - b.$2;
    });

    // Walk ascending: tally/carry the running score, flag lead changes (the §9
    // signal), and bucket by period.
    final byPeriod = <int, List<_Row>>{};
    final order = <int>[];
    int home = 0, away = 0;
    int leadSign = 0; // sign of (home − away) at the last scoring event
    _Row? lastScore;
    for (final (e, _) in keyed) {
      final p = _period(e);
      final row = _Row(e);
      if (e.isScoring) {
        num? a, h;
        if (e.scoreAway != null && e.scoreHome != null) {
          a = e.scoreAway;
          h = e.scoreHome;
        } else if (tallyScore) {
          if (e.side == 'home') {
            home++;
          } else {
            away++;
          }
          a = away;
          h = home;
        }
        if (a != null && h != null) {
          row.score = _score(a, h);
          final sign = h == a ? 0 : (h > a ? 1 : -1);
          if (sign != 0 && leadSign != 0 && sign != leadSign) {
            row.leadChange = true;
          }
          if (sign != 0) leadSign = sign;
        }
        lastScore = row;
      }
      (byPeriod[p] ??= (() {
        order.add(p);
        return <_Row>[];
      })())
          .add(row);
    }
    lastScore?.bright = true;

    // Newest period first; newest event first within each.
    final rows = <Widget>[];
    if (label != null) {
      rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
          child: CardLabel(label!)));
    }
    for (final p in order.reversed) {
      final bucket = byPeriod[p]!;
      // the container's running score at the break (§9: 'HALF TIME · 1–1').
      String? trailing;
      for (final r in bucket.reversed) {
        if (r.score != null) {
          trailing = r.score;
          break;
        }
      }
      rows.add(_periodHeader(bucket.first.e, p, trailing));
      for (final r in bucket.reversed) {
        rows.add(_eventRow(r));
      }
    }
    return _card(rows);
  }

  // ---- structure -----------------------------------------------------------

  Widget _card(List<Widget> children) => Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: T.surface,
          borderRadius: BorderRadius.circular(T.cardRadius),
        ),
        padding: const EdgeInsets.only(bottom: 4),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  /// A period break as the §7.4/§9 rule-label divider, carrying the container's
  /// running score ('3RD QUARTER · 68–61').
  Widget _periodHeader(MatchEvent first, int period, String? score) {
    final label = (first.periodLabel ?? _periodName(period)).toUpperCase();
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
      child: RuleLabelDivider(score != null ? '$label · $score' : label),
    );
  }

  Widget _eventRow(_Row r) {
    final e = r.e;
    final color = _sideColor(e.side);
    final scoring = e.isScoring;
    final sub = _subtitle(e);
    return Container(
      decoration: BoxDecoration(
        gradient: scoring
            ? LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [color.withValues(alpha: 0.10), Colors.transparent],
              )
            : null,
        border: const Border(bottom: BorderSide(color: T.divider)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 38,
          child: Text(e.clock ?? '',
              style: TextStyle(
                  fontFamily: 'BarlowCondensed',
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: scoring ? T.text : T.textDim)),
        ),
        SizedBox(
            width: 18,
            child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: _marker(e, color)))),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              // the §8/§9 score-type chip (football TD/FG); other sports: none.
              if (_scoreType(e) != null) ...[
                ScoreTypeChip(_scoreType(e)!, color: color),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(_headline(e),
                    style: TextStyle(
                        fontSize: 13.5,
                        height: 1.3,
                        fontWeight:
                            scoring ? FontWeight.w700 : FontWeight.w500,
                        color: T.text)),
              ),
              // the lead-change signal (§9 D): the LEAD badge, team-tinted.
              if (r.leadChange) ...[
                const SizedBox(width: 6),
                SignalPill('LEAD', tint: color),
              ],
            ]),
            if (sub != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(sub,
                    style: const TextStyle(
                        fontSize: 12, height: 1.4, color: T.textDim)),
              ),
          ]),
        ),
        // the running score after a scoring event (§7.5): Barlow 18, white latest.
        if (r.score != null)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: RunningScore(r.score!, bright: r.bright),
          ),
      ]),
    );
  }

  /// The football score-type chip label (§8/§9), read from the play text — data
  /// presence, not sport name. Non-football scoring rows return null (no chip).
  String? _scoreType(MatchEvent e) {
    if (!e.isScoring) return null;
    final t = (e.text ?? '').toLowerCase();
    if (t.contains('touchdown')) return 'TD';
    if (t.contains('field goal')) return 'FG';
    if (t.contains('safety')) return 'SAF';
    return null;
  }

  Widget _empty() => Container(
        width: double.infinity,
        padding: T.cardPad,
        decoration: BoxDecoration(
          color: T.surface,
          borderRadius: BorderRadius.circular(T.cardRadius),
        ),
        child: const Text('No plays yet.',
            style: TextStyle(fontSize: 13, color: T.textFaint)),
      );

  // ---- marker / copy -------------------------------------------------------

  Widget _marker(MatchEvent e, Color color) {
    switch (e.kind) {
      case 'goal':
      case 'penalty-goal':
      case 'own-goal':
        return Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle));
      case 'score': // generic scoring play / rugby try — the app's ColorBar glyph
        return ColorBar(color, width: 4, height: 22, radius: 2);
      case 'penalty-missed':
        return Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2)));
      case 'yellow-card':
        return Container(
            width: 11,
            height: 15,
            decoration: BoxDecoration(
                color: T.gold, borderRadius: BorderRadius.circular(2)));
      case 'red-card':
        return Container(
            width: 11,
            height: 15,
            decoration: BoxDecoration(
                color: T.live, borderRadius: BorderRadius.circular(2)));
      case 'substitution':
        return Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
                color: T.track,
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2)));
      case 'var':
        return Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
                color: T.track,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: T.textFaint, width: 1.5)));
      default: // generic non-scoring play
        return Container(
            width: 7,
            height: 7,
            decoration:
                const BoxDecoration(color: T.textFaint, shape: BoxShape.circle));
    }
  }

  String _headline(MatchEvent e) {
    final who = e.athlete;
    switch (e.kind) {
      case 'goal':
      case 'penalty-goal':
        return who != null ? 'GOAL — $who' : 'GOAL';
      case 'own-goal':
        return who != null ? 'OWN GOAL — $who' : 'OWN GOAL';
      case 'penalty-missed':
        return who != null ? 'Penalty missed — $who' : 'Penalty missed';
      case 'yellow-card':
        return who != null ? 'Yellow card — $who' : 'Yellow card';
      case 'red-card':
        return who != null ? 'Red card — $who' : 'Red card';
      case 'substitution':
        return e.teamAbbr != null ? 'Substitution — ${e.teamAbbr}' : 'Substitution';
      case 'var':
        return who != null ? 'VAR — $who' : 'VAR';
      default: // score / play — the play text is already a full sentence
        return e.text ?? e.kind;
    }
  }

  String? _subtitle(MatchEvent e) {
    switch (e.kind) {
      case 'goal':
        return e.assist != null ? 'Assist: ${e.assist}' : null;
      case 'penalty-goal':
        return e.assist != null ? 'Penalty · Assist: ${e.assist}' : 'Penalty';
      case 'substitution':
        if (e.athlete != null && e.assist != null) {
          return '${e.athlete} on · ${e.assist} off';
        }
        return e.text;
      case 'var':
        return e.text;
      default:
        return null;
    }
  }

  Color _sideColor(String? side) {
    if (side == 'home') return teamColor(comp.home);
    if (side == 'away') return teamColor(comp.away);
    return T.textFaint;
  }

  String _score(num away, num home) => '$away–$home';

  int _period(MatchEvent e) => e.period ?? _inferPeriod(e.t ?? _clockMinutes(e.clock) ?? 0);

  int _inferPeriod(int min) =>
      min <= 45 ? 1 : (min <= 90 ? 2 : (min <= 105 ? 3 : (min <= 120 ? 4 : 5)));

  /// Fallback period label when the feed carries no [MatchEvent.periodLabel]
  /// (soccer's structured timeline ships only the number; NFL plays omit it too)
  /// — derived from the competition's own period unit so football reads
  /// "3RD QUARTER", hockey "2ND PERIOD", soccer "2ND HALF".
  String _periodName(int period) {
    final reg = comp.periods.regulation;
    final unit = comp.periods.unit;
    if (unit == 'half') return _half(period);
    if (reg > 0 && period > reg) {
      final ot = period - reg;
      return ot == 1 ? 'Overtime' : '${ot}OT';
    }
    final ord = _ordinal(period);
    return switch (unit) {
      'quarter' => '$ord Quarter',
      'period' => '$ord Period',
      'inning' => '$ord Inning',
      'set' => '$ord Set',
      _ => 'Period $period',
    };
  }

  String _half(int period) => switch (period) {
        1 => '1st Half',
        2 => '2nd Half',
        3 => 'Extra Time',
        4 => 'Extra Time',
        5 => 'Penalties',
        _ => 'Period $period',
      };

  String _ordinal(int n) {
    final m = n % 100;
    if (m >= 11 && m <= 13) return '${n}th';
    return switch (n % 10) {
      1 => '${n}st',
      2 => '${n}nd',
      3 => '${n}rd',
      _ => '${n}th',
    };
  }
}

/// Parse a soccer clock ("45'+2'", "73'") to minutes, tolerant of stoppage time.
int? _clockMinutes(String? clock) {
  if (clock == null) return null;
  final m = RegExp(r'^(\d+)').firstMatch(clock.trim());
  if (m == null) return null;
  var min = int.parse(m.group(1)!);
  final plus = RegExp(r'\+\s*(\d+)').firstMatch(clock);
  if (plus != null) min += int.parse(plus.group(1)!);
  return min;
}

class _Row {
  final MatchEvent e;
  String? score;
  bool bright = false;
  bool leadChange = false; // the scoring event that flipped the lead (§9 signal)
  _Row(this.e);
}
