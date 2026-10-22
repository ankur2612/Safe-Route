/// The kinds of failure the UI needs to tell apart.
enum ApiFailureKind {
  /// The server could not be reached (refused, unreachable, connection lost).
  network,

  /// The server name could not be resolved (DNS).
  hostLookup,

  /// The secure (TLS) connection to the server failed.
  secureConnection,

  /// The app was built with an unusable server address.
  configuration,
  timeout,
  server,
  badResponse,
  notFound,
  permission,
  rateLimited,
}

/// A single error type for the service layer so screens can show a sensible
/// message without inspecting HTTP details.
class ApiException implements Exception {
  const ApiException(this.kind, this.message);

  final ApiFailureKind kind;

  /// Message safe to show to the user.
  final String message;

  /// A request reached no server. This alone does not prove the phone is
  /// offline (the server may be down or the address wrong), so the message
  /// does not claim that.
  const ApiException.network()
      : kind = ApiFailureKind.network,
        message = "Couldn't connect to the SafeRoute server. Check your "
            'connection and try again.';

  const ApiException.timeout()
      : kind = ApiFailureKind.timeout,
        message = 'The request took too long. Please try again.';

  const ApiException.badResponse()
      : kind = ApiFailureKind.badResponse,
        message = 'Received an unexpected response from the server.';

  @override
  String toString() => 'ApiException($kind): $message';
}
