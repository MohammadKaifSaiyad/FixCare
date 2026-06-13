# Booking B2a — Broadcast Dispatch + Accept + Actor-Permissions — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Open a created booking to the eligible technician pool (auto at creation), let the first eligible VERIFIED+skilled technician atomically claim it, support per-technician skip, and add per-transition actor-permission enforcement to the booking state machine.

**Architecture:** Extends `apps/backend/src/modules/bookings/` (state machine gains an `ALLOWED_ACTORS` role gate + `ActorKind`; `createBooking` auto-transitions `CREATED→DISPATCHED`) and adds a new TECHNICIAN-only `src/modules/technician-jobs/` module (available/mine/accept/skip). Accept reuses B1's optimistic-locked `transitionBooking` so concurrent accepts can't both win. Schema adds `Booking.technicianId`, `Service.requiredSkill` (the skill↔service link), and a `JobSkip` join table.

**Tech Stack:** Node 22, Fastify 5, Prisma 6 + PostgreSQL 16, Zod, Vitest (`app.inject()`), TypeScript strict. Branch: `feature/booking-dispatch` (already cut off `main`).

**Design reference:** `docs/designs/2026-06-13-booking-b2a-dispatch-design.md` (decisions 1-8; schema; `ALLOWED_ACTORS` + 3-gate `transitionBooking`; the technician endpoints + atomic-accept flow; directional masking).

**Conventions:** Zod at the boundary (`.strict()`); route→service→DTO (never raw Prisma); auth-first; role-gate in the state machine + identity/ownership-gate in the service; money is integer paise; every transition audited in-tx (Golden Rule 5); directional masking — technician view masks customer phone/omits name, customer view masks technician phone (Golden Rule 7).

---

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `apps/backend/prisma/schema.prisma` | `Booking.technicianId` + relation, `Service.requiredSkill`, `JobSkip` model, Technician back-relations | Modify |
| `apps/backend/prisma/migrations/<ts>_dispatch/` | Generated migration (+ requiredSkill backfill) | Create |
| `apps/backend/tests/schema/helpers.ts` | Add `JobSkip` to TRUNCATE list | Modify |
| `apps/backend/src/shared/utils/mask.ts` | `maskPhone()` helper | Create |
| `apps/backend/src/modules/bookings/bookings.state.ts` | `ActorKind`, `ALLOWED_ACTORS`, 3rd gate, `BookingActor.kind` | Modify |
| `apps/backend/src/modules/bookings/bookings.service.ts` | `createBooking` auto-opens to DISPATCHED; pass `kind` to transitions | Modify |
| `apps/backend/src/modules/bookings/bookings.types.ts` | customer DTO shows assigned technician (name + masked phone) | Modify |
| `apps/backend/src/modules/catalog/catalog.schemas.ts` | `createServiceBody` gains `requiredSkill` | Modify |
| `apps/backend/src/modules/catalog/catalog.service.ts` | `createService` writes `requiredSkill` | Modify |
| `apps/backend/src/modules/technician-jobs/technician-jobs.routes.ts` | `/technician/jobs/*` routes (TECHNICIAN-only) | Create |
| `apps/backend/src/modules/technician-jobs/technician-jobs.service.ts` | `requireTechnician`, `listAvailableJobs`, `listMyJobs`, `acceptJob`, `skipJob` | Create |
| `apps/backend/src/modules/technician-jobs/technician-jobs.types.ts` | `TechnicianJobDto` (masked) + mapper | Create |
| `apps/backend/src/app.ts` | register technician-jobs routes | Modify |
| `apps/backend/tests/bookings/helpers.ts` | extend `seedBookable` with `requiredSkill`; add `makeTechnician` (VERIFIED + skills) | Modify |
| `apps/backend/tests/technician-jobs/dispatch.test.ts` | eligibility, atomic accept race, skip, masking, actor-perms | Create |
| `apps/backend/tests/bookings/booking-create.test.ts` | assert auto-open to DISPATCHED | Modify |
| `docs/02-product/core-flow.md` | push → broadcast wording | Modify |
| `docs/decisions/2026-06-13-dispatch-broadcast-model.md` | record push→broadcast + deferred algo/timer | Create |

All paths relative to repo root `/Users/mohammadkaifsaiyad/Development/FixCare`. Run `pnpm` from `apps/backend`. **Tests need env loaded** — prefix every test command with `set -a && . ./.env && set +a &&`.

**Commit-authorship (every commit):** author `MohammadKaifSaiyad <saiyedkgn6@gmail.com>`, **no** Claude/`Co-Authored-By` trailer. If `prisma migrate dev` reports drift / can't reach the DB, report BLOCKED — do NOT `db push` or hand-patch `_prisma_migrations`.

---

## Task 1: schema — technicianId, requiredSkill, JobSkip + migration

**Files:**
- Modify: `apps/backend/prisma/schema.prisma`
- Modify: `apps/backend/tests/schema/helpers.ts`
- Create: `apps/backend/prisma/migrations/<ts>_dispatch/migration.sql` (generated, then edited for backfill)

- [ ] **Step 1: Add the fields/model to the schema**

In `Booking`, add after `serviceName` (or near the FKs):
```prisma
  technicianId  String?
  technician    Technician?  @relation(fields: [technicianId], references: [id])
```
and in the relations block of `Booking` add `jobSkips JobSkip[]`.

In `Service`, add:
```prisma
  requiredSkill ServiceSkill
```

In `Technician`, add back-relations (among its relation fields):
```prisma
  bookings  Booking[]
  jobSkips  JobSkip[]
```

After the `Booking` model (bookings section), add:
```prisma
model JobSkip {
  id           String     @id @default(uuid())
  technicianId String
  technician   Technician @relation(fields: [technicianId], references: [id])
  bookingId    String
  booking      Booking    @relation(fields: [bookingId], references: [id])
  createdAt    DateTime   @default(now())
  @@unique([technicianId, bookingId])
  @@index([technicianId])
}
```

- [ ] **Step 2: Add `JobSkip` to the test TRUNCATE list**

In `apps/backend/tests/schema/helpers.ts`, the TRUNCATE currently starts `TRUNCATE TABLE "Booking","Address",...`. Add `"JobSkip"` at the FRONT (before `"Booking"`):
```ts
    'TRUNCATE TABLE "JobSkip","Booking","Address","PincodeZone","PartsCatalog","ServicePrice","Service","ServiceCategory","Zone","AuditLog","RefreshToken","Admin","Merchant","Technician","Customer","User" RESTART IDENTITY CASCADE;'
```

- [ ] **Step 3: Generate the migration**
```bash
set -a && . ./.env && set +a && pnpm prisma migrate dev --name dispatch --create-only
```
`--create-only` generates the SQL WITHOUT applying it, so you can add the backfill for the new NOT-NULL `Service.requiredSkill` column (existing service rows have no value → the migration would fail or need a default).

- [ ] **Step 4: Edit the migration to backfill `requiredSkill`**

Open the generated `prisma/migrations/<ts>_dispatch/migration.sql`. Prisma will have emitted `ALTER TABLE "Service" ADD COLUMN "requiredSkill" "ServiceSkill" NOT NULL;` (which fails if rows exist) OR refused. Replace the `requiredSkill` add with an add-nullable → backfill → set-not-null sequence:
```sql
-- requiredSkill: add nullable, backfill existing rows by category name, then enforce NOT NULL
ALTER TABLE "Service" ADD COLUMN "requiredSkill" "ServiceSkill";
UPDATE "Service" s SET "requiredSkill" =
  CASE
    WHEN c."name" ILIKE '%AC%'        THEN 'AC'::"ServiceSkill"
    WHEN c."name" ILIKE '%fan%'       THEN 'FAN'::"ServiceSkill"
    WHEN c."name" ILIKE '%electric%'  THEN 'ELECTRICAL'::"ServiceSkill"
    WHEN c."name" ILIKE '%wir%'       THEN 'WIRING'::"ServiceSkill"
    ELSE 'APPLIANCE'::"ServiceSkill"
  END
  FROM "ServiceCategory" c WHERE s."categoryId" = c."id";
ALTER TABLE "Service" ALTER COLUMN "requiredSkill" SET NOT NULL;
```
Leave the other generated statements (Booking.technicianId column + FK, JobSkip table + indexes) as-is — confirm they are additive. (If Prisma emitted the requiredSkill column differently, adapt: the invariant is add-nullable → backfill → set-not-null.)

- [ ] **Step 5: Apply the migration**
```bash
set -a && . ./.env && set +a && pnpm prisma migrate dev
```
Expected: applies cleanly; client regenerates with `prisma.jobSkip` + `Booking.technicianId` + `Service.requiredSkill`. (`migrate dev` with no `--name` applies the pending edited migration.)

- [ ] **Step 6: Verify the destructive-op scan is understood**
```bash
grep -iE 'DROP|TRUNCATE|ALTER COLUMN' apps/backend/prisma/migrations/*_dispatch/migration.sql
```
Expected: the only `ALTER COLUMN` is the intentional `SET NOT NULL` after backfill (safe — every row was backfilled in the same migration). No `DROP`/`DROP COLUMN`. Note this in the commit message so the migration reviewer knows it's intentional.

- [ ] **Step 7: Commit**
```bash
git add apps/backend/prisma/schema.prisma apps/backend/prisma/migrations apps/backend/tests/schema/helpers.ts
git commit -m "feat(backend): dispatch schema — Booking.technicianId, Service.requiredSkill (backfilled), JobSkip (booking B2a)"
```

---

## Task 2: catalog — `createService` requires `requiredSkill`

**Files:**
- Modify: `apps/backend/src/modules/catalog/catalog.schemas.ts`
- Modify: `apps/backend/src/modules/catalog/catalog.service.ts`
- Modify: `apps/backend/tests/catalog/services-pricing.test.ts` (existing service-create tests now need the field)

- [ ] **Step 1: Add `requiredSkill` to `createServiceBody`**

In `apps/backend/src/modules/catalog/catalog.schemas.ts`, the current line is:
```ts
export const createServiceBody = z.object({ categoryId: z.string().min(1), name: z.string().min(1), tier }).strict();
```
Change to (add a `skill` enum at the top near `tier`, then the field):
```ts
const skill = z.enum(['AC', 'FAN', 'ELECTRICAL', 'WIRING', 'APPLIANCE']);
export const createServiceBody = z.object({ categoryId: z.string().min(1), name: z.string().min(1), tier, requiredSkill: skill }).strict();
```

- [ ] **Step 2: Write `requiredSkill` in `createService`**

In `apps/backend/src/modules/catalog/catalog.service.ts`, `createService`'s `tx.service.create` data currently is `{ categoryId: body.categoryId, name: body.name, tier: body.tier }`. Add `requiredSkill`:
```ts
      const svc = await tx.service.create({ data: { categoryId: body.categoryId, name: body.name, tier: body.tier, requiredSkill: body.requiredSkill } });
```

- [ ] **Step 3: Fix existing service-create tests (they now must send `requiredSkill`)**

Run the catalog suite to find failures:
```bash
set -a && . ./.env && set +a && pnpm test -- tests/catalog/services-pricing.test.ts
```
For every `POST /catalog/services` payload in that file, add `requiredSkill: 'AC'` (or a fitting skill) to the body. Re-run until green.

- [ ] **Step 4: Build + commit**
```bash
cd apps/backend && pnpm build   # expect clean
git add apps/backend/src/modules/catalog tests/catalog/services-pricing.test.ts
git commit -m "feat(backend): service.requiredSkill on create (booking B2a)"
```

---

## Task 3: state machine — `ActorKind` + `ALLOWED_ACTORS` + 3rd gate

**Files:**
- Modify: `apps/backend/src/modules/bookings/bookings.state.ts`
- Create: `apps/backend/tests/bookings/booking-actor-unit.test.ts`

- [ ] **Step 1: Write the failing unit test**

Create `apps/backend/tests/bookings/booking-actor-unit.test.ts`:
```ts
import { describe, expect, it } from 'vitest';
import { actorAllowedFor } from '../../src/modules/bookings/bookings.state.js';

describe('ALLOWED_ACTORS', () => {
  it('SYSTEM may open to DISPATCHED; a customer/technician may not', () => {
    expect(actorAllowedFor('DISPATCHED', 'SYSTEM')).toBe(true);
    expect(actorAllowedFor('DISPATCHED', 'CUSTOMER')).toBe(false);
    expect(actorAllowedFor('DISPATCHED', 'TECHNICIAN')).toBe(false);
  });
  it('TECHNICIAN may accept; a customer may not', () => {
    expect(actorAllowedFor('ACCEPTED', 'TECHNICIAN')).toBe(true);
    expect(actorAllowedFor('ACCEPTED', 'CUSTOMER')).toBe(false);
  });
  it('CUSTOMER may cancel; a technician may not', () => {
    expect(actorAllowedFor('CANCELLED_BY_CUSTOMER', 'CUSTOMER')).toBe(true);
    expect(actorAllowedFor('CANCELLED_BY_CUSTOMER', 'TECHNICIAN')).toBe(false);
  });
  it('an unmapped to-state has no role restriction (returns true)', () => {
    expect(actorAllowedFor('ARRIVED', 'TECHNICIAN')).toBe(true); // no entry yet → allowed (later slices add it)
  });
});
```

- [ ] **Step 2: Run — confirm FAIL**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/bookings/booking-actor-unit.test.ts
```
Expected: FAIL (`actorAllowedFor` not exported).

- [ ] **Step 3: Add `ActorKind`, `ALLOWED_ACTORS`, `actorAllowedFor`, and the gate**

In `apps/backend/src/modules/bookings/bookings.state.ts`:

Add after the imports:
```ts
export type ActorKind = 'CUSTOMER' | 'TECHNICIAN' | 'ADMIN' | 'SYSTEM';

/** Which actor kind may drive a transition INTO a given state. A to-state absent from this map has
 *  no role restriction yet (later slices add their entries). A present to-state is default-deny. */
const ALLOWED_ACTORS: Partial<Record<BookingState, ActorKind[]>> = {
  DISPATCHED:            ['SYSTEM'],
  ACCEPTED:              ['TECHNICIAN'],
  CANCELLED_BY_CUSTOMER: ['CUSTOMER'],
};

export function actorAllowedFor(to: BookingState, kind: ActorKind): boolean {
  const allowed = ALLOWED_ACTORS[to];
  return allowed === undefined || allowed.includes(kind);
}
```

Change `BookingActor` to carry `kind` (keep `type` for the audit's DB enum):
```ts
export interface BookingActor { type: ActorType; kind: ActorKind; id: string; }
```

Import `ForbiddenError` and add the role gate inside `transitionBooking`, between the legality check and the optimistic-lock update:
```ts
import { ConflictError, ForbiddenError } from '../../shared/errors.js';
```
```ts
  if (!isTransitionAllowed(booking.state, to)) {
    throw new ConflictError(`Cannot transition booking from ${booking.state} to ${to}`);
  }
  if (!actorAllowedFor(to, actor.kind)) {
    throw new ForbiddenError(`A ${actor.kind} may not transition a booking to ${to}`);
  }
  // ... existing optimistic-lock updateMany + audit ...
```

- [ ] **Step 4: Run the unit test — confirm PASS**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/bookings/booking-actor-unit.test.ts
```
Expected: PASS (all 4). NOTE: this changes the `BookingActor` shape, so existing callers (createBooking's audit is hand-rolled — not via transitionBooking — but cancelBooking calls transitionBooking with `{ type:'USER', id }` and now needs `kind`). The build will fail until Task 4 updates the callers — that's expected; proceed to Task 4 before re-running the full suite.

- [ ] **Step 5: Commit**
```bash
git add apps/backend/src/modules/bookings/bookings.state.ts apps/backend/tests/bookings/booking-actor-unit.test.ts
git commit -m "feat(backend): actor-permission map + role gate in transitionBooking (booking B2a)"
```

---

## Task 4: auto-open to DISPATCHED + update cancel caller

**Files:**
- Modify: `apps/backend/src/modules/bookings/bookings.service.ts`
- Modify: `apps/backend/tests/bookings/booking-create.test.ts`

- [ ] **Step 1: Update the auto-open assertion in the create test**

In `apps/backend/tests/bookings/booking-create.test.ts`, the first test asserts `state: 'CREATED'`. Change that assertion to `'DISPATCHED'` (the booking now auto-opens), and add an audit-trail assertion:
```ts
    expect(res.json()).toMatchObject({
      state: 'DISPATCHED', visitFeePaise: 14900, laborPaise: 60000, laborTier: 'T2',
      service: { name: 'AC gas refill' }, zone: { name: f.zoneName },
    });
```
And after the create, assert both audit rows exist:
```ts
    const audits = await prisma.auditLog.findMany({ where: { action: 'BOOKING_STATE_CHANGED' }, orderBy: { createdAt: 'asc' } });
    expect(audits.map((a) => (a.metadata as { to: string }).to)).toEqual(['CREATED', 'DISPATCHED']);
```
(Other create tests that only check `statusCode`/422/404 are unaffected. The snapshot-immutability test reads price fields, not state — unaffected.)

- [ ] **Step 2: Run — confirm FAIL**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/bookings/booking-create.test.ts
```
Expected: the first test FAILS (state is still CREATED).

- [ ] **Step 3: Auto-open in `createBooking`; fix the cancel caller's actor**

In `apps/backend/src/modules/bookings/bookings.service.ts`:

Import `transitionBooking` is already imported (used by cancel). Inside `createBooking`'s `$transaction`, after the existing `tx.auditLog.create` (the `null→CREATED` row) and before `return created`, add the auto-open transition:
```ts
        await tx.auditLog.create({
          data: { action: 'BOOKING_STATE_CHANGED', actorType: 'USER', actorId: userId,
                   metadata: { bookingId: created.id, from: null, to: 'CREATED' } },
        });
        // auto-open to the technician pool (SYSTEM actor)
        const opened = await transitionBooking(tx, created, 'DISPATCHED', { type: 'SYSTEM', kind: 'SYSTEM', id: 'system' });
        return opened;
```
(`transitionBooking` does the legality + actor-role (SYSTEM allowed for DISPATCHED) + optimistic-lock + audit, and returns the re-read row in `DISPATCHED`.)

Update `cancelBooking`'s `transitionBooking` call — it currently passes `{ type: 'USER', id: userId }`; add `kind: 'CUSTOMER'`:
```ts
  const updated = await prisma.$transaction((tx) =>
    transitionBooking(tx, booking, 'CANCELLED_BY_CUSTOMER', { type: 'USER', kind: 'CUSTOMER', id: userId }),
  );
```

- [ ] **Step 4: Run — confirm PASS**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/bookings
```
Expected: PASS — create lands in DISPATCHED with both audit rows; cancel still works (CREATED→… wait: bookings now auto-open to DISPATCHED, so the cancel test that creates then cancels now cancels from DISPATCHED — confirm `DISPATCHED→CANCELLED_BY_CUSTOMER` is a legal edge: YES it is in ALLOWED_TRANSITIONS). The "cancel a non-CREATED booking → 409" test force-sets state to `ARRIVED` (ARRIVED has no cancel edge) → still 409. The concurrent-cancel test creates (→DISPATCHED) then double-cancels from DISPATCHED → still one wins. All good.

- [ ] **Step 5: Build + commit**
```bash
cd apps/backend && pnpm build   # expect clean
git add apps/backend/src/modules/bookings/bookings.service.ts apps/backend/tests/bookings/booking-create.test.ts
git commit -m "feat(backend): auto-open booking to DISPATCHED at creation (booking B2a)"
```

---

## Task 5: maskPhone helper + technician-jobs DTO

**Files:**
- Create: `apps/backend/src/shared/utils/mask.ts`
- Create: `apps/backend/tests/shared/mask.test.ts`
- Create: `apps/backend/src/modules/technician-jobs/technician-jobs.types.ts`

- [ ] **Step 1: Write the failing mask test**

Create `apps/backend/tests/shared/mask.test.ts`:
```ts
import { describe, expect, it } from 'vitest';
import { maskPhone } from '../../src/shared/utils/mask.js';

describe('maskPhone', () => {
  it('keeps the last 4 digits, masks the rest', () => {
    expect(maskPhone('9876543210')).toBe('••••••3210');
  });
  it('handles a +91 prefixed number (mask all but last 4)', () => {
    expect(maskPhone('+919876543210')).toMatch(/3210$/);
    expect(maskPhone('+919876543210')).not.toContain('98765');
  });
  it('a short/empty value masks to all dots (never leaks)', () => {
    expect(maskPhone('12')).toBe('••');
    expect(maskPhone('')).toBe('');
  });
});
```

- [ ] **Step 2: Run — confirm FAIL**, then implement `src/shared/utils/mask.ts`:
```bash
set -a && . ./.env && set +a && pnpm test -- tests/shared/mask.test.ts
```
```ts
/** Mask all but the last 4 digits of a phone-like string with • (no PII leak — Golden Rule 7). */
export function maskPhone(phone: string): string {
  if (phone.length <= 4) return '•'.repeat(phone.length);
  return '•'.repeat(phone.length - 4) + phone.slice(-4);
}
```
Re-run → PASS.

- [ ] **Step 3: Create `technician-jobs.types.ts`**

The DTO is a masked job view; the mapper takes a booking row plus its joined service/zone/address/customer-user (the service loads them). No raw customer phone/name.
```ts
import type { Booking, Service, Address } from '@prisma/client';
import { maskPhone } from '../../shared/utils/mask.js';

export interface TechnicianJobDto {
  id: string;
  bookingNumber: string;
  state: Booking['state'];
  scheduledSlot: string;
  service: { name: string; requiredSkill: Service['requiredSkill'] };
  zone: { name: string };
  visitFeePaise: number;
  laborPaise: number;
  address: { line1: string; line2: string | null; landmark: string | null; pincode: string };
  customer: { maskedPhone: string };
}

/** `booking` carries the snapshot fields; `address` is the booking's address row; `customerPhone`
 *  is the customer User.phone (masked here — never returned raw). */
export function toTechnicianJobDto(booking: Booking, address: Address, customerPhone: string): TechnicianJobDto {
  return {
    id: booking.id,
    bookingNumber: booking.bookingNumber,
    state: booking.state,
    scheduledSlot: booking.scheduledSlot.toISOString(),
    service: { name: booking.serviceName, requiredSkill: 'APPLIANCE' as Service['requiredSkill'] }, // overwritten below if loaded
    zone: { name: booking.zoneName },
    visitFeePaise: booking.visitFeePaise,
    laborPaise: booking.laborPaise,
    address: { line1: address.line1, line2: address.line2, landmark: address.landmark, pincode: address.pincode },
    customer: { maskedPhone: maskPhone(customerPhone) },
  };
}
```
NOTE on `requiredSkill` in the DTO: `serviceName` is snapshotted on the booking but `requiredSkill` is not — so the mapper needs it passed in. Simplify: change the mapper signature to also take `requiredSkill: ServiceSkill` and set `service.requiredSkill` from it (the service fetches the Service row for the eligibility filter anyway). Final mapper signature:
```ts
import type { ServiceSkill } from '@prisma/client';
export function toTechnicianJobDto(booking: Booking, address: Address, requiredSkill: ServiceSkill, customerPhone: string): TechnicianJobDto {
  // ...service: { name: booking.serviceName, requiredSkill }, ...
}
```

- [ ] **Step 4: Build + commit**
```bash
cd apps/backend && pnpm build   # expect clean
git add apps/backend/src/shared/utils/mask.ts apps/backend/tests/shared/mask.test.ts apps/backend/src/modules/technician-jobs/technician-jobs.types.ts
git commit -m "feat(backend): maskPhone + TechnicianJobDto (booking B2a)"
```

---

## Task 6: technician-jobs service + routes (available / mine / accept / skip)

**Files:**
- Create: `apps/backend/src/modules/technician-jobs/technician-jobs.service.ts`
- Create: `apps/backend/src/modules/technician-jobs/technician-jobs.routes.ts`
- Modify: `apps/backend/src/app.ts`
- Modify: `apps/backend/tests/bookings/helpers.ts`
- Create: `apps/backend/tests/technician-jobs/dispatch.test.ts`

- [ ] **Step 1: Extend the test helpers**

In `apps/backend/tests/bookings/helpers.ts`: (a) `seedBookable` now must set `requiredSkill` on the service it creates; (b) add a `makeTechnician` helper.

In `seedBookable`, change the service create to include `requiredSkill` and return it:
```ts
  const service = await prisma.service.create({ data: { categoryId: cat.id, name: 'AC gas refill', tier: 'T2', requiredSkill: 'AC' } });
```
(and add `requiredSkill: 'AC' as const` to the returned object if convenient.)

Add:
```ts
import type { ServiceSkill } from '@prisma/client';

export async function makeTechnician(skills: ServiceSkill[] = ['AC'], status: 'VERIFIED' | 'PENDING' = 'VERIFIED') {
  const user = await prisma.user.create({ data: { phone: uniquePhone(), role: 'TECHNICIAN' } });
  const t = await prisma.technician.create({ data: { userId: user.id, name: 'Tech', skills, status } });
  return { token: signAccessToken(user.id, 'TECHNICIAN'), userId: user.id, technicianId: t.id };
}
```

- [ ] **Step 2: Write the failing dispatch tests**

Create `apps/backend/tests/technician-jobs/dispatch.test.ts`:
```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, makeTechnician, seedBookable } from '../bookings/helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
function future() { return new Date(Date.now() + 86_400_000).toISOString(); }

async function book(custToken: string, addressId: string, serviceId: string) {
  return (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(custToken),
    payload: { addressId, serviceId, scheduledSlot: future() } })).json();
}

describe('technician dispatch — available + accept + skip', () => {
  it('a VERIFIED tech with the matching skill sees the open job; masked customer phone, no name', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    await book(c.token, f.address.id, f.service.id);
    const t = await makeTechnician(['AC']);
    const res = await app.inject({ method: 'GET', url: '/technician/jobs/available', headers: auth(t.token) });
    expect(res.statusCode).toBe(200);
    const jobs = res.json();
    expect(jobs).toHaveLength(1);
    expect(jobs[0].customer.maskedPhone).toMatch(/^•+\d{4}$/);
    expect(JSON.stringify(jobs[0])).not.toContain('Cust'); // no customer name leaked
    expect(jobs[0].address.pincode).toBe(f.pincode);       // address IS shown (needed to service)
  });

  it('wrong-skill tech and unverified tech do not see / cannot act', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId); // requiredSkill 'AC'
    await book(c.token, f.address.id, f.service.id);
    const fan = await makeTechnician(['FAN']);
    expect((await app.inject({ method: 'GET', url: '/technician/jobs/available', headers: auth(fan.token) })).json()).toHaveLength(0);
    const pending = await makeTechnician(['AC'], 'PENDING');
    expect((await app.inject({ method: 'GET', url: '/technician/jobs/available', headers: auth(pending.token) })).statusCode).toBe(403);
  });

  it('first-to-accept wins atomically; the loser gets 409; one ACCEPTED audit', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const booking = await book(c.token, f.address.id, f.service.id);
    const t1 = await makeTechnician(['AC']);
    const t2 = await makeTechnician(['AC']);
    const [r1, r2] = await Promise.all([
      app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(t1.token) }),
      app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(t2.token) }),
    ]);
    expect([r1.statusCode, r2.statusCode].sort()).toEqual([200, 409]);
    const updated = await prisma.booking.findUnique({ where: { id: booking.id } });
    expect(updated!.state).toBe('ACCEPTED');
    expect(updated!.technicianId).toBeTruthy();
    const accAudits = await prisma.auditLog.findMany({ where: { action: 'BOOKING_STATE_CHANGED', metadata: { path: ['to'], equals: 'ACCEPTED' } } });
    expect(accAudits).toHaveLength(1);
  });

  it('an unskilled tech accepting → 403; accepting an already-taken job → 409', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const booking = await book(c.token, f.address.id, f.service.id);
    const fan = await makeTechnician(['FAN']);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(fan.token) })).statusCode).toBe(403);
    const ac1 = await makeTechnician(['AC']);
    await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(ac1.token) });
    const ac2 = await makeTechnician(['AC']);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(ac2.token) })).statusCode).toBe(409);
  });

  it('skip hides the job from that tech only; idempotent; others still see it', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const booking = await book(c.token, f.address.id, f.service.id);
    const t1 = await makeTechnician(['AC']);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/skip`, headers: auth(t1.token) })).statusCode).toBe(204);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/skip`, headers: auth(t1.token) })).statusCode).toBe(204); // idempotent
    expect((await app.inject({ method: 'GET', url: '/technician/jobs/available', headers: auth(t1.token) })).json()).toHaveLength(0);
    const t2 = await makeTechnician(['AC']);
    expect((await app.inject({ method: 'GET', url: '/technician/jobs/available', headers: auth(t2.token) })).json()).toHaveLength(1);
  });

  it('mine returns the tech\'s accepted jobs; non-technician → 403', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const booking = await book(c.token, f.address.id, f.service.id);
    const t = await makeTechnician(['AC']);
    await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(t.token) });
    expect((await app.inject({ method: 'GET', url: '/technician/jobs/mine', headers: auth(t.token) })).json()).toHaveLength(1);
    expect((await app.inject({ method: 'GET', url: '/technician/jobs/available', headers: auth(c.token) })).statusCode).toBe(403); // customer
  });
});
```

- [ ] **Step 3: Run — confirm FAIL**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/technician-jobs/dispatch.test.ts
```
Expected: FAIL (routes not registered).

- [ ] **Step 4: Create `technician-jobs.service.ts`**
```ts
import { prisma } from '../../shared/database/prisma.js';
import { ForbiddenError, NotFoundError, ConflictError } from '../../shared/errors.js';
import { transitionBooking } from '../bookings/bookings.state.js';
import { toTechnicianJobDto, type TechnicianJobDto } from './technician-jobs.types.js';

async function requireTechnician(userId: string): Promise<{ id: string; skills: import('@prisma/client').ServiceSkill[] }> {
  const t = await prisma.technician.findFirst({ where: { userId, deletedAt: null } });
  if (!t || t.status !== 'VERIFIED') throw new ForbiddenError('Verified technician required');
  return { id: t.id, skills: t.skills };
}

export async function listAvailableJobs(userId: string): Promise<TechnicianJobDto[]> {
  const tech = await requireTechnician(userId);
  const skipped = await prisma.jobSkip.findMany({ where: { technicianId: tech.id }, select: { bookingId: true } });
  const skippedIds = skipped.map((s) => s.bookingId);
  const bookings = await prisma.booking.findMany({
    where: {
      state: 'DISPATCHED',
      technicianId: null,
      deletedAt: null,
      id: { notIn: skippedIds.length ? skippedIds : undefined },
      service: { requiredSkill: { in: tech.skills } },
    },
    include: { address: true, service: true, customer: { include: { user: true } } },
    orderBy: { createdAt: 'desc' },
  });
  return bookings.map((b) => toTechnicianJobDto(b, b.address, b.service.requiredSkill, b.customer.user.phone));
}

export async function listMyJobs(userId: string): Promise<TechnicianJobDto[]> {
  const tech = await requireTechnician(userId);
  const bookings = await prisma.booking.findMany({
    where: { technicianId: tech.id, deletedAt: null },
    include: { address: true, service: true, customer: { include: { user: true } } },
    orderBy: { createdAt: 'desc' },
  });
  return bookings.map((b) => toTechnicianJobDto(b, b.address, b.service.requiredSkill, b.customer.user.phone));
}

export async function acceptJob(userId: string, bookingId: string): Promise<TechnicianJobDto> {
  const tech = await requireTechnician(userId);
  const booking = await prisma.booking.findFirst({ where: { id: bookingId, deletedAt: null }, include: { service: true } });
  if (!booking) throw new NotFoundError('Job not found');
  if (booking.state !== 'DISPATCHED' || booking.technicianId) throw new ConflictError('This job is no longer available');
  if (!tech.skills.includes(booking.service.requiredSkill)) throw new ForbiddenError('You are not skilled for this job');

  const updated = await prisma.$transaction(async (tx) => {
    // transitionBooking does the optimistic-locked DISPATCHED→ACCEPTED + audit; then claim technicianId
    await transitionBooking(tx, booking, 'ACCEPTED', { type: 'USER', kind: 'TECHNICIAN', id: userId });
    return tx.booking.update({ where: { id: bookingId }, data: { technicianId: tech.id } });
  });
  const full = await prisma.booking.findUniqueOrThrow({ where: { id: updated.id }, include: { address: true, service: true, customer: { include: { user: true } } } });
  return toTechnicianJobDto(full, full.address, full.service.requiredSkill, full.customer.user.phone);
}

export async function skipJob(userId: string, bookingId: string): Promise<void> {
  const tech = await requireTechnician(userId);
  const booking = await prisma.booking.findFirst({ where: { id: bookingId, deletedAt: null } });
  if (!booking) throw new NotFoundError('Job not found');
  await prisma.jobSkip.upsert({
    where: { technicianId_bookingId: { technicianId: tech.id, bookingId } },
    create: { technicianId: tech.id, bookingId },
    update: {},
  });
}
```
NOTE on the accept atomicity: `transitionBooking` is the optimistic lock (`updateMany where {id, state:'DISPATCHED'}`). The concurrent loser's `transitionBooking` gets `count===0` → `ConflictError` (409). The `technicianId` set happens after the successful transition in the same tx. (The pre-tx `state !== 'DISPATCHED'` check is a fast-path 409; the tx is the real guard.)

- [ ] **Step 5: Create `technician-jobs.routes.ts`**
```ts
import type { FastifyInstance } from 'fastify';
import { requireAuth } from '../../shared/middleware/auth.js';
import { ForbiddenError } from '../../shared/errors.js';
import { listAvailableJobs, listMyJobs, acceptJob, skipJob } from './technician-jobs.service.js';

function requireTechnicianRole(req: { user?: { role: string } }): void {
  if (req.user?.role !== 'TECHNICIAN') throw new ForbiddenError('Technician access required');
}

export async function registerTechnicianJobRoutes(app: FastifyInstance) {
  app.get('/technician/jobs/available', { preHandler: [requireAuth] }, async (req, reply) => {
    requireTechnicianRole(req);
    return reply.send(await listAvailableJobs(req.user!.id));
  });

  app.get('/technician/jobs/mine', { preHandler: [requireAuth] }, async (req, reply) => {
    requireTechnicianRole(req);
    return reply.send(await listMyJobs(req.user!.id));
  });

  app.post('/technician/jobs/:id/accept', { preHandler: [requireAuth] }, async (req, reply) => {
    requireTechnicianRole(req);
    return reply.send(await acceptJob(req.user!.id, (req.params as { id: string }).id));
  });

  app.post('/technician/jobs/:id/skip', { preHandler: [requireAuth] }, async (req, reply) => {
    requireTechnicianRole(req);
    await skipJob(req.user!.id, (req.params as { id: string }).id);
    return reply.code(204).send();
  });
}
```

- [ ] **Step 6: Register in `app.ts`**
```ts
import { registerTechnicianJobRoutes } from './modules/technician-jobs/technician-jobs.routes.js';
```
After `await registerBookingRoutes(app);`:
```ts
  await registerTechnicianJobRoutes(app);
```

- [ ] **Step 7: Run — confirm PASS**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/technician-jobs/dispatch.test.ts
```
Expected: PASS (all). If the "wrong-skill list is empty" test fails because `id: { notIn: undefined }` misbehaves, confirm the `notIn` is only set when `skippedIds.length` (the code does `skippedIds.length ? skippedIds : undefined`; Prisma treats `notIn: undefined` as "no filter" — correct).

- [ ] **Step 8: Build + commit**
```bash
cd apps/backend && pnpm build   # expect clean
git add apps/backend/src/modules/technician-jobs apps/backend/src/app.ts apps/backend/tests/bookings/helpers.ts apps/backend/tests/technician-jobs/dispatch.test.ts
git commit -m "feat(backend): technician-jobs — available/mine/accept/skip broadcast dispatch (booking B2a)"
```

---

## Task 7: customer sees assigned technician + docs + full suite + reviews

**Files:**
- Modify: `apps/backend/src/modules/bookings/bookings.types.ts` + `bookings.service.ts` (getBooking includes technician)
- Modify: `apps/backend/tests/bookings/booking-state.test.ts` (assert customer sees technician after accept)
- Modify: `docs/02-product/core-flow.md`
- Create: `docs/decisions/2026-06-13-dispatch-broadcast-model.md`
- Modify: `STATUS.md`, `CHANGELOG.md`

- [ ] **Step 1: Customer DTO shows the assigned technician (masked)**

In `bookings.types.ts`, add an optional `technician` field to `BookingDto`:
```ts
  technician?: { name: string; maskedPhone: string };
```
Change `toBookingDto` to accept an optional technician + phone and include it when present:
```ts
import { maskPhone } from '../../shared/utils/mask.js';
export function toBookingDto(b: Booking, tech?: { name: string; phone: string }): BookingDto {
  return {
    // ...existing fields...,
    ...(tech ? { technician: { name: tech.name, maskedPhone: maskPhone(tech.phone) } } : {}),
  };
}
```
In `bookings.service.ts` `getBooking`, load the technician (+ its user phone) when `technicianId` is set and pass it to `toBookingDto`:
```ts
export async function getBooking(userId: string, id: string): Promise<BookingDto> {
  const { id: customerId } = await requireCustomer(userId);
  const b = await prisma.booking.findFirst({ where: { id, customerId, deletedAt: null }, include: { technician: { include: { user: true } } } });
  if (!b) throw new NotFoundError('Booking not found');
  return toBookingDto(b, b.technician ? { name: b.technician.name, phone: b.technician.user.phone } : undefined);
}
```
(`listBookings` can stay snapshot-only or also include — keep it simple: list stays without technician; detail shows it. If the DTO type requires it, the optional field is fine omitted.)

- [ ] **Step 2: Add the customer-sees-technician test**

In `apps/backend/tests/bookings/booking-state.test.ts` add:
```ts
  it('after a technician accepts, the customer booking detail shows technician name + masked phone', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const booking = await createBooking(c.token, f.address.id, f.service.id);
    const { makeTechnician } = await import('./helpers.js');
    const t = await makeTechnician(['AC']);
    await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(t.token) });
    const got = (await app.inject({ method: 'GET', url: `/me/bookings/${booking.id}`, headers: auth(c.token) })).json();
    expect(got.state).toBe('ACCEPTED');
    expect(got.technician.name).toBe('Tech');
    expect(got.technician.maskedPhone).toMatch(/^•+\d{4}$/);
  });
```
Run `pnpm test -- tests/bookings/booking-state.test.ts` → implement until green.

- [ ] **Step 3: Update `core-flow.md`**

In `docs/02-product/core-flow.md` Phase A, replace the push wording. Change:
```
- Dispatch algorithm picks technician:
  `rating × proximity × current_load × cash_compliance`
```
and the "Accept/reject (30-second timer)" line, to describe the **broadcast** model: the booking opens to all eligible (VERIFIED + matching-skill) technicians; the first to accept wins; the weighted ranking + 30s timer are future enhancements. Keep the surrounding fraud-lock bullets. Add a one-line pointer to the decision doc.

- [ ] **Step 4: Write the decision doc**

Create `docs/decisions/2026-06-13-dispatch-broadcast-model.md`: record that V1 dispatch is **broadcast / first-to-accept** (not the originally-documented push + weighted algorithm); the weighted `rating×proximity×load×cash` algorithm (B2c) and the 30-sec accept timer (B2b) are deferred until trust-score / location / cash / queue infra exist; eligibility is VERIFIED + matching skill (zone-coverage deferred). Link the design doc.

- [ ] **Step 5: Full suite**
```bash
set -a && . ./.env && set +a && cd apps/backend && pnpm test
```
Expected: ALL green (the prior 165 + the new dispatch/mask/actor tests, minus none). Note the total.

- [ ] **Step 6: Review agents**
- `prisma-migration-reviewer` — the `dispatch` migration: the `requiredSkill` add-nullable→backfill→set-not-null sequence (confirm it's safe — every row backfilled in the same migration), `Booking.technicianId` nullable FK, `JobSkip` unique+index.
- `golden-rules-auditor` — actor-permission gate (role in state machine, identity in service); atomic accept (one winner); **directional masking** (no raw customer phone/name in the technician view; no raw technician phone in the customer view); audit-in-tx; no money in B2a.
- `fraud-vector-checker` — broadcast dispatch vs fraud-defenses: confirm the cash-debt-limit + self-dealing locks are **deferred (noted, not dropped)**; the masked-phone requirement holds; no way for an unverified/unskilled tech to claim a job.

Address blockers; then `/code-review` on the branch.

- [ ] **Step 7: STATUS + CHANGELOG**

STATUS: booking module — B1 merged, **B2a done** on branch; Active task → B2a summary; Next 3 → B2b (accept timer + BullMQ) or B3 (arrival handshake). CHANGELOG: `## 2026-06-13 — Booking B2a (broadcast dispatch + accept + actor-permissions)` with the model-change note. `_Last updated_` 2026-06-13.

- [ ] **Step 8: Commit docs + finish branch**
```bash
git add apps/backend/src/modules/bookings docs/02-product/core-flow.md docs/decisions STATUS.md CHANGELOG.md apps/backend/tests/bookings/booking-state.test.ts
git commit -m "feat(backend): customer sees assigned technician + dispatch docs/decision (booking B2a)"
```
Then use `superpowers:finishing-a-development-branch` → PR `feature/booking-dispatch` → `main`. (Push/PR is the user's step.) B2b (accept timer) or B3 (arrival handshake) continues the module after merge.

---

## Self-Review notes

- **Spec coverage:** schema (technicianId/requiredSkill/JobSkip) ✓ T1; requiredSkill on catalog create ✓ T2; ActorKind + ALLOWED_ACTORS + 3rd gate ✓ T3; auto-open CREATED→DISPATCHED ✓ T4; maskPhone + TechnicianJobDto ✓ T5; available/mine/accept(atomic)/skip + eligibility + masking ✓ T6; customer-sees-technician + core-flow update + decision doc ✓ T7. Decisions 1-8 covered. Deferred (B2b timer, B2c algo, zone coverage, money, cash/self-dealing locks) explicitly out of scope.
- **Placeholder scan:** none — every step has concrete code/commands. (T1 S4 backfill SQL and T5 S3 mapper-signature note are concrete instructions.)
- **Type consistency:** `BookingActor { type, kind, id }` updated in T3 and all callers updated in T4 (createBooking auto-open SYSTEM, cancel CUSTOMER) + T6 (accept TECHNICIAN); `ActorKind`/`actorAllowedFor`/`ALLOWED_ACTORS` consistent; `toTechnicianJobDto(booking, address, requiredSkill, customerPhone)` final signature used consistently in service T6; `maskPhone` shared by technician + customer DTOs; `prisma.jobSkip`/`technicianId_bookingId` composite key matches the `@@unique([technicianId, bookingId])`. `transitionBooking` reused (not reimplemented) for the atomic accept.
- **Migration safety:** the one `ALTER COLUMN ... SET NOT NULL` is intentional and safe (backfilled in the same migration) — flagged for the reviewer in T1 S6 + the commit message.
- **Atomic accept:** the optimistic lock lives in `transitionBooking` (reused from B1); the loser gets `count===0`→409. The `technicianId` claim is in the same tx after the successful transition.
