/// App-wide constants. The worker base URL is set by the user in Settings
/// (persisted), so this only holds defaults.
class AppConfig {
  /// Seed for the Material 3 color scheme (a calm sport green).
  static const int seedColor = 0xFF12B886;

  /// Default worker URL — used on a fresh install so the app works out of the
  /// box. A previously-saved URL always wins; change it via the hidden editor on
  /// the Settings → About row (tap it 6 times).
  static const String defaultBaseUrl = 'https://sports-scores.philco.workers.dev';

  /// Leagues followed on first run (until the user customizes in Leagues tab).
  static const List<String> defaultFollowed = [
    'soccer/fifa.world',
    'baseball/mlb',
    'basketball/nba',
  ];

  /// Poll cadence: fast while a game is live, slow when idle (matches the
  /// worker's 15s/5m cache TTLs and respects battery).
  static const Duration refreshLive = Duration(seconds: 15);
  static const Duration refreshIdle = Duration(seconds: 60);

  /// How many future days the "Upcoming" date strip offers (starting tomorrow).
  /// A week so weekly leagues (NFL) stay reachable; each picked day is a single
  /// `dates=YYYYMMDD` fetch, not a week-long range.
  static const int upcomingDays = 7;

  /// Per-request network timeout.
  static const Duration httpTimeout = Duration(seconds: 12);
}
