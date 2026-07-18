import { redis } from '../../src/shared/redis/client.js';

/** Remove OTP + arrival + completion keys between tests so each test is isolated.
 *  The `otp:*` scan also covers the store-derived throttle counters (`otp:<phone>:rl`);
 *  `completion:*` covers the completion codes AND their `:rl` throttle counters. */
export async function flushTestRedis() {
  const keys = await redis.keys('otp:*');
  const arrival = await redis.keys('arrival:*');
  const completion = await redis.keys('completion:*');
  const all = [...keys, ...arrival, ...completion];
  if (all.length) await redis.del(...all);
}
