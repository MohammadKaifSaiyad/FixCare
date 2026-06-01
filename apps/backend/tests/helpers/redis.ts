import { redis } from '../../src/shared/redis/client.js';

/** Remove OTP + rate-limit keys between tests so each test is isolated. */
export async function flushTestRedis() {
  const keys = await redis.keys('otp:*');
  const rl = await redis.keys('otp-rl:*');
  const all = [...keys, ...rl];
  if (all.length) await redis.del(...all);
}
