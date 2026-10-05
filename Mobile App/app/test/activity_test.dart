import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_mobile/features/activity/activity_widgets.dart';

import 'support/fakes.dart';

/// 360dp wide, as the other screen tests: an overflow fails the test.
Future<void> pumpActivity(WidgetTester tester, {String role = 'book_owner', FakeServer? server}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final s = (server ?? FakeServer())..roles = [role];
  await tester.pumpWidget(await Harness(auth: FakeAuth(signedIn: true), server: s).app());
  await tester.pumpAndSettle();
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('Activity')));
  await tester.pumpAndSettle();
}

Future<void> openPayment(WidgetTester tester, String merchant) async {
  await tester.ensureVisible(find.text(merchant));
  await tester.pumpAndSettle();
  await tester.tap(find.text(merchant));
  await tester.pumpAndSettle();
}

Future<void> tapText(WidgetTester tester, String text) async {
  final target = find.text(text).hitTestable().evaluate().isEmpty ? find.text(text) : find.text(text).hitTestable();
  await tester.ensureVisible(target.first);
  await tester.pumpAndSettle();
  await tester.tap(target.first);
  await tester.pumpAndSettle();
}

Future<void> tapButton(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder field(String label) => find.widgetWithText(TextField, label);

void main() {
  group('the list', () {
    testWidgets('shows each payment with its date, category and signed amount', (tester) async {
      await pumpActivity(tester);
      expect(find.text('Swiggy'), findsOneWidget);
      expect(find.text('−₹750'), findsOneWidget);
      expect(find.text('26 Aug · Split 2 ways'), findsOneWidget);
      expect(find.text('+₹5,80,000'), findsOneWidget);
      expect(find.text('25 Aug · Salary'), findsOneWidget);
      expect(find.text('needs review'), findsOneWidget, reason: 'a state is a word, not a colour');
    });

    testWidgets('a chip asks the server for that state', (tester) async {
      final server = FakeServer();
      await pumpActivity(tester, server: server);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Needs review'));
      await tester.pumpAndSettle();
      expect(server.listQueries.last['state'], 'pending_review');
      expect(find.text('Monthly salary'), findsOneWidget);
      expect(find.text('Swiggy'), findsNothing);
    });

    testWidgets('says so when nothing needs review', (tester) async {
      final server = FakeServer();
      await pumpActivity(tester, server: server);
      server.ledger.removeWhere((item) => item['state'] == 'pending_review');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Needs review'));
      await tester.pumpAndSettle();
      expect(find.text('You are all caught up. Nothing needs review.'), findsOneWidget);
    });

    testWidgets('loads older payments a page at a time, then stops offering to', (tester) async {
      final server = FakeServer()..pageSize = 2;
      await pumpActivity(tester, server: server);
      expect(find.text('Hostel EMI'), findsNothing);
      await tapText(tester, 'Load older payments');
      expect(server.listQueries.last['cursor'], 'tx_1');
      expect(find.text('Hostel EMI'), findsOneWidget);
      await tapText(tester, 'Load older payments');
      expect(find.text('Electricity bill'), findsOneWidget);
      expect(find.text('Load older payments'), findsNothing);
    });

    testWidgets('a failed page keeps what is shown and offers another try', (tester) async {
      final server = FakeServer()..pageSize = 2;
      await pumpActivity(tester, server: server);
      server.ledgerStatus = 500;
      await tapText(tester, 'Load older payments');
      expect(find.text('Swiggy'), findsOneWidget);
      expect(find.text('Could not load older payments. Check your connection.'), findsOneWidget);
      server.ledgerStatus = null;
      await tapText(tester, 'Try again');
      expect(find.text('Hostel EMI'), findsOneWidget);
    });

    testWidgets('search covers what is loaded and says there is more', (tester) async {
      final server = FakeServer()..pageSize = 3;
      await pumpActivity(tester, server: server);
      await tester.enterText(find.byType(TextField).first, 'swig');
      await tester.pumpAndSettle();
      expect(find.text('Swiggy'), findsOneWidget);
      expect(find.text('Hostel EMI'), findsNothing);
      expect(find.textContaining('1 of 3 loaded payments match. Older payments are not searched until they are loaded.'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'chai');
      await tester.pumpAndSettle();
      expect(find.textContaining('No loaded payment matches “chai”. Load older payments to search further.'), findsOneWidget);
    });

    testWidgets('an error replaces the list rather than sitting beside it', (tester) async {
      final server = FakeServer()..ledgerStatus = 500;
      await pumpActivity(tester, server: server);
      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('Swiggy'), findsNothing);
      server.ledgerStatus = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Swiggy'), findsOneWidget);
    });

    testWidgets('offline shows no payments at all', (tester) async {
      final server = FakeServer();
      await pumpActivity(tester, server: server);
      server.offline = true;
      await tester.drag(find.text('Swiggy'), const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(find.text('Cannot reach Paisa'), findsOneWidget);
      expect(find.text('Swiggy'), findsNothing);
    });
  });

  group('what each role is offered', () {
    testWidgets('a viewer can look but not act', (tester) async {
      await pumpActivity(tester, role: 'viewer');
      expect(find.text('Add payment'), findsNothing);
      await openPayment(tester, 'Hostel EMI');
      expect(find.text('Edit payment'), findsNothing);
      expect(find.text('Change category'), findsNothing);
      expect(find.text('Split across categories'), findsNothing);
      expect(find.text('Void payment'), findsNothing);
      expect(find.byTooltip('Post comment'), findsNothing);
      expect(find.text('Comments'), findsOneWidget);
    });

    testWidgets('a reviewer can categorise, split and comment, not edit or void', (tester) async {
      await pumpActivity(tester, role: 'reviewer');
      expect(find.text('Add payment'), findsNothing);
      await openPayment(tester, 'Hostel EMI');
      expect(find.text('Change category'), findsOneWidget);
      expect(find.text('Split across categories'), findsOneWidget);
      expect(find.byTooltip('Post comment'), findsOneWidget);
      expect(find.text('Edit payment'), findsNothing);
      expect(find.text('Void payment'), findsNothing);
    });

    testWidgets('an editor can do all of it', (tester) async {
      await pumpActivity(tester, role: 'editor');
      expect(find.text('Add payment'), findsOneWidget);
      await openPayment(tester, 'Hostel EMI');
      for (final label in ['Edit payment', 'Change category', 'Split across categories', 'Void payment']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });
  });

  group('reviewing', () {
    testWidgets('confirming files it under its own category and leaves the "needs review" list', (tester) async {
      final server = FakeServer();
      await pumpActivity(tester, server: server);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Needs review'));
      await tester.pumpAndSettle();
      await openPayment(tester, 'Monthly salary');
      await tapButton(tester, find.widgetWithText(FilledButton, 'Confirm'));
      expect(server.writes, ['PATCH /category']);
      expect((server.lastBody as Map)['categoryId'], 'cat_salary');
      expect(find.text('Needs a quick review'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Monthly salary'), findsNothing);
      expect(find.text('You are all caught up. Nothing needs review.'), findsOneWidget);
    });

    testWidgets('a reviewer can confirm too, because choosing a category is what confirms', (tester) async {
      final server = FakeServer();
      await pumpActivity(tester, role: 'reviewer', server: server);
      await openPayment(tester, 'Monthly salary');
      await tapButton(tester, find.widgetWithText(FilledButton, 'Confirm'));
      expect(server.writes, ['PATCH /category']);
    });

    testWidgets('a new category can be remembered for the merchant, and the comments survive the answer', (tester) async {
      final server = FakeServer();
      await pumpActivity(tester, server: server);
      await openPayment(tester, 'Swiggy');
      expect(find.text('Checked against the bill'), findsOneWidget);
      await tapText(tester, 'Change category');
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      // The split rows behind the sheet also name Groceries.
      await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('Groceries')));
      await tester.pumpAndSettle();
      expect((server.lastBody as Map)['categoryId'], 'cat_groceries');
      expect((server.lastBody as Map)['applyToFuture'], isTrue);
      // The category route answers without comments; the screen must not lose them.
      expect(find.text('Checked against the bill'), findsOneWidget);
      expect(find.text('Split 2 ways'), findsWidgets);
    });

    testWidgets('voiding asks twice, and only the second answer writes', (tester) async {
      final server = FakeServer();
      await pumpActivity(tester, server: server);
      await openPayment(tester, 'Hostel EMI');
      await tapText(tester, 'Void payment');
      expect(find.text('Void this payment?'), findsOneWidget);
      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();
      expect(server.writes, isEmpty);
      await tapText(tester, 'Void payment');
      await tester.tap(find.widgetWithText(FilledButton, 'Void payment'));
      await tester.pumpAndSettle();
      expect(server.writes, ['PATCH transaction']);
      expect((server.lastBody as Map)['state'], 'voided');
      expect(find.text('voided'), findsOneWidget, reason: 'back on the list, where the row carries the word');
    });

    testWidgets('a comment is posted and shown', (tester) async {
      final server = FakeServer();
      await pumpActivity(tester, server: server);
      await openPayment(tester, 'Hostel EMI');
      await tester.ensureVisible(find.byTooltip('Post comment'));
      await tester.enterText(find.widgetWithText(TextField, 'Add a comment'), 'Paid on the 5th');
      await tester.pump();
      await tester.tap(find.byTooltip('Post comment'));
      await tester.pumpAndSettle();
      expect(find.text('Paid on the 5th'), findsOneWidget);
      expect(find.textContaining('You · 25 Aug'), findsOneWidget);
    });
  });

  group('editing', () {
    testWidgets('the amount and the type are sent together, and the new figure shows', (tester) async {
      final server = FakeServer();
      await pumpActivity(tester, server: server);
      await openPayment(tester, 'Hostel EMI');
      await tapText(tester, 'Edit payment');
      await tester.enterText(field('Amount'), '36000');
      await tapButton(tester, find.widgetWithText(FilledButton, 'Save changes'));
      expect(server.lastBody, {'kind': 'expense', 'amountMinor': '-3600000'});
      expect(find.text('−₹36,000'), findsWidgets);
    });

    testWidgets('turning an expense into income flips the sign with it', (tester) async {
      final server = FakeServer();
      await pumpActivity(tester, server: server);
      await openPayment(tester, 'Hostel EMI');
      await tapText(tester, 'Edit payment');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Income'));
      await tester.pumpAndSettle();
      await tapButton(tester, find.widgetWithText(FilledButton, 'Save changes'));
      expect(server.lastBody, {'kind': 'income', 'amountMinor': '3500000'});
    });

    testWidgets('saving without a change says so and sends nothing', (tester) async {
      final server = FakeServer();
      await pumpActivity(tester, server: server);
      await openPayment(tester, 'Hostel EMI');
      await tapText(tester, 'Edit payment');
      await tapButton(tester, find.widgetWithText(FilledButton, 'Save changes'));
      expect(find.text('Nothing has changed.'), findsOneWidget);
      expect(server.writes, isEmpty);
    });

    testWidgets('a split payment cannot change its amount from here', (tester) async {
      await pumpActivity(tester);
      await openPayment(tester, 'Swiggy');
      await tapText(tester, 'Edit payment');
      expect(find.textContaining('split, so its type and amount are locked'), findsOneWidget);
      expect(tester.widget<TextField>(field('Amount')).readOnly, isTrue);
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Income')).onSelected, isNull);
    });

    testWidgets('a statement figure is said to be kept', (tester) async {
      await pumpActivity(tester);
      await openPayment(tester, 'Acme Technologies Pvt Ltd');
      expect(find.text('Original amount'), findsOneWidget);
      expect(find.text('₹5,87,867'), findsOneWidget);
      await tapText(tester, 'Edit payment');
      expect(find.textContaining('The original figure is kept even if you correct it'), findsOneWidget);
    });
  });

  group('adding', () {
    Future<void> openForm(WidgetTester tester) async {
      await tester.tap(find.text('Add payment'));
      await tester.pumpAndSettle();
    }

    testWidgets('an amount is required', (tester) async {
      final server = FakeServer();
      await pumpActivity(tester, server: server);
      await openForm(tester);
      await tapButton(tester, find.widgetWithText(FilledButton, 'Add payment'));
      expect(find.textContaining('Enter an amount like 450'), findsOneWidget);
      await tester.enterText(field('Amount'), '12.345');
      await tapButton(tester, find.widgetWithText(FilledButton, 'Add payment'));
      expect(find.textContaining('at most two decimals'), findsOneWidget);
      expect(server.writes, isEmpty);
    });

    testWidgets('a payment with no category waits for review, on the book\'s own midnight', (tester) async {
      final server = FakeServer();
      await pumpActivity(tester, server: server);
      await openForm(tester);
      await tester.enterText(field('Amount'), '450');
      await tester.enterText(field('Merchant or person'), 'Tea stall');
      await tapButton(tester, find.widgetWithText(FilledButton, 'Add payment'));
      final body = server.lastBody as Map;
      expect(body['kind'], 'expense');
      expect(body['amountMinor'], '-45000');
      expect(body['state'], 'pending_review');
      // 25 August in India begins at 18:30 UTC on the 24th.
      expect(body['occurredAt'], '2026-08-24T18:30:00.000Z');
      expect(find.text('Tea stall'), findsOneWidget);
    });

    testWidgets('income is sent positive', (tester) async {
      final server = FakeServer();
      await pumpActivity(tester, server: server);
      await openForm(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Income'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Amount'), '1000');
      await tapButton(tester, find.widgetWithText(FilledButton, 'Add payment'));
      expect((server.lastBody as Map)['amountMinor'], '100000');
    });

    testWidgets('a retry after a dropped connection creates one payment, not two', (tester) async {
      final server = FakeServer()..dropNextCreateReply = true;
      await pumpActivity(tester, server: server);
      final before = server.ledger.length;
      await openForm(tester);
      await tester.enterText(field('Amount'), '450');
      await tester.enterText(field('Merchant or person'), 'Tea stall');
      await tapButton(tester, find.widgetWithText(FilledButton, 'Add payment'));
      expect(find.textContaining('Cannot reach Paisa'), findsOneWidget);
      await tapButton(tester, find.widgetWithText(FilledButton, 'Add payment'));
      expect(server.createKeys, hasLength(2));
      expect(server.createKeys.first, server.createKeys.last, reason: 'the same form, the same key');
      expect(server.ledger.length, before + 1);
      expect(find.text('Tea stall'), findsOneWidget);
    });
  });

  group('splitting', () {
    testWidgets('Save stays off until the parts add up exactly', (tester) async {
      final server = FakeServer();
      await pumpActivity(tester, server: server);
      await openPayment(tester, 'Electricity bill');
      await tapText(tester, 'Split across categories');
      FilledButton save() => tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save split'));
      expect(save().onPressed, isNull);
      expect(find.text('₹2,340 left to place'), findsOneWidget);

      await tester.tap(find.byType(PickerField).at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Utilities'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PickerField).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Groceries'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Amount').at(0), '1500');
      await tester.enterText(field('Amount').at(1), '800');
      await tester.pumpAndSettle();
      expect(find.text('₹40 left to place'), findsOneWidget);
      expect(save().onPressed, isNull);

      await tester.enterText(field('Amount').at(1), '900');
      await tester.pumpAndSettle();
      expect(find.text('Over by ₹60'), findsOneWidget);
      expect(save().onPressed, isNull);

      await tester.enterText(field('Amount').at(1), '840');
      await tester.pumpAndSettle();
      expect(find.text('Nothing left to place.'), findsOneWidget);
      expect(save().onPressed, isNotNull);

      await tester.tap(find.widgetWithText(FilledButton, 'Save split'));
      await tester.pumpAndSettle();
      expect(server.writes, ['PUT /splits']);
      final parts = ((server.lastBody as Map)['splits'] as List).cast<Map>();
      expect(parts.map((p) => p['amountMinor']), ['-150000', '-84000'], reason: 'an expense\'s parts are negative too');
      expect(parts.map((p) => p['categoryId']), ['cat_utilities', 'cat_groceries']);
      expect(find.text('Split 2 ways'), findsWidgets);
    });
  });
}
