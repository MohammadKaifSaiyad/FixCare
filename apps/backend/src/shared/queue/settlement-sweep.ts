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
  // Plain options (not a pre-built ioredis instance): BullMQ builds its own connection, forcing
  // maxRetriesPerRequest: null itself (blocking worker). Because the connection is BullMQ-owned
  // (shared=false), worker.close() + queue.close() each quit their own client — no leak, so the
  // stop function needs no explicit disconnect.
  const connection = { url: config.REDIS_URL };
  const queue = new Queue(QUEUE, { connection });
  queue.on('error', (err) => console.error('settlement sweep queue error:', err.message)); // narrow (boot-time) but same crash rule as the worker
  await queue.upsertJobScheduler(QUEUE, { every: config.SETTLEMENT_SWEEP_INTERVAL_MINUTES * 60_000 });
  const worker = new Worker(QUEUE, async () => { await settleClosableBookings(); }, { connection });
  worker.on('failed', (_job, err) => console.error('settlement sweep failed:', err.message));
  // A Worker emits 'error' on connection drops/internal faults; an EventEmitter 'error' with NO
  // listener THROWS and crashes the process — for unattended background work that must never
  // happen. Log and let BullMQ's retryStrategy reconnect.
  worker.on('error', (err) => console.error('settlement sweep worker error:', err.message));
  return async () => {
    await worker.close();
    await queue.close();
  };
}
