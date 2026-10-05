import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_mobile/core/api/models.dart';

// These fixtures were recorded from a local API (apps/api, memory store, sample
// data). If one changes, the API moved: update the model on purpose.
dynamic fixture(String name) => jsonDecode(File('test/fixtures/$name.json').readAsStringSync());

void main() {
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
