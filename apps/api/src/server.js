import { buildApp } from './app.js';

const app = await buildApp({ logger: { level: process.env.LOG_LEVEL ?? 'info', redact: ['req.headers.authorization', 'req.headers.x-firebase-appcheck', 'body.metadata', 'body.note'] } });
await app.listen({ port: Number(process.env.PORT ?? 4000), host: process.env.HOST ?? '0.0.0.0' });

async function shutdown(signal) {
  app.log.info({ signal }, 'Shutting down Paisa API');
  await app.close();
  process.exit(0);
}

process.once('SIGTERM', () => void shutdown('SIGTERM'));
process.once('SIGINT', () => void shutdown('SIGINT'));
