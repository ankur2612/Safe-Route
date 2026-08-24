/// Runtime configuration for the app.
///
/// Values come from `--dart-define` so nothing environment-specific is
/// committed to source control. Example:
///
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
class AppConfig {
  const AppConfig._();

  /// Base URL of the SafeRoute FastAPI backend.
  ///
  /// Defaults to the Android emulator's alias for the host machine's
  /// localhost, which is the usual setup during development.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  /// When true the app serves sample data instead of calling the backend.
  /// Useful while the FastAPI service is still being built.
  static const bool useMockData = bool.fromEnvironment(
    'USE_MOCK_DATA',
    defaultValue: true,
  );

  static const String apiPrefix = '/api/v1';

  static const Duration requestTimeout = Duration(seconds: 20);

  /// Tile server for the map. OpenStreetMap matches the OSRM/OSM data the
  /// backend uses and needs no API key.
  static const String mapTileUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// Required by the OpenStreetMap tile usage policy.
  static const String mapUserAgentPackageName = 'com.saferoute.saferoute';
}
