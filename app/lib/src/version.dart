/// The running build's identity, baked at compile time.
///
/// Populated by `--dart-define` in `.github/workflows/release.yml`:
/// `CLIENT_VERSION_CODE` is the GitHub Actions `run_number` — the SAME value that
/// becomes the APK's `versionCode` (`--build-number`), so what the app *reports*
/// and what's *installed* match by construction. `CLIENT_VERSION_NAME` is the git
/// tag (e.g. `0.3.1`).
///
/// A plain `flutter run` / `flutter test` leaves the defaults — `0` / `'dev'`, an
/// honest "unknown/dev" the worker can ignore and the update gate treats as
/// never-nag (see `updateTierProvider`). No `package_info_plus`: a compile-time
/// const is zero-dependency and can't drift from the build number.
library;

/// Monotonic build number. The update gate compares against this (never the
/// semver name). `0` = a local/dev build.
const int kClientVersionCode =
    int.fromEnvironment('CLIENT_VERSION_CODE', defaultValue: 0);

/// Human-facing version (the git tag). Shown in the update banner; not used for
/// comparison.
const String kClientVersionName =
    String.fromEnvironment('CLIENT_VERSION_NAME', defaultValue: 'dev');
