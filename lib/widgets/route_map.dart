import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/crime_incident_model.dart';
import '../models/heatmap_point_model.dart';
import '../models/location_model.dart';
import '../models/route_model.dart';
import '../utils/app_config.dart';
import '../utils/app_theme.dart';
import 'risk_badge.dart';

/// The main map: tiles, heatmap, crime markers, routes and endpoints.
///
/// It is a presentation widget only — it draws what it is given and reports
/// taps upward. No data loading or risk logic happens here.
class RouteMap extends StatelessWidget {
  const RouteMap({
    super.key,
    required this.controller,
    required this.initialCenter,
    this.currentPosition,
    this.destination,
    this.routes = const <RouteModel>[],
    this.selectedRouteId,
    this.heatmapPoints = const <HeatmapPointModel>[],
    this.incidents = const <CrimeIncidentModel>[],
    this.showHeatmap = true,
    this.showIncidents = false,
    this.onRouteTap,
    this.onIncidentTap,
  });

  final MapController controller;
  final LatLng initialCenter;
  final LatLng? currentPosition;
  final LocationModel? destination;
  final List<RouteModel> routes;
  final String? selectedRouteId;
  final List<HeatmapPointModel> heatmapPoints;
  final List<CrimeIncidentModel> incidents;
  final bool showHeatmap;
  final bool showIncidents;
  final ValueChanged<RouteModel>? onRouteTap;
  final ValueChanged<CrimeIncidentModel>? onIncidentTap;

  /// Colour a route is drawn with. Kept in sync with [RouteCard] through
  /// [routeLineColor] so the list and map always match.
  static Color routeLineColor(int index) =>
      AppColors.routeLines[index % AppColors.routeLines.length];

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: initialCenter,
        initialZoom: 13,
        minZoom: 4,
        maxZoom: 18,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: <Widget>[
        TileLayer(
          urlTemplate: AppConfig.mapTileUrl,
          userAgentPackageName: AppConfig.mapUserAgentPackageName,
          maxZoom: 19,
        ),
        if (showHeatmap && heatmapPoints.isNotEmpty)
          CircleLayer<Object>(circles: _buildHeatmapCircles()),
        ..._buildRouteLayers(),
        if (showIncidents && incidents.isNotEmpty)
          MarkerLayer(markers: _buildIncidentMarkers()),
        MarkerLayer(markers: _buildEndpointMarkers()),
      ],
    );
  }

  /// Approximates a heatmap with translucent circles.
  ///
  /// A dedicated heat layer would add a dependency for little gain at this
  /// scale, and circles keep the underlying streets readable.
  List<CircleMarker<Object>> _buildHeatmapCircles() {
    return <CircleMarker<Object>>[
      for (final HeatmapPointModel point in heatmapPoints)
        CircleMarker<Object>(
          point: point.latLng,
          radius: 240,
          useRadiusInMeter: true,
          color: RiskColors.foreground(point.exposure)
              .withValues(alpha: 0.16 + (point.intensity ?? 0.5) * 0.18),
          borderColor: RiskColors.foreground(point.exposure)
              .withValues(alpha: 0.28),
          borderStrokeWidth: 1,
        ),
    ];
  }

  /// Draws unselected routes first so the selected one sits on top.
  List<Widget> _buildRouteLayers() {
    if (routes.isEmpty) return const <Widget>[];

    final List<Polyline<Object>> background = <Polyline<Object>>[];
    final List<Polyline<Object>> foreground = <Polyline<Object>>[];

    for (int i = 0; i < routes.length; i++) {
      final RouteModel route = routes[i];
      final bool isSelected = route.id == selectedRouteId;

      final Polyline<Object> line = Polyline<Object>(
        points: route.points,
        strokeWidth: isSelected ? 6 : 4,
        color: isSelected ? routeLineColor(i) : AppColors.routeInactive,
        borderColor: Colors.white,
        borderStrokeWidth: isSelected ? 2 : 1,
      );

      if (isSelected) {
        foreground.add(line);
      } else {
        background.add(line);
      }
    }

    return <Widget>[
      if (background.isNotEmpty)
        PolylineLayer<Object>(polylines: background),
      if (foreground.isNotEmpty)
        PolylineLayer<Object>(polylines: foreground),
    ];
  }

  List<Marker> _buildIncidentMarkers() {
    return <Marker>[
      for (final CrimeIncidentModel incident in incidents)
        Marker(
          point: incident.latLng,
          width: 26,
          height: 26,
          child: GestureDetector(
            onTap: () => onIncidentTap?.call(incident),
            child: Semantics(
              button: true,
              label: 'Historical incident: ${incident.type}',
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.riskHigh.withValues(alpha: 0.85),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: const Icon(
                  Icons.priority_high,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
    ];
  }

  List<Marker> _buildEndpointMarkers() {
    final LatLng? position = currentPosition;
    final LocationModel? target = destination;

    return <Marker>[
      if (position != null)
        Marker(
          point: position,
          width: 24,
          height: 24,
          child: Semantics(
            label: 'Your current location',
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
              ),
            ),
          ),
        ),
      if (target != null)
        Marker(
          point: target.latLng,
          width: 34,
          height: 40,
          alignment: Alignment.topCenter,
          child: Semantics(
            label: 'Destination: ${target.name}',
            child: const Icon(
              Icons.location_on,
              size: 34,
              color: AppColors.riskHigh,
            ),
          ),
        ),
    ];
  }
}
