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

describe('POST /auth/refresh', () => {
  it('rotates a valid refresh token (new tokens; old revoked + linked)', async () => {
    const { refreshToken, user } = await register('9800000050');
    const res = await app.inject({ method: 'POST', url: '/auth/refresh', payload: { refreshToken } });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.accessToken).toBeTruthy();
    expect(body.refreshToken).toBeTruthy();
    expect(body.refreshToken).not.toBe(refreshToken);

    const rows = await prisma.refreshToken.findMany({ where: { userId: user.id }, orderBy: { createdAt: 'asc' } });
    expect(rows.length).toBe(2);
    expect(rows[0]!.revokedAt).not.toBeNull();
    expect(rows[0]!.replacedById).toBe(rows[1]!.id);
    expect(rows[1]!.revokedAt).toBeNull();
  });

  it('reused (revoked) token → 401 + ALL user tokens revoked + audit', async () => {
    const { refreshToken, user } = await register('9800000051');
    await app.inject({ method: 'POST', url: '/auth/refresh', payload: { refreshToken } });
    const replay = await app.inject({ method: 'POST', url: '/auth/refresh', payload: { refreshToken } });
    expect(replay.statusCode).toBe(401);

    const active = await prisma.refreshToken.count({ where: { userId: user.id, revokedAt: null } });
    expect(active).toBe(0);
    const audit = await prisma.auditLog.findFirst({ where: { action: 'REFRESH_TOKEN_REUSE_DETECTED', subjectId: user.id } });
    expect(audit).toBeTruthy();
    expect(audit!.actorType).toBe('SYSTEM');
  });

  it('unknown token → 401', async () => {
    const res = await app.inject({ method: 'POST', url: '/auth/refresh', payload: { refreshToken: 'nope' } });
    expect(res.statusCode).toBe(401);
  });

  it('expired token → 401', async () => {
    const { refreshToken, user } = await register('9800000052');
    await prisma.refreshToken.updateMany({ where: { userId: user.id }, data: { expiresAt: new Date(Date.now() - 1000) } });
    const res = await app.inject({ method: 'POST', url: '/auth/refresh', payload: { refreshToken } });
    expect(res.statusCode).toBe(401);
  });
});
