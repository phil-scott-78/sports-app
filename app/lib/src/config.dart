/// App-wide constants. The worker base URL is set by the user in Settings
/// (persisted), so this only holds defaults. Mirrors v1's config so both apps
/// speak to the same worker with the same cadences.
class AppConfig {
  /// Default worker URL — used on a fresh install so the app works out of the
  /// box. A previously-saved URL always wins. Overridable per-run for dev
  /// against the offline mock: `flutter run --dart-define=WORKER_URL=http://localhost:8787`.
  static const String defaultBaseUrl = String.fromEnvironment('WORKER_URL',
      defaultValue: 'https://api.scores.philco.dev');

  /// Leagues followed on first run (until the user customizes in Following).
  static const List<String> defaultFollowed = [
    'soccer/fifa.world',
    'baseball/mlb',
    'basketball/nba',
  ];

  /// Poll cadence: fast while a game is live, slow when idle (matches the
  /// worker's 15s/5m cache TTLs and respects battery).
  static const Duration refreshLive = Duration(seconds: 15);
  static const Duration refreshIdle = Duration(seconds: 60);

  /// Near-kickoff cadence + lookahead. When a followed/visible scheduled game is
  /// within [kickoffWindow] of kickoff (either side — approaching, or just
  /// started while ESPN still says 'pre'), poll at [refreshNearKickoff] instead
  /// of the 60s idle cadence so the idle→live flip isn't hidden for a whole idle
  /// window at the most-watched moment. Mirrors the worker's TTL.soon / idleTtl.
  static const Duration refreshNearKickoff = Duration(seconds: 30);
  static const Duration kickoffWindow = Duration(minutes: 5);

  /// Per-request network timeout.
  static const Duration httpTimeout = Duration(seconds: 12);
}
