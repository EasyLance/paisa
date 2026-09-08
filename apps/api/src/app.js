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
import { createStore } from './store/index.js';

const transactionFields = z.object({
  accountId: z.string().nullable().optional(), categoryId: z.string().nullable().optional(), kind: z.enum(['expense', 'income', 'transfer', 'refund']),
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
    api.patch('/books/:bookId/transactions/:transactionId', async (request) => { await access(request, 'edit'); const error = new Error('Imported amount and source fields are immutable; use a categorization or note endpoint'); error.statusCode = 409; error.code = 'IMMUTABLE_SOURCE'; throw error; });
    api.post('/books/:bookId/ingestion-events', async (request, reply) => { const { book } = await access(request, 'create'); const body = parse(ingestionInput, request.body); const event = await app.store.ingest({ ...body, workspaceId: book.workspaceId, bookId: book.id }, request.actor.id, requireIdempotencyKey(request)); return reply.code(event.duplicate ? 200 : 201).send(event); });
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
    api.post('/books/:bookId/imports', async (request, reply) => { const { book } = await access(request, 'edit'); const body = parse(z.object({ fileName: z.string().trim().min(1).max(180), contentType: z.enum(['text/csv', 'application/pdf']), sizeBytes: z.number().int().positive().max(10 * 1024 * 1024), sha256: z.string().regex(/^[a-f0-9]{64}$/i) }), request.body); const record = await app.store.createImport({ ...body, workspaceId: book.workspaceId, bookId: book.id }); return reply.code(record.duplicate ? 200 : 201).send(record); });
    api.get('/books/:bookId/audit-events', async (request) => { await access(request); return { items: await app.store.listAudit(request.params.bookId, 50) }; });
    api.post('/books/:bookId/period-reviews', async (request, reply) => { const { book } = await access(request, 'verify'); const body = parse(z.object({ month: z.string().regex(/^\d{4}-\d{2}$/), status: z.enum(['in_review', 'verified']), note: z.string().max(2000).optional() }), request.body); return reply.code(201).send(await app.store.reviewPeriod(book, body, request.actor.id)); });
  }, { prefix: '/v1' });

  await app.ready();
  return app;
}
