import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { requireAuth } from '../../src/shared/middleware/auth.js';
import { requireAdminLevel } from '../../src/shared/middleware/rbac.js';
import { makeAdminToken, makeCustomerToken } from './helpers.js';

const app = await buildApp();
app.get('/__manager-only', { preHandler: [requireAuth, requireAdminLevel('MANAGER')] }, async () => ({ ok: true }));
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }

describe('requireAdminLevel(MANAGER)', () => {
  it('allows SUPER_ADMIN', async () => {
    const t = await makeAdminToken('SUPER_ADMIN');
    expect((await app.inject({ method: 'GET', url: '/__manager-only', headers: auth(t) })).statusCode).toBe(200);
  });
  it('allows MANAGER', async () => {
    const t = await makeAdminToken('MANAGER');
    expect((await app.inject({ method: 'GET', url: '/__manager-only', headers: auth(t) })).statusCode).toBe(200);
  });
  it('rejects SUPPORT (403)', async () => {
    const t = await makeAdminToken('SUPPORT');
    expect((await app.inject({ method: 'GET', url: '/__manager-only', headers: auth(t) })).statusCode).toBe(403);
  });
  it('rejects a customer (403)', async () => {
    const t = await makeCustomerToken();
    expect((await app.inject({ method: 'GET', url: '/__manager-only', headers: auth(t) })).statusCode).toBe(403);
  });
  it('rejects no token (401)', async () => {
    expect((await app.inject({ method: 'GET', url: '/__manager-only' })).statusCode).toBe(401);
  });
});
