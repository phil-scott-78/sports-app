// team.dart — Dart port of worker/src/team.js. Raw ESPN team endpoints →
// canonical favorite-team shapes. Reuses the shared per-event builder (buildEvent)
// + normalizeScoreboard so team games normalize through the EXACT same path as the
// scoreboard. Pure.

import 'profiles.dart';
import 'util.dart';
import 'normalize.dart';

/// JS String.prototype.localeCompare (default locale) — case-insensitive primary
/// ordering with a case/codepoint tiebreak. Good enough for team-name sorting;
/// verified against the JS output via the teams golden suite.
int localeCompare(String a, String b) {
  final la = a.toLowerCase(), lb = b.toLowerCase();
  final c = la.compareTo(lb);
  if (c != 0) return c;
  return a.compareTo(b);
}

// ---- teams list (the favorites picker) --------------------------------------
List<Map<String, dynamic>> normalizeTeams(Registry reg, String key, dynamic raw) {
  final profile = resolve(reg, key);
  final teams = field(first(field(first(field(raw, 'sports')), 'leagues')), 'teams');
  final list = teams is List ? teams : const [];
  final out = <Map<String, dynamic>>[];
  for (final entry in list) {
    final t = field(entry, 'team');
    if (t == null) continue;
    final light = https(or([field(t, 'logo'), field(first(field(t, 'logos')), 'href')]));
    final o = pickNN({
      'id': jsStr(field(t, 'id') ?? ''),
      'displayName': or([field(t, 'displayName'), field(t, 'name'), field(t, 'shortDisplayName'), '']),
      'abbreviation': or([field(t, 'abbreviation'), null]),
    }, ['id', 'displayName', 'abbreviation']);
    if (light != null) {
      o['logo'] = light;
      final d = darkLogoOf(t, light, profile['espnSport']);
      if (d != null) o['logoDark'] = d;
    }
    if (truthy(field(t, 'color'))) o['color'] = field(t, 'color');
    if (truthy(o['id'])) out.add(o);
  }
  out.sort((a, b) => localeCompare(a['displayName'] as String, b['displayName'] as String));
  return out;
}

// ---- shared team identity block ---------------------------------------------
Map<String, dynamic> teamIdentityOf(Map profile, dynamic t, dynamic teamId) {
  t ??= {};
  final light = https(or([field(t, 'logo'), field(first(field(t, 'logos')), 'href')]));
  final team = pickNN({
    'id': jsStr(field(t, 'id') ?? teamId),
    'displayName': or([field(t, 'displayName'), field(t, 'name'), '']),
    'abbreviation': or([field(t, 'abbreviation'), null]),
    'record': or([field(t, 'recordSummary'), null]),
    'standingSummary': or([field(t, 'standingSummary'), null]),
  }, ['id', 'displayName', 'abbreviation', 'record', 'standingSummary']);
  if (light != null) {
    team['logo'] = light;
    final d = darkLogoOf(t, light, profile['espnSport']);
    if (d != null) team['logoDark'] = d;
  }
  if (truthy(field(t, 'color'))) team['color'] = field(t, 'color');
  return team;
}

// ---- team card (live / last / next) -----------------------------------------
int _ms(dynamic s) => DateTime.tryParse(jsStr(s))?.millisecondsSinceEpoch ?? 0;

Map<String, dynamic> normalizeTeamCard(Registry reg, String key, dynamic teamId, dynamic schedule) {
  final profile = resolve(reg, key);
  final team = teamIdentityOf(profile, field(schedule, 'team'), teamId);
  final events = (field(schedule, 'events') is List ? field(schedule, 'events') as List : const [])
      .map((e) => buildEvent(profile, e as Map))
      .toList();

  Map<String, dynamic>? live, last, next;
  for (final ev in events) {
    final c = first(ev['competitions']);
    if (c == null) continue;
    final ms = _ms(ev['start']);
    final ph = field(c['status'], 'phase');
    if (ph == 'live') {
      if (live == null || _ms(live['start']) > ms) live = ev;
    } else if (field(c['status'], 'ended') == true || ph == 'final') {
      if (last == null || _ms(last['start']) < ms) last = ev;
    } else if (ph == 'scheduled') {
      if (next == null || _ms(next['start']) > ms) next = ev;
    }
  }

  return {
    'league': key,
    'sport': profile['espnSport'],
    'leagueName': or([profile['name'], key.split('/').length > 1 ? key.split('/')[1] : null, '']),
    'team': team,
    'live': live,
    'last': last,
    'next': next,
    'anyLive': live != null,
  };
}

// ---- scoreboard fallback (national teams / tournaments) ----------------------
Map<String, dynamic> applyScoreboardFallback(Registry reg, String key, dynamic teamId, Map card, Map sb) {
  final norm = normalizeScoreboard(reg, key, sb);
  final id = jsStr(teamId);
  Map? compFor(Map ev) {
    for (final c in ev['competitions'] as List) {
      if ((c['competitors'] as List).any((x) => (x as Map)['id'] == id)) return c as Map;
    }
    return null;
  }

  final mine = (norm['events'] as List).where((ev) => compFor(ev as Map) != null).toList();
  if (mine.isEmpty) return card.cast<String, dynamic>();

  var live = card['live'], last = card['last'], next = card['next'];
  for (final ev in mine) {
    final c = compFor(ev as Map)!;
    final ms = _ms(ev['start']);
    final ph = field(c['status'], 'phase');
    if (ph == 'live') {
      if (live == null || _ms(live['start']) > ms) live = ev;
    } else if (field(c['status'], 'ended') == true || ph == 'final') {
      if (last == null || _ms(last['start']) < ms) last = ev;
    } else if (ph == 'scheduled') {
      if (next == null || _ms(next['start']) > ms) next = ev;
    }
  }

  var team = card['team'] as Map;
  if (!truthy(team['displayName']) || !truthy(team['logo'])) {
    final ev = live ?? last ?? next;
    final me = ev != null ? (compFor(ev as Map)?['competitors'] as List?)?.firstWhere((x) => (x as Map)['id'] == id, orElse: () => null) : null;
    if (me != null) {
      team = {
        ...team,
        'displayName': or([team['displayName'], me['displayName']]),
        'abbreviation': or([team['abbreviation'], me['abbreviation']]),
        'logo': or([team['logo'], me['logo']]),
        'logoDark': or([team['logoDark'], me['logoDark']]),
        'color': or([team['color'], me['color']]),
      };
      // JS spread keeps undefined-valued keys out; drop nulls to match.
      team = pickNN(team, team.keys.map((e) => e.toString()).toList());
    }
  }

  return <String, dynamic>{...card.cast<String, dynamic>(), 'team': team, 'live': live, 'last': last, 'next': next, 'anyLive': live != null};
}
