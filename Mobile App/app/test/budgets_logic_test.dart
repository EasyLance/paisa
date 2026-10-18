import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_mobile/core/api/api_client.dart';
import 'package:paisa_mobile/core/api/models.dart';
import 'package:paisa_mobile/core/money.dart';
import 'package:paisa_mobile/core/time.dart';
import 'package:paisa_mobile/features/budgets/budgets_logic.dart';

import 'support/fakes.dart';

Map<String, dynamic> body(String name) => (fixture(name) as Map<String, dynamic>)['body'] as Map<String, dynamic>;
Map<String, dynamic> requestBody(String name) => ((fixture(name) as Map<String, dynamic>)['request'] as Map<String, dynamic>)['body'] as Map<String, dynamic>;

ApiError errorOf(String name) {
  final saved = fixture(name) as Map<String, dynamic>;
  final json = saved['body'] as Map<String, dynamic>;
  return ApiError(status: saved['status'] as int, code: json['code'] as String, message: json['message'] as String, details: json['details'] as Map<String, dynamic>?);
}

List<Category> categories() => [for (final item in (fixture('categories') as Map<String, dynamic>)['items'] as List) Category.fromJson(item as Map<String, dynamic>)];

void main() {
  group('the 50 / 30 / 20 preset', () {
    test('sets the three groups the web sets and zeroes every other', () {
      final shares = presetShares(['Essentials', 'Lifestyle', 'Saving', 'Other', 'Travel']);
      expect(shares, {'Essentials': 50, 'Lifestyle': 30, 'Saving': 20, 'Other': 0, 'Travel': 0});
      expect(totalPercent(shares.values), 100);
    });

    test('is the plan the server holds once the preset is saved', () {
      final saved = BudgetPlan.fromJson(fixture('budget_plan_set') as Map<String, dynamic>);
      final groups = budgetGroups(categories(), saved);
      expect(planChanged(saved, presetShares(groups)), isFalse);
      expect(planChanged(BudgetPlan.fromJson(fixture('budget_plan') as Map<String, dynamic>), presetShares(groups)), isTrue, reason: 'an empty plan differs from the preset');
    });
  });

  group('groups', () {
    test('are the four the web offers, plus others the categories use, never Income', () {
      final empty = BudgetPlan.fromJson(fixture('budget_plan') as Map<String, dynamic>);
      expect(budgetGroups(categories(), empty), ['Essentials', 'Lifestyle', 'Saving', 'Other']);
      expect(categories().any((category) => category.groupName == 'Income'), isTrue, reason: 'setup: the recorded categories do include Income');
    });

    test('keep a group the saved plan already holds, so it can be seen and removed', () {
      final plan = BudgetPlan.fromJson(body('budget_plan_other_group'));
      expect(budgetGroups(categories(), plan), ['Essentials', 'Lifestyle', 'Saving', 'Other', 'Travel']);
      final income = BudgetPlan.fromJson({'items': [{'groupName': 'Income', 'percent': 5}], 'baseIncomeMinor': '0'});
      expect(budgetGroups(categories(), income), contains('Income'));
    });

    test('a group is matched without regard to case, as the server does', () {
      final plan = BudgetPlan.fromJson({'items': [{'groupName': 'essentials', 'percent': 40}], 'baseIncomeMinor': '0'});
      expect(budgetGroups(categories(), plan).where((group) => group.toLowerCase() == 'essentials'), hasLength(1));
      expect(sharesOf(plan, ['Essentials'])['Essentials'], 40);
    });
  });

  group('typed shares', () {
    test('blank is 0; a whole number from 0 to 100 is accepted', () {
      expect(parsePercent(''), 0);
      expect(parsePercent('  '), 0);
      expect(parsePercent('0'), 0);
      expect(parsePercent('35'), 35);
      expect(parsePercent('100'), 100);
    });

    test('anything else is refused rather than guessed', () {
      for (final bad in ['101', '999', '-5', '10.5', '1e1', 'ten', '1 0']) {
        expect(parsePercent(bad), isNull, reason: bad);
      }
    });

    test('the total and what is left are in words', () {
      expect(totalWords(100), 'Fully planned.');
      expect(totalWords(70), '30% unassigned.');
      expect(totalWords(110), '10% over. Trim a group to save.');
    });
  });

  group('rupees per share', () {
    test('are BigInt paise, truncated, and never add up to more than the income', () {
      final base = BigInt.parse((fixture('budget_plan_set') as Map<String, dynamic>)['baseIncomeMinor'] as String);
      expect(shareMinor(base, 50), BigInt.from(29393350));
      expect(formatMoney(shareMinor(base, 50)), '₹2,93,933.50');
      final preset = presetShares(defaultBudgetGroups);
      final sum = preset.values.fold(BigInt.zero, (total, percent) => total + shareMinor(base, percent));
      expect(sum <= base, isTrue);
      expect(base - sum < BigInt.from(3), isTrue, reason: 'only truncation is lost');
    });

    test('truncate rather than round, and survive an amount beyond 64 bits of paise', () {
      expect(shareMinor(BigInt.one, 33), BigInt.zero);
      final huge = BigInt.parse('99999999999999999999999');
      expect(shareMinor(huge, 100), huge);
    });

    test('are zero without an expected income', () {
      expect(shareMinor(BigInt.zero, 100), BigInt.zero);
    });
  });

  group('the plan request', () {
    test('sends what the server was recorded accepting, without the zero shares', () {
      final sent = requestBody('budget_plan_put');
      final shares = {for (final entry in (sent['allocations'] as List).cast<Map<String, dynamic>>()) entry['groupName'] as String: entry['percent'] as int};
      final built = planBody(shares)['allocations'] as List;
      final expected = [for (final entry in (sent['allocations'] as List).cast<Map<String, dynamic>>()) if ((entry['percent'] as int) > 0) entry];
      expect(built, expected);
      final answer = BudgetPlan.fromJson(body('budget_plan_put'));
      expect({for (final share in answer.items) share.groupName: share.percent}, {for (final entry in expected) entry['groupName'] as String: entry['percent'] as int});
    });

    test('an empty plan is a valid request that clears everything', () {
      expect(planBody({'Essentials': 0, 'Other': 0}), {'allocations': <Object>[]});
      expect(requestBody('budget_plan_empty'), {'allocations': <Object>[]});
      expect(BudgetPlan.fromJson(body('budget_plan_empty')).items, isEmpty);
    });

    test('knows when nothing differs from what is saved', () {
      final saved = BudgetPlan.fromJson(fixture('budget_plan_set') as Map<String, dynamic>);
      expect(planChanged(saved, {'Essentials': 50, 'Lifestyle': 30, 'Saving': 20, 'Other': 0}), isFalse);
      expect(planChanged(saved, {'Essentials': 50, 'Lifestyle': 30, 'Saving': 19, 'Other': 0}), isTrue);
      expect(planChanged(saved, {'Essentials': 50, 'Lifestyle': 30, 'Saving': 20, 'Other': 1}), isTrue);
      expect(planChanged(saved, {'Essentials': 50, 'Lifestyle': 30, 'Saving': 0, 'Other': 0}), isTrue);
    });

    test('a cap the phone enforces is the one the server enforces', () {
      final over = errorOf('budget_plan_over_100_error');
      expect(over.status, 400);
      final sent = (requestBody('budget_plan_over_100_error')['allocations'] as List).cast<Map<String, dynamic>>();
      final total = sent.fold<int>(0, (sum, entry) => sum + (entry['percent'] as int));
      expect(total, greaterThan(100));
      expect(over.fieldErrors['allocations'], 'Shares add up to $total% — they cannot exceed 100%');
      expect(describePlanFailure(over), over.fieldErrors['allocations'], reason: 'the server wording is shown as it is');
    });
  });

  group('expected income', () {
    test('a weekly income plan adds its share of twelve months, as the server counts it', () {
      final before = BigInt.parse((fixture('budget_plan') as Map<String, dynamic>)['baseIncomeMinor'] as String);
      final after = BigInt.parse(body('budget_plan_after_weekly_income')['baseIncomeMinor'] as String);
      final plan = RecurringPlan.fromJson(body('recurring_created_income'));
      expect(after - before, plan.amountMinor * BigInt.from(52) ~/ BigInt.from(12));
    });

    test('says where it comes from, and what to do when it is zero', () {
      expect(expectedIncomeNote(BigInt.from(100), canEdit: true), contains('recurring income plans'));
      expect(expectedIncomeNote(BigInt.zero, canEdit: true), contains('Adding a recurring income plan'));
      expect(expectedIncomeNote(BigInt.zero, canEdit: false), isNot(contains('Adding')));
    });
  });

  group('recurring plans', () {
    final clock = BookClock('Asia/Kolkata');

    test('every recorded plan keeps the sign of its kind', () {
      for (final name in ['recurring_created_expense', 'recurring_created_income', 'recurring_edited', 'recurring_stopped']) {
        final plan = RecurringPlan.fromJson(body(name));
        expect(plan.kind == 'expense', plan.amountMinor.isNegative, reason: name);
      }
      for (final item in (fixture('recurring_plans') as Map<String, dynamic>)['items'] as List) {
        final plan = RecurringPlan.fromJson(item as Map<String, dynamic>);
        expect(plan.kind == 'expense', plan.amountMinor.isNegative);
      }
    });

    test('parse a plan with no category and a stopped one', () {
      final created = RecurringPlan.fromJson(body('recurring_created_expense'));
      expect(created.categoryId, isNull, reason: 'the server leaves the key out when none was sent');
      expect(created.active, isTrue);
      expect(RecurringPlan.fromJson(body('recurring_stopped')).active, isFalse);
    });

    test('are listed soonest first, with the date in the book timezone', () {
      final plans = [
        RecurringPlan.fromJson(body('recurring_created_expense')),
        RecurringPlan.fromJson(((fixture('recurring_plans') as Map<String, dynamic>)['items'] as List).first as Map<String, dynamic>),
      ];
      expect(byNextDue(plans).map((plan) => plan.name), ['Monthly salary', 'Monthly rent']);
      expect(planDetail(plans.last, clock), 'Monthly · next 25 Sept');
      // Midnight in India is 18:30 UTC the day before; the day shown is India's.
      expect(planDetail(RecurringPlan.fromJson(body('recurring_created_income')), clock), 'Weekly · next 18 Oct');
    });

    test('a created plan is the body the server was recorded accepting', () {
      final built = recurringCreateBody(
        name: '  Monthly rent ',
        kind: 'expense',
        amountMinor: signedMinor('expense', minorFromRupees('25,000')!),
        cadence: 'monthly',
        nextDueAt: DateTime.utc(2026, 11, 1),
        categoryId: null,
      );
      expect(built, requestBody('recurring_created_expense'));
      final withCategory = recurringCreateBody(
        name: 'Freelance retainer',
        kind: 'income',
        amountMinor: signedMinor('income', minorFromRupees('12000')!),
        cadence: 'weekly',
        nextDueAt: clock.dateAt(2026, 10, 18),
        categoryId: 'cat_salary',
      );
      expect(withCategory, requestBody('recurring_created_income'));
    });

    test('a date a person picked is midnight in the book, sent with Z', () {
      final sent = recurringCreateBody(name: 'x', kind: 'expense', amountMinor: BigInt.from(-100), cadence: 'monthly', nextDueAt: clock.dateAt(2026, 11, 1), categoryId: null);
      expect(sent['nextDueAt'], '2026-10-31T18:30:00.000Z');
      expect(sent['nextDueAt'], endsWith('Z'));
    });

    test('an edit sends kind and amount together, and only what changed', () {
      final before = RecurringPlan.fromJson(body('recurring_created_expense'));
      final patch = recurringEditPatch(
        before,
        name: 'House rent',
        kind: 'expense',
        amountMinor: signedMinor('expense', minorFromRupees('30000')!),
        cadence: 'quarterly',
        categoryId: null,
        nextDueAt: DateTime.utc(2026, 12, 1),
      );
      expect(patch, requestBody('recurring_edited'));
    });

    test('changing only the amount, or only the kind, still sends both', () {
      final before = RecurringPlan.fromJson(body('recurring_created_expense'));
      final amountOnly = recurringEditPatch(before, name: before.name, kind: 'expense', amountMinor: BigInt.from(-3000000), cadence: 'monthly', categoryId: null);
      expect(amountOnly, {'kind': 'expense', 'amountMinor': '-3000000'});
      final kindOnly = recurringEditPatch(before, name: before.name, kind: 'income', amountMinor: signedMinor('income', before.amountMinor), cadence: 'monthly', categoryId: null);
      expect(kindOnly, {'kind': 'income', 'amountMinor': '2500000'});
      // The server refuses either on its own, which is why.
      expect(errorOf('recurring_error_amount_without_kind').fieldErrors['amountMinor'], 'Provide kind and amountMinor together');
    });

    test('an untouched plan sends nothing, and a cleared category is sent as null', () {
      final before = RecurringPlan.fromJson(body('recurring_created_income'));
      expect(recurringEditPatch(before, name: before.name, kind: before.kind, amountMinor: before.amountMinor, cadence: before.cadence, categoryId: before.categoryId, nextDueAt: before.nextDueAt), isEmpty);
      final cleared = recurringEditPatch(before, name: before.name, kind: before.kind, amountMinor: before.amountMinor, cadence: before.cadence, categoryId: null);
      expect(cleared, requestBody('recurring_category_cleared'));
    });
  });

  group('failure sentences', () {
    test('a validation message is passed on because it names the field', () {
      expect(describePlanFailure(errorOf('recurring_error_wrong_sign')), 'Expense amounts must be negative');
      expect(describePlanFailure(errorOf('recurring_error_naked_timestamp')), 'Invalid ISO datetime');
    });

    test('branch on status, not wording', () {
      expect(describePlanFailure(errorOf('budget_plan_forbidden')), 'Your role in this book cannot do that.');
      expect(describePlanFailure(errorOf('recurring_patch_not_found')), contains('no longer exists'));
      expect(describePlanFailure(const ApiError(status: 0, code: 'NETWORK', message: 'x')), contains('Nothing was changed'));
      expect(describePlanFailure(const ApiError(status: 500, code: 'X', message: 'x')), contains('could not save'));
    });

    test('a lost connection on create says the plan may have been saved, because the server has no idempotency key here', () {
      expect(describePlanFailure(const ApiError(status: 0, code: 'NETWORK', message: 'x'), created: true), contains('may or may not have been saved'));
    });
  });
}
