import 'package:flutter/material.dart';

import '../models/route_preference.dart';
import '../utils/app_theme.dart';

/// Lets the user choose how routes should be weighed.
///
/// The choice is sent to the backend, which decides the recommendation.
class RoutePreferenceSelector extends StatelessWidget {
  const RoutePreferenceSelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });

  final RoutePreference selected;
  final ValueChanged<RoutePreference> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Choose preference',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            for (final RoutePreference preference in RoutePreference.values)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: preference == RoutePreference.values.last ? 0 : 8,
                  ),
                  child: _PreferenceChip(
                    label: preference.label,
                    isSelected: preference == selected,
                    enabled: enabled,
                    onTap: () => onChanged(preference),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _PreferenceChip extends StatelessWidget {
  const _PreferenceChip({
    required this.label,
    required this.isSelected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color foreground = isSelected
        ? Colors.white
        : (enabled ? AppColors.textPrimary : AppColors.textMuted);

    return Semantics(
      button: true,
      selected: isSelected,
      label: '$label route preference',
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
