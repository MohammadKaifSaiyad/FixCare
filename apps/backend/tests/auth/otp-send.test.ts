import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });

describe('POST /auth/otp/send', () => {
  it('sends an OTP and returns devOtp in non-prod', async () => {
    const res = await app.inject({
      method: 'POST', url: '/auth/otp/send',
      payload: { phone: '9800000001', role: 'CUSTOMER' },
    });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.ok).toBe(true);
    expect(body.devOtp).toMatch(/^\d{6}$/);
  });

  it('rejects an invalid phone with 400', async () => {
    const res = await app.inject({
      method: 'POST', url: '/auth/otp/send',
      payload: { phone: '12345', role: 'CUSTOMER' },
    });
    expect(res.statusCode).toBe(400);
  });

  it('rate-limits after 3 sends in the window (429)', async () => {
    const send = () => app.inject({ method: 'POST', url: '/auth/otp/send', payload: { phone: '9811111111', role: 'CUSTOMER' } });
    await send(); await send(); await send();
    const fourth = await send();
    expect(fourth.statusCode).toBe(429);
  });
});
