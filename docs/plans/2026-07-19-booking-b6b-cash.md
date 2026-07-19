# Booking B6b — Cash Payment Path Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The friction-added cash path: customer confirms the exact amount in-app and receives a receipt OTP; the technician enters it to capture the payment, incrementing their platform cash debt — gated by a flat ₹500 debt limit and a ₹3000/24h velocity cap.

**Architecture:** Mirrors the completion handshake (approach A of the design): the customer's initiation mints an OTP via `shared/auth/otp-store.ts`; the technician drives `PAYMENT_RECEIVED` with that code as the second party (Golden Rule 2). Debt lives as `Technician.cashDebtPaise` (balance column, incremented inside the capture transaction whose technician-row update doubles as the serializing lock). Cash reuses the B6a `Payment` attempt model; `razorpayOrderId` becomes nullable.

**Tech Stack:** Fastify 5 + Prisma 6 + Zod 4 + shared OTP store (Redis/Lua) + Vitest (`app.inject()`).

**Design:** `docs/designs/2026-07-19-booking-b6b-cash-design.md` — read it if a requirement here seems ambiguous.

## Global Constraints

- Money is integer paise; limits: `CASH_DEBT_LIMIT_PAISE` = **50000**, `CASH_VELOCITY_CAP_PAISE` = **300000**, window = **24h** (code constant).
- OTP: 6-digit, single-use, TTL **600s**, max **5** verify attempts, send throttle **3/900s** — via `shared/auth/otp-store.ts`, NEVER hand-rolled (memory rule).
- `ALLOWED_ACTORS.PAYMENT_RECEIVED` becomes `['SYSTEM', 'TECHNICIAN']` — the SYSTEM-only unit test is consciously updated, not deleted.
- All route inputs Zod-validated; DB writes in the service layer; every money mutation audited in-transaction (`PAYMENT_EVENT` events: `cash_initiated`, `cash_received`); no PII in audit metadata (ids + paise only).
- Errors: 404 foreign owner, 403 wrong role / not-assigned, 409 wrong state / already paid / no active code, 422 gates & zero-payable, 401 bad code, 429 mint throttle.
- Backend commands run from `apps/backend` with env sourced: `set -a && source .env && set +a && pnpm <cmd>`. Docker stack must be up.
- Commit author: `git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "..."` — NO Claude trailer (hook rejects it).
- Migrations apply to BOTH DBs: dev via `migrate dev`, test via `DATABASE_URL="$TEST_DATABASE_URL" pnpm prisma migrate deploy` (memory rule: test schema comes from migrations).

---

### Task 1: Schema (CASH + nullable order id + debt column) + config + actor gate

**Files:**
- Modify: `apps/backend/prisma/schema.prisma` (PaymentMethod enum ~line 395, Payment ~405-420, Technician ~83-95)
- Modify: `apps/backend/src/shared/config.ts:25` (add CASH keys after RAZORPAY block)
- Modify: `apps/backend/src/modules/bookings/bookings.state.ts:50` (PAYMENT_RECEIVED actors)
- Modify: `apps/backend/src/modules/bookings/bookings.service.ts:249-251` (nullable razorpayOrderId narrowing)
- Test: `apps/backend/tests/bookings/booking-state-unit.test.ts`

**Interfaces:**
- Consumes: existing `actorAllowedFor(to, kind)` from `bookings.state.ts`.
- Produces: `PaymentMethod.CASH`; `Payment.razorpayOrderId: string | null`; `Technician.cashDebtPaise: number`; `config.CASH_DEBT_LIMIT_PAISE` / `config.CASH_VELOCITY_CAP_PAISE` (numbers, paise). Tasks 2-3 rely on all of these.

- [ ] **Step 1: Edit the schema**

In `apps/backend/prisma/schema.prisma`:

```prisma
enum PaymentMethod {
  UPI
  CASH
}
```

In `model Payment`, change the order-id line (cash attempts have no gateway order; Postgres unique indexes allow multiple NULLs):

```prisma
  razorpayOrderId   String?       @unique // null for CASH attempts — only UPI rows carry a gateway order
```

In `model Technician`, add after `status`:

```prisma
  // Running cash-debt balance in integer paise. B6b increments on cash receipt (inside the capture
  // tx — the row update is also the lock serializing concurrent captures). B6c settlement decrements;
  // its ledger becomes the source of truth and this stays the cached balance. Never negative in B6b.
  cashDebtPaise Int @default(0)
```

- [ ] **Step 2: Migrate both DBs + regenerate client**

```bash
cd apps/backend && set -a && source .env && set +a && pnpm prisma migrate dev --name payment_cash
DATABASE_URL="$TEST_DATABASE_URL" pnpm prisma migrate deploy
```

Expected: one new migration `*_payment_cash` (ALTER TYPE add value, ALTER COLUMN drop not null, ADD COLUMN), applied cleanly to both `fixcare` and `fixcare_test`.

- [ ] **Step 3: Fix the one type break the nullable column causes**

`pnpm tsc --noEmit` now fails at `bookings.service.ts:250` (`existing.razorpayOrderId` is `string | null`). Replace lines 249-251:

```ts
  if (existing?.status === 'CREATED' && existing.razorpayOrderId) {
    return { orderId: existing.razorpayOrderId, amountPaise: existing.amountPaise, keyId: config.RAZORPAY_KEY_ID ?? null };
  }
```

(A UPI CREATED row always has an order id; the truthiness check narrows the type and defensively falls through to minting a fresh order if it ever didn't.) Run `set -a && source .env && set +a && pnpm tsc --noEmit` → clean.

- [ ] **Step 4: Add the cash config keys**

In `apps/backend/src/shared/config.ts`, after the `RAZORPAY_WEBHOOK_SECRET` line:

```ts
  // Cash path (B6b). Flat new-technician debt limit — becomes a computed trust-ladder value when
  // the trust module lands. Velocity cap is per-technician over a trailing 24h window.
  CASH_DEBT_LIMIT_PAISE: z.coerce.number().int().positive().default(50000),
  CASH_VELOCITY_CAP_PAISE: z.coerce.number().int().positive().default(300000),
```

- [ ] **Step 5: Write the failing actor-gate test**

In `apps/backend/tests/bookings/booking-state-unit.test.ts`, REPLACE the existing `'PAYMENT_RECEIVED is SYSTEM-only — no human actor (not even ADMIN) can mark money received'` test with:

```ts
  it('PAYMENT_RECEIVED: SYSTEM (UPI webhook) + TECHNICIAN (cash receipt, customer OTP = 2nd party) only', () => {
    // Golden Rule 2 both ways: the gateway's signed word OR the technician entering the code
    // minted to the customer. CUSTOMER and ADMIN can never mark money received.
    expect(actorAllowedFor('PAYMENT_RECEIVED', 'SYSTEM')).toBe(true);
    expect(actorAllowedFor('PAYMENT_RECEIVED', 'TECHNICIAN')).toBe(true);
    for (const kind of ['CUSTOMER', 'ADMIN'] as const) {
      expect(actorAllowedFor('PAYMENT_RECEIVED', kind)).toBe(false);
    }
  });
```

- [ ] **Step 6: Run it — expect FAIL**

Run: `set -a && source .env && set +a && pnpm vitest run tests/bookings/booking-state-unit.test.ts`
Expected: FAIL — `actorAllowedFor('PAYMENT_RECEIVED', 'TECHNICIAN')` returns false.

- [ ] **Step 7: Open the actor gate**

In `apps/backend/src/modules/bookings/bookings.state.ts:50` replace the PAYMENT_RECEIVED entry:

```ts
  PAYMENT_RECEIVED:      ['SYSTEM', 'TECHNICIAN'], // UPI: the gateway's signed capture (SYSTEM). Cash (B6b): the technician — but only with the receipt code minted to the CUSTOMER (Rule 2's second party).
```

- [ ] **Step 8: Run the suite slice — expect PASS**

Run: `set -a && source .env && set +a && pnpm vitest run tests/bookings/booking-state-unit.test.ts tests/bookings/payment.test.ts`
Expected: all pass (webhook SYSTEM path untouched).

- [ ] **Step 9: Commit**

```bash
git add -A && git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(backend): cash schema + config + PAYMENT_RECEIVED technician actor (B6b)"
```

---

### Task 2: Cash primitives + customer initiation (`POST /me/bookings/:id/pay-cash`)

**Files:**
- Create: `apps/backend/src/modules/bookings/cash.ts`
- Modify: `apps/backend/src/modules/bookings/bookings.service.ts` (widen /pay captured guard; add `initiateCashPayment` after `initiatePayment`)
- Modify: `apps/backend/src/modules/bookings/bookings.routes.ts` (route after `/pay`)
- Test: `apps/backend/tests/bookings/cash-payment.test.ts` (new file — own rate-limit window)

**Interfaces:**
- Consumes: `mintOtp`/`verifyOtp` (`shared/auth/otp-store.ts`), `chargeAmountFor`, `requireCustomer`, `otpSender`, `config`, errors.
- Produces (Task 3 relies on these exact signatures):
  - `mintCashReceiptCode(bookingId: string, payload: CashReceiptPayload): Promise<{status:'ok';code:string}|{status:'throttled'}>`
  - `verifyCashReceiptCode(bookingId: string, code: string): Promise<{status:'ok';payload:CashReceiptPayload}|{status:'invalid'}|{status:'no-code'}>`
  - `interface CashReceiptPayload { paymentId: string; amountPaise: number }`
  - `cashCollectedLast24hPaise(db, technicianId): Promise<number>` and `CASH_WINDOW_MS`
  - `initiateCashPayment(userId, id): Promise<{amountPaise:number; devOtp?:string}>`

- [ ] **Step 1: Write the failing tests**

Create `apps/backend/tests/bookings/cash-payment.test.ts`:

```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, makeTechnician, seedBookable } from './helpers.js';

// Own file = own rate-limit window (module convention). Payable states are direct-seeded — the
// keystone chain is proven in payment.test.ts; these tests target ONLY the cash initiation.

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
function future() { return new Date(Date.now() + 86_400_000).toISOString(); }

/** Direct-seed a cash-payable booking WITH an assigned technician (cash gates need one). */
async function cashReady(state: 'CUSTOMER_CONFIRMED' | 'DECLINED_BY_CUSTOMER' = 'CUSTOMER_CONFIRMED') {
  const c = await makeCustomer();
  const f = await seedBookable(c.customerId);
  const t = await makeTechnician(['AC']);
  const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
  await prisma.booking.update({
    where: { id: booking.id },
    data: { state, technicianId: t.technicianId, ...(state === 'DECLINED_BY_CUSTOMER' ? { declinedAt: new Date() } : {}) },
  });
  return { c, f, t, bookingId: booking.id as string };
}

/** Seed an already-CAPTURED cash payment for this technician (velocity-window fixture). */
async function seedCapturedCash(c: Awaited<ReturnType<typeof makeCustomer>>, f: Awaited<ReturnType<typeof seedBookable>>, technicianId: string, amountPaise: number, capturedAt: Date) {
  const b = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
  await prisma.booking.update({ where: { id: b.id }, data: { technicianId, state: 'PAYMENT_RECEIVED' } });
  await prisma.payment.create({ data: { bookingId: b.id, method: 'CASH', status: 'CAPTURED', amountPaise, capturedAt } });
}

describe('POST /me/bookings/:id/pay-cash', () => {
  it('mints the receipt OTP for the approved total + CASH attempt row + cash_initiated audit', async () => {
    const { c, bookingId } = await cashReady();
    const res = await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay-cash`, headers: auth(c.token) });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.amountPaise).toBe(45100); // 60000 − 14900, the invariant-locked approved total
    expect(body.devOtp).toMatch(/^\d{6}$/);
    const rows = await prisma.payment.findMany({ where: { bookingId } });
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ method: 'CASH', status: 'CREATED', amountPaise: 45100, razorpayOrderId: null });
    const audit = await prisma.auditLog.findFirst({ where: { action: 'PAYMENT_EVENT', metadata: { path: ['event'], equals: 'cash_initiated' } } });
    expect((audit!.metadata as { amountPaise: number }).amountPaise).toBe(45100);
  });

  it('a DECLINED booking initiates cash for exactly the locked visit fee', async () => {
    const { c, bookingId } = await cashReady('DECLINED_BY_CUSTOMER');
    const res = await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay-cash`, headers: auth(c.token) });
    expect(res.statusCode).toBe(200);
    expect(res.json().amountPaise).toBe(14900);
  });

  it('is idempotent on the attempt row: re-initiation re-mints the code but never duplicates the Payment', async () => {
    const { c, bookingId } = await cashReady();
    const first = (await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay-cash`, headers: auth(c.token) })).json();
    const second = (await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay-cash`, headers: auth(c.token) })).json();
    expect(second.devOtp).not.toBe(first.devOtp); // re-mint replaces the code (single active OTP)
    expect(await prisma.payment.count({ where: { bookingId } })).toBe(1);
  });

  it('throttles the mint: 4th request inside the window → 429', async () => {
    const { c, bookingId } = await cashReady();
    for (let i = 0; i < 3; i++) {
      expect((await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay-cash`, headers: auth(c.token) })).statusCode).toBe(200);
    }
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay-cash`, headers: auth(c.token) })).statusCode).toBe(429);
  });

  it('debt gate: 422 when debt + amount exceeds the ₹500 limit; exactly AT the limit passes', async () => {
    const { c, t, bookingId } = await cashReady();
    await prisma.technician.update({ where: { id: t.technicianId }, data: { cashDebtPaise: 20000 } }); // 20000+45100 > 50000
    const res = await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay-cash`, headers: auth(c.token) });
    expect(res.statusCode).toBe(422);
    expect(await prisma.payment.count({ where: { bookingId } })).toBe(0); // gate precedes the row
    await prisma.technician.update({ where: { id: t.technicianId }, data: { cashDebtPaise: 4900 } }); // 4900+45100 = 50000 exactly
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay-cash`, headers: auth(c.token) })).statusCode).toBe(200);
  });

  it('velocity gate: cash CAPTURED in the trailing 24h counts, older cash does not', async () => {
    const { c, f, t, bookingId } = await cashReady();
    await seedCapturedCash(c, f, t.technicianId, 270000, new Date(Date.now() - 23 * 3600_000)); // inside window: 270000+45100 > 300000
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay-cash`, headers: auth(c.token) })).statusCode).toBe(422);
    await prisma.payment.updateMany({ where: { amountPaise: 270000 }, data: { capturedAt: new Date(Date.now() - 25 * 3600_000) } }); // slide it out of the window
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay-cash`, headers: auth(c.token) })).statusCode).toBe(200);
  });

  it('guards: already-paid 409 (any method), foreign customer 404, technician role 403; /pay (UPI) also 409s on a cash-paid booking', async () => {
    const { c, t, bookingId } = await cashReady();
    const other = await makeCustomer();
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay-cash`, headers: auth(other.token) })).statusCode).toBe(404);
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay-cash`, headers: auth(t.token) })).statusCode).toBe(403);
    await prisma.payment.create({ data: { bookingId, method: 'CASH', status: 'CAPTURED', amountPaise: 45100, capturedAt: new Date() } });
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay-cash`, headers: auth(c.token) })).statusCode).toBe(409);
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay`, headers: auth(c.token) })).statusCode).toBe(409); // "already paid", not "not awaiting payment"
  });
});
```

- [ ] **Step 2: Run — expect FAIL**

Run: `set -a && source .env && set +a && pnpm vitest run tests/bookings/cash-payment.test.ts`
Expected: FAIL — route `/pay-cash` does not exist (404s).

- [ ] **Step 3: Create `apps/backend/src/modules/bookings/cash.ts`**

```ts
import type { Prisma, PrismaClient } from '@prisma/client';
import { mintOtp, verifyOtp } from '../../shared/auth/otp-store.js';

// Same knobs as the completion code (10-min TTL, 5 attempts, 3 sends / 15 min — real SMS spend).
const TTL_SECONDS = 600;
const MAX_ATTEMPTS = 5;
const SEND_LIMIT = { max: 3, windowSeconds: 900 };
const key = (bookingId: string) => `cash-receipt:${bookingId}`;

/** Pinned at initiation: the technician can only capture THIS attempt for THIS amount. */
export interface CashReceiptPayload { paymentId: string; amountPaise: number }

export type CashReceiptMint = { status: 'ok'; code: string } | { status: 'throttled' };

/** Mint the single-use cash receipt code to the CUSTOMER. A re-mint replaces any prior code. */
export async function mintCashReceiptCode(bookingId: string, payload: CashReceiptPayload): Promise<CashReceiptMint> {
  return mintOtp(key(bookingId), { ttlSeconds: TTL_SECONDS, sendLimit: SEND_LIMIT }, payload);
}

export type CashReceiptVerify =
  | { status: 'ok'; payload: CashReceiptPayload }
  | { status: 'invalid' }
  | { status: 'no-code' };

/** Verify (and on success consume) the receipt code. Folds like completion-code: exhausted →
 *  'invalid' (probed 5× = auth signal, 401; a fresh customer mint fixes it); 'no-code' covers
 *  never-minted AND expired (409 — the customer re-initiates). */
export async function verifyCashReceiptCode(bookingId: string, code: string): Promise<CashReceiptVerify> {
  const r = await verifyOtp<CashReceiptPayload>(key(bookingId), code, { maxAttempts: MAX_ATTEMPTS });
  switch (r.status) {
    case 'ok': {
      // Malformed payload must fail auth, not crash (the OTP-primitive review lesson).
      const p = r.payload;
      if (!p || typeof p.paymentId !== 'string' || typeof p.amountPaise !== 'number') return { status: 'invalid' };
      return { status: 'ok', payload: p };
    }
    case 'invalid':
    case 'exhausted':
      return { status: 'invalid' };
    case 'no-code':
      return { status: 'no-code' };
    default: {
      const unreachable: never = r;
      throw new Error(`Unhandled verifyOtp status: ${JSON.stringify(unreachable)}`);
    }
  }
}

export const CASH_WINDOW_MS = 24 * 60 * 60 * 1000;

/** Cash this technician CAPTURED in the trailing 24h (velocity-cap input). Works on the client
 *  (initiation UX check) or a tx (post-lock enforcement in the capture). */
export async function cashCollectedLast24hPaise(
  db: Prisma.TransactionClient | PrismaClient,
  technicianId: string,
): Promise<number> {
  const agg = await db.payment.aggregate({
    _sum: { amountPaise: true },
    where: { method: 'CASH', status: 'CAPTURED', capturedAt: { gt: new Date(Date.now() - CASH_WINDOW_MS) }, booking: { technicianId } },
  });
  return agg._sum.amountPaise ?? 0;
}
```

- [ ] **Step 4: Add `initiateCashPayment` to `bookings.service.ts`**

First widen the /pay guard (replace the `existing` block at the top of `initiatePayment` — lines 247-251):

```ts
  // Existing-attempt guards FIRST: once the booking is paid (either method), chargeAmountFor
  // would 409 with the wrong story ("not awaiting payment") — a stale retry must hear "already
  // paid". CAPTURED is method-agnostic: a cash-paid booking rejects /pay the same way.
  const captured = await prisma.payment.findFirst({ where: { bookingId: id, status: 'CAPTURED' } });
  if (captured) throw new ConflictError('This booking is already paid');
  const existing = await prisma.payment.findFirst({ where: { bookingId: id, method: 'UPI', status: 'CREATED' }, orderBy: { createdAt: 'desc' } });
  if (existing?.razorpayOrderId) {
    return { orderId: existing.razorpayOrderId, amountPaise: existing.amountPaise, keyId: config.RAZORPAY_KEY_ID ?? null };
  }
```

Then add after `initiatePayment` (imports to add at top: `mintCashReceiptCode`, `cashCollectedLast24hPaise` from `./cash.js`):

```ts
/** Customer confirms "I will pay ₹X cash" → gates checked → CASH attempt + receipt OTP minted to
 *  THEIR phone. The technician can only capture by hearing this code from the customer (Rule 2).
 *  Idempotent on the attempt row; each call re-mints (send-throttled 3/900s). */
export async function initiateCashPayment(userId: string, id: string): Promise<{ amountPaise: number; devOtp?: string }> {
  const { id: customerId } = await requireCustomer(userId);
  const booking = await prisma.booking.findFirst({
    where: { id, customerId, deletedAt: null },
    include: { bookingParts: true, customer: { include: { user: true } } },
  });
  if (!booking) throw new NotFoundError('Booking not found');

  const captured = await prisma.payment.findFirst({ where: { bookingId: id, status: 'CAPTURED' } });
  if (captured) throw new ConflictError('This booking is already paid');

  const amountPaise = chargeAmountFor(booking, booking.bookingParts); // 409s on non-payable states
  if (amountPaise === 0) throw new UnprocessableError('Nothing is payable for this booking');
  if (!booking.technicianId) throw new ConflictError('Booking is not awaiting payment'); // unreachable in payable states; narrows the type

  // UX-level gate checks — the ENFORCEMENT re-runs inside the capture tx post-lock (Task 3).
  const tech = await prisma.technician.findUniqueOrThrow({ where: { id: booking.technicianId }, select: { cashDebtPaise: true } });
  if (tech.cashDebtPaise + amountPaise > config.CASH_DEBT_LIMIT_PAISE) {
    throw new UnprocessableError('Cash limit reached for this technician — please pay by UPI');
  }
  if ((await cashCollectedLast24hPaise(prisma, booking.technicianId)) + amountPaise > config.CASH_VELOCITY_CAP_PAISE) {
    throw new UnprocessableError('Cash limit reached for this technician — please pay by UPI');
  }

  // Reuse the open CASH attempt (idempotent like /pay — double-taps never duplicate rows).
  const payment = await prisma.$transaction(async (tx) => {
    const open = await tx.payment.findFirst({ where: { bookingId: id, method: 'CASH', status: 'CREATED' } });
    if (open) return open;
    const row = await tx.payment.create({ data: { bookingId: id, method: 'CASH', amountPaise } });
    await tx.auditLog.create({
      data: { action: 'PAYMENT_EVENT', actorType: 'USER', actorId: userId, metadata: { bookingId: id, event: 'cash_initiated', amountPaise } },
    });
    return row;
  });

  const r = await mintCashReceiptCode(id, { paymentId: payment.id, amountPaise: payment.amountPaise });
  if (r.status === 'throttled') throw new TooManyRequestsError('Too many code requests. Try again later.');
  await otpSender.send(booking.customer.user.phone, r.code);
  return config.NODE_ENV === 'production'
    ? { amountPaise: payment.amountPaise }
    : { amountPaise: payment.amountPaise, devOtp: r.code };
}
```

- [ ] **Step 5: Add the route**

In `apps/backend/src/modules/bookings/bookings.routes.ts` after the `/pay` route (import `initiateCashPayment` alongside `initiatePayment`):

```ts
  app.post('/me/bookings/:id/pay-cash', { preHandler: [requireAuth] }, async (req, reply) => {
    requireCustomerRole(req);
    return reply.send(await initiateCashPayment(req.user!.id, (req.params as { id: string }).id));
  });
```

- [ ] **Step 6: Run — expect PASS**

Run: `set -a && source .env && set +a && pnpm vitest run tests/bookings/cash-payment.test.ts tests/bookings/payment.test.ts`
Expected: all pass (the widened /pay guard keeps every existing payment test green).

- [ ] **Step 7: Commit**

```bash
git add -A && git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(backend): cash initiation — gates + receipt OTP + CASH attempt (B6b)"
```

---

### Task 3: Technician receipt (`POST /technician/jobs/:id/confirm-cash`)

**Files:**
- Modify: `apps/backend/src/modules/technician-jobs/technician-jobs.schemas.ts` (body schema after `confirmCompletionBody`, ~line 53)
- Modify: `apps/backend/src/modules/technician-jobs/technician-jobs.service.ts` (add `confirmCashPayment` after `confirmCompletion`)
- Modify: `apps/backend/src/modules/technician-jobs/technician-jobs.routes.ts` (route after `/confirm-completion`)
- Test: `apps/backend/tests/bookings/cash-confirm.test.ts` (new file — own rate-limit window)

**Interfaces:**
- Consumes: `verifyCashReceiptCode` + `cashCollectedLast24hPaise` from `../bookings/cash.js`; `transitionBooking` from `../bookings/bookings.state.js`; existing `requireTechnician` / `ownAssignedBookingOrThrow`; `config`.
- Produces: `confirmCashPayment(userId, bookingId, body): Promise<{id: string; state: 'PAYMENT_RECEIVED'; cashDebtPaise: number}>` — `cashDebtPaise` is the post-capture running balance (core-flow: "technician sees running balance").

- [ ] **Step 1: Write the failing tests**

Create `apps/backend/tests/bookings/cash-confirm.test.ts`:

```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, makeTechnician, seedBookable } from './helpers.js';

// Own file = own rate-limit window. Payable states direct-seeded (chain proven in payment.test.ts).

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
function future() { return new Date(Date.now() + 86_400_000).toISOString(); }

async function cashReady(state: 'CUSTOMER_CONFIRMED' | 'DECLINED_BY_CUSTOMER' = 'CUSTOMER_CONFIRMED') {
  const c = await makeCustomer();
  const f = await seedBookable(c.customerId);
  const t = await makeTechnician(['AC']);
  const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
  await prisma.booking.update({
    where: { id: booking.id },
    data: { state, technicianId: t.technicianId, ...(state === 'DECLINED_BY_CUSTOMER' ? { declinedAt: new Date() } : {}) },
  });
  return { c, f, t, bookingId: booking.id as string };
}

async function initiate(token: string, bookingId: string) {
  const res = await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/pay-cash`, headers: auth(token) });
  expect(res.statusCode).toBe(200);
  return res.json() as { amountPaise: number; devOtp: string };
}
function wrongCode(devOtp: string) { return devOtp === '000000' ? '000001' : '000000'; }

describe('POST /technician/jobs/:id/confirm-cash', () => {
  it('captures the cash: Payment CAPTURED + debt increment + PAYMENT_RECEIVED (TECHNICIAN actor) + both audits', async () => {
    const { c, t, bookingId } = await cashReady();
    const { devOtp, amountPaise } = await initiate(c.token, bookingId);
    const res = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/confirm-cash`, headers: auth(t.token), payload: { code: devOtp } });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ id: bookingId, state: 'PAYMENT_RECEIVED', cashDebtPaise: 45100 });
    const payment = await prisma.payment.findFirst({ where: { bookingId } });
    expect(payment!.status).toBe('CAPTURED');
    expect(payment!.capturedAt).not.toBeNull();
    expect((await prisma.technician.findUnique({ where: { id: t.technicianId } }))!.cashDebtPaise).toBe(amountPaise);
    const transition = await prisma.auditLog.findFirst({ where: { action: 'BOOKING_STATE_CHANGED', metadata: { path: ['to'], equals: 'PAYMENT_RECEIVED' } } });
    expect((transition!.metadata as { method: string }).method).toBe('CASH');
    const received = await prisma.auditLog.findFirst({ where: { action: 'PAYMENT_EVENT', metadata: { path: ['event'], equals: 'cash_received' } } });
    expect((received!.metadata as { amountPaise: number }).amountPaise).toBe(amountPaise);
  });

  it('a DECLINED booking settles its visit fee in cash', async () => {
    const { c, t, bookingId } = await cashReady('DECLINED_BY_CUSTOMER');
    const { devOtp } = await initiate(c.token, bookingId);
    const res = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/confirm-cash`, headers: auth(t.token), payload: { code: devOtp } });
    expect(res.statusCode).toBe(200);
    expect(res.json().cashDebtPaise).toBe(14900);
    expect((await prisma.booking.findUnique({ where: { id: bookingId } }))!.state).toBe('PAYMENT_RECEIVED');
  });

  it('wrong code → 401, nothing changes; the right code still works after', async () => {
    const { c, t, bookingId } = await cashReady();
    const { devOtp } = await initiate(c.token, bookingId);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/confirm-cash`, headers: auth(t.token), payload: { code: wrongCode(devOtp) } })).statusCode).toBe(401);
    expect((await prisma.technician.findUnique({ where: { id: t.technicianId } }))!.cashDebtPaise).toBe(0);
    expect((await prisma.booking.findUnique({ where: { id: bookingId } }))!.state).toBe('CUSTOMER_CONFIRMED');
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/confirm-cash`, headers: auth(t.token), payload: { code: devOtp } })).statusCode).toBe(200);
  });

  it('no active code → 409; foreign technician → 403; customer role → 403; bad body → 400', async () => {
    const { c, t, bookingId } = await cashReady();
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/confirm-cash`, headers: auth(t.token), payload: { code: '123456' } })).statusCode).toBe(409);
    await initiate(c.token, bookingId);
    const stranger = await makeTechnician(['AC']);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/confirm-cash`, headers: auth(stranger.token), payload: { code: '123456' } })).statusCode).toBe(403);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/confirm-cash`, headers: auth(c.token), payload: { code: '123456' } })).statusCode).toBe(403);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/confirm-cash`, headers: auth(t.token), payload: { code: '12345' } })).statusCode).toBe(400);
  });

  it('booking already paid (late UPI capture won the race) → 409 and debt is UNCHANGED', async () => {
    const { c, t, bookingId } = await cashReady();
    const { devOtp } = await initiate(c.token, bookingId);
    await prisma.booking.update({ where: { id: bookingId }, data: { state: 'PAYMENT_RECEIVED' } }); // the UPI webhook landed first
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/confirm-cash`, headers: auth(t.token), payload: { code: devOtp } })).statusCode).toBe(409);
    expect((await prisma.technician.findUnique({ where: { id: t.technicianId } }))!.cashDebtPaise).toBe(0);
    expect((await prisma.payment.findFirst({ where: { bookingId } }))!.status).toBe('CREATED');
  });

  it('in-tx velocity re-check: cash captured AFTER initiation still blocks the capture, debt rolls back', async () => {
    const { c, f, t, bookingId } = await cashReady();
    const { devOtp } = await initiate(c.token, bookingId); // gates pass at initiation (0 collected)
    // Another ₹2700 cash capture lands between initiation and confirmation:
    const b2 = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
    await prisma.booking.update({ where: { id: b2.id }, data: { technicianId: t.technicianId, state: 'PAYMENT_RECEIVED' } });
    await prisma.payment.create({ data: { bookingId: b2.id, method: 'CASH', status: 'CAPTURED', amountPaise: 270000, capturedAt: new Date() } });
    const res = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/confirm-cash`, headers: auth(t.token), payload: { code: devOtp } });
    expect(res.statusCode).toBe(422); // 270000 + 45100 > 300000 — the ENFORCEMENT check, post-lock
    expect((await prisma.technician.findUnique({ where: { id: t.technicianId } }))!.cashDebtPaise).toBe(0); // increment rolled back
    expect((await prisma.payment.findFirst({ where: { bookingId } }))!.status).toBe('CREATED');
    expect((await prisma.booking.findUnique({ where: { id: bookingId } }))!.state).toBe('CUSTOMER_CONFIRMED');
  });
});
```

- [ ] **Step 2: Run — expect FAIL**

Run: `set -a && source .env && set +a && pnpm vitest run tests/bookings/cash-confirm.test.ts`
Expected: FAIL — route `/confirm-cash` does not exist.

- [ ] **Step 3: Add the body schema**

In `apps/backend/src/modules/technician-jobs/technician-jobs.schemas.ts` after `confirmCompletionBody`:

```ts
export const confirmCashBody = z.object({ code: z.string().length(6) }).strict();
export type ConfirmCashBody = z.infer<typeof confirmCashBody>;
```

- [ ] **Step 4: Add `confirmCashPayment` to `technician-jobs.service.ts`**

After `confirmCompletion`. Imports to add: `verifyCashReceiptCode`, `cashCollectedLast24hPaise` from `../bookings/cash.js`; `config` from `../../shared/config.js`; `ConfirmCashBody` type from the schemas import; `UnprocessableError` is already imported.

```ts
/** Cash receipt (B6b): CUSTOMER_CONFIRMED or DECLINED_BY_CUSTOMER → PAYMENT_RECEIVED. The
 *  technician drives the transition but ONLY with the receipt code minted to the customer's phone
 *  (Rule 2). The code is consumed BEFORE the tx (redis and Postgres can't share one) — if the tx
 *  rolls back the customer re-initiates; fails SAFE, never a false capture (completion idiom).
 *  Gates re-run INSIDE the tx: the debt increment locks the technician row first, so concurrent
 *  captures serialize and the checks read a settled world (initiation-time checks are only UX). */
export async function confirmCashPayment(userId: string, bookingId: string, body: ConfirmCashBody): Promise<{ id: string; state: 'PAYMENT_RECEIVED'; cashDebtPaise: number }> {
  const tech = await requireTechnician(userId);
  const booking = await ownAssignedBookingOrThrow(tech.id, bookingId, ['CUSTOMER_CONFIRMED', 'DECLINED_BY_CUSTOMER'] as const);
  const r = await verifyCashReceiptCode(bookingId, body.code);
  if (r.status === 'no-code') throw new ConflictError('No active code — ask the customer to start the cash payment');
  if (r.status === 'invalid') throw new UnauthorizedError('Invalid or expired cash receipt code');
  const { paymentId, amountPaise } = r.payload;

  const cashDebtPaise = await prisma.$transaction(async (tx) => {
    // Increment FIRST: the technician-row update is the lock serializing this technician's captures.
    const t = await tx.technician.update({
      where: { id: tech.id },
      data: { cashDebtPaise: { increment: amountPaise } },
      select: { cashDebtPaise: true },
    });
    if (t.cashDebtPaise > config.CASH_DEBT_LIMIT_PAISE) {
      throw new UnprocessableError('Cash limit reached — please pay by UPI');
    }
    if ((await cashCollectedLast24hPaise(tx, tech.id)) + amountPaise > config.CASH_VELOCITY_CAP_PAISE) {
      throw new UnprocessableError('Cash limit reached — please pay by UPI');
    }
    // Keyed on CREATED: a superseded/settled attempt can never capture twice.
    const updated = await tx.payment.updateMany({ where: { id: paymentId, status: 'CREATED' }, data: { status: 'CAPTURED', capturedAt: new Date() } });
    if (updated.count === 0) throw new ConflictError('This payment is no longer open');
    // Optimistic lock inside: a late UPI capture racing this rolls the WHOLE tx back — no debt.
    await transitionBooking(tx, booking, 'PAYMENT_RECEIVED', { type: 'USER', kind: 'TECHNICIAN', id: userId }, { method: 'CASH', amountPaise, codeConfirmed: true });
    await tx.auditLog.create({
      data: { action: 'PAYMENT_EVENT', actorType: 'USER', actorId: userId, metadata: { event: 'cash_received', bookingId, paymentId, amountPaise, technicianId: tech.id } },
    });
    return t.cashDebtPaise;
  });
  return { id: bookingId, state: 'PAYMENT_RECEIVED', cashDebtPaise };
}
```

- [ ] **Step 5: Add the route**

In `apps/backend/src/modules/technician-jobs/technician-jobs.routes.ts` after `/confirm-completion` (import `confirmCashPayment` and `confirmCashBody`):

```ts
  app.post('/technician/jobs/:id/confirm-cash', { preHandler: [requireAuth] }, async (req, reply) => {
    requireTechnicianRole(req);
    const p = confirmCashBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.send(await confirmCashPayment(req.user!.id, (req.params as { id: string }).id, p.data));
  });
```

- [ ] **Step 6: Run — expect PASS**

Run: `set -a && source .env && set +a && pnpm vitest run tests/bookings/cash-confirm.test.ts tests/bookings/cash-payment.test.ts`
Expected: all pass. Note the velocity re-check test exercises the amount-mismatch reasoning too: the payload pins `{paymentId, amountPaise}` at initiation, so the captured amount can never drift from what the customer confirmed.

- [ ] **Step 7: Commit**

```bash
git add -A && git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(backend): cash receipt capture — OTP-gated PAYMENT_RECEIVED + debt + in-tx gates (B6b)"
```

---

### Task 4: Full verification + docs

**Files:**
- Modify: `apps/backend/.env.example` (CASH keys)
- Modify: `STATUS.md`, `CHANGELOG.md`

- [ ] **Step 1: `.env.example`**

Add after the RAZORPAY block:

```bash
# Cash path (B6b) — optional, these are the defaults. Flat new-tech debt limit + 24h velocity cap.
# CASH_DEBT_LIMIT_PAISE=50000
# CASH_VELOCITY_CAP_PAISE=300000
```

- [ ] **Step 2: Full suite + typecheck**

```bash
cd apps/backend && set -a && source .env && set +a && pnpm tsc --noEmit && pnpm vitest run
```

Expected: 0 type errors; ALL tests pass (284 pre-existing + ~13 new).

- [ ] **Step 3: Update STATUS.md + CHANGELOG.md**

STATUS: Active task → B6b complete on branch (cash initiation + receipt capture + debt + gates); Next 3 → B6c first. CHANGELOG: new `## 2026-07-19` section (or extend) describing the cash path shipped (initiation gates, OTP handshake, TECHNICIAN actor, debt column, velocity cap, in-tx enforcement).

- [ ] **Step 4: Commit**

```bash
git add -A && git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "docs: STATUS/CHANGELOG + .env.example — B6b cash path complete"
```
