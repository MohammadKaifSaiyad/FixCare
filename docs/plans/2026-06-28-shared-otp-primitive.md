# Shared OTP Primitive Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the three hand-rolled hashed-OTP-in-Redis copies with one audited, type-safe, single-use OTP store, refactoring both existing sites (arrival code, auth login) onto it behavior-preservingly.

**Architecture:** A new `shared/auth/otp-store.ts` composes the existing `otp.ts` (generate/hash) and `redis` client. It exposes `mintOtp<P>` (optional typed payload, optional send throttle) and `verifyOtp<P>` (tagged status union). `arrival-code.ts` and `auth.service.ts` become thin callers that map the union to their existing return types / HTTP statuses. No redis-value migration: the stored shape `{hash, attempts, payload?}` is a superset of both current shapes.

**Tech Stack:** Node 22, TypeScript strict (`noUncheckedIndexedAccess`), ioredis, Vitest (real redis via `flushTestRedis`), Zod (unchanged in callers).

## Global Constraints

- Money is integer paise — N/A here (no money), but no floats anywhere.
- No `any` — use `unknown`/generics and narrow. The payload is a generic `<P>`, never `any`.
- All async has explicit error handling; never swallow errors.
- Commit author MUST be `MohammadKaifSaiyad <saiyedkgn6@gmail.com>` with **NO** `Co-Authored-By`/Claude trailer (a commit-msg hook rejects it). Use `git -c user.name=... -c user.email=... commit`.
- Codes hashed at rest (SHA-256 via `hashOtp`); raw codes never stored or logged. Rule #7: store logs nothing.
- Behavior preservation is the contract: existing auth + arrival/handshake suites pass **unchanged**. Any edit to an existing test needs a one-line rationale comment.
- Run all backend commands from `apps/backend`. Docker stack (Postgres+PostGIS, Redis) must be up: `docker compose up -d` from repo root.

## Refinement vs the design doc (resolved during plan-writing)

The design flagged one open behavior question: arrival currently maps "attempts exhausted" → `no-code` (→409). Reading `tests/bookings/arrival-code.test.ts:20` confirms this is an **asserted** behavior (`verifyArrivalCode` returns `'no-code'` after 5 wrong attempts). To preserve it exactly **without** changing that test, the verify union gains a distinct `exhausted` status (instead of folding exhaustion into `invalid`). Each caller then decides:
- **arrival** maps `exhausted` → its existing `'no-code'` return (test stays green).
- **auth** maps `exhausted` (like `invalid` and `no-code`) → its generic 401.

Final union:

```ts
export type VerifyResult<P> =
  | { status: 'ok'; payload: P }
  | { status: 'invalid' }    // wrong code, key still alive (attempts incremented)
  | { status: 'exhausted' }  // attempts hit max → key deleted
  | { status: 'no-code' };   // missing/expired key
```

This is exact behavior preservation for both sites and removes the design's only ⚠ row.

## File Structure

- **Create** `src/shared/auth/otp-store.ts` — the primitive (`mintOtp`, `verifyOtp`, types). Composes `otp.ts` + `redis`. One responsibility: single-use OTP storage.
- **Create** `tests/shared/otp-store.test.ts` — unit tests against real redis.
- **Modify** `src/modules/bookings/arrival-code.ts` — becomes a thin wrapper; same exported signatures + return type `'ok'|'invalid'|'no-code'`.
- **Modify** `src/modules/auth/auth.service.ts` — `sendOtp`/`verifyOtp` call the primitive.
- **Keep unchanged** `src/shared/auth/otp.ts` (generate/hash — composed, not inlined).
- **Unchanged tests prove preservation:** `tests/bookings/arrival-code.test.ts`, `tests/technician-jobs/arrival.test.ts`, `tests/bookings/*handshake*`, `tests/auth/otp-send.test.ts`, `tests/auth/otp-verify.test.ts`.

---

### Task 1: The OTP store primitive (mint + verify + single-use + attempts)

**Files:**
- Create: `apps/backend/src/shared/auth/otp-store.ts`
- Test: `apps/backend/tests/shared/otp-store.test.ts`

**Interfaces:**
- Consumes: `redis` from `../redis/client.js`; `generateOtp`, `hashOtp` from `./otp.js`.
- Produces:
  - `interface OtpStoreConfig { ttlSeconds: number; maxAttempts: number; sendLimit?: { max: number; windowSeconds: number } }`
  - `type MintResult = { status: 'ok'; code: string } | { status: 'throttled' }`
  - `type VerifyResult<P> = { status: 'ok'; payload: P } | { status: 'invalid' } | { status: 'exhausted' } | { status: 'no-code' }`
  - `function mintOtp<P = undefined>(key: string, cfg: OtpStoreConfig, payload?: P): Promise<MintResult>`
  - `function verifyOtp<P = undefined>(key: string, code: string, cfg: { maxAttempts: number }): Promise<VerifyResult<P>>`

- [ ] **Step 1: Write the failing tests** (`apps/backend/tests/shared/otp-store.test.ts`)

```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { mintOtp, verifyOtp } from '../../src/shared/auth/otp-store.js';
import { redis } from '../../src/shared/redis/client.js';
import { flushTestRedis } from '../helpers/redis.js';

afterAll(() => redis.quit());
beforeEach(flushTestRedis);

const cfg = { ttlSeconds: 300, maxAttempts: 5 };

describe('otp-store', () => {
  it('mints a 6-digit code', async () => {
    const r = await mintOtp('k:1', cfg);
    expect(r.status).toBe('ok');
    if (r.status === 'ok') expect(r.code).toMatch(/^\d{6}$/);
  });

  it('verify ok consumes the code (single-use → no-code on second verify)', async () => {
    const r = await mintOtp('k:2', cfg);
    const code = r.status === 'ok' ? r.code : '';
    expect((await verifyOtp('k:2', code, cfg)).status).toBe('ok');
    expect((await verifyOtp('k:2', code, cfg)).status).toBe('no-code');
  });

  it('wrong code → invalid and key stays alive (TTL preserved)', async () => {
    await mintOtp('k:3', cfg);
    expect((await verifyOtp('k:3', '000000', cfg)).status).toBe('invalid');
    const ttl = await redis.ttl('k:3');
    expect(ttl).toBeGreaterThan(0);
    expect(ttl).toBeLessThanOrEqual(300);
  });

  it('after maxAttempts wrong tries → exhausted and the key is deleted', async () => {
    await mintOtp('k:4', cfg);
    for (let i = 0; i < 5; i++) expect((await verifyOtp('k:4', '000000', cfg)).status).toBe('invalid');
    expect((await verifyOtp('k:4', '000000', cfg)).status).toBe('exhausted');
    expect(await redis.get('k:4')).toBeNull();
  });

  it('verify before any mint → no-code', async () => {
    expect((await verifyOtp('k:5', '123456', cfg)).status).toBe('no-code');
  });

  it('returns a typed payload on success', async () => {
    await mintOtp<{ role: string }>('k:6', cfg, { role: 'CUSTOMER' });
    const code = await redis.get('k:6');
    const hash = JSON.parse(code!).hash as string;
    // verify with the real code path: re-mint deterministically is hard, so assert via a known code:
    // mint again with a payload and read it back through a correct verify.
    const m = await mintOtp<{ role: string }>('k:7', cfg, { role: 'TECHNICIAN' });
    const c = m.status === 'ok' ? m.code : '';
    const v = await verifyOtp<{ role: string }>('k:7', c, cfg);
    expect(v.status).toBe('ok');
    if (v.status === 'ok') expect(v.payload).toEqual({ role: 'TECHNICIAN' });
    expect(hash).toMatch(/^[a-f0-9]{64}$/);
  });

  it('send throttle: returns throttled after `max` mints in the window', async () => {
    const tcfg = { ttlSeconds: 300, maxAttempts: 5, sendLimit: { max: 3, windowSeconds: 900 } };
    expect((await mintOtp('k:8', tcfg)).status).toBe('ok');
    expect((await mintOtp('k:8', tcfg)).status).toBe('ok');
    expect((await mintOtp('k:8', tcfg)).status).toBe('ok');
    expect((await mintOtp('k:8', tcfg)).status).toBe('throttled');
  });

  it('no send throttle by default: many mints all succeed', async () => {
    for (let i = 0; i < 6; i++) expect((await mintOtp('k:9', cfg)).status).toBe('ok');
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd apps/backend && pnpm vitest run tests/shared/otp-store.test.ts`
Expected: FAIL — `Cannot find module '../../src/shared/auth/otp-store.js'`.

- [ ] **Step 3: Write the minimal implementation** (`apps/backend/src/shared/auth/otp-store.ts`)

```ts
import { redis } from '../redis/client.js';
import { generateOtp, hashOtp } from './otp.js';

export interface OtpStoreConfig {
  ttlSeconds: number;
  maxAttempts: number;
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

/** Verify `code` against `key`. Single-use: a correct code deletes the key. */
export async function verifyOtp<P = undefined>(
  key: string,
  code: string,
  cfg: { maxAttempts: number },
): Promise<VerifyResult<P>> {
  const raw = await redis.get(key);
  if (!raw) return { status: 'no-code' };

  const state = JSON.parse(raw) as StoredOtp;

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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd apps/backend && pnpm vitest run tests/shared/otp-store.test.ts`
Expected: PASS (8 tests).

- [ ] **Step 5: Typecheck**

Run: `cd apps/backend && pnpm tsc --noEmit`
Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add apps/backend/src/shared/auth/otp-store.ts apps/backend/tests/shared/otp-store.test.ts
git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" \
  commit -m "feat(backend): single-use OTP store primitive"
```

---

### Task 2: Refactor arrival-code onto the primitive (behavior-preserving)

**Files:**
- Modify: `apps/backend/src/modules/bookings/arrival-code.ts` (full rewrite as a wrapper)
- Unchanged tests prove preservation: `apps/backend/tests/bookings/arrival-code.test.ts`, `apps/backend/tests/technician-jobs/arrival.test.ts`, and any arrival-handshake test in `tests/bookings/`.

**Interfaces:**
- Consumes: `mintOtp`, `verifyOtp` from `../../shared/auth/otp-store.js`.
- Produces (unchanged public API — callers in `technician-jobs.service.ts:113` and `bookings.service.ts` rely on these exact signatures):
  - `function mintArrivalCode(bookingId: string): Promise<string>`
  - `type ArrivalVerifyResult = 'ok' | 'invalid' | 'no-code'`
  - `function verifyArrivalCode(bookingId: string, code: string): Promise<ArrivalVerifyResult>`

- [ ] **Step 1: Confirm the existing arrival tests currently pass (baseline GREEN before refactor)**

Run: `cd apps/backend && pnpm vitest run tests/bookings/arrival-code.test.ts`
Expected: PASS (3 tests). This is the behavior we must preserve — do not edit this test file.

- [ ] **Step 2: Rewrite the implementation as a thin wrapper** (`apps/backend/src/modules/bookings/arrival-code.ts`)

```ts
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
```

- [ ] **Step 3: Run the arrival unit tests + the technician arrival route tests**

Run: `cd apps/backend && pnpm vitest run tests/bookings/arrival-code.test.ts tests/technician-jobs/arrival.test.ts`
Expected: PASS, unchanged. In particular `arrival-code.test.ts:20` (exhausted → `'no-code'`) must still pass.

- [ ] **Step 4: Run the booking handshake tests (the verify→409/401 caller)**

Run: `cd apps/backend && pnpm vitest run tests/bookings`
Expected: PASS — the `verifyArrivalCode` → 401/409 mapping in `bookings.service.ts` is unaffected.

- [ ] **Step 5: Typecheck + commit**

Run: `cd apps/backend && pnpm tsc --noEmit` (expect no errors), then:

```bash
git add apps/backend/src/modules/bookings/arrival-code.ts
git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" \
  commit -m "refactor(backend): arrival code uses shared OTP store"
```

---

### Task 3: Refactor auth OTP (send + verify) onto the primitive (behavior-preserving)

**Files:**
- Modify: `apps/backend/src/modules/auth/auth.service.ts` (the `sendOtp` and `verifyOtp` functions, + remove the now-unused `otp.ts`/`rlKey` redis plumbing those two used directly)
- Unchanged tests prove preservation: `apps/backend/tests/auth/otp-send.test.ts`, `apps/backend/tests/auth/otp-verify.test.ts`.

**Interfaces:**
- Consumes: `mintOtp`, `verifyOtp` (aliased to avoid the name clash with the local `verifyOtp` export) from `../../shared/auth/otp-store.js`.
- Produces (unchanged public API): `sendOtp(body): Promise<SendOtpResult>`, `verifyOtp(body): Promise<AuthTokens>` — same signatures, same HTTP behavior.

- [ ] **Step 1: Confirm auth OTP tests pass as baseline (do not edit them)**

Run: `cd apps/backend && pnpm vitest run tests/auth/otp-send.test.ts tests/auth/otp-verify.test.ts`
Expected: PASS. This is the preservation target (incl. `otp-send.test.ts:30` rate-limit→429, `otp-send.test.ts:11` devOtp).

- [ ] **Step 2: Update the imports** at the top of `apps/backend/src/modules/auth/auth.service.ts`

Replace the line:
```ts
import { generateOtp, hashOtp } from '../../shared/auth/otp.js';
```
with:
```ts
import { mintOtp, verifyOtp as verifyOtpStore } from '../../shared/auth/otp-store.js';
```
And **delete** the two now-unused key helpers:
```ts
const otpKey = (phone: string) => `otp:${phone}`;
const rlKey = (phone: string) => `otp-rl:${phone}`;
```
Replace them with a single key helper (the throttle key is now derived inside the store as `${key}:rl`):
```ts
const otpKey = (phone: string) => `otp:${phone}`;
```
> Note: the send-throttle counter key changes from `otp-rl:<phone>` to `otp:<phone>:rl` (derived by the store). Ephemeral counter; no test asserts the literal key (verified: `otp-send.test.ts` asserts only the 429 status). Documented in the design doc.

- [ ] **Step 3: Rewrite `sendOtp`** to mint via the store with the throttle:

```ts
export async function sendOtp({ phone, role }: SendOtpBody): Promise<SendOtpResult> {
  const r = await mintOtp<{ role: UserRole }>(
    otpKey(phone),
    {
      ttlSeconds: config.OTP_TTL_SECONDS,
      maxAttempts: config.OTP_MAX_VERIFY_ATTEMPTS,
      sendLimit: { max: config.OTP_MAX_SENDS_PER_WINDOW, windowSeconds: config.OTP_SEND_WINDOW_SECONDS },
    },
    { role },
  );
  if (r.status === 'throttled') {
    throw new TooManyRequestsError('Too many OTP requests. Try again later.');
  }
  await otpSender.send(phone, r.code);
  return config.NODE_ENV === 'production' ? { ok: true } : { ok: true, devOtp: r.code };
}
```

- [ ] **Step 4: Rewrite the OTP-check portion of `verifyOtp`** (the redis block at the top; the user-creation transaction below is unchanged). Replace lines that `redis.get`/parse/attempt-check/del with:

```ts
export async function verifyOtp({ phone, otp }: VerifyOtpBody): Promise<AuthTokens> {
  const r = await verifyOtpStore<{ role: UserRole }>(otpKey(phone), otp, {
    maxAttempts: config.OTP_MAX_VERIFY_ATTEMPTS,
  });
  // Auth folds every failure mode into one generic 401 (no enumeration of why).
  if (r.status !== 'ok') throw new UnauthorizedError('Invalid or expired OTP');
  const { role } = r.payload;

  return prisma.$transaction(async (tx) => {
    const existing = await tx.user.findUnique({ where: { phone } });
    let user = existing;
    let isNew = false;
    if (!existing) {
      user = await createUserWithProfile(tx, phone, role);
      isNew = true;
    } else if (existing.status !== 'ACTIVE' || existing.deletedAt) {
      throw new ForbiddenError('Account is not active');
    }
    await tx.auditLog.create({
      data: { action: isNew ? 'USER_REGISTERED' : 'USER_LOGGED_IN', actorType: 'USER', actorId: user!.id },
    });
    const accessToken = signAccessToken(user!.id, user!.role);
    const { raw: refreshToken } = await issueRefreshToken(tx, user!.id);
    return { accessToken, refreshToken, user: toUserDto(user!) };
  });
}
```

> The unused `redis` import may now be removable from `auth.service.ts` IF no other function uses it. Check: `refreshTokens`/`logout`/`adminLogin` use `prisma`, not `redis`. If `redis` is no longer referenced, remove its import to satisfy `noUnusedLocals`. If tsc reports it unused, delete `import { redis } from '../../shared/redis/client.js';`.

- [ ] **Step 5: Run the auth OTP tests (preservation proof)**

Run: `cd apps/backend && pnpm vitest run tests/auth/otp-send.test.ts tests/auth/otp-verify.test.ts`
Expected: PASS, unchanged — devOtp present in non-prod, 429 after 3 sends, wrong/expired OTP → 401, single-use, role carried into registration.

- [ ] **Step 6: Typecheck + full auth suite**

Run: `cd apps/backend && pnpm tsc --noEmit && pnpm vitest run tests/auth`
Expected: no type errors; all auth tests pass.

- [ ] **Step 7: Commit**

```bash
git add apps/backend/src/modules/auth/auth.service.ts
git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" \
  commit -m "refactor(backend): auth OTP uses shared OTP store"
```

---

### Task 4: Full suite, docs, status/changelog

**Files:**
- Modify: `STATUS.md`, `CHANGELOG.md`
- Optionally: a one-line pointer comment in `otp.ts` is NOT needed (it stays a leaf helper).

- [ ] **Step 1: Run the entire backend test suite**

Run: `cd apps/backend && pnpm vitest run`
Expected: all tests pass (prior count 220 + the 8 new otp-store tests = 228; confirm the actual number printed).
> If a 429 rate-limit artifact appears from two request-heavy files in one process (known harness quirk, not a product bug — see memory), re-run the affected file alone to confirm green.

- [ ] **Step 2: Typecheck + lint the whole backend**

Run: `cd apps/backend && pnpm tsc --noEmit && pnpm lint`
Expected: clean.

- [ ] **Step 3: Update `STATUS.md`** — set active task to "Shared OTP primitive — done (228 tests)", note both existing OTP sites migrated, and that B5 completion OTP + B4a approve token now have a ready primitive (`shared/auth/otp-store.ts`). Move the "OTP primitive pre-B5" item out of the deferred backlog.

- [ ] **Step 4: Add a `CHANGELOG.md` entry** under today's date: "Extracted the hashed-OTP-in-Redis idiom into a single audited `otp-store` primitive (generic payload, tagged status union, opt-in send throttle); refactored arrival code + auth login onto it behavior-preservingly."

- [ ] **Step 5: Commit**

```bash
git add STATUS.md CHANGELOG.md
git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" \
  commit -m "docs: status + changelog for shared OTP primitive"
```

---

## Self-Review

**Spec coverage:**
- Decision 1 (migrate both sites) → Tasks 2 + 3. ✓
- Decision 2 (generic `<P>` payload) → Task 1 `mintOtp<P>`/`verifyOtp<P>`, exercised in Task 3 (`{role}`). ✓
- Decision 3 (tagged status union) → Task 1 `VerifyResult<P>`; refined to 4-arm union (added `exhausted`) to keep arrival's exhausted→`no-code` test green. ✓
- Decision 4 (opt-in send throttle) → Task 1 `sendLimit`, used in Task 3 (auth), omitted in Task 2 (arrival). ✓
- Decision 5 (placement + arrival-first sequencing) → file is `shared/auth/otp-store.ts`; Task 2 (arrival) precedes Task 3 (auth). ✓
- Behavior preservation → every refactor task runs the original test files unchanged as the proof. ✓
- Golden Rules (#2 single-impl, #5 audit stays in caller tx, #7 store logs nothing) → preserved; Task 3 keeps the audit writes inside the user-creation tx. ✓

**Placeholder scan:** No TBD/TODO; every code step shows full code; commands have expected output. ✓

**Type consistency:** `mintOtp`/`verifyOtp`/`OtpStoreConfig`/`MintResult`/`VerifyResult<P>` names identical across Tasks 1→3. Auth aliases the store's `verifyOtp` as `verifyOtpStore` to avoid clashing with its own exported `verifyOtp` — flagged explicitly in Task 3 Step 2. Arrival's `ArrivalVerifyResult` return type unchanged (`'ok'|'invalid'|'no-code'`), so its callers are untouched. ✓
