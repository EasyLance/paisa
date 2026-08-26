import { buildApp } from './app.js';

const app = await buildApp({ logger: { level: process.env.LOG_LEVEL ?? 'info', redact: ['req.headers.authorization', 'req.headers.x-app-check', 'body.metadata', 'body.note'] } });
await app.listen({ port: Number(process.env.PORT ?? 4000), host: process.env.HOST ?? '0.0.0.0' });
