/// The kinds of failure the UI needs to tell apart.
enum ApiFailureKind {
  network,
  timeout,
  server,
  badResponse,
  notFound,
  permission,
}

/// A single error type for the service layer so screens can show a sensible
/// message without inspecting HTTP details.
class ApiException implements Exception {
  const ApiException(this.kind, this.message);

  final ApiFailureKind kind;

  /// Message safe to show to the user.
  final String message;

  const ApiException.network()
      : kind = ApiFailureKind.network,
        message = 'No internet connection. Check your network and try again.';

  const ApiException.timeout()
      : kind = ApiFailureKind.timeout,
        message = 'The request took too long. Please try again.';

  const ApiException.badResponse()
      : kind = ApiFailureKind.badResponse,
        message = 'Received an unexpected response from the server.';

  @override
  String toString() => 'ApiException($kind): $message';
}
