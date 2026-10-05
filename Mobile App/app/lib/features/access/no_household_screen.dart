import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session.dart';
import '../../core/widgets.dart';
import 'request_access_sheet.dart';

/// Signed in, but the ledger has no household for this account.
class NoHouseholdScreen extends ConsumerWidget {
  const NoHouseholdScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final email = ref.watch(authServiceProvider).currentEmail;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const PaisaMark(),
                const SizedBox(height: 24),
                Text('No household yet', style: text.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  '${email != null ? 'You are signed in as $email, but this' : 'This'} account is not part of a household. '
                  'Ask the person who runs your household to invite you, or request access and the administrator will review it.',
                ),
                const SizedBox(height: 24),
                SizedBox(width: double.infinity, child: FilledButton(onPressed: () => showRequestAccess(context, email: email), child: const Text('Request access'))),
                const SizedBox(height: 8),
                SizedBox(width: double.infinity, child: OutlinedButton(onPressed: () => ref.read(sessionProvider.notifier).reload(), child: const Text('Check again'))),
                const SizedBox(height: 8),
                SizedBox(width: double.infinity, child: TextButton(onPressed: () => ref.read(sessionProvider.notifier).signOut(), child: const Text('Sign out'))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
