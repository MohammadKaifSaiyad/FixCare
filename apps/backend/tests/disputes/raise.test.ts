import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, makeTechnician, seedBookable } from '../bookings/helpers.js';
import { settleClosableBookings } from '../../src/modules/settlements/settlements.service.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
function future() { return new Date(Date.now() + 86_400_000).toISOString(); }

/** Direct-seed a PAYMENT_RECEIVED booking (paid `paidAgoMs` ago, default 1h) with a captured UPI payment. */
async function paid(opts?: { paidAgoMs?: number }) {
  const c = await makeCustomer();
  const f = await seedBookable(c.customerId);
  const t = await makeTechnician(['AC']);
  const b = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
  await prisma.booking.update({ where: { id: b.id }, data: { state: 'PAYMENT_RECEIVED', technicianId: t.technicianId, paidAt: new Date(Date.now() - (opts?.paidAgoMs ?? 3600_000)) } });
  await prisma.payment.create({ data: { bookingId: b.id, method: 'UPI', status: 'CAPTURED', amountPaise: 45100, capturedAt: new Date(), razorpayOrderId: `order_dev_${Math.random().toString(36).slice(2, 8)}`, razorpayPaymentId: `pay_dev_${Math.random().toString(36).slice(2, 8)}` } });
  return { c, t, bookingId: b.id as string };
}

describe('POST /me/bookings/:id/raise-dispute', () => {
  it('raises: booking → DISPUTED + Dispute OPEN + audit; the sweep then SKIPS it (payout held)', async () => {
    const { c, bookingId } = await paid(); // paid 1h ago — inside the 48h raise window
    const res = await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/raise-dispute`, headers: auth(c.token), payload: { reason: 'AC still not cooling' } });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ id: bookingId, state: 'DISPUTED' });
    expect((await prisma.booking.findUnique({ where: { id: bookingId } }))!.state).toBe('DISPUTED');
    const d = await prisma.dispute.findFirst({ where: { bookingId } });
    expect(d).toMatchObject({ status: 'OPEN', reason: 'AC still not cooling' });
    expect(await prisma.auditLog.count({ where: { action: 'DISPUTE_EVENT', metadata: { path: ['event'], equals: 'raised' } } })).toBe(1);
    // Age paidAt past 48h so the sweep WOULD close it — but DISPUTED (not the window) holds it:
    // the sweep only selects state=PAYMENT_RECEIVED, so a DISPUTED booking is skipped, payout held.
    await prisma.booking.update({ where: { id: bookingId }, data: { paidAt: new Date(Date.now() - 49 * 3600_000) } });
    const r = await settleClosableBookings();
    expect(r.closed).toBe(0);
    expect((await prisma.booking.findUnique({ where: { id: bookingId } }))!.state).toBe('DISPUTED');
    expect(await prisma.ledgerEntry.count({ where: { bookingId } })).toBe(0); // no earning credited
  });

  it('window boundary: within 48h raises; past 48h → 409', async () => {
    const inWindow = await paid({ paidAgoMs: 47 * 3600_000 });
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${inWindow.bookingId}/raise-dispute`, headers: auth(inWindow.c.token), payload: { reason: 'x' } })).statusCode).toBe(200);
    const past = await paid({ paidAgoMs: 49 * 3600_000 });
    // simulate the sweep already closed it OR just past window — here past-window on a still-PAYMENT_RECEIVED row
    await prisma.booking.update({ where: { id: past.bookingId }, data: { paidAt: new Date(Date.now() - 49 * 3600_000) } });
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${past.bookingId}/raise-dispute`, headers: auth(past.c.token), payload: { reason: 'x' } })).statusCode).toBe(409);
  });

  it('guards: double-raise 409 (unique), non-owner 404, technician role 403, wrong state (CLOSED) 409, bad body 400', async () => {
    const { c, t, bookingId } = await paid();
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/raise-dispute`, headers: auth(c.token), payload: { reason: 'first' } })).statusCode).toBe(200);
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/raise-dispute`, headers: auth(c.token), payload: { reason: 'again' } })).statusCode).toBe(409);
    const other = await makeCustomer();
    const fresh = await paid();
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${fresh.bookingId}/raise-dispute`, headers: auth(other.token), payload: { reason: 'x' } })).statusCode).toBe(404);
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${fresh.bookingId}/raise-dispute`, headers: auth(t.token), payload: { reason: 'x' } })).statusCode).toBe(403);
    await prisma.booking.update({ where: { id: fresh.bookingId }, data: { state: 'CLOSED' } });
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${fresh.bookingId}/raise-dispute`, headers: auth(fresh.c.token), payload: { reason: 'x' } })).statusCode).toBe(409);
    const ok = await paid();
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${ok.bookingId}/raise-dispute`, headers: auth(ok.c.token), payload: { reason: '' } })).statusCode).toBe(400);
  });
});
