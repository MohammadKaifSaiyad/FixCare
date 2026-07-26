import { describe, expect, it } from 'vitest';
import { ALLOWED_TRANSITIONS, actorAllowedFor, isTransitionAllowed } from '../../src/modules/bookings/bookings.state.js';

describe('ALLOWED_TRANSITIONS', () => {
  it('allows CREATED → CANCELLED_BY_CUSTOMER and CREATED → DISPATCHED', () => {
    expect(isTransitionAllowed('CREATED', 'CANCELLED_BY_CUSTOMER')).toBe(true);
    expect(isTransitionAllowed('CREATED', 'DISPATCHED')).toBe(true);
  });

  it('rejects an illegal jump (CREATED → CLOSED)', () => {
    expect(isTransitionAllowed('CREATED', 'CLOSED')).toBe(false);
  });

  it('terminal states have no outgoing transitions', () => {
    for (const t of ['CLOSED', 'CANCELLED_BY_CUSTOMER', 'CANCELLED_BY_TECHNICIAN'] as const) {
      expect(ALLOWED_TRANSITIONS[t]).toEqual([]);
    }
  });

  it('DECLINED_BY_CUSTOMER is NOT terminal since B6a — the locked visit fee is still owed', () => {
    expect(ALLOWED_TRANSITIONS['DECLINED_BY_CUSTOMER']).toEqual(['PAYMENT_RECEIVED']);
  });

  it('PAYMENT_RECEIVED: SYSTEM (UPI webhook) + TECHNICIAN (cash receipt, customer OTP = 2nd party) only', () => {
    // Golden Rule 2 both ways: the gateway's signed word OR the technician entering the code
    // minted to the customer. CUSTOMER and ADMIN can never mark money received.
    expect(actorAllowedFor('PAYMENT_RECEIVED', 'SYSTEM')).toBe(true);
    expect(actorAllowedFor('PAYMENT_RECEIVED', 'TECHNICIAN')).toBe(true);
    for (const kind of ['CUSTOMER', 'ADMIN'] as const) {
      expect(actorAllowedFor('PAYMENT_RECEIVED', kind)).toBe(false);
    }
  });

  it('CLOSED is SYSTEM-only — the settlement sweep drives it (B7 adds ADMIN for dispute closes)', () => {
    expect(actorAllowedFor('CLOSED', 'SYSTEM')).toBe(true);
    for (const kind of ['CUSTOMER', 'TECHNICIAN', 'ADMIN'] as const) {
      expect(actorAllowedFor('CLOSED', kind)).toBe(false);
    }
  });

  it('cancel edges only exist before ARRIVED', () => {
    expect(ALLOWED_TRANSITIONS['EN_ROUTE']).toContain('CANCELLED_BY_CUSTOMER');
    expect(ALLOWED_TRANSITIONS['ARRIVED']).not.toContain('CANCELLED_BY_CUSTOMER');
  });
});
