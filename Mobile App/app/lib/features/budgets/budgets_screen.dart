import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/models.dart';
import '../../core/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/time.dart';
import '../../core/widgets.dart';
import '../activity/activity_providers.dart' show categoriesProvider;
import '../dashboard/dashboard_providers.dart';
import 'budgets_logic.dart';
import 'budgets_providers.dart';
import 'recurring_form_screen.dart';

/// The Budgets tab: expected income, the % plan, and the recurring plans.
class BudgetsScreen extends ConsumerStatefulWidget {
  const BudgetsScreen({super.key, required this.book});
  final Book book;

  @override
  ConsumerState<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends ConsumerState<BudgetsScreen> {
  Book get _book => widget.book;

  void _reload() {
    ref.invalidate(budgetPlanProvider(_book.id));
    ref.invalidate(recurringPlansProvider(_book.id));
    ref.invalidate(categoriesProvider(_book.id));
  }

  Future<void> _openForm([RecurringPlan? plan]) async {
    final outcome = await Navigator.of(context).push<PlanOutcome>(MaterialPageRoute(builder: (_) => RecurringFormScreen(book: _book, existing: plan)));
    if (outcome == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    switch (outcome.action) {
      case 'added':
        messenger.showSnackBar(SnackBar(content: Text('${outcome.plan.name} added.')));
      case 'saved':
        messenger.showSnackBar(SnackBar(content: Text('Changes saved.')));
      case 'stopped':
        messenger.showSnackBar(SnackBar(
          content: Text('${outcome.plan.name} stopped. It will not post again.'),
          duration: const Duration(seconds: 10),
          action: SnackBarAction(label: 'Turn back on', onPressed: () => _turnBackOn(outcome.plan)),
        ));
    }
  }

  // The list route returns only active plans, so this message is the one way
  // back to a plan that was just stopped.
  Future<void> _turnBackOn(RecurringPlan plan) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(budgetsApiProvider(_book.id)).updatePlan(plan.id, {'active': true});
      if (!mounted) return;
      budgetsChanged(ref, _book.id);
      messenger.showSnackBar(SnackBar(content: Text('${plan.name} is on again.')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describePlanFailure(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(budgetPlanProvider(_book.id));
    final plans = ref.watch(recurringPlansProvider(_book.id));
    final categories = ref.watch(categoriesProvider(_book.id));
    if (plan.hasError || plans.hasError || categories.hasError) {
      return ErrorPanel(error: plan.error ?? plans.error ?? categories.error!, what: 'your budget', onRetry: _reload);
    }
    if (!plan.hasValue || !plans.hasValue || !categories.hasValue) return const Center(child: CircularProgressIndicator());

    final canEdit = _book.can(Capability.edit);
    final data = plan.requireValue;
    return RefreshIndicator(
      onRefresh: () async {
        _reload();
        try {
          await ref.read(budgetPlanProvider(_book.id).future);
        } catch (_) {
          // The error panel says what happened; a pull has nothing to add.
        }
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _IncomeCard(base: data.baseIncomeMinor, canEdit: canEdit),
          const SizedBox(height: 14),
          _PlanCard(
            // A new key rebuilds the editor from the saved plan after a save or a refetch.
            key: ValueKey('${data.items.map((share) => '${share.groupName}:${share.percent}').join(',')}|${data.baseIncomeMinor}'),
            book: _book,
            plan: data,
            groups: budgetGroups(categories.requireValue, data),
            canEdit: canEdit,
          ),
          const SizedBox(height: 14),
          _RecurringCard(book: _book, plans: plans.requireValue, canEdit: canEdit, onOpen: _openForm),
        ],
      ),
    );
  }
}

class _IncomeCard extends StatelessWidget {
  const _IncomeCard({required this.base, required this.canEdit});
  final BigInt base;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('EXPECTED MONTHLY INCOME', style: text.labelSmall),
          const SizedBox(height: 8),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(formatMoney(base), style: text.headlineSmall)),
          const SizedBox(height: 4),
          Text(expectedIncomeNote(base, canEdit: canEdit), style: text.bodySmall),
        ]),
      ),
    );
  }
}

class _PlanCard extends ConsumerStatefulWidget {
  const _PlanCard({super.key, required this.book, required this.plan, required this.groups, required this.canEdit});
  final Book book;
  final BudgetPlan plan;
  final List<String> groups;
  final bool canEdit;

  @override
  ConsumerState<_PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends ConsumerState<_PlanCard> {
  late final Map<String, TextEditingController> _fields = {
    for (final entry in sharesOf(widget.plan, widget.groups).entries) entry.key: TextEditingController(text: entry.value == 0 ? '' : '${entry.value}'),
  };
  bool _busy = false;
  String? _failure;

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  /// Each group's typed share, or null where the text is not a share.
  Map<String, int?> get _typed => {for (final entry in _fields.entries) entry.key: parsePercent(entry.value.text)};

  void _usePreset() => setState(() {
    for (final entry in presetShares(widget.groups).entries) {
      _fields[entry.key]!.text = entry.value == 0 ? '' : '${entry.value}';
    }
    _failure = null;
  });

  Future<void> _save(Map<String, int> shares) async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await ref.read(budgetsApiProvider(widget.book.id)).savePlan(shares);
      if (!mounted) return;
      budgetsChanged(ref, widget.book.id);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shares saved.')));
    } catch (error) {
      if (mounted) setState(() => _failure = describePlanFailure(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final base = widget.plan.baseIncomeMinor;
    final typed = _typed;
    final valid = typed.values.every((share) => share != null);
    final shares = {for (final entry in typed.entries) entry.key: entry.value ?? 0};
    final total = totalPercent(shares.values);
    final over = total > 100;
    final canSave = widget.canEdit && valid && !over && !_busy && planChanged(widget.plan, shares);

    final saved = sharesOf(widget.plan, widget.groups);
    final readOnlyRows = [for (final entry in saved.entries) if (entry.value > 0) entry];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Share of income', style: text.titleLarge),
          const SizedBox(height: 4),
          Text('Give each group a percentage of your expected income. The rupee limits follow whatever you earn.', style: text.bodySmall),
          const SizedBox(height: 10),
          if (widget.canEdit) ...[
            for (final group in widget.groups)
              _ShareRow(
                group: group,
                controller: _fields[group]!,
                amount: typed[group] == null ? null : shareMinor(base, typed[group]!),
                invalid: typed[group] == null,
                enabled: !_busy,
                onChanged: () => setState(() => _failure = null),
              ),
            const Divider(height: 20),
            Row(children: [
              Expanded(child: Text('Total', style: text.titleSmall)),
              Text('$total%', style: text.titleSmall?.copyWith(color: over ? Theme.of(context).colorScheme.error : null)),
            ]),
            const SizedBox(height: 2),
            Semantics(
              liveRegion: true,
              child: Text(
                valid ? totalWords(total) : 'Enter each share as a whole number from 0 to 100.',
                style: text.bodySmall?.copyWith(color: over || !valid ? Theme.of(context).colorScheme.error : null),
              ),
            ),
            if (_failure != null) Padding(padding: const EdgeInsets.only(top: 10), child: Notice(_failure!)),
            const SizedBox(height: 14),
            Wrap(spacing: 10, runSpacing: 8, children: [
              FilledButton(
                onPressed: canSave ? () => _save(shares) : null,
                child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save shares'),
              ),
              OutlinedButton(onPressed: _busy ? null : _usePreset, child: const Text('Use 50 / 30 / 20')),
            ]),
            const SizedBox(height: 10),
            Text('Saving counts what you move to your own accounts. Essentials, Lifestyle and Saving take the 50 / 30 / 20 split; any other group goes to 0.', style: text.bodySmall),
          ] else if (readOnlyRows.isEmpty)
            Text('No shares set yet. Someone who can edit this book sets them here.', style: text.bodyMedium)
          else ...[
            for (final entry in readOnlyRows) _ReadShareRow(group: entry.key, percent: entry.value, amount: shareMinor(base, entry.value)),
            const SizedBox(height: 6),
            Text('Planned: ${totalPercent(saved.values)}% of expected income.', style: text.bodySmall),
          ],
        ]),
      ),
    );
  }
}

class _ShareRow extends StatelessWidget {
  const _ShareRow({required this.group, required this.controller, required this.amount, required this.invalid, required this.enabled, required this.onChanged});
  final String group;
  final TextEditingController controller;
  final BigInt? amount;
  final bool invalid;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.paisa;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c.group(group), shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(group, style: text.titleSmall),
            Text(amount == null || amount == BigInt.zero ? 'No share' : '${formatMoney(amount!)} a month', style: text.bodySmall),
          ]),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 92,
          child: Semantics(
            label: '$group share in percent',
            child: TextField(
              key: ValueKey('share-$group'),
              controller: controller,
              enabled: enabled,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.end,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
              onChanged: (_) => onChanged(),
              decoration: InputDecoration(hintText: '0', suffixText: '%', isDense: true, errorText: invalid ? '0 to 100' : null),
            ),
          ),
        ),
      ]),
    );
  }
}

class _ReadShareRow extends StatelessWidget {
  const _ReadShareRow({required this.group, required this.percent, required this.amount});
  final String group;
  final int percent;
  final BigInt amount;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: context.paisa.group(group), shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(group, style: text.titleSmall),
            Text(amount == BigInt.zero ? 'No expected income yet' : '${formatMoney(amount)} a month', style: text.bodySmall),
          ]),
        ),
        Text('$percent%', style: text.titleSmall),
      ]),
    );
  }
}

class _RecurringCard extends StatelessWidget {
  const _RecurringCard({required this.book, required this.plans, required this.canEdit, required this.onOpen});
  final Book book;
  final List<RecurringPlan> plans;
  final bool canEdit;
  final void Function([RecurringPlan? plan]) onOpen;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final clock = BookClock(book.timezone);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Recurring plans', style: text.titleLarge),
          const SizedBox(height: 4),
          Text('When a plan falls due, Paisa adds it to Activity on its own, as a payment that needs review.', style: text.bodySmall),
          const SizedBox(height: 8),
          if (plans.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                canEdit ? 'No recurring plans yet. Add your salary and your regular bills so Paisa knows what is coming.' : 'No recurring plans yet.',
                style: text.bodyMedium,
              ),
            ),
          for (final plan in plans) _PlanRow(plan: plan, clock: clock, onTap: canEdit ? () => onOpen(plan) : null),
          if (canEdit) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: () => onOpen(), icon: const Icon(Icons.add), label: const Text('Add recurring plan')),
          ],
        ]),
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.plan, required this.clock, required this.onTap});
  final RecurringPlan plan;
  final BookClock clock;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.paisa;
    final income = !plan.amountMinor.isNegative;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(plan.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall?.copyWith(color: plan.active ? null : c.muted)),
              const SizedBox(height: 2),
              Text(planDetail(plan, clock), maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall),
              const SizedBox(height: 4),
              _ActivePill(active: plan.active),
            ]),
          ),
          const SizedBox(width: 12),
          // Capped and shrunk, so a huge amount cannot squeeze the name to nothing.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(formatMoney(plan.amountMinor, plusSign: true), style: text.titleSmall?.copyWith(color: !plan.active ? c.muted : (income ? c.positive : c.ink))),
            ),
          ),
        ]),
      ),
    );
  }
}

/// "active" or "stopped" as a word with a border, never colour alone.
class _ActivePill extends StatelessWidget {
  const _ActivePill({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = context.paisa.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(border: Border.all(color: color), borderRadius: BorderRadius.circular(20)),
      child: Text(active ? 'active' : 'stopped', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
    );
  }
}
