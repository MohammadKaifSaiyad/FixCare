import { describe, expect, it } from 'vitest';
import { actorAllowedFor } from '../../src/modules/bookings/bookings.state.js';

describe('ALLOWED_ACTORS', () => {
  it('SYSTEM may open to DISPATCHED; a customer/technician may not', () => {
    expect(actorAllowedFor('DISPATCHED', 'SYSTEM')).toBe(true);
    expect(actorAllowedFor('DISPATCHED', 'CUSTOMER')).toBe(false);
    expect(actorAllowedFor('DISPATCHED', 'TECHNICIAN')).toBe(false);
  });
  it('TECHNICIAN may accept; a customer may not', () => {
    expect(actorAllowedFor('ACCEPTED', 'TECHNICIAN')).toBe(true);
    expect(actorAllowedFor('ACCEPTED', 'CUSTOMER')).toBe(false);
  });
  it('CUSTOMER may cancel; a technician may not', () => {
    expect(actorAllowedFor('CANCELLED_BY_CUSTOMER', 'CUSTOMER')).toBe(true);
    expect(actorAllowedFor('CANCELLED_BY_CUSTOMER', 'TECHNICIAN')).toBe(false);
  });
  it('an unmapped to-state has no role restriction (returns true)', () => {
    expect(actorAllowedFor('ARRIVED', 'TECHNICIAN')).toBe(true);
  });
});
