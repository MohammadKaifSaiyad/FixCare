# Booking B6c — Settlement Ledger + CLOSED Wiring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Paid bookings CLOSE after the 48h dispute window via a BullMQ sweep that books technician earnings (80%), platform commission (20%), and auto-nets cash debt into an append-only ledger; zero-payable bookings auto-settle at completion; the debt-limit accept-gate ships; manual admin payouts/repayments until Route.

**Architecture:** New `settlements` module owns the `LedgerEntry` model, the sweep (`settleClosableBookings` — a plain exported function; BullMQ only schedules it), balance derivation, and the admin/technician endpoints. Cross-module writes happen via exported service functions (`recordCashCollected` called from confirmCashPayment's tx). B6b carry-forwards (CHECK constraint, Payment index) fold into this migration.

**Tech Stack:** Fastify 5 + Prisma 6 + Zod 4 + BullMQ (new dep) + ioredis + Vitest.

**Design:** `docs/designs/2026-07-19-booking-b6c-settlement-design.md`.

## Global Constraints

- Money integer paise. `COMMISSION_RATE_BPS` = **2000**; `earning = floor(base × (10000 − rate) / 10000)`, `commission = base − earning` (always sums exactly). Earning base: `declinedAt != null` ⇒ `visitFeePaise`, else `laborPaise`.
- `DISPUTE_WINDOW_HOURS` = **48**, `SETTLEMENT_SWEEP_INTERVAL_MINUTES` = **15**. Sweep keys on `Booking.paidAt`, never `updatedAt`.
- LedgerEntry is APPEND-ONLY: no update/delete/soft-delete anywhere. `amountPaise` always positive; `type` carries direction.
- Balances: payable = ΣEARNING_CREDIT − ΣCASH_DEBT_OFFSET − ΣPAYOUT; debt = ΣCASH_COLLECTED − ΣCASH_DEBT_OFFSET − ΣDEBT_REPAYMENT (must equal the cached `cashDebtPaise`).
- `ALLOWED_ACTORS.CLOSED: ['SYSTEM']`. All money mutations audited in-tx (`SETTLEMENT_EVENT`); no PII in metadata.
- Debt decrements always via the technician-row-update lock (B6b idiom); `CHECK (cashDebtPaise >= 0)` backstops.
- Backend commands from `apps/backend` with `set -a && source .env && set +a && pnpm <cmd>`; Docker stack up. Migrations to BOTH DBs (`migrate dev` + `DATABASE_URL="$TEST_DATABASE_URL" pnpm prisma migrate deploy`).
- Commit author: `git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "..."` — NO Claude trailer.
- Tests: new files under `tests/settlements/` get their own app instance (rate-limit window convention); the sweep is tested by calling `settleClosableBookings()` directly — no timers, no BullMQ in tests.

---

### Task 1: Schema (LedgerEntry + paidAt/closedAt + carry-forwards) + config + actor gate + paidAt wiring

**Files:**
- Modify: `apps/backend/prisma/schema.prisma` (AuditAction ~189-203; Payment model; Technician model; new LedgerEntry after Payment)
- Modify: `apps/backend/src/shared/config.ts` (after CASH keys)
- Modify: `apps/backend/src/modules/bookings/bookings.state.ts:50` region (ALLOWED_ACTORS)
- Modify: `apps/backend/src/modules/payments/webhook.service.ts:69` (happy-capture tx)
- Modify: `apps/backend/src/modules/technician-jobs/technician-jobs.service.ts` (confirmCashPayment tx, ~line 363)
- Modify: `apps/backend/tests/schema/helpers.ts:15` (TRUNCATE list)
- Test: `apps/backend/tests/bookings/booking-state-unit.test.ts`, `apps/backend/tests/settlements/schema.test.ts`

**Interfaces:**
- Produces: `LedgerEntry` model + `LedgerEntryType` enum (EARNING_CREDIT, COMMISSION, CASH_COLLECTED, CASH_DEBT_OFFSET, PAYOUT, DEBT_REPAYMENT); `Booking.paidAt/closedAt: Date | null`; `AuditAction.SETTLEMENT_EVENT`; `config.COMMISSION_RATE_BPS/DISPUTE_WINDOW_HOURS/SETTLEMENT_SWEEP_INTERVAL_MINUTES`; CLOSED allowed for SYSTEM. Both capture paths set `paidAt`.

- [ ] **Step 1: Schema edits**

In `enum AuditAction`, add after `PAYMENT_EVENT`:

```prisma
  SETTLEMENT_EVENT
```

In `model Booking`, add after the existing milestone columns (`confirmedAt` etc.):

```prisma
  paidAt   DateTime? // set by BOTH capture paths + the zero-payable chain; the close sweep keys on this
  closedAt DateTime? // set by the settlement sweep at CLOSED
```

In `model Payment`, add below `@@index([bookingId])`:

```prisma
  @@index([method, status, capturedAt]) // velocity aggregate runs inside the capture row-lock — must be an index scan
```

On the `PaymentStatus` enum (or the Payment model comment block), extend the comment:

```prisma
// FAILED: UPI gateway failures AND cash attempts superseded at close (sweep marks stale CASH CREATED rows FAILED).
```

New model after `Payment`:

```prisma
// Append-only settlement ledger (B6c) — NO updates, NO deletes, NO soft-delete: same evidence
// posture as Payment. amountPaise is always POSITIVE; type carries the direction.
// payable = ΣEARNING_CREDIT − ΣCASH_DEBT_OFFSET − ΣPAYOUT
// debt    = ΣCASH_COLLECTED − ΣCASH_DEBT_OFFSET − ΣDEBT_REPAYMENT (= Technician.cashDebtPaise cache)
model LedgerEntry {
  id           String          @id @default(uuid())
  technicianId String
  technician   Technician      @relation(fields: [technicianId], references: [id])
  bookingId    String? // null for payouts/repayments (no booking context)
  booking      Booking?        @relation(fields: [bookingId], references: [id])
  type         LedgerEntryType
  amountPaise  Int
  metadata     Json? // rate bps + base at close; actor for manual entries. Ids and paise only — no PII.
  createdAt    DateTime        @default(now())

  @@index([technicianId, createdAt])
}

enum LedgerEntryType {
  EARNING_CREDIT
  COMMISSION
  CASH_COLLECTED
  CASH_DEBT_OFFSET
  PAYOUT
  DEBT_REPAYMENT
}
```

Add back-relations: `ledgerEntries LedgerEntry[]` on both `Technician` and `Booking`.

- [ ] **Step 2: Migration with the CHECK constraint (create-only, append raw SQL, apply to both DBs)**

```bash
cd apps/backend && set -a && source .env && set +a && pnpm prisma migrate dev --name settlement_ledger --create-only
```

Append to the generated `prisma/migrations/*_settlement_ledger/migration.sql`:

```sql
-- B6b carry-forward: a settlement bug must never produce a negative cached balance — a negative
-- value would silently disable BOTH cash gates (debt limit + velocity) in B6b's checks.
ALTER TABLE "Technician" ADD CONSTRAINT "Technician_cashDebtPaise_nonnegative" CHECK ("cashDebtPaise" >= 0);
```

Then apply:

```bash
pnpm prisma migrate dev
DATABASE_URL="$TEST_DATABASE_URL" pnpm prisma migrate deploy
```

- [ ] **Step 3: Config keys** (`src/shared/config.ts`, after `CASH_VELOCITY_CAP_PAISE`):

```ts
  // Settlement (B6c). Commission in basis points (2000 = 20% platform / 80% technician —
  // pricing-model.md split table). Sweep closes PAYMENT_RECEIVED bookings paid > window ago.
  COMMISSION_RATE_BPS: z.coerce.number().int().min(0).max(10000).default(2000),
  DISPUTE_WINDOW_HOURS: z.coerce.number().int().positive().default(48),
  SETTLEMENT_SWEEP_INTERVAL_MINUTES: z.coerce.number().int().positive().default(15),
```

- [ ] **Step 4: TRUNCATE list** — in `tests/schema/helpers.ts:15` add `"LedgerEntry",` before `"Payment",`.

- [ ] **Step 5: Failing actor test** — in `tests/bookings/booking-state-unit.test.ts` add:

```ts
  it('CLOSED is SYSTEM-only — the settlement sweep drives it (B7 adds ADMIN for dispute closes)', () => {
    expect(actorAllowedFor('CLOSED', 'SYSTEM')).toBe(true);
    for (const kind of ['CUSTOMER', 'TECHNICIAN', 'ADMIN'] as const) {
      expect(actorAllowedFor('CLOSED', kind)).toBe(false);
    }
  });
```

Run `pnpm vitest run tests/bookings/booking-state-unit.test.ts` → FAIL (CLOSED unmapped → SYSTEM false).

- [ ] **Step 6: Open the gate** — in `ALLOWED_ACTORS` (bookings.state.ts) add:

```ts
  CLOSED:                ['SYSTEM'], // settlement sweep after the 48h dispute window (B6c); B7 adds ADMIN dispute closes
```

Re-run → PASS.

- [ ] **Step 7: paidAt wiring.** In `webhook.service.ts`, in the HAPPY capture tx only (the first `tx.payment.update` at ~line 69, NOT the duplicate_capture path), add after `transitionBooking(...)`:

```ts
        await tx.booking.update({ where: { id: payment.bookingId }, data: { paidAt: new Date() } });
```

In `confirmCashPayment` (technician-jobs.service.ts), add inside the tx after `transitionBooking(...)`:

```ts
    await tx.booking.update({ where: { id: bookingId }, data: { paidAt: new Date() } });
```

- [ ] **Step 8: Schema smoke test** — create `tests/settlements/schema.test.ts`:

```ts
import { describe, expect, it, beforeEach } from 'vitest';
import { prisma, resetDb } from '../schema/helpers.js';
import { makeTechnician } from '../bookings/helpers.js';

beforeEach(async () => { await resetDb(); });

describe('settlement schema', () => {
  it('LedgerEntry round-trips; the CHECK constraint rejects a negative cashDebtPaise', async () => {
    const t = await makeTechnician(['AC']);
    const e = await prisma.ledgerEntry.create({ data: { technicianId: t.technicianId, type: 'EARNING_CREDIT', amountPaise: 48000, metadata: { rateBps: 2000, basePaise: 60000 } } });
    expect(e.bookingId).toBeNull();
    await expect(
      prisma.$executeRawUnsafe(`UPDATE "Technician" SET "cashDebtPaise" = -1 WHERE id = '${t.technicianId}'`),
    ).rejects.toThrow(/Technician_cashDebtPaise_nonnegative|check constraint/i);
  });
});
```

Run `pnpm vitest run tests/settlements/schema.test.ts tests/bookings/` → all pass. Also `pnpm tsc --noEmit` → clean.

- [ ] **Step 9: Commit**

```bash
git add -A && git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(backend): settlement schema — LedgerEntry, paidAt/closedAt, CHECK + Payment index carry-forwards (B6c)"
```

---

### Task 2: Settlement service — balances, recordCashCollected, and the close sweep

**Files:**
- Create: `apps/backend/src/modules/settlements/settlements.service.ts`
- Modify: `apps/backend/src/modules/technician-jobs/technician-jobs.service.ts` (confirmCashPayment tx: CASH_COLLECTED entry)
- Test: `apps/backend/tests/settlements/sweep.test.ts`

**Interfaces:**
- Consumes: `transitionBooking` from `../bookings/bookings.state.js`; `config`; prisma.
- Produces (Tasks 3-4 rely on these exact signatures):
  - `payableBalancePaise(db: Prisma.TransactionClient | PrismaClient, technicianId: string): Promise<number>`
  - `debtBalancePaise(db, technicianId): Promise<number>` (ledger-derived)
  - `recordCashCollected(tx: Prisma.TransactionClient, args: { technicianId: string; bookingId: string; amountPaise: number }): Promise<void>`
  - `settleClosableBookings(now?: Date): Promise<{ closed: number; skipped: number }>`
  - `splitPaise(basePaise: number): { earningPaise: number; commissionPaise: number }`

- [ ] **Step 1: Failing tests** — create `tests/settlements/sweep.test.ts`:

```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, makeTechnician, seedBookable } from '../bookings/helpers.js';
import { settleClosableBookings, splitPaise, payableBalancePaise, debtBalancePaise } from '../../src/modules/settlements/settlements.service.js';

// The sweep is a plain function — tested directly, no BullMQ, no timers. App only for fixtures.
const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
function future() { return new Date(Date.now() + 86_400_000).toISOString(); }
const H49 = 49 * 3600_000;

/** Direct-seed a PAYMENT_RECEIVED booking paid `paidAgoMs` ago. labor 60000, visitFee 14900. */
async function paidBooking(opts?: { paidAgoMs?: number; declined?: boolean; cashDebtPaise?: number; method?: 'UPI' | 'CASH' }) {
  const c = await makeCustomer();
  const f = await seedBookable(c.customerId);
  const t = await makeTechnician(['AC']);
  if (opts?.cashDebtPaise) await prisma.technician.update({ where: { id: t.technicianId }, data: { cashDebtPaise: opts.cashDebtPaise } });
  const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
  await prisma.booking.update({
    where: { id: booking.id },
    data: {
      state: 'PAYMENT_RECEIVED', technicianId: t.technicianId,
      paidAt: new Date(Date.now() - (opts?.paidAgoMs ?? H49)),
      ...(opts?.declined ? { declinedAt: new Date() } : {}),
    },
  });
  await prisma.payment.create({ data: { bookingId: booking.id, method: opts?.method ?? 'UPI', status: 'CAPTURED', amountPaise: 45100, capturedAt: new Date(), ...(opts?.method !== 'CASH' ? { razorpayOrderId: `order_dev_swp_${Math.random().toString(36).slice(2, 8)}` } : {}) } });
  return { c, t, bookingId: booking.id as string };
}

describe('splitPaise', () => {
  it('floors the earning; earning + commission always equals base exactly', () => {
    expect(splitPaise(60000)).toEqual({ earningPaise: 48000, commissionPaise: 12000 });
    expect(splitPaise(14900)).toEqual({ earningPaise: 11920, commissionPaise: 2980 });
    const odd = splitPaise(99);
    expect(odd.earningPaise + odd.commissionPaise).toBe(99); // 79 + 20
  });
});

describe('settleClosableBookings', () => {
  it('closes a booking paid >48h ago: CLOSED + closedAt + EARNING_CREDIT(80% labor) + COMMISSION + audit', async () => {
    const { t, bookingId } = await paidBooking();
    const r = await settleClosableBookings();
    expect(r.closed).toBe(1);
    const b = await prisma.booking.findUnique({ where: { id: bookingId } });
    expect(b!.state).toBe('CLOSED');
    expect(b!.closedAt).not.toBeNull();
    const entries = await prisma.ledgerEntry.findMany({ where: { bookingId }, orderBy: { type: 'asc' } });
    expect(entries.map((e) => [e.type, e.amountPaise])).toEqual([['COMMISSION', 12000], ['EARNING_CREDIT', 48000]]);
    expect((entries[1]!.metadata as { rateBps: number }).rateBps).toBe(2000);
    expect(await payableBalancePaise(prisma, t.technicianId)).toBe(48000);
    expect(await prisma.auditLog.count({ where: { action: 'SETTLEMENT_EVENT' } })).toBe(1);
  });

  it('a DECLINED booking earns 80% of the VISIT FEE, not labor', async () => {
    const { t } = await paidBooking({ declined: true });
    await settleClosableBookings();
    expect(await payableBalancePaise(prisma, t.technicianId)).toBe(11920); // floor(14900 × 0.8)
  });

  it('leaves bookings inside the 48h window untouched (boundary: exactly 48h stays open)', async () => {
    await paidBooking({ paidAgoMs: 47 * 3600_000 });
    await paidBooking({ paidAgoMs: 48 * 3600_000 }); // exactly at the boundary — paidAt <= now − 48h is FALSE only when strictly newer; use < cutoff semantics: paidAt must be <= cutoff... see service comment; this one CLOSES
    const r = await settleClosableBookings();
    expect(r.closed).toBe(1);
  });

  it('auto-offsets cash debt: earning > debt → debt 0, remainder payable; ledger shows the pairing', async () => {
    const { t } = await paidBooking({ cashDebtPaise: 30000 });
    await settleClosableBookings();
    expect((await prisma.technician.findUnique({ where: { id: t.technicianId } }))!.cashDebtPaise).toBe(0);
    expect(await payableBalancePaise(prisma, t.technicianId)).toBe(18000); // 48000 − 30000
    const offset = await prisma.ledgerEntry.findFirst({ where: { type: 'CASH_DEBT_OFFSET' } });
    expect(offset!.amountPaise).toBe(30000);
  });

  it('earning < debt → debt reduced, payable 0; zero debt → NO offset entry', async () => {
    const a = await paidBooking({ cashDebtPaise: 50000 });
    await settleClosableBookings();
    expect((await prisma.technician.findUnique({ where: { id: a.t.technicianId } }))!.cashDebtPaise).toBe(2000); // 50000 − 48000
    expect(await payableBalancePaise(prisma, a.t.technicianId)).toBe(0);
    await resetDb();
    const b = await paidBooking();
    await settleClosableBookings();
    expect(await prisma.ledgerEntry.count({ where: { type: 'CASH_DEBT_OFFSET' } })).toBe(0);
    expect(await debtBalancePaise(prisma, b.t.technicianId)).toBe(0);
  });

  it('is idempotent: a second run writes NOTHING', async () => {
    await paidBooking();
    await settleClosableBookings();
    const before = await prisma.ledgerEntry.count();
    const r2 = await settleClosableBookings();
    expect(r2.closed).toBe(0);
    expect(await prisma.ledgerEntry.count()).toBe(before);
  });

  it('marks stale CASH CREATED attempts FAILED at close (B6b orphan cleanup)', async () => {
    const { bookingId } = await paidBooking();
    await prisma.payment.create({ data: { bookingId, method: 'CASH', status: 'CREATED', amountPaise: 45100 } });
    await settleClosableBookings();
    const stale = await prisma.payment.findFirst({ where: { bookingId, method: 'CASH' } });
    expect(stale!.status).toBe('FAILED');
    expect(stale!.failureReason).toBe('superseded_at_close');
  });
});
```

Run → FAIL (module does not exist).

- [ ] **Step 2: Create `settlements.service.ts`**

```ts
import type { Prisma, PrismaClient } from '@prisma/client';
import { prisma } from '../../shared/database/prisma.js';
import { config } from '../../shared/config.js';
import { transitionBooking } from '../bookings/bookings.state.js';

const SWEEP_BATCH = 100;

/** 80/20 split in integer paise. Earning floors; commission takes the remainder so the two
 *  ALWAYS sum exactly to base (no paise ever created or lost — Golden Rule 4 arithmetic). */
export function splitPaise(basePaise: number): { earningPaise: number; commissionPaise: number } {
  const earningPaise = Math.floor((basePaise * (10000 - config.COMMISSION_RATE_BPS)) / 10000);
  return { earningPaise, commissionPaise: basePaise - earningPaise };
}

/** payable = earnings − offsets − payouts. Derived from the ledger alone (reconcilable). */
export async function payableBalancePaise(db: Prisma.TransactionClient | PrismaClient, technicianId: string): Promise<number> {
  const sums = await db.ledgerEntry.groupBy({ by: ['type'], _sum: { amountPaise: true }, where: { technicianId } });
  const get = (t: string) => sums.find((s) => s.type === t)?._sum.amountPaise ?? 0;
  return get('EARNING_CREDIT') - get('CASH_DEBT_OFFSET') - get('PAYOUT');
}

/** debt = collected − offsets − repayments. Must equal the cached Technician.cashDebtPaise. */
export async function debtBalancePaise(db: Prisma.TransactionClient | PrismaClient, technicianId: string): Promise<number> {
  const sums = await db.ledgerEntry.groupBy({ by: ['type'], _sum: { amountPaise: true }, where: { technicianId } });
  const get = (t: string) => sums.find((s) => s.type === t)?._sum.amountPaise ?? 0;
  return get('CASH_COLLECTED') - get('CASH_DEBT_OFFSET') - get('DEBT_REPAYMENT');
}

/** Called from confirmCashPayment's capture tx: the ledger is the debt source of truth from B6c
 *  on; the Technician.cashDebtPaise increment (same tx, caller's) stays the cached balance. */
export async function recordCashCollected(tx: Prisma.TransactionClient, args: { technicianId: string; bookingId: string; amountPaise: number }): Promise<void> {
  await tx.ledgerEntry.create({ data: { technicianId: args.technicianId, bookingId: args.bookingId, type: 'CASH_COLLECTED', amountPaise: args.amountPaise } });
}

/** Close every PAYMENT_RECEIVED booking whose 48h dispute window has passed, booking the split
 *  and auto-netting cash debt. Idempotent: transitionBooking's optimistic lock makes a double
 *  fire skip. Per-booking try/catch — one failure never aborts the batch. */
export async function settleClosableBookings(now: Date = new Date()): Promise<{ closed: number; skipped: number }> {
  const cutoff = new Date(now.getTime() - config.DISPUTE_WINDOW_HOURS * 3600_000);
  const due = await prisma.booking.findMany({
    where: { state: 'PAYMENT_RECEIVED', deletedAt: null, paidAt: { not: null, lte: cutoff } },
    orderBy: { paidAt: 'asc' },
    take: SWEEP_BATCH,
  });
  let closed = 0;
  let skipped = 0;
  for (const booking of due) {
    try {
      await prisma.$transaction(async (tx) => {
        await transitionBooking(tx, booking, 'CLOSED', { type: 'SYSTEM', kind: 'SYSTEM', id: 'settlement-sweep' });
        if (!booking.technicianId) throw new Error(`paid booking ${booking.id} has no technician`); // data invariant; fail this booking loudly
        const basePaise = booking.declinedAt != null ? booking.visitFeePaise : booking.laborPaise;
        const { earningPaise, commissionPaise } = splitPaise(basePaise);
        const meta = { rateBps: config.COMMISSION_RATE_BPS, basePaise };
        await tx.ledgerEntry.create({ data: { technicianId: booking.technicianId, bookingId: booking.id, type: 'EARNING_CREDIT', amountPaise: earningPaise, metadata: meta } });
        await tx.ledgerEntry.create({ data: { technicianId: booking.technicianId, bookingId: booking.id, type: 'COMMISSION', amountPaise: commissionPaise, metadata: meta } });
        // Auto-net: the technician already HOLDS collected cash — earnings pay the debt down
        // first; payouts only ever move the remainder. Row update = the serializing lock (B6b).
        const tech = await tx.technician.findUniqueOrThrow({ where: { id: booking.technicianId }, select: { cashDebtPaise: true } });
        const offset = Math.min(earningPaise, tech.cashDebtPaise);
        if (offset > 0) {
          await tx.technician.update({ where: { id: booking.technicianId }, data: { cashDebtPaise: { decrement: offset } } });
          await tx.ledgerEntry.create({ data: { technicianId: booking.technicianId, bookingId: booking.id, type: 'CASH_DEBT_OFFSET', amountPaise: offset } });
        }
        // B6b orphan cleanup: an open CASH attempt on a closing booking can never capture now.
        await tx.payment.updateMany({ where: { bookingId: booking.id, method: 'CASH', status: 'CREATED' }, data: { status: 'FAILED', failureReason: 'superseded_at_close' } });
        await tx.booking.update({ where: { id: booking.id }, data: { closedAt: now } });
        await tx.auditLog.create({
          data: { action: 'SETTLEMENT_EVENT', actorType: 'SYSTEM', metadata: { event: 'booking_settled', bookingId: booking.id, technicianId: booking.technicianId, earningPaise, commissionPaise, offsetPaise: offset } },
        });
      });
      closed++;
    } catch {
      skipped++; // raced (409) or data problem — next run retries; never abort the batch
    }
  }
  return { closed, skipped };
}
```

- [ ] **Step 3: CASH_COLLECTED from the capture tx.** In `confirmCashPayment` (technician-jobs.service.ts), import `recordCashCollected` from `../settlements/settlements.service.js` and add inside the tx, right after the `cash_received` audit create:

```ts
    await recordCashCollected(tx, { technicianId: tech.id, bookingId, amountPaise });
```

- [ ] **Step 4: Run** `pnpm vitest run tests/settlements/ tests/bookings/cash-confirm.test.ts` → all pass (cash-confirm still green with the new ledger write). `pnpm tsc --noEmit` clean.

- [ ] **Step 5: Commit**

```bash
git add -A && git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(backend): settlement service — split, balances, close sweep with auto-offset (B6c)"
```

---

### Task 3: Zero-payable chain + accept-gate

**Files:**
- Modify: `apps/backend/src/modules/technician-jobs/technician-jobs.service.ts` (confirmCompletion ~316-329; acceptJob ~50-66)
- Test: `apps/backend/tests/settlements/zero-payable.test.ts`

**Interfaces:**
- Consumes: `computeEstimate` from `../bookings/estimate.js`; `config`.
- Produces: confirmCompletion returns `{ id, state: 'CUSTOMER_CONFIRMED' | 'PAYMENT_RECEIVED' }` (state reflects the chain); acceptJob gains the debt gate.

- [ ] **Step 1: Failing tests** — create `tests/settlements/zero-payable.test.ts`:

```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, makeTechnician, seedBookable, seedRepairPhotos } from '../bookings/helpers.js';
import { mintCompletionCode } from '../../src/modules/bookings/completion-code.js';
import { settleClosableBookings } from '../../src/modules/settlements/settlements.service.js';
import { config } from '../../src/shared/config.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
function future() { return new Date(Date.now() + 86_400_000).toISOString(); }

describe('zero-payable auto-settlement at completion', () => {
  it('confirm-completion chains to PAYMENT_RECEIVED with paidAt when the credit covers everything; sweep later credits the earning', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId, { laborPaise: 10000, visitFeePaise: 14900 }); // credit ≥ labor, empty cart → payable 0
    const t = await makeTechnician(['AC']);
    const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
    await prisma.booking.update({ where: { id: booking.id }, data: { state: 'REPAIR_COMPLETE', technicianId: t.technicianId } });
    await seedRepairPhotos(booking.id);
    const mint = await mintCompletionCode(booking.id);
    if (mint.status !== 'ok') throw new Error('mint throttled');
    const res = await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/confirm-completion`, headers: auth(t.token), payload: { code: mint.code } });
    expect(res.statusCode).toBe(200);
    expect(res.json().state).toBe('PAYMENT_RECEIVED');
    const b = await prisma.booking.findUnique({ where: { id: booking.id } });
    expect(b!.state).toBe('PAYMENT_RECEIVED');
    expect(b!.paidAt).not.toBeNull();
    // the pay endpoints agree nothing is owed
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/pay`, headers: auth(c.token) })).statusCode).toBe(409);
    // sweep (48h later) closes and still credits the earning — the technician did the work
    await prisma.booking.update({ where: { id: booking.id }, data: { paidAt: new Date(Date.now() - 49 * 3600_000) } });
    await settleClosableBookings();
    const earning = await prisma.ledgerEntry.findFirst({ where: { bookingId: booking.id, type: 'EARNING_CREDIT' } });
    expect(earning!.amountPaise).toBe(8000); // floor(10000 × 0.8)
  });

  it('a payable booking still stops at CUSTOMER_CONFIRMED (no chain)', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId); // labor 60000 > credit
    const t = await makeTechnician(['AC']);
    const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
    await prisma.booking.update({ where: { id: booking.id }, data: { state: 'REPAIR_COMPLETE', technicianId: t.technicianId } });
    await seedRepairPhotos(booking.id);
    const mint = await mintCompletionCode(booking.id);
    if (mint.status !== 'ok') throw new Error('mint throttled');
    const res = await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/confirm-completion`, headers: auth(t.token), payload: { code: mint.code } });
    expect(res.json().state).toBe('CUSTOMER_CONFIRMED');
    expect((await prisma.booking.findUnique({ where: { id: booking.id } }))!.paidAt).toBeNull();
  });
});

describe('accept-gate at the debt limit', () => {
  it('a technician AT the limit cannot accept (422); an offset below the limit unlocks accepting', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const t = await makeTechnician(['AC']);
    await prisma.technician.update({ where: { id: t.technicianId }, data: { cashDebtPaise: config.CASH_DEBT_LIMIT_PAISE } });
    const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(t.token) })).statusCode).toBe(422);
    await prisma.technician.update({ where: { id: t.technicianId }, data: { cashDebtPaise: config.CASH_DEBT_LIMIT_PAISE - 1 } });
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(t.token) })).statusCode).toBe(200);
  });
});
```

Run → FAIL.

- [ ] **Step 2: Zero-payable chain.** Replace `confirmCompletion`'s tx + return (technician-jobs.service.ts ~324-329). Add imports: `computeEstimate` from `../bookings/estimate.js`.

```ts
  const finalState = await prisma.$transaction(async (tx) => {
    await transitionBooking(tx, booking, 'CUSTOMER_CONFIRMED', { type: 'USER', kind: 'TECHNICIAN', id: userId }, { codeConfirmed: true });
    await tx.booking.update({ where: { id: bookingId }, data: { confirmedAt: new Date() } });
    // Zero-payable chain (B6c): when the visit-fee credit covers the whole job there is nothing
    // to charge — never show the customer a ₹0 pay screen. Same tx: a crash can't strand the
    // booking between the two states.
    const cart = await tx.bookingPart.findMany({ where: { bookingId } });
    const payable = computeEstimate({ laborPaise: booking.laborPaise, visitFeePaise: booking.visitFeePaise, state: 'CUSTOMER_CONFIRMED', declinedAt: booking.declinedAt }, cart).totalPayablePaise;
    if (payable > 0) return 'CUSTOMER_CONFIRMED' as const;
    await transitionBooking(tx, { ...booking, state: 'CUSTOMER_CONFIRMED' }, 'PAYMENT_RECEIVED', { type: 'SYSTEM', kind: 'SYSTEM', id: 'zero-payable' }, { amountPaise: 0, reason: 'zero_payable' });
    await tx.booking.update({ where: { id: bookingId }, data: { paidAt: new Date() } });
    return 'PAYMENT_RECEIVED' as const;
  });
  return { id: bookingId, state: finalState };
```

Update the signature: `Promise<{ id: string; state: 'CUSTOMER_CONFIRMED' | 'PAYMENT_RECEIVED' }>`.

- [ ] **Step 3: Accept-gate.** In `acceptJob`, after the skills check (line ~55), add:

```ts
  // B6c accept-gate (core-flow: "technician at cash debt limit → cannot accept"). Deferred from
  // B6b until settlement existed — auto-offset now gives a self-healing path out of the lockout.
  if (tech.cashDebtPaise >= config.CASH_DEBT_LIMIT_PAISE) {
    throw new UnprocessableError('Settle your cash debt to accept new jobs');
  }
```

(`requireTechnician` already returns the full row incl. `cashDebtPaise`; `config` import exists from B6b.)

- [ ] **Step 4: Run** `pnpm vitest run tests/settlements/ tests/bookings/completion.test.ts tests/bookings/dispatch-accept.test.ts 2>/dev/null || pnpm vitest run tests/settlements/ tests/bookings/` → all pass (adjust: run whichever existing files cover accept + completion; then the full bookings dir). `pnpm tsc --noEmit` clean.

- [ ] **Step 5: Commit**

```bash
git add -A && git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(backend): zero-payable auto-settlement + debt-limit accept-gate (B6c)"
```

---

### Task 4: Endpoints — technician balance + admin payouts/repayments

**Files:**
- Create: `apps/backend/src/modules/settlements/settlements.routes.ts`, `apps/backend/src/modules/settlements/settlements.schemas.ts`
- Modify: `apps/backend/src/modules/settlements/settlements.service.ts` (add the four endpoint functions)
- Modify: `apps/backend/src/app.ts` (register)
- Test: `apps/backend/tests/settlements/endpoints.test.ts`

**Interfaces:**
- Consumes: Task 2 balance helpers; `requireAuth`, `requireAdminLevel('MANAGER')` (shared/middleware), `requireTechnician` pattern.
- Produces: `technicianBalance(userId): Promise<{payablePaise: number; cashDebtPaise: number}>`; `recordPayout(adminUserId, {technicianId, amountPaise})`; `recordRepayment(adminUserId, {technicianId, amountPaise})`; `getTechnicianSettlement(technicianId)`.

- [ ] **Step 1: Failing tests** — create `tests/settlements/endpoints.test.ts`:

```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeTechnician, makeAdminToken } from '../bookings/helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }

/** Seed a ledger history: 48000 earned, 30000 offset, debt cache 20000 remaining. */
async function seeded() {
  const t = await makeTechnician(['AC']);
  await prisma.technician.update({ where: { id: t.technicianId }, data: { cashDebtPaise: 20000 } });
  await prisma.ledgerEntry.createMany({ data: [
    { technicianId: t.technicianId, type: 'EARNING_CREDIT', amountPaise: 48000 },
    { technicianId: t.technicianId, type: 'CASH_COLLECTED', amountPaise: 50000 },
    { technicianId: t.technicianId, type: 'CASH_DEBT_OFFSET', amountPaise: 30000 },
  ] });
  return t; // payable 18000, debt 20000
}

describe('GET /technician/me/balance', () => {
  it('returns ledger-derived payable + cached debt', async () => {
    const t = await seeded();
    const res = await app.inject({ method: 'GET', url: '/technician/me/balance', headers: auth(t.token) });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ payablePaise: 18000, cashDebtPaise: 20000 });
  });
});

describe('admin settlements', () => {
  it('payout: happy path writes PAYOUT + audit; over-payable → 409; over-debt repayment → 409', async () => {
    const t = await seeded();
    const admin = await makeAdminToken();
    expect((await app.inject({ method: 'POST', url: '/admin/settlements/payouts', headers: auth(admin), payload: { technicianId: t.technicianId, amountPaise: 20000 } })).statusCode).toBe(409); // > 18000 payable
    const ok = await app.inject({ method: 'POST', url: '/admin/settlements/payouts', headers: auth(admin), payload: { technicianId: t.technicianId, amountPaise: 18000 } });
    expect(ok.statusCode).toBe(201);
    expect(await prisma.ledgerEntry.count({ where: { type: 'PAYOUT' } })).toBe(1);
    expect(await prisma.auditLog.count({ where: { action: 'SETTLEMENT_EVENT', metadata: { path: ['event'], equals: 'payout_recorded' } } })).toBe(1);
    expect((await app.inject({ method: 'POST', url: '/admin/settlements/repayments', headers: auth(admin), payload: { technicianId: t.technicianId, amountPaise: 25000 } })).statusCode).toBe(409); // > 20000 debt
  });

  it('repayment decrements the cached debt in the same tx', async () => {
    const t = await seeded();
    const admin = await makeAdminToken();
    const res = await app.inject({ method: 'POST', url: '/admin/settlements/repayments', headers: auth(admin), payload: { technicianId: t.technicianId, amountPaise: 20000 } });
    expect(res.statusCode).toBe(201);
    expect((await prisma.technician.findUnique({ where: { id: t.technicianId } }))!.cashDebtPaise).toBe(0);
  });

  it('walls: technician token on admin routes → 403; unknown technician → 404; zero/negative/float amount → 400', async () => {
    const t = await seeded();
    const admin = await makeAdminToken();
    expect((await app.inject({ method: 'POST', url: '/admin/settlements/payouts', headers: auth(t.token), payload: { technicianId: t.technicianId, amountPaise: 100 } })).statusCode).toBe(403);
    expect((await app.inject({ method: 'POST', url: '/admin/settlements/payouts', headers: auth(admin), payload: { technicianId: '00000000-0000-0000-0000-000000000000', amountPaise: 100 } })).statusCode).toBe(404);
    for (const amountPaise of [0, -5, 10.5]) {
      expect((await app.inject({ method: 'POST', url: '/admin/settlements/payouts', headers: auth(admin), payload: { technicianId: t.technicianId, amountPaise } })).statusCode).toBe(400);
    }
  });

  it('GET /admin/settlements/technicians/:id returns balances + entries newest-first', async () => {
    const t = await seeded();
    const admin = await makeAdminToken();
    const res = await app.inject({ method: 'GET', url: `/admin/settlements/technicians/${t.technicianId}`, headers: auth(admin) });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.payablePaise).toBe(18000);
    expect(body.cashDebtPaise).toBe(20000);
    expect(body.entries.length).toBe(3);
  });
});
```

Run → FAIL.

- [ ] **Step 2: Schemas** — `settlements.schemas.ts`:

```ts
import { z } from 'zod';

export const settlementAmountBody = z.object({
  technicianId: z.string().uuid(),
  amountPaise: z.number().int().positive(),
}).strict();
export type SettlementAmountBody = z.infer<typeof settlementAmountBody>;
```

- [ ] **Step 3: Service functions** (append to `settlements.service.ts`; add imports `NotFoundError, ConflictError, ForbiddenError` from `../../shared/errors.js`):

```ts
/** Technician dashboard balance. Payable derives from the ledger; debt is the cached column.
 *  If the ledger-derived debt disagrees with the cache, flag it loudly (reconciliation) but
 *  return the CACHED value — it is what the gates enforce. */
export async function technicianBalance(userId: string): Promise<{ payablePaise: number; cashDebtPaise: number }> {
  const tech = await prisma.technician.findFirst({ where: { userId, deletedAt: null } });
  if (!tech) throw new ForbiddenError('Technician profile required');
  const [payablePaise, ledgerDebt] = await Promise.all([
    payableBalancePaise(prisma, tech.id),
    debtBalancePaise(prisma, tech.id),
  ]);
  if (ledgerDebt !== tech.cashDebtPaise) {
    // Pre-B6c cash captures wrote no CASH_COLLECTED entries, so a mismatch is expected for
    // migrated technicians — flagged, not fatal. New activity keeps the two in lockstep.
    await prisma.auditLog.create({ data: { action: 'SETTLEMENT_EVENT', actorType: 'SYSTEM', metadata: { event: 'reconciliation_mismatch', technicianId: tech.id, cachedPaise: tech.cashDebtPaise, ledgerPaise: ledgerDebt } } });
  }
  return { payablePaise, cashDebtPaise: tech.cashDebtPaise };
}

async function technicianOrThrow(technicianId: string) {
  const t = await prisma.technician.findFirst({ where: { id: technicianId, deletedAt: null } });
  if (!t) throw new NotFoundError('Technician not found');
  return t;
}

/** Manual payout record (until Razorpay Route): money the founder actually transferred. */
export async function recordPayout(adminUserId: string, body: { technicianId: string; amountPaise: number }): Promise<{ id: string }> {
  await technicianOrThrow(body.technicianId);
  return prisma.$transaction(async (tx) => {
    const payable = await payableBalancePaise(tx, body.technicianId);
    if (body.amountPaise > payable) throw new ConflictError('Amount exceeds the payable balance');
    const entry = await tx.ledgerEntry.create({ data: { technicianId: body.technicianId, type: 'PAYOUT', amountPaise: body.amountPaise } });
    await tx.auditLog.create({ data: { action: 'SETTLEMENT_EVENT', actorType: 'USER', actorId: adminUserId, metadata: { event: 'payout_recorded', technicianId: body.technicianId, amountPaise: body.amountPaise } } });
    return { id: entry.id };
  });
}

/** Manual cash-repayment record: the technician handed collected cash back to the platform. */
export async function recordRepayment(adminUserId: string, body: { technicianId: string; amountPaise: number }): Promise<{ id: string }> {
  await technicianOrThrow(body.technicianId);
  return prisma.$transaction(async (tx) => {
    // Row update first = the serializing lock (B6b idiom); CHECK (>= 0) backstops the race.
    const t = await tx.technician.update({ where: { id: body.technicianId }, data: { cashDebtPaise: { decrement: body.amountPaise } }, select: { cashDebtPaise: true } });
    if (t.cashDebtPaise < 0) throw new ConflictError('Amount exceeds the outstanding debt'); // unreachable past CHECK; explicit for the 409 story
    const entry = await tx.ledgerEntry.create({ data: { technicianId: body.technicianId, type: 'DEBT_REPAYMENT', amountPaise: body.amountPaise } });
    await tx.auditLog.create({ data: { action: 'SETTLEMENT_EVENT', actorType: 'USER', actorId: adminUserId, metadata: { event: 'repayment_recorded', technicianId: body.technicianId, amountPaise: body.amountPaise } } });
    return { id: entry.id };
  });
}
```

NOTE for the implementer: Postgres raises on the CHECK before the `< 0` guard runs — catch `Prisma.PrismaClientKnownRequestError` with the check-violation code around the update and rethrow `ConflictError('Amount exceeds the outstanding debt')` so the client sees 409, not 500:

```ts
    let t;
    try {
      t = await tx.technician.update({ where: { id: body.technicianId }, data: { cashDebtPaise: { decrement: body.amountPaise } }, select: { cashDebtPaise: true } });
    } catch {
      throw new ConflictError('Amount exceeds the outstanding debt');
    }
```

(Use this try/catch form; drop the `< 0` if-check.)

```ts
/** Admin drill-down: balances + recent entries, newest first. */
export async function getTechnicianSettlement(technicianId: string): Promise<{ payablePaise: number; cashDebtPaise: number; entries: { type: string; amountPaise: number; bookingId: string | null; createdAt: string }[] }> {
  const t = await technicianOrThrow(technicianId);
  const [payablePaise, rows] = await Promise.all([
    payableBalancePaise(prisma, technicianId),
    prisma.ledgerEntry.findMany({ where: { technicianId }, orderBy: { createdAt: 'desc' }, take: 50 }),
  ]);
  return { payablePaise, cashDebtPaise: t.cashDebtPaise, entries: rows.map((e) => ({ type: e.type, amountPaise: e.amountPaise, bookingId: e.bookingId, createdAt: e.createdAt.toISOString() })) };
}
```

- [ ] **Step 4: Routes** — `settlements.routes.ts` (follow the module route conventions exactly: requireAuth first, role wall, Zod parse):

```ts
import type { FastifyInstance } from 'fastify';
import { requireAuth } from '../../shared/middleware/auth.js';
import { requireAdminLevel } from '../../shared/middleware/rbac.js';
import { ValidationError } from '../../shared/errors.js';
import { settlementAmountBody } from './settlements.schemas.js';
import { technicianBalance, recordPayout, recordRepayment, getTechnicianSettlement } from './settlements.service.js';

export async function registerSettlementRoutes(app: FastifyInstance): Promise<void> {
  app.get('/technician/me/balance', { preHandler: [requireAuth] }, async (req, reply) => {
    return reply.send(await technicianBalance(req.user!.id)); // service walls non-technicians (403)
  });

  app.post('/admin/settlements/payouts', { preHandler: [requireAuth, requireAdminLevel('MANAGER')] }, async (req, reply) => {
    const p = settlementAmountBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.code(201).send(await recordPayout(req.user!.id, p.data));
  });

  app.post('/admin/settlements/repayments', { preHandler: [requireAuth, requireAdminLevel('MANAGER')] }, async (req, reply) => {
    const p = settlementAmountBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.code(201).send(await recordRepayment(req.user!.id, p.data));
  });

  app.get('/admin/settlements/technicians/:id', { preHandler: [requireAuth, requireAdminLevel('MANAGER')] }, async (req, reply) => {
    return reply.send(await getTechnicianSettlement((req.params as { id: string }).id));
  });
}
```

Check the actual import paths for `requireAuth`/`ValidationError` against a neighboring routes file (e.g. `bookings.routes.ts`) and match them.

- [ ] **Step 5: Register** in `src/app.ts` after `registerWebhookRoutes(app)`:

```ts
  await registerSettlementRoutes(app);
```

(+ the import at top.)

- [ ] **Step 6: Run** `pnpm vitest run tests/settlements/` → all pass; `pnpm tsc --noEmit` clean.

- [ ] **Step 7: Commit**

```bash
git add -A && git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(backend): settlement endpoints — technician balance + admin payouts/repayments (B6c)"
```

---

### Task 5: BullMQ sweep scheduling + docs + full verification

**Files:**
- Create: `apps/backend/src/shared/queue/settlement-sweep.ts`
- Modify: `apps/backend/package.json` (add bullmq), `apps/backend/src/server.ts`, `apps/backend/.env.example`
- Modify: `STATUS.md`, `CHANGELOG.md`

**Interfaces:**
- Consumes: `settleClosableBookings` from Task 2; `config`.
- Produces: `startSettlementSweep(): Promise<() => Promise<void>>` (returns a stop function for graceful shutdown).

- [ ] **Step 1: Install** `set -a && source .env && set +a && pnpm add bullmq` (from apps/backend).

- [ ] **Step 2: Create `src/shared/queue/settlement-sweep.ts`**

```ts
import { Queue, Worker } from 'bullmq';
import IORedis from 'ioredis';
import { config } from '../config.js';
import { settleClosableBookings } from '../../modules/settlements/settlements.service.js';

const QUEUE = 'settlement-sweep';

/** First background work (B6c). BullMQ needs its OWN connection with maxRetriesPerRequest: null
 *  (the shared client uses 3 — BullMQ rejects that). Single in-process worker is fine for V1's
 *  one API instance; B2b's accept-timer reuses this scaffolding. The sweep itself is idempotent
 *  (optimistic lock), so overlapping/repeated fires are harmless. */
export async function startSettlementSweep(): Promise<() => Promise<void>> {
  const connection = new IORedis(config.REDIS_URL, { maxRetriesPerRequest: null });
  const queue = new Queue(QUEUE, { connection });
  await queue.upsertJobScheduler(QUEUE, { every: config.SETTLEMENT_SWEEP_INTERVAL_MINUTES * 60_000 });
  const worker = new Worker(QUEUE, async () => { await settleClosableBookings(); }, { connection });
  worker.on('failed', (_job, err) => console.error('settlement sweep failed:', err.message));
  return async () => {
    await worker.close();
    await queue.close();
    connection.disconnect();
  };
}
```

- [ ] **Step 3: Wire into `src/server.ts`** (after buildApp, before/after listen — match the file's style):

```ts
import { startSettlementSweep } from './shared/queue/settlement-sweep.js';
// ...
const stopSweep = await startSettlementSweep();
```

If the file has a shutdown handler, add `await stopSweep()` to it; if not, add a minimal `process.on('SIGTERM', ...)` that calls it then `app.close()`. Tests never import server.ts, so no test impact.

- [ ] **Step 4: `.env.example`** — add after the CASH block:

```bash
# Settlement (B6c) — optional, defaults shown. Commission bps (2000 = 20% platform).
# COMMISSION_RATE_BPS=2000
# DISPUTE_WINDOW_HOURS=48
# SETTLEMENT_SWEEP_INTERVAL_MINUTES=15
```

- [ ] **Step 5: Full verification**

```bash
cd apps/backend && set -a && source .env && set +a && pnpm tsc --noEmit && pnpm vitest run
```

Expected: clean types; ALL tests pass (304 pre-existing + ~15 new). Also boot-smoke the sweep: `pnpm tsx src/server.ts` for a few seconds (or `node --import tsx` per the dev script) and confirm "listening" with no BullMQ connection errors, then Ctrl-C.

- [ ] **Step 6: STATUS.md + CHANGELOG.md** — Active task → B6c complete on branch; Last shipped B6c entry; Next 3 → B7 disputes / B2b accept-timer (BullMQ now exists) / Flutter customer app start. CHANGELOG: new `## 2026-07-19` B6c section describing ledger, sweep, zero-payable, accept-gate, carry-forwards.

- [ ] **Step 7: Commit**

```bash
git add -A && git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(backend): BullMQ settlement sweep scheduling + docs — B6c complete"
```
