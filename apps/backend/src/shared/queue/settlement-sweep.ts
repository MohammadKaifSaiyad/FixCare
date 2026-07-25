import { Queue, Worker } from 'bullmq';
import { config } from '../config.js';
import { settleClosableBookings } from '../../modules/settlements/settlements.service.js';

const QUEUE = 'settlement-sweep';

/** First background work (B6c). BullMQ needs its OWN connection with maxRetriesPerRequest: null
 *  (the shared client uses 3 — BullMQ rejects that). Passing url+opts lets BullMQ create the
 *  connection via its own bundled ioredis, sidestepping the peer-version type mismatch.
 *  Single in-process worker is fine for V1's one API instance; B2b's accept-timer reuses this
 *  scaffolding. The sweep itself is idempotent (optimistic lock), so overlapping/repeated fires
 *  are harmless. */
export async function startSettlementSweep(): Promise<() => Promise<void>> {
  const connection = { url: config.REDIS_URL, maxRetriesPerRequest: null as null };
  const queue = new Queue(QUEUE, { connection });
  await queue.upsertJobScheduler(QUEUE, { every: config.SETTLEMENT_SWEEP_INTERVAL_MINUTES * 60_000 });
  const worker = new Worker(QUEUE, async () => { await settleClosableBookings(); }, { connection });
  worker.on('failed', (_job, err) => console.error('settlement sweep failed:', err.message));
  return async () => {
    await worker.close();
    await queue.close();
  };
}
