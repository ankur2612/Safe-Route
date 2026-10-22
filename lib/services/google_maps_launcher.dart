import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a URL in the given mode. Matches `launchUrl`, injectable for tests.
typedef UrlOpener = Future<bool> Function(Uri uri, LaunchMode mode);

enum MapsLaunchResult {
  /// Opened in the Google Maps app, or the browser if the app is missing.
  opened,

  /// The external launch failed and the in-app browser was used instead.
  openedFallback,

  /// No valid start or destination, so nothing was opened.
  missingCoordinates,

  /// Nothing on the device could open the link.
  failed,
}

/// Hands a SafeRoute route over to Google Maps for turn-by-turn directions.
///
/// Google Maps calculates its own route. A few points from SafeRoute's
/// geometry are sent as waypoints so it follows the same corridor, but it may
/// still pick different roads, and SafeRoute's risk estimate applies only to
/// the route SafeRoute calculated.
class GoogleMapsLauncher {
  const GoogleMapsLauncher({UrlOpener? open}) : _open = open ?? _launch;

  final UrlOpener _open;

  static Future<bool> _launch(Uri uri, LaunchMode mode) =>
      launchUrl(uri, mode: mode);

  /// Google Maps accepts at most three waypoints when the link opens in a
  /// mobile browser, so never send more.
  static const int maxWaypoints = 3;

  /// Routes shorter than this go without waypoints; the endpoints are enough.
  static const double _minWaypointRouteMeters = 2000;

  /// Builds a Google Maps directions URL (Maps URLs API), or null when a
  /// coordinate is missing or invalid. Coordinates are used instead of place
  /// names so Google Maps cannot resolve the name to a different place.
  static Uri? directionsUri({
    required LatLng? origin,
    required LatLng? destination,
    List<LatLng> routePoints = const <LatLng>[],
  }) {
    if (origin == null || destination == null) return null;
    if (!_isValid(origin) || !_isValid(destination)) return null;

    final List<LatLng> waypoints = sampleWaypoints(routePoints);
    return Uri.https('www.google.com', '/maps/dir/', <String, String>{
      'api': '1',
      'origin': _format(origin),
      'destination': _format(destination),
      'travelmode': 'driving',
      if (waypoints.isNotEmpty) 'waypoints': waypoints.map(_format).join('|'),
    });
  }

  /// Points at even distances along the route (a quarter, half and three
  /// quarters of the way), taken from the route's own geometry so each one
  /// lies on a road SafeRoute actually used.
  static List<LatLng> sampleWaypoints(List<LatLng> points) {
    final List<LatLng> valid = points.where(_isValid).toList(growable: false);
    if (valid.length < 3) return const <LatLng>[];

    const Distance distance = Distance();
    final List<double> along = <double>[0];
    for (int i = 1; i < valid.length; i++) {
      along.add(
        along.last + distance.as(LengthUnit.Meter, valid[i - 1], valid[i]),
      );
    }
    final double total = along.last;
    if (total < _minWaypointRouteMeters) return const <LatLng>[];

    final List<LatLng> picked = <LatLng>[];
    int index = 0;
    for (int k = 1; k <= maxWaypoints; k++) {
      final double target = total * k / (maxWaypoints + 1);
      while (index < valid.length - 1 && along[index] < target) {
        index++;
      }
      // Never the endpoints themselves, and never the same point twice.
      if (index > 0 &&
          index < valid.length - 1 &&
          (picked.isEmpty || picked.last != valid[index])) {
        picked.add(valid[index]);
      }
    }
    return picked;
  }

  Future<MapsLaunchResult> openDirections({
    required LatLng? origin,
    required LatLng? destination,
    List<LatLng> routePoints = const <LatLng>[],
  }) async {
    final Uri? uri = directionsUri(
      origin: origin,
      destination: destination,
      routePoints: routePoints,
    );
    if (uri == null) return MapsLaunchResult.missingCoordinates;

    if (await _tryOpen(uri, LaunchMode.externalApplication)) {
      return MapsLaunchResult.opened;
    }
    if (await _tryOpen(uri, LaunchMode.platformDefault)) {
      return MapsLaunchResult.openedFallback;
    }
    return MapsLaunchResult.failed;
  }

  Future<bool> _tryOpen(Uri uri, LaunchMode mode) async {
    try {
      return await _open(uri, mode);
    } catch (_) {
      // PlatformException when no app can handle the link.
      return false;
    }
  }

  static bool _isValid(LatLng p) =>
      p.latitude.isFinite &&
      p.longitude.isFinite &&
      p.latitude.abs() <= 90 &&
      p.longitude.abs() <= 180;

  static String _format(LatLng p) =>
      '${p.latitude.toStringAsFixed(6)},${p.longitude.toStringAsFixed(6)}';
}
