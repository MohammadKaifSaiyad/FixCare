import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, makeTechnician, seedBookable } from './helpers.js';

// Own file = own rate-limit window (module convention). Covers the design's "wrong OTP ×cap →
// locked" promise for the CASH receipt code; the mechanism is shared otp-store code, so this
// pins the cash-side FOLD (exhausted → 401, then no-code → 409) rather than re-proving the store.

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
function future() { return new Date(Date.now() + 86_400_000).toISOString(); }

describe('cash receipt OTP exhaustion', () => {
  it('5 wrong codes lock the code (401 even for the RIGHT one), then 409 no-code; re-initiation recovers', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const t = await makeTechnician(['AC']);
    const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
    await prisma.booking.update({ where: { id: booking.id }, data: { state: 'CUSTOMER_CONFIRMED', technicianId: t.technicianId } });

    const { devOtp } = (await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/pay-cash`, headers: auth(c.token) })).json();
    const wrong = devOtp === '000000' ? '000001' : '000000';
    for (let i = 0; i < 5; i++) {
      expect((await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/confirm-cash`, headers: auth(t.token), payload: { code: wrong } })).statusCode).toBe(401);
    }
    // Attempt cap hit: the store deletes the code — even the REAL code is now rejected (probed
    // 5× is an auth signal, 401), and the try after that finds no code at all (409).
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/confirm-cash`, headers: auth(t.token), payload: { code: devOtp } })).statusCode).toBe(401);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/confirm-cash`, headers: auth(t.token), payload: { code: devOtp } })).statusCode).toBe(409);
    expect((await prisma.technician.findUnique({ where: { id: t.technicianId } }))!.cashDebtPaise).toBe(0);

    // Recovery: the customer re-initiates (reuses the attempt, fresh code) and the capture works.
    const second = (await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/pay-cash`, headers: auth(c.token) })).json();
    const res = await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/confirm-cash`, headers: auth(t.token), payload: { code: second.devOtp } });
    expect(res.statusCode).toBe(200);
    expect(res.json().cashDebtPaise).toBe(second.amountPaise);
  });
});
