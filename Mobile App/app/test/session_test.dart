import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_mobile/core/session.dart';

import 'support/fakes.dart';

// Riverpod 3 pauses a provider nothing is listening to, so a bare read would
// never complete. In the app a screen is always listening.
Future<SessionState> settled(ProviderContainer container) {
  container.listen(sessionProvider, (_, _) {});
  return container.read(sessionProvider.future);
}

void main() {
  test('signed out when there is no sign-in', () async {
    final h = Harness();
    final c = await h.container();
    addTearDown(c.dispose);
    expect(await settled(c), isA<SignedOut>());
    expect(h.server.requests, isEmpty, reason: 'nothing is asked of the API without a sign-in');
  });

  test('one book is chosen for you', () async {
    final h = Harness(auth: FakeAuth(signedIn: true));
    final c = await h.container();
    addTearDown(c.dispose);
    h.server.roles = ['reviewer'];
    final state = await settled(c) as Ready;
    expect(state.books, hasLength(1));
    expect(state.book?.id, 'book_arjun');
    expect(state.book?.role, 'reviewer');
    expect(c.read(bookProvider)?.id, 'book_arjun');
  });

  test('several books and no memory means the picker', () async {
    final h = Harness(auth: FakeAuth(signedIn: true));
    final c = await h.container();
    addTearDown(c.dispose);
    final state = await settled(c) as Ready;
    expect(state.books, hasLength(2));
    expect(state.book, isNull);
    expect(c.read(bookProvider), isNull);
  });

  test('a remembered book is used when it is still yours', () async {
    final h = Harness(auth: FakeAuth(signedIn: true), prefs: {'paisa.book': 'book_home'});
    final c = await h.container();
    addTearDown(c.dispose);
    expect((await settled(c) as Ready).book?.id, 'book_home');
  });

  test('a remembered book you no longer belong to is ignored', () async {
    final h = Harness(auth: FakeAuth(signedIn: true), prefs: {'paisa.book': 'book_gone'});
    final c = await h.container();
    addTearDown(c.dispose);
    expect((await settled(c) as Ready).book, isNull);
  });

  test('choosing a book remembers it, and Switch forgets it', () async {
    final h = Harness(auth: FakeAuth(signedIn: true));
    final c = await h.container();
    addTearDown(c.dispose);
    final ready = await settled(c) as Ready;
    await c.read(sessionProvider.notifier).chooseBook(ready.books.last);
    expect(c.read(bookProvider)?.id, 'book_home');
    expect(h.prefs.getString('paisa.book'), 'book_home');

    await c.read(sessionProvider.notifier).changeBook();
    expect(c.read(bookProvider), isNull);
    expect(h.prefs.getString('paisa.book'), isNull);
  });

  test('an account with no household is told so, not shown an error', () async {
    final h = Harness(auth: FakeAuth(signedIn: true), server: FakeServer()..meStatus = 403..meError = {'code': 'INVITE_REQUIRED', 'message': 'This account is not active in a workspace'});
    final c = await h.container();
    addTearDown(c.dispose);
    expect(await settled(c), isA<NoHousehold>());
  });

  test('a token that stays invalid signs the person out', () async {
    final auth = FakeAuth(signedIn: true);
    final h = Harness(auth: auth, server: FakeServer()..meStatus = 401);
    final c = await h.container();
    addTearDown(c.dispose);
    await settled(c);
    expect(auth.calls, contains('signOut'));
    await c.pump();
    expect(await settled(c), isA<SignedOut>());
  });

  test('a server error is an error, so the screen can say nothing is shown', () async {
    final h = Harness(auth: FakeAuth(signedIn: true), server: FakeServer()..booksStatus = 500);
    final c = await h.container();
    addTearDown(c.dispose);
    await expectLater(settled(c), throwsA(anything));
    expect(c.read(sessionProvider).hasError, isTrue);
  });

  test('signing out forgets the chosen book', () async {
    final auth = FakeAuth(signedIn: true);
    final h = Harness(auth: auth, prefs: {'paisa.book': 'book_home'});
    final c = await h.container();
    addTearDown(c.dispose);
    await settled(c);
    await c.read(sessionProvider.notifier).signOut();
    expect(h.prefs.getString('paisa.book'), isNull);
    expect(auth.isSignedIn, isFalse);
  });

  test('signing in moves the session on by itself', () async {
    final auth = FakeAuth();
    final h = Harness(auth: auth);
    final c = await h.container();
    addTearDown(c.dispose);
    expect(await settled(c), isA<SignedOut>());
    await auth.signIn('a@b.co', 'x');
    await Future<void>.delayed(Duration.zero);
    expect(await settled(c), isA<Ready>());
  });
}
