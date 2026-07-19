import { redis } from '../../src/shared/redis/client.js';

/** Remove OTP + arrival + completion + cash-receipt keys between tests so each test is isolated.
 *  The `otp:*` scan also covers the store-derived throttle counters (`otp:<phone>:rl`);
 *  `completion:*` covers the completion codes AND their `:rl` throttle counters;
 *  `cash-receipt:*` covers the cash receipt codes AND their `:rl` throttle counters. */
export async function flushTestRedis() {
  const keys = await redis.keys('otp:*');
  const arrival = await redis.keys('arrival:*');
  const completion = await redis.keys('completion:*');
  const cashReceipt = await redis.keys('cash-receipt:*');
  const all = [...keys, ...arrival, ...completion, ...cashReceipt];
  if (all.length) await redis.del(...all);
}
