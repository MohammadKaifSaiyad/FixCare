# Booking B7 — Disputes (design)

**Date:** 2026-07-26 · **Branch:** `feature/booking-b7-disputes` · **Status:** approved
**Follows:** B6c (settlement ledger + CLOSED sweep, PR #20). Completes the booking money/trust loop.

## Goal

Ship the dispute *mechanism*, minimally: a customer raises a dispute on a paid-but-not-yet-closed
booking, which **holds the payout** (the B6c sweep already skips non-`PAYMENT_RECEIVED` bookings);
an admin adjudicates with an outcome + optional refund; the ledger reverses/credits accordingly and
the booking closes. This is exactly the `dispute-resolution.md` posture for V1 — "manual review is
fine at <1000 jobs/month… don't build automated Tier 1… it teaches you the patterns."

## Scope decisions (settled with the founder)

| Question | Decision |
|---|---|
| Payout hold | **DISPUTED excluded from the sweep.** Raise flips PAYMENT_RECEIVED → DISPUTED; B6c's `state='PAYMENT_RECEIVED'` sweep filter already skips it → no earning credited, payout held, until resolution. |
| Who raises / from where | **Customer only, from PAYMENT_RECEIVED only, within the 48h window.** Post-CLOSED complaints/warranty are a separate slice. |
| Resolution money | **Ledger reversal/credit now; refund via Razorpay refund API (UPI) confirmed by webhook, or manual record (cash)** — same manual-until-Route posture as B6c payouts. |
| Tiers / appeals / abuse / dashboard | **Deferred (V2 / admin-dashboard-dependent, ADR-0004).** B7 = manual MANAGER+ adjudication only. |
| Dispute record | **Dedicated `Dispute` model** (case file); `Booking.state=DISPUTED` is the money-hold signal. |

## Data model (one additive migration: `dispute`)

```prisma
model Dispute {
  id              String         @id @default(uuid())
  bookingId       String
  booking         Booking        @relation(fields: [bookingId], references: [id])
  raisedByUserId  String
  reason          String // customer's free text, length-capped (Zod ≤ 500) — assumed non-PII, but see note
  status          DisputeStatus  @default(OPEN)
  outcome         DisputeOutcome? // set at resolution
  refundPaise     Int? // customer refund at resolution; null/0 for FAVOR_TECHNICIAN
  resolvedByUserId String?
  resolvedAt      DateTime?
  createdAt       DateTime       @default(now())
  updatedAt       DateTime       @updatedAt
  @@index([bookingId])
  @@index([status]) // the admin OPEN queue
}
enum DisputeStatus { OPEN RESOLVED }
enum DisputeOutcome { FAVOR_CUSTOMER FAVOR_TECHNICIAN PARTIAL }
```

- **Partial unique index** (raw SQL in the migration): `CREATE UNIQUE INDEX "Dispute_one_open_per_booking" ON "Dispute"("bookingId") WHERE status = 'OPEN';` — one open dispute per booking; the DB backstops a double-raise race.
- `LedgerEntryType += DISPUTE_REVERSAL`; `AuditAction += DISPUTE_EVENT`.
- Actor gates: `ALLOWED_ACTORS.DISPUTED: ['CUSTOMER']`; `CLOSED` widens `['SYSTEM']` → `['SYSTEM', 'ADMIN']` (sweep stays SYSTEM; dispute-close is ADMIN — the entry B6c's review flagged as needed for B7).
- `Booking.disputes Dispute[]` back-relation. `reason` is customer free-text: flagged assumed-non-PII and length-capped; NOT logged in audit metadata (only ids/enums/paise go to audits).

## Raise — `POST /me/bookings/:id/raise-dispute { reason }` (CUSTOMER, owner-scoped)

Guards in order:
1. Auth → role 403 → owner `findFirst` 404.
2. State must be `PAYMENT_RECEIVED` → else 409 ("this booking can't be disputed" — unpaid or already closed).
3. Within window: `booking.paidAt > now − DISPUTE_WINDOW_HOURS` → else 409 ("the dispute window has passed"). Same 48h the sweep uses, so raise and close never race ambiguously (a booking past 48h is already CLOSED or about to be; the state check catches CLOSED).
4. No existing OPEN dispute (checked, and the partial unique index backstops the race) → else 409.

One transaction: `Dispute {OPEN, reason}` + `transitionBooking(DISPUTED, {USER, CUSTOMER, userId}, { disputed: true })` + `DISPUTE_EVENT` audit `{event: 'raised', bookingId, disputeId}`. The booking is now DISPUTED → held.

## Resolve — `POST /admin/disputes/:id/resolve { outcome, refundPaise?, reason }` (MANAGER+)

Validation:
- Dispute must be OPEN (409).
- `chargePaid` = what the customer actually paid = `chargeAmountFor` snapshot for the booking (the captured amount). `refundPaise`:
  - `FAVOR_CUSTOMER`: required, must equal `chargePaid` (full refund).
  - `PARTIAL`: required, `1 ≤ refundPaise < chargePaid`.
  - `FAVOR_TECHNICIAN`: must be absent or 0.
  - else 400.

One transaction:
1. `Dispute` → RESOLVED with `outcome, refundPaise, resolvedByUserId, resolvedAt`.
2. **Ledger (source of truth).** The booking was never swept, so there is no prior EARNING_CREDIT to claw back — resolution books forward from the base (`declinedAt ? visitFeePaise : laborPaise`):
   - technician's kept base = `base − (refundPaise scaled to the technician's share)`. Simpler and conservation-safe: split the **retained amount** (`base − refundPaise`, floored at 0) via `splitPaise` → `EARNING_CREDIT` + `COMMISSION`; write a `DISPUTE_REVERSAL` entry for `refundPaise` (the money leaving to the customer). FAVOR_TECHNICIAN → refund 0 → full base credited, no reversal entry. FAVOR_CUSTOMER → retained 0 → no earning/commission, one `DISPUTE_REVERSAL` for the full charge.
   - Skip zero-amount entries (the B6c invariant — no 0-paise rows).
   - Auto-offset cash debt against the earning (same FOR-UPDATE-locked idiom as the sweep) if any.
3. **Refund (money out).** UPI booking → `paymentGateway.refund(razorpayPaymentId, refundPaise)` (new wrapper method); the `refund.processed` webhook confirms and is now a real handler (records the confirmed refund + is idempotent on `refundId`). Cash booking → recorded as a manual refund (`DISPUTE_EVENT {event:'manual_refund_recorded'}`), no gateway call. `refundPaise==0` (FAVOR_TECHNICIAN) → no refund step.
4. `transitionBooking(CLOSED, {SYSTEM/ADMIN}, { outcome, refundPaise })` + `closedAt` + `DISPUTE_EVENT` audit `{event:'resolved', disputeId, outcome, refundPaise}`.

## Gateway wrapper

`PaymentGateway` gains `refund(paymentId: string, amountPaise: number): Promise<{ refundId: string }>`.
Dev stub: deterministic `rfnd_dev_*`. Real: `razorpay.payments.refund(paymentId, { amount })`, typed-boundary error wrap. Webhook: `refund.processed` / `refund.failed` handled under the same HMAC-signature gate as capture; idempotent on `refundId` (a new `Payment.razorpayRefundId? @unique` anchor, or a dispute-side marker — decided in the plan).

## DTOs

- `BookingDto.dispute` summary: `{ status, outcome, refundPaise } | null` (no reason/PII).
- Admin: `GET /admin/disputes/:id` (case file), `GET /admin/disputes?status=OPEN` (queue, paginated).

## Error handling

Typed errors (404/403/409/400) via the map. Refund amount validated against the real captured
charge (no over-refund). Ledger conservation asserted in tests. No PII in audits (ids/enums/paise;
never the reason text). All money mutations audited in-tx.

## Testing

- **Raise:** window boundary (just-inside OK, past-48h 409), non-PAYMENT_RECEIVED 409 (CLOSED, CUSTOMER_CONFIRMED), non-owner 404, technician role 403, double-raise → 409 (unique index), and **the sweep skips a DISPUTED booking** (seed DISPUTED + paidAt>48h → `settleClosableBookings` closes 0).
- **Resolve:** each outcome's ledger math + money conservation (retained + refund == base); FAVOR_TECHNICIAN full credit no reversal; FAVOR_CUSTOMER no credit + full reversal; PARTIAL split; refund > charge 400, refund on FAVOR_TECHNICIAN 400; UPI resolve calls `gateway.refund` and the `refund.processed` webhook records it (idempotent on redelivery); cash resolve records a manual refund, no gateway call; cash-debt auto-offset on the credited earning; DISPUTED→CLOSED; non-MANAGER 403; resolve-already-RESOLVED 409.
- **Actor-unit:** `DISPUTED` allows CUSTOMER only; `CLOSED` allows SYSTEM + ADMIN, denies CUSTOMER/TECHNICIAN.
- **DTO:** dispute summary present, no reason leaked.

## Out of scope (recorded)

Tier auto-resolve (≤₹500) · human/senior SLA tiers · appeals · customer/technician abuse-detection ·
dispute dashboard/analytics · technician-raised disputes · merchant part-defect holds ·
deposit/earnings damage deduction (Scenario 5) · 7-day rework / 30-day warranty & complaint path ·
insurance. All V2 or admin-dashboard-dependent per dispute-resolution.md + ADR-0004.
