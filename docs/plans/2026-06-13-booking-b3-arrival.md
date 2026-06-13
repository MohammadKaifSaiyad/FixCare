# Booking B3 — Arrival Handshake (Keystone #1) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the two-sided, evidence-gated arrival handshake — technician taps "on my way" → taps Arrived (GPS-validated, mints a single-use code) → customer enters the code → `ARRIVED` with the visit-fee milestone locked. Neither party alone can reach `ARRIVED`.

**Architecture:** Extends `bookings.state.ts` (two new `ALLOWED_ACTORS` entries; the wired `EN_ROUTE`/`ARRIVED` transitions), the `technician-jobs` module (en-route + arrive endpoints, reusing `requireTechnician` + the assigned-technician check), and the `bookings` module (customer `confirm-arrival`, reusing `requireCustomer` + owner-scope). The arrival code is held hashed + single-use in Redis (the auth OTP idiom). 4 nullable evidence columns on `Booking`. No money moves — `visitFeeLockedAt` is the milestone the payment slice (B6) will require.

**Tech Stack:** Node 22, Fastify 5, Prisma 6 + PostgreSQL 16, Redis 7 (ioredis), Zod, Vitest (`app.inject()`), TypeScript strict. Branch: `feature/booking-arrival` (already cut off `main`).

**Design reference:** `docs/designs/2026-06-13-booking-b3-arrival-design.md` (decisions 1-6; the two-step mechanics; the GPS gate; the audit-without-coords; deferred scope).

**Conventions:** Zod at the boundary (`.strict()`); route→service→DTO; auth-first; **role-gate in `transitionBooking` (default-deny) + identity/ownership in the service**; every transition audited in-tx (Golden Rule 5); **no PII / no raw GPS coords in audit or logs** (Golden Rule 7); two-sided + evidence-gated (Golden Rules 1-2). Reuse `generateOtp`/`hashOtp` (`src/shared/auth/otp.ts`) + the Redis `{hash, attempts}` single-use pattern (`auth.service.ts`).

**Commit-authorship (every commit):** author `MohammadKaifSaiyad <saiyedkgn6@gmail.com>`, **no** Claude/`Co-Authored-By` trailer. Run `pnpm` from `apps/backend`; prefix test commands with `set -a && . ./.env && set +a &&`. After any `migrate dev`, apply to the test DB with `DATABASE_URL="$TEST_DATABASE_URL" pnpm prisma migrate deploy`. If migrate can't reach the DB / reports drift → report BLOCKED (no `db push`, no `_prisma_migrations` hand-patch).

---

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `apps/backend/prisma/schema.prisma` | 4 nullable `Booking` evidence columns | Modify |
| `apps/backend/prisma/migrations/<ts>_arrival_evidence/` | Generated migration | Create |
| `apps/backend/src/shared/utils/geo.ts` | `haversineMeters` | Create |
| `apps/backend/src/modules/bookings/arrival-code.ts` | mint/verify the Redis arrival code (reuses otp helpers) | Create |
| `apps/backend/src/modules/bookings/bookings.state.ts` | `ALLOWED_ACTORS` += EN_ROUTE/ARRIVED | Modify |
| `apps/backend/src/modules/technician-jobs/technician-jobs.service.ts` | `enRouteJob`, `arriveJob` | Modify |
| `apps/backend/src/modules/technician-jobs/technician-jobs.routes.ts` | `POST /technician/jobs/:id/en-route`, `/arrive` | Modify |
| `apps/backend/src/modules/technician-jobs/technician-jobs.schemas.ts` | `arriveBody` (lat/lng) | Create |
| `apps/backend/src/modules/bookings/bookings.service.ts` | `confirmArrival` | Modify |
| `apps/backend/src/modules/bookings/bookings.routes.ts` | `POST /me/bookings/:id/confirm-arrival` | Modify |
| `apps/backend/src/modules/bookings/bookings.schemas.ts` | `confirmArrivalBody` (code) | Modify |
| `apps/backend/tests/shared/geo.test.ts` | haversine unit | Create |
| `apps/backend/tests/bookings/booking-actor-unit.test.ts` | EN_ROUTE/ARRIVED actor entries | Modify |
| `apps/backend/tests/technician-jobs/arrival.test.ts` | the full keystone handshake + GPS + identity tests | Create |

All paths relative to repo root `/Users/mohammadkaifsaiyad/Development/FixCare`.

---

## Task 1: schema — arrival evidence columns + migration

**Files:**
- Modify: `apps/backend/prisma/schema.prisma`
- Create: `apps/backend/prisma/migrations/<ts>_arrival_evidence/migration.sql` (generated)

- [ ] **Step 1: Add 4 nullable columns to `Booking`**

In `schema.prisma`, in the `Booking` model (near the other booking fields, before the `@@index` lines), add:
```prisma
  arrivalLat       Float?
  arrivalLng       Float?
  arrivedAt        DateTime?
  visitFeeLockedAt DateTime?
```

- [ ] **Step 2: Generate + apply the migration (dev), then deploy to test**
```bash
set -a && . ./.env && set +a && pnpm prisma migrate dev --name arrival_evidence
DATABASE_URL="$TEST_DATABASE_URL" pnpm prisma migrate deploy
```
Expected: a new `prisma/migrations/<ts>_arrival_evidence/migration.sql` with 4 `ADD COLUMN` (all nullable), applied to dev + test; client regenerates.

- [ ] **Step 3: Verify additive-only**
```bash
grep -iE 'DROP|TRUNCATE|ALTER COLUMN' apps/backend/prisma/migrations/*_arrival_evidence/migration.sql || echo "clean: additive only"
```
Expected: `clean: additive only` (4 nullable ADD COLUMNs; no NOT NULL, no backfill needed).

- [ ] **Step 4: Commit**
```bash
git add apps/backend/prisma/schema.prisma apps/backend/prisma/migrations
git commit -m "feat(backend): add Booking arrival-evidence columns + migration (booking B3)"
```

---

## Task 2: `haversineMeters` geo helper

**Files:**
- Create: `apps/backend/src/shared/utils/geo.ts`
- Create: `apps/backend/tests/shared/geo.test.ts`

- [ ] **Step 1: Write the failing test**

Create `apps/backend/tests/shared/geo.test.ts`:
```ts
import { describe, expect, it } from 'vitest';
import { haversineMeters } from '../../src/shared/utils/geo.js';

describe('haversineMeters', () => {
  it('is 0 for the same point', () => {
    expect(haversineMeters(22.3072, 73.1812, 22.3072, 73.1812)).toBe(0);
  });
  it('approximates a known short distance (~157m) within 5%', () => {
    // ~0.001 deg latitude ≈ 111m; use two nearby Vadodara points
    const d = haversineMeters(22.3072, 73.1812, 22.3086, 73.1812); // ~0.0014 deg lat
    expect(d).toBeGreaterThan(140);
    expect(d).toBeLessThan(175);
  });
  it('grows with distance (1 deg lat ≈ 111km)', () => {
    const d = haversineMeters(22.0, 73.0, 23.0, 73.0);
    expect(d).toBeGreaterThan(110_000);
    expect(d).toBeLessThan(112_000);
  });
});
```

- [ ] **Step 2: Run — confirm FAIL**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/shared/geo.test.ts
```

- [ ] **Step 3: Implement `src/shared/utils/geo.ts`**
```ts
/** Great-circle distance between two lat/lng points, in metres. */
export function haversineMeters(aLat: number, aLng: number, bLat: number, bLng: number): number {
  const R = 6_371_000; // Earth radius (m)
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(bLat - aLat);
  const dLng = toRad(bLng - aLng);
  const lat1 = toRad(aLat);
  const lat2 = toRad(bLat);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}
```

- [ ] **Step 4: Run — PASS; commit**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/shared/geo.test.ts
git add apps/backend/src/shared/utils/geo.ts apps/backend/tests/shared/geo.test.ts
git commit -m "feat(backend): haversineMeters geo helper (booking B3)"
```

---

## Task 3: arrival-code Redis helper

**Files:**
- Create: `apps/backend/src/modules/bookings/arrival-code.ts`
- Create: `apps/backend/tests/bookings/arrival-code.test.ts`

- [ ] **Step 1: Write the failing test**

Create `apps/backend/tests/bookings/arrival-code.test.ts`:
```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { mintArrivalCode, verifyArrivalCode } from '../../src/modules/bookings/arrival-code.js';
import { redis } from '../../src/shared/redis/client.js';
import { flushTestRedis } from '../helpers/redis.js';

afterAll(() => redis.quit());
beforeEach(flushTestRedis);

describe('arrival code', () => {
  it('mints a 6-digit code; verify succeeds once then the code is consumed', async () => {
    const code = await mintArrivalCode('booking-1');
    expect(code).toMatch(/^\d{6}$/);
    expect(await verifyArrivalCode('booking-1', code)).toBe('ok');
    // single-use: the second verify finds no code
    expect(await verifyArrivalCode('booking-1', code)).toBe('no-code');
  });

  it('wrong code → invalid; after 5 wrong attempts the code is invalidated', async () => {
    const code = await mintArrivalCode('booking-2');
    for (let i = 0; i < 5; i++) expect(await verifyArrivalCode('booking-2', '000000')).toBe('invalid');
    // 6th attempt: attempts cap reached → treated as no-code (key deleted)
    expect(await verifyArrivalCode('booking-2', code)).toBe('no-code');
  });

  it('verify before any mint → no-code', async () => {
    expect(await verifyArrivalCode('booking-3', '123456')).toBe('no-code');
  });
});
```
(Assumes `tests/helpers/redis.ts` `flushTestRedis` exists — it does, used by other suites.)

- [ ] **Step 2: Run — confirm FAIL**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/bookings/arrival-code.test.ts
```

- [ ] **Step 3: Implement `src/modules/bookings/arrival-code.ts`**
```ts
import { redis } from '../../shared/redis/client.js';
import { generateOtp, hashOtp } from '../../shared/auth/otp.js';

const TTL_SECONDS = 600;       // 10 minutes
const MAX_ATTEMPTS = 5;
const key = (bookingId: string) => `arrival:${bookingId}`;

/** Mint a single-use 6-digit arrival code for a booking; store only its hash in Redis. Returns the
 *  raw code (shown to the technician once). A re-mint overwrites any existing code. */
export async function mintArrivalCode(bookingId: string): Promise<string> {
  const code = generateOtp();
  await redis.set(key(bookingId), JSON.stringify({ hash: hashOtp(code), attempts: 0 }), 'EX', TTL_SECONDS);
  return code;
}

export type ArrivalVerifyResult = 'ok' | 'invalid' | 'no-code';

/** Verify a code for a booking. 'no-code' = nothing minted / expired / attempts exhausted;
 *  'invalid' = wrong code (attempt counted); 'ok' = correct (code consumed). */
export async function verifyArrivalCode(bookingId: string, code: string): Promise<ArrivalVerifyResult> {
  const raw = await redis.get(key(bookingId));
  if (!raw) return 'no-code';
  const state = JSON.parse(raw) as { hash: string; attempts: number };
  if (state.attempts >= MAX_ATTEMPTS) {
    await redis.del(key(bookingId));
    return 'no-code';
  }
  if (hashOtp(code) !== state.hash) {
    await redis.set(key(bookingId), JSON.stringify({ ...state, attempts: state.attempts + 1 }), 'KEEPTTL');
    return 'invalid';
  }
  await redis.del(key(bookingId)); // single-use
  return 'ok';
}
```

- [ ] **Step 4: Run — PASS; commit**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/bookings/arrival-code.test.ts
git add apps/backend/src/modules/bookings/arrival-code.ts apps/backend/tests/bookings/arrival-code.test.ts
git commit -m "feat(backend): single-use arrival code (Redis, hashed) (booking B3)"
```

---

## Task 4: state machine — EN_ROUTE/ARRIVED actor entries

**Files:**
- Modify: `apps/backend/src/modules/bookings/bookings.state.ts`
- Modify: `apps/backend/tests/bookings/booking-actor-unit.test.ts`

- [ ] **Step 1: Add the failing actor assertions**

In `apps/backend/tests/bookings/booking-actor-unit.test.ts`, add:
```ts
  it('EN_ROUTE is technician-only; ARRIVED is customer-only (the arrival handshake)', () => {
    expect(actorAllowedFor('EN_ROUTE', 'TECHNICIAN')).toBe(true);
    expect(actorAllowedFor('EN_ROUTE', 'CUSTOMER')).toBe(false);
    expect(actorAllowedFor('ARRIVED', 'CUSTOMER')).toBe(true);
    expect(actorAllowedFor('ARRIVED', 'TECHNICIAN')).toBe(false);
  });
```
(The existing default-deny test asserted `actorAllowedFor('ARRIVED','TECHNICIAN')` is false among the unmapped set — once ARRIVED is mapped, that specific case stays false but for a new reason. If that existing test lists ARRIVED as an example unmapped state, update it to use a still-unmapped state like `DIAGNOSED` instead.)

- [ ] **Step 2: Run — confirm the new test FAILS** (EN_ROUTE/ARRIVED currently default-deny → `actorAllowedFor('EN_ROUTE','TECHNICIAN')` is false)
```bash
set -a && . ./.env && set +a && pnpm test -- tests/bookings/booking-actor-unit.test.ts
```

- [ ] **Step 3: Add the entries to `ALLOWED_ACTORS`**

In `apps/backend/src/modules/bookings/bookings.state.ts`, `ALLOWED_ACTORS` currently maps DISPATCHED/ACCEPTED/CANCELLED_BY_CUSTOMER. Add:
```ts
  EN_ROUTE:              ['TECHNICIAN'],
  ARRIVED:               ['CUSTOMER'],
```

- [ ] **Step 4: Run — PASS** (fix the existing default-deny example state if needed per Step 1); commit
```bash
set -a && . ./.env && set +a && pnpm test -- tests/bookings/booking-actor-unit.test.ts
git add apps/backend/src/modules/bookings/bookings.state.ts apps/backend/tests/bookings/booking-actor-unit.test.ts
git commit -m "feat(backend): ALLOWED_ACTORS — EN_ROUTE technician, ARRIVED customer (booking B3)"
```

---

## Task 5: technician en-route + arrive (GPS gate + mint code)

**Files:**
- Create: `apps/backend/src/modules/technician-jobs/technician-jobs.schemas.ts`
- Modify: `apps/backend/src/modules/technician-jobs/technician-jobs.service.ts`
- Modify: `apps/backend/src/modules/technician-jobs/technician-jobs.routes.ts`
- Create: `apps/backend/tests/technician-jobs/arrival.test.ts`

- [ ] **Step 1: Write the failing tests (en-route + arrive portions)**

Create `apps/backend/tests/technician-jobs/arrival.test.ts`:
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

/** Drive a fresh booking to ACCEPTED by the given technician; return its id. */
async function bookedAndAccepted(cust: { token: string; customerId: string }, tech: { token: string }, addrServ: { addressId: string; serviceId: string }) {
  const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(cust.token),
    payload: { addressId: addrServ.addressId, serviceId: addrServ.serviceId, scheduledSlot: future() } })).json();
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(tech.token) });
  return booking.id as string;
}

describe('arrival handshake — en-route + arrive', () => {
  it('technician goes en-route (ACCEPTED→EN_ROUTE) then arrives (GPS recorded, code minted, state unchanged)', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId); // address has no lat/lng by default
    const t = await makeTechnician(['AC']);
    const id = await bookedAndAccepted(c, t, { addressId: f.address.id, serviceId: f.service.id });

    const er = await app.inject({ method: 'POST', url: `/technician/jobs/${id}/en-route`, headers: auth(t.token) });
    expect(er.statusCode).toBe(200);
    expect(er.json().state).toBe('EN_ROUTE');

    const arr = await app.inject({ method: 'POST', url: `/technician/jobs/${id}/arrive`, headers: auth(t.token), payload: { lat: 22.31, lng: 73.18 } });
    expect(arr.statusCode).toBe(200);
    expect(arr.json().arrivalCode).toMatch(/^\d{6}$/);
    expect(arr.json().withinGeofence).toBeNull(); // address has no coords
    const row = await prisma.booking.findUnique({ where: { id } });
    expect(row!.state).toBe('EN_ROUTE'); // arrive does NOT change state
    expect(row!.arrivalLat).toBe(22.31);
  });

  it('GPS gate: with address coords, a tap >200m → 422; within → ok withinGeofence:true', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    await prisma.address.update({ where: { id: f.address.id }, data: { lat: 22.3072, lng: 73.1812 } });
    const t = await makeTechnician(['AC']);
    const id = await bookedAndAccepted(c, t, { addressId: f.address.id, serviceId: f.service.id });
    await app.inject({ method: 'POST', url: `/technician/jobs/${id}/en-route`, headers: auth(t.token) });

    const far = await app.inject({ method: 'POST', url: `/technician/jobs/${id}/arrive`, headers: auth(t.token), payload: { lat: 22.40, lng: 73.30 } });
    expect(far.statusCode).toBe(422);
    const near = await app.inject({ method: 'POST', url: `/technician/jobs/${id}/arrive`, headers: auth(t.token), payload: { lat: 22.3074, lng: 73.1813 } });
    expect(near.statusCode).toBe(200);
    expect(near.json().withinGeofence).toBe(true);
  });

  it('en-route from non-ACCEPTED → 409; arrive from non-EN_ROUTE → 409', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const t = await makeTechnician(['AC']);
    const id = await bookedAndAccepted(c, t, { addressId: f.address.id, serviceId: f.service.id });
    // arrive before en-route (still ACCEPTED) → 409
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${id}/arrive`, headers: auth(t.token), payload: { lat: 22.31, lng: 73.18 } })).statusCode).toBe(409);
    await app.inject({ method: 'POST', url: `/technician/jobs/${id}/en-route`, headers: auth(t.token) });
    // en-route again from EN_ROUTE → 409
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${id}/en-route`, headers: auth(t.token) })).statusCode).toBe(409);
  });

  it("a different technician cannot drive en-route/arrive on someone else's accepted job → 403", async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const t = await makeTechnician(['AC']);
    const id = await bookedAndAccepted(c, t, { addressId: f.address.id, serviceId: f.service.id });
    const other = await makeTechnician(['AC']);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${id}/en-route`, headers: auth(other.token) })).statusCode).toBe(403);
  });

  it('a CUSTOMER calling /arrive → 403; lat without lng → 400', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const t = await makeTechnician(['AC']);
    const id = await bookedAndAccepted(c, t, { addressId: f.address.id, serviceId: f.service.id });
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${id}/arrive`, headers: auth(c.token), payload: { lat: 22.31, lng: 73.18 } })).statusCode).toBe(403);
    await app.inject({ method: 'POST', url: `/technician/jobs/${id}/en-route`, headers: auth(t.token) });
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${id}/arrive`, headers: auth(t.token), payload: { lat: 22.31 } })).statusCode).toBe(400);
  });
});
```

- [ ] **Step 2: Run — confirm FAIL**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/technician-jobs/arrival.test.ts
```

- [ ] **Step 3: Create `technician-jobs.schemas.ts`**
```ts
import { z } from 'zod';

export const arriveBody = z.object({
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
}).strict();
export type ArriveBody = z.infer<typeof arriveBody>;
```

- [ ] **Step 4: Add `enRouteJob` + `arriveJob` to `technician-jobs.service.ts`**

Extend the imports:
```ts
import { transitionBooking } from '../bookings/bookings.state.js';
import { haversineMeters } from '../../shared/utils/geo.js';
import { mintArrivalCode } from '../bookings/arrival-code.js';
import type { ArriveBody } from './technician-jobs.schemas.js';
```
Append:
```ts
const GEOFENCE_METERS = 200;

/** Load a booking that must be assigned to this technician + in the given state. */
async function ownAssignedBookingOrThrow(techId: string, bookingId: string, expectedState: 'ACCEPTED' | 'EN_ROUTE') {
  const b = await prisma.booking.findFirst({ where: { id: bookingId, deletedAt: null }, include: { address: true } });
  if (!b) throw new NotFoundError('Job not found');
  if (b.technicianId !== techId) throw new ForbiddenError('This job is not assigned to you');
  if (b.state !== expectedState) throw new ConflictError(`Job is not in ${expectedState}`);
  return b;
}

/** ACCEPTED → EN_ROUTE ("on my way"). Returns the booking DTO via the bookings module's mapper is
 *  unnecessary here — return a minimal status object the technician app needs. */
export async function enRouteJob(userId: string, bookingId: string): Promise<{ id: string; state: 'EN_ROUTE' }> {
  const tech = await requireTechnician(userId);
  const booking = await ownAssignedBookingOrThrow(tech.id, bookingId, 'ACCEPTED');
  await prisma.$transaction((tx) => transitionBooking(tx, booking, 'EN_ROUTE', { type: 'USER', kind: 'TECHNICIAN', id: userId }));
  return { id: bookingId, state: 'EN_ROUTE' };
}

/** Arrive-tap: GPS gate (validate-if-present) + record GPS + mint the single-use code. NO state change. */
export async function arriveJob(userId: string, bookingId: string, body: ArriveBody): Promise<{ arrivalCode: string; withinGeofence: boolean | null }> {
  const tech = await requireTechnician(userId);
  const booking = await ownAssignedBookingOrThrow(tech.id, bookingId, 'EN_ROUTE');

  let withinGeofence: boolean | null = null;
  if (booking.address.lat != null && booking.address.lng != null) {
    const dist = haversineMeters(booking.address.lat, booking.address.lng, body.lat, body.lng);
    if (dist > GEOFENCE_METERS) throw new UnprocessableError('You are too far from the customer location');
    withinGeofence = true;
  }
  await prisma.booking.update({ where: { id: bookingId }, data: { arrivalLat: body.lat, arrivalLng: body.lng } });
  const arrivalCode = await mintArrivalCode(bookingId);
  return { arrivalCode, withinGeofence };
}
```
Add `UnprocessableError` to the errors import at the top of the file:
```ts
import { ForbiddenError, NotFoundError, ConflictError, UnprocessableError } from '../../shared/errors.js';
```

- [ ] **Step 5: Add the routes**

In `technician-jobs.routes.ts`, import the schema + new service fns and add `ValidationError`:
```ts
import { ValidationError, ForbiddenError } from '../../shared/errors.js';
import { listAvailableJobs, listMyJobs, acceptJob, skipJob, enRouteJob, arriveJob } from './technician-jobs.service.js';
import { arriveBody } from './technician-jobs.schemas.js';
```
Add before the closing `}`:
```ts
  app.post('/technician/jobs/:id/en-route', { preHandler: [requireAuth] }, async (req, reply) => {
    requireTechnicianRole(req);
    return reply.send(await enRouteJob(req.user!.id, (req.params as { id: string }).id));
  });

  app.post('/technician/jobs/:id/arrive', { preHandler: [requireAuth] }, async (req, reply) => {
    requireTechnicianRole(req);
    const p = arriveBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.send(await arriveJob(req.user!.id, (req.params as { id: string }).id, p.data));
  });
```

- [ ] **Step 6: Run — PASS**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/technician-jobs/arrival.test.ts
```
(Only the en-route + arrive tests pass; the confirm-arrival tests are added in Task 6.)

- [ ] **Step 7: Build + commit**
```bash
cd apps/backend && pnpm build   # expect clean
git add apps/backend/src/modules/technician-jobs apps/backend/tests/technician-jobs/arrival.test.ts
git commit -m "feat(backend): technician en-route + arrive (GPS gate + mint code) (booking B3)"
```

---

## Task 6: customer confirm-arrival → ARRIVED + lock

**Files:**
- Modify: `apps/backend/src/modules/bookings/bookings.schemas.ts`
- Modify: `apps/backend/src/modules/bookings/bookings.service.ts`
- Modify: `apps/backend/src/modules/bookings/bookings.routes.ts`
- Modify: `apps/backend/tests/technician-jobs/arrival.test.ts`

- [ ] **Step 1: Add the failing confirm-arrival tests**

Append to `apps/backend/tests/technician-jobs/arrival.test.ts` (a new describe; reuses the helpers above):
```ts
describe('arrival handshake — customer confirm (the two-sided gate)', () => {
  async function enRouteAndArrive(c: { token: string; customerId: string }, t: { token: string }, f: { address: { id: string }; service: { id: string } }) {
    const id = await bookedAndAccepted(c, t, { addressId: f.address.id, serviceId: f.service.id });
    await app.inject({ method: 'POST', url: `/technician/jobs/${id}/en-route`, headers: auth(t.token) });
    const code = (await app.inject({ method: 'POST', url: `/technician/jobs/${id}/arrive`, headers: auth(t.token), payload: { lat: 22.31, lng: 73.18 } })).json().arrivalCode as string;
    return { id, code };
  }

  it('correct code → ARRIVED, arrivedAt + visitFeeLockedAt set, audit has no raw coords', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const t = await makeTechnician(['AC']);
    const { id, code } = await enRouteAndArrive(c, t, f);
    const res = await app.inject({ method: 'POST', url: `/me/bookings/${id}/confirm-arrival`, headers: auth(c.token), payload: { code } });
    expect(res.statusCode).toBe(200);
    expect(res.json().state).toBe('ARRIVED');
    const row = await prisma.booking.findUnique({ where: { id } });
    expect(row!.arrivedAt).not.toBeNull();
    expect(row!.visitFeeLockedAt).not.toBeNull();
    const audit = await prisma.auditLog.findFirst({ where: { action: 'BOOKING_STATE_CHANGED', metadata: { path: ['to'], equals: 'ARRIVED' } } });
    expect(audit!.metadata).toMatchObject({ codeConfirmed: true });
    expect(JSON.stringify(audit!.metadata)).not.toMatch(/73\.18|22\.31/); // no raw coords
  });

  it('confirm before the technician tapped Arrived (no code) → 409', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const t = await makeTechnician(['AC']);
    const id = await bookedAndAccepted(c, t, { addressId: f.address.id, serviceId: f.service.id });
    await app.inject({ method: 'POST', url: `/technician/jobs/${id}/en-route`, headers: auth(t.token) });
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${id}/confirm-arrival`, headers: auth(c.token), payload: { code: '123456' } })).statusCode).toBe(409);
  });

  it('wrong code → 401; 5 wrong attempts invalidate the code (the right code then also 401)', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const t = await makeTechnician(['AC']);
    const { id, code } = await enRouteAndArrive(c, t, f);
    for (let i = 0; i < 5; i++) expect((await app.inject({ method: 'POST', url: `/me/bookings/${id}/confirm-arrival`, headers: auth(c.token), payload: { code: '000000' } })).statusCode).toBe(401);
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${id}/confirm-arrival`, headers: auth(c.token), payload: { code } })).statusCode).toBe(401);
    const row = await prisma.booking.findUnique({ where: { id } });
    expect(row!.state).toBe('EN_ROUTE'); // never reached ARRIVED
  });

  it("another customer's confirm-arrival → 404 (no IDOR); a TECHNICIAN calling it → 403", async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const t = await makeTechnician(['AC']);
    const { id, code } = await enRouteAndArrive(c, t, f);
    const other = await makeCustomer();
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${id}/confirm-arrival`, headers: auth(other.token), payload: { code } })).statusCode).toBe(404);
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${id}/confirm-arrival`, headers: auth(t.token), payload: { code } })).statusCode).toBe(403);
  });

  it('single-party: technician arrives but customer never confirms → booking stays EN_ROUTE', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const t = await makeTechnician(['AC']);
    const { id } = await enRouteAndArrive(c, t, f);
    const row = await prisma.booking.findUnique({ where: { id } });
    expect(row!.state).toBe('EN_ROUTE');
    expect(row!.visitFeeLockedAt).toBeNull();
  });
});
```

- [ ] **Step 2: Run — confirm FAIL**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/technician-jobs/arrival.test.ts
```

- [ ] **Step 3: Add `confirmArrivalBody` to `bookings.schemas.ts`**
```ts
export const confirmArrivalBody = z.object({ code: z.string().regex(/^\d{6}$/, 'code must be 6 digits') }).strict();
export type ConfirmArrivalBody = z.infer<typeof confirmArrivalBody>;
```

- [ ] **Step 4: Add `confirmArrival` to `bookings.service.ts`**

Extend imports:
```ts
import { verifyArrivalCode } from './arrival-code.js';
import { haversineMeters } from '../../shared/utils/geo.js';
import { UnauthorizedError } from '../../shared/errors.js';
import type { ConfirmArrivalBody } from './bookings.schemas.js';
```
Append (reuse `requireCustomer` + `ownBookingOrThrow`; `transitionBooking` already imported):
```ts
export async function confirmArrival(userId: string, id: string, body: ConfirmArrivalBody): Promise<BookingDto> {
  const { id: customerId } = await requireCustomer(userId);
  const booking = await prisma.booking.findFirst({ where: { id, customerId, deletedAt: null }, include: { address: true } });
  if (!booking) throw new NotFoundError('Booking not found');
  if (booking.state !== 'EN_ROUTE') throw new ConflictError('Booking is not awaiting arrival confirmation');

  const result = await verifyArrivalCode(id, body.code);
  if (result === 'no-code') throw new ConflictError('The technician has not marked arrival yet');
  if (result === 'invalid') throw new UnauthorizedError('Invalid or expired arrival code');

  // re-derive audit evidence from the persisted arrival GPS + the address (no raw coords in audit)
  const gpsRecorded = booking.arrivalLat != null && booking.arrivalLng != null;
  const withinGeofence =
    gpsRecorded && booking.address.lat != null && booking.address.lng != null
      ? haversineMeters(booking.address.lat, booking.address.lng, booking.arrivalLat!, booking.arrivalLng!) <= 200
      : null;

  const updated = await prisma.$transaction(async (tx) => {
    await transitionBooking(
      tx, booking, 'ARRIVED', { type: 'USER', kind: 'CUSTOMER', id: userId },
      { gpsRecorded, withinGeofence, codeConfirmed: true }, // evidence → merged into the audit metadata
    );
    return tx.booking.update({ where: { id }, data: { arrivedAt: new Date(), visitFeeLockedAt: new Date() } });
  });
  return toBookingDto(updated);
}
```
**This requires extending `transitionBooking` first** (do it as the first edit of this step, in `bookings.state.ts`): add an optional 5th param `evidence?: Record<string, unknown>` and spread it into the audit metadata:
```ts
export async function transitionBooking(
  tx: Prisma.TransactionClient,
  booking: Booking,
  to: BookingState,
  actor: BookingActor,
  evidence?: Record<string, unknown>,
): Promise<Booking> {
  // ...existing legality + actor + optimistic-lock checks unchanged...
  await tx.auditLog.create({
    data: {
      action: 'BOOKING_STATE_CHANGED',
      actorType: actor.type,
      actorId: actor.id,
      metadata: { bookingId: booking.id, from: booking.state, to, ...(evidence ?? {}) },
    },
  });
  // ...existing re-read + return unchanged...
}
```
Backward-compatible: every existing caller (createBooking, cancelBooking, acceptJob, enRouteJob) omits `evidence` and is unaffected. **Keep no raw coords in `evidence`** — only the booleans `gpsRecorded`/`withinGeofence` + `codeConfirmed`.

- [ ] **Step 5: Add the route**

In `bookings.routes.ts`, import `confirmArrival` + `confirmArrivalBody`, and add:
```ts
  app.post('/me/bookings/:id/confirm-arrival', { preHandler: [requireAuth] }, async (req, reply) => {
    const p = confirmArrivalBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.send(await confirmArrival(req.user!.id, (req.params as { id: string }).id, p.data));
  });
```
(`requireCustomer` in the service throws 403 for non-customers; the role-gate also runs via `ALLOWED_ACTORS[ARRIVED]=['CUSTOMER']` inside `transitionBooking`. No `requireCustomerRole` helper exists in bookings.routes — the service `requireCustomer` + the actor gate cover it. If `ValidationError` isn't imported in bookings.routes.ts, add it.)

- [ ] **Step 6: Run — PASS (full arrival suite)**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/technician-jobs/arrival.test.ts
```
Expected: all en-route/arrive/confirm tests green.

- [ ] **Step 7: Build + full booking + technician suites**
```bash
cd apps/backend && pnpm build
set -a && . ./.env && set +a && pnpm test -- tests/bookings tests/technician-jobs
```
Both green (no regressions; the `transitionBooking` evidence param is backward-compatible).

- [ ] **Step 8: Commit**
```bash
git add apps/backend/src/modules/bookings apps/backend/tests/technician-jobs/arrival.test.ts
git commit -m "feat(backend): customer confirm-arrival → ARRIVED + visit-fee lock (booking B3)"
```

---

## Task 7: full suite + reviews + docs

**Files:**
- Modify: `STATUS.md`, `CHANGELOG.md`

- [ ] **Step 1: Full backend suite**
```bash
set -a && . ./.env && set +a && cd apps/backend && pnpm test
```
Expected: ALL green (the prior 179 + the new geo/arrival-code/arrival tests). Note the total.

- [ ] **Step 2: Review agents**
- `prisma-migration-reviewer` — the `arrival_evidence` migration (4 nullable additive columns, no money fields — lat/lng are coordinates not paise).
- `golden-rules-auditor` — **Golden Rules 1-2 (the keystone): the ARRIVED transition requires BOTH the technician's GPS arrive-tap (which mints the code) AND the customer's code entry — no single-party path to ARRIVED; confirm via the "tech arrives, customer never confirms → stays EN_ROUTE" + "no code → 409" tests.** Audit in-tx; **no raw GPS coords / no phone in audit metadata** (assert the audit-no-coords test). The arrival code is hashed + single-use + attempt-capped (never raw in DB/logs).
- `fraud-vector-checker` — fraud-defenses #11 (Visitation Without Arrival / GPS spoof): the GPS gate (>200m → 422 when coords present) + the two-sided code make a remote "arrived" claim impossible to complete alone. Confirm the record-only fallback (no coords) is a noted V1 acceptance, not a silent hole.

Address blockers; re-run; then `/code-review` on the branch (twice if the first pass finds fixes).

- [ ] **Step 3: STATUS.md**
Phase: booking module — B1+B2a merged, **B3 (arrival handshake, keystone #1) done** on branch. Active task → B3 summary (two-sided GPS+code handshake → ARRIVED + visitFeeLockedAt; the first keystone). Next 3 → B4 (diagnosis + parts) or B5 (completion handshake, keystone #2). `_Last updated_` 2026-06-13.

- [ ] **Step 4: CHANGELOG.md**
`## 2026-06-13 — Booking B3 (arrival handshake — keystone #1)`: the two-sided handshake (tech en-route → GPS-validated arrive-tap mints a single-use Redis code → customer enters code → ARRIVED), the visit-fee milestone (`visitFeeLockedAt`), GPS gate (validate-if-present 200m / record-only), evidence columns, EN_ROUTE/ARRIVED actor entries, no-PII audit, deferred (B4 diagnosis, B5 completion handshake, B6 charge, hard geofence). Test count; review notes.

- [ ] **Step 5: Commit docs + finish branch**
```bash
git add STATUS.md CHANGELOG.md
git commit -m "docs: status + changelog for booking B3 (arrival handshake)"
```
Then `superpowers:finishing-a-development-branch` → PR `feature/booking-arrival` → `main` (push/PR is the user's step). B4 (diagnosis+parts) or B5 (completion handshake) continues the module after merge.

---

## Self-Review notes

- **Spec coverage:** 4 evidence columns + migration ✓ (T1); haversine ✓ (T2); single-use hashed Redis arrival code + attempt cap ✓ (T3); EN_ROUTE/ARRIVED actor entries ✓ (T4); en-route + GPS-gated arrive (validate-if-present / record-only) + mint, no state change, assigned-tech identity ✓ (T5); customer confirm → ARRIVED + arrivedAt/visitFeeLockedAt + evidence-in-audit + the two-sided/no-code/wrong-code/IDOR/single-party assertions ✓ (T6). Decisions 1-6 covered. Deferred (B4/B5/B6, hard geofence, ETA) out of scope.
- **Placeholder scan:** none — every step has concrete code/commands. (T6 Step 4 includes a precise instruction to add an optional `evidence` param to `transitionBooking` and pass it as the 5th arg — concrete, not a placeholder; the inline `as Parameters` cast is explicitly replaced by the real param.)
- **Type consistency:** `mintArrivalCode(bookingId)→string` / `verifyArrivalCode(bookingId,code)→'ok'|'invalid'|'no-code'` used consistently in T3 + T6; `haversineMeters(aLat,aLng,bLat,bLng)` in T2/T5/T6; `arriveBody{lat,lng}` / `confirmArrivalBody{code}`; `enRouteJob`/`arriveJob`/`confirmArrival`; `transitionBooking`'s new optional `evidence` param is backward-compatible (T6) — existing callers (createBooking, cancelBooking, acceptJob, enRouteJob, arriveJob doesn't transition) unaffected. `ownAssignedBookingOrThrow` (technician side) vs `ownBookingOrThrow` (customer side, existing) named distinctly.
- **Keystone integrity (Golden Rules 1-2):** ARRIVED is reachable ONLY through confirmArrival, which requires a code that ONLY arriveJob (GPS-gated) mints → genuinely two-sided; the single-party test proves no bypass. The optimistic lock in transitionBooking prevents replay/double-apply.
