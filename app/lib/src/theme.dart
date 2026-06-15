import 'package:flutter/material.dart';

/// Greyscale-first theme (Binance-derived).
///
/// A calm, glanceable look: a deep near-black canvas holding flat color blocks
/// separated by 1px hairlines — no shadows, no atmospheric gradients. Hierarchy
/// is carried by weight, size, and two-tier muting, *not* color. Color is
/// earned: a subtle team-color wash on final results (see GameCard). The yellow
/// accent (#FCD535) is *demoted* to a scarce functional signal — the one primary
/// action, selection, focus — never brand voltage or decoration. Trading
/// green/red stay strictly up/down semantics. Type runs Inter for copy and IBM
/// Plex Sans for every number (tabular).
///
/// See ../../DESIGN-binance.md for the full design language.

// ---- raw brand tokens -------------------------------------------------------
const _yellow = Color(0xFFFCD535); // primary — the single brand voltage
const _onYellow = Color(0xFF181A20); // black text on yellow (the signature)

// dark canvas family
const _canvasDark = Color(0xFF0B0E11); // page floor (near-black, warm tint)
const _cardDark = Color(0xFF1E2329); // elevated cards, nav, secondary buttons
const _elevatedDark = Color(0xFF2B3139); // nested cards / hovered / hairline
const _bodyDark = Color(0xFFEAECEF); // running text on dark (not pure white)
const _mutedStrong = Color(0xFF929AA5); // emphasized secondary text
const _muted = Color(0xFF707A8A); // captions, column headers, dim borders
const _slate = Color(0xFF5E6673); // neutral counterpart to the yellow accent

// light canvas family (transactional surfaces flip light, same yellow CTAs)
const _canvasLight = Color(0xFFFFFFFF);
const _cardLight = Color(0xFFFAFAFA); // surface-soft
const _strongLight = Color(0xFFF5F5F5); // surface-strong (muted inputs)
const _ink = Color(0xFF181A20); // strongest text on light
const _hairlineLight = Color(0xFFEAECEF);
const _borderStrong = Color(0xFFCDD1D6);

// trading semantics — text/fill price-direction signals, never card surfaces
const _tradingUp = Color(0xFF0ECB81);
const _tradingDown = Color(0xFFF6465D);
const _info = Color(0xFF3B82F6); // focus ring base

// design-handoff functional accents (near-monochrome system; see Scores App.html).
// Each is a *functional* signal — never decoration — and lives on [BinanceColors].
const _live = Color(0xFF36D07A); // in-progress (green) — the single live hue
const _liveLight = Color(0xFF1F9D57); // darker green so it clears AA on light
const _victor = Color(0xFFD9B25E); // warm gold — favorite star / winner accent
const _formWin = Color(0xFF3A9D63); // recent-form win chip
const _formLoss = Color(0xFFC2503F); // recent-form loss chip
const _formDraw = Color(0xFF5B6066); // recent-form draw chip
const _danger = Color(0xFFD8513F); // timeline card / disciplinary event

// ---- type roles -------------------------------------------------------------
/// BinanceNova substitute — all copy, labels, headlines.
const String kSans = 'Inter';

/// BinancePlex substitute — every number (scores, prices, stats, clocks).
/// Pair with [tabularFigures] so digits never shift width as they change.
const String kNumFont = 'IBMPlexSans';

/// Tabular figures so scores don't reflow as digits change.
const List<FontFeature> tabularFigures = [FontFeature.tabularFigures()];

/// Shorthand for a BinancePlex (number) text style. Always tabular.
TextStyle numStyle({
  required double size,
  FontWeight weight = FontWeight.w500,
  Color? color,
  double? letterSpacing,
}) =>
    TextStyle(
      fontFamily: kNumFont,
      fontFeatures: tabularFigures,
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
    );

/// Non-Material design tokens that have no ColorScheme home: the trading
/// up/down semantics and a mode-aware [accent].
///
/// [accent] is the foreground emphasis color: brand yellow on the dark
/// (showcase) canvas, confident ink on light — so the yellow stays a scarce,
/// high-voltage signal in dark and never turns into illegible yellow-on-white.
/// Filled CTAs keep the true yellow (ColorScheme.primary) in both modes.
@immutable
class BinanceColors extends ThemeExtension<BinanceColors> {
  final Color up;
  final Color down;
  final Color accent;
  final Color cardBorder;

  // design-handoff functional accents (see Scores App.html). Winner *emphasis*
  // stays team-color (the card/hero wash); these carry the rest of the system.
  final Color live; // in-progress green
  final Color victor; // warm gold — favorite star / winner accent
  final Color formWin; // recent-form W
  final Color formLoss; // recent-form L
  final Color formDraw; // recent-form D
  final Color danger; // timeline card / disciplinary event

  const BinanceColors({
    required this.up,
    required this.down,
    required this.accent,
    required this.cardBorder,
    required this.live,
    required this.victor,
    required this.formWin,
    required this.formLoss,
    required this.formDraw,
    required this.danger,
  });

  static const _dark = BinanceColors(
    up: _tradingUp,
    down: _tradingDown,
    accent: _yellow,
    cardBorder: _elevatedDark,
    live: _live,
    victor: _victor,
    formWin: _formWin,
    formLoss: _formLoss,
    formDraw: _formDraw,
    danger: _danger,
  );
  static const _light = BinanceColors(
    up: _tradingUp,
    down: _tradingDown,
    accent: _ink,
    cardBorder: _hairlineLight,
    live: _liveLight,
    victor: _victor,
    formWin: _formWin,
    formLoss: _formLoss,
    formDraw: _formDraw,
    danger: _danger,
  );

  /// Reads the registered extension, falling back to sensible defaults so
  /// widgets pumped under a bare [MaterialApp] (e.g. in tests) never crash.
  static BinanceColors of(BuildContext context) =>
      Theme.of(context).extension<BinanceColors>() ??
      (Theme.of(context).brightness == Brightness.dark ? _dark : _light);

  @override
  BinanceColors copyWith({
    Color? up,
    Color? down,
    Color? accent,
    Color? cardBorder,
    Color? live,
    Color? victor,
    Color? formWin,
    Color? formLoss,
    Color? formDraw,
    Color? danger,
  }) =>
      BinanceColors(
        up: up ?? this.up,
        down: down ?? this.down,
        accent: accent ?? this.accent,
        cardBorder: cardBorder ?? this.cardBorder,
        live: live ?? this.live,
        victor: victor ?? this.victor,
        formWin: formWin ?? this.formWin,
        formLoss: formLoss ?? this.formLoss,
        formDraw: formDraw ?? this.formDraw,
        danger: danger ?? this.danger,
      );

  @override
  BinanceColors lerp(ThemeExtension<BinanceColors>? other, double t) {
    if (other is! BinanceColors) return this;
    return BinanceColors(
      up: Color.lerp(up, other.up, t)!,
      down: Color.lerp(down, other.down, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      live: Color.lerp(live, other.live, t)!,
      victor: Color.lerp(victor, other.victor, t)!,
      formWin: Color.lerp(formWin, other.formWin, t)!,
      formLoss: Color.lerp(formLoss, other.formLoss, t)!,
      formDraw: Color.lerp(formDraw, other.formDraw, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

ColorScheme _darkScheme() => ColorScheme.fromSeed(
      seedColor: _yellow,
      brightness: Brightness.dark,
    ).copyWith(
      primary: _yellow,
      onPrimary: _onYellow,
      primaryContainer: _elevatedDark,
      onPrimaryContainer: _yellow,
      secondary: _mutedStrong,
      onSecondary: _onYellow,
      // Neutral grey step — yellow is reserved for real CTAs/winner claims, not
      // generic secondary chrome (the nav pill uses ext.accent explicitly).
      secondaryContainer: _elevatedDark,
      onSecondaryContainer: _bodyDark,
      tertiary: _slate, // neutral counterpart for mirrored stat bars
      onTertiary: _bodyDark,
      error: _tradingDown,
      onError: Colors.white,
      errorContainer: const Color(0xFF3A1A20), // deep red tint for the live pill
      onErrorContainer: _tradingDown,
      surface: _canvasDark,
      onSurface: _bodyDark,
      onSurfaceVariant: _mutedStrong,
      surfaceContainerLowest: const Color(0xFF06080A),
      surfaceContainerLow: _cardDark,
      surfaceContainer: _cardDark,
      surfaceContainerHigh: _elevatedDark,
      surfaceContainerHighest: _elevatedDark,
      outline: _muted,
      outlineVariant: _elevatedDark,
      surfaceTint: _canvasDark, // kill the M3 purple elevation tint — flat blocks
      inverseSurface: _bodyDark,
      onInverseSurface: _canvasDark,
      scrim: Colors.black,
    );

ColorScheme _lightScheme() => ColorScheme.fromSeed(
      seedColor: _yellow,
      brightness: Brightness.light,
    ).copyWith(
      primary: _yellow,
      onPrimary: _onYellow,
      primaryContainer: _strongLight,
      onPrimaryContainer: _ink,
      secondary: _muted,
      onSecondary: Colors.white,
      secondaryContainer: _strongLight,
      onSecondaryContainer: _ink,
      tertiary: _slate,
      onTertiary: Colors.white,
      error: _tradingDown,
      onError: Colors.white,
      errorContainer: const Color(0xFFFDE7EA),
      onErrorContainer: _tradingDown,
      surface: _canvasLight,
      onSurface: _ink,
      // #707a8a is ~4.1:1 on white — below AA for 12-13px secondary text. Use
      // the darker slate (~5.7:1); reserve #707a8a for non-text hairlines only.
      onSurfaceVariant: _slate,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: _cardLight,
      surfaceContainer: _cardLight,
      surfaceContainerHigh: _strongLight,
      surfaceContainerHighest: _hairlineLight,
      outline: _borderStrong,
      outlineVariant: _hairlineLight,
      surfaceTint: _canvasLight,
    );

ThemeData buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme = isDark ? _darkScheme() : _lightScheme();
  final ext = isDark ? BinanceColors._dark : BinanceColors._light;

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: kSans,
    scaffoldBackgroundColor: scheme.surface,
    // Pins DataTable row rules (standings) to the 1px hairline instead of M3's
    // default tonal divider — matches dividerTheme everywhere else.
    dividerColor: scheme.outlineVariant,
    extensions: [ext],

    // Flat near-black bar; no tint, hairline only when scrolled under.
    appBarTheme: AppBarThemeData(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0.5,
      shadowColor: scheme.outlineVariant,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: kSans,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: scheme.onSurface,
      ),
    ),

    // Canvas-floor nav, a subtle grey selection pill, yellow on the active icon.
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.surfaceContainerHigh,
      elevation: 0,
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontFamily: kSans,
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? scheme.onSurface : scheme.onSurfaceVariant,
          )),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            size: 24,
            // Glyph (not a fill) → mode-aware accent so it stays legible on light.
            color: states.contains(WidgetState.selected) ? ext.accent : scheme.onSurfaceVariant,
          )),
    ),

    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),

    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      titleTextStyle: TextStyle(fontFamily: kSans, fontSize: 15, fontWeight: FontWeight.w500, color: scheme.onSurface),
      subtitleTextStyle: TextStyle(fontFamily: kSans, fontSize: 13, color: scheme.onSurfaceVariant),
    ),

    // Yellow fill + black text — the signature CTA, identical in both modes.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        textStyle: const TextStyle(fontFamily: kSans, fontSize: 14, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.onSurfaceVariant,
        textStyle: const TextStyle(fontFamily: kSans, fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),

    // Theme picker: yellow selected segment, black label.
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        textStyle: const WidgetStatePropertyAll(
            TextStyle(fontFamily: kSans, fontSize: 13, fontWeight: FontWeight.w600)),
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? scheme.primary : Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? scheme.onPrimary : scheme.onSurfaceVariant),
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outlineVariant)),
        shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
      ),
    ),

    // Session selector chips (racing): yellow when selected.
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      selectedColor: scheme.primary,
      side: BorderSide(color: scheme.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      labelStyle: TextStyle(fontFamily: kSans, fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurface),
      secondaryLabelStyle: TextStyle(fontFamily: kSans, fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onPrimary),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    ),

    // Worker-URL field: filled card with a blue focus ring.
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      hintStyle: TextStyle(color: scheme.onSurfaceVariant, fontFamily: kSans),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _info, width: 2),
      ),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),

    // Yellow switch — an honest CTA accent for the one preference toggle.
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? scheme.onPrimary : scheme.onSurfaceVariant),
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? scheme.primary : scheme.surfaceContainerHigh),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? Colors.transparent : scheme.outline),
    ),

    progressIndicatorTheme: ProgressIndicatorThemeData(color: ext.accent),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: ext.accent,
      selectionColor: ext.accent.withValues(alpha: 0.3),
      selectionHandleColor: ext.accent,
    ),

    dataTableTheme: DataTableThemeData(
      headingTextStyle: TextStyle(
          fontFamily: kSans, fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
      dataTextStyle: TextStyle(fontFamily: kSans, fontSize: 13, color: scheme.onSurface),
      dividerThickness: 1,
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      contentTextStyle: TextStyle(fontFamily: kSans, color: scheme.onSurface),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}
