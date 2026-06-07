import { describe, expect, it } from 'vitest';
import { generateBookingNumber } from '../../src/modules/bookings/bookings.number.js';

describe('generateBookingNumber', () => {
  it('returns an FC- prefixed code of the right shape', () => {
    const n = generateBookingNumber();
    expect(n).toMatch(/^FC-[0-9A-HJ-NP-Z]{6}$/); // Crockford base32, no I/L/O/U
  });

  it('is highly unlikely to collide across many calls', () => {
    const seen = new Set<string>();
    for (let i = 0; i < 10000; i++) seen.add(generateBookingNumber());
    expect(seen.size).toBe(10000);
  });
});
