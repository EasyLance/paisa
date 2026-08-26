import { PrismaClient } from '@prisma/client';
import { parseMinor, serializeMoney } from '../domain/money.js';

export class PrismaStore {
  constructor(client = new PrismaClient()) { this.db = client; }
  async getUserById(id) { return this.db.userProfile.findUnique({ where: { id } }); }
  async getUserByFirebaseUid(firebaseUid) { return this.db.userProfile.findUnique({ where: { firebaseUid } }); }
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
  async listCategories(workspaceId) { return this.db.category.findMany({ where: { workspaceId, archivedAt: null }, orderBy: [{ groupName: 'asc' }, { name: 'asc' }] }); }
  async createCategory(data) { return this.db.category.create({ data }); }
  async listTransactions(bookId, { state, cursor, limit = 50 } = {}) {
    const items = await this.db.transaction.findMany({ where: { bookId, ...(state ? { state } : {}) }, include: { sources: true, splits: true }, orderBy: [{ occurredAt: 'desc' }, { id: 'desc' }], take: limit + 1, ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}) });
    const hasMore = items.length > limit; if (hasMore) items.pop(); return { items, nextCursor: hasMore ? items.at(-1).id : null };
  }
  async getTransaction(bookId, id) { return this.db.transaction.findFirst({ where: { id, bookId }, include: { sources: true, splits: true } }); }
  async createTransaction(data, actorId) {
    const amountMinor = parseMinor(data.amountMinor);
    return this.db.$transaction(async (db) => {
      const transaction = await db.transaction.create({ data: { workspaceId: data.workspaceId, bookId: data.bookId, accountId: data.accountId ?? null, categoryId: data.categoryId ?? null,
        kind: data.kind, state: data.state ?? 'confirmed', amountMinor, currency: data.currency ?? 'INR', merchant: data.merchant ?? null, note: data.note ?? null,
        occurredAt: new Date(data.occurredAt), createdById: actorId } });
      await db.transactionSource.create({ data: { transactionId: transaction.id, sourceType: 'manual', sourceReference: `manual:${transaction.id}`, importedAmount: amountMinor } });
      return db.transaction.findUnique({ where: { id: transaction.id }, include: { sources: true, splits: true } });
    });
  }
  async updateCategory(bookId, id, categoryId, actorId, applyToFuture = false) {
    return this.db.$transaction(async (db) => {
      const current = await db.transaction.findFirst({ where: { id, bookId } }); if (!current) return null;
      const updated = await db.transaction.update({ where: { id }, data: { categoryId, state: 'confirmed' } });
      await db.auditEvent.create({ data: { workspaceId: current.workspaceId, bookId, actorId, action: 'transaction.reclassified', entityType: 'transaction', entityId: id,
        before: { categoryId: current.categoryId }, after: { categoryId } } });
      if (applyToFuture && current.merchant) await db.categorizationRule.create({ data: { bookId, categoryId, matchType: 'merchant_exact', matchValue: current.merchant, createdById: actorId } });
      return updated;
    });
  }
  async ingest(data, actorId) {
    const amountMinor = parseMinor(data.amountMinor);
    const existing = await this.db.ingestionEvent.findUnique({ where: { workspaceId_sourceHash: { workspaceId: data.workspaceId, sourceHash: data.sourceHash } } });
    if (existing) return { ...existing, duplicate: true };
    return this.db.$transaction(async (db) => {
      const event = await db.ingestionEvent.create({ data: { workspaceId: data.workspaceId, bookId: data.bookId, accountId: data.accountId ?? null, sourceType: data.sourceType,
        sourceHash: data.sourceHash, externalRef: data.externalRef ?? null, direction: data.kind, amountMinor, currency: data.currency ?? 'INR', merchant: data.merchant ?? null,
        occurredAt: new Date(data.occurredAt), metadata: data.metadata ?? undefined } });
      const transaction = await db.transaction.create({ data: { workspaceId: data.workspaceId, bookId: data.bookId, accountId: data.accountId ?? null, categoryId: data.categoryId ?? null,
        kind: data.kind, state: data.categoryId ? 'confirmed' : 'pending_review', amountMinor, currency: data.currency ?? 'INR', merchant: data.merchant ?? null, occurredAt: new Date(data.occurredAt), createdById: actorId } });
      await db.transactionSource.create({ data: { transactionId: transaction.id, ingestionEventId: event.id, sourceType: data.sourceType, sourceReference: data.sourceHash, importedAmount: amountMinor } });
      return { ...event, transactionId: transaction.id, duplicate: false };
    });
  }
  async listBudgets(bookId) { return this.db.budget.findMany({ where: { bookId }, include: { category: true }, orderBy: { month: 'desc' } }); }
  async summary(bookId) {
    const txs = await this.db.transaction.findMany({ where: { bookId, state: { notIn: ['excluded', 'voided'] } }, select: { kind: true, amountMinor: true, categoryId: true, state: true } });
    const income = txs.filter((item) => item.kind === 'income').reduce((sum, item) => sum + item.amountMinor, 0n);
    const spent = txs.filter((item) => item.kind === 'expense').reduce((sum, item) => sum + -item.amountMinor, 0n);
    const categories = await this.db.category.findMany({ where: { transactions: { some: { bookId } } } });
    const byCategory = categories.map((category) => ({ categoryId: category.id, name: category.name, groupName: category.groupName,
      amountMinor: txs.filter((item) => item.categoryId === category.id && item.kind === 'expense').reduce((sum, item) => sum + -item.amountMinor, 0n) })).filter((item) => item.amountMinor > 0n);
    return { incomeMinor: serializeMoney(income), spentMinor: serializeMoney(spent), savedMinor: serializeMoney(income - spent), pendingReview: txs.filter((item) => item.state === 'pending_review').length, byCategory };
  }
  async addAudit(data) { return this.db.auditEvent.create({ data }); }
  async listAudit(bookId, limit = 50) { return this.db.auditEvent.findMany({ where: { bookId }, orderBy: { createdAt: 'desc' }, take: limit }); }
}
