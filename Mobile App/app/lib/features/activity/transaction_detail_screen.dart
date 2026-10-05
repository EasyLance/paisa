import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/models.dart';
import '../../core/money.dart';
import '../../core/theme/tokens.dart';
import '../../core/time.dart';
import '../../core/widgets.dart';
import 'activity_logic.dart';
import 'activity_providers.dart';
import 'activity_widgets.dart';
import 'split_screen.dart';
import 'transaction_form_screen.dart';

class TransactionDetailScreen extends ConsumerStatefulWidget {
  const TransactionDetailScreen({super.key, required this.transaction, required this.book, required this.me});
  final Transaction transaction;
  final Book book;
  final Me me;

  @override
  ConsumerState<TransactionDetailScreen> createState() => _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends ConsumerState<TransactionDetailScreen> {
  late Transaction _tx = widget.transaction;
  final _comment = TextEditingController();
  bool _busy = false;
  String? _failure;

  Book get _book => widget.book;
  LedgerApi get _api => ref.read(ledgerApiProvider(_book.id));

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  /// Runs one write. The screen takes the new version of the payment and the
  /// list and dashboard are told; on failure nothing changes and the person is told.
  Future<bool> _run(Future<Transaction> Function() write) async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final updated = await write();
      if (!mounted) return false;
      ledgerChanged(ref, _book.id, updated);
      setState(() => _tx = updated);
      return true;
    } catch (error) {
      if (mounted) setState(() => _failure = describeFailure(error));
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _say(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  // Choosing a category is what confirms a payment on the server, which is why a
  // reviewer can confirm. Without a category only somebody who may edit can.
  Future<void> _confirm() async {
    final categoryId = _tx.categoryId;
    final ok = await _run(() => categoryId != null && _book.can(Capability.reclassify)
        ? _api.setCategory(_tx, categoryId)
        : _api.edit(_tx, {'state': 'confirmed'}));
    if (ok) _say('Confirmed.');
  }

  Future<void> _changeCategory(List<Category> categories) async {
    final choice = await showCategorySheet(context, categories: categories, selectedId: _tx.categoryId, futureFor: _tx.merchant);
    if (choice == null || !mounted) return;
    final ok = await _run(() => _api.setCategory(_tx, choice.category.id, applyToFuture: choice.applyToFuture));
    if (ok) _say(choice.applyToFuture ? 'Filed under ${choice.category.name}, and future payments to ${_tx.merchant} will be too.' : 'Filed under ${choice.category.name}.');
  }

  Future<void> _void() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Void this payment?'),
        content: const Text('It stays in the ledger with its history, but no longer counts towards any month. This cannot be undone from the app.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: const Text('Keep it')),
          FilledButton(onPressed: () => Navigator.of(dialog).pop(true), child: const Text('Void payment')),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    if (await _run(() => _api.edit(_tx, {'state': 'voided'})) && mounted) {
      _say('Voided. It stays in the ledger but no longer counts.');
      Navigator.of(context).pop();
    }
  }

  Future<void> _push(Widget screen) async {
    final updated = await Navigator.of(context).push<Transaction>(MaterialPageRoute(builder: (_) => screen));
    if (updated != null && mounted) setState(() => _tx = updated);
  }

  Future<void> _postComment() async {
    final body = _comment.text.trim();
    if (body.isEmpty) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final posted = await _api.comment(_tx, body);
      if (!mounted) return;
      final updated = _tx.withComment(posted);
      ledgerChanged(ref, _book.id, updated);
      setState(() {
        _tx = updated;
        _comment.clear();
      });
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
    final clock = BookClock(_book.timezone);
    final tx = _tx;
    final categories = ref.watch(categoriesProvider(_book.id)).value ?? const <Category>[];
    final accounts = {for (final a in ref.watch(accountsProvider(_book.id)).value ?? const <Account>[]) a.id: a};
    final byId = {for (final category in categories) category.id: category};
    final counted = isCounted(tx);
    final reviewable = tx.state == 'pending_review' && (_book.can(Capability.edit) || (tx.categoryId != null && _book.can(Capability.reclassify)));
    final canCategory = _book.can(Capability.reclassify) && tx.state != 'voided';
    final canSplit = _book.can(Capability.split) && tx.state != 'voided';
    final canEdit = _book.can(Capability.edit) && tx.state != 'voided';
    final original = tx.sources.isEmpty ? null : tx.sources.first;

    return Scaffold(
      appBar: AppBar(title: const Text('Payment')),
      body: Column(children: [
        if (_busy) const LinearProgressIndicator(minHeight: 3),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(kindLabel(tx.kind).toUpperCase(), style: text.labelSmall),
                  const SizedBox(height: 6),
                  FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: AmountText(tx, style: text.headlineMedium)),
                  const SizedBox(height: 6),
                  Text(tx.merchant ?? kindLabel(tx.kind), style: text.titleLarge),
                  const SizedBox(height: 2),
                  Text('${clock.longDate(tx.occurredAt)}, ${clock.time(tx.occurredAt)}', style: text.bodySmall),
                  const SizedBox(height: 10),
                  StatusPill(tx.state),
                ]),
              ),
            ),
            if (_failure != null) Padding(padding: const EdgeInsets.only(top: 12), child: Notice(_failure!)),
            if (!counted)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Notice(
                  tx.state == 'voided'
                      ? 'Voided. This payment stays in the ledger for the audit trail but no longer counts towards any month.'
                      : 'Excluded. This payment stays in the ledger but is left out of the totals.',
                  isError: false,
                ),
              ),
            if (reviewable) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Needs a quick review', style: text.titleSmall?.copyWith(color: Theme.of(context).colorScheme.onPrimaryContainer)),
                  const SizedBox(height: 4),
                  Text(
                    tx.categoryId == null ? 'Choose where this belongs, or confirm it as it is.' : 'Confirm it if the category is right, or change it.',
                    style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onPrimaryContainer),
                  ),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    FilledButton(onPressed: _busy ? null : _confirm, child: const Text('Confirm')),
                    if (canCategory) OutlinedButton(onPressed: _busy ? null : () => _changeCategory(categories), child: const Text('Change category')),
                  ]),
                ]),
              ),
            ],
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  _Fact('Category', tx.splits.isNotEmpty ? 'Split ${tx.splits.length} ways' : categoryLabel(tx, byId)),
                  if (accounts[tx.accountId] != null) _Fact(tx.kind == 'transfer' ? 'From account' : 'Account', accounts[tx.accountId]!.label),
                  if (accounts[tx.counterAccountId] != null) _Fact('To account', accounts[tx.counterAccountId]!.label),
                  if (original != null) _Fact('Source', sourceLabel(original.sourceType)),
                  // The bank's figure is kept forever, so a corrected amount is
                  // never mistaken for the original.
                  if (original != null && original.importedAmount != tx.amountMinor) _Fact('Original amount', formatMoney(original.importedAmount)),
                  if (tx.note != null && tx.note!.isNotEmpty) _Fact('Note', tx.note!),
                ]),
              ),
            ),
            if (tx.splits.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Split', style: text.titleLarge),
                    const SizedBox(height: 8),
                    for (final part in tx.splits)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(byId[part.categoryId]?.name ?? 'Category', style: text.bodyMedium),
                              if (part.note != null && part.note!.isNotEmpty) Text(part.note!, style: text.bodySmall),
                            ]),
                          ),
                          const SizedBox(width: 12),
                          Text(formatMoney(part.amountMinor), style: text.bodyMedium),
                        ]),
                      ),
                  ]),
                ),
              ),
            ],
            if (canCategory || canSplit || canEdit) ...[
              const SizedBox(height: 12),
              Card(
                child: Column(children: [
                  if (canEdit) _Action(icon: Icons.edit_outlined, label: 'Edit payment', onTap: _busy ? null : () => _push(TransactionFormScreen(book: _book, existing: tx))),
                  if (canCategory && !reviewable) _Action(icon: Icons.label_outline, label: 'Change category', onTap: _busy ? null : () => _changeCategory(categories)),
                  if (canSplit) _Action(icon: Icons.call_split, label: tx.splits.isEmpty ? 'Split across categories' : 'Edit split', onTap: _busy ? null : () => _push(SplitScreen(book: _book, transaction: tx))),
                  if (canEdit) _Action(icon: Icons.block, label: 'Void payment', onTap: _busy ? null : _void, destructive: true),
                ]),
              ),
            ],
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Comments', style: text.titleLarge),
                  const SizedBox(height: 8),
                  if (tx.comments.isEmpty) Text('No comments yet.', style: text.bodySmall),
                  for (final comment in tx.comments)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          '${comment.authorId == widget.me.id ? 'You' : 'A member of this book'} · ${clock.shortDate(comment.createdAt)}, ${clock.time(comment.createdAt)}',
                          style: text.bodySmall?.copyWith(color: c.muted),
                        ),
                        Text(comment.body, style: text.bodyMedium),
                      ]),
                    ),
                  if (_book.can(Capability.comment)) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _comment,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 2000,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Add a comment',
                        counterText: '',
                        suffixIcon: IconButton(
                          tooltip: 'Post comment',
                          icon: const Icon(Icons.send),
                          onPressed: _busy || _comment.text.trim().isEmpty ? null : _postComment,
                        ),
                      ),
                    ),
                  ],
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 112, child: Text(label, style: text.bodySmall)),
        Expanded(child: Text(value, style: text.bodyMedium)),
      ]),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap, this.destructive = false});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Theme.of(context).colorScheme.error : null;
    return ListTile(
      minTileHeight: 52,
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color)),
      trailing: const Icon(Icons.chevron_right),
      enabled: onTap != null,
      onTap: onTap,
    );
  }
}
