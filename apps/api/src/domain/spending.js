// How a month's spending divides across categories.
//
// One implementation shared by both stores. Two rules matter here and were
// wrong when this was written twice:
//
//   1. Money spent with no category still counts. Building the breakdown by
//      walking the category list silently dropped every uncategorized payment,
//      so the "where your money went" panel disagreed with the spent total by
//      exactly the amount the user had not yet reviewed.
//   2. A split transaction belongs to its parts, not to whichever category
//      happens to sit on the parent row.

export const UNCATEGORIZED = { name: 'Uncategorized', groupName: 'Other' };

const magnitude = (value) => { const amount = BigInt(value); return amount < 0n ? -amount : amount; };

export function spendByCategory(transactions, categories) {
  const totals = new Map();
  const add = (categoryId, amount) => { if (amount > 0n) totals.set(categoryId, (totals.get(categoryId) ?? 0n) + amount); };

  for (const transaction of transactions) {
    // Expenses, plus transfers that left the account: an investment or a top-up
    // of your own savings is not consumption, but it is still where money went.
    // A transfer coming in is not an outflow, so its positive amount is skipped.
    if (transaction.kind !== 'expense' && !(transaction.kind === 'transfer' && BigInt(transaction.amountMinor) < 0n)) continue;
    const splits = transaction.splits ?? [];
    if (splits.length) { for (const split of splits) add(split.categoryId ?? null, magnitude(split.amountMinor)); continue; }
    add(transaction.categoryId ?? null, magnitude(transaction.amountMinor));
  }

  const named = new Map(categories.map((category) => [category.id, category]));
  return [...totals]
    .map(([categoryId, amountMinor]) => {
      const category = categoryId === null ? null : named.get(categoryId);
      return { categoryId, name: category?.name ?? UNCATEGORIZED.name, groupName: category?.groupName ?? UNCATEGORIZED.groupName, amountMinor };
    })
    .sort((a, b) => (a.amountMinor === b.amountMinor ? a.name.localeCompare(b.name) : a.amountMinor > b.amountMinor ? -1 : 1));
}
