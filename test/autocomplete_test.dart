import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:saferoute/models/location_model.dart';
import 'package:saferoute/screens/destination_search_screen.dart';
import 'package:saferoute/services/api_exception.dart';
import 'package:saferoute/utils/app_theme.dart';

import 'helpers/test_app.dart';

/// Search-as-you-type behaviour of the destination screen.
void main() {
  const Duration pastDebounce = Duration(milliseconds: 310);

  const LocationModel koramangala = LocationModel(
    name: 'Koramangala',
    address: 'Bangalore South, Bengaluru',
    locality: 'Koramangala',
    latitude: 12.9352,
    longitude: 77.6245,
  );
  const LocationModel kormangalaBlock = LocationModel(
    name: 'Koramangala 6th Block',
    address: 'Koramangala, Bengaluru',
    latitude: 12.9390,
    longitude: 77.6180,
  );
  const LocationModel korattur = LocationModel(
    name: 'Kor older result',
    address: 'Bengaluru',
    latitude: 12.95,
    longitude: 77.60,
  );

  Widget buildScreen(FakeLocationSearchService service) {
    return MaterialApp(
      theme: AppTheme.light,
      home: DestinationSearchScreen(service: service),
    );
  }

  testWidgets('a partial name produces suggestions', (tester) async {
    final FakeLocationSearchService service = FakeLocationSearchService(
      results: const <LocationModel>[koramangala, kormangalaBlock],
    );
    await tester.pumpWidget(buildScreen(service));

    await tester.enterText(find.byType(TextField), 'kora');
    await tester.pump(pastDebounce);
    await tester.pumpAndSettle();

    expect(service.queries, <String>['kora']);
    expect(find.text('Koramangala'), findsOneWidget);
    expect(find.text('Koramangala 6th Block'), findsOneWidget);
  });

  testWidgets('one character asks for more; two characters search',
      (tester) async {
    final FakeLocationSearchService service = FakeLocationSearchService(
      results: const <LocationModel>[koramangala],
    );
    await tester.pumpWidget(buildScreen(service));

    await tester.enterText(find.byType(TextField), 'k');
    await tester.pump(pastDebounce);
    await tester.pumpAndSettle();
    expect(service.queries, isEmpty);
    expect(find.text('Keep typing: enter at least 2 characters.'),
        findsOneWidget);

    await tester.enterText(find.byType(TextField), 'ko');
    await tester.pump(pastDebounce);
    await tester.pumpAndSettle();
    expect(service.queries, <String>['ko']);
    expect(find.text('Koramangala'), findsOneWidget);
  });

  testWidgets('fast typing is debounced into one request', (tester) async {
    final FakeLocationSearchService service = FakeLocationSearchService(
      results: const <LocationModel>[koramangala],
    );
    await tester.pumpWidget(buildScreen(service));

    for (final String text in <String>['k', 'ko', 'kor', 'kora']) {
      await tester.enterText(find.byType(TextField), text);
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(service.queries, isEmpty);

    await tester.pump(pastDebounce);
    await tester.pumpAndSettle();
    expect(service.queries, <String>['kora']);
  });

  testWidgets('suggestions update as the query changes', (tester) async {
    final FakeLocationSearchService service = FakeLocationSearchService(
      results: const <LocationModel>[korattur],
    );
    await tester.pumpWidget(buildScreen(service));

    await tester.enterText(find.byType(TextField), 'kor');
    await tester.pump(pastDebounce);
    await tester.pumpAndSettle();
    expect(find.text('Kor older result'), findsOneWidget);

    service.results = const <LocationModel>[koramangala];
    await tester.enterText(find.byType(TextField), 'koram');
    await tester.pump(pastDebounce);
    await tester.pumpAndSettle();

    expect(find.text('Koramangala'), findsOneWidget);
    expect(find.text('Kor older result'), findsNothing);
  });

  testWidgets('shows a loading indicator while searching', (tester) async {
    final FakeLocationSearchService service = FakeLocationSearchService()
      ..holdReplies = true;
    await tester.pumpWidget(buildScreen(service));

    await tester.enterText(find.byType(TextField), 'kora');
    await tester.pump(pastDebounce);

    expect(find.text('Searching…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    service.pending['kora']!.complete(const <LocationModel>[koramangala]);
    await tester.pumpAndSettle();

    expect(find.text('Searching…'), findsNothing);
    expect(find.text('Koramangala'), findsOneWidget);
  });

  testWidgets('keeps earlier suggestions visible while refining',
      (tester) async {
    final FakeLocationSearchService service = FakeLocationSearchService()
      ..holdReplies = true;
    await tester.pumpWidget(buildScreen(service));

    await tester.enterText(find.byType(TextField), 'kor');
    await tester.pump(pastDebounce);
    service.pending['kor']!.complete(const <LocationModel>[korattur]);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'kora');
    await tester.pump(pastDebounce);

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Kor older result'), findsOneWidget);

    service.pending['kora']!.complete(const <LocationModel>[koramangala]);
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('a slow older reply cannot overwrite a newer one',
      (tester) async {
    final FakeLocationSearchService service = FakeLocationSearchService()
      ..holdReplies = true;
    await tester.pumpWidget(buildScreen(service));

    await tester.enterText(find.byType(TextField), 'kor');
    await tester.pump(pastDebounce);
    await tester.enterText(find.byType(TextField), 'kora');
    await tester.pump(pastDebounce);

    // Newer query answers first, then the stale one arrives.
    service.pending['kora']!.complete(const <LocationModel>[koramangala]);
    await tester.pumpAndSettle();
    service.pending['kor']!.complete(const <LocationModel>[korattur]);
    await tester.pumpAndSettle();

    expect(find.text('Koramangala'), findsOneWidget);
    expect(find.text('Kor older result'), findsNothing);
  });

  testWidgets('a reply after clearing the field is ignored', (tester) async {
    final FakeLocationSearchService service = FakeLocationSearchService()
      ..holdReplies = true;
    await tester.pumpWidget(buildScreen(service));

    await tester.enterText(find.byType(TextField), 'kora');
    await tester.pump(pastDebounce);
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();

    service.pending['kora']!.complete(const <LocationModel>[koramangala]);
    await tester.pumpAndSettle();

    expect(find.text('Koramangala'), findsNothing);
    expect(
      find.text('Type a place name to search for your destination.'),
      findsOneWidget,
    );
  });

  testWidgets('spacing or case changes do not repeat the request',
      (tester) async {
    final FakeLocationSearchService service = FakeLocationSearchService(
      results: const <LocationModel>[koramangala],
    );
    await tester.pumpWidget(buildScreen(service));

    await tester.enterText(find.byType(TextField), 'kora');
    await tester.pump(pastDebounce);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  KORA ');
    await tester.pump(pastDebounce);
    await tester.pumpAndSettle();

    expect(service.queries, <String>['kora']);
    expect(find.text('Koramangala'), findsOneWidget);
  });

  testWidgets('sends the query with whitespace collapsed', (tester) async {
    final FakeLocationSearchService service = FakeLocationSearchService(
      results: const <LocationModel>[kormangalaBlock],
    );
    await tester.pumpWidget(buildScreen(service));

    await tester.enterText(find.byType(TextField), '  btm    layout ');
    await tester.pump(pastDebounce);
    await tester.pumpAndSettle();

    expect(service.queries, <String>['btm layout']);
  });

  testWidgets('no match shows a helpful empty state', (tester) async {
    await tester.pumpWidget(buildScreen(FakeLocationSearchService()));

    await tester.enterText(find.byType(TextField), 'zzqxv');
    await tester.pump(pastDebounce);
    await tester.pumpAndSettle();

    expect(
      find.text("Couldn't find that location. Try a different search."),
      findsOneWidget,
    );
    expect(find.textContaining('a landmark, road or pincode'),
        findsOneWidget);
  });

  testWidgets('a timeout is shown as a retryable error', (tester) async {
    final FakeLocationSearchService service = FakeLocationSearchService(
      error: const ApiException.timeout(),
    );
    await tester.pumpWidget(buildScreen(service));

    await tester.enterText(find.byType(TextField), 'kora');
    await tester.pump(pastDebounce);
    await tester.pumpAndSettle();

    expect(find.text('The request took too long. Please try again.'),
        findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);
    // An error is not presented as "no match".
    expect(
      find.text("Couldn't find that location. Try a different search."),
      findsNothing,
    );
  });

  testWidgets('selecting a suggestion returns its coordinates',
      (tester) async {
    final FakeLocationSearchService service = FakeLocationSearchService(
      results: const <LocationModel>[koramangala],
    );
    LocationModel? selected;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                selected = await Navigator.of(context).push<LocationModel>(
                  MaterialPageRoute<LocationModel>(
                    builder: (_) => DestinationSearchScreen(service: service),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'kora');
    await tester.pump(pastDebounce);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Koramangala'));
    await tester.pumpAndSettle();

    expect(selected?.latitude, 12.9352);
    expect(selected?.longitude, 77.6245);
    expect(selected?.locality, 'Koramangala');
  });

  testWidgets('finds places that are in no built-in list', (tester) async {
    final FakeLocationSearchService service = FakeLocationSearchService(
      results: const <LocationModel>[
        LocationModel(
          name: 'Hunasamaranahalli',
          address: 'Yelahanka taluku, Karnataka',
          latitude: 13.1453,
          longitude: 77.6201,
          crimeDataAvailable: true,
        ),
        LocationModel(
          name: 'Baga',
          address: 'Calangute, North Goa, Goa 403516',
          latitude: 15.5553,
          longitude: 73.7517,
          crimeDataAvailable: false,
        ),
      ],
    );
    await tester.pumpWidget(buildScreen(service));

    await tester.enterText(find.byType(TextField), 'huns');
    await tester.pump(pastDebounce);
    await tester.pumpAndSettle();

    expect(find.text('Hunasamaranahalli'), findsOneWidget);
    expect(find.text('Baga'), findsOneWidget);
    expect(find.text('Calangute, North Goa, Goa 403516'), findsOneWidget);
    // Only the place outside the crime-data area is labelled.
    expect(find.text('No crime-risk estimate here'), findsOneWidget);
    // Real search, so no sample-data banner.
    expect(find.textContaining('Sample data mode'), findsNothing);
  });

  testWidgets('passes the position along to rank nearby places',
      (tester) async {
    final FakeLocationSearchService service = FakeLocationSearchService();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: DestinationSearchScreen(
          service: service,
          near: const LatLng(19.06, 72.84),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'bandra');
    await tester.pump(pastDebounce);
    await tester.pumpAndSettle();

    expect(service.nearPositions.single, const LatLng(19.06, 72.84));
  });

  testWidgets('a provider failure is an error, not "no results"',
      (tester) async {
    final FakeLocationSearchService service = FakeLocationSearchService(
      error: const ApiException(
        ApiFailureKind.server,
        'Location search is temporarily unavailable. Please try again.',
      ),
    );
    await tester.pumpWidget(buildScreen(service));

    await tester.enterText(find.byType(TextField), 'indiranagar');
    await tester.pump(pastDebounce);
    await tester.pumpAndSettle();

    expect(find.text('Location search is temporarily unavailable. Please try again.'),
        findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);
    expect(find.text("Couldn't find that location. Try a different search."),
        findsNothing);

    service
      ..error = null
      ..results = const <LocationModel>[koramangala];
    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();
    expect(find.text('Koramangala'), findsOneWidget);
  });

  testWidgets('a rate limit shows the backend message', (tester) async {
    await tester.pumpWidget(buildScreen(FakeLocationSearchService(
      error: const ApiException(
        ApiFailureKind.rateLimited,
        'Too many searches right now. Please wait a moment and try again.',
      ),
    )));

    await tester.enterText(find.byType(TextField), 'bandra');
    await tester.pump(pastDebounce);
    await tester.pumpAndSettle();

    expect(find.textContaining('Too many searches'), findsOneWidget);
  });

  testWidgets('labels limited fallback results', (tester) async {
    final FakeLocationSearchService service = FakeLocationSearchService(
      results: const <LocationModel>[koramangala],
    )..degraded = true;
    await tester.pumpWidget(buildScreen(service));

    await tester.enterText(find.byType(TextField), 'kora');
    await tester.pump(pastDebounce);
    await tester.pumpAndSettle();

    expect(find.text('Koramangala'), findsOneWidget);
    expect(find.textContaining('Location search is limited right now'),
        findsOneWidget);
  });

  testWidgets('the clear button resets the query and results',
      (tester) async {
    final FakeLocationSearchService service = FakeLocationSearchService(
      results: const <LocationModel>[koramangala],
    );
    await tester.pumpWidget(buildScreen(service));

    await tester.enterText(find.byType(TextField), 'kora');
    await tester.pump(pastDebounce);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();

    expect(find.text('Koramangala'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    expect(find.text('Type a place name to search for your destination.'),
        findsOneWidget);
  });

  group('loading indicator', () {
    for (final Size size in <Size>[const Size(360, 640), const Size(412, 915)]) {
      testWidgets('sits centred just below the search field at '
          '${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        final FakeLocationSearchService service = FakeLocationSearchService()
          ..holdReplies = true;
        await tester.pumpWidget(buildScreen(service));

        await tester.enterText(find.byType(TextField), 'indr');
        await tester.pump(pastDebounce);

        final Rect field = tester.getRect(find.byType(TextField));
        final Rect spinner = tester.getRect(find.byType(CircularProgressIndicator));
        final Rect label = tester.getRect(find.text('Searching…'));

        // Directly beneath the field, not in the middle or at the bottom.
        expect(spinner.top, greaterThan(field.bottom));
        expect(spinner.top - field.bottom, lessThan(80));
        // Centred horizontally, with the label right under the spinner.
        expect(spinner.center.dx, moreOrLessEquals(size.width / 2, epsilon: 1));
        expect(label.center.dx, moreOrLessEquals(size.width / 2, epsilon: 1));
        expect(label.top, greaterThanOrEqualTo(spinner.bottom));
        expect(label.top - spinner.bottom, lessThan(24));

        service.pending['indr']!.complete(const <LocationModel>[]);
        await tester.pumpAndSettle();
      });
    }

    testWidgets('disappears after results', (tester) async {
      final FakeLocationSearchService service = FakeLocationSearchService()
        ..holdReplies = true;
      await tester.pumpWidget(buildScreen(service));
      await tester.enterText(find.byType(TextField), 'indr');
      await tester.pump(pastDebounce);
      expect(find.byKey(const ValueKey<String>('search-loading')), findsOneWidget);

      service.pending['indr']!.complete(const <LocationModel>[koramangala]);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey<String>('search-loading')), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('disappears after a failure, and retry shows it again',
        (tester) async {
      final FakeLocationSearchService service = FakeLocationSearchService(
        error: const ApiException(
          ApiFailureKind.network,
          "Couldn't connect to the SafeRoute server (api.example.com).",
        ),
      );
      await tester.pumpWidget(buildScreen(service));
      await tester.enterText(find.byType(TextField), 'indr');
      await tester.pump(pastDebounce);
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining("Couldn't connect"), findsOneWidget);

      service
        ..error = null
        ..holdReplies = true;
      await tester.tap(find.text('Try Again'));
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('search-loading')), findsOneWidget);
      expect(find.textContaining("Couldn't connect"), findsNothing);

      service.pending['indr']!.complete(const <LocationModel>[koramangala]);
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Koramangala'), findsOneWidget);
      expect(service.queries, <String>['indr', 'indr']);
    });

    testWidgets('is not shown before typing', (tester) async {
      await tester.pumpWidget(buildScreen(FakeLocationSearchService()));
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  testWidgets('an empty result says "No locations found"', (tester) async {
    await tester.pumpWidget(buildScreen(FakeLocationSearchService()));
    await tester.enterText(find.byType(TextField), 'zzqxv');
    await tester.pump(pastDebounce);
    await tester.pumpAndSettle();

    expect(find.text('No locations found'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a timeout clears the spinner and offers a retry',
      (tester) async {
    await tester.pumpWidget(buildScreen(FakeLocationSearchService(
      error: const ApiException(
        ApiFailureKind.timeout,
        'The SafeRoute server (api.example.com) did not respond in time. '
        'Please try again.',
      ),
    )));
    await tester.enterText(find.byType(TextField), 'majestic');
    await tester.pump(pastDebounce);
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('did not respond in time'), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);
  });
}
