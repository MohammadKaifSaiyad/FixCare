import { describe, expect, it } from 'vitest';
import { computeEstimate, sumParts } from '../../src/modules/bookings/estimate.js';

const cart = [
  { ceilingPricePaise: 70000, qty: 1 },
  { ceilingPricePaise: 12000, qty: 2 },
];

describe('sumParts', () => {
  it('sums ceilingPrice × qty over the cart', () => {
    expect(sumParts(cart)).toBe(94000);
    expect(sumParts([])).toBe(0);
  });
});

describe('computeEstimate', () => {
  it('DIAGNOSED: labor + parts − visit-fee credit', () => {
    const e = computeEstimate({ laborPaise: 60000, visitFeePaise: 14900, state: 'DIAGNOSED' }, cart);
    expect(e).toEqual({ laborPaise: 60000, partsPaise: 94000, visitFeeCreditPaise: 14900, totalPayablePaise: 139100 });
  });
  it('CUSTOMER_APPROVED: same quoted math (empty cart → labor − visit fee)', () => {
    expect(computeEstimate({ laborPaise: 60000, visitFeePaise: 14900, state: 'CUSTOMER_APPROVED' }, []))
      .toMatchObject({ partsPaise: 0, visitFeeCreditPaise: 14900, totalPayablePaise: 45100 });
  });
  it('a DECLINED booking stays 0-payable even after its visit-fee settlement (PAYMENT_RECEIVED)', () => {
    // B6a opens DECLINED_BY_CUSTOMER → PAYMENT_RECEIVED; the state alone no longer identifies a
    // declined booking, but declinedAt does — the repair total must never reappear.
    const e = computeEstimate({ laborPaise: 60000, visitFeePaise: 14900, state: 'PAYMENT_RECEIVED', declinedAt: new Date() }, cart);
    expect(e.totalPayablePaise).toBe(0);
    expect(e.visitFeeCreditPaise).toBe(0);
  });
  it('the approved total NEVER drifts as the repair progresses (B5 states keep the credit)', () => {
    // Golden Rule 4: the number the customer approved IS the price. Every post-quote state must
    // show the same total — a booking mid-repair must not silently gain back the visit fee.
    const approved = computeEstimate({ laborPaise: 60000, visitFeePaise: 14900, state: 'CUSTOMER_APPROVED' }, cart);
    for (const state of ['PARTS_REQUESTED', 'PARTS_ACQUIRED', 'REPAIR_IN_PROGRESS', 'REPAIR_COMPLETE', 'CUSTOMER_CONFIRMED', 'PAYMENT_RECEIVED', 'CLOSED'] as const) {
      expect(computeEstimate({ laborPaise: 60000, visitFeePaise: 14900, state }, cart)).toEqual(approved);
    }
  });
  it('DIAGNOSED: floors total at 0 when the visit fee exceeds labor+parts', () => {
    expect(computeEstimate({ laborPaise: 10000, visitFeePaise: 14900, state: 'DIAGNOSED' }, []).totalPayablePaise).toBe(0);
  });
  it('pre-diagnosis (ARRIVED): indicative — NO visit-fee credit applied, total = labor', () => {
    const e = computeEstimate({ laborPaise: 60000, visitFeePaise: 14900, state: 'ARRIVED' }, []);
    expect(e).toMatchObject({ laborPaise: 60000, partsPaise: 0, visitFeeCreditPaise: 0, totalPayablePaise: 60000 });
  });
  it('CREATED: indicative, never pre-credits the visit fee to a low-labor job', () => {
    expect(computeEstimate({ laborPaise: 10000, visitFeePaise: 14900, state: 'CREATED' }, []).totalPayablePaise).toBe(10000);
  });
  it('DECLINED_BY_CUSTOMER: nothing payable for the repair', () => {
    expect(computeEstimate({ laborPaise: 60000, visitFeePaise: 14900, state: 'DECLINED_BY_CUSTOMER' }, cart))
      .toMatchObject({ visitFeeCreditPaise: 0, totalPayablePaise: 0 });
  });
});
