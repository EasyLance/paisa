import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/session.dart';
import '../dashboard/dashboard_providers.dart';
import 'budgets_logic.dart';

/// The book's recurring plans. The server lists only the active ones.
final recurringPlansProvider = FutureProvider.autoDispose.family<List<RecurringPlan>, String>((ref, bookId) async {
  final json = await ref.watch(apiClientProvider).get('/v1/books/$bookId/recurring-plans') as Map<String, dynamic>;
  return byNextDue([for (final item in json['items'] as List) RecurringPlan.fromJson(item as Map<String, dynamic>)]);
});

/// The writes on the plan and on recurring plans.
class BudgetsApi {
  BudgetsApi(this._api, this.bookId);
  final ApiClient _api;
  final String bookId;

  /// Replaces the whole plan. The answer is the plan as it now stands.
  Future<BudgetPlan> savePlan(Map<String, int> shares) async =>
      BudgetPlan.fromJson(await _api.put('/v1/books/$bookId/budget-plan', body: planBody(shares)) as Map<String, dynamic>);

  Future<RecurringPlan> createPlan(Map<String, Object?> body) async =>
      RecurringPlan.fromJson(await _api.post('/v1/books/$bookId/recurring-plans', body: body) as Map<String, dynamic>);

  /// Edit, stop (`active: false`) or turn back on (`active: true`).
  Future<RecurringPlan> updatePlan(String planId, Map<String, Object?> patch) async =>
      RecurringPlan.fromJson(await _api.patch('/v1/books/$bookId/recurring-plans/$planId', body: patch) as Map<String, dynamic>);
}

final budgetsApiProvider = Provider.family<BudgetsApi, String>((ref, bookId) => BudgetsApi(ref.watch(apiClientProvider), bookId));

/// A plan or a recurring plan changed: fetch both again, because the expected
/// income the plan's rupees depend on comes from the recurring income plans, and
/// the Overview's budget card reads the same plan.
void budgetsChanged(WidgetRef ref, String bookId) {
  ref.invalidate(budgetPlanProvider(bookId));
  ref.invalidate(recurringPlansProvider(bookId));
}
