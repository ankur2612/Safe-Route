import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:saferoute/models/crime_incident_model.dart';
import 'package:saferoute/models/location_model.dart';
import 'package:saferoute/models/recommendation_model.dart';
import 'package:saferoute/models/risk_model.dart';
import 'package:saferoute/models/route_model.dart';
import 'package:saferoute/providers/crime_data_provider.dart';
import 'package:saferoute/providers/location_provider.dart';
import 'package:saferoute/providers/route_provider.dart';
import 'package:saferoute/screens/home_screen.dart';
import 'package:saferoute/services/api_exception.dart';
import 'package:saferoute/services/google_maps_launcher.dart';
import 'package:saferoute/services/location_service.dart';
import 'package:saferoute/utils/app_theme.dart';
import 'package:saferoute/widgets/route_card.dart';
import 'package:saferoute/widgets/route_map.dart';
import 'package:url_launcher/url_launcher.dart';

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
    GoogleMapsLauncher mapsLauncher = const GoogleMapsLauncher(),
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
          home: HomeScreen(mapsLauncher: mapsLauncher),
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

  group('Open in Google Maps', () {
    Future<RouteProvider> routesFound() async {
      final RouteProvider provider =
          RouteProvider(service: FakeRouteService(result: threeRoutes()));
      await provider.findRoutes(
        start: const LatLng(12.9716, 77.5946),
        destination: testDestination,
      );
      return provider;
    }

    Finder mapsButtonOf(String routeName) => find.descendant(
          of: find.widgetWithText(RouteCard, routeName),
          matching: find.text('Open in Google Maps'),
        );

    testWidgets('every route card offers the action', (tester) async {
      await pumpHome(tester, routeProvider: await routesFound());

      for (final String name in <String>['Route A', 'Route B', 'Route C']) {
        expect(mapsButtonOf(name), findsOneWidget);
      }
      // The limitation is explained alongside the routes.
      expect(find.textContaining('Google Maps may still choose different roads'),
          findsOneWidget);
    });

    testWidgets('each card opens its own route with the trip endpoints',
        (tester) async {
      final List<Uri> opened = <Uri>[];
      await pumpHome(
        tester,
        routeProvider: await routesFound(),
        mapsLauncher: GoogleMapsLauncher(
          open: (Uri uri, LaunchMode mode) async {
            opened.add(uri);
            return true;
          },
        ),
      );

      for (final String name in <String>['Route B', 'Route C']) {
        await tester.ensureVisible(mapsButtonOf(name));
        await tester.tap(mapsButtonOf(name));
        await tester.pump();
      }

      expect(opened, hasLength(2));
      for (final Uri uri in opened) {
        expect(uri.queryParameters['origin'], '12.971600,77.594600');
        expect(uri.queryParameters['destination'], '28.612900,77.229500');
      }
    });

    testWidgets('explains when Google Maps cannot be opened', (tester) async {
      await pumpHome(
        tester,
        routeProvider: await routesFound(),
        mapsLauncher: GoogleMapsLauncher(
          open: (Uri uri, LaunchMode mode) async => false,
        ),
      );

      await tester.ensureVisible(mapsButtonOf('Route A'));
      await tester.tap(mapsButtonOf('Route A'));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining("Couldn't open Google Maps"), findsOneWidget);
    });
  });

  group('crime markers for the trip', () {
    const LatLng bengaluruStart = LatLng(12.9716, 77.5946);
    const LocationModel koramangala = LocationModel(
      name: 'Koramangala',
      address: 'Bengaluru',
      latitude: 12.9352,
      longitude: 77.6245,
    );

    /// Three distinct routes inside Bengaluru, where crime data exists.
    RouteResultModel bengaluruRoutes() => RouteResultModel(
          routes: <RouteModel>[
            for (final (String id, double lon) in <(String, double)>[
              ('route-a', 77.61),
              ('route-b', 77.62),
              ('route-c', 77.63),
            ])
              RouteModel(
                id: id,
                name: 'Route ${id.substring(6).toUpperCase()}',
                durationMinutes: 20,
                distanceKm: 6,
                points: <LatLng>[bengaluruStart, LatLng(12.95, lon), koramangala.latLng],
                risk: const RiskModel(level: RiskLevel.moderate),
              ),
          ],
          recommendation: const RecommendationModel(routeId: 'route-b'),
        );
    final CrimeIncidentModel nearStart = const CrimeIncidentModel(
      id: 'incident-1',
      type: 'Theft',
      latitude: 12.972,
      longitude: 77.595,
    );
    final CrimeIncidentModel nearDestination = const CrimeIncidentModel(
      id: 'incident-2',
      type: 'Robbery',
      latitude: 12.935,
      longitude: 77.624,
    );
    final CrimeIncidentModel alongRoute = const CrimeIncidentModel(
      id: 'incident-3',
      type: 'Burglary',
      latitude: 12.95,
      longitude: 77.61,
    );

    FakeCrimeService crimeService() => FakeCrimeService(
          incidentsByCenter: <LatLng, List<CrimeIncidentModel>>{
            const LatLng(12.9716, 77.5946): <CrimeIncidentModel>[nearStart],
            koramangala.latLng: <CrimeIncidentModel>[nearDestination],
          },
          routeIncidents: <CrimeIncidentModel>[alongRoute],
        );

    Future<void> settle(WidgetTester tester) async {
      for (int i = 0; i < 6; i++) {
        await tester.pump();
      }
    }

    List<CrimeIncidentModel> mapIncidents(WidgetTester tester) =>
        tester.widget<RouteMap>(find.byType(RouteMap)).incidents;

    testWidgets('shows records around the origin before a destination',
        (tester) async {
      final FakeCrimeService fake = crimeService();
      await pumpHome(
        tester,
        routeProvider: RouteProvider(service: FakeRouteService()),
        crimeProvider: CrimeDataProvider(service: fake),
      );
      await settle(tester);

      expect(fake.crimeCenters, <LatLng>[const LatLng(12.9716, 77.5946)]);
      expect(mapIncidents(tester), <CrimeIncidentModel>[nearStart]);
    });

    testWidgets('shows origin, destination and route records together',
        (tester) async {
      final FakeCrimeService fake = crimeService();
      final RouteProvider routes =
          RouteProvider(service: FakeRouteService(result: bengaluruRoutes()));
      await routes.findRoutes(
        start: const LatLng(12.9716, 77.5946),
        destination: koramangala,
      );

      await pumpHome(
        tester,
        routeProvider: routes,
        crimeProvider: CrimeDataProvider(service: fake),
      );
      await settle(tester);

      expect(fake.crimeCenters, contains(koramangala.latLng));
      expect(
        mapIncidents(tester),
        containsAll(<CrimeIncidentModel>[nearStart, nearDestination, alongRoute]),
      );
      expect(fake.routeCallCount, 3);
    });

    testWidgets('records stay on the map when the preference changes',
        (tester) async {
      final FakeCrimeService fake = crimeService();
      final FakeRouteService routeService =
          FakeRouteService(result: bengaluruRoutes());
      final RouteProvider routes = RouteProvider(service: routeService);
      await routes.findRoutes(
        start: const LatLng(12.9716, 77.5946),
        destination: koramangala,
      );
      await pumpHome(
        tester,
        routeProvider: routes,
        crimeProvider: CrimeDataProvider(service: fake),
      );
      await settle(tester);
      final int requestsBefore = fake.crimeCenters.length + fake.routeCallCount;

      for (final String preference in <String>['Fastest', 'Lower Risk']) {
        // The backend returns the same routes as fresh objects.
        routeService.result = bengaluruRoutes();
        await tester.tap(find.text(preference).first);
        await settle(tester);

        expect(
          mapIncidents(tester),
          containsAll(<CrimeIncidentModel>[nearStart, nearDestination, alongRoute]),
        );
      }
      expect(fake.crimeCenters.length + fake.routeCallCount, requestsBefore);
    });

    testWidgets('says when the trip has no records rather than implying '
        'lower risk', (tester) async {
      final RouteProvider routes =
          RouteProvider(service: FakeRouteService(result: bengaluruRoutes()));
      await routes.findRoutes(
        start: const LatLng(12.9716, 77.5946),
        destination: koramangala,
      );
      await pumpHome(
        tester,
        routeProvider: routes,
        crimeProvider: CrimeDataProvider(service: FakeCrimeService()),
      );
      await settle(tester);

      expect(find.textContaining('This means there is no data'), findsOneWidget);
    });

    testWidgets('says when only the start has no records', (tester) async {
      final FakeCrimeService fake = crimeService()
        ..incidentsByCenter!.remove(const LatLng(12.9716, 77.5946));
      final RouteProvider routes =
          RouteProvider(service: FakeRouteService(result: bengaluruRoutes()));
      await routes.findRoutes(
        start: const LatLng(12.9716, 77.5946),
        destination: koramangala,
      );
      await pumpHome(
        tester,
        routeProvider: routes,
        crimeProvider: CrimeDataProvider(service: fake),
      );
      await settle(tester);

      expect(
        find.textContaining('No historical crime records are available near '
            'your start'),
        findsOneWidget,
      );
    });

    testWidgets('offers a retry when crime data is unavailable',
        (tester) async {
      final RouteProvider routes =
          RouteProvider(service: FakeRouteService(result: bengaluruRoutes()));
      await routes.findRoutes(
        start: const LatLng(12.9716, 77.5946),
        destination: koramangala,
      );
      await pumpHome(
        tester,
        routeProvider: routes,
        crimeProvider: CrimeDataProvider(
          service: FakeCrimeService(error: const ApiException.network()),
        ),
      );
      await settle(tester);

      expect(find.textContaining("Couldn't connect to the SafeRoute server"), findsOneWidget);
    });
      testWidgets('a destination outside Bengaluru gets routes but no crime '
        'requests or risk estimate', (tester) async {
      const LocationModel baga = LocationModel(
        name: 'Baga',
        address: 'Goa',
        latitude: 15.5553,
        longitude: 73.7517,
        crimeDataAvailable: false,
      );
      final FakeCrimeService fake = crimeService();
      final RouteProvider routes = RouteProvider(
        service: FakeRouteService(
          result: RouteResultModel(
            routes: <RouteModel>[
              RouteModel(
                id: 'route-a',
                name: 'Route A',
                durationMinutes: 600,
                distanceKm: 560,
                points: const <LatLng>[bengaluruStart, LatLng(14.5, 75.5), LatLng(15.5553, 73.7517)],
                risk: const RiskModel(
                  level: RiskLevel.unknown,
                  reason: 'SafeRoute has historical crime data for Bengaluru only.',
                ),
              ),
            ],
            recommendation: const RecommendationModel(routeId: 'route-a'),
            coverageMessage: 'Crime-risk estimates are available only for trips '
                'within Bengaluru.',
          ),
        ),
      );
      await routes.findRoutes(start: bengaluruStart, destination: baga);
      await pumpHome(
        tester,
        routeProvider: routes,
        crimeProvider: CrimeDataProvider(service: fake),
      );
      await settle(tester);

      expect(find.textContaining('available only for trips within Bengaluru'),
          findsOneWidget);
      expect(find.text('N/A'), findsWidgets);
      expect(find.text('LOW'), findsNothing);
      // Bengaluru records are requested for the start only, never for Goa.
      expect(fake.crimeCenters, <LatLng>[bengaluruStart]);
      expect(find.textContaining('near your destination'), findsOneWidget);
    });
  });
}
