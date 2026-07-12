# Booking B5 — Repair Execution + Completion Handshake Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the full repair-execution path (parts states + repair states) with technician-driven transitions, gate REPAIR_COMPLETE on the 3 mandatory repair photos, and implement the completion OTP handshake (keystone #2) — CUSTOMER_CONFIRMED becomes reachable end-to-end.

**Architecture:** Five technician endpoints extend the technician-jobs module using the established trio (`requireTechnician` → `ownAssignedBookingOrThrow` → `transitionBooking` in a tx); one customer endpoint (mint) extends bookings, mirroring the arrival keystone with roles reversed. Photos reuse B4b verbatim via a `PHOTO_WINDOW` map (kind → allowed booking state). The completion code is a thin `completion-code.ts` wrapper over `otp-store` (key `completion:{bookingId}`, sendLimit-throttled). The store's mint path becomes one atomic Lua script (the promised backlog fix), proven by existing suites staying green.

**Tech Stack:** Node 22, Fastify 5, Prisma 6, Zod 4, ioredis (Lua via `redis.eval`), Vitest.

## Global Constraints

- Commit author MUST be `MohammadKaifSaiyad <saiyedkgn6@gmail.com>` with NO Co-Authored-By/Claude trailer. Commit via `git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "..."`.
- Backend commands from `apps/backend` with env sourced: `set -a && source .env && set +a` before `pnpm vitest run` / `pnpm tsc --noEmit`. Docker stack up (`docker compose up -d` from repo root).
- No `any`; TS strict; ESM `.js` imports; Zod-validated route inputs; DB writes in services; DTOs only; auth first; ownership → foreign id 404 (customer) / 403 (tech), per existing idiom.
- Rule 5: audit in the same transaction (all transitions via `transitionBooking`). Rule 7: never the OTP code, customer phone, or coordinates in audit/logs; `devOtp` only when `config.NODE_ENV !== 'production'`.
- Golden Rule 2: no single-party path to CUSTOMER_CONFIRMED — technician drives the transition ONLY with the code minted to the customer.
- Photo gates read inside the tx AFTER a booking-row write (B4b idiom — audit photoIds always reference the final committed set).
- OTP-store Lua refactor is BEHAVIOR-PRESERVING: `tests/shared/otp-store.test.ts`, `tests/auth/*`, `tests/bookings/arrival-code.test.ts` all pass UNCHANGED.
- Design (source of truth): `docs/designs/2026-07-12-booking-b5-completion-design.md`.
- Current baseline: 246 tests green on `feature/booking-b5-completion` (fresh off main `d225f10`).

---

### Task 1: Schema — REPAIR_* photo kinds + milestone timestamps

**Files:**
- Modify: `apps/backend/prisma/schema.prisma` (PhotoKind enum ~line 360; Booking model ~line 333)
- Test: `apps/backend/tests/schema/repair-schema.test.ts`

**Interfaces:**
- Consumes: existing `PhotoKind`, `Booking`.
- Produces: `PhotoKind` += `REPAIR_OLD_PART | REPAIR_NEW_PACKAGING | REPAIR_INSTALLED`; `Booking.repairStartedAt/repairCompletedAt/confirmedAt: DateTime?`. Later tasks rely on these exact names.

- [ ] **Step 1: Write the failing test** (`apps/backend/tests/schema/repair-schema.test.ts`)

```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { prisma, resetDb } from './helpers.js';

afterAll(() => prisma.$disconnect());
beforeEach(resetDb);

// Minimal booking seed — mirrors tests/schema/photo-evidence.test.ts (copy its seed idiom
// verbatim if a required field errors; do not change the schema to fit the test).
async function seedBooking() {
  const user = await prisma.user.create({ data: { phone: `98${Math.floor(Math.random() * 1e8)}`, role: 'CUSTOMER' } });
  const customer = await prisma.customer.create({ data: { userId: user.id, name: 'C' } });
  const zone = await prisma.zone.create({ data: { name: `Z-${Math.random().toString(36).slice(2, 8)}`, visitFeePaise: 9900 } });
  const cat = await prisma.serviceCategory.create({ data: { name: `Cat-${Math.random().toString(36).slice(2, 8)}` } });
  const service = await prisma.service.create({ data: { name: 'S', categoryId: cat.id, tier: 'T1', requiredSkill: 'AC' } });
  const address = await prisma.address.create({ data: { customerId: customer.id, label: 'Home', line1: 'L1', pincode: '390001', zoneId: zone.id } });
  return prisma.booking.create({
    data: {
      bookingNumber: `FC-${Math.random().toString(36).slice(2, 8)}`,
      customerId: customer.id, addressId: address.id, serviceId: service.id,
      zoneId: zone.id, zoneName: zone.name, serviceName: service.name,
      visitFeePaise: 9900, laborPaise: 50000, laborTier: 'T1',
      scheduledSlot: new Date(Date.now() + 86_400_000),
    },
  });
}

describe('B5 schema', () => {
  it('accepts the three REPAIR_* photo kinds', async () => {
    const b = await seedBooking();
    for (const kind of ['REPAIR_OLD_PART', 'REPAIR_NEW_PACKAGING', 'REPAIR_INSTALLED'] as const) {
      await prisma.photoEvidence.create({ data: { bookingId: b.id, kind, r2Key: `jobs/${b.id}/${kind}-x.jpg`, capturedAt: new Date() } });
    }
    expect(await prisma.photoEvidence.count({ where: { bookingId: b.id } })).toBe(3);
  });

  it('milestone timestamps are nullable and writable', async () => {
    const b = await seedBooking();
    expect(b.repairStartedAt).toBeNull();
    expect(b.repairCompletedAt).toBeNull();
    expect(b.confirmedAt).toBeNull();
    const updated = await prisma.booking.update({ where: { id: b.id }, data: { repairStartedAt: new Date(), repairCompletedAt: new Date(), confirmedAt: new Date() } });
    expect(updated.confirmedAt).not.toBeNull();
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd apps/backend && set -a && source .env && set +a && pnpm vitest run tests/schema/repair-schema.test.ts`
Expected: FAIL — `REPAIR_OLD_PART` not a valid PhotoKind / `repairStartedAt` unknown field.

- [ ] **Step 3: Edit `apps/backend/prisma/schema.prisma`**

PhotoKind enum becomes:

```prisma
enum PhotoKind {
  DIAGNOSIS_OVERVIEW
  DIAGNOSIS_CLOSEUP
  REPAIR_OLD_PART
  REPAIR_NEW_PACKAGING
  REPAIR_INSTALLED
}
```

Booking model, after `declinedAt` (~line 334):

```prisma
  repairStartedAt    DateTime?
  repairCompletedAt  DateTime?
  confirmedAt        DateTime? // completion OTP verified — dispute-resolution Tier-1 keys off this
```

- [ ] **Step 4: Migrate BOTH DBs**

```bash
cd apps/backend && set -a && source .env && set +a
pnpm prisma migrate dev --name repair_completion
DATABASE_URL="$TEST_DATABASE_URL" pnpm prisma migrate deploy
```

Expected: additive migration (ALTER TYPE ADD VALUE ×3, ALTER TABLE ADD COLUMN ×3) applied to both.

- [ ] **Step 5: Run the test to verify it passes**

Run: `pnpm vitest run tests/schema/repair-schema.test.ts` → PASS (2 tests). Then `pnpm vitest run tests/schema` → no regressions.

- [ ] **Step 6: Typecheck + commit**

```bash
pnpm tsc --noEmit
git add prisma/schema.prisma prisma/migrations tests/schema/repair-schema.test.ts
git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(backend): REPAIR_* photo kinds + repair/confirmation milestones (B5 schema)"
```

---

### Task 2: OTP-store atomic mint (Lua) — behavior-preserving

**Files:**
- Modify: `apps/backend/src/shared/auth/otp-store.ts` (`mintOtp` only)
- Tests (UNCHANGED — they are the proof): `tests/shared/otp-store.test.ts`, `tests/auth/otp-send.test.ts`, `tests/auth/otp-verify.test.ts`, `tests/bookings/arrival-code.test.ts`

**Interfaces:**
- Consumes: `redis` (ioredis — has `.eval`).
- Produces: `mintOtp` signature and behavior UNCHANGED (`{status:'ok', code} | {status:'throttled'}`); the throttle counter still lives at `${key}:rl` with the same window semantics.

- [ ] **Step 1: Baseline green (this is the RED-equivalent for a refactor)**

Run: `cd apps/backend && set -a && source .env && set +a && pnpm vitest run tests/shared/otp-store.test.ts tests/auth/otp-send.test.ts tests/auth/otp-verify.test.ts tests/bookings/arrival-code.test.ts`
Expected: PASS (records the contract).

- [ ] **Step 2: Replace `mintOtp`'s body** in `apps/backend/src/shared/auth/otp-store.ts` — the imports, types, `rlKey`, and `verifyOtp` stay untouched; `mintOtp` becomes:

```ts
// One atomic script: throttle-increment (+TTL on first hit), limit check, OTP write. Previously
// these were 3 separate commands — a crash between them could burn a send slot (INCR landed, SET
// didn't) or leave a TTL-less counter (INCR landed, EXPIRE didn't) that throttled the key until a
// manual redis del. KEYS[1]=otp key, KEYS[2]=throttle counter; ARGV: json, ttl, max, window.
// max=0 means "no throttle configured" — skip the counter entirely.
const MINT_LUA = `
local max = tonumber(ARGV[3])
if max > 0 then
  local n = redis.call('INCR', KEYS[2])
  if n == 1 then redis.call('EXPIRE', KEYS[2], ARGV[4]) end
  if n > max then return 0 end
end
redis.call('SET', KEYS[1], ARGV[1], 'EX', ARGV[2])
return 1
`;

/** Mint a single-use 6-digit OTP under `key`. Optionally throttles minting and stores a typed payload. */
export async function mintOtp<P = undefined>(
  key: string,
  cfg: OtpStoreConfig,
  payload?: P,
): Promise<MintResult> {
  const code = generateOtp();
  const stored: StoredOtp = { hash: hashOtp(code), attempts: 0, payload };
  const ok = await redis.eval(
    MINT_LUA,
    2,
    key,
    rlKey(key),
    JSON.stringify(stored),
    String(cfg.ttlSeconds),
    String(cfg.sendLimit?.max ?? 0),
    String(cfg.sendLimit?.windowSeconds ?? 0),
  );
  return ok === 1 ? { status: 'ok', code } : { status: 'throttled' };
}
```

(`MINT_LUA` goes above `mintOtp`, after `rlKey`.)

- [ ] **Step 3: Re-run the SAME suites — must pass unchanged**

Run: the Step 1 command again.
Expected: PASS, zero test edits. If any fails, the refactor broke the contract — fix `mintOtp`, never the tests.

- [ ] **Step 4: Typecheck + commit**

```bash
pnpm tsc --noEmit
git add src/shared/auth/otp-store.ts
git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "fix(backend): atomic OTP mint via Lua (closes the INCR/EXPIRE/SET crash windows)"
```

---

### Task 3: Repair-path transitions — parts-needed / parts-acquired / start-repair

**Files:**
- Modify: `apps/backend/src/modules/bookings/bookings.state.ts:36-45` (ALLOWED_ACTORS)
- Modify: `apps/backend/src/modules/technician-jobs/technician-jobs.service.ts` (widen `ownAssignedBookingOrThrow`; three new fns)
- Modify: `apps/backend/src/modules/technician-jobs/technician-jobs.routes.ts` (three routes)
- Test: `apps/backend/tests/technician-jobs/repair-path.test.ts`

**Interfaces:**
- Consumes: `transitionBooking`, `requireTechnician`, `ownAssignedBookingOrThrow`, `UnprocessableError`.
- Produces (Tasks 4-5 rely on):
  - `ownAssignedBookingOrThrow(techId: string, bookingId: string, expectedState: BookingState | readonly BookingState[])` — widened to any state(s); existing single-string callers unchanged.
  - `partsNeeded(userId, bookingId): Promise<{id: string; state: 'PARTS_REQUESTED'}>`
  - `partsAcquired(userId, bookingId): Promise<{id: string; state: 'PARTS_ACQUIRED'}>`
  - `startRepair(userId, bookingId): Promise<{id: string; state: 'REPAIR_IN_PROGRESS'}>` (from CUSTOMER_APPROVED or PARTS_ACQUIRED; sets `repairStartedAt`)
  - Routes: `POST /technician/jobs/:id/parts-needed`, `.../parts-acquired`, `.../start-repair` (all 200).
  - `ALLOWED_ACTORS` += `PARTS_REQUESTED/PARTS_ACQUIRED/REPAIR_IN_PROGRESS: ['TECHNICIAN']`.
  - Test fixture `approvedBooking()` (exported from the test file is fine — Task 4/5 test files build their own; see their briefs).

- [ ] **Step 1: Write the failing tests** (`apps/backend/tests/technician-jobs/repair-path.test.ts`)

```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, makeTechnician, seedBookable, seedIssue, seedDiagnosisPhotos } from '../bookings/helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
function future() { return new Date(Date.now() + 86_400_000).toISOString(); }

/** Booking driven to CUSTOMER_APPROVED (with a seeded cart part so the parts path is legal). */
async function approvedBooking(withPart = true) {
  const c = await makeCustomer();
  const f = await seedBookable(c.customerId);
  const t = await makeTechnician(['AC']);
  const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(t.token) });
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/en-route`, headers: auth(t.token) });
  const code = (await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/arrive`, headers: auth(t.token), payload: { lat: 22.31, lng: 73.18 } })).json().arrivalCode;
  await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/confirm-arrival`, headers: auth(c.token), payload: { code } });
  await seedDiagnosisPhotos(booking.id); // diagnose requires both slots (B4b)
  const issue = await seedIssue(f.cat.id);
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id } });
  if (withPart) {
    // Seed the cart line directly (snapshot fields) — the parts ENDPOINT has its own tests in diagnosis.test.ts.
    await prisma.bookingPart.create({ data: { bookingId: booking.id, partsCatalogId: null as never, sku: 'SEED-1', name: 'Seed part', ceilingPricePaise: 10000, qty: 1 } })
      .catch(async () => {
        const cat = await prisma.partsCatalog.create({ data: { sku: `S-${Math.random().toString(36).slice(2, 8)}`, name: 'Seed part', ceilingPricePaise: 10000 } });
        await prisma.bookingPart.create({ data: { bookingId: booking.id, partsCatalogId: cat.id, sku: cat.sku, name: cat.name, ceilingPricePaise: cat.ceilingPricePaise, qty: 1 } });
      });
  }
  await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/approve`, headers: auth(c.token) });
  return { c, t, bookingId: booking.id as string };
}

describe('repair path', () => {
  it('parts detour: CUSTOMER_APPROVED → PARTS_REQUESTED → PARTS_ACQUIRED → REPAIR_IN_PROGRESS', async () => {
    const { t, bookingId } = await approvedBooking();
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts-needed`, headers: auth(t.token) })).statusCode).toBe(200);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts-acquired`, headers: auth(t.token) })).statusCode).toBe(200);
    const start = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/start-repair`, headers: auth(t.token) });
    expect(start.statusCode).toBe(200);
    const row = await prisma.booking.findUnique({ where: { id: bookingId } });
    expect(row!.state).toBe('REPAIR_IN_PROGRESS');
    expect(row!.repairStartedAt).not.toBeNull();
  });

  it('direct path: CUSTOMER_APPROVED → REPAIR_IN_PROGRESS (no parts detour)', async () => {
    const { t, bookingId } = await approvedBooking(false);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/start-repair`, headers: auth(t.token) })).statusCode).toBe(200);
    expect((await prisma.booking.findUnique({ where: { id: bookingId } }))!.state).toBe('REPAIR_IN_PROGRESS');
  });

  it('parts-needed with an EMPTY cart → 422 (dishonest detour)', async () => {
    const { t, bookingId } = await approvedBooking(false);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts-needed`, headers: auth(t.token) })).statusCode).toBe(422);
  });

  it('actor + state guards: foreign tech 403, customer 403, wrong-state 409, audit written', async () => {
    const { c, t, bookingId } = await approvedBooking();
    const other = await makeTechnician(['AC']);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/start-repair`, headers: auth(other.token) })).statusCode).toBe(403);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/start-repair`, headers: auth(c.token) })).statusCode).toBe(403);
    await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/start-repair`, headers: auth(t.token) });
    // already in repair — every earlier transition now 409s
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts-needed`, headers: auth(t.token) })).statusCode).toBe(409);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/start-repair`, headers: auth(t.token) })).statusCode).toBe(409);
    const audit = await prisma.auditLog.findFirst({ where: { action: 'BOOKING_STATE_CHANGED', metadata: { path: ['to'], equals: 'REPAIR_IN_PROGRESS' } } });
    expect(audit).not.toBeNull();
  });
});
```

> NOTE for the implementer: the `partsCatalogId: null as never` first attempt is wrong-by-design if the FK is required — keep ONLY the `.catch` branch's shape if the schema requires a real catalog row (check `model BookingPart` in schema.prisma and simplify to a single working create; do not leave the catch dance in the final test).

- [ ] **Step 2: Run to verify they fail**

Run: `pnpm vitest run tests/technician-jobs/repair-path.test.ts` → FAIL (404s — routes don't exist).

- [ ] **Step 3: Add the actor entries** in `apps/backend/src/modules/bookings/bookings.state.ts` — extend `ALLOWED_ACTORS`:

```ts
  PARTS_REQUESTED:       ['TECHNICIAN'],
  PARTS_ACQUIRED:        ['TECHNICIAN'],
  REPAIR_IN_PROGRESS:    ['TECHNICIAN'],
```

- [ ] **Step 4: Widen the helper + add the service functions** in `technician-jobs.service.ts`.

Replace `ownAssignedBookingOrThrow` (keep its position):

```ts
/** Load a booking that must be assigned to this technician + in one of the given state(s). */
async function ownAssignedBookingOrThrow(
  techId: string,
  bookingId: string,
  expectedState: import('@prisma/client').BookingState | readonly import('@prisma/client').BookingState[],
) {
  const states = Array.isArray(expectedState) ? expectedState : [expectedState];
  const b = await prisma.booking.findFirst({ where: { id: bookingId, deletedAt: null }, include: { address: true, service: true } });
  if (!b) throw new NotFoundError('Job not found');
  if (b.technicianId !== techId) throw new ForbiddenError('This job is not assigned to you');
  if (!states.includes(b.state)) throw new ConflictError(`Job is not in ${states.join(' or ')}`);
  return b;
}
```

Append the three functions:

```ts
/** CUSTOMER_APPROVED → PARTS_REQUESTED. Only honest with a non-empty approved cart. */
export async function partsNeeded(userId: string, bookingId: string): Promise<{ id: string; state: 'PARTS_REQUESTED' }> {
  const tech = await requireTechnician(userId);
  const booking = await ownAssignedBookingOrThrow(tech.id, bookingId, 'CUSTOMER_APPROVED');
  const partCount = await prisma.bookingPart.count({ where: { bookingId } });
  if (partCount === 0) throw new UnprocessableError('No parts in the approved estimate — start the repair instead');
  await prisma.$transaction((tx) =>
    transitionBooking(tx, booking, 'PARTS_REQUESTED', { type: 'USER', kind: 'TECHNICIAN', id: userId }, { partCount }),
  );
  return { id: bookingId, state: 'PARTS_REQUESTED' };
}

/** PARTS_REQUESTED → PARTS_ACQUIRED (merchant procurement is WhatsApp-manual in V1 — tracked only). */
export async function partsAcquired(userId: string, bookingId: string): Promise<{ id: string; state: 'PARTS_ACQUIRED' }> {
  const tech = await requireTechnician(userId);
  const booking = await ownAssignedBookingOrThrow(tech.id, bookingId, 'PARTS_REQUESTED');
  await prisma.$transaction((tx) =>
    transitionBooking(tx, booking, 'PARTS_ACQUIRED', { type: 'USER', kind: 'TECHNICIAN', id: userId }),
  );
  return { id: bookingId, state: 'PARTS_ACQUIRED' };
}

/** CUSTOMER_APPROVED | PARTS_ACQUIRED → REPAIR_IN_PROGRESS. Opens the repair-photo window. */
export async function startRepair(userId: string, bookingId: string): Promise<{ id: string; state: 'REPAIR_IN_PROGRESS' }> {
  const tech = await requireTechnician(userId);
  const booking = await ownAssignedBookingOrThrow(tech.id, bookingId, ['CUSTOMER_APPROVED', 'PARTS_ACQUIRED'] as const);
  await prisma.$transaction(async (tx) => {
    await transitionBooking(tx, booking, 'REPAIR_IN_PROGRESS', { type: 'USER', kind: 'TECHNICIAN', id: userId });
    await tx.booking.update({ where: { id: bookingId }, data: { repairStartedAt: new Date() } });
  });
  return { id: bookingId, state: 'REPAIR_IN_PROGRESS' };
}
```

- [ ] **Step 5: Register the routes** in `technician-jobs.routes.ts` (extend the service import with `partsNeeded, partsAcquired, startRepair`):

```ts
  app.post('/technician/jobs/:id/parts-needed', { preHandler: [requireAuth] }, async (req, reply) => {
    requireTechnicianRole(req);
    return reply.send(await partsNeeded(req.user!.id, (req.params as { id: string }).id));
  });

  app.post('/technician/jobs/:id/parts-acquired', { preHandler: [requireAuth] }, async (req, reply) => {
    requireTechnicianRole(req);
    return reply.send(await partsAcquired(req.user!.id, (req.params as { id: string }).id));
  });

  app.post('/technician/jobs/:id/start-repair', { preHandler: [requireAuth] }, async (req, reply) => {
    requireTechnicianRole(req);
    return reply.send(await startRepair(req.user!.id, (req.params as { id: string }).id));
  });
```

- [ ] **Step 6: Green + no regressions**

Run: `pnpm vitest run tests/technician-jobs tests/bookings` → all pass (the widened helper must not regress arrival/diagnosis/photos tests).

- [ ] **Step 7: Typecheck + commit**

```bash
pnpm tsc --noEmit
git add src/modules/bookings/bookings.state.ts src/modules/technician-jobs tests/technician-jobs/repair-path.test.ts
git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(backend): repair-path transitions — parts-needed/acquired + start-repair"
```

---

### Task 4: Photo window widening + complete-repair (3-photo gate)

**Files:**
- Modify: `apps/backend/src/modules/technician-jobs/technician-jobs.schemas.ts` (REPAIR_KINDS, PHOTO_WINDOW, photoKind union)
- Modify: `apps/backend/src/modules/technician-jobs/technician-jobs.service.ts` (sign/confirm window; `completeRepair`; freeze union)
- Modify: `apps/backend/src/modules/technician-jobs/technician-jobs.routes.ts` (one route)
- Modify: `apps/backend/tests/bookings/helpers.ts` (add `seedRepairPhotos`)
- Test: extend `apps/backend/tests/technician-jobs/repair-path.test.ts`

**Interfaces:**
- Consumes: Task 3's `approvedBooking` fixture + routes; B4b's sign/confirm/`photoKeyPrefix`/`assertStillInState`/`DIAGNOSIS_KINDS`.
- Produces:
  - `REPAIR_KINDS = ['REPAIR_OLD_PART', 'REPAIR_NEW_PACKAGING', 'REPAIR_INSTALLED'] as const` and `PHOTO_WINDOW: Record<PhotoKindValue, 'ARRIVED' | 'REPAIR_IN_PROGRESS'>` exported from the schemas file; `photoKind` accepts all five kinds.
  - `completeRepair(userId, bookingId): Promise<{id: string; state: 'REPAIR_COMPLETE'}>`; route `POST /technician/jobs/:id/complete-repair` (200); `ALLOWED_ACTORS` += `REPAIR_COMPLETE: ['TECHNICIAN']`; sets `repairCompletedAt`.
  - `seedRepairPhotos(bookingId: string)` in `tests/bookings/helpers.ts`.

- [ ] **Step 1: Write the failing tests** — append to `tests/technician-jobs/repair-path.test.ts` (add `seedRepairPhotos` to the helpers import):

```ts
describe('repair photos + complete-repair', () => {
  async function inRepairBooking() {
    const a = await approvedBooking(false);
    await app.inject({ method: 'POST', url: `/technician/jobs/${a.bookingId}/start-repair`, headers: auth(a.t.token) });
    return a;
  }

  it('repair photo sign works in REPAIR_IN_PROGRESS; diagnosis kinds are 409 there (window map)', async () => {
    const { t, bookingId } = await inRepairBooking();
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/photos/sign`, headers: auth(t.token), payload: { kind: 'REPAIR_OLD_PART', contentLengthBytes: 1000 } })).statusCode).toBe(200);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/photos/sign`, headers: auth(t.token), payload: { kind: 'DIAGNOSIS_OVERVIEW', contentLengthBytes: 1000 } })).statusCode).toBe(409);
  });

  it('complete-repair: 422 until all 3 repair slots active; then 200 with photoIds in audit + repairCompletedAt', async () => {
    const { t, bookingId } = await inRepairBooking();
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/complete-repair`, headers: auth(t.token) })).statusCode).toBe(422);
    await seedRepairPhotos(bookingId);
    // a soft-deleted slot must not count: kill one and re-check
    await prisma.photoEvidence.updateMany({ where: { bookingId, kind: 'REPAIR_INSTALLED' }, data: { deletedAt: new Date() } });
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/complete-repair`, headers: auth(t.token) })).statusCode).toBe(422);
    await prisma.photoEvidence.updateMany({ where: { bookingId, kind: 'REPAIR_INSTALLED' }, data: { deletedAt: null } });
    const ok = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/complete-repair`, headers: auth(t.token) });
    expect(ok.statusCode).toBe(200);
    const row = await prisma.booking.findUnique({ where: { id: bookingId } });
    expect(row!.state).toBe('REPAIR_COMPLETE');
    expect(row!.repairCompletedAt).not.toBeNull();
    const audit = await prisma.auditLog.findFirst({ where: { action: 'BOOKING_STATE_CHANGED', metadata: { path: ['to'], equals: 'REPAIR_COMPLETE' } } });
    expect(((audit!.metadata as { photoIds: string[] }).photoIds)).toHaveLength(3);
  });

  it('diagnosis photos do NOT satisfy the repair gate', async () => {
    const { t, bookingId } = await inRepairBooking();
    // approvedBooking already seeded both diagnosis slots — still 422:
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/complete-repair`, headers: auth(t.token) })).statusCode).toBe(422);
  });
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `pnpm vitest run tests/technician-jobs/repair-path.test.ts` → new tests FAIL (400 unknown kind / 404 route).

- [ ] **Step 3: Schemas** — in `technician-jobs.schemas.ts`, replace the `DIAGNOSIS_KINDS`/`photoKind` block with:

```ts
// The named slots each gate requires — single source of truth for request validation, the gates'
// DB filters, AND the per-kind capture window. B6+ additions extend these lists, nothing else.
export const DIAGNOSIS_KINDS = ['DIAGNOSIS_OVERVIEW', 'DIAGNOSIS_CLOSEUP'] as const;
export const REPAIR_KINDS = ['REPAIR_OLD_PART', 'REPAIR_NEW_PACKAGING', 'REPAIR_INSTALLED'] as const;
export const photoKind = z.enum([...DIAGNOSIS_KINDS, ...REPAIR_KINDS]);
export type PhotoKindValue = z.infer<typeof photoKind>;

// Which booking state each kind may be captured in: diagnosis photos during the on-site ARRIVED
// window; repair photos while the repair is running. Sign/confirm gate + freeze on this.
export const PHOTO_WINDOW: Record<PhotoKindValue, 'ARRIVED' | 'REPAIR_IN_PROGRESS'> = {
  DIAGNOSIS_OVERVIEW: 'ARRIVED',
  DIAGNOSIS_CLOSEUP: 'ARRIVED',
  REPAIR_OLD_PART: 'REPAIR_IN_PROGRESS',
  REPAIR_NEW_PACKAGING: 'REPAIR_IN_PROGRESS',
  REPAIR_INSTALLED: 'REPAIR_IN_PROGRESS',
};
```

- [ ] **Step 4: Service** — in `technician-jobs.service.ts`:

(a) extend the schemas import with `REPAIR_KINDS, PHOTO_WINDOW`;
(b) in `signPhotoUpload` and `confirmPhoto`, replace the hardcoded `'ARRIVED'` in `ownAssignedBookingOrThrow(tech.id, bookingId, 'ARRIVED')` with `PHOTO_WINDOW[body.kind]`;
(c) in `confirmPhoto`'s tx, the freeze becomes `await assertStillInState(tx, bookingId, PHOTO_WINDOW[body.kind], 'Photos can only be confirmed during their capture window — the booking has moved on');`
(d) widen `assertStillInState`'s `state` param type to `'ARRIVED' | 'DIAGNOSED' | 'REPAIR_IN_PROGRESS'`;
(e) append:

```ts
/** REPAIR_IN_PROGRESS → REPAIR_COMPLETE. Gated on ALL 3 repair photos (Rule 1: no photos = no
 *  completion = no payment). Booking row locked first so the gate reads the final committed set. */
export async function completeRepair(userId: string, bookingId: string): Promise<{ id: string; state: 'REPAIR_COMPLETE' }> {
  const tech = await requireTechnician(userId);
  const booking = await ownAssignedBookingOrThrow(tech.id, bookingId, 'REPAIR_IN_PROGRESS');
  await prisma.$transaction(async (tx) => {
    await tx.booking.update({ where: { id: bookingId }, data: { repairCompletedAt: new Date() } });
    const activePhotos = await tx.photoEvidence.findMany({
      where: { bookingId, deletedAt: null, kind: { in: [...REPAIR_KINDS] } },
      select: { id: true, kind: true },
    });
    const slots = new Set(activePhotos.map((p) => p.kind));
    if (!REPAIR_KINDS.every((k) => slots.has(k))) {
      throw new UnprocessableError('3 repair photos required (old part removed, new packaging, installed)');
    }
    await transitionBooking(tx, booking, 'REPAIR_COMPLETE', { type: 'USER', kind: 'TECHNICIAN', id: userId }, { photoIds: activePhotos.map((p) => p.id) });
  });
  return { id: bookingId, state: 'REPAIR_COMPLETE' };
}
```

- [ ] **Step 5: Actor entry + route + fixture.** `bookings.state.ts` ALLOWED_ACTORS += `REPAIR_COMPLETE: ['TECHNICIAN'],`. Route (import `completeRepair`):

```ts
  app.post('/technician/jobs/:id/complete-repair', { preHandler: [requireAuth] }, async (req, reply) => {
    requireTechnicianRole(req);
    return reply.send(await completeRepair(req.user!.id, (req.params as { id: string }).id));
  });
```

`tests/bookings/helpers.ts` — append (mirror `seedDiagnosisPhotos`):

```ts
/** B5: complete-repair requires all three repair slots. Seed directly (endpoints have their own tests). */
export async function seedRepairPhotos(bookingId: string) {
  for (const kind of ['REPAIR_OLD_PART', 'REPAIR_NEW_PACKAGING', 'REPAIR_INSTALLED'] as const) {
    await prisma.photoEvidence.create({
      data: { bookingId, kind, r2Key: `jobs/${bookingId}/${kind}-seed.jpg`, capturedAt: new Date() },
    });
  }
}
```

- [ ] **Step 6: Green + no regressions**

Run: `pnpm vitest run tests/technician-jobs tests/bookings` → all pass (photos.test.ts must be untouched and green — the window map preserves ARRIVED for diagnosis kinds).

- [ ] **Step 7: Typecheck + commit**

```bash
pnpm tsc --noEmit
git add src/modules/bookings/bookings.state.ts src/modules/technician-jobs tests/technician-jobs/repair-path.test.ts tests/bookings/helpers.ts
git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(backend): repair-photo window + complete-repair 3-photo gate"
```

---

### Task 5: The completion handshake (keystone #2)

**Files:**
- Create: `apps/backend/src/modules/bookings/completion-code.ts`
- Modify: `apps/backend/src/modules/bookings/bookings.service.ts` (+`requestCompletionOtp`, otpSender singleton)
- Modify: `apps/backend/src/modules/bookings/bookings.routes.ts` (one route)
- Modify: `apps/backend/src/modules/technician-jobs/technician-jobs.service.ts` (+`confirmCompletion`)
- Modify: `apps/backend/src/modules/technician-jobs/technician-jobs.schemas.ts` (+`confirmCompletionBody`)
- Modify: `apps/backend/src/modules/technician-jobs/technician-jobs.routes.ts` (one route)
- Modify: `apps/backend/src/modules/bookings/bookings.state.ts` (+CUSTOMER_CONFIRMED actor)
- Modify: `apps/backend/tests/helpers/redis.ts` (flush `completion:*`)
- Test: `apps/backend/tests/technician-jobs/completion.test.ts`

**Interfaces:**
- Consumes: `mintOtp`/`verifyOtp` (otp-store), `makeOtpSender` (`shared/third-party/otp-sender.js`), `config`, `TooManyRequestsError`/`UnauthorizedError` (`shared/errors.js`), Task 3/4 endpoints for fixtures.
- Produces:
  - `mintCompletionCode(bookingId): Promise<{status:'ok'; code: string} | {status:'throttled'}>`, `verifyCompletionCode(bookingId, code): Promise<'ok' | 'invalid' | 'no-code'>` (completion-code.ts; key `completion:{bookingId}`, TTL 600, 5 attempts, sendLimit `{max: 3, windowSeconds: 900}`).
  - `requestCompletionOtp(userId, id): Promise<{ok: true; devOtp?: string}>`; route `POST /me/bookings/:id/request-completion-otp` (200).
  - `confirmCompletion(userId, bookingId, body): Promise<{id: string; state: 'CUSTOMER_CONFIRMED'}>`; `confirmCompletionBody = z.object({ code: z.string().length(6) }).strict()`; route `POST /technician/jobs/:id/confirm-completion` (200).
  - `ALLOWED_ACTORS` += `CUSTOMER_CONFIRMED: ['TECHNICIAN']`.

- [ ] **Step 1: Write the failing tests** (`apps/backend/tests/technician-jobs/completion.test.ts`)

```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, makeTechnician, seedBookable, seedIssue, seedDiagnosisPhotos, seedRepairPhotos } from '../bookings/helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
function future() { return new Date(Date.now() + 86_400_000).toISOString(); }

/** Drive a booking through BOTH keystones' prerequisites: … → REPAIR_COMPLETE. */
async function repairCompleteBooking() {
  const c = await makeCustomer();
  const f = await seedBookable(c.customerId);
  const t = await makeTechnician(['AC']);
  const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(t.token) });
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/en-route`, headers: auth(t.token) });
  const code = (await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/arrive`, headers: auth(t.token), payload: { lat: 22.31, lng: 73.18 } })).json().arrivalCode;
  await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/confirm-arrival`, headers: auth(c.token), payload: { code } });
  await seedDiagnosisPhotos(booking.id);
  const issue = await seedIssue(f.cat.id);
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id } });
  await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/approve`, headers: auth(c.token) });
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/start-repair`, headers: auth(t.token) });
  await seedRepairPhotos(booking.id);
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/complete-repair`, headers: auth(t.token) });
  return { c, t, bookingId: booking.id as string };
}

describe('completion handshake (keystone #2)', () => {
  it('E2E: customer requests the code, technician enters it → CUSTOMER_CONFIRMED + confirmedAt + audit evidence', async () => {
    const { c, t, bookingId } = await repairCompleteBooking();
    const mint = await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/request-completion-otp`, headers: auth(c.token) });
    expect(mint.statusCode).toBe(200);
    const devOtp = mint.json().devOtp as string;
    expect(devOtp).toMatch(/^\d{6}$/);
    const confirm = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/confirm-completion`, headers: auth(t.token), payload: { code: devOtp } });
    expect(confirm.statusCode).toBe(200);
    const row = await prisma.booking.findUnique({ where: { id: bookingId } });
    expect(row!.state).toBe('CUSTOMER_CONFIRMED');
    expect(row!.confirmedAt).not.toBeNull();
    const audit = await prisma.auditLog.findFirst({ where: { action: 'BOOKING_STATE_CHANGED', metadata: { path: ['to'], equals: 'CUSTOMER_CONFIRMED' } } });
    expect((audit!.metadata as { codeConfirmed: boolean }).codeConfirmed).toBe(true);
    // single-use: replaying the same code → 409 (booking moved on) not a second confirm
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/confirm-completion`, headers: auth(t.token), payload: { code: devOtp } })).statusCode).toBe(409);
  });

  it('mint guards: wrong state 409, foreign customer 404, technician-role 403, throttle 429 after 3', async () => {
    const { c, t, bookingId } = await repairCompleteBooking();
    const fresh = await makeCustomer();
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/request-completion-otp`, headers: auth(fresh.token) })).statusCode).toBe(404);
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/request-completion-otp`, headers: auth(t.token) })).statusCode).toBe(403);
    for (let i = 0; i < 3; i++) expect((await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/request-completion-otp`, headers: auth(c.token) })).statusCode).toBe(200);
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/request-completion-otp`, headers: auth(c.token) })).statusCode).toBe(429);
  });

  it('mint before REPAIR_COMPLETE → 409', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
    expect((await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/request-completion-otp`, headers: auth(c.token) })).statusCode).toBe(409);
  });

  it('verify guards: no code yet 409; wrong code 401; a re-mint replaces the old code', async () => {
    const { c, t, bookingId } = await repairCompleteBooking();
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/confirm-completion`, headers: auth(t.token), payload: { code: '000000' } })).statusCode).toBe(409); // no-code
    const first = (await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/request-completion-otp`, headers: auth(c.token) })).json().devOtp as string;
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/confirm-completion`, headers: auth(t.token), payload: { code: '000000' } })).statusCode).toBe(401); // invalid
    const second = (await app.inject({ method: 'POST', url: `/me/bookings/${bookingId}/request-completion-otp`, headers: auth(c.token) })).json().devOtp as string;
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/confirm-completion`, headers: auth(t.token), payload: { code: first } })).statusCode).toBe(401); // replaced
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/confirm-completion`, headers: auth(t.token), payload: { code: second } })).statusCode).toBe(200);
  });
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `pnpm vitest run tests/technician-jobs/completion.test.ts` → FAIL (404s).

- [ ] **Step 3: The wrapper** (`apps/backend/src/modules/bookings/completion-code.ts`):

```ts
import { mintOtp, verifyOtp } from '../../shared/auth/otp-store.js';

const TTL_SECONDS = 600;
const MAX_ATTEMPTS = 5;
// The mint sends a real SMS in production — throttle per booking so a tapping-happy customer
// (or a client bug) can't flood SMS spend. 3 codes / 15 min covers every honest retry.
const SEND_LIMIT = { max: 3, windowSeconds: 900 };
const key = (bookingId: string) => `completion:${bookingId}`;

export type CompletionMintResult = { status: 'ok'; code: string } | { status: 'throttled' };

/** Mint the single-use 6-digit completion code (10-min TTL). A re-mint replaces any prior code. */
export async function mintCompletionCode(bookingId: string): Promise<CompletionMintResult> {
  return mintOtp(key(bookingId), { ttlSeconds: TTL_SECONDS, sendLimit: SEND_LIMIT });
}

export type CompletionVerifyResult = 'ok' | 'invalid' | 'no-code';

/** Verify (and on success consume) the completion code. 'invalid' covers wrong AND exhausted
 *  (→401 — a fresh code fixes both); 'no-code' covers never-minted AND expired (→409 — the
 *  customer simply requests a new one). Uses the store's 4-arm union directly. */
export async function verifyCompletionCode(bookingId: string, code: string): Promise<CompletionVerifyResult> {
  const r = await verifyOtp(key(bookingId), code, { maxAttempts: MAX_ATTEMPTS });
  switch (r.status) {
    case 'ok':
      return 'ok';
    case 'invalid':
    case 'exhausted':
      return 'invalid';
    case 'no-code':
      return 'no-code';
    default: {
      const unreachable: never = r;
      throw new Error(`Unhandled verifyOtp status: ${JSON.stringify(unreachable)}`);
    }
  }
}
```

- [ ] **Step 4: Customer mint** — `bookings.service.ts`. Add imports: `TooManyRequestsError` (extend the errors import), `config` from `../../shared/config.js`, `makeOtpSender` from `../../shared/third-party/otp-sender.js`, `mintCompletionCode` from `./completion-code.js`. Module-level `const otpSender = makeOtpSender();` (same as auth). Append:

```ts
/** Customer taps "confirm work completed" → mint the completion code and send it to THEIR phone.
 *  The technician can only close the job by hearing this code from the customer (Rule 2). */
export async function requestCompletionOtp(userId: string, id: string): Promise<{ ok: true; devOtp?: string }> {
  const { id: customerId } = await requireCustomer(userId);
  const booking = await prisma.booking.findFirst({
    where: { id, customerId, deletedAt: null },
    include: { customer: { include: { user: true } } },
  });
  if (!booking) throw new NotFoundError('Booking not found');
  if (booking.state !== 'REPAIR_COMPLETE') throw new ConflictError('Booking is not awaiting completion confirmation');
  const r = await mintCompletionCode(id);
  if (r.status === 'throttled') throw new TooManyRequestsError('Too many code requests. Try again later.');
  await otpSender.send(booking.customer.user.phone, r.code);
  return config.NODE_ENV === 'production' ? { ok: true } : { ok: true, devOtp: r.code };
}
```

Route in `bookings.routes.ts` (extend the service import):

```ts
  app.post('/me/bookings/:id/request-completion-otp', { preHandler: [requireAuth] }, async (req, reply) => {
    return reply.send(await requestCompletionOtp(req.user!.id, (req.params as { id: string }).id));
  });
```

- [ ] **Step 5: Technician verify.** `technician-jobs.schemas.ts` append:

```ts
export const confirmCompletionBody = z.object({ code: z.string().length(6) }).strict();
export type ConfirmCompletionBody = z.infer<typeof confirmCompletionBody>;
```

`technician-jobs.service.ts` — add `UnauthorizedError` to the errors import, `verifyCompletionCode` from `../bookings/completion-code.js`, `ConfirmCompletionBody` to the schemas type import. Append:

```ts
/** REPAIR_COMPLETE → CUSTOMER_CONFIRMED (keystone #2). The technician drives the transition but
 *  ONLY with the code minted to the customer's phone — no single-party path (Rule 2).
 *  NOTE: a correct code is consumed BEFORE the tx (redis and Postgres can't share one); if the tx
 *  rolled back the customer just re-requests — fails SAFE, never a false CUSTOMER_CONFIRMED
 *  (same accepted trade-off as the arrival handshake). */
export async function confirmCompletion(userId: string, bookingId: string, body: ConfirmCompletionBody): Promise<{ id: string; state: 'CUSTOMER_CONFIRMED' }> {
  const tech = await requireTechnician(userId);
  const booking = await ownAssignedBookingOrThrow(tech.id, bookingId, 'REPAIR_COMPLETE');
  const result = await verifyCompletionCode(bookingId, body.code);
  if (result === 'no-code') throw new ConflictError('No active code — ask the customer to request one');
  if (result === 'invalid') throw new UnauthorizedError('Invalid or expired completion code');
  await prisma.$transaction(async (tx) => {
    await transitionBooking(tx, booking, 'CUSTOMER_CONFIRMED', { type: 'USER', kind: 'TECHNICIAN', id: userId }, { codeConfirmed: true });
    await tx.booking.update({ where: { id: bookingId }, data: { confirmedAt: new Date() } });
  });
  return { id: bookingId, state: 'CUSTOMER_CONFIRMED' };
}
```

Route in `technician-jobs.routes.ts` (extend imports with `confirmCompletion` + `confirmCompletionBody`):

```ts
  app.post('/technician/jobs/:id/confirm-completion', { preHandler: [requireAuth] }, async (req, reply) => {
    requireTechnicianRole(req);
    const p = confirmCompletionBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.send(await confirmCompletion(req.user!.id, (req.params as { id: string }).id, p.data));
  });
```

- [ ] **Step 6: Actor entry + redis flush.** `bookings.state.ts` ALLOWED_ACTORS += `CUSTOMER_CONFIRMED: ['TECHNICIAN'],` (comment: `// keystone #2 — the customer's code is the second party`). `tests/helpers/redis.ts` becomes:

```ts
/** Remove OTP + arrival + completion keys between tests so each test is isolated.
 *  The `otp:*` scan also covers the store-derived throttle counters (`otp:<phone>:rl`);
 *  `completion:*` covers the completion codes AND their `:rl` throttle counters. */
export async function flushTestRedis() {
  const keys = await redis.keys('otp:*');
  const arrival = await redis.keys('arrival:*');
  const completion = await redis.keys('completion:*');
  const all = [...keys, ...arrival, ...completion];
  if (all.length) await redis.del(...all);
}
```

- [ ] **Step 7: Green + module suites**

Run: `pnpm vitest run tests/technician-jobs/completion.test.ts` → PASS (4 tests). Then `pnpm vitest run tests/technician-jobs tests/bookings tests/shared` → no regressions.

- [ ] **Step 8: Typecheck + commit**

```bash
pnpm tsc --noEmit
git add src/modules/bookings src/modules/technician-jobs tests/technician-jobs/completion.test.ts tests/helpers/redis.ts
git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(backend): completion handshake — keystone #2 (customer OTP, technician entry)"
```

---

### Task 6: Full suite + docs (core-flow correction, decision resolution, STATUS/CHANGELOG)

**Files:**
- Modify: `docs/02-product/core-flow.md` (completion OTP "4-digit" → "6-digit")
- Modify: `docs/decisions/2026-06-16-approve-decline-no-otp-b4a.md` (append resolution)
- Modify: `STATUS.md`, `CHANGELOG.md`

- [ ] **Step 1: Full verification**

Run: `cd apps/backend && set -a && source .env && set +a && pnpm tsc --noEmit && pnpm vitest run`
Expected: clean types; ALL tests pass (246 pre-B5 + the new schema/repair-path/completion tests; note the exact count).
> Known harness quirk: request-heavy files can trip the global 100-req/min limiter in one process. If a 429-based failure appears, re-run the file alone to confirm green — harness artifact, not a product bug.

- [ ] **Step 2: `core-flow.md`** — find the completion-OTP line saying "4-digit" (~line 166) and change to "6-digit", appending the rationale comment `<!-- 6-digit: one shared OTP primitive across auth/arrival/completion (B5 decision) -->`.

- [ ] **Step 3: Decision doc** — append to `docs/decisions/2026-06-16-approve-decline-no-otp-b4a.md`:

```markdown
---

## Resolution (2026-07-12, B5)

The customer confirmation token is NOT bound to approve/decline. B5's completion OTP is the
customer's money-gating confirmation — payment cannot unlock without a code that only the
customer's phone received. A second OTP at approve would double per-booking friction for a
pre-payment action that already has actor separation and frozen-cart audit evidence.
**B6 (the charge) re-evaluates binding a token at the charge step**, per this decision's
original framing ("the charge-gating action").
```

- [ ] **Step 4: `STATUS.md`** — Active task → B5 done on branch (all repair-path transitions + 3-photo gate + completion handshake; both keystones now end-to-end; test count); Phase line: B5 done on branch; Next targets → PR/merge B5, then **B6 (payment)** — Razorpay charge at CUSTOMER_CONFIRMED, re-evaluate the confirmation token there; retire the OTP-store Lua backlog item (shipped in this slice); note the B4a-token decision resolution.

- [ ] **Step 5: `CHANGELOG.md`** — new `## 2026-07-12 — Booking slice B5` entry (or extend the date header): repair-path transitions (parts detour + direct, empty-cart 422), PHOTO_WINDOW map + 3-repair-photo gate on REPAIR_COMPLETE, completion OTP handshake (mint to customer / technician entry, 6-digit, throttled 3-per-900s, single-use, 4-arm mapping), milestone columns, atomic Lua mint (backlog retired), core-flow + decision-doc updates, test count.

- [ ] **Step 6: Commit**

```bash
git add docs/02-product/core-flow.md docs/decisions/2026-06-16-approve-decline-no-otp-b4a.md STATUS.md CHANGELOG.md
git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "docs: status/changelog + core-flow and decision updates for booking B5"
```

---

## Self-Review

**Spec coverage:** full path incl. parts (T3) ✓; empty-cart 422 (T3) ✓; repairStartedAt/repairCompletedAt/confirmedAt (T1, set in T3/T4/T5) ✓; 3-photo gate with row-lock-first + photoIds evidence (T4) ✓; PHOTO_WINDOW + kinds consts + Zod union (T4) ✓; diagnosis kinds still ARRIVED-only (T4 test) ✓; completion wrapper key/TTL/attempts/sendLimit (T5) ✓; mint endpoint owner-404/409/429/devOtp/otpSender (T5) ✓; verify 4-arm mapping → 401/409, single-use, re-mint replaces (T5) ✓; actor entries for all five to-states (T3/T4/T5) ✓; Rule 2 mirror documented in code comments (T5) ✓; Lua atomic mint, behavior-preserving (T2) ✓; flushTestRedis completion:* (T5) ✓; core-flow 4→6 digit + decision resolution (T6) ✓; E2E through both keystones (T5 test 1 — its fixture drives CREATED→…→CUSTOMER_CONFIRMED) ✓. No gaps.

**Placeholder scan:** every code step carries complete code; commands have expected outputs. Two flagged degrees of freedom are explicit and bounded: T1's seed-idiom fallback (copy from neighbors) and T3's cart-seed simplification note (resolve the `.catch` dance to one working create per the actual schema). ✓

**Type consistency:** `ownAssignedBookingOrThrow` widened once (T3) and used with `'REPAIR_IN_PROGRESS'`/`'REPAIR_COMPLETE'`/array in T4/T5; `REPAIR_KINDS`/`PHOTO_WINDOW`/`PhotoKindValue` defined T4 and consumed there only; `mintCompletionCode`/`verifyCompletionCode` names match T5's service usage; `confirmCompletionBody`/`ConfirmCompletionBody` consistent; `seedRepairPhotos` defined T4, consumed T5; `assertStillInState` union gains `'REPAIR_IN_PROGRESS'` (T4d) before its T4c usage. ✓
