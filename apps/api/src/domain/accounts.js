// How money moved between the book's accounts over a period.
//
// Shared by both stores. Two separate questions, and they answer different
// things:
//
//   byAccount — what entered and left each account, from every transaction
//               tagged to it. Works with no extra bookkeeping.
//   flows     — account-to-account movement. Only a transfer that names a
//               destination can say this, because a transaction records one
//               account; without `counterAccountId` all we know is that money
//               left, not where it landed.

const magnitude = (value) => { const amount = BigInt(value); return amount < 0n ? -amount : amount; };

export function accountActivity(transactions, accounts) {
  const totals = new Map(accounts.map((account) => [account.id, { accountId: account.id, name: account.name, inMinor: 0n, outMinor: 0n }]));
  const untagged = { accountId: null, name: 'Not linked to an account', inMinor: 0n, outMinor: 0n };
  const flows = new Map();

  for (const transaction of transactions) {
    const amount = BigInt(transaction.amountMinor);
    if (amount === 0n) continue;
    const bucket = totals.get(transaction.accountId) ?? untagged;
    if (amount < 0n) bucket.outMinor += -amount; else bucket.inMinor += amount;

    // The other half of a transfer: the destination gains what the source lost.
    const destination = transaction.counterAccountId && totals.get(transaction.counterAccountId);
    if (!destination || transaction.counterAccountId === transaction.accountId) continue;
    destination.inMinor += magnitude(amount);
    const key = `${transaction.accountId ?? ''}>${transaction.counterAccountId}`;
    const flow = flows.get(key) ?? { fromAccountId: transaction.accountId ?? null, fromName: bucket.name, toAccountId: transaction.counterAccountId, toName: destination.name, amountMinor: 0n, count: 0 };
    flow.amountMinor += magnitude(amount);
    flow.count += 1;
    flows.set(key, flow);
  }

  const used = [...totals.values(), untagged].filter((entry) => entry.inMinor > 0n || entry.outMinor > 0n);
  return {
    byAccount: used
      .map((entry) => ({ ...entry, netMinor: entry.inMinor - entry.outMinor }))
      .sort((a, b) => (b.inMinor + b.outMinor > a.inMinor + a.outMinor ? 1 : -1)),
    flows: [...flows.values()].sort((a, b) => (b.amountMinor > a.amountMinor ? 1 : -1)),
  };
}

// A transfer into the account it came from records no movement and would count
// the amount twice on that account.
export function assertDistinctAccounts({ accountId, counterAccountId }) {
  if (!counterAccountId || counterAccountId !== accountId) return;
  const error = new Error('A transfer cannot name the same account as both source and destination');
  error.statusCode = 400;
  error.code = 'SAME_ACCOUNT_TRANSFER';
  throw error;
}
