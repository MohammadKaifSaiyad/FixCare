import { describe, expect, it } from 'vitest';
import { computeEstimate } from '../../src/modules/bookings/estimate.js';

describe('computeEstimate', () => {
  it('labor + parts − visit-fee credit', () => {
    const e = computeEstimate({ laborPaise: 60000, visitFeePaise: 14900 }, [
      { ceilingPricePaise: 70000, qty: 1 },
      { ceilingPricePaise: 12000, qty: 2 },
    ]);
    expect(e).toEqual({ laborPaise: 60000, partsPaise: 94000, visitFeeCreditPaise: 14900, totalPayablePaise: 139100 });
  });
  it('empty cart → labor − visit fee', () => {
    expect(computeEstimate({ laborPaise: 60000, visitFeePaise: 14900 }, [])).toMatchObject({ partsPaise: 0, totalPayablePaise: 45100 });
  });
  it('floors total at 0 when the visit fee exceeds labor+parts', () => {
    expect(computeEstimate({ laborPaise: 10000, visitFeePaise: 14900 }, []).totalPayablePaise).toBe(0);
  });
});
