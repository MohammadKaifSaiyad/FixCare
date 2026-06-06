import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeAdminToken, makeCustomerToken } from './helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }

async function makeZone(name: string, fee: number) {
  const mgr = await makeAdminToken('MANAGER');
  return (await app.inject({ method: 'POST', url: '/catalog/zones', headers: auth(mgr), payload: { name, visitFeePaise: fee } })).json();
}

describe('admin pincode map', () => {
  it('MANAGER creates a mapping; any authed user lists it', async () => {
    const zone = await makeZone('Vadodara', 14900);
    const mgr = await makeAdminToken('MANAGER');
    const create = await app.inject({ method: 'POST', url: '/catalog/pincodes', headers: auth(mgr), payload: { pincode: '390001', zoneId: zone.id } });
    expect(create.statusCode).toBe(201);
    expect(create.json()).toMatchObject({ pincode: '390001', zoneId: zone.id, status: 'ACTIVE' });
    const cust = await makeCustomerToken();
    const list = await app.inject({ method: 'GET', url: '/catalog/pincodes', headers: auth(cust) });
    expect(list.statusCode).toBe(200);
    expect(list.json().some((p: { pincode: string }) => p.pincode === '390001')).toBe(true);
  });

  it('SUPPORT cannot create a mapping → 403; create writes a CATALOG_UPDATED audit', async () => {
    const zone = await makeZone('Vadodara', 14900);
    const sup = await makeAdminToken('SUPPORT');
    expect((await app.inject({ method: 'POST', url: '/catalog/pincodes', headers: auth(sup), payload: { pincode: '390001', zoneId: zone.id } })).statusCode).toBe(403);
    const mgr = await makeAdminToken('MANAGER');
    const p = (await app.inject({ method: 'POST', url: '/catalog/pincodes', headers: auth(mgr), payload: { pincode: '390002', zoneId: zone.id } })).json();
    const audit = await prisma.auditLog.findFirst({ where: { action: 'CATALOG_UPDATED', metadata: { path: ['entityId'], equals: p.id } } });
    expect(audit).toBeTruthy();
    expect((audit!.metadata as { entity: string }).entity).toBe('PincodeZone');
  });

  it('duplicate pincode → 409', async () => {
    const zone = await makeZone('Vadodara', 14900);
    const mgr = await makeAdminToken('MANAGER');
    await app.inject({ method: 'POST', url: '/catalog/pincodes', headers: auth(mgr), payload: { pincode: '390001', zoneId: zone.id } });
    const dup = await app.inject({ method: 'POST', url: '/catalog/pincodes', headers: auth(mgr), payload: { pincode: '390001', zoneId: zone.id } });
    expect(dup.statusCode).toBe(409);
  });

  it('non-6-digit pincode → 400', async () => {
    const zone = await makeZone('Vadodara', 14900);
    const mgr = await makeAdminToken('MANAGER');
    expect((await app.inject({ method: 'POST', url: '/catalog/pincodes', headers: auth(mgr), payload: { pincode: '39', zoneId: zone.id } })).statusCode).toBe(400);
  });

  it('POST with unknown zoneId → 404', async () => {
    const mgr = await makeAdminToken('MANAGER');
    const res = await app.inject({ method: 'POST', url: '/catalog/pincodes', headers: auth(mgr), payload: { pincode: '390001', zoneId: '00000000-0000-0000-0000-000000000000' } });
    expect(res.statusCode).toBe(404);
  });

  it('PATCH re-points zone; returns new zoneId and writes a CATALOG_UPDATED audit', async () => {
    const v = await makeZone('Vadodara', 14900);
    const p2 = await makeZone('Padra', 9900);
    const mgr = await makeAdminToken('MANAGER');
    const pin = (await app.inject({ method: 'POST', url: '/catalog/pincodes', headers: auth(mgr), payload: { pincode: '391440', zoneId: v.id } })).json();
    const res = await app.inject({ method: 'PATCH', url: `/catalog/pincodes/${pin.id}`, headers: auth(mgr), payload: { zoneId: p2.id } });
    expect(res.statusCode).toBe(200);
    expect(res.json().zoneId).toBe(p2.id);
    // PATCH must write its own CATALOG_UPDATED audit (in-transaction) — not just the create's.
    const audits = await prisma.auditLog.findMany({ where: { action: 'CATALOG_UPDATED', metadata: { path: ['entityId'], equals: pin.id } } });
    expect(audits.length).toBe(2); // one from create, one from this PATCH
    const patchAudit = audits.find((a) => (a.metadata as { fields?: string[] }).fields?.includes('zoneId') && !(a.metadata as { fields?: string[] }).fields?.includes('pincode'));
    expect(patchAudit).toBeTruthy();
    // a zone re-point is price-significant → audit captures from→to zone
    expect(patchAudit!.metadata).toMatchObject({ fromZoneId: v.id, toZoneId: p2.id });
  });

  it('listPincodes excludes INACTIVE mappings (consistent with the resolver)', async () => {
    const v = await makeZone('Vadodara', 14900);
    const mgr = await makeAdminToken('MANAGER');
    const pin = (await app.inject({ method: 'POST', url: '/catalog/pincodes', headers: auth(mgr), payload: { pincode: '391444', zoneId: v.id } })).json();
    await app.inject({ method: 'PATCH', url: `/catalog/pincodes/${pin.id}`, headers: auth(mgr), payload: { status: 'INACTIVE' } });
    const cust = await makeCustomerToken();
    const list = (await app.inject({ method: 'GET', url: '/catalog/pincodes', headers: auth(cust) })).json();
    expect(list.find((p: { id: string }) => p.id === pin.id)).toBeUndefined();
  });

  it('PATCH with no real change writes NO new audit (changed-only)', async () => {
    const v = await makeZone('Vadodara', 14900);
    const mgr = await makeAdminToken('MANAGER');
    const pin = (await app.inject({ method: 'POST', url: '/catalog/pincodes', headers: auth(mgr), payload: { pincode: '391443', zoneId: v.id } })).json();
    await app.inject({ method: 'PATCH', url: `/catalog/pincodes/${pin.id}`, headers: auth(mgr), payload: { zoneId: v.id, status: 'ACTIVE' } });
    const count = await prisma.auditLog.count({ where: { action: 'CATALOG_UPDATED', metadata: { path: ['entityId'], equals: pin.id } } });
    expect(count).toBe(1); // only the create audit; the no-op PATCH added none
  });

  it('PATCH a non-existent mapping → 404; PATCH with unknown zoneId → 404', async () => {
    const v = await makeZone('Vadodara', 14900);
    const mgr = await makeAdminToken('MANAGER');
    expect((await app.inject({ method: 'PATCH', url: '/catalog/pincodes/00000000-0000-0000-0000-000000000000', headers: auth(mgr), payload: { status: 'INACTIVE' } })).statusCode).toBe(404);
    const pin = (await app.inject({ method: 'POST', url: '/catalog/pincodes', headers: auth(mgr), payload: { pincode: '391441', zoneId: v.id } })).json();
    expect((await app.inject({ method: 'PATCH', url: `/catalog/pincodes/${pin.id}`, headers: auth(mgr), payload: { zoneId: '00000000-0000-0000-0000-000000000000' } })).statusCode).toBe(404);
  });

  it('DELETE soft-deletes and hides from list', async () => {
    const v = await makeZone('Vadodara', 14900);
    const mgr = await makeAdminToken('MANAGER');
    const pin = (await app.inject({ method: 'POST', url: '/catalog/pincodes', headers: auth(mgr), payload: { pincode: '391442', zoneId: v.id } })).json();
    expect((await app.inject({ method: 'DELETE', url: `/catalog/pincodes/${pin.id}`, headers: auth(mgr) })).statusCode).toBe(204);
    const cust = await makeCustomerToken();
    const list = (await app.inject({ method: 'GET', url: '/catalog/pincodes', headers: auth(cust) })).json();
    expect(list.find((p: { id: string }) => p.id === pin.id)).toBeUndefined();
  });
});
