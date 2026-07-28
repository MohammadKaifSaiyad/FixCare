import { prisma } from '../../shared/database/prisma.js';
import { config } from '../../shared/config.js';
import { NotFoundError, ConflictError } from '../../shared/errors.js';
import { requireCustomer } from '../bookings/bookings.service.js';
import { transitionBooking } from '../bookings/bookings.state.js';
import type { RaiseDisputeBody } from './disputes.schemas.js';

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
