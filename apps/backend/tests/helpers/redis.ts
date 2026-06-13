import { redis } from '../../src/shared/redis/client.js';

/** Remove OTP + rate-limit + arrival-code keys between tests so each test is isolated. */
export async function flushTestRedis() {
  const keys = await redis.keys('otp:*');
  const rl = await redis.keys('otp-rl:*');
  const arrival = await redis.keys('arrival:*');
  const all = [...keys, ...rl, ...arrival];
  if (all.length) await redis.del(...all);
}
