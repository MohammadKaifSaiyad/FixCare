# Shared OTP Primitive — Design

**Date:** 2026-06-28
**Branch:** `feature/shared-otp-primitive`
**Status:** Approved (brainstorming) → ready for `writing-plans`
**Author:** solo founder-dev (via Claude Code)

---

## Problem

The hashed-OTP-in-Redis idiom is now duplicated across three places, and B5 (completion
handshake) plus the deferred B4a approve/decline token will add two more. Each copy
re-implements the same security-sensitive logic — hash, attempt-cap, single-use delete —
by hand:

| Site | File | Key | TTL | Max verify attempts | Payload | Send throttle |
|---|---|---|---|---|---|---|
| Auth login | `auth.service.ts` | `otp:<phone>` | `config.OTP_TTL_SECONDS` | `config.OTP_MAX_VERIFY_ATTEMPTS` | `{role: UserRole}` | yes (`otp-rl:<phone>`) |
| Arrival code | `arrival-code.ts` | `arrival:<bookingId>` | 600s | 5 | none | no |
| (B5) completion | — not built — | `completion:<bookingId>` | tbd | tbd | none | no |

Five hand-rolled copies of single-use-OTP security is exactly the kind of surface where one
copy silently drifts (forgets the attempt-cap, forgets the single-use `del`) and becomes a
fraud hole against **Golden Rule #2** (no single party confirms a transaction alone — the OTP
*is* the second party's proof). One audited implementation removes that drift risk.

## Goal

One reusable, type-safe, single-use OTP store in `shared/`, with **both existing sites
refactored onto it behavior-preservingly** (proven by their existing test suites going green
unchanged), and ready to drop into B5 / B4a-approve with zero new crypto.

Non-goals: changing any HTTP status, any TTL/attempt value, any redis key name, the auth send
throttle's semantics, or the `devOtp` dev-only escape hatch. This is a **refactor**, not a
behavior change.

---

## Decisions (from brainstorming)

1. **Migration scope** — build the primitive AND refactor both `arrival-code.ts` and
   `auth.service.ts`'s OTP onto it. Exactly one implementation; no bespoke copy left.
2. **Payload typing** — generic `<P>`. `mintOtp<P>` stores a typed payload; `verifyOtp<P>`
   returns it on success. Type-safe per call site, no `any`/`as` leaking to callers.
3. **Verify contract** — tagged status union `{status:'ok', payload} | {status:'invalid'} |
   {status:'no-code'}`. Preserves the existing tri-state that `bookings.service.ts` maps to
   401 (invalid) vs 409 (no-code); auth keeps mapping both to its generic 401.
4. **Send throttle** — opt-in config on the primitive (`sendLimit?: {max, windowSeconds}`).
   Auth passes it; arrival/completion omit it. One throttle implementation, used where needed.
5. **Placement** — `src/shared/auth/otp-store.ts`, beside the kept `otp.ts` (generate/hash
   helpers, which it composes). Migrate **arrival-code first** (no payload, simplest), then
   **auth** (payload + throttle), each proven green by its existing tests.

---

## API

`src/shared/auth/otp-store.ts`:

```ts
export interface OtpStoreConfig {
  ttlSeconds: number;
  maxAttempts: number;
  /** Optional send-side throttle: at most `max` mints per `windowSeconds` for this key-stem. */
  sendLimit?: { max: number; windowSeconds: number };
}

export type MintResult =
  | { status: 'ok'; code: string }
  | { status: 'throttled' };

export type VerifyResult<P> =
  | { status: 'ok'; payload: P }
  | { status: 'invalid' }   // wrong code OR attempts exhausted → caller maps to 401
  | { status: 'no-code' };  // missing/expired key            → caller maps to 409 (or 401)

/** Mint a single-use 6-digit OTP under `key`, optionally with a typed payload and send throttle. */
export function mintOtp<P = undefined>(
  key: string,
  cfg: OtpStoreConfig,
  payload?: P,
): Promise<MintResult>;

/** Verify a code against `key`. Single-use: a correct code deletes the key. */
export function verifyOtp<P = undefined>(
  key: string,
  code: string,
  cfg: Pick<OtpStoreConfig, 'maxAttempts'>,
): Promise<VerifyResult<P>>;
```

### Stored value shape (redis)

```ts
// JSON at `key`, EX ttlSeconds:
{ hash: string; attempts: number; payload?: P }
```

Identical to today's three shapes — `arrival-code` stored `{hash, attempts}`; auth stored
`{hash, attempts, role}`. The generic `payload` slot unifies them: `payload` is `{role}` for
auth, absent for arrival. **No redis-value migration needed** — in-flight OTPs at deploy time
are short-lived (≤10min) and the JSON shape is a superset of both old shapes.

### Send throttle (when `sendLimit` is set)

Mirrors auth's current `otp-rl:` logic exactly, keyed off the OTP key with an `-rl` suffix:

```ts
// inside mintOtp, only if cfg.sendLimit:
const rl = `${key}:rl`;
const n = await redis.incr(rl);
if (n === 1) await redis.expire(rl, sendLimit.windowSeconds);
if (n > sendLimit.max) return { status: 'throttled' };
```

> Note: auth's current rl key is `otp-rl:<phone>`; the primitive derives `<otpKey>:rl` =
> `otp:<phone>:rl`. This is a **key-name change** for the throttle counter only (not the OTP
> itself). Acceptable: the counter is ephemeral (≤window seconds), affects no persisted data,
> and no test asserts the literal rl key string. Documented here so it isn't a silent drift.

### Verify semantics (preserved exactly from both sites)

1. `get(key)` → no value ⇒ `{status:'no-code'}`.
2. `attempts >= maxAttempts` ⇒ `del(key)`, return `{status:'invalid'}`.
   *(Auth currently treats exhausted-attempts as 401 — same as wrong code. Arrival treats it
   as `no-code`. To preserve BOTH, exhausted maps to `invalid`; arrival's caller maps
   `invalid`→401 and `no-code`→409, which keeps arrival's "exhausted → not 409" behavior. See
   "Behavior-preservation matrix" below — this is the one subtlety to verify with tests.)*
3. wrong hash ⇒ `set(key, {...state, attempts+1}, 'KEEPTTL')`, return `{status:'invalid'}`.
4. correct hash ⇒ `del(key)` (single-use), return `{status:'ok', payload}`.

---

## Behavior-preservation matrix (the refactor's contract)

| Scenario | Auth today | Arrival today | Primitive result | Auth caller maps | Arrival caller maps |
|---|---|---|---|---|---|
| no key / expired | 401 | `'no-code'` → 409 | `no-code` | 401 | 409 |
| wrong code | 401 (+attempts) | `'invalid'` → 401 | `invalid` | 401 | 401 |
| attempts exhausted | 401 (+del) | `'no-code'` → 409* | `invalid` (+del) | 401 | **401** ⚠ |
| correct code | tokens (+del) | `'ok'` (+del) | `ok` | tokens | proceed |

⚠ **One behavior change to confirm with the user is acceptable, or guard against:** arrival's
*current* code returns `'no-code'` when attempts are exhausted (mapping to 409), but the
primitive returns `invalid` (→401). This is arguably *more correct* (exhausted ≠ "never
existed"), but it is a change. **Mitigation:** check `verifyArrivalCode`'s existing tests — if
none assert the exhausted-→-`no-code` path, the change is invisible and we keep the cleaner
semantics. If a test asserts it, we either (a) update that test with a one-line rationale, or
(b) add an `exhaustedIsNoCode?: boolean` config flag. **Resolve during writing-plans by reading
the arrival tests first** (RED step will surface it).

All other rows are exact preservation.

---

## Migration plan (sequencing — detailed in the plan doc)

1. **Build `otp-store.ts`** + its own unit tests (mint/verify/single-use/attempts/throttle,
   against real redis via the existing test harness). RED→GREEN→REFACTOR.
2. **Refactor `arrival-code.ts`** to a thin wrapper over the primitive:
   `mintArrivalCode` → `mintOtp(arrival:<id>, {ttl:600, maxAttempts:5})`;
   `verifyArrivalCode` → `verifyOtp(...)` mapping `ok/invalid/no-code` to its existing
   `'ok'|'invalid'|'no-code'` return type. **Existing arrival/handshake tests must pass
   unchanged** (modulo the exhausted-attempts subtlety above).
3. **Refactor `auth.service.ts`** OTP send/verify onto the primitive:
   `sendOtp` → `mintOtp(otp:<phone>, {ttl, maxAttempts, sendLimit:{max:OTP_MAX_SENDS_PER_WINDOW,
   windowSeconds:OTP_SEND_WINDOW_SECONDS}}, {role})`, mapping `throttled` →
   `TooManyRequestsError` and returning `devOtp` from the minted code in non-prod;
   `verifyOtp` → `verifyOtp<{role}>(...)`, mapping `invalid|no-code` → its generic 401, then
   proceeding with `payload.role` into the existing user-creation tx. **All existing auth
   tests must pass unchanged.**
4. **Document** the primitive as the canonical OTP path; note B5/B4a-approve will call it.
   Keep `otp.ts` (generate/hash) — the primitive composes it; do not inline.

The `devOtp` escape hatch stays in the **auth caller** (it's auth-policy, not OTP-store
concern): `sendOtp` returns the code it just minted when `NODE_ENV !== 'production'`. The
primitive always returns the code on `mintOtp` success; the caller decides whether to expose it.

---

## Golden Rules / fraud check

- **Rule #2 (no single-party confirm):** the OTP is the second party's proof; centralizing it
  *reduces* the chance a future copy forgets the attempt-cap or single-use delete. Net safer.
- **Rule #5 (audit in tx):** unchanged — audit writes stay in the *callers'* transactions
  (auth's login audit, the handshake's state-change audit). The OTP store is presence-of-proof
  plumbing; it does not itself audit. This matches today.
- **Rule #7 (no PII in logs):** the store logs nothing; the payload (`{role}`) is not PII and
  is never logged. Codes are hashed at rest (SHA-256), never stored or logged raw.
- **fraud-defense #11 (geofence/arrival trace):** untouched — `arriveJob` still records GPS
  before minting; this refactor only changes how the code bytes are stored.

## Risks

- The exhausted-attempts semantics row (above) — resolved by reading arrival tests in the RED
  step. Low risk; bounded to one test at most.
- Throttle rl-key rename (`otp-rl:<phone>` → `otp:<phone>:rl`) — ephemeral counter, no test
  asserts the literal key. Documented, not silent.
- Concurrency: same optimistic single-read-then-write as today (no worse than current); a
  near-simultaneous double-verify race already exists in all three copies and is unchanged.

## Test strategy

- New `otp-store.test.ts`: mint returns 6-digit; verify ok deletes (second verify → no-code);
  wrong code → invalid + attempts increment + TTL preserved; exhausted → invalid + deleted;
  throttle returns `throttled` after `max` mints in window, resets after window.
- Existing `auth.*.test.ts` and arrival/handshake tests: **run unchanged** as the
  behavior-preservation proof. Any required edit gets a one-line rationale comment.
