import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { registerAndToken } from './helpers.js';
import { signAccessToken } from '../../src/shared/auth/tokens.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });

describe('GET /me/profile', () => {
  it('returns a customer profile (no skills field)', async () => {
    const { token } = await registerAndToken(app, '9800000070', 'CUSTOMER');
    const res = await app.inject({ method: 'GET', url: '/me/profile', headers: { authorization: `Bearer ${token}` } });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.role).toBe('CUSTOMER');
    expect(body).toHaveProperty('name');
    expect(body.skills).toBeUndefined();
  });

  it('returns a technician profile with skills', async () => {
    const { token } = await registerAndToken(app, '9800000071', 'TECHNICIAN');
    const res = await app.inject({ method: 'GET', url: '/me/profile', headers: { authorization: `Bearer ${token}` } });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.role).toBe('TECHNICIAN');
    expect(Array.isArray(body.skills)).toBe(true);
  });

  it('rejects a request with no token (401)', async () => {
    const res = await app.inject({ method: 'GET', url: '/me/profile' });
    expect(res.statusCode).toBe(401);
  });

  it('rejects an ADMIN caller (403 — endpoint is customer/technician only)', async () => {
    const user = await prisma.user.create({ data: { phone: '9800000072', role: 'ADMIN' } });
    const token = signAccessToken(user.id, 'ADMIN');
    const res = await app.inject({ method: 'GET', url: '/me/profile', headers: { authorization: `Bearer ${token}` } });
    expect(res.statusCode).toBe(403);
  });

  it('rejects a MERCHANT caller (403)', async () => {
    const user = await prisma.user.create({ data: { phone: '9800000074', role: 'MERCHANT' } });
    const token = signAccessToken(user.id, 'MERCHANT');
    const res = await app.inject({ method: 'GET', url: '/me/profile', headers: { authorization: `Bearer ${token}` } });
    expect(res.statusCode).toBe(403);
  });

  it('returns 404 when the profile is soft-deleted', async () => {
    const { token, userId } = await registerAndToken(app, '9800000073', 'CUSTOMER');
    await prisma.customer.update({ where: { userId }, data: { deletedAt: new Date() } });
    const res = await app.inject({ method: 'GET', url: '/me/profile', headers: { authorization: `Bearer ${token}` } });
    expect(res.statusCode).toBe(404);
  });
});
