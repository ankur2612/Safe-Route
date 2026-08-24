import 'package:latlong2/latlong.dart';

import '../utils/json_parsing.dart';
import 'risk_model.dart';

/// One segment of a route, with its own estimated risk.
///
/// Used to colour parts of a route line and to show where the higher
/// exposure along a route actually sits.
class RouteSegmentModel {
  const RouteSegmentModel({
    required this.points,
    required this.risk,
    this.label,
  });

  final List<LatLng> points;
  final RiskModel risk;
  final String? label;

  static RouteSegmentModel? fromJson(Map<String, dynamic> json) {
    final List<LatLng> points = parseGeometry(json['geometry'] ?? json['points']);
    if (points.isEmpty) return null;

    return RouteSegmentModel(
      points: points,
      risk: RiskModel.fromJson(asMap(json['risk']) ?? json),
      label: asText(json['label']) ?? asText(json['name']),
    );
  }
}

/// A single route option returned by `POST /api/v1/routes`.
class RouteModel {
  const RouteModel({
    required this.id,
    required this.name,
    required this.durationMinutes,
    required this.distanceKm,
    required this.points,
    required this.risk,
    this.segments = const <RouteSegmentModel>[],
  });

  final String id;

  /// Short label such as "Route A".
  final String name;

  final int durationMinutes;
  final double distanceKm;

  /// Full route geometry drawn on the map.
  final List<LatLng> points;

  final RiskModel risk;
  final List<RouteSegmentModel> segments;

  static RouteModel? fromJson(Map<String, dynamic> json, {int index = 0}) {
    final List<LatLng> points = parseGeometry(json['geometry'] ?? json['points']);
    if (points.isEmpty) return null;

    final int? duration = asInt(json['duration_minutes']) ??
        _secondsToMinutes(asDouble(json['duration']));
    final double? distance = asDouble(json['distance_km']) ??
        _metresToKm(asDouble(json['distance']));

    if (duration == null || distance == null) return null;

    return RouteModel(
      id: asText(json['id']) ?? 'route-$index',
      name: asText(json['name']) ?? 'Route ${_letterFor(index)}',
      durationMinutes: duration,
      distanceKm: distance,
      points: points,
      risk: RiskModel.fromJson(asMap(json['risk']) ?? const <String, dynamic>{}),
      segments: asMapList(json['segments'])
          .map(RouteSegmentModel.fromJson)
          .whereType<RouteSegmentModel>()
          .toList(growable: false),
    );
  }

  /// Returns a copy carrying updated risk information, used when
  /// `POST /api/v1/risk/route` is called separately from route generation.
  RouteModel copyWithRisk(RiskModel updated) => RouteModel(
        id: id,
        name: name,
        durationMinutes: durationMinutes,
        distanceKm: distanceKm,
        points: points,
        risk: updated,
        segments: segments,
      );

  String get durationLabel => '$durationMinutes min';

  String get distanceLabel => '${distanceKm.toStringAsFixed(1)} km';

  static int? _secondsToMinutes(double? seconds) =>
      seconds == null ? null : (seconds / 60).round();

  static double? _metresToKm(double? metres) =>
      metres == null ? null : metres / 1000;

  static String _letterFor(int index) =>
      String.fromCharCode(65 + (index % 26));
}

/// Parses route geometry into map points.
///
/// Accepts both `[[lat, lon], ...]` and `[{"lat": .., "lon": ..}, ...]`
/// because the exact OSRM passthrough format is a backend decision.
/// Malformed entries are skipped rather than aborting the whole route.
List<LatLng> parseGeometry(Object? raw) {
  if (raw is! List) return const <LatLng>[];

  final List<LatLng> points = <LatLng>[];
  for (final Object? entry in raw) {
    if (entry is List && entry.length >= 2) {
      final double? lat = asDouble(entry[0]);
      final double? lon = asDouble(entry[1]);
      if (lat != null && lon != null) points.add(LatLng(lat, lon));
    } else {
      final Map<String, dynamic>? map = asMap(entry);
      if (map == null) continue;
      final double? lat = asDouble(map['lat'] ?? map['latitude']);
      final double? lon = asDouble(map['lon'] ?? map['lng'] ?? map['longitude']);
      if (lat != null && lon != null) points.add(LatLng(lat, lon));
    }
  }
  return points;
}
