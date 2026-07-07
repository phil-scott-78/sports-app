import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'src/data/profiles.dart';
import 'src/providers.dart';
import 'src/ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  // Load the bundled data model (schema/league-profiles.json) once, before any
  // request — the app resolves league profiles + normalizes ESPN on-device now
  // (no worker). See lib/src/data/.
  await Registry.load();
  runApp(ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    child: const ScoresV2App(),
  ));
}
