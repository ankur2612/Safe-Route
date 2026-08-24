import 'package:latlong2/latlong.dart';

import '../utils/json_parsing.dart';

/// A historical crime record from `GET /api/v1/crimes`.
///
/// These are past records only. The UI must never present them as a
/// statement about current conditions at a location.
class CrimeIncidentModel {
  const CrimeIncidentModel({
    required this.id,
    required this.type,
    required this.latitude,
    required this.longitude,
    this.date,
    this.area,
    this.description,
  });

  final String id;
  final String type;
  final double latitude;
  final double longitude;
  final DateTime? date;
  final String? area;
  final String? description;

  LatLng get latLng => LatLng(latitude, longitude);

  static CrimeIncidentModel? fromJson(Map<String, dynamic> json, {int index = 0}) {
    final double? lat = asDouble(json['latitude'] ?? json['lat']);
    final double? lon = asDouble(json['longitude'] ?? json['lon'] ?? json['lng']);
    if (lat == null || lon == null) return null;

    return CrimeIncidentModel(
      id: asText(json['id']) ?? 'incident-$index',
      type: asText(json['type']) ?? asText(json['crime_type']) ?? 'Unspecified',
      latitude: lat,
      longitude: lon,
      date: _parseDate(json['date'] ?? json['occurred_at']),
      area: asText(json['area']) ?? asText(json['district']),
      description: asText(json['description']),
    );
  }

  static DateTime? _parseDate(Object? raw) {
    final String? text = asText(raw);
    if (text == null) return null;
    return DateTime.tryParse(text);
  }

  /// Human-readable date, e.g. "12 May 2024". Falls back to the year alone
  /// when the backend only stored a year.
  String get dateLabel {
    final DateTime? value = date;
    if (value == null) return 'Date not recorded';
    return '${value.day} ${_monthNames[value.month - 1]} ${value.year}';
  }

  static const List<String> _monthNames = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
}
