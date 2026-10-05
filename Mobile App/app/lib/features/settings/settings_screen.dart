import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/models.dart';
import '../../core/session.dart';
import '../../core/theme/theme_mode.dart';
import '../../core/theme/tokens.dart';
import '../lock/lock_controller.dart';
import '../phase0/theme_preview.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String? _lockNote;

  Future<void> _toggleLock(bool on) async {
    final lock = ref.read(lockProvider.notifier);
    setState(() => _lockNote = null);
    if (on) {
      final ok = await lock.enable();
      if (!ok && mounted) {
        setState(() => _lockNote = 'The lock was not turned on. Set a screen lock or fingerprint in your phone\'s settings first, then try again.');
      }
    } else {
      await lock.disable();
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final session = ref.watch(sessionProvider).value;
    final ready = session is Ready ? session : null;
    final mode = ref.watch(themeModeProvider);
    final lock = ref.watch(lockProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (ready != null) ...[
            Text('ACCOUNT', style: text.labelSmall),
            const SizedBox(height: 6),
            Card(
              child: Column(children: [
                ListTile(title: Text(ready.me.displayName ?? 'Signed in'), subtitle: Text(ready.me.email ?? '')),
                if (ready.book != null) ...[
                  const Divider(),
                  ListTile(
                    title: Text(ready.book!.name),
                    subtitle: Text('${roleLabel(ready.book!.role)} · ${ready.book!.visibility == 'shared' ? 'Shared' : 'Private'} book'),
                    trailing: ready.books.length > 1
                        ? TextButton(
                            onPressed: () {
                              ref.read(sessionProvider.notifier).changeBook();
                              Navigator.of(context).pop();
                            },
                            child: const Text('Switch'),
                          )
                        : null,
                  ),
                ],
              ]),
            ),
            if (ready.book != null) ...[const SizedBox(height: 10), _Abilities(book: ready.book!)],
            const SizedBox(height: 20),
          ],
          Text('APPEARANCE', style: text.labelSmall),
          const SizedBox(height: 6),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('System')),
              ButtonSegment(value: ThemeMode.light, label: Text('Light')),
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
            ],
            selected: {mode},
            onSelectionChanged: (value) => ref.read(themeModeProvider.notifier).choose(value.first),
          ),
          const SizedBox(height: 20),
          Text('SECURITY', style: text.labelSmall),
          const SizedBox(height: 6),
          Card(
            child: Column(children: [
              SwitchListTile(
                title: const Text('Lock Paisa'),
                subtitle: const Text('Ask for your fingerprint, face or screen lock to open the app.'),
                value: lock.enabled,
                onChanged: _toggleLock,
              ),
              if (lock.enabled) ...[
                const Divider(),
                ListTile(
                  title: const Text('Ask again after'),
                  trailing: DropdownButton<int>(
                    value: lock.graceMinutes,
                    underline: const SizedBox.shrink(),
                    items: [for (final minutes in graceChoices) DropdownMenuItem(value: minutes, child: Text(minutes == 0 ? 'Every time' : '$minutes min away'))],
                    onChanged: (value) => value == null ? null : ref.read(lockProvider.notifier).setGrace(value),
                  ),
                ),
              ],
            ]),
          ),
          if (_lockNote != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_lockNote!, style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 20),
          if (kDebugMode) ...[
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ThemePreview())),
              child: const Text('Preview the look (debug)'),
            ),
            const SizedBox(height: 12),
          ],
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: context.paisa.ink),
            onPressed: () async {
              Navigator.of(context).pop();
              await ref.read(sessionProvider.notifier).signOut();
            },
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

/// What this role may do in this book. The server checks every request again;
/// this only explains why a button is missing.
class _Abilities extends StatelessWidget {
  const _Abilities({required this.book});
  final Book book;

  static const _abilities = [
    (Capability.read, 'See the ledger'),
    (Capability.comment, 'Comment on payments'),
    (Capability.reclassify, 'Confirm and categorise payments'),
    (Capability.split, 'Split a payment'),
    (Capability.edit, 'Edit amounts, dates and merchants'),
    (Capability.create, 'Add payments and import statements'),
    (Capability.manageBook, 'Manage people, budgets and accounts'),
  ];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: const Text('What you can do in this book'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          for (final (capability, label) in _abilities)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Icon(book.can(capability) ? Icons.check_circle : Icons.remove_circle_outline, size: 20, color: book.can(capability) ? context.paisa.positive : context.paisa.muted),
                const SizedBox(width: 10),
                Expanded(child: Text(label)),
                // Colour alone never says it.
                Text(book.can(capability) ? 'Yes' : 'No', style: text.labelMedium),
              ]),
            ),
        ],
      ),
    );
  }
}
