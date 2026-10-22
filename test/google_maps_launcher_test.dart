import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:saferoute/services/google_maps_launcher.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  const LatLng origin = LatLng(13.1338, 77.6683);
  const LatLng koramangala = LatLng(12.9352, 77.6245);

  /// A straight ~22 km line between the two points.
  final List<LatLng> route = <LatLng>[
    for (int i = 0; i <= 40; i++)
      LatLng(
        origin.latitude + (koramangala.latitude - origin.latitude) * i / 40,
        origin.longitude + (koramangala.longitude - origin.longitude) * i / 40,
      ),
  ];

  group('directionsUri', () {
    test('uses the Maps URLs directions format with exact coordinates', () {
      final Uri uri = GoogleMapsLauncher.directionsUri(
        origin: origin,
        destination: koramangala,
      )!;

      expect(uri.scheme, 'https');
      expect(uri.host, 'www.google.com');
      expect(uri.path, '/maps/dir/');
      expect(uri.queryParameters['api'], '1');
      expect(uri.queryParameters['origin'], '13.133800,77.668300');
      expect(uri.queryParameters['destination'], '12.935200,77.624500');
      expect(uri.queryParameters['travelmode'], 'driving');
      expect(uri.queryParameters.containsKey('waypoints'), isFalse);
    });

    test('percent-encodes separators', () {
      final Uri uri = GoogleMapsLauncher.directionsUri(
        origin: origin,
        destination: koramangala,
        routePoints: route,
      )!;
      final String text = uri.toString();

      expect(text, contains('origin=13.133800%2C77.668300'));
      expect(text, contains('%7C'));
      expect(text, isNot(contains('|')));
    });

    test('passes up to three points from the route as waypoints', () {
      final Uri uri = GoogleMapsLauncher.directionsUri(
        origin: origin,
        destination: koramangala,
        routePoints: route,
      )!;
      final List<String> waypoints = uri.queryParameters['waypoints']!.split('|');

      expect(waypoints, hasLength(GoogleMapsLauncher.maxWaypoints));
      final Set<String> onRoute = route
          .map((LatLng p) =>
              '${p.latitude.toStringAsFixed(6)},${p.longitude.toStringAsFixed(6)}')
          .toSet();
      expect(onRoute.containsAll(waypoints), isTrue);
      expect(waypoints, isNot(contains(uri.queryParameters['origin'])));
      expect(waypoints, isNot(contains(uri.queryParameters['destination'])));
    });

    test('short routes need no waypoints', () {
      final List<LatLng> short = <LatLng>[
        koramangala,
        const LatLng(12.9360, 77.6250),
        const LatLng(12.9370, 77.6260),
      ];
      expect(GoogleMapsLauncher.sampleWaypoints(short), isEmpty);
    });

    test('is null when a coordinate is missing or invalid', () {
      expect(
        GoogleMapsLauncher.directionsUri(origin: null, destination: koramangala),
        isNull,
      );
      expect(
        GoogleMapsLauncher.directionsUri(origin: origin, destination: null),
        isNull,
      );
      expect(
        GoogleMapsLauncher.directionsUri(
          origin: const LatLng(double.nan, 77.6),
          destination: koramangala,
        ),
        isNull,
      );
    });
  });

  group('openDirections', () {
    test('opens externally first', () async {
      final List<LaunchMode> modes = <LaunchMode>[];
      final List<Uri> uris = <Uri>[];
      final GoogleMapsLauncher launcher = GoogleMapsLauncher(
        open: (Uri uri, LaunchMode mode) async {
          uris.add(uri);
          modes.add(mode);
          return true;
        },
      );

      final MapsLaunchResult result = await launcher.openDirections(
        origin: origin,
        destination: koramangala,
        routePoints: route,
      );

      expect(result, MapsLaunchResult.opened);
      expect(modes, <LaunchMode>[LaunchMode.externalApplication]);
      expect(uris.single.queryParameters['destination'], '12.935200,77.624500');
    });

    test('falls back to the in-app browser when the external launch fails',
        () async {
      final List<LaunchMode> modes = <LaunchMode>[];
      final GoogleMapsLauncher launcher = GoogleMapsLauncher(
        open: (Uri uri, LaunchMode mode) async {
          modes.add(mode);
          if (mode == LaunchMode.externalApplication) {
            throw PlatformException(code: 'ACTIVITY_NOT_FOUND');
          }
          return true;
        },
      );

      final MapsLaunchResult result = await launcher.openDirections(
        origin: origin,
        destination: koramangala,
      );

      expect(result, MapsLaunchResult.openedFallback);
      expect(modes, <LaunchMode>[
        LaunchMode.externalApplication,
        LaunchMode.platformDefault,
      ]);
    });

    test('reports failure when nothing can open the link', () async {
      final GoogleMapsLauncher launcher =
          GoogleMapsLauncher(open: (Uri uri, LaunchMode mode) async => false);

      expect(
        await launcher.openDirections(origin: origin, destination: koramangala),
        MapsLaunchResult.failed,
      );
    });

    test('opens nothing when coordinates are missing', () async {
      int calls = 0;
      final GoogleMapsLauncher launcher = GoogleMapsLauncher(
        open: (Uri uri, LaunchMode mode) async {
          calls++;
          return true;
        },
      );

      expect(
        await launcher.openDirections(origin: origin, destination: null),
        MapsLaunchResult.missingCoordinates,
      );
      expect(calls, 0);
    });
  });
}
