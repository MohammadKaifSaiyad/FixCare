import { prisma } from '../../shared/database/prisma.js';
import { UnauthorizedError } from '../../shared/errors.js';
import { paymentGateway } from '../../shared/third-party/razorpay.js';
import { transitionBooking } from '../bookings/bookings.state.js';

interface RazorpayPaymentEntity {
  id: string;
  order_id: string;
  amount: number;
  error_description?: string;
}

/** Handle one gateway webhook delivery. The SIGNATURE is the authentication (Rule 1: the
 *  gateway's signed word is the evidence money moved) — invalid/missing → 401, no detail.
 *  Every handled outcome returns void (route replies 200) so the gateway stops retrying;
 *  anomalies are FLAGGED in audit for ops instead of erroring into a retry storm. */
export async function handleWebhookEvent(rawBody: string, signature: string | undefined): Promise<void> {
  if (!signature || !paymentGateway.verifyWebhookSignature(rawBody, signature)) {
    throw new UnauthorizedError('Invalid webhook signature');
  }
  const parsed = JSON.parse(rawBody) as { event?: string; payload?: { payment?: { entity?: RazorpayPaymentEntity } } };
  const event = parsed.event ?? 'unknown';
  const entity = parsed.payload?.payment?.entity;

  if (event === 'payment.captured' && entity) {
    const payment = await prisma.payment.findUnique({ where: { razorpayOrderId: entity.order_id } });
    if (!payment) {
      await prisma.auditLog.create({ data: { action: 'PAYMENT_EVENT', actorType: 'SYSTEM', metadata: { event: 'unknown_order', orderId: entity.order_id } } });
      return;
    }
    if (payment.status === 'CAPTURED') return; // duplicate delivery — already handled
    if (entity.amount !== payment.amountPaise) {
      // Tampered/partial capture must NEVER close the booking. Flag loudly, ack quietly.
      await prisma.auditLog.create({
        data: { action: 'PAYMENT_EVENT', actorType: 'SYSTEM', metadata: { event: 'amount_mismatch', bookingId: payment.bookingId, expectedPaise: payment.amountPaise, gotPaise: entity.amount } },
      });
      return;
    }
    const booking = await prisma.booking.findUniqueOrThrow({ where: { id: payment.bookingId } });
    await prisma.$transaction(async (tx) => {
      await tx.payment.update({ where: { id: payment.id }, data: { status: 'CAPTURED', razorpayPaymentId: entity.id, capturedAt: new Date() } });
      // transitionBooking's optimistic lock makes a concurrent duplicate a 409 → rollback; the
      // status guard above catches the sequential duplicate. Either way: exactly one transition.
      await transitionBooking(tx, booking, 'PAYMENT_RECEIVED', { type: 'SYSTEM', kind: 'SYSTEM', id: 'razorpay-webhook' }, { razorpayPaymentId: entity.id, amountPaise: payment.amountPaise, method: 'UPI' });
    });
    return;
  }

  if (event === 'payment.failed' && entity) {
    await prisma.$transaction(async (tx) => {
      // updateMany keyed on CREATED: a failed event for an already-captured/failed row is a no-op.
      await tx.payment.updateMany({
        where: { razorpayOrderId: entity.order_id, status: 'CREATED' },
        data: { status: 'FAILED', failureReason: entity.error_description ?? 'payment failed' },
      });
      await tx.auditLog.create({ data: { action: 'PAYMENT_EVENT', actorType: 'SYSTEM', metadata: { event: 'payment_failed', orderId: entity.order_id } } });
    });
    return;
  }

  // Unknown / refund.* (B7 skeleton): acknowledge + audit, take no action.
  await prisma.auditLog.create({ data: { action: 'PAYMENT_EVENT', actorType: 'SYSTEM', metadata: { event: 'ignored', type: event } } });
}
