import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_mobile/features/budgets/budgets_screen.dart';

import 'support/budget_fakes.dart';
import 'support/fakes.dart';

/// 360dp wide, as the other screen tests: an overflow fails the test.
Future<FakeServer> pumpBudgets(WidgetTester tester, {String role = 'book_owner', FakeServer? server, Map<String, Object>? prefs}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final s = (server ?? FakeServer())..roles = [role];
  await tester.pumpWidget(await Harness(auth: FakeAuth(signedIn: true), server: s, prefs: prefs).app());
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Budgets')));
  await tester.pumpAndSettle();
  return s;
}

Finder inBudgets(Finder finder) => find.descendant(of: find.byType(BudgetsScreen), matching: finder);
Finder share(String group) => find.byKey(ValueKey('share-$group'));

/// The tab is one long list that builds lazily, so scroll until the thing exists.
Future<void> reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(finder, 200, scrollable: find.descendant(of: find.byType(BudgetsScreen), matching: find.byType(Scrollable)).first);
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> tapText(WidgetTester tester, String text) async {
  await reveal(tester, find.text(text));
  final target = find.text(text).hitTestable().evaluate().isEmpty ? find.text(text) : find.text(text).hitTestable();
  await tester.tap(target.first);
  await tester.pumpAndSettle();
}

Future<void> tapButton(WidgetTester tester, Finder finder) async {
  await reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> typeShare(WidgetTester tester, String group, String value) async {
  await reveal(tester, share(group));
  await tester.enterText(share(group), value);
  await tester.pumpAndSettle();
}

Finder saveShares() => find.widgetWithText(FilledButton, 'Save shares');
bool canSave(WidgetTester tester) => tester.widget<FilledButton>(saveShares()).onPressed != null;

Finder field(String label) => find.widgetWithText(TextFormField, label);

Map<String, dynamic> emptyPlan() => {'items': <Object>[], 'baseIncomeMinor': '58786700'};

void main() {
  group('the plan', () {
    testWidgets('shows the saved shares, what each is worth in rupees, and the total', (tester) async {
      await pumpBudgets(tester);
      expect(inBudgets(find.text('EXPECTED MONTHLY INCOME')), findsOneWidget);
      expect(inBudgets(find.text('₹5,87,867')), findsOneWidget);
      expect(inBudgets(find.textContaining('recurring income plans')), findsOneWidget);
      expect(tester.widget<TextField>(share('Essentials')).controller!.text, '50');
      expect(tester.widget<TextField>(share('Lifestyle')).controller!.text, '30');
      expect(tester.widget<TextField>(share('Saving')).controller!.text, '20');
      expect(tester.widget<TextField>(share('Other')).controller!.text, '');
      expect(inBudgets(find.text('₹2,93,933.50 a month')), findsOneWidget);
      expect(inBudgets(find.text('No share')), findsOneWidget, reason: 'the Other group has none');
      await reveal(tester, inBudgets(find.text('Fully planned.')));
      expect(inBudgets(find.text('100%')), findsOneWidget);
      expect(inBudgets(find.text('Fully planned.')), findsOneWidget);
    });

    testWidgets('over 100 is said in words and cannot be saved', (tester) async {
      final server = await pumpBudgets(tester);
      expect(canSave(tester), isFalse, reason: 'nothing has changed yet');
      await typeShare(tester, 'Essentials', '60');
      expect(find.text('10% over. Trim a group to save.'), findsOneWidget);
      expect(find.text('110%'), findsOneWidget);
      expect(canSave(tester), isFalse);
      await typeShare(tester, 'Essentials', '40');
      expect(find.text('10% unassigned.'), findsOneWidget);
      expect(canSave(tester), isTrue);
      expect(budgetState(server).planPuts, isEmpty);
    });

    testWidgets('a share that is not a whole number up to 100 is named and blocks saving', (tester) async {
      await pumpBudgets(tester);
      await typeShare(tester, 'Other', '101');
      expect(find.text('0 to 100'), findsOneWidget);
      expect(find.text('Enter each share as a whole number from 0 to 100.'), findsOneWidget);
      expect(canSave(tester), isFalse);
      await typeShare(tester, 'Other', '');
      expect(find.text('0 to 100'), findsNothing);
    });

    testWidgets('the preset fills 50 / 30 / 20, saves, and the Overview budget card follows', (tester) async {
      final server = FakeServer()..planBody = emptyPlan();
      await pumpBudgets(tester, server: server);
      expect(inBudgets(find.text('Fully planned.')), findsNothing);
      await tapButton(tester, find.text('Use 50 / 30 / 20'));
      expect(tester.widget<TextField>(share('Essentials')).controller!.text, '50');
      expect(tester.widget<TextField>(share('Other')).controller!.text, '');
      expect(canSave(tester), isTrue);
      await tapButton(tester, saveShares());
      expect(budgetState(server).planPuts.single, {
        'allocations': [
          {'groupName': 'Essentials', 'percent': 50},
          {'groupName': 'Lifestyle', 'percent': 30},
          {'groupName': 'Saving', 'percent': 20},
        ],
      });
      expect(find.text('Shares saved.'), findsOneWidget);
      expect(canSave(tester), isFalse, reason: 'what is on screen is now what is saved');
      expect(server.requests.where((request) => request == 'GET /v1/books/book_arjun/budget-plan').length, greaterThanOrEqualTo(2), reason: 'the plan is fetched again');

      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Overview')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Essentials · 50%'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('Essentials · 50%'), findsOneWidget);
    });

    testWidgets('a share set to zero is dropped from the request, as the server replaces the whole plan', (tester) async {
      final server = await pumpBudgets(tester);
      await typeShare(tester, 'Saving', '0');
      await tapButton(tester, saveShares());
      expect(budgetState(server).planPuts.single['allocations'], [
        {'groupName': 'Essentials', 'percent': 50},
        {'groupName': 'Lifestyle', 'percent': 30},
      ]);
    });

    testWidgets('a refusal from the server is shown in its words and nothing on screen changes', (tester) async {
      final server = await pumpBudgets(tester);
      budgetState(server).nextWriteError = fixture('budget_plan_over_100_error') as Map<String, dynamic>;
      await typeShare(tester, 'Saving', '10');
      await tapButton(tester, saveShares());
      expect(find.text('Shares add up to 110% — they cannot exceed 100%'), findsOneWidget);
      expect(find.text('Shares saved.'), findsNothing);
      expect(tester.widget<TextField>(share('Saving')).controller!.text, '10', reason: 'what was typed is kept so it can be fixed');
      expect(server.planBody, isNull, reason: 'the server kept the old plan');
    });

    testWidgets('a lost connection says nothing was changed', (tester) async {
      final server = await pumpBudgets(tester);
      await typeShare(tester, 'Saving', '10');
      server.offline = true;
      await tapButton(tester, saveShares());
      expect(find.textContaining('Nothing was changed'), findsOneWidget);
    });

    testWidgets('with no expected income it says how to set one, and shows no rupee amounts', (tester) async {
      final server = FakeServer()..planBody = {'items': <Object>[], 'baseIncomeMinor': '0'};
      await pumpBudgets(tester, server: server);
      expect(inBudgets(find.text('₹0')), findsOneWidget);
      expect(inBudgets(find.textContaining('Adding a recurring income plan')), findsOneWidget);
      expect(inBudgets(find.textContaining(' a month')), findsNothing);
    });
  });

  group('errors replace the figures', () {
    testWidgets('a plan that will not load shows the panel and none of the figures', (tester) async {
      final server = FakeServer()..planStatus = 500;
      await pumpBudgets(tester, server: server);
      expect(inBudgets(find.text('Something went wrong')), findsOneWidget);
      expect(inBudgets(find.text('₹5,87,867')), findsNothing);
      expect(inBudgets(find.text('Save shares')), findsNothing);
    });

    testWidgets('recurring plans that will not load do the same, and Try again recovers', (tester) async {
      final server = FakeServer();
      budgetState(server).plansStatus = 500;
      await pumpBudgets(tester, server: server);
      expect(inBudgets(find.text('Something went wrong')), findsOneWidget);
      expect(inBudgets(find.text('Monthly salary')), findsNothing);
      budgetState(server).plansStatus = null;
      await tester.tap(inBudgets(find.text('Try again')));
      await tester.pumpAndSettle();
      await reveal(tester, inBudgets(find.text('Monthly salary')));
      expect(inBudgets(find.text('Monthly salary')), findsOneWidget);
    });

    testWidgets('no connection says so', (tester) async {
      final server = FakeServer();
      await pumpBudgets(tester, server: server);
      server.offline = true;
      await tester.drag(find.byType(ListView).last, const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(inBudgets(find.text('Cannot reach Paisa')), findsOneWidget);
    });
  });

  group('what each role is offered', () {
    for (final role in ['viewer', 'reviewer']) {
      testWidgets('a $role reads the plan and the plans, with nothing to change', (tester) async {
        await pumpBudgets(tester, role: role);
        expect(inBudgets(find.text('Essentials')), findsOneWidget);
        expect(inBudgets(find.text('50%')), findsOneWidget);
        expect(inBudgets(find.text('Saving')), findsOneWidget);
        expect(inBudgets(find.text('Other')), findsNothing, reason: 'a group with no share is not listed');
        expect(inBudgets(find.byType(TextField)), findsNothing);
        expect(inBudgets(find.text('Save shares')), findsNothing);
        expect(inBudgets(find.text('Use 50 / 30 / 20')), findsNothing);
        expect(inBudgets(find.text('Add recurring plan')), findsNothing);
        expect(inBudgets(find.textContaining('Someone who can edit this book')), findsNothing, reason: 'income is set, so no hint is needed');
        await reveal(tester, inBudgets(find.text('Monthly salary')));
        expect(inBudgets(find.text('Monthly salary')), findsOneWidget);
        expect(inBudgets(find.text('active')), findsOneWidget);
        await tester.tap(inBudgets(find.text('Monthly salary')));
        await tester.pumpAndSettle();
        expect(find.text('Edit recurring plan'), findsNothing);
      });
    }

    testWidgets('a viewer of a book with no plan and no income is told who can set them', (tester) async {
      final server = FakeServer()..planBody = {'items': <Object>[], 'baseIncomeMinor': '0'};
      await pumpBudgets(tester, role: 'viewer', server: server);
      expect(inBudgets(find.textContaining('Someone who can edit this book adds one')), findsOneWidget);
      expect(inBudgets(find.text('No shares set yet. Someone who can edit this book sets them here.')), findsOneWidget);
    });

    for (final role in ['editor', 'book_owner']) {
      testWidgets('an $role edits the plan and the recurring plans', (tester) async {
        await pumpBudgets(tester, role: role);
        expect(inBudgets(find.byType(TextField)), findsNWidgets(4));
        expect(inBudgets(find.text('Use 50 / 30 / 20')), findsOneWidget);
        await reveal(tester, inBudgets(find.text('Add recurring plan')));
        expect(inBudgets(find.text('Add recurring plan')), findsOneWidget);
      });
    }
  });

  group('recurring plans', () {
    testWidgets('lists each with its cadence, next date, signed amount and a word for its state', (tester) async {
      await pumpBudgets(tester);
      await reveal(tester, inBudgets(find.text('Monthly salary')));
      expect(inBudgets(find.text('Monthly · next 25 Sept')), findsOneWidget);
      expect(inBudgets(find.text('+₹5,87,867')), findsOneWidget);
      expect(inBudgets(find.text('active')), findsOneWidget);
      expect(inBudgets(find.textContaining('adds it to Activity on its own')), findsOneWidget);
    });

    testWidgets('says what to do when there are none', (tester) async {
      final server = FakeServer();
      budgetState(server).plans.clear();
      await pumpBudgets(tester, server: server);
      await reveal(tester, inBudgets(find.textContaining('No recurring plans yet')));
      expect(inBudgets(find.textContaining('Add your salary')), findsOneWidget);
    });

    testWidgets('adds an expense: negative, midnight in the book, sent with Z', (tester) async {
      final server = await pumpBudgets(tester);
      await tapButton(tester, find.text('Add recurring plan'));
      expect(find.text('Add recurring plan'), findsWidgets);
      await tester.enterText(field('Name'), 'Monthly rent');
      await tester.enterText(field('Amount'), '25,000');
      await tapButton(tester, find.text('Add plan'));
      final sent = budgetState(server).planWrites.single;
      expect(sent.method, 'POST');
      expect(sent.body, {
        'name': 'Monthly rent',
        'kind': 'expense',
        'amountMinor': '-2500000',
        'cadence': 'monthly',
        'nextDueAt': '2026-08-24T18:30:00.000Z',
      });
      expect(find.text('Monthly rent added.'), findsOneWidget);
      await reveal(tester, inBudgets(find.text('Monthly rent')));
      expect(inBudgets(find.text('−₹25,000')), findsOneWidget);
      expect(inBudgets(find.text('Monthly · next 25 Aug')), findsOneWidget);
    });

    testWidgets('adds income: positive, weekly', (tester) async {
      final server = await pumpBudgets(tester);
      await tapButton(tester, find.text('Add recurring plan'));
      await tester.enterText(field('Name'), 'Retainer');
      await tapButton(tester, find.widgetWithText(ChoiceChip, 'Income'));
      await tester.enterText(field('Amount'), '12000');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Weekly').last);
      await tester.pumpAndSettle();
      await tapButton(tester, find.text('Add plan'));
      final body = budgetState(server).planWrites.single.body;
      expect(body['kind'], 'income');
      expect(body['amountMinor'], '1200000');
      expect(body['cadence'], 'weekly');
      expect(BigInt.parse(body['amountMinor'] as String).isNegative, isFalse);
    });

    testWidgets('will not send a blank name or an amount with three decimals', (tester) async {
      final server = await pumpBudgets(tester);
      await tapButton(tester, find.text('Add recurring plan'));
      await tapButton(tester, find.text('Add plan'));
      expect(find.text('Give the plan a name.'), findsOneWidget);
      expect(find.text('Enter an amount like 450 or 450.50, with at most two decimals.'), findsOneWidget);
      await tester.enterText(field('Name'), 'x');
      await tester.enterText(field('Amount'), '10.123');
      await tapButton(tester, find.text('Add plan'));
      expect(find.text('Enter an amount like 450 or 450.50, with at most two decimals.'), findsOneWidget);
      await tester.enterText(field('Amount'), '0');
      await tapButton(tester, find.text('Add plan'));
      expect(find.text('The amount cannot be zero.'), findsOneWidget);
      expect(budgetState(server).planWrites, isEmpty);
    });

    testWidgets('the server refusing a plan is shown in its words, and the form stays', (tester) async {
      final server = await pumpBudgets(tester);
      budgetState(server).nextWriteError = fixture('recurring_error_wrong_sign') as Map<String, dynamic>;
      await tapButton(tester, find.text('Add recurring plan'));
      await tester.enterText(field('Name'), 'Rent');
      await tester.enterText(field('Amount'), '100');
      await tapButton(tester, find.text('Add plan'));
      expect(find.text('Expense amounts must be negative'), findsOneWidget);
      expect(find.text('Add recurring plan'), findsWidgets);
      expect(find.text('Rent added.'), findsNothing);
    });

    testWidgets('a lost reply does not claim the plan was not saved, and the list shows it', (tester) async {
      final server = await pumpBudgets(tester);
      budgetState(server).dropNextPlanCreateReply = true;
      await tapButton(tester, find.text('Add recurring plan'));
      await tester.enterText(field('Name'), 'Rent');
      await tester.enterText(field('Amount'), '100');
      await tapButton(tester, find.text('Add plan'));
      expect(find.textContaining('may or may not have been saved'), findsOneWidget);
      expect(find.textContaining('Nothing was changed'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await reveal(tester, inBudgets(find.text('Rent')));
      expect(inBudgets(find.text('Rent')), findsOneWidget, reason: 'the server did save it, and the list was fetched again');
    });

    testWidgets('an edit shows the plan as it is, and sends kind and amount together', (tester) async {
      final server = await pumpBudgets(tester);
      await tapText(tester, 'Monthly salary');
      expect(find.text('Edit recurring plan'), findsOneWidget);
      expect(tester.widget<TextFormField>(field('Name')).controller!.text, 'Monthly salary');
      expect(tester.widget<TextFormField>(field('Amount')).controller!.text, '587867');
      await tester.enterText(field('Amount'), '600000');
      await tapButton(tester, find.text('Save changes'));
      final sent = budgetState(server).planWrites.single;
      expect(sent.method, 'PATCH');
      expect(sent.body, {'kind': 'income', 'amountMinor': '60000000'});
      expect(find.text('Changes saved.'), findsOneWidget);
      await reveal(tester, inBudgets(find.text('+₹6,00,000')));
      expect(inBudgets(find.text('+₹6,00,000')), findsOneWidget);
    });

    testWidgets('switching the type flips the sign in the same request', (tester) async {
      final server = await pumpBudgets(tester);
      await tapText(tester, 'Monthly salary');
      await tapButton(tester, find.widgetWithText(ChoiceChip, 'Expense'));
      await tapButton(tester, find.text('Save changes'));
      expect(budgetState(server).planWrites.single.body, {'kind': 'expense', 'amountMinor': '-58786700'});
    });

    testWidgets('saving an untouched plan sends nothing', (tester) async {
      final server = await pumpBudgets(tester);
      await tapText(tester, 'Monthly salary');
      await tapButton(tester, find.text('Save changes'));
      expect(find.text('Nothing has changed.'), findsOneWidget);
      expect(budgetState(server).planWrites, isEmpty);
    });

    testWidgets('stopping asks first, then the plan leaves the list and can be turned back on', (tester) async {
      final server = await pumpBudgets(tester);
      await tapText(tester, 'Monthly salary');
      await tapButton(tester, find.text('Stop this plan'));
      expect(find.text('Stop Monthly salary?'), findsOneWidget);
      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();
      expect(budgetState(server).planWrites, isEmpty, reason: 'cancelling sends nothing');

      await tapButton(tester, find.text('Stop this plan'));
      await tester.tap(find.text('Stop plan'));
      await tester.pumpAndSettle();
      expect(budgetState(server).planWrites.single.body, {'active': false});
      expect(find.text('Monthly salary stopped. It will not post again.'), findsOneWidget);
      expect(inBudgets(find.text('Monthly · next 25 Sept')), findsNothing);
      await reveal(tester, inBudgets(find.textContaining('No recurring plans yet')));
      expect(inBudgets(find.textContaining('No recurring plans yet')), findsOneWidget);

      await tester.tap(find.text('Turn back on'));
      await tester.pumpAndSettle();
      expect(budgetState(server).planWrites.last.body, {'active': true});
      expect(find.text('Monthly salary is on again.'), findsOneWidget);
      await reveal(tester, inBudgets(find.text('Monthly salary')));
      expect(inBudgets(find.text('active')), findsOneWidget);
    });

    testWidgets('a stop that fails changes nothing and says so', (tester) async {
      final server = await pumpBudgets(tester);
      await tapText(tester, 'Monthly salary');
      budgetState(server).nextWriteError = fixture('recurring_patch_not_found') as Map<String, dynamic>;
      await tapButton(tester, find.text('Stop this plan'));
      await tester.tap(find.text('Stop plan'));
      await tester.pumpAndSettle();
      expect(find.textContaining('no longer exists'), findsOneWidget);
      expect(find.text('Edit recurring plan'), findsOneWidget, reason: 'still on the form');
    });
  });

  group('long figures and a large font', () {
    testWidgets('a huge income, a long name and 130% text still fit at 360dp', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final server = FakeServer()..planBody = {'items': [{'groupName': 'Essentials', 'percent': 50}, {'groupName': 'Lifestyle', 'percent': 30}, {'groupName': 'Saving', 'percent': 20}], 'baseIncomeMinor': '123456789012'};
      budgetState(server).plans.add({
        ...(fixture('recurring_created_expense') as Map<String, dynamic>)['body'] as Map<String, dynamic>,
        'id': 'long',
        'name': 'An unusually long recurring plan name that keeps going well past one line',
        'amountMinor': '-999999999900',
      });
      await pumpBudgets(tester, server: server);
      expect(inBudgets(find.text('₹1,23,45,67,890.12')), findsOneWidget);
      await reveal(tester, inBudgets(find.text('−₹9,99,99,99,999')));
      expect(inBudgets(find.text('−₹9,99,99,99,999')), findsOneWidget);
    });
  });

  group('at 360dp in the dark', () {
    testWidgets('the whole tab, the form and an over-100 total fit and read', (tester) async {
      await pumpBudgets(tester, prefs: {'paisa.theme': 'dark'});
      await typeShare(tester, 'Essentials', '90');
      expect(find.text('40% over. Trim a group to save.'), findsOneWidget);
      await tapButton(tester, find.text('Add recurring plan'));
      expect(find.text('Add plan'), findsOneWidget);
    });
  });
}
