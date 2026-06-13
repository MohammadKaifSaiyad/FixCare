import { describe, expect, it } from 'vitest';
import { haversineMeters } from '../../src/shared/utils/geo.js';

describe('haversineMeters', () => {
  it('is 0 for the same point', () => {
    expect(haversineMeters(22.3072, 73.1812, 22.3072, 73.1812)).toBe(0);
  });
  it('approximates a known short distance (~157m) within tolerance', () => {
    const d = haversineMeters(22.3072, 73.1812, 22.3086, 73.1812); // ~0.0014 deg lat
    expect(d).toBeGreaterThan(140);
    expect(d).toBeLessThan(175);
  });
  it('grows with distance (1 deg lat ≈ 111km)', () => {
    const d = haversineMeters(22.0, 73.0, 23.0, 73.0);
    expect(d).toBeGreaterThan(110_000);
    expect(d).toBeLessThan(112_000);
  });
});
