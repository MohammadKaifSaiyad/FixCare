import type { Prisma, Booking, BookingState, ActorType } from '@prisma/client';
import { ConflictError } from '../../shared/errors.js';

export const ALLOWED_TRANSITIONS: Record<BookingState, BookingState[]> = {
  CREATED:            ['DISPATCHED', 'CANCELLED_BY_CUSTOMER'],
  DISPATCHED:         ['ACCEPTED', 'CANCELLED_BY_CUSTOMER', 'CANCELLED_BY_TECHNICIAN'],
  ACCEPTED:           ['EN_ROUTE', 'CANCELLED_BY_CUSTOMER', 'CANCELLED_BY_TECHNICIAN'],
  EN_ROUTE:           ['ARRIVED', 'CANCELLED_BY_CUSTOMER', 'CANCELLED_BY_TECHNICIAN'],
  ARRIVED:            ['DIAGNOSED'],
  DIAGNOSED:          ['CUSTOMER_APPROVED', 'DECLINED_BY_CUSTOMER'],
  CUSTOMER_APPROVED:  ['PARTS_REQUESTED', 'REPAIR_IN_PROGRESS'],
  PARTS_REQUESTED:    ['PARTS_ACQUIRED'],
  PARTS_ACQUIRED:     ['REPAIR_IN_PROGRESS'],
  REPAIR_IN_PROGRESS: ['REPAIR_COMPLETE'],
  REPAIR_COMPLETE:    ['CUSTOMER_CONFIRMED'],
  CUSTOMER_CONFIRMED: ['PAYMENT_RECEIVED', 'DISPUTED'],
  PAYMENT_RECEIVED:   ['CLOSED'],
  DISPUTED:           ['CLOSED'],
  CLOSED:                  [],
  CANCELLED_BY_CUSTOMER:   [],
  CANCELLED_BY_TECHNICIAN: [],
  DECLINED_BY_CUSTOMER:    [],
};

export function isTransitionAllowed(from: BookingState, to: BookingState): boolean {
  return ALLOWED_TRANSITIONS[from].includes(to);
}

/** Who is driving a transition. `id` is the User.id (or a system marker). */
export interface BookingActor { type: ActorType; id: string; }

/**
 * Guarded transition: validates legality, writes state + BOOKING_STATE_CHANGED audit in the
 * caller's transaction. Throws ConflictError (409) on illegal transition. (Actor-permission
 * checks are the caller's responsibility in B1 — only customer-cancel exists; later slices add a
 * permission map here.)
 */
export async function transitionBooking(
  tx: Prisma.TransactionClient,
  booking: Booking,
  to: BookingState,
  actor: BookingActor,
): Promise<Booking> {
  if (!isTransitionAllowed(booking.state, to)) {
    throw new ConflictError(`Cannot transition booking from ${booking.state} to ${to}`);
  }
  // Optimistic lock: the update is conditional on the from-state the legality check ran against
  // (which was loaded before this tx). If a concurrent transition already moved the row, 0 rows
  // match and we reject — so two racing transitions can't both commit / double-write the audit.
  const result = await tx.booking.updateMany({
    where: { id: booking.id, state: booking.state },
    data: { state: to },
  });
  if (result.count === 0) {
    throw new ConflictError(`Booking ${booking.id} is no longer in state ${booking.state}`);
  }
  await tx.auditLog.create({
    data: {
      action: 'BOOKING_STATE_CHANGED',
      actorType: actor.type,
      actorId: actor.id,
      metadata: { bookingId: booking.id, from: booking.state, to },
    },
  });
  // re-read the row so callers get the updated state (updateMany doesn't return the row)
  const updated = await tx.booking.findUniqueOrThrow({ where: { id: booking.id } });
  return updated;
}
