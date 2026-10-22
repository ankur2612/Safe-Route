import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:saferoute/models/crime_incident_model.dart';
import 'package:saferoute/models/heatmap_point_model.dart';
import 'package:saferoute/models/risk_model.dart';
import 'package:saferoute/models/route_model.dart';
import 'package:saferoute/providers/crime_data_provider.dart';
import 'package:saferoute/services/api_exception.dart';

import 'helpers/test_app.dart';

void main() {
  const LatLng origin = LatLng(13.1338, 77.6683);
  const LatLng destination = LatLng(12.9352, 77.6245);

  CrimeIncidentModel incident(String id, double lat, double lon) =>
      CrimeIncidentModel(id: id, type: 'Theft', latitude: lat, longitude: lon);

  final CrimeIncidentModel nearOrigin = incident('incident-1', 13.134, 77.668);
  final CrimeIncidentModel nearDestination =
      incident('incident-2', 12.935, 77.624);
  final CrimeIncidentModel onRoute = incident('incident-3', 13.03, 77.64);

  List<RouteModel> routes() => <RouteModel>[
        for (final (String id, double lon) in <(String, double)>[
          ('route-a', 77.64),
          ('route-b', 77.66),
          ('route-c', 77.68),
        ])
          RouteModel(
            id: id,
            name: id,
            durationMinutes: 60,
            distanceKm: 24,
            points: <LatLng>[origin, LatLng(13.03, lon), destination],
            risk: const RiskModel(level: RiskLevel.moderate),
          ),
      ];

  FakeCrimeService service() => FakeCrimeService(
        incidentsByCenter: <LatLng, List<CrimeIncidentModel>>{
          origin: <CrimeIncidentModel>[nearOrigin],
          destination: <CrimeIncidentModel>[nearDestination],
        },
        routeIncidents: <CrimeIncidentModel>[onRoute],
        heatmap: const <HeatmapPointModel>[
          HeatmapPointModel(
            latitude: 13.0,
            longitude: 77.6,
            exposure: RiskLevel.high,
            intensity: 1,
          ),
        ],
      );

  test('loads markers around the origin', () async {
    final FakeCrimeService fake = service();
    final CrimeDataProvider provider = CrimeDataProvider(service: fake);

    await provider.load(origin);

    expect(fake.crimeCenters, <LatLng>[origin]);
    expect(provider.incidents, <CrimeIncidentModel>[nearOrigin]);
    expect(provider.status, CrimeDataStatus.success);
  });

  test('keeps the origin markers and adds the destination', () async {
    final FakeCrimeService fake = service();
    final CrimeDataProvider provider = CrimeDataProvider(service: fake);

    await provider.load(origin);
    await provider.loadTrip(origin: origin, destination: destination);

    expect(provider.incidents, containsAll(<CrimeIncidentModel>[nearOrigin, nearDestination]));
    // The origin answer was reused, not requested again.
    expect(fake.crimeCenters, <LatLng>[origin, destination]);
  });

  test('adds records along every candidate route', () async {
    final FakeCrimeService fake = service();
    final CrimeDataProvider provider = CrimeDataProvider(service: fake);

    await provider.loadTrip(
      origin: origin,
      destination: destination,
      routes: routes(),
    );

    expect(fake.routeCallCount, 3);
    expect(provider.incidents, contains(onRoute));
  });

  test('a record returned by several queries is shown once', () async {
    final FakeCrimeService fake = service()
      ..incidentsByCenter = <LatLng, List<CrimeIncidentModel>>{
        origin: <CrimeIncidentModel>[nearOrigin, onRoute],
        destination: <CrimeIncidentModel>[onRoute, nearDestination],
      };
    final CrimeDataProvider provider = CrimeDataProvider(service: fake);

    await provider.loadTrip(
      origin: origin,
      destination: destination,
      routes: routes(),
    );

    expect(provider.incidents.where((CrimeIncidentModel c) => c.id == onRoute.id),
        hasLength(1));
    expect(provider.incidents, hasLength(3));
    expect(provider.heatmapPoints, hasLength(1));
  });

  test('the same trip is not requested twice', () async {
    final FakeCrimeService fake = service();
    final CrimeDataProvider provider = CrimeDataProvider(service: fake);

    await provider.loadTrip(origin: origin, destination: destination, routes: routes());
    // A preference change returns equal routes as new objects.
    await provider.loadTrip(origin: origin, destination: destination, routes: routes());

    expect(fake.crimeCenters, hasLength(2));
    expect(fake.routeCallCount, 3);
  });

  test('markers stay visible while a new trip loads', () async {
    final FakeCrimeService fake = service();
    final CrimeDataProvider provider = CrimeDataProvider(service: fake);
    await provider.loadTrip(origin: origin, destination: destination);

    fake.gate = Completer<void>();
    final Future<void> pending = provider.loadTrip(
      origin: origin,
      destination: destination,
      routes: routes(),
    );

    expect(provider.isLoading, isTrue);
    expect(provider.incidents, containsAll(<CrimeIncidentModel>[nearOrigin, nearDestination]));

    fake.gate!.complete();
    await pending;
    expect(provider.incidents, contains(onRoute));
  });

  test('an older reply cannot overwrite a newer trip', () async {
    const LatLng otherDestination = LatLng(12.9116, 77.6389);
    final CrimeIncidentModel nearOther = incident('incident-9', 12.912, 77.639);
    final FakeCrimeService fake = service()
      ..incidentsByCenter![otherDestination] = <CrimeIncidentModel>[nearOther]
      ..gate = Completer<void>();
    final CrimeDataProvider provider = CrimeDataProvider(service: fake);

    final Future<void> first =
        provider.loadTrip(origin: origin, destination: destination);
    final Future<void> second =
        provider.loadTrip(origin: origin, destination: otherDestination);
    fake.gate!.complete();
    await Future.wait(<Future<void>>[first, second]);

    expect(provider.incidents, contains(nearOther));
    expect(provider.incidents, isNot(contains(nearDestination)));
  });

  test('no records is "empty", distinct from an error', () async {
    final CrimeDataProvider provider =
        CrimeDataProvider(service: FakeCrimeService());

    await provider.loadTrip(origin: origin, destination: destination);

    expect(provider.status, CrimeDataStatus.empty);
    expect(provider.errorMessage, isNull);
  });

  test('names an endpoint that has no records nearby', () async {
    final FakeCrimeService fake = service()
      ..incidentsByCenter = <LatLng, List<CrimeIncidentModel>>{
        destination: <CrimeIncidentModel>[nearDestination],
      }
      ..heatmap = const <HeatmapPointModel>[];
    final CrimeDataProvider provider = CrimeDataProvider(service: fake);

    await provider.loadTrip(origin: origin, destination: destination);

    expect(provider.status, CrimeDataStatus.success);
    expect(provider.endpointsWithoutRecords, <String>['start']);
  });

  test('a failure with nothing loaded is an error, never "empty"', () async {
    final CrimeDataProvider provider = CrimeDataProvider(
      service: FakeCrimeService(error: const ApiException.network()),
    );

    await provider.loadTrip(origin: origin, destination: destination);

    expect(provider.status, CrimeDataStatus.error);
    expect(provider.hasData, isFalse);
    expect(provider.errorMessage, contains("Couldn't connect to the SafeRoute server"));
  });

  test('a route failure keeps endpoint markers and flags partial data',
      () async {
    final FakeCrimeService fake = service()
      ..routeError = const ApiException.timeout();
    final CrimeDataProvider provider = CrimeDataProvider(service: fake);

    await provider.loadTrip(
      origin: origin,
      destination: destination,
      routes: routes(),
    );

    expect(provider.status, CrimeDataStatus.success);
    expect(provider.isPartial, isTrue);
    expect(provider.incidents, containsAll(<CrimeIncidentModel>[nearOrigin, nearDestination]));

    fake.routeError = null;
    await provider.retry();
    expect(provider.isPartial, isFalse);
    expect(provider.incidents, contains(onRoute));
  });
}
