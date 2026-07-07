import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'models.dart';
import 'theme.dart';

/// Parse an ESPN hex color ('cc3433', '#cc3433') into a Color, or null.
Color? parseHex(String? hex) {
  if (hex == null) return null;
  final h = hex.replaceFirst('#', '').trim();
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

/// A competitor's identity color, made legible against the dark background.
/// ESPN colors are tuned for white backgrounds; a near-black navy vanishes on
/// #111318, so dark colors are lifted toward their alt color or lightened.
Color teamColor(Competitor? c) =>
    _legible(parseHex(c?.color), parseHex(c?.altColor));

Color teamColorOf(String? hex, [String? altHex]) =>
    _legible(parseHex(hex), parseHex(altHex));

Color _legible(Color? primary, Color? alt) {
  Color? pick = primary;
  if (pick == null || _luma(pick) < 0.09) {
    if (alt != null && _luma(alt) >= 0.09) {
      pick = alt;
    }
  }
  pick ??= T.outline;
  // Still too dark to read as a bar on #111318 → lighten it, keeping the hue.
  if (_luma(pick) < 0.09) {
    pick = Color.lerp(pick, Colors.white, 0.35)!;
  }
  return pick;
}

double _luma(Color c) => c.computeLuminance();

/// A legible text/glyph color to sit ON a solid [fill] (team-color square, TD/FG
/// chip, medal square): near-black on a light fill, off-white on a dark one.
Color onColor(Color fill) =>
    fill.computeLuminance() > 0.55 ? T.invertedText : T.text;

/// A team color pulled toward legibility as a *pale glyph/label* on a dark
/// team-tinted surface (tinted avatars, tinted signal pills) — lightened so it
/// reads on `surface`, never washed out.
Color paleOf(Color c) => _luma(c) < 0.5 ? Color.lerp(c, Colors.white, 0.45)! : c;

/// '3:00 PM' for today, 'Sun 3:00 PM' otherwise.
String startLabel(DateTime? start) {
  if (start == null) return '';
  final now = DateTime.now();
  final sameDay = start.year == now.year &&
      start.month == now.month &&
      start.day == now.day;
  final time = DateFormat.jm().format(start);
  return sameDay ? time : '${DateFormat.E().format(start)} $time';
}

/// 'Saturday, July 5' — the TODAY header date.
String todayLabel(DateTime d) => DateFormat('EEEE, MMMM d').format(d);

/// 'YYYYMMDD' (local calendar) — the wire form ESPN's ?date= speaks, used to
/// key the dated home feed / league slate.
String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.day.toString().padLeft(2, '0')}';

/// Parse a 'YYYYMMDD' string back to a local-midnight DateTime, or null.
DateTime? parseYmd(String? s) {
  if (s == null || s.length != 8) return null;
  final y = int.tryParse(s.substring(0, 4));
  final m = int.tryParse(s.substring(4, 6));
  final d = int.tryParse(s.substring(6, 8));
  if (y == null || m == null || d == null) return null;
  return DateTime(y, m, d);
}

/// True when two DateTimes fall on the same local calendar day.
bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// 'MON' — the upper weekday abbreviation for a date-strip chip.
String weekdayAbbrev(DateTime d) => DateFormat.E().format(d).toUpperCase();

/// 'Saturday' / 'Tomorrow' / 'Yesterday' — the non-today home-feed title when a
/// day is picked. Relative words for the immediate neighbours, weekday otherwise.
String dayTitle(DateTime d) {
  final now = DateTime.now();
  if (sameDay(d, now)) return 'TODAY';
  final delta = DateTime(d.year, d.month, d.day)
      .difference(DateTime(now.year, now.month, now.day))
      .inDays;
  if (delta == -1) return 'YESTERDAY';
  if (delta == 1) return 'TOMORROW';
  return DateFormat('EEEE').format(d).toUpperCase();
}

/// The compact status string for a live/final/scheduled row's right column.
String statusLine(Competition comp, SportEvent event) {
  final s = comp.status;
  if (s.live) return s.shortDetail ?? s.detail;
  if (s.isFinal) {
    var label = 'Final';
    if (comp.decision == 'shootout') label = 'Final · Pens';
    if (comp.decision == 'overtime') label = 'Final · OT';
    if (comp.periods.isOvertime && comp.periods.unit == 'inning') {
      label = 'Final/${comp.periods.played}';
    }
    return label;
  }
  if (s.isScheduled) return startLabel(event.start);
  return s.shortDetail ?? s.detail; // postponed / delayed / unknown
}

/// Uppercased display name for score blocks — the design shouts team names.
String blockName(Competitor c) =>
    (c.shortName ?? c.displayName).toUpperCase();
