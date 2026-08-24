import 'package:flutter/material.dart';

import '../models/risk_model.dart';
import '../models/route_model.dart';
import '../utils/app_theme.dart';
import 'risk_badge.dart';

/// One route option in the comparison list.
///
/// Shows time, distance and estimated risk together so the trade-off between
/// them is visible at a glance.
class RouteCard extends StatelessWidget {
  const RouteCard({
    super.key,
    required this.route,
    required this.isSelected,
    required this.lineColor,
    required this.onTap,
    this.isRecommended = false,
    this.isFastest = false,
  });

  final RouteModel route;
  final bool isSelected;

  /// Matches the colour this route is drawn with on the map.
  final Color lineColor;

  final VoidCallback onTap;
  final bool isRecommended;
  final bool isFastest;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      selected: isSelected,
      label: '${route.name}, ${route.durationLabel}, ${route.distanceLabel}, '
          'estimated risk ${route.risk.level.description}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryLight : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  // Colour key tying this card to its line on the map.
                  Container(
                    width: 4,
                    height: 18,
                    decoration: BoxDecoration(
                      color: lineColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(route.name, style: text.titleMedium),
                  const Spacer(),
                  RiskBadge(level: route.risk.level, compact: true),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Text(
                    route.durationLabel,
                    style: text.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('•', style: TextStyle(color: AppColors.textMuted)),
                  const SizedBox(width: 8),
                  Text(route.distanceLabel, style: text.bodyMedium),
                ],
              ),
              if (isRecommended || isFastest) ...<Widget>[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    if (isRecommended)
                      const _RouteTag(
                        label: 'Recommended',
                        icon: Icons.check_circle_outline,
                        color: AppColors.primary,
                      ),
                    if (isFastest)
                      const _RouteTag(
                        label: 'Fastest',
                        icon: Icons.schedule,
                        color: AppColors.textSecondary,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteTag extends StatelessWidget {
  const _RouteTag({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
