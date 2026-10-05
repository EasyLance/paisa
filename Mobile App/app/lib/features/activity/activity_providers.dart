import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/session.dart';
import '../dashboard/dashboard_providers.dart';

const _pageSize = 50;

/// The state chip that is selected; null is "All". The dashboard's Review button
/// sets it to `pending_review` before switching to the tab.
class ActivityFilter extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? state) => this.state = state;
}

final activityFilterProvider = NotifierProvider<ActivityFilter, String?>(ActivityFilter.new);

typedef ActivityKey = ({String bookId, String? state});

class ActivityState {
  const ActivityState({required this.items, required this.nextCursor, this.loadingMore = false, this.moreFailed = false});

  final List<Transaction> items;
  final String? nextCursor;
  final bool loadingMore;

  /// A later page failed. What is already shown is still real, so it stays.
  final bool moreFailed;

  ActivityState copyWith({List<Transaction>? items, String? nextCursor, bool? loadingMore, bool? moreFailed}) => ActivityState(
    items: items ?? this.items,
    nextCursor: nextCursor ?? this.nextCursor,
    loadingMore: loadingMore ?? this.loadingMore,
    moreFailed: moreFailed ?? this.moreFailed,
  );
}

/// The ledger, newest first, one page at a time.
class ActivityController extends AsyncNotifier<ActivityState> {
  ActivityController(this.key);
  final ActivityKey key;

  Future<TransactionPage> _page(String? cursor) async {
    final json = await ref.read(apiClientProvider).get('/v1/books/${key.bookId}/transactions', query: {
      'limit': '$_pageSize',
      'state': ?key.state,
      'cursor': ?cursor,
    });
    return TransactionPage.fromJson(json as Map<String, dynamic>);
  }

  @override
  Future<ActivityState> build() async {
    ref.watch(apiClientProvider);
    final page = await _page(null);
    return ActivityState(items: page.items, nextCursor: page.nextCursor);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.nextCursor == null || current.loadingMore) return;
    state = AsyncData(current.copyWith(loadingMore: true, moreFailed: false));
    try {
      final page = await _page(current.nextCursor);
      final latest = state.value ?? current;
      // A payment edited meanwhile may already be in the list; never show it twice.
      final seen = {for (final item in latest.items) item.id};
      state = AsyncData(ActivityState(items: [...latest.items, ...page.items.where((item) => !seen.contains(item.id))], nextCursor: page.nextCursor));
    } on ApiError {
      state = AsyncData((state.value ?? current).copyWith(loadingMore: false, moreFailed: true));
    }
  }

  /// A payment was changed or added: put the new version where it belongs, or
  /// take it out if it no longer matches the chip (a confirmed payment leaves
  /// "Needs review").
  void apply(Transaction changed) {
    final current = state.value;
    if (current == null) return;
    final items = [...current.items];
    final at = items.indexWhere((item) => item.id == changed.id);
    final belongs = key.state == null || changed.state == key.state;
    if (at >= 0) {
      belongs ? items[at] = changed : items.removeAt(at);
    } else if (belongs) {
      final before = items.indexWhere((item) => item.occurredAt.isBefore(changed.occurredAt));
      items.insert(before < 0 ? items.length : before, changed);
    }
    state = AsyncData(current.copyWith(items: items));
  }
}

final activityProvider = AsyncNotifierProvider.autoDispose.family<ActivityController, ActivityState, ActivityKey>(ActivityController.new);

final categoriesProvider = FutureProvider.autoDispose.family<List<Category>, String>((ref, bookId) async {
  final json = await ref.watch(apiClientProvider).get('/v1/books/$bookId/categories') as Map<String, dynamic>;
  return [for (final item in json['items'] as List) Category.fromJson(item as Map<String, dynamic>)];
});

final accountsProvider = FutureProvider.autoDispose.family<List<Account>, String>((ref, bookId) async {
  final json = await ref.watch(apiClientProvider).get('/v1/books/$bookId/accounts') as Map<String, dynamic>;
  return [for (final item in json['items'] as List) Account.fromJson(item as Map<String, dynamic>)];
});

/// The writes on a payment. Each returns the payment as it now stands.
class LedgerApi {
  LedgerApi(this._api, this.bookId);
  final ApiClient _api;
  final String bookId;

  String get _base => '/v1/books/$bookId/transactions';

  Future<Transaction> setCategory(Transaction tx, String categoryId, {bool applyToFuture = false}) async => Transaction.fromJson(
    await _api.patch('$_base/${tx.id}/category', body: {'categoryId': categoryId, 'applyToFuture': applyToFuture}) as Map<String, dynamic>,
    previous: tx,
  );

  Future<Transaction> edit(Transaction tx, Map<String, Object?> fields) async =>
      Transaction.fromJson(await _api.patch('$_base/${tx.id}', body: fields) as Map<String, dynamic>, previous: tx);

  Future<Transaction> split(Transaction tx, List<({String categoryId, BigInt amountMinor, String? note})> parts) async => Transaction.fromJson(
    await _api.put('$_base/${tx.id}/splits', body: {
      'splits': [for (final part in parts) {'categoryId': part.categoryId, 'amountMinor': part.amountMinor.toString(), if (part.note != null) 'note': part.note}],
    }) as Map<String, dynamic>,
    previous: tx,
  );

  Future<TxComment> comment(Transaction tx, String body) async =>
      TxComment.fromJson(await _api.post('$_base/${tx.id}/comments', body: {'body': body}) as Map<String, dynamic>);

  /// One key per form, reused on a retry: if the connection drops after the
  /// server saved the payment, sending it again returns that payment instead
  /// of adding a second one.
  Future<Transaction> create(Map<String, Object?> body, String idempotencyKey) async =>
      Transaction.fromJson(await _api.post(_base, body: body, headers: {'idempotency-key': idempotencyKey}) as Map<String, dynamic>);
}

final ledgerApiProvider = Provider.family<LedgerApi, String>((ref, bookId) => LedgerApi(ref.watch(apiClientProvider), bookId));

/// A key for one form submission. 128 random bits; the server wants 8 to 200 characters.
String newIdempotencyKey() {
  final random = Random.secure();
  return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// Tell the rest of the app a payment changed: the open list takes the new
/// version and the dashboard's figures are fetched again.
void ledgerChanged(WidgetRef ref, String bookId, Transaction tx) {
  final list = activityProvider((bookId: bookId, state: ref.read(activityFilterProvider)));
  if (ref.exists(list)) ref.read(list.notifier).apply(tx);
  ref.invalidate(summaryProvider);
}
