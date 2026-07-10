// fastcast_log.dart — the FastCast debug log: every push message in/out and
// what the app DID with it (decode, apply, emit/suppress, merge, poll-cadence
// choices, fallbacks). For chasing "the site shows 3-2, we show 3-1" class
// bugs: the log answers "did the message arrive?", "how old was it?", and
// "which source won on screen?".
//
// Zero product surface: a ring buffer (last 800 lines, [FcLog.snapshot]) plus
// a debugPrint mirror in debug builds ([enabled], toggleable at runtime from a
// debugger). Release builds keep the ring buffer only. op:"I" heartbeats are
// counted, not line-logged — at ~2s per topic they'd drown everything else.
//
// Read it with `flutter run` (console) or `adb logcat | grep "\[FC "`.

import 'dart:collection';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

class FcLog {
  /// Mirror every line to debugPrint. Defaults on in debug builds.
  static bool enabled = kDebugMode;

  static const _cap = 800;
  static final ListQueue<String> _buf = ListQueue<String>();

  /// [cat] is a short fixed tag (conn/send/frame/ckpt/apply/emit/overlay/
  /// merge/poll/act/err) so the stream greps cleanly.
  static void log(String cat, String msg) {
    final t = DateTime.now().toIso8601String();
    final line = '[FC ${t.substring(11, 23)}] ${cat.padRight(7)} $msg';
    _buf.addLast(line);
    if (_buf.length > _cap) _buf.removeFirst();
    if (enabled) debugPrint(line);
  }

  /// The retained tail, oldest first — dumpable from a debugger or a future
  /// hidden dev screen.
  static List<String> snapshot() => List.of(_buf);
}
