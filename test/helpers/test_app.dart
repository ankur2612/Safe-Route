import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:saferoute/models/crime_incident_model.dart';
import 'package:saferoute/models/heatmap_point_model.dart';
import 'package:saferoute/models/location_model.dart';
import 'package:saferoute/models/recommendation_model.dart';
import 'package:saferoute/models/risk_model.dart';
import 'package:saferoute/models/route_model.dart';
import 'package:saferoute/models/route_preference.dart';
import 'package:saferoute/services/crime_service.dart';
import 'package:saferoute/services/location_service.dart';
import 'package:saferoute/services/route_service.dart';
import 'package:saferoute/utils/app_theme.dart';

/// Wraps a widget in the app's theme so tests exercise the real styling.
Widget wrapForTest(Widget child) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

/// Builds a route with sensible defaults so tests only state what matters.
RouteModel buildRoute({
  String id = 'route-a',
  String name = 'Route A',
  int durationMinutes = 15,
  double distanceKm = 5.2,
  RiskLevel risk = RiskLevel.low,
  String? reason,
}) {
  return RouteModel(
    id: id,
    name: name,
    durationMinutes: durationMinutes,
    distanceKm: distanceKm,
    points: const <LatLng>[LatLng(28.61, 77.21), LatLng(28.63, 77.23)],
    risk: RiskModel(level: risk, reason: reason),
  );
}

const LocationModel testDestination = LocationModel(
  name: 'India Gate',
  address: 'New Delhi',
  latitude: 28.6129,
  longitude: 77.2295,
);

/// A [RouteService] that returns canned results, so tests never touch the
/// network or the sample-data delays.
class FakeRouteService implements RouteService {
  FakeRouteService({
    this.result,
    this.error,
    this.risk,
  });

  /// Result to return from [generateRoutes]. Ignored when [error] is set.
  RouteResultModel? result;

  /// When set, [generateRoutes] throws this instead of returning.
  Object? error;

  RiskModel? risk;

  /// Preferences seen by [generateRoutes], in call order.
  final List<RoutePreference> requestedPreferences = <RoutePreference>[];

  int generateCallCount = 0;
  bool disposed = false;

  @override
  bool get useMockData => true;

  @override
  Future<RouteResultModel> generateRoutes({
    required LatLng start,
    required LatLng destination,
    required RoutePreference preference,
  }) async {
    generateCallCount++;
    requestedPreferences.add(preference);

    final Object? failure = error;
    if (failure != null) throw failure;

    return result ??
        const RouteResultModel(routes: <RouteModel>[]);
  }

  @override
  Future<RiskModel> calculateRouteRisk(RouteModel route) async {
    return risk ?? route.risk;
  }

  @override
  void dispose() => disposed = true;
}

/// A [LocationSearchService] returning canned results for the search screen.
class FakeLocationSearchService implements LocationSearchService {
  FakeLocationSearchService({this.results = const <LocationModel>[], this.error});

  List<LocationModel> results;

  /// When set, [search] throws this instead of returning results.
  Object? error;

  final List<String> queries = <String>[];

  @override
  bool get useMockData => true;

  @override
  Future<List<LocationModel>> search(String query) async {
    queries.add(query);
    final Object? failure = error;
    if (failure != null) throw failure;
    return results;
  }

  @override
  void dispose() {}
}

/// A [DeviceLocationService] that returns a fixed position or a typed error,
/// so tests never touch real GPS or permission dialogs.
class FakeDeviceLocationService implements DeviceLocationService {
  FakeDeviceLocationService({this.position, this.error});

  LatLng? position;
  LocationException? error;

  int openSettingsCount = 0;

  @override
  Future<LatLng> getCurrentPosition() async {
    final LocationException? failure = error;
    if (failure != null) throw failure;
    return position ?? const LatLng(12.9716, 77.5946);
  }

  @override
  Future<void> openSettings() async => openSettingsCount++;
}

/// A [CrimeService] returning canned crime layers.
class FakeCrimeService implements CrimeService {
  FakeCrimeService({
    this.incidents = const <CrimeIncidentModel>[],
    this.heatmap = const <HeatmapPointModel>[],
    this.error,
  });

  List<CrimeIncidentModel> incidents;
  List<HeatmapPointModel> heatmap;
  Object? error;

  @override
  bool get useMockData => true;

  @override
  Future<List<CrimeIncidentModel>> fetchCrimes({
    required LatLng center,
    double radiusKm = 3,
    int limit = 200,
  }) async {
    final Object? failure = error;
    if (failure != null) throw failure;
    return incidents;
  }

  @override
  Future<List<HeatmapPointModel>> fetchHeatmap({
    required LatLng center,
    double radiusKm = 4,
  }) async {
    final Object? failure = error;
    if (failure != null) throw failure;
    return heatmap;
  }

  @override
  void dispose() {}
}
