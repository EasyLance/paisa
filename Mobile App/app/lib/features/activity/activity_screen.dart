import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/models.dart';
import '../../core/theme/tokens.dart';
import '../../core/time.dart';
import '../../core/widgets.dart';
import 'activity_logic.dart';
import 'activity_providers.dart';
import 'activity_widgets.dart';
import 'transaction_detail_screen.dart';
import '../import/import_screen.dart';
import 'transaction_form_screen.dart';

class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key, required this.book, required this.me});
  final Book book;
  final Me me;

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final filter = ref.watch(activityFilterProvider);
    final key = (bookId: book.id, state: filter);
    final list = ref.watch(activityProvider(key));
    final categories = ref.watch(categoriesProvider(book.id));

    Future<void> refresh() async {
      ref.invalidate(activityProvider(key));
      ref.invalidate(categoriesProvider(book.id));
      try {
        await ref.read(activityProvider(key).future);
      } catch (_) {
        // The error panel says what happened; a pull has nothing to add.
      }
    }

    final Widget body;
    if (list.hasError || categories.hasError) {
      body = ErrorPanel(
        error: list.error ?? categories.error!,
        what: 'your payments',
        onRetry: () {
          ref.invalidate(activityProvider(key));
          ref.invalidate(categoriesProvider(book.id));
        },
      );
    } else if (!list.hasValue || !categories.hasValue) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = _List(
        book: book,
        me: widget.me,
        state: list.requireValue,
        filter: filter,
        query: _search.text,
        categories: {for (final category in categories.requireValue) category.id: category},
        onRefresh: refresh,
        onMore: () => ref.read(activityProvider(key).notifier).loadMore(),
      );
    }

    return Scaffold(
      floatingActionButton: book.can(Capability.create)
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TransactionFormScreen(book: book))),
              icon: const Icon(Icons.add),
              label: const Text('Add payment'),
            )
          : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search payments',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(tooltip: 'Clear search', icon: const Icon(Icons.close), onPressed: () => setState(_search.clear)),
                ),
              ),
            ),
            if (book.can(Capability.edit))
              IconButton(
                tooltip: 'Import a statement',
                icon: const Icon(Icons.upload_file),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ImportScreen(book: book))),
              ),
          ]),
        ),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              for (final option in stateFilters)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(option.label),
                    selected: filter == option.value,
                    onSelected: (_) => ref.read(activityFilterProvider.notifier).select(option.value),
                  ),
                ),
            ],
          ),
        ),
        Expanded(child: body),
      ]),
    );
  }
}

class _List extends StatelessWidget {
  const _List({
    required this.book,
    required this.me,
    required this.state,
    required this.filter,
    required this.query,
    required this.categories,
    required this.onRefresh,
    required this.onMore,
  });

  final Book book;
  final Me me;
  final ActivityState state;
  final String? filter;
  final String query;
  final Map<String, Category> categories;
  final Future<void> Function() onRefresh;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final clock = BookClock(book.timezone);
    final shown = [for (final tx in state.items) if (matchesSearch(tx, query, categories)) tx];
    final searching = query.trim().isNotEmpty;
    final more = state.nextCursor != null;

    String? note;
    if (searching && state.items.isNotEmpty) {
      note = '${shown.length} of ${state.items.length} loaded payments match${more ? '. Older payments are not searched until they are loaded.' : '.'}';
    }

    String empty() {
      if (searching) return 'No loaded payment matches “${query.trim()}”.${more ? ' Load older payments to search further.' : ''}';
      return switch (filter) {
        'pending_review' => 'You are all caught up. Nothing needs review.',
        null => 'No payments yet. They appear here as they are added or imported.',
        _ => 'No ${stateLabel(filter!).toLowerCase()} payments.',
      };
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 300) onMore();
        return false;
      },
      child: RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(bottom: book.can(Capability.create) ? 88 : 24),
          children: [
            if (note != null) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text(note, style: text.bodySmall)),
            if (shown.isEmpty)
              Padding(padding: const EdgeInsets.fromLTRB(24, 48, 24, 16), child: Text(empty(), textAlign: TextAlign.center, style: text.bodyMedium)),
            for (final tx in shown)
              _Row(
                tx: tx,
                label: categoryLabel(tx, categories),
                clock: clock,
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TransactionDetailScreen(transaction: tx, book: book, me: me))),
              ),
            if (more)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: state.loadingMore
                      ? const CircularProgressIndicator()
                      : Column(children: [
                          if (state.moreFailed) const Padding(padding: EdgeInsets.only(bottom: 8), child: Notice('Could not load older payments. Check your connection.')),
                          OutlinedButton(onPressed: onMore, child: Text(state.moreFailed ? 'Try again' : 'Load older payments')),
                        ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.tx, required this.label, required this.clock, required this.onTap});
  final Transaction tx;
  final String label;
  final BookClock clock;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.paisa;
    final quiet = tx.state == 'confirmed' || tx.state == 'reconciled';
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tx.merchant ?? kindLabel(tx.kind), maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
              const SizedBox(height: 2),
              Text('${clock.shortDate(tx.occurredAt)} · $label', maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall),
              if (!quiet) Padding(padding: const EdgeInsets.only(top: 4), child: StatusPill(tx.state)),
            ]),
          ),
          const SizedBox(width: 12),
          AmountText(tx),
        ]),
      ),
    );
  }
}
