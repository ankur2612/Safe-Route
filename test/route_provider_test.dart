import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:saferoute/models/recommendation_model.dart';
import 'package:saferoute/models/risk_model.dart';
import 'package:saferoute/models/route_model.dart';
import 'package:saferoute/models/route_preference.dart';
import 'package:saferoute/providers/route_provider.dart';
import 'package:saferoute/services/api_exception.dart';

import 'helpers/test_app.dart';

void main() {
  const LatLng start = LatLng(28.6289, 77.2196);

  RouteResultModel threeRoutes() {
    return RouteResultModel(
      routes: <RouteModel>[
        buildRoute(
          id: 'route-a',
          name: 'Route A',
          durationMinutes: 15,
          risk: RiskLevel.high,
        ),
        buildRoute(
          id: 'route-b',
          name: 'Route B',
          durationMinutes: 18,
          risk: RiskLevel.low,
        ),
        buildRoute(
          id: 'route-c',
          name: 'Route C',
          durationMinutes: 16,
          risk: RiskLevel.moderate,
        ),
      ],
      recommendation: const RecommendationModel(
        routeId: 'route-b',
        reason: 'Lower estimated historical crime exposure.',
      ),
    );
  }

  test('successful search selects the recommended route', () async {
    final FakeRouteService service = FakeRouteService(result: threeRoutes());
    final RouteProvider provider = RouteProvider(service: service);

    await provider.findRoutes(start: start, destination: testDestination);

    expect(provider.status, RouteStatus.success);
    expect(provider.routes, hasLength(3));
    expect(provider.selectedRoute?.id, 'route-b');
    expect(provider.recommendedRoute?.id, 'route-b');
    expect(provider.isRecommended(provider.routes[1]), isTrue);
  });

  test('identifies the fastest route for labelling', () async {
    final FakeRouteService service = FakeRouteService(result: threeRoutes());
    final RouteProvider provider = RouteProvider(service: service);

    await provider.findRoutes(start: start, destination: testDestination);

    expect(provider.fastestRoute?.id, 'route-a');
  });

  test('an empty route list produces the empty state, not an error', () async {
    final FakeRouteService service = FakeRouteService(
      result: const RouteResultModel(routes: <RouteModel>[]),
    );
    final RouteProvider provider = RouteProvider(service: service);

    await provider.findRoutes(start: start, destination: testDestination);

    expect(provider.status, RouteStatus.empty);
    expect(provider.hasRoutes, isFalse);
    expect(provider.errorMessage, isNull);
  });

  test('api failures surface a message and clear stale routes', () async {
    final FakeRouteService service = FakeRouteService(
      error: const ApiException.network(),
    );
    final RouteProvider provider = RouteProvider(service: service);

    await provider.findRoutes(start: start, destination: testDestination);

    expect(provider.status, RouteStatus.error);
    expect(provider.errorMessage, contains('No internet connection'));
    expect(provider.routes, isEmpty);
  });

  test('unexpected errors still leave a usable error state', () async {
    final FakeRouteService service = FakeRouteService(
      error: StateError('unexpected'),
    );
    final RouteProvider provider = RouteProvider(service: service);

    await provider.findRoutes(start: start, destination: testDestination);

    expect(provider.status, RouteStatus.error);
    expect(provider.errorMessage, 'Could not generate routes right now.');
  });

  test('changing preference re-requests routes with the new value', () async {
    final FakeRouteService service = FakeRouteService(result: threeRoutes());
    final RouteProvider provider = RouteProvider(service: service);

    await provider.findRoutes(start: start, destination: testDestination);
    expect(service.requestedPreferences.last, RoutePreference.balanced);

    await provider.setPreference(RoutePreference.lowerRisk);

    expect(provider.preference, RoutePreference.lowerRisk);
    expect(service.requestedPreferences.last, RoutePreference.lowerRisk);
    expect(service.generateCallCount, 2);
  });

  test('selecting the same preference does not re-request', () async {
    final FakeRouteService service = FakeRouteService(result: threeRoutes());
    final RouteProvider provider = RouteProvider(service: service);

    await provider.findRoutes(start: start, destination: testDestination);
    await provider.setPreference(RoutePreference.balanced);

    expect(service.generateCallCount, 1);
  });

  test('user selection overrides the recommended route', () async {
    final FakeRouteService service = FakeRouteService(result: threeRoutes());
    final RouteProvider provider = RouteProvider(service: service);

    await provider.findRoutes(start: start, destination: testDestination);
    provider.selectRoute('route-c');

    expect(provider.selectedRoute?.id, 'route-c');
    // The backend's recommendation is unchanged by browsing.
    expect(provider.recommendedRoute?.id, 'route-b');
  });

  test('a recommendation naming an unknown route is ignored', () async {
    final FakeRouteService service = FakeRouteService(
      result: RouteResultModel(
        routes: <RouteModel>[buildRoute(id: 'route-a')],
        recommendation: const RecommendationModel(routeId: 'route-z'),
      ),
    );
    final RouteProvider provider = RouteProvider(service: service);

    await provider.findRoutes(start: start, destination: testDestination);

    expect(provider.recommendedRoute, isNull);
    // Falls back to the first route so the map still has a selection.
    expect(provider.selectedRoute?.id, 'route-a');
  });

  test('retry repeats the last request', () async {
    final FakeRouteService service = FakeRouteService(
      error: const ApiException.timeout(),
    );
    final RouteProvider provider = RouteProvider(service: service);

    await provider.findRoutes(start: start, destination: testDestination);
    expect(provider.status, RouteStatus.error);

    service
      ..error = null
      ..result = threeRoutes();
    await provider.retry();

    expect(provider.status, RouteStatus.success);
    expect(provider.routes, hasLength(3));
  });

  test('clearing removes the destination and routes', () async {
    final FakeRouteService service = FakeRouteService(result: threeRoutes());
    final RouteProvider provider = RouteProvider(service: service);

    await provider.findRoutes(start: start, destination: testDestination);
    provider.clearRoutes();

    expect(provider.status, RouteStatus.idle);
    expect(provider.destination, isNull);
    expect(provider.routes, isEmpty);
    expect(provider.selectedRoute, isNull);
  });
}
