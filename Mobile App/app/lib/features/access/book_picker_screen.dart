import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/models.dart';
import '../../core/session.dart';

class BookPickerScreen extends ConsumerWidget {
  const BookPickerScreen({super.key, required this.books});
  final List<Book> books;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose a book'),
        actions: [TextButton(onPressed: () => ref.read(sessionProvider.notifier).signOut(), child: const Text('Sign out'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Each book is its own set of finances. You can switch later from Settings.', style: text.bodySmall),
          const SizedBox(height: 12),
          for (final book in books)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  title: Text(book.name, style: text.titleMedium),
                  subtitle: Text('${book.visibility == 'shared' ? 'Shared' : 'Private'} · ${roleLabel(book.role)}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => ref.read(sessionProvider.notifier).chooseBook(book),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
