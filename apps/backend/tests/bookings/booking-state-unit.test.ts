import { describe, expect, it } from 'vitest';
import { ALLOWED_TRANSITIONS, isTransitionAllowed } from '../../src/modules/bookings/bookings.state.js';

describe('ALLOWED_TRANSITIONS', () => {
  it('allows CREATED → CANCELLED_BY_CUSTOMER and CREATED → DISPATCHED', () => {
    expect(isTransitionAllowed('CREATED', 'CANCELLED_BY_CUSTOMER')).toBe(true);
    expect(isTransitionAllowed('CREATED', 'DISPATCHED')).toBe(true);
  });

  it('rejects an illegal jump (CREATED → CLOSED)', () => {
    expect(isTransitionAllowed('CREATED', 'CLOSED')).toBe(false);
  });

  it('terminal states have no outgoing transitions', () => {
    for (const t of ['CLOSED', 'CANCELLED_BY_CUSTOMER', 'CANCELLED_BY_TECHNICIAN', 'DECLINED_BY_CUSTOMER'] as const) {
      expect(ALLOWED_TRANSITIONS[t]).toEqual([]);
    }
  });

  it('cancel edges only exist before ARRIVED', () => {
    expect(ALLOWED_TRANSITIONS['EN_ROUTE']).toContain('CANCELLED_BY_CUSTOMER');
    expect(ALLOWED_TRANSITIONS['ARRIVED']).not.toContain('CANCELLED_BY_CUSTOMER');
  });
});
