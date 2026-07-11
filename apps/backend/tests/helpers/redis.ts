import { redis } from '../../src/shared/redis/client.js';

/** Remove OTP + arrival-code keys between tests so each test is isolated.
 *  The `otp:*` scan also covers the store-derived throttle counters (`otp:<phone>:rl`). */
export async function flushTestRedis() {
  const keys = await redis.keys('otp:*');
  const arrival = await redis.keys('arrival:*');
  const all = [...keys, ...arrival];
  if (all.length) await redis.del(...all);
}
