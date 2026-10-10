import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:saferoute/models/location_model.dart';
import 'package:saferoute/models/route_preference.dart';
import 'package:saferoute/models/risk_model.dart';
import 'package:saferoute/services/api_client.dart';
import 'package:saferoute/services/api_exception.dart';
import 'package:saferoute/services/crime_service.dart';
import 'package:saferoute/services/location_service.dart';
import 'package:saferoute/services/route_service.dart';

/// Responses in test/fixtures were produced by the real FastAPI backend
/// (backend/), so these tests fail if the backend and the app models drift.
String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

ApiClient clientReturning(String body, {int status = 200, void Function(http.Request)? onRequest}) {
  return ApiClient(
    client: MockClient((http.Request request) async {
      onRequest?.call(request);
      return http.Response(body, status, headers: <String, String>{'content-type': 'application/json'});
    }),
  );
}

void main() {
  serviceAreaTests();
  test('routes response parses into routes, risk and recommendation', () async {
    http.Request? seen;
    final RouteService service = RouteService(
      client: clientReturning(fixture('routes_response.json'), onRequest: (r) => seen = r),
      useMockData: false,
    );

    final result = await service.generateRoutes(
      start: const LatLng(12.9352, 77.6245),
      destination: const LatLng(13.0358, 77.5970),
      preference: RoutePreference.lowerRisk,
    );

    expect(seen!.method, 'POST');
    expect(seen!.url.path, '/api/v1/routes');
    final Map<String, dynamic> sent = jsonDecode(seen!.body) as Map<String, dynamic>;
    expect(sent['preference'], 'lower_risk');
    expect((sent['start'] as Map)['latitude'], 12.9352);

    expect(result.routes.length, 2);
    for (final route in result.routes) {
      expect(route.points.length, greaterThan(2));
      expect(route.durationMinutes, greaterThan(0));
      expect(route.distanceKm, greaterThan(0));
      expect(route.risk.level.isKnown, isTrue);
      expect(route.risk.scorePercent, isNotNull);
      expect(route.risk.reason, isNotNull);
      expect(route.segments, isNotEmpty);
    }
    expect(result.recommendedRoute, isNotNull);
    expect(result.recommendation!.reason, isNotEmpty);
  });

  test('crimes response parses every record', () async {
    final CrimeService service = CrimeService(
      client: clientReturning(fixture('crimes_response.json')),
      useMockData: false,
    );
    final crimes = await service.fetchCrimes(center: const LatLng(12.9716, 77.5946));
    final int expected = ((jsonDecode(fixture('crimes_response.json')) as Map)['crimes'] as List).length;
    expect(crimes.length, expected);
    expect(crimes.first.date, isNotNull);
    expect(crimes.first.area, isNotNull);
  });

  test('heatmap response parses every cell with a known exposure', () async {
    final CrimeService service = CrimeService(
      client: clientReturning(fixture('heatmap_response.json')),
      useMockData: false,
    );
    final points = await service.fetchHeatmap(center: const LatLng(12.9716, 77.5946));
    final int expected = ((jsonDecode(fixture('heatmap_response.json')) as Map)['points'] as List).length;
    expect(points.length, expected);
    expect(points.every((p) => p.exposure.isKnown && p.intensity != null), isTrue);
  });

  test('location search response parses into places', () async {
    http.Request? seen;
    final LocationSearchService service = LocationSearchService(
      client: clientReturning(fixture('locations_response.json'), onRequest: (r) => seen = r),
      useMockData: false,
    );
    final List<LocationModel> places = await service.search('koramangala');
    expect(seen!.url.queryParameters['q'], 'koramangala');
    expect(places, isNotEmpty);
    expect(places.first.name, isNotEmpty);
  });

  test('risk response parses', () async {
    final RouteService service = RouteService(
      client: clientReturning(fixture('risk_response.json')),
      useMockData: false,
    );
    final RiskModel risk = await service.calculateRouteRisk(
      (await RouteService(
        client: clientReturning(fixture('routes_response.json')),
        useMockData: false,
      ).generateRoutes(
        start: const LatLng(12.9352, 77.6245),
        destination: const LatLng(13.0358, 77.5970),
        preference: RoutePreference.balanced,
      ))
          .routes
          .first,
    );
    expect(risk.level.isKnown, isTrue);
  });

  test('backend string detail reaches the user as the error message', () async {
    final RouteService service = RouteService(
      client: clientReturning(
        '{"detail":"SafeRoute currently supports routes within Bengaluru only."}',
        status: 422,
      ),
      useMockData: false,
    );
    expect(
      () => service.generateRoutes(
        start: const LatLng(28.6, 77.2),
        destination: const LatLng(13.0, 77.5),
        preference: RoutePreference.balanced,
      ),
      throwsA(
        isA<ApiException>().having((e) => e.message, 'message', contains('Bengaluru')),
      ),
    );
  });
}

void serviceAreaTests() {
  test('positions outside Bengaluru fall back to the Bengaluru centre', () {
    expect(isInServiceArea(const LatLng(12.9716, 77.5946)), isTrue);
    expect(isInServiceArea(const LatLng(28.6289, 77.2196)), isFalse);
    expect(serviceAreaCenter(const LatLng(28.6289, 77.2196)), developmentFallbackCenter);
    expect(serviceAreaCenter(null), developmentFallbackCenter);
    const LatLng inside = LatLng(12.93, 77.62);
    expect(serviceAreaCenter(inside), inside);
  });
}
