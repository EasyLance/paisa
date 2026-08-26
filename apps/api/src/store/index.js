import { MemoryStore } from './memory-store.js';

export async function createStore(options = {}) {
  const useMemory = options.memory ?? (process.env.USE_MEMORY_STORE ? process.env.USE_MEMORY_STORE === 'true' : !process.env.DATABASE_URL);
  if (useMemory) return new MemoryStore();
  const { PrismaStore } = await import('./prisma-store.js');
  return new PrismaStore();
}
