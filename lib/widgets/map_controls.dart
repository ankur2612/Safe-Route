import 'package:flutter/material.dart';

import '../utils/app_theme.dart';

/// Square map control button, e.g. recentre or toggle a layer.
class MapControlButton extends StatelessWidget {
  const MapControlButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isActive = false,
    this.isBusy = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Highlights the button when the layer it controls is switched on.
  final bool isActive;

  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          color: isActive ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: isBusy ? null : onPressed,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isActive ? AppColors.primary : AppColors.border,
                ),
              ),
              child: Center(
                child: isBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        icon,
                        size: 21,
                        color: isActive ? Colors.white : AppColors.textPrimary,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
