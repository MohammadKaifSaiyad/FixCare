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
