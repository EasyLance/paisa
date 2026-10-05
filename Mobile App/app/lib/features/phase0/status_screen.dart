// Phase 0 scaffolding: proves the app boots and can reach the API. Replaced by
// the real sign-in flow in Phase 1; delete this folder then.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import 'theme_preview.dart';

class StatusScreen extends ConsumerWidget {
  const StatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final books = ref.watch(booksProvider);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Paisa')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Phase 0 check', style: text.headlineMedium),
          const SizedBox(height: 4),
          Text('Confirms the app can reach the API. Real sign-in arrives in Phase 1.', style: text.bodySmall),
          const SizedBox(height: 16),
          _Row(label: 'API', value: AppConfig.apiUrl),
          _Row(label: 'Sign-in', value: AppConfig.devAuth ? 'Development user (${AppConfig.devUserId})' : 'None yet'),
          _Row(
            label: 'Signed in as',
            value: me.when(
              data: (value) => value.displayName ?? value.email ?? value.id,
              loading: () => 'Checking…',
              error: (error, _) => _describe(error),
            ),
          ),
          _Row(
            label: 'Books',
            value: books.when(
              data: (value) => value.map((book) => '${book.name} (${book.role})').join('\n'),
              loading: () => 'Checking…',
              error: (error, _) => _describe(error),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton(
                onPressed: () {
                  ref.invalidate(meProvider);
                  ref.invalidate(booksProvider);
                },
                child: const Text('Check again'),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ThemePreview())),
                child: const Text('Preview the look'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _describe(Object error) {
    if (error is ApiError) {
      if (error.isNetwork) return 'Cannot reach the server';
      if (error.isUnauthenticated) return 'Not signed in';
      return '${error.status} ${error.code}';
    }
    return 'Something went wrong';
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 108, child: Text(label, style: Theme.of(context).textTheme.labelMedium)),
        Expanded(child: Text(value, style: TextStyle(color: context.paisa.ink))),
      ],
    ),
  );
}
