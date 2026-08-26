import { randomUUID } from 'node:crypto';
import { parseMinor, serializeMoney } from '../domain/money.js';

const now = new Date('2026-08-26T15:30:00.000Z');

const users = [
  { id: 'user_owner', firebaseUid: 'firebase-owner', email: 'arjun@example.com', displayName: 'Arjun Mohanesh' },
  { id: 'user_spouse', firebaseUid: 'firebase-spouse', email: 'priya@example.com', displayName: 'Priya Mohanesh' },
  { id: 'user_ca', firebaseUid: 'firebase-ca', email: 'ca@example.com', displayName: 'CA Reviewer' },
];

const categories = [
  ['cat_rent', 'Rent + maintenance', 'Essentials', '#315b46'], ['cat_utilities', 'Utilities', 'Essentials', '#60806f'],
  ['cat_groceries', 'Groceries', 'Essentials', '#89a55b'], ['cat_family', 'Money sent to family', 'Essentials', '#a9bd72'],
  ['cat_emi', 'EMI', 'Essentials', '#607b87'], ['cat_transport', 'Transportation', 'Essentials', '#6f8f83'],
  ['cat_food', 'Food delivery', 'Lifestyle', '#df8d6d'], ['cat_dining', 'Dining out', 'Lifestyle', '#d29a65'],
  ['cat_subscriptions', 'Subscriptions', 'Lifestyle', '#9d83a6'], ['cat_travel', 'Travel', 'Lifestyle', '#6399a4'],
  ['cat_salary', 'Salary', 'Income', '#397454'], ['cat_other', 'Uncategorized', 'Other', '#a1a8a3'],
].map(([id, name, groupName, color]) => ({ id, workspaceId: 'ws_household', name, groupName, color }));

const books = [
  { id: 'book_arjun', workspaceId: 'ws_household', name: "Arjun's finances", visibility: 'private', currency: 'INR', timezone: 'Asia/Kolkata' },
  { id: 'book_priya', workspaceId: 'ws_household', name: "Priya's finances", visibility: 'private', currency: 'INR', timezone: 'Asia/Kolkata' },
  { id: 'book_home', workspaceId: 'ws_household', name: 'Household', visibility: 'shared', currency: 'INR', timezone: 'Asia/Kolkata' },
];

const memberships = [
  { bookId: 'book_arjun', userId: 'user_owner', role: 'book_owner' },
  { bookId: 'book_priya', userId: 'user_spouse', role: 'book_owner' },
  { bookId: 'book_home', userId: 'user_owner', role: 'book_owner' },
  { bookId: 'book_home', userId: 'user_spouse', role: 'editor' },
  { bookId: 'book_home', userId: 'user_ca', role: 'reviewer' },
];

const transactions = [
  ['tx_1', 'book_arjun', 'expense', 'confirmed', '-75000', 'Swiggy', 'cat_food', '2026-08-26T14:20:00.000Z', 'sms'],
  ['tx_2', 'book_arjun', 'expense', 'pending_review', '-3500000', 'Hostel EMI', 'cat_emi', '2026-08-26T09:10:00.000Z', 'sms'],
  ['tx_3', 'book_arjun', 'income', 'reconciled', '58786700', 'Acme Technologies', 'cat_salary', '2026-08-25T05:30:00.000Z', 'statement'],
  ['tx_4', 'book_arjun', 'expense', 'confirmed', '-234000', 'Electricity bill', 'cat_utilities', '2026-08-24T10:45:00.000Z', 'sms'],
  ['tx_5', 'book_home', 'expense', 'confirmed', '-482000', 'Fresh Market', 'cat_groceries', '2026-08-23T11:20:00.000Z', 'manual'],
].map(([id, bookId, kind, state, amountMinor, merchant, categoryId, occurredAt, sourceType]) => ({
  id, workspaceId: 'ws_household', bookId, kind, state, amountMinor: BigInt(amountMinor), currency: 'INR', merchant, categoryId,
  note: null, occurredAt: new Date(occurredAt), createdAt: now, updatedAt: now,
  sources: [{ id: `${id}_source`, sourceType, sourceReference: `${sourceType}:${id}`, importedAmount: BigInt(amountMinor) }], splits: [],
}));

const budgets = [
  ['budget_grocery', 'book_arjun', 'cat_groceries', '600000'], ['budget_dining', 'book_arjun', 'cat_dining', '250000'],
  ['budget_transport', 'book_arjun', 'cat_transport', '600000'], ['budget_food', 'book_arjun', 'cat_food', '700000'],
].map(([id, bookId, categoryId, amountMinor]) => ({ id, bookId, categoryId, month: '2026-08-01', amountMinor: BigInt(amountMinor), currency: 'INR' }));

export class MemoryStore {
  constructor() {
    this.users = structuredClone(users);
    this.workspaces = [{ id: 'ws_household', name: 'Mohanesh household', currency: 'INR', timezone: 'Asia/Kolkata' }];
    this.books = structuredClone(books);
    this.memberships = structuredClone(memberships);
    this.categories = structuredClone(categories);
    this.transactions = structuredClone(transactions);
    this.budgets = structuredClone(budgets);
    this.audit = [];
    this.idempotency = new Map();
    this.ingestion = [];
  }

  async getUserById(id) { return this.users.find((user) => user.id === id) ?? null; }
  async getUserByFirebaseUid(uid) { return this.users.find((user) => user.firebaseUid === uid) ?? null; }
  async listWorkspaces(userId) {
    const workspaceIds = new Set(this.memberships.filter((member) => member.userId === userId).map((member) => this.books.find((book) => book.id === member.bookId)?.workspaceId));
    return this.workspaces.filter((workspace) => workspaceIds.has(workspace.id));
  }
  async listBooks(userId) {
    return this.memberships.filter((member) => member.userId === userId).map((member) => ({ ...this.books.find((book) => book.id === member.bookId), role: member.role }));
  }
  async getBook(bookId) { return this.books.find((book) => book.id === bookId) ?? null; }
  async getMembership(bookId, userId) { return this.memberships.find((member) => member.bookId === bookId && member.userId === userId) ?? null; }
  async listMemberships(bookId) {
    return this.memberships.filter((member) => member.bookId === bookId).map((member) => ({ ...member, user: this.users.find((user) => user.id === member.userId) }));
  }
  async listCategories(workspaceId) { return this.categories.filter((category) => category.workspaceId === workspaceId); }
  async createCategory({ workspaceId, name, groupName, color }) {
    const category = { id: randomUUID(), workspaceId, name, groupName, color };
    this.categories.push(category); return category;
  }
  async listTransactions(bookId, { state, cursor, limit = 50 } = {}) {
    let items = this.transactions.filter((transaction) => transaction.bookId === bookId && (!state || transaction.state === state)).sort((a, b) => b.occurredAt - a.occurredAt);
    if (cursor) items = items.slice(items.findIndex((item) => item.id === cursor) + 1);
    return { items: items.slice(0, limit), nextCursor: items.length > limit ? items[limit - 1].id : null };
  }
  async getTransaction(bookId, transactionId) { return this.transactions.find((item) => item.bookId === bookId && item.id === transactionId) ?? null; }
  async createTransaction(data, actorId, idempotencyKey) {
    if (idempotencyKey && this.idempotency.has(idempotencyKey)) return this.idempotency.get(idempotencyKey);
    const transaction = { id: randomUUID(), workspaceId: data.workspaceId, bookId: data.bookId, accountId: data.accountId ?? null, categoryId: data.categoryId ?? null,
      kind: data.kind, state: data.state ?? 'confirmed', amountMinor: parseMinor(data.amountMinor), currency: data.currency ?? 'INR', merchant: data.merchant ?? null,
      note: data.note ?? null, occurredAt: new Date(data.occurredAt), createdAt: new Date(), updatedAt: new Date(), sources: [{ id: randomUUID(), sourceType: 'manual', sourceReference: `manual:${randomUUID()}`, importedAmount: parseMinor(data.amountMinor) }], splits: [] };
    this.transactions.push(transaction); if (idempotencyKey) this.idempotency.set(idempotencyKey, transaction); return transaction;
  }
  async updateCategory(bookId, transactionId, categoryId, actorId, applyToFuture = false) {
    const transaction = await this.getTransaction(bookId, transactionId); if (!transaction) return null;
    const before = { categoryId: transaction.categoryId }; transaction.categoryId = categoryId; transaction.state = 'confirmed'; transaction.updatedAt = new Date();
    await this.addAudit({ workspaceId: transaction.workspaceId, bookId, actorId, action: 'transaction.reclassified', entityType: 'transaction', entityId: transaction.id, before, after: { categoryId } });
    if (applyToFuture && transaction.merchant) transaction.ruleCreated = true;
    return transaction;
  }
  async ingest(data, actorId, idempotencyKey) {
    const key = `${data.workspaceId}:${data.sourceHash}`;
    const existing = this.ingestion.find((item) => item.key === key);
    if (existing) return { ...existing, duplicate: true };
    if (idempotencyKey && this.idempotency.has(idempotencyKey)) return this.idempotency.get(idempotencyKey);
    const event = { id: randomUUID(), key, ...data, amountMinor: parseMinor(data.amountMinor), state: 'received', createdAt: new Date(), duplicate: false };
    this.ingestion.push(event);
    const transaction = await this.createTransaction({ ...data, state: data.categoryId ? 'confirmed' : 'pending_review' }, actorId, `ingestion:${key}`);
    transaction.sources = [{ id: randomUUID(), sourceType: data.sourceType, sourceReference: data.sourceHash, importedAmount: parseMinor(data.amountMinor) }];
    event.transactionId = transaction.id; if (idempotencyKey) this.idempotency.set(idempotencyKey, event); return event;
  }
  async listBudgets(bookId) { return this.budgets.filter((budget) => budget.bookId === bookId); }
  async summary(bookId) {
    const txs = this.transactions.filter((item) => item.bookId === bookId && !['excluded', 'voided'].includes(item.state));
    const income = txs.filter((item) => item.kind === 'income').reduce((sum, item) => sum + item.amountMinor, 0n);
    const spent = txs.filter((item) => item.kind === 'expense').reduce((sum, item) => sum + -item.amountMinor, 0n);
    const byCategory = this.categories.map((category) => ({ categoryId: category.id, name: category.name, groupName: category.groupName,
      amountMinor: txs.filter((item) => item.categoryId === category.id && item.kind === 'expense').reduce((sum, item) => sum + -item.amountMinor, 0n) })).filter((item) => item.amountMinor > 0n);
    return { incomeMinor: serializeMoney(income), spentMinor: serializeMoney(spent), savedMinor: serializeMoney(income - spent), pendingReview: txs.filter((item) => item.state === 'pending_review').length, byCategory };
  }
  async addAudit(event) { const record = { id: randomUUID(), createdAt: new Date(), ...event }; this.audit.unshift(record); return record; }
  async listAudit(bookId, limit = 50) { return this.audit.filter((event) => event.bookId === bookId).slice(0, limit); }
}
