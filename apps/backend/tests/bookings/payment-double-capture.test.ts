import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, seedBookable } from './helpers.js';
import { paymentGateway, DevPaymentGateway } from '../../src/shared/third-party/razorpay.js';

// Separate file DELIBERATELY: payment.test.ts is at its inject budget against the process rate
// limiter; this file's app instance gets a fresh window. The fixture direct-seeds the payable
// state (the full keystone chain is proven in payment.test.ts) — this file targets ONLY the
// double-capture webhook sequence.

const gw = paymentGateway as DevPaymentGateway;
const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
function future() { return new Date(Date.now() + 86_400_000).toISOString(); }

function capturedEvent(orderId: string, amountPaise: number) {
  return JSON.stringify({
    event: 'payment.captured',
    payload: { payment: { entity: { id: `pay_dev_${Math.random().toString(36).slice(2, 10)}`, order_id: orderId, amount: amountPaise, status: 'captured' } } },
  });
}
function failedEvent(orderId: string) {
  return JSON.stringify({
    event: 'payment.failed',
    payload: { payment: { entity: { id: `pay_dev_${Math.random().toString(36).slice(2, 10)}`, order_id: orderId, amount: 0, error_description: 'UPI declined' } } },
  });
}
async function postWebhook(body: string) {
  return app.inject({ method: 'POST', url: '/webhooks/razorpay', headers: { 'content-type': 'application/json', 'x-razorpay-signature': gw.signPayload(body) }, payload: body });
}

describe('double-capture (customer paid two orders)', () => {
  it('the late capture 200-ACKs, records CAPTURED honestly, flags duplicate_capture for a B7 refund — exactly ONE transition', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
    // Direct-seed the payable state — the keystone chain is proven elsewhere.
    await prisma.booking.update({ where: { id: booking.id }, data: { state: 'CUSTOMER_CONFIRMED' } });

    const first = (await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/pay`, headers: auth(c.token) })).json();
    expect((await postWebhook(failedEvent(first.orderId))).statusCode).toBe(200); // order A fails gateway-side
    const second = (await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/pay`, headers: auth(c.token) })).json();
    expect(second.orderId).not.toBe(first.orderId);
    expect((await postWebhook(capturedEvent(second.orderId, second.amountPaise))).statusCode).toBe(200); // B captures → PAYMENT_RECEIVED

    // ...then A's capture arrives late (the customer ALSO paid the old checkout — money moved twice)
    const late = await postWebhook(capturedEvent(first.orderId, first.amountPaise));
    expect(late.statusCode).toBe(200); // always-ACK — never a gateway retry storm

    const rows = await prisma.payment.findMany({ where: { bookingId: booking.id }, orderBy: { createdAt: 'asc' } });
    expect(rows.map((r) => r.status)).toEqual(['CAPTURED', 'CAPTURED']); // both recorded honestly
    // exactly ONE state transition, and the double charge is flagged for ops (the B7 refund signal)
    expect(await prisma.auditLog.count({ where: { action: 'BOOKING_STATE_CHANGED', metadata: { path: ['to'], equals: 'PAYMENT_RECEIVED' } } })).toBe(1);
    const flag = await prisma.auditLog.findFirst({ where: { action: 'PAYMENT_EVENT', metadata: { path: ['event'], equals: 'duplicate_capture' } } });
    expect((flag!.metadata as { bookingId: string }).bookingId).toBe(booking.id);
    expect((await prisma.booking.findUnique({ where: { id: booking.id } }))!.state).toBe('PAYMENT_RECEIVED');
  });
});
