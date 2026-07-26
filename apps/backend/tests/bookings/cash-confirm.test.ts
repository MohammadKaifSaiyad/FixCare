import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, makeTechnician, seedBookable } from './helpers.js';

// Own file = own rate-limit window. Payable states direct-seeded (chain proven in payment.test.ts).

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
function future() { return new Date(Date.now() + 86_400_000).toISOString(); }

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

async function initiate(token: string, bookingId: string) {
  const res = await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay-cash`, headers: auth(token) });
  expect(res.statusCode).toBe(200);
  return res.json() as { amountPaise: number; devOtp: string };
}
function wrongCode(devOtp: string) { return devOtp === '000000' ? '000001' : '000000'; }

describe('POST /technician/jobs/:id/confirm-cash', () => {
  it('captures the cash: Payment CAPTURED + debt increment + PAYMENT_RECEIVED (TECHNICIAN actor) + both audits', async () => {
    const { c, t, bookingId } = await cashReady();
    const { devOtp, amountPaise } = await initiate(c.token, bookingId);
    const res = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/confirm-cash`, headers: auth(t.token), payload: { code: devOtp } });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ id: bookingId, state: 'PAYMENT_RECEIVED', cashDebtPaise: amountPaise });
    const payment = await prisma.payment.findFirst({ where: { bookingId } });
    expect(payment!.status).toBe('CAPTURED');
    expect(payment!.capturedAt).not.toBeNull();
    expect((await prisma.technician.findUnique({ where: { id: t.technicianId } }))!.cashDebtPaise).toBe(amountPaise);
    // B6c: the capture also writes a CASH_COLLECTED ledger entry in the SAME tx, so the ledger-derived
    // debt stays in lockstep with the cached column (the reconciliation invariant).
    const collected = await prisma.ledgerEntry.findFirst({ where: { bookingId, type: 'CASH_COLLECTED' } });
    expect(collected!.amountPaise).toBe(amountPaise);
    const transition = await prisma.auditLog.findFirst({ where: { action: 'BOOKING_STATE_CHANGED', metadata: { path: ['to'], equals: 'PAYMENT_RECEIVED' } } });
    expect((transition!.metadata as { method: string }).method).toBe('CASH');
    const received = await prisma.auditLog.findFirst({ where: { action: 'PAYMENT_EVENT', metadata: { path: ['event'], equals: 'cash_received' } } });
    expect((received!.metadata as { amountPaise: number }).amountPaise).toBe(amountPaise);
  });

  it('a DECLINED booking settles its visit fee in cash', async () => {
    const { c, t, bookingId } = await cashReady('DECLINED_BY_CUSTOMER');
    const { devOtp } = await initiate(c.token, bookingId);
    const res = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/confirm-cash`, headers: auth(t.token), payload: { code: devOtp } });
    expect(res.statusCode).toBe(200);
    expect(res.json().cashDebtPaise).toBe(14900);
    expect((await prisma.booking.findUnique({ where: { id: bookingId } }))!.state).toBe('PAYMENT_RECEIVED');
  });

  it('wrong code → 401, nothing changes; the right code still works after', async () => {
    const { c, t, bookingId } = await cashReady();
    const { devOtp } = await initiate(c.token, bookingId);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/confirm-cash`, headers: auth(t.token), payload: { code: wrongCode(devOtp) } })).statusCode).toBe(401);
    expect((await prisma.technician.findUnique({ where: { id: t.technicianId } }))!.cashDebtPaise).toBe(0);
    expect((await prisma.booking.findUnique({ where: { id: bookingId } }))!.state).toBe('CUSTOMER_CONFIRMED');
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/confirm-cash`, headers: auth(t.token), payload: { code: devOtp } })).statusCode).toBe(200);
  });

  it('no active code → 409; foreign technician → 403; customer role → 403; bad body → 400', async () => {
    const { c, t, bookingId } = await cashReady();
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/confirm-cash`, headers: auth(t.token), payload: { code: '123456' } })).statusCode).toBe(409);
    await initiate(c.token, bookingId);
    const stranger = await makeTechnician(['AC']);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/confirm-cash`, headers: auth(stranger.token), payload: { code: '123456' } })).statusCode).toBe(403);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/confirm-cash`, headers: auth(c.token), payload: { code: '123456' } })).statusCode).toBe(403);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/confirm-cash`, headers: auth(t.token), payload: { code: '12345' } })).statusCode).toBe(400);
  });

  it('booking already paid (late UPI capture won the race) → 409 and debt is UNCHANGED', async () => {
    const { c, t, bookingId } = await cashReady();
    const { devOtp } = await initiate(c.token, bookingId);
    await prisma.booking.update({ where: { id: bookingId }, data: { state: 'PAYMENT_RECEIVED' } }); // the UPI webhook landed first
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/confirm-cash`, headers: auth(t.token), payload: { code: devOtp } })).statusCode).toBe(409);
    expect((await prisma.technician.findUnique({ where: { id: t.technicianId } }))!.cashDebtPaise).toBe(0);
    expect((await prisma.payment.findFirst({ where: { bookingId } }))!.status).toBe('CREATED');
  });

  it('in-tx velocity re-check: cash captured AFTER initiation still blocks the capture, debt rolls back', async () => {
    const { c, f, t, bookingId } = await cashReady();
    const { devOtp } = await initiate(c.token, bookingId); // gates pass at initiation (0 collected)
    // Another ₹2700 cash capture lands between initiation and confirmation:
    const b2 = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
    await prisma.booking.update({ where: { id: b2.id }, data: { technicianId: t.technicianId, state: 'PAYMENT_RECEIVED' } });
    await prisma.payment.create({ data: { bookingId: b2.id, method: 'CASH', status: 'CAPTURED', amountPaise: 270000, capturedAt: new Date() } });
    const res = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/confirm-cash`, headers: auth(t.token), payload: { code: devOtp } });
    expect(res.statusCode).toBe(422); // 270000 + 45100 > 300000 — the ENFORCEMENT check, post-lock
    expect((await prisma.technician.findUnique({ where: { id: t.technicianId } }))!.cashDebtPaise).toBe(0); // increment rolled back
    expect((await prisma.payment.findFirst({ where: { bookingId } }))!.status).toBe('CREATED');
    expect((await prisma.booking.findUnique({ where: { id: bookingId } }))!.state).toBe('CUSTOMER_CONFIRMED');
  });
});
