// overview.dart — Dart port of worker/src/overview.js. Per-league "season pulse"
// classifier: given a raw ESPN scoreboard + a reference instant, returns a compact
// {state, detail, live} for the Leagues list. Pure. Calendar parsing lives in
// calendar.dart (the single home). state ∈ live|today|upcoming|recent|offseason.

import 'calendar.dart';
import 'util.dart';

const _day = 86400000;
const _eventSpanCap = 14 * _day;
const _wd = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const _mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _wdOf(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  return _wd[d.weekday % 7]; // Dart Mon=1..Sun=7 -> JS Sun=0..Sat=6
}

String _mdOf(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  return '${_mo[d.month - 1]} ${d.day}';
}

Map<String, dynamic> classifyLeague(dynamic raw, DateTime now) {
  final today = easternDayMs(now)!;
  final lgMap = (first(field(raw, 'leagues')) is Map ? first(field(raw, 'leagues')) as Map : <String, dynamic>{});
  final events = field(raw, 'events') is List ? field(raw, 'events') as List : const [];
  final ranges = rangesFromCalendar(lgMap['calendarType'], lgMap['calendar']);

  final eventDays = <int>[];
  for (final e in events) {
    final ms = easternDayMs(field(e, 'date'));
    if (ms != null) eventDays.add(ms);
  }

  final todayEvents = events.where((e) => easternDayMs(field(e, 'date')) == today).toList();

  final gameWindows = ranges.where((r) => r['nested'] != true && ((r['end'] as int) - (r['start'] as int)) <= _eventSpanCap).toList();
  final hasToday = todayEvents.isNotEmpty || gameWindows.any((r) => today >= (r['start'] as int) && today <= (r['end'] as int));

  bool stateIn(dynamic e) => field(field(field(first(field(e, 'competitions')), 'status'), 'type'), 'state') == 'in';
  final liveToday = todayEvents.any(stateIn) ||
      (events.any(stateIn) && gameWindows.any((r) => (r['end'] as int) > (r['start'] as int) && today >= (r['start'] as int) && today <= (r['end'] as int)));

  int? next, prev;
  void consider(int s, int en) {
    if (s > today) next = next == null ? s : (s < next! ? s : next);
    if (en < today) prev = prev == null ? en : (en > prev! ? en : prev);
  }

  for (final r in ranges) {
    consider(r['start'] as int, r['end'] as int);
  }
  for (final d in eventDays) {
    consider(d, d);
  }

  final season = lgMap['season'] is Map ? lgMap['season'] as Map : {};
  final sStart = season['startDate'] != null ? easternDayMs(season['startDate']) : (ranges.isNotEmpty ? ranges[0]['start'] as int : null);
  final sEnd = season['endDate'] != null
      ? easternDayMs(season['endDate'])
      : (ranges.isNotEmpty ? ranges.map((r) => r['end'] as int).reduce((a, b) => a > b ? a : b) : null);
  final inSeason = (sStart != null && sEnd != null) ? (today >= sStart && today <= sEnd) : (hasToday || next != null);

  final dNext = next != null ? ((next! - today) / _day).round() : null;
  final dPrev = prev != null ? ((today - prev!) / _day).round() : null;

  if (hasToday) {
    return liveToday
        ? {'state': 'live', 'detail': 'Live now', 'live': true}
        : {'state': 'today', 'detail': 'Games today', 'live': false};
  }
  if (!inSeason) {
    return {'state': 'offseason', 'detail': next != null ? 'Returns ${_mdOf(next!)}' : 'Off-season', 'live': false};
  }
  if (dNext != null && dNext <= 7) {
    return {'state': 'upcoming', 'detail': dNext <= 1 ? 'Tomorrow' : _wdOf(next!), 'live': false};
  }
  if (dPrev != null && dPrev <= 3) {
    return {'state': 'recent', 'detail': dPrev <= 1 ? 'Yesterday' : _wdOf(prev!), 'live': false};
  }
  if (dNext != null) return {'state': 'upcoming', 'detail': 'Next ${_mdOf(next!)}', 'live': false};
  if (dPrev != null) return {'state': 'recent', 'detail': 'Last ${_mdOf(prev!)}', 'live': false};
  return {'state': 'offseason', 'detail': 'Off-season', 'live': false};
}

final _uidLeagueId = RegExp(r'(?:^|~)l:(\d+)(?:~|$)');

/// Port of worker/src/overview.js classifyMergedSlate: a merged `<sport>/all`
/// scoreboard (capability `hasAllScoreboard`) → per-ESPN-league-id pulse
/// entries, POSITIVE states only (live | today). The merged feed carries no
/// per-league season/calendar, so leagues without a game in the slate stay
/// silent — the per-league classifyLeague fan-out supplies their captions.
/// League ids come from each event's uid (`s:600~l:700~e:…`).
Map<String, dynamic> classifyMergedSlate(dynamic raw, DateTime now) {
  final today = easternDayMs(now);
  final events = field(raw, 'events') is List ? field(raw, 'events') as List : const [];
  final acc = <String, List<bool>>{}; // id → [anyLive, anyToday], first-seen order
  for (final e in events) {
    final uid = field(e, 'uid');
    final m = _uidLeagueId.firstMatch(uid is String ? uid : '');
    if (m == null) continue;
    final cur = acc.putIfAbsent(m.group(1)!, () => [false, false]);
    // An in-progress event is live NOW regardless of its listed date (golf/MMA
    // date to their start day); a dated-today event marks the day's slate.
    final st = field(field(field(first(field(e, 'competitions')), 'status'), 'type'), 'state');
    if (st == 'in') cur[0] = true;
    if (easternDayMs(field(e, 'date')) == today) cur[1] = true;
  }
  final out = <String, dynamic>{};
  acc.forEach((id, s) {
    if (s[0]) {
      out[id] = {'state': 'live', 'detail': 'Live now', 'live': true};
    } else if (s[1]) {
      out[id] = {'state': 'today', 'detail': 'Games today', 'live': false};
    }
  });
  return out;
}
