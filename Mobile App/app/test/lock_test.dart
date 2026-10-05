import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisa_mobile/features/lock/lock_controller.dart';

import 'support/fakes.dart';

Future<ProviderContainer> lockContainer(Harness h) async {
  final c = await h.container();
  addTearDown(c.dispose);
  c.listen(lockProvider, (_, _) {});
  return c;
}

void main() {
  group('LockController', () {
    test('a cold start is open when the lock is off', () async {
      final c = await lockContainer(Harness());
      expect(c.read(lockProvider).enabled, isFalse);
      expect(c.read(lockProvider).locked, isFalse);
    });

    test('a cold start is locked when the lock is on', () async {
      final c = await lockContainer(Harness(prefs: {'paisa.lock.enabled': true}));
      expect(c.read(lockProvider).locked, isTrue);
    });

    test('turning it on needs a phone that can prompt, and a successful prompt', () async {
      final h = Harness();
      final c = await lockContainer(h);

      h.authenticator.available = false;
      expect(await c.read(lockProvider.notifier).enable(), isFalse);
      expect(c.read(lockProvider).enabled, isFalse);
      expect(h.authenticator.reasons, isEmpty, reason: 'no prompt on a phone with no screen lock');

      h.authenticator.available = true;
      h.authenticator.succeeds = false;
      expect(await c.read(lockProvider.notifier).enable(), isFalse);
      expect(c.read(lockProvider).enabled, isFalse);

      h.authenticator.succeeds = true;
      expect(await c.read(lockProvider.notifier).enable(), isTrue);
      expect(c.read(lockProvider).enabled, isTrue);
      expect(c.read(lockProvider).locked, isFalse, reason: 'you just proved who you are');
      expect(h.prefs.getBool('paisa.lock.enabled'), isTrue);
    });

    test('turning it off asks again', () async {
      final h = Harness(prefs: {'paisa.lock.enabled': true});
      final c = await lockContainer(h);
      h.authenticator.succeeds = false;
      expect(await c.read(lockProvider.notifier).disable(), isFalse);
      expect(c.read(lockProvider).enabled, isTrue);
      h.authenticator.succeeds = true;
      expect(await c.read(lockProvider.notifier).disable(), isTrue);
      expect(h.prefs.getBool('paisa.lock.enabled'), isFalse);
    });

    test('coming back within the grace period leaves it open', () async {
      final h = Harness();
      final c = await lockContainer(h);
      await c.read(lockProvider.notifier).enable();
      c.read(lockProvider.notifier).resumedAfter(const Duration(seconds: 30));
      expect(c.read(lockProvider).locked, isFalse);
    });

    test('coming back after the grace period locks it', () async {
      final h = Harness();
      final c = await lockContainer(h);
      await c.read(lockProvider.notifier).enable();
      c.read(lockProvider.notifier).resumedAfter(const Duration(minutes: 1));
      expect(c.read(lockProvider).locked, isTrue);
    });

    test('"every time" locks on any return', () async {
      final h = Harness();
      final c = await lockContainer(h);
      await c.read(lockProvider.notifier).enable();
      await c.read(lockProvider.notifier).setGrace(0);
      c.read(lockProvider.notifier).resumedAfter(Duration.zero);
      expect(c.read(lockProvider).locked, isTrue);
      expect(h.prefs.getInt('paisa.lock.grace'), 0);
    });

    test('with the lock off nothing ever locks', () async {
      final c = await lockContainer(Harness());
      c.read(lockProvider.notifier).resumedAfter(const Duration(hours: 5));
      expect(c.read(lockProvider).locked, isFalse);
    });

    test('unlocking needs a successful prompt', () async {
      final h = Harness(prefs: {'paisa.lock.enabled': true});
      final c = await lockContainer(h);
      h.authenticator.succeeds = false;
      await c.read(lockProvider.notifier).unlock();
      expect(c.read(lockProvider).locked, isTrue);
      h.authenticator.succeeds = true;
      await c.read(lockProvider.notifier).unlock();
      expect(c.read(lockProvider).locked, isFalse);
    });

    test('the prompt backgrounding the app does not lock it again', () async {
      final h = Harness(prefs: {'paisa.lock.enabled': true, 'paisa.lock.grace': 0});
      final c = await lockContainer(h);
      h.authenticator.duringPrompt = () => c.read(lockProvider.notifier).resumedAfter(const Duration(minutes: 10));
      await c.read(lockProvider.notifier).unlock();
      expect(c.read(lockProvider).locked, isFalse);
    });
  });

  group('the lock screen', () {
    testWidgets('covers a signed-in app and asks straight away', (tester) async {
      final h = Harness(auth: FakeAuth(signedIn: true), prefs: {'paisa.lock.enabled': true});
      h.authenticator.succeeds = false;
      h.server.roles = ['book_owner'];
      await tester.pumpWidget(await h.app());
      await tester.pumpAndSettle();
      expect(find.text('Paisa is locked'), findsOneWidget);
      expect(h.authenticator.reasons, ['Unlock Paisa']);

      h.authenticator.succeeds = true;
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(find.text('Paisa is locked'), findsNothing);
      expect(find.byTooltip('Settings'), findsOneWidget);
    });

    testWidgets('does not appear before sign-in, when there is nothing to protect', (tester) async {
      final h = Harness(prefs: {'paisa.lock.enabled': true});
      await tester.pumpWidget(await h.app());
      await tester.pumpAndSettle();
      expect(find.text('Paisa is locked'), findsNothing);
      expect(find.text('Your finances, clearly shared.'), findsOneWidget);
    });

    testWidgets('signing in does not immediately ask again', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final h = Harness(prefs: {'paisa.lock.enabled': true});
      h.server.roles = ['book_owner'];
      await tester.pumpWidget(await h.app());
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'a@b.co');
      await tester.enterText(find.byType(TextFormField).at(1), 'secret-pass');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Paisa is locked'), findsNothing);
      expect(h.authenticator.reasons, isEmpty);
    });

    testWidgets('"Sign out instead" is a way out when the sensor fails', (tester) async {
      final auth = FakeAuth(signedIn: true);
      final h = Harness(auth: auth, prefs: {'paisa.lock.enabled': true});
      h.authenticator.succeeds = false;
      await tester.pumpWidget(await h.app());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out instead'));
      await tester.pumpAndSettle();
      expect(auth.calls, contains('signOut'));
      expect(find.text('Your finances, clearly shared.'), findsOneWidget);
    });
  });
}
