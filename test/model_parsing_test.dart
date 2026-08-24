import 'package:flutter_test/flutter_test.dart';
import 'package:saferoute/models/crime_incident_model.dart';
import 'package:saferoute/models/heatmap_point_model.dart';
import 'package:saferoute/models/location_model.dart';
import 'package:saferoute/models/recommendation_model.dart';
import 'package:saferoute/models/risk_model.dart';
import 'package:saferoute/models/route_model.dart';

void main() {
  group('RouteModel parsing', () {
    test('reads a route in the expected response shape', () {
      final RouteModel? route = RouteModel.fromJson(<String, dynamic>{
        'id': 'route-b',
        'name': 'Route B',
        'duration_minutes': 18,
        'distance_km': 6.0,
        'geometry': <List<double>>[
          <double>[28.61, 77.21],
          <double>[28.63, 77.23],
        ],
        'risk': <String, dynamic>{'risk': 'low', 'score': 0.24},
      });

      expect(route, isNotNull);
      expect(route!.name, 'Route B');
      expect(route.durationLabel, '18 min');
      expect(route.distanceLabel, '6.0 km');
      expect(route.risk.level, RiskLevel.low);
      expect(route.points, hasLength(2));
    });

    test('converts raw OSRM-style seconds and metres', () {
      final RouteModel? route = RouteModel.fromJson(<String, dynamic>{
        'duration': 1080,
        'distance': 6000,
        'geometry': <List<double>>[
          <double>[28.61, 77.21],
          <double>[28.63, 77.23],
        ],
      });

      expect(route!.durationMinutes, 18);
      expect(route.distanceKm, 6.0);
    });

    test('names routes A, B, C when the backend omits names', () {
      final Map<String, dynamic> payload = <String, dynamic>{
        'duration_minutes': 15,
        'distance_km': 5.2,
        'geometry': <List<double>>[
          <double>[28.61, 77.21],
          <double>[28.63, 77.23],
        ],
      };

      expect(RouteModel.fromJson(payload, index: 0)!.name, 'Route A');
      expect(RouteModel.fromJson(payload, index: 2)!.name, 'Route C');
    });

    test('drops a route with no geometry rather than showing an empty line',
        () {
      final RouteModel? route = RouteModel.fromJson(<String, dynamic>{
        'duration_minutes': 15,
        'distance_km': 5.2,
      });

      expect(route, isNull);
    });

    test('a route with no risk field reports unknown, not low', () {
      final RouteModel? route = RouteModel.fromJson(<String, dynamic>{
        'duration_minutes': 15,
        'distance_km': 5.2,
        'geometry': <List<double>>[
          <double>[28.61, 77.21],
          <double>[28.63, 77.23],
        ],
      });

      expect(route!.risk.level, RiskLevel.unknown);
    });
  });

  group('parseGeometry', () {
    test('accepts objects as well as pairs', () {
      final points = parseGeometry(<Map<String, dynamic>>[
        <String, dynamic>{'lat': 28.61, 'lon': 77.21},
        <String, dynamic>{'latitude': 28.63, 'longitude': 77.23},
      ]);

      expect(points, hasLength(2));
      expect(points.first.latitude, 28.61);
      expect(points.last.longitude, 77.23);
    });

    test('skips malformed points instead of failing', () {
      final points = parseGeometry(<Object?>[
        <double>[28.61, 77.21],
        null,
        <double>[28.63],
        'not a point',
        <String, dynamic>{'lat': 28.65, 'lon': 77.25},
      ]);

      expect(points, hasLength(2));
    });

    test('returns empty for a non-list', () {
      expect(parseGeometry(null), isEmpty);
      expect(parseGeometry('geometry'), isEmpty);
    });
  });

  group('RouteResultModel parsing', () {
    test('parses routes and resolves the recommendation', () {
      final RouteResultModel result =
          RouteResultModel.fromJson(<String, dynamic>{
        'routes': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'route-a',
            'duration_minutes': 15,
            'distance_km': 5.2,
            'geometry': <List<double>>[
              <double>[28.61, 77.21],
              <double>[28.63, 77.23],
            ],
          },
        ],
        'recommendation': <String, dynamic>{
          'route_id': 'route-a',
          'reason': 'Lower estimated historical crime exposure.',
        },
      });

      expect(result.routes, hasLength(1));
      expect(result.recommendedRoute?.id, 'route-a');
      expect(
        result.recommendation?.reason,
        'Lower estimated historical crime exposure.',
      );
    });

    test('an entirely empty response is empty, not a crash', () {
      final RouteResultModel result =
          RouteResultModel.fromJson(<String, dynamic>{});

      expect(result.isEmpty, isTrue);
      expect(result.recommendedRoute, isNull);
    });

    test('keeps valid routes when one entry is malformed', () {
      final RouteResultModel result =
          RouteResultModel.fromJson(<String, dynamic>{
        'routes': <Object?>[
          <String, dynamic>{'id': 'broken', 'duration_minutes': 15},
          <String, dynamic>{
            'id': 'route-b',
            'duration_minutes': 18,
            'distance_km': 6.0,
            'geometry': <List<double>>[
              <double>[28.61, 77.21],
              <double>[28.63, 77.23],
            ],
          },
        ],
      });

      expect(result.routes, hasLength(1));
      expect(result.routes.single.id, 'route-b');
    });
  });

  group('LocationModel parsing', () {
    test('reads a search result', () {
      final LocationModel? place = LocationModel.fromJson(<String, dynamic>{
        'name': 'India Gate',
        'address': 'New Delhi',
        'latitude': 28.6129,
        'longitude': 77.2295,
      });

      expect(place!.name, 'India Gate');
      expect(place.latLng.latitude, 28.6129);
    });

    test('drops entries with no coordinates', () {
      expect(
        LocationModel.fromJson(<String, dynamic>{'name': 'Nowhere'}),
        isNull,
      );
    });

    test('accepts coordinates sent as strings', () {
      final LocationModel? place = LocationModel.fromJson(<String, dynamic>{
        'name': 'Karol Bagh',
        'lat': '28.6519',
        'lon': '77.1909',
      });

      expect(place!.latitude, 28.6519);
    });
  });

  group('CrimeIncidentModel parsing', () {
    test('formats the incident date for display', () {
      final CrimeIncidentModel? incident =
          CrimeIncidentModel.fromJson(<String, dynamic>{
        'id': 'c-1',
        'type': 'Theft',
        'latitude': 28.61,
        'longitude': 77.21,
        'date': '2024-05-12',
        'area': 'Central District',
      });

      expect(incident!.dateLabel, '12 May 2024');
      expect(incident.type, 'Theft');
    });

    test('handles a missing date without inventing one', () {
      final CrimeIncidentModel? incident =
          CrimeIncidentModel.fromJson(<String, dynamic>{
        'latitude': 28.61,
        'longitude': 77.21,
      });

      expect(incident!.dateLabel, 'Date not recorded');
      expect(incident.type, 'Unspecified');
    });
  });

  group('HeatmapPointModel parsing', () {
    test('reads exposure and clamps intensity', () {
      final HeatmapPointModel? point =
          HeatmapPointModel.fromJson(<String, dynamic>{
        'latitude': 28.61,
        'longitude': 77.21,
        'exposure': 'higher',
        'intensity': 1.4,
      });

      expect(point!.exposure, RiskLevel.high);
      expect(point.intensity, 1.0);
    });

    test('unrecognised exposure becomes unknown', () {
      final HeatmapPointModel? point =
          HeatmapPointModel.fromJson(<String, dynamic>{
        'latitude': 28.61,
        'longitude': 77.21,
        'exposure': 'extreme',
      });

      expect(point!.exposure, RiskLevel.unknown);
    });
  });

  group('RiskModel score display', () {
    test('normalises a 0..1 score to a whole percentage', () {
      expect(const RiskModel(level: RiskLevel.low, score: 0.7348291).scorePercent, 73);
    });

    test('accepts a score already given as a percentage', () {
      expect(const RiskModel(level: RiskLevel.high, score: 73.48).scorePercent, 73);
    });
  });
}
