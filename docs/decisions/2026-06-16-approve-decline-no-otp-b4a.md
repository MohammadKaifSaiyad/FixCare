# Decision: B4a customer approve/decline has no evidence token (OTP deferred)

_Date: 2026-06-16 · Scope: booking B4a (diagnosis + parts cart) · Status: accepted_

## Context

The `golden-rules-auditor` review of B4a flagged that `POST /me/bookings/:id/approve`
and `/decline` accept a single authenticated, owner-scoped POST with **no evidence
token** (no OTP, no confirmation PIN). Because this decision routes whether B6 will
later charge the full estimate (labor + parts − visit-fee credit) or only the visit
fee, the auditor classified it as a single-party money-routing decision (Golden Rules
1 and 2).

## Decision

For B4a, approve/decline stays a plain `requireAuth` + `requireCustomerRole` +
owner-scoped (`{id, customerId}` → 404 on miss) call. **No OTP / confirmation token is
added in this slice.** We revisit a customer-side confirmation token when the shared
single-use OTP primitive is extracted (planned before B5, the completion handshake).

## Why this is acceptable for B4a

- **No money moves in B4a.** The charge (and the Razorpay path) is the B6 slice.
  Approve/decline only changes booking state (`DIAGNOSED → CUSTOMER_APPROVED` /
  `DECLINED_BY_CUSTOMER`); no debit, credit, or payout occurs.
- **The visit fee is already locked at ARRIVED** (B3, the arrival keystone, which *is*
  two-sided: GPS + single-use code). Declining does not refund it, so a stray decline
  cannot move money the customer already owes.
- **Actor separation already holds.** `ALLOWED_ACTORS` enforces `CUSTOMER_APPROVED`/
  `DECLINED_BY_CUSTOMER` = `CUSTOMER`-only and `DIAGNOSED` = `TECHNICIAN`-only, via
  `transitionBooking`. The technician cannot approve; the customer cannot diagnose.
  The diagnosis→approval handoff is therefore genuinely two-sided at the *actor* level.
- **Both transitions now carry audit evidence** (`source: customer_approval|customer_decline`,
  the frozen cart's `partCount`/`partsTotalPaise`), read inside the same transaction as
  the state change — so the approved cart is captured at the moment of approval.

## What we will do before/at B6 (the real money-movement slice)

- Build the shared single-use, rate-limited, short-lived OTP/challenge primitive
  (also needed by B5's completion handshake) and require a customer-supplied
  confirmation token on the charge-gating action.
- Re-evaluate whether approve itself (vs. the B6 charge step) is the right place to
  bind the OTP, now that the primitive exists.

## Revisit trigger

When the shared OTP primitive lands (pre-B5), and again when B6 introduces the charge.
Until then this decision stands. See [[booking-zone-price-snapshot]] and the B4a design
(`docs/designs/2026-06-14-booking-b4a-diagnosis-design.md`).

---

## Resolution (2026-07-13, B5)

The customer confirmation token is NOT bound to approve/decline. B5's completion OTP is the
customer's money-gating confirmation — payment cannot unlock without a code that only the
customer's phone received. A second OTP at approve would double per-booking friction for a
pre-payment action that already has actor separation and frozen-cart audit evidence.
**B6 (the charge) re-evaluates binding a token at the charge step**, per this decision's
original framing ("the charge-gating action").

---

## Final (2026-07-18, B6a)

No charge-time OTP. The completion OTP (B5) plus the customer's own UPI-app authorization are the
two confirmations; a third adds friction without evidence value. Cash (B6b) has its own receipt
OTP by design. This closes the question this document opened.
