// Pure rules for the Activity screens, so they can be tested without a widget.
import '../../core/api/api_client.dart';
import '../../core/api/models.dart';

/// The filter chips, in the order they appear. A null value is "everything".
const stateFilters = <({String? value, String label})>[
  (value: null, label: 'All'),
  (value: 'pending_review', label: 'Needs review'),
  (value: 'confirmed', label: 'Confirmed'),
  (value: 'reconciled', label: 'Reconciled'),
  (value: 'excluded', label: 'Excluded'),
  (value: 'voided', label: 'Voided'),
];

String stateLabel(String state) => switch (state) {
  'pending_review' => 'Needs review',
  'confirmed' => 'Confirmed',
  'reconciled' => 'Reconciled',
  'excluded' => 'Excluded',
  'voided' => 'Voided',
  _ => state,
};

String kindLabel(String kind) => switch (kind) {
  'expense' => 'Expense',
  'income' => 'Income',
  'refund' => 'Refund',
  'transfer' => 'Transfer',
  _ => kind,
};

String sourceLabel(String type) => switch (type) {
  'sms' => 'Text message',
  'statement' => 'Bank statement',
  'manual' => 'Added by hand',
  _ => type,
};

/// Voided and excluded payments no longer count towards any total.
bool isCounted(Transaction tx) => tx.state != 'voided' && tx.state != 'excluded';

/// What the list shows in place of a category name.
String categoryLabel(Transaction tx, Map<String, Category> categories) {
  if (tx.splits.isNotEmpty) return 'Split ${tx.splits.length} ways';
  final id = tx.categoryId;
  if (id == null) return tx.kind == 'transfer' ? 'Transfer' : 'Uncategorised';
  return categories[id]?.name ?? 'Category';
}

/// Search runs over what has been loaded, on the words a person would use.
bool matchesSearch(Transaction tx, String query, Map<String, Category> categories) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return true;
  return [tx.merchant, tx.note, categoryLabel(tx, categories)].any((text) => text != null && text.toLowerCase().contains(needle));
}

/// How much of [total] the split rows have not yet covered. Negative when the
/// rows overshoot. Everything is a magnitude: the sign is the payment's.
BigInt splitRemaining(BigInt total, Iterable<BigInt?> parts) =>
    total.abs() - parts.fold(BigInt.zero, (sum, part) => sum + (part?.abs() ?? BigInt.zero));

/// A sentence for a failed write. Branches on the status and code, never on the
/// server's wording; a validation message is passed on because it names the field.
String describeFailure(Object error) {
  if (error is! ApiError) return 'Paisa could not save that. Try again in a moment.';
  if (error.isNetwork) return 'Cannot reach Paisa. Check your connection. Nothing was changed.';
  if (error.status == 403) return 'Your role in this book cannot do that.';
  if (error.isNotFound) return 'That payment no longer exists. Pull down on the list to refresh it.';
  if (error.status == 400 && error.fieldErrors.isNotEmpty) return error.fieldErrors.values.first;
  if (error.code == 'IDEMPOTENCY_CONFLICT') return 'This form was already sent once with different details. Check Activity in case the first one went through, then save again.';
  if (error.code == 'SPLIT_TOTAL_MISMATCH') return 'The parts must add up to the payment exactly.';
  return 'Paisa could not save that. Try again in a moment.';
}

/// What changed in an edit, as the body of a PATCH. `kind` and `amountMinor` go
/// together or not at all: the sign is the direction, and the server refuses one
/// without the other. Empty means nothing changed.
Map<String, Object?> editPatch(
  Transaction before, {
  required String kind,
  required BigInt amountMinor,
  required String merchant,
  required String note,
  required String? accountId,
  required String? counterAccountId,
  DateTime? occurredAt,
}) {
  final patch = <String, Object?>{};
  if (kind != before.kind || amountMinor != before.amountMinor) {
    patch['kind'] = kind;
    patch['amountMinor'] = amountMinor.toString();
  }
  if (merchant.trim() != (before.merchant ?? '')) patch['merchant'] = merchant.trim().isEmpty ? null : merchant.trim();
  if (note.trim() != (before.note ?? '')) patch['note'] = note.trim().isEmpty ? null : note.trim();
  if (accountId != before.accountId) patch['accountId'] = accountId;
  if (counterAccountId != before.counterAccountId) patch['counterAccountId'] = counterAccountId;
  if (occurredAt != null && !occurredAt.isAtSameMomentAs(before.occurredAt)) patch['occurredAt'] = occurredAt.toUtc().toIso8601String();
  return patch;
}

/// The body of a new manual payment. One without a category waits for review,
/// so it shows up where the household looks; a transfer needs none.
Map<String, Object?> createBody({
  required String kind,
  required BigInt amountMinor,
  required String merchant,
  required String note,
  required String? categoryId,
  required String? accountId,
  required String? counterAccountId,
  required DateTime occurredAt,
}) => {
  'kind': kind,
  'amountMinor': amountMinor.toString(),
  'occurredAt': occurredAt.toUtc().toIso8601String(),
  'state': categoryId == null && kind != 'transfer' ? 'pending_review' : 'confirmed',
  if (merchant.trim().isNotEmpty) 'merchant': merchant.trim(),
  if (note.trim().isNotEmpty) 'note': note.trim(),
  'categoryId': ?categoryId,
  'accountId': ?accountId,
  if (counterAccountId != null && kind == 'transfer') 'counterAccountId': counterAccountId,
};
