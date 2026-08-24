import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saferoute/models/risk_model.dart';
import 'package:saferoute/widgets/risk_badge.dart';

import 'helpers/test_app.dart';

void main() {
  group('RiskBadge', () {
    testWidgets('shows a text label for every risk level', (tester) async {
      for (final (RiskLevel level, String expected) in <(RiskLevel, String)>[
        (RiskLevel.low, 'LOW'),
        (RiskLevel.moderate, 'MEDIUM'),
        (RiskLevel.high, 'HIGH'),
        (RiskLevel.unknown, 'N/A'),
      ]) {
        await tester.pumpWidget(wrapForTest(RiskBadge(level: level)));
        expect(
          find.text(expected),
          findsOneWidget,
          reason: 'risk level $level should be labelled "$expected"',
        );
      }
    });

    testWidgets('uses a distinct colour per level', (tester) async {
      await tester.pumpWidget(
        wrapForTest(
          const Column(
            children: <Widget>[
              RiskBadge(level: RiskLevel.low),
              RiskBadge(level: RiskLevel.high),
            ],
          ),
        ),
      );

      expect(
        RiskColors.foreground(RiskLevel.low),
        isNot(RiskColors.foreground(RiskLevel.high)),
      );
    });
  });

  group('RiskModel', () {
    test('maps backend risk strings onto levels', () {
      expect(RiskModel.parseLevel('low'), RiskLevel.low);
      expect(RiskModel.parseLevel('MEDIUM'), RiskLevel.moderate);
      expect(RiskModel.parseLevel('moderate'), RiskLevel.moderate);
      expect(RiskModel.parseLevel('High'), RiskLevel.high);
    });

    test('falls back to unknown for missing or unexpected values', () {
      expect(RiskModel.parseLevel(null), RiskLevel.unknown);
      expect(RiskModel.parseLevel('critical'), RiskLevel.unknown);
      expect(RiskModel.parseLevel(7), RiskLevel.unknown);
    });

    test('parses a full risk payload', () {
      final RiskModel risk = RiskModel.fromJson(<String, dynamic>{
        'risk': 'low',
        'score': 0.24,
        'reason': 'Lower estimated historical crime exposure',
      });

      expect(risk.level, RiskLevel.low);
      expect(risk.scorePercent, 24);
      expect(risk.reason, 'Lower estimated historical crime exposure');
    });

    test('handles a response with no risk fields at all', () {
      final RiskModel risk = RiskModel.fromJson(<String, dynamic>{});

      expect(risk.level, RiskLevel.unknown);
      expect(risk.score, isNull);
      expect(risk.scorePercent, isNull);
      expect(risk.reason, isNull);
    });

    test('unknown risk sorts last so it is never treated as safer', () {
      final List<RiskLevel> levels = <RiskLevel>[
        RiskLevel.unknown,
        RiskLevel.high,
        RiskLevel.low,
        RiskLevel.moderate,
      ]..sort((a, b) => a.comparisonRank.compareTo(b.comparisonRank));

      expect(levels.last, RiskLevel.unknown);
      expect(levels.first, RiskLevel.low);
    });
  });
}
