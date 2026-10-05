import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_mobile/core/api/api_client.dart';
import 'package:paisa_mobile/core/api/models.dart';
import 'package:paisa_mobile/core/money.dart';
import 'package:paisa_mobile/features/activity/activity_logic.dart';

import 'support/fakes.dart';

Transaction tx0({String kind = 'expense', String state = 'confirmed', String amount = '-75000', String? merchant = 'Swiggy', String? note, String? categoryId = 'cat_food', List<TxSplit> splits = const []}) => Transaction(
  id: 't', kind: kind, state: state, amountMinor: BigInt.parse(amount), occurredAt: DateTime.utc(2026, 8, 26), merchant: merchant, note: note,
  categoryId: categoryId, sources: const [], splits: splits, comments: const [],
);

final cats = {for (final c in (fixture('categories') as Map<String, dynamic>)['items'] as List) (c as Map<String, dynamic>)['id'] as String: Category.fromJson(c)};

void main() {
  group('search over what is loaded', () {
    test('matches merchant, note and category, ignoring case', () {
      final tx = tx0(note: 'Birthday dinner');
      expect(matchesSearch(tx, 'swig', cats), isTrue);
      expect(matchesSearch(tx, 'BIRTHDAY', cats), isTrue);
      expect(matchesSearch(tx, cats['cat_food']!.name.substring(0, 3), cats), isTrue);
      expect(matchesSearch(tx, 'zomato', cats), isFalse);
    });

    test('an empty query matches everything, and a missing merchant never throws', () {
      expect(matchesSearch(tx0(merchant: null), '  ', cats), isTrue);
      expect(matchesSearch(tx0(merchant: null), 'x', cats), isFalse);
    });
  });

  group('what the list calls a category', () {
    test('a split says how many ways, whatever the category was', () {
      final parts = [TxSplit(categoryId: 'cat_food', amountMinor: BigInt.from(-50000)), TxSplit(categoryId: 'cat_groceries', amountMinor: BigInt.from(-25000))];
      expect(categoryLabel(tx0(splits: parts), cats), 'Split 2 ways');
    });

    test('no category is "Uncategorised", except a transfer', () {
      expect(categoryLabel(tx0(categoryId: null), cats), 'Uncategorised');
      expect(categoryLabel(tx0(categoryId: null, kind: 'transfer'), cats), 'Transfer');
    });
  });

  test('voided and excluded payments do not count', () {
    expect(isCounted(tx0(state: 'voided')), isFalse);
    expect(isCounted(tx0(state: 'excluded')), isFalse);
    for (final state in ['pending_review', 'confirmed', 'reconciled']) {
      expect(isCounted(tx0(state: state)), isTrue, reason: state);
    }
  });

  group('the split remainder', () {
    test('is what the parts have not covered, by magnitude', () {
      expect(splitRemaining(BigInt.from(-75000), [BigInt.from(50000), BigInt.from(25000)]), BigInt.zero);
      expect(splitRemaining(BigInt.from(-75000), [BigInt.from(50000), null]), BigInt.from(25000));
    });

    test('goes negative when the parts overshoot', () {
      expect(splitRemaining(BigInt.from(75000), [BigInt.from(80000)]), BigInt.from(-5000));
    });
  });

  group('an edit sends only what changed', () {
    final before = tx0(note: null);
    Map<String, Object?> patch({String kind = 'expense', String amount = '-75000', String merchant = 'Swiggy', String note = '', String? account, String? counter, DateTime? at}) =>
        editPatch(before, kind: kind, amountMinor: BigInt.parse(amount), merchant: merchant, note: note, accountId: account, counterAccountId: counter, occurredAt: at);

    test('nothing changed is an empty patch', () => expect(patch(), isEmpty));

    test('kind and amount travel together when either changes', () {
      expect(patch(amount: '-80000'), {'kind': 'expense', 'amountMinor': '-80000'});
      expect(patch(kind: 'income', amount: '75000'), {'kind': 'income', 'amountMinor': '75000'});
    });

    test('a cleared text field becomes null, not an empty string', () {
      final withNote = tx0(note: 'x');
      final cleared = editPatch(withNote, kind: 'expense', amountMinor: BigInt.from(-75000), merchant: '', note: '', accountId: null, counterAccountId: null);
      expect(cleared, {'merchant': null, 'note': null});
    });

    test('the date is sent as an instant with a Z, and only if it moved', () {
      expect(patch(at: DateTime.utc(2026, 8, 26)), isEmpty);
      expect(patch(at: DateTime.utc(2026, 8, 24, 18, 30)), {'occurredAt': '2026-08-24T18:30:00.000Z'});
    });
  });

  group('a new payment', () {
    Map<String, Object?> body({String kind = 'expense', String? category, String merchant = ' Chai ', String note = ''}) => createBody(
      kind: kind, amountMinor: BigInt.from(-45000), merchant: merchant, note: note, categoryId: category, accountId: null, counterAccountId: null, occurredAt: DateTime.utc(2026, 8, 24, 18, 30),
    );

    test('without a category waits for review, with one it is confirmed', () {
      expect(body()['state'], 'pending_review');
      expect(body(category: 'cat_food')['state'], 'confirmed');
    });

    test('a transfer needs no review', () => expect(body(kind: 'transfer')['state'], 'confirmed'));

    test('leaves out what was not filled in, and trims what was', () {
      final sent = body();
      expect(sent.containsKey('note'), isFalse);
      expect(sent.containsKey('categoryId'), isFalse);
      expect(sent['merchant'], 'Chai');
      expect(sent['amountMinor'], '-45000');
      expect(sent['occurredAt'], '2026-08-24T18:30:00.000Z');
    });
  });

  group('a failed write is described without quoting the server', () {
    String say(ApiError e) => describeFailure(e);
    ApiError err(int status, String code, {Map<String, dynamic>? details}) => ApiError(status: status, code: code, message: 'wording that may change', details: details);

    test('no connection says nothing was changed', () => expect(say(err(0, 'NETWORK')), contains('Nothing was changed')));
    test('403 and 404 say what to do', () {
      expect(say(err(403, 'FORBIDDEN')), contains('role'));
      expect(say(err(404, 'NOT_FOUND')), contains('refresh'));
    });
    test('a validation error names the field it complains about', () {
      expect(say(err(400, 'VALIDATION_ERROR', details: {'fieldErrors': {'amountMinor': ['Amount cannot be zero']}})), 'Amount cannot be zero');
    });
    test('a conflicting idempotency key tells the person to check Activity', () => expect(say(err(409, 'IDEMPOTENCY_CONFLICT')), contains('Check Activity')));
  });

  test('plain rupees round-trip through minorFromRupees', () {
    for (final minor in ['75000', '75050', '5', '100', '123456789']) {
      expect(minorFromRupees(plainRupees(BigInt.parse(minor))), BigInt.parse(minor));
    }
    expect(plainRupees(BigInt.from(-75050)), '750.50', reason: 'a field shows the magnitude; the sign is the kind');
  });
}
