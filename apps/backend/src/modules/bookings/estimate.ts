export interface Estimate {
  laborPaise: number;
  partsPaise: number;
  visitFeeCreditPaise: number;
  totalPayablePaise: number;
}

/** Compute the customer-facing estimate from snapshots. The visit fee is a CREDIT toward labor+parts
 *  (pricing-model); the total is floored at 0 (a credit never makes the customer owe a negative). All
 *  inputs are integer paise. */
export function computeEstimate(
  booking: { laborPaise: number; visitFeePaise: number },
  parts: { ceilingPricePaise: number; qty: number }[],
): Estimate {
  const partsPaise = parts.reduce((sum, p) => sum + p.ceilingPricePaise * p.qty, 0);
  const visitFeeCreditPaise = booking.visitFeePaise;
  const totalPayablePaise = Math.max(0, booking.laborPaise + partsPaise - visitFeeCreditPaise);
  return { laborPaise: booking.laborPaise, partsPaise, visitFeeCreditPaise, totalPayablePaise };
}
