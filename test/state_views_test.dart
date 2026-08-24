import 'package:flutter_test/flutter_test.dart';
import 'package:saferoute/widgets/state_views.dart';

import 'helpers/test_app.dart';

void main() {
  group('ErrorMessage', () {
    testWidgets('shows the message and a retry action', (tester) async {
      int retries = 0;

      await tester.pumpWidget(
        wrapForTest(
          ErrorMessage(
            message: "Couldn't generate routes right now.",
            onRetry: () => retries++,
          ),
        ),
      );

      expect(
        find.text("Couldn't generate routes right now."),
        findsOneWidget,
      );

      await tester.tap(find.text('Try Again'));
      await tester.pump();

      expect(retries, 1);
    });

    testWidgets('hides the action when there is nothing to retry',
        (tester) async {
      await tester.pumpWidget(
        wrapForTest(
          const ErrorMessage(
            message: 'Risk information is temporarily unavailable.',
          ),
        ),
      );

      expect(find.text('Try Again'), findsNothing);
    });

    testWidgets('supports a custom action label', (tester) async {
      await tester.pumpWidget(
        wrapForTest(
          ErrorMessage(
            message: 'Location access is needed to use your current position.',
            retryLabel: 'Open Settings',
            onRetry: () {},
          ),
        ),
      );

      expect(find.text('Open Settings'), findsOneWidget);
    });
  });

  group('EmptyMessage', () {
    testWidgets('states that no data exists without implying low risk',
        (tester) async {
      await tester.pumpWidget(
        wrapForTest(
          const EmptyMessage(
            message: 'No historical crime data is available for this area.',
          ),
        ),
      );

      expect(
        find.text('No historical crime data is available for this area.'),
        findsOneWidget,
      );
    });
  });

  group('LoadingMessage', () {
    testWidgets('explains what is happening while routes load',
        (tester) async {
      await tester.pumpWidget(
        wrapForTest(
          const LoadingMessage(
            title: 'Finding routes...',
            subtitle:
                'Checking historical crime exposure and comparing routes.',
          ),
        ),
      );

      expect(find.text('Finding routes...'), findsOneWidget);
      expect(
        find.text('Checking historical crime exposure and comparing routes.'),
        findsOneWidget,
      );
    });
  });
}
