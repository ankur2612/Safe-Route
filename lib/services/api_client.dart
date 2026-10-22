import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../utils/app_config.dart';
import '../utils/json_parsing.dart';
import 'api_exception.dart';

/// Thin HTTP wrapper around the SafeRoute FastAPI backend.
///
/// It owns the base URL and turns transport and status errors into
/// [ApiException] so no widget has to deal with HTTP details.
class ApiClient {
  ApiClient({
    http.Client? client,
    String? baseUrl,
    bool releaseBuild = kReleaseMode,
  })  : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? AppConfig.apiBaseUrl,
        _releaseBuild = releaseBuild;

  final http.Client _client;
  final String _baseUrl;
  final bool _releaseBuild;

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
    Duration timeout = AppConfig.requestTimeout,
  }) async {
    final Uri uri = _buildUri(path, query);
    return _send(uri, timeout, () => _client.get(uri, headers: _headers));
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final Uri uri = _buildUri(path, null);
    return _send(
      uri,
      AppConfig.requestTimeout,
      () => _client.post(
        uri,
        headers: _headers,
        body: jsonEncode(body ?? const <String, dynamic>{}),
      ),
    );
  }

  void dispose() => _client.close();

  static const Map<String, String> _headers = <String, String>{
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  Uri _buildUri(String path, Map<String, String>? query) {
    final Uri base = Uri.parse('$_baseUrl${AppConfig.apiPrefix}$path');
    if (query == null || query.isEmpty) return base;
    return base.replace(queryParameters: <String, String>{
      ...base.queryParameters,
      ...query,
    });
  }

  Future<Map<String, dynamic>> _send(
    Uri uri,
    Duration timeout,
    Future<http.Response> Function() request,
  ) async {
    // Fail at once, with the real reason, instead of waiting for an address
    // the phone can never reach.
    final String? problem =
        AppConfig.apiBaseUrlProblem(_baseUrl, releaseBuild: _releaseBuild);
    if (problem != null) {
      throw ApiException(ApiFailureKind.configuration, problem);
    }

    late final http.Response response;
    try {
      response = await request().timeout(timeout);
    } on TimeoutException {
      throw ApiException(
        ApiFailureKind.timeout,
        'The SafeRoute server (${_server(uri)}) did not respond in time. '
        'Please try again.',
      );
    } on Exception catch (error) {
      throw _connectionError(error, uri);
    } on StateError catch (error) {
      // dart:io refuses plain http when the platform forbids it.
      if (!error.message.contains('Insecure HTTP')) rethrow;
      throw ApiException(
        ApiFailureKind.configuration,
        'This build only allows secure (https) server addresses, but it points '
        'at ${_server(uri)}. Rebuild it with an https API_BASE_URL.',
      );
    }

    if (response.statusCode == 404) {
      throw const ApiException(
        ApiFailureKind.notFound,
        'The requested information was not found.',
      );
    }

    if (response.statusCode == 429) {
      throw ApiException(
        ApiFailureKind.rateLimited,
        _errorMessage(response.body) ??
            'Too many requests right now. Please wait a moment and try again.',
      );
    }

    if (response.statusCode >= 500) {
      // The backend explains its own failures (e.g. "Location search is
      // temporarily unavailable"); anything else gets a generic message.
      throw ApiException(
        ApiFailureKind.server,
        _errorMessage(response.body) ??
            'The server is not responding correctly. Please try again shortly.',
      );
    }

    if (response.statusCode >= 400) {
      throw ApiException(
        ApiFailureKind.badResponse,
        _errorMessage(response.body) ?? 'The request could not be completed.',
      );
    }

    if (response.body.trim().isEmpty) {
      return const <String, dynamic>{};
    }

    try {
      final Object? decoded = jsonDecode(response.body);
      final Map<String, dynamic>? map = asMap(decoded);
      if (map != null) return map;
      // Some endpoints may return a bare list; wrap it so callers see a
      // consistent shape.
      if (decoded is List) return <String, dynamic>{'items': decoded};
      throw const ApiException.badResponse();
    } on FormatException {
      throw const ApiException.badResponse();
    }
  }

  /// Names what actually failed. package:http reports socket errors as a
  /// [http.ClientException] that is also a [SocketException]; the text tells
  /// a failed name lookup apart from a refused or unreachable server.
  ApiException _connectionError(Exception error, Uri uri) {
    final String server = _server(uri);
    if (error is TlsException) {
      return ApiException(
        ApiFailureKind.secureConnection,
        "Couldn't make a secure connection to the SafeRoute server ($server).",
      );
    }
    if (error is! SocketException && error is! http.ClientException) {
      return ApiException(
        ApiFailureKind.network,
        "Couldn't connect to the SafeRoute server ($server).",
      );
    }
    if (error.toString().contains('Failed host lookup')) {
      return ApiException(
        ApiFailureKind.hostLookup,
        "Couldn't find the SafeRoute server ($server). Check your internet "
        'connection and that the server address is correct.',
      );
    }
    final String hint = AppConfig.developmentOnlyHosts.contains(uri.host)
        ? ' That address only works from the development computer or its '
            'emulator; on a phone, use a deployed server or the computer\'s '
            'network IP.'
        : ' The server may be offline, or the address may be wrong.';
    return ApiException(
      ApiFailureKind.network,
      "Couldn't connect to the SafeRoute server ($server).$hint",
    );
  }

  static String _server(Uri uri) =>
      uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;

  /// Pulls FastAPI's `detail` field out of an error body when present.
  String? _errorMessage(String body) {
    try {
      final Map<String, dynamic>? map = asMap(jsonDecode(body));
      return asText(map?['detail']) ?? asText(map?['message']);
    } on FormatException {
      return null;
    }
  }
}
