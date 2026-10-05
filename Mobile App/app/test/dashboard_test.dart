import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// A 360dp-wide phone, the narrowest common one: layouts that fit here fit
/// everywhere, and Flutter fails a test on any overflow.
Future<void> pumpDashboard(WidgetTester tester, Harness h, {Size size = const Size(1080, 2400)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(await h.app());
  await tester.pumpAndSettle();
}

Harness owner({FakeServer? server, DateTime? now, Map<String, Object>? prefs}) {
  final s = server ?? FakeServer();
  s.roles = ['book_owner'];
  return Harness(auth: FakeAuth(signedIn: true), server: s, now: now, prefs: prefs);
}

Map<String, dynamic> summary({String spent = '3932450', String moved = '1000000', String income = '58786700', String? balance, int pending = 1, List<Map<String, dynamic>>? lines, Map<String, dynamic>? period}) {
  final base = Map<String, dynamic>.from(fixture('summary_rich') as Map<String, dynamic>);
  base['spentMinor'] = spent;
  base['movedMinor'] = moved;
  base['incomeMinor'] = income;
  base['balanceMinor'] = balance ?? (BigInt.parse(income) - BigInt.parse(spent) - BigInt.parse(moved)).toString();
  base['pendingReview'] = pending;
  if (lines != null) base['byCategory'] = lines;
  if (period != null) base['period'] = period;
  return base;
}

void main() {
  group('the figures', () {
    testWidgets('show what the server said, in rupees', (tester) async {
      await pumpDashboard(tester, owner());
      expect(find.text('October 2026'), findsNothing);
      expect(find.text('August 2026'), findsOneWidget);
      expect(find.text('₹5,87,867'), findsWidgets, reason: 'income tile, and the base of the budget');
      expect(find.text('₹39,324.50'), findsOneWidget);
      expect(find.text('₹10,000'), findsWidgets);
      expect(find.text('₹5,38,542.50'), findsOneWidget);
      expect(find.text('6.6% of income'), findsOneWidget);
      expect(find.text('Income minus spending and saving'), findsOneWidget);
    });

    testWidgets('account for every rupee that left, including the uncategorised and the saved', (tester) async {
      await pumpDashboard(tester, owner());
      expect(find.text('Essentials'), findsOneWidget);
      expect(find.text('₹37,340'), findsOneWidget);
      expect(find.text('Other'), findsOneWidget);
      expect(find.text('₹11,234.50'), findsOneWidget);
      expect(find.text('Lifestyle'), findsOneWidget);
      expect(find.text('₹49,324.50 left the account: ₹39,324.50 spent and ₹10,000 saved to your own accounts.'), findsOneWidget);
    });

    testWidgets('a group opens to show its categories', (tester) async {
      await pumpDashboard(tester, owner());
      expect(find.text('EMI'), findsNothing);
      await tester.ensureVisible(find.text('Essentials'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Essentials'));
      await tester.pumpAndSettle();
      expect(find.text('EMI'), findsOneWidget);
      expect(find.text('₹35,000'), findsOneWidget);
    });

    testWidgets('a negative balance keeps its sign and says why', (tester) async {
      final server = FakeServer()..summaryBody = summary(spent: '60000000', moved: '0', income: '58786700');
      await pumpDashboard(tester, owner(server: server));
      expect(find.text('−₹12,133'), findsOneWidget);
      expect(find.text('You spent and saved more than you earned'), findsOneWidget);
    });

    testWidgets('an empty period says so instead of showing zeros as if they were spending', (tester) async {
      final server = FakeServer()..summaryBody = summary(spent: '0', moved: '0', income: '0', pending: 0, lines: []);
      await pumpDashboard(tester, owner(server: server));
      expect(find.text('No spending recorded this period yet.'), findsOneWidget);
      expect(find.text('No income to compare against'), findsOneWidget);
    });

    testWidgets('read fine in the dark on a narrow phone', (tester) async {
      await pumpDashboard(tester, owner(prefs: {'paisa.theme': 'dark'}), size: const Size(1080, 2400));
      expect(find.text('Where your money went'), findsOneWidget);
    });
  });

  group('months', () {
    testWidgets('open on today\'s period and cannot go past it', (tester) async {
      final h = owner();
      await pumpDashboard(tester, h);
      expect(h.server.summaryMonths, ['2026-08']);
      final next = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_right));
      expect(next.onPressed, isNull);
    });

    testWidgets('going back asks the server for that month, and shows nothing from this one meanwhile', (tester) async {
      final h = owner();
      await pumpDashboard(tester, h);
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      expect(h.server.summaryMonths, ['2026-08', '2026-07']);
      expect(find.text('July 2026'), findsOneWidget);
      final next = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_right));
      expect(next.onPressed, isNotNull);

      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(find.text('August 2026'), findsOneWidget);
    });

    testWidgets('a pay cycle is named for the month it pays for, with its window printed', (tester) async {
      final server = FakeServer()
        ..periodStartDay = 26
        ..summaryBody = summary(period: {'month': '2026-11', 'startDay': 26, 'startsAt': '2026-10-25T18:30:00.000Z', 'endsAt': '2026-11-25T18:30:00.000Z'});
      final h = owner(server: server, now: DateTime.parse('2026-10-28T12:00:00+05:30'));
      await pumpDashboard(tester, h);
      expect(h.server.summaryMonths, ['2026-11'], reason: '28 Oct is already inside the cycle that pays for November');
      expect(find.text('November 2026'), findsOneWidget);
      expect(find.text('26 Oct – 25 Nov'), findsOneWidget);
    });

    testWidgets('a calendar-month book prints no window', (tester) async {
      await pumpDashboard(tester, owner());
      expect(find.textContaining('–'), findsNothing);
    });
  });

  group('review card', () {
    testWidgets('counts what is waiting, with the verb agreeing', (tester) async {
      await pumpDashboard(tester, owner());
      expect(find.text('1 payment needs a quick review'), findsOneWidget);
    });

    testWidgets('says so when there is nothing to do', (tester) async {
      final server = FakeServer()..summaryBody = summary(pending: 0);
      await pumpDashboard(tester, owner(server: server));
      expect(find.text('You are all caught up'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Review'), findsNothing);
    });

    testWidgets('leads to the Activity tab', (tester) async {
      await pumpDashboard(tester, owner());
      await tester.tap(find.widgetWithText(FilledButton, 'Review'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ChoiceChip, 'Needs review'), findsOneWidget);
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Needs review')).selected, isTrue, reason: 'the list opens already filtered');
      expect(find.text('Monthly salary'), findsOneWidget);
    });

    testWidgets('is not offered to somebody who cannot act on a payment', (tester) async {
      final server = FakeServer()..roles = ['viewer'];
      await pumpDashboard(tester, Harness(auth: FakeAuth(signedIn: true), server: server));
      expect(find.text('1 payment needs a quick review'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Review'), findsNothing);
    });

    testWidgets('is offered to a reviewer, who can confirm', (tester) async {
      final server = FakeServer()..roles = ['reviewer'];
      await pumpDashboard(tester, Harness(auth: FakeAuth(signedIn: true), server: server));
      expect(find.widgetWithText(FilledButton, 'Review'), findsOneWidget);
    });
  });

  group('budget', () {
    testWidgets('shows each group\'s share of expected income', (tester) async {
      await pumpDashboard(tester, owner());
      await tester.scrollUntilVisible(find.text('Essentials · 50%'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Essentials · 50%'), findsOneWidget);
      expect(find.text('₹37,340 of ₹2,93,933.50'), findsOneWidget);
      expect(find.text('Lifestyle · 30%'), findsOneWidget);
      expect(find.text('Saving · 20%'), findsOneWidget);
      expect(find.textContaining('expected income'), findsOneWidget);
    });

    testWidgets('overspending is a word and a bar, not a red page', (tester) async {
      final server = FakeServer()
        ..summaryBody = summary(lines: [{'categoryId': 'cat_food', 'name': 'Food delivery', 'groupName': 'Lifestyle', 'amountMinor': '20000000'}], spent: '20000000', moved: '0');
      await pumpDashboard(tester, owner(server: server));
      await tester.scrollUntilVisible(find.text('Lifestyle · 30%'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('Over the plan'), findsOneWidget);
    });

    testWidgets('no plan yet explains itself', (tester) async {
      final server = FakeServer()..planBody = {'items': [], 'baseIncomeMinor': '0'};
      await pumpDashboard(tester, owner(server: server));
      await tester.scrollUntilVisible(find.textContaining('No budget plan yet'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('No budget plan yet'), findsOneWidget);
    });

    testWidgets('a budget that will not load leaves the true figures in place', (tester) async {
      final server = FakeServer()..planStatus = 500;
      await pumpDashboard(tester, owner(server: server));
      expect(find.text('₹39,324.50'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('The budget could not be loaded.'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('The budget could not be loaded.'), findsOneWidget);
    });
  });

  group('when the ledger cannot be reached', () {
    testWidgets('no figures and no zeros, only the error', (tester) async {
      final server = FakeServer()..summaryStatus = 500;
      await pumpDashboard(tester, owner(server: server));
      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('INCOME'), findsNothing);
      expect(find.textContaining('₹'), findsNothing);
    });

    testWidgets('offline says so, and Try again recovers', (tester) async {
      final h = owner();
      await pumpDashboard(tester, h);
      // Loaded fine; now the next month cannot be fetched.
      h.server.summaryStatus = 500;
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('INCOME'), findsNothing);

      h.server.summaryStatus = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('INCOME'), findsOneWidget);
      expect(find.text('July 2026'), findsOneWidget);
    });
  });
}
