import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, seedBookable } from './helpers.js';

// Own file = own rate-limit window (module convention; payment.test.ts is at its inject budget).

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
function future() { return new Date(Date.now() + 86_400_000).toISOString(); }

describe('payment DTO pick across mixed attempts', () => {
  it('a stale CASH CREATED attempt never masks the UPI capture (CAPTURED wins over latest)', async () => {
    // B6b regression: customer opened UPI checkout, then initiated cash (newer row), then the UPI
    // webhook captured. take-1-latest would show the pending CASH attempt on a PAID booking.
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
    await prisma.booking.update({ where: { id: booking.id }, data: { state: 'PAYMENT_RECEIVED' } });
    const older = new Date(Date.now() - 60_000);
    await prisma.payment.create({ data: { bookingId: booking.id, method: 'UPI', status: 'CAPTURED', amountPaise: 45100, razorpayOrderId: `order_dev_mask_${Math.random().toString(36).slice(2, 8)}`, capturedAt: new Date(), createdAt: older } });
    await prisma.payment.create({ data: { bookingId: booking.id, method: 'CASH', status: 'CREATED', amountPaise: 45100 } }); // newer — the stale attempt
    const res = await app.inject({ method: 'GET', url: `/me/bookings/${booking.id}`, headers: auth(c.token) });
    expect(res.statusCode).toBe(200);
    expect(res.json().payment).toEqual({ status: 'CAPTURED', method: 'UPI', amountPaise: 45100 });
  });

  it('with no capture, the latest attempt still shows (unchanged behavior)', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
    const older = new Date(Date.now() - 60_000);
    await prisma.payment.create({ data: { bookingId: booking.id, method: 'UPI', status: 'FAILED', amountPaise: 45100, razorpayOrderId: `order_dev_mask_${Math.random().toString(36).slice(2, 8)}`, createdAt: older } });
    await prisma.payment.create({ data: { bookingId: booking.id, method: 'CASH', status: 'CREATED', amountPaise: 45100 } });
    const got = (await app.inject({ method: 'GET', url: `/me/bookings/${booking.id}`, headers: auth(c.token) })).json();
    expect(got.payment).toEqual({ status: 'CREATED', method: 'CASH', amountPaise: 45100 });
  });
});
