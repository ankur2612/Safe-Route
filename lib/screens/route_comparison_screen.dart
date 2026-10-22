import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/risk_model.dart';
import '../models/route_model.dart';
import '../navigation/app_routes.dart';
import '../providers/route_provider.dart';
import '../services/google_maps_launcher.dart';
import '../utils/app_theme.dart';
import '../widgets/google_maps_action.dart';
import '../widgets/risk_badge.dart';
import '../widgets/route_map.dart';
import '../widgets/route_preference_selector.dart';
import '../widgets/state_views.dart';

/// Side-by-side view of every route option.
///
/// Uses a vertical card list rather than a wide table so it stays readable on
/// a phone.
class RouteComparisonScreen extends StatelessWidget {
  const RouteComparisonScreen({
    super.key,
    this.mapsLauncher = const GoogleMapsLauncher(),
  });

  /// Injectable for tests; opens routes in Google Maps.
  final GoogleMapsLauncher mapsLauncher;

  @override
  Widget build(BuildContext context) {
    final RouteProvider routes = context.watch<RouteProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Compare routes')),
      body: routes.hasRoutes
          ? _ComparisonList(routes: routes, mapsLauncher: mapsLauncher)
          : const Padding(
              padding: EdgeInsets.all(16),
              child: EmptyMessage(
                message: 'No routes to compare yet. Search for a destination '
                    'first.',
                icon: Icons.route_outlined,
              ),
            ),
    );
  }
}

class _ComparisonList extends StatelessWidget {
  const _ComparisonList({required this.routes, required this.mapsLauncher});

  final RouteProvider routes;
  final GoogleMapsLauncher mapsLauncher;

  @override
  Widget build(BuildContext context) {
    final RouteModel? recommended = routes.recommendedRoute;
    final RouteModel? fastest = routes.fastestRoute;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        RoutePreferenceSelector(
          selected: routes.preference,
          enabled: !routes.isLoading,
          onChanged: (preference) async {
            await routes.setPreference(preference);
          },
        ),
        const SizedBox(height: 18),
        if (routes.isLoading)
          const LoadingMessage(title: 'Updating routes...')
        else
          for (int i = 0; i < routes.routes.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ComparisonCard(
                route: routes.routes[i],
                lineColor: RouteMap.routeLineColor(i),
                isRecommended: routes.routes[i].id == recommended?.id,
                isFastest: routes.routes[i].id == fastest?.id,
                onSelect: () {
                  routes.selectRoute(routes.routes[i].id);
                  Navigator.of(context)
                      .popUntil(ModalRoute.withName(AppRoutes.home));
                },
                onOpenInGoogleMaps: () => openRouteInGoogleMaps(
                  context,
                  launcher: mapsLauncher,
                  origin: routes.start,
                  destination: routes.destination?.latLng,
                  route: routes.routes[i],
                ),
              ),
            ),
        const SizedBox(height: 4),
        Text(
          'Estimated risk is based on available historical crime data. '
          'Historical data cannot guarantee future safety, and missing or '
          'incomplete records can affect the result.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4),
        ),
        const SizedBox(height: 8),
        Text(
          googleMapsLimitationNote,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4),
        ),
      ],
    );
  }
}

class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({
    required this.route,
    required this.lineColor,
    required this.isRecommended,
    required this.isFastest,
    required this.onSelect,
    required this.onOpenInGoogleMaps,
  });

  final RouteModel route;
  final Color lineColor;
  final bool isRecommended;
  final bool isFastest;
  final VoidCallback onSelect;
  final VoidCallback onOpenInGoogleMaps;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String? reason = route.risk.reason;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isRecommended ? AppColors.primary : AppColors.border,
          width: isRecommended ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
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
              if (isRecommended)
                const Text(
                  'Recommended',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: _Metric(label: 'Time', value: route.durationLabel),
              ),
              Expanded(
                child: _Metric(label: 'Distance', value: route.distanceLabel),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Estimated Risk', style: text.bodySmall),
                    const SizedBox(height: 5),
                    RiskBadge(level: route.risk.level, compact: true),
                  ],
                ),
              ),
            ],
          ),
          if (isFastest) ...<Widget>[
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                const Icon(
                  Icons.schedule,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 5),
                Text('Fastest option', style: text.bodySmall),
              ],
            ),
          ],
          if (reason != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(reason, style: text.bodyMedium?.copyWith(height: 1.35)),
          ],
          if (!route.risk.level.isKnown) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              'Estimated risk is not available for this route.',
              style: text.bodySmall,
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onSelect,
              child: const Text('Show on map'),
            ),
          ),
          const SizedBox(height: 8),
          GoogleMapsButton(
            routeName: route.name,
            onPressed: onOpenInGoogleMaps,
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: text.bodySmall),
        const SizedBox(height: 5),
        Text(
          value,
          style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
