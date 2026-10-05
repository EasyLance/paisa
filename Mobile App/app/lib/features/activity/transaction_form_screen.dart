import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/models.dart';
import '../../core/money.dart';
import '../../core/time.dart';
import '../../core/widgets.dart';
import '../dashboard/dashboard_providers.dart';
import 'activity_logic.dart';
import 'activity_providers.dart';
import 'activity_widgets.dart';

/// Add a payment by hand, or correct one ([existing]). Pops with the saved
/// payment so the screen it came from can show it.
class TransactionFormScreen extends ConsumerStatefulWidget {
  const TransactionFormScreen({super.key, required this.book, this.existing});
  final Book book;
  final Transaction? existing;

  @override
  ConsumerState<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends ConsumerState<TransactionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final BookClock _clock = BookClock(widget.book.timezone);
  late final TextEditingController _amount;
  late final TextEditingController _merchant;
  late final TextEditingController _note;
  late String _kind;
  late DateTime _day; // the book's own calendar day, as y/m/d at UTC midnight
  late String? _accountId;
  late String? _counterId;
  String? _categoryId;
  bool _dayPicked = false;
  bool _busy = false;
  String? _failure;

  // One key per form. Reused if the connection drops, because the server may
  // have saved the payment before the reply was lost; a retry with the same
  // key hands back that payment instead of adding a second one.
  String _key = newIdempotencyKey();

  Transaction? get _existing => widget.existing;
  bool get _locked => _existing?.splits.isNotEmpty ?? false;

  /// A transfer keeps the direction it already has; a new one goes out of the
  /// first account into the second.
  bool get _transferOut => _existing == null || _existing!.amountMinor.isNegative;

  @override
  void initState() {
    super.initState();
    final tx = _existing;
    _kind = tx?.kind ?? 'expense';
    _amount = TextEditingController(text: tx == null ? '' : plainRupees(tx.amountMinor));
    _merchant = TextEditingController(text: tx?.merchant ?? '');
    _note = TextEditingController(text: tx?.note ?? '');
    _accountId = tx?.accountId;
    _counterId = tx?.counterAccountId;
    final wall = _clock.wall(tx?.occurredAt ?? ref.read(clockProvider)());
    _day = DateTime.utc(wall.year, wall.month, wall.day);
  }

  @override
  void dispose() {
    _amount.dispose();
    _merchant.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(_day.year, _day.month, _day.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(_day.year + 1, 12, 31),
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
    final amount = signedMinor(_kind, minorFromRupees(_amount.text)!, transferOut: _transferOut);
    final existing = _existing;
    final counter = _kind == 'transfer' ? _counterId : null;
    final day = _clock.dateAt(_day.year, _day.month, _day.day);

    Map<String, Object?>? patch;
    if (existing != null) {
      final before = _clock.wall(existing.occurredAt);
      final moved = _dayPicked && (before.year != _day.year || before.month != _day.month || before.day != _day.day);
      patch = editPatch(
        existing,
        kind: _kind,
        amountMinor: amount,
        merchant: _merchant.text,
        note: _note.text,
        accountId: _accountId,
        counterAccountId: counter,
        occurredAt: moved ? day : null,
      );
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
      final api = ref.read(ledgerApiProvider(widget.book.id));
      final saved = existing == null
          ? await api.create(
              createBody(kind: _kind, amountMinor: amount, merchant: _merchant.text, note: _note.text, categoryId: _kind == 'transfer' ? null : _categoryId, accountId: _accountId, counterAccountId: counter, occurredAt: day),
              _key,
            )
          : await api.edit(existing, patch!);
      if (!mounted) return;
      ledgerChanged(ref, widget.book.id, saved);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(existing == null ? 'Payment added.' : 'Changes saved.')));
      Navigator.of(context).pop(saved);
    } catch (error) {
      // Anything the server answered was seen and refused, so the next try is a
      // new request. Only a lost connection leaves the outcome unknown, and only
      // then is the key kept.
      if (error is ApiError && !error.isNetwork) _key = newIdempotencyKey();
      if (mounted) setState(() => _failure = describeFailure(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final accounts = ref.watch(accountsProvider(widget.book.id)).value ?? const <Account>[];
    final categories = ref.watch(categoriesProvider(widget.book.id)).value ?? const <Category>[];
    final editing = _existing != null;
    final original = _existing?.sources.isEmpty ?? true ? null : _existing!.sources.first;

    List<DropdownMenuItem<String?>> accountItems() => [
      const DropdownMenuItem<String?>(value: null, child: Text('None')),
      for (final account in accounts) DropdownMenuItem<String?>(value: account.id, child: Text(account.label, overflow: TextOverflow.ellipsis)),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit payment' : 'Add payment')),
      body: Form(
        key: _formKey,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          if (original != null && original.sourceType != 'manual')
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Notice('This came from a ${sourceLabel(original.sourceType).toLowerCase()}. The original figure is kept even if you correct it here.', isError: false),
            ),
          if (_locked)
            const Padding(padding: EdgeInsets.only(bottom: 12), child: Notice('This payment is split, so its type and amount are locked. Change the split instead.', isError: false)),
          Text('TYPE', style: text.labelSmall),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final kind in const ['expense', 'income', 'refund', 'transfer'])
              ChoiceChip(label: Text(kindLabel(kind)), selected: _kind == kind, onSelected: _locked ? null : (_) => setState(() => _kind = kind)),
          ]),
          const SizedBox(height: 16),
          TextFormField(
            controller: _amount,
            readOnly: _locked,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ '),
            validator: (value) {
              final parsed = minorFromRupees(value ?? '');
              if (parsed == null) return 'Enter an amount like 450 or 450.50, with at most two decimals.';
              return parsed == BigInt.zero ? 'The amount cannot be zero.' : null;
            },
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: _pickDay,
            borderRadius: BorderRadius.circular(10),
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Date', suffixIcon: Icon(Icons.calendar_today_outlined)),
              child: Text(_clock.longDate(_clock.dateAt(_day.year, _day.month, _day.day)), style: text.bodyLarge),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(controller: _merchant, maxLength: 160, decoration: const InputDecoration(labelText: 'Merchant or person', counterText: '')),
          const SizedBox(height: 16),
          if (!editing && _kind != 'transfer') ...[
            PickerField(
              label: 'Category',
              value: categories.where((category) => category.id == _categoryId).map((category) => category.name).firstOrNull,
              hint: 'None yet. It will wait for review.',
              onTap: categories.isEmpty ? null : () => _pickCategory(categories),
            ),
            const SizedBox(height: 16),
          ],
          if (accounts.isNotEmpty) ...[
            DropdownButtonFormField<String?>(
              initialValue: _accountId,
              isExpanded: true,
              decoration: InputDecoration(labelText: _kind == 'transfer' ? 'From account' : 'Account'),
              items: accountItems(),
              onChanged: (value) => setState(() => _accountId = value),
            ),
            const SizedBox(height: 16),
          ],
          if (_kind == 'transfer' && accounts.isNotEmpty) ...[
            DropdownButtonFormField<String?>(
              initialValue: _counterId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'To account'),
              items: accountItems(),
              onChanged: (value) => setState(() => _counterId = value),
              validator: (value) => value != null && value == _accountId ? 'Choose two different accounts.' : null,
            ),
            const SizedBox(height: 16),
          ],
          TextFormField(controller: _note, maxLines: 3, minLines: 1, maxLength: 2000, decoration: const InputDecoration(labelText: 'Note', counterText: '')),
          if (_failure != null) Padding(padding: const EdgeInsets.only(top: 12), child: Notice(_failure!)),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(editing ? 'Save changes' : 'Add payment'),
          ),
        ]),
      ),
    );
  }
}
