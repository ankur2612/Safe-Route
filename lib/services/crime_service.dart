import 'package:latlong2/latlong.dart';

import '../data/mock_data.dart';
import '../models/crime_incident_model.dart';
import '../models/heatmap_point_model.dart';
import '../utils/app_config.dart';
import '../utils/json_parsing.dart';
import 'api_client.dart';

/// Reads historical crime records and heatmap cells from the backend.
///
/// Requests are always bounded by an area so the full dataset is never
/// downloaded to the device.
class CrimeService {
  CrimeService({ApiClient? client, this.useMockData = AppConfig.useMockData})
      : _client = client ?? ApiClient();

  final ApiClient _client;
  final bool useMockData;

  /// `GET /api/v1/crimes` - historical incidents near a point.
  Future<List<CrimeIncidentModel>> fetchCrimes({
    required LatLng center,
    double radiusKm = 3,
    int limit = 200,
  }) async {
    if (useMockData) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      return MockData.crimes(center);
    }

    final Map<String, dynamic> json = await _client.get(
      '/crimes',
      query: <String, String>{
        'latitude': center.latitude.toString(),
        'longitude': center.longitude.toString(),
        'radius_km': radiusKm.toString(),
        'limit': limit.toString(),
      },
    );

    return _parseCrimes(json);
  }

  /// `POST /api/v1/crimes/route` - historical incidents within the corridor
  /// the backend uses for the route's risk score.
  ///
  /// The sample data has no records along routes, so it returns none rather
  /// than inventing them.
  Future<List<CrimeIncidentModel>> fetchRouteCrimes({
    required List<LatLng> points,
    int limit = 150,
  }) async {
    if (useMockData || points.length < 2) return const <CrimeIncidentModel>[];

    final Map<String, dynamic> json = await _client.post(
      '/crimes/route',
      body: <String, dynamic>{
        'geometry': <List<double>>[
          for (final LatLng point in points)
            <double>[point.latitude, point.longitude],
        ],
        'limit': limit,
      },
    );
    return _parseCrimes(json);
  }

  List<CrimeIncidentModel> _parseCrimes(Map<String, dynamic> json) {
    final List<Map<String, dynamic>> raw = asMapList(json['crimes'] ?? json['items']);
    final List<CrimeIncidentModel> crimes = <CrimeIncidentModel>[];
    for (int i = 0; i < raw.length; i++) {
      final CrimeIncidentModel? incident =
          CrimeIncidentModel.fromJson(raw[i], index: i);
      if (incident != null) crimes.add(incident);
    }
    return crimes;
  }

  /// `GET /api/v1/crimes/heatmap` - aggregated exposure cells for an area.
  Future<List<HeatmapPointModel>> fetchHeatmap({
    required LatLng center,
    double radiusKm = 4,
  }) async {
    if (useMockData) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      return MockData.heatmap(center);
    }

    final Map<String, dynamic> json = await _client.get(
      '/crimes/heatmap',
      query: <String, String>{
        'latitude': center.latitude.toString(),
        'longitude': center.longitude.toString(),
        'radius_km': radiusKm.toString(),
      },
    );

    return asMapList(json['points'] ?? json['items'])
        .map(HeatmapPointModel.fromJson)
        .whereType<HeatmapPointModel>()
        .toList(growable: false);
  }

  void dispose() => _client.dispose();
}
