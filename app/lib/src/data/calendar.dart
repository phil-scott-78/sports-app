// calendar.dart — Dart port of worker/src/calendar.js. The season skeleton ESPN
// ships inside every scoreboard's leagues[0]. Pure. Single home for reading
// ESPN's calendar (normalize.dart's scores passthrough + overview.dart's
// season-pulse classifier both use it — the rule must never fork).
//
// The JS reads US-Eastern calendar days via Intl.DateTimeFormat('America/
// New_York'). Dart has no bundled IANA tz DB, so we compute the US Eastern
// offset from the standard DST rules (EDT = UTC-4 from the 2nd Sunday of March
// 02:00 to the 1st Sunday of November 02:00; EST = UTC-5 otherwise). This matches
// Intl for every US Eastern date — verified against the JS output via the scores
// golden suite (calendarDays parity).

/// nth Sunday of a month as a UTC instant at [utcHour]:00.
int _nthSundayUtc(int year, int month, int nth, int utcHour) {
  var d = DateTime.utc(year, month, 1);
  var count = 0;
  while (true) {
    if (d.weekday == DateTime.sunday) {
      count++;
      if (count == nth) break;
    }
    d = d.add(const Duration(days: 1));
  }
  return DateTime.utc(year, month, d.day, utcHour).millisecondsSinceEpoch;
}

/// US Eastern UTC offset (in hours, negative) for a given UTC instant.
int _etOffsetHours(int utcMs) {
  final year = DateTime.fromMillisecondsSinceEpoch(utcMs, isUtc: true).year;
  // DST spring-forward: 2nd Sunday of March at 02:00 EST == 07:00 UTC.
  final dstStart = _nthSundayUtc(year, 3, 2, 7);
  // DST fall-back: 1st Sunday of November at 02:00 EDT == 06:00 UTC.
  final dstEnd = _nthSundayUtc(year, 11, 1, 6);
  return (utcMs >= dstStart && utcMs < dstEnd) ? -4 : -5;
}

/// US-Eastern calendar day as a UTC-midnight stamp, matching ESPN's bucketing
/// (and the app's "today"). Returns null if unparsable.
int? easternDayMs(dynamic input) {
  int? utcMs;
  if (input is int) {
    utcMs = input;
  } else if (input is DateTime) {
    utcMs = input.millisecondsSinceEpoch;
  } else if (input is String) {
    final d = DateTime.tryParse(input);
    if (d != null) utcMs = d.millisecondsSinceEpoch;
  }
  if (utcMs == null) return null;
  final local = DateTime.fromMillisecondsSinceEpoch(
      utcMs + _etOffsetHours(utcMs) * 3600 * 1000,
      isUtc: true);
  return DateTime.utc(local.year, local.month, local.day).millisecondsSinceEpoch;
}

String _pad(int n) => n < 10 ? '0$n' : '$n';

/// 'YYYYMMDD' for an ET-day stamp (the app's date-param + day-key format).
String ymd(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  return '${d.year}${_pad(d.month)}${_pad(d.day)}';
}

/// Collapse a league's calendar into sorted ranges (ET days), each tagged with
/// whether it came from a NESTED season bucket vs a flat top-level entry.
/// Shape: { start, end, nested }. Mirrors rangesFromCalendar in calendar.js.
List<Map<String, dynamic>> rangesFromCalendar(dynamic calendarType, dynamic calendar) {
  final out = <Map<String, dynamic>>[];
  if (calendar is! List || calendar.isEmpty) return out;
  final isDay = calendarType == 'day' || calendar[0] is String;
  if (isDay) {
    for (final s in calendar) {
      final ms = easternDayMs(s);
      if (ms != null) out.add({'start': ms, 'end': ms, 'nested': false});
    }
  } else {
    for (final entry in calendar) {
      if (entry is! Map) continue;
      final entries = entry['entries'];
      final nested = entries is List && entries.isNotEmpty;
      final kids = nested ? entries : [entry];
      for (final k in kids) {
        if (k is! Map || k['startDate'] == null) continue;
        final start = easternDayMs(k['startDate']);
        if (start == null) continue;
        final endRaw = k['endDate'];
        int? end = start;
        if (endRaw != null) {
          final parsed = DateTime.tryParse(endRaw.toString());
          if (parsed != null) {
            end = easternDayMs(parsed.millisecondsSinceEpoch - 1000);
          }
        }
        out.add({'start': start, 'end': (end ?? start) > start ? end : start, 'nested': nested});
      }
    }
  }
  out.sort((a, b) => (a['start'] as int).compareTo(b['start'] as int));
  return out;
}

/// The on-the-scores-payload calendar: a precise game-day list for "day"-type
/// leagues + the season window. Returns {} when absent. Mirrors buildCalendar.
Map<String, dynamic> buildCalendar(dynamic lg) {
  final out = <String, dynamic>{};
  final cal = lg is Map ? lg['calendar'] : null;
  final isDay = lg is Map &&
      (lg['calendarType'] == 'day' || (cal is List && cal.isNotEmpty && cal[0] is String));
  if (isDay && cal is List && cal.isNotEmpty) {
    final set = <String>{};
    for (final s in cal) {
      final ms = easternDayMs(s);
      if (ms != null) set.add(ymd(ms));
    }
    if (set.isNotEmpty) {
      final sorted = set.toList()..sort();
      out['calendarDays'] = sorted;
    }
  }
  final season = (lg is Map ? lg['season'] : null) ?? {};
  final win = <String, dynamic>{};
  if (season is Map && season['startDate'] != null) win['startDate'] = season['startDate'];
  if (season is Map && season['endDate'] != null) win['endDate'] = season['endDate'];
  if (win.isNotEmpty) out['seasonWindow'] = win;
  return out;
}
