import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, seedBookable } from './helpers.js';

// Separate file for a fresh rate-limit window (same reasoning as payment-double-capture.test.ts).
// Direct-seeds the payable state — the keystone chain is proven in payment.test.ts.

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
function future() { return new Date(Date.now() + 86_400_000).toISOString(); }

describe('POST /me/bookings/:id/pay — zero payable', () => {
  it('422s when the visit-fee credit covers the whole job (no 0-amount gateway order, no Payment row)', async () => {
    // Razorpay rejects sub-₹1 orders in production, and a 0-amount Payment row would let a
    // 0-amount capture "pay" the booking with no money moving (Golden Rule 1).
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
    // labor 10000 < visitFee 14900, empty cart → computeEstimate floors the total at 0
    await prisma.booking.update({ where: { id: booking.id }, data: { state: 'CUSTOMER_CONFIRMED', laborPaise: 10000, visitFeePaise: 14900 } });

    const res = await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/pay`, headers: auth(c.token) });
    expect(res.statusCode).toBe(422);
    expect(await prisma.payment.count({ where: { bookingId: booking.id } })).toBe(0);
  });
});
