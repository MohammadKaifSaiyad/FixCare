import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, makeAdminToken, seedBookable } from './helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
function future() { return new Date(Date.now() + 86_400_000).toISOString(); }

describe('POST /me/bookings', () => {
  it('creates a booking with the full price snapshot + CREATED state + audit', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const res = await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token),
      payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } });
    expect(res.statusCode).toBe(201);
    expect(res.json()).toMatchObject({
      state: 'CREATED', visitFeePaise: 14900, laborPaise: 60000, laborTier: 'T2',
      service: { name: 'AC gas refill' }, zone: { name: f.zoneName },
    });
    expect(res.json().bookingNumber).toMatch(/^FC-/);
    const audit = await prisma.auditLog.findFirst({ where: { action: 'BOOKING_STATE_CHANGED' } });
    expect(audit).toBeTruthy();
    expect(audit!.metadata).toMatchObject({ to: 'CREATED' });
  });

  it('SNAPSHOT IS IMMUTABLE: changing catalog price + pincode→zone after creation does not change the booking', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const created = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token),
      payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
    // mutate the live catalog + coverage
    await prisma.servicePrice.updateMany({ where: { serviceId: f.service.id, zoneId: f.zone.id }, data: { laborPaise: 999999 } });
    await prisma.zone.update({ where: { id: f.zone.id }, data: { visitFeePaise: 888888 } });
    await prisma.pincodeZone.updateMany({ where: { pincode: f.pincode }, data: { deletedAt: new Date() } });
    const got = (await app.inject({ method: 'GET', url: `/me/bookings/${created.id}`, headers: auth(c.token) })).json();
    expect(got.visitFeePaise).toBe(14900);    // unchanged
    expect(got.laborPaise).toBe(60000);       // unchanged
    expect(got.zone.name).toBe(f.zoneName);   // unchanged
  });

  it('unserviceable address (no pincode mapping) → 422', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    await prisma.pincodeZone.deleteMany({ where: { pincode: f.pincode } });
    const res = await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token),
      payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } });
    expect(res.statusCode).toBe(422);
  });

  it('serviceable but service unpriced in that zone → 422', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    await prisma.servicePrice.deleteMany({ where: { serviceId: f.service.id, zoneId: f.zone.id } });
    const res = await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token),
      payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } });
    expect(res.statusCode).toBe(422);
  });

  it("another customer's addressId → 404 (no IDOR)", async () => {
    const a = await makeCustomer();
    const f = await seedBookable(a.customerId);
    const b = await makeCustomer();
    const res = await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(b.token),
      payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } });
    expect(res.statusCode).toBe(404);
  });

  it('unknown/soft-deleted service → 404', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    await prisma.service.update({ where: { id: f.service.id }, data: { deletedAt: new Date() } });
    const res = await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token),
      payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } });
    expect(res.statusCode).toBe(404);
  });

  it('past scheduledSlot → 400; non-CUSTOMER → 403; no token → 401', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const pastBody = { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: new Date(Date.now() - 1000).toISOString() };
    expect((await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: pastBody })).statusCode).toBe(400);
    const adm = await makeAdminToken();
    expect((await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(adm),
      payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).statusCode).toBe(403);
    expect((await app.inject({ method: 'POST', url: '/me/bookings',
      payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).statusCode).toBe(401);
  });
});
