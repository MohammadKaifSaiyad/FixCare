import { mintOtp, verifyOtp } from '../../shared/auth/otp-store.js';

const TTL_SECONDS = 600;
const MAX_ATTEMPTS = 5;
const key = (bookingId: string) => `arrival:${bookingId}`;

export async function mintArrivalCode(bookingId: string): Promise<string> {
  const r = await mintOtp(key(bookingId), { ttlSeconds: TTL_SECONDS, maxAttempts: MAX_ATTEMPTS });
  // No sendLimit configured here, so mint never throttles — 'ok' is the only outcome.
  if (r.status !== 'ok') throw new Error('arrival code mint failed unexpectedly');
  return r.code;
}

export type ArrivalVerifyResult = 'ok' | 'invalid' | 'no-code';

export async function verifyArrivalCode(bookingId: string, code: string): Promise<ArrivalVerifyResult> {
  const r = await verifyOtp(key(bookingId), code, { maxAttempts: MAX_ATTEMPTS });
  switch (r.status) {
    case 'ok':
      return 'ok';
    case 'invalid':
      return 'invalid';
    // Exhausted attempts deletes the key; arrival has always surfaced this as 'no-code'
    // (the booking caller maps 'no-code' → 409). Preserve that exactly.
    case 'exhausted':
    case 'no-code':
      return 'no-code';
  }
}
