import 'package:flutter/material.dart';

import '../models/risk_model.dart';
import '../utils/app_theme.dart';
import 'risk_badge.dart';

/// Compact legend explaining the heatmap colours.
///
/// Deliberately small so it does not compete with the map itself.
class MapLegend extends StatelessWidget {
  const MapLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Historical crime exposure',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 6),
          const _LegendRow(level: RiskLevel.low, label: 'Lower'),
          const SizedBox(height: 3),
          const _LegendRow(level: RiskLevel.moderate, label: 'Medium'),
          const SizedBox(height: 3),
          const _LegendRow(level: RiskLevel.high, label: 'Higher'),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.level, required this.label});

  final RiskLevel level;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: RiskColors.foreground(level).withValues(alpha: 0.65),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
