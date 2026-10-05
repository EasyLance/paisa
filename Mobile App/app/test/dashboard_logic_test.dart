import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_mobile/core/api/models.dart';
import 'package:paisa_mobile/core/time.dart';
import 'package:paisa_mobile/features/dashboard/dashboard_logic.dart';

import 'support/fakes.dart';

Summary rich() => Summary.fromJson(fixture('summary_rich') as Map<String, dynamic>);
BudgetPlan planned() => BudgetPlan.fromJson(fixture('budget_plan_set') as Map<String, dynamic>);

SpendLine line(String name, String group, int paise) => SpendLine(categoryId: name, name: name, groupName: group, amountMinor: BigInt.from(paise));

void main() {
  group('the recorded summary', () {
    test('adds up: the breakdown is exactly what left the account', () {
      final s = rich();
      final total = s.byCategory.fold(BigInt.zero, (sum, line) => sum + line.amountMinor);
      expect(total, leftTheAccount(s));
      expect(total, s.spentMinor + s.movedMinor);
    });

    test('keeps uncategorised spending and outgoing transfers in the breakdown', () {
      final s = rich();
      expect(s.byCategory.map((l) => l.name), contains('Uncategorized'));
      expect(s.movedMinor, BigInt.from(1000000));
    });

    test('balance is income minus spent minus saved', () {
      final s = rich();
      expect(s.balanceMinor, s.incomeMinor - s.spentMinor - s.movedMinor);
    });
  });

  group('groupSpend', () {
    test('groups by the book\'s own groups, largest first', () {
      final groups = groupSpend(rich().byCategory);
      expect(groups.map((g) => g.name), ['Essentials', 'Other', 'Lifestyle']);
      expect(groups.first.total, BigInt.from(3734000));
      expect(groups.first.items.map((i) => i.name), ['EMI', 'Utilities']);
    });

    test('groups sum to the lines they were made from', () {
      final lines = rich().byCategory;
      expect(groupSpend(lines).fold(BigInt.zero, (s, g) => s + g.total), lines.fold(BigInt.zero, (s, l) => s + l.amountMinor));
    });

    test('equal totals are ordered by name so the screen does not shuffle', () {
      final groups = groupSpend([line('b', 'Zeta', 100), line('a', 'Alpha', 100)]);
      expect(groups.map((g) => g.name), ['Alpha', 'Zeta']);
    });

    test('nothing in, nothing out', () => expect(groupSpend(const []), isEmpty));

    test('a missing group name becomes Other', () {
      final l = SpendLine.fromJson({'categoryId': null, 'name': 'Uncategorized', 'groupName': null, 'amountMinor': '500'});
      expect(l.groupName, 'Other');
    });
  });

  group('percentOf', () {
    test('truncates to one decimal, as the web does', () {
      expect(percentOf(BigInt.from(3932450), BigInt.from(58786700)), 6.6);
      expect(percentOf(BigInt.from(1), BigInt.from(3)), 33.3);
    });
    test('is zero with nothing to compare against', () {
      expect(percentOf(BigInt.from(5), BigInt.zero), 0);
      expect(percentOf(BigInt.from(5), BigInt.from(-1)), 0);
    });
    test('goes past 100 when over', () => expect(percentOf(BigInt.from(150), BigInt.from(100)), 150));
  });

  group('budget', () {
    test('shares of expected income, spent per group', () {
      final rows = budgetRows(planned(), rich());
      expect(rows.map((r) => r.groupName), ['Essentials', 'Lifestyle', 'Saving']);
      expect(rows[0].allocated, BigInt.from(29393350)); // 50% of 58,78,67.00
      expect(rows[0].spent, BigInt.from(3734000));
      expect(rows[1].spent, BigInt.from(75000));
      expect(rows[2].spent, BigInt.zero);
      expect(rows.any((r) => r.over), isFalse);
    });

    test('with no recurring income, falls back to what arrived this period', () {
      final plan = BudgetPlan(items: planned().items, baseIncomeMinor: BigInt.zero);
      final base = budgetBase(plan, rich());
      expect(base.planned, isFalse);
      expect(base.base, rich().incomeMinor);
    });

    test('with no income at all every allowance is zero and any spending is over', () {
      final s = Summary(incomeMinor: BigInt.zero, spentMinor: BigInt.from(100), movedMinor: BigInt.zero, balanceMinor: BigInt.from(-100), pendingReview: 0, byCategory: [line('x', 'Essentials', 100)], period: null);
      final rows = budgetRows(BudgetPlan(items: const [BudgetShare(groupName: 'Essentials', percent: 50)], baseIncomeMinor: BigInt.zero), s);
      expect(rows.single.allocated, BigInt.zero);
      expect(rows.single.over, isTrue);
      expect(rows.single.warning, isFalse, reason: 'no allowance, so no percentage to warn about');
    });

    test('warns from 90% and is over past 100%', () {
      BudgetRow row(int spent) => BudgetRow(groupName: 'g', percent: 10, allocated: BigInt.from(1000), spent: BigInt.from(spent));
      expect(row(899).warning, isFalse);
      expect(row(900).warning, isTrue);
      expect(row(1000).over, isFalse);
      expect(row(1001).over, isTrue);
    });

    test('rounds the allowance down to a whole paisa, never up', () {
      final s = Summary(incomeMinor: BigInt.from(1000), spentMinor: BigInt.zero, movedMinor: BigInt.zero, balanceMinor: BigInt.from(1000), pendingReview: 0, byCategory: const [], period: null);
      final rows = budgetRows(BudgetPlan(items: const [BudgetShare(groupName: 'a', percent: 33)], baseIncomeMinor: BigInt.zero), s);
      expect(rows.single.allocated, BigInt.from(330));
    });
  });

  group('wording', () {
    test('review headline agrees with the number', () {
      expect(reviewHeadline(0), 'You are all caught up');
      expect(reviewHeadline(1), '1 payment needs a quick review');
      expect(reviewHeadline(3), '3 payments need a quick review');
    });

    test('spent detail needs income to compare against', () {
      expect(spentDetail(rich()), '6.6% of income');
      final none = Summary(incomeMinor: BigInt.zero, spentMinor: BigInt.from(5), movedMinor: BigInt.zero, balanceMinor: BigInt.from(-5), pendingReview: 0, byCategory: const [], period: null);
      expect(spentDetail(none), 'No income to compare against');
    });

    test('a negative balance says why', () {
      final none = Summary(incomeMinor: BigInt.zero, spentMinor: BigInt.from(5), movedMinor: BigInt.zero, balanceMinor: BigInt.from(-5), pendingReview: 0, byCategory: const [], period: null);
      expect(balanceDetail(none), 'You spent and saved more than you earned');
      expect(balanceDetail(rich()), 'Income minus spending and saving');
    });
  });

  group('periodWindow', () {
    final clock = BookClock('Asia/Kolkata');
    Period p(int day, String from, String to) => Period(month: '2026-11', startDay: day, startsAt: DateTime.parse(from), endsAt: DateTime.parse(to));

    test('is blank for calendar months, where the month name is enough', () {
      expect(periodWindow(p(1, '2026-07-31T18:30:00Z', '2026-08-31T18:30:00Z'), clock), '');
      expect(periodWindow(null, clock), '');
    });

    test('names both ends of a pay cycle, the last being the day before the next starts', () {
      expect(periodWindow(p(26, '2026-10-25T18:30:00Z', '2026-11-25T18:30:00Z'), clock), '26 Oct – 25 Nov');
      expect(periodWindow(p(26, '2026-09-25T18:30:00Z', '2026-10-25T18:30:00Z'), clock), '26 Sept – 25 Oct');
    });
  });
}
