# Customer App Slice 5 — Payment (Design)

**Date:** 2026-09-12
**Branch:** `feature/customer-app-slice5-payment`
**Status:** Approved design → ready for plan
**ADR:** `docs/adrs/ADR-0006-razorpay-flutter-checkout.md` (new native dep)
**Builds on:** Slice 4 tracking (merged PR #30) — payment rides the existing poll.

---

## Goal

Replace the Slice-4 "payment coming soon" placeholder (the `_PhaseSummary`
`payment`/`declined` branches in `booking_tracking_screen.dart`) with a real pay
card offering **UPI** (Razorpay checkout) and **Cash** (receipt-OTP handshake), at
the two payable states:

- `CUSTOMER_CONFIRMED` → the approved total (`estimate.totalPayablePaise`)
- `DECLINED_BY_CUSTOMER` → the visit fee only (`visitFeePaise`)

## Non-goals (deliberate, not omissions)

- **The app never submits the cash OTP.** The customer reads the SMS'd 6-digit code
  to the technician, who submits it at `POST /technician/jobs/:id/confirm-cash`. The
  customer app only *displays* the code. (Keystone asymmetry, like completion.)
- **No client-trusted "paid" state.** UPI confirmation is webhook-driven server-side
  (`POST /webhooks/razorpay` → `PAYMENT_RECEIVED`). The checkout success callback only
  triggers a refetch; `paid` comes only from the polled DTO (`payment.status ==
  CAPTURED`). Golden Rule 1: money moves on gateway evidence, not client claims.
- **No new polling.** Payment rides Slice-4's `BookingTracking` controller.
- **No backend change.** Both endpoints already exist and are bodyless.

---

## Backend contract (verified against `apps/backend/`)

Both endpoints: `requireAuth` + `requireCustomerRole`; foreign booking id → 404 (no
IDOR); **no request body** (the server computes the amount via `chargeAmountFor`).

### `POST /me/bookings/:id/pay` (UPI)
- Success: `{ orderId: string, amountPaise: number, keyId: string | null }`
  (`keyId = RAZORPAY_KEY_ID ?? null` — **null in dev / without keys**).
- Valid-from: `CUSTOMER_CONFIRMED` (approved total) or `DECLINED_BY_CUSTOMER` (visit fee).
- Idempotent re-tap: returns the SAME `orderId` for an open UPI `CREATED` attempt.
- Errors: 409 `"This booking is already paid"`; 409 `"Booking is not awaiting payment"`;
  422 `"Nothing is payable for this booking"`; 404 `"Booking not found"`.

### `POST /me/bookings/:id/pay-cash` (cash)
- Success: `{ amountPaise: number, devOtp?: string }` — receipt OTP SMS'd to the
  customer; `devOtp` present only when `NODE_ENV !== 'production'`.
- Valid-from: same two states.
- Errors: 409 `"This booking is already paid"` / `"Booking is not awaiting payment"`;
  422 `"Nothing is payable for this booking"`; 422 `"Cash is unavailable for this
  booking — please pay by UPI"`; 422 `"Cash limit reached for this technician —
  please pay by UPI"`; 429 `"Too many code requests. Try again later."`
- OTP: 6 digits, TTL 600s, 3 sends / 900s, 5 verify attempts.

### UPI confirmation (webhook — server-side, not the app)
`POST /webhooks/razorpay`, HMAC-verified, amount-checked (`entity.amount ==
payment.amountPaise` or no transition), idempotent → booking `PAYMENT_RECEIVED` as
`SYSTEM`, `payment.status = CAPTURED`. The app never calls this.

### Cash confirmation (technician — not the app)
`POST /technician/jobs/:id/confirm-cash`, body `{code: 6 digits}` → `PAYMENT_RECEIVED`
as `TECHNICIAN`. The customer app does NOT call this. (No technician app yet — for
testing, drive it via curl with the `devOtp`.)

### `PaymentSummary` on `BookingDto` (already modeled app-side)
`{ status, method, amountPaise }` only — no gateway ids. `status ∈ {CREATED, CAPTURED,
FAILED}`; `method ∈ {UPI, CASH}`. Non-null once ≥1 pay attempt exists; the summary is
the `CAPTURED` one if any, else the latest attempt.

---

## Architecture & data flow

### Repository — extend `BookingRepository`
- `initiatePayment(id) -> Result<PaymentInitDto>` → bodyless `POST …/pay`.
- `initiateCashPayment(id) -> Result<CashInitDto>` → bodyless `POST …/pay-cash`.

New freezed DTOs (in `booking_dtos.dart`):
- `PaymentInitDto { required String orderId, required int amountPaise, String? keyId }`
- `CashInitDto { required int amountPaise, String? devOtp }`

### UPI checkout — `RazorpayCheckout` service (wraps `razorpay_flutter`)
The plugin is callback-based (`EventChannel`) and leaks native listeners if not
cleared. Wrap it: `Future<CheckoutOutcome> open({keyId, orderId, amountPaise, name,
description, prefillContact?})` that registers `PAYMENT_SUCCESS`/`PAYMENT_ERROR`/
`EXTERNAL_WALLET`, completes on the first, and **always `clear()`s in `finally`**.
`CheckoutOutcome = success(paymentId, signature) | failed(code, message) |
dismissed`. Exposed via `razorpayCheckoutProvider` (fakeable in tests; real plugin
on-device only).

**UPI flow:** tap "Pay by UPI" → `initiatePayment` → if `keyId == null` show "UPI
unavailable — pay by cash" (no plugin call); else `open(...)`. On `success`, show
`upiPending` + `refetch()` (webhook is the source of truth); on `failed`/`dismissed`
→ back to `choose` with the message (dismiss is quiet).

**Cash flow:** tap "Pay cash" → `initiateCashPayment` → show the OTP panel ("read
this to your technician", dev echoes `devOtp` behind `!kReleaseMode`, `Key('devCashOtp')`)
+ "waiting for confirmation". Poll resolves `→ PAYMENT_RECEIVED` when the technician
confirms. The customer never submits the code.

---

## The pay-state model

Payment is a sub-state of the payable phases, derived by a pure
`payViewFor(BookingDto) -> PayView` (mirrors Slice-4's `phaseFor`; Flutter-free,
exhaustively tested). `payableAmountPaise(BookingDto)` returns the pre-init amount.

| state + payment | PayView | Card |
|---|---|---|
| payable, `payment == null` | `choose` | amount owed + **Pay by UPI** / **Pay cash** |
| payable, `CREATED`/`UPI` | `upiPending` | "Confirming your payment…" + retry escape |
| payable, `CREATED`/`CASH` | `cashPending` | OTP panel + "waiting for the technician" |
| payable, `FAILED` | `choose` (+ "didn't go through") | the two buttons again |
| `CAPTURED` (state ≥ PAYMENT_RECEIVED) | `paid` | ✓ "Paid — {method}, {amount}" |
| non-payable state | `none` | pay card hidden |

- **Payable states:** `CUSTOMER_CONFIRMED` and `DECLINED_BY_CUSTOMER`. The declined
  branch (visit fee owed) now shows the same pay card instead of a static note.
- **Amount source:** before init, `payableAmountPaise` (estimate total / visit fee);
  after init, the `amountPaise` from the `/pay`|`/pay-cash` response (server's
  authoritative figure). The app never computes the charge.
- `paid` is reached **only via the poll** — never set from the checkout callback.

---

## Error handling

Never swallow a `Failure` — map each to visible UX, surfacing the backend message:
- `initiatePayment`: 409/422/404 → SnackBar with the message; idempotent same-`orderId`
  re-tap is not an error (re-open checkout).
- `initiateCashPayment`: 409/422 (incl. "Cash is unavailable…", "Cash limit reached…")
  → inline on the cash control; 429 "Too many code requests…" → message + brief
  button disable.
- `RazorpayCheckout`: `failed(code,message)` → SnackBar, back to `choose`; `dismissed`
  → quiet, back to `choose`; `success` → `upiPending` + `refetch()` (NOT paid).
- **`keyId == null`** → first-class "UPI unavailable" branch, cash still offered.
- **Stale-state race:** a pay tap on a stale card yields a 409 → SnackBar; the poll
  reconciles. Cards derive from the current DTO, so this self-heals. A gate call in
  flight disables that card's buttons (per-card busy flag).

---

## Files

**ADR:** `docs/adrs/ADR-0006-razorpay-flutter-checkout.md` (new).

**Data:**
- `booking/data/booking_dtos.dart` — **add** `PaymentInitDto`, `CashInitDto`.
- `booking/data/booking_repository.dart` — **add** `initiatePayment`, `initiateCashPayment`.

**Presentation:**
- `booking/presentation/pay_view.dart` — **new, pure:** `PayView` enum, `payViewFor`,
  `payableAmountPaise`.
- `booking/presentation/razorpay_checkout.dart` — **new:** `RazorpayCheckout` +
  `CheckoutOutcome` + `razorpayCheckoutProvider`.
- `booking/presentation/booking_tracking_screen.dart` — **modify:** replace the
  `_PhaseSummary` payment/declined placeholder with `_PayCard` (`payViewFor`-driven),
  split into `_PayChoose`/`_UpiPending`/`_CashPending`/`_PaidReceipt`.

**Native config:**
- `android/app/proguard-rules.pro` — Razorpay ProGuard keep rules.
- `pubspec.yaml` — add `razorpay_flutter` (pinned). iOS pods via `flutter build`/`run`.

**Reuse:** `rupees()`, `FixCareColors/Radii`, the `Result` idiom, Slice-4's
`BookingTracking` controller + `refetch()`.

---

## Testing strategy

Bar: `flutter analyze` 0 issues; hermetic (mock transport / fake the plugin); TDD.

1. **`pay_view.dart` — pure unit tests.** Table over (state × payment) → `PayView`:
   choose / upiPending / cashPending / choose(FAILED) / paid; declined-unpaid →
   choose, declined-paid → paid; non-payable → none. `payableAmountPaise`:
   CUSTOMER_CONFIRMED → estimate total, DECLINED → visit fee.
2. **Repository — contract-guarded** (`FullHttpRequestMatcher(needsExactBody: true)`):
   both are bodyless POSTs (no body stamped); parse `{orderId, amountPaise, keyId}`
   incl. `keyId: null`; parse `{amountPaise, devOtp}` + prod `{amountPaise}`;
   409/422/429/404 → right `FailureKind` + exact backend message.
3. **`RazorpayCheckout` — via a fake plugin seam:** success → `CheckoutOutcome.success`;
   error → `.failed(code,message)`; `clear()` always called (leak guard).
4. **Widget — `ProviderScope` overrides** (fake repo recording calls + fake
   `razorpayCheckoutProvider`): `choose` shows both buttons + estimate amount; Pay-UPI
   with `keyId != null` + fake success → `refetch` fired + `upiPending`; **`keyId ==
   null` → checkout never opened, "UPI unavailable" + cash offered**; Pay-cash →
   `initiateCashPayment` called, on `Ok(devOtp:'654321')` the OTP panel +
   `Key('devCashOtp')` `654321` render and there is **no customer submit/verify
   control** (asserts absence); `FAILED` → "didn't go through" + buttons; `CAPTURED` →
   paid receipt, no buttons; cash 429 → message + brief disable; declined-unpaid →
   card shows the visit fee amount.

**Deferred follow-up (noted, not built):** real-backend smoke proof of `/pay` +
`/pay-cash` once Razorpay TEST keys are configured and the technician `confirm-cash`
actor is drivable (same harness gap as Slice 4's gate endpoints).

---

## Carry-forwards honored

- Both pay calls are bodyless — the app never sends an amount, a customer id, or a
  client-snapshotted price; the server computes the charge.
- No PII sent or logged; the cash devOtp never renders in a release build.
- Payment confirmation is webhook/technician-driven server-side — the app trusts the
  polled DTO, never its own checkout callback, for `paid`.
