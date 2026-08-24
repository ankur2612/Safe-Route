import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models/location_model.dart';
import '../models/recommendation_model.dart';
import '../models/route_model.dart';
import '../models/route_preference.dart';
import '../services/api_exception.dart';
import '../services/route_service.dart';

/// Where the route request currently stands.
enum RouteStatus { idle, loading, success, empty, error }

/// Holds the destination, route options and the backend's recommendation.
///
/// No risk calculation happens here. The provider stores what the backend
/// returned and tracks which route the user is looking at.
class RouteProvider extends ChangeNotifier {
  RouteProvider({RouteService? service})
      : _service = service ?? RouteService();

  final RouteService _service;

  RouteStatus _status = RouteStatus.idle;
  RouteStatus get status => _status;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  LocationModel? _destination;
  LocationModel? get destination => _destination;

  LatLng? _start;
  LatLng? get start => _start;

  List<RouteModel> _routes = const <RouteModel>[];
  List<RouteModel> get routes => _routes;

  RecommendationModel? _recommendation;
  RecommendationModel? get recommendation => _recommendation;

  RoutePreference _preference = RoutePreference.balanced;
  RoutePreference get preference => _preference;

  String? _selectedRouteId;

  bool get hasRoutes => _routes.isNotEmpty;

  bool get isLoading => _status == RouteStatus.loading;

  /// The route the user is currently viewing. Defaults to the recommended
  /// route so the screen opens on the backend's suggestion.
  RouteModel? get selectedRoute {
    if (_routes.isEmpty) return null;
    for (final RouteModel route in _routes) {
      if (route.id == _selectedRouteId) return route;
    }
    return recommendedRoute ?? _routes.first;
  }

  RouteModel? get recommendedRoute {
    final RecommendationModel? rec = _recommendation;
    if (rec == null) return null;
    for (final RouteModel route in _routes) {
      if (route.id == rec.routeId) return route;
    }
    return null;
  }

  bool isRecommended(RouteModel route) => recommendedRoute?.id == route.id;

  /// The fastest option, used to label route cards. This is a display
  /// convenience over values the backend already sent, not a risk decision.
  RouteModel? get fastestRoute {
    if (_routes.isEmpty) return null;
    return _routes.reduce(
      (RouteModel a, RouteModel b) =>
          b.durationMinutes < a.durationMinutes ? b : a,
    );
  }

  void selectRoute(String routeId) {
    if (_selectedRouteId == routeId) return;
    _selectedRouteId = routeId;
    notifyListeners();
  }

  /// Changing preference re-requests routes so the backend can pick the
  /// recommendation for that preference.
  Future<void> setPreference(RoutePreference preference) async {
    if (_preference == preference) return;
    _preference = preference;
    notifyListeners();

    final LatLng? start = _start;
    final LocationModel? destination = _destination;
    if (start != null && destination != null) {
      await findRoutes(start: start, destination: destination);
    }
  }

  Future<void> findRoutes({
    required LatLng start,
    required LocationModel destination,
  }) async {
    _start = start;
    _destination = destination;
    _status = RouteStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final RouteResultModel result = await _service.generateRoutes(
        start: start,
        destination: destination.latLng,
        preference: _preference,
      );

      _routes = result.routes;
      _recommendation = result.recommendation;
      // Reset the selection so the new recommendation is shown first.
      _selectedRouteId = result.recommendedRoute?.id ??
          (result.routes.isEmpty ? null : result.routes.first.id);
      _status = result.isEmpty ? RouteStatus.empty : RouteStatus.success;
    } on ApiException catch (error) {
      _status = RouteStatus.error;
      _errorMessage = error.message;
      _routes = const <RouteModel>[];
      _recommendation = null;
      _selectedRouteId = null;
    } catch (_) {
      _status = RouteStatus.error;
      _errorMessage = 'Could not generate routes right now.';
      _routes = const <RouteModel>[];
      _recommendation = null;
      _selectedRouteId = null;
    }

    notifyListeners();
  }

  /// Retries the last request, used by the error state's "Try Again" action.
  Future<void> retry() async {
    final LatLng? start = _start;
    final LocationModel? destination = _destination;
    if (start == null || destination == null) return;
    await findRoutes(start: start, destination: destination);
  }

  /// Clears the destination and returns the map to its browsing state.
  void clearRoutes() {
    _routes = const <RouteModel>[];
    _recommendation = null;
    _selectedRouteId = null;
    _destination = null;
    _status = RouteStatus.idle;
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}
