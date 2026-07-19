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
  it('DIAGNOSED is technician-only; CUSTOMER_APPROVED/DECLINED are customer-only', () => {
    expect(actorAllowedFor('DIAGNOSED', 'TECHNICIAN')).toBe(true);
    expect(actorAllowedFor('DIAGNOSED', 'CUSTOMER')).toBe(false);
    expect(actorAllowedFor('CUSTOMER_APPROVED', 'CUSTOMER')).toBe(true);
    expect(actorAllowedFor('CUSTOMER_APPROVED', 'TECHNICIAN')).toBe(false);
    expect(actorAllowedFor('DECLINED_BY_CUSTOMER', 'CUSTOMER')).toBe(true);
    expect(actorAllowedFor('DECLINED_BY_CUSTOMER', 'TECHNICIAN')).toBe(false);
  });
  it('repair-path states are technician-only (B5)', () => {
    expect(actorAllowedFor('PARTS_REQUESTED', 'TECHNICIAN')).toBe(true);
    expect(actorAllowedFor('PARTS_REQUESTED', 'CUSTOMER')).toBe(false);
    expect(actorAllowedFor('PARTS_ACQUIRED', 'TECHNICIAN')).toBe(true);
    expect(actorAllowedFor('PARTS_ACQUIRED', 'CUSTOMER')).toBe(false);
    expect(actorAllowedFor('REPAIR_IN_PROGRESS', 'TECHNICIAN')).toBe(true);
    expect(actorAllowedFor('REPAIR_IN_PROGRESS', 'CUSTOMER')).toBe(false);
  });
  it('REPAIR_COMPLETE + CUSTOMER_CONFIRMED are technician-only (keystone #2 — the customer mints, never transitions)', () => {
    expect(actorAllowedFor('REPAIR_COMPLETE', 'TECHNICIAN')).toBe(true);
    expect(actorAllowedFor('REPAIR_COMPLETE', 'CUSTOMER')).toBe(false);
    expect(actorAllowedFor('CUSTOMER_CONFIRMED', 'TECHNICIAN')).toBe(true);
    expect(actorAllowedFor('CUSTOMER_CONFIRMED', 'CUSTOMER')).toBe(false);
    expect(actorAllowedFor('CUSTOMER_CONFIRMED', 'ADMIN')).toBe(false);
  });
  it('PAYMENT_RECEIVED is SYSTEM-only (the gateway drives it, never a party)', () => {
    expect(actorAllowedFor('PAYMENT_RECEIVED', 'SYSTEM')).toBe(true);
    expect(actorAllowedFor('PAYMENT_RECEIVED', 'CUSTOMER')).toBe(false);
    expect(actorAllowedFor('PAYMENT_RECEIVED', 'TECHNICIAN')).toBe(false);
  });
  it('DEFAULT-DENY: still-unmapped to-states are rejected for every actor', () => {
    expect(actorAllowedFor('CANCELLED_BY_TECHNICIAN', 'TECHNICIAN')).toBe(false);
    expect(actorAllowedFor('CLOSED', 'SYSTEM')).toBe(false); // B6c/B7 wires the dispute-window close
  });
});
