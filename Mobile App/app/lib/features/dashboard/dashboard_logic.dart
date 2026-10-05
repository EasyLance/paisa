// What the dashboard says, with no widgets in it, so every rule can be tested
// directly. The rules mirror the web dashboard (apps/web/app/page.tsx); the
// server does the arithmetic that matters (totals, the pay-cycle window) and this
// file only groups, divides and words what it is handed.
import '../../core/api/models.dart';
import '../../core/time.dart';

/// `part` as a percentage of `whole`, to one decimal. Zero when there is nothing
/// to compare against. A percentage is a display figure, never an amount.
double percentOf(BigInt part, BigInt whole) {
  if (whole <= BigInt.zero) return 0;
  return (part * BigInt.from(1000) ~/ whole).toInt() / 10;
}

class SpendGroup {
  const SpendGroup({required this.name, required this.total, required this.items});

  final String name;
  final BigInt total;
  final List<SpendLine> items;
}

/// Spending grouped as the book actually used it, largest first, so the legend
/// always adds up to what left the account. A fixed list of groups once hid
/// uncategorised spending.
List<SpendGroup> groupSpend(List<SpendLine> lines) {
  final byGroup = <String, List<SpendLine>>{};
  for (final line in lines) {
    (byGroup[line.groupName] ??= []).add(line);
  }
  final groups = [
    for (final entry in byGroup.entries)
      SpendGroup(
        name: entry.key,
        total: entry.value.fold(BigInt.zero, (sum, line) => sum + line.amountMinor),
        items: [...entry.value]..sort((a, b) => b.amountMinor.compareTo(a.amountMinor)),
      ),
  ];
  groups.sort((a, b) {
    final byTotal = b.total.compareTo(a.total);
    return byTotal != 0 ? byTotal : a.name.compareTo(b.name);
  });
  return groups;
}

/// Everything that left the account this period: spent plus saved to your own
/// accounts. The breakdown always sums to this, and the server tests that.
BigInt leftTheAccount(Summary summary) => summary.spentMinor + summary.movedMinor;

class BudgetRow {
  const BudgetRow({required this.groupName, required this.percent, required this.allocated, required this.spent});

  final String groupName;
  final int percent;
  final BigInt allocated;
  final BigInt spent;

  bool get over => spent > allocated;

  /// 0 to 100 and beyond, to one decimal. With no allowance at all, spending is
  /// "over" but has no percentage, so 0 is returned and [over] says the rest.
  double get usedPercent => percentOf(spent, allocated);

  /// The web turns a row amber from 90%.
  bool get warning => allocated > BigInt.zero && usedPercent >= 90;
}

/// Shares are of *expected* income so a budget works before payday. With no
/// income plan yet, fall back to what actually arrived this period.
({BigInt base, bool planned}) budgetBase(BudgetPlan plan, Summary summary) {
  final planned = plan.baseIncomeMinor > BigInt.zero;
  return (base: planned ? plan.baseIncomeMinor : summary.incomeMinor, planned: planned);
}

List<BudgetRow> budgetRows(BudgetPlan plan, Summary summary) {
  final base = budgetBase(plan, summary).base;
  final groups = {for (final group in groupSpend(summary.byCategory)) group.name: group.total};
  return [
    for (final share in plan.items)
      BudgetRow(
        groupName: share.groupName,
        percent: share.percent,
        allocated: base * BigInt.from(share.percent) ~/ BigInt.from(100),
        spent: groups[share.groupName] ?? BigInt.zero,
      ),
  ];
}

String spentDetail(Summary summary) => summary.incomeMinor > BigInt.zero
    ? '${percentOf(summary.spentMinor, summary.incomeMinor).toStringAsFixed(1)}% of income'
    : 'No income to compare against';

String balanceDetail(Summary summary) =>
    summary.balanceMinor.isNegative ? 'You spent and saved more than you earned' : 'Income minus spending and saving';

// The web says "1 payment need a quick review"; the verb agrees here.
String reviewHeadline(int pending) => pending == 0
    ? 'You are all caught up'
    : pending == 1
        ? '1 payment needs a quick review'
        : '$pending payments need a quick review';

String reviewDetail(int pending) => pending == 0
    ? 'Every detected payment has been reviewed.'
    : 'Confirm the categories while they are fresh.';

/// "26 Sept – 25 Oct". Printed only when the book is not on calendar months,
/// because then the month name alone is ambiguous. The window is the server's;
/// `endsAt` is the first instant of the next cycle, so the last day is the day before.
String periodWindow(Period? period, BookClock clock) {
  if (period == null || period.startDay == 1) return '';
  final last = period.endsAt.subtract(const Duration(days: 1));
  return '${clock.shortDate(period.startsAt)} – ${clock.shortDate(last)}';
}
