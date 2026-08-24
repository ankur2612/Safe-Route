import 'package:flutter_test/flutter_test.dart';
import 'package:saferoute/models/route_preference.dart';
import 'package:saferoute/widgets/route_preference_selector.dart';

import 'helpers/test_app.dart';

void main() {
  group('RoutePreferenceSelector', () {
    testWidgets('offers all three preferences from the PRD', (tester) async {
      await tester.pumpWidget(
        wrapForTest(
          RoutePreferenceSelector(
            selected: RoutePreference.balanced,
            onChanged: (_) {},
          ),
        ),
      );

      expect(find.text('Fastest'), findsOneWidget);
      expect(find.text('Balanced'), findsOneWidget);
      expect(find.text('Lower Risk'), findsOneWidget);
    });

    testWidgets('reports the chosen preference', (tester) async {
      RoutePreference? chosen;

      await tester.pumpWidget(
        wrapForTest(
          RoutePreferenceSelector(
            selected: RoutePreference.balanced,
            onChanged: (RoutePreference value) => chosen = value,
          ),
        ),
      );

      await tester.tap(find.text('Lower Risk'));
      await tester.pump();

      expect(chosen, RoutePreference.lowerRisk);
    });

    testWidgets('ignores taps while disabled', (tester) async {
      RoutePreference? chosen;

      await tester.pumpWidget(
        wrapForTest(
          RoutePreferenceSelector(
            selected: RoutePreference.fastest,
            enabled: false,
            onChanged: (RoutePreference value) => chosen = value,
          ),
        ),
      );

      await tester.tap(find.text('Balanced'));
      await tester.pump();

      expect(chosen, isNull);
    });
  });

  test('preference api values match the backend contract', () {
    expect(RoutePreference.fastest.apiValue, 'fastest');
    expect(RoutePreference.balanced.apiValue, 'balanced');
    expect(RoutePreference.lowerRisk.apiValue, 'lower_risk');
  });
}
