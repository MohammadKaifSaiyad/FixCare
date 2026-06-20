import type { BookingState } from '@prisma/client';

export interface Estimate {
  laborPaise: number;
  partsPaise: number;
  visitFeeCreditPaise: number;
  totalPayablePaise: number;
}

/** Sum a parts cart in integer paise. Single source of truth for the parts total — reused by
 *  computeEstimate and by the approve/decline audit-evidence snapshot so the two can never drift. */
export function sumParts(parts: { ceilingPricePaise: number; qty: number }[]): number {
  return parts.reduce((sum, p) => sum + p.ceilingPricePaise * p.qty, 0);
}

/** Compute the customer-facing estimate from snapshots, scaled to the booking's lifecycle stage.
 *  Integer paise throughout; the payable never goes negative.
 *
 *  - Before DIAGNOSED: nothing is quoted yet, so this is indicative only — labor with NO visit-fee
 *    credit applied (showing a credited/zero payable before any work is agreed would mislead the
 *    customer into thinking the job is free).
 *  - DIAGNOSED / CUSTOMER_APPROVED: the real quote — visit fee is CREDITED toward labor + parts
 *    (pricing-model), floored at 0.
 *  - DECLINED_BY_CUSTOMER / CANCELLED_*: the repair will not happen, so nothing is payable for it
 *    (the visit fee that locked at ARRIVED is owed separately and is not modelled as an estimate). */
export function computeEstimate(
  booking: { laborPaise: number; visitFeePaise: number; state: BookingState },
  parts: { ceilingPricePaise: number; qty: number }[],
): Estimate {
  const partsPaise = sumParts(parts);

  if (booking.state === 'DECLINED_BY_CUSTOMER' || booking.state === 'CANCELLED_BY_CUSTOMER' || booking.state === 'CANCELLED_BY_TECHNICIAN') {
    return { laborPaise: booking.laborPaise, partsPaise, visitFeeCreditPaise: 0, totalPayablePaise: 0 };
  }

  const quoted = booking.state === 'DIAGNOSED' || booking.state === 'CUSTOMER_APPROVED';
  const visitFeeCreditPaise = quoted ? booking.visitFeePaise : 0;
  const totalPayablePaise = Math.max(0, booking.laborPaise + partsPaise - visitFeeCreditPaise);
  return { laborPaise: booking.laborPaise, partsPaise, visitFeeCreditPaise, totalPayablePaise };
}
