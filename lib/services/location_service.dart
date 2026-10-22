import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../data/mock_data.dart';
import '../models/location_model.dart';
import '../utils/app_config.dart';
import '../utils/json_parsing.dart';
import 'api_client.dart';
import 'api_exception.dart';

/// Trims and collapses runs of whitespace, so "  HSR   Layout " and
/// "HSR Layout" are the same search.
String normalizeSearchQuery(String query) =>
    query.trim().split(RegExp(r'\s+')).where((String w) => w.isNotEmpty).join(' ');

/// One answer from [LocationSearchService.search].
class LocationSearchResult {
  const LocationSearchResult(this.places, {this.degraded = false});

  final List<LocationModel> places;

  /// True when the geocoding provider failed and the backend answered from
  /// its short built-in list instead, so results are incomplete.
  final bool degraded;
}

/// Destination search against the backend, which covers all of India.
///
/// Recent answers are kept for a few minutes so retyping or deleting a
/// character does not repeat a request the backend has just answered.
class LocationSearchService {
  LocationSearchService({
    ApiClient? client,
    this.useMockData = AppConfig.useMockData,
    DateTime Function()? clock,
  })  : _client = client ?? ApiClient(),
        _clock = clock ?? DateTime.now;

  final ApiClient _client;
  final bool useMockData;
  final DateTime Function() _clock;

  /// Shorter queries are not sent; the geocoder rejects single characters.
  static const int minQueryLength = 2;

  static const int _cacheSize = 40;
  static const Duration _cacheTtl = Duration(minutes: 10);

  /// Insertion-ordered, so the first key is the least recently used.
  final Map<String, _CachedSearch> _cache = <String, _CachedSearch>{};

  /// `GET /api/v1/locations/search`
  ///
  /// [near] (usually the user's position) ranks nearby places first; results
  /// still cover all of India.
  Future<LocationSearchResult> search(String query, {LatLng? near}) async {
    final String normalized = normalizeSearchQuery(query);
    if (normalized.replaceAll(' ', '').length < minQueryLength) {
      return const LocationSearchResult(<LocationModel>[]);
    }

    // Position rounded to ~50 km so small movements reuse the cache.
    final String key = near == null
        ? normalized.toLowerCase()
        : '${normalized.toLowerCase()}|'
            '${(near.latitude * 2).round()},${(near.longitude * 2).round()}';
    final _CachedSearch? cached = _cache.remove(key);
    if (cached != null && _clock().difference(cached.storedAt) < _cacheTtl) {
      _cache[key] = cached;
      return LocationSearchResult(cached.results);
    }

    final LocationSearchResult result = await _fetch(normalized, near);
    // A degraded answer is not cached, so the next search can get full results.
    if (!result.degraded) {
      _cache[key] = _CachedSearch(result.places, _clock());
      if (_cache.length > _cacheSize) _cache.remove(_cache.keys.first);
    }
    return result;
  }

  Future<LocationSearchResult> _fetch(String query, LatLng? near) async {
    if (useMockData) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      return LocationSearchResult(MockData.searchPlaces(query));
    }

    final Map<String, dynamic> json = await _client.get(
      '/locations/search',
      query: <String, String>{
        'q': query,
        if (near != null) 'latitude': near.latitude.toStringAsFixed(4),
        if (near != null) 'longitude': near.longitude.toStringAsFixed(4),
      },
      timeout: AppConfig.searchTimeout,
    );
    if (json['results'] is! List && json['items'] is! List) {
      // Not a search response at all (wrong server or path): an error, not
      // "no locations found".
      throw const ApiException.badResponse();
    }

    return LocationSearchResult(
      asMapList(json['results'] ?? json['items'])
          .map(LocationModel.fromJson)
          .whereType<LocationModel>()
          .toList(growable: false),
      degraded: json['degraded'] == true,
    );
  }

  void dispose() => _client.dispose();
}

class _CachedSearch {
  const _CachedSearch(this.results, this.storedAt);

  final List<LocationModel> results;
  final DateTime storedAt;
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

/// Bounds of the area the backend has crime data (and risk estimates) for.
/// Search and routing reach further; see [LocationModel.crimeDataAvailable].
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
