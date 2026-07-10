// fastcast_merge.dart — merge a FastCast slate overlay (normalizeFastcastSlate
// output, fastcast.dart) over the last polled canonical scoreboard. Track 2 of
// fastcast-plan.md: the event-* doc can never REPLACE the scoreboard (its
// events are flattened — no linescores/leaders/probables/timeline), so the
// overlay updates only what push carries: status, score, winner, situation,
// seriesSummary — and the derived bits those feed (decision, periods.played /
// isOvertime, top-level anyLive / nextStartMs).
//
// Dart-only, NO JS oracle: like marquee.dart this is DOWNSTREAM of canonical
// (both inputs are already-normalized shapes; there is no worker-side merge).
// Unit-tested in test/fastcast_merge_test.dart. Inputs are never mutated.

import 'normalize.dart' show decide, nextScheduledStart, otUnits;

dynamic _deepCopy(dynamic v) {
  if (v is List) return v.map(_deepCopy).toList();
  if (v is Map) return {for (final k in v.keys) k: _deepCopy(v[k])};
  return v;
}

/// Merge [overlay] (`{key, events[]}`) into a COPY of [slate] (a canonical
/// normalized scoreboard). Overlay events match a competition by competition
/// id, falling back to the event id for single-competition events (they're the
/// same for team sports; multi-comp events — racing weekends, tennis draws —
/// only merge on an exact comp-id hit). Unmatched overlay events are ignored:
/// a game that just appeared on ESPN's slate arrives via the reconciliation
/// poll, never the overlay.
Map<String, dynamic> mergeFastcastSlate(
    Map profile, Map<String, dynamic> slate, Map overlay) {
  final out = Map<String, dynamic>.from(_deepCopy(slate) as Map);
  final events = out['events'] is List ? out['events'] as List : const [];
  final byId = <String, Map>{};
  for (final ov in (overlay['events'] is List ? overlay['events'] as List : const [])) {
    if (ov is Map && ov['id'] != null) byId[ov['id'].toString()] = ov;
  }
  if (byId.isEmpty || events.isEmpty) return out;

  var touched = false;
  for (final ev in events) {
    if (ev is! Map) continue;
    final comps = ev['competitions'] is List ? ev['competitions'] as List : const [];
    for (final comp in comps) {
      if (comp is! Map) continue;
      final ov = byId[comp['id']?.toString()] ??
          (comps.length == 1 ? byId[ev['id']?.toString()] : null);
      if (ov == null) continue;
      _applyToCompetition(profile, comp, ov);
      touched = true;
    }
  }
  if (touched) {
    // The pushed statuses move the derived slate signals too — anyLive drives
    // the poll cadence, nextStartMs the near-kickoff tier.
    out['anyLive'] = events.any((ev) {
      final comps = (ev as Map)['competitions'];
      return comps is List &&
          comps.any((c) => c is Map && c['status'] is Map && (c['status'] as Map)['live'] == true);
    });
    final ns = nextScheduledStart(events);
    if (ns != null) {
      out['nextStartMs'] = ns;
    } else {
      out.remove('nextStartMs');
    }
  }
  return out;
}

void _applyToCompetition(Map profile, Map comp, Map ov) {
  final ovSt = ov['status'];
  if (ovSt is Map) {
    final st = _deepCopy(ovSt) as Map;
    final old = comp['status'];
    // The overlay mirrors buildCompetition's status EXCEPT altDetail, which is
    // poll-only — carry it over rather than lose it until reconciliation.
    if (old is Map && old['altDetail'] != null && !st.containsKey('altDetail')) {
      st['altDetail'] = old['altDetail'];
    }
    comp['status'] = st;
    // Track the pushed period so periods.played / isOvertime can't lag a whole
    // reconciliation window when a game runs long. (Line-score COLUMNS still
    // arrive by poll — the overlay carries no per-period scores.)
    final periods = comp['periods'];
    if (periods is Map && st['period'] is num) {
      final p = st['period'] as num;
      final played = periods['played'] is num ? periods['played'] as num : 0;
      if (p > played) {
        periods['played'] = p;
        final reg = periods['regulation'] is num ? periods['regulation'] as num : 0;
        periods['isOvertime'] = otUnits.contains(periods['unit']) && reg > 0 && p > reg;
      }
    }
  }
  final ovCs = ov['competitors'];
  if (ovCs is List) {
    final cs = comp['competitors'] is List ? comp['competitors'] as List : const [];
    for (final oc in ovCs) {
      if (oc is! Map || oc['id'] == null) continue;
      for (final c in cs) {
        if (c is Map && c['id']?.toString() == oc['id'].toString()) {
          if (oc.containsKey('score')) c['score'] = _deepCopy(oc['score']);
          if (oc['winner'] is bool) c['winner'] = oc['winner'];
          break;
        }
      }
    }
  }
  // Situation: replace when the overlay carries one; when absent, KEEP the
  // polled situation — some event docs never serve one for a sport that has it,
  // and the reconciliation poll clears anything truly gone. The event doc's
  // situation never carries dueUp, so the polled onDeck is carried over rather
  // than flickering off until reconciliation (same rule as status.altDetail).
  if (ov['situation'] is Map) {
    final st = _deepCopy(ov['situation']) as Map;
    final old = comp['situation'];
    if (old is Map && old['onDeck'] != null && !st.containsKey('onDeck')) {
      st['onDeck'] = old['onDeck'];
    }
    // dueUp rides the same rule as onDeck: the event doc's situation never
    // carries it, so the polled list persists until reconciliation clears it.
    if (old is Map && old['dueUp'] != null && !st.containsKey('dueUp')) {
      st['dueUp'] = old['dueUp'];
    }
    comp['situation'] = st;
  }
  if (ov['seriesSummary'] != null) {
    final meta = comp['meta'] is Map
        ? comp['meta'] as Map
        : (comp['meta'] = <String, dynamic>{}) as Map;
    meta['seriesSummary'] = ov['seriesSummary'];
  }
  // A pushed final needs its decision (winner presentation); shootout/aggregate
  // inputs may lag the poll, so keep the old decision as the fallback.
  comp['decision'] = decide(profile, comp) ?? comp['decision'];
}
