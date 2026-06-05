import { describe, expect, it } from 'vitest';
import { rupeesToPaise, paiseToRupees, formatPaise, assertValidPaise } from '../src/shared/utils/currency.js';
import { ValidationError } from '../src/shared/errors.js';

describe('currency', () => {
  it('converts rupees → paise (integer)', () => {
    expect(rupeesToPaise(149)).toBe(14900);
    expect(rupeesToPaise(99.5)).toBe(9950);
  });
  it('converts paise → rupees', () => {
    expect(paiseToRupees(14900)).toBe(149);
  });
  it('formats paise as ₹', () => {
    expect(formatPaise(14900)).toBe('₹149.00');
    expect(formatPaise(9950)).toBe('₹99.50');
  });
  it('assertValidPaise accepts a non-negative integer', () => {
    expect(() => assertValidPaise(0)).not.toThrow();
    expect(() => assertValidPaise(14900)).not.toThrow();
  });
  it('assertValidPaise rejects negatives, floats, and non-numbers', () => {
    expect(() => assertValidPaise(-1)).toThrow(ValidationError);
    expect(() => assertValidPaise(10.5)).toThrow(ValidationError);
    expect(() => assertValidPaise('100')).toThrow(ValidationError);
  });
});
