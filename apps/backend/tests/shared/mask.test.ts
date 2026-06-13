import { describe, expect, it } from 'vitest';
import { maskPhone } from '../../src/shared/utils/mask.js';

describe('maskPhone', () => {
  it('keeps the last 4 digits, masks the rest', () => {
    expect(maskPhone('9876543210')).toBe('••••••3210');
  });
  it('handles a +91 prefixed number (mask all but last 4)', () => {
    expect(maskPhone('+919876543210')).toMatch(/3210$/);
    expect(maskPhone('+919876543210')).not.toContain('98765');
  });
  it('a short/empty value masks to all dots (never leaks)', () => {
    expect(maskPhone('12')).toBe('••');
    expect(maskPhone('')).toBe('');
  });
});
