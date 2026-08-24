import 'package:flutter_test/flutter_test.dart';
import 'package:saferoute/models/recommendation_model.dart';
import 'package:saferoute/models/risk_model.dart';
import 'package:saferoute/models/route_preference.dart';
import 'package:saferoute/widgets/recommendation_card.dart';

import 'helpers/test_app.dart';

void main() {
  group('RecommendationCard', () {
    testWidgets('shows time, distance, risk and the reason', (tester) async {
      await tester.pumpWidget(
        wrapForTest(
          RecommendationCard(
            route: buildRoute(
              name: 'Route B',
              durationMinutes: 19,
              distanceKm: 6.1,
              risk: RiskLevel.low,
            ),
            preference: RoutePreference.lowerRisk,
            recommendation: const RecommendationModel(
              routeId: 'route-a',
              reason: 'Lower estimated historical crime exposure than the '
                  'alternatives.',
            ),
          ),
        ),
      );

      expect(find.text('19 min • 6.1 km'), findsOneWidget);
      expect(find.text('LOW'), findsOneWidget);
      expect(find.text('Why this route?'), findsOneWidget);
      expect(
        find.textContaining('Lower estimated historical crime exposure'),
        findsOneWidget,
      );
    });

    testWidgets('titles the lower-risk pick as relatively safer',
        (tester) async {
      await tester.pumpWidget(
        wrapForTest(
          RecommendationCard(
            route: buildRoute(),
            preference: RoutePreference.lowerRisk,
          ),
        ),
      );

      expect(find.text('Relatively safer route'), findsOneWidget);
    });

    testWidgets('does not call the fastest pick a safer route',
        (tester) async {
      await tester.pumpWidget(
        wrapForTest(
          RecommendationCard(
            route: buildRoute(risk: RiskLevel.high),
            preference: RoutePreference.fastest,
          ),
        ),
      );

      expect(find.text('Fastest route'), findsOneWidget);
      expect(find.text('Relatively safer route'), findsNothing);
    });

    testWidgets('says so when risk is unavailable', (tester) async {
      await tester.pumpWidget(
        wrapForTest(
          RecommendationCard(
            route: buildRoute(risk: RiskLevel.unknown),
            preference: RoutePreference.balanced,
          ),
        ),
      );

      expect(
        find.text('Estimated risk is not available for this route.'),
        findsOneWidget,
      );
    });

    testWidgets('falls back to the risk reason when no recommendation reason',
        (tester) async {
      await tester.pumpWidget(
        wrapForTest(
          RecommendationCard(
            route: buildRoute(reason: 'Moderate historical crime exposure.'),
            preference: RoutePreference.balanced,
          ),
        ),
      );

      expect(
        find.text('Moderate historical crime exposure.'),
        findsOneWidget,
      );
    });
  });
}
