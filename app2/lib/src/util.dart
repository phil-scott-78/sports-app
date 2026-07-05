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
