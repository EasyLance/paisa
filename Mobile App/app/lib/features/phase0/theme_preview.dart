// Phase 0 scaffolding: one screen in both modes so the look can be approved
// before real screens are built on it. All figures are invented and labelled as
// such. Delete when the dashboard (Phase 2) exists.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/theme/theme_mode.dart';
import '../../core/theme/tokens.dart';

class ThemePreview extends ConsumerWidget {
  const ThemePreview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.paisa;
    final text = Theme.of(context).textTheme;
    final mode = ref.watch(themeModeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Preview the look')),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Overview'),
          NavigationDestination(icon: Icon(Icons.swap_horiz), label: 'Activity'),
          NavigationDestination(icon: Icon(Icons.donut_large), label: 'Budgets'),
          NavigationDestination(icon: Icon(Icons.people_outline), label: 'People'),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('System')),
              ButtonSegment(value: ThemeMode.light, label: Text('Light')),
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
            ],
            selected: {mode},
            onSelectionChanged: (value) => ref.read(themeModeProvider.notifier).choose(value.first),
          ),
          const SizedBox(height: 16),
          Text('SAMPLE DATA · NOT YOUR LEDGER', style: text.labelSmall),
          const SizedBox(height: 4),
          Text('October 2026', style: text.headlineMedium),
          Text('26 Sept – 25 Oct', style: text.bodySmall),
          const SizedBox(height: 16),
          _ReviewBanner(count: 3),
          const SizedBox(height: 14),
          IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: _Tile(label: 'INCOME', value: formatMinorString('58786700'))),
            const SizedBox(width: 10),
            Expanded(child: _Tile(label: 'SPENT', value: formatMinorString('28755000'))),
          ])),
          const SizedBox(height: 10),
          IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: _Tile(label: 'SAVING', value: formatMinorString('1000000'))),
            const SizedBox(width: 10),
            Expanded(child: _Tile(label: 'BALANCE', value: formatMinorString('-6914200'), note: 'Income minus spending and saving')),
          ])),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Where your money went', style: text.titleLarge),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    height: 12,
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Expanded(flex: 49, child: ColoredBox(color: c.essentials)),
                      Expanded(flex: 24, child: ColoredBox(color: c.lifestyle)),
                      Expanded(flex: 17, child: ColoredBox(color: c.saving)),
                      Expanded(flex: 10, child: ColoredBox(color: c.other)),
                    ]),
                  ),
                ),
                const SizedBox(height: 14),
                _Legend(color: c.essentials, label: 'Essentials', amount: '19275000'),
                _Legend(color: c.lifestyle, label: 'Lifestyle', amount: '9480000'),
                _Legend(color: c.saving, label: 'Saving', amount: '1000000'),
                _Legend(color: c.other, label: 'Other', amount: '420000'),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Budget', style: text.titleLarge),
                const SizedBox(height: 12),
                const _Budget(label: 'Essentials', used: .72),
                const _Budget(label: 'Lifestyle', used: 1.18),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(children: [
                _Ledger(mark: 'S', name: 'Swiggy', meta: '26 Aug · Food delivery', amount: '-75000', state: 'confirmed'),
                const Divider(),
                _Ledger(mark: 'H', name: 'Hostel EMI', meta: '26 Aug · Needs a category', amount: '-3500000', state: 'pending review'),
                const Divider(),
                _Ledger(mark: 'A', name: 'Acme Technologies', meta: '25 Aug · Salary', amount: '58786700', state: 'reconciled'),
                const Divider(),
                _Ledger(mark: 'N', name: 'Netflix', meta: '15 Aug · Subscriptions', amount: '-64900', state: 'voided', struck: true),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          Row(children: [
            FilledButton(onPressed: () {}, child: const Text('Confirm')),
            const SizedBox(width: 10),
            OutlinedButton(onPressed: () {}, child: const Text('Edit')),
            const SizedBox(width: 10),
            TextButton(onPressed: () {}, child: const Text('Cancel')),
          ]),
          const SizedBox(height: 14),
          const TextField(decoration: InputDecoration(labelText: 'Amount', errorText: 'Enter an amount with at most two decimals')),
        ],
      ),
    );
  }
}

class _ReviewBanner extends StatelessWidget {
  const _ReviewBanner({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Icon(Icons.check_circle_outline, color: scheme.onPrimaryContainer),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$count payments need review', style: text.titleSmall?.copyWith(color: scheme.onPrimaryContainer)),
            Text('Confirm them while you remember them.', style: text.bodySmall?.copyWith(color: scheme.onPrimaryContainer)),
          ]),
        ),
        FilledButton(onPressed: () {}, child: const Text('Review')),
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, this.note});
  final String label;
  final String value;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: text.labelSmall),
          const SizedBox(height: 8),
          Text(value, style: text.headlineSmall),
          if (note != null) ...[const SizedBox(height: 4), Text(note!, style: text.bodySmall)],
        ]),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, required this.amount});
  final Color color;
  final String label;
  final String amount;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 10),
      Expanded(child: Text(label)),
      Text(formatMinorString(amount), style: Theme.of(context).textTheme.labelLarge),
    ]),
  );
}

// Overspending is a bar passing its limit, not a red page (docs/design.md §2).
class _Budget extends StatelessWidget {
  const _Budget({required this.label, required this.used});
  final String label;
  final double used;

  @override
  Widget build(BuildContext context) {
    final c = context.paisa;
    final over = used > 1;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label)),
          Text(over ? '${(used * 100).round()}% of plan, over' : '${(used * 100).round()}% of plan', style: Theme.of(context).textTheme.bodySmall),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: used.clamp(0, 1).toDouble(),
            minHeight: 8,
            backgroundColor: c.line,
            color: over ? c.coral : c.essentials,
          ),
        ),
      ]),
    );
  }
}

class _Ledger extends StatelessWidget {
  const _Ledger({required this.mark, required this.name, required this.meta, required this.amount, required this.state, this.struck = false});
  final String mark;
  final String name;
  final String meta;
  final String amount;
  final String state;
  final bool struck;

  @override
  Widget build(BuildContext context) {
    final c = context.paisa;
    final text = Theme.of(context).textTheme;
    final income = !amount.startsWith('-');
    final strike = struck ? TextDecoration.lineThrough : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        CircleAvatar(radius: 18, backgroundColor: c.line, child: Text(mark, style: text.labelLarge)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: text.titleSmall?.copyWith(decoration: strike)),
            Text(meta, style: text.bodySmall),
            const SizedBox(height: 4),
            _Pill(state),
          ]),
        ),
        Text(
          formatMinorString(amount, plusSign: true),
          style: text.titleSmall?.copyWith(color: income ? c.positive : c.ink, decoration: strike),
        ),
      ]),
    );
  }
}

// Status is a word, never colour alone.
class _Pill extends StatelessWidget {
  const _Pill(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.paisa;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(border: Border.all(color: c.line), borderRadius: BorderRadius.circular(10)),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}
