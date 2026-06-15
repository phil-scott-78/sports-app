import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'src/providers.dart';
import 'src/ui/app.dart';

/// Single funnel for uncaught errors. Today it just logs; a crash reporter
/// (Sentry/Crashlytics) would slot in here without touching call sites.
void _reportError(Object error, StackTrace? stack) {
  // Visible in debug; in release this is the one place to forward to telemetry.
  debugPrint('Uncaught: $error\n$stack');
}

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Framework build/layout/paint errors → present (red overlay in debug,
    // logged) then funnel. Platform-channel/async errors that escape the
    // framework → funnel too. Both previously vanished in release.
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      _reportError(details.exception, details.stack);
    };
    WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
      _reportError(error, stack);
      return true;
    };
    // Replace Flutter's red/grey error box with a calm, in-theme placeholder so a
    // single widget failure degrades quietly instead of shouting.
    ErrorWidget.builder = (details) => const _CalmErrorBox();

    // Storage init sits ahead of the first frame — guard it so a corrupt prefs
    // store or a plugin race shows a retry screen, not a permanent white screen.
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (e, st) {
      _reportError(e, st);
    }

    if (prefs == null) {
      runApp(const _StartupErrorApp());
      return;
    }

    runApp(
      ProviderScope(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
        child: const ScoresApp(),
      ),
    );
  }, _reportError);
}

/// In-theme replacement for the default error widget — a muted box, no stack
/// trace shown to users. Self-contained (own Directionality) so it renders even
/// when the failed subtree had no ambient one.
class _CalmErrorBox extends StatelessWidget {
  const _CalmErrorBox();

  @override
  Widget build(BuildContext context) {
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: Color(0xFF0B0E11), // theme surface (dark)
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Something went wrong here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF8A9199), fontSize: 13),
            ),
          ),
        ),
      ),
    );
  }
}

/// Last-resort screen when storage can't be initialised before the first frame.
/// Offers a retry that re-runs startup (idempotent) rather than dying silently.
class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark),
      home: const Scaffold(
        backgroundColor: Color(0xFF0B0E11),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: Color(0xFF8A9199), size: 40),
                SizedBox(height: 16),
                Text(
                  "Couldn't start",
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white),
                ),
                SizedBox(height: 8),
                Text(
                  'Storage was unavailable. Try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF8A9199), fontSize: 13),
                ),
                SizedBox(height: 24),
                FilledButton(onPressed: main, child: Text('Retry')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
