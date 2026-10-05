import 'package:flutter/material.dart';

import '../../core/api/models.dart';
import '../../core/money.dart';
import '../../core/theme/tokens.dart';
import 'activity_logic.dart';

/// A word with a border: status is never carried by colour alone.
class StatusPill extends StatelessWidget {
  const StatusPill(this.state, {super.key});
  final String state;

  @override
  Widget build(BuildContext context) {
    final c = context.paisa;
    final attention = state == 'pending_review';
    final color = attention ? c.coral : c.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(border: Border.all(color: color), borderRadius: BorderRadius.circular(20)),
      child: Text(stateLabel(state).toLowerCase(), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: attention ? Theme.of(context).colorScheme.onSurface : c.muted)),
    );
  }
}

/// A signed amount in the colour of its direction. Voided and excluded payments
/// are struck through: they no longer count.
class AmountText extends StatelessWidget {
  const AmountText(this.tx, {super.key, this.style});
  final Transaction tx;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final c = context.paisa;
    final base = style ?? Theme.of(context).textTheme.titleSmall!;
    final counted = isCounted(tx);
    return Text(
      formatMoney(tx.amountMinor, plusSign: true),
      style: base.copyWith(
        color: !counted ? c.muted : (tx.amountMinor.isNegative ? c.ink : c.positive),
        decoration: counted ? null : TextDecoration.lineThrough,
      ),
    );
  }
}

Color swatch(String hex, Color fallback) {
  final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
  return value == null || hex.length != 7 ? fallback : Color(0xff000000 | value);
}

class CategoryChoice {
  const CategoryChoice(this.category, {this.applyToFuture = false});
  final Category category;
  final bool applyToFuture;
}

/// Pick a category from a sheet, grouped as the dashboard groups them. Pass
/// [futureFor] (the merchant) to offer "do the same next time": that writes a
/// rule on the server.
Future<CategoryChoice?> showCategorySheet(
  BuildContext context, {
  required List<Category> categories,
  String? selectedId,
  String? futureFor,
  String title = 'Choose a category',
}) {
  final groups = <String, List<Category>>{};
  for (final category in categories) {
    groups.putIfAbsent(category.groupName, () => []).add(category);
  }
  var future = false;
  return showModalBottomSheet<CategoryChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, setState) {
        final text = Theme.of(sheet).textTheme;
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text(title, style: text.titleLarge)),
            if (futureFor != null && futureFor.trim().isNotEmpty)
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                title: Text('Do the same for future payments to $futureFor', style: text.bodyMedium),
                value: future,
                onChanged: (value) => setState(() => future = value),
              ),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final entry in groups.entries) ...[
                  Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 2), child: Text(entry.key.toUpperCase(), style: text.labelSmall)),
                  for (final category in entry.value)
                    ListTile(
                      minTileHeight: 48,
                      leading: CircleAvatar(radius: 6, backgroundColor: swatch(category.color, sheet.paisa.other)),
                      title: Text(category.name),
                      trailing: category.id == selectedId ? const Icon(Icons.check) : null,
                      onTap: () => Navigator.of(sheet).pop(CategoryChoice(category, applyToFuture: future)),
                    ),
                ],
              ]),
            ),
          ]),
        );
      },
    ),
  );
}

/// A field-shaped row that opens a picker, for choices too long for a dropdown.
class PickerField extends StatelessWidget {
  const PickerField({super.key, required this.label, required this.value, required this.onTap, this.hint = 'Choose'});
  final String label;
  final String? value;
  final String hint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: InputDecorator(
      decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.expand_more)),
      child: Text(value ?? hint, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: value == null ? context.paisa.muted : null)),
    ),
  );
}
