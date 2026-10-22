import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saferoute/models/risk_model.dart';
import 'package:saferoute/models/route_model.dart';
import 'package:saferoute/utils/app_theme.dart';
import 'package:saferoute/widgets/route_card.dart';

import 'helpers/test_app.dart';

void main() {
  group('RouteCard', () {
    testWidgets('shows name, time, distance and risk together', (tester) async {
      await tester.pumpWidget(
        wrapForTest(
          RouteCard(
            route: buildRoute(
              name: 'Route B',
              durationMinutes: 18,
              distanceKm: 6.0,
              risk: RiskLevel.low,
            ),
            isSelected: false,
            lineColor: AppColors.primary,
            onTap: () {},
          ),
        ),
      );

      expect(find.text('Route B'), findsOneWidget);
      expect(find.text('18 min'), findsOneWidget);
      expect(find.text('6.0 km'), findsOneWidget);
      expect(find.text('LOW'), findsOneWidget);
    });

    testWidgets('reports taps', (tester) async {
      RouteModel? tapped;

      final RouteModel route = buildRoute(id: 'route-c', name: 'Route C');
      await tester.pumpWidget(
        wrapForTest(
          RouteCard(
            route: route,
            isSelected: false,
            lineColor: AppColors.primary,
            onTap: () => tapped = route,
          ),
        ),
      );

      await tester.tap(find.text('Route C'));
      await tester.pump();

      expect(tapped?.id, 'route-c');
    });

    testWidgets('labels the recommended and fastest options', (tester) async {
      await tester.pumpWidget(
        wrapForTest(
          RouteCard(
            route: buildRoute(),
            isSelected: true,
            lineColor: AppColors.primary,
            isRecommended: true,
            isFastest: true,
            onTap: () {},
          ),
        ),
      );

      expect(find.text('Recommended'), findsOneWidget);
      expect(find.text('Fastest'), findsOneWidget);
    });

    testWidgets('shows N/A when the backend sent no risk', (tester) async {
      await tester.pumpWidget(
        wrapForTest(
          RouteCard(
            route: buildRoute(risk: RiskLevel.unknown),
            isSelected: false,
            lineColor: AppColors.primary,
            onTap: () {},
          ),
        ),
      );

      expect(find.text('N/A'), findsOneWidget);
      // No invented risk level should appear.
      expect(find.text('LOW'), findsNothing);
      expect(find.text('HIGH'), findsNothing);
    });
  });

  group('RouteCard Google Maps action', () {
    testWidgets('sits below the route details and keeps them intact',
        (tester) async {
      await tester.pumpWidget(
        wrapForTest(
          RouteCard(
            route: buildRoute(
              name: 'Route A',
              durationMinutes: 68,
              distanceKm: 23.3,
              risk: RiskLevel.high,
            ),
            isSelected: false,
            lineColor: AppColors.primary,
            onTap: () {},
            onOpenInGoogleMaps: () {},
          ),
        ),
      );

      expect(find.text('Open in Google Maps'), findsOneWidget);
      expect(find.text('68 min'), findsOneWidget);
      expect(find.text('23.3 km'), findsOneWidget);
      expect(find.text('HIGH'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Open in Google Maps')).dy,
        greaterThan(tester.getTopLeft(find.text('68 min')).dy),
      );
    });

    testWidgets('triggers only its own action, not the card tap',
        (tester) async {
      int cardTaps = 0;
      int mapsTaps = 0;
      await tester.pumpWidget(
        wrapForTest(
          RouteCard(
            route: buildRoute(),
            isSelected: false,
            lineColor: AppColors.primary,
            onTap: () => cardTaps++,
            onOpenInGoogleMaps: () => mapsTaps++,
          ),
        ),
      );

      await tester.tap(find.text('Open in Google Maps'));
      await tester.pump();

      expect(mapsTaps, 1);
      expect(cardTaps, 0);
    });

    testWidgets('is hidden without a handler', (tester) async {
      await tester.pumpWidget(
        wrapForTest(
          RouteCard(
            route: buildRoute(),
            isSelected: false,
            lineColor: AppColors.primary,
            onTap: () {},
          ),
        ),
      );

      expect(find.text('Open in Google Maps'), findsNothing);
    });

    testWidgets('fits a small screen with large text', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(1.3),
          ),
          child: wrapForTest(
            RouteCard(
              route: buildRoute(risk: RiskLevel.moderate),
              isSelected: true,
              lineColor: AppColors.primary,
              isRecommended: true,
              isFastest: true,
              onTap: () {},
              onOpenInGoogleMaps: () {},
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(OutlinedButton), findsOneWidget);
    });
  });
}
