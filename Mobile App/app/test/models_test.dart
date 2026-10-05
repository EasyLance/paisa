import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_mobile/core/api/models.dart';

// These fixtures were recorded from a local API (apps/api, memory store, sample
// data). If one changes, the API moved: update the model on purpose.
dynamic fixture(String name) => jsonDecode(File('test/fixtures/$name.json').readAsStringSync());

void main() {
  paymentModels();
  test('Me parses /v1/me', () {
    final me = Me.fromJson(fixture('me') as Map<String, dynamic>);
    expect(me.id, 'user_owner');
    expect(me.displayName, 'Arjun Mohanesh');
  });

  test('Book parses /v1/books with role, timezone and pay-cycle day', () {
    final items = (fixture('books') as Map<String, dynamic>)['items'] as List;
    final books = [for (final item in items) Book.fromJson(item as Map<String, dynamic>)];
    expect(books.map((b) => b.id), ['book_arjun', 'book_home']);
    expect(books.first.timezone, 'Asia/Kolkata');
    expect(books.first.periodStartDay, 1);
    expect(books.first.role, 'book_owner');
  });

  group('capabilities mirror the server', () {
    Book as(String role) => Book(id: 'b', name: 'n', visibility: 'private', currency: 'INR', timezone: 'Asia/Kolkata', periodStartDay: 1, role: role);

    test('a viewer can only read', () {
      final viewer = as('viewer');
      expect(viewer.can(Capability.read), isTrue);
      for (final other in Capability.values.where((c) => c != Capability.read)) {
        expect(viewer.can(other), isFalse, reason: other.name);
      }
    });

    test('a reviewer can reclassify and split but not edit', () {
      final reviewer = as('reviewer');
      expect(reviewer.can(Capability.reclassify), isTrue);
      expect(reviewer.can(Capability.split), isTrue);
      expect(reviewer.can(Capability.edit), isFalse);
      expect(reviewer.can(Capability.create), isFalse);
    });

    test('an editor edits but does not manage the book', () {
      final editor = as('editor');
      expect(editor.can(Capability.edit), isTrue);
      expect(editor.can(Capability.manageBook), isFalse);
    });

    test('only an owner manages the book', () {
      expect(as('book_owner').can(Capability.manageBook), isTrue);
    });

    test('an unknown role can do nothing', () {
      expect(as('stranger').can(Capability.read), isFalse);
    });
  });
}

// Phase 3: payments, as the real API sends them (test/fixtures/transactions_*.json).
void paymentModels() {
  group('payments', () {
    test('a page carries its cursor, and the last page has none', () {
      final first = TransactionPage.fromJson(fixture('transactions_page1') as Map<String, dynamic>);
      final last = TransactionPage.fromJson(fixture('transactions_page2') as Map<String, dynamic>);
      expect(first.items, hasLength(2));
      expect(first.nextCursor, 'tx_1');
      expect(last.items.first.id, 'tx_2');
    });

    test('money is paise as BigInt, signed by direction', () {
      final page = TransactionPage.fromJson(fixture('transactions_rich') as Map<String, dynamic>);
      final tx1 = page.items.firstWhere((t) => t.id == 'tx_1');
      expect(tx1.amountMinor, BigInt.from(-75000));
      expect(tx1.sources.single.importedAmount, BigInt.from(-75000));
      expect(tx1.splits.map((s) => s.amountMinor), [BigInt.from(-50000), BigInt.from(-25000)]);
      expect(tx1.splits.last.note, 'milk');
      expect(tx1.comments.single.body, 'Checked against the bill');
      expect(page.items.firstWhere((t) => t.id == 'tx_3').amountMinor, BigInt.from(58000000));
    });

    test('a corrected amount keeps the bank figure beside it', () {
      final tx3 = TransactionPage.fromJson(fixture('transactions_rich') as Map<String, dynamic>).items.firstWhere((t) => t.id == 'tx_3');
      expect(tx3.amountMinor, isNot(tx3.sources.single.importedAmount));
    });

    test('a response that leaves out comments and splits keeps the ones already known', () {
      final known = TransactionPage.fromJson(fixture('transactions_rich') as Map<String, dynamic>).items.firstWhere((t) => t.id == 'tx_1');
      // The category route answers without `comments`; the real shape is recorded.
      final response = fixture('transaction_after_category') as Map<String, dynamic>;
      expect(response.containsKey('comments'), isFalse);
      final merged = Transaction.fromJson({...response, 'id': 'tx_1'}, previous: known);
      expect(merged.comments, hasLength(1));
      expect(merged.state, 'confirmed');
    });

    test('without a previous version the missing lists are empty, not an error', () {
      expect(Transaction.fromJson(fixture('transaction_after_category') as Map<String, dynamic>).comments, isEmpty);
    });

    test('a comment is read with its author and time', () {
      final comment = TxComment.fromJson(fixture('comment') as Map<String, dynamic>);
      expect(comment.authorId, 'user_owner');
      expect(comment.createdAt.isUtc, isTrue);
    });

    test('categories and accounts', () {
      final category = Category.fromJson(((fixture('categories') as Map<String, dynamic>)['items'] as List).first as Map<String, dynamic>);
      expect(category.groupName, isNotEmpty);
      final account = Account.fromJson(((fixture('accounts') as Map<String, dynamic>)['items'] as List).first as Map<String, dynamic>);
      expect(account.label, 'Primary bank ····0042');
    });
  });
}
