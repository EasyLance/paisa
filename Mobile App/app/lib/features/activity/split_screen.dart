import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/models.dart';
import '../../core/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets.dart';
import 'activity_logic.dart';
import 'activity_providers.dart';
import 'activity_widgets.dart';

class _Part {
  _Part({this.categoryId, String amount = '', String note = ''})
    : amount = TextEditingController(text: amount),
      note = TextEditingController(text: note);

  String? categoryId;
  final TextEditingController amount;
  final TextEditingController note;
}

/// Share one payment across categories. The parts must add up to the payment
/// exactly, so Save stays off until the remainder is zero. Pops with the payment.
class SplitScreen extends ConsumerStatefulWidget {
  const SplitScreen({super.key, required this.book, required this.transaction});
  final Book book;
  final Transaction transaction;

  @override
  ConsumerState<SplitScreen> createState() => _SplitScreenState();
}

class _SplitScreenState extends ConsumerState<SplitScreen> {
  static const _maxParts = 20;
  late final List<_Part> _parts;
  bool _busy = false;
  String? _failure;

  Transaction get _tx => widget.transaction;

  @override
  void initState() {
    super.initState();
    _parts = _tx.splits.isEmpty
        ? [_Part(), _Part()]
        : [for (final part in _tx.splits) _Part(categoryId: part.categoryId, amount: plainRupees(part.amountMinor), note: part.note ?? '')];
  }

  @override
  void dispose() {
    for (final part in _parts) {
      part.amount.dispose();
      part.note.dispose();
    }
    super.dispose();
  }

  List<BigInt?> get _amounts => [for (final part in _parts) minorFromRupees(part.amount.text)];
  BigInt get _remaining => splitRemaining(_tx.amountMinor, _amounts);

  bool get _valid =>
      _parts.length >= 2 &&
      _remaining == BigInt.zero &&
      _parts.every((part) => part.categoryId != null) &&
      _amounts.every((amount) => amount != null && amount > BigInt.zero);

  Future<void> _save() async {
    // The sign is the payment's: an expense's parts are negative too.
    final negative = _tx.amountMinor.isNegative;
    final parts = [
      for (var i = 0; i < _parts.length; i++)
        (
          categoryId: _parts[i].categoryId!,
          amountMinor: negative ? -_amounts[i]! : _amounts[i]!,
          note: _parts[i].note.text.trim().isEmpty ? null : _parts[i].note.text.trim(),
        ),
    ];
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final saved = await ref.read(ledgerApiProvider(widget.book.id)).split(_tx, parts);
      if (!mounted) return;
      ledgerChanged(ref, widget.book.id, saved);
      Navigator.of(context).pop(saved);
    } catch (error) {
      if (mounted) setState(() => _failure = describeFailure(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.paisa;
    final categories = ref.watch(categoriesProvider(widget.book.id)).value ?? const <Category>[];
    final remaining = _remaining;
    final settled = remaining == BigInt.zero;

    return Scaffold(
      appBar: AppBar(title: const Text('Split payment')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _valid && !_busy ? _save : null,
            child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save split'),
          ),
        ),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_tx.merchant ?? 'Payment', style: text.titleLarge),
              const SizedBox(height: 4),
              Text('Total ${formatMoney(_tx.amountMinor.abs())}', style: text.bodyMedium),
              const SizedBox(height: 4),
              Semantics(
                liveRegion: true,
                child: Text(
                  settled ? 'Nothing left to place.' : (remaining.isNegative ? 'Over by ${formatMoney(remaining.abs())}' : '${formatMoney(remaining)} left to place'),
                  style: text.titleSmall?.copyWith(color: settled ? c.positive : Theme.of(context).colorScheme.error),
                ),
              ),
            ]),
          ),
        ),
        for (var i = 0; i < _parts.length; i++) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('Part ${i + 1}', style: text.titleSmall)),
                  if (_parts.length > 2) IconButton(tooltip: 'Remove part ${i + 1}', icon: const Icon(Icons.delete_outline), onPressed: () => setState(() => _parts.removeAt(i).amount.dispose())),
                ]),
                const SizedBox(height: 4),
                PickerField(
                  label: 'Category',
                  value: categories.where((category) => category.id == _parts[i].categoryId).map((category) => category.name).firstOrNull,
                  onTap: categories.isEmpty
                      ? null
                      : () async {
                          final choice = await showCategorySheet(context, categories: categories, selectedId: _parts[i].categoryId);
                          if (choice != null) setState(() => _parts[i].categoryId = choice.category.id);
                        },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _parts[i].amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ '),
                ),
                const SizedBox(height: 12),
                TextField(controller: _parts[i].note, maxLength: 250, decoration: const InputDecoration(labelText: 'Note (optional)', counterText: '')),
              ]),
            ),
          ),
        ],
        if (_parts.length < _maxParts) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: () => setState(() => _parts.add(_Part())), icon: const Icon(Icons.add), label: const Text('Add a part')),
        ],
        if (_failure != null) Padding(padding: const EdgeInsets.only(top: 12), child: Notice(_failure!)),
      ]),
    );
  }
}
