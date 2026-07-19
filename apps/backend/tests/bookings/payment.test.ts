import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, makeTechnician, seedBookable, seedIssue, seedDiagnosisPhotos, seedRepairPhotos } from './helpers.js';
import { paymentGateway, DevPaymentGateway } from '../../src/shared/third-party/razorpay.js';

const gw = paymentGateway as DevPaymentGateway;

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
function future() { return new Date(Date.now() + 86_400_000).toISOString(); }

/** Drive a booking through BOTH keystones to CUSTOMER_CONFIRMED. labor 60000, visitFee 14900. */
export async function confirmedBooking() {
  const c = await makeCustomer();
  const f = await seedBookable(c.customerId);
  const t = await makeTechnician(['AC']);
  const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(t.token) });
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/en-route`, headers: auth(t.token) });
  const code = (await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/arrive`, headers: auth(t.token), payload: { lat: 22.31, lng: 73.18 } })).json().arrivalCode;
  await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/confirm-arrival`, headers: auth(c.token), payload: { code } });
  await seedDiagnosisPhotos(booking.id);
  const issue = await seedIssue(f.cat.id);
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id } });
  await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/approve`, headers: auth(c.token) });
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/start-repair`, headers: auth(t.token) });
  await seedRepairPhotos(booking.id);
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/complete-repair`, headers: auth(t.token) });
  const otp = (await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/request-completion-otp`, headers: auth(c.token) })).json().devOtp as string;
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/confirm-completion`, headers: auth(t.token), payload: { code: otp } });
  return { c, t, bookingId: booking.id as string };
}

describe('POST /me/bookings/:id/pay', () => {
  it('creates the order for the approved total (empty cart: labor − visitFee) + Payment row + audit', async () => {
    const { c, bookingId } = await confirmedBooking();
    const res = await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay`, headers: auth(c.token) });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.amountPaise).toBe(45100); // 60000 − 14900, the invariant-locked approved total
    expect(body.orderId).toMatch(/^order_dev_/);
    const rows = await prisma.payment.findMany({ where: { bookingId } });
    expect(rows).toHaveLength(1);
    expect(rows[0]!.status).toBe('CREATED');
    expect(rows[0]!.amountPaise).toBe(45100);
    expect(await prisma.auditLog.count({ where: { action: 'PAYMENT_EVENT' } })).toBe(1);
  });

  it('is idempotent: a second pay returns the SAME order (no duplicate rows)', async () => {
    const { c, bookingId } = await confirmedBooking();
    const first = (await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay`, headers: auth(c.token) })).json();
    const second = (await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay`, headers: auth(c.token) })).json();
    expect(second.orderId).toBe(first.orderId);
    expect(await prisma.payment.count({ where: { bookingId } })).toBe(1);
  });

  it('a DECLINED booking pays exactly the locked visit fee', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const t = await makeTechnician(['AC']);
    const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
    await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(t.token) });
    await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/en-route`, headers: auth(t.token) });
    const code = (await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/arrive`, headers: auth(t.token), payload: { lat: 22.31, lng: 73.18 } })).json().arrivalCode;
    await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/confirm-arrival`, headers: auth(c.token), payload: { code } });
    await seedDiagnosisPhotos(booking.id);
    const issue = await seedIssue(f.cat.id);
    await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id } });
    await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/decline`, headers: auth(c.token) });
    const res = await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/pay`, headers: auth(c.token) });
    expect(res.statusCode).toBe(200);
    expect(res.json().amountPaise).toBe(14900); // visitFeePaise only
  });

  it('guards: wrong state 409, foreign customer 404, technician 403', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/pay`, headers: auth(c.token) })).statusCode).toBe(409);
    const confirmed = await confirmedBooking();
    const other = await makeCustomer();
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${confirmed.bookingId}/pay`, headers: auth(other.token) })).statusCode).toBe(404);
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${confirmed.bookingId}/pay`, headers: auth(confirmed.t.token) })).statusCode).toBe(403);
  });
});

/** Build a Razorpay-shaped payment.captured body for an order. */
function capturedEvent(orderId: string, amountPaise: number, paymentId = `pay_dev_${Math.random().toString(36).slice(2, 10)}`) {
  return JSON.stringify({
    event: 'payment.captured',
    payload: { payment: { entity: { id: paymentId, order_id: orderId, amount: amountPaise, status: 'captured' } } },
  });
}
function failedEvent(orderId: string) {
  return JSON.stringify({
    event: 'payment.failed',
    payload: { payment: { entity: { id: `pay_dev_${Math.random().toString(36).slice(2, 10)}`, order_id: orderId, amount: 0, error_description: 'UPI declined' } } },
  });
}
async function postWebhook(body: string, signature = gw.signPayload(body)) {
  return app.inject({ method: 'POST', url: '/webhooks/razorpay', headers: { 'content-type': 'application/json', 'x-razorpay-signature': signature }, payload: body });
}

describe('POST /webhooks/razorpay', () => {
  it('valid capture → Payment CAPTURED + PAYMENT_RECEIVED + evidence audit; duplicate delivery is a no-op', async () => {
    const { c, bookingId } = await confirmedBooking();
    const { orderId, amountPaise } = (await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay`, headers: auth(c.token) })).json();
    const body = capturedEvent(orderId, amountPaise);
    expect((await postWebhook(body)).statusCode).toBe(200);
    const row = await prisma.booking.findUnique({ where: { id: bookingId } });
    expect(row!.state).toBe('PAYMENT_RECEIVED');
    const payment = await prisma.payment.findFirst({ where: { bookingId } });
    expect(payment!.status).toBe('CAPTURED');
    expect(payment!.razorpayPaymentId).not.toBeNull();
    expect(payment!.capturedAt).not.toBeNull();
    const audit = await prisma.auditLog.findFirst({ where: { action: 'BOOKING_STATE_CHANGED', metadata: { path: ['to'], equals: 'PAYMENT_RECEIVED' } } });
    expect((audit!.metadata as { amountPaise: number }).amountPaise).toBe(amountPaise);
    // duplicate delivery: still 200, still exactly ONE transition
    expect((await postWebhook(body)).statusCode).toBe(200);
    expect(await prisma.auditLog.count({ where: { action: 'BOOKING_STATE_CHANGED', metadata: { path: ['to'], equals: 'PAYMENT_RECEIVED' } } })).toBe(1);
  });

  it('bad signature → 401 and NOTHING changes', async () => {
    const { c, bookingId } = await confirmedBooking();
    const { orderId, amountPaise } = (await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay`, headers: auth(c.token) })).json();
    expect((await postWebhook(capturedEvent(orderId, amountPaise), 'deadbeef')).statusCode).toBe(401);
    expect((await prisma.booking.findUnique({ where: { id: bookingId } }))!.state).toBe('CUSTOMER_CONFIRMED');
  });

  it('amount mismatch → flagged audit, NO transition, 200 (gateway stops retrying; ops investigates)', async () => {
    const { c, bookingId } = await confirmedBooking();
    const { orderId } = (await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay`, headers: auth(c.token) })).json();
    expect((await postWebhook(capturedEvent(orderId, 1))).statusCode).toBe(200); // tampered/partial amount
    expect((await prisma.booking.findUnique({ where: { id: bookingId } }))!.state).toBe('CUSTOMER_CONFIRMED');
    const flagged = await prisma.auditLog.findFirst({ where: { action: 'PAYMENT_EVENT', metadata: { path: ['event'], equals: 'amount_mismatch' } } });
    expect(flagged).not.toBeNull();
  });

  it('payment.failed → FAILED with reason; a re-pay issues a NEW order; unknown events → 200 ignored', async () => {
    const { c, bookingId } = await confirmedBooking();
    const first = (await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay`, headers: auth(c.token) })).json();
    expect((await postWebhook(failedEvent(first.orderId))).statusCode).toBe(200);
    const failed = await prisma.payment.findFirst({ where: { razorpayOrderId: first.orderId } });
    expect(failed!.status).toBe('FAILED');
    expect(failed!.failureReason).toBe('UPI declined');
    const second = (await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay`, headers: auth(c.token) })).json();
    expect(second.orderId).not.toBe(first.orderId);
    expect(await prisma.payment.count({ where: { bookingId } })).toBe(2);
    expect((await postWebhook(JSON.stringify({ event: 'refund.processed', payload: {} }))).statusCode).toBe(200);
  });
});

describe('payment in the customer DTO', () => {
  it('GET /me/bookings/:id shows the latest attempt (no gateway ids leaked)', async () => {
    // Direct-seeded state (sanctioned fixture pattern): the full pay→webhook flow is already
    // covered above — this test targets ONLY the DTO mapping, and the file's inject budget is
    // tight against the process rate limiter.
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
    await prisma.booking.update({ where: { id: booking.id }, data: { state: 'PAYMENT_RECEIVED' } });
    await prisma.payment.create({ data: { bookingId: booking.id, method: 'UPI', status: 'CAPTURED', amountPaise: 45100, razorpayOrderId: `order_dev_dto_${Math.random().toString(36).slice(2, 8)}`, razorpayPaymentId: `pay_dev_dto_${Math.random().toString(36).slice(2, 8)}`, capturedAt: new Date() } });
    const got = (await app.inject({ method: 'GET', url: `/me/bookings/${booking.id}`, headers: auth(c.token) })).json();
    expect(got.state).toBe('PAYMENT_RECEIVED');
    expect(got.payment).toEqual({ status: 'CAPTURED', method: 'UPI', amountPaise: 45100 });
    expect(JSON.stringify(got.payment)).not.toContain('order_');
    expect(JSON.stringify(got.payment)).not.toContain('pay_dev');
  });
});
