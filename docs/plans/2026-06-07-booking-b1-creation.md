# Booking B1 — Creation + Price Snapshot + State Skeleton — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a customer create a booking for a catalog service at one of their addresses, capturing a price snapshot (zone + visit fee + labor + tier) locked at creation, with a guarded state machine that B2–B7 will extend; plus owner-scoped read + customer-cancel.

**Architecture:** New `apps/backend/src/modules/bookings/` mirroring the catalog/addresses modules (route→service→DTO, CUSTOMER-only owner-scoping). A central `ALLOWED_TRANSITIONS` table + a single guarded `transitionBooking` is the seam every later booking slice extends. Creation resolves the address→zone live (reusing addresses' `resolvePincode`) and looks up the catalog `ServicePrice`, then **denormalizes** the result onto the `Booking` row so later catalog/coverage edits never change an existing booking. Every transition writes `BOOKING_STATE_CHANGED` to AuditLog in the same transaction.

**Tech Stack:** Node 22, Fastify 5, Prisma 6 + PostgreSQL 16, Zod, Vitest (`app.inject()`), TypeScript strict. Branch: `feature/booking-module` (already cut off `main`).

**Design reference:** `docs/designs/2026-06-07-booking-b1-creation-design.md` (decisions 1-8; schema `Booking`; `ALLOWED_TRANSITIONS` + `transitionBooking`; the 4 endpoints + 8-step creation flow; the snapshot-immutability test).

**Conventions:** Zod at the boundary (`.strict()`); route→service→DTO (never raw Prisma); auth-first; **CUSTOMER-only** + ownership (others' ids → 404, no IDOR); money is integer paise; **every transition audited in-transaction** (Golden Rule 5); no PII in audit metadata.

---

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `apps/backend/prisma/schema.prisma` | `Booking` model + `BookingState` enum + `BOOKING_STATE_CHANGED` audit action + Customer/Address/Service back-relations | Modify |
| `apps/backend/prisma/migrations/<ts>_booking/` | Generated migration | Create (migrate dev) |
| `apps/backend/tests/schema/helpers.ts` | Add `Booking` to TRUNCATE list | Modify |
| `apps/backend/src/modules/bookings/bookings.number.ts` | `generateBookingNumber()` (FC- + base32) | Create |
| `apps/backend/src/modules/bookings/bookings.state.ts` | `ALLOWED_TRANSITIONS`, actor-permission map, `transitionBooking`, `BookingActor` type | Create |
| `apps/backend/src/modules/bookings/bookings.types.ts` | `BookingDto` + `toBookingDto` | Create |
| `apps/backend/src/modules/bookings/bookings.schemas.ts` | `createBookingBody` | Create |
| `apps/backend/src/modules/bookings/bookings.service.ts` | `createBooking`, `listBookings`, `getBooking`, `cancelBooking` | Create |
| `apps/backend/src/modules/bookings/bookings.routes.ts` | the 4 `/me/bookings` routes (CUSTOMER-only) | Create |
| `apps/backend/src/app.ts` | register booking routes | Modify |
| `apps/backend/tests/bookings/helpers.ts` | seed a customer+token + zone/service/price/pincode/address happy-path fixture | Create |
| `apps/backend/tests/bookings/booking-create.test.ts` | creation + snapshot-immutability + guards | Create |
| `apps/backend/tests/bookings/booking-state.test.ts` | list/get/cancel + ownership + transition guards | Create |

All paths relative to repo root `/Users/mohammadkaifsaiyad/Development/FixCare`. Run `pnpm` from `apps/backend`. **Tests need env loaded** — every test command is prefixed `set -a && . ./.env && set +a &&`.

**Commit-authorship (every commit):** author `MohammadKaifSaiyad <saiyedkgn6@gmail.com>`, **no** Claude/`Co-Authored-By` trailer (a git hook rejects it). If `prisma migrate dev` reports drift or can't reach the DB, report BLOCKED — do NOT `db push` or hand-patch `_prisma_migrations`.

---

## Task 1: `Booking` model + enum + audit action + migration

**Files:**
- Modify: `apps/backend/prisma/schema.prisma`
- Modify: `apps/backend/tests/schema/helpers.ts`
- Create: `apps/backend/prisma/migrations/<ts>_booking/migration.sql` (generated)

- [ ] **Step 1: Add `BOOKING_STATE_CHANGED` to the `AuditAction` enum**

In `apps/backend/prisma/schema.prisma`, the `AuditAction` enum currently ends with `CATALOG_UPDATED`. Add the new value:
```prisma
  PRICE_CHANGED
  CATALOG_UPDATED
  BOOKING_STATE_CHANGED
}
```

- [ ] **Step 2: Add the `Booking` model + `BookingState` enum**

After the `Address` model (the addresses module section), add:
```prisma
model Booking {
  id            String   @id @default(uuid())
  bookingNumber String   @unique
  customerId    String
  customer      Customer @relation(fields: [customerId], references: [id])
  addressId     String
  address       Address  @relation(fields: [addressId], references: [id])
  serviceId     String
  service       Service  @relation(fields: [serviceId], references: [id])

  zoneId        String
  zoneName      String
  serviceName   String
  visitFeePaise Int
  laborPaise    Int
  laborTier     LaborTier

  scheduledSlot DateTime
  state         BookingState @default(CREATED)
  createdAt     DateTime     @default(now())
  updatedAt     DateTime     @updatedAt
  deletedAt     DateTime?
  @@index([customerId])
  @@index([state])
}

enum BookingState {
  CREATED
  DISPATCHED
  ACCEPTED
  EN_ROUTE
  ARRIVED
  DIAGNOSED
  CUSTOMER_APPROVED
  PARTS_REQUESTED
  PARTS_ACQUIRED
  REPAIR_IN_PROGRESS
  REPAIR_COMPLETE
  CUSTOMER_CONFIRMED
  PAYMENT_RECEIVED
  CLOSED
  CANCELLED_BY_CUSTOMER
  CANCELLED_BY_TECHNICIAN
  DECLINED_BY_CUSTOMER
  DISPUTED
}
```

- [ ] **Step 3: Add back-relations on `Customer`, `Address`, `Service`**

- `Customer` model: after its last field (`addresses Address[]`), add `bookings Booking[]`.
- `Address` model: after its last field/`@@index`, add `bookings Booking[]` (before the closing `}` / after the relations block — place it among the relation fields).
- `Service` model: it currently has `prices ServicePrice[]`; add `bookings Booking[]`.

(Read each model first; add the back-relation line without disturbing existing fields.)

- [ ] **Step 4: Add `Booking` to the test TRUNCATE list**

In `apps/backend/tests/schema/helpers.ts`, the TRUNCATE currently starts `TRUNCATE TABLE "Address","PincodeZone",...`. Add `"Booking"` at the FRONT:
```ts
    'TRUNCATE TABLE "Booking","Address","PincodeZone","PartsCatalog","ServicePrice","Service","ServiceCategory","Zone","AuditLog","RefreshToken","Admin","Merchant","Technician","Customer","User" RESTART IDENTITY CASCADE;'
```

- [ ] **Step 5: Generate + apply the migration**
```bash
set -a && . ./.env && set +a && pnpm prisma migrate dev --name booking
```
Expected: `prisma/migrations/<ts>_booking/migration.sql` created + applied; client regenerates with a `prisma.booking` accessor and the new enum + `BOOKING_STATE_CHANGED`. CREATE TABLE with FKs to Customer/Address/Service, unique `bookingNumber`, indexes on `customerId` + `state`. Additive only.

- [ ] **Step 6: Verify additive-only**
```bash
grep -iE 'DROP|TRUNCATE|ALTER COLUMN' apps/backend/prisma/migrations/*_booking/migration.sql || echo "clean: additive only"
```
Expected: `clean: additive only` (a new enum value + new enum + new table; `ALTER TYPE ... ADD VALUE` for the audit enum is additive and fine).

- [ ] **Step 7: Commit**
```bash
git add apps/backend/prisma/schema.prisma apps/backend/prisma/migrations apps/backend/tests/schema/helpers.ts
git commit -m "feat(backend): add Booking model + state enum + audit action (booking B1)"
```

---

## Task 2: `generateBookingNumber`

**Files:**
- Create: `apps/backend/src/modules/bookings/bookings.number.ts`
- Create: `apps/backend/tests/bookings/booking-number.test.ts`

- [ ] **Step 1: Write the failing test**

Create `apps/backend/tests/bookings/booking-number.test.ts`:
```ts
import { describe, expect, it } from 'vitest';
import { generateBookingNumber } from '../../src/modules/bookings/bookings.number.js';

describe('generateBookingNumber', () => {
  it('returns an FC- prefixed code of the right shape', () => {
    const n = generateBookingNumber();
    expect(n).toMatch(/^FC-[0-9A-HJ-NP-Z]{6}$/); // Crockford base32, no I/L/O/U
  });

  it('is highly unlikely to collide across many calls', () => {
    const seen = new Set<string>();
    for (let i = 0; i < 10000; i++) seen.add(generateBookingNumber());
    expect(seen.size).toBe(10000);
  });
});
```

- [ ] **Step 2: Run — confirm FAIL**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/bookings/booking-number.test.ts
```
Expected: FAIL (module not found).

- [ ] **Step 3: Implement**

Create `apps/backend/src/modules/bookings/bookings.number.ts`:
```ts
import { randomInt } from 'node:crypto';

// Crockford base32 alphabet (no I, L, O, U — avoids ambiguity when read aloud to support).
const ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/** Generate a human-friendly booking reference, e.g. "FC-7K3M2Q".
 *  6 chars of crypto-random base32 → ~1.07e9 space; uniqueness is enforced by the DB @unique,
 *  the caller retries on the rare P2002 collision. */
export function generateBookingNumber(): string {
  let code = '';
  for (let i = 0; i < 6; i++) code += ALPHABET[randomInt(ALPHABET.length)];
  return `FC-${code}`;
}
```
Note: the test regex `[0-9A-HJ-NP-Z]` permits exactly the Crockford letters used here (no I/L/O/U); `V`,`W`,`X`,`Y`,`Z` are included, `T` too — all within `A-HJ-NP-Z`? Verify: the alphabet uses `...HJKMNPQRSTVWXYZ`. The regex class `A-HJ-NP-Z` excludes I, O. It still allows L and U which the alphabet doesn't emit (fine — regex is a superset). It correctly rejects I/O. Acceptable.

- [ ] **Step 4: Run — confirm PASS**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/bookings/booking-number.test.ts
```
Expected: PASS (both).

- [ ] **Step 5: Commit**
```bash
git add apps/backend/src/modules/bookings/bookings.number.ts apps/backend/tests/bookings/booking-number.test.ts
git commit -m "feat(backend): bookingNumber generator (booking B1)"
```

---

## Task 3: state machine — `ALLOWED_TRANSITIONS` + `transitionBooking`

**Files:**
- Create: `apps/backend/src/modules/bookings/bookings.state.ts`
- Create: `apps/backend/tests/bookings/booking-state-unit.test.ts`

- [ ] **Step 1: Write the failing unit test**

Create `apps/backend/tests/bookings/booking-state-unit.test.ts`:
```ts
import { describe, expect, it } from 'vitest';
import { ALLOWED_TRANSITIONS, isTransitionAllowed } from '../../src/modules/bookings/bookings.state.js';

describe('ALLOWED_TRANSITIONS', () => {
  it('allows CREATED → CANCELLED_BY_CUSTOMER and CREATED → DISPATCHED', () => {
    expect(isTransitionAllowed('CREATED', 'CANCELLED_BY_CUSTOMER')).toBe(true);
    expect(isTransitionAllowed('CREATED', 'DISPATCHED')).toBe(true);
  });

  it('rejects an illegal jump (CREATED → CLOSED)', () => {
    expect(isTransitionAllowed('CREATED', 'CLOSED')).toBe(false);
  });

  it('terminal states have no outgoing transitions', () => {
    for (const t of ['CLOSED', 'CANCELLED_BY_CUSTOMER', 'CANCELLED_BY_TECHNICIAN', 'DECLINED_BY_CUSTOMER'] as const) {
      expect(ALLOWED_TRANSITIONS[t]).toEqual([]);
    }
  });

  it('cancel edges only exist before ARRIVED', () => {
    expect(ALLOWED_TRANSITIONS['EN_ROUTE']).toContain('CANCELLED_BY_CUSTOMER');
    expect(ALLOWED_TRANSITIONS['ARRIVED']).not.toContain('CANCELLED_BY_CUSTOMER');
  });
});
```

- [ ] **Step 2: Run — confirm FAIL**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/bookings/booking-state-unit.test.ts
```
Expected: FAIL (module not found).

- [ ] **Step 3: Implement `bookings.state.ts`**

Create `apps/backend/src/modules/bookings/bookings.state.ts` (import ONLY `ConflictError` — B1 has no actor-permission map yet; B2 will add `ForbiddenError` when it does):
```ts
import type { Prisma, Booking, BookingState, ActorType } from '@prisma/client';
import { ConflictError } from '../../shared/errors.js';

export const ALLOWED_TRANSITIONS: Record<BookingState, BookingState[]> = {
  CREATED:            ['DISPATCHED', 'CANCELLED_BY_CUSTOMER'],
  DISPATCHED:         ['ACCEPTED', 'CANCELLED_BY_CUSTOMER', 'CANCELLED_BY_TECHNICIAN'],
  ACCEPTED:           ['EN_ROUTE', 'CANCELLED_BY_CUSTOMER', 'CANCELLED_BY_TECHNICIAN'],
  EN_ROUTE:           ['ARRIVED', 'CANCELLED_BY_CUSTOMER', 'CANCELLED_BY_TECHNICIAN'],
  ARRIVED:            ['DIAGNOSED'],
  DIAGNOSED:          ['CUSTOMER_APPROVED', 'DECLINED_BY_CUSTOMER'],
  CUSTOMER_APPROVED:  ['PARTS_REQUESTED', 'REPAIR_IN_PROGRESS'],
  PARTS_REQUESTED:    ['PARTS_ACQUIRED'],
  PARTS_ACQUIRED:     ['REPAIR_IN_PROGRESS'],
  REPAIR_IN_PROGRESS: ['REPAIR_COMPLETE'],
  REPAIR_COMPLETE:    ['CUSTOMER_CONFIRMED'],
  CUSTOMER_CONFIRMED: ['PAYMENT_RECEIVED', 'DISPUTED'],
  PAYMENT_RECEIVED:   ['CLOSED'],
  DISPUTED:           ['CLOSED'],
  CLOSED:                  [],
  CANCELLED_BY_CUSTOMER:   [],
  CANCELLED_BY_TECHNICIAN: [],
  DECLINED_BY_CUSTOMER:    [],
};

export function isTransitionAllowed(from: BookingState, to: BookingState): boolean {
  return ALLOWED_TRANSITIONS[from].includes(to);
}

/** Who is driving a transition. `id` is the User.id (or a system marker). */
export interface BookingActor { type: ActorType; id: string; }

/** Guarded transition: validates legality, writes state + BOOKING_STATE_CHANGED audit in the
 *  caller's transaction. Throws ConflictError (409) on illegal transition. Actor-permission
 *  checks are the caller's responsibility in B1 (only customer-cancel exists); later slices add
 *  a permission map here. */
export async function transitionBooking(
  tx: Prisma.TransactionClient,
  booking: Booking,
  to: BookingState,
  actor: BookingActor,
): Promise<Booking> {
  if (!isTransitionAllowed(booking.state, to)) {
    throw new ConflictError(`Cannot transition booking from ${booking.state} to ${to}`);
  }
  const updated = await tx.booking.update({ where: { id: booking.id }, data: { state: to } });
  await tx.auditLog.create({
    data: {
      action: 'BOOKING_STATE_CHANGED',
      actorType: actor.type,
      actorId: actor.id,
      metadata: { bookingId: booking.id, from: booking.state, to },
    },
  });
  return updated;
}
```

- [ ] **Step 4: Run — confirm PASS**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/bookings/booking-state-unit.test.ts
```
Expected: PASS (all 4).

- [ ] **Step 5: Build + commit**
```bash
cd apps/backend && pnpm build   # expect clean
git add apps/backend/src/modules/bookings/bookings.state.ts apps/backend/tests/bookings/booking-state-unit.test.ts
git commit -m "feat(backend): booking state machine — ALLOWED_TRANSITIONS + transitionBooking (booking B1)"
```

---

## Task 4: DTO + create schema

**Files:**
- Create: `apps/backend/src/modules/bookings/bookings.types.ts`
- Create: `apps/backend/src/modules/bookings/bookings.schemas.ts`

- [ ] **Step 1: Create `bookings.types.ts`**

The DTO carries the snapshot + state + nested display objects, never raw Prisma. The service will pass the booking row (the snapshot fields are denormalized on it) so the mapper stays pure.
```ts
import type { Booking } from '@prisma/client';

export interface BookingDto {
  id: string;
  bookingNumber: string;
  state: Booking['state'];
  scheduledSlot: string;          // ISO string
  visitFeePaise: number;
  laborPaise: number;
  laborTier: Booking['laborTier'];
  service: { id: string; name: string };
  zone: { id: string; name: string };
  address: { id: string };        // address detail comes from the address DTO elsewhere; B1 echoes the id
}

export function toBookingDto(b: Booking): BookingDto {
  return {
    id: b.id,
    bookingNumber: b.bookingNumber,
    state: b.state,
    scheduledSlot: b.scheduledSlot.toISOString(),
    visitFeePaise: b.visitFeePaise,
    laborPaise: b.laborPaise,
    laborTier: b.laborTier,
    service: { id: b.serviceId, name: b.serviceName },
    zone: { id: b.zoneId, name: b.zoneName },
    address: { id: b.addressId },
  };
}
```
(Snapshot `serviceName`/`zoneName` are read off the booking row — display-stable even if the live service/zone is later renamed. The address is echoed by id only in B1; a fuller address sub-object can be added when a booking-detail screen needs it.)

- [ ] **Step 2: Create `bookings.schemas.ts`**
```ts
import { z } from 'zod';

export const createBookingBody = z
  .object({
    addressId: z.string().min(1),
    serviceId: z.string().min(1),
    scheduledSlot: z.string().datetime(),  // ISO 8601; refined to future below
  })
  .strict()
  .refine((b) => new Date(b.scheduledSlot).getTime() > Date.now(), {
    message: 'scheduledSlot must be in the future',
    path: ['scheduledSlot'],
  });
export type CreateBookingBody = z.infer<typeof createBookingBody>;
```

- [ ] **Step 3: Type-check + commit**
```bash
cd apps/backend && pnpm build   # expect clean
git add apps/backend/src/modules/bookings/bookings.types.ts apps/backend/src/modules/bookings/bookings.schemas.ts
git commit -m "feat(backend): booking DTO + create schema (booking B1)"
```

---

## Task 5: creation service + the snapshot-immutability test

**Files:**
- Create: `apps/backend/src/modules/bookings/bookings.service.ts`
- Create: `apps/backend/tests/bookings/helpers.ts`
- Create: `apps/backend/tests/bookings/booking-create.test.ts`

- [ ] **Step 1: Create the test fixture helper `tests/bookings/helpers.ts`**
```ts
import { prisma } from '../schema/helpers.js';
import { signAccessToken } from '../../src/shared/auth/tokens.js';

let seq = 0;
function uniquePhone(): string { return '9' + String(300000000 + seq++); }

export async function makeCustomer(): Promise<{ token: string; userId: string; customerId: string }> {
  const user = await prisma.user.create({ data: { phone: uniquePhone(), role: 'CUSTOMER' } });
  const c = await prisma.customer.create({ data: { userId: user.id, name: 'Cust' } });
  return { token: signAccessToken(user.id, 'CUSTOMER'), userId: user.id, customerId: c.id };
}

export async function makeAdminToken(): Promise<string> {
  const user = await prisma.user.create({ data: { phone: uniquePhone(), role: 'ADMIN' } });
  await prisma.admin.create({ data: { userId: user.id, name: 'Adm', email: `adm-${user.id}@fixcare.in`, passwordHash: 'x', adminLevel: 'MANAGER' } });
  return signAccessToken(user.id, 'ADMIN');
}

/** Seed a serviceable happy-path: zone + visit fee, a service priced in that zone, a pincode→zone
 *  mapping, and an address (owned by customerId) in that pincode. Returns the ids + the price values. */
export async function seedBookable(customerId: string, opts?: { visitFeePaise?: number; laborPaise?: number }) {
  const visitFeePaise = opts?.visitFeePaise ?? 14900;
  const laborPaise = opts?.laborPaise ?? 60000;
  const zone = await prisma.zone.create({ data: { name: 'Vadodara', visitFeePaise } });
  const cat = await prisma.serviceCategory.create({ data: { name: 'AC' } });
  const service = await prisma.service.create({ data: { categoryId: cat.id, name: 'AC gas refill', tier: 'T2' } });
  await prisma.servicePrice.create({ data: { serviceId: service.id, zoneId: zone.id, laborPaise } });
  await prisma.pincodeZone.create({ data: { pincode: '390001', zoneId: zone.id } });
  const address = await prisma.address.create({
    data: { customerId, label: 'Home', line1: '12 MG Road', pincode: '390001', zoneId: zone.id, isDefault: true },
  });
  return { zone, cat, service, address, visitFeePaise, laborPaise };
}
```

- [ ] **Step 2: Write the failing creation + snapshot tests**

Create `apps/backend/tests/bookings/booking-create.test.ts`:
```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, makeAdminToken, seedBookable } from './helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
function future() { return new Date(Date.now() + 86_400_000).toISOString(); }

describe('POST /me/bookings', () => {
  it('creates a booking with the full price snapshot + CREATED state + audit', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const res = await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token),
      payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } });
    expect(res.statusCode).toBe(201);
    expect(res.json()).toMatchObject({
      state: 'CREATED', visitFeePaise: 14900, laborPaise: 60000, laborTier: 'T2',
      service: { name: 'AC gas refill' }, zone: { name: 'Vadodara' },
    });
    expect(res.json().bookingNumber).toMatch(/^FC-/);
    const audit = await prisma.auditLog.findFirst({ where: { action: 'BOOKING_STATE_CHANGED' } });
    expect(audit).toBeTruthy();
    expect(audit!.metadata).toMatchObject({ to: 'CREATED' });
  });

  it('SNAPSHOT IS IMMUTABLE: changing catalog price + pincode→zone after creation does not change the booking', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const created = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token),
      payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
    // mutate the live catalog + coverage
    await prisma.servicePrice.updateMany({ where: { serviceId: f.service.id, zoneId: f.zone.id }, data: { laborPaise: 999999 } });
    await prisma.zone.update({ where: { id: f.zone.id }, data: { visitFeePaise: 888888 } });
    await prisma.pincodeZone.updateMany({ where: { pincode: '390001' }, data: { deletedAt: new Date() } });
    const got = (await app.inject({ method: 'GET', url: `/me/bookings/${created.id}`, headers: auth(c.token) })).json();
    expect(got.visitFeePaise).toBe(14900);  // unchanged
    expect(got.laborPaise).toBe(60000);     // unchanged
    expect(got.zone.name).toBe('Vadodara'); // unchanged
  });

  it('unserviceable address (no pincode mapping) → 422', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    await prisma.pincodeZone.deleteMany({ where: { pincode: '390001' } });
    const res = await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token),
      payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } });
    expect(res.statusCode).toBe(422);
  });

  it('serviceable but service unpriced in that zone → 422', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    await prisma.servicePrice.deleteMany({ where: { serviceId: f.service.id, zoneId: f.zone.id } });
    const res = await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token),
      payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } });
    expect(res.statusCode).toBe(422);
  });

  it("another customer's addressId → 404 (no IDOR)", async () => {
    const a = await makeCustomer();
    const f = await seedBookable(a.customerId);
    const b = await makeCustomer();
    const res = await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(b.token),
      payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } });
    expect(res.statusCode).toBe(404);
  });

  it('unknown/soft-deleted service → 404', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    await prisma.service.update({ where: { id: f.service.id }, data: { deletedAt: new Date() } });
    const res = await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token),
      payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } });
    expect(res.statusCode).toBe(404);
  });

  it('past scheduledSlot → 400; non-CUSTOMER → 403; no token → 401', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const pastBody = { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: new Date(Date.now() - 1000).toISOString() };
    expect((await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: pastBody })).statusCode).toBe(400);
    const adm = await makeAdminToken();
    expect((await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(adm),
      payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).statusCode).toBe(403);
    expect((await app.inject({ method: 'POST', url: '/me/bookings',
      payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).statusCode).toBe(401);
  });
});
```

- [ ] **Step 3: Run — confirm FAIL**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/bookings/booking-create.test.ts
```
Expected: FAIL (route/service not present).

- [ ] **Step 4: Implement `bookings.service.ts` (create + the reads/cancel used by tests)**

Create `apps/backend/src/modules/bookings/bookings.service.ts`:
```ts
import { Prisma } from '@prisma/client';
import { prisma } from '../../shared/database/prisma.js';
import { ForbiddenError, NotFoundError, ValidationError } from '../../shared/errors.js';
import { resolvePincode } from '../addresses/serviceability.service.js';
import { generateBookingNumber } from './bookings.number.js';
import { transitionBooking } from './bookings.state.js';
import { toBookingDto, type BookingDto } from './bookings.types.js';
import type { CreateBookingBody } from './bookings.schemas.js';

async function requireCustomer(userId: string): Promise<{ id: string }> {
  const c = await prisma.customer.findFirst({ where: { userId, deletedAt: null } });
  if (!c) throw new ForbiddenError('Only customers can book');
  return { id: c.id };
}

async function ownBookingOrThrow(customerId: string, id: string) {
  const b = await prisma.booking.findFirst({ where: { id, customerId, deletedAt: null } });
  if (!b) throw new NotFoundError('Booking not found');
  return b;
}

export async function createBooking(userId: string, body: CreateBookingBody): Promise<BookingDto> {
  const { id: customerId } = await requireCustomer(userId);

  const address = await prisma.address.findFirst({ where: { id: body.addressId, customerId, deletedAt: null } });
  if (!address) throw new NotFoundError('Address not found');

  const service = await prisma.service.findFirst({ where: { id: body.serviceId, deletedAt: null, status: 'ACTIVE' } });
  if (!service) throw new NotFoundError('Service not found');

  // resolve zone live (authoritative at booking time)
  const svc = await resolvePincode(address.pincode);
  if (!svc.serviceable || !svc.zone) throw new ValidationError('We don\'t serve this area yet'); // 422 (see note)
  const zone = svc.zone;

  const price = await prisma.servicePrice.findUnique({
    where: { serviceId_zoneId: { serviceId: service.id, zoneId: zone.id } },
  });
  if (!price) throw new ValidationError('This service is unavailable in your area'); // 422

  for (let attempt = 0; attempt < 5; attempt++) {
    try {
      const row = await prisma.$transaction(async (tx) => {
        const created = await tx.booking.create({
          data: {
            bookingNumber: generateBookingNumber(),
            customerId,
            addressId: address.id,
            serviceId: service.id,
            zoneId: zone.id,
            zoneName: zone.name,
            serviceName: service.name,
            visitFeePaise: zone.visitFeePaise,
            laborPaise: price.laborPaise,
            laborTier: service.tier,
            scheduledSlot: new Date(body.scheduledSlot),
          },
        });
        await tx.auditLog.create({
          data: { action: 'BOOKING_STATE_CHANGED', actorType: 'USER', actorId: userId,
                   metadata: { bookingId: created.id, from: null, to: 'CREATED' } },
        });
        return created;
      });
      return toBookingDto(row);
    } catch (e) {
      if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === 'P2002') continue; // bookingNumber collision → retry
      throw e;
    }
  }
  throw new Error('Could not generate a unique booking number');
}

export async function listBookings(userId: string): Promise<BookingDto[]> {
  const { id: customerId } = await requireCustomer(userId);
  const rows = await prisma.booking.findMany({ where: { customerId, deletedAt: null }, orderBy: { createdAt: 'desc' } });
  return rows.map(toBookingDto);
}

export async function getBooking(userId: string, id: string): Promise<BookingDto> {
  const { id: customerId } = await requireCustomer(userId);
  const b = await ownBookingOrThrow(customerId, id);
  return toBookingDto(b);
}

export async function cancelBooking(userId: string, id: string): Promise<BookingDto> {
  const { id: customerId } = await requireCustomer(userId);
  const booking = await ownBookingOrThrow(customerId, id);
  const updated = await prisma.$transaction((tx) =>
    transitionBooking(tx, booking, 'CANCELLED_BY_CUSTOMER', { type: 'USER', id: userId }),
  );
  return toBookingDto(updated);
}
```
**422 note:** the global error handler maps error classes to status codes. If `ValidationError` maps to 400 (it does — it's the Zod/boundary error), the two "unserviceable/unpriced" throws would be 400, not 422. To return **422**, add a dedicated error class. See Step 5.

- [ ] **Step 5: Add an `UnprocessableError` (422) class if one doesn't exist**

Check `apps/backend/src/shared/errors.ts`. If there is no 422 class, add:
```ts
export class UnprocessableError extends AppError {
  constructor(message: string) { super(422, message); }
}
```
(Match the existing `AppError` constructor signature — read the file; other classes call `super(statusCode, message)`.) Then in `bookings.service.ts` import `UnprocessableError` instead of `ValidationError` for the two serviceability throws:
```ts
import { ForbiddenError, NotFoundError, UnprocessableError } from '../../shared/errors.js';
...
if (!svc.serviceable || !svc.zone) throw new UnprocessableError("We don't serve this area yet");
...
if (!price) throw new UnprocessableError('This service is unavailable in your area');
```
Confirm the global error handler returns `err.statusCode` for any `AppError` subclass (it does — that's how 409/404 already work), so 422 flows through automatically.

- [ ] **Step 6: Create the routes `bookings.routes.ts`**
```ts
import type { FastifyInstance } from 'fastify';
import { requireAuth } from '../../shared/middleware/auth.js';
import { ValidationError, ForbiddenError } from '../../shared/errors.js';
import { createBookingBody } from './bookings.schemas.js';
import { createBooking, listBookings, getBooking, cancelBooking } from './bookings.service.js';

function requireCustomerRole(req: { user?: { role: string } }): void {
  if (req.user?.role !== 'CUSTOMER') throw new ForbiddenError('Only customers can book');
}

export async function registerBookingRoutes(app: FastifyInstance) {
  app.post('/me/bookings', { preHandler: [requireAuth] }, async (req, reply) => {
    requireCustomerRole(req);
    const p = createBookingBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.code(201).send(await createBooking(req.user!.id, p.data));
  });

  app.get('/me/bookings', { preHandler: [requireAuth] }, async (req, reply) => {
    requireCustomerRole(req);
    return reply.send(await listBookings(req.user!.id));
  });

  app.get('/me/bookings/:id', { preHandler: [requireAuth] }, async (req, reply) => {
    requireCustomerRole(req);
    return reply.send(await getBooking(req.user!.id, (req.params as { id: string }).id));
  });

  app.post('/me/bookings/:id/cancel', { preHandler: [requireAuth] }, async (req, reply) => {
    requireCustomerRole(req);
    return reply.send(await cancelBooking(req.user!.id, (req.params as { id: string }).id));
  });
}
```

- [ ] **Step 7: Register in `app.ts`**

Add the import next to the others and the call after `registerAddressesRoutes`:
```ts
import { registerBookingRoutes } from './modules/bookings/bookings.routes.js';
```
```ts
  await registerAddressesRoutes(app);
  await registerBookingRoutes(app);
```

- [ ] **Step 8: Run — confirm PASS**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/bookings/booking-create.test.ts
```
Expected: PASS (incl. the snapshot-immutability test and all guard/IDOR/422 cases).

- [ ] **Step 9: Build + commit**
```bash
cd apps/backend && pnpm build   # expect clean
git add apps/backend/src/modules/bookings/bookings.service.ts apps/backend/src/modules/bookings/bookings.routes.ts apps/backend/src/app.ts apps/backend/src/shared/errors.ts apps/backend/tests/bookings/helpers.ts apps/backend/tests/bookings/booking-create.test.ts
git commit -m "feat(backend): booking creation + price snapshot + /me/bookings routes (booking B1)"
```

---

## Task 6: list / get / cancel + ownership + transition guards

**Files:**
- Create: `apps/backend/tests/bookings/booking-state.test.ts`
- (service + routes for these already landed in Task 5 — this task is the dedicated test coverage)

- [ ] **Step 1: Write the tests**

Create `apps/backend/tests/bookings/booking-state.test.ts`:
```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, seedBookable } from './helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
function future() { return new Date(Date.now() + 86_400_000).toISOString(); }

async function createBooking(token: string, addressId: string, serviceId: string) {
  return (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(token),
    payload: { addressId, serviceId, scheduledSlot: future() } })).json();
}

describe('GET/list + cancel /me/bookings', () => {
  it('list returns only the caller\'s own bookings (newest first)', async () => {
    const a = await makeCustomer();
    const f = await seedBookable(a.customerId);
    await createBooking(a.token, f.address.id, f.service.id);
    const b = await makeCustomer();
    const fb = await seedBookable(b.customerId);
    await createBooking(b.token, fb.address.id, fb.service.id);
    const listA = await app.inject({ method: 'GET', url: '/me/bookings', headers: auth(a.token) });
    expect(listA.statusCode).toBe(200);
    expect(listA.json()).toHaveLength(1);
  });

  it('GET :id of another customer\'s booking → 404 (no IDOR); unknown id → 404', async () => {
    const a = await makeCustomer();
    const f = await seedBookable(a.customerId);
    const booking = await createBooking(a.token, f.address.id, f.service.id);
    const b = await makeCustomer();
    expect((await app.inject({ method: 'GET', url: `/me/bookings/${booking.id}`, headers: auth(b.token) })).statusCode).toBe(404);
    expect((await app.inject({ method: 'GET', url: '/me/bookings/00000000-0000-0000-0000-000000000000', headers: auth(a.token) })).statusCode).toBe(404);
  });

  it('cancel from CREATED → CANCELLED_BY_CUSTOMER + audit', async () => {
    const a = await makeCustomer();
    const f = await seedBookable(a.customerId);
    const booking = await createBooking(a.token, f.address.id, f.service.id);
    const res = await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/cancel`, headers: auth(a.token) });
    expect(res.statusCode).toBe(200);
    expect(res.json().state).toBe('CANCELLED_BY_CUSTOMER');
    const audits = await prisma.auditLog.findMany({ where: { action: 'BOOKING_STATE_CHANGED', metadata: { path: ['bookingId'], equals: booking.id } } });
    expect(audits.length).toBe(2); // create (→CREATED) + cancel (→CANCELLED_BY_CUSTOMER)
  });

  it('cancel a non-CREATED booking → 409 (illegal transition)', async () => {
    const a = await makeCustomer();
    const f = await seedBookable(a.customerId);
    const booking = await createBooking(a.token, f.address.id, f.service.id);
    await prisma.booking.update({ where: { id: booking.id }, data: { state: 'ARRIVED' } }); // force a non-cancelable state
    const res = await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/cancel`, headers: auth(a.token) });
    expect(res.statusCode).toBe(409);
  });

  it('cancel another customer\'s booking → 404', async () => {
    const a = await makeCustomer();
    const f = await seedBookable(a.customerId);
    const booking = await createBooking(a.token, f.address.id, f.service.id);
    const b = await makeCustomer();
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/cancel`, headers: auth(b.token) })).statusCode).toBe(404);
  });
});
```

- [ ] **Step 2: Run — confirm PASS**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/bookings/booking-state.test.ts
```
Expected: PASS (all). If `cancel a non-CREATED → 409` fails because the global handler maps `ConflictError` to a different code, confirm `ConflictError` → 409 (it does — catalog dup tests rely on it).

- [ ] **Step 3: Full bookings suite + build**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/bookings
cd apps/backend && pnpm build
```
Expected: all bookings tests green; build clean.

- [ ] **Step 4: Commit**
```bash
git add apps/backend/tests/bookings/booking-state.test.ts
git commit -m "test(backend): booking list/get/cancel + ownership + transition guards (booking B1)"
```

---

## Task 7: full suite + reviews + status/changelog

**Files:**
- Modify: `STATUS.md`, `CHANGELOG.md`

- [ ] **Step 1: Full backend suite**
```bash
set -a && . ./.env && set +a && cd apps/backend && pnpm test
```
Expected: ALL green (the prior 146 + the new booking tests). Note the total.

- [ ] **Step 2: Run the FixCare review agents (read-only, before merge)**

- `prisma-migration-reviewer` — the `booking` migration (additive; FKs to Customer/Address/Service; unique bookingNumber; indexes; `ALTER TYPE AuditAction ADD VALUE` additive; integer-paise snapshot fields).
- `golden-rules-auditor` — money-is-paise on the snapshot; `BOOKING_STATE_CHANGED` audit in-transaction on create AND cancel; ownership (404-not-403); CUSTOMER-only; no PII in audit metadata (bookingId/from/to only); DTO not raw Prisma.
- `fraud-vector-checker` — **the snapshot IS a documented fraud defense**: verify the snapshot-immutability test actually proves catalog/coverage edits can't change a created booking; confirm no customer-controlled price/zone input (zone resolved server-side from the address pincode).

Address blocking findings (re-run the relevant test after each fix). Then run `/code-review` on the branch (twice if the first pass finds fixes, per prior slices).

- [ ] **Step 3: Update `STATUS.md`**
Phase: booking module underway — B1 (creation + snapshot + state skeleton) done on branch. Active task → B1 summary. Last shipped bullet (Booking model + snapshot + state machine + create/cancel; test count; review result; the snapshot-immutability proof). Next 3 → B2 dispatch. `_Last updated_` 2026-06-07.

- [ ] **Step 4: `CHANGELOG.md` entry**
Under `## 2026-06-07 — Booking B1 (creation + price snapshot + state skeleton)`: Booking model + full BookingState enum + BOOKING_STATE_CHANGED; `POST/GET/GET:id/cancel /me/bookings` (CUSTOMER-only, owner-scoped 404-not-403); price snapshot (zone+visitFee+labor+tier) locked at creation — **catalog/coverage edits don't change an existing booking** (the fraud defense, tested); central ALLOWED_TRANSITIONS + guarded transitionBooking (B1 wires create+cancel; full graph declared); unserviceable/unpriced→422; bookingNumber FC-; UnprocessableError(422) added; test count; review notes. Note the 7-slice decomposition (B2-B7 deferred).

- [ ] **Step 5: Commit docs**
```bash
git add STATUS.md CHANGELOG.md
git commit -m "docs: status + changelog for booking B1"
```

- [ ] **Step 6: Finish the branch**
Use `superpowers:finishing-a-development-branch` → PR `feature/booking-module` → `main`, `/code-review`. (Pushing/PR is the user's step in this environment.) Note B2 (dispatch) continues the booking module in a new branch off `main` after merge.

---

## Self-Review notes

- **Spec coverage:** Booking model + full enum + BOOKING_STATE_CHANGED ✓ (T1); bookingNumber ✓ (T2); ALLOWED_TRANSITIONS + transitionBooking (audit-in-tx) ✓ (T3); DTO + create schema (future-slot) ✓ (T4); creation flow with live zone resolve + ServicePrice lookup + snapshot + 422/404/403/401/400 + the snapshot-immutability test ✓ (T5); list/get/cancel + ownership + 409 illegal transition ✓ (T6). Decisions 1-8 all covered. Deferred B2-B7 explicitly out of scope.
- **Placeholder scan:** none — every step has concrete code/commands. (Task 5 Step 5 conditionally adds `UnprocessableError` only if a 422 class doesn't already exist — a concrete instruction, not a placeholder.)
- **Type consistency:** `BookingActor { type: ActorType; id }`, `transitionBooking(tx, booking, to, actor)`, `ALLOWED_TRANSITIONS`/`isTransitionAllowed`, `createBooking/listBookings/getBooking/cancelBooking`, `BookingDto`/`toBookingDto`, `createBookingBody`, `generateBookingNumber` consistent across tasks. `prisma.booking` accessor. `resolvePincode` reused from addresses (returns `{serviceable, zone:{id,name,visitFeePaise}|null, message?}`) — matches the snapshot fields read. `serviceId_zoneId` is the existing ServicePrice composite-unique key (confirmed from catalog).
- **422 routing:** flagged in T5 S5 — `UnprocessableError` must extend `AppError` so the global handler returns 422; verify the handler returns `err.statusCode` for AppError subclasses (it does).
- **Audit on create:** written directly in `createBooking` (`from:null→CREATED`), not via `transitionBooking` (which is for state→state). Cancel uses `transitionBooking`. Both write `BOOKING_STATE_CHANGED` in-transaction — consistent metadata shape `{ bookingId, from, to }`.
