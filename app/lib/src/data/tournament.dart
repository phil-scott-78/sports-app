// tournament.dart — Dart port of worker/src/tournament.js (the golden-parity
// oracle). Raw (range) scoreboard(s) + optional league standings → canonical
// TournamentResponse (schema/canonical.ts §Tournament, spec §2.7). Pure map→map,
// no I/O. Behavior is data-presence + profile-discriminator driven, never sport
// name; unknown round labels become a pass-through bucket — never a crash.
// Verified byte-for-byte against the JS oracle via test/port_tournament_test.dart.

import 'util.dart';
import 'profiles.dart';
import 'normalize.dart' show statusToPhase;
import 'standings.dart' as st;

// ---- round classification -----------------------------------------------------
/// One canonical key from any of the three observed label vocabularies (tennis
/// round.displayName / notes[].headline / soccer altGameNote). Specificity order
/// mirrors the oracle ('Qualifying Final' is qualifying, not final). Returns a
/// canonical key, 'pool' (double-elim pool game), or null (unknown).
String? classifyRound(dynamic label) {
  final s = jsStr(label ?? '');
  if (s.isEmpty) return null;
  bool re(String p) => RegExp(p, caseSensitive: false).hasMatch(s);
  if (re('elimination|advances to')) return 'pool';
  if (re('qualif')) return 'qualifying';
  if (re('group|league phase')) return 'group';
  final ro = RegExp(r'round of (\d+)', caseSensitive: false).firstMatch(s);
  if (ro != null) return _roundOfKey(int.parse(ro.group(1)!));
  if (re('sweet (16|sixteen)')) return 'roundOf16';
  if (re('elite (8|eight)')) return 'quarterfinal';
  if (re('final four')) return 'semifinal';
  if (re('quarter')) return 'quarterfinal';
  if (re('semi')) return 'semifinal';
  if (re('third place|3rd place|bronze')) return 'thirdPlace';
  if (re(r'\bfinals?\b|championship')) return 'final';
  return null;
}

String? _roundOfKey(int n) {
  if (n == 2) return 'final';
  if (n == 4) return 'semifinal';
  if (n == 8) return 'quarterfinal';
  if (n == 16 || n == 32 || n == 64 || n == 128) return 'roundOf$n';
  return null;
}

const _wordOrdinals = {
  'first': 1, 'second': 2, 'third': 3, 'fourth': 4, 'fifth': 5, 'sixth': 6,
};

/// Ordinal round number in a segment ('1st Round', 'Round 2', 'First Round') →
/// (n, rest) where rest is the segment minus the round words, or null.
({int n, String rest})? ordinalRound(dynamic seg) {
  final s = jsStr(seg ?? '');
  String? matched;
  int? n;
  final m1 = RegExp(r'(\d+)(?:st|nd|rd|th)\s+round\b', caseSensitive: false).firstMatch(s);
  if (m1 != null) {
    matched = m1.group(0);
    n = int.parse(m1.group(1)!);
  } else {
    final w = RegExp(r'\b(first|second|third|fourth|fifth|sixth)\s+round\b',
            caseSensitive: false)
        .firstMatch(s);
    if (w != null) {
      matched = w.group(0);
      n = _wordOrdinals[w.group(1)!.toLowerCase()];
    } else {
      final r = RegExp(r'\bround\s+(\d+)\b', caseSensitive: false).firstMatch(s);
      if (r != null) {
        matched = r.group(0);
        n = int.parse(r.group(1)!);
      }
    }
  }
  if (matched == null || n == null) return null;
  final rest = s
      .replaceFirst(matched, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return (n: n, rest: rest);
}

// ---- label parsing --------------------------------------------------------------
class _ParsedLabel {
  String? key;
  String roundLabel = '';
  String? bracket;
  int? gameNumber;
  int? ordinal;
}

/// A cleaned label (tournament-title prefix already stripped) → its round bucket.
/// Mirrors parseLabel in the oracle: ' - ' segments, 'Game N' lifted out, the LAST
/// classifiable segment names the round, leftovers become the bracket tag.
_ParsedLabel _parseLabel(dynamic cleaned) {
  final out = _ParsedLabel();
  var s = jsStr(cleaned ?? '').trim();
  final gm = RegExp(r'[\s\-–]*\bgame\s+(\d+)\b', caseSensitive: false).firstMatch(s);
  if (gm != null) {
    out.gameNumber = int.parse(gm.group(1)!);
    s = s.replaceFirst(gm.group(0)!, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }
  s = s.replaceFirst(RegExp(r'[\s,\-–]+$'), '');
  if (s.isEmpty) return out;
  final segs =
      s.split(' - ').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
  final leftovers = <String>[];
  for (final seg in segs) {
    final k = classifyRound(seg);
    if (k != null) {
      out.key = k;
      out.roundLabel = seg;
      out.ordinal = null;
      continue;
    }
    final ord = ordinalRound(seg);
    if (ord != null) {
      // ordinal round, possibly with an inline region ('East 1st Round')
      out.key = null;
      out.ordinal = ord.n;
      out.roundLabel = ord.rest.isNotEmpty
          ? seg.replaceFirst(ord.rest, ' ').replaceAll(RegExp(r'\s+'), ' ').trim()
          : seg;
      if (ord.rest.isNotEmpty) leftovers.insert(0, ord.rest);
      continue;
    }
    leftovers.add(seg);
  }
  if (out.key == 'group') {
    out.bracket = out.roundLabel; // 'Group A' IS the tag
  } else if (leftovers.isNotEmpty) {
    out.bracket = leftovers[0];
  }
  if (out.roundLabel.isEmpty) out.roundLabel = s;
  return out;
}

/// Longest common prefix over labels, cut back to a word boundary — the shared
/// tournament name ("Men's College World Series - …"). '' when <2 labels or short.
String commonLabelPrefix(List<dynamic> labels) {
  final list = labels.whereType<String>().where((l) => l.isNotEmpty).toList();
  if (list.length < 2) return '';
  var p = list[0];
  for (final l in list.skip(1)) {
    var i = 0;
    while (i < p.length && i < l.length && p[i] == l[i]) {
      i++;
    }
    p = p.substring(0, i);
    if (p.isEmpty) return '';
  }
  // never cut mid-word: if any label continues with a non-space, back up
  if (RegExp(r'\S$').hasMatch(p) &&
      list.any((l) => l.length > p.length && RegExp(r'\S').hasMatch(l[p.length]))) {
    final sp = p.lastIndexOf(' ');
    p = sp < 0 ? '' : p.substring(0, sp);
  }
  p = p.replaceFirst(RegExp(r'[\s,\-–:]+$'), '');
  return p.length >= 8 ? p : '';
}

String _stripPrefix(dynamic label, String prefix) {
  final s = jsStr(label ?? '');
  if (prefix.isEmpty || !s.toLowerCase().startsWith(prefix.toLowerCase())) {
    return s.trim();
  }
  return s.substring(prefix.length).replaceFirst(RegExp(r'^[\s,\-–:]+'), '').trim();
}

// ---- matchup building -----------------------------------------------------------
String _scoreDisplay(dynamic raw) {
  if (raw != null && raw is Map) raw = raw['displayValue'] ?? raw['value'] ?? '';
  return raw == null ? '' : raw.toString();
}

Map<String, dynamic> _buildSide(Map profile, dynamic raw, String phase) {
  final team = field(raw, 'team');
  final ath = field(raw, 'athlete');
  final roster = field(raw, 'roster');
  final side = <String, dynamic>{
    'id': jsStr(field(raw, 'id') ?? field(team, 'id') ?? field(ath, 'id') ?? ''),
    'name': or([
      field(team, 'displayName'), field(ath, 'displayName'),
      field(roster, 'displayName'), field(team, 'name'),
      field(team, 'shortDisplayName'), '',
    ]),
  };
  final short = or([
    field(ath, 'shortName'), field(roster, 'shortDisplayName'),
    field(team, 'shortDisplayName'),
  ]);
  if (truthy(short)) side['shortName'] = short;
  if (truthy(field(team, 'abbreviation'))) side['abbr'] = field(team, 'abbreviation');
  if (truthy(field(raw, 'homeAway'))) side['homeAway'] = field(raw, 'homeAway');
  // seed: ONLY where curatedRank IS the seed — athlete draws (tennis). Team
  // curatedRank is a poll rank (real seeds = core tournamentMatchup, a hook).
  if (profile['competitorKind'] == 'athlete') {
    final cr = field(field(raw, 'curatedRank'), 'current');
    if (cr != null && cr != 99) side['seed'] = cr;
  }
  if (field(raw, 'winner') == true) side['winner'] = true;
  if (field(raw, 'score') != null && phase != 'scheduled') {
    final d = _scoreDisplay(field(raw, 'score'));
    if (d != '') side['score'] = d;
  }
  if (field(raw, 'shootoutScore') != null) side['shootout'] = field(raw, 'shootoutScore');
  final ls = field(raw, 'linescores');
  if (ls is List && ls.isNotEmpty) {
    side['sets'] = ls
        .map((l) => pickNN({
              'value': field(l, 'value'),
              'tiebreak': field(l, 'tiebreak'),
              'winner': field(l, 'winner'),
            }, ['value', 'tiebreak', 'winner']))
        .toList();
  }
  return side;
}

Map<String, dynamic> _buildMatchup(
    Map profile, Map ev, Map rc, _ParsedLabel parsed, String? usedHeadline) {
  final ph = statusToPhase(
      field(rc['status'], 'type') ?? field(ev['status'], 'type') ?? const {});
  final m = <String, dynamic>{'eventId': jsStr(ev['id'])};
  if (rc['id'] != null && jsStr(rc['id']) != jsStr(ev['id'])) {
    m['competitionId'] = jsStr(rc['id']);
  }
  final date = or([rc['date'], ev['date']]);
  if (truthy(date)) m['date'] = date;
  m['phase'] = ph['phase'];
  if (ph['live'] == true) m['live'] = true;
  final head = _headlines(rc).isNotEmpty ? _headlines(rc)[0] : null;
  if (truthy(head) && head != usedHeadline) m['note'] = head;
  if (parsed.gameNumber != null) m['gameNumber'] = parsed.gameNumber;
  if (truthy(parsed.bracket)) m['bracket'] = parsed.bracket;
  m['competitors'] = (rc['competitors'] is List ? rc['competitors'] as List : const [])
      .map((c) => _buildSide(profile, c, jsStr(ph['phase'])))
      .toList();
  return m;
}

List<dynamic> _headlines(Map rc) => (rc['notes'] is List ? rc['notes'] as List : const [])
    .map((n) => field(n, 'headline'))
    .where(truthy)
    .toList();

double _dateMsOf(dynamic iso) {
  if (iso is! String || iso.isEmpty) return double.infinity;
  final t = DateTime.tryParse(iso);
  return t == null ? double.infinity : t.millisecondsSinceEpoch.toDouble();
}

double _dateMs(Map m) => _dateMsOf(m['date']);
String _matchupRef(Map m) => jsStr(m['competitionId'] ?? m['eventId']);

/// Deterministic matchup order: date, then id (stable across JS/Dart sorts).
int _byDate(Map a, Map b) {
  final da = _dateMs(a), db = _dateMs(b);
  if (da != db) return da < db ? -1 : 1;
  return _matchupRef(a).compareTo(_matchupRef(b));
}

// ---- pools (CWS double-elim reconstruction) --------------------------------------
List<Map<String, dynamic>> _buildPools(
    List<({Map ev, Map rc, _ParsedLabel parsed})> items, Set<String> seriesTeamIds) {
  if (items.isEmpty) return const [];
  final games = items.map((it) {
    final ph = statusToPhase(field(it.rc['status'], 'type') ?? const {});
    final head = _headlines(it.rc).isNotEmpty ? jsStr(_headlines(it.rc)[0]) : '';
    return <String, dynamic>{
      'eventId': jsStr(it.ev['id']),
      'date': or([it.rc['date'], it.ev['date']]),
      'phase': ph['phase'],
      'headline': head,
      'sides': (it.rc['competitors'] is List ? it.rc['competitors'] as List : const [])
          .map((c) => <String, dynamic>{
                'id': jsStr(field(c, 'id') ?? field(field(c, 'team'), 'id') ?? ''),
                'name': or([
                  field(field(c, 'team'), 'displayName'),
                  field(field(c, 'team'), 'name'),
                  ''
                ]),
                'abbr': field(field(c, 'team'), 'abbreviation'),
                'winner': field(c, 'winner') == true,
              })
          .toList(),
    };
  }).toList()
    ..sort((a, b) {
      final da = _dateMsOf(a['date']), db = _dateMsOf(b['date']);
      if (da != db) return da < db ? -1 : 1;
      return jsStr(a['eventId']).compareTo(jsStr(b['eventId'])) < 0 ? -1 : 1;
    });

  // connectivity: union teams that met
  final parent = <String, String>{};
  String find(String x) {
    var r = x;
    while (parent[r] != r) {
      r = parent[r]!;
    }
    // path-compress like the recursive oracle
    var c = x;
    while (parent[c] != r) {
      final next = parent[c]!;
      parent[c] = r;
      c = next;
    }
    return r;
  }

  void union(String a, String b) => parent[find(a)] = find(b);
  final teams = <String, Map<String, dynamic>>{};
  for (final g in games) {
    final sides = g['sides'] as List;
    for (final s in sides) {
      final id = jsStr(s['id']);
      if (id.isEmpty) continue;
      parent.putIfAbsent(id, () => id);
      teams.putIfAbsent(id, () => {
            'id': id, 'name': s['name'], 'abbr': s['abbr'],
            'w': 0, 'l': 0, 'advances': false,
          });
      if (truthy(s['name']) && !truthy(teams[id]!['name'])) teams[id]!['name'] = s['name'];
      if (truthy(s['abbr']) && !truthy(teams[id]!['abbr'])) teams[id]!['abbr'] = s['abbr'];
    }
    final ids = sides.map((s) => jsStr(s['id'])).where((x) => x.isNotEmpty).toList();
    for (var i = 1; i < ids.length; i++) {
      union(ids[0], ids[i]);
    }
    if (g['phase'] == 'final') {
      for (final s in sides) {
        final id = jsStr(s['id']);
        if (id.isEmpty) continue;
        if (s['winner'] == true) {
          teams[id]!['w'] = (teams[id]!['w'] as int) + 1;
          if (RegExp('advances to', caseSensitive: false).hasMatch(jsStr(g['headline']))) {
            teams[id]!['advances'] = true;
          }
        } else {
          teams[id]!['l'] = (teams[id]!['l'] as int) + 1;
        }
      }
    }
  }
  // components → pools, ordered by each pool's earliest game
  final compOf = <String, int>{};
  final order = <String>[];
  for (final g in games) {
    String? id;
    for (final s in (g['sides'] as List)) {
      final x = jsStr(s['id']);
      if (x.isNotEmpty) {
        id = x;
        break;
      }
    }
    if (id == null) continue;
    final root = find(id);
    if (!compOf.containsKey(root)) {
      compOf[root] = order.length;
      order.add(root);
    }
  }
  final pools = List.generate(order.length, (_) => <Map<String, dynamic>>[]);
  for (final t in teams.values) {
    pools[compOf[find(jsStr(t['id']))]!].add(t);
  }
  final out = <Map<String, dynamic>>[];
  var i = 0;
  for (final p in pools) {
    if (p.length <= 1) continue;
    i++;
    final rows = p
        .map((t) => <String, dynamic>{
              'team': pickNN({'id': t['id'], 'name': t['name'], 'abbr': t['abbr']},
                  ['id', 'name', 'abbr']),
              'w': t['w'],
              'l': t['l'],
              'status': (t['l'] as int) >= 2
                  ? 'eliminated'
                  : (t['advances'] == true || seriesTeamIds.contains(jsStr(t['id'])))
                      ? 'advances'
                      : 'alive',
            })
        .toList()
      ..sort((a, b) {
        int rank(Map r) =>
            r['status'] == 'advances' ? 0 : r['status'] == 'alive' ? 1 : 2;
        var d = rank(a) - rank(b);
        if (d != 0) return d;
        d = (b['w'] as int) - (a['w'] as int);
        if (d != 0) return d;
        d = (a['l'] as int) - (b['l'] as int);
        if (d != 0) return d;
        final an = jsStr((a['team'] as Map)['name']);
        final bn = jsStr((b['team'] as Map)['name']);
        return an.compareTo(bn);
      });
    out.add({'label': 'Bracket $i', 'rows': rows});
  }
  return out;
}

// ---- series (championship best-of-N) ----------------------------------------------
Map<String, dynamic>? _buildSeries(List<({Map ev, Map rc, _ParsedLabel parsed})> items) {
  if (items.isEmpty) return null;
  final groups = <String, List<({Map ev, Map rc, _ParsedLabel parsed})>>{};
  for (final it in items) {
    final sr = it.rc['series'] as Map;
    final comps = sr['competitors'] is List ? sr['competitors'] as List : const [];
    final ids = comps.map((c) => jsStr(field(c, 'id') ?? '')).toList()..sort();
    groups.putIfAbsent(ids.join('|'), () => []).add(it);
  }
  double parseOr0(dynamic iso) {
    final t = iso is String ? DateTime.tryParse(iso) : null;
    return t == null ? 0 : t.millisecondsSinceEpoch.toDouble();
  }

  List<({Map ev, Map rc, _ParsedLabel parsed})>? best;
  var bestMs = double.negativeInfinity;
  for (final list in groups.values) {
    var ms = double.negativeInfinity;
    for (final it in list) {
      final t = parseOr0(or([it.rc['date'], it.ev['date']]));
      if (t > ms) ms = t;
    }
    if (ms > bestMs) {
      bestMs = ms;
      best = list;
    }
  }
  final games = best!.map((it) {
    final ph = statusToPhase(field(it.rc['status'], 'type') ?? const {});
    final g = <String, dynamic>{'eventId': jsStr(it.ev['id'])};
    final date = or([it.rc['date'], it.ev['date']]);
    if (truthy(date)) g['date'] = date;
    g['phase'] = ph['phase'];
    if (it.parsed.gameNumber != null) g['gameNumber'] = it.parsed.gameNumber;
    g['sides'] = (it.rc['competitors'] is List ? it.rc['competitors'] as List : const [])
        .map((c) {
      final scoreD = ph['phase'] == 'scheduled' ? '' : _scoreDisplay(field(c, 'score'));
      return pickNN({
        'id': jsStr(field(c, 'id') ?? field(field(c, 'team'), 'id') ?? ''),
        'abbr': field(field(c, 'team'), 'abbreviation'),
        'score': scoreD == '' ? null : scoreD,
        'winner': field(c, 'winner') == true ? true : null,
      }, ['id', 'abbr', 'score', 'winner']);
    }).toList();
    return g;
  }).toList()
    ..sort((a, b) {
      final ga = (a['gameNumber'] as int?) ?? 0, gb = (b['gameNumber'] as int?) ?? 0;
      if (ga != gb) return ga - gb;
      final da = _dateMs(a), db = _dateMs(b);
      if (da != db) return da < db ? -1 : 1;
      return 0;
    });
  var last = best[0];
  for (final y in best.skip(1)) {
    if (parseOr0(or([y.rc['date'], y.ev['date']])) >=
        parseOr0(or([last.rc['date'], last.ev['date']]))) {
      last = y;
    }
  }
  final sr = last.rc['series'] as Map;
  final meta = <String, Map<String, dynamic>>{};
  for (final c in (last.rc['competitors'] is List ? last.rc['competitors'] as List : const [])) {
    meta[jsStr(field(c, 'id') ?? field(field(c, 'team'), 'id') ?? '')] = {
      'name': or([field(field(c, 'team'), 'displayName'), field(field(c, 'team'), 'name')]),
      'abbr': field(field(c, 'team'), 'abbreviation'),
    };
  }
  // title: the common cleaned game label ('Championship Final'), else series.title
  final labelSet = <String>{};
  final labels = <String>[];
  for (final it in best) {
    final l = it.parsed.roundLabel;
    if (l.isNotEmpty && labelSet.add(l)) labels.add(l);
  }
  final title = labels.length == 1
      ? labels[0]
      : or([commonLabelPrefix(labels), sr['title']]);
  final out = pickNN({
    'title': truthy(title) ? title : null,
    'total': sr['totalCompetitions'] is num ? sr['totalCompetitions'] : null,
    'completed': sr['completed'] is bool ? sr['completed'] : null,
  }, ['title', 'total', 'completed']);
  out['competitors'] =
      (sr['competitors'] is List ? sr['competitors'] as List : const []).map((c) {
    final id = jsStr(field(c, 'id') ?? '');
    final wins = field(c, 'wins');
    final w = wins is num ? wins : num.tryParse(jsStr(wins));
    return pickNN({
      'id': id,
      'name': field(meta[id], 'name'),
      'abbr': field(meta[id], 'abbr'),
      'wins': (w == null || w.isNaN || !truthy(w)) ? 0 : w,
    }, ['id', 'name', 'abbr', 'wins']);
  }).toList();
  out['games'] = games;
  return out;
}

// ---- groups (round-robin tables) ---------------------------------------------------
/// EXACTLY the rows the standings renderer consumes — normalizeStandings already
/// carries the soccer qualification note {color, description} on each row.
List<Map<String, dynamic>> buildTournamentGroups(dynamic standingsRaw) {
  if (!truthy(standingsRaw)) return const [];
  return st
      .normalizeStandings(standingsRaw)
      .map((g) => {'label': g['name'], 'rows': g['rows']})
      .toList();
}

class _Item {
  final Map ev;
  final Map rc;
  String rawLabel = '';
  String? usedHeadline;
  _ParsedLabel? parsed;

  /// Label came from round.displayName — a pre-created COMPLETE draw (tennis),
  /// the only source where bucket size == round size (gates ordinal refinement).
  bool fromRound = false;
  _Item(this.ev, this.rc);
}

// ---- top level ----------------------------------------------------------------------
/// input: { scoreboards: [raw…] | scoreboard: raw, standings?: raw,
///          grouping?: slug, eventId?: id }. Port of normalizeTournament.
Map<String, dynamic> normalizeTournament(Registry reg, String key, Map input) {
  final profile = resolve(reg, key);
  final raws = input['scoreboards'] is List
      ? input['scoreboards'] as List
      : (input['scoreboard'] != null ? [input['scoreboard']] : const []);
  final evMap = <String, Map>{};
  Map? league;
  for (final sbRaw in raws) {
    final leagues = field(sbRaw, 'leagues');
    if (league == null && leagues is List && leagues.isNotEmpty && leagues[0] is Map) {
      league = leagues[0] as Map;
    }
    final events = field(sbRaw, 'events');
    if (events is List) {
      for (final e in events) {
        if (e is Map && e['id'] != null) evMap[jsStr(e['id'])] = e;
      }
    }
  }
  final events = evMap.values.toList();

  // ---- pick the item list + title/subtitle -----------------------------------
  final drawEvents = events
      .where((e) => e['groupings'] is List && (e['groupings'] as List).isNotEmpty)
      .toList();
  final items = <_Item>[];
  var title = '';
  String? subtitle;
  if (drawEvents.isNotEmpty) {
    Map? ev;
    if (input['eventId'] != null) {
      for (final e in drawEvents) {
        if (jsStr(e['id']) == jsStr(input['eventId'])) {
          ev = e;
          break;
        }
      }
    }
    ev ??= drawEvents.firstWhere((e) => e['major'] == true, orElse: () => drawEvents[0]);
    title = jsStr(or([ev['name'], ev['shortName'], '']));
    final gs = ev['groupings'] as List;
    Map? g;
    if (truthy(input['grouping'])) {
      for (final x in gs) {
        if (field(field(x, 'grouping'), 'slug') == input['grouping']) {
          g = x as Map;
          break;
        }
      }
    }
    g ??= gs[0] is Map ? gs[0] as Map : null;
    final sd = field(field(g, 'grouping'), 'displayName');
    subtitle = truthy(sd) ? jsStr(sd) : null;
    final comps = field(g, 'competitions');
    if (comps is List) {
      for (final rc in comps) {
        if (rc is Map) items.add(_Item(ev, rc));
      }
    }
  } else {
    for (final e in events) {
      final comps = e['competitions'];
      if (comps is List) {
        for (final rc in comps) {
          if (rc is Map) items.add(_Item(e, rc));
        }
      }
    }
    final heads = <String>[];
    for (final e in events) {
      final comps = e['competitions'];
      final c0 = comps is List && comps.isNotEmpty ? comps[0] : null;
      final hs = c0 is Map ? _headlines(c0) : const [];
      if (hs.isNotEmpty) heads.add(jsStr(hs[0]));
    }
    title = jsStr(or([
      commonLabelPrefix(heads),
      field(league, 'name'),
      profile['name'],
      '',
    ]));
  }

  // ---- label each item ---------------------------------------------------------
  for (final it in items) {
    final rc = it.rc;
    final candidates = <String>[];
    void addCand(dynamic v) {
      if (v is String && v.trim().isNotEmpty) candidates.add(v);
    }

    addCand(field(rc['round'], 'displayName'));
    for (final h in _headlines(rc)) {
      addCand(h);
    }
    addCand(rc['altGameNote']);
    addCand(field(rc['series'], 'title'));
    for (final cand in candidates) {
      final parsed = _parseLabel(_stripPrefix(cand, title));
      if (parsed.key != null || parsed.ordinal != null) {
        it.rawLabel = cand;
        it.parsed = parsed;
        it.fromRound = cand == field(rc['round'], 'displayName');
        if (_headlines(rc).contains(cand)) it.usedHeadline = cand;
        break;
      }
    }
    if (it.parsed == null) {
      final hs = _headlines(rc);
      final fallback = jsStr(or([rc['altGameNote'], hs.isNotEmpty ? hs[0] : null, '']));
      it.rawLabel = fallback;
      it.parsed = _parseLabel(_stripPrefix(fallback, title));
    }
  }

  // ---- route: series / pools / rounds ------------------------------------------
  bool hasSeries(_Item it) {
    final sr = it.rc['series'];
    if (sr is! Map) return false;
    final comps = sr['competitors'];
    final total = sr['totalCompetitions'];
    return comps is List && comps.isNotEmpty && total is num && total > 1;
  }

  final seriesItems = items.where(hasSeries).toList();
  final seriesSet = seriesItems.toSet();
  final poolItems = items
      .where((it) => !seriesSet.contains(it) && it.parsed!.key == 'pool')
      .toList();
  final roundItems = items
      .where((it) => !seriesSet.contains(it) && it.parsed!.key != 'pool')
      .toList();

  final series = _buildSeries(
      seriesItems.map((it) => (ev: it.ev, rc: it.rc, parsed: it.parsed!)).toList());
  final seriesTeamIds = <String>{
    if (series != null)
      for (final c in series['competitors'] as List) jsStr((c as Map)['id']),
  };
  final pools = _buildPools(
      poolItems.map((it) => (ev: it.ev, rc: it.rc, parsed: it.parsed!)).toList(),
      seriesTeamIds);

  // rounds: bucket by (group-collapsed) round label
  final buckets = <String, Map<String, dynamic>>{};
  for (final it in roundItems) {
    final p = it.parsed!;
    final bucketId = p.key == 'group'
        ? '#group'
        : (p.roundLabel.isNotEmpty ? p.roundLabel : '#unlabeled');
    buckets.putIfAbsent(
        bucketId,
        () => {
              'key': p.key,
              'label': p.key == 'group' ? 'Group Stage' : p.roundLabel,
              'ordinal': p.ordinal,
              'structured': true,
              'matchups': <Map<String, dynamic>>[],
            });
    final b = buckets[bucketId]!;
    if (!it.fromRound) b['structured'] = false;
    (b['matchups'] as List)
        .add(_buildMatchup(profile, it.ev, it.rc, p, it.usedHeadline));
  }
  // ordinal refinement: 'Round 4' with 8 UNIQUE pairings → roundOf16. ONLY for
  // buckets sourced entirely from round.displayName (a pre-created COMPLETE draw,
  // tennis) — a headline-sourced ordinal bucket may be a PARTIAL slate, where
  // bucket size lies about round size: those pass through with round: null.
  for (final b in buckets.values) {
    if (b['key'] != null || b['ordinal'] == null || b['structured'] != true) continue;
    final ms = b['matchups'] as List;
    final pairs = ms.map((m) {
      final ids = ((m as Map)['competitors'] as List)
          .map((c) => jsStr((c as Map)['id']))
          .where((x) => x.isNotEmpty)
          .toList()
        ..sort();
      return ids.join('|');
    }).toList();
    final unique =
        pairs.toSet().length == pairs.length && pairs.every((p) => p.isNotEmpty);
    if (unique) b['key'] = _roundOfKey(ms.length * 2);
  }
  final rounds = buckets.values.map((b) {
    final ms = (b['matchups'] as List).cast<Map<String, dynamic>>()..sort(_byDate);
    return <String, dynamic>{'round': b['key'], 'label': b['label'], 'matchups': ms};
  }).toList()
    ..sort((a, b) {
      final ams = a['matchups'] as List;
      final bms = b['matchups'] as List;
      final am = ams.isNotEmpty ? _dateMs(ams[0] as Map) : double.infinity;
      final bm = bms.isNotEmpty ? _dateMs(bms[0] as Map) : double.infinity;
      if (am != bm) return am < bm ? -1 : 1;
      return jsStr(a['label']).compareTo(jsStr(b['label']));
    });

  // ---- cheap-path bracket linkage ----------------------------------------------
  // A DECIDED matchup links forward to the earliest later matchup IN A DIFFERENT
  // ROUND that contains its winner (real ids only) — a winner never advances
  // within its own round, so same-bucket candidates are never edges.
  final linkable = <({Map<String, dynamic> m, int ri})>[];
  for (var ri = 0; ri < rounds.length; ri++) {
    final r = rounds[ri];
    if (r['round'] == 'group') continue;
    for (final m in (r['matchups'] as List).cast<Map<String, dynamic>>()) {
      linkable.add((m: m, ri: ri));
    }
  }
  for (final lk in linkable) {
    final m = lk.m;
    Map? w;
    for (final c in (m['competitors'] as List)) {
      if ((c as Map)['winner'] == true) {
        w = c;
        break;
      }
    }
    final widStr = w != null ? jsStr(w['id']) : '';
    final wid = widStr.isNotEmpty && !widStr.startsWith('-') ? widStr : null;
    if (wid == null || !_dateMs(m).isFinite) continue;
    Map<String, dynamic>? best;
    for (final nk in linkable) {
      final n = nk.m;
      if (identical(n, m) || nk.ri == lk.ri || !(_dateMs(n) > _dateMs(m))) continue;
      if (!(n['competitors'] as List).any((c) => jsStr((c as Map)['id']) == wid)) {
        continue;
      }
      if (best == null || _byDate(n, best) < 0) best = n;
    }
    if (best != null) m['advancesTo'] = _matchupRef(best);
  }

  // ---- assemble ------------------------------------------------------------------
  final groups = buildTournamentGroups(input['standings']);
  final out = <String, dynamic>{'league': key, 'title': title};
  if (subtitle != null) out['subtitle'] = subtitle;
  if (groups.isNotEmpty) out['groups'] = groups;
  if (rounds.isNotEmpty) out['rounds'] = rounds;
  if (pools.isNotEmpty) out['pools'] = pools;
  if (series != null) out['series'] = series;
  return out;
}
