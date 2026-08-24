import 'package:latlong2/latlong.dart';

import '../utils/json_parsing.dart';

/// A place the user can pick as a start or destination.
///
/// Returned by `GET /api/v1/locations/search`.
class LocationModel {
  const LocationModel({
    required this.name,
    required this.latitude,
    required this.longitude,
    this.address,
  });

  final String name;

  /// Secondary line shown under the name, e.g. "New Delhi".
  final String? address;

  final double latitude;
  final double longitude;

  LatLng get latLng => LatLng(latitude, longitude);

  /// Returns null when the payload has no usable coordinates, so callers can
  /// drop the entry instead of placing a marker at (0, 0).
  static LocationModel? fromJson(Map<String, dynamic> json) {
    final double? lat = asDouble(json['latitude'] ?? json['lat']);
    final double? lon = asDouble(json['longitude'] ?? json['lon'] ?? json['lng']);
    if (lat == null || lon == null) return null;

    return LocationModel(
      name: asText(json['name']) ?? asText(json['display_name']) ?? 'Unnamed place',
      address: asText(json['address']) ?? asText(json['region']),
      latitude: lat,
      longitude: lon,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        if (address != null) 'address': address,
        'latitude': latitude,
        'longitude': longitude,
      };

  /// Convenience for turning a device GPS fix into a location entry.
  factory LocationModel.currentLocation(LatLng point) => LocationModel(
        name: 'Current location',
        latitude: point.latitude,
        longitude: point.longitude,
      );
}
