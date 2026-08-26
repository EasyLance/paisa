import Fastify from 'fastify';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import swagger from '@fastify/swagger';
import swaggerUi from '@fastify/swagger-ui';
import { z } from 'zod';
import authPlugin from './plugins/auth.js';
import { assertCapability } from './domain/permissions.js';
import { jsonSafe } from './domain/money.js';
import { createStore } from './store/index.js';

const transactionInput = z.object({
  accountId: z.string().nullable().optional(), categoryId: z.string().nullable().optional(), kind: z.enum(['expense', 'income', 'transfer', 'refund']),
  amountMinor: z.string().regex(/^-?\d+$/), currency: z.string().length(3).default('INR'), merchant: z.string().max(160).nullable().optional(),
  note: z.string().max(2000).nullable().optional(), occurredAt: z.string().datetime(), state: z.enum(['pending_review', 'confirmed']).optional(),
});

const ingestionInput = transactionInput.extend({ sourceType: z.enum(['sms', 'statement']), sourceHash: z.string().min(16).max(128), externalRef: z.string().max(120).optional(), metadata: z.record(z.string(), z.unknown()).optional() });

function parse(schema, input) {
  const result = schema.safeParse(input);
  if (!result.success) { const error = new Error('Request validation failed'); error.statusCode = 400; error.code = 'VALIDATION_ERROR'; error.details = result.error.flatten(); throw error; }
  return result.data;
}

export async function buildApp(options = {}) {
  const app = Fastify({ logger: options.logger ?? false, trustProxy: true, bodyLimit: 5 * 1024 * 1024 });
  app.decorate('store', options.store ?? await createStore({ memory: options.memory }));
  await app.register(cors, { origin: (process.env.CORS_ORIGINS ?? 'http://localhost:3000').split(','), credentials: true });
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

  app.get('/health', async () => ({ status: 'ok', service: 'paisa-api' }));

  async function access(request, capability = 'read') {
    const book = await app.store.getBook(request.params.bookId); if (!book) { const error = new Error('Book not found'); error.statusCode = 404; error.code = 'NOT_FOUND'; throw error; }
    const membership = await app.store.getMembership(book.id, request.actor.id); if (!membership) { const error = new Error('Book not found'); error.statusCode = 404; error.code = 'NOT_FOUND'; throw error; }
    assertCapability(membership.role, capability); return { book, membership };
  }

  app.register(async function v1(api) {
    api.addHook('preHandler', app.authenticate);
    api.get('/workspaces', async (request) => ({ items: await app.store.listWorkspaces(request.actor.id) }));
    api.get('/books', async (request) => ({ items: await app.store.listBooks(request.actor.id) }));
    api.get('/books/:bookId/memberships', async (request) => { await access(request, 'manage_book'); return { items: await app.store.listMemberships(request.params.bookId) }; });
    api.get('/books/:bookId/categories', async (request) => { const { book } = await access(request); return { items: await app.store.listCategories(book.workspaceId) }; });
    api.post('/books/:bookId/categories', async (request, reply) => { const { book } = await access(request, 'edit'); const body = parse(z.object({ name: z.string().min(1).max(80), groupName: z.string().min(1).max(80), color: z.string().regex(/^#[0-9a-f]{6}$/i) }), request.body); return reply.code(201).send(await app.store.createCategory({ workspaceId: book.workspaceId, ...body })); });
    api.get('/books/:bookId/summary', async (request) => { await access(request); return app.store.summary(request.params.bookId, request.query?.month); });
    api.get('/books/:bookId/transactions', async (request) => { await access(request); const query = parse(z.object({ state: z.enum(['pending_review', 'confirmed', 'reconciled', 'excluded', 'voided']).optional(), cursor: z.string().optional(), limit: z.coerce.number().int().min(1).max(100).default(50) }), request.query ?? {}); return app.store.listTransactions(request.params.bookId, query); });
    api.post('/books/:bookId/transactions', async (request, reply) => { const { book } = await access(request, 'create'); const body = parse(transactionInput, request.body); const transaction = await app.store.createTransaction({ ...body, workspaceId: book.workspaceId, bookId: book.id }, request.actor.id, request.headers['idempotency-key']); await app.store.addAudit({ workspaceId: book.workspaceId, bookId: book.id, actorId: request.actor.id, action: 'transaction.created', entityType: 'transaction', entityId: transaction.id, after: { source: 'manual' } }); return reply.code(201).send(transaction); });
    api.patch('/books/:bookId/transactions/:transactionId/category', async (request) => { await access(request, 'reclassify'); const body = parse(z.object({ categoryId: z.string(), applyToFuture: z.boolean().default(false) }), request.body); const transaction = await app.store.updateCategory(request.params.bookId, request.params.transactionId, body.categoryId, request.actor.id, body.applyToFuture); if (!transaction) { const error = new Error('Transaction not found'); error.statusCode = 404; throw error; } return transaction; });
    api.patch('/books/:bookId/transactions/:transactionId', async (request) => { await access(request, 'edit'); const error = new Error('Imported amount and source fields are immutable; use a categorization or note endpoint'); error.statusCode = 409; error.code = 'IMMUTABLE_SOURCE'; throw error; });
    api.post('/books/:bookId/ingestion-events', async (request, reply) => { const { book } = await access(request, 'create'); const body = parse(ingestionInput, request.body); const event = await app.store.ingest({ ...body, workspaceId: book.workspaceId, bookId: book.id }, request.actor.id, request.headers['idempotency-key']); return reply.code(event.duplicate ? 200 : 201).send(event); });
    api.get('/books/:bookId/budgets', async (request) => { await access(request); return { items: await app.store.listBudgets(request.params.bookId) }; });
    api.get('/books/:bookId/audit-events', async (request) => { await access(request); return { items: await app.store.listAudit(request.params.bookId, 50) }; });
    api.post('/books/:bookId/period-reviews', async (request, reply) => { const { book } = await access(request, 'verify'); const body = parse(z.object({ month: z.string().regex(/^\d{4}-\d{2}$/), status: z.enum(['in_review', 'verified']), note: z.string().max(2000).optional() }), request.body); const audit = await app.store.addAudit({ workspaceId: book.workspaceId, bookId: book.id, actorId: request.actor.id, action: `period.${body.status}`, entityType: 'period_review', entityId: `${book.id}:${body.month}`, after: body }); return reply.code(201).send(audit); });
  }, { prefix: '/v1' });

  await app.ready();
  return app;
}
