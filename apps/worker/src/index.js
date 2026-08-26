import { Queue, Worker } from 'bullmq';
import IORedis from 'ioredis';

const connection = new IORedis(process.env.REDIS_URL ?? 'redis://localhost:6379', {
  maxRetriesPerRequest: null,
  lazyConnect: true,
});

export const queues = {
  imports: new Queue('statement-imports', { connection }),
  reconciliation: new Queue('reconciliation', { connection }),
  notifications: new Queue('notifications', { connection }),
  exports: new Queue('report-exports', { connection }),
};

const handlers = {
  'statement-imports': async (job) => ({ importId: job.data.importId, status: 'parsed' }),
  reconciliation: async (job) => ({ bookId: job.data.bookId, status: 'reconciled' }),
  notifications: async (job) => ({ userId: job.data.userId, status: 'queued-for-fcm' }),
  'report-exports': async (job) => ({ reportId: job.data.reportId, status: 'generated' }),
};

export async function startWorkers() {
  await connection.connect();
  return Object.entries(handlers).map(([name, processor]) => new Worker(name, processor, {
    connection,
    concurrency: name === 'statement-imports' ? 2 : 5,
  }));
}

if (process.env.NODE_ENV !== 'test') {
  startWorkers()
    .then(() => console.log('Paisa workers ready'))
    .catch((error) => {
      console.error('Unable to start workers', error.message);
      process.exitCode = 1;
    });
}
