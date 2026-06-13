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
  it('EN_ROUTE is technician-only; ARRIVED is customer-only (the arrival handshake)', () => {
    expect(actorAllowedFor('EN_ROUTE', 'TECHNICIAN')).toBe(true);
    expect(actorAllowedFor('EN_ROUTE', 'CUSTOMER')).toBe(false);
    expect(actorAllowedFor('ARRIVED', 'CUSTOMER')).toBe(true);
    expect(actorAllowedFor('ARRIVED', 'TECHNICIAN')).toBe(false);
  });
  it('DEFAULT-DENY: a still-unmapped to-state is rejected for every actor (a later slice must add its entry)', () => {
    expect(actorAllowedFor('DIAGNOSED', 'TECHNICIAN')).toBe(false);
    expect(actorAllowedFor('CANCELLED_BY_TECHNICIAN', 'TECHNICIAN')).toBe(false);
    expect(actorAllowedFor('PAYMENT_RECEIVED', 'SYSTEM')).toBe(false);
  });
});
