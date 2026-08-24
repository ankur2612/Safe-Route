import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saferoute/navigation/app_routes.dart';
import 'package:saferoute/screens/splash_screen.dart';
import 'package:saferoute/utils/app_theme.dart';

void main() {
  group('SplashScreen', () {
    testWidgets('shows the app name and tagline', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          initialRoute: AppRoutes.splash,
          routes: <String, WidgetBuilder>{
            AppRoutes.splash: (_) => const SplashScreen(),
            AppRoutes.home: (_) => const Scaffold(body: Text('home')),
          },
        ),
      );
      await tester.pump();

      expect(find.text('SafeRoute'), findsOneWidget);
      expect(find.text('Choose a relatively safer route.'), findsOneWidget);

      // Let the pending navigation timer expire so the test ends cleanly.
      await tester.pump(SplashScreen.displayDuration);
      await tester.pumpAndSettle();
    });

    testWidgets('moves on to the home route after its delay', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          initialRoute: AppRoutes.splash,
          routes: <String, WidgetBuilder>{
            AppRoutes.splash: (_) => const SplashScreen(),
            AppRoutes.home: (_) =>
                const Scaffold(body: Text('home-screen-stub')),
          },
        ),
      );

      expect(find.text('home-screen-stub'), findsNothing);

      await tester.pump(SplashScreen.displayDuration);
      await tester.pumpAndSettle();

      expect(find.text('home-screen-stub'), findsOneWidget);
      expect(find.byType(SplashScreen), findsNothing);
    });
  });
}
