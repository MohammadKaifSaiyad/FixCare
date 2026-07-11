import { redis } from '../redis/client.js';
import { generateOtp, hashOtp } from './otp.js';

export interface OtpStoreConfig {
  ttlSeconds: number;
  /** Optional send-side throttle: at most `max` mints per `windowSeconds` for this key. */
  sendLimit?: { max: number; windowSeconds: number };
}

export type MintResult = { status: 'ok'; code: string } | { status: 'throttled' };

export type VerifyResult<P> =
  | { status: 'ok'; payload: P }
  | { status: 'invalid' }
  | { status: 'exhausted' }
  | { status: 'no-code' };

interface StoredOtp {
  hash: string;
  attempts: number;
  payload?: unknown;
}

const rlKey = (key: string) => `${key}:rl`;

/** Mint a single-use 6-digit OTP under `key`. Optionally throttles minting and stores a typed payload. */
export async function mintOtp<P = undefined>(
  key: string,
  cfg: OtpStoreConfig,
  payload?: P,
): Promise<MintResult> {
  if (cfg.sendLimit) {
    const n = await redis.incr(rlKey(key));
    if (n === 1) await redis.expire(rlKey(key), cfg.sendLimit.windowSeconds);
    if (n > cfg.sendLimit.max) return { status: 'throttled' };
  }
  const code = generateOtp();
  const stored: StoredOtp = { hash: hashOtp(code), attempts: 0, payload };
  await redis.set(key, JSON.stringify(stored), 'EX', cfg.ttlSeconds);
  return { status: 'ok', code };
}

/** Verify `code` against `key`. Single-use: a correct code deletes the key.
 *  Note: `exhausted` also deletes the key, so a retry AFTER exhaustion reports `no-code`. */
export async function verifyOtp<P = undefined>(
  key: string,
  code: string,
  cfg: { maxAttempts: number },
): Promise<VerifyResult<P>> {
  const raw = await redis.get(key);
  if (!raw) return { status: 'no-code' };

  let state: StoredOtp;
  try {
    state = JSON.parse(raw) as StoredOtp;
  } catch {
    // Corrupt value (only this store writes these keys, so near-impossible): treat as
    // "no valid code" rather than throwing at a security boundary — fail safe, fail closed.
    await redis.del(key);
    return { status: 'no-code' };
  }

  if (state.attempts >= cfg.maxAttempts) {
    await redis.del(key);
    return { status: 'exhausted' };
  }
  if (hashOtp(code) !== state.hash) {
    await redis.set(key, JSON.stringify({ ...state, attempts: state.attempts + 1 }), 'KEEPTTL');
    return { status: 'invalid' };
  }
  await redis.del(key); // single-use
  return { status: 'ok', payload: state.payload as P };
}
