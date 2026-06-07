import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomerToken, makeAdminToken, seedZoneWithPincode } from './helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }

const base = { label: 'Home', line1: '12 MG Road', pincode: '390001' };

describe('POST /me/addresses + GET /me/addresses', () => {
  it('customer creates an address (first one auto-default) with live serviceability', async () => {
    await seedZoneWithPincode('Vadodara', 14900, '390001');
    const tok = await makeCustomerToken();
    const res = await app.inject({ method: 'POST', url: '/me/addresses', headers: auth(tok), payload: base });
    expect(res.statusCode).toBe(201);
    expect(res.json()).toMatchObject({
      label: 'Home', line1: '12 MG Road', pincode: '390001',
      isDefault: true, serviceable: true, zone: { name: 'Vadodara', visitFeePaise: 14900 },
    });
  });

  it('out-of-area pincode still saves (201) but serviceable:false + message', async () => {
    const tok = await makeCustomerToken();
    const res = await app.inject({ method: 'POST', url: '/me/addresses', headers: auth(tok), payload: { ...base, pincode: '395003' } });
    expect(res.statusCode).toBe(201);
    expect(res.json()).toMatchObject({ serviceable: false, zone: null, message: "We don't serve this area yet" });
  });

  it('GET lists only the caller own active addresses with LIVE serviceability', async () => {
    await seedZoneWithPincode('Vadodara', 14900, '390001');
    const a = await makeCustomerToken();
    await app.inject({ method: 'POST', url: '/me/addresses', headers: auth(a), payload: base });
    const b = await makeCustomerToken();
    await app.inject({ method: 'POST', url: '/me/addresses', headers: auth(b), payload: { ...base, label: 'B' } });
    const listA = await app.inject({ method: 'GET', url: '/me/addresses', headers: auth(a) });
    expect(listA.statusCode).toBe(200);
    expect(listA.json()).toHaveLength(1);
    expect(listA.json()[0].label).toBe('Home');
    expect(listA.json()[0].serviceable).toBe(true);
  });

  it('coverage expansion: out-of-area address becomes serviceable after admin adds its pincode (re-resolve on read)', async () => {
    const tok = await makeCustomerToken();
    const created = (await app.inject({ method: 'POST', url: '/me/addresses', headers: auth(tok), payload: { ...base, pincode: '390050' } })).json();
    expect(created.serviceable).toBe(false);
    await seedZoneWithPincode('Vadodara', 14900, '390050');
    const list = (await app.inject({ method: 'GET', url: '/me/addresses', headers: auth(tok) })).json();
    expect(list[0].serviceable).toBe(true);
    expect(list[0].zone.name).toBe('Vadodara');
  });

  it('non-CUSTOMER (admin) → 403; no token → 401; lat without lng → 400', async () => {
    const adm = await makeAdminToken('MANAGER');
    expect((await app.inject({ method: 'POST', url: '/me/addresses', headers: auth(adm), payload: base })).statusCode).toBe(403);
    expect((await app.inject({ method: 'GET', url: '/me/addresses' })).statusCode).toBe(401);
    const tok = await makeCustomerToken();
    expect((await app.inject({ method: 'POST', url: '/me/addresses', headers: auth(tok), payload: { ...base, lat: 22.3 } })).statusCode).toBe(400);
  });
});

describe('GET/PATCH/DELETE /me/addresses/:id + default rule', () => {
  it('GET :id returns own; another customer id → 404 (no IDOR)', async () => {
    const a = await makeCustomerToken();
    const addr = (await app.inject({ method: 'POST', url: '/me/addresses', headers: auth(a), payload: base })).json();
    const got = await app.inject({ method: 'GET', url: `/me/addresses/${addr.id}`, headers: auth(a) });
    expect(got.statusCode).toBe(200);
    expect(got.json().id).toBe(addr.id);
    const b = await makeCustomerToken();
    expect((await app.inject({ method: 'GET', url: `/me/addresses/${addr.id}`, headers: auth(b) })).statusCode).toBe(404);
  });

  it('GET a non-existent id → 404', async () => {
    const a = await makeCustomerToken();
    expect((await app.inject({ method: 'GET', url: '/me/addresses/00000000-0000-0000-0000-000000000000', headers: auth(a) })).statusCode).toBe(404);
  });

  it('PATCH updates own fields; can clear line2 to null', async () => {
    const a = await makeCustomerToken();
    const addr = (await app.inject({ method: 'POST', url: '/me/addresses', headers: auth(a), payload: { ...base, line2: 'Flat 4' } })).json();
    const res = await app.inject({ method: 'PATCH', url: `/me/addresses/${addr.id}`, headers: auth(a), payload: { label: 'Work', line2: null } });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ label: 'Work', line2: null });
  });

  it('PATCH another customer address → 404; empty body → 400', async () => {
    const a = await makeCustomerToken();
    const addr = (await app.inject({ method: 'POST', url: '/me/addresses', headers: auth(a), payload: base })).json();
    const b = await makeCustomerToken();
    expect((await app.inject({ method: 'PATCH', url: `/me/addresses/${addr.id}`, headers: auth(b), payload: { label: 'X' } })).statusCode).toBe(404);
    expect((await app.inject({ method: 'PATCH', url: `/me/addresses/${addr.id}`, headers: auth(a), payload: {} })).statusCode).toBe(400);
  });

  it('PATCH pincode re-resolves the zone (serviceability updates)', async () => {
    await seedZoneWithPincode('Vadodara', 14900, '390001');
    const a = await makeCustomerToken();
    const addr = (await app.inject({ method: 'POST', url: '/me/addresses', headers: auth(a), payload: { ...base, pincode: '395003' } })).json();
    expect(addr.serviceable).toBe(false);
    const res = await app.inject({ method: 'PATCH', url: `/me/addresses/${addr.id}`, headers: auth(a), payload: { pincode: '390001' } });
    expect(res.json()).toMatchObject({ serviceable: true, zone: { name: 'Vadodara' } });
  });

  it('setting a new default clears the previous one (exactly one default)', async () => {
    const a = await makeCustomerToken();
    const first = (await app.inject({ method: 'POST', url: '/me/addresses', headers: auth(a), payload: base })).json();
    const second = (await app.inject({ method: 'POST', url: '/me/addresses', headers: auth(a), payload: { ...base, label: 'Office' } })).json();
    expect(first.isDefault).toBe(true);
    expect(second.isDefault).toBe(false);
    await app.inject({ method: 'PATCH', url: `/me/addresses/${second.id}`, headers: auth(a), payload: { isDefault: true } });
    const list = (await app.inject({ method: 'GET', url: '/me/addresses', headers: auth(a) })).json();
    const defaults = list.filter((x: { isDefault: boolean }) => x.isDefault);
    expect(defaults).toHaveLength(1);
    expect(defaults[0].id).toBe(second.id);
  });

  it('DELETE soft-deletes own; gone from list and GET :id → 404', async () => {
    const a = await makeCustomerToken();
    const addr = (await app.inject({ method: 'POST', url: '/me/addresses', headers: auth(a), payload: base })).json();
    expect((await app.inject({ method: 'DELETE', url: `/me/addresses/${addr.id}`, headers: auth(a) })).statusCode).toBe(204);
    expect((await app.inject({ method: 'GET', url: '/me/addresses', headers: auth(a) })).json()).toHaveLength(0);
    expect((await app.inject({ method: 'GET', url: `/me/addresses/${addr.id}`, headers: auth(a) })).statusCode).toBe(404);
  });

  it('DELETE another customer address → 404', async () => {
    const a = await makeCustomerToken();
    const addr = (await app.inject({ method: 'POST', url: '/me/addresses', headers: auth(a), payload: base })).json();
    const b = await makeCustomerToken();
    expect((await app.inject({ method: 'DELETE', url: `/me/addresses/${addr.id}`, headers: auth(b) })).statusCode).toBe(404);
  });

  it('no address CRUD writes any AuditLog row (decision 8)', async () => {
    await seedZoneWithPincode('Vadodara', 14900, '390001');
    const a = await makeCustomerToken();
    const addr = (await app.inject({ method: 'POST', url: '/me/addresses', headers: auth(a), payload: base })).json();
    await app.inject({ method: 'PATCH', url: `/me/addresses/${addr.id}`, headers: auth(a), payload: { label: 'X' } });
    await app.inject({ method: 'DELETE', url: `/me/addresses/${addr.id}`, headers: auth(a) });
    expect(await prisma.auditLog.count()).toBe(0);
  });
});
