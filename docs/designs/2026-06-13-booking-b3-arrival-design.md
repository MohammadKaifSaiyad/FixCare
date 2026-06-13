# Design — Booking B3 (arrival handshake, keystone #1)

_Date: 2026-06-13 · Status: approved (pending spec review) · Scope: the two-sided, evidence-gated arrival handshake that locks the visit-fee milestone, in `apps/backend`_

## Context

Third booking slice (after B1 creation+snapshot, B2a broadcast dispatch). This implements **Keystone
Interaction #1** — the arrival handshake — per the `keystone-handshake` skill and `core-flow.md`
Phase B. It is the project's first **two-sided, money-gating** interaction: per Golden Rules 1–2,
*money never moves without evidence* and *no single party confirms a transaction alone*. The booking
reaches `ARRIVED` only when **both** the technician (GPS-stamped arrive-tap) and the customer
(entering the technician-shown code) have acted; neither alone suffices.

Grounded in: the `keystone-handshake` skill (GPS-validated "Arrived" + customer QR/code → lock visit
fee, audit in the same transaction, no PII/coords in logs); `core-flow.md` Phase B; `fraud-defenses.md`
#11 "Visitation Without Arrival" (GPS validation within X m of customer location → block visit-fee
claim); B1's `Booking` snapshot + B1/B2a's guarded `transitionBooking` (legality → **default-deny
actor gate** → optimistic lock → audit); the auth OTP idiom (`generateOtp`/`hashOtp` +
Redis `{hash, attempts}` single-use, attempt-capped — `src/shared/auth/otp.ts`, `auth.service.ts`);
B2a's `technician-jobs` module + `requireTechnician`; the addresses `Address.lat/lng` (optional).

## Decisions locked (during brainstorming)

1. **Server-generated, booking-scoped arrival code** (not a static technician badge). The technician's
   arrive-tap mints a single-use 6-digit code held **hashed in Redis** (short TTL); the technician
   shows it; the customer enters it. The code only exists because the tech tapped Arrived; it only
   does anything when the customer enters it → genuine two-sided proof. Never stored raw, never in DB.
2. **GPS gate = validate-if-present, record-only if absent.** The arrive-tap always carries the
   technician's GPS, which is **recorded** on the booking. If the customer address has `lat/lng`:
   compute haversine distance and **reject (422) if > 200 m**. If the address has no coordinates
   (common — PostGIS deferred): record the GPS as evidence, no distance gate. The hard geofence
   becomes universal once addresses carry coordinates.
3. **Three transitions wired** (all already legal edges): `ACCEPTED → EN_ROUTE` (tech "on my way"),
   then the **arrive-tap happens while `EN_ROUTE` and does NOT change state** (it records GPS + mints
   the code), then `EN_ROUTE → ARRIVED` (customer enters the code).
4. **"Locked" = a milestone, no money yet.** `visitFeeLockedAt` (timestamp) is set when `ARRIVED` is
   reached; the payment slice (B6) will require it before any visit-fee claim. No charge/hold in B3.
5. **Evidence on the Booking row + audit metadata** (no new table): `arrivalLat`, `arrivalLng`,
   `arrivedAt`, `visitFeeLockedAt`. The `ARRIVED` transition's `BOOKING_STATE_CHANGED` audit records
   `{ gpsRecorded, withinGeofence: boolean|null, codeConfirmed: true }` — **no raw coordinates**
   (Golden Rule 7).
6. **Actor-permission entries** (mandatory under B2a's default-deny): `EN_ROUTE → ['TECHNICIAN']`,
   `ARRIVED → ['CUSTOMER']`. Role-gate in `transitionBooking`; the **assigned-technician** identity
   check + customer ownership in the service layer.

## Schema (additive migration)

```prisma
model Booking {
  ...
  arrivalLat       Float?      // technician GPS latitude at the arrive-tap (evidence; always recorded)
  arrivalLng       Float?      // technician GPS longitude at the arrive-tap
  arrivedAt        DateTime?   // set when ARRIVED is reached
  visitFeeLockedAt DateTime?   // the visit-fee milestone — set at ARRIVED; B6 requires it before any claim
  ...
}
```
All nullable → no backfill. No new enum, no new table. The arrival **code** is NOT a column — it
lives hashed in Redis (`{ hash, attempts }`, `EX` TTL), single-use, mirroring the auth OTP store.

## State machine + actor-permissions (`bookings.state.ts`)

`ALLOWED_TRANSITIONS` already has `ACCEPTED→EN_ROUTE→ARRIVED`. B3 wires them and adds to
`ALLOWED_ACTORS`:
```ts
  EN_ROUTE: ['TECHNICIAN'],   // technician taps "on my way"
  ARRIVED:  ['CUSTOMER'],     // customer enters the code → completes the handshake
```
(Default-deny from B2a means these entries are required for the routes to work — a forgotten entry
would fail loud with 403, which is the intended safety for a keystone.)

## Handshake mechanics (the two-sided gate — Golden Rules 1–2)

### Step A — `POST /technician/jobs/:id/arrive` { lat, lng } (assigned TECHNICIAN)
1. `requireTechnician` (VERIFIED). Load booking (include `address`); must be `EN_ROUTE` **and**
   `booking.technicianId === tech.id` → else 409 (wrong state) / 403 (not your job).
2. **GPS gate:** if `address.lat != null && address.lng != null` → `haversineMeters(addr, tap)`;
   `> 200` → **422** "You are too far from the customer location". If absent → skip the distance check.
   `withinGeofence = (coords present) ? (dist ≤ 200) : null`.
3. Record `arrivalLat/arrivalLng` on the booking (always).
4. **Mint the code:** `generateOtp()` → `redis.set(arrivalKey(bookingId), JSON({hash: hashOtp(code),
   attempts: 0}), 'EX', 600)` (10 min). Return the **raw code once** to the technician.
5. **No state change** (stays `EN_ROUTE`). Response: `{ arrivalCode, withinGeofence }`. A re-tap
   re-mints (overwrites) — one active code per booking; harmless.

### Step B — `POST /me/bookings/:id/confirm-arrival` { code } (owning CUSTOMER)
1. `requireCustomer`. Load booking owner-scoped (`{ id, customerId, deletedAt: null }`) → else **404**
   (no IDOR). Must be `EN_ROUTE` → else 409.
2. `redis.get(arrivalKey(bookingId))`. Missing → **409** "technician has not marked arrival yet".
3. Attempt cap: `attempts >= 5` → `del` the key + **401** "invalid or expired code". Wrong
   `hashOtp(code)` → increment attempts (`KEEPTTL`) + **401**. (Mirrors the auth OTP verify.)
4. **Correct:** one `$transaction` — `transitionBooking(tx, booking, 'ARRIVED', { type:'USER',
   kind:'CUSTOMER', id: userId })` **and** `tx.booking.update` set `arrivedAt = now`,
   `visitFeeLockedAt = now`. Then `redis.del(arrivalKey)` (single-use). Return the booking DTO.

**Two-sided guarantee:** no code exists without the technician's GPS-stamped arrive-tap; the code
does nothing without the customer's confirm. The optimistic lock (`where {id, state:'EN_ROUTE'}`)
makes a replayed/concurrent confirm a no-op (409). A technician tapping arrive but the customer never
confirming leaves the booking in `EN_ROUTE` forever — never `ARRIVED`, never locked.

**Audit (in the transition's tx, no PII):** `BOOKING_STATE_CHANGED` metadata
`{ bookingId, from:'EN_ROUTE', to:'ARRIVED', gpsRecorded, withinGeofence, codeConfirmed: true }`.
No raw coordinates, no phone.

**How `withinGeofence`/`gpsRecorded` reach the confirm-time audit** (the geofence is computed at the
*arrive* step, but the audit is written at the *confirm* step): at confirm time the booking already
carries the recorded `arrivalLat/arrivalLng`. The confirm handler **re-derives** the audit fields
from stored state — `gpsRecorded = arrivalLat != null` — and recomputes `withinGeofence` from the
stored `arrivalLat/arrivalLng` + the address coords (`null` if either side lacks coords). No extra
column needed; the arrive step already persisted the coordinates. (Equivalently: a tiny
`arrivalWithinGeofence Boolean?` could be stored at arrive-time — but re-deriving from the persisted
coords avoids the extra column and keeps a single source of truth.)

## Endpoints

| Endpoint | Actor (role + identity) | Effect |
|---|---|---|
| `POST /technician/jobs/:id/en-route` | assigned TECHNICIAN | `ACCEPTED → EN_ROUTE` |
| `POST /technician/jobs/:id/arrive` { lat, lng } | assigned TECHNICIAN | GPS gate + record GPS + mint code; **no state change** |
| `POST /me/bookings/:id/confirm-arrival` { code } | owning CUSTOMER | verify code → `EN_ROUTE → ARRIVED` + lock |

- Technician endpoints extend the **`technician-jobs`** module (`enRouteJob`, `arriveJob`; reuse
  `requireTechnician`; the **assigned-technician** check `booking.technicianId === tech.id`).
- `confirm-arrival` extends the **`bookings`** module (`confirmArrival`; reuse `requireCustomer` +
  owner-scope).
- New `src/shared/utils/geo.ts` (`haversineMeters(aLat,aLng,bLat,bLng): number`) and arrival-code
  Redis helpers (mint/verify) — colocated in the bookings module or `shared/` (reusing `generateOtp`/`hashOtp`).

### Validation (Zod, strict)
- `arrive`: `lat` −90..90, `lng` −180..180 (both required) → 400 otherwise.
- `confirm-arrival`: `code` exactly 6 digits (`/^\d{6}$/`) → 400 otherwise.

### Error contract
400 (Zod), 401 (invalid/expired arrival code), 403 (wrong role; technician who isn't the assigned
one; unverified), 404 (booking not found / not owned), 409 (wrong state; confirm before tech tapped
Arrived; illegal transition), 422 (GPS > 200 m when coords present).

## Testing (TDD, `app.inject()`, `fixcare_test` + test Redis)

- **Happy path:** accept → en-route → arrive (returns code, state stays EN_ROUTE, GPS recorded) →
  confirm-arrival(code) → `ARRIVED`, `arrivedAt` + `visitFeeLockedAt` set; audit has
  `{withinGeofence, codeConfirmed:true}` and **no coords**.
- **Two-sided (keystone) assertions:** confirm before the tech tapped arrive (no code) → 409; wrong
  code → 401; **5 wrong attempts** → code invalidated; tech taps arrive but customer never confirms →
  booking stays `EN_ROUTE` (no single-party `ARRIVED`).
- **GPS gate:** coords present + >200 m → 422; coords present + within → ok, `withinGeofence:true`;
  no coords → ok, GPS recorded, `withinGeofence:null`.
- **Identity/ownership:** a different technician calling en-route/arrive → 403; another customer's
  confirm-arrival → 404 (IDOR).
- **State + actor guards:** en-route from non-ACCEPTED → 409; arrive from non-EN_ROUTE → 409; a
  CUSTOMER calling `/arrive` → 403; a TECHNICIAN calling `confirm-arrival` → 403 (default-deny + role).
- **Actor unit test:** `actorAllowedFor('EN_ROUTE','TECHNICIAN')` true / `('EN_ROUTE','CUSTOMER')`
  false; `('ARRIVED','CUSTOMER')` true / `('ARRIVED','TECHNICIAN')` false.
- **geo unit test:** `haversineMeters` — same point → 0; ~known short distance within tolerance.
- **No PII:** assert no GPS coords or phone in any `AuditLog` metadata.
Seed: reuse `seedBookable` + `makeTechnician`; drive the booking to `ACCEPTED` via the B2a accept flow.

## Review gates

`prisma-migration-reviewer` (4 nullable additive columns); `golden-rules-auditor` (Golden Rules 1–2:
two-sided + evidence-gated, no single-party ARRIVED; audit-in-tx; no PII/coords in logs);
**`fraud-vector-checker`** (the keystone — verify against fraud-defenses #11 GPS-spoof / visitation-
without-arrival: the GPS gate + the two-sided code make a remote "arrived" claim impossible to
complete alone). Then `/code-review`.

## Out of scope (deferred)

Completion handshake / keystone #2 (OTP + 3 repair photos → CUSTOMER_CONFIRMED) — B5. Diagnosis +
parts cart (`ARRIVED → DIAGNOSED`) — B4. Actual visit-fee charge/hold — payment slice B6 (B3 sets only
the `visitFeeLockedAt` milestone). Hard PostGIS geofence for coordinate-less addresses (record-only
until addresses carry lat/lng). Live technician location/ETA tracking (WebSocket). The
cancel-by-technician route + other unwired transitions. No money moves in B3.

## Next step

writing-plans for **B3**. On branch `feature/booking-arrival` (already cut off `main`).
