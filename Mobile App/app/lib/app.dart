import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/session.dart';
import 'core/theme/theme.dart';
import 'core/theme/theme_mode.dart';
import 'core/widgets.dart';
import 'features/access/book_picker_screen.dart';
import 'features/access/no_household_screen.dart';
import 'features/access/sign_in_screen.dart';
import 'features/home/home_shell.dart';
import 'features/lock/lock_gate.dart';

class PaisaApp extends ConsumerWidget {
  const PaisaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Paisa',
    theme: buildTheme(Brightness.light),
    darkTheme: buildTheme(Brightness.dark),
    themeMode: ref.watch(themeModeProvider),
    // Above the navigator, so the lock covers dialogs and pushed screens too.
    builder: (context, child) => LockGate(child: child!),
    home: const SessionGate(),
  );
}

/// Chooses the screen from where the person is in the way in. Nothing past
/// this point renders without a signed-in session and a chosen book.
class SessionGate extends ConsumerWidget {
  const SessionGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return session.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        body: SafeArea(
          child: ErrorPanel(
            error: error,
            what: 'your books',
            onRetry: () => ref.read(sessionProvider.notifier).reload(),
            extra: [TextButton(onPressed: () => ref.read(authServiceProvider).signOut(), child: const Text('Sign out'))],
          ),
        ),
      ),
      data: (state) => switch (state) {
        SignedOut() => const SignInScreen(),
        NoHousehold() => const NoHouseholdScreen(),
        Ready(book: null, :final books) => BookPickerScreen(books: books),
        Ready(:final me, :final book?) => HomeShell(key: ValueKey(book.id), me: me, book: book),
      },
    );
  }
}
