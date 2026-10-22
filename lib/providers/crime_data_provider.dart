import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models/crime_incident_model.dart';
import '../models/heatmap_point_model.dart';
import '../models/route_model.dart';
import '../services/api_exception.dart';
import '../services/crime_service.dart';
import '../services/location_service.dart';

enum CrimeDataStatus { idle, loading, success, empty, error }

/// Holds the historical crime records and heatmap cells around the trip: the
/// origin, the destination (once chosen) and every candidate route.
///
/// Each of those areas is fetched on its own, cached, and merged without
/// duplicates, so choosing a new destination or preference only requests what
/// is new and the markers already on the map stay put while it loads.
class CrimeDataProvider extends ChangeNotifier {
  CrimeDataProvider({CrimeService? service})
    : _service = service ?? CrimeService();

  final CrimeService _service;

  static const int _cacheSize = 16;

  CrimeDataStatus _status = CrimeDataStatus.idle;
  CrimeDataStatus get status => _status;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  List<CrimeIncidentModel> _incidents = const <CrimeIncidentModel>[];
  List<CrimeIncidentModel> get incidents => _incidents;

  List<HeatmapPointModel> _heatmapPoints = const <HeatmapPointModel>[];
  List<HeatmapPointModel> get heatmapPoints => _heatmapPoints;

  bool _showHeatmap = true;
  bool get showHeatmap => _showHeatmap;

  bool _showIncidents = false;
  bool get showIncidents => _showIncidents;

  /// True when some areas loaded but others failed, so what is shown is
  /// incomplete rather than a full picture.
  bool _isPartial = false;
  bool get isPartial => _isPartial;

  /// Trip endpoints ("start", "destination") with no historical records
  /// nearby, so the UI can say that this means no data, not low exposure.
  List<String> _endpointsWithoutRecords = const <String>[];
  List<String> get endpointsWithoutRecords => _endpointsWithoutRecords;

  _TripRequest? _request;

  /// Bumped on every request so a slow, older response cannot overwrite the
  /// data for a newer trip.
  int _generation = 0;

  /// Successful answers per area, least recently used first.
  final Map<String, _AreaData> _cache = <String, _AreaData>{};

  bool get isLoading => _status == CrimeDataStatus.loading;

  bool get hasData => _heatmapPoints.isNotEmpty || _incidents.isNotEmpty;

  void toggleHeatmap() {
    _showHeatmap = !_showHeatmap;
    notifyListeners();
  }

  void toggleIncidents() {
    _showIncidents = !_showIncidents;
    notifyListeners();
  }

  /// Loads the area around a single point, e.g. before a destination is set.
  Future<void> load(LatLng center) => loadTrip(origin: center);

  /// Loads the origin, destination and route corridors together.
  ///
  /// Calling it again with the same trip is a no-op unless the previous
  /// attempt failed, so callers can safely call it after every state change.
  Future<void> loadTrip({
    required LatLng origin,
    LatLng? destination,
    List<RouteModel> routes = const <RouteModel>[],
  }) async {
    final _TripRequest request = _TripRequest(origin, destination, routes);
    final bool sameTrip = request.key == _request?.key;
    if (sameTrip &&
        (_status == CrimeDataStatus.loading ||
            ((_status == CrimeDataStatus.success ||
                    _status == CrimeDataStatus.empty) &&
                !_isPartial))) {
      return;
    }

    _request = request;
    final int generation = ++_generation;
    // Existing markers stay visible until the merged result is ready.
    _status = CrimeDataStatus.loading;
    _errorMessage = null;
    notifyListeners();

    final List<_AreaResult> results = await Future.wait(
      request.areas.map(_loadArea),
    );
    if (generation != _generation) return;

    final List<_AreaData> loaded = <_AreaData>[
      for (final _AreaResult result in results)
        if (result.data != null) result.data!,
    ];
    final String? firstError = results
        .map((_AreaResult r) => r.error)
        .whereType<String>()
        .firstOrNull;

    _incidents = _mergeIncidents(loaded);
    _heatmapPoints = _mergeHeatmap(loaded);
    _isPartial = firstError != null && loaded.isNotEmpty;
    _endpointsWithoutRecords = List<String>.unmodifiable(<String>[
      for (int i = 0; i < results.length; i++)
        if (request.areas[i].label != null && (results[i].data?.isEmpty ?? false))
          request.areas[i].label!,
    ]);

    if (firstError != null && !hasData) {
      // Nothing to show because of a failure: an error, never "no records".
      _status = CrimeDataStatus.error;
      _errorMessage = firstError;
    } else {
      _status = hasData ? CrimeDataStatus.success : CrimeDataStatus.empty;
      _errorMessage = _isPartial
          ? 'Some historical crime data could not be loaded.'
          : null;
    }
    notifyListeners();
  }

  Future<void> retry() async {
    final _TripRequest? request = _request;
    if (request == null) return;
    await loadTrip(
      origin: request.origin,
      destination: request.destination,
      routes: request.routes,
    );
  }

  Future<_AreaResult> _loadArea(_Area area) async {
    final _AreaData? cached = _cache.remove(area.key);
    if (cached != null) {
      _cache[area.key] = cached;
      return _AreaResult(data: cached);
    }

    try {
      final _AreaData data = await area.fetch(_service);
      _cache[area.key] = data;
      if (_cache.length > _cacheSize) _cache.remove(_cache.keys.first);
      return _AreaResult(data: data);
    } on ApiException catch (error) {
      return _AreaResult(error: error.message);
    } catch (_) {
      return const _AreaResult(
        error: 'Crime information is temporarily unavailable.',
      );
    }
  }

  /// One marker per record, even when the origin, destination and route
  /// queries all return it.
  static List<CrimeIncidentModel> _mergeIncidents(List<_AreaData> areas) {
    final Map<String, CrimeIncidentModel> unique =
        <String, CrimeIncidentModel>{};
    for (final _AreaData area in areas) {
      for (final CrimeIncidentModel incident in area.incidents) {
        unique.putIfAbsent(
          '${incident.id}@${incident.latitude.toStringAsFixed(5)},'
          '${incident.longitude.toStringAsFixed(5)}',
          () => incident,
        );
      }
    }
    return List<CrimeIncidentModel>.unmodifiable(unique.values);
  }

  static List<HeatmapPointModel> _mergeHeatmap(List<_AreaData> areas) {
    final Map<String, HeatmapPointModel> unique = <String, HeatmapPointModel>{};
    for (final _AreaData area in areas) {
      for (final HeatmapPointModel point in area.heatmap) {
        unique.putIfAbsent(
          '${point.latitude.toStringAsFixed(4)},'
          '${point.longitude.toStringAsFixed(4)}',
          () => point,
        );
      }
    }
    return List<HeatmapPointModel>.unmodifiable(unique.values);
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}

class _TripRequest {
  _TripRequest(this.origin, this.destination, this.routes)
    : areas = _unique(<_Area>[
        _Area.point(origin, label: 'start'),
        if (destination != null) _Area.point(destination, label: 'destination'),
        for (final RouteModel route in routes) _Area.route(route),
      ]) {
    key = areas.map((_Area a) => a.key).join('|');
  }

  /// Overlapping areas (identical routes, destination at the origin) are
  /// fetched once.
  static List<_Area> _unique(List<_Area> areas) {
    final Set<String> seen = <String>{};
    return areas.where((_Area a) => seen.add(a.key)).toList(growable: false);
  }

  final LatLng origin;
  final LatLng? destination;
  final List<RouteModel> routes;
  final List<_Area> areas;
  late final String key;
}

/// One area to fetch: the surroundings of a point, or a route's corridor.
class _Area {
  _Area.point(LatLng center, {this.label})
    : key =
          'p:${center.latitude.toStringAsFixed(4)},'
          '${center.longitude.toStringAsFixed(4)}',
      // Outside Bengaluru there is no crime data: nothing to request, and
      // the endpoint is reported as having no records (never as low risk).
      fetch = !isInServiceArea(center)
          ? ((CrimeService service) async => _AreaData.none)
          : ((CrimeService service) async {
        final List<Object> results = await Future.wait<Object>(<Future<Object>>[
          service.fetchHeatmap(center: center),
          service.fetchCrimes(center: center),
        ]);
        return _AreaData(
          incidents: results[1] as List<CrimeIncidentModel>,
          heatmap: results[0] as List<HeatmapPointModel>,
        );
      });

  _Area.route(RouteModel route)
    : label = null,
      key = 'r:${route.points.length}:${Object.hashAll(route.points)}',
      fetch = !route.points.any(isInServiceArea)
          ? ((CrimeService service) async => _AreaData.none)
          : ((CrimeService service) async => _AreaData(
        incidents: await service.fetchRouteCrimes(points: route.points),
        heatmap: const <HeatmapPointModel>[],
      ));

  final String key;

  /// Names a trip endpoint; null for route corridors.
  final String? label;
  final Future<_AreaData> Function(CrimeService service) fetch;
}

class _AreaData {
  const _AreaData({required this.incidents, required this.heatmap});

  static const _AreaData none = _AreaData(
    incidents: <CrimeIncidentModel>[],
    heatmap: <HeatmapPointModel>[],
  );

  bool get isEmpty => incidents.isEmpty && heatmap.isEmpty;

  final List<CrimeIncidentModel> incidents;
  final List<HeatmapPointModel> heatmap;
}

class _AreaResult {
  const _AreaResult({this.data, this.error});

  final _AreaData? data;
  final String? error;
}
