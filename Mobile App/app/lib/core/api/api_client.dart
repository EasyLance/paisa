import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AppConfig {
  const AppConfig._();

  /// Production unless a debug build says otherwise. The emulator reaches the
  /// host machine at 10.0.2.2.
  static const apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: kDebugMode ? 'http://10.0.2.2:4000' : 'https://paisa.easylancefreelance.com',
  );

  /// Local development against `AUTH_MODE=dev`: send `x-dev-user-id` instead of
  /// a Firebase token. `kDebugMode` is a compile-time constant, so a release
  /// build cannot turn this on whatever `--dart-define` is passed.
  static const devAuth = kDebugMode && bool.fromEnvironment('DEV_AUTH');
  static const devUserId = String.fromEnvironment('DEV_USER_ID', defaultValue: 'user_owner');

}

/// Every failure from the API, or from reaching it. Branch on [status] and
/// [code], never on [message]: the wording belongs to the server and may change.
class ApiError implements Exception {
  const ApiError({required this.status, required this.code, required this.message, this.details});

  /// HTTP status, or 0 when there was no response at all.
  final int status;
  final String code;
  final String message;
  final Map<String, dynamic>? details;

  bool get isNetwork => status == 0;
  bool get isUnauthenticated => status == 401;
  bool get isNotFound => status == 404;
  bool get isRateLimited => status == 429;

  /// Per-field messages from a `400 VALIDATION_ERROR`, by field name.
  Map<String, String> get fieldErrors {
    final raw = details?['fieldErrors'];
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        if (entry.value is List && (entry.value as List).isNotEmpty)
          entry.key.toString(): (entry.value as List).first.toString(),
    };
  }

  @override
  String toString() => 'ApiError($status $code)';
}

/// Supplies the headers that identify the caller. A function, not a stored
/// token: Firebase caches and refreshes tokens itself, so the app asks each time.
abstract class AuthSource {
  Future<Map<String, String>> headers({bool forceRefresh = false});
}

class NoAuth implements AuthSource {
  const NoAuth();
  @override
  Future<Map<String, String>> headers({bool forceRefresh = false}) async => const {};
}

class DevAuth implements AuthSource {
  const DevAuth(this.userId);
  final String userId;
  @override
  Future<Map<String, String>> headers({bool forceRefresh = false}) async => {'x-dev-user-id': userId};
}

class ApiClient {
  ApiClient({required this.baseUrl, required this.auth, http.Client? client, this.timeout = const Duration(seconds: 20)})
    : _client = client ?? http.Client();

  final String baseUrl;
  final AuthSource auth;
  final Duration timeout;
  final http.Client _client;

  Future<dynamic> get(String path, {Map<String, String>? query}) => _send('GET', path, query: query);
  Future<dynamic> post(String path, {Object? body, Map<String, String>? headers}) => _send('POST', path, body: body, extra: headers);
  Future<dynamic> patch(String path, {Object? body}) => _send('PATCH', path, body: body);
  Future<dynamic> put(String path, {Object? body}) => _send('PUT', path, body: body);

  // A DELETE with a content-type and no body is a 400 at the API's parser, and
  // a 204 has nothing to decode. Send neither.
  Future<void> delete(String path) => _send('DELETE', path);

  Future<dynamic> _send(String method, String path, {Map<String, String>? query, Object? body, Map<String, String>? extra}) async {
    var response = await _once(method, path, query, body, extra, forceRefresh: false);
    // One silent retry with a freshly minted token. A second 401 is real and is
    // left to the session layer to act on.
    if (response.statusCode == 401) {
      response = await _once(method, path, query, body, extra, forceRefresh: true);
    }
    return _decode(response);
  }

  Future<http.Response> _once(String method, String path, Map<String, String>? query, Object? body, Map<String, String>? extra, {required bool forceRefresh}) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query == null || query.isEmpty ? null : query);
    final request = http.Request(method, uri);
    request.headers.addAll(await auth.headers(forceRefresh: forceRefresh));
    if (extra != null) request.headers.addAll(extra);
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    try {
      return await http.Response.fromStream(await _client.send(request).timeout(timeout));
    } on TimeoutException {
      throw const ApiError(status: 0, code: 'NETWORK', message: 'The server took too long to answer');
    } on http.ClientException {
      throw const ApiError(status: 0, code: 'NETWORK', message: 'Could not reach the server');
    }
  }

  dynamic _decode(http.Response response) {
    final ok = response.statusCode >= 200 && response.statusCode < 300;
    final text = utf8.decode(response.bodyBytes);
    dynamic json;
    if (text.isNotEmpty) {
      try {
        json = jsonDecode(text);
      } on FormatException {
        json = null;
      }
    }
    if (ok) return json;
    final map = json is Map<String, dynamic> ? json : const <String, dynamic>{};
    throw ApiError(
      status: response.statusCode,
      code: map['code'] as String? ?? 'REQUEST_ERROR',
      message: map['message'] as String? ?? 'The request failed (${response.statusCode})',
      details: map['details'] as Map<String, dynamic>?,
    );
  }

  void close() => _client.close();
}
