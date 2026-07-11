import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { mintOtp, verifyOtp } from '../../src/shared/auth/otp-store.js';
import { redis } from '../../src/shared/redis/client.js';
import { flushTestRedis } from '../helpers/redis.js';

afterAll(() => redis.quit());
beforeEach(flushTestRedis);

// Test keys live under the `otp:` prefix so flushTestRedis isolates them — the derived
// throttle counter (`<key>:rl`, 900s TTL) would otherwise leak across runs and trip
// the send-throttle test on any re-run inside the window.
const cfg = { ttlSeconds: 300, maxAttempts: 5 };

describe('otp-store', () => {
  it('mints a 6-digit code', async () => {
    const r = await mintOtp('otp:test:1', cfg);
    expect(r.status).toBe('ok');
    if (r.status === 'ok') expect(r.code).toMatch(/^\d{6}$/);
  });

  it('verify ok consumes the code (single-use → no-code on second verify)', async () => {
    const r = await mintOtp('otp:test:2', cfg);
    const code = r.status === 'ok' ? r.code : '';
    expect((await verifyOtp('otp:test:2', code, cfg)).status).toBe('ok');
    expect((await verifyOtp('otp:test:2', code, cfg)).status).toBe('no-code');
  });

  it('wrong code → invalid and key stays alive (TTL preserved)', async () => {
    await mintOtp('otp:test:3', cfg);
    expect((await verifyOtp('otp:test:3', '000000', cfg)).status).toBe('invalid');
    const ttl = await redis.ttl('otp:test:3');
    expect(ttl).toBeGreaterThan(0);
    expect(ttl).toBeLessThanOrEqual(300);
  });

  it('after maxAttempts wrong tries → exhausted and the key is deleted', async () => {
    await mintOtp('otp:test:4', cfg);
    for (let i = 0; i < 5; i++) expect((await verifyOtp('otp:test:4', '000000', cfg)).status).toBe('invalid');
    expect((await verifyOtp('otp:test:4', '000000', cfg)).status).toBe('exhausted');
    expect(await redis.get('otp:test:4')).toBeNull();
  });

  it('a correct code on the LAST allowed attempt still succeeds (boundary: maxAttempts-1 wrong tries)', async () => {
    const m = await mintOtp('otp:test:11', cfg);
    const code = m.status === 'ok' ? m.code : '';
    for (let i = 0; i < 4; i++) expect((await verifyOtp('otp:test:11', '000000', cfg)).status).toBe('invalid');
    expect((await verifyOtp('otp:test:11', code, cfg)).status).toBe('ok');
  });

  it('verify before any mint → no-code', async () => {
    expect((await verifyOtp('otp:test:5', '123456', cfg)).status).toBe('no-code');
  });

  it('returns a typed payload on success', async () => {
    await mintOtp<{ role: string }>('otp:test:6', cfg, { role: 'CUSTOMER' });
    const code = await redis.get('otp:test:6');
    const hash = JSON.parse(code!).hash as string;
    // verify with the real code path: re-mint deterministically is hard, so assert via a known code:
    // mint again with a payload and read it back through a correct verify.
    const m = await mintOtp<{ role: string }>('otp:test:7', cfg, { role: 'TECHNICIAN' });
    const c = m.status === 'ok' ? m.code : '';
    const v = await verifyOtp<{ role: string }>('otp:test:7', c, cfg);
    expect(v.status).toBe('ok');
    if (v.status === 'ok') expect(v.payload).toEqual({ role: 'TECHNICIAN' });
    expect(hash).toMatch(/^[a-f0-9]{64}$/);
  });

  it('send throttle: returns throttled after `max` mints in the window', async () => {
    const tcfg = { ttlSeconds: 300, maxAttempts: 5, sendLimit: { max: 3, windowSeconds: 900 } };
    expect((await mintOtp('otp:test:8', tcfg)).status).toBe('ok');
    expect((await mintOtp('otp:test:8', tcfg)).status).toBe('ok');
    expect((await mintOtp('otp:test:8', tcfg)).status).toBe('ok');
    expect((await mintOtp('otp:test:8', tcfg)).status).toBe('throttled');
  });

  it('no send throttle by default: many mints all succeed', async () => {
    for (let i = 0; i < 6; i++) expect((await mintOtp('otp:test:9', cfg)).status).toBe('ok');
  });

  it('corrupt stored value → no-code and the key is deleted (fail safe, fail closed)', async () => {
    await redis.set('otp:test:10', 'not-json', 'EX', 60);
    expect((await verifyOtp('otp:test:10', '123456', cfg)).status).toBe('no-code');
    expect(await redis.get('otp:test:10')).toBeNull();
  });
});
