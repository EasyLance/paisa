import Fastify from 'fastify';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import swagger from '@fastify/swagger';
import swaggerUi from '@fastify/swagger-ui';
import { z } from 'zod';
import { createHash, randomBytes } from 'node:crypto';
import authPlugin from './plugins/auth.js';
import { assertCapability } from './domain/permissions.js';
import { jsonSafe } from './domain/money.js';
import { MAX_PERIOD_START_DAY, MIN_PERIOD_START_DAY } from './domain/period.js';
import { createStore } from './store/index.js';
import { parseStatementCsv, parseStatementXlsx } from './domain/statement.js';
import { mergeDirectory, platformAdmins } from './domain/platform-admin.js';
import { createFirebaseUser, deleteFirebaseUser, firebaseAdminConfigured, listFirebaseUsers, lookupFirebaseUser, sendFirebasePasswordReset, updateFirebaseUser } from './domain/firebase-admin.js';

const transactionFields = z.object({
  accountId: z.string().nullable().optional(), counterAccountId: z.string().nullable().optional(), categoryId: z.string().nullable().optional(), kind: z.enum(['expense', 'income', 'transfer', 'refund']),
  amountMinor: z.string().regex(/^-?\d+$/), currency: z.string().length(3).default('INR'), merchant: z.string().max(160).nullable().optional(),
  note: z.string().max(2000).nullable().optional(), occurredAt: z.string().datetime(), state: z.enum(['pending_review', 'confirmed']).optional(),
});
function validateAmountSign(value, context) {
  const amount = BigInt(value.amountMinor);
  if (amount === 0n) context.addIssue({ code: 'custom', path: ['amountMinor'], message: 'Amount cannot be zero' });
  if (value.kind === 'expense' && amount >= 0n) context.addIssue({ code: 'custom', path: ['amountMinor'], message: 'Expense amounts must be negative' });
  if (['income', 'refund'].includes(value.kind) && amount <= 0n) context.addIssue({ code: 'custom', path: ['amountMinor'], message: `${value.kind} amounts must be positive` });
}
const transactionInput = transactionFields.superRefine(validateAmountSign);

const ingestionInput = transactionFields.extend({ sourceType: z.enum(['sms', 'statement']), sourceHash: z.string().min(16).max(128), externalRef: z.string().max(120).optional(), metadata: z.record(z.string(), z.unknown()).optional() }).superRefine(validateAmountSign);
const recurringInput = z.object({ categoryId: z.string().nullable().optional(), name: z.string().trim().min(1).max(120), kind: z.enum(['expense', 'income']), amountMinor: z.string().regex(/^-?\d+$/), currency: z.string().length(3).default('INR'), cadence: z.enum(['weekly', 'monthly', 'quarterly', 'yearly']), nextDueAt: z.string().datetime() }).superRefine(validateAmountSign);

const recurringPatch = z.object({
  categoryId: z.string().nullable().optional(), name: z.string().trim().min(1).max(120).optional(), kind: z.enum(['expense', 'income']).optional(),
  amountMinor: z.string().regex(/^-?\d+$/).optional(), cadence: z.enum(['weekly', 'monthly', 'quarterly', 'yearly']).optional(), nextDueAt: z.string().datetime().optional(), active: z.boolean().optional(),
}).superRefine((value, context) => {
  if ((value.amountMinor === undefined) !== (value.kind === undefined)) context.addIssue({ code: 'custom', path: ['amountMinor'], message: 'Provide kind and amountMinor together' });
  else if (value.amountMinor !== undefined) validateAmountSign(value, context);
});
const transactionPatch = z.object({
  merchant: z.string().max(160).nullable().optional(), note: z.string().max(2000).nullable().optional(),
  amountMinor: z.string().regex(/^-?\d+$/).optional(), kind: z.enum(['expense', 'income', 'transfer', 'refund']).optional(),
  occurredAt: z.string().datetime().optional(), state: z.enum(['pending_review', 'confirmed', 'reconciled', 'excluded', 'voided']).optional(),
  accountId: z.string().nullable().optional(), counterAccountId: z.string().nullable().optional(),
}).superRefine((value, context) => {
  requireFields(value, context);
  // The sign carries the direction, so changing one without the other would
  // silently turn income into an expense or vice versa.
  if ((value.amountMinor === undefined) !== (value.kind === undefined)) context.addIssue({ code: 'custom', path: ['amountMinor'], message: 'Provide kind and amountMinor together' });
  else if (value.amountMinor !== undefined) validateAmountSign(value, context);
});

const budgetPlanInput = z.object({
  allocations: z.array(z.object({ groupName: z.string().trim().min(1).max(80), percent: z.number().int().min(0).max(100) })).max(20),
}).superRefine((value, context) => {
  const names = value.allocations.map((entry) => entry.groupName.toLowerCase());
  if (new Set(names).size !== names.length) context.addIssue({ code: 'custom', path: ['allocations'], message: 'Each group can only be given one share' });
  const total = value.allocations.reduce((sum, entry) => sum + entry.percent, 0);
  if (total > 100) context.addIssue({ code: 'custom', path: ['allocations'], message: `Shares add up to ${total}% — they cannot exceed 100%` });
});

const MAX_STATEMENT_ROWS = 2000;
const XLSX_MIME = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
const PARSEABLE = ['text/csv', XLSX_MIME];

const importInput = z.object({
  fileName: z.string().trim().min(1).max(180), contentType: z.enum(['text/csv', 'application/pdf', XLSX_MIME]),
  sizeBytes: z.number().int().positive().max(10 * 1024 * 1024), sha256: z.string().regex(/^[a-f0-9]{64}$/i),
  // CSV arrives as text; a spreadsheet is binary, so it arrives base64-encoded.
  accountId: z.string().nullable().optional(), content: z.string().max(3 * 1024 * 1024).optional(),
}).superRefine((value, context) => {
  if (value.content !== undefined && !PARSEABLE.includes(value.contentType)) context.addIssue({ code: 'custom', path: ['content'], message: 'PDF statements cannot be read yet — export the statement as CSV or Excel' });
});

function requireFields(value, context) {
  if (!Object.keys(value).length) context.addIssue({ code: 'custom', path: [], message: 'Provide at least one field to update' });
}

function parse(schema, input) {
  const result = schema.safeParse(input);
  if (!result.success) { const error = new Error('Request validation failed'); error.statusCode = 400; error.code = 'VALIDATION_ERROR'; error.details = result.error.flatten(); throw error; }
  return result.data;
}
function requireIdempotencyKey(request) {
  const value = request.headers['idempotency-key'];
  if (typeof value !== 'string' || value.length < 8 || value.length > 200) { const error = new Error('A valid Idempotency-Key header is required'); error.statusCode = 400; error.code = 'IDEMPOTENCY_KEY_REQUIRED'; throw error; }
  return value;
}

export async function buildApp(options = {}) {
  const trustedProxyHops = options.trustProxy ?? (process.env.TRUST_PROXY_HOPS ? Number(process.env.TRUST_PROXY_HOPS) : false);
  const app = Fastify({ logger: options.logger ?? false, trustProxy: trustedProxyHops, bodyLimit: 5 * 1024 * 1024 });
  app.decorate('store', options.store ?? await createStore({ memory: options.memory }));
  await app.register(cors, { origin: (process.env.CORS_ORIGINS ?? 'http://localhost:3000').split(','), credentials: true, methods: ['GET', 'HEAD', 'POST', 'PATCH', 'PUT', 'DELETE'] });
  await app.register(helmet, { contentSecurityPolicy: false });
  await app.register(rateLimit, { max: 120, timeWindow: '1 minute' });
  await app.register(swagger, { openapi: { info: { title: 'Paisa API', description: 'Private, auditable household finance API', version: '0.1.0' }, servers: [{ url: '/v1' }], components: { securitySchemes: { bearerAuth: { type: 'http', scheme: 'bearer', bearerFormat: 'JWT' } } } } });
  await app.register(swaggerUi, { routePrefix: '/docs' });
  await app.register(authPlugin, { mode: options.authMode });

  app.setErrorHandler((error, _request, reply) => {
    const status = error.statusCode ?? 500;
    reply.code(status).send({ code: error.code ?? (status === 500 ? 'INTERNAL_ERROR' : 'REQUEST_ERROR'), message: status === 500 ? 'Unexpected server error' : error.message, ...(error.details ? { details: error.details } : {}) });
  });
  app.addHook('preSerialization', async (_request, _reply, payload) => jsonSafe(payload));
  app.addHook('onClose', async () => { await app.store.close?.(); });

  app.get('/health', async () => ({ status: 'ok', service: 'paisa-api' }));
  app.get('/ready', async (_request, reply) => {
    try {
      await app.store.ping();
      return { status: 'ready', service: 'paisa-api', datastore: 'reachable' };
    } catch {
      return reply.code(503).send({ status: 'not_ready', service: 'paisa-api', datastore: 'unreachable' });
    }
  });

  async function access(request, capability = 'read') {
    const book = await app.store.getBook(request.params.bookId); if (!book) { const error = new Error('Book not found'); error.statusCode = 404; error.code = 'NOT_FOUND'; throw error; }
    const membership = await app.store.getMembership(book.id, request.actor.id); if (!membership) { const error = new Error('Book not found'); error.statusCode = 404; error.code = 'NOT_FOUND'; throw error; }
    assertCapability(membership.role, capability); return { book, membership };
  }

  app.register(async function v1(api) {
    api.addHook('preHandler', app.authenticate);
    api.get('/me', async (request) => ({ id: request.actor.id, email: request.actor.email, displayName: request.actor.displayName ?? null }));
    api.patch('/me', async (request) => {
      // Only the display name is editable here: email and password belong to the
      // identity provider, not this ledger.
      const body = parse(z.object({ displayName: z.string().trim().min(1).max(120) }), request.body);
      const profile = await app.store.updateProfile(request.actor.id, body);
      if (!profile) { const error = new Error('Profile not found'); error.statusCode = 404; error.code = 'NOT_FOUND'; throw error; }
      return { id: profile.id, email: profile.email, displayName: profile.displayName ?? null };
    });
    api.get('/workspaces', async (request) => ({ items: await app.store.listWorkspaces(request.actor.id) }));
    api.get('/books', async (request) => ({ items: await app.store.listBooks(request.actor.id) }));
    api.patch('/books/:bookId', async (request) => {
      const { book } = await access(request, 'manage_book');
      // 1 is a calendar month. Anything else moves the boundary to just before
      // payday, so a salary always lands at the start of the period it funds.
      // 28 is the ceiling: no month is missing that day.
      const body = parse(z.object({
        name: z.string().trim().min(1).max(120).optional(),
        periodStartDay: z.number().int().min(MIN_PERIOD_START_DAY).max(MAX_PERIOD_START_DAY).optional(),
      }).superRefine(requireFields), request.body);
      const updated = await app.store.updateBook(book.id, body);
      if (!updated) { const error = new Error('Book not found'); error.statusCode = 404; error.code = 'NOT_FOUND'; throw error; }
      await app.store.addAudit({ workspaceId: book.workspaceId, bookId: book.id, actorId: request.actor.id, action: 'book.updated', entityType: 'book', entityId: book.id, before: { name: book.name, periodStartDay: book.periodStartDay ?? 1 }, after: body });
      return updated;
    });
    api.get('/books/:bookId/memberships', async (request) => { await access(request, 'manage_book'); return { items: await app.store.listMemberships(request.params.bookId) }; });
    async function assertNotLastOwner(book, userId, actorId) {
      if (userId === actorId) { const error = new Error('You cannot change or remove your own access to this book'); error.statusCode = 409; error.code = 'SELF_ACCESS_CHANGE'; throw error; }
      const membership = await app.store.getMembership(book.id, userId);
      if (membership?.role === 'book_owner' && await app.store.countBookOwners(book.id) < 2) { const error = new Error('A book must keep at least one owner'); error.statusCode = 409; error.code = 'LAST_OWNER'; throw error; }
    }
    api.patch('/books/:bookId/memberships/:userId', async (request) => { const { book } = await access(request, 'manage_book'); const body = parse(z.object({ role: z.enum(['book_owner', 'editor', 'reviewer', 'viewer']) }), request.body); await assertNotLastOwner(book, request.params.userId, request.actor.id); const membership = await app.store.updateMembershipRole(book.id, request.params.userId, body.role); if (!membership) { const error = new Error('Membership not found'); error.statusCode = 404; error.code = 'NOT_FOUND'; throw error; } await app.store.addAudit({ workspaceId: book.workspaceId, bookId: book.id, actorId: request.actor.id, action: 'membership.role_changed', entityType: 'book_membership', entityId: request.params.userId, after: { role: body.role } }); return membership; });
    api.delete('/books/:bookId/memberships/:userId', async (request, reply) => {
      const { book } = await access(request, 'manage_book');
      await assertNotLastOwner(book, request.params.userId, request.actor.id);
      const removed = await app.store.removeMembership(book.id, request.params.userId);
      if (!removed) { const error = new Error('Membership not found'); error.statusCode = 404; error.code = 'NOT_FOUND'; throw error; }
      await app.store.addAudit({ workspaceId: book.workspaceId, bookId: book.id, actorId: request.actor.id, action: 'membership.removed', entityType: 'book_membership', entityId: request.params.userId, before: { role: removed.role } });
      return reply.code(204).send();
    });
    api.delete('/books/:bookId/invitations/:invitationId', async (request, reply) => {
      const { book } = await access(request, 'manage_book');
      const invitation = await app.store.revokeInvitation(book.id, request.params.invitationId);
      if (!invitation) { const error = new Error('Invitation not found'); error.statusCode = 404; error.code = 'NOT_FOUND'; throw error; }
      await app.store.addAudit({ workspaceId: book.workspaceId, bookId: book.id, actorId: request.actor.id, action: 'membership.invitation_revoked', entityType: 'book_invitation', entityId: invitation.id, before: { email: invitation.email, role: invitation.role } });
      return reply.code(204).send();
    });
    api.get('/books/:bookId/invitations', async (request) => { await access(request, 'manage_book'); return { items: await app.store.listInvitations(request.params.bookId) }; });
    api.post('/books/:bookId/invitations', async (request, reply) => { const { book } = await access(request, 'manage_book'); const body = parse(z.object({ email: z.string().email().transform((value) => value.trim().toLowerCase()), role: z.enum(['editor', 'reviewer', 'viewer']) }), request.body); const token = randomBytes(32).toString('base64url'); const tokenHash = createHash('sha256').update(token).digest('hex'); const invitation = await app.store.createInvitation({ workspaceId: book.workspaceId, bookId: book.id, email: body.email, role: body.role, tokenHash, invitedById: request.actor.id, expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000) }); await app.store.addAudit({ workspaceId: book.workspaceId, bookId: book.id, actorId: request.actor.id, action: 'membership.invited', entityType: 'book_invitation', entityId: invitation.id, after: { email: body.email, role: body.role } }); return reply.code(201).send({ id: invitation.id, email: invitation.email, role: invitation.role, status: invitation.status, expiresAt: invitation.expiresAt, createdAt: invitation.createdAt, token }); });
    api.post('/invitations/accept', async (request) => { const body = parse(z.object({ token: z.string().min(32).max(256) }), request.body); const tokenHash = createHash('sha256').update(body.token).digest('hex'); const invitation = await app.store.acceptInvitation(tokenHash, request.actor); if (!invitation) { const error = new Error('Invitation is invalid or expired'); error.statusCode = 404; error.code = 'INVITATION_INVALID'; throw error; } await app.store.addAudit({ workspaceId: invitation.workspaceId, bookId: invitation.bookId, actorId: invitation.actorId, action: 'membership.accepted', entityType: 'book_invitation', entityId: invitation.id, after: { role: invitation.role } }); return { accepted: true, bookId: invitation.bookId, role: invitation.role }; });
    api.get('/books/:bookId/accounts', async (request) => { await access(request); return { items: await app.store.listAccounts(request.params.bookId) }; });
    api.post('/books/:bookId/accounts', async (request, reply) => { const { book } = await access(request, 'manage_book'); const body = parse(z.object({ name: z.string().min(1).max(80), institution: z.string().max(120).nullable().optional(), accountMask: z.string().max(8).nullable().optional(), accountType: z.enum(['bank', 'cash', 'credit_card', 'wallet']), currency: z.string().length(3).default('INR') }), request.body); const account = await app.store.createAccount({ ...body, workspaceId: book.workspaceId, bookId: book.id, openingBalance: 0n }); return reply.code(201).send(account); });
    api.patch('/books/:bookId/accounts/:accountId', async (request) => {
      const { book } = await access(request, 'manage_book');
      const body = parse(z.object({ name: z.string().min(1).max(80).optional(), institution: z.string().max(120).nullable().optional(), accountMask: z.string().max(8).nullable().optional(), accountType: z.enum(['bank', 'cash', 'credit_card', 'wallet']).optional(), archived: z.boolean().optional() }).superRefine(requireFields), request.body);
      const account = await app.store.updateAccount(book.id, request.params.accountId, body);
      if (!account) { const error = new Error('Account not found'); error.statusCode = 404; error.code = 'NOT_FOUND'; throw error; }
      await app.store.addAudit({ workspaceId: book.workspaceId, bookId: book.id, actorId: request.actor.id, action: body.archived === true ? 'account.archived' : 'account.updated', entityType: 'financial_account', entityId: account.id, after: body });
      return account;
    });
    api.patch('/books/:bookId/categories/:categoryId', async (request) => {
      const { book } = await access(request, 'edit');
      const body = parse(z.object({ name: z.string().min(1).max(80).optional(), groupName: z.string().min(1).max(80).optional(), color: z.string().regex(/^#[0-9a-f]{6}$/i).optional(), archived: z.boolean().optional() }).superRefine(requireFields), request.body);
      const category = await app.store.editCategory(book.workspaceId, request.params.categoryId, body);
      if (!category) { const error = new Error('Category not found'); error.statusCode = 404; error.code = 'NOT_FOUND'; throw error; }
      await app.store.addAudit({ workspaceId: book.workspaceId, bookId: book.id, actorId: request.actor.id, action: body.archived === true ? 'category.archived' : 'category.updated', entityType: 'category', entityId: category.id, after: body });
      return category;
    });
    api.get('/books/:bookId/categories', async (request) => { const { book } = await access(request); return { items: await app.store.listCategories(book.workspaceId) }; });
    api.post('/books/:bookId/categories', async (request, reply) => { const { book } = await access(request, 'edit'); const body = parse(z.object({ name: z.string().min(1).max(80), groupName: z.string().min(1).max(80), color: z.string().regex(/^#[0-9a-f]{6}$/i) }), request.body); return reply.code(201).send(await app.store.createCategory({ workspaceId: book.workspaceId, ...body })); });
    api.get('/books/:bookId/summary', async (request) => { await access(request); const query=parse(z.object({month:z.string().regex(/^\d{4}-\d{2}$/).optional()}),request.query??{});return app.store.summary(request.params.bookId, query.month); });
    api.get('/books/:bookId/transactions', async (request) => { await access(request); const query = parse(z.object({ state: z.enum(['pending_review', 'confirmed', 'reconciled', 'excluded', 'voided']).optional(), cursor: z.string().optional(), limit: z.coerce.number().int().min(1).max(100).default(50) }), request.query ?? {}); return app.store.listTransactions(request.params.bookId, query); });
    api.post('/books/:bookId/transactions', async (request, reply) => { const { book } = await access(request, 'create'); const body = parse(transactionInput, request.body); const idempotencyKey=requireIdempotencyKey(request);const transaction = await app.store.createTransaction({ ...body, workspaceId: book.workspaceId, bookId: book.id }, request.actor.id, idempotencyKey); const { __idempotentReplay, ...response } = transaction;if(!__idempotentReplay)await app.store.addAudit({ workspaceId: book.workspaceId, bookId: book.id, actorId: request.actor.id, action: 'transaction.created', entityType: 'transaction', entityId: transaction.id, after: { source: 'manual' } }); return reply.code(__idempotentReplay?200:201).send(response); });
    api.patch('/books/:bookId/transactions/:transactionId/category', async (request) => { await access(request, 'reclassify'); const body = parse(z.object({ categoryId: z.string(), applyToFuture: z.boolean().default(false) }), request.body); const transaction = await app.store.updateCategory(request.params.bookId, request.params.transactionId, body.categoryId, request.actor.id, body.applyToFuture); if (!transaction) { const error = new Error('Transaction not found'); error.statusCode = 404; throw error; } return transaction; });
    api.put('/books/:bookId/transactions/:transactionId/splits', async (request) => { await access(request, 'split'); const body = parse(z.object({ splits: z.array(z.object({ categoryId: z.string(), amountMinor: z.string().regex(/^-?\d+$/), note: z.string().max(250).optional() })).min(2).max(20) }), request.body); const transaction = await app.store.splitTransaction(request.params.bookId, request.params.transactionId, body.splits, request.actor.id); if (!transaction) { const error = new Error('Transaction not found'); error.statusCode = 404; throw error; } return transaction; });
    api.post('/books/:bookId/transactions/:transactionId/comments', async (request, reply) => { await access(request, 'comment'); const body = parse(z.object({ body: z.string().trim().min(1).max(2000) }), request.body); const comment = await app.store.addComment(request.params.bookId, request.params.transactionId, body.body, request.actor.id); if (!comment) { const error = new Error('Transaction not found'); error.statusCode = 404; throw error; } return reply.code(201).send(comment); });
    api.patch('/books/:bookId/transactions/:transactionId', async (request) => {
      await access(request, 'edit');
      const body = parse(transactionPatch, request.body);
      const updated = await app.store.updateTransaction(request.params.bookId, request.params.transactionId, body, request.actor.id);
      if (!updated) { const error = new Error('Transaction not found in this book'); error.statusCode = 404; error.code = 'NOT_FOUND'; throw error; }
      return updated;
    });
    api.post('/books/:bookId/ingestion-events', async (request, reply) => { const { book } = await access(request, 'create'); const body = parse(ingestionInput, request.body); const event = await app.store.ingest({ ...body, workspaceId: book.workspaceId, bookId: book.id }, request.actor.id, requireIdempotencyKey(request)); return reply.code(event.duplicate ? 200 : 201).send(event); });
    api.get('/books/:bookId/budget-plan', async (request) => { await access(request); return app.store.getBudgetPlan(request.params.bookId); });
    api.put('/books/:bookId/budget-plan', async (request) => {
      const { book } = await access(request, 'edit');
      const body = parse(budgetPlanInput, request.body);
      return app.store.saveBudgetPlan(book.id, body.allocations, request.actor.id);
    });
    // Superseded by budget-plan above, which budgets a share of income per group.
    // Kept because the endpoints work and the table may hold existing rows.
    api.get('/books/:bookId/budgets', async (request) => { await access(request); return { items: await app.store.listBudgets(request.params.bookId) }; });
    api.put('/books/:bookId/budgets/:categoryId', async (request) => { const { book } = await access(request, 'edit'); const body = parse(z.object({ month: z.string().regex(/^\d{4}-\d{2}-01$/), amountMinor: z.string().regex(/^\d+$/).refine((value) => BigInt(value) > 0n, 'Budget must be greater than zero'), currency: z.string().length(3).default('INR') }), request.body); const budget = await app.store.upsertBudget({ bookId: book.id, categoryId: request.params.categoryId, ...body }); await app.store.addAudit({ workspaceId: book.workspaceId, bookId: book.id, actorId: request.actor.id, action: 'budget.updated', entityType: 'budget', entityId: budget.id, after: { categoryId: request.params.categoryId, month: body.month, amountMinor: body.amountMinor } }); return budget; });
    api.get('/books/:bookId/categorization-rules', async (request) => { await access(request); return { items: await app.store.listRules(request.params.bookId) }; });
    api.post('/books/:bookId/categorization-rules', async (request, reply) => { await access(request, 'edit'); const body = parse(z.object({ categoryId: z.string(), matchType: z.enum(['merchant_exact', 'merchant_contains', 'vpa_exact']), matchValue: z.string().trim().min(2).max(160), priority: z.number().int().min(1).max(1000).default(100) }), request.body); return reply.code(201).send(await app.store.createRule({ ...body, bookId: request.params.bookId, createdById: request.actor.id })); });
    api.patch('/books/:bookId/categorization-rules/:ruleId', async (request) => {
      const { book } = await access(request, 'edit');
      const body = parse(z.object({ categoryId: z.string().optional(), matchType: z.enum(['merchant_exact', 'merchant_contains', 'vpa_exact']).optional(), matchValue: z.string().trim().min(2).max(160).optional(), priority: z.number().int().min(1).max(1000).optional(), enabled: z.boolean().optional() }).superRefine(requireFields), request.body);
      const rule = await app.store.updateRule(book.id, request.params.ruleId, body);
      if (!rule) { const error = new Error('Rule not found'); error.statusCode = 404; error.code = 'NOT_FOUND'; throw error; }
      await app.store.addAudit({ workspaceId: book.workspaceId, bookId: book.id, actorId: request.actor.id, action: 'rule.updated', entityType: 'categorization_rule', entityId: rule.id, after: body });
      return rule;
    });
    api.delete('/books/:bookId/categorization-rules/:ruleId', async (request, reply) => {
      const { book } = await access(request, 'edit');
      const removed = await app.store.deleteRule(book.id, request.params.ruleId);
      if (!removed) { const error = new Error('Rule not found'); error.statusCode = 404; error.code = 'NOT_FOUND'; throw error; }
      await app.store.addAudit({ workspaceId: book.workspaceId, bookId: book.id, actorId: request.actor.id, action: 'rule.deleted', entityType: 'categorization_rule', entityId: request.params.ruleId, before: { matchType: removed.matchType, matchValue: removed.matchValue, categoryId: removed.categoryId } });
      return reply.code(204).send();
    });
    api.patch('/books/:bookId/recurring-plans/:planId', async (request) => {
      const { book } = await access(request, 'edit');
      const body = parse(recurringPatch, request.body);
      const plan = await app.store.updateRecurring(book.id, request.params.planId, body);
      if (!plan) { const error = new Error('Recurring plan not found'); error.statusCode = 404; error.code = 'NOT_FOUND'; throw error; }
      await app.store.addAudit({ workspaceId: book.workspaceId, bookId: book.id, actorId: request.actor.id, action: body.active === false ? 'recurring.stopped' : 'recurring.updated', entityType: 'recurring_plan', entityId: plan.id, after: body });
      return plan;
    });
    api.get('/books/:bookId/recurring-plans', async (request) => { await access(request); return { items: await app.store.listRecurring(request.params.bookId) }; });
    api.post('/books/:bookId/recurring-plans', async (request, reply) => { await access(request, 'edit'); const body = parse(recurringInput, request.body); return reply.code(201).send(await app.store.createRecurring({ ...body, bookId: request.params.bookId })); });
    api.get('/books/:bookId/imports', async (request) => { await access(request); return { items: await app.store.listImports(request.params.bookId) }; });
    api.post('/books/:bookId/imports', async (request, reply) => {
      const { book } = await access(request, 'edit');
      const { content, accountId, ...meta } = parse(importInput, request.body);
      const record = await app.store.createImport({ ...meta, workspaceId: book.workspaceId, bookId: book.id });
      // Parse even a file we have seen before. Each row carries its own hash, so
      // re-uploading is already safe, and a file recorded by an older build that
      // never parsed anything would otherwise be impossible to import.
      if (!content) return reply.code(record.duplicate ? 200 : 201).send(record);
      let parsed;
      try { parsed = meta.contentType === XLSX_MIME ? parseStatementXlsx(Buffer.from(content, 'base64')) : parseStatementCsv(content); }
      catch (error) { const failure = new Error(error.message); failure.statusCode = 422; failure.code = 'STATEMENT_UNPARSEABLE'; throw failure; }
      // Each row is its own database transaction, so an unbounded file would tie
      // up a connection for as long as it takes to write every one of them.
      if (parsed.rows.length > MAX_STATEMENT_ROWS) {
        const error = new Error(`This statement has ${parsed.rows.length} rows; ${MAX_STATEMENT_ROWS} is the most that can be imported at once. Split it by month and import each part.`);
        error.statusCode = 413; error.code = 'STATEMENT_TOO_LARGE'; throw error;
      }
      let imported = 0; let duplicates = 0;
      for (const [index, row] of parsed.rows.entries()) {
        const event = await app.store.ingest({ ...row, accountId: accountId ?? null, workspaceId: book.workspaceId, bookId: book.id }, request.actor.id, `statement:${meta.sha256}:${index}`);
        if (event.duplicate) duplicates += 1; else imported += 1;
      }
      return reply.code(record.duplicate ? 200 : 201).send({ ...record, status: 'parsed', account: parsed.account, imported, duplicates, warnings: parsed.warnings });
    });
    api.get('/books/:bookId/audit-events', async (request) => { await access(request); return { items: await app.store.listAudit(request.params.bookId, 50) }; });
    api.post('/books/:bookId/period-reviews', async (request, reply) => { const { book } = await access(request, 'verify'); const body = parse(z.object({ month: z.string().regex(/^\d{4}-\d{2}$/), status: z.enum(['in_review', 'verified']), note: z.string().max(2000).optional() }), request.body); return reply.code(201).send(await app.store.reviewPeriod(book, body, request.actor.id)); });
  }, { prefix: '/v1' });

  // ---- master admin ------------------------------------------------
  // Membership of PLATFORM_ADMINS is the only way in, and these routes 404
  // rather than 403 for everyone else — the same convention the book routes
  // use, so their existence is not something you can probe for.
  app.register(async function admin(api) {
    api.addHook('preHandler', app.authenticate);
    api.addHook('preHandler', async (request) => {
      if (request.isPlatformAdmin) return;
      request.log.warn({ identity: request.identityEmail, profile: request.actor?.email }, 'Rejected a request to the master admin API');
      const error = new Error('Not found'); error.statusCode = 404; error.code = 'NOT_FOUND'; throw error;
    });

    // Firebase is the directory; the ledger is what we did with it. The page
    // needs both, and needs to say which of the two is missing.
    async function directory() {
      const profiles = await app.store.listPlatformUsers();
      if (!firebaseAdminConfigured()) return { firebase: false, users: mergeDirectory(profiles, []), reason: 'No Firebase service account is configured, so this lists only accounts that have signed in at least once.' };
      try {
        return { firebase: true, users: mergeDirectory(profiles, await listFirebaseUsers()) };
      } catch (error) {
        // A key that has expired or lost its role must not blank the page —
        // the ledger half is still true and still useful.
        api.log?.error({ reason: error?.message }, 'Firebase admin call failed');
        return { firebase: false, users: mergeDirectory(profiles, []), reason: `Firebase could not be reached: ${error.message}` };
      }
    }

    // An id may be a ledger profile id or, for an account that has never signed
    // in, a Firebase uid. Resolve both so the page can pass through whatever it
    // was given.
    async function target(id) {
      const profile = await app.store.getUserById(id) ?? await app.store.getUserByFirebaseUid(id);
      const firebaseUid = profile?.firebaseUid ?? id;
      if (!profile && !firebaseAdminConfigured()) { const error = new Error('No such user'); error.statusCode = 404; error.code = 'NOT_FOUND'; throw error; }
      return { profile, firebaseUid };
    }
    function requireFirebase() {
      if (firebaseAdminConfigured()) return;
      const error = new Error('This needs a Firebase service account on the server. Set FIREBASE_SERVICE_ACCOUNT_FILE and restart the API.');
      error.statusCode = 501; error.code = 'FIREBASE_ADMIN_UNCONFIGURED'; throw error;
    }
    // Destructive calls repeat the email back. A wrong id in a script is the
    // likeliest way to wipe the wrong household, and an id is unmemorable.
    function confirmEmail(body, profile) {
      const given = parse(z.object({ confirmEmail: z.string().min(3).max(320) }), body).confirmEmail.trim().toLowerCase();
      if (given !== String(profile.email).trim().toLowerCase()) {
        const error = new Error('confirmEmail does not match that account'); error.statusCode = 400; error.code = 'CONFIRMATION_MISMATCH'; throw error;
      }
    }
    // Admin actions are not workspace-scoped, and the workspace an audit row
    // would live in is sometimes the thing being deleted. The journal is the
    // record that survives.
    function record(request, action, detail) {
      request.log.warn({ action, actor: request.actor?.email, ...detail }, 'Master admin action');
    }

    api.get('/users', async () => {
      const { firebase, users, reason } = await directory();
      return { items: users, firebaseConfigured: firebaseAdminConfigured(), firebaseReachable: firebase, reason: reason ?? null, admins: platformAdmins() };
    });

    api.post('/users', async (request, reply) => {
      requireFirebase();
      const body = parse(z.object({
        email: z.string().email().max(320).transform((value) => value.trim().toLowerCase()),
        displayName: z.string().trim().min(1).max(120).optional(),
        provision: z.boolean().default(true),
      }), request.body);
      if (await app.store.getUserByEmail(body.email)) { const error = new Error('That email already has a ledger profile'); error.statusCode = 409; error.code = 'EMAIL_IN_USE'; throw error; }
      const account = await createFirebaseUser(body);
      // No password is set anywhere. The new user follows the reset link and
      // chooses their own, so nobody here ever handles it.
      await sendFirebasePasswordReset(body.email);
      let provisioned = null;
      if (body.provision) {
        provisioned = await app.store.provisionTenant({ firebaseUid: account.uid, email: body.email, displayName: body.displayName ?? null });
      }
      record(request, 'admin.user_created', { email: body.email, provisioned: Boolean(provisioned) });
      return reply.code(201).send({ firebase: account, profile: provisioned, passwordEmailSent: true });
    });

    api.patch('/users/:id', async (request) => {
      const { profile, firebaseUid } = await target(request.params.id);
      const body = parse(z.object({
        email: z.string().email().max(320).transform((value) => value.trim().toLowerCase()).optional(),
        displayName: z.string().trim().min(1).max(120).optional(),
        disabled: z.boolean().optional(),
      }).superRefine(requireFields), request.body);
      // Changing the email in only one of the two places leaves an account that
      // can sign in but resolves to nobody, or an invitation that never matches.
      if (body.email !== undefined || body.disabled !== undefined) requireFirebase();
      const clash = body.email ? await app.store.getUserByEmail(body.email) : null;
      if (clash && clash.id !== profile?.id) { const error = new Error('Another account already uses that email address'); error.statusCode = 409; error.code = 'EMAIL_IN_USE'; throw error; }
      // A profile outlives its Firebase account if somebody deletes the account
      // in the console. The name is still ours to change; the email and the
      // disabled flag are not, and pretending otherwise would report success.
      const exists = firebaseAdminConfigured() ? await lookupFirebaseUser(firebaseUid) : null;
      if (!exists && (body.email !== undefined || body.disabled !== undefined)) {
        const error = new Error('Firebase has no account for this user any more, so only the name can be changed here');
        error.statusCode = 409; error.code = 'FIREBASE_ACCOUNT_MISSING'; throw error;
      }
      const firebase = exists ? await updateFirebaseUser(firebaseUid, body) : null;
      const updated = profile ? await app.store.setUserIdentity(profile.id, body) : null;
      record(request, 'admin.user_updated', { target: profile?.email ?? firebaseUid, changed: Object.keys(body) });
      return { firebase, profile: updated };
    });

    api.post('/users/:id/password-reset', async (request) => {
      requireFirebase();
      const { profile, firebaseUid } = await target(request.params.id);
      const email = profile?.email ?? (await lookupFirebaseUser(firebaseUid))?.email;
      if (!email) { const error = new Error('That account has no email address to send a reset to'); error.statusCode = 409; error.code = 'NO_EMAIL'; throw error; }
      // Firebase sends it. Returning the link instead would hand whoever is on
      // this page a one-click takeover of somebody else's account.
      await sendFirebasePasswordReset(email);
      record(request, 'admin.password_reset_sent', { target: email });
      return { sent: true, email };
    });

    api.get('/users/:id/export', async (request) => {
      const { profile } = await target(request.params.id);
      if (!profile) { const error = new Error('That account has never signed in, so there is nothing in the ledger to export'); error.statusCode = 404; error.code = 'NOT_FOUND'; throw error; }
      const data = await app.store.exportUserData(profile.id);
      record(request, 'admin.user_exported', { target: profile.email });
      return data;
    });

    api.post('/users/:id/ledger-reset', async (request) => {
      const { profile } = await target(request.params.id);
      if (!profile) { const error = new Error('That account has no ledger to reset'); error.statusCode = 404; error.code = 'NOT_FOUND'; throw error; }
      confirmEmail(request.body, profile);
      const result = await app.store.wipeUserLedger(profile.id);
      // Rules and budgets survive on purpose, exactly as reset-ledger.sh leaves
      // them: they are learned configuration, not data.
      for (const book of result.books) {
        await app.store.addAudit({ workspaceId: (await app.store.getBook(book.id))?.workspaceId, bookId: book.id, actorId: request.actor.id, action: 'admin.ledger_reset', entityType: 'book', entityId: book.id, before: { transactions: result.transactionsRemoved } });
      }
      record(request, 'admin.ledger_reset', { target: profile.email, books: result.books.length, transactions: result.transactionsRemoved });
      return result;
    });

    api.post('/users/:id/factory-reset', async (request) => {
      const { profile } = await target(request.params.id);
      if (!profile) { const error = new Error('That account has no household to reset'); error.statusCode = 404; error.code = 'NOT_FOUND'; throw error; }
      confirmEmail(request.body, profile);
      const result = await app.store.factoryResetUser(profile.id);
      // The audit trail for these books was part of what was cleared, so this
      // row is the first entry in the new one.
      for (const book of result.books) {
        await app.store.addAudit({ workspaceId: (await app.store.getBook(book.id))?.workspaceId, bookId: book.id, actorId: request.actor.id, action: 'admin.factory_reset', entityType: 'book', entityId: book.id, before: { transactions: result.transactionsRemoved, categoriesRemoved: result.categoriesRemoved } });
      }
      record(request, 'admin.factory_reset', { target: profile.email, books: result.books.length, transactions: result.transactionsRemoved, categoriesRestored: result.categoriesRestored });
      return result;
    });

    api.post('/users/:id/delete', async (request) => {
      const { profile, firebaseUid } = await target(request.params.id);
      const body = parse(z.object({ confirmEmail: z.string().min(3).max(320), deleteFirebaseAccount: z.boolean().default(false) }), request.body);
      if (profile) confirmEmail({ confirmEmail: body.confirmEmail }, profile);
      if (profile && profile.email === request.actor.email) { const error = new Error('You cannot delete your own account from here'); error.statusCode = 409; error.code = 'SELF_DELETE'; throw error; }
      const removed = profile ? await app.store.deletePlatformUser(profile.id) : { userId: null, email: body.confirmEmail, booksDeleted: [], workspacesDeleted: [] };
      if (body.deleteFirebaseAccount) { requireFirebase(); await deleteFirebaseUser(firebaseUid); }
      record(request, 'admin.user_deleted', { target: removed.email, books: removed.booksDeleted.length, workspaces: removed.workspacesDeleted.length, firebase: body.deleteFirebaseAccount });
      return { ...removed, firebaseAccountDeleted: body.deleteFirebaseAccount };
    });
  }, { prefix: '/v1/admin' });

  await app.ready();
  return app;
}
