import { mintOtp, verifyOtp } from '../../shared/auth/otp-store.js';

const TTL_SECONDS = 600;
const MAX_ATTEMPTS = 5;
const key = (bookingId: string) => `arrival:${bookingId}`;

/** Mint the single-use 6-digit arrival code (10-min TTL). Re-minting replaces any prior code. */
export async function mintArrivalCode(bookingId: string): Promise<string> {
  const r = await mintOtp(key(bookingId), { ttlSeconds: TTL_SECONDS });
  // No sendLimit configured here, so mint never throttles — 'ok' is the only outcome.
  if (r.status !== 'ok') throw new Error('arrival code mint failed unexpectedly');
  return r.code;
}

export type ArrivalVerifyResult = 'ok' | 'invalid' | 'no-code';

/** Verify (and on success consume) the arrival code. Tri-state: 'ok' | 'invalid' (wrong code,
 *  attempts remain) | 'no-code' (never minted, expired, exhausted, or already consumed).
 *  NOTE the DELIBERATE difference from completion-code, which folds exhausted→'invalid' instead:
 *  here the cheapest recovery for a dead code is the technician re-tapping Arrived (the caller
 *  maps 'no-code' → 409 with that guidance). A future OTP wrapper must CHOOSE its fold. */
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
    default: {
      // Compile-time exhaustiveness: a 5th VerifyResult status must be mapped here explicitly.
      const unreachable: never = r;
      throw new Error(`Unhandled verifyOtp status: ${JSON.stringify(unreachable)}`);
    }
  }
}
