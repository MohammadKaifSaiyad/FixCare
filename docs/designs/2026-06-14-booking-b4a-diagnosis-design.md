# Design — Booking B4a (diagnosis + parts cart + approve/decline)

_Date: 2026-06-14 · Status: approved (pending spec review) · Scope: the structured diagnosis record, the snapshotted parts cart, and the customer approve/decline transitions, in `apps/backend`_

## Context

Fourth booking slice (after B1 creation, B2a dispatch, B3 arrival handshake). Per `core-flow.md`
Phase B "Diagnosis Step": after arrival the technician selects a diagnosed issue from a **structured
dropdown (no free text)**, the system shows a parts cart, and the customer sees diagnosis + parts +
estimate (visit fee credited) and **approves or declines** (decline ends the job cleanly). Fraud
defenses in play: no free-text diagnosis, technician has **zero parts-pricing discretion** (catalog
ceiling prices, snapshotted), and parts changes are logged.

**B4 is split** (it bundled too much, incl. standing up R2 storage):
| Sub-slice | What | Buildable now? |
|---|---|---|
| **B4a** (this) | `DiagnosedIssue` catalog + diagnosis record + `BookingPart` cart (snapshot) + approve/decline transitions | ✅ yes |
| B4b | R2 `third-party-wrapper` + presigned uploads + `PhotoEvidence` + the **2 mandatory diagnosis photos** (reused by B5's 3 repair photos) | deferred (R2 unwired) |

B4a records the diagnosis **without photo enforcement** (photos are B4b). Grounded in: B1's
`Booking` price-snapshot pattern, B1/B2a/B3's guarded `transitionBooking` (legality → default-deny
actor gate → optimistic lock → audit, with the optional `evidence` param from B3), the catalog
admin pattern (parts/pincodes: MANAGER+, `CATALOG_UPDATED` audit, `asConflict`→409), `PartsCatalog`
(`ceilingPricePaise`), the `technician-jobs` module (`requireTechnician` + assigned-tech check), and
the booking `requireCustomer` + owner-scope.

## Decisions locked (during brainstorming)

1. **Structured issue = admin-managed `DiagnosedIssue` table** (category-scoped, audited, soft-delete),
   not free text and not an enum. Diagnosis stores `diagnosedIssueId` (FK) **+ a snapshot
   `diagnosedIssueName`** (display-stable if the issue is later renamed).
2. **Parts cart = `BookingPart` line-items**, each **snapshotting** `sku/name/ceilingPricePaise` at
   add-time (the B1-deferred **parts snapshot** — catalog edits after diagnosis never change a
   quoted cart) + `qty`. The technician has zero price input; the price comes from the catalog row.
3. **Flow:** `POST /diagnose {diagnosedIssueId}` → `ARRIVED→DIAGNOSED` + creates the diagnosis,
   cart starts **empty**. While `DIAGNOSED` (pre-decision) the tech adds/removes cart lines (each
   logged). Customer `approve`/`decline`. Cart is **frozen** once `CUSTOMER_APPROVED` (part edits
   require `DIAGNOSED`).
4. **Auto-suggest deferred** — the cart starts empty; the tech builds it. The Issue→suggested-parts
   mapping (and the suggestion) is a later slice.
5. **Decline is terminal + milestone-only:** `DIAGNOSED→DECLINED_BY_CUSTOMER` records `declinedAt`;
   `visitFeeLockedAt` was already set at `ARRIVED` (B3). The actual visit-fee charge + technician
   payout happen in the payment slice (B6) reading that milestone + the declined state. **No money
   in B4a.** Decline reason omitted (lean).
6. **Estimate is computed, not stored:** `labor (snapshot) + Σ(part ceilingPricePaise×qty) −
   visitFeeCredit`, **floored at 0**; all from snapshots. Integer paise.
7. **Issue–service category match:** the diagnosed issue's `categoryId` must equal the booking's
   `service.categoryId` → else **422** (an AC issue can't be the diagnosis for a Fan service).
8. **Actor entries** (mandatory under default-deny): `DIAGNOSED→TECHNICIAN`,
   `CUSTOMER_APPROVED→CUSTOMER`, `DECLINED_BY_CUSTOMER→CUSTOMER`. Role-gate in the state machine;
   assigned-tech / owner identity in the service.

## Schema (additive migration)

```prisma
model DiagnosedIssue {
  id         String          @id @default(uuid())
  name       String                       // "AC compressor fault"
  categoryId String
  category   ServiceCategory @relation(fields: [categoryId], references: [id])
  status     CatalogStatus   @default(ACTIVE)
  createdAt  DateTime @default(now())
  updatedAt  DateTime @updatedAt
  deletedAt  DateTime?
  @@unique([categoryId, name])
  @@index([categoryId])
}

model BookingPart {
  id                String   @id @default(uuid())
  bookingId         String
  booking           Booking  @relation(fields: [bookingId], references: [id])
  partsCatalogId    String                // reference (not a snapshot of the row's mutable fields)
  sku               String                // snapshot
  name              String                // snapshot
  ceilingPricePaise Int                   // snapshot of the catalog ceiling price at add-time (paise)
  qty               Int                   // >= 1 (Zod)
  createdAt         DateTime @default(now())
  @@index([bookingId])
}

model Booking {
  ...
  diagnosedIssueId   String?
  diagnosedIssue     DiagnosedIssue? @relation(fields: [diagnosedIssueId], references: [id])
  diagnosedIssueName String?              // snapshot
  diagnosedAt        DateTime?
  declinedAt         DateTime?
  bookingParts       BookingPart[]
  ...
}
```
- **Two distinct audit actions, deliberately:** admin edits to the **issue catalog** write
  `CATALOG_UPDATED` (it's reference/config data, like parts/pincodes); per-**booking** diagnosis +
  cart mutations write the new **`DIAGNOSIS_UPDATED`**. Transitions still use `BOOKING_STATE_CHANGED`.
  Back-relations: `ServiceCategory.diagnosedIssues`, `Booking.bookingParts`.
- Money is integer paise. `DiagnosedIssue` reuses `CatalogStatus` + soft-delete (the catalog pattern).
- **`BookingPart` has no soft-delete by design:** it's a *pre-approval mutable cart line* (remove =
  hard delete is correct while `DIAGNOSED`). It is NOT yet a financial record — the cart is frozen at
  `CUSTOMER_APPROVED` and never edited after; the immutable financial artifact is the approved snapshot,
  consumed by B6. (So the "financial record needs soft-delete" convention doesn't apply pre-approval.)
- No `PhotoEvidence` here (B4b).

## State machine + actor-permissions (`bookings.state.ts`)

`ALLOWED_TRANSITIONS` already has `ARRIVED→DIAGNOSED`, `DIAGNOSED→[CUSTOMER_APPROVED,
DECLINED_BY_CUSTOMER]`. B4a wires them and adds to `ALLOWED_ACTORS`:
```ts
  DIAGNOSED:            ['TECHNICIAN'],
  CUSTOMER_APPROVED:    ['CUSTOMER'],
  DECLINED_BY_CUSTOMER: ['CUSTOMER'],
```

## Endpoints

### Admin issue catalog — `catalog/` (MANAGER+ writes, audited; reads any authed user)
```
GET    /catalog/issues[?categoryId=]   list ACTIVE issues (technician app fetches the dropdown)
POST   /catalog/issues                 {name, categoryId}  MANAGER+; dup (category,name) → 409; unknown category → 404
PATCH  /catalog/issues/:id             {name?, status?}    MANAGER+
DELETE /catalog/issues/:id             MANAGER+ soft-delete
```
Writes `CATALOG_UPDATED` (entity `DiagnosedIssue`). Seeded with sample issues per category.

### Technician diagnose + cart — `technician-jobs/` (assigned TECHNICIAN)
```
POST   /technician/jobs/:id/diagnose      {diagnosedIssueId}        ARRIVED → DIAGNOSED
POST   /technician/jobs/:id/parts         {partsCatalogId, qty}     add a cart line (DIAGNOSED only)
DELETE /technician/jobs/:id/parts/:partId                           remove a cart line (DIAGNOSED only)
```
- **diagnose:** assigned tech, booking `ARRIVED` (else 409). Validate the issue is ACTIVE and its
  `categoryId === booking.service.categoryId` (else **422**). `$transaction`: set
  `diagnosedIssueId` + snapshot `diagnosedIssueName` + `diagnosedAt`;
  `transitionBooking(ARRIVED→DIAGNOSED, kind:TECHNICIAN, evidence:{diagnosedIssueId})`; cart empty.
- **add part:** assigned tech, `DIAGNOSED` (else 409). Load `PartsCatalog` (ACTIVE → else 404);
  create `BookingPart` snapshotting `sku/name/ceilingPricePaise`, `qty` (Zod ≥1). Audit
  `DIAGNOSIS_UPDATED {action:'part_added', sku, qty}` (no PII). No state change.
- **remove part:** assigned tech, `DIAGNOSED`; delete the `BookingPart` scoped to this booking
  (else 404). Audit `DIAGNOSIS_UPDATED {action:'part_removed', sku}`.

### Customer approve/decline — `bookings/` (owning CUSTOMER)
```
POST /me/bookings/:id/approve    DIAGNOSED → CUSTOMER_APPROVED
POST /me/bookings/:id/decline    DIAGNOSED → DECLINED_BY_CUSTOMER (terminal)
```
- **approve:** owner, `DIAGNOSED` (else 409). `transitionBooking(→CUSTOMER_APPROVED, kind:CUSTOMER)`.
  Cart frozen (part edits require `DIAGNOSED`). 
- **decline:** owner, `DIAGNOSED` (else 409). `transitionBooking(→DECLINED_BY_CUSTOMER, kind:CUSTOMER)`
  + set `declinedAt`. Terminal. `visitFeeLockedAt` already set at ARRIVED; B6 settles it.
- The customer reads diagnosis + cart + estimate via the existing `GET /me/bookings/:id` (extended).

### Estimate (computed in the DTO, not stored)
```
laborPaise          = booking.laborPaise (snapshot)
partsPaise          = Σ(BookingPart.ceilingPricePaise × qty)
visitFeeCreditPaise = booking.visitFeePaise
totalPayablePaise   = max(0, laborPaise + partsPaise − visitFeeCreditPaise)
```
All from snapshots → catalog edits after diagnosis never change a quoted estimate.

### DTOs
`BookingDto` (customer) gains: `diagnosis: { issueName } | null`, `parts: [{ id, sku, name,
ceilingPricePaise, qty }]`, `estimate: { laborPaise, partsPaise, visitFeeCreditPaise,
totalPayablePaise }`. The technician job DTO (B2a) gains the same `parts` + `estimate` so the tech
sees the cart they're building. No new PII (sku/name/prices are catalog data).

### Error contract
400 (Zod — qty<1, malformed body), 401 (no token), 403 (wrong role; technician not assigned;
default-deny actor), 404 (booking/issue/part/catalog-part not found-or-not-owned), 409 (wrong state —
diagnose from non-ARRIVED, parts-edit/approve/decline from wrong state, illegal transition),
422 (issue category ≠ booking service category).

## Module structure

- `catalog/`: `DiagnosedIssue` DTO + `createIssueBody`/`updateIssueBody` + `listIssues`/`createIssue`/
  `updateIssue`/`deleteIssue` + routes (mirror the parts/pincode CRUD).
- `technician-jobs/`: `diagnoseJob`, `addPart`, `removePart` + schemas + routes.
- `bookings/`: `approveDiagnosis`, `declineDiagnosis` + routes; extend `toBookingDto` (diagnosis +
  parts + estimate); a small `estimate.ts` (`computeEstimate(booking, parts)`).
- `bookings.state.ts`: the 3 `ALLOWED_ACTORS` entries.
- schema migration (+ `DiagnosedIssue`, `BookingPart` to the test TRUNCATE list); seed sample issues.

## Testing (TDD, `app.inject()`, `fixcare_test` + test Redis)

- **Issue catalog:** MANAGER creates; dup (category,name)→409; unknown category→404; SUPPORT→403;
  audit `CATALOG_UPDATED`; reads (any authed) filter ACTIVE + category.
- **Diagnose:** ARRIVED→DIAGNOSED sets issue + snapshot name + `diagnosedAt`; issue-category-mismatch→422;
  diagnose from non-ARRIVED→409; non-assigned tech→403; customer calling diagnose→403; `DIAGNOSIS_UPDATED` audit.
- **Parts cart (the snapshot integrity assertion):** add snapshots ceiling price+qty; **change the
  catalog `ceilingPricePaise` after add → the `BookingPart` line + the estimate are unchanged**; add/remove
  only while DIAGNOSED (add after approve→409); remove another booking's part→404; qty<1→400; each audited.
- **Estimate:** labor + Σ(parts) − visit-fee credit, floored at 0; from snapshots.
- **Approve/decline:** DIAGNOSED→CUSTOMER_APPROVED then part-add→409 (frozen); DIAGNOSED→DECLINED_BY_CUSTOMER
  terminal + `declinedAt` set + `visitFeeLockedAt` still set (no outgoing edges); from non-DIAGNOSED→409;
  another customer→404; technician calling approve→403.
- **DTO:** customer GET shows diagnosis + parts + estimate; no PII in audit.
- **Actor unit:** DIAGNOSED→TECHNICIAN, CUSTOMER_APPROVED/DECLINED→CUSTOMER + cross-role denials.
Seed: reuse the booking helpers; drive a booking to ARRIVED via the B3 handshake; seed a DiagnosedIssue
in the booking's service category + PartsCatalog rows.

## Review gates

`prisma-migration-reviewer` (additive; `BookingPart.ceilingPricePaise` integer paise; indexes);
`golden-rules-auditor` (parts-snapshot = money-evidence integrity; audit-in-tx; actor + assigned-tech/owner;
no PII in audit; catalog-prices-only — tech provides no price); `fraud-vector-checker` (no-free-text
diagnosis enforced by the FK; parts price can't be padded by the technician — snapshotted from the catalog,
not from request input; issue-service category match). Then `/code-review`.

## Out of scope (deferred)

**B4b** — R2 `third-party-wrapper` + presigned uploads + `PhotoEvidence` + the **2 mandatory diagnosis
photos** (and reusable for B5's 3 repair photos); B4a records the diagnosis without photo enforcement.
Auto-suggest parts (Issue→parts mapping); the diagnosis-to-parts **mismatch** fraud rule; tier-based
dynamic estimate; `CUSTOMER_APPROVED→PARTS_REQUESTED/REPAIR_IN_PROGRESS` (B5/repair); the actual
visit-fee/labor charge + payout (B6); decline reason. No money moves in B4a.

## Next step

writing-plans for **B4a**. On branch `feature/booking-diagnosis` (already cut off `main`).
