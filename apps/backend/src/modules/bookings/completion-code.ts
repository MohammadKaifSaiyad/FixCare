import { mintOtp, verifyOtp } from '../../shared/auth/otp-store.js';

const TTL_SECONDS = 600;
const MAX_ATTEMPTS = 5;
// The mint sends a real SMS in production — throttle per booking so a tapping-happy customer
// (or a client bug) can't flood SMS spend. 3 codes / 15 min covers every honest retry.
const SEND_LIMIT = { max: 3, windowSeconds: 900 };
const key = (bookingId: string) => `completion:${bookingId}`;

export type CompletionMintResult = { status: 'ok'; code: string } | { status: 'throttled' };

/** Mint the single-use 6-digit completion code (10-min TTL). A re-mint replaces any prior code. */
export async function mintCompletionCode(bookingId: string): Promise<CompletionMintResult> {
  return mintOtp(key(bookingId), { ttlSeconds: TTL_SECONDS, sendLimit: SEND_LIMIT });
}

export type CompletionVerifyResult = 'ok' | 'invalid' | 'no-code';

/** Verify (and on success consume) the completion code. 'invalid' covers wrong AND exhausted
 *  (→401 — a fresh code fixes both); 'no-code' covers never-minted AND expired (→409 — the
 *  customer simply requests a new one). Uses the store's 4-arm union directly. */
export async function verifyCompletionCode(bookingId: string, code: string): Promise<CompletionVerifyResult> {
  const r = await verifyOtp(key(bookingId), code, { maxAttempts: MAX_ATTEMPTS });
  switch (r.status) {
    case 'ok':
      return 'ok';
    case 'invalid':
    case 'exhausted':
      return 'invalid';
    case 'no-code':
      return 'no-code';
    default: {
      const unreachable: never = r;
      throw new Error(`Unhandled verifyOtp status: ${JSON.stringify(unreachable)}`);
    }
  }
}
