import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/models.dart';
import '../../core/session.dart';
import '../../core/time.dart';

/// Overridable so tests can say what day it is.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// What decides a book's pay cycle. Passed in by the screen rather than read
/// from the session: while somebody is signing out the session has no book for a
/// moment, and the dashboard still on screen must not be asked for one.
typedef PeriodKey = ({String timezone, int startDay});

PeriodKey periodKeyOf(Book book) => (timezone: book.timezone, startDay: book.periodStartDay);

/// The period the book is in today, by its own pay cycle.
final currentMonthProvider = Provider.family<String, PeriodKey>(
  (ref, key) => currentPeriodLabel(ref.watch(clockProvider)(), key.timezone, key.startDay),
);

/// The month being looked at. Starts on the current period and goes back one at
/// a time.
class MonthController extends Notifier<String> {
  MonthController(this.key);
  final PeriodKey key;

  @override
  String build() => ref.watch(currentMonthProvider(key));

  void previous() => state = shiftMonth(state, -1);

  /// Nothing to see beyond today's period, so it stops there.
  void next() {
    if (state.compareTo(ref.read(currentMonthProvider(key))) < 0) state = shiftMonth(state, 1);
  }
}

final selectedMonthProvider = NotifierProvider.family<MonthController, String, PeriodKey>(MonthController.new);

typedef SummaryKey = ({String bookId, String month});

final summaryProvider = FutureProvider.autoDispose.family<Summary, SummaryKey>((ref, key) async {
  final json = await ref.watch(apiClientProvider).get('/v1/books/${key.bookId}/summary', query: {'month': key.month});
  return Summary.fromJson(json as Map<String, dynamic>);
});

final budgetPlanProvider = FutureProvider.autoDispose.family<BudgetPlan, String>((ref, bookId) async {
  final json = await ref.watch(apiClientProvider).get('/v1/books/$bookId/budget-plan');
  return BudgetPlan.fromJson(json as Map<String, dynamic>);
});
