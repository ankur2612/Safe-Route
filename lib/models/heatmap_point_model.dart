import 'package:latlong2/latlong.dart';

import '../utils/json_parsing.dart';
import 'risk_model.dart';

/// One cell of the historical crime exposure heatmap, from
/// `GET /api/v1/crimes/heatmap`.
///
/// The backend decides the exposure banding; the app only draws it.
class HeatmapPointModel {
  const HeatmapPointModel({
    required this.latitude,
    required this.longitude,
    required this.exposure,
    this.intensity,
  });

  final double latitude;
  final double longitude;

  /// Lower / medium / higher historical crime exposure for this cell.
  final RiskLevel exposure;

  /// Optional 0..1 weight used to vary the circle opacity.
  final double? intensity;

  LatLng get latLng => LatLng(latitude, longitude);

  static HeatmapPointModel? fromJson(Map<String, dynamic> json) {
    final double? lat = asDouble(json['latitude'] ?? json['lat']);
    final double? lon = asDouble(json['longitude'] ?? json['lon'] ?? json['lng']);
    if (lat == null || lon == null) return null;

    final double? weight = asDouble(json['intensity'] ?? json['weight']);

    return HeatmapPointModel(
      latitude: lat,
      longitude: lon,
      exposure: RiskModel.parseLevel(json['exposure'] ?? json['level']),
      intensity: weight?.clamp(0.0, 1.0).toDouble(),
    );
  }
}
