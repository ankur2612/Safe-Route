/// How the user wants routes weighed. Sent to the backend, which decides
/// which route to recommend — the app does not rank routes itself.
enum RoutePreference { fastest, balanced, lowerRisk }

extension RoutePreferenceDisplay on RoutePreference {
  String get label {
    switch (this) {
      case RoutePreference.fastest:
        return 'Fastest';
      case RoutePreference.balanced:
        return 'Balanced';
      case RoutePreference.lowerRisk:
        return 'Lower Risk';
    }
  }

  /// Value sent in the API request body.
  String get apiValue {
    switch (this) {
      case RoutePreference.fastest:
        return 'fastest';
      case RoutePreference.balanced:
        return 'balanced';
      case RoutePreference.lowerRisk:
        return 'lower_risk';
    }
  }
}
