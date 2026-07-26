import type { Prisma, Booking, BookingState, ActorType } from '@prisma/client';
import { ConflictError, ForbiddenError } from '../../shared/errors.js';

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
  DECLINED_BY_CUSTOMER:    ['PAYMENT_RECEIVED'], // the locked visit fee is still owed (B6a)
};

export function isTransitionAllowed(from: BookingState, to: BookingState): boolean {
  return ALLOWED_TRANSITIONS[from].includes(to);
}

export type ActorKind = 'CUSTOMER' | 'TECHNICIAN' | 'ADMIN' | 'SYSTEM';

/** Which actor kind(s) may drive a transition INTO a given state. DEFAULT-DENY: a to-state NOT
 *  listed here is rejected for every actor — so each later slice MUST add its entry before its
 *  transition route works (an omission fails loud with 403, not a silent bypass). This matters most
 *  for the keystone handshakes (ARRIVED, CUSTOMER_CONFIRMED) where Golden Rule 2 forbids a single
 *  party driving the transition alone. B2a wires only the three below. */
const ALLOWED_ACTORS: Partial<Record<BookingState, ActorKind[]>> = {
  DISPATCHED:            ['SYSTEM'],
  EN_ROUTE:              ['TECHNICIAN'],
  ARRIVED:               ['CUSTOMER'],
  ACCEPTED:              ['TECHNICIAN'],
  CANCELLED_BY_CUSTOMER: ['CUSTOMER'],
  DIAGNOSED:             ['TECHNICIAN'],
  CUSTOMER_APPROVED:     ['CUSTOMER'],
  DECLINED_BY_CUSTOMER:  ['CUSTOMER'],
  PARTS_REQUESTED:       ['TECHNICIAN'],
  PARTS_ACQUIRED:        ['TECHNICIAN'],
  REPAIR_IN_PROGRESS:    ['TECHNICIAN'],
  REPAIR_COMPLETE:       ['TECHNICIAN'],
  CUSTOMER_CONFIRMED:    ['TECHNICIAN'], // keystone #2 — the customer's code is the second party
  PAYMENT_RECEIVED:      ['SYSTEM', 'TECHNICIAN'], // UPI: the gateway's signed capture (SYSTEM). Cash (B6b): the technician — but only with the receipt code minted to the CUSTOMER (Rule 2's second party).
  DISPUTED:              ['CUSTOMER'], // B7: the customer raises within the 48h window
  CLOSED:                ['SYSTEM', 'ADMIN'], // SYSTEM = settlement sweep (B6c); ADMIN = dispute resolution (B7)
};

export function actorAllowedFor(to: BookingState, kind: ActorKind): boolean {
  const allowed = ALLOWED_ACTORS[to];
  return allowed !== undefined && allowed.includes(kind); // default-deny: unmapped to-state → false
}

/** Who is driving a transition. `id` is the User.id (or a system marker). */
export interface BookingActor { type: ActorType; kind: ActorKind; id: string; }

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
  evidence?: Record<string, unknown>,
): Promise<Booking> {
  if (!isTransitionAllowed(booking.state, to)) {
    throw new ConflictError(`Cannot transition booking from ${booking.state} to ${to}`);
  }
  if (!actorAllowedFor(to, actor.kind)) {
    throw new ForbiddenError(`A ${actor.kind} may not transition a booking to ${to}`);
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
      metadata: { bookingId: booking.id, from: booking.state, to, ...(evidence ?? {}) },
    },
  });
  // re-read the row so callers get the updated state (updateMany doesn't return the row)
  const updated = await tx.booking.findUniqueOrThrow({ where: { id: booking.id } });
  return updated;
}
