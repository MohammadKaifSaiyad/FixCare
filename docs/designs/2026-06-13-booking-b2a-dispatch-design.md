# Design — Booking B2a (broadcast dispatch + accept + actor-permissions)

_Date: 2026-06-13 · Status: approved (pending spec review) · Scope: open a booking to the eligible technician pool, atomic first-to-accept claim, and per-transition actor-permission enforcement, in `apps/backend`_

## Context

Second slice of the booking module (after B1 creation + snapshot + state skeleton). The booking
module was decomposed into 7 sub-slices; the original **B2 "dispatch / technician matching"** is
itself too big and depends on subsystems that do not exist yet, so it is **further decomposed**:

| Sub-slice | What | Buildable now? |
|---|---|---|
| **B2a** (this) | broadcast dispatch + atomic accept/skip + actor-permission map | ✅ yes |
| B2b | 30-sec accept timer + BullMQ queue/worker infrastructure | deferred (no queue infra yet) |
| B2c | the weighted matching algorithm `rating × proximity × current_load × cash_compliance` | deferred (needs trust-score + technician location + cash/ledger models — none exist) |

**Model change (important):** `core-flow.md` describes a **push** model (the system picks one
technician who gets a 30-sec accept/reject). During brainstorming the founder chose the **broadcast /
first-to-accept** model instead: a booking opens to *all eligible technicians*, and the first to
accept atomically wins. This slice **updates `core-flow.md`** to match and records the
push→broadcast decision (+ the deferral of the weighted algorithm) in `docs/decisions/`.

Grounded in: `docs/02-product/core-flow.md` (Phase A; "what technician sees" = address + masked
customer phone), B1's `Booking` + `transitionBooking` (the optimistic-locked guarded state machine),
the merged catalog (`Service`, `ServiceSkill`), `Technician` (`skills`, `status`), the
`/me/*` ownership pattern, and the [[booking-zone-price-snapshot]] memory (B1 deferred
actor-permission enforcement to "the slice that exposes each transition" — that's now).

## Decisions locked (during brainstorming)

1. **Broadcast / first-to-accept**, not push. A booking opens to all eligible technicians; the first
   to accept atomically claims it. No system pre-selection, no per-tech assignment, no weighted score.
2. **Auto-open at creation.** `POST /me/bookings` creates in `CREATED` then immediately
   transitions to `DISPATCHED` (opens to the pool) in the same flow, driven by a `SYSTEM` actor —
   so the audit trail reads `null→CREATED→DISPATCHED`. No separate dispatch endpoint.
3. **Eligible technician = `status: VERIFIED` AND the booking's `service.requiredSkill` ∈
   `technician.skills[]`.** Adds `Service.requiredSkill: ServiceSkill` (the link that makes skill
   matching computable). **Zone-coverage filtering deferred** (all VERIFIED techs serve both V1
   zones; Vadodara + Padra are adjacent).
4. **Accept = atomic claim.** First technician to accept: `DISPATCHED→ACCEPTED` + set
   `Booking.technicianId`, via the B1 optimistic-lock `transitionBooking` (`where {id, state:
   DISPATCHED}`). A concurrent second accept gets `count===0` → 409 "already taken".
5. **Skip = per-technician hide.** `JobSkip { technicianId, bookingId }` (unique pair); a skipped
   job drops out of *that* tech's available list; booking state unchanged, others still see it.
6. **Actor-permission enforcement** (the deferred B1 item): a `ALLOWED_ACTORS` map in
   `transitionBooking`, checked after legality and before the optimistic-lock write. Role-gate in
   the state machine; identity/ownership-gate in the service (same split as B1).
7. **Masking is directional** (Golden Rule 7 + core-flow): the **technician** view of a job masks
   the *customer* phone and omits the customer name (shows only address + masked phone). The
   **customer** view of an accepted booking shows the *technician's* real name + masked technician
   phone + QR-badge id (per core-flow "what customer sees"). Each side sees only what it needs;
   neither sees the other's raw phone.
8. **No money moves in B2a.** Visit-fee UPI authorization is a later (payment) slice.

## Schema changes

```prisma
model Booking {
  ...
  technicianId  String?       // null while open in the pool; set atomically on ACCEPTED
  technician    Technician?   @relation(fields: [technicianId], references: [id])
  jobSkips      JobSkip[]
  ...
}

model Service {
  ...
  requiredSkill ServiceSkill  // which technician skill this service needs
  ...
}

model Technician {
  ...
  bookings      Booking[]     // back-relation
  jobSkips      JobSkip[]
}

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

**`Service.requiredSkill` migration (non-null on an existing table):** the column is `NOT NULL`,
but seeded/existing `Service` rows have no value. Migration approach: add the column with a
**transitional default** to backfill existing rows (e.g. `@default(APPLIANCE)` or a data-migration
mapping category→skill), then the catalog seed sets `requiredSkill` explicitly going forward. Flag
for the migration reviewer; do NOT add a permanent schema default if the intent is that every new
service must specify a skill — prefer a one-off backfill in the migration SQL + drop the default.
(Catalog `createService` will need a `requiredSkill` field in its body — a small catalog-schema
touch in this slice.)

`Booking.technicianId` FK is nullable, `ON DELETE RESTRICT` (consistent with the other booking FKs).

## State machine + actor-permissions (`bookings.state.ts`)

`CREATED→DISPATCHED` and `DISPATCHED→ACCEPTED` are already legal edges in `ALLOWED_TRANSITIONS`
(declared in B1). B2a wires them and adds the actor gate.

```ts
// In-memory permission concept (NOT the DB ActorType enum). Derived from the caller's user.role.
export type ActorKind = 'CUSTOMER' | 'TECHNICIAN' | 'ADMIN' | 'SYSTEM';

// Which actor kind may drive a transition INTO a given state. Keyed by to-state (unique per action
// in B2a's wired set). Transitions not in the map have no role restriction yet (later slices add them).
const ALLOWED_ACTORS: Partial<Record<BookingState, ActorKind[]>> = {
  DISPATCHED:            ['SYSTEM'],     // auto-open at creation
  ACCEPTED:              ['TECHNICIAN'], // a technician claims it
  CANCELLED_BY_CUSTOMER: ['CUSTOMER'],   // the owning customer (identity checked in service)
};
```

`BookingActor` gains a `kind: ActorKind` (the existing `type: ActorType` stays for the audit row;
`ActorType` has only USER/ADMIN/SYSTEM, which can't distinguish customer from technician). `kind` is
derived at the service layer from `request.user.role` (`UserRole` = CUSTOMER|TECHNICIAN|MERCHANT|
ADMIN) or set to `SYSTEM` for the auto-open.

**`transitionBooking(tx, booking, to, actor)`** now gates in order:
1. **legality** — `to ∈ ALLOWED_TRANSITIONS[from]` → else `ConflictError` (409).
2. **actor-role** — if `ALLOWED_ACTORS[to]` is defined, `actor.kind` must be in it → else
   `ForbiddenError` (403).
3. **optimistic lock** — `updateMany({ where: { id, state: from }, data: { state: to } })`;
   `count===0` → `ConflictError` (409) (the B1 concurrency fix).
4. **audit** — `BOOKING_STATE_CHANGED` `{ bookingId, from, to }` in the same tx (`actorType` = the
   DB enum: USER for customer/technician, SYSTEM for auto-open).

The role gate answers "can a TECHNICIAN do ACCEPTED *at all*"; **which** technician/customer
(identity/ownership) is checked in the service layer (cancel verifies `booking.customerId`; accept
verifies the caller is VERIFIED + skilled). **Default-deny:** a to-state present in `ALLOWED_ACTORS`
rejects any actor kind not listed (so MERCHANT, and CUSTOMER attempting ACCEPTED, are rejected 403);
a to-state absent from the map has no role restriction yet and is gated only by legality +
the service layer (later slices add their entries as they wire those transitions).

## Endpoints

### Customer (existing, B1) — behavior change
- `POST /me/bookings` — now also auto-opens to `DISPATCHED` (SYSTEM) in the create flow.
- `GET /me/bookings/:id` — once `ACCEPTED`, includes the assigned technician: name + **masked phone**
  + QR-badge id (per core-flow "what customer sees").

### Technician — new module `src/modules/technician-jobs/` (requireAuth + TECHNICIAN-only)
```
GET  /technician/jobs/available     eligible + still-open jobs (DISPATCHED, technicianId null)
GET  /technician/jobs/mine          jobs this technician has accepted
POST /technician/jobs/:id/accept    atomic claim → ACCEPTED (sets technicianId)
POST /technician/jobs/:id/skip      per-technician dismiss (hide from my available list)
```

- **`requireTechnician(userId)`** resolves the caller's Technician row; TECHNICIAN role + `status:
  VERIFIED` → else `ForbiddenError` (403). An unverified technician sees no jobs and cannot accept.
- **`GET /available`**: `state: DISPATCHED`, `technicianId: null`, `deletedAt: null`,
  `service.requiredSkill ∈ technician.skills[]`, and `bookingId ∉` this tech's `JobSkip`. Ordered
  newest-first. Returns `TechnicianJobDto` (masked — see below).
- **`POST /:id/accept`**: load booking; not `DISPATCHED` or already has `technicianId` → 409;
  verify `service.requiredSkill ∈ technician.skills[]` → else 403; in one tx
  `transitionBooking(..., 'ACCEPTED', { kind:'TECHNICIAN', ... })` **and** set `technicianId`. The
  optimistic lock guarantees exactly one winner; concurrent loser → 409 "already taken".
- **`POST /:id/skip`**: upsert a `JobSkip` (idempotent on the unique pair); booking unchanged; 204.
- **`GET /mine`**: bookings where `technicianId =` this technician (their accepted jobs).

### `TechnicianJobDto` (masked customer view)
`{ id, bookingNumber, state, scheduledSlot, service:{ name, requiredSkill }, zone:{ name },
   visitFeePaise, laborPaise, address:{ line1, line2, landmark, pincode },
   customer:{ maskedPhone } }`. **No** customer name, **no** raw phone (mask to e.g. `••••••1234`),
   no internal ids beyond what's needed. Address is shown (needed to do the job).

### Error contract
400 (Zod), 401 (no token), 403 (non-technician / unverified / unskilled / wrong actor role),
404 (job/booking not found), 409 (already taken / illegal transition).

## Module structure

- New `src/modules/technician-jobs/`: `technician-jobs.routes.ts`, `.service.ts`
  (`listAvailableJobs`, `listMyJobs`, `acceptJob`, `skipJob`, `requireTechnician`),
  `.types.ts` (`TechnicianJobDto` + masker), `.schemas.ts`. Registered after bookings in `buildApp()`.
- Extend `bookings.state.ts` (`ActorKind`, `ALLOWED_ACTORS`, 3rd gate, `BookingActor.kind`);
  `bookings.service.ts` `createBooking` auto-opens to DISPATCHED; the customer DTO shows the
  assigned technician.
- Schema migration: `Booking.technicianId`, `Service.requiredSkill` (+ backfill), `JobSkip`,
  back-relations. Catalog `createService` body gains `requiredSkill`. Add `JobSkip` to the test
  TRUNCATE list.
- A shared phone-masking helper (if none exists) under `shared/utils/`.

## Testing (TDD, `app.inject()`, `fixcare_test` + test Redis)

- **State machine + actors:** `CREATED→DISPATCHED` ok for SYSTEM, 403 for CUSTOMER/TECHNICIAN;
  `DISPATCHED→ACCEPTED` ok for TECHNICIAN, 403 for CUSTOMER; `ACCEPTED` only from `DISPATCHED` (409).
- **Auto-open:** `POST /me/bookings` → ends in `DISPATCHED`; audit trail `null→CREATED` +
  `CREATED→DISPATCHED` (SYSTEM).
- **Eligibility:** available list includes a VERIFIED tech with the matching skill; excludes
  wrong-skill / non-VERIFIED (403 on the endpoint) / already-accepted / skipped; an unverified tech → 403.
- **Atomic accept race:** two technicians accept the same job concurrently → exactly one 200 (with
  `technicianId` set), the other 409; exactly one `BOOKING_STATE_CHANGED→ACCEPTED` audit.
- **Unskilled accept → 403; accept a non-DISPATCHED / already-taken job → 409.**
- **Skip:** skipped job disappears from that tech's available list, still visible to another tech;
  skip is idempotent.
- **Masked view:** available + customer-facing DTOs contain no raw customer phone/name; assert mask.
- **Customer view:** after accept, `GET /me/bookings/:id` shows technician name + masked phone + QR id.
- **No PII in audit** (bookingId/from/to only).
Seed: zone + service (with `requiredSkill`) + price + pincode + customer address (reuse B1's
`seedBookable`, extended with `requiredSkill`); mint technician tokens with VERIFIED + skills.

## Docs to update (part of this slice)

- `docs/02-product/core-flow.md` Phase A: push → **broadcast / first-to-accept** wording.
- `docs/decisions/2026-06-13-dispatch-broadcast-model.md`: record the push→broadcast change + that the
  weighted `rating×proximity×load×cash` algorithm (B2c) and the 30-sec accept timer (B2b) are deferred.

## Out of scope (deferred)

B2b (30-sec accept timer + BullMQ infra — a job stays open until accepted; no auto-expire/re-broadcast);
B2c (weighted matching algorithm — needs trust-score + technician location + cash model); technician
zone-coverage filtering; visit-fee UPI authorization (payment slice); the cash-debt-limit and
self-dealing fraud locks (need the cash/ledger model — **deferred, not dropped**); technician
location/ETA. No money moves in B2a.

## Next step

writing-plans for **B2a**. On branch `feature/booking-dispatch` (already cut off `main`).
