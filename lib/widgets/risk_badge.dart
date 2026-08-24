import 'package:flutter/material.dart';

import '../models/risk_model.dart';
import '../utils/app_theme.dart';

/// Colours for each risk level, kept in one place so the badge, route lines
/// and heatmap legend always agree.
class RiskColors {
  const RiskColors._();

  static Color foreground(RiskLevel level) {
    switch (level) {
      case RiskLevel.low:
        return AppColors.riskLow;
      case RiskLevel.moderate:
        return AppColors.riskModerate;
      case RiskLevel.high:
        return AppColors.riskHigh;
      case RiskLevel.unknown:
        return AppColors.riskUnknown;
    }
  }

  static Color surface(RiskLevel level) {
    switch (level) {
      case RiskLevel.low:
        return AppColors.riskLowSurface;
      case RiskLevel.moderate:
        return AppColors.riskModerateSurface;
      case RiskLevel.high:
        return AppColors.riskHighSurface;
      case RiskLevel.unknown:
        return AppColors.riskUnknownSurface;
    }
  }
}

/// Small pill showing an estimated risk level.
///
/// The text label is always present, so the level never depends on colour
/// alone to be understood.
class RiskBadge extends StatelessWidget {
  const RiskBadge({
    super.key,
    required this.level,
    this.compact = false,
  });

  final RiskLevel level;

  /// Smaller variant used inside dense route cards.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final Color foreground = RiskColors.foreground(level);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: RiskColors.surface(level),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: foreground.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: foreground,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            level.badgeLabel,
            style: TextStyle(
              color: foreground,
              fontSize: compact ? 11.5 : 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}
