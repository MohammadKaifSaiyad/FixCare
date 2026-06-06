import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeAdminToken, makeCustomerToken } from './helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }

describe('parts catalog', () => {
  it('MANAGER creates a part; any authed user reads it (active only)', async () => {
    const mgr = await makeAdminToken('MANAGER');
    const create = await app.inject({ method: 'POST', url: '/catalog/parts', headers: auth(mgr), payload: { sku: 'AC-COMP-1.5T', name: 'AC compressor 1.5T', ceilingPricePaise: 850000 } });
    expect(create.statusCode).toBe(201);
    const cust = await makeCustomerToken();
    const list = await app.inject({ method: 'GET', url: '/catalog/parts', headers: auth(cust) });
    expect(list.statusCode).toBe(200);
    expect(list.json()).toHaveLength(1);
    expect(list.json()[0]).toMatchObject({ sku: 'AC-COMP-1.5T', ceilingPricePaise: 850000, categoryId: null });
  });

  it('GET /catalog/parts requires a token → 401', async () => {
    const res = await app.inject({ method: 'GET', url: '/catalog/parts' });
    expect(res.statusCode).toBe(401);
  });

  it('INACTIVE and soft-deleted parts are hidden from reads', async () => {
    const mgr = await makeAdminToken('MANAGER');
    const active = (await app.inject({ method: 'POST', url: '/catalog/parts', headers: auth(mgr), payload: { sku: 'A', name: 'Active', ceilingPricePaise: 100 } })).json();
    const inactive = (await app.inject({ method: 'POST', url: '/catalog/parts', headers: auth(mgr), payload: { sku: 'B', name: 'Inactive', ceilingPricePaise: 200 } })).json();
    const deleted = (await app.inject({ method: 'POST', url: '/catalog/parts', headers: auth(mgr), payload: { sku: 'C', name: 'Deleted', ceilingPricePaise: 300 } })).json();
    await prisma.partsCatalog.update({ where: { id: inactive.id }, data: { status: 'INACTIVE' } });
    await prisma.partsCatalog.update({ where: { id: deleted.id }, data: { deletedAt: new Date() } });
    const cust = await makeCustomerToken();
    const ids = (await app.inject({ method: 'GET', url: '/catalog/parts', headers: auth(cust) })).json().map((p: { id: string }) => p.id);
    expect(ids).toEqual([active.id]);
  });

  it('filters by categoryId', async () => {
    const mgr = await makeAdminToken('MANAGER');
    const cat = (await app.inject({ method: 'POST', url: '/catalog/categories', headers: auth(mgr), payload: { name: 'AC' } })).json();
    await app.inject({ method: 'POST', url: '/catalog/parts', headers: auth(mgr), payload: { sku: 'IN-CAT', name: 'In cat', categoryId: cat.id, ceilingPricePaise: 100 } });
    await app.inject({ method: 'POST', url: '/catalog/parts', headers: auth(mgr), payload: { sku: 'NO-CAT', name: 'No cat', ceilingPricePaise: 200 } });
    const cust = await makeCustomerToken();
    const list = (await app.inject({ method: 'GET', url: `/catalog/parts?categoryId=${cat.id}`, headers: auth(cust) })).json();
    expect(list).toHaveLength(1);
    expect(list[0].sku).toBe('IN-CAT');
  });

  it('SUPPORT cannot create a part → 403', async () => {
    const sup = await makeAdminToken('SUPPORT');
    const res = await app.inject({ method: 'POST', url: '/catalog/parts', headers: auth(sup), payload: { sku: 'X', name: 'X', ceilingPricePaise: 100 } });
    expect(res.statusCode).toBe(403);
  });

  it('duplicate sku → 409', async () => {
    const mgr = await makeAdminToken('MANAGER');
    await app.inject({ method: 'POST', url: '/catalog/parts', headers: auth(mgr), payload: { sku: 'DUP', name: 'A', ceilingPricePaise: 100 } });
    const dup = await app.inject({ method: 'POST', url: '/catalog/parts', headers: auth(mgr), payload: { sku: 'DUP', name: 'B', ceilingPricePaise: 200 } });
    expect(dup.statusCode).toBe(409);
  });

  it('negative or float ceilingPricePaise → 400', async () => {
    const mgr = await makeAdminToken('MANAGER');
    expect((await app.inject({ method: 'POST', url: '/catalog/parts', headers: auth(mgr), payload: { sku: 'N', name: 'N', ceilingPricePaise: -1 } })).statusCode).toBe(400);
    expect((await app.inject({ method: 'POST', url: '/catalog/parts', headers: auth(mgr), payload: { sku: 'F', name: 'F', ceilingPricePaise: 99.5 } })).statusCode).toBe(400);
  });

  it('create writes a CATALOG_UPDATED audit', async () => {
    const mgr = await makeAdminToken('MANAGER');
    const part = (await app.inject({ method: 'POST', url: '/catalog/parts', headers: auth(mgr), payload: { sku: 'AUD', name: 'Aud', ceilingPricePaise: 100 } })).json();
    const audit = await prisma.auditLog.findFirst({ where: { action: 'CATALOG_UPDATED', metadata: { path: ['entityId'], equals: part.id } } });
    expect(audit).toBeTruthy();
    expect((audit!.metadata as { entity: string }).entity).toBe('PartsCatalog');
  });

  it('PATCH changing ceiling price writes a PRICE_CHANGED audit (from→to)', async () => {
    const mgr = await makeAdminToken('MANAGER');
    const part = (await app.inject({ method: 'POST', url: '/catalog/parts', headers: auth(mgr), payload: { sku: 'PC', name: 'Pc', ceilingPricePaise: 1000 } })).json();
    const res = await app.inject({ method: 'PATCH', url: `/catalog/parts/${part.id}`, headers: auth(mgr), payload: { ceilingPricePaise: 1500 } });
    expect(res.statusCode).toBe(200);
    expect(res.json().ceilingPricePaise).toBe(1500);
    const audit = await prisma.auditLog.findFirst({ where: { action: 'PRICE_CHANGED', metadata: { path: ['entityId'], equals: part.id } } });
    expect(audit).toBeTruthy();
    const md = audit!.metadata as { field: string; fromPaise: number; toPaise: number };
    expect(md).toMatchObject({ field: 'ceilingPricePaise', fromPaise: 1000, toPaise: 1500 });
  });

  it('PATCH changing name only writes CATALOG_UPDATED, not PRICE_CHANGED', async () => {
    const mgr = await makeAdminToken('MANAGER');
    const part = (await app.inject({ method: 'POST', url: '/catalog/parts', headers: auth(mgr), payload: { sku: 'NM', name: 'Old', ceilingPricePaise: 1000 } })).json();
    await app.inject({ method: 'PATCH', url: `/catalog/parts/${part.id}`, headers: auth(mgr), payload: { name: 'New' } });
    const priceAudit = await prisma.auditLog.findFirst({ where: { action: 'PRICE_CHANGED', metadata: { path: ['entityId'], equals: part.id } } });
    const catAudit = await prisma.auditLog.findFirst({ where: { action: 'CATALOG_UPDATED', metadata: { path: ['entityId'], equals: part.id } } });
    expect(priceAudit).toBeNull();
    expect(catAudit).toBeTruthy();
  });

  it('PATCH a non-existent or soft-deleted part → 404', async () => {
    const mgr = await makeAdminToken('MANAGER');
    expect((await app.inject({ method: 'PATCH', url: '/catalog/parts/00000000-0000-0000-0000-000000000000', headers: auth(mgr), payload: { name: 'X' } })).statusCode).toBe(404);
    const part = (await app.inject({ method: 'POST', url: '/catalog/parts', headers: auth(mgr), payload: { sku: 'GONE', name: 'Gone', ceilingPricePaise: 100 } })).json();
    await prisma.partsCatalog.update({ where: { id: part.id }, data: { deletedAt: new Date() } });
    expect((await app.inject({ method: 'PATCH', url: `/catalog/parts/${part.id}`, headers: auth(mgr), payload: { name: 'X' } })).statusCode).toBe(404);
  });

  it('PATCH with an unknown categoryId → 404', async () => {
    const mgr = await makeAdminToken('MANAGER');
    const part = (await app.inject({ method: 'POST', url: '/catalog/parts', headers: auth(mgr), payload: { sku: 'CAT', name: 'Cat', ceilingPricePaise: 100 } })).json();
    const res = await app.inject({ method: 'PATCH', url: `/catalog/parts/${part.id}`, headers: auth(mgr), payload: { categoryId: '00000000-0000-0000-0000-000000000000' } });
    expect(res.statusCode).toBe(404);
  });

  it('soft-delete via PATCH status INACTIVE removes it from reads', async () => {
    const mgr = await makeAdminToken('MANAGER');
    const part = (await app.inject({ method: 'POST', url: '/catalog/parts', headers: auth(mgr), payload: { sku: 'DEL', name: 'Del', ceilingPricePaise: 100 } })).json();
    await app.inject({ method: 'PATCH', url: `/catalog/parts/${part.id}`, headers: auth(mgr), payload: { status: 'INACTIVE' } });
    const cust = await makeCustomerToken();
    const list = (await app.inject({ method: 'GET', url: '/catalog/parts', headers: auth(cust) })).json();
    expect(list.find((p: { id: string }) => p.id === part.id)).toBeUndefined();
  });
});
