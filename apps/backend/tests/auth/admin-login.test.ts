import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { hashPassword } from '../../src/shared/auth/argon2.js';
import { requireAuth } from '../../src/shared/middleware/auth.js';

const app = await buildApp();
app.get('/__me', { preHandler: [requireAuth] }, async (req) => ({ id: req.user!.id, role: req.user!.role }));
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });

async function makeAdmin(email: string, password: string, opts: { status?: 'ACTIVE' | 'SUSPENDED'; deleted?: boolean } = {}) {
  const user = await prisma.user.create({ data: { phone: '9' + Math.floor(1e9 + Math.random() * 8e9), role: 'ADMIN' } });
  await prisma.admin.create({
    data: {
      userId: user.id, name: 'Boss', email, passwordHash: await hashPassword(password),
      adminLevel: 'SUPER_ADMIN', status: opts.status ?? 'ACTIVE',
      ...(opts.deleted ? { deletedAt: new Date() } : {}),
    },
  });
  return user;
}

describe('POST /admin/auth/login', () => {
  it('valid credentials → 200 + tokens + admin DTO (no passwordHash) + ADMIN role', async () => {
    await makeAdmin('boss@fixcare.in', 'super-secret-pw');
    const res = await app.inject({ method: 'POST', url: '/admin/auth/login', payload: { email: 'boss@fixcare.in', password: 'super-secret-pw' } });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.accessToken).toBeTruthy();
    expect(body.refreshToken).toBeTruthy();
    expect(body.admin.email).toBe('boss@fixcare.in');
    expect(body.admin.adminLevel).toBe('SUPER_ADMIN');
    expect(body.admin.passwordHash).toBeUndefined();

    const me = await app.inject({ method: 'GET', url: '/__me', headers: { authorization: `Bearer ${body.accessToken}` } });
    expect(me.statusCode).toBe(200);
    expect(me.json().role).toBe('ADMIN');
  });

  it('wrong password → 401, and unknown email → identical 401 (no enumeration)', async () => {
    await makeAdmin('boss2@fixcare.in', 'super-secret-pw');
    const wrong = await app.inject({ method: 'POST', url: '/admin/auth/login', payload: { email: 'boss2@fixcare.in', password: 'nope' } });
    const unknown = await app.inject({ method: 'POST', url: '/admin/auth/login', payload: { email: 'ghost@fixcare.in', password: 'whatever' } });
    expect(wrong.statusCode).toBe(401);
    expect(unknown.statusCode).toBe(401);
    expect(wrong.json()).toEqual(unknown.json());
  });

  it('suspended admin → 403', async () => {
    await makeAdmin('susp@fixcare.in', 'super-secret-pw', { status: 'SUSPENDED' });
    const res = await app.inject({ method: 'POST', url: '/admin/auth/login', payload: { email: 'susp@fixcare.in', password: 'super-secret-pw' } });
    expect(res.statusCode).toBe(403);
  });

  it('soft-deleted admin → 403', async () => {
    await makeAdmin('del@fixcare.in', 'super-secret-pw', { deleted: true });
    const res = await app.inject({ method: 'POST', url: '/admin/auth/login', payload: { email: 'del@fixcare.in', password: 'super-secret-pw' } });
    expect(res.statusCode).toBe(403);
  });
});
