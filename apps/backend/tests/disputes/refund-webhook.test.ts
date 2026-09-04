import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, makeTechnician, seedBookable } from '../bookings/helpers.js';
import { paymentGateway, DevPaymentGateway } from '../../src/shared/third-party/razorpay.js';

const gw = paymentGateway as DevPaymentGateway;

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });

/** Direct-seed a DISPUTED booking (with a captured UPI payment) for webhook-only tests. */
async function disputedWithPayment() {
  const c = await makeCustomer();
  const f = await seedBookable(c.customerId);
  const t = await makeTechnician(['AC']);
  const b = await prisma.booking.create({
    data: {
      customerId: c.customerId,
      bookingNumber: `FC-RFND-${Date.now()}`,
      state: 'DISPUTED',
      scheduledSlot: new Date(),
      serviceId: f.service.id,
      serviceName: f.service.name,
      zoneId: f.zone.id,
      zoneName: f.zoneName,
      addressId: f.address.id,
      laborPaise: f.laborPaise,
      visitFeePaise: f.visitFeePaise,
      laborTier: 'T2',
      technicianId: t.technicianId,
      paidAt: new Date(),
    },
  });
  const razorpayPaymentId = `pay_dev_rfnd_${Math.random().toString(36).slice(2, 10)}`;
  const payment = await prisma.payment.create({
    data: {
      bookingId: b.id,
      method: 'UPI',
      status: 'CAPTURED',
      amountPaise: 45100,
      capturedAt: new Date(),
      razorpayOrderId: `order_dev_rfnd_${Math.random().toString(36).slice(2, 8)}`,
      razorpayPaymentId,
    },
  });
  await prisma.dispute.create({
    data: { bookingId: b.id, raisedByUserId: c.userId, reason: 'AC not cooling', status: 'OPEN' },
  });
  return { c, t, bookingId: b.id as string, payment, razorpayPaymentId };
}

function refundProcessedEvent(razorpayPaymentId: string, amountPaise: number, refundId: string) {
  return JSON.stringify({
    event: 'refund.processed',
    payload: {
      refund: {
        entity: {
          id: refundId,
          payment_id: razorpayPaymentId,
          amount: amountPaise,
        },
      },
    },
  });
}

function refundFailedEvent(razorpayPaymentId: string, refundId: string) {
  return JSON.stringify({
    event: 'refund.failed',
    payload: {
      refund: {
        entity: {
          id: refundId,
          payment_id: razorpayPaymentId,
          amount: 45100,
        },
      },
    },
  });
}

async function postWebhook(body: string, signature = gw.signPayload(body)) {
  return app.inject({
    method: 'POST',
    url: '/webhooks/razorpay',
    headers: { 'content-type': 'application/json', 'x-razorpay-signature': signature },
    payload: body,
  });
}

describe('POST /webhooks/razorpay — refund.processed', () => {
  it('sets razorpayRefundId + writes a refund_confirmed DISPUTE_EVENT audit; no ledger entry', async () => {
    const { bookingId, payment, razorpayPaymentId } = await disputedWithPayment();
    const refundId = `rfnd_dev_${Math.random().toString(36).slice(2, 14)}`;
    const body = refundProcessedEvent(razorpayPaymentId, 45100, refundId);

    const res = await postWebhook(body);
    expect(res.statusCode).toBe(200);

    // Payment must have the refundId recorded
    const updatedPayment = await prisma.payment.findUnique({ where: { id: payment.id } });
    expect(updatedPayment!.razorpayRefundId).toBe(refundId);

    // Must have a DISPUTE_EVENT audit with event='refund_confirmed'
    const audit = await prisma.auditLog.findFirst({
      where: { action: 'DISPUTE_EVENT', metadata: { path: ['event'], equals: 'refund_confirmed' } },
    });
    expect(audit).not.toBeNull();
    const meta = audit!.metadata as { event: string; bookingId: string; refundId: string; amountPaise: number };
    expect(meta.bookingId).toBe(bookingId);
    expect(meta.refundId).toBe(refundId);
    expect(meta.amountPaise).toBe(45100);

    // CRITICAL: this webhook must NOT write any ledger entry (resolution does that)
    expect(await prisma.ledgerEntry.count({ where: { bookingId } })).toBe(0);
  });

  it('redelivery is a no-op (idempotent on razorpayRefundId)', async () => {
    const { payment, razorpayPaymentId } = await disputedWithPayment();
    const refundId = `rfnd_dev_${Math.random().toString(36).slice(2, 14)}`;
    const body = refundProcessedEvent(razorpayPaymentId, 45100, refundId);

    await postWebhook(body);
    // Second delivery: same body, same signature
    const res2 = await postWebhook(body);
    expect(res2.statusCode).toBe(200);

    // Still only one refundId set (not null/overwritten)
    const updatedPayment = await prisma.payment.findUnique({ where: { id: payment.id } });
    expect(updatedPayment!.razorpayRefundId).toBe(refundId);

    // Only one refund_confirmed audit (no duplicate)
    expect(
      await prisma.auditLog.count({
        where: { action: 'DISPUTE_EVENT', metadata: { path: ['event'], equals: 'refund_confirmed' } },
      }),
    ).toBe(1);

    // No ledger entries from either delivery
    expect(await prisma.ledgerEntry.count()).toBe(0);
  });

  it('unknown payment_id → always-ACK 200 + unknown_refund audit; no crash', async () => {
    const body = refundProcessedEvent('pay_nonexistent_xyz', 45100, `rfnd_dev_${Math.random().toString(36).slice(2, 14)}`);
    const res = await postWebhook(body);
    expect(res.statusCode).toBe(200);

    const audit = await prisma.auditLog.findFirst({
      where: { action: 'DISPUTE_EVENT', metadata: { path: ['event'], equals: 'unknown_refund' } },
    });
    expect(audit).not.toBeNull();
  });
});

describe('POST /webhooks/razorpay — refund.failed', () => {
  it('writes refund_failed DISPUTE_EVENT audit; no razorpayRefundId set, no ledger entry', async () => {
    const { bookingId, payment, razorpayPaymentId } = await disputedWithPayment();
    const refundId = `rfnd_dev_failed_${Math.random().toString(36).slice(2, 14)}`;
    const body = refundFailedEvent(razorpayPaymentId, refundId);

    const res = await postWebhook(body);
    expect(res.statusCode).toBe(200);

    // razorpayRefundId must NOT be set for a failed refund
    const updatedPayment = await prisma.payment.findUnique({ where: { id: payment.id } });
    expect(updatedPayment!.razorpayRefundId).toBeNull();

    // Must have a DISPUTE_EVENT audit with event='refund_failed'
    const audit = await prisma.auditLog.findFirst({
      where: { action: 'DISPUTE_EVENT', metadata: { path: ['event'], equals: 'refund_failed' } },
    });
    expect(audit).not.toBeNull();
    const meta = audit!.metadata as { event: string; bookingId: string; refundId: string };
    expect(meta.bookingId).toBe(bookingId);
    expect(meta.refundId).toBe(refundId);

    // No ledger entries
    expect(await prisma.ledgerEntry.count({ where: { bookingId } })).toBe(0);
  });
});
