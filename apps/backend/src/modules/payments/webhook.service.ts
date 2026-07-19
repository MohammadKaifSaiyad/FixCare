import { z } from 'zod';
import { prisma } from '../../shared/database/prisma.js';
import { ConflictError, UnauthorizedError } from '../../shared/errors.js';
import { paymentGateway } from '../../shared/third-party/razorpay.js';
import { transitionBooking } from '../bookings/bookings.state.js';

// Zod, not a cast (convention: all route inputs validated): a signed body is still EXTERNAL input.
// amount must be an INTEGER — a float here would silently pass the paise equality check's shape.
// An entity missing order_id must never reach payment.failed's updateMany: Prisma treats an
// undefined filter value as "no filter", which would mass-FAIL every open payment.
const paymentEntitySchema = z.object({
  id: z.string().min(1),
  order_id: z.string().min(1),
  amount: z.number().int().nonnegative(),
  error_description: z.string().optional(),
});

const envelopeSchema = z.object({
  event: z.string().optional(),
  payload: z.object({ payment: z.object({ entity: z.unknown() }).optional() }).optional(),
});

/** Handle one gateway webhook delivery. The SIGNATURE is the authentication (Rule 1: the
 *  gateway's signed word is the evidence money moved) — invalid/missing → 401, no detail.
 *  Every handled outcome returns void (route replies 200) so the gateway stops retrying;
 *  anomalies are FLAGGED in audit for ops instead of erroring into a retry storm. */
export async function handleWebhookEvent(rawBody: string, signature: string | undefined): Promise<void> {
  if (!signature || !paymentGateway.verifyWebhookSignature(rawBody, signature)) {
    throw new UnauthorizedError('Invalid webhook signature');
  }
  let json: unknown;
  try {
    json = JSON.parse(rawBody);
  } catch {
    // A valid signature with malformed JSON can only be a gateway/secret-holder bug — but a 500
    // here would put the gateway into a permanent retry loop. Keep the always-ACK contract:
    // flag it, return (route replies 200), ops investigates.
    await prisma.auditLog.create({ data: { action: 'PAYMENT_EVENT', actorType: 'SYSTEM', metadata: { event: 'malformed_body' } } });
    return;
  }
  const envelope = envelopeSchema.safeParse(json);
  if (!envelope.success) {
    await prisma.auditLog.create({ data: { action: 'PAYMENT_EVENT', actorType: 'SYSTEM', metadata: { event: 'malformed_body' } } });
    return;
  }
  const event = envelope.data.event ?? 'unknown';
  // Entity validated separately from the envelope so an unknown/refund event with a differently
  // shaped payload still lands in the audited 'ignored' path, not malformed_body.
  const entityParsed = paymentEntitySchema.safeParse(envelope.data.payload?.payment?.entity);
  const entity = entityParsed.success ? entityParsed.data : undefined;

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
    try {
      await prisma.$transaction(async (tx) => {
        await tx.payment.update({ where: { id: payment.id }, data: { status: 'CAPTURED', razorpayPaymentId: entity.id, capturedAt: new Date() } });
        // transitionBooking's optimistic lock (updateMany WHERE state) is the DB-level duplicate
        // guard; the status check above catches the sequential duplicate before it.
        await transitionBooking(tx, booking, 'PAYMENT_RECEIVED', { type: 'SYSTEM', kind: 'SYSTEM', id: 'razorpay-webhook' }, { razorpayPaymentId: entity.id, amountPaise: payment.amountPaise, method: 'UPI' });
        // PAYMENT_EVENT rows already cover order_created, payment_failed, and every anomaly —
        // this completes the payment timeline so ops can query one action for the full history.
        await tx.auditLog.create({
          data: { action: 'PAYMENT_EVENT', actorType: 'SYSTEM', metadata: { event: 'captured', bookingId: payment.bookingId, orderId: entity.order_id, razorpayPaymentId: entity.id, amountPaise: payment.amountPaise } },
        });
      });
    } catch (e) {
      if (!(e instanceof ConflictError)) throw e;
      // The booking already transitioned (e.g. the customer paid a SECOND order after the first
      // failed gateway-side, and both captured — real money moved twice). Record this capture
      // honestly and flag it LOUDLY: ops owes a refund (B7). Always-ACK so the gateway stops
      // retrying — a 409 here caused a retry storm with no signal.
      await prisma.$transaction(async (tx) => {
        await tx.payment.update({ where: { id: payment.id }, data: { status: 'CAPTURED', razorpayPaymentId: entity.id, capturedAt: new Date() } });
        await tx.auditLog.create({
          data: { action: 'PAYMENT_EVENT', actorType: 'SYSTEM', metadata: { event: 'duplicate_capture', bookingId: payment.bookingId, razorpayPaymentId: entity.id, amountPaise: payment.amountPaise } },
        });
      });
    }
    return;
  }

  if (event === 'payment.captured') {
    // captured but the entity failed to parse — a capture we couldn't process deserves a
    // distinct flag, not the generic 'ignored'.
    await prisma.auditLog.create({ data: { action: 'PAYMENT_EVENT', actorType: 'SYSTEM', metadata: { event: 'malformed_captured' } } });
    return;
  }

  if (event === 'payment.failed' && entity) {
    await prisma.$transaction(async (tx) => {
      // updateMany keyed on CREATED: a failed event for an already-captured/failed row is a no-op.
      await tx.payment.updateMany({
        where: { razorpayOrderId: entity.order_id, status: 'CREATED' },
        // gateway-controlled string, assumed non-PII; length-capped so a future gateway change
        // can never persist runaway/user-supplied text (Rule 7 posture)
        data: { status: 'FAILED', failureReason: (entity.error_description ?? 'payment failed').slice(0, 200) },
      });
      await tx.auditLog.create({ data: { action: 'PAYMENT_EVENT', actorType: 'SYSTEM', metadata: { event: 'payment_failed', orderId: entity.order_id } } });
    });
    return;
  }

  // Unknown / refund.* (B7 skeleton): acknowledge + audit, take no action.
  await prisma.auditLog.create({ data: { action: 'PAYMENT_EVENT', actorType: 'SYSTEM', metadata: { event: 'ignored', type: event } } });
}
