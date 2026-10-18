import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/money.dart';
import '../../core/time.dart';
import '../../core/widgets.dart';
import '../activity/activity_logic.dart' show kindLabel;
import '../activity/activity_providers.dart' show categoriesProvider;
import '../activity/activity_widgets.dart';
import '../dashboard/dashboard_providers.dart';
import 'budgets_logic.dart';
import 'budgets_providers.dart';

/// What the form hands back: the plan as saved, and whether it was saved or
/// stopped, so the Budgets tab (which stays mounted) can say so and offer undo.
typedef PlanOutcome = ({String action, RecurringPlan plan});

/// Add a recurring plan, or correct one ([existing]) or stop it.
class RecurringFormScreen extends ConsumerStatefulWidget {
  const RecurringFormScreen({super.key, required this.book, this.existing});
  final Book book;
  final RecurringPlan? existing;

  @override
  ConsumerState<RecurringFormScreen> createState() => _RecurringFormScreenState();
}

class _RecurringFormScreenState extends ConsumerState<RecurringFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final BookClock _clock = BookClock(widget.book.timezone);
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late String _kind;
  late String _cadence;
  late DateTime _day; // the book's own calendar day, as y/m/d at UTC midnight
  String? _categoryId;
  bool _dayPicked = false;
  bool _busy = false;
  String? _failure;

  RecurringPlan? get _existing => widget.existing;

  @override
  void initState() {
    super.initState();
    final plan = _existing;
    _name = TextEditingController(text: plan?.name ?? '');
    _amount = TextEditingController(text: plan == null ? '' : plainRupees(plan.amountMinor));
    _kind = plan?.kind ?? 'expense';
    _cadence = plan?.cadence ?? 'monthly';
    _categoryId = plan?.categoryId;
    final wall = _clock.wall(plan?.nextDueAt ?? ref.read(clockProvider)());
    _day = DateTime.utc(wall.year, wall.month, wall.day);
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final today = _clock.wall(ref.read(clockProvider)());
    final initial = DateTime(_day.year, _day.month, _day.day);
    final earliest = DateTime(today.year, today.month, today.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      // An overdue plan keeps its own date selectable; a new date is never in the past.
      firstDate: initial.isBefore(earliest) ? initial : earliest,
      lastDate: DateTime(today.year + 10, 12, 31),
    );
    if (picked != null) {
      setState(() {
        _day = DateTime.utc(picked.year, picked.month, picked.day);
        _dayPicked = true;
      });
    }
  }

  Future<void> _pickCategory(List<Category> categories) async {
    final choice = await showCategorySheet(context, categories: categories, selectedId: _categoryId);
    if (choice != null) setState(() => _categoryId = choice.category.id);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final existing = _existing;
    final amount = signedMinor(_kind, minorFromRupees(_amount.text)!);
    final due = _clock.dateAt(_day.year, _day.month, _day.day);

    Map<String, Object?>? patch;
    if (existing != null) {
      final before = _clock.wall(existing.nextDueAt);
      final moved = _dayPicked && (before.year != _day.year || before.month != _day.month || before.day != _day.day);
      patch = recurringEditPatch(existing, name: _name.text, kind: _kind, amountMinor: amount, cadence: _cadence, categoryId: _categoryId, nextDueAt: moved ? due : null);
      if (patch.isEmpty) {
        setState(() => _failure = 'Nothing has changed.');
        return;
      }
    }

    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final api = ref.read(budgetsApiProvider(widget.book.id));
      final saved = existing == null
          ? await api.createPlan(recurringCreateBody(name: _name.text, kind: _kind, amountMinor: amount, cadence: _cadence, nextDueAt: due, categoryId: _categoryId))
          : await api.updatePlan(existing.id, patch!);
      if (!mounted) return;
      budgetsChanged(ref, widget.book.id);
      Navigator.of(context).pop<PlanOutcome>((action: existing == null ? 'added' : 'saved', plan: saved));
    } catch (error) {
      // A POST has no idempotency key, so a lost connection may have saved it:
      // refresh the list behind this screen so it shows the truth on return.
      if (error is ApiError && error.isNetwork && existing == null) budgetsChanged(ref, widget.book.id);
      if (mounted) setState(() => _failure = describePlanFailure(error, created: existing == null));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    final plan = _existing!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Stop ${plan.name}?'),
        content: const Text('It will not post again and leaves this list. Payments it already added stay in Activity. Right after, a message lets you turn it back on.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: const Text('Keep it')),
          TextButton(onPressed: () => Navigator.of(dialog).pop(true), child: const Text('Stop plan')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final stopped = await ref.read(budgetsApiProvider(widget.book.id)).updatePlan(plan.id, {'active': false});
      if (!mounted) return;
      budgetsChanged(ref, widget.book.id);
      Navigator.of(context).pop<PlanOutcome>((action: 'stopped', plan: stopped));
    } catch (error) {
      if (mounted) setState(() => _failure = describePlanFailure(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final categories = ref.watch(categoriesProvider(widget.book.id)).value ?? const <Category>[];
    final editing = _existing != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit recurring plan' : 'Add recurring plan')),
      body: Form(
        key: _formKey,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Notice('When a plan falls due, Paisa adds it to Activity on its own, as a payment that needs review.', isError: false),
          ),
          TextFormField(
            controller: _name,
            maxLength: 120,
            decoration: const InputDecoration(labelText: 'Name', hintText: 'For example Monthly rent', counterText: ''),
            validator: (value) => (value ?? '').trim().isEmpty ? 'Give the plan a name.' : null,
          ),
          const SizedBox(height: 16),
          Text('TYPE', style: text.labelSmall),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final kind in const ['expense', 'income'])
              ChoiceChip(label: Text(kindLabel(kind)), selected: _kind == kind, onSelected: (_) => setState(() => _kind = kind)),
          ]),
          const SizedBox(height: 16),
          TextFormField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ '),
            validator: (value) {
              final parsed = minorFromRupees(value ?? '');
              if (parsed == null) return 'Enter an amount like 450 or 450.50, with at most two decimals.';
              return parsed == BigInt.zero ? 'The amount cannot be zero.' : null;
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _cadence,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Repeats'),
            items: [for (final option in cadences) DropdownMenuItem(value: option.value, child: Text(option.label))],
            onChanged: (value) => setState(() => _cadence = value ?? _cadence),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: _pickDay,
            borderRadius: BorderRadius.circular(10),
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Next due', suffixIcon: Icon(Icons.calendar_today_outlined)),
              child: Text(_clock.longDate(_clock.dateAt(_day.year, _day.month, _day.day)), style: text.bodyLarge),
            ),
          ),
          const SizedBox(height: 16),
          PickerField(
            label: 'Category (optional)',
            value: categories.where((category) => category.id == _categoryId).map((category) => category.name).firstOrNull,
            hint: 'None',
            onTap: categories.isEmpty ? null : () => _pickCategory(categories),
          ),
          if (_categoryId != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: () => setState(() => _categoryId = null), child: const Text('Remove category')),
            ),
          if (_failure != null) Padding(padding: const EdgeInsets.only(top: 12), child: Notice(_failure!)),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(editing ? 'Save changes' : 'Add plan'),
          ),
          if (editing) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _busy ? null : _stop, child: const Text('Stop this plan')),
            const SizedBox(height: 8),
            Text('Stopping keeps the payments it already added. A stopped plan leaves the list, so turn it back on from the message right after, or add it again.', style: text.bodySmall),
          ],
        ]),
      ),
    );
  }
}
