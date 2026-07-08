// normalize.dart — Dart port of worker/src/normalize.js. Raw ESPN scoreboard →
// canonical ScoresResponse JSON map (schema/canonical.ts), fed straight into
// models.dart's ScoresResponse.fromJson. Behaviour is driven by the resolved
// league profile, so a new league is data (league-profiles.json), not code here.
//
// This is a faithful line-for-line port of the JS. Keep them in lock-step; the
// scores golden suite (test/port_scores_test.dart) asserts byte parity against
// the JS output for every committed fixture.

import 'profiles.dart';
import 'calendar.dart';
import 'util.dart';

// ---- normalize-local helpers (generic ones live in util.dart) ---------------
String _decodeEntities(dynamic s) => s is String
    ? s
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll(RegExp(r'&#0?39;|&apos;'), "'")
    : (s as String);

int _maxInt(Iterable<int> xs, int seed) {
  var m = seed;
  for (final x in xs) {
    if (x > m) m = x;
  }
  return m;
}

/// The `meta` sub-map, created lazily (JS `comp.meta ||= {}`).
Map<String, dynamic> _meta(Map comp) =>
    (comp['meta'] ??= <String, dynamic>{}) as Map<String, dynamic>;

// ---- dark logo --------------------------------------------------------------
String? _deriveDark(dynamic u) =>
    (u is String && u.contains('/i/teamlogos/') && u.contains('/500/'))
        ? u.replaceFirst('/500/', '/500-dark/')
        : null;

const _darkLogoSports = {'baseball', 'basketball', 'football', 'hockey'};

String? darkLogoOf(dynamic team, dynamic light, dynamic espnSport) {
  final ls = field(team, 'logos');
  if (ls is List) {
    Map? pickDark(bool Function(List rel) test) {
      for (final l in ls) {
        final rel = field(l, 'rel');
        if (rel is List && test(rel)) return l as Map;
      }
      return null;
    }

    final d = pickDark((rel) => rel.contains('dark') && !rel.contains('scoreboard')) ??
        pickDark((rel) => rel.contains('dark'));
    final href = field(d, 'href');
    if (href != null) return https(href);
  }
  return _darkLogoSports.contains(espnSport) ? _deriveDark(light) : null;
}

// ---- status -----------------------------------------------------------------
/// Branch on type.name, never on state alone (postponed can read state='post').
Map<String, dynamic> statusToPhase([dynamic t]) {
  final name = jsStr(field(t, 'name'));
  final state = field(t, 'state');
  final completed = field(t, 'completed') == true;
  if (RegExp('POSTPON').hasMatch(name)) return {'phase': 'postponed', 'live': false, 'ended': false};
  if (RegExp('CANCEL').hasMatch(name)) return {'phase': 'canceled', 'live': false, 'ended': false};
  if (RegExp('ABANDON').hasMatch(name)) return {'phase': 'abandoned', 'live': false, 'ended': false};
  if (RegExp('SUSPEND|RAIN|DELAY').hasMatch(name)) {
    return {'phase': state == 'in' ? 'live' : 'suspended', 'live': state == 'in', 'ended': false};
  }
  if (state == 'in') return {'phase': 'live', 'live': true, 'ended': false};
  if (state == 'post' || completed) return {'phase': 'final', 'live': false, 'ended': completed};
  if (state == 'pre') return {'phase': 'scheduled', 'live': false, 'ended': false};
  return {'phase': 'unknown', 'live': false, 'ended': false};
}

// ---- score (by scoreKind) ---------------------------------------------------
Map<String, dynamic> _buildScore(dynamic scoreKind, dynamic raw) {
  if (raw != null && raw is Map) raw = raw['displayValue'] ?? raw['value'] ?? '';
  final display = raw == null ? '' : raw.toString();
  final s = <String, dynamic>{'display': display};
  if (scoreKind == 'numeric') {
    final v = jsParseInt(raw);
    if (v != null) s['value'] = v;
  } else if (scoreKind == 'toPar') {
    if (display == 'E') {
      s['toPar'] = 0;
    } else {
      final v = jsParseInt(display.replaceAll('+', ''));
      if (v != null) s['toPar'] = v;
    }
  } else if (scoreKind == 'cricket') {
    final m = RegExp(r'^\s*(\d+)(?:\/(\d+))?').firstMatch(display);
    if (m != null) {
      final cricket = <String, dynamic>{'runs': int.parse(m.group(1)!)};
      if (m.group(2) != null) cricket['wickets'] = int.parse(m.group(2)!);
      s['cricket'] = cricket;
    }
    final ov = RegExp(r'([\d.]+)\s*(?:\/\s*\d+)?\s*ov', caseSensitive: false).firstMatch(display);
    if (ov != null && s['cricket'] != null) (s['cricket'] as Map)['overs'] = num.parse(ov.group(1)!);
    final t = RegExp(r'target\s+(\d+)', caseSensitive: false).firstMatch(display);
    if (t != null && s['cricket'] != null) (s['cricket'] as Map)['target'] = int.parse(t.group(1)!);
  }
  return s;
}

// ---- competitor -------------------------------------------------------------
Map<String, dynamic> _buildCompetitor(Map profile, Map raw) {
  final kind = profile['competitorKind'] ?? 'team';
  final c = <String, dynamic>{
    'kind': kind,
    'id': jsStr(raw['id'] ?? field(raw['team'], 'id') ?? field(raw['athlete'], 'id') ?? ''),
    'displayName': '',
  };
  final team = raw['team'];
  final espnSport = profile['espnSport'];

  if (kind == 'team' && team is Map) {
    c['displayName'] = or([team['displayName'], team['name'], team['shortDisplayName'], '']);
    if (truthy(team['shortDisplayName'])) c['shortName'] = team['shortDisplayName'];
    if (truthy(team['abbreviation'])) c['abbreviation'] = team['abbreviation'];
    final logo = https(or([team['logo'], field(first(team['logos']), 'href')]));
    if (logo != null) {
      c['logo'] = logo;
      final d = darkLogoOf(team, logo, espnSport);
      if (d != null) c['logoDark'] = d;
    }
    if (truthy(team['color'])) c['color'] = team['color'];
    if (truthy(team['alternateColor'])) c['altColor'] = team['alternateColor'];
  } else {
    List list;
    if (raw['athlete'] != null) {
      list = [raw['athlete']];
    } else {
      final rosterAths = field(raw['roster'], 'athletes');
      if (rosterAths is List) {
        list = rosterAths.map((a) => field(a, 'athlete') ?? a).toList();
      } else if (raw['athletes'] is List) {
        list = raw['athletes'] as List;
      } else {
        list = const [];
      }
    }
    c['athletes'] = list.map((a) {
      final o = <String, dynamic>{
        'id': jsStr(or([field(a, 'id'), ''])),
        'name': or([field(a, 'displayName'), field(a, 'fullName'), field(a, 'shortName'), '']),
      };
      if (truthy(field(a, 'jersey'))) o['jersey'] = field(a, 'jersey');
      final country = or([field(field(a, 'flag'), 'alt'), field(a, 'citizenship')]);
      if (truthy(country)) o['country'] = country;
      final hs = https(or([field(field(a, 'headshot'), 'href'), field(a, 'headshot')]));
      if (hs != null) o['headshot'] = hs;
      final pos = field(field(a, 'position'), 'abbreviation');
      if (truthy(pos)) o['position'] = pos;
      return o;
    }).toList();
    final athletes = c['athletes'] as List;
    final joined = athletes.map((a) => a['name']).where((n) => truthy(n)).join(' / ');
    c['displayName'] = or([
      field(raw['roster'], 'displayName'),
      joined,
      field(raw['athlete'], 'displayName'),
      field(team, 'displayName'),
      field(team, 'shortDisplayName'),
      field(team, 'name'),
      '',
    ]);
    if (athletes.length == 2 && raw['roster'] != null) c['kind'] = 'pair';
    if (athletes.length == 1 && !truthy(athletes[0]['id']) && truthy(c['id'])) {
      athletes[0]['id'] = c['id'];
    }
    if (truthy(field(team, 'abbreviation'))) c['abbreviation'] = field(team, 'abbreviation');
    if (athletes.isEmpty && truthy(field(team, 'shortDisplayName'))) c['shortName'] = field(team, 'shortDisplayName');
    if (athletes.isEmpty && truthy(field(team, 'color'))) c['color'] = field(team, 'color');
    final logo = https(field(team, 'logo'));
    if (logo != null) {
      c['logo'] = logo;
      final d = darkLogoOf(team, logo, espnSport);
      if (d != null) c['logoDark'] = d;
    }
  }

  if (truthy(raw['homeAway'])) c['homeAway'] = raw['homeAway'];
  if (raw['possession'] == true) c['serving'] = true;
  if (raw['order'] != null) c['order'] = raw['order'];
  if (raw['startOrder'] != null) c['startOrder'] = raw['startOrder'];
  final cr = field(raw['curatedRank'], 'current');
  if (cr != null) c['rank'] = cr == 99 ? null : cr;
  if (raw['winner'] != null) c['winner'] = raw['winner'];
  if (raw['score'] != null) c['score'] = _buildScore(profile['scoreKind'], raw['score']);

  final linescores = raw['linescores'];
  if (linescores is List && linescores.isNotEmpty) {
    final ignore = profile['ignorePeriods'];
    final maxRound = profile['periodUnit'] == 'hole_rounds' ? (profile['regulationPeriods'] ?? 0) : 0;
    final ps = <Map<String, dynamic>>[];
    for (var i = 0; i < linescores.length; i++) {
      final ls = linescores[i];
      final period = (ls is Map && ls['period'] != null) ? ls['period'] : i + 1;
      if (ls == null || ls is! Map) continue;
      final hasVal = ls['value'] != null || ls['displayValue'] != null || ls['runs'] != null;
      if (!hasVal) continue;
      if (ignore is List && ignore.contains(period)) continue;
      if (maxRound != 0 && (period as num) > (maxRound as num)) continue;
      final p = <String, dynamic>{
        'period': period,
        'value': ls['value'],
        'display': ls['displayValue'] ?? jsStr(ls['value'] ?? ''),
      };
      if (ls['tiebreak'] != null) p['tiebreak'] = ls['tiebreak'];
      if (ls['winner'] != null) p['setWinner'] = ls['winner'];
      if (ls['linescores'] is List) p['holesPlayed'] = (ls['linescores'] as List).length;
      if (ls['runs'] != null || ls['wickets'] != null) {
        // JS `{runs: ls.runs, wickets: ls.wickets}` — an absent key is undefined
        // (omitted), an explicit null is kept; containsKey replicates that.
        final cricket = <String, dynamic>{};
        if (ls.containsKey('runs')) cricket['runs'] = ls['runs'];
        if (ls.containsKey('wickets')) cricket['wickets'] = ls['wickets'];
        if (ls['overs'] != null) cricket['overs'] = ls['overs'];
        if (ls['isBatting'] != null) cricket['isBatting'] = ls['isBatting'];
        if (ls['target'] != null) cricket['target'] = ls['target'];
        if (truthy(ls['description'])) cricket['reason'] = ls['description'];
        p['cricket'] = cricket;
      }
      ps.add(p);
    }
    c['periodScores'] = ps;
  }

  if (profile['scoreKind'] == 'toPar' &&
      c['score'] != null &&
      c['periodScores'] is List &&
      (c['periodScores'] as List).isNotEmpty) {
    final psList = c['periodScores'] as List;
    int sumOf(bool Function(Map p) pred) {
      var s = 0;
      for (final p in psList) {
        if (pred(p as Map) && p['value'] is num) s += (p['value'] as num).toInt();
      }
      return s;
    }

    final anyHoleData = psList.any((p) => (p as Map)['holesPlayed'] != null);
    final strokes = anyHoleData ? sumOf((p) => p['holesPlayed'] == 18) : sumOf((_) => true);
    if (strokes > 0 && (c['score'] as Map)['strokes'] == null) (c['score'] as Map)['strokes'] = strokes;
  }
  if (raw['records'] is List && (raw['records'] as List).isNotEmpty) {
    c['records'] = (raw['records'] as List)
        .map((r) => {'type': or([field(r, 'type'), field(r, 'name'), 'total']), 'summary': field(r, 'summary')})
        .toList();
  }
  if (raw['shootoutScore'] != null) c['shootoutScore'] = raw['shootoutScore'];
  if (raw['aggregateScore'] != null) c['aggregateScore'] = jsStr(raw['aggregateScore']);
  if (raw['advance'] != null) c['advance'] = raw['advance'];
  if (raw['amateur'] != null) c['amateur'] = raw['amateur'];
  if (raw['vehicle'] != null) {
    c['vehicle'] = pickNN(raw['vehicle'] as Map, ['number', 'manufacturer', 'team', 'owner', 'sponsor']);
  }

  // ---- cheap-tier context ----
  if (raw['hits'] != null) {
    final n = jsParseInt(raw['hits']);
    if (n != null) c['hits'] = n;
  }
  if (raw['errors'] != null) {
    final n = jsParseInt(raw['errors']);
    if (n != null) c['errors'] = n;
  }
  if (truthy(raw['form'])) c['form'] = jsStr(raw['form']);
  if (raw['statistics'] is List && (raw['statistics'] as List).isNotEmpty) {
    final stats = <String, dynamic>{};
    for (final s in raw['statistics'] as List) {
      final v = field(s, 'displayValue') ?? field(s, 'value');
      if (v == null) continue;
      final abbr = field(s, 'abbreviation');
      final name = field(s, 'name');
      if (abbr != null && stats[abbr] == null) stats[abbr] = v;
      if (name != null && stats[name] == null) stats[name] = v;
    }
    if (stats.isNotEmpty) c['stats'] = stats;
  }
  if (raw['leaders'] is List && (raw['leaders'] as List).isNotEmpty) {
    final leaders = (raw['leaders'] as List)
        .map((g) {
          final top = first(field(g, 'leaders'));
          final ath = field(top, 'athlete');
          return pickNN({
            'name': or([field(g, 'name'), field(g, 'shortDisplayName'), field(g, 'abbreviation'), '']),
            'label': or([field(g, 'shortDisplayName'), field(g, 'abbreviation'), field(g, 'displayName'), field(g, 'name'), '']),
            'display': field(top, 'displayValue'),
            'athlete': ath != null ? or([field(ath, 'shortName'), field(ath, 'displayName'), field(ath, 'fullName')]) : null,
          }, ['name', 'label', 'display', 'athlete']);
        })
        .where((l) => truthy(l['display']) || truthy(l['athlete']))
        .toList();
    if (leaders.isNotEmpty) c['leaders'] = leaders;
  }
  if (raw['probables'] is List && (raw['probables'] as List).isNotEmpty) {
    final probables = (raw['probables'] as List)
        .map((pr) {
          final ath = field(pr, 'athlete');
          final rec = field(pr, 'record');
          return pickNN({
            'role': or([field(pr, 'shortDisplayName'), field(pr, 'displayName'), field(pr, 'name'), '']),
            'athlete': ath != null
                ? or([field(ath, 'shortName'), field(ath, 'displayName'), field(ath, 'fullName')])
                : (pr is String ? pr : null),
            'record': (rec is String && rec.trim().isNotEmpty) ? rec : null,
            'confirmed': field(field(pr, 'status'), 'type') == 'confirmed' ? true : null,
          }, ['role', 'athlete', 'record', 'confirmed']);
        })
        .where((p) => p['athlete'] != null)
        .toList();
    if (probables.isNotEmpty) c['probables'] = probables;
  }
  return c;
}

// ---- broadcast (cheap TV/stream label) --------------------------------------
// Port of normalize.js buildBroadcast: competitions[].broadcast (often ''), else
// the national geoBroadcasts[].media.shortName, else any geoBroadcast.
String? _buildBroadcast(Map rc) {
  final b = rc['broadcast'] is String ? (rc['broadcast'] as String).trim() : '';
  if (b.isNotEmpty) return b;
  final geos = rc['geoBroadcasts'] is List ? rc['geoBroadcasts'] as List : const [];
  String short(dynamic g) {
    final s = field(field(g, 'media'), 'shortName');
    return s is String ? s.trim() : '';
  }

  dynamic nat;
  for (final g in geos) {
    if (field(field(g, 'market'), 'type') == 'National' && short(g).isNotEmpty) {
      nat = g;
      break;
    }
  }
  if (nat == null) {
    for (final g in geos) {
      if (short(g).isNotEmpty) {
        nat = g;
        break;
      }
    }
  }
  return nat == null ? null : short(nat);
}

// ---- odds (pre-game betting line) -------------------------------------------
// Port of normalize.js buildOdds/oddsFromList/normalizeCompetitionOdds. One shape
// from BOTH the inline scoreboard odds[] and a core competition-odds items[]
// element (the core one adds the per-team moneyline). Only served keys are kept.
Map<String, dynamic>? _buildOdds(dynamic o) {
  if (o is! Map) return null;
  num? n(dynamic v) => v is num ? v : null;
  final details = field(o, 'details');
  final provider = field(field(o, 'provider'), 'name');
  final out = pickNN({
    'details':
        details is String && details.trim().isNotEmpty ? details.trim() : null,
    'spread': n(field(o, 'spread')),
    'overUnder': n(field(o, 'overUnder')),
    'homeMoneyline': n(field(field(o, 'homeTeamOdds'), 'moneyLine')),
    'awayMoneyline': n(field(field(o, 'awayTeamOdds'), 'moneyLine')),
    'drawMoneyline': n(field(field(o, 'drawOdds'), 'moneyLine')),
    'provider': provider is String && provider.isNotEmpty ? provider : null,
  }, [
    'details',
    'spread',
    'overUnder',
    'homeMoneyline',
    'awayMoneyline',
    'drawMoneyline',
    'provider',
  ]);
  return out.keys.any((k) => k != 'provider') ? out : null;
}

// Highest-priority usable line from a list (inline odds[] or core items[]).
Map<String, dynamic>? _oddsFromList(dynamic items) {
  if (items is! List) return null;
  Map<String, dynamic>? best;
  num bestPrio = double.negativeInfinity;
  for (final it in items) {
    final o = _buildOdds(it);
    if (o == null) continue;
    final prio = field(field(it, 'provider'), 'priority');
    final p = prio is num ? prio : 0;
    if (p > bestPrio) {
      best = o;
      bestPrio = p;
    }
  }
  return best;
}

/// The core competition-odds resource (`.../competitions/{id}/odds`) → canonical
/// Odds map (or null). Lazy detail-open enrichment; pure. Port of normalize.js.
Map<String, dynamic>? normalizeCompetitionOdds(dynamic raw) =>
    _oddsFromList(field(raw, 'items'));

// ---- live situation ---------------------------------------------------------
Map<String, dynamic>? _buildSituation(Map rc) {
  final sit = rc['situation'];
  if (sit == null || sit is! Map) return null;
  final s = <String, dynamic>{};
  for (final k in ['balls', 'strikes', 'outs', 'down', 'distance', 'homeTimeouts', 'awayTimeouts']) {
    final v = sit[k];
    final n = v is num ? v : (v is String && RegExp(r'^\d+$').hasMatch(v) ? int.parse(v) : null);
    if (n != null) s[k] = n;
  }
  for (final k in ['onFirst', 'onSecond', 'onThird', 'isRedZone', 'powerPlay', 'emptyNet']) {
    if (sit[k] != null) s[k] = sit[k] == true;
  }
  final p = field(sit['pitcher'], 'athlete');
  if (p != null) s['pitcher'] = or([field(p, 'shortName'), field(p, 'displayName'), field(p, 'fullName')]);
  final b = field(sit['batter'], 'athlete');
  if (b != null) s['batter'] = or([field(b, 'shortName'), field(b, 'displayName'), field(b, 'fullName')]);
  if (field(sit['pitcher'], 'summary') != null) s['pitcherLine'] = field(sit['pitcher'], 'summary');
  if (field(sit['batter'], 'summary') != null) s['batterLine'] = field(sit['batter'], 'summary');
  if (sit['downDistanceText'] != null) s['downDistanceText'] = sit['downDistanceText'];
  if (sit['possession'] != null) s['possession'] = jsStr(sit['possession']);
  final lp = sit['lastPlay'];
  final lpText = lp != null ? (field(field(lp, 'type'), 'alternativeText') ?? field(lp, 'text') ?? field(field(lp, 'type'), 'text')) : null;
  if (lpText != null) s['lastPlay'] = lpText;
  // CHEAP win probability — basketball scoreboard only (~14%; scoreboard.md).
  // HOME win % as a 0-100 rounded int; absent for every other sport.
  final hwp = field(field(lp, 'probability'), 'homeWinPercentage');
  if (hwp is num) s['homeWinPct'] = (hwp * 100).round();
  final strength = field(field(lp, 'strength'), 'abbreviation') ?? field(field(lp, 'strength'), 'type');
  if (strength != null) s['strength'] = jsStr(strength).toLowerCase();
  final strengthTeam = field(field(lp, 'team'), 'id') ?? field(lp, 'team');
  if (strengthTeam != null && (s['strength'] != null || s['powerPlay'] != null)) s['strengthTeam'] = jsStr(strengthTeam);
  if (rc['outsText'] != null) s['outsText'] = rc['outsText'];
  return s.isNotEmpty ? s : null;
}

const _otUnits = {'half', 'quarter', 'period', 'inning', 'over_innings'};

// ---- decision ---------------------------------------------------------------
String? _decide(Map profile, Map comp) {
  if (field(comp['status'], 'phase') != 'final') return null;
  final cs = comp['competitors'] as List;
  if (cs.any((c) => (c as Map)['shootoutScore'] != null)) return 'shootout';
  if (cs.any((c) => (c as Map)['aggregateScore'] != null)) return 'aggregate';
  final isDraw = profile['layout'] == 'headToHead' && cs.length == 2 && cs.every((c) => (c as Map)['winner'] == false);
  if (profile['scoreKind'] == 'none') {
    if (isDraw) return 'draw';
    return profile['espnSport'] == 'mma' ? 'method' : 'regulation';
  }
  if (field(comp['periods'], 'isOvertime') == true && profile['periodUnit'] != 'inning') return 'overtime';
  if (isDraw) return 'draw';
  return 'regulation';
}

// per-family touch-ups
void _decorate(Map profile, Map comp, Map rc) {
  final sport = profile['espnSport'];
  if (sport == 'cricket') {
    final m = _meta(comp);
    final gcc = field(field(rc, 'class'), 'generalClassCard');
    if (gcc != null) m['cricketClass'] = gcc;
    final summary = or([field(rc['status'], 'summary'), field(field(rc['status'], 'type'), 'summary')]);
    if (truthy(summary)) m['cricketSummary'] = _decodeEntities(summary);
  } else if (sport == 'mma') {
    final r = field(rc['status'], 'result');
    if (r != null) {
      comp['method'] = pickNN({
        'kind': or([field(r, 'displayName'), field(r, 'shortDisplayName')]),
        'detail': field(r, 'description'),
        'target': field(field(r, 'target'), 'name'),
        'finishRound': field(comp['status'], 'period'),
        'finishTime': field(comp['status'], 'detail'),
      }, ['kind', 'detail', 'target', 'finishRound', 'finishTime']);
    } else if (field(comp['status'], 'phase') == 'final') {
      final details = rc['details'];
      var det = '';
      if (details is List) {
        for (final d in details) {
          final t = or([(field(d, 'type') is String ? field(d, 'type') : field(field(d, 'type'), 'text')), field(d, 'text'), '']);
          if (RegExp('unofficial winner', caseSensitive: false).hasMatch(t.toString())) {
            det = t.toString();
            break;
          }
        }
      }
      final mm = RegExp(r'unofficial winner\s+(.+)$', caseSensitive: false).firstMatch(det);
      if (mm != null) {
        var kind = mm.group(1)!.trim();
        if (RegExp(r'^kotko$', caseSensitive: false).hasMatch(kind)) kind = 'KO/TKO';
        final decision = RegExp('decision', caseSensitive: false).hasMatch(kind);
        final clock = field(rc['status'], 'displayClock');
        comp['method'] = pickNN({
          'kind': kind,
          'finishRound': decision ? null : field(comp['status'], 'period'),
          'finishTime': (decision || clock == null || clock == '-' || clock == '0:00') ? null : clock,
        }, ['kind', 'finishRound', 'finishTime']);
      }
    }
    if (truthy(field(rc['cardSegment'], 'description'))) _meta(comp)['cardSegment'] = field(rc['cardSegment'], 'description');
    if (truthy(field(rc['status'], 'featured'))) _meta(comp)['featured'] = true;
  } else if (sport == 'racing') {
    if (field(rc['status'], 'flag') != null) _meta(comp)['flag'] = field(rc['status'], 'flag');
  }
}

// ---- scoring timeline -------------------------------------------------------
const _scoringTimelineSports = {'soccer', 'rugby', 'rugby-league'};

String _scoringEventType(Map d, bool isSoccer) {
  if (d['ownGoal'] == true) return 'own-goal';
  if (d['penaltyKick'] == true) return d['scoringPlay'] == true ? 'penalty-goal' : 'penalty-missed';
  if (d['redCard'] == true) return 'red-card';
  if (d['yellowCard'] == true) return 'yellow-card';
  if (d['scoringPlay'] == true) return isSoccer ? 'goal' : 'score';
  return 'other';
}

List<Map<String, dynamic>>? _buildScoringEvents(Map profile, Map rc, List competitors) {
  final details = rc['details'];
  if (details is! List || details.isEmpty) return null;
  String? sideOf(dynamic id) {
    for (final c in competitors) {
      if ((c as Map)['id'] == jsStr(id)) return c['homeAway'];
    }
    return null;
  }

  final isSoccer = profile['espnSport'] == 'soccer';
  final out = <Map<String, dynamic>>[];
  for (final d in details) {
    if (d == null || d is! Map) continue;
    final type = _scoringEventType(d, isSoccer);
    if (type == 'other') continue;
    final ath = first(d['athletesInvolved']);
    final e = pickNN({
      'type': type,
      'team': sideOf(field(d['team'], 'id')),
      'clock': field(d['clock'], 'displayValue'),
      'period': d['period'] is num ? d['period'] : null,
      'athlete': ath != null ? or([field(ath, 'shortName'), field(ath, 'displayName'), field(ath, 'fullName')]) : null,
      'detail': field(d['type'], 'text'),
      'scoreValue': d['scoreValue'] is num ? d['scoreValue'] : null,
    }, ['type', 'team', 'clock', 'period', 'athlete', 'detail', 'scoreValue']);
    final flags = pickNN({
      'ownGoal': d['ownGoal'] == true ? true : null,
      'penalty': d['penaltyKick'] == true ? true : null,
      'redCard': d['redCard'] == true ? true : null,
    }, ['ownGoal', 'penalty', 'redCard']);
    if (flags.isNotEmpty) e['flags'] = flags;
    out.add(e);
  }
  return out.isNotEmpty ? out : null;
}

// ---- competition ------------------------------------------------------------
Map<String, dynamic> _buildCompetition(Map profile, Map rc, Map rawEvent) {
  final st = rc['status'] ?? rawEvent['status'] ?? {};
  final type = field(st, 'type') ?? {};
  final ph = statusToPhase(type);
  final competitors = (rc['competitors'] is List ? rc['competitors'] as List : const [])
      .map((x) => _buildCompetitor(profile, x as Map))
      .toList();
  if (profile['layout'] == 'field') {
    competitors.sort((a, b) => ((a['order'] ?? 1e9) as num).compareTo((b['order'] ?? 1e9) as num));
  }

  final regCount = (profile['regulationPeriods'] ?? 0) as num;
  final stPeriod = field(st, 'period') is num ? field(st, 'period') as num : 0;
  final clampedStPeriod = (profile['periodUnit'] == 'hole_rounds' && regCount != 0 && stPeriod > regCount) ? regCount : stPeriod;
  final played = _maxInt(
    competitors.map((c) {
      final ps = c['periodScores'];
      if (ps is List && ps.isNotEmpty) {
        return _maxInt(ps.map((p) => ((p as Map)['period'] as num).toInt()), 0);
      }
      return 0;
    }),
    clampedStPeriod.toInt(),
  );
  final comp = <String, dynamic>{
    'id': jsStr(rc['id'] ?? rawEvent['id']),
    'layout': profile['layout'],
    'scoreKind': profile['scoreKind'],
    'competitorKind': profile['competitorKind'],
    'status': <String, dynamic>{
      'phase': ph['phase'],
      'live': ph['live'],
      'ended': ph['ended'],
      'period': clampedStPeriod,
      'periodLabel': or([field(type, 'shortDetail'), field(type, 'detail'), field(type, 'description'), '']),
      'espnName': or([field(type, 'name'), '']),
      'detail': or([field(type, 'detail'), '']),
    },
    'periods': <String, dynamic>{
      'unit': profile['periodUnit'],
      'regulation': regCount,
      'played': played,
      'isOvertime': _otUnits.contains(profile['periodUnit']) && regCount > 0 && played > regCount,
      if (profile['periodLengthMin'] != null) 'lengthMin': profile['periodLengthMin'],
    },
    'decision': null,
    'competitors': competitors,
  };
  final sport = profile['espnSport'];
  if (sport == 'racing' && (truthy(field(rc['type'], 'abbreviation')) || truthy(field(rc['type'], 'text')))) {
    comp['label'] = or([field(rc['type'], 'abbreviation'), field(rc['type'], 'text')]);
  } else if (sport == 'mma' && truthy(field(rc['type'], 'abbreviation'))) {
    comp['label'] = field(rc['type'], 'abbreviation');
  }
  final status = comp['status'] as Map<String, dynamic>;
  if (field(type, 'shortDetail') != null) status['shortDetail'] = field(type, 'shortDetail');
  if (field(type, 'altDetail') != null) status['altDetail'] = field(type, 'altDetail');
  if (ph['live'] == true && field(st, 'displayClock') != null && field(st, 'displayClock') != '0:00') {
    status['clock'] = field(st, 'displayClock');
  }

  final notesHead = (rc['notes'] is List ? rc['notes'] as List : const [])
      .map((n) => field(n, 'headline'))
      .where((h) => h != null && h != '')
      .toList();
  if (notesHead.isNotEmpty) {
    _meta(comp)['round'] = notesHead[0];
  } else if (field(rc['round'], 'displayName') != null) {
    _meta(comp)['round'] = field(rc['round'], 'displayName');
  }
  final golfPlayoff = profile['periodUnit'] == 'hole_rounds' &&
      regCount != 0 &&
      (rc['competitors'] is List) &&
      (rc['competitors'] as List).any((x) {
        final ls = field(x, 'linescores');
        return ls is List && ls.any((l) => ((field(l, 'period') ?? 0) as num) > regCount);
      });
  if (field(rc['status'], 'hadPlayoff') == true || golfPlayoff) _meta(comp)['hadPlayoff'] = true;
  if (truthy(field(rc['series'], 'summary'))) _meta(comp)['seriesSummary'] = field(rc['series'], 'summary');
  final sr = rc['series'];
  if (sr is Map &&
      sr['competitors'] is List &&
      (sr['competitors'] as List).isNotEmpty &&
      (sr['type'] == 'playoff' || (sr['totalCompetitions'] is num && (sr['totalCompetitions'] as num) > 1))) {
    _meta(comp)['series'] = pickNN({
      'type': sr['type'],
      'total': sr['totalCompetitions'] is num ? sr['totalCompetitions'] : null,
      'completed': sr['completed'] is bool ? sr['completed'] : null,
      'competitors': (sr['competitors'] as List)
          .map((s) => {'id': jsStr(field(s, 'id') ?? ''), 'wins': (field(s, 'wins') is num ? (field(s, 'wins') as num).toInt() : 0)})
          .toList(),
    }, ['type', 'total', 'completed', 'competitors']);
  }

  if (_scoringTimelineSports.contains(sport)) {
    final evs = _buildScoringEvents(profile, rc, competitors);
    if (evs != null) comp['events'] = evs;
  }

  if (rc['attendance'] is num && (rc['attendance'] as num) > 0) comp['attendance'] = rc['attendance'];
  if (rc['conferenceCompetition'] == true) comp['conferenceGame'] = true;
  if (rc['wasSuspended'] == true) comp['wasSuspended'] = true;
  final hl = rc['headlines'] is List && (rc['headlines'] as List).isNotEmpty ? (rc['headlines'] as List)[0] : null;
  final hlText = hl != null ? (field(hl, 'shortLinkText') ?? field(hl, 'description')) : null;
  if (hlText != null) comp['headline'] = _decodeEntities(jsStr(hlText));
  final broadcast = _buildBroadcast(rc);
  if (broadcast != null) comp['broadcast'] = broadcast;
  final odds = _oddsFromList(rc['odds']);
  if (odds != null) comp['odds'] = odds;

  final situation = _buildSituation(rc);
  if (situation != null) comp['situation'] = situation;

  comp['decision'] = _decide(profile, comp);
  _decorate(profile, comp, rc);
  if (comp['meta'] != null) comp['decision'] = _decide(profile, comp) ?? comp['decision'];
  return comp;
}

// ---- event ------------------------------------------------------------------
Map<String, dynamic>? _buildVenue(dynamic v) {
  if (v == null) return null;
  final id = field(v, 'id');
  final out = pickNN({
    'id': id != null ? jsStr(id) : null,
    'name': field(v, 'fullName'),
    'city': field(field(v, 'address'), 'city'),
    'country': field(field(v, 'address'), 'country'),
    'indoor': field(v, 'indoor'),
  }, ['id', 'name', 'city', 'country', 'indoor']);
  return out;
}

// racing circuit join — events[].circuit → {id, fullName, city?, country?}.
// Emitted alongside the venue fold (buildEvent still folds circuit into the venue
// name/address); port of normalize.js buildCircuit. Null when absent.
Map<String, dynamic>? _buildCircuit(dynamic cir) {
  if (cir is! Map) return null;
  final id = cir['id'];
  final out = pickNN({
    'id': id != null ? jsStr(id) : null,
    'fullName': field(cir, 'fullName'),
    'city': field(field(cir, 'address'), 'city'),
    'country': field(field(cir, 'address'), 'country'),
  }, ['id', 'fullName', 'city', 'country']);
  return out.isNotEmpty ? out : null;
}

String? _weekLabelOf(Map profile, Map e) {
  final wk = field(e['week'], 'number');
  if (wk is! num) return null;
  final sp = profile['espnSport'];
  if (sp != 'football' && sp != 'rugby' && sp != 'rugby-league') return null;
  final slug = jsStr(field(e['season'], 'slug')).toLowerCase();
  final isReg = field(e['season'], 'type') == 2 || RegExp('reg').hasMatch(slug);
  final isPost = field(e['season'], 'type') == 3 || RegExp('post|playoff|bowl|final').hasMatch(slug);
  if (!isReg || isPost) return null;
  return '${sp == 'football' ? 'Week' : 'Round'} $wk';
}

Map<String, dynamic>? _buildWeather(Map e, Map? venue) {
  final w = e['weather'];
  if (w == null || w is! Map || (venue != null && venue['indoor'] == true)) return null;
  final out = pickNN({
    'temperature': w['temperature'] is num ? w['temperature'] : null,
    'condition': w['conditionId'],
  }, ['temperature', 'condition']);
  return out.isNotEmpty ? out : null;
}

Map<String, dynamic> buildEvent(Map profile, Map e) {
  final rawComps = (e['competitions'] is List && (e['competitions'] as List).isNotEmpty)
      ? e['competitions'] as List
      : (e['groupings'] is List ? (e['groupings'] as List).expand((g) => field(g, 'competitions') is List ? field(g, 'competitions') as List : const []).toList() : const []);
  final c0 = rawComps.isNotEmpty ? rawComps[0] as Map : null;
  final links = <String, dynamic>{};
  final eLinks = e['links'];
  String? findLink(bool Function(List rel) test) {
    if (eLinks is! List) return null;
    for (final l in eLinks) {
      final rel = field(l, 'rel');
      if (rel is List && test(rel)) return https(field(l, 'href'));
    }
    return null;
  }

  final web = findLink((rel) => rel.contains('summary') || rel.contains('desktop'));
  final box = findLink((rel) => rel.contains('boxscore'));
  if (web != null) links['web'] = web;
  if (box != null) links['box'] = box;
  final circuit = e['circuit'];
  final venue = _buildVenue(field(c0, 'venue') ??
      e['venue'] ??
      (circuit is Map ? {'fullName': circuit['fullName'], 'address': circuit['address']} : null));
  final circuitObj = _buildCircuit(circuit);
  final weekLabel = _weekLabelOf(profile, e);
  final weather = _buildWeather(e, venue);
  final broadcasts = <dynamic>{};
  for (final b in (field(c0, 'broadcasts') is List ? field(c0, 'broadcasts') as List : const [])) {
    final names = field(b, 'names');
    if (names is List) broadcasts.addAll(names);
  }
  return {
    'id': jsStr(e['id']),
    'name': or([e['name'], '']),
    'shortName': or([e['shortName'], '']),
    'start': e['date'],
    'neutralSite': field(c0, 'neutralSite') == true,
    if (venue != null) 'venue': venue,
    if (circuitObj != null) 'circuit': circuitObj,
    'broadcasts': broadcasts.toList(),
    'notes': (field(c0, 'notes') is List ? field(c0, 'notes') as List : const [])
        .map((n) => field(n, 'headline'))
        .where((h) => h != null && h != '')
        .toList(),
    if (weekLabel != null) 'weekLabel': weekLabel,
    if (weather != null) 'weather': weather,
    'links': links,
    'competitions': rawComps.map((c) => _buildCompetition(profile, c as Map, e)).toList(),
  };
}

/// Soonest kickoff (epoch ms) among scheduled events, or null when none.
int? nextScheduledStart(List events) {
  int? min;
  for (final ev in events) {
    final comps = (ev as Map)['competitions'] as List;
    if (ev['start'] == null || !comps.any((c) => field((c as Map)['status'], 'phase') == 'scheduled')) continue;
    final ms = DateTime.tryParse(ev['start'].toString())?.millisecondsSinceEpoch;
    if (ms == null) continue;
    if (min == null || ms < min) min = ms;
  }
  return min;
}

// ---- golf tournament meta ---------------------------------------------------
Map<String, dynamic>? golfMetaFromTournament(dynamic t) {
  if (t == null || t is! Map || t['numberOfRounds'] is! num) return null;
  final m = <String, dynamic>{'numberOfRounds': t['numberOfRounds']};
  if (t['currentRound'] is num) m['currentRound'] = t['currentRound'];
  if (t['cutRound'] is num) m['cutRound'] = t['cutRound'];
  if (t['cutScore'] is num) m['cutScore'] = t['cutScore'];
  if (t['cutCount'] is num) m['cutCount'] = t['cutCount'];
  if (t['major'] is bool) m['major'] = t['major'];
  final ss = field(t['scoringSystem'], 'name');
  if (ss != null) m['scoringSystem'] = jsStr(ss);
  return m;
}

// ---- top level --------------------------------------------------------------
Map<String, dynamic> normalizeScoreboard(Registry reg, String key, Map sb, [Map extras = const {}]) {
  final profile = resolve(reg, key);
  final lg = (sb['leagues'] is List && (sb['leagues'] as List).isNotEmpty) ? (sb['leagues'] as List)[0] as Map : <String, dynamic>{};
  final events = (sb['events'] is List ? sb['events'] as List : const []).map((e) => buildEvent(profile, e as Map)).toList();
  final tournaments = extras['golfTournaments'] ?? {};
  for (final ev in events) {
    final m = golfMetaFromTournament(field(tournaments, ev['id']));
    if (m == null) continue;
    for (final c in ev['competitions'] as List) {
      if ((c as Map)['scoreKind'] == 'toPar') _meta(c)['golf'] = m;
    }
  }
  final cal = buildCalendar(lg);
  final season = pickNN({
    'year': field(lg['season'], 'year'),
    'type': field(field(lg['season'], 'type'), 'type') ?? (field(lg['season'], 'type') is num ? field(lg['season'], 'type') : null),
    'slug': or([field(lg['season'], 'slug'), field(field(lg['season'], 'type'), 'name')]),
    'displayName': field(lg['season'], 'displayName'),
  }, ['year', 'type', 'slug', 'displayName']);
  final day = field(sb['day'], 'date');
  final nextStart = nextScheduledStart(events);
  return {
    'sport': profile['espnSport'],
    'league': or([lg['slug'], key.split('/')[1]]),
    'leagueId': jsStr(lg['id'] ?? profile['espnLeagueId'] ?? ''),
    'leagueName': or([lg['name'], profile['name'], '']),
    'season': season,
    if (day != null) 'day': day,
    'updated': DateTime.now().toUtc().toIso8601String(),
    'anyLive': events.any((ev) => (ev['competitions'] as List).any((c) => field((c as Map)['status'], 'live') == true)),
    if (nextStart != null) 'nextStartMs': nextStart,
    if (cal['calendarDays'] != null) 'calendarDays': cal['calendarDays'],
    if (cal['seasonWindow'] != null) 'seasonWindow': cal['seasonWindow'],
    'events': events,
  };
}
