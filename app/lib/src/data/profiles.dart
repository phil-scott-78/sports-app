// profiles.dart — the Dart port of schema/tools/resolve.mjs + the registry
// loader + the catalog builder (schema/tools/resolve.mjs, worker/src/catalog.js).
//
// The app bundles schema/league-profiles.json (see pubspec + tool/sync_registry)
// and resolves league profiles ON-DEVICE — this is the foundation the worker used
// to carry. `resolve` walks the three-tier `extends` chain (family -> profile ->
// league; nearest wins, scalars replace, objects shallow-merge) exactly as the JS
// resolver does. Keep this in lock-step with resolve.mjs.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

/// The parsed data model. Holds the three inheritance tiers + the client gate.
/// Construct once (async) from the bundled asset via [Registry.load]; tests build
/// it synchronously from a JSON string via [Registry.fromJsonString].
class Registry {
  final Map<String, dynamic> leagues;
  final Map<String, dynamic> profiles;
  final Map<String, dynamic> families;
  final Map<String, dynamic> raw;

  Registry._(this.leagues, this.profiles, this.families, this.raw);

  factory Registry.fromJsonString(String jsonStr) {
    final m = jsonDecode(jsonStr) as Map<String, dynamic>;
    Map<String, dynamic> sub(String k) => m[k] is Map
        ? (m[k] as Map).map((a, b) => MapEntry(a.toString(), b))
        : <String, dynamic>{};
    return Registry._(sub('leagues'), sub('profiles'), sub('families'), m);
  }

  static Registry? _cached;

  /// Load the bundled registry once (cached). Call before any resolve/normalize.
  static Future<Registry> load() async {
    if (_cached != null) return _cached!;
    final s = await rootBundle.loadString('assets/league-profiles.json');
    return _cached = Registry.fromJsonString(s);
  }

  /// The synchronously-available instance once [load] has completed. Normalizers
  /// need a resolver without awaiting; the app awaits [load] at startup, so by the
  /// time any request runs this is populated. Throws if accessed too early.
  static Registry get instance {
    final r = _cached;
    if (r == null) {
      throw StateError('Registry.load() must complete before Registry.instance');
    }
    return r;
  }

  /// Test hook: inject a registry as the cached instance.
  static set instance(Registry r) => _cached = r;

  /// Whether [load] has completed — for the rare synchronous caller that must
  /// degrade gracefully instead of throwing (e.g. capability gates evaluated
  /// from widget tests that never load the registry).
  static bool get loaded => _cached != null;

  /// Find a node by key across leagues -> profiles -> families (in that order).
  Map<String, dynamic>? findNode(String key) {
    final n = leagues[key] ?? profiles[key] ?? families[key];
    return n is Map ? n.map((a, b) => MapEntry(a.toString(), b)) : null;
  }
}

/// Resolve a league/profile/family key to its effective config by walking the
/// `extends` chain. Nearest wins; scalars replace, objects shallow-merge. Mirrors
/// resolve.mjs (including the cyclic-extends guard and the `_key` stamp).
Map<String, dynamic> resolve(Registry reg, String key, [Set<String>? seen]) {
  seen ??= <String>{};
  if (seen.contains(key)) throw StateError('cyclic extends at $key');
  seen.add(key);
  final node = reg.findNode(key);
  if (node == null) throw StateError('unknown profile key: $key');
  final ext = node['extends'];
  final base = ext is String
      ? resolve(reg, ext, seen)
      : <String, dynamic>{};
  final merged = Map<String, dynamic>.from(base);
  for (final entry in node.entries) {
    final k = entry.key;
    if (k == 'extends') continue;
    final v = entry.value;
    final b = base[k];
    // objects shallow-merge onto a same-typed base object; scalars/arrays replace.
    merged[k] = (v is Map && v is! List && b is Map)
        ? {...b.map((a, c) => MapEntry(a.toString(), c)), ...v.map((a, c) => MapEntry(a.toString(), c))}
        : v;
  }
  merged['_key'] = key;
  return merged;
}

/// Read a capability flag off a resolved profile — the registry's per-family
/// `capabilities{}` object (SCHEMA.md §2a), resolved through the extends chain
/// like everything else. OMIT-MEANS-FALSE: a missing object or missing flag
/// means the sport does not serve that datum — hide the element cleanly.
/// Flags: hasSummaryTier, hasSituation, hasWinProb, hasScoringPlaysArray,
/// hasPlaysFeed, hasCommentary, hasForm, hasPowerPlay, hasSeeds, hasWeather,
/// hasOdds.
/// (hasLineScores and rankingsFeed predate this object and stay top-level keys.)
bool hasCapability(Map<String, dynamic> profile, String flag) {
  final caps = profile['capabilities'];
  return caps is Map && caps[flag] == true;
}

/// All concrete league keys, optionally filtered. Skips dynamic `_*` buckets.
/// `priority` accepts a single tier ('v1') or a list (['v1','v2']). Order is
/// registry insertion order (JSON object key order — preserved by dart:convert),
/// so page slices are deterministic. Mirrors leagueKeys in resolve.mjs.
List<String> leagueKeys(Registry reg,
    {Object? priority, String? sport, bool includeBuckets = false}) {
  final prios = priority == null
      ? null
      : (priority is List ? priority.map((e) => e.toString()).toList() : [priority.toString()]);
  return reg.leagues.keys.where((k) {
    if (!includeBuckets) {
      final parts = k.split('/');
      if (parts.length > 1 && parts[1].startsWith('_')) return false;
    }
    if (prios != null) {
      final p = (reg.leagues[k] as Map)['priority'];
      if (!prios.contains(p)) return false;
    }
    if (sport != null && !k.startsWith('$sport/')) return false;
    return true;
  }).toList(growable: false);
}

/// Build the league catalog (grouped by sport) locally from the registry —
/// replaces the worker's /v1/catalog. Mirrors worker/src/catalog.js. Returns the
/// same JSON shape the app's CatalogSport.fromJson consumes:
///   [ { sport, leagues: [ { key, league, name, leagueId, abbr, region,
///                           priority, hasTeams, competitorKind, rankings? } ] } ]
List<Map<String, dynamic>> buildCatalog(Registry reg,
    {Object? priority, String? sport}) {
  final bySport = <String, List<Map<String, dynamic>>>{};
  for (final key in leagueKeys(reg, priority: priority, sport: sport)) {
    final p = reg.leagues[key] as Map;
    final prof = resolve(reg, key);
    final parts = key.split('/');
    final sportKey = parts[0];
    final league = parts.length > 1 ? parts[1] : '';
    final hasTeams = prof['hasTeams'] != null
        ? prof['hasTeams'] == true
        : prof['competitorKind'] == 'team';
    (bySport[sportKey] ??= []).add({
      'key': key,
      'league': league,
      'name': p['name'],
      'leagueId': p['espnLeagueId'],
      'abbr': p['abbr'],
      'region': p['region'],
      'priority': p['priority'],
      'hasTeams': hasTeams,
      'competitorKind': prof['competitorKind'],
      if (prof['rankingsFeed'] != null) 'rankings': prof['rankingsFeed'],
    });
  }
  return bySport.entries
      .map((e) => {'sport': e.key, 'leagues': e.value})
      .toList(growable: false);
}
