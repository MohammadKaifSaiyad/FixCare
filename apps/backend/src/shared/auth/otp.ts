import { createHash, randomInt } from 'node:crypto';

/** A cryptographically-random 6-digit OTP as a string (zero-padded). */
export function generateOtp(): string {
  return randomInt(0, 1_000_000).toString().padStart(6, '0');
}

/** SHA-256 hash of an OTP — we store/compare hashes, never the raw OTP. */
export function hashOtp(otp: string): string {
  return createHash('sha256').update(otp).digest('hex');
}
