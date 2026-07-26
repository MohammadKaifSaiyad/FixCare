# Booking B6c — Settlement Ledger + CLOSED Wiring (design)

**Date:** 2026-07-19 · **Branch:** `feature/booking-b6c-settlement` · **Status:** approved
**Follows:** B6b (cash path, PR #19). **Precedes:** B7 (disputes).

## Goal

Close the money loop: paid bookings CLOSE after the 48h dispute window, technician earnings
(80% of labor / visit fee per `pricing-model.md`) are booked to an append-only ledger, cash
debt auto-nets against earnings, and the platform's 20% commission is recorded per job.
Payouts and debt repayments are manual admin records until Razorpay Route approval. This is
also the codebase's **first background work** (BullMQ, the locked stack) and it folds in the
B6b schema carry-forwards.

## Scope decisions (settled with the founder)

| Question | Decision |
|---|---|
| Close driver | **BullMQ repeatable sweep** (~15 min): the locked stack, Redis already runs, B2b's accept-timer reuses the same infra. The sweep function is a plain exported service function — tests call it directly, no timers. |
| Debt vs earnings | **Auto-offset at close**: `CASH_DEBT_OFFSET` consumes `min(earning, debt)` — a cash-collecting technician already holds the money; payouts move only the remainder. Debt self-heals with honest work. |
| Zero-payable settlement | **At the completion handshake**: `confirmCompletion` chains CUSTOMER_CONFIRMED → PAYMENT_RECEIVED (SYSTEM, `{amountPaise: 0, reason: 'zero_payable'}`) in the same tx. No ₹0 pay screen; the sweep closes it normally. |
| Commission rate source | **Config constant now** (`COMMISSION_RATE_BPS` = 2000), **ledger snapshots the rate + computed paise at close** — later rate changes never rewrite history. Trust-tier commission later swaps the constant for a computed value; the ledger shape is stable. |
| Accept-gate | **Ships now** (B6b deferral honored): `acceptJob` 422s at `cashDebtPaise >= CASH_DEBT_LIMIT_PAISE`. Safe because auto-offset gives a self-healing path out. |
| Technician balance surface | `GET /technician/me/balance` (dashboard header) — resolves the B6b "cashDebtPaise on job DTO" deviation: a balance endpoint, not per-job duplication. |

## Ledger model (the heart)

Append-only `LedgerEntry` — no updates, no deletes, no soft-delete (same evidence posture as
`Payment`):

```
id            uuid
technicianId  FK Technician
bookingId     FK Booking, nullable (payouts/repayments have no booking)
type          LedgerEntryType
amountPaise   Int  (always POSITIVE; type carries the direction)
metadata      Json (rate bps used, source, offset pairing)
createdAt     @default(now())
@@index([technicianId, createdAt])
```

`LedgerEntryType`:
- `EARNING_CREDIT` — technician's 80% share, booked at close.
- `COMMISSION` — platform's 20%, booked explicitly at close (revenue is queryable per job).
- `CASH_COLLECTED` — written by `confirmCashPayment` in its capture tx from B6c onward; the
  ledger becomes the debt source of truth B6b promised, `Technician.cashDebtPaise` stays the
  cached balance.
- `CASH_DEBT_OFFSET` — the auto-net at close: consumes both debt and payable.
- `PAYOUT` — manual admin record of money paid out (until Route).
- `DEBT_REPAYMENT` — manual admin record of cash returned by the technician.

Derived balances (both reconcilable from entries alone):
- **payable** = Σ EARNING_CREDIT − Σ CASH_DEBT_OFFSET − Σ PAYOUT
- **debt** = Σ CASH_COLLECTED − Σ CASH_DEBT_OFFSET − Σ DEBT_REPAYMENT (= cached column)

Earning base (per the `pricing-model.md` split table): DECLINED booking (visit-fee
settlement) → 80% × `visitFeePaise`; confirmed repair → 80% × `laborPaise`. Parts money is
merchant-domain (no merchant linkage exists yet) — it stays with the platform in V1
accounting; recorded as out of scope.

## Schema changes (one migration: `settlement_ledger`)

- `LedgerEntry` + `LedgerEntryType` (above).
- `Booking.paidAt DateTime?` — set by BOTH capture paths (UPI webhook tx, confirm-cash tx)
  and by the zero-payable chain. The sweep keys on it (never on `updatedAt`).
- `Booking.closedAt DateTime?` — set by the sweep.
- `AuditAction.SETTLEMENT_EVENT`.
- `ALLOWED_ACTORS.CLOSED: ['SYSTEM']` (B7 adds ADMIN for dispute closes).
- **B6b carry-forwards folded in:** raw-SQL `CHECK ("cashDebtPaise" >= 0)` on Technician
  (mandatory now that decrements exist — a settlement bug must never produce a negative
  balance that disables the B6b gates); `@@index([method, status, capturedAt])` on Payment
  (the velocity aggregate runs inside the capture lock); schema comment that
  `PaymentStatus.FAILED` is UPI-only… **amended:** the sweep now also marks stale CASH
  CREATED attempts FAILED at close (orphan cleanup), so the comment instead documents both
  writers.
- Config: `COMMISSION_RATE_BPS` (2000), `DISPUTE_WINDOW_HOURS` (48),
  `SETTLEMENT_SWEEP_INTERVAL_MINUTES` (15).

## The close sweep

Minimal BullMQ infra in `shared/queue/`: one connection from `REDIS_URL`, one repeatable
job registered at boot (skipped in tests), worker runs in-process (single instance V1 —
B2b's accept-timer reuses this scaffolding). The job handler calls the exported service
function `settleClosableBookings()`:

1. Find `Booking WHERE state = PAYMENT_RECEIVED AND paidAt <= now − DISPUTE_WINDOW_HOURS
   AND deletedAt IS NULL` (bounded batch, e.g. 100/run).
2. Per booking, ONE transaction:
   a. `transitionBooking(CLOSED, SYSTEM 'settlement-sweep')` — the optimistic lock makes a
      double-fired sweep 409 and skip (idempotency).
   b. Compute the earning base from snapshots (`declinedAt` ⇒ visit fee, else labor);
      `earning = base × (10000 − COMMISSION_RATE_BPS) / 10000` (integer floor);
      `commission = base − earning` (the two always sum exactly to base).
   c. Write `EARNING_CREDIT` + `COMMISSION` with `{rateBps, basePaise}` metadata.
   d. Lock the technician row (the B6b idiom: the update IS the lock), offset
      `min(earning, cashDebtPaise)` — if > 0, write `CASH_DEBT_OFFSET` and decrement
      `cashDebtPaise`.
   e. Mark any stale CASH `CREATED` attempts for this booking `FAILED`
      (`failureReason: 'superseded_at_close'`) — the B6b orphan cleanup.
   f. Set `closedAt`; audit `SETTLEMENT_EVENT` `{bookingId, earningPaise, commissionPaise,
      offsetPaise}`.
3. Per-booking try/catch: one failed booking (e.g. 409 race) never aborts the batch.

## Zero-payable chain

In `confirmCompletion`, after the CUSTOMER_CONFIRMED transition, compute
`chargeAmountFor`-equivalent in-tx; if 0 → `transitionBooking(PAYMENT_RECEIVED, SYSTEM
'zero-payable', {amountPaise: 0, reason: 'zero_payable'})` + `paidAt`, same transaction.
The earning still credits at close — the technician did the work; the visit fee credit is
customer-facing pricing, not a technician penalty.

## Accept-gate

`acceptJob` (technician-jobs): after the existing guards, `cashDebtPaise >=
CASH_DEBT_LIMIT_PAISE` → 422 "Settle your cash debt to accept new jobs". Read fresh in the
accept transaction (not from a stale profile read).

## Endpoints

- **`GET /technician/me/balance`** (technician): `{payablePaise, cashDebtPaise}` — payable
  derived from the ledger, debt from the cached column (self-check: log mismatch as a
  `SETTLEMENT_EVENT reconciliation_mismatch` flag, return the ledger-derived value).
- **`POST /admin/settlements/payouts`** (MANAGER+): `{technicianId, amountPaise}` —
  1 ≤ amount ≤ payable else 409; `PAYOUT` entry + audit in-tx.
- **`POST /admin/settlements/repayments`** (MANAGER+): `{technicianId, amountPaise}` —
  1 ≤ amount ≤ debt else 409; `DEBT_REPAYMENT` entry + debt decrement (row-lock) + audit
  in-tx.
- **`GET /admin/settlements/technicians/:id`** (MANAGER+): balances + recent entries
  (paginated, newest first).

## Error handling

Typed errors throughout (404 unknown technician, 409 over-balance, 422 gates, 400 Zod).
Amounts validated as positive integers (`assertValidPaise` semantics). No PII anywhere in
ledger metadata or audits (ids + paise + bps only). Sweep failures log per booking and
continue.

## Testing

- Sweep (direct function calls, no timers): closes only `paidAt` older than 48h; boundary
  at exactly 48h; full ledger assertions per close (earning + commission sum to base, rate
  snapshot recorded); netting math — earning > debt (debt → 0, remainder payable),
  earning < debt (debt reduced, payable 0), zero debt (no offset entry); double-run
  idempotency (second run writes NOTHING); stale CASH CREATED → FAILED; declined-booking
  earning = 80% of visit fee.
- Zero-payable: completion chains to PAYMENT_RECEIVED with `paidAt`; sweep then closes and
  credits the earning.
- Accept-gate: 422 at limit; accepting works again after an offset/repayment brings debt
  down.
- Admin: payout > payable 409; repayment > debt 409; happy paths write ledger + audit +
  (repayment) debt decrement; role walls (technician → 403).
- Balance endpoint: matches ledger-derived values after a mixed history.
- CHECK constraint: raw update to negative debt rejected by Postgres.

## Out of scope (recorded)

Merchant payouts (no merchant-booking linkage yet) · DISPUTED flows + payout holds (B7) ·
Razorpay Route split automation (post-approval: PAYOUT entries become Route transfers) ·
trust-tier commission/limits (trust module) · customer wallet credits (pricing bonuses).
