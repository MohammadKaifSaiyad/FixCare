# Booking B6b — Cash Payment Path (design)

**Date:** 2026-07-19 · **Branch:** `feature/booking-b6b-cash` · **Status:** approved
**Follows:** B6a (UPI charge, PR #18). **Precedes:** B6c (settlement ledger, CLOSED wiring).

## Goal

The friction-added cash alternative to UPI, exactly as `core-flow.md` Phase E and
`trust-system.md` specify: the customer confirms the exact amount in-app, the technician
confirms receipt via a separate OTP, the technician's cash debt to the platform increases,
and cash collection is capped at ₹3000 per 24h. Money still never moves without evidence
(Golden Rule 1), and no single party can confirm the payment alone (Golden Rule 2: the
customer's OTP + the technician's entry are the two sides).

## Scope decisions (settled with the founder)

| Question | Decision |
|---|---|
| Debt limit model | **Flat ₹500 for all technicians** (the documented new-technician tier). The trust-ladder (₹500→₹5000) arrives with the trust-system module — one config constant becomes a computed value. |
| "At debt limit → cannot accept jobs" gate | **Deferred to B6c** (ships together with settlement, so a technician can never be locked out of work with no way to pay debt down). B6b blocks only the cash *payment*; the customer falls back to UPI. |
| Debt storage | **`Technician.cashDebtPaise` balance column**, mutated in the capture transaction. The velocity cap is computed from `Payment` rows, not this column. B6c's ledger becomes the source of truth; this stays as the cached balance. |
| ₹20 UPI discount | **Deferred** to its own pricing slice. B6b keeps UPI = cash = the approved total. |
| Actor for cash PAYMENT_RECEIVED | **Approach A:** `TECHNICIAN` drives the transition (the customer's OTP is the second party) — the same idiom as keystone #2 (CUSTOMER_CONFIRMED is TECHNICIAN-actor). `ALLOWED_ACTORS.PAYMENT_RECEIVED` becomes `['SYSTEM', 'TECHNICIAN']`; the SYSTEM-only unit test is consciously updated. |
| Amount mismatch auto-dispute | **Impossible by construction in V1** — the amount is server-computed (`chargeAmountFor`); both parties confirm the same number. The doc's auto-dispute defense targets free-entry amounts; recorded for B7. |

## Schema (one additive migration: `payment_cash`)

- `PaymentMethod` += `CASH`.
- `Payment.razorpayOrderId String @unique` → **`String? @unique`** (cash rows have no
  gateway order; Postgres unique allows multiple NULLs). No other Payment change — cash
  reuses the append-only attempt model and `capturedAt`.
- `Technician.cashDebtPaise Int @default(0)` — integer paise, never negative in B6b
  (only increments; settlement decrements in B6c).
- Config (Zod, required with defaults): `CASH_DEBT_LIMIT_PAISE` = 50000,
  `CASH_VELOCITY_CAP_PAISE` = 300000. The 24h window is a code constant.

## Flow

### Customer initiation — `POST /me/bookings/:id/pay-cash` (CUSTOMER, owner-scoped)

Guards, in order (mirrors `/pay`):
1. Auth → role 403 → owner `findFirst` 404.
2. CAPTURED attempt exists (any method) → 409 "already paid".
3. `chargeAmountFor(booking, parts)` — same ONE amount source as UPI
   (CUSTOMER_CONFIRMED → approved total; DECLINED_BY_CUSTOMER → locked visit fee;
   else 409). Zero payable → 422 (B6a guard applies unchanged).
4. **Velocity gate:** sum of `Payment {method CASH, status CAPTURED}` joined through the
   booking's `technicianId`, `capturedAt > now − 24h`, plus this amount, must be
   ≤ `CASH_VELOCITY_CAP_PAISE` → else 422 "cash limit reached — please pay by UPI".
5. **Debt gate:** `technician.cashDebtPaise + amount ≤ CASH_DEBT_LIMIT_PAISE`
   → else 422 same message shape.

On pass, in one transaction: reuse the open `{CASH, CREATED}` attempt or create one
(idempotent like UPI pay — no duplicate rows), `PAYMENT_EVENT cash_initiated` audit
`{bookingId, amountPaise}`. Then mint the receipt OTP via **`shared/auth/otp-store.ts`**
(never hand-rolled): purpose `cash-receipt`, key = booking id, payload pins
`{paymentId, amountPaise}`, 6-digit, single-use, attempt-capped, `sendLimit` throttled;
delivered to the **customer** (dev: `devOtp` in the response, prod: SMS — same posture as
the completion mint). Response `{amountPaise, devOtp?}`.

Re-request = same endpoint again: reuses the attempt, re-mints (throttle 429s abuse).

### Technician receipt — `POST /technician/jobs/:id/confirm-cash {code}` (TECHNICIAN, assigned)

1. Assigned-technician guard (foreign tech → 404), Zod body (6-digit code).
2. Verify OTP (wrong → 401 with attempts decrementing; expired/absent → 401). Payload's
   `paymentId` must match the open CASH attempt — stale OTP from a superseded attempt fails.
3. One transaction (the money moment):
   a. `updateMany Technician {id, cashDebtPaise: current}` increment — the row update is
      also the **row lock** serializing concurrent captures for the same technician.
   b. **Re-check both gates post-lock** (initiation-time checks are UX; these are the
      enforcement — two parallel initiations cannot jointly exceed a cap). Violation →
      throw 422, whole tx rolls back.
   c. `Payment → CAPTURED` + `capturedAt`.
   d. `transitionBooking(booking, PAYMENT_RECEIVED, TECHNICIAN actor,
      {method: 'CASH', amountPaise, codeConfirmed: true})` — the optimistic lock makes a
      race with a late UPI capture roll back the ENTIRE tx (no debt increment, 409).
   e. `PAYMENT_EVENT cash_received` audit `{bookingId, paymentId, amountPaise,
      technicianId}`.
4. A late UPI webhook capture arriving AFTER a cash capture lands in B6a's existing
   `duplicate_capture` flag machinery unchanged (recorded honestly + flagged for refund).

### DTOs

- `BookingDto.payment {status, method, amountPaise}` — cash flows through unchanged.
- Technician job DTO / jobs responses gain **`cashDebtPaise`** (core-flow: "technician
  sees running balance").

## Error handling

Every guard is a typed error (409/404/403/422/401/429) through the existing error map.
No PII in audit metadata (ids and paise only). OTP hashes at rest (store guarantees).
All writes audited in-transaction (Golden Rule 5).

## Testing

- **Unit:** gate math (velocity window boundary at exactly 24h and exactly ₹3000; debt
  boundary at exactly ₹500), actor-unit update (`PAYMENT_RECEIVED` allows SYSTEM +
  TECHNICIAN, denies CUSTOMER/ADMIN).
- **Route (module pattern, direct-seeded payable states where the chain is proven
  elsewhere):** happy cash flow for both amount sources (approved total + declined visit
  fee) asserting Payment CAPTURED, debt increment, PAYMENT_RECEIVED, both audits; wrong
  OTP 401 ×cap → locked; foreign technician 404; customer role on confirm-cash 403;
  velocity-cap 422 (seeded captured cash rows inside/outside the window); debt-limit 422;
  already-paid 409; cash-after-UPI-capture 409 with debt UNCHANGED (the rollback test);
  DTO shows the running balance; re-initiation idempotency (one CASH row).

## Out of scope (recorded)

Settlement/repayment + accept-gate + CLOSED wiring (B6c) · dynamic debt ladder + cash-
compliance score (trust module) · ₹20 UPI discount (pricing slice) · amount-mismatch
auto-dispute (B7; impossible in V1) · merchant splits (Route, post-approval).
