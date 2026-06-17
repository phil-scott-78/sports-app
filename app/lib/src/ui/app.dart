import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../theme.dart';
import 'home_shell.dart';
import 'update_banner.dart';

class ScoresApp extends ConsumerWidget {
  const ScoresApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(settingsProvider.select((s) => s.themeMode));
    return MaterialApp(
      title: 'Scores',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: mode,
      // Honour system text scaling, but cap it: the dense, fixed-geometry score
      // grids (line scores, box scores, leaderboards) misalign/clip past ~1.3×.
      // This keeps large-font users legible without overflowing the core surface.
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: _AppChrome(child: child!),
      ),
      home: const HomeShell(),
    );
  }
}

/// Rides the [UpdateBanner] above the whole app (all three tabs). In the common
/// case (current build / no gate served / dismissed) it renders the app
/// untouched — zero layout cost. Only when the banner actually shows does it wrap
/// in a top [SafeArea]: that both seats the banner below the status bar AND zeroes
/// the top inset for the page beneath, so the page's own AppBar doesn't pad for
/// the status bar a second time.
class _AppChrome extends ConsumerWidget {
  final Widget child;
  const _AppChrome({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(bannerVisibleProvider)) return child; // common case: no-op
    return SafeArea(
      top: true,
      bottom: false,
      child: Column(
        children: [
          const UpdateBanner(),
          Expanded(child: child),
        ],
      ),
    );
  }
}
