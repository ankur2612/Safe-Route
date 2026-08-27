import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:saferoute/main.dart';
import 'package:saferoute/providers/crime_data_provider.dart';
import 'package:saferoute/providers/location_provider.dart';
import 'package:saferoute/providers/route_provider.dart';
import 'package:saferoute/screens/splash_screen.dart';
import 'package:saferoute/utils/app_theme.dart';

void main() {
  group('SafeRouteApp', () {
    // The splash screen holds a timer that navigates to the home screen, and
    // the real home screen reaches for GPS and the network. Replacing the tree
    // disposes the splash screen, which cancels that timer, so these tests
    // stay on the first screen.
    Future<void> disposeApp(WidgetTester tester) =>
        tester.pumpWidget(const SizedBox.shrink());

    testWidgets('starts on the splash screen', (tester) async {
      await tester.pumpWidget(const SafeRouteApp());
      await tester.pump();

      expect(find.byType(SplashScreen), findsOneWidget);
      expect(find.text('SafeRoute'), findsOneWidget);

      await disposeApp(tester);
    });

    testWidgets('provides the app state to the screens below it', (
      tester,
    ) async {
      await tester.pumpWidget(const SafeRouteApp());
      await tester.pump();

      final BuildContext context = tester.element(find.byType(SplashScreen));

      expect(context.read<LocationProvider>(), isNotNull);
      expect(context.read<RouteProvider>(), isNotNull);
      expect(context.read<CrimeDataProvider>(), isNotNull);

      await disposeApp(tester);
    });

    testWidgets('applies the app theme and hides the debug banner', (
      tester,
    ) async {
      await tester.pumpWidget(const SafeRouteApp());
      await tester.pump();

      final MaterialApp app = tester.widget<MaterialApp>(
        find.byType(MaterialApp),
      );

      expect(app.theme, AppTheme.light);
      expect(app.debugShowCheckedModeBanner, isFalse);

      await disposeApp(tester);
    });
  });
}
