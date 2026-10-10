import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:saferoute/models/recommendation_model.dart';
import 'package:saferoute/models/risk_model.dart';
import 'package:saferoute/models/route_model.dart';
import 'package:saferoute/providers/crime_data_provider.dart';
import 'package:saferoute/providers/location_provider.dart';
import 'package:saferoute/providers/route_provider.dart';
import 'package:saferoute/screens/home_screen.dart';
import 'package:saferoute/services/api_exception.dart';
import 'package:saferoute/services/location_service.dart';
import 'package:saferoute/utils/app_theme.dart';
import 'package:saferoute/widgets/route_card.dart';
import 'package:saferoute/widgets/route_map.dart';

import 'helpers/test_app.dart';

void main() {
  // The map's tile layer would try to fetch images over the network; a
  // phone-sized surface keeps the layout assertions realistic.
  const Size phone = Size(390, 844);

  RouteResultModel threeRoutes() {
    return RouteResultModel(
      routes: <RouteModel>[
        buildRoute(
          id: 'route-a',
          name: 'Route A',
          durationMinutes: 15,
          distanceKm: 5.2,
          risk: RiskLevel.high,
        ),
        buildRoute(
          id: 'route-b',
          name: 'Route B',
          durationMinutes: 18,
          distanceKm: 6.0,
          risk: RiskLevel.low,
        ),
        buildRoute(
          id: 'route-c',
          name: 'Route C',
          durationMinutes: 16,
          distanceKm: 5.5,
          risk: RiskLevel.moderate,
        ),
      ],
      recommendation: const RecommendationModel(
        routeId: 'route-b',
        reason: 'Lower estimated historical crime exposure than the '
            'alternatives.',
      ),
    );
  }

  Future<void> pumpHome(
    WidgetTester tester, {
    required RouteProvider routeProvider,
    LocationProvider? locationProvider,
    CrimeDataProvider? crimeProvider,
  }) async {
    tester.view.physicalSize = phone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LocationProvider>.value(
            value: locationProvider ??
                LocationProvider(service: FakeDeviceLocationService()),
          ),
          ChangeNotifierProvider<RouteProvider>.value(value: routeProvider),
          ChangeNotifierProvider<CrimeDataProvider>.value(
            value: crimeProvider ??
                CrimeDataProvider(service: FakeCrimeService()),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('opens on the map with a destination prompt', (tester) async {
    await pumpHome(
      tester,
      routeProvider: RouteProvider(service: FakeRouteService()),
    );

    expect(find.byType(RouteMap), findsOneWidget);
    expect(find.text('SafeRoute'), findsOneWidget);
    expect(find.text('Search destination...'), findsOneWidget);
    expect(find.text('Where do you want to go?'), findsOneWidget);
  });

  testWidgets('offers current location and layer controls', (tester) async {
    await pumpHome(
      tester,
      routeProvider: RouteProvider(service: FakeRouteService()),
    );

    expect(find.byTooltip('Go to current location'), findsOneWidget);
    expect(find.byTooltip('Show crime markers'), findsOneWidget);
    expect(find.byIcon(Icons.my_location), findsOneWidget);
  });

  testWidgets('shows the recommendation and every route option',
      (tester) async {
    final RouteProvider provider =
        RouteProvider(service: FakeRouteService(result: threeRoutes()));
    await provider.findRoutes(
      start: const LatLng(12.9716, 77.5946),
      destination: testDestination,
    );

    await pumpHome(tester, routeProvider: provider);

    // The backend's pick, titled for the active preference.
    expect(find.text('Balanced route'), findsOneWidget);
    expect(
      find.textContaining('Lower estimated historical crime exposure'),
      findsOneWidget,
    );

    // All three options are listed for comparison.
    expect(find.byType(RouteCard), findsNWidgets(3));
    expect(find.text('Route A'), findsOneWidget);
    expect(find.text('Route C'), findsOneWidget);

    // Preference selector is present.
    expect(find.text('Fastest'), findsWidgets);
    expect(find.text('Lower Risk'), findsWidgets);
  });

  testWidgets('always states that risk comes from historical data',
      (tester) async {
    final RouteProvider provider =
        RouteProvider(service: FakeRouteService(result: threeRoutes()));
    await provider.findRoutes(
      start: const LatLng(12.9716, 77.5946),
      destination: testDestination,
    );

    await pumpHome(tester, routeProvider: provider);

    expect(
      find.textContaining('cannot guarantee future safety'),
      findsOneWidget,
    );
  });

  testWidgets('shows a retryable error when routing fails', (tester) async {
    final RouteProvider provider = RouteProvider(
      service: FakeRouteService(error: const ApiException.timeout()),
    );
    await provider.findRoutes(
      start: const LatLng(12.9716, 77.5946),
      destination: testDestination,
    );

    await pumpHome(tester, routeProvider: provider);

    expect(find.textContaining('took too long'), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);
    // The map stays on screen so the user is never stranded.
    expect(find.byType(RouteMap), findsOneWidget);
  });

  testWidgets('reports an empty route result without inventing routes',
      (tester) async {
    final RouteProvider provider = RouteProvider(
      service: FakeRouteService(
        result: const RouteResultModel(routes: <RouteModel>[]),
      ),
    );
    await provider.findRoutes(
      start: const LatLng(12.9716, 77.5946),
      destination: testDestination,
    );

    await pumpHome(tester, routeProvider: provider);

    expect(
      find.text('No routes were found between these two points.'),
      findsOneWidget,
    );
    expect(find.byType(RouteCard), findsNothing);
  });

  testWidgets('offers settings when location is permanently denied',
      (tester) async {
    final LocationProvider location = LocationProvider(
      service: FakeDeviceLocationService(
        error: const LocationException(
          LocationErrorKind.permanentlyDenied,
          'Location access is needed to use your current position.',
        ),
      ),
    );
    await location.load();

    await pumpHome(
      tester,
      routeProvider: RouteProvider(service: FakeRouteService()),
      locationProvider: location,
    );

    expect(
      find.textContaining('Location access is needed'),
      findsOneWidget,
    );
    expect(find.text('Open Settings'), findsOneWidget);
  });

  testWidgets('says when no crime data exists for the area', (tester) async {
    final CrimeDataProvider crime =
        CrimeDataProvider(service: FakeCrimeService());
    await crime.load(const LatLng(12.9716, 77.5946));

    await pumpHome(
      tester,
      routeProvider: RouteProvider(service: FakeRouteService()),
      crimeProvider: crime,
    );

    expect(
      find.text('No historical crime data is available for this area.'),
      findsOneWidget,
    );
  });

  testWidgets('the map keeps most of the screen', (tester) async {
    final RouteProvider provider =
        RouteProvider(service: FakeRouteService(result: threeRoutes()));
    await provider.findRoutes(
      start: const LatLng(12.9716, 77.5946),
      destination: testDestination,
    );

    await pumpHome(tester, routeProvider: provider);

    final double mapHeight = tester.getSize(find.byType(RouteMap)).height;
    expect(
      mapHeight,
      greaterThan(phone.height * 0.35),
      reason: 'the bottom panel must not crowd out the map',
    );
  });
}
