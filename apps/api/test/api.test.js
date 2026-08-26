import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.js';

describe('Paisa API authorization and ledger invariants', () => {
  let app;
  beforeEach(async () => { app = await buildApp({ memory: true, authMode: 'dev' }); });
  afterEach(async () => { await app.close(); });

  const as = (userId) => ({ 'x-dev-user-id': userId });

  it('returns only the books explicitly granted to a user', async () => {
    const owner = await app.inject({ method: 'GET', url: '/v1/books', headers: as('user_owner') });
    const spouse = await app.inject({ method: 'GET', url: '/v1/books', headers: as('user_spouse') });
    expect(owner.statusCode).toBe(200);
    expect(owner.json().items.map((book) => book.id)).toEqual(['book_arjun', 'book_home']);
    expect(spouse.json().items.map((book) => book.id)).toEqual(['book_priya', 'book_home']);
  });

  it('hides a private book as not found instead of leaking its existence', async () => {
    const response = await app.inject({ method: 'GET', url: '/v1/books/book_priya/transactions', headers: as('user_owner') });
    expect(response.statusCode).toBe(404);
    expect(response.json().code).toBe('NOT_FOUND');
  });

  it('allows a reviewer to reclassify a shared transaction and audits it', async () => {
    const response = await app.inject({ method: 'PATCH', url: '/v1/books/book_home/transactions/tx_5/category', headers: { ...as('user_ca'), 'content-type': 'application/json' }, payload: { categoryId: 'cat_food', applyToFuture: false } });
    expect(response.statusCode).toBe(200);
    expect(response.json().categoryId).toBe('cat_food');
    const audit = await app.inject({ method: 'GET', url: '/v1/books/book_home/audit-events', headers: as('user_ca') });
    expect(audit.json().items[0].action).toBe('transaction.reclassified');
  });

  it('prevents a reviewer from creating or altering source amounts', async () => {
    const create = await app.inject({ method: 'POST', url: '/v1/books/book_home/transactions', headers: { ...as('user_ca'), 'content-type': 'application/json' }, payload: { kind: 'expense', amountMinor: '-10000', occurredAt: '2026-08-26T10:00:00.000Z' } });
    expect(create.statusCode).toBe(403);
    const mutate = await app.inject({ method: 'PATCH', url: '/v1/books/book_home/transactions/tx_5', headers: { ...as('user_ca'), 'content-type': 'application/json' }, payload: { amountMinor: '-1' } });
    expect(mutate.statusCode).toBe(403);
  });

  it('deduplicates retried SMS ingestion by workspace and source hash', async () => {
    const payload = { sourceType: 'sms', sourceHash: 'sha256:one-financial-event', kind: 'expense', amountMinor: '-49900', merchant: 'UPI MERCHANT', occurredAt: '2026-08-26T10:00:00.000Z' };
    const headers = { ...as('user_owner'), 'content-type': 'application/json', 'idempotency-key': 'sms-device-1-message-1' };
    const first = await app.inject({ method: 'POST', url: '/v1/books/book_arjun/ingestion-events', headers, payload });
    const second = await app.inject({ method: 'POST', url: '/v1/books/book_arjun/ingestion-events', headers, payload });
    expect(first.statusCode).toBe(201);
    expect(second.statusCode).toBe(200);
    expect(second.json().duplicate).toBe(true);
    expect(second.json().transactionId).toBe(first.json().transactionId);
  });

  it('serializes money as integer strings and computes exact summary totals', async () => {
    const response = await app.inject({ method: 'GET', url: '/v1/books/book_arjun/summary', headers: as('user_owner') });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toMatchObject({ incomeMinor: '58786700', spentMinor: '3824000', savedMinor: '54962700', pendingReview: 1 });
  });
});
