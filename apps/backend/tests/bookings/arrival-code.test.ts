import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { mintArrivalCode, verifyArrivalCode } from '../../src/modules/bookings/arrival-code.js';
import { redis } from '../../src/shared/redis/client.js';
import { flushTestRedis } from '../helpers/redis.js';

afterAll(() => redis.quit());
beforeEach(flushTestRedis);

describe('arrival code', () => {
  it('mints a 6-digit code; verify succeeds once then the code is consumed', async () => {
    const code = await mintArrivalCode('booking-1');
    expect(code).toMatch(/^\d{6}$/);
    expect(await verifyArrivalCode('booking-1', code)).toBe('ok');
    expect(await verifyArrivalCode('booking-1', code)).toBe('no-code'); // single-use
  });

  it('wrong code → invalid; after 5 wrong attempts the code is invalidated', async () => {
    const code = await mintArrivalCode('booking-2');
    for (let i = 0; i < 5; i++) expect(await verifyArrivalCode('booking-2', '000000')).toBe('invalid');
    expect(await verifyArrivalCode('booking-2', code)).toBe('no-code'); // attempts exhausted → key deleted
  });

  it('verify before any mint → no-code', async () => {
    expect(await verifyArrivalCode('booking-3', '123456')).toBe('no-code');
  });
});
