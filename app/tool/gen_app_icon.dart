// Generates the launcher-icon source art (assets/icon/) from the design
// tokens. Run with `flutter test tool/gen_app_icon.dart`, then
// `dart run flutter_launcher_icons` to fan out the platform mipmaps.
//
// The mark is the app's card grammar reduced to a glyph: a two-row scorebug —
// winner bar bright, loser bar dim, live dot as the one hot accent — on the
// broadcast-dark page background. No text, no logo (DESIGN.md §1).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _bg = Color(0xFF111318); // T.bg
const _bright = Color(0xFFEEF1F4); // T.text — the winning row
const _dim = Color(0xFF6C7480); // T.textFaint — the trailing row
const _live = Color(0xFFE5484D); // T.live

// Geometry on a 1024 canvas, centered on (515, 516).
void _mark(Canvas c, double scale) {
  c.translate(512, 512);
  c.scale(scale);
  c.translate(-515, -516);
  final bright = Paint()..color = _bright;
  final dim = Paint()..color = _dim;
  final live = Paint()..color = _live;
  c.drawRRect(
    RRect.fromRectAndRadius(
        const Rect.fromLTWH(306, 392, 290, 100), const Radius.circular(50)),
    bright,
  );
  c.drawCircle(const Offset(668, 442), 56, live);
  c.drawRRect(
    RRect.fromRectAndRadius(
        const Rect.fromLTWH(306, 540, 206, 100), const Radius.circular(50)),
    dim,
  );
}

Future<void> _writePng(String path, void Function(Canvas) draw) async {
  final rec = ui.PictureRecorder();
  draw(Canvas(rec));
  final img = await rec.endRecording().toImage(1024, 1024);
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!.buffer.asUint8List());
  debugPrint('wrote $path');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generate launcher icon art', () async {
    // Full icon (legacy mipmaps, web favicon): bg + mark.
    await _writePng('assets/icon/icon.png', (c) {
      c.drawRect(const Rect.fromLTWH(0, 0, 1024, 1024), Paint()..color = _bg);
      _mark(c, 1.4);
    });
    // Adaptive foreground: transparent, mark inside the 66% safe zone.
    await _writePng('assets/icon/icon_foreground.png', (c) => _mark(c, 1.22));
  });
}
