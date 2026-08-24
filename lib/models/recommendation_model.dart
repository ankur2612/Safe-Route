import '../utils/json_parsing.dart';
import 'route_model.dart';

/// The backend's recommended route for the selected preference.
///
/// The reason text comes from the backend so the wording stays consistent
/// with the Risk Engine's own explanation.
class RecommendationModel {
  const RecommendationModel({
    required this.routeId,
    this.reason,
  });

  final String routeId;
  final String? reason;

  static RecommendationModel? fromJson(Map<String, dynamic> json) {
    final String? id = asText(json['route_id']) ?? asText(json['id']);
    if (id == null) return null;
    return RecommendationModel(
      routeId: id,
      reason: asText(json['reason']) ?? asText(json['explanation']),
    );
  }
}

/// Route generation result: the options plus which one the backend
/// recommends for the requested preference.
class RouteResultModel {
  const RouteResultModel({
    required this.routes,
    this.recommendation,
  });

  final List<RouteModel> routes;
  final RecommendationModel? recommendation;

  bool get isEmpty => routes.isEmpty;

  /// The recommended route, or null when the backend did not name one or
  /// named an id that is not in the list.
  RouteModel? get recommendedRoute {
    final RecommendationModel? rec = recommendation;
    if (rec == null) return null;
    for (final RouteModel route in routes) {
      if (route.id == rec.routeId) return route;
    }
    return null;
  }

  factory RouteResultModel.fromJson(Map<String, dynamic> json) {
    final List<RouteModel> routes = <RouteModel>[];
    final List<Map<String, dynamic>> rawRoutes = asMapList(json['routes']);
    for (int i = 0; i < rawRoutes.length; i++) {
      final RouteModel? route = RouteModel.fromJson(rawRoutes[i], index: i);
      if (route != null) routes.add(route);
    }

    final Map<String, dynamic>? rawRec = asMap(json['recommendation']);

    return RouteResultModel(
      routes: routes,
      recommendation:
          rawRec == null ? null : RecommendationModel.fromJson(rawRec),
    );
  }
}
