import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });

async function register(phone: string) {
  const send = await app.inject({ method: 'POST', url: '/auth/otp/send', payload: { phone, role: 'CUSTOMER' } });
  const otp = send.json().devOtp as string;
  const verify = await app.inject({ method: 'POST', url: '/auth/otp/verify', payload: { phone, role: 'CUSTOMER', otp } });
  return verify.json() as { accessToken: string; refreshToken: string; user: { id: string } };
}

describe('logout', () => {
  it('POST /auth/logout revokes the presented refresh token', async () => {
    const { refreshToken, user } = await register('9800000060');
    const res = await app.inject({ method: 'POST', url: '/auth/logout', payload: { refreshToken } });
    expect(res.statusCode).toBe(200);
    const row = await prisma.refreshToken.findFirst({ where: { userId: user.id } });
    expect(row!.revokedAt).not.toBeNull();
    const refresh = await app.inject({ method: 'POST', url: '/auth/refresh', payload: { refreshToken } });
    expect(refresh.statusCode).toBe(401);
  });

  it('POST /auth/logout-all revokes ALL the authed user\'s tokens', async () => {
    const { accessToken, refreshToken, user } = await register('9800000061');
    await app.inject({ method: 'POST', url: '/auth/refresh', payload: { refreshToken } });
    const res = await app.inject({ method: 'POST', url: '/auth/logout-all', headers: { authorization: `Bearer ${accessToken}` } });
    expect(res.statusCode).toBe(200);
    const active = await prisma.refreshToken.count({ where: { userId: user.id, revokedAt: null } });
    expect(active).toBe(0);
  });

  it('POST /auth/logout-all without a token → 401', async () => {
    const res = await app.inject({ method: 'POST', url: '/auth/logout-all' });
    expect(res.statusCode).toBe(401);
  });
});
