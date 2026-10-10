import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../data/mock_data.dart';
import '../models/location_model.dart';
import '../utils/app_config.dart';
import '../utils/json_parsing.dart';
import 'api_client.dart';

/// Destination search against the backend.
class LocationSearchService {
  LocationSearchService({
    ApiClient? client,
    this.useMockData = AppConfig.useMockData,
  }) : _client = client ?? ApiClient();

  final ApiClient _client;
  final bool useMockData;

  /// `GET /api/v1/locations/search`
  Future<List<LocationModel>> search(String query) async {
    final String trimmed = query.trim();
    if (trimmed.isEmpty) return const <LocationModel>[];

    if (useMockData) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      return MockData.searchPlaces(trimmed);
    }

    final Map<String, dynamic> json = await _client.get(
      '/locations/search',
      query: <String, String>{'q': trimmed},
    );

    return asMapList(json['results'] ?? json['items'])
        .map(LocationModel.fromJson)
        .whereType<LocationModel>()
        .toList(growable: false);
  }

  void dispose() => _client.dispose();
}

/// Why a location request failed, so the UI can offer the right action.
enum LocationErrorKind { serviceDisabled, permissionDenied, permanentlyDenied, failed }

class LocationException implements Exception {
  const LocationException(this.kind, this.message);

  final LocationErrorKind kind;
  final String message;

  @override
  String toString() => 'LocationException($kind): $message';
}

/// Wraps the device GPS. Permission handling lives here so screens only deal
/// with a position or a typed error.
class DeviceLocationService {
  const DeviceLocationService();

  Future<LatLng> getCurrentPosition() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationException(
        LocationErrorKind.serviceDisabled,
        'Location services are turned off on this device.',
      );
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(
        LocationErrorKind.permanentlyDenied,
        'Location access is needed to use your current position. '
        'You can enable it in your device settings.',
      );
    }

    if (permission == LocationPermission.denied) {
      throw const LocationException(
        LocationErrorKind.permissionDenied,
        'Location access is needed to use your current position.',
      );
    }

    try {
      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return LatLng(position.latitude, position.longitude);
    } on Exception {
      throw const LocationException(
        LocationErrorKind.failed,
        'Unable to get your location.',
      );
    }
  }

  /// Opens the OS settings screen so the user can grant permission after a
  /// permanent denial.
  Future<void> openSettings() => Geolocator.openAppSettings();
}

/// Centre of the supported area (Bengaluru), used before a GPS fix is
/// available or when the device is outside the area SafeRoute covers.
LatLng get developmentFallbackCenter => MockData.fallbackCenter;

/// Bounds of the area the backend has crime data and routing for.
const double _minLat = 12.70;
const double _maxLat = 13.30;
const double _minLon = 77.35;
const double _maxLon = 77.80;

/// True when [point] is inside the supported area (Bengaluru).
bool isInServiceArea(LatLng point) =>
    point.latitude >= _minLat &&
    point.latitude <= _maxLat &&
    point.longitude >= _minLon &&
    point.longitude <= _maxLon;

/// The position to use for the map and routing: the device position when it
/// is inside the supported area, otherwise the area's centre. This keeps the
/// app usable (and the backend from rejecting requests) when the user is
/// somewhere SafeRoute has no data for.
LatLng serviceAreaCenter(LatLng? position) =>
    position != null && isInServiceArea(position)
        ? position
        : developmentFallbackCenter;
