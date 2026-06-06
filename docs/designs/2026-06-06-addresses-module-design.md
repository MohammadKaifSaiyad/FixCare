# Design — Addresses Module + Pincode→Zone Resolution

_Date: 2026-06-06 · Status: approved (pending spec review) · Scope: customer addresses + serviceability/zone resolution, in `apps/backend`_

## Context

The next backend module after the (now complete) service-catalog module, and the prerequisite
for the booking lifecycle. Per `docs/02-product/core-flow.md`, booking step 3 is "Determine zone
(Vadodara/Padra) → apply geofenced rate" — so an address's primary downstream job is to resolve to
a **Zone**, which selects the geofenced catalog labor price + visit fee (`docs/02-product/pricing-model.md`).
Addresses also later feed arrival-GPS validation ("within X m of customer location",
`fraud-defenses.md`) and address-frequency fraud checks — both deferred.

Grounded in: `docs/04-architecture/module-structure.md` (`addresses/` — "Customer addresses, geofence
zones"), the merged catalog module (`Zone`, `CatalogStatus`, `requireAdminLevel(MANAGER)`,
`CATALOG_UPDATED` audit, the `asConflict`→409 helper), the profiles module (the `/me/*` implicit-
ownership + DTO + field-names-only audit pattern), and `coding-conventions.md` (Zod at the boundary,
route→service→DTO, auth-first, ownership-not-just-auth, no PII in logs — Golden Rule 7).

## Decisions locked (during brainstorming)

1. **Zone resolution = pincode→zone map** (no PostGIS in V1). A customer enters a 6-digit pincode; an
   admin-managed `PincodeZone` table maps it to a `Zone`. Deterministic, no external dependency.
   PostGIS-polygon geofencing + Google geocoding are deferred (lat/lng stored now, used later).
2. **Out-of-area = save + tell the app.** An address whose pincode has no active mapping is **still
   saved** (201), but every address/serviceability response carries an explicit `serviceable: false`
   + a human-readable `message`. The customer is never blocked mid-signup; the *booking* module is
   the one that hard-refuses a null-zone address (deferred).
3. **API designed for app UX.** `serviceable` + `zone` (+ `message` when unserviceable) are **always
   present** on every address read/write and on the serviceability check — the app never infers
   serviceability. A lightweight `GET /serviceability?pincode=` lets the app give live feedback while
   the customer is still typing the pincode during signup, before any save.
4. **Pincode map is admin-managed + audited** (lives in the **catalog** module — it's coverage
   config): `GET/POST/PATCH/DELETE /catalog/pincodes`, MANAGER+, `CATALOG_UPDATED` audit, dup
   pincode → 409. Seeded with Vadodara/Padra pincodes alongside the existing catalog seed.
5. **Stored `zoneId` is a cached hint; reads re-resolve live.** Save resolves the pincode and stores
   `zoneId` (or null) so booking has it cheaply, but `GET` list/one and `/serviceability` always
   re-resolve from the **current** `PincodeZone` map. Expanding coverage instantly un-blocks
   previously-unserviceable saved addresses; booking re-resolves at booking-time (authoritative).
6. **Address fields = practical set + optional geo:** `label`, `line1`, `line2?`, `landmark?`,
   `pincode`, optional `lat`/`lng` (nullable floats — device map-pin, for later arrival-GPS),
   `isDefault`, cached `zoneId?`, soft-delete + timestamps.
7. **Owner-scoped, one default enforced.** All routes under `/me/addresses`; **CUSTOMER role only**
   (technician/admin/merchant → 403). Every `:id` route is scoped to the caller's `customerId`;
   another customer's id is indistinguishable from missing (both → 404, no IDOR). Setting
   `isDefault: true` atomically clears the previous default (only ever one). The first address
   auto-becomes default. Deleting the default leaves no default (app/booking prompts to pick).
8. **No audit on customer address CRUD.** Address changes are customer self-service PII, not a
   money/trust/security event — the append-only audit log stays focused on financial + security
   events, and audit metadata never carries address PII. (Only the admin **pincode-map** changes are
   audited.) Fraud address-frequency detection is a later module.
9. **PII discipline (Golden Rule 7):** no address line, pincode, lat/lng, or label ever appears in
   logs or audit metadata. The out-of-area `message` is a static string.

## Schema

```prisma
// ── ADDRESSES ────────────────────────────────────────────────
model Address {
  id         String        @id @default(uuid())
  customerId String
  customer   Customer      @relation(fields: [customerId], references: [id])
  label      String                       // "Home", "Office"
  line1      String
  line2      String?
  landmark   String?
  pincode    String                       // 6-digit (validated /^\d{6}$/)
  lat        Float?                        // optional device map-pin (later arrival-GPS)
  lng        Float?
  zoneId     String?                       // resolved-at-save HINT; null = unserviceable
  zone       Zone?         @relation(fields: [zoneId], references: [id])
  isDefault  Boolean       @default(false)
  status     AddressStatus @default(ACTIVE)
  createdAt  DateTime      @default(now())
  updatedAt  DateTime      @updatedAt
  deletedAt  DateTime?
  @@index([customerId])
}

// ── COVERAGE (catalog module) ────────────────────────────────
model PincodeZone {
  id        String        @id @default(uuid())
  pincode   String        @unique          // "390001"
  zoneId    String
  zone      Zone          @relation(fields: [zoneId], references: [id])
  status    CatalogStatus @default(ACTIVE)
  createdAt DateTime      @default(now())
  updatedAt DateTime      @updatedAt
  deletedAt DateTime?
  @@index([zoneId])
}

enum AddressStatus { ACTIVE  INACTIVE }
```
Back-relations added: `Customer.addresses Address[]`; `Zone.addresses Address[]` + `Zone.pincodeZones PincodeZone[]`.
`PincodeZone` reuses the existing `CatalogStatus` enum. No new `AuditAction` values (admin pincode
changes reuse `CATALOG_UPDATED`). All lat/lng are plain `Float?` — no PostGIS yet.

## Zone resolver (the heart of the module)

One internal function, reused by every read/write:

```
resolvePincode(pincode) ->
  PincodeZone.findFirst({ pincode, deletedAt: null, status: ACTIVE,
                          zone: { deletedAt: null, status: ACTIVE } })
  match    -> { serviceable: true,  zone: { id, name, visitFeePaise } }
  no match -> { serviceable: false, zone: null, message: "We don't serve this area yet" }
```
- A pincode mapped to a **soft-deleted or INACTIVE zone** resolves as **unserviceable** (same guard
  catalog reads use) — never a dangling zone.
- **Save**: resolve, store `zoneId` (or null) as the cached hint.
- **Read** (`GET` list/one, `/serviceability`): resolve **fresh**; the stored `zoneId` is never
  trusted for display.

## Endpoints

### Customer addresses — `src/modules/addresses/` (requireAuth + CUSTOMER only; owner-scoped)
```
GET    /me/addresses           list own ACTIVE addresses (each with LIVE serviceability)
POST   /me/addresses           create; first address auto-default; out-of-area → 201 serviceable:false
GET    /me/addresses/:id       own only (else 404 — no IDOR)
PATCH  /me/addresses/:id       own only; partial, .strict(), ≥1 field
DELETE /me/addresses/:id       soft-delete own (deletedAt)
```

### Serviceability check — `src/modules/addresses/` (requireAuth, any authed user)
```
GET /serviceability?pincode=390001
```

### Admin pincode map — `src/modules/catalog/` (requireAuth + requireAdminLevel(MANAGER); audited)
```
GET    /catalog/pincodes            list mappings
POST   /catalog/pincodes            add pincode→zone   (dup pincode → 409 via asConflict)
PATCH  /catalog/pincodes/:id        change zone / status (CATALOG_UPDATED)
DELETE /catalog/pincodes/:id        soft-delete
```

### Response shape (the API-UX core)
```jsonc
// address DTO (list / get / create / patch)
{ "id": "...", "label": "Home", "line1": "...", "line2": null, "landmark": null,
  "pincode": "390001", "lat": null, "lng": null, "isDefault": true,
  "serviceable": true,
  "zone": { "id": "...", "name": "Vadodara", "visitFeePaise": 14900 } }

// out-of-area (still saved, 201)
{ "id": "...", "pincode": "395003", "isDefault": false,
  "serviceable": false, "zone": null, "message": "We don't serve this area yet" }

// GET /serviceability?pincode=395003  (nothing saved)
{ "serviceable": false, "zone": null, "message": "We don't serve this area yet" }
```
`serviceable` + `zone` (+ `message` when false) are always present — zero inference for the app.
DTOs out, never raw Prisma.

## Validation (Zod, strict, at the boundary)

- `pincode`: `/^\d{6}$/` → 400 otherwise.
- `label`, `line1`: non-empty strings; `line2`, `landmark`: optional strings.
- `lat`: −90..90, `lng`: −180..180, both optional, **both-or-neither** (one without the other → 400).
- `isDefault`: optional boolean.
- PATCH: `.partial().strict()` + at-least-one-field (no mass-assignment; unknown field → 400).

## Error contract (global handler, no internal-detail leak)

| Code | When |
|---|---|
| 400 | Zod failure (bad pincode, lat-without-lng, empty/unknown-field body) |
| 401 | no/invalid token |
| 403 | authenticated non-CUSTOMER on `/me/addresses`; non-MANAGER on `/catalog/pincodes` writes |
| 404 | address not found **or not owned** (identical → no IDOR enumeration); soft-deleted |
| 409 | duplicate pincode on `POST /catalog/pincodes` |

## Default-address rule

`isDefault: true` on create/patch atomically clears the previous default in the **same transaction**
(only ever one default per customer). First-ever address auto-defaults. Deleting the **default**
leaves the customer with no default (V1 — app/booking prompts to pick; we do **not** auto-promote
another address). Deleting a **non-default** address is a plain soft-delete with no default change.
The canonical out-of-area message string is exactly `"We don't serve this area yet"` (tests assert it).

## Sub-slice split & build order

- **Slice A — Pincode map + serviceability** (in `catalog/`): `PincodeZone` model + migration,
  `resolvePincode`, admin `GET/POST/PATCH/DELETE /catalog/pincodes` (MANAGER+, audited, dup→409),
  `GET /serviceability`, and Vadodara/Padra pincodes added to the catalog seed (idempotent). Ships:
  anyone checks serviceability; admins manage coverage.
- **Slice B — Customer addresses** (in `addresses/`): `Address` model + migration, owner-scoped
  `/me/addresses` CRUD, the default-address transaction, and the serviceability verdict baked into
  every address DTO (reuses A's resolver). Depends on A.

Each sub-slice = own plan + PR off `main`, TDD, then `/code-review` before merge.

## Testing (TDD, `app.inject()`, `fixcare_test` + test Redis)

- **resolver:** known pincode → serviceable + right zone/visitFee; unknown → unserviceable;
  pincode mapped to INACTIVE/soft-deleted zone → unserviceable.
- **serviceability endpoint:** 390001→Vadodara; 395003→unserviceable + message; bad pincode→400; no token→401.
- **address CRUD:** create (first auto-default); list shows LIVE serviceability; out-of-area saves
  201 `serviceable:false`; setting a new default clears the old (exactly one default); another
  customer's id→404 (IDOR); non-CUSTOMER→403; soft-delete hides from list; lat-without-lng→400;
  **coverage-expansion:** save unserviceable address → admin adds its pincode → GET now serviceable
  (proves re-resolve-on-read).
- **pincode admin:** MANAGER creates; SUPPORT→403; dup pincode→409; `CATALOG_UPDATED` audit written.
- **PII:** assert no address line/pincode/lat/lng appears in any `AuditLog` metadata.
Mint tokens via `signAccessToken` + seeded customers/admins (as the catalog/profile tests do).

## Out of scope (deferred)

- **Public services/areas marketing page** — a later **V1 front-end slice** (sales/promotion) that
  reads existing zone + catalog data to show what we offer and where; no new backend. Recorded so it
  is not lost; built after the core app/backend work.
- PostGIS-polygon geofencing + Google geocoding (lat/lng stored now, consumed later).
- Arrival-GPS validation ("within X m of customer location") — keystone-handshake / jobs module.
- Booking's hard-refusal of a null-zone address + booking-time zone re-resolution — booking module.
- Fraud address-frequency anomaly detection — later trust/fraud module.

## Next step

writing-plans for **Slice A** first (PincodeZone + resolver + admin endpoints + serviceability +
seed), then **Slice B** (Address CRUD) as its own plan. On branch `feature/addresses-module`
(already cut off `main`).
