import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saferoute/models/location_model.dart';
import 'package:saferoute/screens/destination_search_screen.dart';
import 'package:saferoute/services/api_exception.dart';
import 'package:saferoute/utils/app_theme.dart';

import 'helpers/test_app.dart';

void main() {
  /// The screen debounces input, so tests advance past that window.
  const Duration pastDebounce = Duration(milliseconds: 400);

  const List<LocationModel> delhiPlaces = <LocationModel>[
    LocationModel(
      name: 'Connaught Place',
      address: 'New Delhi',
      latitude: 28.6315,
      longitude: 77.2167,
    ),
    LocationModel(
      name: 'India Gate',
      address: 'New Delhi',
      latitude: 28.6129,
      longitude: 77.2295,
    ),
  ];

  Widget buildScreen(FakeLocationSearchService service) {
    return MaterialApp(
      theme: AppTheme.light,
      home: DestinationSearchScreen(service: service),
    );
  }

  testWidgets('prompts the user before any search', (tester) async {
    await tester.pumpWidget(buildScreen(FakeLocationSearchService()));

    expect(find.text('Where do you want to go?'), findsOneWidget);
    expect(
      find.text('Type a place name to search for your destination.'),
      findsOneWidget,
    );
  });

  testWidgets('lists matching places', (tester) async {
    final FakeLocationSearchService service =
        FakeLocationSearchService(results: delhiPlaces);

    await tester.pumpWidget(buildScreen(service));
    await tester.enterText(find.byType(TextField), 'delhi');
    await tester.pump(pastDebounce);
    await tester.pumpAndSettle();

    expect(find.text('Connaught Place'), findsOneWidget);
    expect(find.text('India Gate'), findsOneWidget);
    expect(service.queries, contains('delhi'));
  });

  testWidgets('returns the chosen place to the caller', (tester) async {
    final FakeLocationSearchService service =
        FakeLocationSearchService(results: delhiPlaces);
    LocationModel? selected;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  selected = await Navigator.of(context).push<LocationModel>(
                    MaterialPageRoute<LocationModel>(
                      builder: (_) =>
                          DestinationSearchScreen(service: service),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'india');
    await tester.pump(pastDebounce);
    await tester.pumpAndSettle();

    await tester.tap(find.text('India Gate'));
    await tester.pumpAndSettle();

    expect(selected?.name, 'India Gate');
  });

  testWidgets('shows a not-found message for no matches', (tester) async {
    await tester.pumpWidget(buildScreen(FakeLocationSearchService()));

    await tester.enterText(find.byType(TextField), 'nowhere');
    await tester.pump(pastDebounce);
    await tester.pumpAndSettle();

    expect(
      find.text("Couldn't find that location. Try a different search."),
      findsOneWidget,
    );
  });

  testWidgets('shows a retryable error when the search fails',
      (tester) async {
    final FakeLocationSearchService service = FakeLocationSearchService(
      error: const ApiException.network(),
    );

    await tester.pumpWidget(buildScreen(service));
    await tester.enterText(find.byType(TextField), 'delhi');
    await tester.pump(pastDebounce);
    await tester.pumpAndSettle();

    expect(find.textContaining("Couldn't connect to the SafeRoute server"), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);

    // Recovering should replace the error with results.
    service
      ..error = null
      ..results = delhiPlaces;
    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();

    expect(find.text('Connaught Place'), findsOneWidget);
  });

  testWidgets('clearing the field returns to the prompt', (tester) async {
    final FakeLocationSearchService service =
        FakeLocationSearchService(results: delhiPlaces);

    await tester.pumpWidget(buildScreen(service));
    await tester.enterText(find.byType(TextField), 'delhi');
    await tester.pump(pastDebounce);
    await tester.pumpAndSettle();
    expect(find.text('Connaught Place'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();

    expect(find.text('Connaught Place'), findsNothing);
    expect(
      find.text('Type a place name to search for your destination.'),
      findsOneWidget,
    );
  });
}
