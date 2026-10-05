import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:paisa_mobile/app.dart';
import 'package:paisa_mobile/core/api/api_client.dart';
import 'package:paisa_mobile/core/auth/auth_service.dart';
import 'package:paisa_mobile/core/prefs.dart';
import 'package:paisa_mobile/core/session.dart';
import 'package:paisa_mobile/features/dashboard/dashboard_providers.dart';
import 'package:paisa_mobile/features/lock/lock_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

dynamic fixture(String name) => jsonDecode(File('test/fixtures/$name.json').readAsStringSync());

class FakeAuth implements AuthService {
  FakeAuth({bool signedIn = false, this.email}) : _signedIn = signedIn;

  bool _signedIn;
  String? email;
  AuthFailure? failSignIn;
  final calls = <String>[];
  final _changes = StreamController<bool>.broadcast();

  @override
  bool get isSignedIn => _signedIn;

  @override
  String? get currentEmail => email;

  @override
  Stream<bool> get signedInChanges async* {
    yield _signedIn;
    yield* _changes.stream;
  }

  @override
  Future<Map<String, String>> headers({bool forceRefresh = false}) async => _signedIn ? {'authorization': 'Bearer test'} : const {};

  @override
  Future<void> signIn(String email, String password) async {
    calls.add('signIn:$email');
    if (failSignIn != null) throw failSignIn!;
    _signedIn = true;
    _changes.add(true);
  }

  @override
  Future<void> sendPasswordReset(String email) async => calls.add('reset:$email');

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    _signedIn = false;
    _changes.add(false);
  }
}

class FakeAuthenticator implements Authenticator {
  bool available = true;
  bool succeeds = true;
  final reasons = <String>[];

  /// Runs while the prompt is "on screen", to simulate the app being paused and
  /// resumed around it.
  void Function()? duringPrompt;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate(String reason) async {
    reasons.add(reason);
    duringPrompt?.call();
    return succeeds;
  }
}

http.Response jsonResponse(int status, Object body) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

/// A scripted API. Defaults to the recorded fixtures; override per test.
class FakeServer {
  FakeServer({List<String>? roles}) : roles = roles ?? ['book_owner', 'book_owner'];

  /// The role for each book in `fixtures/books.json`, in order.
  List<String> roles;
  bool offline = false;

  /// What the server answers for a month's summary and the budget plan; null
  /// means the recorded fixtures.
  Map<String, dynamic>? summaryBody;
  int? summaryStatus;
  Map<String, dynamic>? planBody;
  int? planStatus;
  int periodStartDay = 1;
  final summaryMonths = <String>[];
  int? meStatus;
  Map<String, dynamic>? meError;
  int? booksStatus;
  Map<String, dynamic>? accessRequestReply;
  int accessRequestStatus = 201;
  final requests = <String>[];
  Object? lastBody;

  /// The payments the server holds: a mutable copy of the recorded ledger
  /// (`transactions_rich.json`), changed by the write routes below.
  late final List<Map<String, dynamic>> ledger = [
    for (final item in (fixture('transactions_rich') as Map<String, dynamic>)['items'] as List) Map<String, dynamic>.from(item as Map<String, dynamic>),
  ];

  /// Payments per page; small values make paging visible.
  int pageSize = 50;
  int? ledgerStatus;
  final listQueries = <Map<String, String>>[];
  final writes = <String>[];

  /// The next POST of a payment is saved, then the connection drops before the
  /// reply arrives: the case an idempotency key exists for.
  bool dropNextCreateReply = false;
  final createKeys = <String>[];
  final _byKey = <String, Map<String, dynamic>>{};

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    requests.add('${request.method} $path');
    if (offline) throw http.ClientException('offline');
    if (path == '/v1/me') {
      if (meStatus != null) return jsonResponse(meStatus!, meError ?? {'code': 'ERROR', 'message': 'no'});
      return jsonResponse(200, fixture('me'));
    }
    if (path == '/v1/books') {
      if (booksStatus != null) return jsonResponse(booksStatus!, {'code': 'ERROR', 'message': 'no'});
      final books = (fixture('books') as Map<String, dynamic>)['items'] as List;
      return jsonResponse(200, {
        'items': [for (var i = 0; i < books.length && i < roles.length; i++) {...(books[i] as Map<String, dynamic>), 'role': roles[i], 'periodStartDay': periodStartDay}],
      });
    }
    if (RegExp(r'^/v1/books/[^/]+/summary$').hasMatch(path)) {
      summaryMonths.add(request.url.queryParameters['month'] ?? '');
      if (summaryStatus != null) return jsonResponse(summaryStatus!, {'code': 'ERROR', 'message': 'no'});
      return jsonResponse(200, summaryBody ?? fixture('summary_rich'));
    }
    if (RegExp(r'^/v1/books/[^/]+/budget-plan$').hasMatch(path)) {
      if (planStatus != null) return jsonResponse(planStatus!, {'code': 'ERROR', 'message': 'no'});
      return jsonResponse(200, planBody ?? fixture('budget_plan_set'));
    }
    final ledgerResponse = _ledger(request, path);
    if (ledgerResponse != null) return ledgerResponse;
    if (path == '/v1/access-requests') {
      lastBody = jsonDecode(request.body);
      return jsonResponse(accessRequestStatus, accessRequestReply ?? {'status': 'received'});
    }
    return jsonResponse(404, {'code': 'NOT_FOUND', 'message': 'Not found'});
  }
}

extension on FakeServer {
  Map<String, dynamic>? _find(String id) => ledger.where((item) => item['id'] == id).firstOrNull;

  http.Response _ok(Map<String, dynamic> tx, {bool withComments = true}) =>
      jsonResponse(200, withComments ? tx : (Map<String, dynamic>.from(tx)..remove('comments')));

  http.Response? _ledger(http.Request request, String path) {
    final base = RegExp(r'^/v1/books/[^/]+/(.*)$').firstMatch(path)?.group(1);
    if (base == null) return null;
    if (base == 'categories') return jsonResponse(200, fixture('categories'));
    if (base == 'accounts') return jsonResponse(200, fixture('accounts'));
    if (base == 'transactions' && request.method == 'GET') {
      listQueries.add(request.url.queryParameters);
      if (ledgerStatus != null) return jsonResponse(ledgerStatus!, {'code': 'ERROR', 'message': 'no'});
      final state = request.url.queryParameters['state'];
      final cursor = request.url.queryParameters['cursor'];
      var items = [for (final item in ledger) if (state == null || item['state'] == state) item];
      if (cursor != null) items = items.sublist(items.indexWhere((item) => item['id'] == cursor) + 1);
      final limit = min(pageSize, int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 50);
      final page = items.take(limit).toList();
      return jsonResponse(200, {'items': page, 'nextCursor': items.length > limit ? page.last['id'] : null});
    }
    if (base == 'transactions' && request.method == 'POST') {
      final key = request.headers['idempotency-key'];
      if (key == null || key.length < 8) return jsonResponse(400, {'code': 'IDEMPOTENCY_KEY_REQUIRED', 'message': 'A valid Idempotency-Key header is required'});
      createKeys.add(key);
      writes.add('POST transactions');
      final replay = _byKey[key];
      if (replay != null) return jsonResponse(200, replay);
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final created = <String, dynamic>{
        ...(fixture('transaction_created') as Map<String, dynamic>),
        'id': 'new_${ledger.length}',
        'kind': body['kind'],
        'state': body['state'] ?? 'confirmed',
        'amountMinor': body['amountMinor'],
        'merchant': body['merchant'],
        'note': body['note'],
        'categoryId': body['categoryId'],
        'accountId': body['accountId'],
        'counterAccountId': body['counterAccountId'],
        'occurredAt': body['occurredAt'],
        'sources': [{'id': 's', 'sourceType': 'manual', 'sourceReference': 'manual:x', 'importedAmount': body['amountMinor']}],
      };
      lastBody = body;
      _byKey[key] = created;
      ledger.insert(0, created);
      if (dropNextCreateReply) {
        dropNextCreateReply = false;
        throw http.ClientException('connection dropped');
      }
      return jsonResponse(201, created);
    }
    final match = RegExp(r'^transactions/([^/]+)(/category|/splits|/comments)?$').firstMatch(base);
    if (match == null) return null;
    final tx = _find(match.group(1)!);
    if (tx == null) return jsonResponse(404, {'code': 'NOT_FOUND', 'message': 'Transaction not found'});
    final body = request.body.isEmpty ? <String, dynamic>{} : jsonDecode(request.body) as Map<String, dynamic>;
    lastBody = body;
    writes.add('${request.method} ${match.group(2) ?? 'transaction'}');
    switch (match.group(2)) {
      case '/category':
        tx['categoryId'] = body['categoryId'];
        tx['state'] = 'confirmed';
        return _ok(tx, withComments: false);
      case '/splits':
        final parts = body['splits'] as List;
        final sum = parts.fold<BigInt>(BigInt.zero, (a, p) => a + BigInt.parse((p as Map)['amountMinor'] as String).abs());
        if (sum != BigInt.parse(tx['amountMinor'] as String).abs()) {
          return jsonResponse(400, fixture('split_mismatch_error'));
        }
        tx['splits'] = [for (final p in parts) {'id': 'sp', ...(p as Map<String, dynamic>)}];
        return _ok(tx, withComments: false);
      case '/comments':
        final comment = {'id': 'c${(tx['comments'] as List).length}', 'transactionId': tx['id'], 'authorId': 'user_owner', 'body': body['body'], 'createdAt': '2026-08-25T06:30:00.000Z'};
        (tx['comments'] as List).add(comment);
        return jsonResponse(201, comment);
      default:
        if ((body['amountMinor'] == null) != (body['kind'] == null)) return jsonResponse(400, fixture('patch_amount_only_error'));
        tx.addAll(body);
        return _ok(tx);
    }
  }
}

class Harness {
  Harness({FakeAuth? auth, FakeServer? server, Map<String, Object>? prefs, FakeAuthenticator? authenticator, DateTime? now})
    : now = now ?? DateTime.utc(2026, 8, 25, 6, 30),
      auth = auth ?? FakeAuth(),
      server = server ?? FakeServer(),
      authenticator = authenticator ?? FakeAuthenticator() {
    SharedPreferences.setMockInitialValues(prefs ?? {});
  }

  final FakeAuth auth;
  final FakeServer server;
  final FakeAuthenticator authenticator;

  /// "Today". The default is noon on 25 August 2026 in India, inside the month
  /// the recorded summary describes.
  final DateTime now;
  late final SharedPreferences prefs;

  Future<List<Override>> overrides() async {
    prefs = await SharedPreferences.getInstance();
    final client = ApiClient(baseUrl: 'https://x.test', auth: auth, client: MockClient(server.handle));
    return [
      sharedPreferencesProvider.overrideWithValue(prefs),
      authServiceProvider.overrideWithValue(auth),
      apiClientProvider.overrideWithValue(client),
      authenticatorProvider.overrideWithValue(authenticator),
      clockProvider.overrideWithValue(() => now),
    ];
  }

  Future<ProviderContainer> container() async => ProviderContainer(overrides: await overrides(), retry: (count, error) => null);

  Future<Widget> app() async => ProviderScope(retry: (count, error) => null, overrides: await overrides(), child: const PaisaApp());
}
