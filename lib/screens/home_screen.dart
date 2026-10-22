import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/crime_incident_model.dart';
import '../models/location_model.dart';
import '../models/route_model.dart';
import '../models/route_preference.dart';
import '../navigation/app_routes.dart';
import '../providers/crime_data_provider.dart';
import '../providers/location_provider.dart';
import '../providers/route_provider.dart';
import '../services/google_maps_launcher.dart';
import '../services/location_service.dart';
import '../utils/app_theme.dart';
import '../widgets/crime_info_card.dart';
import '../widgets/destination_search_bar.dart';
import '../widgets/google_maps_action.dart';
import '../widgets/map_controls.dart';
import '../widgets/map_legend.dart';
import '../widgets/recommendation_card.dart';
import '../widgets/route_card.dart';
import '../widgets/route_map.dart';
import '../widgets/route_preference_selector.dart';
import '../widgets/state_views.dart';
import 'destination_search_screen.dart';

/// The main screen: an interactive map with a panel underneath that shows
/// whichever step of the flow the user is on.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.mapsLauncher = const GoogleMapsLauncher(),
  });

  /// Injectable for tests; opens routes in Google Maps.
  final GoogleMapsLauncher mapsLauncher;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MapController _mapController = MapController();

  /// Set once the map is built, so camera moves are not attempted early.
  bool _mapReady = false;

  /// Size of the map area, used to keep camera padding inside the map.
  Size? _mapSize;

  /// The trip the crime layers were last requested for, so they are only
  /// re-requested when the origin, destination or routes actually change.
  String? _crimeTripKey;
  List<RouteModel>? _crimeTripRoutes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialise());
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  /// Gets a position and moves the map there. The crime layers follow from
  /// [_syncCrimeData] once the position is known.
  Future<void> _initialise() async {
    if (!mounted) return;
    final LocationProvider location = context.read<LocationProvider>();
    await location.load();
    if (!mounted) return;

    final LatLng? position = location.currentPosition;
    if (position != null && !isInServiceArea(position)) {
      _showSnack(
        'Crime-risk estimates cover Bengaluru only. You can still search and '
        'get routes elsewhere in India.',
      );
    }
    _moveCamera(position ?? developmentFallbackCenter, 14);
  }

  Future<void> _recentre() async {
    final LocationProvider location = context.read<LocationProvider>();
    await location.load();
    if (!mounted) return;

    final LatLng? position = location.currentPosition;
    if (position != null) {
      _moveCamera(position, 15);
    } else if (location.errorMessage != null) {
      _showSnack(location.errorMessage!);
    }
  }

  void _moveCamera(LatLng center, double zoom) {
    if (!_mapReady) return;
    _mapController.move(center, zoom);
  }

  /// Frames the whole route so the user sees it end to end.
  void _fitRoute(RouteModel route) => _fitCoordinates(route.points);

  /// Frames both endpoints and every candidate route, rather than centring
  /// on the destination alone.
  void _fitTrip() {
    final RouteProvider routes = context.read<RouteProvider>();
    _fitCoordinates(<LatLng>[
      if (routes.start != null) routes.start!,
      if (routes.destination != null) routes.destination!.latLng,
      for (final RouteModel route in routes.routes) ...route.points,
    ]);
  }

  void _fitCoordinates(List<LatLng> coordinates) {
    if (!_mapReady || coordinates.isEmpty) return;
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: coordinates,
        padding: _fitPadding(),
        maxZoom: 16,
      ),
    );
  }

  /// Room for the search bar (top) and map buttons (right), capped to a share
  /// of the map. Fixed padding taller than a short map left nothing to fit
  /// into, which zoomed the camera onto the destination.
  EdgeInsets _fitPadding() {
    final Size size = _mapSize ?? const Size(360, 360);
    double vertical(double value) => math.min(value, size.height / 4);
    double horizontal(double value) => math.min(value, size.width / 5);
    return EdgeInsets.fromLTRB(
      horizontal(28),
      vertical(84),
      horizontal(76),
      vertical(28),
    );
  }

  /// Keeps the crime layers in step with the trip: the origin, the
  /// destination once chosen, and the routes once generated. While routes are
  /// loading the current layers are left alone, so markers do not disappear
  /// when the preference changes.
  void _syncCrimeData(LocationProvider location, RouteProvider routes) {
    if (location.status == LocationStatus.idle || location.isLoading) return;
    if (routes.isLoading) return;

    final LatLng? destination = routes.destination?.latLng;
    // A trip keeps the start its routes were generated from.
    final LatLng origin = (destination != null ? routes.start : null) ??
        location.currentPosition ??
        developmentFallbackCenter;
    final List<RouteModel> tripRoutes = routes.status == RouteStatus.success
        ? routes.routes
        : const <RouteModel>[];

    final String key = '$origin|$destination';
    if (key == _crimeTripKey && identical(tripRoutes, _crimeTripRoutes)) return;
    _crimeTripKey = key;
    _crimeTripRoutes = tripRoutes;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CrimeDataProvider>().loadTrip(
            origin: origin,
            destination: destination,
            routes: tripRoutes,
          );
    });
  }

  Future<void> _openInGoogleMaps(RouteModel route) {
    final RouteProvider routes = context.read<RouteProvider>();
    return openRouteInGoogleMaps(
      context,
      launcher: widget.mapsLauncher,
      origin: routes.start,
      destination: routes.destination?.latLng,
      route: route,
    );
  }

  Future<void> _openSearch() async {
    final LocationModel? destination = await Navigator.of(context).push<LocationModel>(
      MaterialPageRoute<LocationModel>(
        builder: (_) => DestinationSearchScreen(
          near: context.read<LocationProvider>().currentPosition,
        ),
      ),
    );

    if (destination == null || !mounted) return;
    await _findRoutes(destination);
  }

  Future<void> _findRoutes(LocationModel destination) async {
    final LocationProvider location = context.read<LocationProvider>();
    final RouteProvider routes = context.read<RouteProvider>();

    // Route from where the user really is (routing covers India; risk
    // estimates are added only inside Bengaluru). Without a position, fall
    // back to central Bengaluru so the flow stays usable.
    final LatLng start = location.currentPosition ?? developmentFallbackCenter;

    await routes.findRoutes(start: start, destination: destination);
    if (!mounted) return;
    _fitTrip();
  }

  Future<void> _retryRoutes() async {
    final RouteProvider routes = context.read<RouteProvider>();
    await routes.retry();
    if (!mounted) return;
    _fitTrip();
  }

  void _onRouteSelected(RouteModel route) {
    context.read<RouteProvider>().selectRoute(route.id);
    _fitRoute(route);
  }

  Future<void> _onPreferenceChanged(RoutePreference preference) async {
    final RouteProvider routes = context.read<RouteProvider>();
    await routes.setPreference(preference);
    if (!mounted) return;
    _fitTrip();
  }

  void _clearDestination() {
    context.read<RouteProvider>().clearRoutes();
    final LatLng? position = context.read<LocationProvider>().currentPosition;
    _moveCamera(position ?? developmentFallbackCenter, 14);
  }

  void _showIncidentDetails(CrimeIncidentModel incident) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => CrimeInfoCard(incident: incident),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final LocationProvider location = context.watch<LocationProvider>();
    final CrimeDataProvider crimeData = context.watch<CrimeDataProvider>();
    final RouteProvider routes = context.watch<RouteProvider>();
    _syncCrimeData(location, routes);

    // Mark the map usable after the first build so camera calls are safe.
    if (!_mapReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mapReady = true;
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('SafeRoute'),
        actions: <Widget>[
          IconButton(
            onPressed: () =>
                Navigator.of(context).pushNamed(AppRoutes.aboutRisk),
            icon: const Icon(Icons.info_outline),
            tooltip: 'About risk',
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                _mapSize = constraints.biggest;
                return Stack(
                  children: <Widget>[
                    RouteMap(
                      controller: _mapController,
                      initialCenter:
                          location.currentPosition ?? developmentFallbackCenter,
                      currentPosition: location.currentPosition,
                      destination: routes.destination,
                      routes: routes.routes,
                      selectedRouteId: routes.selectedRoute?.id,
                      heatmapPoints: crimeData.heatmapPoints,
                      incidents: crimeData.incidents,
                      showHeatmap: crimeData.showHeatmap,
                      showIncidents: crimeData.showIncidents,
                      onIncidentTap: _showIncidentDetails,
                    ),
                    Positioned(
                      top: 12,
                      left: 12,
                      right: 12,
                      child: DestinationSearchBar(
                        onTap: _openSearch,
                        destinationName: routes.destination?.name,
                        onClear: routes.destination == null
                            ? null
                            : _clearDestination,
                      ),
                    ),
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: Column(
                        children: <Widget>[
                          MapControlButton(
                            icon: Icons.layers_outlined,
                            tooltip: crimeData.showHeatmap
                                ? 'Hide crime heatmap'
                                : 'Show crime heatmap',
                            isActive: crimeData.showHeatmap,
                            onPressed: crimeData.toggleHeatmap,
                          ),
                          const SizedBox(height: 8),
                          MapControlButton(
                            icon: Icons.place_outlined,
                            tooltip: crimeData.showIncidents
                                ? 'Hide crime markers'
                                : 'Show crime markers',
                            isActive: crimeData.showIncidents,
                            onPressed: crimeData.toggleIncidents,
                          ),
                          const SizedBox(height: 8),
                          MapControlButton(
                            icon: Icons.my_location,
                            tooltip: 'Go to current location',
                            isBusy: location.isLoading,
                            onPressed: _recentre,
                          ),
                        ],
                      ),
                    ),
                    if (crimeData.showHeatmap && crimeData.heatmapPoints.isNotEmpty)
                      const Positioned(left: 12, bottom: 12, child: MapLegend()),
                  ],
                );
              },
            ),
          ),
          _BottomPanel(
            location: location,
            crimeData: crimeData,
            routes: routes,
            onRetryLocation: _initialise,
            onOpenLocationSettings: location.openSettings,
            onSearch: _openSearch,
            onRouteSelected: _onRouteSelected,
            onPreferenceChanged: _onPreferenceChanged,
            onRetryRoutes: _retryRoutes,
            onOpenInGoogleMaps: _openInGoogleMaps,
          ),
        ],
      ),
    );
  }
}

/// The panel under the map. It shows one thing at a time, matching whichever
/// step the user has reached.
class _BottomPanel extends StatelessWidget {
  const _BottomPanel({
    required this.location,
    required this.crimeData,
    required this.routes,
    required this.onRetryLocation,
    required this.onOpenLocationSettings,
    required this.onSearch,
    required this.onRouteSelected,
    required this.onPreferenceChanged,
    required this.onRetryRoutes,
    required this.onOpenInGoogleMaps,
  });

  final LocationProvider location;
  final CrimeDataProvider crimeData;
  final RouteProvider routes;
  final VoidCallback onRetryLocation;
  final VoidCallback onOpenLocationSettings;
  final VoidCallback onSearch;
  final ValueChanged<RouteModel> onRouteSelected;
  final ValueChanged<RoutePreference> onPreferenceChanged;
  final VoidCallback onRetryRoutes;
  final ValueChanged<RouteModel> onOpenInGoogleMaps;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          // Caps the panel so the map always keeps most of the screen.
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.46,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: _buildContent(context),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    // Location problems block the whole flow, so they come first.
    if (location.status == LocationStatus.error && !location.hasPosition) {
      return ErrorMessage(
        message: location.errorMessage ?? 'Unable to get your location.',
        icon: Icons.location_off_outlined,
        retryLabel: location.needsSettings ? 'Open Settings' : 'Try Again',
        onRetry:
            location.needsSettings ? onOpenLocationSettings : onRetryLocation,
      );
    }

    switch (routes.status) {
      case RouteStatus.loading:
        return const LoadingMessage(
          title: 'Finding routes...',
          subtitle: 'Checking historical crime exposure and comparing routes.',
        );

      case RouteStatus.error:
        return ErrorMessage(
          message: routes.errorMessage ?? "Couldn't generate routes right now.",
          onRetry: onRetryRoutes,
        );

      case RouteStatus.empty:
        return const EmptyMessage(
          message: 'No routes were found between these two points.',
          icon: Icons.route_outlined,
        );

      case RouteStatus.success:
        return _RouteResults(
          routes: routes,
          crimeData: crimeData,
          onRouteSelected: onRouteSelected,
          onPreferenceChanged: onPreferenceChanged,
          onOpenInGoogleMaps: onOpenInGoogleMaps,
        );

      case RouteStatus.idle:
        return _IdlePanel(
          location: location,
          crimeData: crimeData,
          onSearch: onSearch,
        );
    }
  }
}

/// Shown before a destination is chosen: a prompt plus the state of the
/// historical crime layer for the current area.
class _IdlePanel extends StatelessWidget {
  const _IdlePanel({
    required this.location,
    required this.crimeData,
    required this.onSearch,
  });

  final LocationProvider location;
  final CrimeDataProvider crimeData;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Where do you want to go?', style: text.titleMedium),
        const SizedBox(height: 6),
        Text(
          'Search a destination to compare routes by travel time and '
          'estimated historical crime exposure.',
          style: text.bodyMedium?.copyWith(height: 1.35),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onSearch,
            icon: const Icon(Icons.search, size: 20),
            label: const Text('Search destination'),
          ),
        ),
        if (location.isLoading) ...<Widget>[
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              const SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Text('Getting your location...', style: text.bodyMedium),
            ],
          ),
        ],
        if (crimeData.status == CrimeDataStatus.error) ...<Widget>[
          const SizedBox(height: 14),
          ErrorMessage(
            message: crimeData.errorMessage ??
                'Crime information is temporarily unavailable.',
            compact: true,
            onRetry: crimeData.retry,
          ),
        ],
        if (crimeData.status == CrimeDataStatus.empty) ...<Widget>[
          const SizedBox(height: 14),
          const EmptyMessage(
            message:
                'No historical crime data is available for this area.',
          ),
        ],
      ],
    );
  }
}

/// Preference selector, the recommendation, and the route options.
class _RouteResults extends StatelessWidget {
  const _RouteResults({
    required this.routes,
    required this.crimeData,
    required this.onRouteSelected,
    required this.onPreferenceChanged,
    required this.onOpenInGoogleMaps,
  });

  final RouteProvider routes;
  final CrimeDataProvider crimeData;
  final ValueChanged<RouteModel> onRouteSelected;
  final ValueChanged<RoutePreference> onPreferenceChanged;
  final ValueChanged<RouteModel> onOpenInGoogleMaps;

  @override
  Widget build(BuildContext context) {
    final RouteModel? recommended = routes.recommendedRoute;
    final RouteModel? fastest = routes.fastestRoute;
    final RouteModel? selected = routes.selectedRoute;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        RoutePreferenceSelector(
          selected: routes.preference,
          onChanged: onPreferenceChanged,
          enabled: !routes.isLoading,
        ),
        const SizedBox(height: 16),
        if (routes.coverageMessage != null) ...<Widget>[
          EmptyMessage(
            message: routes.coverageMessage!,
            icon: Icons.info_outline,
          ),
          const SizedBox(height: 16),
        ],
        if (recommended != null) ...<Widget>[
          RecommendationCard(
            route: recommended,
            preference: routes.preference,
            recommendation: routes.recommendation,
            onViewDetails: () =>
                Navigator.of(context).pushNamed(AppRoutes.comparison),
          ),
          const SizedBox(height: 16),
        ],
        Text(
          'All routes',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
        ),
        const SizedBox(height: 8),
        for (int i = 0; i < routes.routes.length; i++)
          Padding(
            padding: EdgeInsets.only(
              bottom: i == routes.routes.length - 1 ? 0 : 8,
            ),
            child: RouteCard(
              route: routes.routes[i],
              isSelected: routes.routes[i].id == selected?.id,
              lineColor: RouteMap.routeLineColor(i),
              isRecommended: routes.routes[i].id == recommended?.id,
              isFastest: routes.routes[i].id == fastest?.id,
              onTap: () => onRouteSelected(routes.routes[i]),
              onOpenInGoogleMaps: () => onOpenInGoogleMaps(routes.routes[i]),
            ),
          ),
        const SizedBox(height: 12),
        _CrimeDataNote(crimeData: crimeData),
        const _DataNote(),
        const SizedBox(height: 8),
        const _DataNote(text: googleMapsLimitationNote, icon: Icons.map_outlined),
      ],
    );
  }
}

/// Standing reminder that everything shown is an estimate from past records.
class _DataNote extends StatelessWidget {
  const _DataNote({
    this.text = 'Estimated risk is based on available historical crime data '
        'and cannot guarantee future safety.',
    this.icon = Icons.info_outline,
  });

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 15, color: AppColors.textMuted),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.3),
          ),
        ),
      ],
    );
  }
}

/// State of the crime layers for the trip, shown with the route results so
/// missing data is never mistaken for low exposure.
class _CrimeDataNote extends StatelessWidget {
  const _CrimeDataNote({required this.crimeData});

  final CrimeDataProvider crimeData;

  @override
  Widget build(BuildContext context) {
    final List<String> withoutRecords = crimeData.endpointsWithoutRecords;
    final Widget? note = switch (crimeData.status) {
      CrimeDataStatus.error => ErrorMessage(
          message: crimeData.errorMessage ??
              'Crime information is temporarily unavailable.',
          compact: true,
          onRetry: crimeData.retry,
        ),
      CrimeDataStatus.empty => const EmptyMessage(
          message: 'No historical crime records are available around this '
              'trip. This means there is no data, not that the area has lower '
              'crime exposure.',
        ),
      CrimeDataStatus.success when crimeData.isPartial => ErrorMessage(
          message: crimeData.errorMessage ??
              'Some historical crime data could not be loaded.',
          compact: true,
          onRetry: crimeData.retry,
        ),
      CrimeDataStatus.success when withoutRecords.isNotEmpty => EmptyMessage(
          message: 'No historical crime records are available near your '
              '${withoutRecords.join(' or ')}. This means there is no data '
              'there, not that it has lower crime exposure.',
        ),
      _ => null,
    };
    if (note == null) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(bottom: 10), child: note);
  }
}
