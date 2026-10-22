import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:saferoute/services/api_client.dart';
import 'package:saferoute/services/api_exception.dart';
import 'package:saferoute/utils/app_config.dart';

/// How each kind of failure is reported. None of them may claim the phone is
/// offline: a failed request alone cannot prove that.
void main() {
  const String server = 'https://api.saferoute.example';
  int calls = 0;

  ApiClient clientWith(
    Future<http.Response> Function(http.Request request) handler, {
    String baseUrl = server,
    bool releaseBuild = false,
  }) {
    calls = 0;
    return ApiClient(
      client: MockClient((http.Request request) {
        calls++;
        return handler(request);
      }),
      baseUrl: baseUrl,
      releaseBuild: releaseBuild,
    );
  }

  Future<ApiException> failure(ApiClient client, {Duration? timeout}) async {
    try {
      await client.get(
        '/locations/search',
        query: <String, String>{'q': 'indr'},
        timeout: timeout ?? AppConfig.requestTimeout,
      );
    } on ApiException catch (error) {
      expect(error.message, isNot(contains('No internet')));
      return error;
    }
    fail('expected an ApiException');
  }

  group('server address', () {
    test('a release build left on the emulator address fails at once',
        () async {
      final ApiClient client = clientWith(
        (_) async => http.Response('{}', 200),
        baseUrl: 'http://10.0.2.2:8000',
        releaseBuild: true,
      );

      final ApiException error = await failure(client);

      expect(error.kind, ApiFailureKind.configuration);
      expect(error.message, contains('10.0.2.2'));
      expect(error.message, contains('API_BASE_URL'));
      expect(calls, 0, reason: 'no request to an unreachable address');
    });

    test('a debug build may use the emulator address', () async {
      final ApiClient client = clientWith(
        (_) async => http.Response('{"results": []}', 200),
        baseUrl: 'http://10.0.2.2:8000',
      );
      await client.get('/locations/search');
      expect(calls, 1);
    });

    test('an invalid address is a configuration error', () {
      expect(AppConfig.apiBaseUrlProblem('not a url', releaseBuild: false),
          isNotNull);
      expect(AppConfig.apiBaseUrlProblem('ftp://x.example', releaseBuild: false),
          isNotNull);
      expect(AppConfig.apiBaseUrlProblem(server, releaseBuild: true), isNull);
      expect(
        AppConfig.apiBaseUrlProblem('http://192.168.1.20:8000', releaseBuild: true),
        isNull,
      );
    });
  });

  group('connection failures', () {
    test('refused or unreachable server names the server', () async {
      final ApiException error = await failure(clientWith((http.Request r) async {
        throw http.ClientException(
          'SocketException: Connection refused (OS Error: Connection refused, errno = 111)',
          r.url,
        );
      }));
      expect(error.kind, ApiFailureKind.network);
      expect(error.message, contains('api.saferoute.example'));
      expect(error.message, contains('may be offline'));
    });

    test('the emulator address gets a hint for phones', () async {
      final ApiException error = await failure(clientWith(
        (_) async => throw const SocketException('Network is unreachable'),
        baseUrl: 'http://10.0.2.2:8000',
      ));
      expect(error.kind, ApiFailureKind.network);
      expect(error.message, contains('10.0.2.2:8000'));
      expect(error.message, contains('emulator'));
    });

    test('a failed name lookup is reported as such', () async {
      final ApiException error = await failure(clientWith((http.Request r) async {
        throw http.ClientException(
          "SocketException: Failed host lookup: 'api.saferoute.example'",
          r.url,
        );
      }));
      expect(error.kind, ApiFailureKind.hostLookup);
      expect(error.message, contains("Couldn't find the SafeRoute server"));
    });

    test('a TLS failure is reported as a secure-connection problem', () async {
      final ApiException error = await failure(
        clientWith((_) async => throw const HandshakeException('bad certificate')),
      );
      expect(error.kind, ApiFailureKind.secureConnection);
    });

    test('plain http refused by the platform is a configuration error',
        () async {
      final ApiException error = await failure(clientWith(
        (_) async => throw StateError(
            'Insecure HTTP is not allowed by platform: http://x'),
      ));
      expect(error.kind, ApiFailureKind.configuration);
      expect(error.message, contains('https'));
    });

    test('a request that never answers times out', () async {
      final ApiException error = await failure(
        clientWith((_) => Completer<http.Response>().future),
        timeout: const Duration(milliseconds: 50),
      );
      expect(error.kind, ApiFailureKind.timeout);
      expect(error.message, contains('did not respond in time'));
    });
  });

  group('responses', () {
    test('a server error shows the backend\'s explanation', () async {
      final ApiException error = await failure(clientWith((_) async => http.Response(
            '{"detail": "Location search is temporarily unavailable. Please try again."}',
            503,
          )));
      expect(error.kind, ApiFailureKind.server);
      expect(error.message, startsWith('Location search is temporarily unavailable'));
    });

    test('a server error without details gets a generic message', () async {
      final ApiException error = await failure(
        clientWith((_) async => http.Response('<html>Bad gateway</html>', 502)),
      );
      expect(error.kind, ApiFailureKind.server);
      expect(error.message, contains('server is not responding correctly'));
    });

    test('a rate limit is its own kind', () async {
      final ApiException error = await failure(clientWith(
        (_) async => http.Response('{"detail": "Too many searches right now."}', 429),
      ));
      expect(error.kind, ApiFailureKind.rateLimited);
      expect(error.message, 'Too many searches right now.');
    });

    test('invalid JSON is a bad response', () async {
      final ApiException error = await failure(
        clientWith((_) async => http.Response('{"results": [', 200)),
      );
      expect(error.kind, ApiFailureKind.badResponse);
    });

    test('a JSON value that is not an object is a bad response', () async {
      final ApiException error = await failure(
        clientWith((_) async => http.Response('"hello"', 200)),
      );
      expect(error.kind, ApiFailureKind.badResponse);
    });
  });
}
