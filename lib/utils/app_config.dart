import 'package:flutter/foundation.dart';

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
  ///
  /// On by default in debug builds only: a release build talks to the real
  /// backend unless sample data is requested explicitly, so the eight sample
  /// places never stand in for real search on a phone.
  static const bool useMockData = bool.fromEnvironment(
    'USE_MOCK_DATA',
    defaultValue: !kReleaseMode,
  );

  static const String apiPrefix = '/api/v1';

  static const Duration requestTimeout = Duration(seconds: 20);

  /// Destination search answers within the backend's geocoder timeout (5 s),
  /// so a much longer wait means the server is unreachable.
  static const Duration searchTimeout = Duration(seconds: 12);

  /// Hosts that only mean something on the development machine or its
  /// emulator. A phone cannot reach them.
  static const Set<String> developmentOnlyHosts = <String>{
    '10.0.2.2',
    'localhost',
    '127.0.0.1',
    '0.0.0.0',
  };

  /// Why [url] cannot work as the backend address, or null if it may.
  ///
  /// A release build left on the default `http://10.0.2.2:8000` (the
  /// emulator's alias for the development computer) can never reach the
  /// server from a phone; requests would hang and then fail as if the phone
  /// were offline.
  static String? apiBaseUrlProblem(String url, {bool releaseBuild = kReleaseMode}) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return 'This build has an invalid server address ("$url"). Rebuild it '
          'with --dart-define=API_BASE_URL=https://<your server>.';
    }
    if (releaseBuild && developmentOnlyHosts.contains(uri.host)) {
      return 'This build is not connected to a SafeRoute server: it points at '
          '${uri.host}, which only works from the development computer or its '
          'emulator. Rebuild it with '
          '--dart-define=API_BASE_URL=https://<your server>.';
    }
    return null;
  }

  /// Tile server for the map. OpenStreetMap matches the OSRM/OSM data the
  /// backend uses and needs no API key.
  static const String mapTileUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// Required by the OpenStreetMap tile usage policy.
  static const String mapUserAgentPackageName = 'com.saferoute.saferoute';
}
