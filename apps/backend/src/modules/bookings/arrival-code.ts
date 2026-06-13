import { redis } from '../../shared/redis/client.js';
import { generateOtp, hashOtp } from '../../shared/auth/otp.js';

const TTL_SECONDS = 600; // 10 minutes
const MAX_ATTEMPTS = 5;
const key = (bookingId: string) => `arrival:${bookingId}`;

/** Mint a single-use 6-digit arrival code for a booking; store only its hash in Redis. Returns the
 *  raw code (shown to the technician once). A re-mint overwrites any existing code. */
export async function mintArrivalCode(bookingId: string): Promise<string> {
  const code = generateOtp();
  await redis.set(key(bookingId), JSON.stringify({ hash: hashOtp(code), attempts: 0 }), 'EX', TTL_SECONDS);
  return code;
}

export type ArrivalVerifyResult = 'ok' | 'invalid' | 'no-code';

/** Verify a code for a booking. 'no-code' = nothing minted / expired / attempts exhausted;
 *  'invalid' = wrong code (attempt counted); 'ok' = correct (code consumed, single-use). */
export async function verifyArrivalCode(bookingId: string, code: string): Promise<ArrivalVerifyResult> {
  const raw = await redis.get(key(bookingId));
  if (!raw) return 'no-code';
  const state = JSON.parse(raw) as { hash: string; attempts: number };
  if (state.attempts >= MAX_ATTEMPTS) {
    await redis.del(key(bookingId));
    return 'no-code';
  }
  if (hashOtp(code) !== state.hash) {
    await redis.set(key(bookingId), JSON.stringify({ ...state, attempts: state.attempts + 1 }), 'KEEPTTL');
    return 'invalid';
  }
  await redis.del(key(bookingId)); // single-use
  return 'ok';
}
