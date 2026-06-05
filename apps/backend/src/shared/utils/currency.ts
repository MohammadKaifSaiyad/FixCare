import { ValidationError } from '../errors.js';

/** Rupees → integer paise. Rounds to the nearest paisa. */
export function rupeesToPaise(rupees: number): number {
  return Math.round(rupees * 100);
}

/** Integer paise → rupees (number). */
export function paiseToRupees(paise: number): number {
  return paise / 100;
}

/** Format paise as a ₹ string with 2 decimals, e.g. 14900 → "₹149.00". */
export function formatPaise(paise: number): string {
  return `₹${(paise / 100).toFixed(2)}`;
}

/** Assert a value is a non-negative integer number of paise; throws ValidationError otherwise. */
export function assertValidPaise(v: unknown): asserts v is number {
  if (typeof v !== 'number' || !Number.isInteger(v) || v < 0) {
    throw new ValidationError('Amount must be a non-negative integer (paise)');
  }
}
