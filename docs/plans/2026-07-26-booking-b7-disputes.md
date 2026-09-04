# Booking B7 — Disputes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A customer raises a dispute on a paid-but-unclosed booking (holding the payout via the existing sweep filter); an admin adjudicates with an outcome + optional refund; the ledger credits the retained amount / writes a reversal and the booking closes.

**Architecture:** New `disputes` module owns the `Dispute` model, the customer raise endpoint, and the admin resolve/query endpoints. Raise flips PAYMENT_RECEIVED → DISPUTED (B6c's sweep already skips non-PAYMENT_RECEIVED → payout held for free). Resolve books the technician's share of the *retained* amount forward (the booking was never swept, so there is no EARNING_CREDIT to claw back) and refunds via the Razorpay refund API (UPI, confirmed by the now-real refund.* webhook) or a manual record (cash). Reuses B6c's `splitPaise` + auto-offset idiom.

**Tech Stack:** Fastify 5 + Prisma 6 + Zod 4 + Vitest; Razorpay wrapper (Dev stub).

**Design:** `docs/designs/2026-07-26-booking-b7-disputes-design.md`.

## Global Constraints

- Customer raises ONLY from `PAYMENT_RECEIVED`, ONLY within `DISPUTE_WINDOW_HOURS` (48, existing config), one OPEN dispute per booking (partial unique index backstops the race).
- The captured charge = the booking's CAPTURED `Payment.amountPaise` (NOT `chargeAmountFor` — that throws on DISPUTED). Read the CAPTURED payment row.
- Resolution ledger: retained = `base − refundPaise` where `base = declinedAt ? visitFeePaise : laborPaise`; `splitPaise(retained)` → EARNING_CREDIT + COMMISSION (skip zero-amount rows, B6c invariant); one DISPUTE_REVERSAL entry of `refundPaise` when refundPaise>0. Auto-offset cash debt against the earning (FOR-UPDATE-locked, B6c idiom). Money conserved: retained + refund == base.
- `refundPaise` rules: FAVOR_CUSTOMER → == charge; PARTIAL → 1 ≤ refundPaise < charge; FAVOR_TECHNICIAN → absent/0. Else 400. (`base` and `charge` differ only by the visit-fee credit; validate the refund against the CHARGE the customer paid.)
- Actor gates: `ALLOWED_ACTORS.DISPUTED = ['CUSTOMER']`; `CLOSED = ['SYSTEM','ADMIN']`.
- Integer paise; every money mutation audited in-tx (`DISPUTE_EVENT`); NO PII in audit metadata (never the `reason` text — ids/enums/paise only). `reason` Zod ≤ 500 chars.
- Backend commands from `apps/backend` with `set -a && source .env && set +a && pnpm <cmd>`; Docker up. Migrations to BOTH DBs (`migrate dev` + `DATABASE_URL="$TEST_DATABASE_URL" pnpm prisma migrate deploy`); partial unique index is raw SQL appended via `--create-only`.
- Commit author `git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "..."` — NO Claude trailer.
- New test files under `tests/disputes/` get their own app instance (rate-limit window convention).

---

### Task 1: Schema (Dispute + enums + actor gates) + config-free wiring

**Files:**
- Modify: `apps/backend/prisma/schema.prisma` (new Dispute model + 2 enums after LedgerEntry; `LedgerEntryType += DISPUTE_REVERSAL`; `AuditAction += DISPUTE_EVENT`; `Booking.disputes` + `Payment.razorpayRefundId`)
- Modify: `apps/backend/src/modules/bookings/bookings.state.ts` (ALLOWED_ACTORS DISPUTED + CLOSED)
- Modify: `apps/backend/tests/schema/helpers.ts` (TRUNCATE list)
- Test: `apps/backend/tests/bookings/booking-state-unit.test.ts`, `apps/backend/tests/disputes/schema.test.ts`

**Interfaces:**
- Produces: `Dispute` model + `DisputeStatus` (OPEN/RESOLVED) + `DisputeOutcome` (FAVOR_CUSTOMER/FAVOR_TECHNICIAN/PARTIAL); `LedgerEntryType.DISPUTE_REVERSAL`; `AuditAction.DISPUTE_EVENT`; `Payment.razorpayRefundId: string | null` (@unique, refund idempotency anchor); `ALLOWED_ACTORS.DISPUTED=['CUSTOMER']`, `CLOSED=['SYSTEM','ADMIN']`.

- [ ] **Step 1: Schema edits**

`AuditAction` enum, add after `SETTLEMENT_EVENT`: `DISPUTE_EVENT`.
`LedgerEntryType` enum, add after `DEBT_REPAYMENT`: `DISPUTE_REVERSAL`.
In `model Payment`, add after `razorpayPaymentId`:

```prisma
  razorpayRefundId  String?       @unique // set when a refund is confirmed by webhook — refund idempotency anchor
```

In `model Booking`, add to the relation block (near `payments`/`ledgerEntries`): `disputes Dispute[]`.

New models after `LedgerEntry`'s enum:

```prisma
model Dispute {
  id               String          @id @default(uuid())
  bookingId        String
  booking          Booking         @relation(fields: [bookingId], references: [id], onDelete: Restrict)
  raisedByUserId   String
  reason           String // customer free text (Zod-capped ≤ 500) — assumed non-PII; NEVER copied into audit metadata
  status           DisputeStatus   @default(OPEN)
  outcome          DisputeOutcome? // set at resolution
  refundPaise      Int? // customer refund at resolution; null/0 for FAVOR_TECHNICIAN
  resolvedByUserId String?
  resolvedAt       DateTime?
  createdAt        DateTime        @default(now())
  updatedAt        DateTime        @updatedAt

  @@index([bookingId])
  @@index([status]) // admin OPEN queue
}

enum DisputeStatus { OPEN RESOLVED }
enum DisputeOutcome { FAVOR_CUSTOMER FAVOR_TECHNICIAN PARTIAL }
```

- [ ] **Step 2: Migration (create-only, append the partial unique index, apply both DBs)**

```bash
cd apps/backend && set -a && source .env && set +a && pnpm prisma migrate dev --name dispute --create-only
```

Append to the generated `prisma/migrations/*_dispute/migration.sql`:

```sql
-- One OPEN dispute per booking — the DB backstops a double-raise race (partial unique index).
CREATE UNIQUE INDEX "Dispute_one_open_per_booking" ON "Dispute"("bookingId") WHERE status = 'OPEN';
```

Then:

```bash
pnpm prisma migrate dev
DATABASE_URL="$TEST_DATABASE_URL" pnpm prisma migrate deploy
```

- [ ] **Step 3: TRUNCATE list** — in `tests/schema/helpers.ts` add `"Dispute",` before `"LedgerEntry",`.

- [ ] **Step 4: Failing actor test** — in `tests/bookings/booking-state-unit.test.ts` add:

```ts
  it('DISPUTED is CUSTOMER-only; CLOSED allows SYSTEM (sweep) + ADMIN (dispute resolution)', () => {
    expect(actorAllowedFor('DISPUTED', 'CUSTOMER')).toBe(true);
    for (const k of ['TECHNICIAN', 'ADMIN', 'SYSTEM'] as const) expect(actorAllowedFor('DISPUTED', k)).toBe(false);
    expect(actorAllowedFor('CLOSED', 'SYSTEM')).toBe(true);
    expect(actorAllowedFor('CLOSED', 'ADMIN')).toBe(true);
    for (const k of ['CUSTOMER', 'TECHNICIAN'] as const) expect(actorAllowedFor('CLOSED', k)).toBe(false);
  });
```

Run `set -a && source .env && set +a && pnpm vitest run tests/bookings/booking-state-unit.test.ts` → FAIL (DISPUTED unmapped; CLOSED lacks ADMIN).

Note: an existing test (`CLOSED is SYSTEM-only`) asserts `actorAllowedFor('CLOSED','ADMIN')` is false — UPDATE that test to expect `true` now (B7 is the slice that adds the ADMIN dispute-close it anticipated), keeping the SYSTEM=true / CUSTOMER=false / TECHNICIAN=false assertions.

- [ ] **Step 5: Open the gates** — in `ALLOWED_ACTORS` (bookings.state.ts):

```ts
  DISPUTED:              ['CUSTOMER'], // B7: the customer raises within the 48h window
```

and change the CLOSED line:

```ts
  CLOSED:                ['SYSTEM', 'ADMIN'], // SYSTEM = settlement sweep (B6c); ADMIN = dispute resolution (B7)
```

Re-run both booking-state-unit tests → PASS.

- [ ] **Step 6: Schema smoke test** — create `tests/disputes/schema.test.ts`:

```ts
import { describe, expect, it, beforeEach } from 'vitest';
import { prisma, resetDb } from '../schema/helpers.js';
import { makeCustomer } from '../bookings/helpers.js';

beforeEach(async () => { await resetDb(); });

describe('dispute schema', () => {
  it('one OPEN dispute per booking (partial unique index); a RESOLVED one does not block a new OPEN', async () => {
    const c = await makeCustomer();
    const b = await prisma.booking.create({ data: { customerId: c.customerId, bookingNumber: `FC-${Date.now()}`, state: 'PAYMENT_RECEIVED', scheduledSlot: new Date(), serviceId: 's', serviceName: 'X', zoneId: 'z', zoneName: 'Z', addressId: 'a', laborPaise: 60000, visitFeePaise: 14900, laborTier: 'T2' } as never });
    await prisma.dispute.create({ data: { bookingId: b.id, raisedByUserId: c.userId, reason: 'first' } });
    await expect(prisma.dispute.create({ data: { bookingId: b.id, raisedByUserId: c.userId, reason: 'second' } })).rejects.toThrow();
    await prisma.dispute.updateMany({ where: { bookingId: b.id }, data: { status: 'RESOLVED' } });
    await expect(prisma.dispute.create({ data: { bookingId: b.id, raisedByUserId: c.userId, reason: 'third' } })).resolves.toBeTruthy();
  });
});
```

Note: if `booking.create` requires fields this literal omits, seed via the existing `seedBookable` + a POST like other tests do — adapt to the real Booking shape (read `tests/bookings/helpers.ts`). The assertion that matters: 2nd OPEN throws, post-RESOLVED a 3rd OPEN succeeds.

Run `pnpm vitest run tests/disputes/schema.test.ts tests/bookings/booking-state-unit.test.ts` + `pnpm tsc --noEmit` → green/clean.

- [ ] **Step 7: Commit**

```bash
git add -A && git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(backend): dispute schema — Dispute model, DISPUTE_REVERSAL/DISPUTE_EVENT, actor gates (B7)"
```

---

### Task 2: Raise dispute (`POST /me/bookings/:id/raise-dispute`)

**Files:**
- Create: `apps/backend/src/modules/disputes/disputes.service.ts`, `apps/backend/src/modules/disputes/disputes.schemas.ts`, `apps/backend/src/modules/disputes/disputes.routes.ts`
- Modify: `apps/backend/src/app.ts` (register)
- Test: `apps/backend/tests/disputes/raise.test.ts`

**Interfaces:**
- Consumes: `transitionBooking`, `requireCustomer` (bookings.service or its helper), `config.DISPUTE_WINDOW_HOURS`, errors.
- Produces: `raiseDispute(userId, bookingId, body: { reason: string }): Promise<{ id: string; state: 'DISPUTED' }>`; `raiseDisputeBody` Zod (`{ reason: z.string().min(1).max(500) }.strict()`); `registerDisputeRoutes(app)`.

- [ ] **Step 1: Failing tests** — create `tests/disputes/raise.test.ts`:

```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, makeTechnician, seedBookable } from '../bookings/helpers.js';
import { settleClosableBookings } from '../../src/modules/settlements/settlements.service.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
function future() { return new Date(Date.now() + 86_400_000).toISOString(); }

/** Direct-seed a PAYMENT_RECEIVED booking (paid `paidAgoMs` ago, default 1h) with a captured UPI payment. */
async function paid(opts?: { paidAgoMs?: number }) {
  const c = await makeCustomer();
  const f = await seedBookable(c.customerId);
  const t = await makeTechnician(['AC']);
  const b = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
  await prisma.booking.update({ where: { id: b.id }, data: { state: 'PAYMENT_RECEIVED', technicianId: t.technicianId, paidAt: new Date(Date.now() - (opts?.paidAgoMs ?? 3600_000)) } });
  await prisma.payment.create({ data: { bookingId: b.id, method: 'UPI', status: 'CAPTURED', amountPaise: 45100, capturedAt: new Date(), razorpayOrderId: `order_dev_${Math.random().toString(36).slice(2, 8)}`, razorpayPaymentId: `pay_dev_${Math.random().toString(36).slice(2, 8)}` } });
  return { c, t, bookingId: b.id as string };
}

describe('POST /me/bookings/:id/raise-dispute', () => {
  it('raises: booking → DISPUTED + Dispute OPEN + audit; the sweep then SKIPS it (payout held)', async () => {
    const { c, bookingId } = await paid({ paidAgoMs: 49 * 3600_000 }); // old enough that the sweep WOULD close it if not disputed
    const res = await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/raise-dispute`, headers: auth(c.token), payload: { reason: 'AC still not cooling' } });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ id: bookingId, state: 'DISPUTED' });
    expect((await prisma.booking.findUnique({ where: { id: bookingId } }))!.state).toBe('DISPUTED');
    const d = await prisma.dispute.findFirst({ where: { bookingId } });
    expect(d).toMatchObject({ status: 'OPEN', reason: 'AC still not cooling' });
    expect(await prisma.auditLog.count({ where: { action: 'DISPUTE_EVENT', metadata: { path: ['event'], equals: 'raised' } } })).toBe(1);
    // payout held: the sweep only closes PAYMENT_RECEIVED
    const r = await settleClosableBookings();
    expect(r.closed).toBe(0);
    expect((await prisma.booking.findUnique({ where: { id: bookingId } }))!.state).toBe('DISPUTED');
    expect(await prisma.ledgerEntry.count({ where: { bookingId } })).toBe(0); // no earning credited
  });

  it('window boundary: within 48h raises; past 48h → 409', async () => {
    const inWindow = await paid({ paidAgoMs: 47 * 3600_000 });
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${inWindow.bookingId}/raise-dispute`, headers: auth(inWindow.c.token), payload: { reason: 'x' } })).statusCode).toBe(200);
    const past = await paid({ paidAgoMs: 49 * 3600_000 });
    // simulate the sweep already closed it OR just past window — here past-window on a still-PAYMENT_RECEIVED row
    await prisma.booking.update({ where: { id: past.bookingId }, data: { paidAt: new Date(Date.now() - 49 * 3600_000) } });
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${past.bookingId}/raise-dispute`, headers: auth(past.c.token), payload: { reason: 'x' } })).statusCode).toBe(409);
  });

  it('guards: double-raise 409 (unique), non-owner 404, technician role 403, wrong state (CLOSED) 409, bad body 400', async () => {
    const { c, t, bookingId } = await paid();
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/raise-dispute`, headers: auth(c.token), payload: { reason: 'first' } })).statusCode).toBe(200);
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/raise-dispute`, headers: auth(c.token), payload: { reason: 'again' } })).statusCode).toBe(409);
    const other = await makeCustomer();
    const fresh = await paid();
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${fresh.bookingId}/raise-dispute`, headers: auth(other.token), payload: { reason: 'x' } })).statusCode).toBe(404);
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${fresh.bookingId}/raise-dispute`, headers: auth(t.token), payload: { reason: 'x' } })).statusCode).toBe(403);
    await prisma.booking.update({ where: { id: fresh.bookingId }, data: { state: 'CLOSED' } });
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${fresh.bookingId}/raise-dispute`, headers: auth(fresh.c.token), payload: { reason: 'x' } })).statusCode).toBe(409);
    const ok = await paid();
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${ok.bookingId}/raise-dispute`, headers: auth(ok.c.token), payload: { reason: '' } })).statusCode).toBe(400);
  });
});
```

Run → FAIL (route missing).

- [ ] **Step 2: Schema** — `disputes.schemas.ts`:

```ts
import { z } from 'zod';
export const raiseDisputeBody = z.object({ reason: z.string().min(1).max(500) }).strict();
export type RaiseDisputeBody = z.infer<typeof raiseDisputeBody>;
```

- [ ] **Step 3: Service** — `disputes.service.ts` (import `requireCustomer` from bookings.service.js if exported; else replicate the customer lookup used by other `/me/bookings` handlers — read `bookings.service.ts` for the exact helper):

```ts
import { prisma } from '../../shared/database/prisma.js';
import { config } from '../../shared/config.js';
import { NotFoundError, ConflictError } from '../../shared/errors.js';
import { requireCustomer } from '../bookings/bookings.service.js';
import { transitionBooking } from '../bookings/bookings.state.js';
import type { RaiseDisputeBody } from './disputes.schemas.js';

/** Customer raises a dispute on a paid booking within the 48h window → PAYMENT_RECEIVED → DISPUTED.
 *  The B6c sweep only closes PAYMENT_RECEIVED, so a DISPUTED booking's payout is held automatically. */
export async function raiseDispute(userId: string, bookingId: string, body: RaiseDisputeBody): Promise<{ id: string; state: 'DISPUTED' }> {
  const { id: customerId } = await requireCustomer(userId);
  const booking = await prisma.booking.findFirst({ where: { id: bookingId, customerId, deletedAt: null } });
  if (!booking) throw new NotFoundError('Booking not found');
  if (booking.state !== 'PAYMENT_RECEIVED') throw new ConflictError('This booking cannot be disputed');
  if (!booking.paidAt || booking.paidAt.getTime() <= Date.now() - config.DISPUTE_WINDOW_HOURS * 3600_000) {
    throw new ConflictError('The dispute window has passed');
  }
  const open = await prisma.dispute.findFirst({ where: { bookingId, status: 'OPEN' } });
  if (open) throw new ConflictError('A dispute is already open for this booking');
  await prisma.$transaction(async (tx) => {
    // The partial unique index is the real race backstop; a concurrent raise throws here → ConflictError below.
    const dispute = await tx.dispute.create({ data: { bookingId, raisedByUserId: userId, reason: body.reason } });
    await transitionBooking(tx, booking, 'DISPUTED', { type: 'USER', kind: 'CUSTOMER', id: userId }, { disputed: true });
    await tx.auditLog.create({ data: { action: 'DISPUTE_EVENT', actorType: 'USER', actorId: userId, metadata: { event: 'raised', bookingId, disputeId: dispute.id } } });
  }).catch((e) => {
    // Unique-index violation on a concurrent double-raise → 409, not a 500.
    if (e instanceof Error && /Dispute_one_open_per_booking|unique/i.test(e.message)) throw new ConflictError('A dispute is already open for this booking');
    throw e;
  });
  return { id: bookingId, state: 'DISPUTED' };
}
```

If `requireCustomer` is not exported from bookings.service.ts, export it there (add `export`) — check first; it is used by initiatePayment etc.

- [ ] **Step 4: Route** — `disputes.routes.ts`:

```ts
import type { FastifyInstance } from 'fastify';
import { requireAuth } from '../../shared/middleware/auth.js';
import { requireCustomerRole } from '../../shared/middleware/roles.js'; // match the actual helper used in bookings.routes.ts
import { ValidationError } from '../../shared/errors.js';
import { raiseDisputeBody } from './disputes.schemas.js';
import { raiseDispute } from './disputes.service.js';

export async function registerDisputeRoutes(app: FastifyInstance): Promise<void> {
  app.post('/me/bookings/:id/raise-dispute', { preHandler: [requireAuth] }, async (req, reply) => {
    requireCustomerRole(req);
    const p = raiseDisputeBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.send(await raiseDispute(req.user!.id, (req.params as { id: string }).id, p.data));
  });
}
```

Read `bookings.routes.ts` for the EXACT import of `requireCustomerRole` / `requireAuth` / `ValidationError` and match them.

- [ ] **Step 5: Register** in `src/app.ts` after `registerSettlementRoutes(app)`: `await registerDisputeRoutes(app);` (+ import).

- [ ] **Step 6: Run** `pnpm vitest run tests/disputes/` + `pnpm tsc --noEmit` → green/clean.

- [ ] **Step 7: Commit**

```bash
git add -A && git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(backend): raise-dispute endpoint — PAYMENT_RECEIVED → DISPUTED, payout held (B7)"
```

---

### Task 3: Gateway refund method + real refund.* webhook handler

**Files:**
- Modify: `apps/backend/src/shared/third-party/razorpay.ts` (interface + Dev stub + real impl)
- Modify: `apps/backend/src/modules/payments/webhook.service.ts` (refund.processed/failed handling)
- Test: `apps/backend/tests/disputes/refund-webhook.test.ts`

**Interfaces:**
- Produces: `PaymentGateway.refund(paymentId: string, amountPaise: number): Promise<{ refundId: string }>`; DevPaymentGateway deterministic `rfnd_dev_*`; the webhook records a confirmed refund (`Payment.razorpayRefundId` set, `DISPUTE_REVERSAL` ledger entry written, `refund_recorded` audit) idempotently.

- [ ] **Step 1: Failing test** — create `tests/disputes/refund-webhook.test.ts` (own app instance; drive the webhook the way `payment.test.ts` does — reuse its `postWebhook` + `gw.signPayload` pattern). Assert: a `refund.processed` event for a booking's captured payment sets `razorpayRefundId`, writes a `DISPUTE_REVERSAL` ledger entry of the refund amount, writes a `refund_recorded` DISPUTE_EVENT audit, and a redelivery is a no-op (idempotent on refundId). Model the refund entity on Razorpay's shape: `{ event: 'refund.processed', payload: { refund: { entity: { id, payment_id, amount, notes } } } }`. Seed a CAPTURED payment + an OPEN/RESOLVED dispute for the booking so the handler can link refund → booking → technician for the reversal entry.

(Write the full test literal following payment.test.ts's webhook helpers; the assertions above are the contract.)

Run → FAIL (refund.* is still the ignore skeleton).

- [ ] **Step 2: Gateway interface + impls** — in `razorpay.ts`, add to `PaymentGateway`:

```ts
  /** Refund a captured payment (full or partial), amountPaise. Returns the gateway refund id. */
  refund(paymentId: string, amountPaise: number): Promise<{ refundId: string }>;
```

DevPaymentGateway:

```ts
  async refund(_paymentId: string, _amountPaise: number): Promise<{ refundId: string }> {
    return { refundId: `rfnd_dev_${randomUUID().slice(0, 12)}` };
  }
```

RazorpayGateway:

```ts
  async refund(paymentId: string, amountPaise: number): Promise<{ refundId: string }> {
    const { client } = this.rz();
    try {
      const r = await client.payments.refund(paymentId, { amount: amountPaise });
      return { refundId: r.id };
    } catch { throw new Error('Razorpay refund failed'); }
  }
```

- [ ] **Step 3: Webhook refund handler** — replace the `refund.*` ignore skeleton in `webhook.service.ts`. Add a refund entity schema (`{ id, payment_id, amount, notes? }`), and on `refund.processed` with a valid entity: find the Payment by `razorpayPaymentId = entity.payment_id`; if not found → audit `unknown_refund` + return (always-ACK). If `Payment.razorpayRefundId` already set → return (idempotent). Else, in one tx: set `Payment.razorpayRefundId = entity.id`; write a `DISPUTE_REVERSAL` ledger entry (`technicianId` from the booking, `bookingId`, `amountPaise = entity.amount`); audit `DISPUTE_EVENT { event: 'refund_recorded', bookingId, refundId, amountPaise }`. `refund.failed` → audit `refund_failed` flag (ops follows up), no ledger change. Keep the always-ACK contract; keep the existing `ignored` branch for genuinely unknown events.

(Full code: mirror the `payment.captured` handler's structure — schema-validate the entity, findUnique, idempotency guard, one tx with ledger + audit.)

- [ ] **Step 4: Run** `pnpm vitest run tests/disputes/refund-webhook.test.ts tests/bookings/payment.test.ts` → all pass (existing webhook tests unaffected — the refund branch is new; capture/failed untouched).

- [ ] **Step 5: Commit**

```bash
git add -A && git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(backend): gateway refund method + real refund.* webhook (records reversal, idempotent) (B7)"
```

---

### Task 4: Resolve dispute (`POST /admin/disputes/:id/resolve`) + admin queries

**Files:**
- Modify: `apps/backend/src/modules/disputes/disputes.service.ts` (add resolve + queries), `disputes.schemas.ts` (resolve body), `disputes.routes.ts` (admin routes)
- Test: `apps/backend/tests/disputes/resolve.test.ts`

**Interfaces:**
- Consumes: `splitPaise` from `../settlements/settlements.service.js`; `paymentGateway` from `../../shared/third-party/razorpay.js`; `transitionBooking`; `requireAdminLevel('MANAGER')`.
- Produces: `resolveDispute(adminUserId, disputeId, body): Promise<{ id: string; state: 'CLOSED'; outcome; refundPaise }>`; `getDispute(id)`; `listDisputes(status?)`; `resolveDisputeBody` Zod (`{ outcome: enum, refundPaise: z.number().int().nonnegative().optional(), reason: z.string().min(1).max(500) }`).

- [ ] **Step 1: Failing tests** — create `tests/disputes/resolve.test.ts`. Cover, with the captured charge = 45100 (labor 60000 − visitFee 14900) and base = laborPaise 60000:
  - **FAVOR_TECHNICIAN** (refund 0): retained = base 60000 → EARNING_CREDIT floor(60000×0.8)=48000 + COMMISSION 12000, NO DISPUTE_REVERSAL, booking CLOSED, no gateway.refund call.
  - **FAVOR_CUSTOMER** (refund == charge 45100): retained = base − 45100 = 14900 → EARNING_CREDIT 11920 + COMMISSION 2980 (the visit-fee slice the tech keeps) + DISPUTE_REVERSAL 45100; gateway.refund called for the UPI payment (assert via the Payment.razorpayRefundId being set after simulating the refund.processed webhook, OR assert the service returns and a refund was initiated — the dev stub's refund is synchronous, so assert a DISPUTE_EVENT 'refund_initiated' audit). CLOSED.
  - **PARTIAL** (refund 20000): retained = 60000 − 20000 = 40000 → split 32000/8000 + DISPUTE_REVERSAL 20000. Money conserved: retained(40000) + refund(20000) = base(60000). CLOSED.
  - Validation: refund > charge → 400; refund on FAVOR_TECHNICIAN → 400; missing refund on PARTIAL → 400; resolve already-RESOLVED → 409; non-MANAGER (technician token) → 403.
  - **cash** booking resolve: no gateway.refund, a manual `refund_recorded` audit, DISPUTE_REVERSAL still written.
  - `GET /admin/disputes/:id` returns the case file; `GET /admin/disputes?status=OPEN` lists open ones.

  Seed each via a DISPUTED booking (paid UPI or cash captured, an OPEN Dispute). Decide the "charge" the customer paid = the CAPTURED Payment.amountPaise for that booking; refund validation is against THAT.

Run → FAIL.

- [ ] **Step 2: Resolve body schema** — add to `disputes.schemas.ts`:

```ts
export const resolveDisputeBody = z.object({
  outcome: z.enum(['FAVOR_CUSTOMER', 'FAVOR_TECHNICIAN', 'PARTIAL']),
  refundPaise: z.number().int().nonnegative().optional(),
  reason: z.string().min(1).max(500),
}).strict();
export type ResolveDisputeBody = z.infer<typeof resolveDisputeBody>;
```

- [ ] **Step 3: resolveDispute service** — add to `disputes.service.ts`. The shape:

```ts
export async function resolveDispute(adminUserId: string, disputeId: string, body: ResolveDisputeBody): Promise<{ id: string; state: 'CLOSED'; outcome: string; refundPaise: number }> {
  const dispute = await prisma.dispute.findUnique({ where: { id: disputeId }, include: { booking: true } });
  if (!dispute) throw new NotFoundError('Dispute not found');
  if (dispute.status !== 'OPEN') throw new ConflictError('Dispute is already resolved');
  const booking = dispute.booking;
  const captured = await prisma.payment.findFirst({ where: { bookingId: booking.id, status: 'CAPTURED' } });
  if (!captured) throw new ConflictError('No captured payment for this booking');
  const charge = captured.amountPaise;

  // Validate refund against the outcome + the real captured charge.
  const refundPaise = body.refundPaise ?? 0;
  if (body.outcome === 'FAVOR_TECHNICIAN' && refundPaise !== 0) throw new UnprocessableError('FAVOR_TECHNICIAN takes no refund');
  if (body.outcome === 'FAVOR_CUSTOMER' && refundPaise !== charge) throw new UnprocessableError('FAVOR_CUSTOMER refunds the full charge');
  if (body.outcome === 'PARTIAL' && !(refundPaise >= 1 && refundPaise < charge)) throw new UnprocessableError('PARTIAL refund must be between 1 and the charge');

  const base = booking.declinedAt != null ? booking.visitFeePaise : booking.laborPaise;
  const retained = Math.max(0, base - refundPaise);
  const { earningPaise, commissionPaise } = splitPaise(retained);

  // Refund the money BEFORE the tx for UPI (like createOrder in B6a): a gateway failure must not
  // leave a half-closed dispute. Cash → manual record, no gateway call.
  let refundId: string | null = null;
  if (refundPaise > 0 && captured.method === 'UPI' && captured.razorpayPaymentId) {
    refundId = (await paymentGateway.refund(captured.razorpayPaymentId, refundPaise)).refundId;
  }

  await prisma.$transaction(async (tx) => {
    await tx.dispute.update({ where: { id: disputeId }, data: { status: 'RESOLVED', outcome: body.outcome, refundPaise, resolvedByUserId: adminUserId, resolvedAt: new Date() } });
    if (earningPaise > 0) await tx.ledgerEntry.create({ data: { technicianId: booking.technicianId!, bookingId: booking.id, type: 'EARNING_CREDIT', amountPaise: earningPaise, metadata: { source: 'dispute', outcome: body.outcome } } });
    if (commissionPaise > 0) await tx.ledgerEntry.create({ data: { technicianId: booking.technicianId!, bookingId: booking.id, type: 'COMMISSION', amountPaise: commissionPaise, metadata: { source: 'dispute', outcome: body.outcome } } });
    if (refundPaise > 0) await tx.ledgerEntry.create({ data: { technicianId: booking.technicianId!, bookingId: booking.id, type: 'DISPUTE_REVERSAL', amountPaise: refundPaise, metadata: { outcome: body.outcome, method: captured.method } } });
    // Auto-offset cash debt against the credited earning (FOR-UPDATE-locked, B6c idiom).
    if (earningPaise > 0) {
      const [locked] = await tx.$queryRaw<{ cashDebtPaise: number }[]>`SELECT "cashDebtPaise" FROM "Technician" WHERE id = ${booking.technicianId} FOR UPDATE`;
      if (locked) {
        const offset = Math.min(earningPaise, Number(locked.cashDebtPaise));
        if (offset > 0) {
          await tx.technician.update({ where: { id: booking.technicianId! }, data: { cashDebtPaise: { decrement: offset } } });
          await tx.ledgerEntry.create({ data: { technicianId: booking.technicianId!, bookingId: booking.id, type: 'CASH_DEBT_OFFSET', amountPaise: offset } });
        }
      }
    }
    await transitionBooking(tx, booking, 'CLOSED', { type: 'USER', kind: 'ADMIN', id: adminUserId }, { source: 'dispute_resolution', outcome: body.outcome, refundPaise });
    await tx.booking.update({ where: { id: booking.id }, data: { closedAt: new Date() } });
    await tx.auditLog.create({ data: { action: 'DISPUTE_EVENT', actorType: 'USER', actorId: adminUserId, metadata: { event: 'resolved', disputeId, bookingId: booking.id, outcome: body.outcome, refundPaise, refundId, method: captured.method } } });
  });
  return { id: booking.id, state: 'CLOSED', outcome: body.outcome, refundPaise };
}
```

Add `UnprocessableError` + `splitPaise` + `paymentGateway` imports. Note: the actor kind is `'ADMIN'` — confirm `ActorKind` includes 'ADMIN' (it does, from B2a). For the UPI refund, the actual money settles when the `refund.processed` webhook lands (Task 3), which sets `razorpayRefundId`; the ledger DISPUTE_REVERSAL here records the intent at resolution. If you prefer to let ONLY the webhook write the reversal entry (avoid double-count), gate the resolution-time DISPUTE_REVERSAL to cash-only and let the webhook write it for UPI — DECIDE and make the test match; the money-conservation assertion must hold exactly once. (Recommended: resolution writes the reversal for BOTH; the webhook for UPI only sets razorpayRefundId + a `refund_confirmed` audit, NOT a second ledger entry — adjust Task 3's handler accordingly so there is exactly one DISPUTE_REVERSAL per refund.)

- [ ] **Step 4: Queries + routes** — add `getDispute(id)` (case file DTO: dispute fields + bookingId, no raw user objects) and `listDisputes(status?)` to the service; add the three admin routes to `disputes.routes.ts` (all `requireAdminLevel('MANAGER')`):
  - `POST /admin/disputes/:id/resolve`
  - `GET /admin/disputes/:id`
  - `GET /admin/disputes` (optional `?status=OPEN|RESOLVED` query, Zod-validated)

- [ ] **Step 5: Run** `pnpm vitest run tests/disputes/` + `pnpm tsc --noEmit` → green/clean. Reconcile the Task 3 refund-webhook double-entry decision so exactly one DISPUTE_REVERSAL exists per refund (adjust and re-run both files).

- [ ] **Step 6: Commit**

```bash
git add -A && git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(backend): resolve-dispute — outcome ledger + refund + CLOSED as ADMIN, admin queries (B7)"
```

---

### Task 5: Dispute in the customer DTO + docs + full verification

**Files:**
- Modify: `apps/backend/src/modules/bookings/bookings.types.ts` (BookingDto.dispute), `bookings.service.ts` (getBooking/listBookings include + map)
- Test: `apps/backend/tests/disputes/dto.test.ts`
- Modify: `STATUS.md`, `CHANGELOG.md`

**Interfaces:**
- Produces: `BookingDto.dispute: { status; outcome; refundPaise } | null` (no `reason`/PII).

- [ ] **Step 1: Failing test** — `tests/disputes/dto.test.ts`: a booking with an OPEN dispute shows `dispute: { status: 'OPEN', outcome: null, refundPaise: null }` in `GET /me/bookings/:id`; a RESOLVED one shows the outcome + refundPaise; `JSON.stringify(dto.dispute)` does NOT contain the reason text. Direct-seed the states.

Run → FAIL.

- [ ] **Step 2: DTO type + mapper** — add `DisputeSummary { status: DisputeStatus; outcome: DisputeOutcome | null; refundPaise: number | null }` and `dispute: DisputeSummary | null` to `BookingDto`. Add a 7th positional param `dispute: DisputeSummary | null = null` to `toBookingDto` and include it. In `bookings.service.ts` `getBooking`/`listBookings`, include `disputes: { orderBy: { createdAt: 'desc' }, take: 1 }` and map the latest to the summary (never the reason). Follow the exact `pickPaymentSummary` pattern already in the file.

- [ ] **Step 3: Run** `pnpm vitest run tests/disputes/ tests/bookings/` → all pass.

- [ ] **Step 4: Full verification**

```bash
cd apps/backend && set -a && source .env && set +a && pnpm tsc --noEmit && pnpm vitest run
```

Expected: 0 type errors; ALL tests pass (324 pre-existing + ~14 new).

- [ ] **Step 5: STATUS.md + CHANGELOG.md** — Active task → B7 complete on branch (raise/hold/resolve/refund/reversal, deferred tiers/appeals/dashboard); Last shipped B7 entry; Next 3 → B2b accept-timer / Flutter customer app / (dispute dashboard when admin lands). CHANGELOG: new `## 2026-07-26 — Booking slice B7 (disputes)` section.

- [ ] **Step 6: Commit**

```bash
git add -A && git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(backend): dispute in customer DTO + docs — B7 complete"
```
