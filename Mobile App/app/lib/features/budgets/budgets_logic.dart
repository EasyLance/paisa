// Pure rules for the Budgets tab, so they can be tested without a widget.
// The server decides what is valid; these only build what is sent and the words
// shown beside it. Percentages here are whole numbers a person types, and the
// rupees beside them are BigInt (docs/rules.md §2).
import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/time.dart';
import '../activity/activity_logic.dart' show describeFailure;

/// The groups the web always offers, in its order. Income is never budgeted.
const defaultBudgetGroups = ['Essentials', 'Lifestyle', 'Saving', 'Other'];

/// What the web's "Use 50 / 30 / 20" button sets. Every other group goes to 0.
const preset503020 = <String, int>{'Essentials': 50, 'Lifestyle': 30, 'Saving': 20};

/// The groups a plan can give a share to: the four defaults, then any other
/// group the book's categories use (never Income), then any group the saved
/// plan already holds so an old share can still be seen and removed.
List<String> budgetGroups(Iterable<Category> categories, BudgetPlan plan) {
  final seen = <String>{};
  final groups = <String>[];
  void add(String name) {
    if (seen.add(name.toLowerCase())) groups.add(name);
  }

  defaultBudgetGroups.forEach(add);
  for (final category in categories) {
    if (category.groupName.toLowerCase() != 'income') add(category.groupName);
  }
  for (final share in plan.items) {
    add(share.groupName);
  }
  return groups;
}

/// Each group's saved share. A group with none is 0.
Map<String, int> sharesOf(BudgetPlan plan, Iterable<String> groups) {
  final saved = {for (final share in plan.items) share.groupName.toLowerCase(): share.percent};
  return {for (final group in groups) group: saved[group.toLowerCase()] ?? 0};
}

/// The preset applied to [groups]: its three shares, and 0 everywhere else.
Map<String, int> presetShares(Iterable<String> groups) => {for (final group in groups) group: preset503020[group] ?? 0};

int totalPercent(Iterable<int> shares) => shares.fold(0, (sum, share) => sum + share);

/// A typed share: blank is 0, otherwise a whole number from 0 to 100. Null means
/// it is not one, so the screen can say so rather than guess.
int? parsePercent(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return 0;
  if (!RegExp(r'^\d{1,3}$').hasMatch(trimmed)) return null;
  final value = int.parse(trimmed);
  return value > 100 ? null : value;
}

/// A group's share of expected income in paise, truncated. A display figure: the
/// server holds the percentages, not these amounts.
BigInt shareMinor(BigInt base, int percent) => base * BigInt.from(percent) ~/ BigInt.from(100);

/// The running total in words, as the web says it. Over the cap is a sentence,
/// not only a colour.
String totalWords(int total) {
  if (total > 100) return '${total - 100}% over. Trim a group to save.';
  if (total == 100) return 'Fully planned.';
  return '${100 - total}% unassigned.';
}

/// The body of `PUT budget-plan`: only the groups with a share, since the server
/// replaces the whole plan and drops the rest.
Map<String, Object?> planBody(Map<String, int> shares) => {
  'allocations': [
    for (final entry in shares.entries)
      if (entry.value > 0) {'groupName': entry.key, 'percent': entry.value},
  ],
};

/// Whether [shares] differ from what is saved.
bool planChanged(BudgetPlan saved, Map<String, int> shares) {
  final before = {for (final share in saved.items) share.groupName.toLowerCase(): share.percent};
  final after = {for (final entry in shares.entries) if (entry.value > 0) entry.key.toLowerCase(): entry.value};
  if (before.length != after.length) return true;
  return after.entries.any((entry) => before[entry.key] != entry.value);
}

/// Where the expected income comes from, in a sentence. The figure itself is
/// the server's: active recurring income plans, each spread over twelve months.
String expectedIncomeNote(BigInt base, {required bool canEdit}) {
  if (base > BigInt.zero) {
    return 'Worked out from your active recurring income plans, spread over twelve months. Each share below is a percentage of it.';
  }
  return canEdit
      ? 'Adding a recurring income plan below sets this. Until then the Overview budget uses what you received this period.'
      : 'A recurring income plan sets this. Someone who can edit this book adds one. Until then the Overview budget uses what was received this period.';
}

// ---- Recurring plans --------------------------------------------------------

const cadences = <({String value, String label})>[
  (value: 'weekly', label: 'Weekly'),
  (value: 'monthly', label: 'Monthly'),
  (value: 'quarterly', label: 'Quarterly'),
  (value: 'yearly', label: 'Yearly'),
];

String cadenceLabel(String cadence) => cadences.where((option) => option.value == cadence).map((option) => option.label).firstOrNull ?? cadence;

/// `Monthly · next 25 Sept`, the date in the book's own timezone.
String planDetail(RecurringPlan plan, BookClock clock) => '${cadenceLabel(plan.cadence)} · next ${clock.shortDate(plan.nextDueAt)}';

/// Soonest first. The database store sorts, the memory store does not.
List<RecurringPlan> byNextDue(Iterable<RecurringPlan> plans) => [...plans]..sort((a, b) => a.nextDueAt.compareTo(b.nextDueAt));

/// The body of `POST recurring-plans`. [amountMinor] is already signed by the
/// kind (`signedMinor`), which the server checks. The date is a UTC instant that
/// was midnight in the book's timezone, sent with its `Z`.
Map<String, Object?> recurringCreateBody({
  required String name,
  required String kind,
  required BigInt amountMinor,
  required String cadence,
  required DateTime nextDueAt,
  required String? categoryId,
}) => {
  'name': name.trim(),
  'kind': kind,
  'amountMinor': amountMinor.toString(),
  'cadence': cadence,
  'nextDueAt': nextDueAt.toUtc().toIso8601String(),
  'categoryId': ?categoryId,
};

/// What changed in an edit, as the body of a PATCH. `kind` and `amountMinor` go
/// together or not at all (the server answers 400 for one alone). Empty means
/// nothing changed. A due date is sent only when the person moved it, so an
/// untouched plan keeps its exact time.
Map<String, Object?> recurringEditPatch(
  RecurringPlan before, {
  required String name,
  required String kind,
  required BigInt amountMinor,
  required String cadence,
  required String? categoryId,
  DateTime? nextDueAt,
}) {
  final patch = <String, Object?>{};
  if (name.trim() != before.name) patch['name'] = name.trim();
  if (kind != before.kind || amountMinor != before.amountMinor) {
    patch['kind'] = kind;
    patch['amountMinor'] = amountMinor.toString();
  }
  if (cadence != before.cadence) patch['cadence'] = cadence;
  if (categoryId != before.categoryId) patch['categoryId'] = categoryId;
  if (nextDueAt != null && !nextDueAt.isAtSameMomentAs(before.nextDueAt)) patch['nextDueAt'] = nextDueAt.toUtc().toIso8601String();
  return patch;
}

/// A sentence for a failed budget or recurring write. Branches on status and
/// code. [created] says the request was a POST with no idempotency key, so a
/// lost connection may still have saved the plan.
String describePlanFailure(Object error, {bool created = false}) {
  if (error is ApiError) {
    if (error.isNetwork && created) return 'Cannot reach Paisa, so the plan may or may not have been saved. Check the list before you add it again.';
    if (error.isNotFound) return 'That plan no longer exists. Pull down on the list to refresh it.';
  }
  return describeFailure(error);
}
