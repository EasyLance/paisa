import { PrismaClient } from '@prisma/client';
import { createHash } from 'node:crypto';
import { jsonSafe, parseMinor, serializeMoney } from '../domain/money.js';
import { monthRangeUtc } from '../domain/period.js';
import { matchCategoryRule } from '../domain/categorization.js';
import { spendByCategory } from '../domain/spending.js';
import { duePostings, postingKey } from '../domain/recurring.js';
import { assertCorrectable } from '../domain/permissions.js';

export class PrismaStore {
  constructor(client = new PrismaClient()) { this.db = client; }
  async assertReferences(db, { bookId, workspaceId, accountId, categoryIds = [] }) {
    const book = await db.book.findUnique({ where: { id: bookId }, select: { workspaceId: true } });
    const invalidBook = !book || (workspaceId && book.workspaceId !== workspaceId);
    const account = accountId ? await db.financialAccount.findFirst({ where: { id: accountId, bookId, workspaceId: book?.workspaceId } }) : true;
    const uniqueCategories = [...new Set(categoryIds.filter(Boolean))];
    const categoryCount = uniqueCategories.length ? await db.category.count({ where: { id: { in: uniqueCategories }, workspaceId: book?.workspaceId } }) : 0;
    if (invalidBook || !account || categoryCount !== uniqueCategories.length) { const error = new Error('Referenced account or category is outside this book'); error.statusCode = 400; error.code = 'REFERENCE_SCOPE_ERROR'; throw error; }
  }
  async getUserById(id) { return this.db.userProfile.findUnique({ where: { id } }); }
  async getUserByFirebaseUid(firebaseUid) { return this.db.userProfile.findUnique({ where: { firebaseUid } }); }
  async updateProfile(userId, { displayName }) {
    const current = await this.db.userProfile.findUnique({ where: { id: userId } });
    if (!current) return null;
    return this.db.userProfile.update({ where: { id: userId }, data: { displayName } });
  }
  async ping() { await this.db.$queryRaw`SELECT 1`; return true; }
  async close() { await this.db.$disconnect(); }
  async listWorkspaces(userId) {
    return this.db.workspace.findMany({ where: { books: { some: { memberships: { some: { userId } } } } }, orderBy: { name: 'asc' } });
  }
  async listBooks(userId) {
    const rows = await this.db.bookMembership.findMany({ where: { userId }, include: { book: true }, orderBy: { book: { name: 'asc' } } });
    return rows.map(({ book, role }) => ({ ...book, role }));
  }
  async getBook(id) { return this.db.book.findUnique({ where: { id } }); }
  async getMembership(bookId, userId) { return this.db.bookMembership.findUnique({ where: { bookId_userId: { bookId, userId } } }); }
  async listMemberships(bookId) { return this.db.bookMembership.findMany({ where: { bookId }, include: { user: true } }); }
  async updateMembershipRole(bookId, userId, role) {
    const current = await this.db.bookMembership.findUnique({ where: { bookId_userId: { bookId, userId } } });
    if (!current) return null;
    return this.db.bookMembership.update({ where: { bookId_userId: { bookId, userId } }, data: { role }, include: { user: true } });
  }
  async countBookOwners(bookId) { return this.db.bookMembership.count({ where: { bookId, role: 'book_owner' } }); }
  async removeMembership(bookId, userId) {
    const current = await this.db.bookMembership.findUnique({ where: { bookId_userId: { bookId, userId } } });
    if (!current) return null;
    await this.db.bookMembership.delete({ where: { bookId_userId: { bookId, userId } } });
    return current;
  }
  async listInvitations(bookId) { return this.db.bookInvitation.findMany({ where: { bookId, status: 'pending' }, orderBy: { createdAt: 'desc' }, select: { id: true, email: true, role: true, status: true, expiresAt: true, createdAt: true } }); }
  async revokeInvitation(bookId, invitationId) {
    const invitation = await this.db.bookInvitation.findFirst({ where: { id: invitationId, bookId, status: 'pending' } });
    if (!invitation) return null;
    return this.db.bookInvitation.update({ where: { id: invitationId }, data: { status: 'revoked' } });
  }
  async createInvitation(data) {
    return this.db.$transaction(async (db) => {
      await db.bookInvitation.updateMany({ where: { bookId: data.bookId, email: data.email, status: 'pending' }, data: { status: 'revoked' } });
      return db.bookInvitation.create({ data });
    });
  }
  async acceptInvitation(tokenHash, actor) {
    return this.db.$transaction(async (db) => {
      const invitation = await db.bookInvitation.findUnique({ where: { tokenHash } });
      if (!invitation || invitation.status !== 'pending') return null;
      if (invitation.expiresAt <= new Date()) { await db.bookInvitation.update({ where: { id: invitation.id }, data: { status: 'expired' } }); return null; }
      if (invitation.email.toLowerCase() !== actor.email.toLowerCase()) { const error = new Error('Invitation email does not match the signed-in account'); error.statusCode = 403; error.code = 'INVITATION_EMAIL_MISMATCH'; throw error; }
      let user = actor.id ? await db.userProfile.findUnique({ where: { id: actor.id } }) : await db.userProfile.findUnique({ where: { firebaseUid: actor.firebaseUid } });
      if (!user) {
        user = await db.userProfile.create({ data: { firebaseUid: actor.firebaseUid, email: actor.email.toLowerCase(), displayName: actor.displayName ?? null } });
      }
      await db.workspaceUser.upsert({ where: { workspaceId_userId: { workspaceId: invitation.workspaceId, userId: user.id } }, create: { workspaceId: invitation.workspaceId, userId: user.id }, update: {} });
      await db.bookMembership.upsert({ where: { bookId_userId: { bookId: invitation.bookId, userId: user.id } }, create: { bookId: invitation.bookId, userId: user.id, role: invitation.role, invitedById: invitation.invitedById }, update: { role: invitation.role } });
      const accepted = await db.bookInvitation.update({ where: { id: invitation.id }, data: { status: 'accepted', acceptedAt: new Date() } });
      return { ...accepted, actorId: user.id };
    });
  }
  async listCategories(workspaceId) { return this.db.category.findMany({ where: { workspaceId, archivedAt: null }, orderBy: [{ groupName: 'asc' }, { name: 'asc' }] }); }
  async createCategory(data) {
    try { return await this.db.category.create({ data }); }
    catch (error) { throw this.categoryNameConflict(error); }
  }
  categoryNameConflict(error) {
    if (error?.code !== 'P2002') return error;
    const conflict = new Error('Another category in this workspace already uses that name'); conflict.statusCode = 409; conflict.code = 'CATEGORY_NAME_TAKEN'; return conflict;
  }
  async editCategory(workspaceId, categoryId, { archived, ...fields }) {
    const current = await this.db.category.findFirst({ where: { id: categoryId, workspaceId } });
    if (!current) return null;
    const data = { ...fields, ...(archived === undefined ? {} : { archivedAt: archived ? new Date() : null }) };
    try { return await this.db.category.update({ where: { id: categoryId }, data }); }
    catch (error) { throw this.categoryNameConflict(error); }
  }
  async updateTransaction(bookId, transactionId, fields, actorId) {
    const include = { sources: true, splits: true, comments: { orderBy: { createdAt: 'asc' } } };
    return this.db.$transaction(async (db) => {
      const current = await db.transaction.findFirst({ where: { id: transactionId, bookId }, include: { sources: { select: { sourceType: true } } } });
      if (!current) return null;
      assertCorrectable(current.sources.map((source) => source.sourceType), fields, current.amountMinor);
      const data = { ...fields };
      if (fields.amountMinor !== undefined) data.amountMinor = parseMinor(fields.amountMinor);
      if (fields.occurredAt !== undefined) data.occurredAt = new Date(fields.occurredAt);
      const updated = await db.transaction.update({ where: { id: transactionId }, data, include });
      const snapshot = (row) => Object.fromEntries(Object.keys(fields).map((key) => [key, jsonSafe(row[key])]));
      await db.auditEvent.create({ data: { workspaceId: current.workspaceId, bookId, actorId, action: 'transaction.corrected', entityType: 'transaction', entityId: transactionId, before: snapshot(current), after: snapshot(updated) } });
      return updated;
    });
  }
  async listAccounts(bookId) { return this.db.financialAccount.findMany({ where: { bookId, archivedAt: null }, orderBy: { name: 'asc' } }); }
  async createAccount(data) { return this.db.financialAccount.create({ data }); }
  async updateAccount(bookId, accountId, { archived, ...fields }) {
    const current = await this.db.financialAccount.findFirst({ where: { id: accountId, bookId } });
    if (!current) return null;
    return this.db.financialAccount.update({ where: { id: accountId }, data: { ...fields, ...(archived === undefined ? {} : { archivedAt: archived ? new Date() : null }) } });
  }
  async listTransactions(bookId, { state, cursor, limit = 50 } = {}) {
    const items = await this.db.transaction.findMany({ where: { bookId, ...(state ? { state } : {}) }, include: { sources: true, splits: true, comments: { orderBy: { createdAt: 'asc' } } }, orderBy: [{ occurredAt: 'desc' }, { id: 'desc' }], take: limit + 1, ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}) });
    const hasMore = items.length > limit; if (hasMore) items.pop(); return { items, nextCursor: hasMore ? items.at(-1).id : null };
  }
  async getTransaction(bookId, id) { return this.db.transaction.findFirst({ where: { id, bookId }, include: { sources: true, splits: true, comments: { orderBy: { createdAt: 'asc' } } } }); }
  async createTransaction(data, actorId, idempotencyKey) {
    const amountMinor = parseMinor(data.amountMinor);
    const keyHash = createHash('sha256').update(idempotencyKey).digest('hex');
    const requestHash = createHash('sha256').update(JSON.stringify({ ...data, amountMinor: amountMinor.toString() })).digest('hex');
    const unique = { workspaceId_actorId_operation_keyHash: { workspaceId: data.workspaceId, actorId, operation: 'transaction.create', keyHash } };
    const existing = await this.db.idempotencyRecord.findUnique({ where: unique });
    if (existing) { if (existing.requestHash !== requestHash) { const error = new Error('Idempotency key was already used for a different request'); error.statusCode = 409; error.code = 'IDEMPOTENCY_CONFLICT'; throw error; } return { ...await this.getTransaction(data.bookId, existing.transactionId), __idempotentReplay: true }; }
    try {
      return await this.db.$transaction(async (db) => {
        await this.assertReferences(db, { ...data, categoryIds: [data.categoryId] });
        const transaction = await db.transaction.create({ data: { workspaceId: data.workspaceId, bookId: data.bookId, accountId: data.accountId ?? null, categoryId: data.categoryId ?? null,
          kind: data.kind, state: data.state ?? 'confirmed', amountMinor, currency: data.currency ?? 'INR', merchant: data.merchant ?? null, note: data.note ?? null,
          occurredAt: new Date(data.occurredAt), createdById: actorId } });
        await db.transactionSource.create({ data: { transactionId: transaction.id, sourceType: 'manual', sourceReference: `manual:${transaction.id}`, importedAmount: amountMinor } });
        await db.idempotencyRecord.create({ data: { workspaceId: data.workspaceId, actorId, operation: 'transaction.create', keyHash, requestHash, transactionId: transaction.id, expiresAt: new Date(Date.now()+24*60*60*1000) } });
        return db.transaction.findUnique({ where: { id: transaction.id }, include: { sources: true, splits: true } });
      });
    } catch (error) {
      if (error?.code !== 'P2002') throw error;
      const winner = await this.db.idempotencyRecord.findUnique({ where: unique });
      if (!winner || winner.requestHash !== requestHash) { const conflict = new Error('Idempotency key was already used for a different request'); conflict.statusCode = 409; conflict.code = 'IDEMPOTENCY_CONFLICT'; throw conflict; }
      return { ...await this.getTransaction(data.bookId, winner.transactionId), __idempotentReplay: true };
    }
  }
  async updateCategory(bookId, id, categoryId, actorId, applyToFuture = false) {
    return this.db.$transaction(async (db) => {
      const current = await db.transaction.findFirst({ where: { id, bookId } }); if (!current) return null;
      await this.assertReferences(db, { bookId, workspaceId: current.workspaceId, categoryIds: [categoryId] });
      const updated = await db.transaction.update({ where: { id }, data: { categoryId, state: 'confirmed' } });
      await db.auditEvent.create({ data: { workspaceId: current.workspaceId, bookId, actorId, action: 'transaction.reclassified', entityType: 'transaction', entityId: id,
        before: { categoryId: current.categoryId }, after: { categoryId } } });
      if (applyToFuture && current.merchant) await db.categorizationRule.create({ data: { bookId, categoryId, matchType: 'merchant_exact', matchValue: current.merchant, createdById: actorId } });
      return updated;
    });
  }
  async splitTransaction(bookId, id, splits, actorId) {
    return this.db.$transaction(async (db) => {
      const current = await db.transaction.findFirst({ where: { id, bookId } }); if (!current) return null;
      await this.assertReferences(db, { bookId, workspaceId: current.workspaceId, categoryIds: splits.map((split) => split.categoryId) });
      if (splits.some((split) => { const amount = parseMinor(split.amountMinor); return amount === 0n || (current.amountMinor < 0n) !== (amount < 0n); })) { const error = new Error('Split signs must match the transaction'); error.statusCode = 400; error.code = 'SPLIT_SIGN_MISMATCH'; throw error; }
      const expected = current.amountMinor < 0n ? -current.amountMinor : current.amountMinor;
      const actual = splits.reduce((sum, split) => { const amount = parseMinor(split.amountMinor); return sum + (amount < 0n ? -amount : amount); }, 0n);
      if (actual !== expected) { const error = new Error('Split amounts must equal the transaction amount'); error.statusCode = 400; error.code = 'SPLIT_TOTAL_MISMATCH'; throw error; }
      await db.transactionSplit.deleteMany({ where: { transactionId: id } });
      await db.transactionSplit.createMany({ data: splits.map((split) => ({ transactionId: id, categoryId: split.categoryId, amountMinor: parseMinor(split.amountMinor), note: split.note ?? null })) });
      await db.auditEvent.create({ data: { workspaceId: current.workspaceId, bookId, actorId, action: 'transaction.split', entityType: 'transaction', entityId: id, after: { splitCount: splits.length } } });
      return db.transaction.findUnique({ where: { id }, include: { sources: true, splits: true } });
    });
  }
  async addComment(bookId, transactionId, body, actorId) {
    return this.db.$transaction(async (db) => {
      const transaction = await db.transaction.findFirst({ where: { id: transactionId, bookId } }); if (!transaction) return null;
      const comment = await db.comment.create({ data: { transactionId, authorId: actorId, body } });
      await db.auditEvent.create({ data: { workspaceId: transaction.workspaceId, bookId, actorId, action: 'transaction.commented', entityType: 'transaction', entityId: transactionId, after: { commentId: comment.id } } });
      return comment;
    });
  }
  async ingest(data, actorId) {
    const amountMinor = parseMinor(data.amountMinor);
    const unique = { workspaceId_sourceHash: { workspaceId: data.workspaceId, sourceHash: data.sourceHash } };
    const findExisting = async () => { const event = await this.db.ingestionEvent.findUnique({ where: unique, include: { source: { select: { transactionId: true } } } }); return event ? { ...event, transactionId: event.source?.transactionId ?? null, duplicate: true } : null; };
    const existing = await findExisting(); if (existing) return existing;
    try {
      return await this.db.$transaction(async (db) => {
        await this.assertReferences(db, { ...data, categoryIds: [data.categoryId] });
        const event = await db.ingestionEvent.create({ data: { workspaceId: data.workspaceId, bookId: data.bookId, accountId: data.accountId ?? null, sourceType: data.sourceType,
          sourceHash: data.sourceHash, externalRef: data.externalRef ?? null, direction: data.kind, amountMinor, currency: data.currency ?? 'INR', merchant: data.merchant ?? null,
          occurredAt: new Date(data.occurredAt), metadata: data.metadata ?? undefined } });
        // A rule the user already taught this book classifies the payment now, so a
        // repeat of a payment they categorised once does not come back for review.
        const rule = data.categoryId ? null : matchCategoryRule(await db.categorizationRule.findMany({ where: { bookId: data.bookId }, orderBy: { priority: 'asc' } }), { merchant: data.merchant });
        const categoryId = data.categoryId ?? rule?.categoryId ?? null;
        const transaction = await db.transaction.create({ data: { workspaceId: data.workspaceId, bookId: data.bookId, accountId: data.accountId ?? null, categoryId,
          kind: data.kind, state: categoryId ? 'confirmed' : 'pending_review', amountMinor, currency: data.currency ?? 'INR', merchant: data.merchant ?? null, note: data.note ?? null, occurredAt: new Date(data.occurredAt), createdById: actorId } });
        if (rule) await db.auditEvent.create({ data: { workspaceId: data.workspaceId, bookId: data.bookId, actorId, action: 'transaction.auto_categorized', entityType: 'transaction', entityId: transaction.id, after: { categoryId, ruleId: rule.id, matchType: rule.matchType, matchValue: rule.matchValue } } });
        await db.transactionSource.create({ data: { transactionId: transaction.id, ingestionEventId: event.id, sourceType: data.sourceType, sourceReference: data.sourceHash, importedAmount: amountMinor } });
        return { ...event, transactionId: transaction.id, duplicate: false };
      });
    } catch (error) {
      if (error?.code !== 'P2002') throw error;
      const winner = await findExisting(); if (winner) return winner; throw error;
    }
  }
  async listBudgets(bookId) { return this.db.budget.findMany({ where: { bookId }, include: { category: true }, orderBy: { month: 'desc' } }); }
  async upsertBudget({ bookId, categoryId, month, amountMinor, currency = 'INR' }) {
    const date = new Date(`${month}T00:00:00.000Z`);
    await this.assertReferences(this.db, { bookId, categoryIds: [categoryId] });
    return this.db.budget.upsert({
      where: { bookId_categoryId_month: { bookId, categoryId, month: date } },
      create: { bookId, categoryId, month: date, amountMinor: parseMinor(amountMinor), currency },
      update: { amountMinor: parseMinor(amountMinor), currency },
      include: { category: true },
    });
  }
  async listRules(bookId) { return this.db.categorizationRule.findMany({ where: { bookId }, orderBy: { priority: 'asc' } }); }
  async createRule(data) { await this.assertReferences(this.db, { bookId: data.bookId, categoryIds: [data.categoryId] }); return this.db.categorizationRule.create({ data }); }
  async updateRule(bookId, ruleId, fields) {
    const current = await this.db.categorizationRule.findFirst({ where: { id: ruleId, bookId } });
    if (!current) return null;
    await this.assertReferences(this.db, { bookId, categoryIds: [fields.categoryId] });
    return this.db.categorizationRule.update({ where: { id: ruleId }, data: fields });
  }
  async deleteRule(bookId, ruleId) {
    const current = await this.db.categorizationRule.findFirst({ where: { id: ruleId, bookId } });
    if (!current) return null;
    await this.db.categorizationRule.delete({ where: { id: ruleId } });
    return current;
  }
  async listRecurring(bookId) { return this.db.recurringPlan.findMany({ where: { bookId, active: true }, orderBy: { nextDueAt: 'asc' } }); }
  async createRecurring(data) { await this.assertReferences(this.db, { bookId: data.bookId, categoryIds: [data.categoryId] }); return this.db.recurringPlan.create({ data: { ...data, amountMinor: parseMinor(data.amountMinor), nextDueAt: new Date(data.nextDueAt) } }); }
  async updateRecurring(bookId, planId, { amountMinor, nextDueAt, ...fields }) {
    const current = await this.db.recurringPlan.findFirst({ where: { id: planId, bookId } });
    if (!current) return null;
    await this.assertReferences(this.db, { bookId, categoryIds: [fields.categoryId] });
    return this.db.recurringPlan.update({ where: { id: planId }, data: { ...fields, ...(amountMinor === undefined ? {} : { amountMinor: parseMinor(amountMinor) }), ...(nextDueAt === undefined ? {} : { nextDueAt: new Date(nextDueAt) }) } });
  }
  // Post whatever the active plans owe. Entries land as pending_review, not
  // confirmed: a plan is a prediction, and the same payment will usually turn up
  // again from the bank, so it belongs in front of a human either way.
  async postDueRecurring(now = new Date()) {
    const plans = await this.db.recurringPlan.findMany({ where: { active: true, nextDueAt: { lte: now } }, include: { book: { select: { workspaceId: true } } } });
    const posted = [];
    for (const plan of plans) {
      const { postings, nextDueAt } = duePostings(plan, now);
      if (!postings.length) continue;
      const owner = await this.db.bookMembership.findFirst({ where: { bookId: plan.bookId, role: 'book_owner' }, select: { userId: true } });
      for (const dueAt of postings) {
        const transaction = await this.createTransaction({ workspaceId: plan.book.workspaceId, bookId: plan.bookId, categoryId: plan.categoryId ?? null, kind: plan.kind,
          amountMinor: plan.amountMinor.toString(), currency: plan.currency, merchant: plan.name, state: 'pending_review', occurredAt: dueAt.toISOString() }, owner?.userId ?? null, postingKey(plan.id, dueAt));
        if (transaction.__idempotentReplay) continue;
        await this.db.auditEvent.create({ data: { workspaceId: plan.book.workspaceId, bookId: plan.bookId, actorId: owner?.userId ?? null, action: 'recurring.posted', entityType: 'transaction', entityId: transaction.id, after: { planId: plan.id, planName: plan.name, dueAt: dueAt.toISOString() } } });
        posted.push({ planId: plan.id, transactionId: transaction.id, dueAt: dueAt.toISOString() });
      }
      await this.db.recurringPlan.update({ where: { id: plan.id }, data: { nextDueAt } });
    }
    return posted;
  }
  async listImports(bookId) { return this.db.attachment.findMany({ where: { bookId, transactionId: null, contentType: { in: ['text/csv', 'application/pdf'] } }, orderBy: { createdAt: 'desc' }, take: 25 }); }
  async createImport(data) {
    const storageKey = `imports/${data.workspaceId}/${data.bookId}/${data.sha256}`;
    const existing = await this.db.attachment.findFirst({ where: { bookId: data.bookId, sha256: data.sha256, contentType: { in: ['text/csv', 'application/pdf'] } } });
    if (existing) return { ...existing, duplicate: true, status: 'already_uploaded' };
    const record = await this.db.attachment.create({ data: { bookId: data.bookId, storageKey, contentType: data.contentType, sizeBytes: data.sizeBytes, sha256: data.sha256, expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000) } });
    return { ...record, duplicate: false, status: 'upload_pending' };
  }
  async summary(bookId, month) {
    const book = await this.db.book.findUnique({ where: { id: bookId }, select: { timezone: true, workspaceId: true } });
    const range = month ? monthRangeUtc(month, book?.timezone ?? 'UTC') : null; const period = range ? { gte: range.start, lt: range.end } : undefined;
    const txs = await this.db.transaction.findMany({ where: { bookId, state: { notIn: ['excluded', 'voided'] }, ...(period ? { occurredAt: period } : {}) }, select: { kind: true, amountMinor: true, categoryId: true, state: true, splits: { select: { categoryId: true, amountMinor: true } } } });
    const income = txs.filter((item) => item.kind === 'income').reduce((sum, item) => sum + item.amountMinor, 0n);
    const spent = txs.filter((item) => item.kind === 'expense').reduce((sum, item) => sum + -item.amountMinor, 0n);
    // Every category in the workspace, not just those already on a transaction:
    // a split can name a category the parent row does not.
    const categories = await this.db.category.findMany({ where: { workspaceId: book?.workspaceId } });
    const byCategory = spendByCategory(txs, categories);
    return { incomeMinor: serializeMoney(income), spentMinor: serializeMoney(spent), savedMinor: serializeMoney(income - spent), pendingReview: txs.filter((item) => item.state === 'pending_review').length, byCategory };
  }
  async reviewPeriod(book, { month, status, note }, actorId) {
    const { start, end } = monthRangeUtc(month, book.timezone);
    return this.db.$transaction(async (db) => {
      if (status === 'verified') {
        const pending = await db.transaction.count({ where: { bookId: book.id, state: 'pending_review', occurredAt: { gte: start, lt: end } } });
        if (pending) { const error = new Error('Resolve pending transactions before verifying this period'); error.statusCode = 409; error.code = 'PERIOD_HAS_PENDING_TRANSACTIONS'; throw error; }
      }
      const reviewedAt = new Date();
      const review = await db.periodReview.upsert({ where: { bookId_month: { bookId: book.id, month: start } }, create: { bookId: book.id, month: start, status, note: note ?? null, reviewedById: actorId, reviewedAt }, update: { status, note: note ?? null, reviewedById: actorId, reviewedAt } });
      await db.auditEvent.create({ data: { workspaceId: book.workspaceId, bookId: book.id, actorId, action: `period.${status}`, entityType: 'period_review', entityId: review.id, after: { month, status, note: note ?? null } } });
      return review;
    });
  }
  async addAudit(data) { return this.db.auditEvent.create({ data }); }
  async listAudit(bookId, limit = 50) { return this.db.auditEvent.findMany({ where: { bookId }, orderBy: { createdAt: 'desc' }, take: limit }); }
}
