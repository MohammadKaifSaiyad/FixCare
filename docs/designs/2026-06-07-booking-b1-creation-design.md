# Design — Booking Module, Slice B1 (creation + price snapshot + state skeleton)

_Date: 2026-06-07 · Status: approved (pending spec review) · Scope: booking creation + point-in-time price snapshot + the guarded state-machine skeleton, in `apps/backend`_

## Context

The first slice of the **booking module** — the core business object the platform exists to
coordinate. Per `docs/02-product/core-flow.md` the full job lifecycle is a 14-state machine
(`CREATED → … → CLOSED` + cancel/decline/dispute branches) spanning dispatch, two keystone
handshakes, repair photos, payment, and disputes. That is far too large for one design, so the
booking module is **decomposed into sub-slices** (see "Decomposition" below); this spec covers
**B1 only**: a customer creates a booking for a catalog service at one of their addresses, the
booking captures a **price snapshot** locked at creation, and it enters a guarded state machine
that every later slice extends.

Grounded in: `docs/02-product/core-flow.md` (Phase A + the State Machine Reference),
`docs/02-product/pricing-model.md` (visit fee per zone, geofenced labor, tiers), the merged
**catalog** module (`Zone.visitFeePaise`, `ServicePrice (serviceId,zoneId)→laborPaise`, `Service.tier`),
the merged **addresses** module (`resolvePincode` → live zone, `Address` owner-scoping), the
`/me/*` implicit-ownership pattern (profiles/addresses), `audit-logged-mutation` conventions, and
the **locked requirement** from the addresses fraud review: *booking MUST snapshot zone + prices at
creation and never re-resolve later* (the [[booking-zone-price-snapshot]] memory).

## Decomposition of the booking module (each = own design → plan → PR)

| # | Sub-slice | Covers | Depends on |
|---|---|---|---|
| **B1** (this) | creation + price/zone snapshot + state skeleton | `Booking` entity; `POST /me/bookings`; snapshot zone+visitFee+labor+tier; guarded state machine; create + customer-cancel; read endpoints | catalog, addresses, audit |
| B2 | dispatch / technician matching | `DISPATCHED→ACCEPTED`/reject, matching algo, 30s accept timer (BullMQ) | B1 + technician profiles |
| B3 | arrival handshake (Keystone #1) | GPS + customer QR/code → `ARRIVED`, lock visit fee | B1/B2 + keystone-handshake |
| B4 | diagnosis + parts cart + approval | 2 photos, structured issue, parts cart, `DIAGNOSED→CUSTOMER_APPROVED`/`DECLINED` | B3 + parts catalog |
| B5 | repair + completion handshake (Keystone #2) | 3 photos + completion OTP → `CUSTOMER_CONFIRMED`, unlock payment | B4 + keystone-handshake |
| B6 | payment + ledger + settlement split | `PAYMENT_RECEIVED→CLOSED`, Razorpay Route split | B5 + **Razorpay approval (blocked)** |
| B7 | disputes | `DISPUTED` branch + resolution | B5/B6 |

B1 is the foundation; it is fully buildable now (no blocked vendor deps) and locks the snapshot.

## Decisions locked (during brainstorming)

1. **Snapshot at creation = zone + visit fee + labor price + tier** (`zoneId`, `zoneName`,
   `serviceName`, `visitFeePaise`, `laborPaise`, `laborTier`). Parts are NOT known at creation
   (they come at diagnosis, B4) — parts snapshot deferred to B4. Tier-based dynamic pricing stays
   deferred (catalog design) — `laborTier` is stored as a label only, no surcharge math.
2. **Unserviceable/unpriced → reject at creation (422).** Resolve the address pincode→zone live at
   booking time (authoritative). No zone → 422 "outside service area"; zone but no `ServicePrice`
   for (service,zone) → 422 "service unavailable in your area". **Every `CREATED` booking has a
   complete, locked price snapshot** — no half-priced bookings.
3. **State machine = a central `ALLOWED_TRANSITIONS` table + one guarded `transitionBooking`.** The
   full edge graph is declared now; later slices add the *endpoints/actors* that drive each edge.
4. **Full `BookingState` enum declared now** (stable schema); B1 *wires* only `CREATED` (create) and
   `CANCELLED_BY_CUSTOMER` (customer cancel from `CREATED`).
5. **UUID `id` + human `bookingNumber`** (`FC-` + 6 base32, `@unique`) for support/customer reference.
6. **CUSTOMER-only, owner-scoped** in B1 (another customer's id → 404, no IDOR). Technician/admin
   read scopes come in later slices.
7. **No money moves in B1.** The snapshot is *recorded*; no visit-fee authorization/charge happens
   yet (that's B3/B6). B1 is pure booking-record + state.
8. **Every transition writes `BOOKING_STATE_CHANGED` to AuditLog in the same transaction** (Golden
   Rule 5): `{ bookingId, from, to }` (+ an `evidence` ref in later handshake slices). No PII.

## Schema

```prisma
model Booking {
  id            String   @id @default(uuid())
  bookingNumber String   @unique               // "FC-7K3M2Q"
  customerId    String
  customer      Customer @relation(fields: [customerId], references: [id])
  addressId     String
  address       Address  @relation(fields: [addressId], references: [id])
  serviceId     String
  service       Service  @relation(fields: [serviceId], references: [id])

  // ── PRICE SNAPSHOT (locked at creation; never re-resolved) ──
  zoneId        String                          // resolved from the address pincode at creation
  zoneName      String                          // denormalized — display/audit stable
  serviceName   String                          // denormalized snapshot
  visitFeePaise Int                             // from the zone, at creation (integer paise)
  laborPaise    Int                             // ServicePrice(service,zone), at creation
  laborTier     LaborTier                       // T1/T2/T3 label snapshot

  scheduledSlot DateTime                        // requested time slot (future)
  state         BookingState @default(CREATED)
  createdAt     DateTime     @default(now())
  updatedAt     DateTime     @updatedAt
  deletedAt     DateTime?
  @@index([customerId])
  @@index([state])
}

enum BookingState {
  CREATED  DISPATCHED  ACCEPTED  EN_ROUTE  ARRIVED
  DIAGNOSED  CUSTOMER_APPROVED  PARTS_REQUESTED  PARTS_ACQUIRED
  REPAIR_IN_PROGRESS  REPAIR_COMPLETE  CUSTOMER_CONFIRMED
  PAYMENT_RECEIVED  CLOSED
  CANCELLED_BY_CUSTOMER  CANCELLED_BY_TECHNICIAN  DECLINED_BY_CUSTOMER  DISPUTED
}
```
Back-relations: `Customer.bookings Booking[]`, `Address.bookings Booking[]`, `Service.bookings Booking[]`.
`AuditAction` gains `BOOKING_STATE_CHANGED` (enum migration, like prior slices). Money is integer
paise. `zoneId`/`zoneName`/`serviceName` denormalized so the snapshot is self-contained even if the
zone/service is later renamed or soft-deleted.

## State machine (`bookings.state.ts`)

```ts
const ALLOWED_TRANSITIONS: Record<BookingState, BookingState[]> = {
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
  CLOSED: [], CANCELLED_BY_CUSTOMER: [], CANCELLED_BY_TECHNICIAN: [], DECLINED_BY_CUSTOMER: [],
};
```
Cancel edges exist only **before ARRIVED** (per core-flow — once the arrival handshake locks the
visit fee, exit is decline/dispute, not free cancel).

**Actor** is `{ type: ActorType; id: string }` (`ActorType` from the existing AuditLog enum:
`USER` | `ADMIN` | `SYSTEM`) — a stable contract later slices reuse. **Actor permissions** — a map
of which actor may drive each `to`-transition. B1 registers only:
`CANCELLED_BY_CUSTOMER ← the owning customer (USER)`. Later slices add `DISPATCHED ← SYSTEM`,
`ACCEPTED ← assigned technician (USER)`, etc. The create-time audit (`null→CREATED`) is written with
`actorType:'USER'`, `actorId:` the customer's userId.

**`transitionBooking(tx, booking, to, actor, evidence?)`** (runs inside a caller-opened `$transaction`):
1. assert `to ∈ ALLOWED_TRANSITIONS[booking.state]` → else `ConflictError` (409, illegal transition).
2. assert `actor` is permitted for this transition → else `ForbiddenError` (403).
3. `tx.booking.update({ where:{id}, data:{ state: to } })`.
4. `tx.auditLog.create({ action:'BOOKING_STATE_CHANGED', actorType, actorId, metadata:{ bookingId, from, to } })`.

The from-state check runs against the current row inside the transaction → concurrent
double-transition is naturally guarded. This engine is the seam B2–B7 extend without modifying it.

## Endpoints — `src/modules/bookings/` (requireAuth + CUSTOMER-only; owner-scoped)

```
POST   /me/bookings              create → CREATED (full price snapshot)
GET    /me/bookings              list own (newest first; deletedAt:null)
GET    /me/bookings/:id          own only (else 404 — no IDOR)
POST   /me/bookings/:id/cancel   own only; CREATED → CANCELLED_BY_CUSTOMER (via transitionBooking)
```

### Creation flow (`POST /me/bookings`, body `{ addressId, serviceId, scheduledSlot }`)
1. Resolve caller's `Customer` row (CUSTOMER-only → else 403).
2. Load the address scoped to this customer (`addressId` + `customerId`, `deletedAt:null`) → else **404**.
3. Load the `Service` (`status:'ACTIVE'`, `deletedAt:null`) → else **404**.
4. Resolve the address pincode → zone **live** via `resolvePincode`. Unserviceable → **422**.
5. Look up `ServicePrice` for (serviceId, zoneId). No row → **422** "service unavailable in your area".
6. Build the snapshot: `zoneId, zoneName, serviceName, visitFeePaise (zone), laborPaise (ServicePrice), laborTier (service.tier)`.
7. Generate a unique `bookingNumber` (retry on the rare P2002 collision).
8. In one `$transaction`: create the booking (`CREATED`) + write `BOOKING_STATE_CHANGED` (`from:null → to:CREATED`). Return **201** + DTO.

`scheduledSlot`: valid datetime, must be in the future (Zod) → else 400. V1 has no
availability/capacity engine (a dispatch-era concern).

### DTO (never raw Prisma)
`{ id, bookingNumber, state, scheduledSlot, visitFeePaise, laborPaise, laborTier,
   service:{ id, name }, zone:{ id, name }, address:{ id, label, line1, pincode } }`.
No internal-only fields (customerId, deletedAt) leaked.

### Error contract (global handler, no internal-detail leak)
400 (Zod / past slot), 401 (no token), 403 (non-CUSTOMER), 404 (address/service/booking
not-found-or-not-owned), 409 (`ConflictError` — illegal transition, e.g. cancel a non-CREATED
booking), 422 (unserviceable / unpriced).

## Module structure

`src/modules/bookings/`: `bookings.routes.ts`, `bookings.service.ts` (createBooking, listBookings,
getBooking, cancelBooking), `bookings.state.ts` (ALLOWED_TRANSITIONS + actor map + transitionBooking),
`bookings.schemas.ts` (createBookingBody), `bookings.types.ts` (BookingDto + toBookingDto),
`bookings.number.ts` (generateBookingNumber). Registered in `buildApp()` after addresses. Tests in
`tests/bookings/`. Add `"Booking"` to the test TRUNCATE list.

## Testing (TDD, `app.inject()`, `fixcare_test` + test Redis)

- **Snapshot integrity (THE fraud-defense assertion):** create a booking → row carries the right
  `visitFeePaise`/`laborPaise`/`laborTier`/`zoneName`/`serviceName` from catalog; **then mutate the
  catalog `ServicePrice` + the zone `visitFeePaise` + the pincode→zone mapping → re-read the booking
  → snapshot UNCHANGED.** `BOOKING_STATE_CHANGED` (null→CREATED) audit written in-tx.
- **Creation guards:** unserviceable address → 422; serviceable-but-unpriced service → 422; another
  customer's addressId → 404; soft-deleted/unknown service → 404; past `scheduledSlot` → 400;
  non-CUSTOMER (admin/technician) → 403; no token → 401.
- **Ownership:** list returns only own; `GET :id` of another customer's booking → 404.
- **State machine:** cancel from `CREATED` → `CANCELLED_BY_CUSTOMER` (+ audit); cancel a non-CREATED
  booking (force-set state in DB) → 409; cancel another customer's booking → 404; illegal direct
  transition rejected.
- **bookingNumber:** unique + `FC-` format; two bookings differ.
Mint tokens via `signAccessToken` + seeded customers/admins (as catalog/address tests do); seed a
zone + service + ServicePrice + pincode mapping + a customer address for the happy path.

## Out of scope (deferred)

B2 dispatch/matching + accept timer; B3 arrival handshake (GPS+QR, lock visit fee); B4 diagnosis +
parts cart + parts snapshot; B5 completion handshake (OTP + 3 photos); B6 payment/ledger/settlement
(needs Razorpay approval); B7 disputes. No money authorization/charge in B1. No slot
availability/capacity engine. Technician/admin booking views.

## Next step

writing-plans for **B1**. On branch `feature/booking-module` (already cut off `main`).
