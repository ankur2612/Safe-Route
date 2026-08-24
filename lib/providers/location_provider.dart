import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../services/location_service.dart';

enum LocationStatus { idle, loading, success, error }

/// Tracks the user's current position and any permission problem.
class LocationProvider extends ChangeNotifier {
  LocationProvider({DeviceLocationService? service})
      : _service = service ?? const DeviceLocationService();

  final DeviceLocationService _service;

  LocationStatus _status = LocationStatus.idle;
  LocationStatus get status => _status;

  LatLng? _currentPosition;
  LatLng? get currentPosition => _currentPosition;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  LocationErrorKind? _errorKind;
  LocationErrorKind? get errorKind => _errorKind;

  bool get isLoading => _status == LocationStatus.loading;

  bool get hasPosition => _currentPosition != null;

  /// True when the user must change a device setting rather than simply
  /// retrying, so the UI can offer "Open settings" instead of "Try again".
  bool get needsSettings => _errorKind == LocationErrorKind.permanentlyDenied;

  Future<void> load() async {
    _status = LocationStatus.loading;
    _errorMessage = null;
    _errorKind = null;
    notifyListeners();

    try {
      _currentPosition = await _service.getCurrentPosition();
      _status = LocationStatus.success;
    } on LocationException catch (error) {
      _status = LocationStatus.error;
      _errorMessage = error.message;
      _errorKind = error.kind;
    } catch (_) {
      _status = LocationStatus.error;
      _errorMessage = 'Unable to get your location.';
      _errorKind = LocationErrorKind.failed;
    }

    notifyListeners();
  }

  Future<void> openSettings() => _service.openSettings();
}
