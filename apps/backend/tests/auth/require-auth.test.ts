import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { requireAuth } from '../../src/shared/middleware/auth.js';

const app = await buildApp();
app.get('/__me', { preHandler: [requireAuth] }, async (req) => ({ id: req.user!.id, role: req.user!.role }));
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });

async function registerAndGetAccess(phone: string, role: 'CUSTOMER' | 'TECHNICIAN') {
  const send = await app.inject({ method: 'POST', url: '/auth/otp/send', payload: { phone, role } });
  const otp = send.json().devOtp as string;
  const verify = await app.inject({ method: 'POST', url: '/auth/otp/verify', payload: { phone, role, otp } });
  return verify.json() as { accessToken: string; refreshToken: string; user: { id: string } };
}

describe('requireAuth', () => {
  it('allows a valid access token and attaches request.user', async () => {
    const { accessToken, user } = await registerAndGetAccess('9800000040', 'CUSTOMER');
    const res = await app.inject({ method: 'GET', url: '/__me', headers: { authorization: `Bearer ${accessToken}` } });
    expect(res.statusCode).toBe(200);
    expect(res.json().id).toBe(user.id);
    expect(res.json().role).toBe('CUSTOMER');
  });

  it('rejects a missing token with 401', async () => {
    const res = await app.inject({ method: 'GET', url: '/__me' });
    expect(res.statusCode).toBe(401);
  });

  it('rejects a garbage token with 401', async () => {
    const res = await app.inject({ method: 'GET', url: '/__me', headers: { authorization: 'Bearer not-a-jwt' } });
    expect(res.statusCode).toBe(401);
  });

  it('rejects a suspended user with 403', async () => {
    const { accessToken, user } = await registerAndGetAccess('9800000041', 'CUSTOMER');
    await prisma.user.update({ where: { id: user.id }, data: { status: 'SUSPENDED' } });
    const res = await app.inject({ method: 'GET', url: '/__me', headers: { authorization: `Bearer ${accessToken}` } });
    expect(res.statusCode).toBe(403);
  });

  it('rejects a soft-deleted user with 401', async () => {
    const { accessToken, user } = await registerAndGetAccess('9800000042', 'CUSTOMER');
    await prisma.user.update({ where: { id: user.id }, data: { deletedAt: new Date() } });
    const res = await app.inject({ method: 'GET', url: '/__me', headers: { authorization: `Bearer ${accessToken}` } });
    expect(res.statusCode).toBe(401);
  });
});
