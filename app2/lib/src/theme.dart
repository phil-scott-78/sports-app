import 'package:flutter/material.dart';

/// The v2 "broadcast dark" design tokens, lifted verbatim from the design
/// explorations (Sports App Explorations.dc.html, turns 2–8). One palette, two
/// typefaces: Barlow Condensed is the scoreboard voice (team names, scores,
/// clocks, stat numbers — always tabular), Archivo is the copy voice.
abstract final class T {
  // ---- surfaces ----
  static const bg = Color(0xFF111318); // page background
  static const surface = Color(0xFF1A1E25); // cards
  static const sheet = Color(0xFF1D222A); // bottom sheets
  static const navBg = Color(0xFF15181E); // bottom nav
  static const track = Color(0xFF22272F); // progress tracks, empty bases
  static const dragSurface = Color(0xFF242B36); // lifted (dragging) card

  // ---- strokes ----
  static const divider = Color(0xFF262C35); // hairlines inside cards
  static const border = Color(0xFF2A303A); // chip outlines, score-block rules
  static const outline = Color(0xFF414A55); // dashed/empty markers
  static const fieldLine = Color(0xFF232933); // yard/period gridlines
  static const diamondLine = Color(0xFF333A44); // baseball diamond path

  // ---- text ----
  static const text = Color(0xFFEEF1F4); // primary
  static const textDim = Color(0xFF9AA3AD); // secondary (losing side, captions)
  static const textFaint = Color(0xFF6C7480); // tertiary (units, hints)
  static const textBody = Color(0xFFC8CFD6); // play-feed prose

  // ---- accents ----
  static const live = Color(0xFFE5484D); // live dot, red cards, cut line
  static const gold = Color(0xFFFFC52F); // occupied bases, PP badge, star, markers
  static const green = Color(0xFF3FA96B); // winning streak, runs scored, under-WR
  static const underPar = Color(0xFFF26D6D); // golf red numbers
  static const silver = Color(0xFFB9BFC7);
  static const bronze = Color(0xFFB07A4A);

  // ---- inverted (LAST PLAY) card ----
  static const invertedBg = Color(0xFFEEF1F4);
  static const invertedText = Color(0xFF111318);
  static const invertedLabel = Color(0xFF6C7480);

  // ---- shape ----
  static const cardRadius = 20.0; // detail cards
  static const rowCardRadius = 16.0; // feed league cards / following rows
  static const cardPad = EdgeInsets.all(18);
  static const pageMargin = 20.0;

  // ---- type: scoreboard voice --------------------------------------------
  static const _bc = 'BarlowCondensed';
  static const _tab = [FontFeature.tabularFigures()];

  /// Giant score-block team name (40) / score (52).
  static const blockName = TextStyle(
      fontFamily: _bc, fontWeight: FontWeight.w700, fontSize: 40, height: 1.0);
  static const blockScore = TextStyle(
      fontFamily: _bc,
      fontWeight: FontWeight.w700,
      fontSize: 52,
      height: 1.0,
      fontFeatures: _tab);

  /// Hero favorite card team abbr (24) / score (32).
  static const heroName = TextStyle(
      fontFamily: _bc, fontWeight: FontWeight.w700, fontSize: 24, height: 1.0);
  static const heroScore = TextStyle(
      fontFamily: _bc,
      fontWeight: FontWeight.w700,
      fontSize: 32,
      height: 1.0,
      fontFeatures: _tab);

  /// Situation-card headline ("3RD & 4", "2–1 COUNT", "27 OFF 22").
  static const situationHead = TextStyle(
      fontFamily: _bc,
      fontWeight: FontWeight.w700,
      fontSize: 24,
      height: 1.1,
      color: text,
      fontFeatures: _tab);

  /// Big stat callout ("CHC 68%", clock "4:12").
  static const statCallout = TextStyle(
      fontFamily: _bc,
      fontWeight: FontWeight.w700,
      fontSize: 24,
      color: text,
      fontFeatures: _tab);

  /// Compact row score (17) and abbr-with-score bug (19).
  static const rowScore = TextStyle(
      fontFamily: _bc,
      fontWeight: FontWeight.w700,
      fontSize: 17,
      color: text,
      fontFeatures: _tab);
  static const bugScore = TextStyle(
      fontFamily: _bc,
      fontWeight: FontWeight.w700,
      fontSize: 19,
      color: text,
      fontFeatures: _tab);

  /// Stat-line numbers in list rows ('2-3, HR, 3 RBI' / '58 (39) · 148.7').
  static const statLine = TextStyle(
      fontFamily: _bc,
      fontWeight: FontWeight.w600,
      fontSize: 14,
      color: text,
      fontFeatures: _tab);
  static const statLineStrong = TextStyle(
      fontFamily: _bc,
      fontWeight: FontWeight.w700,
      fontSize: 16,
      color: text,
      fontFeatures: _tab);

  /// League section header ('MLB', 'WORLD CUP · ROUND OF 16').
  static const sectionTitle = TextStyle(
      fontFamily: _bc,
      fontWeight: FontWeight.w700,
      fontSize: 16,
      color: text,
      letterSpacing: 1.3);

  /// Page title ('TODAY', 'STANDINGS', 'FOLLOWING').
  static const pageTitle = TextStyle(
      fontFamily: _bc,
      fontWeight: FontWeight.w700,
      fontSize: 30,
      height: 1.0,
      color: text);

  // ---- type: copy voice ----------------------------------------------------
  /// Small-caps card label ('WIN PROBABILITY', 'LAST PLAY').
  static const cardLabel = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.72,
      color: textDim);
  static const cardLabelFaint = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.66,
      color: textFaint);

  /// Status pill text ('BOT 7 · 2 OUT').
  static const pillText = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.44,
      color: text);

  /// Caption (venue, footnotes).
  static const caption = TextStyle(fontSize: 12, color: textDim);
  static const captionFaint = TextStyle(fontSize: 11, color: textFaint);

  /// Row primary text (team names in dense rows / lists).
  static const rowText =
      TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: text);
  static const rowTextDim = TextStyle(fontSize: 14, color: textDim);
  static const listText = TextStyle(fontSize: 13.5, color: text);

  /// Inverted last-play prose.
  static const invertedProse = TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      height: 1.35,
      color: invertedText);
}

/// The MaterialApp theme: dark-only, Archivo everywhere by default.
ThemeData buildV2Theme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    fontFamily: 'Archivo',
    scaffoldBackgroundColor: T.bg,
    colorScheme: const ColorScheme.dark(
      surface: T.bg,
      onSurface: T.text,
      primary: T.gold,
      onPrimary: T.invertedText,
      secondary: T.textDim,
      error: T.live,
      surfaceContainerHighest: T.surface,
      outline: T.border,
    ),
    splashFactory: InkSparkle.splashFactory,
  );
  return base.copyWith(
    dividerColor: T.divider,
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: T.gold,
      selectionColor: Color(0x33FFC52F),
      selectionHandleColor: T.gold,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: T.sheet,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
    }),
  );
}
