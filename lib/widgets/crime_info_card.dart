import 'package:flutter/material.dart';

import '../models/crime_incident_model.dart';
import '../utils/app_theme.dart';

/// Details for a single historical incident, shown after tapping a marker.
///
/// The closing note is important: an old record says nothing definite about
/// conditions at that place today.
class CrimeInfoCard extends StatelessWidget {
  const CrimeInfoCard({super.key, required this.incident});

  final CrimeIncidentModel incident;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 16 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Historical incident', style: text.titleMedium),
          const SizedBox(height: 14),
          _DetailRow(label: 'Type', value: incident.type),
          _DetailRow(label: 'Date', value: incident.dateLabel),
          if (incident.area != null)
            _DetailRow(label: 'Area', value: incident.area!),
          if (incident.description != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(incident.description!, style: text.bodyMedium),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(
                  Icons.history,
                  size: 17,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'This is a past record from the available crime dataset. '
                    'It does not describe current conditions at this location.',
                    style: text.bodySmall?.copyWith(height: 1.35),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 68,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
