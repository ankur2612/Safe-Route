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
    this.locality,
    this.category,
    this.placeId,
    this.crimeDataAvailable,
  });

  /// Display name, e.g. "Koramangala 6th Block".
  final String name;

  /// Secondary line shown under the name, e.g. "Sarjapur Road, Bengaluru".
  final String? address;

  /// Neighbourhood or district the place belongs to, when known.
  final String? locality;

  /// Kind of place, e.g. "suburb", "station", "primary" (a main road).
  final String? category;

  /// Geocoder identifier, e.g. "osm:N123".
  final String? placeId;

  /// Whether SafeRoute has crime data here (Bengaluru only). Null when the
  /// backend did not say. Places without it can still be routed to, but get
  /// no crime-risk estimate.
  final bool? crimeDataAvailable;

  final double latitude;
  final double longitude;

  LatLng get latLng => LatLng(latitude, longitude);

  /// Returns null when the payload has no usable coordinates, so callers can
  /// drop the entry instead of placing a marker at (0, 0).
  static LocationModel? fromJson(Map<String, dynamic> json) {
    final double? lat = asDouble(json['latitude'] ?? json['lat']);
    final double? lon = asDouble(json['longitude'] ?? json['lon'] ?? json['lng']);
    if (lat == null || lon == null) return null;
    if (!lat.isFinite || !lon.isFinite || lat.abs() > 90 || lon.abs() > 180) {
      return null;
    }

    return LocationModel(
      name: asText(json['name']) ?? asText(json['display_name']) ?? 'Unnamed place',
      address: asText(json['address']) ?? asText(json['region']),
      locality: asText(json['locality']),
      category: asText(json['category']),
      placeId: asText(json['place_id']),
      crimeDataAvailable: json['crime_data_available'] is bool
          ? json['crime_data_available'] as bool
          : null,
      latitude: lat,
      longitude: lon,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        if (address != null) 'address': address,
        if (locality != null) 'locality': locality,
        if (category != null) 'category': category,
        if (placeId != null) 'place_id': placeId,
        if (crimeDataAvailable != null)
          'crime_data_available': crimeDataAvailable,
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
