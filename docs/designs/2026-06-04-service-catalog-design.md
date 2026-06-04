# Design — Service Catalog Module

_Date: 2026-06-04 · Status: approved (pending spec review) · Scope: admin-managed service catalog + geofenced labor pricing + parts master, in `apps/backend`_

## Context

Next backend module after the auth module + profile-update slice. The catalog is the
pricing foundation the booking flow will read from. Per `docs/02-product/pricing-model.md`:
three transparent components — a geofenced **visit fee** (Vadodara ₹149 / Padra ₹99), **catalog
labor** (geofenced, technician has zero discretion), and a **parts master** with platform-set
ceiling prices. Golden Rules in play: **catalog prices only** (no technician discretion),
**money is integer paise**, **price/catalog mutations are audited**.

Grounded in: `docs/02-product/pricing-model.md`, `docs/04-architecture/module-structure.md`
(`services/`, `service-pricing/`, `parts-catalog/`, `merchant-catalog/`), `docs/05-development/coding-conventions.md`
(money via `shared/utils/currency.ts`, soft-delete, route→service→DTO, auth-first). Builds on the
merged auth module (`requireAuth`, `signAccessToken`, the `Admin.adminLevel` enum) and the
`audit-logged-mutation` / `prisma-schema-model` / `scaffold-module` / `zod-validated-route` skills.

## Decisions locked (during brainstorming)

1. **Scope = one design, two sub-slices.** A: Zone + ServiceCategory + Service + ServicePrice
   (+ currency util + `requireAdminLevel`). B: PartsCatalog + catalog seed. **Deferred:**
   merchant-catalog (needs onboarded merchants), PostGIS-polygon geofencing + address→zone
   resolution (the `addresses/` module).
2. **Normalized per-zone pricing:** `ServiceCategory → Service (tier) → ServicePrice {serviceId, zoneId, laborPaise}`. Adding a zone = add price rows, not schema changes.
3. **Visit fee is per-zone:** `visitFeePaise` on `Zone`.
4. **Zones are a named table** (no polygons yet); address→zone resolution deferred to `addresses/`.
5. **Money:** build `shared/utils/currency.ts` now (first heavy money module); all prices `Int` paise.
6. **Price changes:** update in place + `PRICE_CHANGED` audit (old→to paise — internal pricing data,
   not PII). Point-in-time billing correctness comes from booking-time price **snapshots** (booking module, later) — the catalog is always "current".
7. **Write RBAC:** `requireAdminLevel(MANAGER)` preHandler (the incremental first piece of the
   deferred `rbac.ts`) gates writes to MANAGER+. **Reads:** any authenticated user.
8. **Lifecycle:** `status (ACTIVE|INACTIVE)` + `deletedAt` soft-delete on every catalog entity.
9. **Parts** = platform-set ceiling price, **zone-agnostic** (parts MRP isn't geofenced like labor). Merchant cost deferred.
10. **Tier** = a `LaborTier` enum label (T1|T2|T3) on `Service`; tier-based dynamic pricing deferred to booking/estimation.
11. **Seed:** extend the existing seed with zones + sample categories/services/prices + parts (idempotent).

## Schema

```prisma
// ── CATALOG ──────────────────────────────────────────────────
model Zone {
  id            String        @id @default(uuid())
  name          String        @unique           // "Vadodara", "Padra"
  visitFeePaise Int                              // geofenced visit fee (₹149 = 14900)
  status        CatalogStatus @default(ACTIVE)
  createdAt     DateTime      @default(now())
  updatedAt     DateTime      @updatedAt
  deletedAt     DateTime?
  servicePrices ServicePrice[]
}

model ServiceCategory {
  id        String        @id @default(uuid())
  name      String        @unique               // "AC", "Fan", "Electrical"
  status    CatalogStatus @default(ACTIVE)
  createdAt DateTime      @default(now())
  updatedAt DateTime      @updatedAt
  deletedAt DateTime?
  services  Service[]
  parts     PartsCatalog[]
}

model Service {
  id         String          @id @default(uuid())
  categoryId String
  category   ServiceCategory @relation(fields: [categoryId], references: [id])
  name       String                              // "AC gas refill"
  tier       LaborTier                           // T1 | T2 | T3 (complexity label)
  status     CatalogStatus   @default(ACTIVE)
  createdAt  DateTime        @default(now())
  updatedAt  DateTime        @updatedAt
  deletedAt  DateTime?
  prices     ServicePrice[]
  @@unique([categoryId, name])
}

model ServicePrice {
  id         String   @id @default(uuid())
  serviceId  String
  service    Service  @relation(fields: [serviceId], references: [id])
  zoneId     String
  zone       Zone     @relation(fields: [zoneId], references: [id])
  laborPaise Int                                 // catalog labor price for this service in this zone
  createdAt  DateTime @default(now())
  updatedAt  DateTime @updatedAt
  @@unique([serviceId, zoneId])                  // one price per service×zone
  @@index([zoneId])
}

model PartsCatalog {                             // sub-slice B
  id                String          @id @default(uuid())
  sku               String          @unique
  name              String
  categoryId        String?
  category          ServiceCategory? @relation(fields: [categoryId], references: [id])
  ceilingPricePaise Int                          // platform-set catalog price (zone-agnostic)
  status            CatalogStatus   @default(ACTIVE)
  createdAt         DateTime        @default(now())
  updatedAt         DateTime        @updatedAt
  deletedAt         DateTime?
}

enum CatalogStatus { ACTIVE  INACTIVE }
enum LaborTier     { T1  T2  T3 }
```
`AuditAction` gains `PRICE_CHANGED` and `CATALOG_UPDATED` (enum migration, like `PROFILE_UPDATED`).
All money is `Int` paise. AuditLog is referenced loosely (actorId/metadata), no FK relations.

## Shared pieces (sub-slice A)

- **`shared/utils/currency.ts`** — `rupeesToPaise`, `paiseToRupees`, `formatPaise`, `assertValidPaise`
  (non-negative integer guard). All catalog money flows through it (coding-conventions mandate).
- **`shared/errors.ts`** += `ConflictError` (409) for unique-constraint conflicts.
- **`shared/middleware/rbac.ts`** — `requireAdminLevel(min: AdminLevel)`: preHandler after `requireAuth`,
  ranks SUPER_ADMIN > MANAGER > SUPPORT, loads the caller's Admin row, throws `ForbiddenError` (403)
  if below `min`. The incremental start of the deferred `rbac.ts`.

## Module `src/modules/catalog/`

`catalog.routes.ts`, `catalog.service.ts`, `catalog.schemas.ts`, `catalog.types.ts`, `__tests__/`.
Registered in `buildApp()` after the profile routes.

### Read endpoints — `requireAuth` (any authenticated user)
```
GET /catalog/zones                         → active zones { id, name, visitFeePaise, status }
GET /catalog/categories[?include=services] → active categories
GET /catalog/services?zoneId=&categoryId=  → services + price for THAT zone
        { id, name, tier, category, laborPaise, visitFeePaise }
GET /catalog/parts[?categoryId=]           → active parts { id, sku, name, ceilingPricePaise }  (B)
```
Customer-facing reads filter `deletedAt: null` AND `status: ACTIVE`. `GET /catalog/services?zoneId=X`
is the key query the booking flow uses ("cost of service X in zone Y"). DTOs out (paise as integers).

### Write endpoints — `requireAuth` + `requireAdminLevel(MANAGER)`
```
POST /catalog/zones            PATCH /catalog/zones/:id
POST /catalog/categories       PATCH /catalog/categories/:id
POST /catalog/services         PATCH /catalog/services/:id
PUT  /catalog/services/:id/prices/:zoneId   (upsert labor price for a service×zone)
POST /catalog/parts            PATCH /catalog/parts/:id                                   (B)
```
- Zod-validated; money fields validated as non-negative integer paise via the currency util.
- **Price-affecting writes** (zone visit fee, service price upsert, part ceiling) write `AuditLog`
  `PRICE_CHANGED` in the same transaction: `metadata { entity, entityId, zoneId?, field, fromPaise, toPaise }`.
- Other mutations (create/status/soft-delete) write `CATALOG_UPDATED` (entity + id + changed fields).
- Soft-delete via PATCH/DELETE setting `deletedAt` (never hard-delete).

### Error contract (global handler)
400 (Zod / invalid paise), 401 (no token), 403 (not MANAGER+ on writes), 404 (not found / soft-deleted),
409 (`ConflictError` — duplicate zone name, second price for same service×zone). No internal-detail leak.

## Sub-slice split & build order

**A — Zones + service catalog + geofenced labor pricing:** currency util (+unit tests),
`ConflictError`, `requireAdminLevel`, the 4 catalog models + enums + audit actions (one migration),
zone/category/service read+write endpoints + price upsert (audited). Ships: admin builds the labor
catalog; users read price-by-zone.
**B — Parts master + seed:** `PartsCatalog` (migration), parts read+write, and an idempotent catalog
seed (Vadodara/Padra zones + sample categories/services/prices + parts) alongside the SUPER_ADMIN seed.
B depends on A (shares `CatalogStatus`, the module, the currency util). Each sub-slice = own plan + PR off `main`.

## Testing (TDD, `app.inject()`, `fixcare_test` + test Redis)

- **currency util:** rupees↔paise roundtrip; rejects non-integer/negative; formatting.
- **rbac:** `requireAdminLevel(MANAGER)` — SUPER_ADMIN & MANAGER pass; SUPPORT → 403; customer/technician → 403; no token → 401.
- **reads:** zones list; `services?zoneId=` returns the right `laborPaise` + zone `visitFeePaise`, and a
  *different* price for the other zone (geofencing assertion); INACTIVE/soft-deleted excluded; no token → 401.
- **writes:** MANAGER creates category/service/price; price upsert updates in place; `PRICE_CHANGED`
  audit written with from→to paise (and `CATALOG_UPDATED` for non-price changes); SUPPORT → 403;
  duplicate zone name / second price same service×zone → 409; negative/float paise → 400; soft-delete hides from reads.
- **seed (B):** idempotent (twice = no dup); creates documented zones/services/parts.
Mint tokens via `signAccessToken` + seeded admins (as profile tests do).

## Out of scope (deferred)

merchant-catalog (per-merchant negotiated cost — needs onboarded merchants); PostGIS-polygon
geofencing + address→zone resolution (`addresses/` module); tier-based dynamic pricing/estimation
(booking module); booking-time price snapshot (booking module); open-market premium, AMC discounts,
bonus tiers, UPI/cash pricing, cost-of-living indexing (later pricing-engine concerns); unauthed
public catalog browsing.

## Next step

writing-plans for **sub-slice A** first (currency + rbac + zones/categories/services/prices), then B
(parts + seed) as its own plan. On branch `feature/service-catalog` (already cut off `main`).
