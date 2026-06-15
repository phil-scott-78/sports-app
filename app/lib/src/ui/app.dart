import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../theme.dart';
import 'home_shell.dart';

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
        child: child!,
      ),
      home: const HomeShell(),
    );
  }
}
