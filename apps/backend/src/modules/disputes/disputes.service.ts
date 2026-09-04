import { prisma } from '../../shared/database/prisma.js';
import { config } from '../../shared/config.js';
import { NotFoundError, ConflictError, UnprocessableError } from '../../shared/errors.js';
import { requireCustomer } from '../bookings/bookings.service.js';
import { transitionBooking } from '../bookings/bookings.state.js';
import { splitPaise } from '../settlements/settlements.service.js';
import { paymentGateway } from '../../shared/third-party/razorpay.js';
import type { RaiseDisputeBody, ResolveDisputeBody } from './disputes.schemas.js';

/** Customer raises a dispute on a paid booking within the 48h window → PAYMENT_RECEIVED → DISPUTED.
 *  The B6c sweep only closes PAYMENT_RECEIVED, so a DISPUTED booking's payout is held automatically. */
export async function raiseDispute(userId: string, bookingId: string, body: RaiseDisputeBody): Promise<{ id: string; state: 'DISPUTED' }> {
  const { id: customerId } = await requireCustomer(userId);
  const booking = await prisma.booking.findFirst({ where: { id: bookingId, customerId, deletedAt: null } });
  if (!booking) throw new NotFoundError('Booking not found');
  if (booking.state !== 'PAYMENT_RECEIVED') throw new ConflictError('This booking cannot be disputed');
  if (!booking.paidAt || booking.paidAt.getTime() <= Date.now() - config.DISPUTE_WINDOW_HOURS * 3600_000) {
    throw new ConflictError('The dispute window has passed');
  }
  const open = await prisma.dispute.findFirst({ where: { bookingId, status: 'OPEN' } });
  if (open) throw new ConflictError('A dispute is already open for this booking');
  try {
    await prisma.$transaction(async (tx) => {
      // The partial unique index (bookingId WHERE status=OPEN) is the real race backstop — a
      // concurrent raise throws the unique violation here, mapped to 409 below.
      const dispute = await tx.dispute.create({ data: { bookingId, raisedByUserId: userId, reason: body.reason } });
      await transitionBooking(tx, booking, 'DISPUTED', { type: 'USER', kind: 'CUSTOMER', id: userId }, { disputed: true });
      await tx.auditLog.create({ data: { action: 'DISPUTE_EVENT', actorType: 'USER', actorId: userId, metadata: { event: 'raised', bookingId, disputeId: dispute.id } } });
    });
  } catch (e) {
    // Match ONLY the one-open-per-booking index — a broad /unique/ would misattribute any future
    // unique violation in this tx to "dispute already open".
    if (e instanceof Error && /Dispute_one_open_per_booking/i.test(e.message)) throw new ConflictError('A dispute is already open for this booking');
    throw e;
  }
  return { id: bookingId, state: 'DISPUTED' };
}

/** Admin resolves a dispute: writes ledger entries, optionally calls gateway refund (UPI only),
 *  auto-offsets cash debt, transitions booking to CLOSED, writes DISPUTE_EVENT audit.
 *
 *  SINGLE-REVERSAL CONTRACT: this function writes the ONE DISPUTE_REVERSAL for BOTH UPI and cash.
 *  The refund.processed webhook (Task 3) only confirms the refund by setting razorpayRefundId +
 *  writing a refund_confirmed audit — it never writes a second ledger entry.
 *  Conservation: retained + refund == base (exactly; proven by tests). */
export async function resolveDispute(
  adminUserId: string,
  disputeId: string,
  body: ResolveDisputeBody,
): Promise<{ id: string; state: 'CLOSED'; outcome: string; refundPaise: number }> {
  const dispute = await prisma.dispute.findUnique({ where: { id: disputeId }, include: { booking: true } });
  if (!dispute) throw new NotFoundError('Dispute not found');
  if (dispute.status !== 'OPEN') throw new ConflictError('Dispute is already resolved');

  const booking = dispute.booking;
  const captured = await prisma.payment.findFirst({ where: { bookingId: booking.id, status: 'CAPTURED' } });
  if (!captured) throw new ConflictError('No captured payment for this booking');
  const charge = captured.amountPaise;

  // Validate refund amount against outcome + the real captured charge.
  const refundPaise = body.refundPaise ?? 0;
  if (body.outcome === 'FAVOR_TECHNICIAN' && refundPaise !== 0) {
    throw new UnprocessableError('FAVOR_TECHNICIAN takes no refund');
  }
  if (body.outcome === 'FAVOR_CUSTOMER' && refundPaise !== charge) {
    throw new UnprocessableError('FAVOR_CUSTOMER must refund the full captured charge');
  }
  if (body.outcome === 'PARTIAL' && !(refundPaise >= 1 && refundPaise < charge)) {
    throw new UnprocessableError('PARTIAL refund must be between 1 and the captured charge (exclusive)');
  }

  // Retention keys off the CAPTURED CHARGE (what the customer actually paid), NOT labor — so a
  // full refund (technician at fault) leaves retained 0 and credits the technician nothing, per
  // dispute-resolution.md ("at fault → deduct from payout"). Keying off labor would credit the
  // tech the visit-fee slice even on a full refund, and — with parts, where charge > labor — could
  // drive retained negative. charge already nets the visit-fee credit and includes parts, so
  // retained + refund == charge holds exactly for every outcome.
  const retained = charge - refundPaise; // refund is bounded 0..charge above, so retained is 0..charge
  const { earningPaise, commissionPaise } = splitPaise(retained);

  // CLAIM the dispute atomically BEFORE the gateway call: flip OPEN→RESOLVED conditioned on
  // status='OPEN'. Two concurrent resolves (double-submit, retry, two admins) would otherwise
  // both pass the read-only status check and each fire a REAL, non-transactional gateway refund
  // — the booking's optimistic lock keeps the DB consistent but the money already left twice.
  // count===0 means another resolve won the race → 409, and NO gateway refund fires here.
  const claim = await prisma.dispute.updateMany({
    where: { id: disputeId, status: 'OPEN' },
    data: { status: 'RESOLVED', outcome: body.outcome, refundPaise, resolvedByUserId: adminUserId, resolvedAt: new Date() },
  });
  if (claim.count === 0) throw new ConflictError('Dispute is already resolved');

  // Issue the gateway refund AFTER the claim, BEFORE the ledger tx (mirror B6a's
  // createOrder-before-tx pattern). A gateway failure must not leave a half-closed dispute with
  // ledger side effects committed. Cash → no gateway call; recorded as manually handled.
  let refundId: string | null = null;
  if (refundPaise > 0 && captured.method === 'UPI' && captured.razorpayPaymentId) {
    refundId = (await paymentGateway.refund(captured.razorpayPaymentId, refundPaise)).refundId;
  }

  await prisma.$transaction(async (tx) => {
    // The dispute was already claimed RESOLVED above (the concurrency backstop) — the tx now only
    // books the ledger + closes the booking. If this tx rolls back the dispute stays RESOLVED with
    // no ledger; that fails SAFE (no double payout) and is recoverable by ops, same accepted
    // tradeoff as B6a's orphaned-order-after-gateway-success.

    // Ledger entries: skip zero-amount rows (B6c invariant).
    if (earningPaise > 0) {
      await tx.ledgerEntry.create({
        data: {
          technicianId: booking.technicianId!,
          bookingId: booking.id,
          type: 'EARNING_CREDIT',
          amountPaise: earningPaise,
          metadata: { source: 'dispute_resolution', outcome: body.outcome },
        },
      });
    }
    if (commissionPaise > 0) {
      await tx.ledgerEntry.create({
        data: {
          technicianId: booking.technicianId!,
          bookingId: booking.id,
          type: 'COMMISSION',
          amountPaise: commissionPaise,
          metadata: { source: 'dispute_resolution', outcome: body.outcome },
        },
      });
    }
    // SINGLE-REVERSAL: write DISPUTE_REVERSAL once here for BOTH UPI and cash.
    // For UPI the gateway call has already happened above; the webhook later only sets razorpayRefundId.
    if (refundPaise > 0) {
      await tx.ledgerEntry.create({
        data: {
          technicianId: booking.technicianId!,
          bookingId: booking.id,
          type: 'DISPUTE_REVERSAL',
          amountPaise: refundPaise,
          metadata: { outcome: body.outcome, method: captured.method },
        },
      });
    }

    // Auto-offset cash debt against the credited earning (FOR-UPDATE-locked, B6c idiom).
    if (earningPaise > 0) {
      const [locked] = await tx.$queryRaw<{ cashDebtPaise: number }[]>`
        SELECT "cashDebtPaise" FROM "Technician" WHERE id = ${booking.technicianId} FOR UPDATE
      `;
      if (!locked) throw new Error(`technician ${booking.technicianId} vanished mid-resolution`); // fail LOUD (roll back), parity with the sweep — never silently skip the offset
      {
        const currentDebt = Number(locked.cashDebtPaise);
        const offset = Math.min(earningPaise, currentDebt);
        if (offset > 0) {
          await tx.technician.update({
            where: { id: booking.technicianId! },
            data: { cashDebtPaise: { decrement: offset } },
          });
          await tx.ledgerEntry.create({
            data: {
              technicianId: booking.technicianId!,
              bookingId: booking.id,
              type: 'CASH_DEBT_OFFSET',
              amountPaise: offset,
            },
          });
        }
      }
    }

    await transitionBooking(
      tx,
      booking,
      'CLOSED',
      { type: 'USER', kind: 'ADMIN', id: adminUserId },
      { source: 'dispute_resolution', outcome: body.outcome, refundPaise },
    );
    await tx.booking.update({ where: { id: booking.id }, data: { closedAt: new Date() } });

    // Audit log — no customer PII. adminReason is the ADMIN's own adjudication rationale (not the
    // customer's free text) — safe to log and the record of WHY a money-moving ruling was made.
    await tx.auditLog.create({
      data: {
        action: 'DISPUTE_EVENT',
        actorType: 'USER',
        actorId: adminUserId,
        metadata: {
          event: 'resolved',
          disputeId,
          bookingId: booking.id,
          outcome: body.outcome,
          refundPaise,
          refundId, // null for cash or FAVOR_TECHNICIAN; non-null for UPI refund
          method: captured.method,
          adminReason: body.reason,
        },
      },
    });
  });

  return { id: booking.id, state: 'CLOSED', outcome: body.outcome, refundPaise };
}

/** Case file DTO for admin drill-down (MANAGER+ route only). Includes the customer's `reason` —
 *  the admin must read the complaint to adjudicate. `reason` is appliance-complaint text, NOT a
 *  restricted PII category (phone/UPI/address/Aadhaar/photo), and this endpoint is admin-gated;
 *  the CUSTOMER-facing BookingDto.dispute still omits it. No raw user objects. */
export async function getDispute(disputeId: string): Promise<{
  id: string;
  bookingId: string;
  status: string;
  reason: string;
  outcome: string | null;
  refundPaise: number | null;
  resolvedAt: string | null;
  createdAt: string;
}> {
  const dispute = await prisma.dispute.findUnique({ where: { id: disputeId } });
  if (!dispute) throw new NotFoundError('Dispute not found');
  return {
    id: dispute.id,
    bookingId: dispute.bookingId,
    status: dispute.status,
    reason: dispute.reason,
    outcome: dispute.outcome ?? null,
    refundPaise: dispute.refundPaise ?? null,
    resolvedAt: dispute.resolvedAt?.toISOString() ?? null,
    createdAt: dispute.createdAt.toISOString(),
  };
}

/** Admin list of disputes, optionally filtered by status. Newest first. */
export async function listDisputes(status?: 'OPEN' | 'RESOLVED'): Promise<{
  disputes: {
    id: string;
    bookingId: string;
    status: string;
    outcome: string | null;
    refundPaise: number | null;
    createdAt: string;
  }[];
}> {
  const rows = await prisma.dispute.findMany({
    where: status ? { status } : undefined,
    orderBy: { createdAt: 'desc' },
    take: 100,
  });
  return {
    disputes: rows.map((d) => ({
      id: d.id,
      bookingId: d.bookingId,
      status: d.status,
      outcome: d.outcome ?? null,
      refundPaise: d.refundPaise ?? null,
      createdAt: d.createdAt.toISOString(),
    })),
  };
}
