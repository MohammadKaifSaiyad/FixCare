import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeAdminToken, makeCustomerToken } from './helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }

async function makeCategory(name: string) {
  const mgr = await makeAdminToken('MANAGER');
  return (await app.inject({ method: 'POST', url: '/catalog/categories', headers: auth(mgr), payload: { name } })).json();
}

describe('diagnosed-issue catalog', () => {
  it('MANAGER creates an issue; any authed user lists by category', async () => {
    const cat = await makeCategory('AC');
    const mgr = await makeAdminToken('MANAGER');
    const create = await app.inject({ method: 'POST', url: '/catalog/issues', headers: auth(mgr), payload: { name: 'Compressor fault', categoryId: cat.id } });
    expect(create.statusCode).toBe(201);
    expect(create.json()).toMatchObject({ name: 'Compressor fault', categoryId: cat.id, status: 'ACTIVE' });
    const cust = await makeCustomerToken();
    const list = await app.inject({ method: 'GET', url: `/catalog/issues?categoryId=${cat.id}`, headers: auth(cust) });
    expect(list.statusCode).toBe(200);
    expect(list.json().some((i: { name: string }) => i.name === 'Compressor fault')).toBe(true);
  });

  it('SUPPORT cannot create (403); create writes a CATALOG_UPDATED audit', async () => {
    const cat = await makeCategory('AC');
    const sup = await makeAdminToken('SUPPORT');
    expect((await app.inject({ method: 'POST', url: '/catalog/issues', headers: auth(sup), payload: { name: 'X', categoryId: cat.id } })).statusCode).toBe(403);
    const mgr = await makeAdminToken('MANAGER');
    const i = (await app.inject({ method: 'POST', url: '/catalog/issues', headers: auth(mgr), payload: { name: 'Gas leak', categoryId: cat.id } })).json();
    const audit = await prisma.auditLog.findFirst({ where: { action: 'CATALOG_UPDATED', metadata: { path: ['entityId'], equals: i.id } } });
    expect(audit).toBeTruthy();
    expect((audit!.metadata as { entity: string }).entity).toBe('DiagnosedIssue');
  });

  it('duplicate (category,name) → 409; unknown category → 404', async () => {
    const cat = await makeCategory('AC');
    const mgr = await makeAdminToken('MANAGER');
    await app.inject({ method: 'POST', url: '/catalog/issues', headers: auth(mgr), payload: { name: 'Dup', categoryId: cat.id } });
    expect((await app.inject({ method: 'POST', url: '/catalog/issues', headers: auth(mgr), payload: { name: 'Dup', categoryId: cat.id } })).statusCode).toBe(409);
    expect((await app.inject({ method: 'POST', url: '/catalog/issues', headers: auth(mgr), payload: { name: 'Y', categoryId: '00000000-0000-0000-0000-000000000000' } })).statusCode).toBe(404);
  });

  it('PATCH status / DELETE soft-delete hides from list', async () => {
    const cat = await makeCategory('AC');
    const mgr = await makeAdminToken('MANAGER');
    const i = (await app.inject({ method: 'POST', url: '/catalog/issues', headers: auth(mgr), payload: { name: 'Gone', categoryId: cat.id } })).json();
    expect((await app.inject({ method: 'DELETE', url: `/catalog/issues/${i.id}`, headers: auth(mgr) })).statusCode).toBe(204);
    const cust = await makeCustomerToken();
    const list = (await app.inject({ method: 'GET', url: `/catalog/issues?categoryId=${cat.id}`, headers: auth(cust) })).json();
    expect(list.find((x: { id: string }) => x.id === i.id)).toBeUndefined();
  });
});
