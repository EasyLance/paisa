import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { buildApp } from '../src/app.js';
import { MemoryStore } from '../src/store/memory-store.js';
import { parseStatementCsv } from '../src/domain/statement.js';
import { advance, duePostings } from '../src/domain/recurring.js';
import { isPlatformAdmin } from '../src/domain/platform-admin.js';
import { DEFAULT_CATEGORIES } from '../src/domain/default-categories.js';
import { currentPeriodLabel, normaliseStartDay, periodRangeUtc } from '../src/domain/period.js';
import { deflateRawSync } from 'node:zlib';

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

  it('will not fall back to header-trusting dev auth when AUTH_MODE is unset', async () => {
    const saved = process.env.AUTH_MODE;
    delete process.env.AUTH_MODE;
    try {
      // No mode given anywhere: the default must be the one that checks tokens,
      // not the one where x-dev-user-id is enough to be the owner.
      const strict = await buildApp({ memory: true });
      try {
        const response = await strict.inject({ method: 'GET', url: '/v1/books', headers: { 'x-dev-user-id': 'user_owner' } });
        expect(response.statusCode).toBe(401);
        expect(response.json().code).toBe('UNAUTHENTICATED');
      } finally {
        await strict.close();
      }
    } finally {
      if (saved === undefined) delete process.env.AUTH_MODE; else process.env.AUTH_MODE = saved;
    }
  });

  it('refuses a statement with more rows than one request should write', async () => {
    const header = 'Date,Details,Ref No/Cheque No,Debit,Credit,Balance\n';
    const rows = Array.from({ length: 2001 }, (_, index) => `01/09/2026,"Payment ${index}",,1.00,,${100000 - index}.00`).join('\n');
    const content = `${header}${rows}\n`;
    const response = await app.inject({ method: 'POST', url: '/v1/books/book_arjun/imports', headers: as('user_owner'),
      payload: { fileName: 'huge.csv', contentType: 'text/csv', sizeBytes: content.length, sha256: '9'.repeat(64), content } });
    expect(response.statusCode).toBe(413);
    expect(response.json().code).toBe('STATEMENT_TOO_LARGE');
    // Nothing was written before it gave up.
    const ledger = await app.inject({ method: 'GET', url: '/v1/books/book_arjun/transactions?limit=100', headers: as('user_owner') });
    expect(ledger.json().items.some((item) => String(item.merchant).startsWith('Payment '))).toBe(false);
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
    expect(response.json()).toMatchObject({ incomeMinor: '58786700', spentMinor: '3809000', movedMinor: '0', balanceMinor: '54977700', pendingReview: 1 });
    const emptyMonth = await app.inject({ method: 'GET', url: '/v1/books/book_arjun/summary?month=2026-07', headers: as('user_owner') });
    expect(emptyMonth.json()).toMatchObject({ incomeMinor: '0', spentMinor: '0', movedMinor: '0', balanceMinor: '0', pendingReview: 0 });
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

  // Built here rather than committed: a real bank export is somebody's finances,
  // and the reader has to survive a genuine ZIP either way.
  function buildXlsx(rows) {
    const strings = [...new Set(rows.flat())];
    const sheet = `<worksheet><sheetData>${rows.map((row, rowIndex) => `<row r="${rowIndex + 1}">${row.map((cell, cellIndex) =>
      `<c r="${String.fromCharCode(65 + cellIndex)}${rowIndex + 1}" t="s"><v>${strings.indexOf(cell)}</v></c>`).join('')}</row>`).join('')}</sheetData></worksheet>`;
    const shared = `<sst>${strings.map((value) => `<si><t>${value.replaceAll('&', '&amp;').replaceAll('<', '&lt;')}</t></si>`).join('')}</sst>`;
    const members = [['xl/worksheets/sheet1.xml', sheet], ['xl/sharedStrings.xml', shared]];
    const locals = []; const central = []; let offset = 0;
    for (const [name, xml] of members) {
      const body = Buffer.from(xml, 'utf8'); const deflated = deflateRawSync(body);
      const local = Buffer.alloc(30); local.writeUInt32LE(0x04034b50, 0); local.writeUInt16LE(8, 8);
      local.writeUInt32LE(deflated.length, 18); local.writeUInt32LE(body.length, 22); local.writeUInt16LE(name.length, 26);
      const entry = Buffer.concat([local, Buffer.from(name), deflated]);
      const directory = Buffer.alloc(46); directory.writeUInt32LE(0x02014b50, 0); directory.writeUInt16LE(8, 10);
      directory.writeUInt32LE(deflated.length, 20); directory.writeUInt32LE(body.length, 24);
      directory.writeUInt16LE(name.length, 28); directory.writeUInt32LE(offset, 42);
      central.push(Buffer.concat([directory, Buffer.from(name)]));
      locals.push(entry); offset += entry.length;
    }
    const directory = Buffer.concat(central);
    const end = Buffer.alloc(22); end.writeUInt32LE(0x06054b50, 0);
    end.writeUInt16LE(members.length, 8); end.writeUInt16LE(members.length, 10);
    end.writeUInt32LE(directory.length, 12); end.writeUInt32LE(offset, 16);
    return Buffer.concat([...locals, directory, end]);
  }

  it('imports an HDFC spreadsheet export, whose columns and narrations differ from SBI', async () => {
    // HDFC names its columns Narration/Withdrawal/Deposit and hyphenates the
    // payee instead of using SBI's slashes. Same table, so the same pipeline.
    const workbook = buildXlsx([
      ['HDFC BANK Ltd.', '', '', '', '', '', ''],
      ['Account No :50100441721871   OTHER', '', '', '', '', '', ''],
      ['Date', 'Narration', 'Chq./Ref.No.', 'Value Dt', 'Withdrawal Amt.', 'Deposit Amt.', 'Closing Balance'],
      ['01/08/26', 'UPI-ROYAL CITY RESTAURAN-308987587270377A@CNRB-CNRB0003909-657908594940-PAID VIA', '0000657908594940', '01/08/26', '1901', '', '77584.15'],
      ['01/08/26', 'UPI-NANDU  KRISHNAN-NANDUKRISHNAN022-2@OKSBI-SBIN0070833-622170585125-UPI', '0000622170585125', '01/08/26', '', '650', '78234.15'],
      ['04/08/26', 'NEFT CR-HSBC0400002-UNTOLD STUDIOS PRIVATE LIMITED-JADHEER TP-HSBCN21673958319', '', '04/08/26', '', '118800', '197034.15'],
    ]);
    const content = workbook.toString('base64');
    const response = await app.inject({ method: 'POST', url: '/v1/books/book_arjun/imports', headers: as('user_owner'),
      payload: { fileName: 'hdfc.xlsx', contentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', sizeBytes: workbook.length, sha256: '7'.repeat(64), content } });
    expect(response.statusCode).toBe(201);
    // Every closing balance reconciles, which is the real proof the amounts read right.
    expect(response.json()).toMatchObject({ imported: 3, duplicates: 0, warnings: [], account: { number: '50100441721871' } });

    const ledger = await app.inject({ method: 'GET', url: '/v1/books/book_arjun/transactions?limit=100', headers: as('user_owner') });
    const byMerchant = Object.fromEntries(ledger.json().items.map((item) => [item.merchant, item]));
    expect(byMerchant['ROYAL CITY RESTAURAN']).toMatchObject({ kind: 'expense', amountMinor: '-190100' });
    // A hyphen inside the VPA must not leave half the handle as the payee name.
    expect(byMerchant['NANDU KRISHNAN']).toMatchObject({ kind: 'income', amountMinor: '65000' });
    // No VPA at all: the remitter, not the bank code or the reference.
    expect(byMerchant['UNTOLD STUDIOS PRIVATE LIMITED']).toMatchObject({ kind: 'income', amountMinor: '11880000' });
  });

  it('will not pretend to read a PDF statement', async () => {
    const response = await app.inject({ method: 'POST', url: '/v1/books/book_arjun/imports', headers: as('user_owner'),
      payload: { fileName: 'statement.pdf', contentType: 'application/pdf', sizeBytes: 1024, sha256: '8'.repeat(64), content: 'JVBERi0xLjQK' } });
    expect(response.statusCode).toBe(400);
    expect(JSON.stringify(response.json().details)).toContain('PDF');
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
    // The invariant the dashboard depends on: the panel accounts for everything
    // that left the account, spending and transfers out alike.
    expect(breakdown).toBe(BigInt(spentMinor) + BigInt(summary.json().movedMinor));
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

  it('gives a first-time Firebase identity its own household, invisible to everyone else', async () => {
    const store = new MemoryStore();
    const stranger = await store.provisionTenant({ firebaseUid: 'firebase-stranger', email: 'stranger@example.com', displayName: 'Ravi' });

    const books = await store.listBooks(stranger.id);
    expect(books.map((book) => [book.name, book.visibility, book.role]).sort((a, b) => a[0].localeCompare(b[0])))
      .toEqual([['Household', 'shared', 'book_owner'], ["Ravi's finances", 'private', 'book_owner']]);
    // Their own workspace, with its own copy of the starter categories.
    const workspaceId = books[0].workspaceId;
    expect(workspaceId).not.toBe('ws_household');
    expect(await store.listCategories(workspaceId)).toHaveLength(15);

    // Arjun cannot see any of it, and they cannot see his.
    expect((await store.listBooks('user_owner')).map((book) => book.id)).not.toContain(books[0].id);
    expect(await store.getMembership('book_owner', stranger.id)).toBeFalsy();
    expect(await store.getMembership(books[0].id, 'user_owner')).toBeFalsy();
    expect((await store.listWorkspaces(stranger.id)).map((workspace) => workspace.id)).toEqual([workspaceId]);
    expect((await store.listWorkspaces('user_owner')).map((workspace) => workspace.id)).toEqual(['ws_household']);
  });

  it('provisions a household for a console-created account, which is never email-verified', async () => {
    process.env.TENANT_SELF_PROVISION = 'true';
    try {
      const store = new MemoryStore();
      const app2 = await buildApp({ store, authMode: 'firebase' });
      try {
        // An account an operator creates in the Firebase console arrives with
        // email_verified false. Requiring verification would block the only way
        // this feature is meant to be used.
        expect(await store.getUserByEmail('tptp.jadheer@example.com')).toBeNull();
        const user = await store.provisionTenant({ firebaseUid: 'firebase-console-made', email: 'tptp.jadheer@example.com', displayName: null });
        // Falls back to the email local part when Firebase carries no name.
        expect((await store.listBooks(user.id)).map((book) => book.name).sort()).toEqual(['Household', "tptp.jadheer's finances"]);
        // A second identity on the same address must not collide on the unique column.
        expect(await store.getUserByEmail('TPTP.JADHEER@example.com')).toMatchObject({ id: user.id });
      } finally {
        await app2.close();
      }
    } finally {
      delete process.env.TENANT_SELF_PROVISION;
    }
  });

  it('sends someone with an outstanding invitation to that book instead of a new household', async () => {
    const store = new MemoryStore();
    expect(await store.hasPendingInvitation('nobody@example.com')).toBe(false);
    await store.createInvitation({
      workspaceId: 'ws_household', bookId: 'book_home', email: 'spouse.to.be@example.com', role: 'editor',
      tokenHash: 'pending-token-hash', invitedById: 'user_owner', expiresAt: new Date(Date.now() + 60_000),
    });
    // The auth hook checks this before provisioning, so an invited person joins
    // the household they were invited to rather than starting their own.
    expect(await store.hasPendingInvitation('spouse.to.be@example.com')).toBe(true);
    expect(await store.hasPendingInvitation('SPOUSE.TO.BE@example.com')).toBe(true);

    const expired = await store.createInvitation({
      workspaceId: 'ws_household', bookId: 'book_home', email: 'stale@example.com', role: 'viewer',
      tokenHash: 'stale-token-hash', invitedById: 'user_owner', expiresAt: new Date(Date.now() - 60_000),
    });
    expect(expired).toBeTruthy();
    expect(await store.hasPendingInvitation('stale@example.com')).toBe(false);
  });

  it('budgets a share of expected income per group, not a rupee figure per category', async () => {
    const headers = as('user_owner');
    // Expected income comes from the recurring plan, so a budget can be set
    // before payday rather than reading zero until the salary lands.
    await app.inject({ method: 'POST', url: '/v1/books/book_arjun/recurring-plans', headers,
      payload: { name: 'Salary', kind: 'income', amountMinor: '10000000', categoryId: 'cat_salary', cadence: 'monthly', nextDueAt: '2026-10-31T00:00:00.000Z' } });

    const saved = await app.inject({ method: 'PUT', url: '/v1/books/book_arjun/budget-plan', headers,
      payload: { allocations: [{ groupName: 'Essentials', percent: 50 }, { groupName: 'Lifestyle', percent: 30 }, { groupName: 'Saving', percent: 20 }, { groupName: 'Other', percent: 0 }] } });
    expect(saved.statusCode).toBe(200);
    // A group given nothing is dropped rather than stored at 0.
    expect(saved.json().items).toEqual([{ groupName: 'Essentials', percent: 50 }, { groupName: 'Lifestyle', percent: 30 }, { groupName: 'Saving', percent: 20 }]);

    const plan = await app.inject({ method: 'GET', url: '/v1/books/book_arjun/budget-plan', headers });
    // The seeded book already has a salary plan, so expected income is both.
    expect(BigInt(plan.json().baseIncomeMinor)).toBe(10000000n + 58786700n);

    // Saving again replaces the plan instead of merging into it.
    await app.inject({ method: 'PUT', url: '/v1/books/book_arjun/budget-plan', headers, payload: { allocations: [{ groupName: 'Essentials', percent: 60 }] } });
    expect((await app.inject({ method: 'GET', url: '/v1/books/book_arjun/budget-plan', headers })).json().items).toEqual([{ groupName: 'Essentials', percent: 60 }]);

    const audit = await app.inject({ method: 'GET', url: '/v1/books/book_arjun/audit-events', headers });
    expect(audit.json().items.some((event) => event.action === 'budget_plan.saved')).toBe(true);
  });

  it('refuses shares that add up to more than the whole income', async () => {
    const over = await app.inject({ method: 'PUT', url: '/v1/books/book_arjun/budget-plan', headers: as('user_owner'),
      payload: { allocations: [{ groupName: 'Essentials', percent: 60 }, { groupName: 'Lifestyle', percent: 50 }] } });
    expect(over.statusCode).toBe(400);
    expect(JSON.stringify(over.json().details)).toContain('110%');

    const twice = await app.inject({ method: 'PUT', url: '/v1/books/book_arjun/budget-plan', headers: as('user_owner'),
      payload: { allocations: [{ groupName: 'Essentials', percent: 30 }, { groupName: 'essentials', percent: 20 }] } });
    expect(twice.statusCode).toBe(400);

    // A reviewer can see the plan but not change it.
    expect((await app.inject({ method: 'GET', url: '/v1/books/book_home/budget-plan', headers: as('user_ca') })).statusCode).toBe(200);
    expect((await app.inject({ method: 'PUT', url: '/v1/books/book_home/budget-plan', headers: as('user_ca'), payload: { allocations: [{ groupName: 'Essentials', percent: 10 }] } })).statusCode).toBe(403);
  });

  it('reports where money moved between accounts, and only when a destination is named', async () => {
    const headers = as('user_owner');
    const account = async (name) => (await app.inject({ method: 'POST', url: '/v1/books/book_arjun/accounts', headers, payload: { name, accountType: 'bank', currency: 'INR' } })).json();
    const sbi = await account('SBI - Salary');
    const hdfc = await account('HDFC Saving');
    const post = async (payload, key) => { const response = await app.inject({ method: 'POST', url: '/v1/books/book_arjun/transactions', headers: { ...headers, 'idempotency-key': key }, payload }); expect(response.statusCode).toBe(201); return response; };

    await post({ kind: 'income', amountMinor: '10417800', merchant: 'Salary', occurredAt: '2026-11-01T05:30:00.000Z', categoryId: 'cat_salary', accountId: sbi.id }, 'flow-income');
    await post({ kind: 'expense', amountMinor: '-2322600', merchant: 'EMI', occurredAt: '2026-11-02T05:30:00.000Z', categoryId: 'cat_emi', accountId: sbi.id }, 'flow-emi');
    // Two transfers out of SBI that say where they landed, and one that does not.
    await post({ kind: 'transfer', amountMinor: '-2500000', merchant: 'To HDFC', occurredAt: '2026-11-03T05:30:00.000Z', categoryId: 'cat_investment', accountId: sbi.id, counterAccountId: hdfc.id }, 'flow-transfer-1');
    await post({ kind: 'transfer', amountMinor: '-500000', merchant: 'To HDFC', occurredAt: '2026-11-04T05:30:00.000Z', categoryId: 'cat_investment', accountId: sbi.id, counterAccountId: hdfc.id }, 'flow-transfer-2');
    await post({ kind: 'transfer', amountMinor: '-130000', merchant: 'Somewhere', occurredAt: '2026-11-05T05:30:00.000Z', categoryId: 'cat_investment', accountId: sbi.id }, 'flow-transfer-3');

    const summary = (await app.inject({ method: 'GET', url: '/v1/books/book_arjun/summary?month=2026-11', headers })).json();
    const of = (id) => summary.byAccount.find((entry) => entry.accountId === id);
    expect(of(sbi.id)).toMatchObject({ inMinor: '10417800', outMinor: '5452600', netMinor: '4965200' });
    // The destination gains what the source lost, but only for the two that named it.
    expect(of(hdfc.id)).toMatchObject({ inMinor: '3000000', outMinor: '0' });
    expect(summary.flows).toEqual([{ fromAccountId: sbi.id, fromName: 'SBI - Salary', toAccountId: hdfc.id, toName: 'HDFC Saving', amountMinor: '3000000', count: 2 }]);

    // Naming the source as the destination records no movement at all.
    const same = await app.inject({ method: 'PATCH', url: `/v1/books/book_arjun/transactions/${(await post({ kind: 'transfer', amountMinor: '-100', merchant: 'x', occurredAt: '2026-11-06T05:30:00.000Z', accountId: sbi.id }, 'flow-transfer-4')).json().id}`,
      headers, payload: { counterAccountId: sbi.id } });
    expect(same.statusCode).toBe(400);
    expect(same.json().code).toBe('SAME_ACCOUNT_TRANSFER');
  });

  it('takes both spending and saving out of the balance', async () => {
    const headers = as('user_owner');
    const post = (payload, key) => app.inject({ method: 'POST', url: '/v1/books/book_arjun/transactions', headers: { ...headers, 'idempotency-key': key }, payload });
    await post({ kind: 'income', amountMinor: '10000000', merchant: 'Salary', occurredAt: '2026-10-01T05:30:00.000Z', categoryId: 'cat_salary' }, 'balance-income-1');
    await post({ kind: 'expense', amountMinor: '-2500000', merchant: 'Rent', occurredAt: '2026-10-02T05:30:00.000Z', categoryId: 'cat_rent' }, 'balance-spend-1');
    await post({ kind: 'transfer', amountMinor: '-1500000', merchant: 'To my HDFC', occurredAt: '2026-10-03T05:30:00.000Z', categoryId: 'cat_investment' }, 'balance-save-1');

    const summary = await app.inject({ method: 'GET', url: '/v1/books/book_arjun/summary?month=2026-10', headers });
    const { incomeMinor, spentMinor, movedMinor, balanceMinor } = summary.json();
    expect([incomeMinor, spentMinor, movedMinor]).toEqual(['10000000', '2500000', '1500000']);
    // Balance is what is left, so money set aside is not counted as still available.
    expect(balanceMinor).toBe('6000000');
    expect(BigInt(balanceMinor)).toBe(BigInt(incomeMinor) - BigInt(spentMinor) - BigInt(movedMinor));
  });

  it('shows an investment moved to your own account under its category', async () => {
    const created = await app.inject({ method: 'POST', url: '/v1/books/book_arjun/transactions', headers: { ...as('user_owner'), 'idempotency-key': 'investment-0001' },
      payload: { kind: 'transfer', amountMinor: '-2500000', merchant: 'Moved to my HDFC', occurredAt: '2026-09-01T05:30:00.000Z', categoryId: 'cat_investment' } });
    expect(created.statusCode).toBe(201);

    const summary = await app.inject({ method: 'GET', url: '/v1/books/book_arjun/summary?month=2026-09', headers: as('user_owner') });
    const { byCategory, spentMinor, movedMinor } = summary.json();
    // It is not spending...
    expect(BigInt(spentMinor)).toBe(0n);
    expect(BigInt(movedMinor)).toBe(2500000n);
    // ...but "where your money went" still shows it, under Saving.
    expect(byCategory.find((item) => item.categoryId === 'cat_investment')).toMatchObject({ name: 'Investment', groupName: 'Saving', amountMinor: '2500000' });
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

  it('edits an imported entry in full while keeping the figure the bank sent', async () => {
    const imported = await app.inject({ method: 'POST', url: '/v1/books/book_arjun/imports', headers: as('user_owner'),
      payload: { fileName: 'sbi.csv', contentType: 'text/csv', sizeBytes: sbiStatement.length, sha256: 'e'.repeat(64), content: sbiStatement } });
    expect(imported.statusCode).toBe(201);
    const hashes = new Set(parseStatementCsv(sbiStatement).rows.map((row) => row.sourceHash));
    const ledger = await app.inject({ method: 'GET', url: '/v1/books/book_arjun/transactions?limit=100', headers: as('user_owner') });
    const row = ledger.json().items.find((item) => item.sources?.some((source) => hashes.has(source.sourceReference)));
    const bankAmount = row.sources.find((source) => hashes.has(source.sourceReference)).importedAmount;

    const edited = await app.inject({ method: 'PATCH', url: `/v1/books/book_arjun/transactions/${row.id}`, headers: as('user_owner'),
      payload: { kind: 'transfer', amountMinor: '-90000', merchant: 'Moved to my HDFC account', occurredAt: '2026-09-03T18:30:00.000Z', accountId: 'account_primary' } });
    expect(edited.statusCode).toBe(200);
    expect(edited.json()).toMatchObject({ kind: 'transfer', amountMinor: '-90000', merchant: 'Moved to my HDFC account', accountId: 'account_primary' });

    // The bank's own figure is still on the source record after the edit, and the
    // previous values are in the audit trail.
    const reread = await app.inject({ method: 'GET', url: '/v1/books/book_arjun/transactions?limit=100', headers: as('user_owner') });
    const after = reread.json().items.find((item) => item.id === row.id);
    expect(after.sources.find((source) => hashes.has(source.sourceReference)).importedAmount).toBe(bankAmount);
    const audit = await app.inject({ method: 'GET', url: '/v1/books/book_arjun/audit-events', headers: as('user_owner') });
    expect(audit.json().items.find((event) => event.action === 'transaction.corrected' && event.entityId === row.id))
      .toMatchObject({ before: { amountMinor: bankAmount, kind: 'expense' }, after: { amountMinor: '-90000', kind: 'transfer' } });

    // A transfer stops counting as spending but is still accounted for, so the
    // money does not simply vanish from the breakdown.
    const summary = await app.inject({ method: 'GET', url: '/v1/books/book_arjun/summary?month=2026-09', headers: as('user_owner') });
    expect(BigInt(summary.json().movedMinor)).toBe(90000n);
    expect(summary.json().byCategory.reduce((sum, item) => sum + BigInt(item.amountMinor), 0n)).toBe(BigInt(summary.json().spentMinor) + BigInt(summary.json().movedMinor));

    const voided = await app.inject({ method: 'PATCH', url: `/v1/books/book_arjun/transactions/${row.id}`, headers: as('user_owner'), payload: { state: 'voided' } });
    expect(voided.json().state).toBe('voided');
  });

  it('refuses to move an entry onto an account from another book', async () => {
    const created = await app.inject({ method: 'POST', url: '/v1/books/book_arjun/transactions', headers: { ...as('user_owner'), 'idempotency-key': 'wrong-account-001' },
      payload: { kind: 'expense', amountMinor: '-2500', merchant: 'Chai', occurredAt: '2026-09-04T05:30:00.000Z', categoryId: 'cat_dining' } });
    const response = await app.inject({ method: 'PATCH', url: `/v1/books/book_arjun/transactions/${created.json().id}`, headers: as('user_owner'), payload: { accountId: 'acct_not_in_this_book' } });
    expect(response.statusCode).toBe(400);
    expect(response.json().code).toBe('REFERENCE_SCOPE_ERROR');
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
  describe('master admin', () => {
    // PLATFORM_ADMINS is read per request, so it can be set and cleared around
    // each case rather than needing a second app.
    const asAdmin = async (fn) => {
      const saved = process.env.PLATFORM_ADMINS;
      process.env.PLATFORM_ADMINS = 'arjun@example.com';
      try { await fn(); } finally { if (saved === undefined) delete process.env.PLATFORM_ADMINS; else process.env.PLATFORM_ADMINS = saved; }
    };

    it('matches an admin on the whole address, never a bare local part', async () => {
      // The live deployment seeded a profile as `arjunm295707` with the domain
      // missing, which locked the owner out of their own admin page. A partial
      // match must stay a non-match — the fix was to compare against the signed
      // token email, not to loosen this.
      const saved = process.env.PLATFORM_ADMINS;
      process.env.PLATFORM_ADMINS = ' ArjunM295707@Gmail.com ';
      try {
        expect(isPlatformAdmin('arjunm295707@gmail.com')).toBe(true);
        expect(isPlatformAdmin('  ARJUNM295707@GMAIL.COM ')).toBe(true);
        expect(isPlatformAdmin('arjunm295707')).toBe(false);
        expect(isPlatformAdmin('arjunm295707@gmail.com.evil.test')).toBe(false);
        expect(isPlatformAdmin('')).toBe(false);
        expect(isPlatformAdmin(null)).toBe(false);
      } finally {
        if (saved === undefined) delete process.env.PLATFORM_ADMINS; else process.env.PLATFORM_ADMINS = saved;
      }
    });

    it('hides the admin API from everyone who is not listed, with a 404 rather than a 403', async () => {
      // Nobody is an admin yet: even the owner must not see that it exists.
      const unlisted = await app.inject({ method: 'GET', url: '/v1/admin/users', headers: as('user_owner') });
      expect(unlisted.statusCode).toBe(404);
      await asAdmin(async () => {
        const spouse = await app.inject({ method: 'GET', url: '/v1/admin/users', headers: as('user_spouse') });
        expect(spouse.statusCode).toBe(404);
        const owner = await app.inject({ method: 'GET', url: '/v1/admin/users', headers: as('user_owner') });
        expect(owner.statusCode).toBe(200);
      });
    });

    it('counts only the books a user owns towards their own data', async () => {
      await asAdmin(async () => {
        const response = await app.inject({ method: 'GET', url: '/v1/admin/users', headers: as('user_owner') });
        const rows = response.json().items;
        const ca = rows.find((row) => row.email === 'ca@example.com');
        // The CA reviews the household book but owns nothing, so wiping them
        // must never be reported as wiping somebody else's ledger.
        expect(ca.bookCount).toBe(1);
        expect(ca.ownedBookCount).toBe(0);
        expect(ca.transactionCount).toBe(0);
        expect(rows.find((row) => row.email === 'arjun@example.com').ownedBookCount).toBe(2);
      });
    });

    it('refuses a reset whose confirmation does not name the account', async () => {
      await asAdmin(async () => {
        const wrong = await app.inject({ method: 'POST', url: '/v1/admin/users/user_spouse/ledger-reset', headers: as('user_owner'), payload: { confirmEmail: 'arjun@example.com' } });
        expect(wrong.statusCode).toBe(400);
        expect(wrong.json().code).toBe('CONFIRMATION_MISMATCH');
      });
    });

    it('exports a user before wiping them, and wipes only what they own', async () => {
      await asAdmin(async () => {
        const exported = await app.inject({ method: 'GET', url: '/v1/admin/users/user_owner/export', headers: as('user_owner') });
        expect(exported.statusCode).toBe(200);
        const backup = exported.json();
        expect(backup.format).toBe('paisa.user-export.v1');
        const entries = backup.books.flatMap((book) => book.transactions);
        expect(entries.length).toBeGreaterThan(0);

        const spouseBefore = await app.inject({ method: 'GET', url: '/v1/books/book_priya/transactions', headers: as('user_spouse') });
        const reset = await app.inject({ method: 'POST', url: '/v1/admin/users/user_owner/ledger-reset', headers: as('user_owner'), payload: { confirmEmail: 'arjun@example.com' } });
        expect(reset.statusCode).toBe(200);
        expect(reset.json().transactionsRemoved).toBe(entries.length);

        const after = await app.inject({ method: 'GET', url: '/v1/books/book_arjun/transactions', headers: as('user_owner') });
        expect(after.json().items).toHaveLength(0);
        // The spouse's own book is in the same workspace and must be untouched.
        const spouseAfter = await app.inject({ method: 'GET', url: '/v1/books/book_priya/transactions', headers: as('user_spouse') });
        expect(spouseAfter.json().items).toEqual(spouseBefore.json().items);
      });
    });

    it('resets a household to new without reaching into a book it does not own', async () => {
      await asAdmin(async () => {
        // A rule and a split in the spouse's book, which the owner does not own.
        const rule = await app.inject({ method: 'POST', url: '/v1/books/book_priya/categorization-rules', headers: as('user_spouse'), payload: { categoryId: 'cat_food', matchType: 'merchant_contains', matchValue: 'Swiggy', priority: 10 } });
        expect(rule.statusCode).toBe(201);

        const before = await app.inject({ method: 'GET', url: '/v1/admin/users', headers: as('user_owner') });
        expect(before.json().items.find((row) => row.email === 'arjun@example.com').transactionCount).toBeGreaterThan(0);

        const reset = await app.inject({ method: 'POST', url: '/v1/admin/users/user_owner/factory-reset', headers: as('user_owner'), payload: { confirmEmail: 'arjun@example.com' } });
        expect(reset.statusCode).toBe(200);
        const result = reset.json();
        expect(result.transactionsRemoved).toBeGreaterThan(0);

        // The ledger and everything learned on top of it is gone.
        for (const path of ['transactions', 'accounts', 'categorization-rules', 'recurring-plans', 'imports']) {
          const left = await app.inject({ method: 'GET', url: `/v1/books/book_arjun/${path}`, headers: as('user_owner') });
          expect({ path, items: left.json().items }).toEqual({ path, items: [] });
        }

        // The old audit trail is gone, and the reset itself is the first entry
        // of the new one — a wipe that leaves no trace is not acceptable.
        const audit = await app.inject({ method: 'GET', url: '/v1/books/book_arjun/audit-events', headers: as('user_owner') });
        expect(audit.json().items.map((event) => event.action)).toEqual(['admin.factory_reset']);

        // But the books, the membership and the login are untouched...
        const books = await app.inject({ method: 'GET', url: '/v1/books', headers: as('user_owner') });
        expect(books.json().items.map((book) => book.id).sort()).toEqual(['book_arjun', 'book_home']);

        // ...the starter categories are back, so the book still works...
        const categories = await app.inject({ method: 'GET', url: '/v1/books/book_arjun/categories', headers: as('user_owner') });
        expect(categories.json().items.length).toBe(DEFAULT_CATEGORIES.length);
        expect(result.categoriesRestored).toBeGreaterThan(0);

        // ...and the spouse's own rule survived, with the category it points at.
        const spouseRules = await app.inject({ method: 'GET', url: '/v1/books/book_priya/categorization-rules', headers: as('user_spouse') });
        expect(spouseRules.json().items).toHaveLength(1);
        const spouseCategories = await app.inject({ method: 'GET', url: '/v1/books/book_priya/categories', headers: as('user_spouse') });
        expect(spouseCategories.json().items.some((category) => category.id === spouseRules.json().items[0].categoryId)).toBe(true);
      });
    });

    it('will not let an admin delete themselves, and leaves a shared book standing', async () => {
      await asAdmin(async () => {
        const self = await app.inject({ method: 'POST', url: '/v1/admin/users/user_owner/delete', headers: as('user_owner'), payload: { confirmEmail: 'arjun@example.com' } });
        expect(self.statusCode).toBe(409);
        expect(self.json().code).toBe('SELF_DELETE');

        const removed = await app.inject({ method: 'POST', url: '/v1/admin/users/user_ca/delete', headers: as('user_owner'), payload: { confirmEmail: 'ca@example.com' } });
        expect(removed.statusCode).toBe(200);
        // The CA owned nothing, so nothing of the household goes with them.
        expect(removed.json().booksDeleted).toEqual([]);
        const household = await app.inject({ method: 'GET', url: '/v1/books/book_home/transactions', headers: as('user_owner') });
        expect(household.statusCode).toBe(200);
      });
    });

    it('says plainly when a Firebase-only action has no service account behind it', async () => {
      await asAdmin(async () => {
        const created = await app.inject({ method: 'POST', url: '/v1/admin/users', headers: as('user_owner'), payload: { email: 'new@example.com' } });
        expect(created.statusCode).toBe(501);
        expect(created.json().code).toBe('FIREBASE_ADMIN_UNCONFIGURED');
        // Reading the directory still works — it just says what is missing.
        const listed = await app.inject({ method: 'GET', url: '/v1/admin/users', headers: as('user_owner') });
        expect(listed.json().firebaseConfigured).toBe(false);
        expect(listed.json().reason).toMatch(/service account/i);
      });
    });
  });
  describe('access requests', () => {
    const asAdmin = async (fn) => {
      const saved = process.env.PLATFORM_ADMINS;
      process.env.PLATFORM_ADMINS = 'arjun@example.com';
      try { await fn(); } finally { if (saved === undefined) delete process.env.PLATFORM_ADMINS; else process.env.PLATFORM_ADMINS = saved; }
    };
    const ask = (payload) => app.inject({ method: 'POST', url: '/v1/access-requests', payload });

    it('takes a request from a stranger with no token at all', async () => {
      // The only unauthenticated write on the API. If this ever starts needing
      // a token, the landing page's button silently stops working.
      const first = await ask({ name: 'Priya', email: ' Priya@Example.com ' });
      expect(first.statusCode).toBe(201);
      expect(first.json().status).toBe('received');
      await asAdmin(async () => {
        const listed = await app.inject({ method: 'GET', url: '/v1/admin/access-requests', headers: as('user_owner') });
        expect(listed.json().items).toMatchObject([{ email: 'priya@example.com', name: 'Priya', approvedAt: null }]);
      });
    });

    it('tells a second submission to wait rather than filing it twice', async () => {
      await ask({ name: 'Priya', email: 'priya@example.com' });
      const again = await ask({ name: 'Priya again', email: 'PRIYA@example.com' });
      expect(again.statusCode).toBe(200);
      expect(again.json().status).toBe('pending');
      await asAdmin(async () => {
        const listed = await app.inject({ method: 'GET', url: '/v1/admin/access-requests', headers: as('user_owner') });
        expect(listed.json().items).toHaveLength(1);
      });
    });

    it('tells someone already let in to sign in, not to wait their turn', async () => {
      await ask({ name: 'Priya', email: 'priya@example.com' });
      // What approving does to the row; the approval route itself needs a
      // Firebase service account, which no test has.
      await app.store.grantAccessRequest({ email: 'priya@example.com', name: 'Priya' });
      expect((await ask({ name: 'Priya', email: 'priya@example.com' })).json().status).toBe('granted');
    });

    it('rejects a blank name or a non-address', async () => {
      expect((await ask({ name: '  ', email: 'priya@example.com' })).statusCode).toBe(400);
      expect((await ask({ name: 'Priya', email: 'not-an-email' })).statusCode).toBe(400);
    });

    it('lets a deleted user ask again instead of being told they still have access', async () => {
      await app.store.grantAccessRequest({ email: 'ca@example.com', name: 'The CA' });
      await asAdmin(async () => {
        const removed = await app.inject({ method: 'POST', url: '/v1/admin/users/user_ca/delete', headers: as('user_owner'), payload: { confirmEmail: 'ca@example.com' } });
        expect(removed.statusCode).toBe(200);
      });
      expect((await ask({ name: 'The CA', email: 'ca@example.com' })).json().status).toBe('received');
    });

    it('keeps the requests list away from everyone who is not a master admin', async () => {
      const outsider = await app.inject({ method: 'GET', url: '/v1/admin/access-requests', headers: as('user_spouse') });
      expect(outsider.statusCode).toBe(404);
    });

    it('removes a request the admin does not want', async () => {
      await ask({ name: 'Spam', email: 'spam@example.com' });
      await asAdmin(async () => {
        const { items } = (await app.inject({ method: 'GET', url: '/v1/admin/access-requests', headers: as('user_owner') })).json();
        const gone = await app.inject({ method: 'POST', url: `/v1/admin/access-requests/${items[0].id}/delete`, headers: as('user_owner'), payload: {} });
        expect(gone.statusCode).toBe(200);
        const after = await app.inject({ method: 'GET', url: '/v1/admin/access-requests', headers: as('user_owner') });
        expect(after.json().items).toEqual([]);
      });
    });
  });

  describe('pay cycles', () => {
    // A household paid on the last working day cannot use calendar months: the
    // salary that funds November lands in October, so the dashboard reads as a
    // month-long deficit and then leaps on the 30th.
    it('labels a late-month cycle by the month it pays for', () => {
      const tz = 'Asia/Kolkata';
      const iso = (d) => d.toISOString();
      // Day 26: "2026-11" is 26 Oct -> 26 Nov, because that money buys November.
      const november = periodRangeUtc('2026-11', tz, 26);
      expect(iso(november.start)).toBe('2026-10-25T18:30:00.000Z'); // 26 Oct 00:00 IST
      expect(iso(november.end)).toBe('2026-11-25T18:30:00.000Z');
      // Day 5 pays for the month it starts in, so no shift.
      const early = periodRangeUtc('2026-11', tz, 5);
      expect(iso(early.start)).toBe('2026-11-04T18:30:00.000Z');
      // Day 1 must stay exactly what it has always been.
      const calendar = periodRangeUtc('2026-11', tz, 1);
      expect(iso(calendar.start)).toBe('2026-10-31T18:30:00.000Z');
      expect(iso(calendar.end)).toBe('2026-11-30T18:30:00.000Z');
    });

    it('moves the current period on payday, not on the 1st', () => {
      const tz = 'Asia/Kolkata';
      const on = (day) => new Date(`2026-10-${day}T12:00:00Z`);
      expect(currentPeriodLabel(on('02'), tz, 26)).toBe('2026-10'); // still spending Sept's pay
      expect(currentPeriodLabel(on('25'), tz, 26)).toBe('2026-10');
      expect(currentPeriodLabel(on('27'), tz, 26)).toBe('2026-11'); // paid, November has begun
      expect(currentPeriodLabel(on('02'), tz, 5)).toBe('2026-09');
      expect(currentPeriodLabel(on('06'), tz, 5)).toBe('2026-10');
      expect(currentPeriodLabel(on('02'), tz, 1)).toBe('2026-10');
    });

    it('rejects a start day no month has, and accepts every one that exists', async () => {
      for (const bad of [0, 32, 2.5, -1]) expect(normaliseStartDay(bad)).toBe(1);
      expect(normaliseStartDay(31)).toBe(31);
      const rejected = await app.inject({ method: 'PATCH', url: '/v1/books/book_arjun', headers: as('user_owner'), payload: { periodStartDay: 32 } });
      expect(rejected.statusCode).toBe(400);
      const accepted = await app.inject({ method: 'PATCH', url: '/v1/books/book_arjun', headers: as('user_owner'), payload: { periodStartDay: 30 } });
      expect(accepted.statusCode).toBe(200);
    });

    it('clamps a late start day into short months without leaving a gap', () => {
      const tz = 'Asia/Kolkata';
      // IST midnight is 18:30 UTC the day before, so compare the local date.
      const local = (d) => new Date(d.getTime() + 5.5 * 3600000).toISOString().slice(0, 10);
      const at = (month, startDay) => periodRangeUtc(month, tz, startDay);

      // February has no 30th, so the cycle starts on the 28th that year.
      expect(local(at('2027-02', 30).start)).toBe('2027-01-30');
      expect(local(at('2027-02', 30).end)).toBe('2027-02-28');
      expect(local(at('2027-03', 30).start)).toBe('2027-02-28');
      // A leap year gives it the 29th.
      expect(local(at('2028-02', 31).end)).toBe('2028-02-29');
      expect(local(at('2028-03', 31).start)).toBe('2028-02-29');

      // The clamp must not drop a day or double-count one: consecutive periods
      // meet exactly, every month, for every start day.
      for (const startDay of [26, 29, 30, 31]) {
        for (let month = 1; month <= 11; month += 1) {
          const label = (m) => `2027-${String(m).padStart(2, '0')}`;
          expect(at(label(month), startDay).end.getTime()).toBe(at(label(month + 1), startDay).start.getTime());
        }
      }
    });

    it('treats the clamped day as the boundary when deciding the current period', () => {
      const tz = 'Asia/Kolkata';
      // 28 Feb 2027 is as close to "the 30th" as February gets, so the next
      // cycle has begun; the day before, it has not.
      expect(currentPeriodLabel(new Date('2027-02-28T12:00:00Z'), tz, 30)).toBe('2027-03');
      expect(currentPeriodLabel(new Date('2027-02-27T12:00:00Z'), tz, 30)).toBe('2027-02');
    });

    it('counts a month-end salary into the period it funds', async () => {
      // Salary on 30 Sept, rent on 2 Oct — one pay cycle, not two months.
      const salary = { kind: 'income', amountMinor: '50000000', currency: 'INR', merchant: 'Acme', occurredAt: '2026-09-30T05:30:00.000Z', state: 'confirmed' };
      const rent = { kind: 'expense', amountMinor: '-2000000', currency: 'INR', merchant: 'Landlord', occurredAt: '2026-10-02T05:30:00.000Z', state: 'confirmed' };
      for (const [index, payload] of [salary, rent].entries()) {
        const created = await app.inject({ method: 'POST', url: '/v1/books/book_arjun/transactions', headers: { ...as('user_owner'), 'idempotency-key': `cycle-seed-${index}` }, payload });
        expect(created.statusCode).toBe(201);
      }
      const calendar = await app.inject({ method: 'GET', url: '/v1/books/book_arjun/summary?month=2026-10', headers: as('user_owner') });
      // On calendar months October sees the rent but not the salary that paid for it.
      expect(calendar.json().incomeMinor).toBe('0');

      const moved = await app.inject({ method: 'PATCH', url: '/v1/books/book_arjun', headers: as('user_owner'), payload: { periodStartDay: 26 } });
      expect(moved.statusCode).toBe(200);
      const cycle = await app.inject({ method: 'GET', url: '/v1/books/book_arjun/summary?month=2026-10', headers: as('user_owner') });
      const body = cycle.json();
      expect(body.incomeMinor).toBe('50000000');
      expect(BigInt(body.spentMinor)).toBeGreaterThanOrEqual(2000000n);
      // The window is reported, so the header can never contradict the figures.
      expect(body.period).toMatchObject({ month: '2026-10', startDay: 26 });
      expect(body.period.startsAt).toBe('2026-09-25T18:30:00.000Z');
    });
  });
});
