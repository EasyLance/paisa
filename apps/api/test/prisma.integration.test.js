import { afterAll, describe, expect, it } from 'vitest';
import { PrismaStore } from '../src/store/prisma-store.js';

const run = process.env.RUN_PRISMA_TESTS === 'true';

describe.skipIf(!run)('PrismaStore production invariants', () => {
  const store = new PrismaStore();
  const createdTransactionIds = [];

  afterAll(async () => {
    if (createdTransactionIds.length) {
      await store.db.transaction.deleteMany({ where: { id: { in: createdTransactionIds } } });
    }
    await store.db.idempotencyRecord.deleteMany({ where: { actorId: 'user_owner', operation: 'transaction.create' } });
    await store.close();
  });

  it('persists manual transaction idempotency in MySQL', async () => {
    const data = { workspaceId: 'ws_household', bookId: 'book_owner', categoryId: 'cat_food', kind: 'expense', amountMinor: '-12345', currency: 'INR', merchant: 'CI idempotency', occurredAt: '2026-08-29T10:00:00.000Z' };
    const first = await store.createTransaction(data, 'user_owner', 'ci-manual-transaction');
    const replay = await store.createTransaction(data, 'user_owner', 'ci-manual-transaction');
    createdTransactionIds.push(first.id);
    expect(replay.id).toBe(first.id);
    expect(replay.__idempotentReplay).toBe(true);
  });

  it('deduplicates concurrent ingestion at the database constraint', async () => {
    const sourceHash = `ci-source-${Date.now()}`;
    const data = { workspaceId: 'ws_household', bookId: 'book_owner', categoryId: 'cat_food', sourceType: 'statement', sourceHash, kind: 'expense', amountMinor: '-50000', currency: 'INR', merchant: 'CI statement', occurredAt: '2026-08-29T10:00:00.000Z' };
    const [first, second] = await Promise.all([store.ingest(data, 'user_owner'), store.ingest(data, 'user_owner')]);
    createdTransactionIds.push(first.transactionId);
    expect(second.transactionId).toBe(first.transactionId);
    expect([first.duplicate, second.duplicate]).toContain(true);
  });
});
