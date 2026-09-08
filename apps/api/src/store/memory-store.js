import { randomUUID } from 'node:crypto';
import { jsonSafe, parseMinor, serializeMoney } from '../domain/money.js';
import { isInBookMonth } from '../domain/period.js';
import { matchCategoryRule } from '../domain/categorization.js';
import { spendByCategory } from '../domain/spending.js';
import { duePostings, postingKey } from '../domain/recurring.js';

const now = new Date('2026-08-26T15:30:00.000Z');

const users = [
  { id: 'user_owner', firebaseUid: 'firebase-owner', email: 'arjun@example.com', displayName: 'Arjun Mohanesh' },
  { id: 'user_spouse', firebaseUid: 'firebase-spouse', email: 'priya@example.com', displayName: 'Priya Mohanesh' },
  { id: 'user_ca', firebaseUid: 'firebase-ca', email: 'ca@example.com', displayName: 'CA Reviewer' },
];

// The same SEED_* variables the production seed script reads. Setting them lets a
// real Firebase sign-in resolve to the sample owner, so the Firebase project can be
// verified end to end locally before a database exists. Absent, the placeholder
// identities above are used and only dev-header auth works.
const seedIdentities = { user_owner: 'OWNER', user_spouse: 'SPOUSE', user_ca: 'CA' };
function withSeedIdentity(user) {
  const prefix = seedIdentities[user.id];
  return {
    ...user,
    firebaseUid: process.env[`SEED_${prefix}_FIREBASE_UID`] || user.firebaseUid,
    email: process.env[`SEED_${prefix}_EMAIL`] || user.email,
  };
}

const categories = [
  ['cat_rent', 'Rent + maintenance', 'Essentials', '#315b46'], ['cat_utilities', 'Utilities', 'Essentials', '#60806f'],
  ['cat_groceries', 'Groceries', 'Essentials', '#89a55b'], ['cat_family', 'Money sent to family', 'Essentials', '#a9bd72'],
  ['cat_emi', 'EMI', 'Essentials', '#607b87'], ['cat_transport', 'Transportation', 'Essentials', '#6f8f83'],
  ['cat_food', 'Food delivery', 'Lifestyle', '#df8d6d'], ['cat_dining', 'Dining out', 'Lifestyle', '#d29a65'],
  ['cat_subscriptions', 'Subscriptions', 'Lifestyle', '#9d83a6'], ['cat_travel', 'Travel', 'Lifestyle', '#6399a4'],
  ['cat_salary', 'Salary', 'Income', '#397454'],
  ['cat_investment', 'Investment', 'Saving', '#4a7c8c'], ['cat_savings_transfer', 'Transfer to savings', 'Saving', '#5f8f9c'],
  ['cat_other', 'Uncategorized', 'Other', '#a1a8a3'],
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
    this.users = structuredClone(users).map(withSeedIdentity);
    this.workspaces = [{ id: 'ws_household', name: 'Mohanesh household', currency: 'INR', timezone: 'Asia/Kolkata' }];
    this.books = structuredClone(books);
    this.memberships = structuredClone(memberships);
    this.categories = structuredClone(categories);
    this.transactions = structuredClone(transactions);
    this.budgets = structuredClone(budgets);
    this.accounts = [{ id: 'account_primary', workspaceId: 'ws_household', bookId: 'book_arjun', name: 'Primary bank', institution: 'Demo Bank', accountMask: '0042', accountType: 'bank', currency: 'INR' }];
    this.rules = [];
    this.recurring = [{ id: 'recurring_salary', bookId: 'book_arjun', categoryId: 'cat_salary', name: 'Monthly salary', kind: 'income', amountMinor: 58786700n, currency: 'INR', cadence: 'monthly', nextDueAt: new Date('2026-09-25T05:30:00.000Z'), active: true }];
    this.comments = [];
    this.imports = [];
    this.audit = [];
    this.invitations = [];
    this.periodReviews = [];
    this.idempotency = new Map();
    this.ingestion = [];
  }

  async getUserById(id) { return this.users.find((user) => user.id === id) ?? null; }
  async getUserByFirebaseUid(uid) { return this.users.find((user) => user.firebaseUid === uid) ?? null; }
  async updateProfile(userId, { displayName }) {
    const user = this.users.find((item) => item.id === userId);
    if (!user) return null;
    user.displayName = displayName;
    return user;
  }
  async ping() { return true; }
  async close() { return undefined; }
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
  async updateMembershipRole(bookId, userId, role) {
    const membership = this.memberships.find((member) => member.bookId === bookId && member.userId === userId);
    if (!membership) return null;
    membership.role = role;
    return { ...membership, user: this.users.find((user) => user.id === userId) };
  }
  async countBookOwners(bookId) { return this.memberships.filter((member) => member.bookId === bookId && member.role === 'book_owner').length; }
  async removeMembership(bookId, userId) {
    const index = this.memberships.findIndex((member) => member.bookId === bookId && member.userId === userId);
    if (index === -1) return null;
    return this.memberships.splice(index, 1)[0];
  }
  async listInvitations(bookId) { return this.invitations.filter((item) => item.bookId === bookId && item.status === 'pending'); }
  async revokeInvitation(bookId, invitationId) {
    const invitation = this.invitations.find((item) => item.id === invitationId && item.bookId === bookId && item.status === 'pending');
    if (!invitation) return null;
    invitation.status = 'revoked'; invitation.updatedAt = new Date(); return invitation;
  }
  async createInvitation(data) {
    this.invitations.forEach((item) => { if (item.bookId === data.bookId && item.email === data.email && item.status === 'pending') item.status = 'revoked'; });
    const invitation = { id: randomUUID(), status: 'pending', createdAt: new Date(), updatedAt: new Date(), acceptedAt: null, ...data };
    this.invitations.push(invitation); return invitation;
  }
  async acceptInvitation(tokenHash, actor) {
    const invitation = this.invitations.find((item) => item.tokenHash === tokenHash && item.status === 'pending');
    if (!invitation) return null;
    if (new Date(invitation.expiresAt) <= new Date()) { invitation.status = 'expired'; return null; }
    if (invitation.email.toLowerCase() !== actor.email.toLowerCase()) { const error = new Error('Invitation email does not match the signed-in account'); error.statusCode = 403; error.code = 'INVITATION_EMAIL_MISMATCH'; throw error; }
    let user = actor.id ? await this.getUserById(actor.id) : await this.getUserByFirebaseUid(actor.firebaseUid);
    if (!user) {
      user = { id: randomUUID(), firebaseUid: actor.firebaseUid, email: actor.email.toLowerCase(), displayName: actor.displayName ?? null, createdAt: new Date(), updatedAt: new Date(), disabledAt: null };
      this.users.push(user);
    }
    const membership = this.memberships.find((item) => item.bookId === invitation.bookId && item.userId === user.id);
    if (membership) membership.role = invitation.role;
    else this.memberships.push({ bookId: invitation.bookId, userId: user.id, role: invitation.role, invitedById: invitation.invitedById, createdAt: new Date() });
    invitation.status = 'accepted'; invitation.acceptedAt = new Date(); invitation.updatedAt = new Date(); return { ...invitation, actorId: user.id };
  }
  async listCategories(workspaceId) { return this.categories.filter((category) => category.workspaceId === workspaceId && !category.archivedAt); }
  assertCategoryNameFree(workspaceId, name, exceptId) {
    if (this.categories.some((item) => item.workspaceId === workspaceId && item.name.toLowerCase() === name.toLowerCase() && item.id !== exceptId)) {
      const error = new Error('Another category in this workspace already uses that name'); error.statusCode = 409; error.code = 'CATEGORY_NAME_TAKEN'; throw error;
    }
  }
  async createCategory({ workspaceId, name, groupName, color }) {
    this.assertCategoryNameFree(workspaceId, name);
    const category = { id: randomUUID(), workspaceId, name, groupName, color, archivedAt: null };
    this.categories.push(category); return category;
  }
  async editCategory(workspaceId, categoryId, { name, groupName, color, archived }) {
    const category = this.categories.find((item) => item.id === categoryId && item.workspaceId === workspaceId);
    if (!category) return null;
    if (name !== undefined) { this.assertCategoryNameFree(workspaceId, name, category.id); category.name = name; }
    if (groupName !== undefined) category.groupName = groupName;
    if (color !== undefined) category.color = color;
    if (archived !== undefined) category.archivedAt = archived ? new Date() : null;
    return category;
  }
  withComments(transaction) { return transaction && { ...transaction, comments: this.comments.filter((comment) => comment.transactionId === transaction.id).sort((a, b) => a.createdAt - b.createdAt) }; }
  async listTransactions(bookId, { state, cursor, limit = 50 } = {}) {
    let items = this.transactions.filter((transaction) => transaction.bookId === bookId && (!state || transaction.state === state)).sort((a, b) => b.occurredAt - a.occurredAt);
    if (cursor) items = items.slice(items.findIndex((item) => item.id === cursor) + 1);
    return { items: items.slice(0, limit).map((item) => this.withComments(item)), nextCursor: items.length > limit ? items[limit - 1].id : null };
  }
  async getTransaction(bookId, transactionId) { return this.transactions.find((item) => item.bookId === bookId && item.id === transactionId) ?? null; }
  async updateTransaction(bookId, transactionId, fields, actorId) {
    const transaction = this.transactions.find((item) => item.bookId === bookId && item.id === transactionId);
    if (!transaction) return null;
    this.assertReferences({ bookId, accountId: fields.accountId ?? undefined, categoryIds: [] });
    const before = {}; const after = {};
    for (const [key, value] of Object.entries(fields)) {
      const next = key === 'amountMinor' ? parseMinor(value) : key === 'occurredAt' ? new Date(value) : value;
      before[key] = transaction[key] instanceof Date ? transaction[key].toISOString() : jsonSafe(transaction[key]);
      transaction[key] = next;
      after[key] = next instanceof Date ? next.toISOString() : jsonSafe(next);
    }
    transaction.updatedAt = new Date();
    await this.addAudit({ workspaceId: transaction.workspaceId, bookId, actorId, action: 'transaction.corrected', entityType: 'transaction', entityId: transaction.id, before, after });
    return this.withComments(transaction);
  }
  async listAccounts(bookId) { return this.accounts.filter((account) => account.bookId === bookId && !account.archivedAt); }
  async createAccount(data) { const account = { id: randomUUID(), archivedAt: null, ...data }; this.accounts.push(account); return account; }
  async updateAccount(bookId, accountId, { archived, ...fields }) {
    const account = this.accounts.find((item) => item.id === accountId && item.bookId === bookId);
    if (!account) return null;
    Object.entries(fields).forEach(([key, value]) => { account[key] = value; });
    if (archived !== undefined) account.archivedAt = archived ? new Date() : null;
    return account;
  }
  assertReferences({ bookId, workspaceId, accountId, categoryIds = [] }) {
    const book = this.books.find((item) => item.id === bookId);
    const invalidBook = !book || (workspaceId && book.workspaceId !== workspaceId);
    const invalidAccount = accountId && !this.accounts.some((item) => item.id === accountId && item.bookId === bookId && item.workspaceId === book?.workspaceId);
    const invalidCategory = categoryIds.filter(Boolean).some((id) => !this.categories.some((item) => item.id === id && item.workspaceId === book?.workspaceId));
    if (invalidBook || invalidAccount || invalidCategory) { const error = new Error('Referenced account or category is outside this book'); error.statusCode = 400; error.code = 'REFERENCE_SCOPE_ERROR'; throw error; }
  }
  async createTransaction(data, actorId, idempotencyKey) {
    const scopedKey = idempotencyKey ? `${data.workspaceId}:${actorId}:transaction.create:${idempotencyKey}` : null;
    if (scopedKey && this.idempotency.has(scopedKey)) return { ...this.idempotency.get(scopedKey), __idempotentReplay: true };
    this.assertReferences({ ...data, categoryIds: [data.categoryId] });
    const transaction = { id: randomUUID(), workspaceId: data.workspaceId, bookId: data.bookId, accountId: data.accountId ?? null, categoryId: data.categoryId ?? null,
      kind: data.kind, state: data.state ?? 'confirmed', amountMinor: parseMinor(data.amountMinor), currency: data.currency ?? 'INR', merchant: data.merchant ?? null,
      note: data.note ?? null, occurredAt: new Date(data.occurredAt), createdAt: new Date(), updatedAt: new Date(), sources: [{ id: randomUUID(), sourceType: 'manual', sourceReference: `manual:${randomUUID()}`, importedAmount: parseMinor(data.amountMinor) }], splits: [] };
    this.transactions.push(transaction); if (scopedKey) this.idempotency.set(scopedKey, transaction); return transaction;
  }
  async updateCategory(bookId, transactionId, categoryId, actorId, applyToFuture = false) {
    const transaction = await this.getTransaction(bookId, transactionId); if (!transaction) return null;
    this.assertReferences({ bookId, workspaceId: transaction.workspaceId, categoryIds: [categoryId] });
    const before = { categoryId: transaction.categoryId }; transaction.categoryId = categoryId; transaction.state = 'confirmed'; transaction.updatedAt = new Date();
    await this.addAudit({ workspaceId: transaction.workspaceId, bookId, actorId, action: 'transaction.reclassified', entityType: 'transaction', entityId: transaction.id, before, after: { categoryId } });
    if (applyToFuture && transaction.merchant) await this.createRule({ bookId, categoryId, matchType: 'merchant_exact', matchValue: transaction.merchant, createdById: actorId });
    return transaction;
  }
  async splitTransaction(bookId, transactionId, splits, actorId) {
    const transaction = await this.getTransaction(bookId, transactionId); if (!transaction) return null;
    this.assertReferences({ bookId, workspaceId: transaction.workspaceId, categoryIds: splits.map((split) => split.categoryId) });
    if (splits.some((split) => { const amount = parseMinor(split.amountMinor); return amount === 0n || (transaction.amountMinor < 0n) !== (amount < 0n); })) { const error = new Error('Split signs must match the transaction'); error.statusCode = 400; error.code = 'SPLIT_SIGN_MISMATCH'; throw error; }
    const expected = transaction.amountMinor < 0n ? -transaction.amountMinor : transaction.amountMinor;
    const actual = splits.reduce((sum, split) => sum + (parseMinor(split.amountMinor) < 0n ? -parseMinor(split.amountMinor) : parseMinor(split.amountMinor)), 0n);
    if (actual !== expected) { const error = new Error('Split amounts must equal the transaction amount'); error.statusCode = 400; error.code = 'SPLIT_TOTAL_MISMATCH'; throw error; }
    transaction.splits = splits.map((split) => ({ id: randomUUID(), ...split, amountMinor: parseMinor(split.amountMinor) }));
    await this.addAudit({ workspaceId: transaction.workspaceId, bookId, actorId, action: 'transaction.split', entityType: 'transaction', entityId: transaction.id, after: { splitCount: splits.length } });
    return transaction;
  }
  async addComment(bookId, transactionId, body, actorId) {
    const transaction = await this.getTransaction(bookId, transactionId); if (!transaction) return null;
    const comment = { id: randomUUID(), transactionId, authorId: actorId, body, createdAt: new Date() }; this.comments.push(comment);
    await this.addAudit({ workspaceId: transaction.workspaceId, bookId, actorId, action: 'transaction.commented', entityType: 'transaction', entityId: transaction.id, after: { commentId: comment.id } });
    return comment;
  }
  async ingest(data, actorId, idempotencyKey) {
    const key = `${data.workspaceId}:${data.sourceHash}`;
    const existing = this.ingestion.find((item) => item.key === key);
    if (existing) return { ...existing, duplicate: true };
    if (idempotencyKey && this.idempotency.has(idempotencyKey)) return this.idempotency.get(idempotencyKey);
    const event = { id: randomUUID(), key, ...data, amountMinor: parseMinor(data.amountMinor), state: 'received', createdAt: new Date(), duplicate: false };
    this.ingestion.push(event);
    // A rule the user already taught this book classifies the payment now, so a
    // repeat of a payment they categorised once does not come back for review.
    const rule = data.categoryId ? null : matchCategoryRule(await this.listRules(data.bookId), { merchant: data.merchant });
    const categoryId = data.categoryId ?? rule?.categoryId ?? null;
    const transaction = await this.createTransaction({ ...data, categoryId, state: categoryId ? 'confirmed' : 'pending_review' }, actorId, `ingestion:${key}`);
    if (rule) await this.addAudit({ workspaceId: data.workspaceId, bookId: data.bookId, actorId, action: 'transaction.auto_categorized', entityType: 'transaction', entityId: transaction.id, after: { categoryId, ruleId: rule.id, matchType: rule.matchType, matchValue: rule.matchValue } });
    transaction.sources = [{ id: randomUUID(), sourceType: data.sourceType, sourceReference: data.sourceHash, importedAmount: parseMinor(data.amountMinor) }];
    event.transactionId = transaction.id; if (idempotencyKey) this.idempotency.set(idempotencyKey, event); return event;
  }
  async listBudgets(bookId) { return this.budgets.filter((budget) => budget.bookId === bookId); }
  async upsertBudget({ bookId, categoryId, month, amountMinor, currency = 'INR' }) {
    this.assertReferences({ bookId, categoryIds: [categoryId] });
    const existing = this.budgets.find((budget) => budget.bookId === bookId && budget.categoryId === categoryId && String(budget.month).slice(0, 10) === month);
    if (existing) {
      existing.amountMinor = parseMinor(amountMinor); existing.currency = currency; return existing;
    }
    const budget = { id: randomUUID(), bookId, categoryId, month, amountMinor: parseMinor(amountMinor), currency };
    this.budgets.push(budget); return budget;
  }
  async listRules(bookId) { return this.rules.filter((rule) => rule.bookId === bookId); }
  async createRule(data) { this.assertReferences({ bookId: data.bookId, categoryIds: [data.categoryId] }); const rule = { id: randomUUID(), enabled: true, priority: 100, createdAt: new Date(), ...data }; this.rules.push(rule); return rule; }
  async updateRule(bookId, ruleId, fields) {
    const rule = this.rules.find((item) => item.id === ruleId && item.bookId === bookId);
    if (!rule) return null;
    this.assertReferences({ bookId, categoryIds: [fields.categoryId] });
    Object.entries(fields).forEach(([key, value]) => { rule[key] = value; });
    return rule;
  }
  async deleteRule(bookId, ruleId) {
    const index = this.rules.findIndex((item) => item.id === ruleId && item.bookId === bookId);
    if (index === -1) return null;
    return this.rules.splice(index, 1)[0];
  }
  async listRecurring(bookId) { return this.recurring.filter((plan) => plan.bookId === bookId && plan.active); }
  async createRecurring(data) { this.assertReferences({ bookId: data.bookId, categoryIds: [data.categoryId] }); const plan = { id: randomUUID(), active: true, ...data, amountMinor: parseMinor(data.amountMinor), nextDueAt: new Date(data.nextDueAt) }; this.recurring.push(plan); return plan; }
  async updateRecurring(bookId, planId, { amountMinor, nextDueAt, ...fields }) {
    const plan = this.recurring.find((item) => item.id === planId && item.bookId === bookId);
    if (!plan) return null;
    this.assertReferences({ bookId, categoryIds: [fields.categoryId] });
    Object.entries(fields).forEach(([key, value]) => { plan[key] = value; });
    if (amountMinor !== undefined) plan.amountMinor = parseMinor(amountMinor);
    if (nextDueAt !== undefined) plan.nextDueAt = new Date(nextDueAt);
    return plan;
  }
  // Post whatever the active plans owe. Entries land as pending_review, not
  // confirmed: a plan is a prediction, and the same payment will usually turn up
  // again from the bank, so it belongs in front of a human either way.
  async postDueRecurring(now = new Date()) {
    const posted = [];
    for (const plan of this.recurring.filter((item) => item.active)) {
      const { postings, nextDueAt } = duePostings(plan, now);
      if (!postings.length) continue;
      const book = this.books.find((item) => item.id === plan.bookId);
      const actorId = this.memberships.find((member) => member.bookId === plan.bookId && member.role === 'book_owner')?.userId ?? null;
      for (const dueAt of postings) {
        const transaction = await this.createTransaction({ workspaceId: book.workspaceId, bookId: plan.bookId, categoryId: plan.categoryId ?? null, kind: plan.kind,
          amountMinor: String(plan.amountMinor), currency: plan.currency ?? 'INR', merchant: plan.name, state: 'pending_review', occurredAt: dueAt.toISOString() }, actorId, postingKey(plan.id, dueAt));
        if (transaction.__idempotentReplay) continue;
        await this.addAudit({ workspaceId: book.workspaceId, bookId: plan.bookId, actorId, action: 'recurring.posted', entityType: 'transaction', entityId: transaction.id, after: { planId: plan.id, planName: plan.name, dueAt: dueAt.toISOString() } });
        posted.push({ planId: plan.id, transactionId: transaction.id, dueAt: dueAt.toISOString() });
      }
      plan.nextDueAt = nextDueAt;
    }
    return posted;
  }
  async listImports(bookId) { return this.imports.filter((item) => item.bookId === bookId).sort((a, b) => b.createdAt - a.createdAt); }
  async createImport(data) {
    const existing = this.imports.find((item) => item.bookId === data.bookId && item.sha256 === data.sha256);
    if (existing) return { ...existing, duplicate: true };
    const record = { id: randomUUID(), status: 'upload_pending', storageKey: `imports/${data.workspaceId}/${data.bookId}/${randomUUID()}`, createdAt: new Date(), duplicate: false, ...data };
    this.imports.push(record); return record;
  }
  async summary(bookId, month) {
    const timezone = this.books.find((book) => book.id === bookId)?.timezone ?? 'UTC';
    const txs = this.transactions.filter((item) => item.bookId === bookId && !['excluded', 'voided'].includes(item.state) && (!month || isInBookMonth(item.occurredAt, month, timezone)));
    const income = txs.filter((item) => item.kind === 'income').reduce((sum, item) => sum + item.amountMinor, 0n);
    const spent = txs.filter((item) => item.kind === 'expense').reduce((sum, item) => sum + -item.amountMinor, 0n);
    const byCategory = spendByCategory(txs, this.categories);
    return { incomeMinor: serializeMoney(income), spentMinor: serializeMoney(spent), savedMinor: serializeMoney(income - spent), pendingReview: txs.filter((item) => item.state === 'pending_review').length, byCategory };
  }
  async reviewPeriod(book, { month, status, note }, actorId) {
    if (status === 'verified' && this.transactions.some((item) => item.bookId === book.id && item.state === 'pending_review' && isInBookMonth(item.occurredAt, month, book.timezone))) {
      const error = new Error('Resolve pending transactions before verifying this period'); error.statusCode = 409; error.code = 'PERIOD_HAS_PENDING_TRANSACTIONS'; throw error;
    }
    let review = this.periodReviews.find((item) => item.bookId === book.id && item.month === month);
    const values = { status, note: note ?? null, reviewedById: actorId, reviewedAt: new Date(), updatedAt: new Date() };
    if (review) Object.assign(review, values); else { review = { id: randomUUID(), bookId: book.id, month, createdAt: new Date(), ...values }; this.periodReviews.push(review); }
    await this.addAudit({ workspaceId: book.workspaceId, bookId: book.id, actorId, action: `period.${status}`, entityType: 'period_review', entityId: review.id, after: { month, status, note: note ?? null } });
    return review;
  }
  async addAudit(event) { const record = { id: randomUUID(), createdAt: new Date(), ...event }; this.audit.unshift(record); return record; }
  async listAudit(bookId, limit = 50) { return this.audit.filter((event) => event.bookId === bookId).slice(0, limit); }
}
