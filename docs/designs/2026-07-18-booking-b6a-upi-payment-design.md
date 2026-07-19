# Booking B6a — UPI Payment via Razorpay — Design

**Date:** 2026-07-18
**Branch:** `feature/booking-b6-payment`
**Status:** Approved (brainstorming) → ready for `writing-plans`
**Depends on:** B5 (merged, PR #17 — CUSTOMER_CONFIRMED reachable end-to-end)

---

## Problem

Both keystones exist, but no money moves: CUSTOMER_CONFIRMED is a dead end. The docs define the
payment phase (core-flow §E: UPI primary, cash fallback; pricing-model splits; Route settlements),
but that is **three subsystems** — the UPI charge, the cash path (+debt tracking), and the
settlement ledger. Per project precedent (B2a/b/c, B4a/b), B6 is split:

- **B6a (this slice): the UPI charge** — Razorpay order → customer pays → signature-verified
  webhook → PAYMENT_RECEIVED. The primary V1 money path, shippable now on test keys.
- **B6b: the cash path** — amount confirm + receipt OTP + technician cash debt + ₹3000/24h cap.
- **B6c: settlement ledger** — manual merchant/technician payouts until Route approval; Route
  splits after.

## Decisions (brainstorming, 2026-07-18)

1. **Split confirmed** — B6a is UPI-only; smallest reviewable money surface first.
2. **No second OTP at charge** (final resolution of the B4a-token question): B5's completion OTP is
   the customer's money-gating consent, and the UPI payment itself is customer-authorized in their
   UPI app — two confirmations already exist. The decision doc gets this final entry.
3. **Declined bookings charge their visit fee in B6a** — `DECLINED_BY_CUSTOMER` owes the locked
   `visitFeePaise` (B3/B4a); leaving it until B6b/c is revenue leakage. The graph gains
   `DECLINED_BY_CUSTOMER → PAYMENT_RECEIVED`.
4. **Payment model over Booking fields** — UPI attempts can fail and retry; the attempt history IS
   evidence, and B7 refunds hang off Payment rows.
5. **Webhook-driven transition** — the gateway's signed `payment.captured` event (not any client
   claim) drives CUSTOMER_CONFIRMED→PAYMENT_RECEIVED as SYSTEM. (Rejected: client-confirmed
   payment — trusts client timing, loses history; polling worker — BullMQ not wired, webhooks are
   the documented approach.)
6. **CLOSED stays unwired** — default-deny protects it; the 48h dispute-window auto-close belongs
   to B6c/B7 (needs a timer or admin close).

## Schema

```prisma
enum PaymentMethod {
  UPI
  // B6b appends: CASH
}

enum PaymentStatus {
  CREATED   // order created, awaiting the customer's UPI approval
  CAPTURED  // gateway confirmed capture — the money moved
  FAILED    // gateway reported failure — customer may retry (new order)
}

model Payment {
  id                String        @id @default(uuid())
  bookingId         String
  booking           Booking       @relation(fields: [bookingId], references: [id])
  method            PaymentMethod
  status            PaymentStatus @default(CREATED)
  amountPaise       Int           // snapshot of the charge amount at order time — the ONLY amount we accept capture for
  razorpayOrderId   String        @unique
  razorpayPaymentId String?       @unique // set on capture; the idempotency anchor for webhooks
  failureReason     String?
  capturedAt        DateTime?
  createdAt         DateTime      @default(now())
  updatedAt         DateTime      @updatedAt

  @@index([bookingId])
}
```

- `Booking.payments Payment[]` back-relation. No soft-delete — payment attempts are append-only
  evidence (status is the lifecycle; rows are never deleted).
- `AuditAction` += `PAYMENT_EVENT` (order created / captured / failed / flagged).
- State machine: `ALLOWED_TRANSITIONS.DECLINED_BY_CUSTOMER: ['PAYMENT_RECEIVED']` (was terminal);
  `ALLOWED_ACTORS.PAYMENT_RECEIVED: ['SYSTEM']`.
- Additive migration, both DBs.

## Razorpay wrapper (`shared/third-party/razorpay.ts` — third-party-wrapper pattern)

```ts
export interface PaymentGateway {
  /** Create a gateway order for exactly amountPaise. `receipt` carries the bookingId. */
  createOrder(amountPaise: number, receipt: string): Promise<{ orderId: string }>;
  /** HMAC-SHA256 the RAW body with RAZORPAY_WEBHOOK_SECRET; timing-safe compare. */
  verifyWebhookSignature(rawBody: string, signature: string): boolean;
}
```

- `DevPaymentGateway`: deterministic fake order ids (`order_dev_<n>`); `verifyWebhookSignature`
  computes the same HMAC with the dev secret so tests can sign valid payloads; exposes a
  `signPayload(rawBody)` test hook.
- `RazorpayGateway`: official `razorpay` npm SDK (sanctioned in the locked stack — no ADR), creds
  checked **lazily on first use** (R2 posture — production boots before keys are provisioned).
- `makePaymentGateway()` factory + module singleton. Config: `RAZORPAY_KEY_ID`,
  `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET` — all optional in Zod; `.env.example` stubs.
- Typed error boundary; SDK errors never leak; secrets never logged.

## Charge amount — one source of truth

`chargeAmountFor(booking, parts)` in the bookings module:
- `CUSTOMER_CONFIRMED` → `computeEstimate(booking, parts).totalPayablePaise` — the invariant-locked
  approved total (the estimate-drift regression test from B5 guards this number).
- `DECLINED_BY_CUSTOMER` → `booking.visitFeePaise` (the visit happened; the repair didn't).
- Any other state → `ConflictError` 409.

## Endpoints

1. **`POST /me/bookings/:id/pay`** (customer; `requireCustomerRole` + owner-scoped 404):
   - State must be CUSTOMER_CONFIRMED or DECLINED_BY_CUSTOMER → else 409.
   - **Idempotent**: an existing `CREATED` Payment for this booking returns the SAME
     `{orderId, amountPaise, keyId}` (no duplicate orders from double-taps). CAPTURED → 409
     "already paid".
   - Else: compute the amount → create the gateway order → persist the Payment row (CREATED) +
     `PAYMENT_EVENT` audit (`{bookingId, event: 'order_created', amountPaise}`) in one tx.
     (Order-create precedes the tx; an orphaned gateway order from a tx failure is harmless —
     unpaid orders expire gateway-side.)
   - Returns `{orderId, amountPaise, keyId}` — the app opens Razorpay checkout with these.
2. **`POST /webhooks/razorpay`** (NO requireAuth — the signature IS the authentication):
   - Fastify raw-body capture for this route only; missing/invalid signature → 401 (no detail).
   - `payment.captured`: look up the Payment by `razorpayOrderId` → **verify the captured amount
     equals `Payment.amountPaise`** (mismatch → `PAYMENT_EVENT` audit `{event: 'amount_mismatch'}`,
     no transition, 200-acknowledge so the gateway stops retrying, ops investigates) → in one tx:
     Payment→CAPTURED (+`razorpayPaymentId`, `capturedAt`) + `transitionBooking(booking,
     'PAYMENT_RECEIVED', SYSTEM, {razorpayPaymentId, amountPaise, method: 'UPI'})`.
     **Duplicate-delivery idempotency**: the transition's optimistic lock (state no longer matches)
     and the Payment's status guard make a second delivery a no-op → 200 acknowledged.
   - `payment.failed`: Payment→FAILED (+`failureReason` from the event, no PII) + audit; the
     booking stays put; a later `pay` creates a NEW order (the failed row remains as history).
   - Unknown/`refund.*` events: 200 acknowledged, audited (`{event: 'ignored', type}`), no action —
     the B7 skeleton.
3. **DTO**: `BookingDto` += `payment: {status, method, amountPaise} | null` (latest attempt;
   no gateway ids leaked to the app beyond what checkout needs from `pay`).

## Golden Rules check

- **Rule 1 (money needs evidence):** PAYMENT_RECEIVED requires the gateway's signed capture event
  for the exact ordered amount — the money provably moved before the state does.
- **Rule 2 (no single party):** SYSTEM transitions on the *gateway's* word; neither customer nor
  technician can claim payment. (The customer's consents: completion OTP + their UPI-app approval.)
- **Rule 3 (platform holds cash):** funds land in the platform's Razorpay account. The technician
  never touches UPI money. (Cash = B6b, with its friction by design.)
- **Rule 4:** the charge amount is the frozen approved total — `chargeAmountFor` reads snapshots
  only.
- **Rule 5:** Payment mutation + transition + audit in one tx.
- **Rule 7:** no card/UPI-VPA details stored or logged — Razorpay ids only; webhook bodies are not
  logged raw.

## Vendor reality (shippable now)

Everything in B6a runs on Razorpay **test keys** today; live keys swap in post-KYC with zero code
change. Route splits are NOT in this slice (manual settlement = B6c). No SMS dependency.

## Testing (Dev gateway only — no network)

- pay: happy path (row + audit), idempotent re-pay (same order), already-captured 409, wrong-state
  409, foreign customer 404, technician 403.
- webhook: valid capture → CAPTURED + PAYMENT_RECEIVED + evidence audit; duplicate delivery →
  single transition + 200; bad signature → 401; amount mismatch → flagged, no transition;
  failed → FAILED + re-pay issues a new order; unknown event → 200 ignored+audited.
- declined booking: pay charges exactly `visitFeePaise`; DECLINED_BY_CUSTOMER → PAYMENT_RECEIVED.
- E2E: both keystones → pay → signed webhook → PAYMENT_RECEIVED.
- Actor unit: PAYMENT_RECEIVED is SYSTEM-only; CLOSED still default-denied.
