import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/models.dart';
import '../../core/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/time.dart';
import '../../core/widgets.dart';
import 'dashboard_logic.dart';
import 'dashboard_providers.dart';

class DashboardView extends ConsumerWidget {
  const DashboardView({super.key, required this.book, required this.onReview});
  final Book book;

  /// Takes the person to the payments waiting for review.
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periodKey = periodKeyOf(book);
    final month = ref.watch(selectedMonthProvider(periodKey));
    final key = (bookId: book.id, month: month);
    final summary = ref.watch(summaryProvider(key));
    final clock = BookClock(book.timezone);

    Future<void> refresh() async {
      ref.invalidate(summaryProvider(key));
      ref.invalidate(budgetPlanProvider(book.id));
      try {
        await ref.read(summaryProvider(key).future);
      } catch (_) {
        // The error state below says what happened; a pull has nothing to add.
      }
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        // Always scrollable, so a short or empty screen can still be pulled down.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _MonthBar(periodKey: periodKey, month: month, window: periodWindow(summary.value?.period, clock)),
          const SizedBox(height: 12),
          ...summary.when(
            loading: () => const [Padding(padding: EdgeInsets.symmetric(vertical: 80), child: Center(child: CircularProgressIndicator()))],
            error: (error, _) => [
              SizedBox(
                height: 420,
                child: ErrorPanel(error: error, what: 'this month', onRetry: () => ref.invalidate(summaryProvider(key))),
              ),
            ],
            data: (data) => _Loaded.build(context, ref, book: book, summary: data, onReview: onReview),
          ),
        ],
      ),
    );
  }
}

class _MonthBar extends ConsumerWidget {
  const _MonthBar({required this.periodKey, required this.month, required this.window});
  final PeriodKey periodKey;
  final String month;
  final String window;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final controller = ref.read(selectedMonthProvider(periodKey).notifier);
    final canGoForward = month.compareTo(ref.watch(currentMonthProvider(periodKey))) < 0;
    return Row(children: [
      IconButton(tooltip: 'Previous month', icon: const Icon(Icons.chevron_left), onPressed: controller.previous),
      Expanded(
        child: Semantics(
          liveRegion: true,
          child: Column(children: [
            Text(monthLabel(month), style: text.headlineSmall),
            if (window.isNotEmpty) Text(window, style: text.bodySmall),
          ]),
        ),
      ),
      IconButton(tooltip: 'Next month', icon: const Icon(Icons.chevron_right), onPressed: canGoForward ? controller.next : null),
    ]);
  }
}

/// The body once a month has loaded. A class of statics rather than a widget so
/// it can return several list children at once.
class _Loaded {
  static List<Widget> build(BuildContext context, WidgetRef ref, {required Book book, required Summary summary, required VoidCallback onReview}) {
    final canReview = book.can(Capability.reclassify);
    return [
      _ReviewCard(pending: summary.pendingReview, canReview: canReview, onReview: onReview),
      const SizedBox(height: 14),
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: _Tile(label: 'INCOME', value: formatMoney(summary.incomeMinor), detail: 'Received this period')),
          const SizedBox(width: 10),
          Expanded(child: _Tile(label: 'SPENT', value: formatMoney(summary.spentMinor), detail: spentDetail(summary))),
        ]),
      ),
      const SizedBox(height: 10),
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: _Tile(label: 'SAVING', value: formatMoney(summary.movedMinor), detail: 'Moved to your own accounts')),
          const SizedBox(width: 10),
          Expanded(child: _Tile(label: 'BALANCE', value: formatMoney(summary.balanceMinor), detail: balanceDetail(summary))),
        ]),
      ),
      const SizedBox(height: 14),
      _Breakdown(summary: summary),
      const SizedBox(height: 14),
      _Budget(bookId: book.id, summary: summary),
    ];
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.pending, required this.canReview, required this.onReview});
  final int pending;
  final bool canReview;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final caughtUp = pending == 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Icon(caughtUp ? Icons.check_circle : Icons.pending_actions, color: scheme.onPrimaryContainer),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(reviewHeadline(pending), style: text.titleSmall?.copyWith(color: scheme.onPrimaryContainer)),
            Text(reviewDetail(pending), style: text.bodySmall?.copyWith(color: scheme.onPrimaryContainer)),
          ]),
        ),
        // A viewer cannot act on a payment, so the way in is not offered.
        if (!caughtUp && canReview) ...[const SizedBox(width: 8), FilledButton(onPressed: onReview, child: const Text('Review'))],
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, required this.detail});
  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: text.labelSmall),
          const SizedBox(height: 8),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: text.headlineSmall)),
          const SizedBox(height: 4),
          Text(detail, style: text.bodySmall),
        ]),
      ),
    );
  }
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.summary});
  final Summary summary;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.paisa;
    final groups = groupSpend(summary.byCategory);
    final total = leftTheAccount(summary);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Where your money went', style: text.titleLarge),
          const SizedBox(height: 14),
          if (groups.isEmpty)
            Text('No spending recorded this period yet.', style: text.bodySmall)
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 12,
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  // Proportions in tenths of a percent, never less than 1 so a
                  // small group does not vanish from the bar.
                  for (final group in groups)
                    Expanded(flex: (group.total * BigInt.from(1000) ~/ total).toInt().clamp(1, 1000), child: ColoredBox(color: c.group(group.name))),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            if (summary.incomeMinor > BigInt.zero) Text('${percentOf(summary.spentMinor, summary.incomeMinor).toStringAsFixed(1)}% of income spent', style: text.bodySmall),
            const SizedBox(height: 6),
            for (final group in groups) _GroupRow(group: group),
            if (summary.movedMinor > BigInt.zero) ...[
              const SizedBox(height: 8),
              Text(
                '${formatMoney(total)} left the account: ${formatMoney(summary.spentMinor)} spent and ${formatMoney(summary.movedMinor)} saved to your own accounts.',
                style: text.bodySmall,
              ),
            ],
          ],
        ]),
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.group});
  final SpendGroup group;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.paisa;
    return Theme(
      // The tile draws its own divider lines; the card already has a border.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        visualDensity: VisualDensity.compact,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: 22, bottom: 6),
        title: Row(children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c.group(group.name), shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(child: Text(group.name)),
          const SizedBox(width: 8),
          Text(formatMoney(group.total), style: text.labelLarge),
        ]),
        children: [
          for (final item in group.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(child: Text(item.name, style: text.bodySmall)),
                Text(formatMoney(item.amountMinor), style: text.bodySmall),
              ]),
            ),
        ],
      ),
    );
  }
}

class _Budget extends ConsumerWidget {
  const _Budget({required this.bookId, required this.summary});
  final String bookId;
  final Summary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final plan = ref.watch(budgetPlanProvider(bookId));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Budget', style: text.titleLarge),
          const SizedBox(height: 12),
          plan.when(
            loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: CircularProgressIndicator())),
            // The figures above are still true, so a budget that will not load
            // says so here and does not blank the whole screen.
            error: (error, _) => Row(children: [
              const Expanded(child: Text('The budget could not be loaded.')),
              TextButton(onPressed: () => ref.invalidate(budgetPlanProvider(bookId)), child: const Text('Try again')),
            ]),
            data: (data) => _BudgetBody(plan: data, summary: summary),
          ),
        ]),
      ),
    );
  }
}

class _BudgetBody extends StatelessWidget {
  const _BudgetBody({required this.plan, required this.summary});
  final BudgetPlan plan;
  final Summary summary;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final rows = budgetRows(plan, summary);
    if (rows.isEmpty) {
      return Text('No budget plan yet. Share your income across the groups to see how each is doing.', style: text.bodySmall);
    }
    final base = budgetBase(plan, summary);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        base.base == BigInt.zero
            ? 'No income to budget against yet. Add a recurring income plan.'
            : 'Shares of ${formatMoney(base.base)} ${base.planned ? 'expected income' : 'received this period'}.',
        style: text.bodySmall,
      ),
      const SizedBox(height: 10),
      for (final row in rows) _BudgetRowView(row: row),
    ]);
  }
}

// Overspending is a bar passing its limit, not a red page (docs/design.md §2).
class _BudgetRowView extends StatelessWidget {
  const _BudgetRowView({required this.row});
  final BudgetRow row;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.paisa;
    final fill = row.allocated == BigInt.zero ? (row.spent > BigInt.zero ? 1.0 : 0.0) : (row.usedPercent / 100).clamp(0.0, 1.0);
    final status = row.over ? 'over' : row.warning ? 'close' : 'on track';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Semantics(
        label: '${row.groupName}: ${formatMoney(row.spent)} of ${formatMoney(row.allocated)}, $status',
        excludeSemantics: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${row.groupName} · ${row.percent}%')),
            if (row.allocated > BigInt.zero) Text('${row.usedPercent.round()}% used', style: text.bodySmall),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fill.toDouble(),
              minHeight: 8,
              backgroundColor: c.line,
              color: row.over ? c.coral : (row.warning ? c.saving : c.group(row.groupName)),
            ),
          ),
          // Under the bar, where a long pair of amounts can wrap on a narrow phone.
          // The word is there so colour is never the only signal.
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${formatMoney(row.spent)} of ${formatMoney(row.allocated)}${row.over ? ' · Over the plan' : row.warning ? ' · Close to the plan' : ''}',
              style: text.bodySmall,
            ),
          ),
        ]),
      ),
    );
  }
}
