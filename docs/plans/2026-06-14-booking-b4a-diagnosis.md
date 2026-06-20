# Booking B4a — Diagnosis + Parts Cart + Approve/Decline — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After arrival, let the technician record a structured diagnosis (admin issue catalog, no free text) and build a price-snapshotted parts cart, then let the customer approve or decline (decline ends the job; cart frozen at approval). No money moves.

**Architecture:** Adds a `DiagnosedIssue` admin catalog (catalog module, MANAGER+, the parts/pincode pattern) and a `BookingPart` snapshot line-item table. Technician `diagnose`/`parts` endpoints (technician-jobs module, assigned-tech) drive `ARRIVED→DIAGNOSED` + cart edits; customer `approve`/`decline` (bookings module, owner-scoped) drive the terminal transitions. All transitions go through the guarded `transitionBooking` (default-deny actor gate). Parts snapshot the catalog ceiling price at add-time so later catalog edits never change a quoted cart.

**Tech Stack:** Node 22, Fastify 5, Prisma 6 + PostgreSQL 16, Zod, Vitest (`app.inject()`), TypeScript strict. Branch: `feature/booking-diagnosis` (already cut off `main`).

**Design reference:** `docs/designs/2026-06-14-booking-b4a-diagnosis-design.md` (decisions 1-8; schema; the diagnose/cart/approve/decline flow; the computed estimate; category-match 422).

**Conventions:** Zod at the boundary (`.strict()`); route→service→DTO; auth-first; role-gate in `transitionBooking` + assigned-tech/owner identity in the service; money is integer paise; transitions + diagnosis mutations audited in-tx (Golden Rule 5); no PII in audit. Reuse `requireTechnician` + the assigned-tech `ownAssignedBookingOrThrow` pattern (technician-jobs), `requireCustomer` (bookings), `asConflict`→409 (catalog), the `evidence` param on `transitionBooking` (B3).

**Commit-authorship (every commit):** author `MohammadKaifSaiyad <saiyedkgn6@gmail.com>`, **no** Claude/`Co-Authored-By` trailer. Run `pnpm` from `apps/backend`; prefix test commands with `set -a && . ./.env && set +a &&`. After `migrate dev`, apply to test DB: `DATABASE_URL="$TEST_DATABASE_URL" pnpm prisma migrate deploy`. Migrate failure/drift → report BLOCKED (no `db push`, no `_prisma_migrations` hand-patch).

---

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `apps/backend/prisma/schema.prisma` | `DiagnosedIssue` + `BookingPart` models, Booking diagnosis fields, `DIAGNOSIS_UPDATED` audit action, back-relations | Modify |
| `apps/backend/prisma/migrations/<ts>_diagnosis/` | Generated migration | Create |
| `apps/backend/tests/schema/helpers.ts` | TRUNCATE += `DiagnosedIssue`, `BookingPart` | Modify |
| `apps/backend/src/modules/catalog/catalog.schemas.ts` | `createIssueBody`, `updateIssueBody` | Modify |
| `apps/backend/src/modules/catalog/catalog.types.ts` | `DiagnosedIssueDto` + mapper | Modify |
| `apps/backend/src/modules/catalog/catalog.service.ts` | `listIssues`/`createIssue`/`updateIssue`/`deleteIssue` | Modify |
| `apps/backend/src/modules/catalog/catalog.routes.ts` | `/catalog/issues` CRUD | Modify |
| `apps/backend/src/modules/bookings/estimate.ts` | `computeEstimate(booking, parts)` | Create |
| `apps/backend/src/modules/bookings/bookings.types.ts` | `BookingDto` += diagnosis/parts/estimate; `toBookingDto` 3rd `parts` arg | Modify |
| `apps/backend/src/modules/bookings/bookings.state.ts` | `ALLOWED_ACTORS` += DIAGNOSED/CUSTOMER_APPROVED/DECLINED_BY_CUSTOMER | Modify |
| `apps/backend/src/modules/technician-jobs/technician-jobs.schemas.ts` | `diagnoseBody`, `addPartBody` | Modify |
| `apps/backend/src/modules/technician-jobs/technician-jobs.service.ts` | `diagnoseJob`, `addPart`, `removePart` | Modify |
| `apps/backend/src/modules/technician-jobs/technician-jobs.routes.ts` | `/diagnose`, `/parts`, `/parts/:partId` | Modify |
| `apps/backend/src/modules/bookings/bookings.service.ts` | `approveDiagnosis`, `declineDiagnosis`; `getBooking` includes diagnosis+parts | Modify |
| `apps/backend/src/modules/bookings/bookings.schemas.ts` | (none new — approve/decline take no body) | — |
| `apps/backend/src/modules/bookings/bookings.routes.ts` | `/me/bookings/:id/approve`, `/decline` | Modify |
| `apps/backend/prisma/seed.ts` | seed sample `DiagnosedIssue` rows | Modify |
| `apps/backend/tests/catalog/issues.test.ts` | issue-catalog CRUD tests | Create |
| `apps/backend/tests/bookings/helpers.ts` | helper to drive a booking to ARRIVED + seed an issue | Modify |
| `apps/backend/tests/bookings/diagnosis.test.ts` | diagnose + cart + estimate + approve/decline tests | Create |
| `apps/backend/tests/bookings/booking-actor-unit.test.ts` | DIAGNOSED/APPROVED/DECLINED actor entries | Modify |

All paths relative to repo root `/Users/mohammadkaifsaiyad/Development/FixCare`.

---

## Task 1: schema — DiagnosedIssue + BookingPart + Booking fields + migration

**Files:**
- Modify: `apps/backend/prisma/schema.prisma`, `apps/backend/tests/schema/helpers.ts`
- Create: `apps/backend/prisma/migrations/<ts>_diagnosis/migration.sql` (generated)

- [ ] **Step 1: Add `DIAGNOSIS_UPDATED` to the `AuditAction` enum**

In `schema.prisma`, the `AuditAction` enum ends with `BOOKING_STATE_CHANGED`. Add:
```prisma
  BOOKING_STATE_CHANGED
  DIAGNOSIS_UPDATED
}
```

- [ ] **Step 2: Add `DiagnosedIssue` + `BookingPart` models**

After the `Booking` model (booking section), add:
```prisma
model DiagnosedIssue {
  id         String          @id @default(uuid())
  name       String
  categoryId String
  category   ServiceCategory @relation(fields: [categoryId], references: [id])
  status     CatalogStatus   @default(ACTIVE)
  createdAt  DateTime        @default(now())
  updatedAt  DateTime        @updatedAt
  deletedAt  DateTime?
  @@unique([categoryId, name])
  @@index([categoryId])
}

model BookingPart {
  id                String   @id @default(uuid())
  bookingId         String
  booking           Booking  @relation(fields: [bookingId], references: [id])
  partsCatalogId    String
  sku               String
  name              String
  ceilingPricePaise Int
  qty               Int
  createdAt         DateTime @default(now())
  @@index([bookingId])
}
```

- [ ] **Step 3: Add Booking diagnosis fields + back-relations**

In `Booking`, after the arrival fields (`visitFeeLockedAt`), add:
```prisma
  diagnosedIssueId   String?
  diagnosedIssue     DiagnosedIssue? @relation(fields: [diagnosedIssueId], references: [id])
  diagnosedIssueName String?
  diagnosedAt        DateTime?
  declinedAt         DateTime?
  bookingParts       BookingPart[]
```
In `ServiceCategory`, add the back-relation among its relations: `diagnosedIssues DiagnosedIssue[]`.

- [ ] **Step 4: Add both tables to the test TRUNCATE list**

In `tests/schema/helpers.ts`, the TRUNCATE currently starts `TRUNCATE TABLE "JobSkip","Booking",...`. Add `"BookingPart","DiagnosedIssue"` at the FRONT (before `"JobSkip"`):
```ts
    'TRUNCATE TABLE "BookingPart","DiagnosedIssue","JobSkip","Booking","Address","PincodeZone","PartsCatalog","ServicePrice","Service","ServiceCategory","Zone","AuditLog","RefreshToken","Admin","Merchant","Technician","Customer","User" RESTART IDENTITY CASCADE;'
```

- [ ] **Step 5: Generate + apply migration (dev), deploy to test**
```bash
set -a && . ./.env && set +a && pnpm prisma migrate dev --name diagnosis
DATABASE_URL="$TEST_DATABASE_URL" pnpm prisma migrate deploy
```
Expected: a new `*_diagnosis/migration.sql` (ALTER TYPE add enum value; CREATE TABLE DiagnosedIssue + BookingPart with FKs + indexes; ALTER Booking add nullable cols + FK), applied to dev + test; client regenerates.

- [ ] **Step 6: Verify additive-only**
```bash
grep -iE 'DROP|TRUNCATE|ALTER COLUMN' apps/backend/prisma/migrations/*_diagnosis/migration.sql || echo "clean: additive only"
```
Expected: `clean: additive only` (enum ADD VALUE + CREATE TABLE + nullable ADD COLUMN are additive).

- [ ] **Step 7: Commit**
```bash
git add apps/backend/prisma/schema.prisma apps/backend/prisma/migrations apps/backend/tests/schema/helpers.ts
git commit -m "feat(backend): DiagnosedIssue + BookingPart + diagnosis fields + migration (booking B4a)"
```

---

## Task 2: catalog — DiagnosedIssue admin CRUD

**Files:**
- Modify: `apps/backend/src/modules/catalog/catalog.schemas.ts`, `catalog.types.ts`, `catalog.service.ts`, `catalog.routes.ts`
- Create: `apps/backend/tests/catalog/issues.test.ts`

- [ ] **Step 1: Write the failing tests**

Create `apps/backend/tests/catalog/issues.test.ts`:
```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeAdminToken, makeCustomerToken } from './helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }

async function makeCategory(name: string) {
  const mgr = await makeAdminToken('MANAGER');
  return (await app.inject({ method: 'POST', url: '/catalog/categories', headers: auth(mgr), payload: { name } })).json();
}

describe('diagnosed-issue catalog', () => {
  it('MANAGER creates an issue; any authed user lists by category', async () => {
    const cat = await makeCategory('AC');
    const mgr = await makeAdminToken('MANAGER');
    const create = await app.inject({ method: 'POST', url: '/catalog/issues', headers: auth(mgr), payload: { name: 'Compressor fault', categoryId: cat.id } });
    expect(create.statusCode).toBe(201);
    expect(create.json()).toMatchObject({ name: 'Compressor fault', categoryId: cat.id, status: 'ACTIVE' });
    const cust = await makeCustomerToken();
    const list = await app.inject({ method: 'GET', url: `/catalog/issues?categoryId=${cat.id}`, headers: auth(cust) });
    expect(list.statusCode).toBe(200);
    expect(list.json().some((i: { name: string }) => i.name === 'Compressor fault')).toBe(true);
  });

  it('SUPPORT cannot create (403); create writes a CATALOG_UPDATED audit', async () => {
    const cat = await makeCategory('AC');
    const sup = await makeAdminToken('SUPPORT');
    expect((await app.inject({ method: 'POST', url: '/catalog/issues', headers: auth(sup), payload: { name: 'X', categoryId: cat.id } })).statusCode).toBe(403);
    const mgr = await makeAdminToken('MANAGER');
    const i = (await app.inject({ method: 'POST', url: '/catalog/issues', headers: auth(mgr), payload: { name: 'Gas leak', categoryId: cat.id } })).json();
    const audit = await prisma.auditLog.findFirst({ where: { action: 'CATALOG_UPDATED', metadata: { path: ['entityId'], equals: i.id } } });
    expect(audit).toBeTruthy();
    expect((audit!.metadata as { entity: string }).entity).toBe('DiagnosedIssue');
  });

  it('duplicate (category,name) → 409; unknown category → 404', async () => {
    const cat = await makeCategory('AC');
    const mgr = await makeAdminToken('MANAGER');
    await app.inject({ method: 'POST', url: '/catalog/issues', headers: auth(mgr), payload: { name: 'Dup', categoryId: cat.id } });
    expect((await app.inject({ method: 'POST', url: '/catalog/issues', headers: auth(mgr), payload: { name: 'Dup', categoryId: cat.id } })).statusCode).toBe(409);
    expect((await app.inject({ method: 'POST', url: '/catalog/issues', headers: auth(mgr), payload: { name: 'Y', categoryId: '00000000-0000-0000-0000-000000000000' } })).statusCode).toBe(404);
  });

  it('PATCH status / DELETE soft-delete hides from list', async () => {
    const cat = await makeCategory('AC');
    const mgr = await makeAdminToken('MANAGER');
    const i = (await app.inject({ method: 'POST', url: '/catalog/issues', headers: auth(mgr), payload: { name: 'Gone', categoryId: cat.id } })).json();
    expect((await app.inject({ method: 'DELETE', url: `/catalog/issues/${i.id}`, headers: auth(mgr) })).statusCode).toBe(204);
    const cust = await makeCustomerToken();
    const list = (await app.inject({ method: 'GET', url: `/catalog/issues?categoryId=${cat.id}`, headers: auth(cust) })).json();
    expect(list.find((x: { id: string }) => x.id === i.id)).toBeUndefined();
  });
});
```

- [ ] **Step 2: Run — confirm FAIL**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/catalog/issues.test.ts
```

- [ ] **Step 3: Add `DiagnosedIssueDto` + mapper (`catalog.types.ts`)**

Add `DiagnosedIssue` to the `@prisma/client` import on line 1, then append:
```ts
export interface DiagnosedIssueDto { id: string; name: string; categoryId: string; status: DiagnosedIssue['status']; }
export function toDiagnosedIssueDto(i: DiagnosedIssue): DiagnosedIssueDto {
  return { id: i.id, name: i.name, categoryId: i.categoryId, status: i.status };
}
```

- [ ] **Step 4: Add `createIssueBody` + `updateIssueBody` (`catalog.schemas.ts`)**

Append:
```ts
export const createIssueBody = z.object({ name: z.string().min(1), categoryId: z.string().min(1) }).strict();
export type CreateIssueBody = z.infer<typeof createIssueBody>;

export const updateIssueBody = z
  .object({ name: z.string().min(1), status: z.enum(['ACTIVE', 'INACTIVE']) })
  .partial().strict()
  .refine((b) => Object.keys(b).length > 0, { message: 'At least one field is required' });
export type UpdateIssueBody = z.infer<typeof updateIssueBody>;
```

- [ ] **Step 5: Add service fns (`catalog.service.ts`)**

Extend the types import to add `toDiagnosedIssueDto, type DiagnosedIssueDto` and the schemas import to add `CreateIssueBody, UpdateIssueBody`. Append (mirrors `listPincodes`/`createPincode`/`updatePincode`/`deletePincode`):
```ts
export async function listIssues(categoryId?: string): Promise<DiagnosedIssueDto[]> {
  const rows = await prisma.diagnosedIssue.findMany({
    where: { deletedAt: null, status: 'ACTIVE', ...(categoryId ? { categoryId } : {}) },
    orderBy: { name: 'asc' },
  });
  return rows.map(toDiagnosedIssueDto);
}

export async function createIssue(actorId: string, body: CreateIssueBody): Promise<DiagnosedIssueDto> {
  const cat = await prisma.serviceCategory.findFirst({ where: { id: body.categoryId, deletedAt: null } });
  if (!cat) throw new NotFoundError('Category not found');
  try {
    return await prisma.$transaction(async (tx) => {
      const row = await tx.diagnosedIssue.create({ data: { name: body.name, categoryId: body.categoryId } });
      await tx.auditLog.create({ data: { action: 'CATALOG_UPDATED', actorType: 'ADMIN', actorId, metadata: { entity: 'DiagnosedIssue', entityId: row.id, fields: Object.keys(body) } } });
      return toDiagnosedIssueDto(row);
    });
  } catch (e) { return asConflict(e, 'An issue with that name already exists in this category'); }
}

export async function updateIssue(actorId: string, id: string, body: UpdateIssueBody): Promise<DiagnosedIssueDto> {
  const existing = await prisma.diagnosedIssue.findFirst({ where: { id, deletedAt: null } });
  if (!existing) throw new NotFoundError('Issue not found');
  const changedFields = (Object.keys(body) as (keyof typeof body)[])
    .filter((k) => (body as Record<string, unknown>)[k] !== (existing as Record<string, unknown>)[k]);
  if (changedFields.length === 0) return toDiagnosedIssueDto(existing);
  return prisma.$transaction(async (tx) => {
    const row = await tx.diagnosedIssue.update({ where: { id }, data: body });
    await tx.auditLog.create({ data: { action: 'CATALOG_UPDATED', actorType: 'ADMIN', actorId, metadata: { entity: 'DiagnosedIssue', entityId: id, fields: changedFields } } });
    return toDiagnosedIssueDto(row);
  });
}

export async function deleteIssue(actorId: string, id: string): Promise<void> {
  const existing = await prisma.diagnosedIssue.findFirst({ where: { id, deletedAt: null } });
  if (!existing) throw new NotFoundError('Issue not found');
  await prisma.$transaction(async (tx) => {
    await tx.diagnosedIssue.update({ where: { id }, data: { deletedAt: new Date() } });
    await tx.auditLog.create({ data: { action: 'CATALOG_UPDATED', actorType: 'ADMIN', actorId, metadata: { entity: 'DiagnosedIssue', entityId: id, fields: ['deletedAt'] } } });
  });
}
```

- [ ] **Step 6: Register routes (`catalog.routes.ts`)**

Extend the schemas import to add `createIssueBody, updateIssueBody` and the service import to add `listIssues, createIssue, updateIssue, deleteIssue`. Before the closing `}`, add:
```ts
  app.get('/catalog/issues', { preHandler: [requireAuth] }, async (req, reply) => {
    const q = req.query as { categoryId?: string };
    return reply.send(await listIssues(q.categoryId));
  });

  app.post('/catalog/issues', { preHandler: [requireAuth, requireAdminLevel('MANAGER')] }, async (req, reply) => {
    const p = createIssueBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.code(201).send(await createIssue(req.user!.id, p.data));
  });

  app.patch('/catalog/issues/:id', { preHandler: [requireAuth, requireAdminLevel('MANAGER')] }, async (req, reply) => {
    const p = updateIssueBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.send(await updateIssue(req.user!.id, (req.params as { id: string }).id, p.data));
  });

  app.delete('/catalog/issues/:id', { preHandler: [requireAuth, requireAdminLevel('MANAGER')] }, async (req, reply) => {
    await deleteIssue(req.user!.id, (req.params as { id: string }).id);
    return reply.code(204).send();
  });
```

- [ ] **Step 7: Run — PASS; build; commit**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/catalog/issues.test.ts
cd apps/backend && pnpm build
git add apps/backend/src/modules/catalog apps/backend/tests/catalog/issues.test.ts
git commit -m "feat(backend): DiagnosedIssue admin CRUD (booking B4a)"
```

---

## Task 3: state machine — DIAGNOSED/APPROVED/DECLINED actor entries

**Files:**
- Modify: `apps/backend/src/modules/bookings/bookings.state.ts`
- Modify: `apps/backend/tests/bookings/booking-actor-unit.test.ts`

- [ ] **Step 1: Add failing actor assertions**

In `tests/bookings/booking-actor-unit.test.ts`, add:
```ts
  it('DIAGNOSED is technician-only; CUSTOMER_APPROVED/DECLINED are customer-only', () => {
    expect(actorAllowedFor('DIAGNOSED', 'TECHNICIAN')).toBe(true);
    expect(actorAllowedFor('DIAGNOSED', 'CUSTOMER')).toBe(false);
    expect(actorAllowedFor('CUSTOMER_APPROVED', 'CUSTOMER')).toBe(true);
    expect(actorAllowedFor('CUSTOMER_APPROVED', 'TECHNICIAN')).toBe(false);
    expect(actorAllowedFor('DECLINED_BY_CUSTOMER', 'CUSTOMER')).toBe(true);
    expect(actorAllowedFor('DECLINED_BY_CUSTOMER', 'TECHNICIAN')).toBe(false);
  });
```
If the existing "default-deny" test uses `DIAGNOSED` as a still-unmapped example, switch it to a state B4a does NOT map (e.g. `PARTS_REQUESTED` or `REPAIR_IN_PROGRESS`).

- [ ] **Step 2: Run — confirm FAIL**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/bookings/booking-actor-unit.test.ts
```

- [ ] **Step 3: Add the entries to `ALLOWED_ACTORS`**

In `bookings.state.ts`, add:
```ts
  DIAGNOSED:            ['TECHNICIAN'],
  CUSTOMER_APPROVED:    ['CUSTOMER'],
  DECLINED_BY_CUSTOMER: ['CUSTOMER'],
```

- [ ] **Step 4: Run — PASS; commit**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/bookings/booking-actor-unit.test.ts
git add apps/backend/src/modules/bookings/bookings.state.ts apps/backend/tests/bookings/booking-actor-unit.test.ts
git commit -m "feat(backend): ALLOWED_ACTORS — DIAGNOSED/APPROVED/DECLINED (booking B4a)"
```

---

## Task 4: estimate helper + DTO extension

**Files:**
- Create: `apps/backend/src/modules/bookings/estimate.ts`
- Create: `apps/backend/tests/bookings/estimate.test.ts`
- Modify: `apps/backend/src/modules/bookings/bookings.types.ts`

- [ ] **Step 1: Write the failing estimate test**

Create `apps/backend/tests/bookings/estimate.test.ts`:
```ts
import { describe, expect, it } from 'vitest';
import { computeEstimate } from '../../src/modules/bookings/estimate.js';

describe('computeEstimate', () => {
  it('labor + parts − visit-fee credit', () => {
    const e = computeEstimate({ laborPaise: 60000, visitFeePaise: 14900 }, [
      { ceilingPricePaise: 70000, qty: 1 },
      { ceilingPricePaise: 12000, qty: 2 },
    ]);
    expect(e).toEqual({ laborPaise: 60000, partsPaise: 94000, visitFeeCreditPaise: 14900, totalPayablePaise: 139100 });
  });
  it('empty cart → labor − visit fee', () => {
    expect(computeEstimate({ laborPaise: 60000, visitFeePaise: 14900 }, [])).toMatchObject({ partsPaise: 0, totalPayablePaise: 45100 });
  });
  it('floors total at 0 when the visit fee exceeds labor+parts', () => {
    expect(computeEstimate({ laborPaise: 10000, visitFeePaise: 14900 }, []).totalPayablePaise).toBe(0);
  });
});
```

- [ ] **Step 2: Run — FAIL; implement `src/modules/bookings/estimate.ts`**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/bookings/estimate.test.ts
```
```ts
export interface Estimate {
  laborPaise: number;
  partsPaise: number;
  visitFeeCreditPaise: number;
  totalPayablePaise: number;
}

/** Compute the customer-facing estimate from snapshots. Visit fee is a CREDIT toward labor+parts
 *  (pricing-model); total is floored at 0 (a credit never makes the customer owe negative). */
export function computeEstimate(
  booking: { laborPaise: number; visitFeePaise: number },
  parts: { ceilingPricePaise: number; qty: number }[],
): Estimate {
  const partsPaise = parts.reduce((sum, p) => sum + p.ceilingPricePaise * p.qty, 0);
  const visitFeeCreditPaise = booking.visitFeePaise;
  const totalPayablePaise = Math.max(0, booking.laborPaise + partsPaise - visitFeeCreditPaise);
  return { laborPaise: booking.laborPaise, partsPaise, visitFeeCreditPaise, totalPayablePaise };
}
```
Run → PASS.

- [ ] **Step 3: Extend `BookingDto` + `toBookingDto` (`bookings.types.ts`)**

Add to `BookingDto`:
```ts
  diagnosis: { issueName: string } | null;
  parts: { id: string; sku: string; name: string; ceilingPricePaise: number; qty: number }[];
  estimate: import('./estimate.js').Estimate;
```
Change `toBookingDto` to accept the parts and compute diagnosis+estimate. Import the helper at the top:
```ts
import { computeEstimate } from './estimate.js';
import type { BookingPart } from '@prisma/client';
```
Update the signature + body (keep the existing optional `tech` param):
```ts
export function toBookingDto(b: Booking, tech?: { name: string; phone: string }, parts: BookingPart[] = []): BookingDto {
  return {
    // ...existing fields...,
    ...(tech ? { technician: { name: tech.name, maskedPhone: maskPhone(tech.phone) } } : {}),
    diagnosis: b.diagnosedIssueName ? { issueName: b.diagnosedIssueName } : null,
    parts: parts.map((p) => ({ id: p.id, sku: p.sku, name: p.name, ceilingPricePaise: p.ceilingPricePaise, qty: p.qty })),
    estimate: computeEstimate(b, parts),
  };
}
```
(All existing `toBookingDto(b)` / `toBookingDto(b, tech)` callers still compile — `parts` defaults to `[]`. Existing callers will now emit `parts: []` + a labor-only estimate + `diagnosis: null` until diagnosis happens, which is correct.)

- [ ] **Step 4: Build + run booking suite (catch DTO regressions); commit**
```bash
cd apps/backend && pnpm build
set -a && . ./.env && set +a && pnpm test -- tests/bookings tests/technician-jobs
git add apps/backend/src/modules/bookings/estimate.ts apps/backend/tests/bookings/estimate.test.ts apps/backend/src/modules/bookings/bookings.types.ts
git commit -m "feat(backend): estimate helper + BookingDto diagnosis/parts/estimate (booking B4a)"
```
Note: existing booking tests that `toMatchObject` a subset of the DTO still pass (extra fields are fine). If any test does a strict `toEqual` on the whole DTO, update it to include the new fields.

---

## Task 5: technician diagnose + parts cart

**Files:**
- Modify: `apps/backend/src/modules/technician-jobs/technician-jobs.schemas.ts`, `technician-jobs.service.ts`, `technician-jobs.routes.ts`
- Modify: `apps/backend/tests/bookings/helpers.ts`
- Create: `apps/backend/tests/bookings/diagnosis.test.ts`

- [ ] **Step 1: Extend test helpers**

In `tests/bookings/helpers.ts`, add a helper to drive a booking to ARRIVED + seed an issue. (The B3 arrival flow: en-route → arrive(mints code) → confirm-arrival. seedBookable's address has no coords → geofence record-only.) Add:
```ts
import { mintArrivalCode } from '../../src/modules/bookings/arrival-code.js'; // if needed; else drive via HTTP

/** Seed an ACTIVE DiagnosedIssue in the given category. */
export async function seedIssue(categoryId: string, name = 'Compressor fault') {
  return prisma.diagnosedIssue.create({ data: { name, categoryId } });
}
```
The diagnosis test will drive ARRIVED via the HTTP handshake (accept → en-route → arrive → confirm-arrival) using the existing booking/technician helpers — no new arrival helper needed; just reuse the endpoints.

- [ ] **Step 2: Write the failing diagnose + cart tests**

Create `apps/backend/tests/bookings/diagnosis.test.ts`:
```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, makeTechnician, seedBookable, seedIssue } from './helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
function future() { return new Date(Date.now() + 86_400_000).toISOString(); }

/** Drive a fresh booking all the way to ARRIVED; return ids + the issue + a seeded part. */
async function arrivedBooking() {
  const c = await makeCustomer();
  const f = await seedBookable(c.customerId); // creates zone + service(category) + price + pincode + address
  const t = await makeTechnician(['AC']);
  const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(t.token) });
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/en-route`, headers: auth(t.token) });
  const code = (await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/arrive`, headers: auth(t.token), payload: { lat: 22.31, lng: 73.18 } })).json().arrivalCode;
  await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/confirm-arrival`, headers: auth(c.token), payload: { code } });
  const issue = await seedIssue(f.cat.id);                 // f.cat = the service's category (seedBookable returns it)
  const part = await prisma.partsCatalog.create({ data: { sku: 'P1', name: 'Capacitor', ceilingPricePaise: 50000, categoryId: f.cat.id } });
  return { c, t, f, bookingId: booking.id as string, issue, part };
}

describe('diagnose + parts cart', () => {
  it('technician diagnoses (ARRIVED→DIAGNOSED) with the issue snapshot', async () => {
    const { t, bookingId, issue } = await arrivedBooking();
    const res = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id } });
    expect(res.statusCode).toBe(200);
    const row = await prisma.booking.findUnique({ where: { id: bookingId } });
    expect(row!.state).toBe('DIAGNOSED');
    expect(row!.diagnosedIssueName).toBe('Compressor fault');
    expect(row!.diagnosedAt).not.toBeNull();
  });

  it('issue from a different category → 422', async () => {
    const { t, bookingId } = await arrivedBooking();
    const otherCat = await prisma.serviceCategory.create({ data: { name: 'Fan' } });
    const otherIssue = await prisma.diagnosedIssue.create({ data: { name: 'Blade', categoryId: otherCat.id } });
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: otherIssue.id } })).statusCode).toBe(422);
  });

  it('diagnose from non-ARRIVED → 409; non-assigned tech → 403; customer → 403', async () => {
    const { c, t, f, bookingId, issue } = await arrivedBooking();
    await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id } });
    // second diagnose (now DIAGNOSED) → 409
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id } })).statusCode).toBe(409);
    const other = await makeTechnician(['AC']);
    // a different tech on a non-ARRIVED booking: assigned-tech check fires (403) — use a fresh ARRIVED booking for clarity
    const fresh = await arrivedBooking();
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${fresh.bookingId}/diagnose`, headers: auth(other.token), payload: { diagnosedIssueId: fresh.issue.id } })).statusCode).toBe(403);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${fresh.bookingId}/diagnose`, headers: auth(fresh.c.token), payload: { diagnosedIssueId: fresh.issue.id } })).statusCode).toBe(403);
  });

  it('add a part snapshots the ceiling price; catalog edit after add does NOT change the line (snapshot integrity)', async () => {
    const { t, bookingId, issue, part } = await arrivedBooking();
    await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id } });
    const add = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts`, headers: auth(t.token), payload: { partsCatalogId: part.id, qty: 2 } });
    expect(add.statusCode).toBe(201);
    await prisma.partsCatalog.update({ where: { id: part.id }, data: { ceilingPricePaise: 999999 } });
    const lines = await prisma.bookingPart.findMany({ where: { bookingId } });
    expect(lines).toHaveLength(1);
    expect(lines[0].ceilingPricePaise).toBe(50000); // unchanged snapshot
    expect(lines[0].qty).toBe(2);
  });

  it('qty < 1 → 400; add to an unknown catalog part → 404; remove another booking part → 404', async () => {
    const { t, bookingId, issue, part } = await arrivedBooking();
    await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id } });
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts`, headers: auth(t.token), payload: { partsCatalogId: part.id, qty: 0 } })).statusCode).toBe(400);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts`, headers: auth(t.token), payload: { partsCatalogId: '00000000-0000-0000-0000-000000000000', qty: 1 } })).statusCode).toBe(404);
    expect((await app.inject({ method: 'DELETE', url: `/technician/jobs/${bookingId}/parts/00000000-0000-0000-0000-000000000000`, headers: auth(t.token) })).statusCode).toBe(404);
  });

  it('add/remove only while DIAGNOSED; remove works + is logged', async () => {
    const { t, bookingId, issue, part } = await arrivedBooking();
    await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id } });
    const line = (await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts`, headers: auth(t.token), payload: { partsCatalogId: part.id, qty: 1 } })).json();
    expect((await app.inject({ method: 'DELETE', url: `/technician/jobs/${bookingId}/parts/${line.id}`, headers: auth(t.token) })).statusCode).toBe(204);
    expect(await prisma.bookingPart.count({ where: { bookingId } })).toBe(0);
    const audits = await prisma.auditLog.findMany({ where: { action: 'DIAGNOSIS_UPDATED' } });
    expect(audits.length).toBeGreaterThanOrEqual(3); // diagnose + add + remove
  });
});
```
Note: this assumes `seedBookable` returns `cat` (it does — confirmed in the helpers). If `seedBookable` doesn't expose the category id, add it to its return.

- [ ] **Step 3: Run — confirm FAIL**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/bookings/diagnosis.test.ts
```

- [ ] **Step 4: Add schemas (`technician-jobs.schemas.ts`)**
```ts
export const diagnoseBody = z.object({ diagnosedIssueId: z.string().min(1) }).strict();
export type DiagnoseBody = z.infer<typeof diagnoseBody>;

export const addPartBody = z.object({ partsCatalogId: z.string().min(1), qty: z.number().int().min(1) }).strict();
export type AddPartBody = z.infer<typeof addPartBody>;
```

- [ ] **Step 5: Add `diagnoseJob`, `addPart`, `removePart` (`technician-jobs.service.ts`)**

Extend imports: `UnprocessableError` (errors) is already imported; add `ValidationError` only if used (not needed here). Add `DiagnoseBody, AddPartBody` from the schemas. Append:
```ts
export async function diagnoseJob(userId: string, bookingId: string, body: DiagnoseBody): Promise<{ id: string; state: 'DIAGNOSED' }> {
  const tech = await requireTechnician(userId);
  const booking = await prisma.booking.findFirst({ where: { id: bookingId, deletedAt: null }, include: { service: true } });
  if (!booking) throw new NotFoundError('Job not found');
  if (booking.technicianId !== tech.id) throw new ForbiddenError('This job is not assigned to you');
  if (booking.state !== 'ARRIVED') throw new ConflictError('Job is not in ARRIVED');
  const issue = await prisma.diagnosedIssue.findFirst({ where: { id: body.diagnosedIssueId, deletedAt: null, status: 'ACTIVE' } });
  if (!issue) throw new NotFoundError('Diagnosed issue not found');
  if (issue.categoryId !== booking.service.categoryId) throw new UnprocessableError('That issue does not apply to this service');

  await prisma.$transaction(async (tx) => {
    await tx.booking.update({ where: { id: bookingId }, data: { diagnosedIssueId: issue.id, diagnosedIssueName: issue.name, diagnosedAt: new Date() } });
    // re-read for the transition's from-state (still ARRIVED in this tx)
    const fresh = await tx.booking.findUniqueOrThrow({ where: { id: bookingId } });
    await transitionBooking(tx, fresh, 'DIAGNOSED', { type: 'USER', kind: 'TECHNICIAN', id: userId }, { diagnosedIssueId: issue.id });
    await tx.auditLog.create({ data: { action: 'DIAGNOSIS_UPDATED', actorType: 'USER', actorId: userId, metadata: { bookingId, action: 'diagnosed', diagnosedIssueId: issue.id } } });
  });
  return { id: bookingId, state: 'DIAGNOSED' };
}

async function ownDiagnosedBookingOrThrow(techId: string, bookingId: string) {
  const b = await prisma.booking.findFirst({ where: { id: bookingId, deletedAt: null } });
  if (!b) throw new NotFoundError('Job not found');
  if (b.technicianId !== techId) throw new ForbiddenError('This job is not assigned to you');
  if (b.state !== 'DIAGNOSED') throw new ConflictError('Job is not in DIAGNOSED');
  return b;
}

export async function addPart(userId: string, bookingId: string, body: AddPartBody): Promise<{ id: string }> {
  const tech = await requireTechnician(userId);
  await ownDiagnosedBookingOrThrow(tech.id, bookingId);
  const cat = await prisma.partsCatalog.findFirst({ where: { id: body.partsCatalogId, deletedAt: null, status: 'ACTIVE' } });
  if (!cat) throw new NotFoundError('Part not found');
  const line = await prisma.$transaction(async (tx) => {
    const created = await tx.bookingPart.create({
      data: { bookingId, partsCatalogId: cat.id, sku: cat.sku, name: cat.name, ceilingPricePaise: cat.ceilingPricePaise, qty: body.qty },
    });
    await tx.auditLog.create({ data: { action: 'DIAGNOSIS_UPDATED', actorType: 'USER', actorId: userId, metadata: { bookingId, action: 'part_added', sku: cat.sku, qty: body.qty } } });
    return created;
  });
  return { id: line.id };
}

export async function removePart(userId: string, bookingId: string, partId: string): Promise<void> {
  const tech = await requireTechnician(userId);
  await ownDiagnosedBookingOrThrow(tech.id, bookingId);
  const line = await prisma.bookingPart.findFirst({ where: { id: partId, bookingId } });
  if (!line) throw new NotFoundError('Part line not found');
  await prisma.$transaction(async (tx) => {
    await tx.bookingPart.delete({ where: { id: partId } });
    await tx.auditLog.create({ data: { action: 'DIAGNOSIS_UPDATED', actorType: 'USER', actorId: userId, metadata: { bookingId, action: 'part_removed', sku: line.sku } } });
  });
}
```

- [ ] **Step 6: Add routes (`technician-jobs.routes.ts`)**

Import `diagnoseBody, addPartBody` + the new service fns + `ValidationError`. Add:
```ts
  app.post('/technician/jobs/:id/diagnose', { preHandler: [requireAuth] }, async (req, reply) => {
    requireTechnicianRole(req);
    const p = diagnoseBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.send(await diagnoseJob(req.user!.id, (req.params as { id: string }).id, p.data));
  });

  app.post('/technician/jobs/:id/parts', { preHandler: [requireAuth] }, async (req, reply) => {
    requireTechnicianRole(req);
    const p = addPartBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.code(201).send(await addPart(req.user!.id, (req.params as { id: string }).id, p.data));
  });

  app.delete('/technician/jobs/:id/parts/:partId', { preHandler: [requireAuth] }, async (req, reply) => {
    requireTechnicianRole(req);
    const { id, partId } = req.params as { id: string; partId: string };
    await removePart(req.user!.id, id, partId);
    return reply.code(204).send();
  });
```
(`ValidationError` may need adding to the technician-jobs.routes errors import.)

- [ ] **Step 7: Run — PASS; build; commit**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/bookings/diagnosis.test.ts
cd apps/backend && pnpm build
git add apps/backend/src/modules/technician-jobs apps/backend/tests/bookings/diagnosis.test.ts apps/backend/tests/bookings/helpers.ts
git commit -m "feat(backend): technician diagnose + parts cart with snapshot (booking B4a)"
```

---

## Task 6: customer approve / decline + DTO surfacing

**Files:**
- Modify: `apps/backend/src/modules/bookings/bookings.service.ts`, `bookings.routes.ts`
- Modify: `apps/backend/tests/bookings/diagnosis.test.ts`

- [ ] **Step 1: Add approve/decline + DTO tests**

Append to `tests/bookings/diagnosis.test.ts`:
```ts
describe('approve / decline', () => {
  async function diagnosedWithPart() {
    const a = await arrivedBooking();
    await app.inject({ method: 'POST', url: `/technician/jobs/${a.bookingId}/diagnose`, headers: auth(a.t.token), payload: { diagnosedIssueId: a.issue.id } });
    await app.inject({ method: 'POST', url: `/technician/jobs/${a.bookingId}/parts`, headers: auth(a.t.token), payload: { partsCatalogId: a.part.id, qty: 1 } });
    return a;
  }

  it('customer GET shows diagnosis + parts + estimate', async () => {
    const a = await diagnosedWithPart();
    const got = (await app.inject({ method: 'GET', url: `/me/bookings/${a.bookingId}`, headers: auth(a.c.token) })).json();
    expect(got.diagnosis.issueName).toBe('Compressor fault');
    expect(got.parts).toHaveLength(1);
    expect(got.estimate.partsPaise).toBe(50000);
    // labor 60000 + parts 50000 − visitFee 14900 = 95100
    expect(got.estimate.totalPayablePaise).toBe(95100);
  });

  it('approve → CUSTOMER_APPROVED; cart frozen (part add after approve → 409)', async () => {
    const a = await diagnosedWithPart();
    const res = await app.inject({ method: 'POST', url: `/me/bookings/${a.bookingId}/approve`, headers: auth(a.c.token) });
    expect(res.statusCode).toBe(200);
    expect(res.json().state).toBe('CUSTOMER_APPROVED');
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${a.bookingId}/parts`, headers: auth(a.t.token), payload: { partsCatalogId: a.part.id, qty: 1 } })).statusCode).toBe(409);
  });

  it('decline → DECLINED_BY_CUSTOMER (terminal) + declinedAt; visitFeeLockedAt stays set', async () => {
    const a = await diagnosedWithPart();
    const res = await app.inject({ method: 'POST', url: `/me/bookings/${a.bookingId}/decline`, headers: auth(a.c.token) });
    expect(res.statusCode).toBe(200);
    expect(res.json().state).toBe('DECLINED_BY_CUSTOMER');
    const row = await prisma.booking.findUnique({ where: { id: a.bookingId } });
    expect(row!.declinedAt).not.toBeNull();
    expect(row!.visitFeeLockedAt).not.toBeNull(); // set at ARRIVED (B3), unchanged
  });

  it('approve/decline from non-DIAGNOSED → 409; another customer → 404; technician calling approve → 403', async () => {
    const a = await diagnosedWithPart();
    const other = await makeCustomer();
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${a.bookingId}/approve`, headers: auth(other.token) })).statusCode).toBe(404);
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${a.bookingId}/approve`, headers: auth(a.t.token) })).statusCode).toBe(403);
    await app.inject({ method: 'POST', url: `/me/bookings/${a.bookingId}/approve`, headers: auth(a.c.token) });
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${a.bookingId}/decline`, headers: auth(a.c.token) })).statusCode).toBe(409); // already approved
  });
});
```

- [ ] **Step 2: Run — confirm FAIL**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/bookings/diagnosis.test.ts
```

- [ ] **Step 3: Add `approveDiagnosis` + `declineDiagnosis`; surface diagnosis+parts in `getBooking` (`bookings.service.ts`)**

Append:
```ts
export async function approveDiagnosis(userId: string, id: string): Promise<BookingDto> {
  const { id: customerId } = await requireCustomer(userId);
  const booking = await prisma.booking.findFirst({ where: { id, customerId, deletedAt: null } });
  if (!booking) throw new NotFoundError('Booking not found');
  if (booking.state !== 'DIAGNOSED') throw new ConflictError('Booking is not awaiting a decision');
  const updated = await prisma.$transaction((tx) => transitionBooking(tx, booking, 'CUSTOMER_APPROVED', { type: 'USER', kind: 'CUSTOMER', id: userId }));
  const parts = await prisma.bookingPart.findMany({ where: { bookingId: id } });
  return toBookingDto(updated, undefined, parts);
}

export async function declineDiagnosis(userId: string, id: string): Promise<BookingDto> {
  const { id: customerId } = await requireCustomer(userId);
  const booking = await prisma.booking.findFirst({ where: { id, customerId, deletedAt: null } });
  if (!booking) throw new NotFoundError('Booking not found');
  if (booking.state !== 'DIAGNOSED') throw new ConflictError('Booking is not awaiting a decision');
  const updated = await prisma.$transaction(async (tx) => {
    await transitionBooking(tx, booking, 'DECLINED_BY_CUSTOMER', { type: 'USER', kind: 'CUSTOMER', id: userId });
    return tx.booking.update({ where: { id }, data: { declinedAt: new Date() } });
  });
  const parts = await prisma.bookingPart.findMany({ where: { bookingId: id } });
  return toBookingDto(updated, undefined, parts);
}
```
Update `getBooking` to include the parts (and technician, as it already does):
```ts
export async function getBooking(userId: string, id: string): Promise<BookingDto> {
  const { id: customerId } = await requireCustomer(userId);
  const b = await prisma.booking.findFirst({
    where: { id, customerId, deletedAt: null },
    include: { technician: { include: { user: true } }, bookingParts: true },
  });
  if (!b) throw new NotFoundError('Booking not found');
  const tech = b.technician ? { name: b.technician.name, phone: b.technician.user.phone } : undefined;
  return toBookingDto(b, tech, b.bookingParts);
}
```
(Confirm `getBooking` currently includes `technician`; add `bookingParts: true` to its include. If `getBooking` used `ownBookingOrThrow`, switch to this explicit findFirst with includes.)

- [ ] **Step 4: Add routes (`bookings.routes.ts`)**

Import `approveDiagnosis, declineDiagnosis`. Add (customer-only — `requireCustomerRole` already in this file, the actor gate also enforces):
```ts
  app.post('/me/bookings/:id/approve', { preHandler: [requireAuth] }, async (req, reply) => {
    requireCustomerRole(req);
    return reply.send(await approveDiagnosis(req.user!.id, (req.params as { id: string }).id));
  });

  app.post('/me/bookings/:id/decline', { preHandler: [requireAuth] }, async (req, reply) => {
    requireCustomerRole(req);
    return reply.send(await declineDiagnosis(req.user!.id, (req.params as { id: string }).id));
  });
```

- [ ] **Step 5: Run — PASS; build; full booking+technician suites; commit**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/bookings/diagnosis.test.ts
cd apps/backend && pnpm build
set -a && . ./.env && set +a && pnpm test -- tests/bookings tests/technician-jobs tests/catalog
git add apps/backend/src/modules/bookings apps/backend/tests/bookings/diagnosis.test.ts
git commit -m "feat(backend): customer approve/decline diagnosis + DTO surfacing (booking B4a)"
```

---

## Task 7: seed + full suite + reviews + docs

**Files:**
- Modify: `apps/backend/prisma/seed.ts`, `STATUS.md`, `CHANGELOG.md`

- [ ] **Step 1: Seed sample issues**

In `seedCatalog` (prisma/seed.ts), after the categories/services are upserted, add a couple of `DiagnosedIssue` upserts keyed on `(categoryId, name)`:
```ts
  const issues: Array<{ name: string; categoryId: string }> = [
    { name: 'AC compressor fault', categoryId: ac.id },
    { name: 'AC gas leak', categoryId: ac.id },
    { name: 'Fan capacitor failure', categoryId: fan.id },
  ];
  for (const iss of issues) {
    await prisma.diagnosedIssue.upsert({
      where: { categoryId_name: { categoryId: iss.categoryId, name: iss.name } },
      update: {}, create: iss,
    });
  }
```
Update the seed `console.log` count line to mention issues. (Confirm `ac`/`fan` category vars are in scope — they are, from the existing seed.)

- [ ] **Step 2: Run the seed test (if it asserts counts) + db:seed twice (idempotent)**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/catalog/seed-catalog.test.ts && pnpm db:seed && pnpm db:seed
```
(If the seed test asserts exact entity counts, add an issues assertion; otherwise it should still pass.)

- [ ] **Step 3: Full backend suite**
```bash
set -a && . ./.env && set +a && cd apps/backend && pnpm test
```
Expected: ALL green (prior 197 + the new issues/estimate/diagnosis tests). Note the total.

- [ ] **Step 4: Review agents**
- `prisma-migration-reviewer` — the `diagnosis` migration (additive; `BookingPart.ceilingPricePaise` integer paise; indexes; `BookingPart` intentionally no soft-delete = pre-approval mutable cart).
- `golden-rules-auditor` — parts-snapshot = money-evidence integrity (catalog edit doesn't change a quoted line); audit-in-tx (DIAGNOSIS_UPDATED + transitions); actor gate + assigned-tech/owner identity; catalog-prices-only (tech provides no price); no PII in audit.
- `fraud-vector-checker` — no-free-text diagnosis (FK-enforced); tech can't pad parts price (snapshot from catalog, not request); issue-service category match; cart frozen at approval.

Address blockers; re-run; then `/code-review` on the branch.

- [ ] **Step 5: STATUS.md + CHANGELOG.md**
STATUS: booking module — B1/B2a/B3 merged, **B4a (diagnosis + parts cart) done** on branch. Active task → B4a summary. Next 3 → **B4b** (R2 + 2 mandatory diagnosis photos) then **B5** (completion handshake, keystone #2 — needs the pre-B5 shared-OTP-primitive extraction first). `_Last updated_` 2026-06-14.
CHANGELOG: `## 2026-06-14 — Booking B4a (diagnosis + parts cart + approve/decline)` — DiagnosedIssue catalog, diagnose (ARRIVED→DIAGNOSED, category-matched), BookingPart snapshot cart (add/remove logged, frozen at approval), computed estimate (visit-fee credit), approve/decline (decline terminal), DIAGNOSIS_UPDATED audit; deferred B4b photos + auto-suggest. Test count; review notes.

- [ ] **Step 6: Commit docs + finish branch**
```bash
git add apps/backend/prisma/seed.ts STATUS.md CHANGELOG.md apps/backend/tests/catalog/seed-catalog.test.ts
git commit -m "docs+seed: sample diagnosed issues + status/changelog for booking B4a"
```
Then `superpowers:finishing-a-development-branch` → PR `feature/booking-diagnosis` → `main`. (Push/PR is the user's step.) **B4b (R2 + photos)** or **the pre-B5 OTP-primitive refactor** continues after merge.

---

## Self-Review notes

- **Spec coverage:** DiagnosedIssue model + admin CRUD ✓ (T1/T2); BookingPart snapshot ✓ (T1/T5); actor entries ✓ (T3); computed estimate (visit-fee credit, floor 0) ✓ (T4); diagnose (category-match 422, ARRIVED→DIAGNOSED, issue snapshot) ✓ (T5); cart add/remove (snapshot, DIAGNOSED-only, logged) + the snapshot-integrity test ✓ (T5); approve/decline (terminal decline, cart frozen, declinedAt, visitFeeLockedAt unchanged) + DTO surfacing ✓ (T6); seed ✓ (T7). Decisions 1-8 covered. Deferred (B4b photos, auto-suggest, mismatch fraud-rule, charge) out of scope.
- **Placeholder scan:** none — every step has concrete code/commands. (T5 Step 1 notes `seedBookable` must return `cat` — verify in the helper; it does per the exploration. If it doesn't expose the category, add `cat` to its return as the first sub-step.)
- **Type consistency:** `computeEstimate(booking, parts)`/`Estimate` used in T4 + the DTO + service; `toBookingDto(b, tech?, parts=[])` 3-arg signature consistent across getBooking/approve/decline/createBooking/cancel (all existing 1-2 arg callers still compile); `diagnoseJob`/`addPart`/`removePart`, `diagnoseBody`/`addPartBody`, `approveDiagnosis`/`declineDiagnosis`, `DiagnosedIssueDto`/`toDiagnosedIssueDto`, `createIssueBody`/`updateIssueBody`, `listIssues`/`createIssue`/`updateIssue`/`deleteIssue` consistent. `transitionBooking`'s `evidence` 5th param reused (diagnose passes `{diagnosedIssueId}`). `prisma.diagnosedIssue`/`prisma.bookingPart` accessors. `categoryId_name` is the DiagnosedIssue composite-unique key (matches `@@unique([categoryId, name])`).
- **Snapshot integrity:** BookingPart snapshots sku/name/ceilingPricePaise at add; the T5 test mutates the catalog and asserts the line is unchanged — the money-evidence guarantee.
- **diagnose tx note:** the update-then-re-read-then-transition inside one tx keeps the from-state (ARRIVED) correct for the optimistic lock; the transition's own audit + the explicit DIAGNOSIS_UPDATED are both in-tx.
