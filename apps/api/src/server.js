import { setInterval } from 'node:timers';
import { buildApp } from './app.js';

const app = await buildApp({ logger: { level: process.env.LOG_LEVEL ?? 'info', redact: ['req.headers.authorization', 'req.headers.x-firebase-appcheck', 'body.metadata', 'body.note'] } });
await app.listen({ port: Number(process.env.PORT ?? 4000), host: process.env.HOST ?? '0.0.0.0' });

// One API process under systemd, so a plain interval is all the scheduling this
// needs - no cron, no queue, no Redis. Postings are keyed by plan and due date,
// so an overlapping tick or a restart mid-run cannot post the same month twice.
const recurringIntervalMs = Number(process.env.RECURRING_POLL_MS ?? 15 * 60 * 1000);
async function postDueRecurring() {
  try {
    const posted = await app.store.postDueRecurring();
    if (posted.length) app.log.info({ posted }, 'Posted due recurring plans');
  } catch (error) {
    app.log.error({ err: error }, 'Could not post due recurring plans');
  }
}
if (recurringIntervalMs > 0) {
  // Run once at boot so a plan that came due while the API was down is caught up.
  void postDueRecurring();
  setInterval(postDueRecurring, recurringIntervalMs).unref();
}

async function shutdown(signal) {
  app.log.info({ signal }, 'Shutting down Paisa API');
  await app.close();
  process.exit(0);
}

process.once('SIGTERM', () => void shutdown('SIGTERM'));
process.once('SIGINT', () => void shutdown('SIGINT'));
