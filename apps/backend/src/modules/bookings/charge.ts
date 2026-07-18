import type { BookingPart, BookingState } from '@prisma/client';
import { ConflictError } from '../../shared/errors.js';
import { computeEstimate } from './estimate.js';

/** The ONE source of the charge amount (Golden Rule 4: snapshots only, never live catalog).
 *  - CUSTOMER_CONFIRMED: the invariant-locked approved total (labor + parts − visit-fee credit).
 *  - DECLINED_BY_CUSTOMER: the visit fee locked at ARRIVED — the visit happened, the repair didn't.
 *  Anything else is not chargeable. */
export function chargeAmountFor(
  booking: { state: BookingState; laborPaise: number; visitFeePaise: number },
  parts: BookingPart[],
): number {
  if (booking.state === 'CUSTOMER_CONFIRMED') {
    return computeEstimate(booking, parts).totalPayablePaise;
  }
  if (booking.state === 'DECLINED_BY_CUSTOMER') {
    return booking.visitFeePaise;
  }
  throw new ConflictError('Booking is not awaiting payment');
}
