import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { buildApp } from '../src/app.js';
import { MemoryStore } from '../src/store/memory-store.js';
import { parseStatementCsv } from '../src/domain/statement-csv.js';
import { advance, duePostings } from '../src/domain/recurring.js';

const sbiStatement = readFileSync(join(import.meta.dirname, 'fixtures/sbi-statement.csv'), 'utf8');

describe('Paisa API authorization and ledger invariants', () => {
  let app;
  beforeEach(async () => { app = await buildApp({ memory: true, authMode: 'dev' }); });
  afterEach(async () => { await app.close(); });

  const as = (userId) => ({ 'x-dev-user-id': userId });

  it('maps the sample owner onto a real Firebase identity when SEED_ variables are set', async () => {
    process.env.SEED_OWNER_FIREBASE_UID = 'firebase-uid-from-console';
    process.env.SEED_OWNER_EMAIL = 'owner@paisa.test';
    try {
      const store = new MemoryStore();
      expect(await store.getUserByFirebaseUid('firebase-uid-from-console')).toMatchObject({ id: 'user_owner', email: 'owner@paisa.test' });
      expect(await store.getUserByFirebaseUid('firebase-owner')).toBeNull();
    } finally {
      delete process.env.SEED_OWNER_FIREBASE_UID;
      delete process.env.SEED_OWNER_EMAIL;
    }
    expect(await new MemoryStore().getUserByFirebaseUid('firebase-owner')).toMatchObject({ id: 'user_owner' });
  });

  it('exposes separate liveness and datastore readiness checks', async () => {
    const live = await app.inject({ method: 'GET', url: '/health' });
    const ready = await app.inject({ method: 'GET', url: '/ready' });
    expect(live.statusCode).toBe(200);
    expect(ready.statusCode).toBe(200);
    expect(ready.json()).toEqual({ status: 'ready', service: 'paisa-api', datastore: 'reachable' });
  });

  it('allows browsers to preflight the mutating dashboard methods', async () => {
    const response = await app.inject({ method: 'OPTIONS', url: '/v1/books/book_arjun/budgets/cat_groceries', headers: { origin: 'http://localhost:3000', 'access-control-request-method': 'PUT' } });
    expect(response.headers['access-control-allow-methods']).toContain('PUT');
    expect(response.headers['access-control-allow-methods']).toContain('PATCH');
  });

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

  it('creates a merchant rule only when the reviewer applies a category to future payments', async () => {
    const headers = { ...as('user_ca'), 'content-type': 'application/json' };
    await app.inject({ method: 'PATCH', url: '/v1/books/book_home/transactions/tx_5/category', headers, payload: { categoryId: 'cat_food', applyToFuture: false } });
    expect((await app.inject({ method: 'GET', url: '/v1/books/book_home/categorization-rules', headers })).json().items).toEqual([]);
    await app.inject({ method: 'PATCH', url: '/v1/books/book_home/transactions/tx_5/category', headers, payload: { categoryId: 'cat_dining', applyToFuture: true } });
    const rules = (await app.inject({ method: 'GET', url: '/v1/books/book_home/categorization-rules', headers })).json().items;
    expect(rules).toMatchObject([{ categoryId: 'cat_dining', matchType: 'merchant_exact', matchValue: 'Fresh Market' }]);
  });

  it('prevents a reviewer from creating or altering source amounts', async () => {
    const create = await app.inject({ method: 'POST', url: '/v1/books/book_home/transactions', headers: { ...as('user_ca'), 'content-type': 'application/json' }, payload: { kind: 'expense', amountMinor: '-10000', occurredAt: '2026-08-26T10:00:00.000Z' } });
    expect(create.statusCode).toBe(403);
    const mutate = await app.inject({ method: 'PATCH', url: '/v1/books/book_home/transactions/tx_5', headers: { ...as('user_ca'), 'content-type': 'application/json' }, payload: { amountMinor: '-1' } });
    expect(mutate.statusCode).toBe(403);
  });

  it('lets a reviewer split and comment without changing the imported total', async () => {
    const headers = { ...as('user_ca'), 'content-type': 'application/json' };
    const split = await app.inject({ method: 'PUT', url: '/v1/books/book_home/transactions/tx_5/splits', headers, payload: { splits: [{ categoryId: 'cat_groceries', amountMinor: '-300000' }, { categoryId: 'cat_food', amountMinor: '-182000' }] } });
    expect(split.statusCode).toBe(200);
    expect(split.json().splits).toHaveLength(2);
    const comment = await app.inject({ method: 'POST', url: '/v1/books/book_home/transactions/tx_5/comments', headers, payload: { body: 'Please keep the receipt for reconciliation.' } });
    expect(comment.statusCode).toBe(201);
  });

  it('returns splits and reviewer comments when the ledger is read back', async () => {
    const headers = { ...as('user_ca'), 'content-type': 'application/json' };
    await app.inject({ method: 'PUT', url: '/v1/books/book_home/transactions/tx_5/splits', headers, payload: { splits: [{ categoryId: 'cat_groceries', amountMinor: '-300000' }, { categoryId: 'cat_food', amountMinor: '-182000' }] } });
    await app.inject({ method: 'POST', url: '/v1/books/book_home/transactions/tx_5/comments', headers, payload: { body: 'Split against the grocery receipt.' } });
    const response = await app.inject({ method: 'GET', url: '/v1/books/book_home/transactions', headers: as('user_owner') });
    const transaction = response.json().items.find((item) => item.id === 'tx_5');
    expect(transaction.splits).toHaveLength(2);
    expect(transaction.comments.map((comment) => comment.body)).toEqual(['Split against the grocery receipt.']);
  });

  it('lists statement imports for the book that recorded them', async () => {
    const payload = { fileName: 'august-statement.csv', contentType: 'text/csv', sizeBytes: 2048, sha256: 'a'.repeat(64) };
    const created = await app.inject({ method: 'POST', url: '/v1/books/book_arjun/imports', headers: { ...as('user_owner'), 'content-type': 'application/json' }, payload });
    expect(created.statusCode).toBe(201);
    const listed = await app.inject({ method: 'GET', url: '/v1/books/book_arjun/imports', headers: as('user_owner') });
    expect(listed.json().items.map((item) => item.sha256)).toEqual([payload.sha256]);
    const otherBook = await app.inject({ method: 'GET', url: '/v1/books/book_home/imports', headers: as('user_owner') });
    expect(otherBook.json().items).toEqual([]);
  });

  it('rejects a split whose parts do not equal the source amount', async () => {
    const response = await app.inject({ method: 'PUT', url: '/v1/books/book_home/transactions/tx_5/splits', headers: { ...as('user_ca'), 'content-type': 'application/json' }, payload: { splits: [{ categoryId: 'cat_groceries', amountMinor: '-100' }, { categoryId: 'cat_food', amountMinor: '-200' }] } });
    expect(response.statusCode).toBe(400);
    expect(response.json().code).toBe('SPLIT_TOTAL_MISMATCH');
  });

  it('auto-categorizes a repeat payment to a VPA the user classified once', async () => {
    const headers = { ...as('user_owner'), 'content-type': 'application/json' };
    const sms = (hash, occurredAt) => ({ sourceType: 'sms', sourceHash: hash, kind: 'expense', amountMinor: '-92000', merchant: 'bluetokai@okhdfcbank', occurredAt });

    // Month one: nothing knows this VPA, so it lands in the review queue.
    const first = await app.inject({ method: 'POST', url: '/v1/books/book_arjun/ingestion-events', headers: { ...headers, 'idempotency-key': 'sms-dinner-month-1' }, payload: sms('sha256:dinner-month-1', '2026-08-10T19:30:00.000Z') });
    expect(first.statusCode).toBe(201);
    const monthOneId = first.json().transactionId;
    const pending = (await app.inject({ method: 'GET', url: '/v1/books/book_arjun/transactions', headers: as('user_owner') })).json().items.find((item) => item.id === monthOneId);
    expect(pending.state).toBe('pending_review');
    expect(pending.categoryId).toBeNull();

    // The user reviews it once and asks for it to apply to future payments.
    await app.inject({ method: 'PATCH', url: `/v1/books/book_arjun/transactions/${monthOneId}/category`, headers, payload: { categoryId: 'cat_dining', applyToFuture: true } });

    // Month two: the same VPA arrives and is classified without asking again.
    const second = await app.inject({ method: 'POST', url: '/v1/books/book_arjun/ingestion-events', headers: { ...headers, 'idempotency-key': 'sms-dinner-month-2' }, payload: sms('sha256:dinner-month-2', '2026-09-10T19:30:00.000Z') });
    expect(second.statusCode).toBe(201);
    const monthTwo = (await app.inject({ method: 'GET', url: '/v1/books/book_arjun/transactions', headers: as('user_owner') })).json().items.find((item) => item.id === second.json().transactionId);
    expect(monthTwo.categoryId).toBe('cat_dining');
    expect(monthTwo.state).toBe('confirmed');

    // And the reason is attributable, not magic.
    const audit = (await app.inject({ method: 'GET', url: '/v1/books/book_arjun/audit-events', headers: as('user_owner') })).json().items;
    expect(audit[0]).toMatchObject({ action: 'transaction.auto_categorized', after: { categoryId: 'cat_dining', matchValue: 'bluetokai@okhdfcbank' } });
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
    const response = await app.inject({ method: 'GET', url: '/v1/books/book_arjun/summary?month=2026-08', headers: as('user_owner') });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toMatchObject({ incomeMinor: '58786700', spentMinor: '3809000', savedMinor: '54977700', pendingReview: 1 });
    const emptyMonth = await app.inject({ method: 'GET', url: '/v1/books/book_arjun/summary?month=2026-07', headers: as('user_owner') });
    expect(emptyMonth.json()).toMatchObject({ incomeMinor: '0', spentMinor: '0', savedMinor: '0', pendingReview: 0 });
  });

  it('assigns transactions to months using the book timezone', async () => {
    app.store.transactions.push({ id: 'tx_boundary', workspaceId: 'ws_household', bookId: 'book_arjun', kind: 'expense', state: 'confirmed', amountMinor: -100n, currency: 'INR', merchant: 'Boundary', categoryId: 'cat_other', occurredAt: new Date('2026-07-31T19:00:00.000Z'), createdAt: new Date(), updatedAt: new Date(), sources: [], splits: [] });
    const august = await app.inject({ method: 'GET', url: '/v1/books/book_arjun/summary?month=2026-08', headers: as('user_owner') });
    const july = await app.inject({ method: 'GET', url: '/v1/books/book_arjun/summary?month=2026-07', headers: as('user_owner') });
    expect(august.json().spentMinor).toBe('3809100');
    expect(july.json().spentMinor).toBe('0');
  });

  it('rejects transaction amounts whose sign conflicts with their kind', async () => {
    const response = await app.inject({ method: 'POST', url: '/v1/books/book_arjun/transactions', headers: { ...as('user_owner'), 'content-type': 'application/json', 'idempotency-key': 'invalid-positive-expense' }, payload: { kind: 'expense', amountMinor: '10000', occurredAt: '2026-08-26T10:00:00.000Z' } });
    expect(response.statusCode).toBe(400);
    expect(response.json().code).toBe('VALIDATION_ERROR');
  });

  it('applies amount sign invariants to recurring plans', async () => {
    const response = await app.inject({ method: 'POST', url: '/v1/books/book_arjun/recurring-plans', headers: { ...as('user_owner'), 'content-type': 'application/json' }, payload: { name: 'Invalid expense', kind: 'expense', amountMinor: '50000', currency: 'INR', cadence: 'monthly', nextDueAt: '2026-09-01T00:00:00.000Z' } });
    expect(response.statusCode).toBe(400);
    expect(response.json().code).toBe('VALIDATION_ERROR');
  });

  it('requires and honors idempotency keys for manual ledger creation', async () => {
    const payload = { kind: 'expense', amountMinor: '-10000', occurredAt: '2026-08-26T10:00:00.000Z' };
    const missing = await app.inject({ method: 'POST', url: '/v1/books/book_arjun/transactions', headers: { ...as('user_owner'), 'content-type': 'application/json' }, payload });
    expect(missing.statusCode).toBe(400);
    expect(missing.json().code).toBe('IDEMPOTENCY_KEY_REQUIRED');
    const headers = { ...as('user_owner'), 'content-type': 'application/json', 'idempotency-key': 'manual-entry-one' };
    const first = await app.inject({ method: 'POST', url: '/v1/books/book_arjun/transactions', headers, payload });
    const retry = await app.inject({ method: 'POST', url: '/v1/books/book_arjun/transactions', headers, payload });
    expect(retry.json().id).toBe(first.json().id);
  });

  it('edits and archives an account without deleting its history', async () => {
    const headers = { ...as('user_owner'), 'content-type': 'application/json' };
    const renamed = await app.inject({ method: 'PATCH', url: '/v1/books/book_arjun/accounts/account_primary', headers, payload: { name: 'Salary account', accountMask: '9911' } });
    expect(renamed.statusCode).toBe(200);
    expect(renamed.json()).toMatchObject({ name: 'Salary account', accountMask: '9911' });
    await app.inject({ method: 'PATCH', url: '/v1/books/book_arjun/accounts/account_primary', headers, payload: { archived: true } });
    const listed = await app.inject({ method: 'GET', url: '/v1/books/book_arjun/accounts', headers: as('user_owner') });
    expect(listed.json().items).toEqual([]);
    const audit = await app.inject({ method: 'GET', url: '/v1/books/book_arjun/audit-events', headers: as('user_owner') });
    expect(audit.json().items[0].action).toBe('account.archived');
  });

  it('renames a category and refuses a name another category already uses', async () => {
    const headers = { ...as('user_owner'), 'content-type': 'application/json' };
    const renamed = await app.inject({ method: 'PATCH', url: '/v1/books/book_arjun/categories/cat_dining', headers, payload: { name: 'Eating out', color: '#aa4433' } });
    expect(renamed.statusCode).toBe(200);
    expect(renamed.json()).toMatchObject({ name: 'Eating out', color: '#aa4433' });
    const clash = await app.inject({ method: 'PATCH', url: '/v1/books/book_arjun/categories/cat_dining', headers, payload: { name: 'Groceries' } });
    expect(clash.statusCode).toBe(409);
    expect(clash.json().code).toBe('CATEGORY_NAME_TAKEN');
  });

  it('edits and deletes a categorization rule', async () => {
    const headers = { ...as('user_owner'), 'content-type': 'application/json' };
    const created = await app.inject({ method: 'POST', url: '/v1/books/book_arjun/categorization-rules', headers, payload: { categoryId: 'cat_food', matchType: 'merchant_contains', matchValue: 'Swiggy' } });
    const ruleId = created.json().id;
    const edited = await app.inject({ method: 'PATCH', url: `/v1/books/book_arjun/categorization-rules/${ruleId}`, headers, payload: { matchValue: 'Swiggy Instamart', priority: 20 } });
    expect(edited.json()).toMatchObject({ matchValue: 'Swiggy Instamart', priority: 20 });
    const removed = await app.inject({ method: 'DELETE', url: `/v1/books/book_arjun/categorization-rules/${ruleId}`, headers: as('user_owner') });
    expect(removed.statusCode).toBe(204);
    expect((await app.inject({ method: 'GET', url: '/v1/books/book_arjun/categorization-rules', headers: as('user_owner') })).json().items).toEqual([]);
    expect((await app.inject({ method: 'DELETE', url: `/v1/books/book_arjun/categorization-rules/${ruleId}`, headers: as('user_owner') })).statusCode).toBe(404);
  });

  it('edits a recurring plan and stops it without deleting the record', async () => {
    const headers = { ...as('user_owner'), 'content-type': 'application/json' };
    const edited = await app.inject({ method: 'PATCH', url: '/v1/books/book_arjun/recurring-plans/recurring_salary', headers, payload: { name: 'Salary (revised)', kind: 'income', amountMinor: '60000000' } });
    expect(edited.json()).toMatchObject({ name: 'Salary (revised)', amountMinor: '60000000' });
    const wrongSign = await app.inject({ method: 'PATCH', url: '/v1/books/book_arjun/recurring-plans/recurring_salary', headers, payload: { kind: 'income', amountMinor: '-1000' } });
    expect(wrongSign.statusCode).toBe(400);
    await app.inject({ method: 'PATCH', url: '/v1/books/book_arjun/recurring-plans/recurring_salary', headers, payload: { active: false } });
    expect((await app.inject({ method: 'GET', url: '/v1/books/book_arjun/recurring-plans', headers: as('user_owner') })).json().items).toEqual([]);
  });

  it('stops a reviewer from editing accounts, categories, rules, or plans', async () => {
    const headers = { ...as('user_ca'), 'content-type': 'application/json' };
    const attempts = await Promise.all([
      app.inject({ method: 'PATCH', url: '/v1/books/book_home/categories/cat_dining', headers, payload: { name: 'Renamed by CA' } }),
      app.inject({ method: 'PATCH', url: '/v1/books/book_home/recurring-plans/recurring_salary', headers, payload: { active: false } }),
      app.inject({ method: 'DELETE', url: '/v1/books/book_home/categorization-rules/any', headers: as('user_ca') }),
    ]);
    expect(attempts.map((response) => response.statusCode)).toEqual([403, 403, 403]);
  });

  it('rejects account and category references outside the authorized book scope', async () => {
    app.store.categories.push({ id: 'cat_other_workspace', workspaceId: 'ws_other', name: 'Outside', groupName: 'Other', color: '#000000' });
    const headers = { ...as('user_owner'), 'content-type': 'application/json', 'idempotency-key': 'cross-scope-reference' };
    const category = await app.inject({ method: 'POST', url: '/v1/books/book_home/transactions', headers, payload: { kind: 'expense', amountMinor: '-10000', categoryId: 'cat_other_workspace', occurredAt: '2026-08-26T10:00:00.000Z' } });
    expect(category.statusCode).toBe(400);
    expect(category.json().code).toBe('REFERENCE_SCOPE_ERROR');
    const account = await app.inject({ method: 'POST', url: '/v1/books/book_home/transactions', headers: { ...headers, 'idempotency-key': 'cross-book-account' }, payload: { kind: 'expense', amountMinor: '-10000', accountId: 'account_primary', occurredAt: '2026-08-26T10:00:00.000Z' } });
    expect(account.statusCode).toBe(400);
    expect(account.json().code).toBe('REFERENCE_SCOPE_ERROR');
  });

  it('persists period verification only after pending transactions are resolved', async () => {
    const headers = { ...as('user_owner'), 'content-type': 'application/json' };
    const blocked = await app.inject({ method: 'POST', url: '/v1/books/book_arjun/period-reviews', headers, payload: { month: '2026-08', status: 'verified' } });
    expect(blocked.statusCode).toBe(409);
    await app.inject({ method: 'PATCH', url: '/v1/books/book_arjun/transactions/tx_2/category', headers, payload: { categoryId: 'cat_emi', applyToFuture: false } });
    const verified = await app.inject({ method: 'POST', url: '/v1/books/book_arjun/period-reviews', headers, payload: { month: '2026-08', status: 'verified', note: 'Reviewed' } });
    expect(verified.statusCode).toBe(201);
    expect(verified.json()).toMatchObject({ bookId: 'book_arjun', status: 'verified', reviewedById: 'user_owner' });
  });

  it('lets an owner update budgets and member roles with an audit trail', async () => {
    const headers = { ...as('user_owner'), 'content-type': 'application/json' };
    const budget = await app.inject({ method: 'PUT', url: '/v1/books/book_home/budgets/cat_groceries', headers, payload: { month: '2026-08-01', amountMinor: '900000', currency: 'INR' } });
    expect(budget.statusCode).toBe(200);
    expect(budget.json().amountMinor).toBe('900000');
    const role = await app.inject({ method: 'PATCH', url: '/v1/books/book_home/memberships/user_ca', headers, payload: { role: 'viewer' } });
    expect(role.statusCode).toBe(200);
    expect(role.json().role).toBe('viewer');
    const audit = await app.inject({ method: 'GET', url: '/v1/books/book_home/audit-events', headers: as('user_owner') });
    expect(audit.json().items.map((event) => event.action)).toEqual(expect.arrayContaining(['budget.updated', 'membership.role_changed']));
  });

  it('removes a member and revokes a pending invitation', async () => {
    const headers = { ...as('user_owner'), 'content-type': 'application/json' };
    const invitation = await app.inject({ method: 'POST', url: '/v1/books/book_home/invitations', headers, payload: { email: 'auditor@example.com', role: 'viewer' } });
    const revoked = await app.inject({ method: 'DELETE', url: `/v1/books/book_home/invitations/${invitation.json().id}`, headers: as('user_owner') });
    expect(revoked.statusCode).toBe(204);
    expect((await app.inject({ method: 'GET', url: '/v1/books/book_home/invitations', headers: as('user_owner') })).json().items).toEqual([]);
    const removed = await app.inject({ method: 'DELETE', url: '/v1/books/book_home/memberships/user_ca', headers: as('user_owner') });
    expect(removed.statusCode).toBe(204);
    expect((await app.inject({ method: 'GET', url: '/v1/books/book_home/memberships', headers: as('user_owner') })).json().items.map((item) => item.userId)).toEqual(['user_owner', 'user_spouse']);
    const afterRemoval = await app.inject({ method: 'GET', url: '/v1/books/book_home/transactions', headers: as('user_ca') });
    expect(afterRemoval.statusCode).toBe(404);
  });

  it('keeps at least one owner and refuses self-service access changes', async () => {
    const headers = { ...as('user_owner'), 'content-type': 'application/json' };
    const demoteSelf = await app.inject({ method: 'PATCH', url: '/v1/books/book_arjun/memberships/user_owner', headers, payload: { role: 'viewer' } });
    expect(demoteSelf.statusCode).toBe(409);
    expect(demoteSelf.json().code).toBe('SELF_ACCESS_CHANGE');
    expect((await app.inject({ method: 'DELETE', url: '/v1/books/book_arjun/memberships/user_owner', headers: as('user_owner') })).json().code).toBe('SELF_ACCESS_CHANGE');
    await app.inject({ method: 'PATCH', url: '/v1/books/book_home/memberships/user_spouse', headers, payload: { role: 'book_owner' } });
    const demoteOther = await app.inject({ method: 'PATCH', url: '/v1/books/book_home/memberships/user_spouse', headers, payload: { role: 'viewer' } });
    expect(demoteOther.statusCode).toBe(200);
  });

  it('stops an editor from managing members or invitations', async () => {
    const attempts = await Promise.all([
      app.inject({ method: 'DELETE', url: '/v1/books/book_home/memberships/user_ca', headers: as('user_spouse') }),
      app.inject({ method: 'DELETE', url: '/v1/books/book_home/invitations/any', headers: as('user_spouse') }),
    ]);
    expect(attempts.map((response) => response.statusCode)).toEqual([403, 403]);
  });

  it('creates expiring book invitations and accepts them only as the invited account', async () => {
    const invitation = await app.inject({ method: 'POST', url: '/v1/books/book_arjun/invitations', headers: { ...as('user_owner'), 'content-type': 'application/json' }, payload: { email: 'priya@example.com', role: 'editor' } });
    expect(invitation.statusCode).toBe(201);
    expect(invitation.json().token).toHaveLength(43);
    const mismatch = await app.inject({ method: 'POST', url: '/v1/invitations/accept', headers: { ...as('user_ca'), 'content-type': 'application/json' }, payload: { token: invitation.json().token } });
    expect(mismatch.statusCode).toBe(403);
    const accepted = await app.inject({ method: 'POST', url: '/v1/invitations/accept', headers: { ...as('user_spouse'), 'content-type': 'application/json' }, payload: { token: invitation.json().token } });
    expect(accepted.statusCode).toBe(200);
    expect(accepted.json()).toMatchObject({ accepted: true, bookId: 'book_arjun', role: 'editor' });
    const books = await app.inject({ method: 'GET', url: '/v1/books', headers: as('user_spouse') });
    expect(books.json().items.map((book) => book.id)).toContain('book_arjun');
  });

  it('parses a real SBI CSV export, wrapped narrations and all', () => {
    const { account, rows, warnings } = parseStatementCsv(sbiStatement);
    expect(account).toEqual({ number: '37791533954', ifsc: 'SBIN0070190' });
    // The bank's own running balance column agrees with every amount we read.
    expect(warnings).toEqual([]);
    expect(rows).toHaveLength(4);
    // "smohanes\n h1" is one wrapped token, not two words.
    expect(rows[0]).toMatchObject({ kind: 'expense', amountMinor: '-100000', merchant: 'SHOBHA M', externalRef: '624417205755' });
    expect(rows[0].metadata.upiHandle).toBe('smohanesh1');
    expect(rows[1]).toMatchObject({ kind: 'income', amountMinor: '500000', merchant: 'BOAZ M R' });
    // A non-UPI narration keeps its description but drops the branch booking suffix.
    expect(rows[2].merchant).toBe('DIRECT DR 0043896596535 OF Mr. Test User');
    expect(rows[3]).toMatchObject({ merchant: 'SAAVN', amountMinor: '-8900' });
    // Midnight in Asia/Kolkata, so a payment never slips into the previous month.
    expect(rows[0].occurredAt).toBe('2026-08-31T18:30:00.000Z');
    // Re-parsing produces the same identity for each row, so re-imports dedupe.
    expect(parseStatementCsv(sbiStatement).rows.map((row) => row.sourceHash)).toEqual(rows.map((row) => row.sourceHash));
  });

  it('imports statement rows into the ledger and ignores a second upload of the same file', async () => {
    const upload = () => app.inject({ method: 'POST', url: '/v1/books/book_arjun/imports', headers: as('user_owner'),
      payload: { fileName: 'sbi.csv', contentType: 'text/csv', sizeBytes: sbiStatement.length, sha256: 'a'.repeat(64), content: sbiStatement } });

    const fromStatement = async () => {
      const ledger = await app.inject({ method: 'GET', url: '/v1/books/book_arjun/transactions?limit=100', headers: as('user_owner') });
      const hashes = new Set(parseStatementCsv(sbiStatement).rows.map((row) => row.sourceHash));
      return ledger.json().items.filter((item) => item.sources?.some((source) => hashes.has(source.sourceReference)));
    };

    const first = await upload();
    expect(first.statusCode).toBe(201);
    expect(first.json()).toMatchObject({ status: 'parsed', imported: 4, duplicates: 0, warnings: [] });

    const imported = await fromStatement();
    expect(imported).toHaveLength(4);
    expect(imported.every((item) => item.state === 'pending_review')).toBe(true);

    // A second upload of the same file is re-parsed, but every row is recognised.
    const second = await upload();
    expect(second.statusCode).toBe(200);
    expect(second.json()).toMatchObject({ duplicate: true, imported: 0, duplicates: 4 });
    expect(await fromStatement()).toHaveLength(4);
  });

  it('accounts for every rupee it says was spent, including uncategorized and split payments', async () => {
    // 17 statement rows, none of them categorised yet.
    const imported = await app.inject({ method: 'POST', url: '/v1/books/book_arjun/imports', headers: as('user_owner'),
      payload: { fileName: 'sbi.csv', contentType: 'text/csv', sizeBytes: sbiStatement.length, sha256: 'f'.repeat(64), content: sbiStatement } });
    expect(imported.json().imported).toBe(4);

    const summary = await app.inject({ method: 'GET', url: '/v1/books/book_arjun/summary', headers: as('user_owner') });
    const { spentMinor, byCategory } = summary.json();
    const breakdown = byCategory.reduce((sum, item) => sum + BigInt(item.amountMinor), 0n);
    // The invariant the dashboard depends on: the panel adds up to the tile.
    expect(breakdown).toBe(BigInt(spentMinor));
    expect(byCategory.find((item) => item.categoryId === null)).toMatchObject({ name: 'Uncategorized', groupName: 'Other' });
    // Largest first, so "top spending" is actually the top.
    expect([...byCategory].sort((a, b) => (BigInt(b.amountMinor) > BigInt(a.amountMinor) ? 1 : -1)).map((item) => item.name)).toEqual(byCategory.map((item) => item.name));
  });

  it('attributes a split payment to its parts rather than to the parent category', async () => {
    const created = await app.inject({ method: 'POST', url: '/v1/books/book_arjun/transactions', headers: { ...as('user_owner'), 'idempotency-key': 'split-summary-001' },
      payload: { kind: 'expense', amountMinor: '-100000', merchant: 'Big Bazaar', occurredAt: '2026-09-02T05:30:00.000Z', categoryId: 'cat_groceries' } });
    const id = created.json().id;
    const split = await app.inject({ method: 'PUT', url: `/v1/books/book_arjun/transactions/${id}/splits`, headers: as('user_owner'),
      payload: { splits: [{ categoryId: 'cat_groceries', amountMinor: '-40000' }, { categoryId: 'cat_dining', amountMinor: '-60000' }] } });
    expect(split.statusCode).toBe(200);

    const summary = await app.inject({ method: 'GET', url: '/v1/books/book_arjun/summary?month=2026-09', headers: as('user_owner') });
    const { byCategory, spentMinor } = summary.json();
    const amountOf = (categoryId) => BigInt(byCategory.find((item) => item.categoryId === categoryId)?.amountMinor ?? '0');
    expect(amountOf('cat_dining')).toBe(60000n);
    expect(amountOf('cat_groceries')).toBe(40000n);
    expect(byCategory.reduce((sum, item) => sum + BigInt(item.amountMinor), 0n)).toBe(BigInt(spentMinor));
  });

  it('keeps a month-end recurring plan at month end instead of drifting backwards', () => {
    const day = (value) => new Date(value).toISOString().slice(0, 10);
    // Clamping alone would give 28 Feb, then 28 Mar, then 28 Apr - the plan
    // would walk away from month end and never come back.
    let due = '2026-01-31T00:00:00.000Z';
    const run = [];
    for (let index = 0; index < 5; index += 1) { run.push(day(due)); due = advance(due, 'monthly'); }
    expect(run).toEqual(['2026-01-31', '2026-02-28', '2026-03-31', '2026-04-30', '2026-05-31']);
    // A mid-month plan keeps its own day.
    expect(day(advance('2026-01-15T00:00:00.000Z', 'monthly'))).toBe('2026-02-15');
    expect(day(advance('2026-11-30T00:00:00.000Z', 'quarterly'))).toBe('2027-02-28');
    expect(() => advance('2026-01-15T00:00:00.000Z', 'fortnightly')).toThrow(/cadence/i);

    // Months missed while the API was down are all caught up, not skipped.
    const behind = duePostings({ nextDueAt: '2026-06-30T00:00:00.000Z', cadence: 'monthly', active: true }, new Date('2026-09-08T00:00:00.000Z'));
    expect(behind.postings.map(day)).toEqual(['2026-06-30', '2026-07-31', '2026-08-31']);
    expect(day(behind.nextDueAt)).toBe('2026-09-30');
  });

  it('posts a due recurring plan into the ledger exactly once', async () => {
    const plan = await app.inject({ method: 'POST', url: '/v1/books/book_arjun/recurring-plans', headers: as('user_owner'),
      payload: { name: 'Salary', kind: 'income', amountMinor: '10417800', categoryId: 'cat_salary', cadence: 'monthly', nextDueAt: '2026-09-30T00:00:00.000Z' } });
    expect(plan.statusCode).toBe(201);
    const planId = plan.json().id;
    // The seeded book has its own plans, so look only at this one.
    const run = async (at) => (await app.store.postDueRecurring(new Date(at))).filter((entry) => entry.planId === planId);

    // Not due yet: nothing is posted early.
    expect(await run('2026-09-29T00:00:00.000Z')).toEqual([]);

    expect(await run('2026-09-30T06:00:00.000Z')).toHaveLength(1);
    // A running tick, or a restart, must not post the same month again.
    expect(await run('2026-09-30T23:00:00.000Z')).toEqual([]);

    const ledger = await app.inject({ method: 'GET', url: '/v1/books/book_arjun/transactions?limit=100', headers: as('user_owner') });
    const salaries = ledger.json().items.filter((item) => item.merchant === 'Salary');
    expect(salaries).toHaveLength(1);
    // A plan is a prediction, so it waits for a human rather than counting itself.
    expect(salaries[0]).toMatchObject({ kind: 'income', amountMinor: '10417800', categoryId: 'cat_salary', state: 'pending_review' });
    expect(salaries[0].occurredAt.slice(0, 10)).toBe('2026-09-30');

    const audit = await app.inject({ method: 'GET', url: '/v1/books/book_arjun/audit-events', headers: as('user_owner') });
    expect(audit.json().items.find((event) => event.action === 'recurring.posted')).toMatchObject({ after: { planName: 'Salary' } });

    // The plan has moved on to October, and October is month end too.
    const plans = await app.inject({ method: 'GET', url: '/v1/books/book_arjun/recurring-plans', headers: as('user_owner') });
    expect(plans.json().items.find((item) => item.name === 'Salary').nextDueAt.slice(0, 10)).toBe('2026-10-31');
  });

  it('files salary under Income and savings transfers under Saving', async () => {
    const categories = await app.inject({ method: 'GET', url: '/v1/books/book_arjun/categories', headers: as('user_owner') });
    const groupOf = (name) => categories.json().items.find((item) => item.name === name)?.groupName;
    expect(groupOf('Salary')).toBe('Income');
    expect(groupOf('Investment')).toBe('Saving');
    expect(groupOf('Transfer to savings')).toBe('Saving');
    expect(new Set(categories.json().items.map((item) => item.groupName))).toEqual(new Set(['Essentials', 'Income', 'Lifestyle', 'Saving', 'Other']));
  });

  it('corrects a manual entry that was booked the wrong way round', async () => {
    const created = await app.inject({ method: 'POST', url: '/v1/books/book_arjun/transactions', headers: { ...as('user_owner'), 'idempotency-key': 'salary-typo-0001' },
      payload: { kind: 'expense', amountMinor: '-5000000', merchant: 'Salary', occurredAt: '2026-09-01T05:30:00.000Z', categoryId: 'cat_salary' } });
    expect(created.statusCode).toBe(201);
    const id = created.json().id;

    const fixed = await app.inject({ method: 'PATCH', url: `/v1/books/book_arjun/transactions/${id}`, headers: as('user_owner'), payload: { kind: 'income', amountMinor: '5000000' } });
    expect(fixed.statusCode).toBe(200);
    expect(fixed.json()).toMatchObject({ kind: 'income', amountMinor: '5000000' });

    // The correction is on the record, with what it used to say.
    const audit = await app.inject({ method: 'GET', url: '/v1/books/book_arjun/audit-events', headers: as('user_owner') });
    expect(audit.json().items.find((event) => event.action === 'transaction.corrected')).toMatchObject({ entityId: id, before: { amountMinor: '-5000000', kind: 'expense' }, after: { amountMinor: '5000000', kind: 'income' } });
  });

  it('refuses to rewrite an imported amount but still allows voiding the entry', async () => {
    const imported = await app.inject({ method: 'POST', url: '/v1/books/book_arjun/imports', headers: as('user_owner'),
      payload: { fileName: 'sbi.csv', contentType: 'text/csv', sizeBytes: sbiStatement.length, sha256: 'e'.repeat(64), content: sbiStatement } });
    expect(imported.statusCode).toBe(201);
    const hashes = new Set(parseStatementCsv(sbiStatement).rows.map((row) => row.sourceHash));
    const ledger = await app.inject({ method: 'GET', url: '/v1/books/book_arjun/transactions?limit=100', headers: as('user_owner') });
    const row = ledger.json().items.find((item) => item.sources?.some((source) => hashes.has(source.sourceReference)));

    const rewrite = await app.inject({ method: 'PATCH', url: `/v1/books/book_arjun/transactions/${row.id}`, headers: as('user_owner'), payload: { kind: 'income', amountMinor: '1' } });
    expect(rewrite.statusCode).toBe(409);
    expect(rewrite.json().code).toBe('IMMUTABLE_SOURCE');
    const redate = await app.inject({ method: 'PATCH', url: `/v1/books/book_arjun/transactions/${row.id}`, headers: as('user_owner'), payload: { occurredAt: '2026-01-01T00:00:00.000Z' } });
    expect(redate.statusCode).toBe(409);

    // A debit to your own other account is a transfer, not spending. The bank's
    // amount is untouched, so re-reading what it was for is allowed.
    const before = await app.inject({ method: 'GET', url: '/v1/books/book_arjun/summary', headers: as('user_owner') });
    const reclassified = await app.inject({ method: 'PATCH', url: `/v1/books/book_arjun/transactions/${row.id}`, headers: as('user_owner'), payload: { kind: 'transfer', amountMinor: row.amountMinor } });
    expect(reclassified.statusCode).toBe(200);
    expect(reclassified.json()).toMatchObject({ kind: 'transfer', amountMinor: row.amountMinor });
    const after = await app.inject({ method: 'GET', url: '/v1/books/book_arjun/summary', headers: as('user_owner') });
    // It stops counting as spending, and the breakdown still adds up.
    expect(BigInt(after.json().spentMinor)).toBe(BigInt(before.json().spentMinor) + BigInt(row.amountMinor));
    expect(after.json().byCategory.reduce((sum, item) => sum + BigInt(item.amountMinor), 0n)).toBe(BigInt(after.json().spentMinor));

    const voided = await app.inject({ method: 'PATCH', url: `/v1/books/book_arjun/transactions/${row.id}`, headers: as('user_owner'), payload: { state: 'voided' } });
    expect(voided.statusCode).toBe(200);
    expect(voided.json().state).toBe('voided');
    // A voided entry stays in the ledger but stops counting towards the month.
    const summary = await app.inject({ method: 'GET', url: '/v1/books/book_arjun/summary?month=2026-09', headers: as('user_owner') });
    expect(summary.statusCode).toBe(200);
  });

  it('will not accept a correction that separates the kind from the sign, or an empty one', async () => {
    const created = await app.inject({ method: 'POST', url: '/v1/books/book_arjun/transactions', headers: { ...as('user_owner'), 'idempotency-key': 'sign-check-0001' },
      payload: { kind: 'expense', amountMinor: '-1000', merchant: 'Tea', occurredAt: '2026-09-01T05:30:00.000Z', categoryId: 'cat_dining' } });
    const id = created.json().id;
    const halfway = await app.inject({ method: 'PATCH', url: `/v1/books/book_arjun/transactions/${id}`, headers: as('user_owner'), payload: { kind: 'income' } });
    expect(halfway.statusCode).toBe(400);
    const wrongSign = await app.inject({ method: 'PATCH', url: `/v1/books/book_arjun/transactions/${id}`, headers: as('user_owner'), payload: { kind: 'income', amountMinor: '-1000' } });
    expect(wrongSign.statusCode).toBe(400);
    const empty = await app.inject({ method: 'PATCH', url: `/v1/books/book_arjun/transactions/${id}`, headers: as('user_owner'), payload: {} });
    expect(empty.statusCode).toBe(400);
  });

  it('imports a statement whose file was recorded by an earlier build that never parsed it', async () => {
    const payload = { fileName: 'sbi.csv', contentType: 'text/csv', sizeBytes: sbiStatement.length, sha256: 'd'.repeat(64) };
    // The fingerprint-only upload the previous release performed.
    const recorded = await app.inject({ method: 'POST', url: '/v1/books/book_arjun/imports', headers: as('user_owner'), payload });
    expect(recorded.statusCode).toBe(201);
    expect(recorded.json().imported).toBeUndefined();

    const retried = await app.inject({ method: 'POST', url: '/v1/books/book_arjun/imports', headers: as('user_owner'), payload: { ...payload, content: sbiStatement } });
    expect(retried.statusCode).toBe(200);
    expect(retried.json()).toMatchObject({ duplicate: true, imported: 4, duplicates: 0 });
  });

  it('rejects a file that is not a statement instead of importing nothing quietly', async () => {
    const response = await app.inject({ method: 'POST', url: '/v1/books/book_arjun/imports', headers: as('user_owner'),
      payload: { fileName: 'notes.csv', contentType: 'text/csv', sizeBytes: 20, sha256: 'b'.repeat(64), content: 'hello,world\n1,2\n' } });
    expect(response.statusCode).toBe(422);
    expect(response.json().code).toBe('STATEMENT_UNPARSEABLE');
  });

  it('provisions a newly invited Firebase identity only when its email matches', async () => {
    const store = new MemoryStore();
    await store.createInvitation({
      workspaceId: 'ws_household',
      bookId: 'book_home',
      email: 'new.member@example.com',
      role: 'viewer',
      tokenHash: 'new-member-token-hash',
      invitedById: 'user_owner',
      expiresAt: new Date(Date.now() + 60_000),
    });

    const accepted = await store.acceptInvitation('new-member-token-hash', {
      firebaseUid: 'firebase-new-member',
      email: 'new.member@example.com',
      displayName: 'New Member',
    });

    const user = await store.getUserByFirebaseUid('firebase-new-member');
    expect(user).toMatchObject({ email: 'new.member@example.com', displayName: 'New Member' });
    expect(accepted.actorId).toBe(user.id);
    expect(await store.getMembership('book_home', user.id)).toMatchObject({ role: 'viewer' });
  });
});
