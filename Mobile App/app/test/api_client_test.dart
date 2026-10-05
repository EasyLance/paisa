import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:paisa_mobile/core/api/api_client.dart';

class _FakeAuth implements AuthSource {
  final refreshes = <bool>[];
  @override
  Future<Map<String, String>> headers({bool forceRefresh = false}) async {
    refreshes.add(forceRefresh);
    return {'authorization': 'Bearer ${forceRefresh ? 'fresh' : 'cached'}'};
  }
}

http.Response json(int status, Object body) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  test('sends the auth headers and decodes JSON', () async {
    late http.BaseRequest seen;
    final api = ApiClient(baseUrl: 'https://x.test', auth: _FakeAuth(), client: MockClient((request) async {
      seen = request;
      return json(200, {'id': 'u1'});
    }));
    final result = await api.get('/v1/me');
    expect(result, {'id': 'u1'});
    expect(seen.headers['authorization'], 'Bearer cached');
    expect(seen.url.toString(), 'https://x.test/v1/me');
  });

  test('puts query parameters on the URL', () async {
    late Uri url;
    final api = ApiClient(baseUrl: 'https://x.test', auth: const NoAuth(), client: MockClient((request) async {
      url = request.url;
      return json(200, {});
    }));
    await api.get('/v1/books/b/transactions', query: {'state': 'pending_review', 'limit': '50'});
    expect(url.queryParameters, {'state': 'pending_review', 'limit': '50'});
  });

  test('a 401 is retried once with a freshly minted token', () async {
    final auth = _FakeAuth();
    var calls = 0;
    final api = ApiClient(baseUrl: 'https://x.test', auth: auth, client: MockClient((request) async {
      calls++;
      return calls == 1 ? json(401, {'code': 'INVALID_TOKEN', 'message': 'Token is invalid or expired'}) : json(200, {'ok': true});
    }));
    expect(await api.get('/v1/me'), {'ok': true});
    expect(auth.refreshes, [false, true]);
    expect(calls, 2);
  });

  test('a second 401 is surfaced, not retried forever', () async {
    var calls = 0;
    final api = ApiClient(baseUrl: 'https://x.test', auth: _FakeAuth(), client: MockClient((request) async {
      calls++;
      return json(401, {'code': 'INVALID_TOKEN', 'message': 'no'});
    }));
    await expectLater(api.get('/v1/me'), throwsA(isA<ApiError>().having((e) => e.isUnauthenticated, 'isUnauthenticated', true)));
    expect(calls, 2);
  });

  test('maps the API error shape, including field errors', () async {
    final api = ApiClient(baseUrl: 'https://x.test', auth: const NoAuth(), client: MockClient((request) async => json(400, {
      'code': 'VALIDATION_ERROR',
      'message': 'Request validation failed',
      'details': {'formErrors': [], 'fieldErrors': {'amountMinor': ['Expense amounts must be negative']}},
    })));
    try {
      await api.post('/v1/books/b/transactions', body: {'kind': 'expense'});
      fail('should have thrown');
    } on ApiError catch (error) {
      expect(error.status, 400);
      expect(error.code, 'VALIDATION_ERROR');
      expect(error.fieldErrors, {'amountMinor': 'Expense amounts must be negative'});
    }
  });

  test('keeps the status when the body is not the expected shape', () async {
    final api = ApiClient(baseUrl: 'https://x.test', auth: const NoAuth(), client: MockClient((request) async => http.Response('<html>bad gateway</html>', 502)));
    await expectLater(api.get('/v1/me'), throwsA(isA<ApiError>().having((e) => e.status, 'status', 502).having((e) => e.code, 'code', 'REQUEST_ERROR')));
  });

  test('a 204 has nothing to decode and sends no body', () async {
    late http.BaseRequest seen;
    final api = ApiClient(baseUrl: 'https://x.test', auth: const NoAuth(), client: MockClient((request) async {
      seen = request;
      return http.Response('', 204);
    }));
    await api.delete('/v1/books/b/memberships/u');
    expect(seen.method, 'DELETE');
    expect(seen.headers.containsKey('content-type'), isFalse);
  });

  test('a body is sent as JSON', () async {
    late http.Request seen;
    final api = ApiClient(baseUrl: 'https://x.test', auth: const NoAuth(), client: MockClient((request) async {
      seen = request;
      return json(201, {});
    }));
    await api.post('/v1/access-requests', body: {'name': 'A', 'email': 'a@b.co'}, headers: {'idempotency-key': 'abcdefgh'});
    expect(seen.headers['content-type'], 'application/json');
    expect(seen.headers['idempotency-key'], 'abcdefgh');
    expect(jsonDecode(seen.body), {'name': 'A', 'email': 'a@b.co'});
  });

  test('no connection becomes a network error, not a crash', () async {
    final api = ApiClient(baseUrl: 'https://x.test', auth: const NoAuth(), client: MockClient((request) async => throw http.ClientException('offline')));
    await expectLater(api.get('/v1/me'), throwsA(isA<ApiError>().having((e) => e.isNetwork, 'isNetwork', true)));
  });

  test('a slow server times out', () async {
    final api = ApiClient(baseUrl: 'https://x.test', auth: const NoAuth(), timeout: const Duration(milliseconds: 20), client: MockClient((request) async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return json(200, {});
    }));
    await expectLater(api.get('/v1/me'), throwsA(isA<ApiError>().having((e) => e.isNetwork, 'isNetwork', true)));
  });

  test('development sign-in is off unless a debug build asks for it', () {
    expect(AppConfig.devAuth, isFalse);
  });
}
