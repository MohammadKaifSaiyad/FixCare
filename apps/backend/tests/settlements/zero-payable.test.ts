import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, makeTechnician, seedBookable, seedRepairPhotos } from '../bookings/helpers.js';
import { mintCompletionCode } from '../../src/modules/bookings/completion-code.js';
import { settleClosableBookings } from '../../src/modules/settlements/settlements.service.js';
import { config } from '../../src/shared/config.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
function future() { return new Date(Date.now() + 86_400_000).toISOString(); }

describe('zero-payable auto-settlement at completion', () => {
  it('confirm-completion chains to PAYMENT_RECEIVED with paidAt when the credit covers everything; sweep later credits the earning', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId, { laborPaise: 10000, visitFeePaise: 14900 }); // credit ≥ labor, empty cart → payable 0
    const t = await makeTechnician(['AC']);
    const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
    await prisma.booking.update({ where: { id: booking.id }, data: { state: 'REPAIR_COMPLETE', technicianId: t.technicianId } });
    await seedRepairPhotos(booking.id);
    const mint = await mintCompletionCode(booking.id);
    if (mint.status !== 'ok') throw new Error('mint throttled');
    const res = await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/confirm-completion`, headers: auth(t.token), payload: { code: mint.code } });
    expect(res.statusCode).toBe(200);
    expect(res.json().state).toBe('PAYMENT_RECEIVED');
    const b = await prisma.booking.findUnique({ where: { id: booking.id } });
    expect(b!.state).toBe('PAYMENT_RECEIVED');
    expect(b!.paidAt).not.toBeNull();
    // the pay endpoints agree nothing is owed
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/pay`, headers: auth(c.token) })).statusCode).toBe(409);
    // sweep (48h later) closes and still credits the earning — the technician did the work
    await prisma.booking.update({ where: { id: booking.id }, data: { paidAt: new Date(Date.now() - 49 * 3600_000) } });
    await settleClosableBookings();
    const earning = await prisma.ledgerEntry.findFirst({ where: { bookingId: booking.id, type: 'EARNING_CREDIT' } });
    expect(earning!.amountPaise).toBe(8000); // floor(10000 × 0.8)
  });

  it('a payable booking still stops at CUSTOMER_CONFIRMED (no chain)', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId); // labor 60000 > credit
    const t = await makeTechnician(['AC']);
    const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
    await prisma.booking.update({ where: { id: booking.id }, data: { state: 'REPAIR_COMPLETE', technicianId: t.technicianId } });
    await seedRepairPhotos(booking.id);
    const mint = await mintCompletionCode(booking.id);
    if (mint.status !== 'ok') throw new Error('mint throttled');
    const res = await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/confirm-completion`, headers: auth(t.token), payload: { code: mint.code } });
    expect(res.json().state).toBe('CUSTOMER_CONFIRMED');
    expect((await prisma.booking.findUnique({ where: { id: booking.id } }))!.paidAt).toBeNull();
  });
});

describe('accept-gate at the debt limit', () => {
  it('a technician AT the limit cannot accept (422); an offset below the limit unlocks accepting', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const t = await makeTechnician(['AC']);
    await prisma.technician.update({ where: { id: t.technicianId }, data: { cashDebtPaise: config.CASH_DEBT_LIMIT_PAISE } });
    const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(t.token) })).statusCode).toBe(422);
    await prisma.technician.update({ where: { id: t.technicianId }, data: { cashDebtPaise: config.CASH_DEBT_LIMIT_PAISE - 1 } });
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(t.token) })).statusCode).toBe(200);
  });
});
