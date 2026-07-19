import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, makeTechnician, seedBookable } from './helpers.js';

// Own file = own rate-limit window (module convention). Payable states are direct-seeded — the
// keystone chain is proven in payment.test.ts; these tests target ONLY the cash initiation.

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
function future() { return new Date(Date.now() + 86_400_000).toISOString(); }

/** Direct-seed a cash-payable booking WITH an assigned technician (cash gates need one). */
async function cashReady(state: 'CUSTOMER_CONFIRMED' | 'DECLINED_BY_CUSTOMER' = 'CUSTOMER_CONFIRMED') {
  const c = await makeCustomer();
  const f = await seedBookable(c.customerId);
  const t = await makeTechnician(['AC']);
  const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
  await prisma.booking.update({
    where: { id: booking.id },
    data: { state, technicianId: t.technicianId, ...(state === 'DECLINED_BY_CUSTOMER' ? { declinedAt: new Date() } : {}) },
  });
  return { c, f, t, bookingId: booking.id as string };
}

/** Seed an already-CAPTURED cash payment for this technician (velocity-window fixture). */
async function seedCapturedCash(c: Awaited<ReturnType<typeof makeCustomer>>, f: Awaited<ReturnType<typeof seedBookable>>, technicianId: string, amountPaise: number, capturedAt: Date) {
  const b = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
  await prisma.booking.update({ where: { id: b.id }, data: { technicianId, state: 'PAYMENT_RECEIVED' } });
  await prisma.payment.create({ data: { bookingId: b.id, method: 'CASH', status: 'CAPTURED', amountPaise, capturedAt } });
}

describe('POST /me/bookings/:id/pay-cash', () => {
  it('mints the receipt OTP for the approved total + CASH attempt row + cash_initiated audit', async () => {
    const { c, bookingId } = await cashReady();
    const res = await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay-cash`, headers: auth(c.token) });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.amountPaise).toBe(45100); // 60000 − 14900, the invariant-locked approved total
    expect(body.devOtp).toMatch(/^\d{6}$/);
    const rows = await prisma.payment.findMany({ where: { bookingId } });
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ method: 'CASH', status: 'CREATED', amountPaise: 45100, razorpayOrderId: null });
    const audit = await prisma.auditLog.findFirst({ where: { action: 'PAYMENT_EVENT', metadata: { path: ['event'], equals: 'cash_initiated' } } });
    expect((audit!.metadata as { amountPaise: number }).amountPaise).toBe(45100);
  });

  it('a DECLINED booking initiates cash for exactly the locked visit fee', async () => {
    const { c, bookingId } = await cashReady('DECLINED_BY_CUSTOMER');
    const res = await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay-cash`, headers: auth(c.token) });
    expect(res.statusCode).toBe(200);
    expect(res.json().amountPaise).toBe(14900);
  });

  it('is idempotent on the attempt row: re-initiation re-mints the code but never duplicates the Payment', async () => {
    const { c, bookingId } = await cashReady();
    const first = (await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay-cash`, headers: auth(c.token) })).json();
    const second = (await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay-cash`, headers: auth(c.token) })).json();
    expect(second.devOtp).not.toBe(first.devOtp); // re-mint replaces the code (single active OTP)
    expect(await prisma.payment.count({ where: { bookingId } })).toBe(1);
  });

  it('throttles the mint: 4th request inside the window → 429', async () => {
    const { c, bookingId } = await cashReady();
    for (let i = 0; i < 3; i++) {
      expect((await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay-cash`, headers: auth(c.token) })).statusCode).toBe(200);
    }
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay-cash`, headers: auth(c.token) })).statusCode).toBe(429);
  });

  it('debt gate: 422 when debt + amount exceeds the ₹500 limit; exactly AT the limit passes', async () => {
    const { c, t, bookingId } = await cashReady();
    await prisma.technician.update({ where: { id: t.technicianId }, data: { cashDebtPaise: 20000 } }); // 20000+45100 > 50000
    const res = await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay-cash`, headers: auth(c.token) });
    expect(res.statusCode).toBe(422);
    expect(await prisma.payment.count({ where: { bookingId } })).toBe(0); // gate precedes the row
    await prisma.technician.update({ where: { id: t.technicianId }, data: { cashDebtPaise: 4900 } }); // 4900+45100 = 50000 exactly
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay-cash`, headers: auth(c.token) })).statusCode).toBe(200);
  });

  it('velocity gate: cash CAPTURED in the trailing 24h counts, older cash does not', async () => {
    const { c, f, t, bookingId } = await cashReady();
    await seedCapturedCash(c, f, t.technicianId, 270000, new Date(Date.now() - 23 * 3600_000)); // inside window: 270000+45100 > 300000
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay-cash`, headers: auth(c.token) })).statusCode).toBe(422);
    await prisma.payment.updateMany({ where: { amountPaise: 270000 }, data: { capturedAt: new Date(Date.now() - 25 * 3600_000) } }); // slide it out of the window
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay-cash`, headers: auth(c.token) })).statusCode).toBe(200);
  });

  it('guards: already-paid 409 (any method), foreign customer 404, technician role 403; /pay (UPI) also 409s on a cash-paid booking', async () => {
    const { c, t, bookingId } = await cashReady();
    const other = await makeCustomer();
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay-cash`, headers: auth(other.token) })).statusCode).toBe(404);
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay-cash`, headers: auth(t.token) })).statusCode).toBe(403);
    await prisma.payment.create({ data: { bookingId, method: 'CASH', status: 'CAPTURED', amountPaise: 45100, capturedAt: new Date() } });
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay-cash`, headers: auth(c.token) })).statusCode).toBe(409);
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay`, headers: auth(c.token) })).statusCode).toBe(409); // "already paid", not "not awaiting payment"
  });
});
