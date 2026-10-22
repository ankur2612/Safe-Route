import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:saferoute/models/location_model.dart';
import 'package:saferoute/services/api_client.dart';
import 'package:saferoute/services/api_exception.dart';
import 'package:saferoute/services/location_service.dart';

/// `LocationSearchService` against a mocked backend, so nothing here depends
/// on a live geocoder.
void main() {
  late List<Uri> requests;

  LocationSearchService serviceReplying(
    FutureOr<http.Response> Function(http.Request request) reply, {
    DateTime Function()? clock,
  }) {
    requests = <Uri>[];
    return LocationSearchService(
      client: ApiClient(
        client: MockClient((http.Request request) async {
          requests.add(request.url);
          return reply(request);
        }),
      ),
      useMockData: false,
      clock: clock,
    );
  }

  http.Response results(List<Map<String, Object?>> places) =>
      http.Response(jsonEncode(<String, Object?>{'results': places}), 200);

  Map<String, Object?> place(String name, double lat, double lon) =>
      <String, Object?>{
        'name': name,
        'address': 'Bengaluru',
        'locality': name,
        'latitude': lat,
        'longitude': lon,
      };

  group('normalizeSearchQuery', () {
    test('trims and collapses whitespace', () {
      expect(normalizeSearchQuery('  HSR   Layout \t'), 'HSR Layout');
      expect(normalizeSearchQuery('   '), '');
    });
  });

  test('sends a partial query and parses name, locality and coordinates',
      () async {
    final LocationSearchService service = serviceReplying(
      (_) => results(<Map<String, Object?>>[place('Koramangala', 12.9352, 77.6245)]),
    );

    final List<LocationModel> found = (await service.search('kora')).places;

    expect(requests.single.path, '/api/v1/locations/search');
    expect(requests.single.queryParameters['q'], 'kora');
    expect(found.single.name, 'Koramangala');
    expect(found.single.locality, 'Koramangala');
    expect(found.single.latitude, 12.9352);
    expect(found.single.longitude, 77.6245);
  });

  test('normalises case and whitespace and reuses recent answers', () async {
    final LocationSearchService service = serviceReplying(
      (_) => results(<Map<String, Object?>>[place('HSR Layout', 12.9116, 77.6389)]),
    );

    await service.search('  hsr   layout ');
    await service.search('HSR LAYOUT');

    expect(requests, hasLength(1));
    expect(requests.single.queryParameters['q'], 'hsr layout');
  });

  test('cached answers expire', () async {
    DateTime now = DateTime(2026, 1, 1, 12);
    final LocationSearchService service = serviceReplying(
      (_) => results(const <Map<String, Object?>>[]),
      clock: () => now,
    );

    await service.search('hebbal');
    now = now.add(const Duration(minutes: 11));
    await service.search('hebbal');

    expect(requests, hasLength(2));
  });

  test('blank input makes no request', () async {
    final LocationSearchService service =
        serviceReplying((_) => results(const <Map<String, Object?>>[]));
    expect((await service.search('   ')).places, isEmpty);
    expect(requests, isEmpty);
  });

  test('drops entries without valid coordinates', () async {
    final LocationSearchService service = serviceReplying(
      (_) => results(<Map<String, Object?>>[
        place('Whitefield', 12.9698, 77.75),
        <String, Object?>{'name': 'No coordinates'},
        place('Out of range', 123.0, 77.6),
        <String, Object?>{'name': 'Text', 'latitude': 'abc', 'longitude': 77.6},
      ]),
    );

    final List<LocationModel> found = (await service.search('white')).places;
    expect(found.map((LocationModel p) => p.name), <String>['Whitefield']);
  });

  test('an empty result is an empty list, not an error', () async {
    final LocationSearchService service =
        serviceReplying((_) => results(const <Map<String, Object?>>[]));
    expect((await service.search('zzqxv')).places, isEmpty);
  });

  test('provider outage surfaces as an error and is not cached', () async {
    int calls = 0;
    final LocationSearchService service = serviceReplying((_) {
      calls++;
      return calls == 1
          ? http.Response('{"detail": "Location search is temporarily unavailable."}', 503)
          : results(<Map<String, Object?>>[place('Hebbal', 13.0358, 77.597)]);
    });

    await expectLater(
      service.search('hebbal'),
      throwsA(isA<ApiException>()
          .having((ApiException e) => e.kind, 'kind', ApiFailureKind.server)),
    );
    expect((await service.search('hebbal')).places.single.name, 'Hebbal');
  });

  test('a timeout surfaces as a timeout error', () async {
    final LocationSearchService service =
        serviceReplying((_) => throw TimeoutException('slow'));
    await expectLater(
      service.search('hebbal'),
      throwsA(isA<ApiException>()
          .having((ApiException e) => e.kind, 'kind', ApiFailureKind.timeout)),
    );
  });

  test('malformed JSON surfaces as a bad response', () async {
    final LocationSearchService service =
        serviceReplying((_) => http.Response('<html>', 200));
    await expectLater(
      service.search('hebbal'),
      throwsA(isA<ApiException>().having(
          (ApiException e) => e.kind, 'kind', ApiFailureKind.badResponse)),
    );
  });

  group('Bengaluru localities', () {
    const Map<String, List<double>> localities = <String, List<double>>{
      'Koramangala': <double>[12.9352, 77.6245],
      'HSR Layout': <double>[12.9116, 77.6389],
      'BTM Layout': <double>[12.9166, 77.6101],
      'Electronic City': <double>[12.8452, 77.6602],
      'Whitefield': <double>[12.9698, 77.75],
      'Yelahanka': <double>[13.1007, 77.5963],
      'Bagaluru': <double>[13.1338, 77.6683],
      'Hebbal': <double>[13.0358, 77.597],
      'Indiranagar': <double>[12.9784, 77.6408],
      'Jayanagar': <double>[12.9279, 77.5937],
      'Marathahalli': <double>[12.9569, 77.7011],
      'Rajajinagar': <double>[12.9916, 77.552],
      'Vijayanagar': <double>[12.9719, 77.5329],
      'Banashankari': <double>[12.9255, 77.5468],
      'Bellandur': <double>[12.9304, 77.6784],
      'Sarjapur Road': <double>[12.9242, 77.6289],
      'Thanisandra': <double>[13.0546, 77.6337],
      'Manyata Tech Park': <double>[13.0451, 77.6200],
    };

    for (final MapEntry<String, List<double>> entry in localities.entries) {
      test('partial "${entry.key}" yields valid coordinates', () async {
        final LocationSearchService service = serviceReplying(
          (_) => results(<Map<String, Object?>>[
            place(entry.key, entry.value[0], entry.value[1]),
          ]),
        );
        final String partial =
            entry.key.substring(0, (entry.key.length / 2).ceil());

        final LocationModel found = (await service.search(partial)).places.single;

        expect(requests.single.queryParameters['q'], partial);
        expect(found.name, entry.key);
        expect(isInServiceArea(found.latLng), isTrue);
      });
    }
  });

  test('one character is not sent; two are', () async {
    final LocationSearchService service =
        serviceReplying((_) => results(const <Map<String, Object?>>[]));
    expect((await service.search('k')).places, isEmpty);
    expect(requests, isEmpty);
    await service.search('ko');
    expect(requests, hasLength(1));
  });

  test('sends the position as a ranking hint and caches per area', () async {
    final LocationSearchService service =
        serviceReplying((_) => results(const <Map<String, Object?>>[]));

    await service.search('mg road', near: const LatLng(19.0596, 72.8295));
    await service.search('mg road', near: const LatLng(19.0601, 72.8301));
    await service.search('mg road', near: const LatLng(12.9716, 77.5946));

    expect(requests, hasLength(2));
    expect(requests.first.queryParameters['latitude'], '19.0596');
    expect(requests.first.queryParameters['longitude'], '72.8295');
  });

  test('parses category, place id and crime-data coverage', () async {
    final LocationSearchService service = serviceReplying(
      (_) => results(<Map<String, Object?>>[
        <String, Object?>{
          'name': 'Baga',
          'address': 'Calangute, Goa',
          'latitude': 15.5553,
          'longitude': 73.7517,
          'category': 'suburb',
          'place_id': 'osm:N42',
          'crime_data_available': false,
        },
      ]),
    );

    final LocationModel baga = (await service.search('baga')).places.single;
    expect(baga.category, 'suburb');
    expect(baga.placeId, 'osm:N42');
    expect(baga.crimeDataAvailable, isFalse);
  });

  test('a degraded answer is flagged and not cached', () async {
    final LocationSearchService service = serviceReplying(
      (_) => http.Response(
        jsonEncode(<String, Object?>{
          'results': <Map<String, Object?>>[place('Koramangala', 12.9352, 77.6245)],
          'degraded': true,
        }),
        200,
      ),
    );

    expect((await service.search('kora')).degraded, isTrue);
    await service.search('kora');
    expect(requests, hasLength(2));
  });

  test('a rate limit is its own error with the backend message', () async {
    final LocationSearchService service = serviceReplying(
      (_) => http.Response('{"detail": "Too many searches right now."}', 429),
    );
    await expectLater(
      service.search('bandra'),
      throwsA(isA<ApiException>()
          .having((ApiException e) => e.kind, 'kind', ApiFailureKind.rateLimited)
          .having((ApiException e) => e.message, 'message', 'Too many searches right now.')),
    );
  });

  group('places elsewhere in India', () {
    const Map<String, List<double>> places = <String, List<double>>{
      'Baga': <double>[15.5553, 73.7517],
      'Connaught Place': <double>[28.6315, 77.2167],
      'Bandra West': <double>[19.0596, 72.8295],
      'HITEC City': <double>[17.4504, 78.3808],
      'Salt Lake': <double>[22.58, 88.4155],
      'T. Nagar': <double>[13.0418, 80.2341],
    };

    for (final MapEntry<String, List<double>> entry in places.entries) {
      test('"${entry.key}" is returned with its own coordinates', () async {
        final LocationSearchService service = serviceReplying(
          (_) => results(<Map<String, Object?>>[
            <String, Object?>{
              ...place(entry.key, entry.value[0], entry.value[1]),
              'crime_data_available': false,
            },
          ]),
        );

        final LocationModel found =
            (await service.search(entry.key.substring(0, 4))).places.single;
        expect(found.latitude, entry.value[0]);
        expect(found.longitude, entry.value[1]);
        expect(isInServiceArea(found.latLng), isFalse);
        expect(found.crimeDataAvailable, isFalse);
      });
    }
  });

  test('a reply that is not a search response is an error, not "no results"',
      () async {
    final LocationSearchService service = serviceReplying(
      (_) => http.Response('{"status": "ok", "incidents": 2060}', 200),
    );
    await expectLater(
      service.search('indr'),
      throwsA(isA<ApiException>().having(
          (ApiException e) => e.kind, 'kind', ApiFailureKind.badResponse)),
    );
  });
}
