import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeAdminToken, makeCustomerToken } from './helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }

describe('zones + categories', () => {
  it('MANAGER creates a zone; any authed user reads it', async () => {
    const mgr = await makeAdminToken('MANAGER');
    const create = await app.inject({ method: 'POST', url: '/catalog/zones', headers: auth(mgr), payload: { name: 'Vadodara', visitFeePaise: 14900 } });
    expect(create.statusCode).toBe(201);
    const cust = await makeCustomerToken();
    const list = await app.inject({ method: 'GET', url: '/catalog/zones', headers: auth(cust) });
    expect(list.statusCode).toBe(200);
    expect(list.json()).toHaveLength(1);
    expect(list.json()[0].visitFeePaise).toBe(14900);
  });

  it('SUPPORT cannot create a zone (403); CATALOG_UPDATED audit on create', async () => {
    const sup = await makeAdminToken('SUPPORT');
    expect((await app.inject({ method: 'POST', url: '/catalog/zones', headers: auth(sup), payload: { name: 'Padra', visitFeePaise: 9900 } })).statusCode).toBe(403);
    const mgr = await makeAdminToken('MANAGER');
    await app.inject({ method: 'POST', url: '/catalog/zones', headers: auth(mgr), payload: { name: 'Padra', visitFeePaise: 9900 } });
    const audit = await prisma.auditLog.findFirst({ where: { action: 'CATALOG_UPDATED' } });
    expect(audit).toBeTruthy();
  });

  it('duplicate zone name → 409', async () => {
    const mgr = await makeAdminToken('MANAGER');
    await app.inject({ method: 'POST', url: '/catalog/zones', headers: auth(mgr), payload: { name: 'Vadodara', visitFeePaise: 14900 } });
    const dup = await app.inject({ method: 'POST', url: '/catalog/zones', headers: auth(mgr), payload: { name: 'Vadodara', visitFeePaise: 14900 } });
    expect(dup.statusCode).toBe(409);
  });

  it('negative paise → 400', async () => {
    const mgr = await makeAdminToken('MANAGER');
    expect((await app.inject({ method: 'POST', url: '/catalog/zones', headers: auth(mgr), payload: { name: 'X', visitFeePaise: -5 } })).statusCode).toBe(400);
  });

  it('soft-deleted zone hidden from reads', async () => {
    const mgr = await makeAdminToken('MANAGER');
    const created = await app.inject({ method: 'POST', url: '/catalog/zones', headers: auth(mgr), payload: { name: 'Gone', visitFeePaise: 100 } });
    const id = created.json().id;
    await prisma.zone.update({ where: { id }, data: { deletedAt: new Date() } });
    const cust = await makeCustomerToken();
    const list = await app.inject({ method: 'GET', url: '/catalog/zones', headers: auth(cust) });
    expect(list.json().find((z: { id: string }) => z.id === id)).toBeUndefined();
  });

  it('renaming a zone to an existing name → 409', async () => {
    const mgr = await makeAdminToken('MANAGER');
    await app.inject({ method: 'POST', url: '/catalog/zones', headers: auth(mgr), payload: { name: 'Vadodara', visitFeePaise: 14900 } });
    const padra = (await app.inject({ method: 'POST', url: '/catalog/zones', headers: auth(mgr), payload: { name: 'Padra', visitFeePaise: 9900 } })).json();
    const res = await app.inject({ method: 'PATCH', url: `/catalog/zones/${padra.id}`, headers: auth(mgr), payload: { name: 'Vadodara' } });
    expect(res.statusCode).toBe(409);
  });

  it('PATCH changing both name and visitFee writes BOTH a PRICE_CHANGED and a CATALOG_UPDATED audit', async () => {
    const mgr = await makeAdminToken('MANAGER');
    const z = (await app.inject({ method: 'POST', url: '/catalog/zones', headers: auth(mgr), payload: { name: 'Z1', visitFeePaise: 10000 } })).json();
    await app.inject({ method: 'PATCH', url: `/catalog/zones/${z.id}`, headers: auth(mgr), payload: { name: 'Z1b', visitFeePaise: 12000 } });
    const priceAudit = await prisma.auditLog.findFirst({ where: { action: 'PRICE_CHANGED', metadata: { path: ['entityId'], equals: z.id } } });
    const catAudit = await prisma.auditLog.findFirst({ where: { action: 'CATALOG_UPDATED', metadata: { path: ['entityId'], equals: z.id } } });
    expect(priceAudit).toBeTruthy();
    expect(catAudit).toBeTruthy();
  });

  it('rejects non-integer (float) visitFeePaise → 400', async () => {
    const mgr = await makeAdminToken('MANAGER');
    const res = await app.inject({ method: 'POST', url: '/catalog/zones', headers: auth(mgr), payload: { name: 'Floaty', visitFeePaise: 99.5 } });
    expect(res.statusCode).toBe(400);
  });

  it('categories: MANAGER creates, user reads', async () => {
    const mgr = await makeAdminToken('MANAGER');
    expect((await app.inject({ method: 'POST', url: '/catalog/categories', headers: auth(mgr), payload: { name: 'AC' } })).statusCode).toBe(201);
    const cust = await makeCustomerToken();
    const list = await app.inject({ method: 'GET', url: '/catalog/categories', headers: auth(cust) });
    expect(list.json().some((c: { name: string }) => c.name === 'AC')).toBe(true);
  });
});
