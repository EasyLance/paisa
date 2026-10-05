// The four tabs. Overview is the live dashboard; the others are filled in by
// their own phases (3 activity, 5 budgets, 6 people).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/models.dart';
import '../../core/theme/tokens.dart';
import '../dashboard/dashboard_view.dart';
import '../settings/settings_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.me, required this.book});
  final Me me;
  final Book book;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final name = widget.me.displayName ?? widget.me.email ?? '';
    final initials = name.trim().isEmpty ? '?' : name.trim().split(RegExp(r'\s+')).take(2).map((part) => part[0].toUpperCase()).join();
    return Scaffold(
      appBar: AppBar(
        title: Text(book.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: CircleAvatar(radius: 16, backgroundColor: context.paisa.lime, child: Text(initials, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xff1c3b2f)))),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: IndexedStack(index: _tab, children: [
        DashboardView(book: book, onReview: () => setState(() => _tab = 1)),
        const _Soon(icon: Icons.swap_horiz, title: 'Activity', copy: 'Browse, review and import payments. This is where the Review button leads; it arrives in the next phase.'),
        const _Soon(icon: Icons.donut_large, title: 'Budgets', copy: 'Plan a share of income per group, and manage recurring payments.'),
        const _Soon(icon: Icons.people_outline, title: 'People', copy: 'See who has access to this book and invite others.'),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Overview'),
          NavigationDestination(icon: Icon(Icons.swap_horiz), label: 'Activity'),
          NavigationDestination(icon: Icon(Icons.donut_large), label: 'Budgets'),
          NavigationDestination(icon: Icon(Icons.people_outline), label: 'People'),
        ],
      ),
    );
  }
}

class _Soon extends StatelessWidget {
  const _Soon({required this.icon, required this.title, required this.copy});
  final IconData icon;
  final String title;
  final String copy;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 44, color: context.paisa.muted),
        const SizedBox(height: 12),
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(copy, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
      ]),
    ),
  );
}
