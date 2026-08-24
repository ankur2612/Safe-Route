import 'package:flutter/material.dart';

import '../models/recommendation_model.dart';
import '../models/risk_model.dart';
import '../models/route_model.dart';
import '../models/route_preference.dart';
import '../utils/app_theme.dart';
import 'risk_badge.dart';

/// Shows the route the backend recommends for the selected preference,
/// together with the reason it gave.
///
/// Wording is deliberately careful: the app never claims a route is safe,
/// only that its estimated historical crime exposure compares favourably.
class RecommendationCard extends StatelessWidget {
  const RecommendationCard({
    super.key,
    required this.route,
    required this.preference,
    this.recommendation,
    this.onViewDetails,
  });

  final RouteModel route;
  final RoutePreference preference;
  final RecommendationModel? recommendation;
  final VoidCallback? onViewDetails;

  /// Title reflects what the user actually asked for, so a "Fastest" pick is
  /// not mislabelled as the safer option.
  String get _title {
    switch (preference) {
      case RoutePreference.fastest:
        return 'Fastest route';
      case RoutePreference.balanced:
        return 'Balanced route';
      case RoutePreference.lowerRisk:
        return 'Relatively safer route';
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String? reason = recommendation?.reason ?? route.risk.reason;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.recommend_outlined,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _title,
                  style: text.titleMedium?.copyWith(color: AppColors.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(route.name, style: text.bodyMedium),
                    const SizedBox(height: 2),
                    Text(
                      '${route.durationLabel} • ${route.distanceLabel}',
                      style: text.titleLarge,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text('Estimated Risk', style: text.bodySmall),
                  const SizedBox(height: 4),
                  RiskBadge(level: route.risk.level),
                ],
              ),
            ],
          ),
          if (reason != null) ...<Widget>[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 14),
            Text(
              'Why this route?',
              style: text.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(reason, style: text.bodyMedium),
          ],
          if (!route.risk.level.isKnown) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              'Estimated risk is not available for this route.',
              style: text.bodySmall,
            ),
          ],
          if (onViewDetails != null) ...<Widget>[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onViewDetails,
                child: const Text('Compare all routes'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
