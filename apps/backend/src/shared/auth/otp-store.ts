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

// One atomic script: throttle-increment (+TTL on first hit), limit check, OTP write. Previously
// these were 3 separate commands — a crash between them could burn a send slot (INCR landed, SET
// didn't) or leave a TTL-less counter (INCR landed, EXPIRE didn't) that throttled the key until a
// manual redis del. KEYS[1]=otp key, KEYS[2]=throttle counter; ARGV: json, ttl, max, window.
// max=0 means "no throttle configured" — skip the counter entirely.
const MINT_LUA = `
local max = tonumber(ARGV[3])
if max > 0 then
  local n = redis.call('INCR', KEYS[2])
  if n == 1 then redis.call('EXPIRE', KEYS[2], ARGV[4]) end
  if n > max then return 0 end
end
redis.call('SET', KEYS[1], ARGV[1], 'EX', ARGV[2])
return 1
`;

/** Mint a single-use 6-digit OTP under `key`. Optionally throttles minting and stores a typed payload. */
export async function mintOtp<P = undefined>(
  key: string,
  cfg: OtpStoreConfig,
  payload?: P,
): Promise<MintResult> {
  const code = generateOtp();
  const stored: StoredOtp = { hash: hashOtp(code), attempts: 0, payload };
  const ok = await redis.eval(
    MINT_LUA,
    2,
    key,
    rlKey(key),
    JSON.stringify(stored),
    String(cfg.ttlSeconds),
    String(cfg.sendLimit?.max ?? 0),
    String(cfg.sendLimit?.windowSeconds ?? 0),
  );
  return ok === 1 ? { status: 'ok', code } : { status: 'throttled' };
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
