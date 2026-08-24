import 'package:flutter/material.dart';

import '../models/risk_model.dart';
import '../utils/app_theme.dart';
import '../widgets/risk_badge.dart';

/// Explains what the risk estimate means and what it cannot tell the user.
///
/// The PRD requires these accuracy statements to be available in the app, so
/// they live on their own screen rather than being squeezed into the map.
class AboutRiskScreen extends StatelessWidget {
  const AboutRiskScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('About risk')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('How SafeRoute estimates risk', style: text.titleMedium),
          const SizedBox(height: 8),
          Text(
            'SafeRoute looks at recorded historical crime data near each '
            'route and uses it to estimate how much historical crime '
            'exposure that route has. Routes are then compared on travel '
            'time, distance and this estimate.',
            style: text.bodyLarge?.copyWith(height: 1.45),
          ),
          const SizedBox(height: 24),
          Text('What the risk levels mean', style: text.titleMedium),
          const SizedBox(height: 12),
          const _LevelExplanation(
            level: RiskLevel.low,
            description:
                'Lower recorded historical crime exposure compared with the '
                'other routes shown.',
          ),
          const SizedBox(height: 10),
          const _LevelExplanation(
            level: RiskLevel.moderate,
            description:
                'Moderate recorded historical crime exposure compared with '
                'the other routes shown.',
          ),
          const SizedBox(height: 10),
          const _LevelExplanation(
            level: RiskLevel.high,
            description:
                'Higher recorded historical crime exposure compared with the '
                'other routes shown.',
          ),
          const SizedBox(height: 24),
          Text('Important limitations', style: text.titleMedium),
          const SizedBox(height: 12),
          const _Limitation(
            'These are estimates, not guarantees. SafeRoute never describes '
            'any route or area as safe.',
          ),
          const _Limitation(
            'Historical crime data describes what was recorded in the past. '
            'It cannot predict or guarantee future safety.',
          ),
          const _Limitation(
            'Missing, old or incomplete records can affect the result. An '
            'area with few records is not necessarily a low-risk area — it '
            'may simply have less data.',
          ),
          const _Limitation(
            'Risk levels are relative to the routes being compared, not an '
            'absolute measure.',
          ),
          const _Limitation(
            'Always use your own judgement and follow local guidance.',
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              'SafeRoute is a student project built to demonstrate route '
              'comparison using historical crime data. It is not an '
              'emergency service.',
              style: text.bodyMedium?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelExplanation extends StatelessWidget {
  const _LevelExplanation({required this.level, required this.description});

  final RiskLevel level;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              RiskBadge(level: level),
              const SizedBox(width: 10),
              Text(
                level.description,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _Limitation extends StatelessWidget {
  const _Limitation(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(Icons.circle, size: 5, color: AppColors.textMuted),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
