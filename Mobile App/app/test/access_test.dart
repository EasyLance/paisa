import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_mobile/core/auth/auth_service.dart';

import 'support/fakes.dart';

Future<void> pumpApp(WidgetTester tester, Harness h) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(await h.app());
  await tester.pumpAndSettle();
}

Future<void> fillSignIn(WidgetTester tester, {String email = 'a@b.co', String password = 'secret-pass'}) async {
  await tester.enterText(find.byType(TextFormField).at(0), email);
  await tester.enterText(find.byType(TextFormField).at(1), password);
}

Future<void> openAbilities(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Settings'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('What you can do in this book'));
  await tester.pumpAndSettle();
}

Future<void> openRequestAccess(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, 'Request access'));
  await tester.pumpAndSettle();
}

// The sign-in form is still on screen behind the sheet and has an Email field
// too, so look inside the sheet only.
Finder inSheet(Finder finder) => find.descendant(of: find.byType(BottomSheet), matching: finder);

Future<void> sendRequest(WidgetTester tester) async {
  await tester.enterText(inSheet(find.widgetWithText(TextFormField, 'Name')), '  Asha Rao ');
  await tester.enterText(inSheet(find.widgetWithText(TextFormField, 'Email')), ' Asha@Example.com ');
  await tester.tap(inSheet(find.widgetWithText(FilledButton, 'Send request')));
  await tester.pumpAndSettle();
}

void main() {
  group('sign in', () {
    testWidgets('asks for both fields before it calls anything', (tester) async {
      final h = Harness();
      await pumpApp(tester, h);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(find.text('Enter your password'), findsOneWidget);
      expect(h.auth.calls, isEmpty);
    });

    testWidgets('shows the reason a sign-in failed, in the web\'s words', (tester) async {
      final h = Harness();
      h.auth.failSignIn = authFailureFromCode('invalid-credential');
      await pumpApp(tester, h);
      await fillSignIn(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('That email and password combination is not recognised.'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget, reason: 'still on the form');
    });

    testWidgets('a person with two books chooses one, then lands on it', (tester) async {
      final h = Harness();
      await pumpApp(tester, h);
      await fillSignIn(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a book'), findsOneWidget);
      expect(find.text("Arjun's finances"), findsOneWidget);
      expect(find.text('Household'), findsOneWidget);

      await tester.tap(find.text('Household'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Settings'), findsOneWidget);
      expect(h.prefs.getString('paisa.book'), 'book_home');
    });

    testWidgets('forgot password needs an address first', (tester) async {
      final h = Harness();
      await pumpApp(tester, h);
      await tester.tap(find.text('Forgot your password?'));
      await tester.pumpAndSettle();
      expect(find.text('Enter your email address first, then choose reset.'), findsOneWidget);
      expect(h.auth.calls, isEmpty);
    });

    testWidgets('forgot password does not claim the account exists', (tester) async {
      final h = Harness();
      await pumpApp(tester, h);
      await tester.enterText(find.byType(TextFormField).at(0), 'who@example.com');
      await tester.tap(find.text('Forgot your password?'));
      await tester.pumpAndSettle();
      expect(h.auth.calls, ['reset:who@example.com']);
      expect(find.text('If who@example.com has an account, a reset link is on its way.'), findsOneWidget);
    });
  });

  group('request access', () {
    testWidgets('sends a trimmed name and a lower-cased email, with no sign-in', (tester) async {
      final h = Harness();
      await pumpApp(tester, h);
      await openRequestAccess(tester);
      await sendRequest(tester);
      expect(h.server.lastBody, {'name': 'Asha Rao', 'email': 'asha@example.com'});
      expect(find.text('Request sent'), findsOneWidget);
    });

    for (final (status, code, heading) in [
      ('pending', 200, 'Already on the list'),
      ('granted', 200, 'You already have access'),
    ]) {
      testWidgets('says $status as the server does', (tester) async {
        final h = Harness();
        h.server.accessRequestReply = {'status': status};
        h.server.accessRequestStatus = code;
        await pumpApp(tester, h);
        await openRequestAccess(tester);
        await sendRequest(tester);
        expect(find.text(heading), findsOneWidget);
      });
    }

    testWidgets('checks the form before sending', (tester) async {
      final h = Harness();
      await pumpApp(tester, h);
      await openRequestAccess(tester);
      await tester.tap(inSheet(find.widgetWithText(FilledButton, 'Send request')));
      await tester.pumpAndSettle();
      expect(find.text('Enter your name'), findsOneWidget);
      expect(find.text('Enter a valid email address'), findsWidgets);
      expect(h.server.requests.where((r) => r.contains('access-requests')), isEmpty);
    });

    testWidgets('a rate limit is explained', (tester) async {
      final h = Harness();
      h.server.accessRequestStatus = 429;
      h.server.accessRequestReply = {'code': 'RATE_LIMITED', 'message': 'Rate limit exceeded'};
      await pumpApp(tester, h);
      await openRequestAccess(tester);
      await sendRequest(tester);
      expect(find.text('Too many requests from here. Try again in a few minutes.'), findsOneWidget);
    });

    testWidgets('no connection is explained', (tester) async {
      final h = Harness();
      h.server.offline = true;
      await pumpApp(tester, h);
      await openRequestAccess(tester);
      await sendRequest(tester);
      expect(find.text('Cannot reach Paisa. Check your connection and try again.'), findsOneWidget);
    });
  });

  group('after sign-in', () {
    testWidgets('an account with no household is told what to do', (tester) async {
      final h = Harness(auth: FakeAuth(signedIn: true, email: 'new@example.com'), server: FakeServer()..meStatus = 403..meError = {'code': 'INVITE_REQUIRED', 'message': 'x'});
      await pumpApp(tester, h);
      expect(find.text('No household yet'), findsOneWidget);
      expect(find.textContaining('new@example.com'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Request access'));
      await tester.pumpAndSettle();
      expect(inSheet(find.widgetWithText(TextFormField, 'new@example.com')), findsOneWidget, reason: 'prefilled');
    });

    testWidgets('a viewer is shown that they cannot edit', (tester) async {
      final h = Harness(auth: FakeAuth(signedIn: true));
      h.server.roles = ['viewer'];
      await pumpApp(tester, h);
      await openAbilities(tester);
      expect(find.textContaining('Viewer'), findsWidgets);
      expect(find.text('Yes'), findsOneWidget);
      expect(find.text('No'), findsNWidgets(6));
    });

    testWidgets('a reviewer can confirm and split but not edit', (tester) async {
      final h = Harness(auth: FakeAuth(signedIn: true));
      h.server.roles = ['reviewer'];
      await pumpApp(tester, h);
      await openAbilities(tester);
      expect(find.text('Yes'), findsNWidgets(4));
      expect(find.text('No'), findsNWidgets(3));
    });

    testWidgets('an owner can do everything', (tester) async {
      final h = Harness(auth: FakeAuth(signedIn: true));
      h.server.roles = ['book_owner'];
      await pumpApp(tester, h);
      await openAbilities(tester);
      expect(find.text('Yes'), findsNWidgets(7));
      expect(find.text('No'), findsNothing);
    });

    testWidgets('no connection shows nothing, not stale numbers', (tester) async {
      final h = Harness(auth: FakeAuth(signedIn: true));
      h.server.offline = true;
      await pumpApp(tester, h);
      expect(find.text('Cannot reach Paisa'), findsOneWidget);
      expect(find.textContaining('Hello'), findsNothing);

      h.server.offline = false;
      h.server.roles = ['book_owner'];
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Cannot reach Paisa'), findsNothing);
      expect(find.byTooltip('Settings'), findsOneWidget);
    });

    testWidgets('a server error says so without detail', (tester) async {
      final h = Harness(auth: FakeAuth(signedIn: true), server: FakeServer()..booksStatus = 500);
      await pumpApp(tester, h);
      expect(find.text('Something went wrong'), findsOneWidget);
    });

    testWidgets('settings: sign out returns to the form', (tester) async {
      final auth = FakeAuth(signedIn: true);
      final h = Harness(auth: auth);
      h.server.roles = ['book_owner'];
      await pumpApp(tester, h);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(auth.calls, contains('signOut'));
      expect(find.text('Your finances, clearly shared.'), findsOneWidget);
    });

    testWidgets('settings: the lock cannot be turned on without a screen lock', (tester) async {
      final h = Harness(auth: FakeAuth(signedIn: true));
      h.server.roles = ['book_owner'];
      h.authenticator.available = false;
      await pumpApp(tester, h);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.textContaining('Set a screen lock or fingerprint'), findsOneWidget);
      expect(h.prefs.getBool('paisa.lock.enabled'), isNull);
    });

    testWidgets('settings: the theme choice is remembered', (tester) async {
      final h = Harness(auth: FakeAuth(signedIn: true));
      h.server.roles = ['book_owner'];
      await pumpApp(tester, h);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(h.prefs.getString('paisa.theme'), 'dark');
    });
  });
}
