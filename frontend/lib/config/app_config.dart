/// Build-time configuration.
///
/// The API base URL is injected with `--dart-define`:
///
/// * Web (production build): `--dart-define=API_BASE_URL=` (empty = relative URLs,
///   uses nginx `/api/` reverse proxy — no CORS issues)
/// * Web / iOS simulator (local dev): `--dart-define=API_BASE_URL=http://localhost:8000`
/// * Android emulator:     `--dart-define=API_BASE_URL=http://10.0.2.2:8000`
///   (the emulator cannot reach the host's `localhost`; `10.0.2.2` is the
///   host loopback alias.)
///
/// Default is empty (relative URLs) so the production web build works with the
/// nginx reverse proxy at `/api/`. Local development must pass the flag explicitly.
class AppConfig {
  const AppConfig();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  /// Normalised base URL with no trailing slash.
  String get baseUrl =>
      apiBaseUrl.endsWith('/') ? apiBaseUrl.substring(0, apiBaseUrl.length - 1) : apiBaseUrl;
}
