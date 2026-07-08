// summary.dart — Dart port of worker/src/summary.js. Raw ESPN /summary →
// canonical GameSummary JSON map (schema/canonical.ts), fed into models.dart's
// GameSummary.fromJson. The RICH tier: box scores, team-stat comparison, scoring
// feed, per-period splits, lineups, MMA bouts. Pure. Faithful port — kept in
// lock-step with the JS; the summary golden suite asserts byte parity.

import 'profiles.dart';
import 'util.dart';

// summary.js's `pick` drops null AND '' → pickT (util). `str` → jsStr.
num? _numOrNull(dynamic v) {
  if (v is num) return v;
  if (v is String && RegExp(r'^-?\d+$').hasMatch(v)) return int.parse(v);
  return null;
}

String? _cap(dynamic s) {
  if (!truthy(s)) return s as String?;
  final str = s.toString();
  return str[0].toUpperCase() + str.substring(1);
}

String aShort(dynamic a) => or([field(a, 'shortName'), field(a, 'displayName'), field(a, 'fullName'), '']);
dynamic _aPos(dynamic a) => or([field(field(a, 'position'), 'abbreviation'), field(field(a, 'position'), 'name')]);

// ---- side maps --------------------------------------------------------------
Map<String, dynamic> _sideMaps(Map raw) {
  final cs = field(first(field(raw['header'], 'competitions')), 'competitors');
  final compsList = cs is List ? cs : const [];
  final side = <String, dynamic>{}, abbr = <String, dynamic>{}, nameSide = <String, dynamic>{}, haAbbr = <String, dynamic>{};
  for (final c in compsList) {
    final id = jsStr(field(c, 'id') ?? field(field(c, 'team'), 'id') ?? '');
    final ha = field(c, 'homeAway');
    if (id != '' && ha != null) side[id] = ha;
    final a = field(field(c, 'team'), 'abbreviation');
    if (id != '' && a != null) abbr[id] = a;
    if (ha != null) {
      if (a != null) haAbbr[ha] = a;
      final t = field(c, 'team') ?? {};
      for (final n in [field(t, 'displayName'), field(t, 'shortDisplayName'), field(t, 'name')]) {
        if (truthy(n)) nameSide[n] = ha;
      }
    }
  }
  // athlete id → short name, for resolving a play's participant to an actor name
  // (§4b basketball). Built from the boxscore, the only place ids meet names.
  final athletes = <String, dynamic>{};
  final players = field(raw['boxscore'], 'players');
  if (players is List) {
    for (final tb in players) {
      final stats = field(tb, 'statistics');
      if (stats is List) {
        for (final g in stats) {
          final aths = field(g, 'athletes');
          if (aths is List) {
            for (final a in aths) {
              final id = jsStr(field(field(a, 'athlete'), 'id') ?? '');
              if (id != '' && !truthy(athletes[id])) {
                athletes[id] = aShort(field(a, 'athlete'));
              }
            }
          }
        }
      }
    }
  }
  return {'side': side, 'abbr': abbr, 'nameSide': nameSide, 'haAbbr': haAbbr, 'comps': compsList, 'athletes': athletes};
}

// ---- team stat comparison ---------------------------------------------------
const _teamStatDeny = {
  'largestLead', 'leadChanges', 'leadPercentage',
  'totalTurnovers', 'teamTurnovers', 'totalTechnicalFouls',
  'fullTimeoutsRemaining', 'shortTimeoutsRemaining', 'timeoutsRemaining', 'timeoutsUsed',
};

List<Map<String, dynamic>> _buildTeamStats(Map raw) {
  final teams = field(raw['boxscore'], 'teams');
  if (teams is! List || teams.length < 2) return [];
  final byHa = <String, dynamic>{};
  for (final t in teams) {
    if (field(t, 'homeAway') != null) byHa[field(t, 'homeAway')] = t;
  }
  final away = byHa['away'] ?? teams[0];
  final home = byHa['home'] ?? teams[1];
  Map<String, dynamic> flat(dynamic t) {
    final m = <String, dynamic>{};
    for (final s in (field(t, 'statistics') is List ? field(t, 'statistics') as List : const [])) {
      if (field(s, 'displayValue') == null) continue;
      if (_teamStatDeny.contains(field(s, 'name'))) continue;
      m[field(s, 'name')] = {
        'label': or([field(s, 'label'), field(s, 'shortDisplayName'), field(s, 'displayName'), field(s, 'name')]),
        'value': jsStr(field(s, 'displayValue')),
      };
    }
    return m;
  }

  final a = flat(away), h = flat(home);
  final rows = <Map<String, dynamic>>[];
  final seen = <String>{};
  for (final k in a.keys) {
    seen.add(k);
    rows.add(pickT({'label': a[k]['label'], 'away': a[k]['value'], 'home': field(h[k], 'value')}, ['label', 'away', 'home']));
  }
  for (final k in h.keys) {
    if (seen.contains(k)) continue;
    rows.add(pickT({'label': h[k]['label'], 'home': h[k]['value']}, ['label', 'home']));
  }
  return rows.where((r) => r['away'] != null || r['home'] != null).toList();
}

// ---- per-player box groups --------------------------------------------------
List<Map<String, dynamic>> _buildBoxGroups(Map raw, Map side) {
  final players = field(raw['boxscore'], 'players');
  if (players is! List || players.isEmpty) return [];
  final order = <String>[];
  final byTitle = <String, Map<String, dynamic>>{};
  for (final teamBlock in players) {
    final tid = jsStr(field(field(teamBlock, 'team'), 'id') ?? '');
    final teamSide = side[tid];
    final teamAbbr = field(field(teamBlock, 'team'), 'abbreviation');
    for (final g in (field(teamBlock, 'statistics') is List ? field(teamBlock, 'statistics') as List : const [])) {
      final title = or([_cap(or([field(g, 'name'), field(g, 'type')])), 'Players']);
      final columns = (field(g, 'labels') is List ? field(g, 'labels') as List : const []).map(jsStr).toList();
      final rows = <Map<String, dynamic>>[];
      for (final aRow in (field(g, 'athletes') is List ? field(g, 'athletes') as List : const [])) {
        final name = aShort(field(aRow, 'athlete'));
        final stats = (field(aRow, 'stats') is List ? field(aRow, 'stats') as List : const []).map(jsStr).toList();
        if (name == '' || stats.isEmpty || (columns.isNotEmpty && stats.length != columns.length)) continue;
        // baseball substitutions (§3d): the batting LINEUP note, NOT the
        // pitchingDecision (W/L). starter only when ESPN ships it (baseball).
        final notes = field(aRow, 'notes');
        String? note;
        if (notes is List) {
          for (final n in notes) {
            if (field(n, 'type') == 'lineup') {
              note = field(n, 'text');
              break;
            }
          }
        }
        final st = field(aRow, 'starter');
        rows.add(pickT({
          'name': name,
          'pos': or([_aPos(field(aRow, 'athlete')), field(field(aRow, 'position'), 'abbreviation')]),
          'stats': stats,
          'starter': st is bool ? st : null,
          'note': note,
        }, ['name', 'pos', 'stats', 'starter', 'note']));
      }
      if (rows.isEmpty) continue;
      if (!byTitle.containsKey(title)) {
        byTitle[title] = {'title': title, 'columns': columns, 'teams': []};
        order.add(title);
      }
      final grp = byTitle[title]!;
      if ((grp['columns'] as List).isEmpty && columns.isNotEmpty) grp['columns'] = columns;
      (grp['teams'] as List).add(pickT({'side': teamSide, 'abbr': teamAbbr, 'rows': rows}, ['side', 'abbr', 'rows']));
    }
  }
  return order.map((t) => byTitle[t]!).toList();
}

// ---- scoring feed -----------------------------------------------------------
final _soccerKeep = RegExp(r'goal|card|penalt|substitution', caseSensitive: false);

String cleanSubText(dynamic text) {
  final t = text is String ? text : '';
  final tail = RegExp(r"([^.]*\breplaces\b[^.]*\.?)\s*$", caseSensitive: false).firstMatch(t);
  final res = (tail != null ? tail.group(1)! : t.replaceFirst(RegExp(r'^substitution[,.]?\s*', caseSensitive: false), '')).trim();
  return res.isNotEmpty ? res : t;
}

Map<String, dynamic> _mapPlay(Map p, Map side, Map abbr, Map athletes) {
  final tid = jsStr(field(p['team'], 'id') ?? '');
  // Baseball ships period.type = 'Top'|'Bottom' → canonical half, so the feed can
  // key containers on (period, half) — a 4-run bottom no longer merges into the
  // top of the same inning (§3c). Absent for every other sport.
  final pt = field(p['period'], 'type');
  final half = (pt != null && pt != '') ? pt.toString().toLowerCase() : null;
  // basketball actor (§4b): the first participant's athlete, resolved to a name via
  // the boxscore. Absent when there's no participant or the id isn't in the box —
  // the app then renders the whole line dim rather than guessing.
  final parts = field(p, 'participants');
  final firstPart = (parts is List && parts.isNotEmpty) ? parts.first : null;
  final pid = jsStr(field(field(firstPart, 'athlete'), 'id') ?? '');
  final actor = pid != '' ? athletes[pid] : null;
  return pickT({
    'period': field(p['period'], 'number'),
    'half': half == 'top' || half == 'bottom' ? half : null,
    'periodLabel': field(p['period'], 'displayValue'),
    'clock': field(p['clock'], 'displayValue'),
    'side': or([side[tid], field(p['team'], 'homeAway')]),
    'teamAbbr': or([abbr[tid], field(p['team'], 'abbreviation')]),
    'actor': actor,
    'text': or([p['text'], p['shortText'], '']),
    'away': _numOrNull(p['awayScore']),
    'home': _numOrNull(p['homeScore']),
    'type': or([field(p['scoringType'], 'displayName'), field(p['type'], 'text')]),
  }, ['period', 'half', 'periodLabel', 'clock', 'side', 'teamAbbr', 'actor', 'text', 'away', 'home', 'type']);
}

List<Map<String, dynamic>> _buildScoringPlays(Map raw, Map side, Map abbr, Map athletes) {
  List src = const [];
  var soccer = false;
  if (raw['scoringPlays'] is List && (raw['scoringPlays'] as List).isNotEmpty) {
    src = raw['scoringPlays'] as List;
  } else if (raw['plays'] is List && (raw['plays'] as List).isNotEmpty) {
    src = (raw['plays'] as List).where((p) => field(p, 'scoringPlay') == true).toList();
  } else if (raw['keyEvents'] is List && (raw['keyEvents'] as List).isNotEmpty) {
    src = (raw['keyEvents'] as List)
        .where((p) => field(p, 'scoringPlay') == true || _soccerKeep.hasMatch(jsStr(field(field(p, 'type'), 'text'))))
        .toList();
    soccer = true;
  }
  final out = <Map<String, dynamic>>[];
  for (final p in src) {
    final m = _mapPlay(p as Map, side, abbr, athletes);
    m['scoring'] = soccer ? field(p, 'scoringPlay') == true : true;
    if (truthy(m['text'])) out.add(m);
  }
  for (final p in out) {
    if (RegExp('substitution', caseSensitive: false).hasMatch(jsStr(p['type']))) p['text'] = cleanSubText(p['text']);
  }
  return out.length > 120 ? out.sublist(0, 120) : out;
}

// ---- structured match timeline (soccer) -------------------------------------
final _minuteRe = RegExp(r"^(\d+)(?:'?\s*\+\s*(\d+))?");
num? _clockMinutes(dynamic display) {
  final m = _minuteRe.firstMatch(jsStr(display).trim());
  if (m == null) return null;
  return int.parse(m.group(1)!) + (m.group(2) != null ? int.parse(m.group(2)!) : 0);
}

String? _eventKind(dynamic typeText) {
  final t = jsStr(typeText).toLowerCase();
  if (t == '') return null;
  if (t.contains('own goal')) return 'own-goal';
  if (t.contains('penalt')) return RegExp('miss|saved').hasMatch(t) ? 'penalty-missed' : 'penalty-goal';
  if (t.contains('goal')) return 'goal';
  if (t.contains('red card') || t.contains('second yellow')) return 'red-card';
  if (t.contains('yellow')) return 'yellow-card';
  if (t.contains('substitution')) return 'substitution';
  if (t.contains('var')) return 'var';
  return null;
}

List<Map<String, dynamic>>? buildMatchTimeline(Map raw, Map maps) {
  final side = maps['side'] as Map, abbr = maps['abbr'] as Map;
  final src = raw['keyEvents'];
  if (src is! List || src.isEmpty) return null;
  final out = <Map<String, dynamic>>[];
  for (final e in src) {
    final kind = _eventKind(field(field(e, 'type'), 'text'));
    if (kind == null) continue;
    final tid = jsStr(field(field(e, 'team'), 'id') ?? '');
    final names = (field(e, 'participants') is List ? field(e, 'participants') as List : const [])
        .map((p) => aShort(field(p, 'athlete')))
        .where((n) => truthy(n))
        .toList();
    final twoActor = kind == 'substitution' || kind == 'goal' || kind == 'penalty-goal';
    out.add(pickT({
      't': _clockMinutes(field(field(e, 'clock'), 'displayValue')),
      'clock': field(field(e, 'clock'), 'displayValue'),
      'period': field(field(e, 'period'), 'number'),
      'kind': kind,
      'side': side[tid],
      'teamAbbr': abbr[tid],
      'athlete': names.isNotEmpty ? names[0] : null,
      'assist': twoActor ? (names.length > 1 ? names[1] : null) : null,
      'text': or([field(e, 'text'), field(e, 'shortText'), '']),
      'scoring': field(e, 'scoringPlay') == true,
    }, ['t', 'clock', 'period', 'kind', 'side', 'teamAbbr', 'athlete', 'assist', 'text', 'scoring']));
  }
  if (out.isEmpty) return null;
  final indexed = out.asMap().entries.toList();
  indexed.sort((a, b) {
    final pa = (a.value['period'] ?? 0) as num, pb = (b.value['period'] ?? 0) as num;
    if (pa != pb) return pa.compareTo(pb);
    final ta = (a.value['t'] ?? 0) as num, tb = (b.value['t'] ?? 0) as num;
    if (ta != tb) return ta.compareTo(tb);
    return a.key.compareTo(b.key);
  });
  return indexed.map((x) => x.value).toList();
}

// ---- per-period splits ------------------------------------------------------
Map<String, dynamic>? _buildPeriodLines(Map raw, Map profile) {
  final cs = field(first(field(raw['header'], 'competitions')), 'competitors');
  final competitors = cs is List ? cs : const [];
  if (competitors.length < 2) return null;
  final byHa = <String, dynamic>{};
  for (final c in competitors) {
    if (field(c, 'homeAway') != null) byHa[field(c, 'homeAway')] = c;
  }
  final away = byHa['away'] ?? competitors[0];
  final home = byHa['home'] ?? competitors[1];
  final aLs = field(away, 'linescores') is List ? field(away, 'linescores') as List : const [];
  final hLs = field(home, 'linescores') is List ? field(home, 'linescores') as List : const [];
  final n = aLs.length > hLs.length ? aLs.length : hLs.length;
  if (n == 0) return null;
  final reg = (profile['regulationPeriods'] ?? 0) as num;
  final st = field(first(field(raw['header'], 'competitions')), 'status');
  final stType = field(st, 'type') ?? {};
  final statusStr = '${or([field(stType, 'shortDetail'), ''])} ${or([field(stType, 'detail'), ''])} ${or([field(stType, 'description'), ''])}';
  final wentToShootout = profile['periodUnit'] == 'period' && RegExp(r'\bSO\b|shootout', caseSensitive: false).hasMatch(statusStr);
  final labels = <String>[];
  for (var i = 0; i < n; i++) {
    if (reg == 0 || i < reg) {
      labels.add('${i + 1}');
      continue;
    }
    final ex = i - reg.toInt();
    if (wentToShootout && i == n - 1) {
      labels.add('SO');
      continue;
    }
    labels.add(ex == 0 ? 'OT' : '${ex + 1}OT');
  }
  List<String> vals(List ls) => ls.map((x) => jsStr(field(x, 'displayValue') ?? field(x, 'value') ?? '')).toList();
  return {
    'unit': profile['periodUnit'],
    'labels': labels,
    'away': pickT({'abbr': field(field(away, 'team'), 'abbreviation'), 'values': vals(aLs), 'total': jsStr(field(away, 'score'))}, ['abbr', 'values', 'total']),
    'home': pickT({'abbr': field(field(home, 'team'), 'abbreviation'), 'values': vals(hLs), 'total': jsStr(field(home, 'score'))}, ['abbr', 'values', 'total']),
  };
}

// ---- soccer per-player lines ------------------------------------------------
const _soccerOutfieldCols = [
  ['G', 'totalGoals'], ['A', 'goalAssists'], ['SH', 'totalShots'], ['ST', 'shotsOnTarget'],
  ['YC', 'yellowCards'], ['RC', 'redCards'], ['FC', 'foulsCommitted'], ['FA', 'foulsSuffered'],
];
const _soccerKeeperCols = [['SHF', 'shotsFaced'], ['SV', 'saves'], ['GA', 'goalsConceded']];

List<Map<String, dynamic>> _buildRosterBoxGroups(Map raw, Map side) {
  final rosters = raw['rosters'] is List ? raw['rosters'] as List : const [];
  bool anyStats = rosters.any((r) => (field(r, 'roster') is List ? field(r, 'roster') as List : const []).any((p) => field(p, 'stats') is List && (field(p, 'stats') as List).isNotEmpty));
  if (!anyStats) return [];
  final groups = [
    {'title': 'Players', 'columns': _soccerOutfieldCols.map((c) => c[0]).toList(), 'teams': <dynamic>[]},
    {'title': 'Goalkeepers', 'columns': _soccerKeeperCols.map((c) => c[0]).toList(), 'teams': <dynamic>[]},
  ];
  for (final r in rosters) {
    final teamSide = or([field(r, 'homeAway'), side[jsStr(field(field(r, 'team'), 'id') ?? '')]]);
    final teamAbbr = field(field(r, 'team'), 'abbreviation');
    final out = <Map<String, dynamic>>[], gk = <Map<String, dynamic>>[];
    for (final p in (field(r, 'roster') is List ? field(r, 'roster') as List : const [])) {
      final name = or([aShort(field(p, 'athlete')), field(field(p, 'athlete'), 'displayName')]);
      final stats = <String, dynamic>{};
      for (final s in (field(p, 'stats') is List ? field(p, 'stats') as List : const [])) {
        if (field(s, 'name') != null) stats[field(s, 'name')] = jsStr(field(s, 'displayValue') ?? field(s, 'value') ?? '');
      }
      final played = field(p, 'starter') == true || field(p, 'subbedIn') == true || (_numOrNull(stats['appearances']) ?? 0) > 0;
      if (!truthy(name) || !played || stats.isEmpty) continue;
      final isKeeper = or([field(field(p, 'position'), 'abbreviation'), field(field(p, 'position'), 'name')]) == 'G';
      final cols = isKeeper ? _soccerKeeperCols : _soccerOutfieldCols;
      (isKeeper ? gk : out).add(pickT({
        'name': name,
        'pos': or([_aPos(field(p, 'athlete')), field(field(p, 'position'), 'abbreviation')]),
        'stats': cols.map((c) => or([stats[c[1]], ''])).toList(),
      }, ['name', 'pos', 'stats']));
    }
    if (out.isNotEmpty) (groups[0]['teams'] as List).add(pickT({'side': teamSide, 'abbr': teamAbbr, 'rows': out}, ['side', 'abbr', 'rows']));
    if (gk.isNotEmpty) (groups[1]['teams'] as List).add(pickT({'side': teamSide, 'abbr': teamAbbr, 'rows': gk}, ['side', 'abbr', 'rows']));
  }
  return groups.where((g) => (g['teams'] as List).isNotEmpty).toList();
}

// ---- lineups ----------------------------------------------------------------
List<Map<String, dynamic>> _buildLineups(Map raw, Map side) {
  final rosters = raw['rosters'] is List ? raw['rosters'] as List : const [];
  if (rosters.isEmpty) return [];
  final result = <Map<String, dynamic>>[];
  for (final r in rosters) {
    final rosterList = field(r, 'roster') is List ? field(r, 'roster') as List : const [];
    final players = <Map<String, dynamic>>[];
    for (final p in rosterList) {
      final row = pickT({
        'name': or([aShort(field(p, 'athlete')), field(field(p, 'athlete'), 'displayName')]),
        'pos': or([field(field(p, 'position'), 'abbreviation'), field(field(p, 'position'), 'name')]),
        'jersey': field(p, 'jersey'),
      }, ['name', 'pos', 'jersey']);
      players.add(row);
    }
    final named = players.where((p) => truthy(p['name'])).toList();
    // JS quirk: starters/bench index the FILTERED players list against the raw
    // roster by position — replicate exactly (see summary.js buildLineups).
    final starters = <Map<String, dynamic>>[], bench = <Map<String, dynamic>>[];
    for (var i = 0; i < named.length; i++) {
      if (field(i < rosterList.length ? rosterList[i] : null, 'starter') == true) {
        starters.add(named[i]);
      } else {
        bench.add(named[i]);
      }
    }
    final l = pickT({
      'side': or([field(r, 'homeAway'), side[jsStr(field(field(r, 'team'), 'id') ?? '')]]),
      'abbr': field(field(r, 'team'), 'abbreviation'),
      'formation': field(r, 'formation'),
      'starters': starters,
      'bench': bench,
    }, ['side', 'abbr', 'formation', 'starters', 'bench']);
    if ((l['starters'] is List && (l['starters'] as List).isNotEmpty) || (l['bench'] is List && (l['bench'] as List).isNotEmpty)) {
      result.add(l);
    }
  }
  return result;
}

// ---- season series ----------------------------------------------------------
Map<String, dynamic>? _buildSeasonSeries(Map raw) {
  final ss = raw['seasonseries'];
  if (ss is! List || ss.isEmpty) return null;
  final pref = ss.firstWhere((s) => truthy(field(s, 'type')) && !RegExp('pre', caseSensitive: false).hasMatch(jsStr(field(s, 'type'))), orElse: () => ss[ss.length - 1]);
  final summary = or([field(pref, 'summary'), field(pref, 'description')]);
  if (!truthy(summary)) return null;
  return pickT({
    'summary': jsStr(summary),
    'score': field(pref, 'seriesScore') != null ? jsStr(field(pref, 'seriesScore')) : null,
    'title': field(pref, 'title'),
  }, ['summary', 'score', 'title']);
}

// ---- recent form ------------------------------------------------------------
List<Map<String, dynamic>>? _buildRecentForm(Map raw, Map side) {
  final lf = raw['lastFiveGames'];
  if (lf is! List || lf.isEmpty) return null;
  final out = <Map<String, dynamic>>[];
  for (final t in lf) {
    final tid = jsStr(field(field(t, 'team'), 'id') ?? '');
    final evs = (field(t, 'events') is List ? List.from(field(t, 'events') as List) : <dynamic>[]);
    evs.sort((a, b) {
      final da = DateTime.tryParse(jsStr(field(a, 'gameDate') ?? field(a, 'date') ?? 0))?.millisecondsSinceEpoch ?? 0;
      final db = DateTime.tryParse(jsStr(field(b, 'gameDate') ?? field(b, 'date') ?? 0))?.millisecondsSinceEpoch ?? 0;
      return da.compareTo(db);
    });
    final form = evs.map((e) => jsStr(field(e, 'gameResult') ?? '').toUpperCase()).where((r) => RegExp(r'^[WLTD]$').hasMatch(r)).join('');
    final row = pickT({'side': or([side[tid], field(field(t, 'team'), 'homeAway')]), 'abbr': field(field(t, 'team'), 'abbreviation'), 'form': form}, ['side', 'abbr', 'form']);
    if (truthy(row['form'])) out.add(row);
  }
  return out.isNotEmpty ? out : null;
}

// ---- injuries ---------------------------------------------------------------
List<Map<String, dynamic>>? _buildInjuries(Map raw, Map side) {
  final inj = raw['injuries'];
  if (inj is! List || inj.isEmpty) return null;
  final out = <Map<String, dynamic>>[];
  for (final block in inj) {
    final tid = jsStr(field(field(block, 'team'), 'id') ?? '');
    final items = <Map<String, dynamic>>[];
    for (final it in (field(block, 'injuries') is List ? field(block, 'injuries') as List : const [])) {
      final a = field(it, 'athlete');
      final row = pickT({
        'name': aShort(a),
        'pos': _aPos(a),
        'status': field(it, 'status'),
        'detail': or([field(field(it, 'details'), 'detail'), field(field(it, 'type'), 'description'), field(field(it, 'details'), 'type')]),
        'returnDate': field(field(it, 'details'), 'returnDate'),
      }, ['name', 'pos', 'status', 'detail', 'returnDate']);
      if (truthy(row['name']) && truthy(row['status'])) items.add(row);
    }
    final b = pickT({'side': or([side[tid], field(field(block, 'team'), 'homeAway')]), 'abbr': field(field(block, 'team'), 'abbreviation'), 'items': items}, ['side', 'abbr', 'items']);
    if (b['items'] is List && (b['items'] as List).isNotEmpty) out.add(b);
  }
  return out.isNotEmpty ? out : null;
}

// ---- win probability --------------------------------------------------------
Map<String, dynamic>? _buildWinProbability(Map raw) {
  final wp = raw['winprobability'];
  if (wp is! List || wp.isEmpty) return null;
  final last = wp[wp.length - 1];
  final hRaw = field(last, 'homeWinPercentage');
  if (hRaw is! num) return null;
  final tie = ((field(last, 'tiePercentage') is num ? field(last, 'tiePercentage') as num : 0) * 100).round();
  final home = (hRaw * 100).round();
  final away = (100 - home - tie) < 0 ? 0 : (100 - home - tie);
  return pickT({'home': home, 'away': away, 'tie': tie != 0 ? tie : null}, ['home', 'away', 'tie']);
}

// ---- gridiron drives --------------------------------------------------------
List _drivesList(Map raw) {
  final d = raw['drives'];
  if (d == null || d is! Map) return const [];
  final prev = d['previous'] is List ? d['previous'] as List : const [];
  final cur = d['current'];
  return (cur != null && field(cur, 'id') != null && !prev.any((x) => field(x, 'id') == field(cur, 'id'))) ? [...prev, cur] : prev;
}

List<Map<String, dynamic>>? _buildDrives(Map raw, Map side, Map abbr) {
  final rows = <Map<String, dynamic>>[];
  for (final d in _drivesList(raw)) {
    final tid = jsStr(field(field(d, 'team'), 'id') ?? '');
    final dp = field(d, 'plays') is List ? field(d, 'plays') as List : const [];
    final last = dp.isNotEmpty ? dp.last : null;
    // §5b: the drive's quarter (from its first play), elapsed clock (raw field
    // when captured, else the tail of the description), running score after the
    // drive, and a slim play list (text + clock) for the 9c All-view expansion.
    final period = field(field(first(dp), 'period'), 'number') ??
        field(field(field(d, 'start'), 'period'), 'number');
    final desc = field(d, 'description');
    final timeElapsed = or([
      field(field(d, 'timeElapsed'), 'displayValue'),
      desc is String
          ? RegExp(r'(\d{1,2}:\d{2})\s*$').firstMatch(desc)?.group(1)
          : null,
    ]);
    final plays = <Map<String, dynamic>>[];
    for (final p in dp) {
      final pl = pickT({
        'text': or([field(p, 'text'), field(p, 'shortText')]),
        'clock': field(field(p, 'clock'), 'displayValue'),
        'scoring': field(p, 'scoringPlay') == true ? true : null,
      }, ['text', 'clock', 'scoring']);
      if (truthy(pl['text'])) plays.add(pl);
    }
    final row = pickT({
      'side': side[tid],
      'teamAbbr': or([abbr[tid], field(field(d, 'team'), 'abbreviation')]),
      'description': desc,
      'result': or([field(d, 'displayResult'), field(d, 'shortDisplayResult'), field(d, 'result')]),
      'isScore': field(d, 'isScore') == true ? true : null,
      'yards': field(d, 'yards') is num ? field(d, 'yards') : null,
      'playCount': field(d, 'offensivePlays') is num ? field(d, 'offensivePlays') : null,
      'period': period is num ? period : null,
      'timeElapsed': timeElapsed,
      'awayScore': _numOrNull(field(last, 'awayScore')),
      'homeScore': _numOrNull(field(last, 'homeScore')),
      'plays': plays.isNotEmpty ? plays : null,
    }, ['side', 'teamAbbr', 'description', 'result', 'isScore', 'yards', 'playCount', 'period', 'timeElapsed', 'awayScore', 'homeScore', 'plays']);
    if (truthy(row['description']) || truthy(row['result'])) rows.add(row);
  }
  return rows.isNotEmpty ? rows : null;
}

// ---- full play-by-play ------------------------------------------------------
List<Map<String, dynamic>>? _buildPlays(Map raw, Map maps) {
  final side = maps['side'] as Map, abbr = maps['abbr'] as Map, athletes = maps['athletes'] as Map;
  List plays = raw['plays'] is List ? raw['plays'] as List : const [];
  if (plays.isEmpty) {
    final drives = _drivesList(raw);
    if (drives.isNotEmpty) {
      plays = drives.expand((d) => (field(d, 'plays') is List ? field(d, 'plays') as List : const []).map((p) => field(p, 'team') != null ? p : {...(p as Map), 'team': field(d, 'team')})).toList();
    }
  }
  if (plays.isEmpty) return _buildCommentaryPlays(raw, maps);
  final mapped = <Map<String, dynamic>>[];
  for (final p in plays) {
    final m = _mapPlay(p as Map, side, abbr, athletes);
    m['scoring'] = field(p, 'scoringPlay') == true;
    if (truthy(m['text'])) mapped.add(m);
  }
  if (mapped.length <= 1) return null;
  const cap = 800;
  return mapped.length > cap ? mapped.sublist(mapped.length - cap) : mapped;
}

// ---- baseball at-bats (the §3e all-plays disclosure layer) ------------------
// MLB ships the FULL play feed: per at-bat an 'A' header ("X pitches to Y"), the
// 'P' pitch rows, and a terminal 'N'/'S' batting result ('S' = scoring). Group
// them by atBatId so the app's All-plays view renders one condensed row per
// at-bat that expands to its pitch sequence (design 9e). Only built when pitch
// rows are present (summaryType 'P'); a scoring-only capture (college) keeps the
// flat scoring feed. When built, the noisy flat plays[] is suppressed upstream.
final _pitchPrefix = RegExp(r'^Pitch\s+\d+\s*:\s*', caseSensitive: false);
String _pitchResult(dynamic p) {
  // A contact pitch's `text` is 'Ball In Play' while its `type.text` is the
  // BATTED-BALL outcome ('Double', 'Fly Out') — so read 'in play' off the pitch
  // text first, then classify the rest off type.text (the pitch call).
  if (jsStr(field(p, 'text')).toLowerCase().contains('in play')) return 'inplay';
  final t = jsStr(or([field(field(p, 'type'), 'text'), field(p, 'text')])).toLowerCase();
  if (t.contains('foul')) return 'foul';
  if (t.contains('ball')) return 'ball';
  if (t.contains('strike')) return 'strike';
  return 'other';
}

List<Map<String, dynamic>>? _buildAtBats(Map raw, Map side, Map abbr, Map athletes) {
  final plays = raw['plays'] is List ? raw['plays'] as List : const [];
  if (!plays.any((p) => field(p, 'summaryType') == 'P')) return null; // no pitch data
  final order = <dynamic>[];
  final groups = <dynamic, List>{};
  for (final p in plays) {
    final id = field(p, 'atBatId');
    if (id == null) continue;
    (groups[id] ??= (() {
      order.add(id);
      return <dynamic>[];
    })())
        .add(p);
  }
  final out = <Map<String, dynamic>>[];
  for (final id in order) {
    final g = groups[id]!;
    final header = g.firstWhere((p) => field(p, 'summaryType') == 'A', orElse: () => null);
    final pitches = g.where((p) => field(p, 'summaryType') == 'P').toList();
    // Batting result = the last N/S row (S = scoring). 'C' rows are pitching-change
    // notes mid at-bat, not the batting outcome; 'I'/undefined are inning/junk.
    final results = g.where((p) => field(p, 'summaryType') == 'N' || field(p, 'summaryType') == 'S').toList();
    final term = results.isNotEmpty ? results.last : null;
    if (header == null && pitches.isEmpty && term == null) continue;
    final last = pitches.isNotEmpty ? pitches.last : null;
    // side/team = the BATTING team (header/result); pitch rows carry the pitcher's
    // team, so never anchor off a pitch for the side.
    final teamAnchor = term ?? header ?? last;
    final tid = jsStr(field(field(teamAnchor, 'team'), 'id') ?? '');
    final stateAnchor = term ?? last ?? header; // outs + running score come from here
    final live = term == null;
    // batter (live only — a finished row's text already leads with the last name):
    // the header's batter participant, resolved to a short name via the boxscore.
    final parts = field(header, 'participants') ?? field(teamAnchor, 'participants');
    final bpart = (parts is List)
        ? parts.firstWhere((x) => field(x, 'type') == 'batter', orElse: () => null)
        : null;
    final bpid = jsStr(field(field(bpart, 'athlete'), 'id') ?? '');
    final batter = live && bpid != '' ? athletes[bpid] : null;
    final termType = field(term, 'summaryType');
    out.add(pickT({
      'period': field(field(teamAnchor, 'period'), 'number'),
      'half': field(field(teamAnchor, 'period'), 'type') != null
          ? jsStr(field(field(teamAnchor, 'period'), 'type')).toLowerCase()
          : null,
      'side': or([side[tid], field(field(teamAnchor, 'team'), 'homeAway')]),
      'teamAbbr': or([abbr[tid], field(field(teamAnchor, 'team'), 'abbreviation')]),
      'batter': batter,
      'text': term != null ? or([field(term, 'text'), '']) : '',
      'scoring': term != null && termType == 'S' ? true : null,
      'outs': field(stateAnchor, 'outs') is num ? field(stateAnchor, 'outs') : null,
      'away': _numOrNull(field(stateAnchor, 'awayScore')),
      'home': _numOrNull(field(stateAnchor, 'homeScore')),
      'live': live ? true : null,
      'balls': live ? field(field(last, 'resultCount'), 'balls') : null,
      'strikes': live ? field(field(last, 'resultCount'), 'strikes') : null,
      'pitches': [
        for (final p in pitches)
          pickT({
            'r': _pitchResult(p),
            'text': jsStr(or([field(p, 'text'), ''])).replaceFirst(_pitchPrefix, ''),
            'velo': field(p, 'pitchVelocity') is num ? field(p, 'pitchVelocity') : null,
          }, ['r', 'text', 'velo']),
      ],
    }, ['period', 'half', 'side', 'teamAbbr', 'batter', 'text', 'scoring', 'outs', 'away', 'home', 'live', 'balls', 'strikes', 'pitches']));
  }
  return out.isNotEmpty ? out : null;
}

String? _halfLabel(dynamic n) => const {1: '1st Half', 2: '2nd Half', 3: 'Extra Time', 4: 'Extra Time', 5: 'Penalties'}[n];

List<Map<String, dynamic>>? _buildCommentaryPlays(Map raw, Map maps) {
  final nameSide = maps['nameSide'] as Map, haAbbr = maps['haAbbr'] as Map;
  final src = raw['commentary'];
  if (src is! List || src.isEmpty) return null;
  final sorted = List.from(src);
  sorted.sort((a, b) => (_numOrNull(field(a, 'sequence')) ?? 0).compareTo(_numOrNull(field(b, 'sequence')) ?? 0));
  final mapped = <Map<String, dynamic>>[];
  for (final c in sorted) {
    final p = field(c, 'play') ?? {};
    final side = nameSide[field(field(p, 'team'), 'displayName')];
    final m = pickT({
      'period': field(field(p, 'period'), 'number'),
      'periodLabel': or([field(field(p, 'period'), 'displayValue'), _halfLabel(field(field(p, 'period'), 'number'))]),
      'clock': or([field(field(c, 'time'), 'displayValue'), field(field(p, 'clock'), 'displayValue')]),
      'side': side,
      'teamAbbr': side != null ? haAbbr[side] : null,
      'text': or([field(c, 'text'), field(p, 'text'), '']),
      'away': _numOrNull(field(p, 'awayScore')),
      'home': _numOrNull(field(p, 'homeScore')),
      'type': field(field(p, 'type'), 'text'),
      'scoring': field(p, 'scoringPlay') == true,
    }, ['period', 'periodLabel', 'clock', 'side', 'teamAbbr', 'text', 'away', 'home', 'type', 'scoring']);
    if (truthy(m['text'])) mapped.add(m);
  }
  if (mapped.length <= 1) return null;
  const cap = 800;
  return mapped.length > cap ? mapped.sublist(mapped.length - cap) : mapped;
}

// ---- attendance + officials -------------------------------------------------
Map<String, dynamic> _buildGameInfo(Map raw) {
  final gi = raw['gameInfo'];
  if (gi == null || gi is! Map) return {};
  final out = <String, dynamic>{};
  if (field(gi, 'attendance') is num && (field(gi, 'attendance') as num) > 0) out['attendance'] = gi['attendance'];
  final officials = <Map<String, dynamic>>[];
  for (final o in (field(gi, 'officials') is List ? field(gi, 'officials') as List : const [])) {
    final row = pickT({'name': or([field(o, 'fullName'), field(o, 'displayName')]), 'role': or([field(field(o, 'position'), 'displayName'), field(field(o, 'position'), 'name')])}, ['name', 'role']);
    if (truthy(row['name'])) officials.add(row);
  }
  if (officials.isNotEmpty) out['officials'] = officials.length > 6 ? officials.sublist(0, 6) : officials;
  return out;
}

// ---- cricket scorecard ------------------------------------------------------
List<Map<String, dynamic>>? _buildCricketInnings(Map raw) {
  final cards = raw['matchcards'];
  if (cards is! List || cards.isEmpty) return null;
  final byInnings = <int, Map<String, dynamic>>{};
  Map<String, dynamic> slot(int n) => byInnings.putIfAbsent(n, () => {'innings': n, 'battingTeam': '', 'batting': [], 'bowling': []});
  for (final mc in cards) {
    final n = jsParseInt(field(mc, 'inningsNumber'));
    if (n == null) continue;
    final rows = field(mc, 'playerDetails') is List ? field(mc, 'playerDetails') as List : const [];
    final kind = jsStr(field(mc, 'headline')).toLowerCase();
    if (kind == 'batting') {
      final s = slot(n);
      if (truthy(field(mc, 'teamName'))) s['battingTeam'] = jsStr(field(mc, 'teamName'));
      final total = [field(mc, 'runs'), field(mc, 'total')].where((v) => v != null && v != '').join(' ');
      if (truthy(total)) s['total'] = total;
      if (truthy(field(mc, 'extras'))) s['extras'] = jsStr(field(mc, 'extras'));
      s['batting'] = rows.map((r) => pickT({'name': field(r, 'playerName'), 'dismissal': field(r, 'dismissal'), 'runs': field(r, 'runs'), 'balls': field(r, 'ballsFaced'), 'fours': field(r, 'fours'), 'sixes': field(r, 'sixes')}, ['name', 'dismissal', 'runs', 'balls', 'fours', 'sixes'])).where((r) => truthy(r['name'])).toList();
    } else if (kind == 'bowling') {
      final s = slot(n);
      if (truthy(field(mc, 'teamName'))) s['bowlingTeam'] = jsStr(field(mc, 'teamName'));
      s['bowling'] = rows.map((r) => pickT({'name': field(r, 'playerName'), 'overs': field(r, 'overs'), 'maidens': field(r, 'maidens'), 'runs': field(r, 'conceded'), 'wickets': field(r, 'wickets'), 'economy': field(r, 'economyRate')}, ['name', 'overs', 'maidens', 'runs', 'wickets', 'economy'])).where((r) => truthy(r['name'])).toList();
    }
  }
  final out = byInnings.values.where((s) => (s['batting'] as List).isNotEmpty || (s['bowling'] as List).isNotEmpty).toList();
  out.sort((a, b) => (a['innings'] as int).compareTo(b['innings'] as int));
  return out.isNotEmpty ? out : null;
}

// ---- top level --------------------------------------------------------------
Map<String, dynamic> normalizeSummary(Registry reg, String key, Map raw) {
  final profile = resolve(reg, key);
  final maps = _sideMaps(raw);
  final side = maps['side'] as Map, abbr = maps['abbr'] as Map, athletes = maps['athletes'] as Map;
  final header = raw['header'] ?? {};
  final comp0 = first(field(header, 'competitions')) ?? {};
  final status = field(field(comp0, 'status'), 'type') ?? {};
  final lineups = _buildLineups(raw, side);
  final periodLines = _buildPeriodLines(raw, profile);
  final boxGroups = _buildBoxGroups(raw, side);
  final out = <String, dynamic>{
    'eventId': jsStr(field(header, 'id') ?? raw['id'] ?? ''),
    'live': field(status, 'state') == 'in',
    'teamStats': _buildTeamStats(raw),
    'boxGroups': boxGroups.isNotEmpty ? boxGroups : _buildRosterBoxGroups(raw, side),
    'scoringPlays': _buildScoringPlays(raw, side, abbr, athletes),
    'lineups': lineups,
  };
  if (periodLines != null) out['periodLines'] = periodLines;
  final seasonSeries = _buildSeasonSeries(raw);
  if (seasonSeries != null) out['seasonSeries'] = seasonSeries;
  final recentForm = _buildRecentForm(raw, side);
  if (recentForm != null) out['recentForm'] = recentForm;
  final injuries = _buildInjuries(raw, side);
  if (injuries != null) out['injuries'] = injuries;
  final winProbability = _buildWinProbability(raw);
  if (winProbability != null) out['winProbability'] = winProbability;
  final timeline = buildMatchTimeline(raw, maps);
  if (timeline != null) out['timeline'] = timeline;
  // Baseball groups into at-bats (each with its pitch sequence) for the §3e
  // all-plays disclosure; when present it REPLACES the flat pitch-by-pitch plays[]
  // (which would be ~500 rows of noise) as the Plays tab's source.
  final atBats = _buildAtBats(raw, side, abbr, athletes);
  if (atBats != null) out['atBats'] = atBats;
  final plays = timeline != null || atBats != null ? null : _buildPlays(raw, maps);
  if (plays != null) out['plays'] = plays;
  final drives = _buildDrives(raw, side, abbr);
  if (drives != null) out['drives'] = drives;
  final cricketInnings = _buildCricketInnings(raw);
  if (cricketInnings != null) out['cricketInnings'] = cricketInnings;
  out.addAll(_buildGameInfo(raw));
  if (field(status, 'state') == 'pre' && field(comp0, 'date') != null) {
    final ms = DateTime.tryParse(jsStr(field(comp0, 'date')))?.millisecondsSinceEpoch;
    if (ms != null) out['nextStartMs'] = ms;
  }
  return out;
}

// ---- MMA card summary -------------------------------------------------------
Map<String, dynamic> normalizeMmaSummary(dynamic coreEvent, [Map statuses = const {}, Map linescores = const {}]) {
  final comps = field(coreEvent, 'competitions') is List ? field(coreEvent, 'competitions') as List : const [];
  final bouts = <Map<String, dynamic>>[];
  var anyLive = false;
  var allPre = comps.isNotEmpty;
  for (final c in comps) {
    final id = jsStr(field(c, 'id') ?? '');
    if (id == '') continue;
    final st = statuses[id];
    final state = field(field(st, 'type'), 'state');
    if (state == 'in') anyLive = true;
    if (state != 'pre') allPre = false;
    final r = field(st, 'result');
    if (r == null && state != 'post') continue;
    final bout = pickT({
      'id': id,
      'result': or([field(r, 'displayName'), field(r, 'name')]),
      'shortResult': field(r, 'shortDisplayName'),
      'round': (field(st, 'period') is num && (field(st, 'period') as num) > 0) ? field(st, 'period') : null,
      'clock': (field(st, 'displayClock') != null && field(st, 'displayClock') != '-') ? jsStr(field(st, 'displayClock')) : null,
    }, ['id', 'result', 'shortResult', 'round', 'clock']);
    final judges = <Map<String, dynamic>>[];
    for (final comp in (field(c, 'competitors') is List ? field(c, 'competitors') as List : const [])) {
      final ls = linescores['$id/${field(comp, 'id')}'];
      final item = first(field(ls, 'items'));
      if (item == null || field(item, 'linescores') is! List) continue;
      final lsList = List.from(field(item, 'linescores') as List);
      lsList.sort((a, b) => ((field(a, 'order') ?? 0) as num).compareTo((field(b, 'order') ?? 0) as num));
      final totals = lsList.map((l) => field(l, 'value')).whereType<num>().toList();
      if (totals.isEmpty) continue;
      final j = pickT({
        'competitorId': jsStr(field(comp, 'id') ?? ''),
        'total': field(item, 'value') is num ? field(item, 'value') : null,
        'totals': totals,
      }, ['competitorId', 'total', 'totals']);
      judges.add(j);
    }
    if (judges.isNotEmpty) bout['judges'] = judges;
    bouts.add(bout);
  }
  final out = <String, dynamic>{
    'eventId': jsStr(field(coreEvent, 'id') ?? ''),
    'live': anyLive,
    'teamStats': [], 'boxGroups': [], 'scoringPlays': [], 'lineups': [],
    'bouts': bouts,
  };
  if (!anyLive && allPre && field(coreEvent, 'date') != null) {
    final ms = DateTime.tryParse(jsStr(field(coreEvent, 'date')))?.millisecondsSinceEpoch;
    if (ms != null) out['nextStartMs'] = ms;
  }
  return out;
}
