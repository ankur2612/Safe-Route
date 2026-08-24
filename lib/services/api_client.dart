import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../utils/app_config.dart';
import '../utils/json_parsing.dart';
import 'api_exception.dart';

/// Thin HTTP wrapper around the SafeRoute FastAPI backend.
///
/// It owns the base URL and turns transport and status errors into
/// [ApiException] so no widget has to deal with HTTP details.
class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
  }) async {
    final Uri uri = _buildUri(path, query);
    return _send(() => _client.get(uri, headers: _headers));
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final Uri uri = _buildUri(path, null);
    return _send(
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
    final Uri base = Uri.parse('${AppConfig.apiBaseUrl}${AppConfig.apiPrefix}$path');
    if (query == null || query.isEmpty) return base;
    return base.replace(queryParameters: <String, String>{
      ...base.queryParameters,
      ...query,
    });
  }

  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() request,
  ) async {
    late final http.Response response;
    try {
      response = await request().timeout(AppConfig.requestTimeout);
    } on TimeoutException {
      throw const ApiException.timeout();
    } on SocketException {
      throw const ApiException.network();
    } on http.ClientException {
      throw const ApiException.network();
    }

    if (response.statusCode == 404) {
      throw const ApiException(
        ApiFailureKind.notFound,
        'The requested information was not found.',
      );
    }

    if (response.statusCode >= 500) {
      throw const ApiException(
        ApiFailureKind.server,
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
