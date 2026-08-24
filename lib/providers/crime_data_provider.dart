import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models/crime_incident_model.dart';
import '../models/heatmap_point_model.dart';
import '../services/api_exception.dart';
import '../services/crime_service.dart';

enum CrimeDataStatus { idle, loading, success, empty, error }

/// Holds the historical crime records and heatmap cells for the visible area.
///
/// The two layers are fetched together but tracked as one status because they
/// describe the same underlying dataset.
class CrimeDataProvider extends ChangeNotifier {
  CrimeDataProvider({CrimeService? service})
      : _service = service ?? CrimeService();

  final CrimeService _service;

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

  LatLng? _lastCenter;

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

  Future<void> load(LatLng center) async {
    _lastCenter = center;
    _status = CrimeDataStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      // Both layers describe the same area, so request them together.
      final List<Object> results = await Future.wait<Object>(<Future<Object>>[
        _service.fetchHeatmap(center: center),
        _service.fetchCrimes(center: center),
      ]);

      _heatmapPoints = results[0] as List<HeatmapPointModel>;
      _incidents = results[1] as List<CrimeIncidentModel>;
      _status = hasData ? CrimeDataStatus.success : CrimeDataStatus.empty;
    } on ApiException catch (error) {
      _status = CrimeDataStatus.error;
      _errorMessage = error.message;
      _heatmapPoints = const <HeatmapPointModel>[];
      _incidents = const <CrimeIncidentModel>[];
    } catch (_) {
      _status = CrimeDataStatus.error;
      _errorMessage = 'Crime information is temporarily unavailable.';
      _heatmapPoints = const <HeatmapPointModel>[];
      _incidents = const <CrimeIncidentModel>[];
    }

    notifyListeners();
  }

  Future<void> retry() async {
    final LatLng? center = _lastCenter;
    if (center == null) return;
    await load(center);
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}
