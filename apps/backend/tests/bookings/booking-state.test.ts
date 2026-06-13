import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, makeTechnician, seedBookable } from './helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
function future() { return new Date(Date.now() + 86_400_000).toISOString(); }

async function createBooking(token: string, addressId: string, serviceId: string) {
  return (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(token),
    payload: { addressId, serviceId, scheduledSlot: future() } })).json();
}

describe('GET/list + cancel /me/bookings', () => {
  it('list returns only the caller\'s own bookings (newest first)', async () => {
    const a = await makeCustomer();
    const f = await seedBookable(a.customerId);
    await createBooking(a.token, f.address.id, f.service.id);
    const b = await makeCustomer();
    const fb = await seedBookable(b.customerId);
    await createBooking(b.token, fb.address.id, fb.service.id);
    const listA = await app.inject({ method: 'GET', url: '/me/bookings', headers: auth(a.token) });
    expect(listA.statusCode).toBe(200);
    expect(listA.json()).toHaveLength(1);
  });

  it('GET :id of another customer\'s booking → 404 (no IDOR); unknown id → 404', async () => {
    const a = await makeCustomer();
    const f = await seedBookable(a.customerId);
    const booking = await createBooking(a.token, f.address.id, f.service.id);
    const b = await makeCustomer();
    expect((await app.inject({ method: 'GET', url: `/me/bookings/${booking.id}`, headers: auth(b.token) })).statusCode).toBe(404);
    expect((await app.inject({ method: 'GET', url: '/me/bookings/00000000-0000-0000-0000-000000000000', headers: auth(a.token) })).statusCode).toBe(404);
  });

  it('cancel from DISPATCHED → CANCELLED_BY_CUSTOMER + audit', async () => {
    const a = await makeCustomer();
    const f = await seedBookable(a.customerId);
    const booking = await createBooking(a.token, f.address.id, f.service.id);
    const res = await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/cancel`, headers: auth(a.token) });
    expect(res.statusCode).toBe(200);
    expect(res.json().state).toBe('CANCELLED_BY_CUSTOMER');
    const audits = await prisma.auditLog.findMany({ where: { action: 'BOOKING_STATE_CHANGED', metadata: { path: ['bookingId'], equals: booking.id } } });
    expect(audits.length).toBe(3); // null→CREATED + CREATED→DISPATCHED (auto-open) + DISPATCHED→CANCELLED_BY_CUSTOMER
  });

  it('two concurrent cancels: exactly one wins (200), the other is rejected; only one cancel audit', async () => {
    const a = await makeCustomer();
    const f = await seedBookable(a.customerId);
    const booking = await createBooking(a.token, f.address.id, f.service.id);
    const [r1, r2] = await Promise.all([
      app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/cancel`, headers: auth(a.token) }),
      app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/cancel`, headers: auth(a.token) }),
    ]);
    const codes = [r1.statusCode, r2.statusCode].sort();
    expect(codes).toEqual([200, 409]); // optimistic lock: one wins, one loses
    const cancelAudits = await prisma.auditLog.findMany({
      where: { action: 'BOOKING_STATE_CHANGED', metadata: { path: ['to'], equals: 'CANCELLED_BY_CUSTOMER' } },
    });
    expect(cancelAudits.length).toBe(1); // no double-write
  });

  it('cancel a non-CREATED booking → 409 (illegal transition)', async () => {
    const a = await makeCustomer();
    const f = await seedBookable(a.customerId);
    const booking = await createBooking(a.token, f.address.id, f.service.id);
    await prisma.booking.update({ where: { id: booking.id }, data: { state: 'ARRIVED' } });
    const res = await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/cancel`, headers: auth(a.token) });
    expect(res.statusCode).toBe(409);
  });

  it('cancel another customer\'s booking → 404', async () => {
    const a = await makeCustomer();
    const f = await seedBookable(a.customerId);
    const booking = await createBooking(a.token, f.address.id, f.service.id);
    const b = await makeCustomer();
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/cancel`, headers: auth(b.token) })).statusCode).toBe(404);
  });

  it('after a technician accepts, the customer booking detail shows technician name + masked phone', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const booking = await createBooking(c.token, f.address.id, f.service.id);
    const t = await makeTechnician(['AC']);
    await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(t.token) });
    const got = (await app.inject({ method: 'GET', url: `/me/bookings/${booking.id}`, headers: auth(c.token) })).json();
    expect(got.state).toBe('ACCEPTED');
    expect(got.technician.name).toBe('Tech');
    expect(got.technician.maskedPhone).toMatch(/^•+\d{4}$/);
    // directional masking: customer never sees the technician's raw phone
    expect(JSON.stringify(got)).not.toMatch(/9\d{9}/);
  });
});
