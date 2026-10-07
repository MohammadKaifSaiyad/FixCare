# Technician App Slice 4 — Earnings, Cash Debt + Payout Requests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A technician sees what FixCare owes them, what is pending, their cash debt vs the limit and a per-job money history, and can request a payout of the whole net balance; ops marks it paid (netting cash debt first) or rejects it with a reason.

**Architecture:** Backend adds a `PayoutRequest` table and five endpoints in the `settlements` module (which owns the ledger): technician summary / statement / request, and MANAGER list / pay / reject. Pay runs in one locked transaction: offset cash debt (`CASH_DEBT_OFFSET`), record `PAYOUT`, mark the request paid. The technician app adds an earnings feature (repository, summary provider, paged statement controller), an Earnings screen at `/earnings`, a money card on jobs home, and an Earnings button on the Suspended screen.

**Tech Stack:** Backend — Node 22, Fastify 5, TypeScript strict (`noUncheckedIndexedAccess`), Prisma 6 / Postgres 16, Zod 4, vitest 4 (real DB). Technician app — Flutter 3 / Dart 3, Riverpod 3 (`@riverpod` codegen), freezed 4 + json_serializable, dio 5, http_mock_adapter, go_router.

**Spec:** `docs/designs/2026-10-07-technician-app-slice4-earnings-design.md`

## Global Constraints

- Branch `feature/technician-app-slice4-earnings`; run `git branch --show-current` before every commit; never commit to `main`.
- Commit author `MohammadKaifSaiyad <saiyedkgn6@gmail.com>` (`git -c user.name=MohammadKaifSaiyad -c user.email=saiyedkgn6@gmail.com commit …`); NO Co-Authored-By / Claude trailer.
- NEVER stage `apps/customer/ios/*`, `apps/customer/ios/Podfile.lock`, or any `xcshareddata/swiftpm/` folder (founder-owned leftovers). Stage files by explicit path.
- Golden Rule 1/2/3/5 — money: integer paise everywhere; a payout is recorded ONLY by ops' explicit pay action, inside one transaction holding the technician row lock; cash debt is netted (`CASH_DEBT_OFFSET`) before any `PAYOUT`; every request / pay / reject writes its `SETTLEMENT_EVENT` audit row in the SAME transaction. A request can never be paid twice and a payout can never exceed what is owed.
- Golden Rule 7 — no PII in logs / audit metadata (ids, paise, statuses and ops' reason only); the admin list shows the phone only via `maskPhone()`; no `console.log` of request bodies; no `print`/`debugPrint`.
- Backend: auth first (`requireAuth` preHandler), Zod at the boundary (params, query AND body), DB writes in the service layer, DTOs only, TS strict, no `any`; errors via `src/shared/errors.ts` classes (`{code, message}` envelope).
- App: Riverpod + repositories only (UI never touches dio); no global dio content-type; bodyless requests carry no body; busy flags reset in `try/finally`; `if (!mounted) return;` after every await before touching `context`/`setState`; money only via `rupees()` (`lib/core/format.dart`); Failure messages shown verbatim; unexpected throws reported via `FlutterError.reportError` (exception + stack + a static context only).
- Exact copy (use verbatim):
  - 409 `PAYOUT_ALREADY_REQUESTED`: `You already have a payout request in progress`
  - 422 `PAYOUT_BELOW_MINIMUM`: `Payouts start at ` + the minimum formatted as whole rupees (`₹100`)
  - 409 `PAYOUT_REQUEST_NOT_OPEN`: `This payout request is no longer open`
  - 409 `NOTHING_TO_PAY`: `Nothing is owed after settling cash debt — reject this request instead`
  - 404: `Payout request not found`
  - app card: `Owed to you`, `pending`, `Cash to hand over`, paused line `New jobs are paused until your cash is settled (₹D of ₹L limit)`
  - app payout: button `Request payout of ₹N`; dialog `Request ₹N? FixCare transfers it and confirms here.` + (when debt > 0) ` Your ₹D cash is settled first.`; below minimum `Payouts start at ₹M`; open `₹N requested on <date> — FixCare will transfer it soon`; paid `₹N paid on <date>`; rejected `Not paid: <reason>`
  - app pending: `Releases <date, time>` / `On hold — under dispute`
  - app history labels: `Earned` · `FixCare fee (20%)` · `Cash collected` · `Cash settled from earnings` · `Paid to you` · `Cash handed over` · `Customer refunded after a dispute`
- Backend tests need the local Docker stack (Postgres + Redis) — check `docker ps`; if it is not running, report BLOCKED (never start/stop containers yourself). Command: `cd apps/backend && set -a && source .env && set +a && pnpm vitest run <file>`; full suite `pnpm vitest run`; `pnpm build` (type-checks tests too — type inject payload helpers as `object`, never `unknown`/`any`). One app instance per test file, 100 requests/minute — keep each file under ~90 injects (split files if needed).
- Migrations apply to BOTH DBs: dev `pnpm prisma migrate dev --name <name>`, test `DATABASE_URL="$TEST_DATABASE_URL" pnpm prisma migrate deploy`. Never `db push`, never edit an applied migration, never hand-edit `_prisma_migrations`; if migrate wants a reset or reports drift, STOP (BLOCKED).
- Known rare flake: `tests/bookings/booking-number.test.ts` "highly unlikely to collide" — re-run once if it fails and note it.
- App tests: `cd apps/technician && flutter test <file>`; full `flutter test`; `flutter analyze` 0 issues. After editing a `@freezed`/`@riverpod` file run `dart run build_runner build --delete-conflicting-outputs` and commit generated files.

## Review Focus

1. **Two ops clicks on "pay" (or pay racing reject)** → exactly one `PAYOUT`, the request ends in exactly one terminal state. Pinned in Task 5 (concurrent pay test; guarded `updateMany` on the request row in both pay and reject).
2. **Cash collected between request and pay** → pay nets the CURRENT debt (not the snapshot) and never overdraws; if nothing is left it refuses (`NOTHING_TO_PAY`) and writes nothing. Pinned in Task 5.
3. **Two statement rows with the same `createdAt`** (the sweep writes EARNING + COMMISSION + OFFSET in one tx) → paging never repeats or drops a row. Pinned in Task 3 (cursor on `(createdAt, id)` + a tie test).
4. **A tap on "Request payout" while the summary is stale** (a request already open on another device) → 409 shown verbatim and the screen refreshes into the "requested" state, never a second request. Pinned in Task 4 (backend 409) and Task 8 (app snack + refresh).
5. **Long reject reasons / service names on a 320 px phone** → wrap, never overflow. Pinned in Tasks 8 and 9.

---

## File map

**Backend (`apps/backend`)**
- `prisma/schema.prisma` + migration `technician_payout_requests` (Task 1)
- `src/shared/config.ts` — `PAYOUT_MIN_PAISE` (Task 1)
- `src/shared/errors.ts` — `UnprocessableError` takes an optional code (Task 4)
- `src/shared/validation/review-reason.ts` — shared `reasonBody` (moved from technicians; Task 5)
- `src/modules/settlements/settlements.types.ts` (new) — DTOs + mappers (Tasks 2–5)
- `src/modules/settlements/settlements.schemas.ts` — query / params schemas (Tasks 3, 5)
- `src/modules/settlements/earnings.service.ts` (new) — summary + statement (Tasks 2–3)
- `src/modules/settlements/payout-requests.service.ts` (new) — request / list / pay / reject (Tasks 4–5)
- `src/modules/settlements/settlements.routes.ts` — 5 routes (Tasks 2–5)
- tests: `tests/settlements/earnings-summary.test.ts`, `tests/settlements/ledger-statement.test.ts`, `tests/settlements/payout-request.test.ts`, `tests/settlements/admin-payouts.test.ts`, `tests/settlements/helpers.ts` (new shared fixtures), `tests/schema/payout-request.test.ts`, `tests/schema/helpers.ts`

**Technician app (`apps/technician`)**
- `lib/core/format.dart` — `formatShortDate`, `formatShortDateTime` (Task 6)
- `lib/features/earnings/data/earnings_dtos.dart` (+ generated), `earnings_repository.dart` (Task 6)
- `lib/features/earnings/presentation/earnings_providers.dart` (+ generated) — summary provider + `LedgerController` (Task 7)
- `lib/features/earnings/presentation/earnings_screen.dart`, `payout_section.dart` (Task 8), `statement_section.dart` (Task 9)
- `lib/features/jobs/presentation/money_card.dart`, `jobs_home_screen.dart`; `lib/features/onboarding/presentation/suspended_screen.dart`; `lib/core/router/app_router.dart` (Tasks 8, 10)
- tests under `test/core/`, `test/earnings/`, `test/jobs/`, `test/onboarding/`, `test/router/`

**Docs** — `docs/06-operations/technician-review-runbook.md`, `STATUS.md`, `CHANGELOG.md` (Task 11)

---

### Task 1: Schema — `PayoutRequest`, config minimum

**Files:**
- Modify: `apps/backend/prisma/schema.prisma` (Technician model relations ~line 104; add enum + model after `LedgerEntry`)
- Create: migration `technician_payout_requests`
- Modify: `apps/backend/src/shared/config.ts` (after `CASH_VELOCITY_CAP_PAISE`)
- Modify: `apps/backend/tests/schema/helpers.ts` (resetDb list)
- Test: `apps/backend/tests/schema/payout-request.test.ts`

**Interfaces:**
- Produces: Prisma `payoutRequest { id, technicianId, amountPaise, status: PayoutRequestStatus, reviewNote?, reviewedBy?, reviewedAt?, payoutEntryId? (unique), createdAt, updatedAt }`, enum `PayoutRequestStatus { REQUESTED PAID REJECTED }`, relation `technician.payoutRequests`; `config.PAYOUT_MIN_PAISE: number` (default 10000).

- [ ] **Step 1: Write the failing test** — `tests/schema/payout-request.test.ts`

```ts
import { beforeEach, describe, expect, it } from 'vitest';
import { prisma, resetDb } from './helpers.js';
import { config } from '../../src/shared/config.js';

async function tech() {
  const user = await prisma.user.create({ data: { phone: '9811100002', role: 'TECHNICIAN' } });
  return prisma.technician.create({ data: { userId: user.id, name: 'Tech', skills: ['AC'] } });
}

describe('PayoutRequest model', () => {
  beforeEach(resetDb);

  it('defaults to REQUESTED with no review fields', async () => {
    const t = await tech();
    const r = await prisma.payoutRequest.create({ data: { technicianId: t.id, amountPaise: 25000 } });
    expect(r.status).toBe('REQUESTED');
    expect(r.reviewNote).toBeNull();
    expect(r.reviewedAt).toBeNull();
    expect(r.payoutEntryId).toBeNull();
  });

  it('a ledger entry backs at most one request (payoutEntryId is unique)', async () => {
    const t = await tech();
    await prisma.payoutRequest.create({ data: { technicianId: t.id, amountPaise: 100, payoutEntryId: 'e1' } });
    await expect(prisma.payoutRequest.create({ data: { technicianId: t.id, amountPaise: 100, payoutEntryId: 'e1' } }))
      .rejects.toMatchObject({ code: 'P2002' });
  });

  it('PAYOUT_MIN_PAISE defaults to ₹100', () => {
    expect(config.PAYOUT_MIN_PAISE).toBe(10000);
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/backend && set -a && source .env && set +a && pnpm vitest run tests/schema/payout-request.test.ts`
Expected: FAIL — `prisma.payoutRequest` undefined / `PAYOUT_MIN_PAISE` undefined.

- [ ] **Step 3: Schema + config**

In `model Technician` relations add `payoutRequests PayoutRequest[]`. After `model LedgerEntry` add:

```prisma
/// A technician's request to be paid what FixCare owes them (net of cash debt). Ops transfers the money by hand, then
/// marks it PAID — which writes the CASH_DEBT_OFFSET (if any) + PAYOUT ledger entries in the same locked transaction —
/// or REJECTED with a reason. One open (REQUESTED) request per technician, enforced under the technician row lock.
model PayoutRequest {
  id            String              @id @default(uuid())
  technicianId  String
  technician    Technician          @relation(fields: [technicianId], references: [id])
  amountPaise   Int                 // the net amount the technician saw when requesting (positive)
  status        PayoutRequestStatus @default(REQUESTED)
  reviewNote    String?             // ops' reject reason, shown to the technician
  reviewedBy    String?             // admin user id
  reviewedAt    DateTime?
  payoutEntryId String?             @unique // the PAYOUT LedgerEntry written when marked paid
  createdAt     DateTime            @default(now())
  updatedAt     DateTime            @updatedAt

  @@index([technicianId, createdAt])
  @@index([status, createdAt])
}

enum PayoutRequestStatus {
  REQUESTED
  PAID
  REJECTED
}
```

`src/shared/config.ts` — after `CASH_VELOCITY_CAP_PAISE`:

```ts
  // Smallest net payout a technician can request (integer paise). Stops ₹12 transfers.
  PAYOUT_MIN_PAISE: z.coerce.number().int().positive().default(10000),
```

`tests/schema/helpers.ts` — add `"PayoutRequest",` to the TRUNCATE list before `"LedgerEntry"`.

- [ ] **Step 4: Migrate both DBs**

```bash
cd apps/backend && set -a && source .env && set +a && pnpm prisma migrate dev --name technician_payout_requests
DATABASE_URL="$TEST_DATABASE_URL" pnpm prisma migrate deploy
```

Expected: one new additive migration (`CREATE TYPE "PayoutRequestStatus"`, `CREATE TABLE "PayoutRequest"`, the unique index on `payoutEntryId`, two indexes, the FK). No `DROP`.

- [ ] **Step 5: Run the test + suite + build** — focused test PASS (3); `pnpm vitest run` green; `pnpm build` clean.

- [ ] **Step 6: Commit**

```bash
git add apps/backend/prisma/schema.prisma apps/backend/prisma/migrations apps/backend/src/shared/config.ts apps/backend/tests/schema/helpers.ts apps/backend/tests/schema/payout-request.test.ts
git commit -m "feat(backend): PayoutRequest model + PAYOUT_MIN_PAISE"
```

---

### Task 2: `GET /technician/me/earnings` — summary

**Files:**
- Create: `apps/backend/src/modules/settlements/settlements.types.ts`, `apps/backend/src/modules/settlements/earnings.service.ts`, `apps/backend/tests/settlements/helpers.ts`
- Modify: `apps/backend/src/modules/settlements/settlements.routes.ts`
- Test: `apps/backend/tests/settlements/earnings-summary.test.ts`

**Interfaces:**
- Consumes: `payableBalancePaise`, `splitPaise` (settlements.service), `config.CASH_DEBT_LIMIT_PAISE`, `config.DISPUTE_WINDOW_HOURS`, `config.PAYOUT_MIN_PAISE`.
- Produces: `EarningsSummaryDto`, `PendingReleaseDto`, `PayoutRequestDto`, `toPayoutRequestDto(r)` (settlements.types); `earningsSummary(userId): Promise<EarningsSummaryDto>`, `technicianForUser(userId): Promise<{ id: string }>` (earnings.service — reused by Tasks 3–4); test fixtures `paidBooking(app, opts)`, `ledger(technicianId, entries)`.

- [ ] **Step 1: Shared test fixtures** — `tests/settlements/helpers.ts`

```ts
import type { buildApp } from '../../src/app.js';
import type { BookingState, LedgerEntryType } from '@prisma/client';
import { prisma } from '../schema/helpers.js';
import { makeCustomer, makeTechnician, seedBookable } from '../bookings/helpers.js';

type App = Awaited<ReturnType<typeof buildApp>>;
export function auth(t: string) { return { authorization: `Bearer ${t}` }; }
function future() { return new Date(Date.now() + 86_400_000).toISOString(); }

/** A booking assigned to `technicianId`, forced into `state` (fixture shortcut — the state machine has its own tests).
 *  labor 60000 / visit fee 14900 from seedBookable. */
export async function assignedBooking(app: App, technicianId: string, state: BookingState, extra: { paidAt?: Date | null; declinedAt?: Date } = {}) {
  const c = await makeCustomer();
  const f = await seedBookable(c.customerId);
  const b = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json() as { id: string; bookingNumber: string };
  await prisma.booking.update({ where: { id: b.id }, data: { state, technicianId, ...extra } });
  return { bookingId: b.id, bookingNumber: b.bookingNumber, serviceName: f.service.name };
}

/** Seed ledger rows directly (amounts positive, as the ledger stores them). */
export async function ledger(technicianId: string, rows: { type: LedgerEntryType; amountPaise: number; bookingId?: string; createdAt?: Date }[]) {
  for (const r of rows) await prisma.ledgerEntry.create({ data: { technicianId, type: r.type, amountPaise: r.amountPaise, bookingId: r.bookingId ?? null, ...(r.createdAt ? { createdAt: r.createdAt } : {}) } });
}

export { makeTechnician };
```

- [ ] **Step 2: Write the failing test** — `tests/settlements/earnings-summary.test.ts`

```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer } from '../bookings/helpers.js';
import { assignedBooking, auth, ledger, makeTechnician } from './helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
const get = (token: string) => app.inject({ method: 'GET', url: '/technician/me/earnings', headers: auth(token) });

describe('GET /technician/me/earnings', () => {
  it('owed comes from the ledger; net = owed − debt; limit, minimum and blocked flag reported', async () => {
    const t = await makeTechnician(['AC']);
    await ledger(t.technicianId, [
      { type: 'EARNING_CREDIT', amountPaise: 48000 }, { type: 'COMMISSION', amountPaise: 12000 },
      { type: 'CASH_DEBT_OFFSET', amountPaise: 5000 }, { type: 'PAYOUT', amountPaise: 10000 },
    ]);
    await prisma.technician.update({ where: { id: t.technicianId }, data: { cashDebtPaise: 20000 } });
    const res = await get(t.token);
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({
      owedPaise: 33000, netPayoutPaise: 13000, cashDebtPaise: 20000, cashDebtLimitPaise: 50000,
      acceptBlocked: false, payoutMinPaise: 10000, pendingPaise: 0, pending: [], latestPayoutRequest: null,
    });
  });

  it('acceptBlocked only ABOVE the limit (same rule as accept)', async () => {
    const t = await makeTechnician(['AC']);
    await prisma.technician.update({ where: { id: t.technicianId }, data: { cashDebtPaise: 50000 } });
    expect((await get(t.token)).json().acceptBlocked).toBe(false);
    await prisma.technician.update({ where: { id: t.technicianId }, data: { cashDebtPaise: 50001 } });
    expect((await get(t.token)).json().acceptBlocked).toBe(true);
  });

  it('net never goes below 0', async () => {
    const t = await makeTechnician(['AC']);
    await ledger(t.technicianId, [{ type: 'EARNING_CREDIT', amountPaise: 1000 }]);
    await prisma.technician.update({ where: { id: t.technicianId }, data: { cashDebtPaise: 5000 } });
    expect((await get(t.token)).json().netPayoutPaise).toBe(0);
  });

  it('pending: own PAYMENT_RECEIVED with the sweep share + release time; DISPUTED on hold; others excluded', async () => {
    const t = await makeTechnician(['AC']);
    const other = await makeTechnician(['AC']);
    const paidAt = new Date('2026-10-05T08:30:00.000Z');
    const labor = await assignedBooking(app, t.technicianId, 'PAYMENT_RECEIVED', { paidAt });
    const declined = await assignedBooking(app, t.technicianId, 'PAYMENT_RECEIVED', { paidAt, declinedAt: new Date() });
    const disputed = await assignedBooking(app, t.technicianId, 'DISPUTED', { paidAt });
    await assignedBooking(app, t.technicianId, 'CLOSED', { paidAt });
    await assignedBooking(app, other.technicianId, 'PAYMENT_RECEIVED', { paidAt });
    const body = (await get(t.token)).json();
    const byId = new Map((body.pending as Array<{ bookingId: string }>).map((p) => [p.bookingId, p]));
    expect(byId.size).toBe(3);
    expect(byId.get(labor.bookingId)).toEqual({
      bookingId: labor.bookingId, bookingNumber: labor.bookingNumber, serviceName: labor.serviceName,
      amountPaise: 48000, releasesAt: '2026-10-07T08:30:00.000Z', onHold: false,
    });
    expect(byId.get(declined.bookingId)).toMatchObject({ amountPaise: 11920, onHold: false });
    expect(byId.get(disputed.bookingId)).toMatchObject({ amountPaise: 48000, onHold: true, releasesAt: null });
    expect(body.pendingPaise).toBe(48000 + 11920);
  });

  it('reports the latest payout request (newest by createdAt)', async () => {
    const t = await makeTechnician(['AC']);
    await prisma.payoutRequest.create({ data: { technicianId: t.technicianId, amountPaise: 15000, status: 'PAID', createdAt: new Date('2026-10-01T00:00:00Z'), reviewedAt: new Date('2026-10-02T00:00:00Z') } });
    await prisma.payoutRequest.create({ data: { technicianId: t.technicianId, amountPaise: 20000, status: 'REJECTED', reviewNote: 'Bank details not confirmed', createdAt: new Date('2026-10-03T00:00:00Z'), reviewedAt: new Date('2026-10-04T00:00:00Z') } });
    expect((await get(t.token)).json().latestPayoutRequest).toEqual({
      id: expect.any(String), status: 'REJECTED', amountPaise: 20000, requestedAt: '2026-10-03T00:00:00.000Z',
      reviewedAt: '2026-10-04T00:00:00.000Z', reviewNote: 'Bank details not confirmed',
    });
  });

  it('works for a SUSPENDED technician; customer → 403; no token → 401', async () => {
    const t = await makeTechnician(['AC'], 'SUSPENDED');
    expect((await get(t.token)).statusCode).toBe(200);
    const c = await makeCustomer();
    expect((await get(c.token)).statusCode).toBe(403);
    expect((await app.inject({ method: 'GET', url: '/technician/me/earnings' })).statusCode).toBe(401);
  });
});
```

- [ ] **Step 3: Run it to verify it fails** — `pnpm vitest run tests/settlements/earnings-summary.test.ts` → FAIL (404 route).

- [ ] **Step 4: Types** — `src/modules/settlements/settlements.types.ts`

```ts
import type { PayoutRequest } from '@prisma/client';

export interface PayoutRequestDto {
  id: string;
  status: PayoutRequest['status'];
  amountPaise: number;
  requestedAt: string;
  reviewedAt: string | null;
  reviewNote: string | null;
}

export function toPayoutRequestDto(r: PayoutRequest): PayoutRequestDto {
  return {
    id: r.id, status: r.status, amountPaise: r.amountPaise, requestedAt: r.createdAt.toISOString(),
    reviewedAt: r.reviewedAt?.toISOString() ?? null, reviewNote: r.reviewNote,
  };
}

export interface PendingReleaseDto {
  bookingId: string;
  bookingNumber: string;
  serviceName: string;
  amountPaise: number;
  /** When the settlement sweep may release it (paidAt + dispute window); null when on hold or unpaid. */
  releasesAt: string | null;
  /** The booking is DISPUTED — the amount is the full expected share, released only after resolution. */
  onHold: boolean;
}

export interface EarningsSummaryDto {
  owedPaise: number;
  netPayoutPaise: number;
  pendingPaise: number;
  cashDebtPaise: number;
  cashDebtLimitPaise: number;
  acceptBlocked: boolean;
  payoutMinPaise: number;
  pending: PendingReleaseDto[];
  latestPayoutRequest: PayoutRequestDto | null;
}
```

- [ ] **Step 5: Service** — `src/modules/settlements/earnings.service.ts`

```ts
import { prisma } from '../../shared/database/prisma.js';
import { config } from '../../shared/config.js';
import { ForbiddenError } from '../../shared/errors.js';
import { payableBalancePaise, splitPaise } from './settlements.service.js';
import { toPayoutRequestDto, type EarningsSummaryDto, type PendingReleaseDto } from './settlements.types.js';

/** The caller's technician row (any status — a suspended technician is still owed their money). */
export async function technicianForUser(userId: string): Promise<{ id: string }> {
  const t = await prisma.technician.findFirst({ where: { userId, deletedAt: null }, select: { id: true } });
  if (!t) throw new ForbiddenError('Technician profile required');
  return t;
}

export async function earningsSummary(userId: string): Promise<EarningsSummaryDto> {
  const tech = await technicianForUser(userId);
  // One snapshot: balance, debt, pending and the latest request read in the same transaction.
  return prisma.$transaction(async (tx) => {
    const owedPaise = await payableBalancePaise(tx, tech.id);
    const { cashDebtPaise } = await tx.technician.findUniqueOrThrow({ where: { id: tech.id }, select: { cashDebtPaise: true } });
    const bookings = await tx.booking.findMany({
      where: { technicianId: tech.id, deletedAt: null, state: { in: ['PAYMENT_RECEIVED', 'DISPUTED'] } },
      select: { id: true, bookingNumber: true, state: true, paidAt: true, declinedAt: true, laborPaise: true, visitFeePaise: true, service: { select: { name: true } } },
      orderBy: { paidAt: 'asc' },
    });
    const windowMs = config.DISPUTE_WINDOW_HOURS * 3600_000;
    const pending: PendingReleaseDto[] = bookings.map((b) => {
      const onHold = b.state === 'DISPUTED';
      // The sweep's exact base: the visit fee when the estimate was declined, else labor.
      const base = b.declinedAt != null ? b.visitFeePaise : b.laborPaise;
      return {
        bookingId: b.id, bookingNumber: b.bookingNumber, serviceName: b.service.name,
        amountPaise: splitPaise(base).earningPaise,
        releasesAt: onHold || !b.paidAt ? null : new Date(b.paidAt.getTime() + windowMs).toISOString(),
        onHold,
      };
    });
    const latest = await tx.payoutRequest.findFirst({ where: { technicianId: tech.id }, orderBy: { createdAt: 'desc' } });
    return {
      owedPaise,
      netPayoutPaise: Math.max(0, owedPaise - cashDebtPaise),
      pendingPaise: pending.filter((p) => !p.onHold).reduce((s, p) => s + p.amountPaise, 0),
      cashDebtPaise,
      cashDebtLimitPaise: config.CASH_DEBT_LIMIT_PAISE,
      acceptBlocked: cashDebtPaise > config.CASH_DEBT_LIMIT_PAISE, // the exact rule acceptJob uses
      payoutMinPaise: config.PAYOUT_MIN_PAISE,
      pending,
      latestPayoutRequest: latest ? toPayoutRequestDto(latest) : null,
    };
  });
}
```

- [ ] **Step 6: Route** — in `settlements.routes.ts` add (import `ForbiddenError` and `earningsSummary`):

```ts
  app.get('/technician/me/earnings', { preHandler: [requireAuth] }, async (req, reply) => {
    if (req.user!.role !== 'TECHNICIAN') throw new ForbiddenError('Technician access required');
    return reply.send(await earningsSummary(req.user!.id));
  });
```

- [ ] **Step 7: Run tests + suite + build** — focused PASS (6); `pnpm vitest run` green (existing settlements tests unchanged); `pnpm build` clean.

- [ ] **Step 8: Commit**

```bash
git add apps/backend/src/modules/settlements apps/backend/tests/settlements/helpers.ts apps/backend/tests/settlements/earnings-summary.test.ts
git commit -m "feat(backend): technician earnings summary (owed, pending, cash debt, latest payout request)"
```

---

### Task 3: `GET /technician/me/ledger` — statement with a tie-safe cursor

**Files:**
- Modify: `apps/backend/src/modules/settlements/settlements.types.ts`, `earnings.service.ts`, `settlements.schemas.ts`, `settlements.routes.ts`
- Test: `apps/backend/tests/settlements/ledger-statement.test.ts`

**Interfaces:**
- Consumes: `technicianForUser` (Task 2).
- Produces: `LedgerEntryDto { id, type, amountPaise, bookingNumber: string|null, serviceName: string|null, createdAt }`, `LedgerPageDto { entries, nextCursor: string|null }`; `ledgerStatement(userId, { before?: string; limit: number })`; schema `ledgerQuery`.

- [ ] **Step 1: Write the failing test** — `tests/settlements/ledger-statement.test.ts`

```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer } from '../bookings/helpers.js';
import { assignedBooking, auth, ledger, makeTechnician } from './helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
const page = (token: string, qs = '') => app.inject({ method: 'GET', url: `/technician/me/ledger${qs}`, headers: auth(token) });

describe('GET /technician/me/ledger', () => {
  it('newest first; booking number + service on job rows only; own rows only', async () => {
    const t = await makeTechnician(['AC']);
    const other = await makeTechnician(['AC']);
    const b = await assignedBooking(app, t.technicianId, 'CLOSED');
    await ledger(t.technicianId, [
      { type: 'EARNING_CREDIT', amountPaise: 48000, bookingId: b.bookingId, createdAt: new Date('2026-10-01T00:00:00Z') },
      { type: 'PAYOUT', amountPaise: 48000, createdAt: new Date('2026-10-02T00:00:00Z') },
    ]);
    await ledger(other.technicianId, [{ type: 'EARNING_CREDIT', amountPaise: 1 }]);
    const res = await page(t.token);
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({
      entries: [
        { id: expect.any(String), type: 'PAYOUT', amountPaise: 48000, bookingNumber: null, serviceName: null, createdAt: '2026-10-02T00:00:00.000Z' },
        { id: expect.any(String), type: 'EARNING_CREDIT', amountPaise: 48000, bookingNumber: b.bookingNumber, serviceName: b.serviceName, createdAt: '2026-10-01T00:00:00.000Z' },
      ],
      nextCursor: null,
    });
  });

  it('pages through rows with identical timestamps without repeating or skipping', async () => {
    const t = await makeTechnician(['AC']);
    const same = new Date('2026-10-03T10:00:00Z');
    await ledger(t.technicianId, Array.from({ length: 5 }, (_, i) => ({ type: 'EARNING_CREDIT' as const, amountPaise: 100 + i, createdAt: same })));
    const seen: string[] = [];
    let cursor: string | null = null;
    do {
      const qs: string = `?limit=2${cursor ? `&before=${encodeURIComponent(cursor)}` : ''}`;
      const body = (await page(t.token, qs)).json() as { entries: { id: string }[]; nextCursor: string | null };
      seen.push(...body.entries.map((e) => e.id));
      cursor = body.nextCursor;
    } while (cursor);
    expect(seen).toHaveLength(5);
    expect(new Set(seen).size).toBe(5);
  });

  it('400 for a bad limit or cursor; 403 for a customer', async () => {
    const t = await makeTechnician(['AC']);
    for (const qs of ['?limit=0', '?limit=51', '?limit=abc', '?before=not-a-cursor', '?x=1']) {
      expect((await page(t.token, qs)).statusCode).toBe(400);
    }
    const c = await makeCustomer();
    expect((await page(c.token)).statusCode).toBe(403);
  });
});
```

- [ ] **Step 2: Run it to verify it fails** → FAIL (404).

- [ ] **Step 3: Schema** — append to `settlements.schemas.ts`:

```ts
/** Opaque statement cursor: base64url of `<ISO createdAt>|<entry id>` — (createdAt, id) keeps ties stable. */
export function encodeLedgerCursor(createdAt: Date, id: string): string {
  return Buffer.from(`${createdAt.toISOString()}|${id}`).toString('base64url');
}
export function decodeLedgerCursor(cursor: string): { createdAt: Date; id: string } | null {
  const raw = Buffer.from(cursor, 'base64url').toString('utf8');
  const [iso, id, ...rest] = raw.split('|');
  if (!iso || !id || rest.length > 0) return null;
  const createdAt = new Date(iso);
  if (Number.isNaN(createdAt.getTime()) || createdAt.toISOString() !== iso) return null;
  if (!z.string().uuid().safeParse(id).success) return null;
  return { createdAt, id };
}

export const ledgerQuery = z.object({
  limit: z.coerce.number().int().min(1).max(50).default(20),
  before: z.string().min(1).refine((c) => decodeLedgerCursor(c) !== null, 'Invalid cursor').optional(),
}).strict();
export type LedgerQuery = z.infer<typeof ledgerQuery>;
```

- [ ] **Step 4: Types + service** — append to `settlements.types.ts`:

```ts
export interface LedgerEntryDto {
  id: string;
  type: string;
  amountPaise: number;
  bookingNumber: string | null;
  serviceName: string | null;
  createdAt: string;
}
export interface LedgerPageDto { entries: LedgerEntryDto[]; nextCursor: string | null; }
```

Append to `earnings.service.ts` (import `decodeLedgerCursor`, `encodeLedgerCursor`, `type LedgerQuery`, `type LedgerPageDto`):

```ts
export async function ledgerStatement(userId: string, q: LedgerQuery): Promise<LedgerPageDto> {
  const tech = await technicianForUser(userId);
  const c = q.before ? decodeLedgerCursor(q.before) : null;
  const rows = await prisma.ledgerEntry.findMany({
    where: {
      technicianId: tech.id,
      ...(c ? { OR: [{ createdAt: { lt: c.createdAt } }, { createdAt: c.createdAt, id: { lt: c.id } }] } : {}),
    },
    orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
    take: q.limit + 1, // one extra row tells us whether another page exists
    include: { booking: { select: { bookingNumber: true, service: { select: { name: true } } } } },
  });
  const pageRows = rows.slice(0, q.limit);
  const last = pageRows[pageRows.length - 1];
  return {
    entries: pageRows.map((e) => ({
      id: e.id, type: e.type, amountPaise: e.amountPaise,
      bookingNumber: e.booking?.bookingNumber ?? null, serviceName: e.booking?.service.name ?? null,
      createdAt: e.createdAt.toISOString(),
    })),
    nextCursor: rows.length > q.limit && last ? encodeLedgerCursor(last.createdAt, last.id) : null,
  };
}
```

- [ ] **Step 5: Route** — in `settlements.routes.ts` (import `ledgerQuery`, `ledgerStatement`, `ValidationError` already imported):

```ts
  app.get('/technician/me/ledger', { preHandler: [requireAuth] }, async (req, reply) => {
    if (req.user!.role !== 'TECHNICIAN') throw new ForbiddenError('Technician access required');
    const p = ledgerQuery.safeParse(req.query);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.send(await ledgerStatement(req.user!.id, p.data));
  });
```

- [ ] **Step 6: Run tests + suite + build** — focused PASS (3); full suite + build green.

- [ ] **Step 7: Commit**

```bash
git add apps/backend/src/modules/settlements apps/backend/tests/settlements/ledger-statement.test.ts
git commit -m "feat(backend): technician money statement with a tie-safe cursor"
```

---

### Task 4: `POST /technician/me/payout-requests`

**Files:**
- Modify: `apps/backend/src/shared/errors.ts` (`UnprocessableError` optional code)
- Create: `apps/backend/src/modules/settlements/payout-requests.service.ts`
- Modify: `apps/backend/src/modules/settlements/settlements.routes.ts`
- Test: `apps/backend/tests/settlements/payout-request.test.ts`

**Interfaces:**
- Consumes: `technicianForUser` (Task 2), `payableBalancePaise`, `toPayoutRequestDto`, `config.PAYOUT_MIN_PAISE`, `formatPaise` (`src/shared/utils/currency.ts`).
- Produces: `requestPayout(userId): Promise<PayoutRequestDto>`; codes `PAYOUT_ALREADY_REQUESTED`, `PAYOUT_BELOW_MINIMUM`; `UnprocessableError(message?, code?)`.

- [ ] **Step 1: Write the failing test** — `tests/settlements/payout-request.test.ts`

```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer } from '../bookings/helpers.js';
import { auth, ledger, makeTechnician } from './helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
const request = (token: string) => app.inject({ method: 'POST', url: '/technician/me/payout-requests', headers: auth(token) });

describe('POST /technician/me/payout-requests', () => {
  it('requests the NET amount (owed − cash debt); audited; returned as the latest request', async () => {
    const t = await makeTechnician(['AC']);
    await ledger(t.technicianId, [{ type: 'EARNING_CREDIT', amountPaise: 60000 }]);
    await prisma.technician.update({ where: { id: t.technicianId }, data: { cashDebtPaise: 40000 } });
    const res = await request(t.token);
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ status: 'REQUESTED', amountPaise: 20000, reviewedAt: null, reviewNote: null });
    const audit = await prisma.auditLog.findFirstOrThrow({ where: { action: 'SETTLEMENT_EVENT' } });
    expect(audit.metadata).toMatchObject({ event: 'payout_requested', technicianId: t.technicianId, amountPaise: 20000 });
    expect((await app.inject({ method: 'GET', url: '/technician/me/earnings', headers: auth(t.token) })).json().latestPayoutRequest.status).toBe('REQUESTED');
  });

  it('422 PAYOUT_BELOW_MINIMUM when the net amount is under ₹100', async () => {
    const t = await makeTechnician(['AC']);
    await ledger(t.technicianId, [{ type: 'EARNING_CREDIT', amountPaise: 15000 }]);
    await prisma.technician.update({ where: { id: t.technicianId }, data: { cashDebtPaise: 6000 } }); // net 9000
    const res = await request(t.token);
    expect(res.statusCode).toBe(422);
    expect(res.json()).toEqual({ code: 'PAYOUT_BELOW_MINIMUM', message: 'Payouts start at ₹100' });
    expect(await prisma.payoutRequest.count()).toBe(0);
  });

  it('409 PAYOUT_ALREADY_REQUESTED while one is open; allowed again after it is paid or rejected', async () => {
    const t = await makeTechnician(['AC']);
    await ledger(t.technicianId, [{ type: 'EARNING_CREDIT', amountPaise: 60000 }]);
    expect((await request(t.token)).statusCode).toBe(200);
    const again = await request(t.token);
    expect(again.statusCode).toBe(409);
    expect(again.json()).toEqual({ code: 'PAYOUT_ALREADY_REQUESTED', message: 'You already have a payout request in progress' });
    await prisma.payoutRequest.updateMany({ data: { status: 'REJECTED', reviewNote: 'x', reviewedAt: new Date() } });
    expect((await request(t.token)).statusCode).toBe(200);
  });

  it('two simultaneous requests → exactly one is created', async () => {
    const t = await makeTechnician(['AC']);
    await ledger(t.technicianId, [{ type: 'EARNING_CREDIT', amountPaise: 60000 }]);
    const [a, b] = await Promise.all([request(t.token), request(t.token)]);
    expect([a.statusCode, b.statusCode].sort()).toEqual([200, 409]);
    expect(await prisma.payoutRequest.count({ where: { status: 'REQUESTED' } })).toBe(1);
  });

  it('a SUSPENDED technician can request; a customer cannot; no token → 401', async () => {
    const t = await makeTechnician(['AC'], 'SUSPENDED');
    await ledger(t.technicianId, [{ type: 'EARNING_CREDIT', amountPaise: 60000 }]);
    expect((await request(t.token)).statusCode).toBe(200);
    const c = await makeCustomer();
    expect((await request(c.token)).statusCode).toBe(403);
    expect((await app.inject({ method: 'POST', url: '/technician/me/payout-requests' })).statusCode).toBe(401);
  });
});
```

- [ ] **Step 2: Run it to verify it fails** → FAIL (404).

- [ ] **Step 3: Error class** — `src/shared/errors.ts`:

```ts
export class UnprocessableError extends AppError {
  constructor(message = 'Unprocessable', code = 'UNPROCESSABLE') { super(message, 422, code); }
}
```

(Optional second argument — every existing caller keeps compiling.)

- [ ] **Step 4: Service** — `src/modules/settlements/payout-requests.service.ts`

```ts
import { prisma } from '../../shared/database/prisma.js';
import { config } from '../../shared/config.js';
import { ConflictError, UnprocessableError } from '../../shared/errors.js';
import { formatPaise } from '../../shared/utils/currency.js';
import { payableBalancePaise } from './settlements.service.js';
import { technicianForUser } from './earnings.service.js';
import { toPayoutRequestDto, type PayoutRequestDto } from './settlements.types.js';

/** "₹100" for whole rupees, "₹100.50" otherwise. */
const rupeeLabel = (paise: number) => formatPaise(paise).replace(/\.00$/, '');

/** The technician asks to be paid everything owed, net of the cash they hold. One open request at a time —
 *  enforced under the technician row lock (the same lock recordPayout / pay use), so two taps can't create two. */
export async function requestPayout(userId: string): Promise<PayoutRequestDto> {
  const tech = await technicianForUser(userId);
  return prisma.$transaction(async (tx) => {
    await tx.$queryRaw`SELECT id FROM "Technician" WHERE id = ${tech.id} FOR UPDATE`;
    const open = await tx.payoutRequest.findFirst({ where: { technicianId: tech.id, status: 'REQUESTED' }, select: { id: true } });
    if (open) throw new ConflictError('You already have a payout request in progress', 'PAYOUT_ALREADY_REQUESTED');
    const owed = await payableBalancePaise(tx, tech.id);
    const { cashDebtPaise } = await tx.technician.findUniqueOrThrow({ where: { id: tech.id }, select: { cashDebtPaise: true } });
    const net = Math.max(0, owed - cashDebtPaise);
    if (net < config.PAYOUT_MIN_PAISE) {
      throw new UnprocessableError(`Payouts start at ${rupeeLabel(config.PAYOUT_MIN_PAISE)}`, 'PAYOUT_BELOW_MINIMUM');
    }
    const created = await tx.payoutRequest.create({ data: { technicianId: tech.id, amountPaise: net } });
    await tx.auditLog.create({
      data: { action: 'SETTLEMENT_EVENT', actorType: 'USER', actorId: userId, subjectId: tech.id, metadata: { event: 'payout_requested', technicianId: tech.id, payoutRequestId: created.id, amountPaise: net } },
    });
    return toPayoutRequestDto(created);
  });
}
```

- [ ] **Step 5: Route** — in `settlements.routes.ts`:

```ts
  app.post('/technician/me/payout-requests', { preHandler: [requireAuth] }, async (req, reply) => {
    if (req.user!.role !== 'TECHNICIAN') throw new ForbiddenError('Technician access required');
    return reply.send(await requestPayout(req.user!.id));
  });
```

- [ ] **Step 6: Run tests + suite + build** — focused PASS (5); full suite + build green.

- [ ] **Step 7: Commit**

```bash
git add apps/backend/src/shared/errors.ts apps/backend/src/modules/settlements apps/backend/tests/settlements/payout-request.test.ts
git commit -m "feat(backend): technician payout request (net of cash debt, one open at a time)"
```

---

### Task 5: Ops payout queue — list, pay (net then pay), reject

**Files:**
- Create: `apps/backend/src/shared/validation/review-reason.ts`
- Modify: `apps/backend/src/modules/technicians/technicians.schemas.ts` (re-export `reasonBody` from the shared file)
- Modify: `apps/backend/src/modules/settlements/settlements.types.ts`, `settlements.schemas.ts`, `payout-requests.service.ts`, `settlements.routes.ts`
- Test: `apps/backend/tests/settlements/admin-payouts.test.ts`

**Interfaces:**
- Consumes: Tasks 1–4; `makeAdmin(level)`, `makeAdminToken(level)` (`tests/bookings/helpers.ts`); `maskPhone`.
- Produces: `AdminPayoutRequestDto { id, technicianId, technicianName, maskedPhone, amountPaise, status, requestedAt, reviewedAt, reviewNote, paidPaise: number|null, currentOwedPaise, currentCashDebtPaise }`; `listPayoutRequests(status?)`, `payPayoutRequest(adminUserId, id)`, `rejectPayoutRequest(adminUserId, id, reason)`; codes `PAYOUT_REQUEST_NOT_OPEN`, `NOTHING_TO_PAY`; shared `reasonBody` in `src/shared/validation/review-reason.ts`.

- [ ] **Step 1: Write the failing test** — `tests/settlements/admin-payouts.test.ts`

```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeAdmin, makeAdminToken, makeCustomer } from '../bookings/helpers.js';
import { debtBalancePaise, payableBalancePaise } from '../../src/modules/settlements/settlements.service.js';
import { auth, ledger, makeTechnician } from './helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
const post = (token: string, url: string, payload?: object) =>
  app.inject({ method: 'POST', url, headers: auth(token), ...(payload === undefined ? {} : { payload }) });

/** A technician owed `owed`, holding `debt` (ledger + cached column consistent), with an open request. */
async function openRequest(owed: number, debt = 0) {
  const t = await makeTechnician(['AC']);
  await ledger(t.technicianId, [{ type: 'EARNING_CREDIT', amountPaise: owed }, ...(debt ? [{ type: 'CASH_COLLECTED' as const, amountPaise: debt }] : [])]);
  if (debt) await prisma.technician.update({ where: { id: t.technicianId }, data: { cashDebtPaise: debt } });
  const r = (await post(t.token, '/technician/me/payout-requests')).json() as { id: string };
  return { t, requestId: r.id };
}

describe('admin payout requests', () => {
  it('walls: 401 without a token; 403 for SUPPORT, customer, technician', async () => {
    const { t, requestId } = await openRequest(60000);
    const callers = [await makeAdminToken('SUPPORT'), (await makeCustomer()).token, t.token];
    const routes = [
      { method: 'GET' as const, url: '/admin/payout-requests' },
      { method: 'POST' as const, url: `/admin/payout-requests/${requestId}/pay` },
      { method: 'POST' as const, url: `/admin/payout-requests/${requestId}/reject`, payload: { reason: 'x' } },
    ];
    for (const r of routes) {
      expect((await app.inject(r)).statusCode).toBe(401);
      for (const token of callers) expect((await app.inject({ ...r, headers: auth(token) })).statusCode).toBe(403);
    }
  });

  it('lists oldest first with masked phone + current balances; filters by status', async () => {
    const a = await openRequest(60000);
    const b = await openRequest(30000, 5000);
    const admin = await makeAdminToken();
    const res = await app.inject({ method: 'GET', url: '/admin/payout-requests?status=REQUESTED', headers: auth(admin) });
    expect(res.statusCode).toBe(200);
    const list = res.json() as Array<Record<string, unknown>>;
    expect(list.map((r) => r.id)).toEqual([a.requestId, b.requestId]);
    const phone = (await prisma.user.findUniqueOrThrow({ where: { id: b.t.userId } })).phone;
    expect(list[1]).toMatchObject({ technicianName: 'Tech', maskedPhone: `••••••${phone.slice(-4)}`, amountPaise: 25000, status: 'REQUESTED', paidPaise: null, currentOwedPaise: 30000, currentCashDebtPaise: 5000 });
    expect(res.body).not.toContain(phone);
    expect((await app.inject({ method: 'GET', url: '/admin/payout-requests?status=NOPE', headers: auth(admin) })).statusCode).toBe(400);
  });

  it('pay: nets the CURRENT cash debt first, then pays the rest; PAID + linked entry; ledger debt == cached debt', async () => {
    const { t, requestId } = await openRequest(60000, 10000); // requested 50000
    await ledger(t.technicianId, [{ type: 'CASH_COLLECTED', amountPaise: 5000 }]); // more cash collected after the request
    await prisma.technician.update({ where: { id: t.technicianId }, data: { cashDebtPaise: 15000 } });
    const admin = await makeAdmin();
    const res = await post(admin.token, `/admin/payout-requests/${requestId}/pay`);
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ status: 'PAID', amountPaise: 50000, paidPaise: 45000, currentOwedPaise: 0, currentCashDebtPaise: 0 });
    const req = await prisma.payoutRequest.findUniqueOrThrow({ where: { id: requestId } });
    const payout = await prisma.ledgerEntry.findUniqueOrThrow({ where: { id: req.payoutEntryId! } });
    expect(payout).toMatchObject({ type: 'PAYOUT', amountPaise: 45000 });
    expect(await prisma.ledgerEntry.count({ where: { technicianId: t.technicianId, type: 'CASH_DEBT_OFFSET', amountPaise: 15000 } })).toBe(1);
    expect(await payableBalancePaise(prisma, t.technicianId)).toBe(0);
    expect(await debtBalancePaise(prisma, t.technicianId)).toBe(0);
    expect((await prisma.technician.findUniqueOrThrow({ where: { id: t.technicianId } })).cashDebtPaise).toBe(0);
    const audit = await prisma.auditLog.findFirstOrThrow({ where: { action: 'SETTLEMENT_EVENT', actorId: admin.userId } });
    expect(audit.metadata).toMatchObject({ event: 'payout_request_paid', payoutRequestId: requestId, requestedPaise: 50000, offsetPaise: 15000, paidPaise: 45000 });
  });

  it('pay: 409 NOTHING_TO_PAY when debt now covers everything (nothing written); 409 when not open; 404 missing', async () => {
    const { t, requestId } = await openRequest(30000); // requested 30000
    await ledger(t.technicianId, [{ type: 'CASH_COLLECTED', amountPaise: 30000 }]);
    await prisma.technician.update({ where: { id: t.technicianId }, data: { cashDebtPaise: 30000 } });
    const admin = await makeAdminToken();
    const res = await post(admin, `/admin/payout-requests/${requestId}/pay`);
    expect(res.statusCode).toBe(409);
    expect(res.json()).toEqual({ code: 'NOTHING_TO_PAY', message: 'Nothing is owed after settling cash debt — reject this request instead' });
    expect(await prisma.ledgerEntry.count({ where: { type: { in: ['PAYOUT', 'CASH_DEBT_OFFSET'] } } })).toBe(0);
    expect((await prisma.technician.findUniqueOrThrow({ where: { id: t.technicianId } })).cashDebtPaise).toBe(30000);
    expect((await post(admin, `/admin/payout-requests/${requestId}/reject`, { reason: 'Covered by your cash collections' })).statusCode).toBe(200);
    const notOpen = await post(admin, `/admin/payout-requests/${requestId}/pay`);
    expect(notOpen.json()).toEqual({ code: 'PAYOUT_REQUEST_NOT_OPEN', message: 'This payout request is no longer open' });
    expect((await post(admin, '/admin/payout-requests/00000000-0000-0000-0000-000000000000/pay')).statusCode).toBe(404);
    expect((await post(admin, '/admin/payout-requests/not-a-uuid/pay')).statusCode).toBe(400);
  });

  it('two concurrent pays of one request → exactly one PAYOUT', async () => {
    const { requestId } = await openRequest(60000);
    const admin = await makeAdminToken();
    const [a, b] = await Promise.all([post(admin, `/admin/payout-requests/${requestId}/pay`), post(admin, `/admin/payout-requests/${requestId}/pay`)]);
    expect([a.statusCode, b.statusCode].sort()).toEqual([200, 409]);
    expect(await prisma.ledgerEntry.count({ where: { type: 'PAYOUT' } })).toBe(1);
  });

  it('pay racing reject → exactly one terminal state, at most one PAYOUT', async () => {
    const { requestId } = await openRequest(60000);
    const admin = await makeAdminToken();
    const [p, r] = await Promise.all([post(admin, `/admin/payout-requests/${requestId}/pay`), post(admin, `/admin/payout-requests/${requestId}/reject`, { reason: 'Duplicate' })]);
    expect([p.statusCode, r.statusCode].sort()).toEqual([200, 409]);
    const final = await prisma.payoutRequest.findUniqueOrThrow({ where: { id: requestId } });
    expect(await prisma.ledgerEntry.count({ where: { type: 'PAYOUT' } })).toBe(final.status === 'PAID' ? 1 : 0);
  });

  it('reject: reason rules; REJECTED + note; audited; technician sees it', async () => {
    const { t, requestId } = await openRequest(60000);
    const admin = await makeAdmin();
    const url = `/admin/payout-requests/${requestId}/reject`;
    for (const payload of [undefined, {}, { reason: '  ' }, { reason: 'x'.repeat(501) }, { reason: 'call 98765 43210' }, { reason: 'ok', extra: 1 }]) {
      expect((await post(admin.token, url, payload)).statusCode).toBe(400);
    }
    const res = await post(admin.token, url, { reason: 'Bank details not confirmed yet' });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ status: 'REJECTED', reviewNote: 'Bank details not confirmed yet', paidPaise: null });
    const audit = await prisma.auditLog.findFirstOrThrow({ where: { action: 'SETTLEMENT_EVENT', actorId: admin.userId } });
    expect(audit.metadata).toMatchObject({ event: 'payout_request_rejected', payoutRequestId: requestId });
    const latest = (await app.inject({ method: 'GET', url: '/technician/me/earnings', headers: auth(t.token) })).json().latestPayoutRequest;
    expect(latest).toMatchObject({ status: 'REJECTED', reviewNote: 'Bank details not confirmed yet' });
  });
});
```

- [ ] **Step 2: Run it to verify it fails** → FAIL (404).

- [ ] **Step 3: Shared reason schema** — create `src/shared/validation/review-reason.ts` by MOVING the existing `reasonBody` definition (its trim, 1..500 and separator-stripped 10+-digit refine, with the exact existing messages) out of `src/modules/technicians/technicians.schemas.ts`; in `technicians.schemas.ts` replace the definition with `export { reasonBody } from '../../shared/validation/review-reason.js';`. Behavior must not change (the technicians tests prove it).

- [ ] **Step 4: Types + schemas** — append to `settlements.types.ts`:

```ts
export interface AdminPayoutRequestDto extends PayoutRequestDto {
  technicianId: string;
  technicianName: string;
  maskedPhone: string;
  /** Amount of the PAYOUT entry when PAID (may differ from amountPaise if money moved in between). */
  paidPaise: number | null;
  currentOwedPaise: number;
  currentCashDebtPaise: number;
}
```

Append to `settlements.schemas.ts`:

```ts
export const payoutRequestIdParams = z.object({ id: z.string().uuid('Invalid payout request id') });
export const listPayoutRequestsQuery = z.object({ status: z.enum(['REQUESTED', 'PAID', 'REJECTED']).optional() }).strict();
```

- [ ] **Step 5: Service** — append to `payout-requests.service.ts` (imports: `NotFoundError`; `maskPhone` from `../../shared/utils/mask.js`; `type PayoutRequestStatus` from `@prisma/client`; `type AdminPayoutRequestDto`):

```ts
const NOT_OPEN = () => new ConflictError('This payout request is no longer open', 'PAYOUT_REQUEST_NOT_OPEN');

async function toAdminDtos(ids: string[]): Promise<AdminPayoutRequestDto[]> {
  const rows = await prisma.payoutRequest.findMany({
    where: { id: { in: ids } },
    include: { technician: { select: { name: true, cashDebtPaise: true, user: { select: { phone: true } } } } },
    orderBy: { createdAt: 'asc' },
  });
  const entryIds = rows.map((r) => r.payoutEntryId).filter((x): x is string => x !== null);
  const entries = await prisma.ledgerEntry.findMany({ where: { id: { in: entryIds } }, select: { id: true, amountPaise: true } });
  const paidById = new Map(entries.map((e) => [e.id, e.amountPaise]));
  const owedByTech = new Map<string, number>();
  for (const techId of new Set(rows.map((r) => r.technicianId))) owedByTech.set(techId, await payableBalancePaise(prisma, techId));
  return rows.map((r) => ({
    ...toPayoutRequestDto(r),
    technicianId: r.technicianId,
    technicianName: r.technician.name,
    maskedPhone: maskPhone(r.technician.user.phone),
    paidPaise: r.payoutEntryId ? paidById.get(r.payoutEntryId) ?? null : null,
    currentOwedPaise: owedByTech.get(r.technicianId) ?? 0,
    currentCashDebtPaise: r.technician.cashDebtPaise,
  }));
}

/** Ops' queue, oldest first. */
export async function listPayoutRequests(status?: PayoutRequestStatus): Promise<AdminPayoutRequestDto[]> {
  const ids = await prisma.payoutRequest.findMany({ where: status ? { status } : {}, orderBy: { createdAt: 'asc' }, select: { id: true } });
  return toAdminDtos(ids.map((r) => r.id));
}

/** Ops transferred the money by hand: net the technician's CURRENT cash debt first (CASH_DEBT_OFFSET, like the
 *  sweep), then record the PAYOUT for the rest, and close the request — one transaction under the technician row
 *  lock. The request row is updated with a status guard, so a racing pay/reject can never both win. */
export async function payPayoutRequest(adminUserId: string, requestId: string): Promise<AdminPayoutRequestDto> {
  await prisma.$transaction(async (tx) => {
    const req = await tx.payoutRequest.findUnique({ where: { id: requestId }, select: { technicianId: true } });
    if (!req) throw new NotFoundError('Payout request not found');
    await tx.$queryRaw`SELECT id FROM "Technician" WHERE id = ${req.technicianId} FOR UPDATE`;
    const fresh = await tx.payoutRequest.findUniqueOrThrow({ where: { id: requestId } });
    if (fresh.status !== 'REQUESTED') throw NOT_OPEN();
    const owed = await payableBalancePaise(tx, req.technicianId);
    const { cashDebtPaise } = await tx.technician.findUniqueOrThrow({ where: { id: req.technicianId }, select: { cashDebtPaise: true } });
    const offset = Math.min(Math.max(owed, 0), cashDebtPaise);
    const pay = owed - offset;
    if (pay <= 0) throw new ConflictError('Nothing is owed after settling cash debt — reject this request instead', 'NOTHING_TO_PAY');
    if (offset > 0) {
      await tx.technician.update({ where: { id: req.technicianId }, data: { cashDebtPaise: { decrement: offset } } });
      await tx.ledgerEntry.create({ data: { technicianId: req.technicianId, type: 'CASH_DEBT_OFFSET', amountPaise: offset, metadata: { payoutRequestId: requestId } } });
    }
    const entry = await tx.ledgerEntry.create({ data: { technicianId: req.technicianId, type: 'PAYOUT', amountPaise: pay, metadata: { payoutRequestId: requestId } } });
    const closed = await tx.payoutRequest.updateMany({
      where: { id: requestId, status: 'REQUESTED' },
      data: { status: 'PAID', payoutEntryId: entry.id, reviewedBy: adminUserId, reviewedAt: new Date() },
    });
    if (closed.count === 0) throw NOT_OPEN(); // a reject landed in between — roll everything back
    await tx.auditLog.create({
      data: { action: 'SETTLEMENT_EVENT', actorType: 'ADMIN', actorId: adminUserId, subjectId: req.technicianId, metadata: { event: 'payout_request_paid', payoutRequestId: requestId, technicianId: req.technicianId, requestedPaise: fresh.amountPaise, offsetPaise: offset, paidPaise: pay } },
    });
  });
  return (await toAdminDtos([requestId]))[0]!;
}

export async function rejectPayoutRequest(adminUserId: string, requestId: string, reason: string): Promise<AdminPayoutRequestDto> {
  await prisma.$transaction(async (tx) => {
    const req = await tx.payoutRequest.findUnique({ where: { id: requestId }, select: { technicianId: true } });
    if (!req) throw new NotFoundError('Payout request not found');
    const closed = await tx.payoutRequest.updateMany({
      where: { id: requestId, status: 'REQUESTED' },
      data: { status: 'REJECTED', reviewNote: reason, reviewedBy: adminUserId, reviewedAt: new Date() },
    });
    if (closed.count === 0) throw NOT_OPEN();
    await tx.auditLog.create({
      data: { action: 'SETTLEMENT_EVENT', actorType: 'ADMIN', actorId: adminUserId, subjectId: req.technicianId, metadata: { event: 'payout_request_rejected', payoutRequestId: requestId, technicianId: req.technicianId, reason } },
    });
  });
  return (await toAdminDtos([requestId]))[0]!;
}
```

- [ ] **Step 6: Routes** — in `settlements.routes.ts` (imports: `listPayoutRequestsQuery`, `payoutRequestIdParams`, `reasonBody` from `../../shared/validation/review-reason.js`, the three service functions). Use the existing inline `safeParse → ValidationError` style:

```ts
  const manager = { preHandler: [requireAuth, requireAdminLevel('MANAGER')] };

  app.get('/admin/payout-requests', manager, async (req, reply) => {
    const q = listPayoutRequestsQuery.safeParse(req.query);
    if (!q.success) throw new ValidationError(q.error.issues[0]?.message ?? 'Invalid input');
    return reply.send(await listPayoutRequests(q.data.status));
  });

  app.post('/admin/payout-requests/:id/pay', manager, async (req, reply) => {
    const p = payoutRequestIdParams.safeParse(req.params);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.send(await payPayoutRequest(req.user!.id, p.data.id));
  });

  app.post('/admin/payout-requests/:id/reject', manager, async (req, reply) => {
    const p = payoutRequestIdParams.safeParse(req.params);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    const b = reasonBody.safeParse(req.body);
    if (!b.success) throw new ValidationError(b.error.issues[0]?.message ?? 'Invalid input');
    return reply.send(await rejectPayoutRequest(req.user!.id, p.data.id, b.data.reason));
  });
```

- [ ] **Step 7: Run tests + suite + build** — focused PASS (7); `pnpm vitest run` green (incl. `tests/technicians/*` after the reason move and the existing `tests/settlements/*`); `pnpm build` clean.

- [ ] **Step 8: Commit**

```bash
git add apps/backend/src/shared/validation apps/backend/src/modules/technicians/technicians.schemas.ts apps/backend/src/modules/settlements apps/backend/tests/settlements/admin-payouts.test.ts
git commit -m "feat(backend): ops payout queue — pay nets cash debt first, reject with a reason"
```

---

### Task 6: Technician app — date helpers, DTOs, repository

**Files:**
- Modify: `apps/technician/lib/core/format.dart`; Test: `apps/technician/test/core/format_test.dart`
- Create: `apps/technician/lib/features/earnings/data/earnings_dtos.dart` (+ generated), `earnings_repository.dart`
- Test: `apps/technician/test/earnings/earnings_repository_test.dart`

**Interfaces:**
- Produces: `String formatShortDate(String iso)` → `3 Oct`; `String formatShortDateTime(String iso)` → `5 Oct, 2:00 pm` (local time); freezed `EarningsSummaryDto`, `PendingReleaseDto`, `PayoutRequestDto`, `LedgerEntryDto`, `LedgerPageDto` (fields exactly as the backend JSON in Tasks 2–4); `EarningsRepository(Dio)` with `summary()`, `ledger({String? before, int limit = 20})`, `requestPayout()`, all `Future<Result<…>>`; `earningsRepositoryProvider`.

- [ ] **Step 1: Write the failing tests**

Append to `test/core/format_test.dart`:

```dart
  test('formatShortDate / formatShortDateTime render local day + month (+ time)', () {
    final d = DateTime(2026, 10, 5, 14, 0).toUtc().toIso8601String();
    expect(formatShortDate(d), '5 Oct');
    expect(formatShortDateTime(d), '5 Oct, 2:00 pm');
    final midnight = DateTime(2026, 10, 3, 0, 5).toUtc().toIso8601String();
    expect(formatShortDateTime(midnight), '3 Oct, 12:05 am');
  });
```

`test/earnings/earnings_repository_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/features/earnings/data/earnings_repository.dart';

Map<String, dynamic> summaryJson() => {
      'owedPaise': 33000, 'netPayoutPaise': 13000, 'pendingPaise': 48000, 'cashDebtPaise': 20000,
      'cashDebtLimitPaise': 50000, 'acceptBlocked': false, 'payoutMinPaise': 10000,
      'pending': [
        {'bookingId': 'b1', 'bookingNumber': 'FC-1', 'serviceName': 'AC gas refill', 'amountPaise': 48000, 'releasesAt': '2026-10-07T08:30:00.000Z', 'onHold': false},
        {'bookingId': 'b2', 'bookingNumber': 'FC-2', 'serviceName': 'Fan repair', 'amountPaise': 8000, 'releasesAt': null, 'onHold': true},
      ],
      'latestPayoutRequest': {'id': 'p1', 'status': 'REJECTED', 'amountPaise': 20000, 'requestedAt': '2026-10-03T00:00:00.000Z', 'reviewedAt': '2026-10-04T00:00:00.000Z', 'reviewNote': 'Bank details not confirmed'},
    };

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late EarningsRepository repo;
  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://test', validateStatus: (_) => true));
    adapter = DioAdapter(dio: dio, matcher: const FullHttpRequestMatcher(needsExactBody: true));
    repo = EarningsRepository(dio);
  });

  test('summary is a bodyless GET and parses every field', () async {
    adapter.onGet('/technician/me/earnings', (s) => s.reply(200, summaryJson()));
    final v = (await repo.summary() as Ok<EarningsSummaryDto>).value;
    expect(v.owedPaise, 33000);
    expect(v.netPayoutPaise, 13000);
    expect(v.pending, hasLength(2));
    expect(v.pending.last.onHold, true);
    expect(v.pending.last.releasesAt, isNull);
    expect(v.latestPayoutRequest!.status, 'REJECTED');
    expect(v.latestPayoutRequest!.reviewNote, 'Bank details not confirmed');
  });

  test('summary with no request parses latestPayoutRequest as null', () async {
    adapter.onGet('/technician/me/earnings', (s) => s.reply(200, {...summaryJson(), 'pending': <Object>[], 'latestPayoutRequest': null}));
    expect((await repo.summary() as Ok<EarningsSummaryDto>).value.latestPayoutRequest, isNull);
  });

  test('ledger sends limit (+ before when given) and parses the page', () async {
    adapter.onGet('/technician/me/ledger', (s) => s.reply(200, {
          'entries': [
            {'id': 'e1', 'type': 'EARNING_CREDIT', 'amountPaise': 48000, 'bookingNumber': 'FC-1', 'serviceName': 'AC gas refill', 'createdAt': '2026-10-01T00:00:00.000Z'},
            {'id': 'e2', 'type': 'PAYOUT', 'amountPaise': 10000, 'bookingNumber': null, 'serviceName': null, 'createdAt': '2026-09-30T00:00:00.000Z'},
          ],
          'nextCursor': 'abc',
        }), queryParameters: {'limit': 20, 'before': 'xyz'});
    final v = (await repo.ledger(before: 'xyz') as Ok<LedgerPageDto>).value;
    expect(v.entries.map((e) => e.type), ['EARNING_CREDIT', 'PAYOUT']);
    expect(v.entries.last.bookingNumber, isNull);
    expect(v.nextCursor, 'abc');
  });

  test('requestPayout is a bodyless POST; 409 keeps code + message', () async {
    adapter.onPost('/technician/me/payout-requests', (s) => s.reply(200, {'id': 'p2', 'status': 'REQUESTED', 'amountPaise': 13000, 'requestedAt': '2026-10-07T00:00:00.000Z', 'reviewedAt': null, 'reviewNote': null}));
    expect((await repo.requestPayout() as Ok<PayoutRequestDto>).value.status, 'REQUESTED');
    adapter.onPost('/technician/me/payout-requests', (s) => s.reply(409, {'code': 'PAYOUT_ALREADY_REQUESTED', 'message': 'You already have a payout request in progress'}));
    final f = await repo.requestPayout() as Failure;
    expect(f.code, 'PAYOUT_ALREADY_REQUESTED');
    expect(f.message, 'You already have a payout request in progress');
  });

  test('network error → Failure(network)', () async {
    adapter.onGet('/technician/me/earnings', (s) => s.throws(0, DioException.connectionError(requestOptions: RequestOptions(path: '/technician/me/earnings'), reason: 'down')));
    expect((await repo.summary() as Failure).kind, FailureKind.network);
  });
}
```

- [ ] **Step 2: Run to verify they fail** — `cd apps/technician && flutter test test/core/format_test.dart test/earnings/earnings_repository_test.dart` → compile errors.

- [ ] **Step 3: Date helpers** — append to `lib/core/format.dart` (reusing its private `_months` / `_timeLabel`):

```dart
/// "3 Oct" in local time from an ISO (UTC) string.
String formatShortDate(String iso) {
  final d = DateTime.parse(iso).toLocal();
  return '${d.day} ${_months[d.month - 1]}';
}

/// "5 Oct, 2:00 pm" in local time from an ISO (UTC) string.
String formatShortDateTime(String iso) {
  final d = DateTime.parse(iso).toLocal();
  return '${d.day} ${_months[d.month - 1]}, ${_timeLabel(d)}';
}
```

- [ ] **Step 4: DTOs** — `lib/features/earnings/data/earnings_dtos.dart`

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
part 'earnings_dtos.freezed.dart';
part 'earnings_dtos.g.dart';

@freezed
abstract class PendingReleaseDto with _$PendingReleaseDto {
  const factory PendingReleaseDto({
    required String bookingId,
    required String bookingNumber,
    required String serviceName,
    required int amountPaise,
    String? releasesAt,
    @Default(false) bool onHold,
  }) = _PendingReleaseDto;
  factory PendingReleaseDto.fromJson(Map<String, dynamic> j) => _$PendingReleaseDtoFromJson(j);
}

@freezed
abstract class PayoutRequestDto with _$PayoutRequestDto {
  const factory PayoutRequestDto({
    required String id,
    required String status, // REQUESTED | PAID | REJECTED
    required int amountPaise,
    required String requestedAt,
    String? reviewedAt,
    String? reviewNote,
  }) = _PayoutRequestDto;
  factory PayoutRequestDto.fromJson(Map<String, dynamic> j) => _$PayoutRequestDtoFromJson(j);
}

@freezed
abstract class EarningsSummaryDto with _$EarningsSummaryDto {
  const factory EarningsSummaryDto({
    required int owedPaise,
    required int netPayoutPaise,
    required int pendingPaise,
    required int cashDebtPaise,
    required int cashDebtLimitPaise,
    required bool acceptBlocked,
    required int payoutMinPaise,
    @Default(<PendingReleaseDto>[]) List<PendingReleaseDto> pending,
    PayoutRequestDto? latestPayoutRequest,
  }) = _EarningsSummaryDto;
  factory EarningsSummaryDto.fromJson(Map<String, dynamic> j) => _$EarningsSummaryDtoFromJson(j);
}

@freezed
abstract class LedgerEntryDto with _$LedgerEntryDto {
  const factory LedgerEntryDto({
    required String id,
    required String type,
    required int amountPaise,
    String? bookingNumber,
    String? serviceName,
    required String createdAt,
  }) = _LedgerEntryDto;
  factory LedgerEntryDto.fromJson(Map<String, dynamic> j) => _$LedgerEntryDtoFromJson(j);
}

@freezed
abstract class LedgerPageDto with _$LedgerPageDto {
  const factory LedgerPageDto({
    @Default(<LedgerEntryDto>[]) List<LedgerEntryDto> entries,
    String? nextCursor,
  }) = _LedgerPageDto;
  factory LedgerPageDto.fromJson(Map<String, dynamic> j) => _$LedgerPageDtoFromJson(j);
}
```

Run `dart run build_runner build --delete-conflicting-outputs`.

- [ ] **Step 5: Repository** — `lib/features/earnings/data/earnings_repository.dart`

```dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/result.dart';
import 'earnings_dtos.dart';

export 'earnings_dtos.dart';

class EarningsRepository {
  EarningsRepository(this._dio);
  final Dio _dio;

  String _msg(dynamic data) =>
      (data is Map && data['message'] is String) ? data['message'] as String : 'Something went wrong.';

  Future<Result<T>> _call<T>(Future<Response> Function() send, T Function(Map<String, dynamic>) parse) async {
    try {
      final res = await send();
      final status = res.statusCode ?? 0;
      if (status >= 200 && status < 300) {
        final data = res.data;
        if (data is! Map) return const Failure(FailureKind.server, 'Unexpected response from the server.');
        return Ok(parse(data.cast<String, dynamic>()));
      }
      return Failure(failureKindFromStatus(status), _msg(res.data), code: errorCodeOf(res.data));
    } on DioException catch (e) {
      if (e.response != null) {
        return Failure(failureKindFromStatus(e.response!.statusCode), _msg(e.response!.data), code: errorCodeOf(e.response!.data));
      }
      return const Failure(FailureKind.network, 'Network error. Check your connection.');
    }
  }

  Future<Result<EarningsSummaryDto>> summary() => _call(() => _dio.get('/technician/me/earnings'), EarningsSummaryDto.fromJson);

  Future<Result<LedgerPageDto>> ledger({String? before, int limit = 20}) => _call(
        () => _dio.get('/technician/me/ledger', queryParameters: {'limit': limit, if (before case final String b) 'before': b}),
        LedgerPageDto.fromJson,
      );

  /// Bodyless: the backend computes the net amount.
  Future<Result<PayoutRequestDto>> requestPayout() => _call(() => _dio.post('/technician/me/payout-requests'), PayoutRequestDto.fromJson);
}

final earningsRepositoryProvider = Provider<EarningsRepository>((ref) => EarningsRepository(ref.read(dioProvider)));
```

- [ ] **Step 6: Run tests + analyze** — focused PASS; `flutter test` green; `flutter analyze` 0.

- [ ] **Step 7: Commit**

```bash
git add apps/technician/lib/core/format.dart apps/technician/test/core/format_test.dart apps/technician/lib/features/earnings/data apps/technician/test/earnings/earnings_repository_test.dart
git commit -m "feat(technician): earnings DTOs, repository and short date helpers"
```

---

### Task 7: Technician app — summary provider + `LedgerController`

**Files:**
- Create: `apps/technician/lib/features/earnings/presentation/earnings_providers.dart` (+ generated)
- Test: `apps/technician/test/earnings/earnings_providers_test.dart`

**Interfaces:**
- Consumes: Task 6 repository + DTOs.
- Produces: `earningsSummaryProvider` (`FutureProvider<EarningsSummaryDto>` via `@Riverpod(retry: noAutoRetry)` — never auto-retries; throws `EarningsLoadException(message)` on Failure); `ledgerControllerProvider` (`AsyncNotifier<LedgerState>`); `class LedgerState { List<LedgerEntryDto> entries; String? nextCursor; bool loadingMore; String? loadMoreError; }`; `LedgerController.loadMore()`, `LedgerController.refresh()`.

- [ ] **Step 1: Write the failing test** — `test/earnings/earnings_providers_test.dart`

```dart
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/features/earnings/data/earnings_repository.dart';
import 'package:fixcare_technician/features/earnings/presentation/earnings_providers.dart';

LedgerEntryDto _e(String id) => LedgerEntryDto(id: id, type: 'EARNING_CREDIT', amountPaise: 100, createdAt: '2026-10-01T00:00:00.000Z');

class _FakeRepo extends EarningsRepository {
  _FakeRepo() : super(Dio());
  int summaryCalls = 0;
  Result<EarningsSummaryDto> summaryResult = const Failure(FailureKind.server, 'boom');
  final pages = <String?, Result<LedgerPageDto>>{};
  final ledgerCalls = <String?>[];
  Completer<void>? gate;
  @override
  Future<Result<EarningsSummaryDto>> summary() async {
    summaryCalls++;
    return summaryResult;
  }
  @override
  Future<Result<LedgerPageDto>> ledger({String? before, int limit = 20}) async {
    ledgerCalls.add(before);
    if (gate case final g?) await g.future;
    return pages[before] ?? const Ok(LedgerPageDto());
  }
}

void main() {
  late _FakeRepo repo;
  late ProviderContainer c;
  setUp(() {
    repo = _FakeRepo();
    c = ProviderContainer(overrides: [earningsRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(c.dispose);
  });

  test('summary failure surfaces as EarningsLoadException and is NOT auto-retried', () async {
    final sub = c.listen(earningsSummaryProvider, (_, _) {});
    addTearDown(sub.close);
    await expectLater(c.read(earningsSummaryProvider.future), throwsA(isA<EarningsLoadException>()));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(repo.summaryCalls, 1);
  });

  test('ledger: first page, loadMore appends with the cursor, stops at the end', () async {
    repo.pages[null] = Ok(LedgerPageDto(entries: [_e('a'), _e('b')], nextCursor: 'c1'));
    repo.pages['c1'] = Ok(LedgerPageDto(entries: [_e('c')]));
    final first = await c.read(ledgerControllerProvider.future);
    expect(first.entries.map((e) => e.id), ['a', 'b']);
    await c.read(ledgerControllerProvider.notifier).loadMore();
    final after = c.read(ledgerControllerProvider).value!;
    expect(after.entries.map((e) => e.id), ['a', 'b', 'c']);
    expect(after.nextCursor, isNull);
    await c.read(ledgerControllerProvider.notifier).loadMore();
    expect(repo.ledgerCalls, [null, 'c1']); // no call past the end
  });

  test('loadMore while one is in flight is a no-op; a failure is kept as loadMoreError', () async {
    repo.pages[null] = Ok(LedgerPageDto(entries: [_e('a')], nextCursor: 'c1'));
    await c.read(ledgerControllerProvider.future);
    repo.gate = Completer<void>();
    repo.pages['c1'] = const Failure(FailureKind.network, 'Network error. Check your connection.');
    final n = c.read(ledgerControllerProvider.notifier);
    final f1 = n.loadMore();
    final f2 = n.loadMore();
    repo.gate!.complete();
    await Future.wait([f1, f2]);
    expect(repo.ledgerCalls, [null, 'c1']);
    final s = c.read(ledgerControllerProvider).value!;
    expect(s.entries.map((e) => e.id), ['a']);
    expect(s.loadMoreError, 'Network error. Check your connection.');
    expect(s.loadingMore, false);
  });

  test('a loadMore that lands after a refresh is dropped', () async {
    repo.pages[null] = Ok(LedgerPageDto(entries: [_e('a')], nextCursor: 'c1'));
    await c.read(ledgerControllerProvider.future);
    repo.gate = Completer<void>();
    repo.pages['c1'] = Ok(LedgerPageDto(entries: [_e('stale')]));
    final n = c.read(ledgerControllerProvider.notifier);
    final more = n.loadMore();
    repo.pages[null] = Ok(LedgerPageDto(entries: [_e('fresh')]));
    final refreshed = n.refresh();
    repo.gate!.complete();
    await Future.wait([more, refreshed]);
    expect(c.read(ledgerControllerProvider).value!.entries.map((e) => e.id), ['fresh']);
  });
}
```

- [ ] **Step 2: Run to verify it fails** → compile error.

- [ ] **Step 3: Implement** — `lib/features/earnings/presentation/earnings_providers.dart`

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/result.dart';
import '../data/earnings_repository.dart';

part 'earnings_providers.g.dart';

/// A definitive load failure carrying the backend's message verbatim (shown with a Retry button).
class EarningsLoadException implements Exception {
  const EarningsLoadException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Money screens never auto-retry — the UI offers Retry (Riverpod 3 retries a throwing build by default).
Duration? noAutoRetry(int retryCount, Object error) => null;

@Riverpod(retry: noAutoRetry)
Future<EarningsSummaryDto> earningsSummary(Ref ref) async {
  final r = await ref.read(earningsRepositoryProvider).summary();
  return switch (r) {
    Ok(value: final v) => v,
    Failure(message: final m) => throw EarningsLoadException(m),
  };
}

class LedgerState {
  const LedgerState({required this.entries, this.nextCursor, this.loadingMore = false, this.loadMoreError});
  final List<LedgerEntryDto> entries;
  final String? nextCursor;
  final bool loadingMore;
  final String? loadMoreError;

  LedgerState copyWith({List<LedgerEntryDto>? entries, String? nextCursor, bool clearCursor = false, bool? loadingMore, String? loadMoreError, bool clearError = false}) =>
      LedgerState(
        entries: entries ?? this.entries,
        nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
        loadingMore: loadingMore ?? this.loadingMore,
        loadMoreError: clearError ? null : (loadMoreError ?? this.loadMoreError),
      );
}

/// The paged money statement. Every fetch takes a generation number; a page that lands after a refresh started is
/// dropped, so a late "Load more" can never splice stale rows into a fresh list.
@Riverpod(retry: noAutoRetry)
class LedgerController extends _$LedgerController {
  int _generation = 0;

  @override
  Future<LedgerState> build() async {
    final gen = ++_generation;
    final r = await ref.read(earningsRepositoryProvider).ledger();
    if (gen != _generation && state.hasValue && !state.hasError) return state.value!;
    return switch (r) {
      Ok(value: final p) => LedgerState(entries: p.entries, nextCursor: p.nextCursor),
      Failure(message: final m) => throw EarningsLoadException(m),
    };
  }

  Future<void> refresh() async {
    final gen = ++_generation;
    final r = await ref.read(earningsRepositoryProvider).ledger();
    if (!ref.mounted || gen != _generation) return;
    state = switch (r) {
      Ok(value: final p) => AsyncData(LedgerState(entries: p.entries, nextCursor: p.nextCursor)),
      Failure(message: final m) => AsyncError(EarningsLoadException(m), StackTrace.current),
    };
  }

  Future<void> loadMore() async {
    final current = state.hasError ? null : state.value;
    if (current == null || current.loadingMore || current.nextCursor == null) return;
    final gen = _generation;
    state = AsyncData(current.copyWith(loadingMore: true, clearError: true));
    final r = await ref.read(earningsRepositoryProvider).ledger(before: current.nextCursor);
    if (!ref.mounted || gen != _generation) return; // a refresh replaced the list meanwhile
    final now = state.hasError ? null : state.value;
    if (now == null) return;
    state = AsyncData(switch (r) {
      Ok(value: final p) => now.copyWith(entries: [...now.entries, ...p.entries], nextCursor: p.nextCursor, clearCursor: p.nextCursor == null, loadingMore: false),
      Failure(message: final m) => now.copyWith(loadingMore: false, loadMoreError: m),
    });
  }
}
```

Run `dart run build_runner build --delete-conflicting-outputs`.

- [ ] **Step 4: Run tests + analyze** — focused PASS (4); `flutter test` green; `flutter analyze` 0.

- [ ] **Step 5: Commit**

```bash
git add apps/technician/lib/features/earnings/presentation apps/technician/test/earnings/earnings_providers_test.dart
git commit -m "feat(technician): earnings summary provider + paged statement controller"
```

---

### Task 8: Earnings screen — summary + payout section; `/earnings` route

**Files:**
- Create: `apps/technician/lib/features/earnings/presentation/earnings_screen.dart`, `payout_section.dart`
- Modify: `apps/technician/lib/core/router/app_router.dart` (add the route)
- Test: `apps/technician/test/earnings/earnings_screen_test.dart`

**Interfaces:**
- Consumes: Tasks 6–7.
- Produces: `EarningsScreen` (key `earningsScreen`; route `/earnings`) whose body is a `RefreshIndicator` + `ListView` holding: `_SummaryBlock` (keys `owedText`, `pendingTotalText`, `cashDebtText`, `pausedText`), `PayoutSection(summary)` (keys `requestPayoutBtn`, `confirmPayoutBtn`, `cancelPayoutBtn`, `payoutMinText`, `payoutStatusText`), and a `StatementSection()` slot that Task 9 fills (in this task use `const SizedBox.shrink(key: Key('statementSlot'))`). Error state: key `earningsError` + `earningsRetryBtn`.

- [ ] **Step 1: Write the failing test** — `test/earnings/earnings_screen_test.dart`

```dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/features/earnings/data/earnings_repository.dart';
import 'package:fixcare_technician/features/earnings/presentation/earnings_screen.dart';

EarningsSummaryDto summary({int owed = 33000, int net = 13000, int debt = 20000, bool blocked = false, PayoutRequestDto? latest}) => EarningsSummaryDto(
      owedPaise: owed, netPayoutPaise: net, pendingPaise: 48000, cashDebtPaise: debt, cashDebtLimitPaise: 50000,
      acceptBlocked: blocked, payoutMinPaise: 10000, latestPayoutRequest: latest);

PayoutRequestDto req(String status, {String? note}) => PayoutRequestDto(
    id: 'p1', status: status, amountPaise: 13000, requestedAt: '2026-10-03T06:00:00.000Z',
    reviewedAt: status == 'REQUESTED' ? null : '2026-10-04T06:00:00.000Z', reviewNote: note);

class _FakeRepo extends EarningsRepository {
  _FakeRepo(this.summaries) : super(Dio());
  final List<Result<EarningsSummaryDto>> summaries;
  int summaryCalls = 0;
  int requestCalls = 0;
  Result<PayoutRequestDto> requestResult = Ok(req('REQUESTED'));
  @override
  Future<Result<EarningsSummaryDto>> summary() async {
    final r = summaries[summaryCalls < summaries.length ? summaryCalls : summaries.length - 1];
    summaryCalls++;
    return r;
  }
  @override
  Future<Result<LedgerPageDto>> ledger({String? before, int limit = 20}) async => const Ok(LedgerPageDto());
  @override
  Future<Result<PayoutRequestDto>> requestPayout() async {
    requestCalls++;
    return requestResult;
  }
}

void main() {
  late _FakeRepo repo;
  Future<void> pump(WidgetTester tester, List<Result<EarningsSummaryDto>> summaries) async {
    repo = _FakeRepo(summaries);
    await tester.pumpWidget(ProviderScope(
      overrides: [earningsRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: EarningsScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('summary block: owed, pending, cash to hand over', (tester) async {
    await pump(tester, [Ok(summary())]);
    expect(find.text('₹330'), findsOneWidget);
    expect(find.byKey(const Key('pendingTotalText')), findsOneWidget);
    expect(find.textContaining('₹200'), findsWidgets); // cash debt
    expect(find.byKey(const Key('pausedText')), findsNothing);
  });

  testWidgets('blocked: paused line with the debt and the limit', (tester) async {
    await pump(tester, [Ok(summary(debt: 60000, blocked: true, net: 0))]);
    expect(find.text('New jobs are paused until your cash is settled (₹600 of ₹500 limit)'), findsOneWidget);
  });

  testWidgets('eligible → confirm dialog (with the cash clause) → request → summary refreshed', (tester) async {
    await pump(tester, [Ok(summary()), Ok(summary(latest: req('REQUESTED')))]);
    await tester.tap(find.byKey(const Key('requestPayoutBtn')));
    await tester.pumpAndSettle();
    expect(find.text('Request ₹130? FixCare transfers it and confirms here. Your ₹200 cash is settled first.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmPayoutBtn')));
    await tester.pumpAndSettle();
    expect(repo.requestCalls, 1);
    expect(repo.summaryCalls, 2);
    expect(find.text('₹130 requested on 3 Oct — FixCare will transfer it soon'), findsOneWidget);
    expect(find.byKey(const Key('requestPayoutBtn')), findsNothing);
  });

  testWidgets('no cash debt → dialog without the cash clause; cancel sends nothing', (tester) async {
    await pump(tester, [Ok(summary(debt: 0, net: 33000))]);
    await tester.tap(find.byKey(const Key('requestPayoutBtn')));
    await tester.pumpAndSettle();
    expect(find.text('Request ₹330? FixCare transfers it and confirms here.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cancelPayoutBtn')));
    await tester.pumpAndSettle();
    expect(repo.requestCalls, 0);
  });

  testWidgets('below the minimum → disabled + "Payouts start at ₹100"', (tester) async {
    await pump(tester, [Ok(summary(net: 9000))]);
    expect(tester.widget<FilledButton>(find.byKey(const Key('requestPayoutBtn'))).onPressed, isNull);
    expect(find.text('Payouts start at ₹100'), findsOneWidget);
  });

  testWidgets('latest paid / rejected states (button back when eligible)', (tester) async {
    await pump(tester, [Ok(summary(latest: req('PAID')))]);
    expect(find.text('₹130 paid on 4 Oct'), findsOneWidget);
    expect(find.byKey(const Key('requestPayoutBtn')), findsOneWidget);
    await pump(tester, [Ok(summary(latest: req('REJECTED', note: 'Bank details not confirmed')))]);
    expect(find.text('Not paid: Bank details not confirmed'), findsOneWidget);
    expect(find.byKey(const Key('requestPayoutBtn')), findsOneWidget);
  });

  testWidgets('409 already requested → message verbatim + summary refreshed', (tester) async {
    await pump(tester, [Ok(summary()), Ok(summary(latest: req('REQUESTED')))]);
    repo.requestResult = const Failure(FailureKind.unknown, 'You already have a payout request in progress', code: 'PAYOUT_ALREADY_REQUESTED');
    await tester.tap(find.byKey(const Key('requestPayoutBtn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmPayoutBtn')));
    await tester.pumpAndSettle();
    expect(find.text('You already have a payout request in progress'), findsOneWidget);
    expect(repo.summaryCalls, 2);
  });

  testWidgets('load error → message + Retry reloads', (tester) async {
    await pump(tester, [const Failure(FailureKind.network, 'Network error. Check your connection.'), Ok(summary())]);
    expect(find.text('Network error. Check your connection.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('earningsRetryBtn')));
    await tester.pumpAndSettle();
    expect(find.text('₹330'), findsOneWidget);
  });

  testWidgets('a 500-char reject reason wraps at 320 px', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester, [Ok(summary(latest: req('REJECTED', note: 'word ' * 100)))]);
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run to verify it fails** → compile error.

- [ ] **Step 3: Payout section** — `lib/features/earnings/presentation/payout_section.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/result.dart';
import '../../../core/theme.dart';
import '../data/earnings_repository.dart';
import 'earnings_providers.dart';

/// Request-payout button + the latest request's status. The amount is always the backend's net figure.
class PayoutSection extends ConsumerStatefulWidget {
  const PayoutSection({super.key, required this.summary});
  final EarningsSummaryDto summary;

  @override
  ConsumerState<PayoutSection> createState() => _PayoutSectionState();
}

class _PayoutSectionState extends ConsumerState<PayoutSection> {
  bool _busy = false;

  Future<void> _request() async {
    final s = widget.summary;
    final cash = s.cashDebtPaise > 0 ? ' Your ${rupees(s.cashDebtPaise)} cash is settled first.' : '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request payout'),
        content: Text('Request ${rupees(s.netPayoutPaise)}? FixCare transfers it and confirms here.$cash'),
        actions: [
          TextButton(key: const Key('cancelPayoutBtn'), onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(key: const Key('confirmPayoutBtn'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Request')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await ref.read(earningsRepositoryProvider).requestPayout();
      if (!mounted) return;
      if (r case Failure(:final message)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
      ref.invalidate(earningsSummaryProvider); // either way: show the server's current state
    } catch (e, st) {
      FlutterError.reportError(FlutterErrorDetails(exception: e, stack: st, library: 'fixcare earnings', context: ErrorDescription('requesting a payout')));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Something went wrong. Please try again.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    final latest = s.latestPayoutRequest;
    final open = latest?.status == 'REQUESTED';
    final eligible = !open && s.netPayoutPaise >= s.payoutMinPaise;
    final status = switch (latest) {
      PayoutRequestDto(status: 'REQUESTED') => '${rupees(latest!.amountPaise)} requested on ${formatShortDate(latest.requestedAt)} — FixCare will transfer it soon',
      PayoutRequestDto(status: 'PAID', reviewedAt: final at?) => '${rupees(latest!.amountPaise)} paid on ${formatShortDate(at)}',
      PayoutRequestDto(status: 'REJECTED') => 'Not paid: ${latest!.reviewNote ?? ''}',
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (status != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(status, key: const Key('payoutStatusText'), style: const TextStyle(fontSize: 14, color: FixCareColors.textSecondary, height: 1.4)),
          ),
        if (!open) ...[
          FilledButton(
            key: const Key('requestPayoutBtn'),
            onPressed: eligible && !_busy ? _request : null,
            child: _busy
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('Request payout of ${rupees(s.netPayoutPaise)}'),
          ),
          if (!eligible)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Payouts start at ${rupees(s.payoutMinPaise)}', key: const Key('payoutMinText'), style: const TextStyle(color: FixCareColors.textMuted)),
            ),
        ],
      ],
    );
  }
}
```

(The `PayoutRequestDto(status: 'PAID', reviewedAt: final at?)` object pattern requires freezed's generated getters — fine; if the analyzer rejects the null-assert inside the switch, bind `latest` to a local non-null variable first. Do not use `!` on anything that can be null at runtime.)

- [ ] **Step 4: Screen** — `lib/features/earnings/presentation/earnings_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../data/earnings_repository.dart';
import 'earnings_providers.dart';
import 'payout_section.dart';

class EarningsScreen extends ConsumerWidget {
  const EarningsScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(earningsSummaryProvider);
    await ref.read(ledgerControllerProvider.notifier).refresh();
    await ref.read(earningsSummaryProvider.future).catchError((_) => const EarningsSummaryDto(
          owedPaise: 0, netPayoutPaise: 0, pendingPaise: 0, cashDebtPaise: 0, cashDebtLimitPaise: 0, acceptBlocked: false, payoutMinPaise: 0));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(earningsSummaryProvider);
    return Scaffold(
      key: const Key('earningsScreen'),
      appBar: AppBar(title: const Text('Earnings')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              switch (async) {
                AsyncData(value: final s) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [_SummaryBlock(summary: s), const SizedBox(height: 20), PayoutSection(summary: s)],
                  ),
                AsyncError(error: final e) => Column(
                    key: const Key('earningsError'),
                    children: [
                      Text('$e', textAlign: TextAlign.center, style: const TextStyle(color: FixCareColors.errorText)),
                      TextButton(key: const Key('earningsRetryBtn'), onPressed: () => ref.invalidate(earningsSummaryProvider), child: const Text('Retry')),
                    ],
                  ),
                _ => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
              },
              const SizedBox(height: 24),
              const SizedBox.shrink(key: Key('statementSlot')), // Task 9: pending + history
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryBlock extends StatelessWidget {
  const _SummaryBlock({required this.summary});
  final EarningsSummaryDto summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: FixCareColors.surface, border: Border.all(color: FixCareColors.border), borderRadius: BorderRadius.circular(FixCareRadii.card)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Owed to you', style: TextStyle(color: FixCareColors.textMuted)),
          Text(rupees(s.owedPaise), key: const Key('owedText'), style: Theme.of(context).textTheme.headlineMedium),
          if (s.pendingPaise > 0) Text('${rupees(s.pendingPaise)} pending', key: const Key('pendingTotalText'), style: const TextStyle(color: FixCareColors.textSecondary)),
          if (s.cashDebtPaise > 0) ...[
            const SizedBox(height: 12),
            Text('Cash to hand over ${rupees(s.cashDebtPaise)}', key: const Key('cashDebtText'), style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
          if (s.acceptBlocked) ...[
            const SizedBox(height: 8),
            Text(
              'New jobs are paused until your cash is settled (${rupees(s.cashDebtPaise)} of ${rupees(s.cashDebtLimitPaise)} limit)',
              key: const Key('pausedText'),
              style: const TextStyle(color: FixCareColors.errorText, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}
```

NOTE for the implementer: the `pendingTotalText` test expects the key present when `pendingPaise > 0` (it is 48000 in the fixture). Simplify `_refresh` if you like (e.g. `await Future.wait([ref.read(ledgerControllerProvider.notifier).refresh(), ref.refresh(earningsSummaryProvider.future).then((_) {}, onError: (_) {})])`) — the requirement is: pull-to-refresh reloads both and never throws out of `onRefresh`.

- [ ] **Step 5: Route** — `app_router.dart`: import the screen and add `GoRoute(path: '/earnings', builder: (_, _) => const EarningsScreen()),` after `/home`. (The non-verified redirect only covers `/job/*` — leave it.)

- [ ] **Step 6: Run tests + analyze** — focused PASS (9); `flutter test` green; `flutter analyze` 0.

- [ ] **Step 7: Commit**

```bash
git add apps/technician/lib/features/earnings/presentation apps/technician/lib/core/router/app_router.dart apps/technician/test/earnings/earnings_screen_test.dart
git commit -m "feat(technician): earnings screen — balance, cash debt, payout request"
```

---

### Task 9: Earnings screen — pending releases + money history

**Files:**
- Create: `apps/technician/lib/features/earnings/presentation/statement_section.dart`
- Modify: `apps/technician/lib/features/earnings/presentation/earnings_screen.dart` (replace the `statementSlot` placeholder with `StatementSection(pending: …)`)
- Test: `apps/technician/test/earnings/statement_section_test.dart`

**Interfaces:**
- Consumes: Tasks 6–8 (`ledgerControllerProvider`, `formatShortDateTime`, `formatShortDate`).
- Produces: `StatementSection({required List<PendingReleaseDto> pending})` (keys: `pending_<bookingId>`, `ledgerRow_<id>`, `loadMoreBtn`, `ledgerError`, `ledgerRetryBtn`, `ledgerEmpty`); `ledgerRowLabel(LedgerEntryDto)` and `ledgerRowEffect(LedgerEntryDto)` (pure functions, exported for tests).

- [ ] **Step 1: Write the failing test** — `test/earnings/statement_section_test.dart`

```dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/features/earnings/data/earnings_repository.dart';
import 'package:fixcare_technician/features/earnings/presentation/statement_section.dart';

LedgerEntryDto e(String id, String type, int paise, {String? booking, String? service}) =>
    LedgerEntryDto(id: id, type: type, amountPaise: paise, bookingNumber: booking, serviceName: service, createdAt: '2026-10-01T06:00:00.000Z');

class _FakeRepo extends EarningsRepository {
  _FakeRepo(this.pages) : super(Dio());
  final Map<String?, Result<LedgerPageDto>> pages;
  final calls = <String?>[];
  @override
  Future<Result<LedgerPageDto>> ledger({String? before, int limit = 20}) async {
    calls.add(before);
    return pages[before] ?? const Ok(LedgerPageDto());
  }
}

void main() {
  test('every ledger type has a label and an effect', () {
    expect(ledgerRowLabel(e('1', 'EARNING_CREDIT', 48000, booking: 'FC-1', service: 'AC gas refill')), 'Earned · FC-1 · AC gas refill');
    expect(ledgerRowEffect(e('1', 'EARNING_CREDIT', 48000)), 'Owed +₹480');
    expect(ledgerRowLabel(e('2', 'COMMISSION', 12000, booking: 'FC-1')), 'FixCare fee (20%) · FC-1');
    expect(ledgerRowEffect(e('2', 'COMMISSION', 12000)), 'Info · ₹120');
    expect(ledgerRowEffect(e('3', 'CASH_COLLECTED', 50000)), 'Cash to hand over +₹500');
    expect(ledgerRowLabel(e('4', 'CASH_DEBT_OFFSET', 5000)), 'Cash settled from earnings');
    expect(ledgerRowEffect(e('4', 'CASH_DEBT_OFFSET', 5000)), 'Owed −₹50 · Cash −₹50');
    expect(ledgerRowEffect(e('5', 'PAYOUT', 10000)), 'Owed −₹100');
    expect(ledgerRowLabel(e('5', 'PAYOUT', 10000)), 'Paid to you');
    expect(ledgerRowEffect(e('6', 'DEBT_REPAYMENT', 2000)), 'Cash −₹20');
    expect(ledgerRowLabel(e('6', 'DEBT_REPAYMENT', 2000)), 'Cash handed over');
    expect(ledgerRowLabel(e('7', 'DISPUTE_REVERSAL', 3000, booking: 'FC-9')), 'Customer refunded after a dispute · FC-9');
    expect(ledgerRowEffect(e('7', 'DISPUTE_REVERSAL', 3000)), 'Info · ₹30');
    expect(ledgerRowEffect(e('8', 'SOMETHING_NEW', 100)), 'Info · ₹1'); // unknown types never crash
  });

  Future<_FakeRepo> pump(WidgetTester tester, Map<String?, Result<LedgerPageDto>> pages, {List<PendingReleaseDto> pending = const []}) async {
    final repo = _FakeRepo(pages);
    await tester.pumpWidget(ProviderScope(
      overrides: [earningsRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(home: Scaffold(body: ListView(children: [StatementSection(pending: pending)]))),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('pending rows: release time or on hold', (tester) async {
    await pump(tester, {}, pending: const [
      PendingReleaseDto(bookingId: 'b1', bookingNumber: 'FC-1', serviceName: 'AC gas refill', amountPaise: 48000, releasesAt: '2026-10-05T08:30:00.000Z'),
      PendingReleaseDto(bookingId: 'b2', bookingNumber: 'FC-2', serviceName: 'Fan repair', amountPaise: 8000, onHold: true),
    ]);
    expect(find.byKey(const Key('pending_b1')), findsOneWidget);
    expect(find.textContaining('Releases '), findsOneWidget);
    expect(find.text('On hold — under dispute'), findsOneWidget);
  });

  testWidgets('history rows + Load more appends once; hidden at the end', (tester) async {
    final repo = await pump(tester, {
      null: Ok(LedgerPageDto(entries: [e('a', 'PAYOUT', 10000)], nextCursor: 'c1')),
      'c1': Ok(LedgerPageDto(entries: [e('b', 'EARNING_CREDIT', 48000, booking: 'FC-1', service: 'AC gas refill')])),
    });
    expect(find.byKey(const Key('ledgerRow_a')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('loadMoreBtn')));
    await tester.tap(find.byKey(const Key('loadMoreBtn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ledgerRow_b')), findsOneWidget);
    expect(find.byKey(const Key('loadMoreBtn')), findsNothing);
    expect(repo.calls, [null, 'c1']);
  });

  testWidgets('empty history → "No money movements yet"; error → Retry', (tester) async {
    await pump(tester, {null: const Ok(LedgerPageDto())});
    expect(find.byKey(const Key('ledgerEmpty')), findsOneWidget);
    await pump(tester, {null: const Failure(FailureKind.network, 'Network error. Check your connection.')});
    expect(find.text('Network error. Check your connection.'), findsOneWidget);
    expect(find.byKey(const Key('ledgerRetryBtn')), findsOneWidget);
  });

  testWidgets('long service names wrap at 320 px', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester, {null: Ok(LedgerPageDto(entries: [e('a', 'EARNING_CREDIT', 48000, booking: 'FC-1', service: 'Split AC deep cleaning and gas refill with leak test ' * 3)]))});
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run to verify it fails** → compile error.

- [ ] **Step 3: Implement** — `lib/features/earnings/presentation/statement_section.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../data/earnings_repository.dart';
import 'earnings_providers.dart';

String _suffix(LedgerEntryDto e) => [if (e.bookingNumber != null) e.bookingNumber!, if (e.serviceName != null) e.serviceName!].map((s) => ' · $s').join();

/// What the row is.
String ledgerRowLabel(LedgerEntryDto e) => switch (e.type) {
      'EARNING_CREDIT' => 'Earned${_suffix(e)}',
      'COMMISSION' => 'FixCare fee (20%)${e.bookingNumber != null ? ' · ${e.bookingNumber}' : ''}',
      'CASH_COLLECTED' => 'Cash collected${e.bookingNumber != null ? ' · ${e.bookingNumber}' : ''}',
      'CASH_DEBT_OFFSET' => 'Cash settled from earnings',
      'PAYOUT' => 'Paid to you',
      'DEBT_REPAYMENT' => 'Cash handed over',
      'DISPUTE_REVERSAL' => 'Customer refunded after a dispute${e.bookingNumber != null ? ' · ${e.bookingNumber}' : ''}',
      _ => 'Other',
    };

/// Which running total the row moves ("Owed" = what FixCare owes them; "Cash" = cash they hold for FixCare).
String ledgerRowEffect(LedgerEntryDto e) {
  final amt = rupees(e.amountPaise);
  return switch (e.type) {
    'EARNING_CREDIT' => 'Owed +$amt',
    'CASH_COLLECTED' => 'Cash to hand over +$amt',
    'CASH_DEBT_OFFSET' => 'Owed −$amt · Cash −$amt',
    'PAYOUT' => 'Owed −$amt',
    'DEBT_REPAYMENT' => 'Cash −$amt',
    _ => 'Info · $amt', // COMMISSION, DISPUTE_REVERSAL, and any future type
  };
}

class StatementSection extends ConsumerWidget {
  const StatementSection({super.key, required this.pending});
  final List<PendingReleaseDto> pending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(ledgerControllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pending.isNotEmpty) ...[
          const Text('Pending', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          for (final p in pending)
            ListTile(
              key: Key('pending_${p.bookingId}'),
              contentPadding: EdgeInsets.zero,
              title: Text('${p.bookingNumber} · ${p.serviceName}'),
              subtitle: Text(p.onHold ? 'On hold — under dispute' : 'Releases ${formatShortDateTime(p.releasesAt ?? '')}'),
              trailing: Text(rupees(p.amountPaise)),
            ),
          const SizedBox(height: 16),
        ],
        const Text('History', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        switch (ledger) {
          AsyncData(value: final s) when s.entries.isEmpty => const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('No money movements yet', key: Key('ledgerEmpty'), style: TextStyle(color: FixCareColors.textMuted)),
            ),
          AsyncData(value: final s) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final e in s.entries)
                  ListTile(
                    key: Key('ledgerRow_${e.id}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(ledgerRowLabel(e)),
                    subtitle: Text('${ledgerRowEffect(e)} · ${formatShortDate(e.createdAt)}'),
                  ),
                if (s.loadMoreError case final err?) Text(err, style: const TextStyle(color: FixCareColors.errorText)),
                if (s.nextCursor != null)
                  TextButton(
                    key: const Key('loadMoreBtn'),
                    onPressed: s.loadingMore ? null : () => ref.read(ledgerControllerProvider.notifier).loadMore(),
                    child: s.loadingMore ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Load more'),
                  ),
              ],
            ),
          AsyncError(error: final err) => Column(
              key: const Key('ledgerError'),
              children: [
                Text('$err', style: const TextStyle(color: FixCareColors.errorText)),
                TextButton(key: const Key('ledgerRetryBtn'), onPressed: () => ref.read(ledgerControllerProvider.notifier).refresh(), child: const Text('Retry')),
              ],
            ),
          _ => const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
        },
      ],
    );
  }
}
```

(Guard the pending `releasesAt` null case so `formatShortDateTime('')` is never called — e.g. show `'Releases soon'` when null and not on hold. Do not ship a path that parses an empty string.)

In `earnings_screen.dart` replace the `statementSlot` placeholder with `if (async case AsyncData(value: final s)) StatementSection(pending: s.pending) else const StatementSection(pending: [])` (or an equivalent that always shows the history).

- [ ] **Step 4: Run tests + analyze** — focused PASS (5); `flutter test` green (Task 8's screen tests still pass); `flutter analyze` 0.

- [ ] **Step 5: Commit**

```bash
git add apps/technician/lib/features/earnings/presentation apps/technician/test/earnings/statement_section_test.dart
git commit -m "feat(technician): pending releases + money history with Load more"
```

---

### Task 10: Jobs home money card; Earnings from the Suspended screen

**Files:**
- Create: `apps/technician/lib/features/jobs/presentation/money_card.dart`
- Modify: `apps/technician/lib/features/jobs/presentation/jobs_home_screen.dart`, `apps/technician/lib/features/onboarding/presentation/suspended_screen.dart`
- Modify tests: `apps/technician/test/jobs/jobs_home_widget_test.dart` (add an earnings repo override), `apps/technician/test/onboarding/suspended_screen_test.dart`, `apps/technician/test/router/token_gate_test.dart`
- Test: `apps/technician/test/jobs/money_card_test.dart`

**Interfaces:**
- Consumes: `earningsSummaryProvider`, `/earnings` route.
- Produces: `MoneyCard` (key `moneyCard`; texts as in the spec; error row key `moneyCardError` + `moneyCardRetryBtn`); Suspended screen button key `earningsBtn`.

- [ ] **Step 1: Write the failing tests**

`test/jobs/money_card_test.dart` — pump `MaterialApp.router` with a tiny `GoRouter` (`/` → `Scaffold(body: MoneyCard())`, `/earnings` → `Text('EARNINGS PAGE')`) and a fake `EarningsRepository`:
- owed `₹330` + `₹480 pending` + `Cash to hand over ₹200` shown; no paused line;
- `acceptBlocked: true, cashDebtPaise: 60000` → `New jobs are paused until your cash is settled (₹600 of ₹500 limit)`;
- summary Failure → `moneyCardError` row with the message + `moneyCardRetryBtn` reloads;
- tap the card → `EARNINGS PAGE` shown; when popped back the summary is fetched again (call count +1).

`test/onboarding/suspended_screen_test.dart` — add: the `earningsBtn` exists; tapping it navigates to `/earnings` (wrap in the same tiny GoRouter pattern).

`test/router/token_gate_test.dart` — add: a SUSPENDED session can `router.go('/earnings')` and stays on `/earnings` (override `earningsRepositoryProvider` with a fake returning an `Ok` summary and an empty ledger page); `/job/b1` still redirects to `/home` (existing test).

`test/jobs/jobs_home_widget_test.dart` — add `earningsRepositoryProvider.overrideWithValue(<fake returning Ok(summary)>)` to its `ProviderScope` overrides so the new card never hits the network; existing assertions unchanged.

- [ ] **Step 2: Run to verify they fail** → compile errors / missing keys.

- [ ] **Step 3: Implement**

`lib/features/jobs/presentation/money_card.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../../earnings/presentation/earnings_providers.dart';

/// Top of jobs home: what FixCare owes them, cash they hold, and whether new jobs are paused. Tap → /earnings.
/// A failed load never blocks the job lists — it shows a one-line Retry.
class MoneyCard extends ConsumerWidget {
  const MoneyCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(earningsSummaryProvider);
    return switch (async) {
      AsyncData(value: final s) => InkWell(
          key: const Key('moneyCard'),
          borderRadius: BorderRadius.circular(FixCareRadii.card),
          onTap: () async {
            await context.push('/earnings');
            ref.invalidate(earningsSummaryProvider); // back from Earnings → fresh numbers
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: FixCareColors.surface, border: Border.all(color: FixCareColors.border), borderRadius: BorderRadius.circular(FixCareRadii.card)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text('Owed to you ${rupees(s.owedPaise)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                  const Icon(Icons.chevron_right),
                ]),
                if (s.pendingPaise > 0) Text('${rupees(s.pendingPaise)} pending', style: const TextStyle(color: FixCareColors.textSecondary)),
                if (s.cashDebtPaise > 0) Text('Cash to hand over ${rupees(s.cashDebtPaise)}'),
                if (s.acceptBlocked)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'New jobs are paused until your cash is settled (${rupees(s.cashDebtPaise)} of ${rupees(s.cashDebtLimitPaise)} limit)',
                      style: const TextStyle(color: FixCareColors.errorText, height: 1.4),
                    ),
                  ),
              ],
            ),
          ),
        ),
      AsyncError(error: final e) => Row(
          key: const Key('moneyCardError'),
          children: [
            Expanded(child: Text('Couldn\'t load earnings: $e', style: const TextStyle(color: FixCareColors.textMuted))),
            TextButton(key: const Key('moneyCardRetryBtn'), onPressed: () => ref.invalidate(earningsSummaryProvider), child: const Text('Retry')),
          ],
        ),
      _ => const SizedBox(height: 56),
    };
  }
}
```

`jobs_home_screen.dart`: insert `const MoneyCard(), const SizedBox(height: 16),` as the first children of the `ListView`, and in `_AvailableSection._onRefresh` also `ref.invalidate(earningsSummaryProvider);` (so the jobs pull-to-refresh reloads the card).

`suspended_screen.dart`: under the Check again button add

```dart
              const SizedBox(height: 8),
              OutlinedButton(key: const Key('earningsBtn'), onPressed: () => context.push('/earnings'), child: const Text('Earnings')),
```

(import `package:go_router/go_router.dart`).

- [ ] **Step 4: Run tests + analyze** — focused PASS; `flutter test` green; `flutter analyze` 0.

- [ ] **Step 5: Commit**

```bash
git add apps/technician/lib/features/jobs/presentation/money_card.dart apps/technician/lib/features/jobs/presentation/jobs_home_screen.dart apps/technician/lib/features/onboarding/presentation/suspended_screen.dart apps/technician/test/jobs apps/technician/test/onboarding/suspended_screen_test.dart apps/technician/test/router/token_gate_test.dart
git commit -m "feat(technician): money card on jobs home; Earnings reachable when suspended"
```

---

### Task 11: Docs — payout runbook, STATUS, CHANGELOG

**Files:**
- Modify: `docs/06-operations/technician-review-runbook.md` (new "Payout requests" section), `STATUS.md`, `CHANGELOG.md`

- [ ] **Step 1: Runbook** — add a "Payout requests" section with copy-pasteable curl (MANAGER token from `POST /admin/auth/login`):
  - the queue: `curl -s "$BASE/admin/payout-requests?status=REQUESTED" -H "authorization: Bearer $ADMIN"` (fields: requested amount, current owed, current cash debt, masked phone);
  - paying: transfer the money by hand FIRST (to the details collected in person), then `POST /admin/payout-requests/<id>/pay` — explain the netting (cash debt is settled from what's owed first; the paid amount is in the response as `paidPaise` and can differ from the requested amount if money moved since) and the 409s (`PAYOUT_REQUEST_NOT_OPEN`, `NOTHING_TO_PAY` → reject instead);
  - rejecting: `POST /admin/payout-requests/<id>/reject` with `{"reason": "…"}` — reasons are shown to the technician and stored in the audit log; never include phone/ID numbers (the API refuses 10+-digit runs).
- [ ] **Step 2: STATUS.md** — Slice 3 → Last shipped as merged (#39); Active task = Slice 4 earnings (branch, what it adds, gates, deploy order: backend first — one additive migration; an older app just doesn't show earnings); deferred: in-app bank/UPI capture, Razorpay Route automatic payouts, technician-cancelled requests, push on paid, trust score, statements/CSV, online/offline mode; keep "Next 3" current.
- [ ] **Step 3: CHANGELOG.md** — one `## 2026-10-07 — Technician app Slice 4: earnings, cash debt + payout requests (on branch)` entry in the existing style.
- [ ] **Step 4: Commit**

```bash
git add docs/06-operations/technician-review-runbook.md STATUS.md CHANGELOG.md
git commit -m "docs: payout runbook; STATUS + CHANGELOG for Slice 4"
```

---

## Final verification (after all tasks)

- `cd apps/backend && set -a && source .env && set +a && pnpm vitest run && pnpm build` → green; `DATABASE_URL="$TEST_DATABASE_URL" pnpm prisma migrate status` and `pnpm prisma migrate status` → up to date.
- `cd apps/technician && flutter test && flutter analyze` → green, 0 issues. Customer app untouched (`cd apps/customer && flutter test` still green).
- `git status --short` shows only the founder-owned iOS leftovers.
