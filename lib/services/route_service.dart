import 'package:latlong2/latlong.dart';

import '../data/mock_data.dart';
import '../models/recommendation_model.dart';
import '../models/risk_model.dart';
import '../models/route_model.dart';
import '../models/route_preference.dart';
import '../utils/app_config.dart';
import '../utils/json_parsing.dart';
import 'api_client.dart';

/// Talks to the routing and risk endpoints.
///
/// All route generation and risk calculation happens on the backend. This
/// class only sends the request and parses the reply.
class RouteService {
  RouteService({ApiClient? client, this.useMockData = AppConfig.useMockData})
      : _client = client ?? ApiClient();

  final ApiClient _client;
  final bool useMockData;

  /// `POST /api/v1/routes` - generate and evaluate route options.
  Future<RouteResultModel> generateRoutes({
    required LatLng start,
    required LatLng destination,
    required RoutePreference preference,
  }) async {
    if (useMockData) {
      // Sample data path: brief delay so loading states are visible.
      await Future<void>.delayed(const Duration(milliseconds: 900));
      return MockData.routes(
        start: start,
        destination: destination,
        preference: preference,
      );
    }

    final Map<String, dynamic> json = await _client.post(
      '/routes',
      body: <String, dynamic>{
        'start': <String, double>{
          'latitude': start.latitude,
          'longitude': start.longitude,
        },
        'destination': <String, double>{
          'latitude': destination.latitude,
          'longitude': destination.longitude,
        },
        'preference': preference.apiValue,
      },
    );

    return RouteResultModel.fromJson(json);
  }

  /// `POST /api/v1/risk/route` - risk for one already-generated route.
  ///
  /// Used when the backend returns routes without risk attached, or when the
  /// user changes preference and only the risk view needs refreshing.
  Future<RiskModel> calculateRouteRisk(RouteModel route) async {
    if (useMockData) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      return route.risk;
    }

    final Map<String, dynamic> json = await _client.post(
      '/risk/route',
      body: <String, dynamic>{
        'route_id': route.id,
        'geometry': <List<double>>[
          for (final LatLng point in route.points)
            <double>[point.latitude, point.longitude],
        ],
      },
    );

    return RiskModel.fromJson(asMap(json['risk']) ?? json);
  }

  void dispose() => _client.dispose();
}
