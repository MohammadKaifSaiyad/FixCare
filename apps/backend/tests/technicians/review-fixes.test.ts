import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import type { BookingState, PaymentMethod, PaymentStatus } from '@prisma/client';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeAdminToken, makeCustomer, makeTechnician, seedBookable } from '../bookings/helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
function future() { return new Date(Date.now() + 86_400_000).toISOString(); }
const post = (token: string, url: string, payload?: object) => app.inject({ method: 'POST', url, headers: auth(token), payload });

async function createBooking(state: BookingState, technicianId: string | null, customer: Awaited<ReturnType<typeof makeCustomer>>, f: Awaited<ReturnType<typeof seedBookable>>) {
  const res = await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(customer.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } });
  const booking = res.json() as { id: string };
  await prisma.booking.update({ where: { id: booking.id }, data: { technicianId, state } });
  return booking.id;
}

describe('R1: suspend refused while a cash handover may be in progress', () => {
  async function fixture(method: PaymentMethod, status: PaymentStatus, ageMs: number) {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const t = await makeTechnician(['AC'], 'VERIFIED', [f.zone.id]);
    const bookingId = await createBooking('CUSTOMER_CONFIRMED', t.technicianId, c, f);
    await prisma.payment.create({ data: { bookingId, method, status, amountPaise: 50_000, createdAt: new Date(Date.now() - ageMs) } });
    return t;
  }

  it('fresh CREATED CASH payment → 409 TECHNICIAN_COLLECTING_CASH, status unchanged', async () => {
    const t = await fixture('CASH', 'CREATED', 60_000);
    const res = await post(await makeAdminToken(), `/admin/technicians/${t.technicianId}/suspend`, { reason: 'Test' });
    expect(res.statusCode).toBe(409);
    expect(res.json()).toEqual({ code: 'TECHNICIAN_COLLECTING_CASH', message: 'This technician is collecting a cash payment right now — try again in a few minutes' });
    expect((await prisma.technician.findUniqueOrThrow({ where: { id: t.technicianId } })).status).toBe('VERIFIED');
    expect(await prisma.auditLog.count({ where: { action: 'TECHNICIAN_STATUS_CHANGED' } })).toBe(0);
  });

  it.each([
    ['older than the OTP TTL', 'CASH', 'CREATED', 11 * 60_000],
    ['CAPTURED', 'CASH', 'CAPTURED', 60_000],
    ['FAILED', 'CASH', 'FAILED', 60_000],
    ['UPI', 'UPI', 'CREATED', 60_000],
  ] as const)('allowed when the payment is %s', async (_label, method, status, ageMs) => {
    const t = await fixture(method, status, ageMs);
    const res = await post(await makeAdminToken(), `/admin/technicians/${t.technicianId}/suspend`, { reason: 'Test' });
    expect(res.statusCode).toBe(200);
    expect((await prisma.technician.findUniqueOrThrow({ where: { id: t.technicianId } })).status).toBe('SUSPENDED');
  });
});

describe('R2: a suspended technician cannot accept (suspend/accept serialize on the technician row)', () => {
  it('accept by a SUSPENDED technician → 403 TECHNICIAN_NOT_VERIFIED; booking stays DISPATCHED, unassigned', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const t = await makeTechnician(['AC'], 'VERIFIED', [f.zone.id]);
    const bookingId = await createBooking('DISPATCHED', null, c, f);
    await prisma.technician.update({ where: { id: t.technicianId }, data: { status: 'SUSPENDED' } });
    const res = await post(t.token, `/technician/jobs/${bookingId}/accept`);
    expect(res.statusCode).toBe(403);
    expect(res.json()).toMatchObject({ code: 'TECHNICIAN_NOT_VERIFIED' });
    const b = await prisma.booking.findUniqueOrThrow({ where: { id: bookingId } });
    expect(b.state).toBe('DISPATCHED');
    expect(b.technicianId).toBeNull();
  });

  it('suspend refuses (and rolls the status back) when the technician already holds an accepted job', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const t = await makeTechnician(['AC'], 'VERIFIED', [f.zone.id]);
    const bookingId = await createBooking('DISPATCHED', null, c, f);
    expect((await post(t.token, `/technician/jobs/${bookingId}/accept`)).statusCode).toBe(200);
    const res = await post(await makeAdminToken(), `/admin/technicians/${t.technicianId}/suspend`, { reason: 'Test' });
    expect(res.statusCode).toBe(409);
    expect(res.json()).toMatchObject({ code: 'TECHNICIAN_HAS_ACTIVE_JOB' });
    expect((await prisma.technician.findUniqueOrThrow({ where: { id: t.technicianId } })).status).toBe('VERIFIED');
    expect(await prisma.auditLog.count({ where: { action: 'TECHNICIAN_STATUS_CHANGED' } })).toBe(0);
  });
});

describe('R3: the reason guard ignores separators', () => {
  it.each(['Aadhaar 1234 5678 9012 did not match', 'call 98765 43210', 'call (987) 654-3210', 'call +91 98765.43210'])('%s → 400', async (reason) => {
    const c = await makeTechnician(['AC'], 'KYC_SUBMITTED');
    const res = await post(await makeAdminToken(), `/admin/technicians/${c.technicianId}/send-back`, { reason });
    expect(res.statusCode).toBe(400);
  });

  it('a reason carrying a UPI ID / email (@) → 400 with the guidance message', async () => {
    const c = await makeTechnician(['AC'], 'KYC_SUBMITTED');
    const res = await post(await makeAdminToken(), `/admin/technicians/${c.technicianId}/send-back`, { reason: 'pay me at name@okbank' });
    expect(res.statusCode).toBe(400);
    expect(JSON.stringify(res.json())).toContain("Don't include UPI IDs or email addresses in the reason");
  });

  it.each(['Visit 2 of 3', 'Jobs on 2026-10-02 and 2026-10-05'])('%s → accepted', async (reason) => {
    const c = await makeTechnician(['AC'], 'KYC_SUBMITTED');
    const res = await post(await makeAdminToken(), `/admin/technicians/${c.technicianId}/send-back`, { reason });
    expect(res.statusCode).toBe(200);
  });
});

describe('R6: locked beats an invalid zone', () => {
  it('a KYC_SUBMITTED technician PATCHing an inactive zone → 409 PROFILE_LOCKED (not 422)', async () => {
    const z = await prisma.zone.create({ data: { name: 'Padra', visitFeePaise: 9900 } });
    const inactive = await prisma.zone.create({ data: { name: 'Old', visitFeePaise: 9900, status: 'INACTIVE' } });
    const t = await makeTechnician(['AC'], 'KYC_SUBMITTED', [z.id]);
    const res = await app.inject({ method: 'PATCH', url: '/me/profile', headers: auth(t.token), payload: { zoneIds: [inactive.id] } });
    expect(res.statusCode).toBe(409);
    expect(res.json()).toMatchObject({ code: 'PROFILE_LOCKED' });
  });
});
