import 'package:flutter/material.dart';

import '../utils/app_theme.dart';

/// Tappable field on the map screen that opens the search screen.
///
/// It is not an input itself: keeping typing on its own screen avoids the
/// results list covering the map.
class DestinationSearchBar extends StatelessWidget {
  const DestinationSearchBar({
    super.key,
    required this.onTap,
    this.destinationName,
    this.onClear,
  });

  final VoidCallback onTap;

  /// When set, the bar shows the chosen destination instead of the hint.
  final String? destinationName;

  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final String? name = destinationName;
    final bool hasDestination = name != null;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(8),
      elevation: 1.5,
      shadowColor: Colors.black26,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: <Widget>[
              const Icon(Icons.search, size: 21, color: AppColors.textMuted),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  hasDestination ? name : 'Search destination...',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    color: hasDestination
                        ? AppColors.textPrimary
                        : AppColors.textMuted,
                    fontWeight:
                        hasDestination ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
              ),
              if (hasDestination && onClear != null)
                IconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.close, size: 20),
                  color: AppColors.textSecondary,
                  tooltip: 'Clear destination',
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
