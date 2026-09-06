# Customer App Slice 4 — Booking Tracking (Design)

**Date:** 2026-09-06
**Branch:** `feature/customer-app-slice4-booking-tracking`
**Status:** Approved design → ready for plan
**Supersedes:** the Slice-3 tracking *stub* (`booking_tracking_screen.dart`)

---

## Goal

Replace the one-shot tracking stub at `/booking/:id` with a live, state-driven
tracking screen that:

1. **polls** `GET /me/bookings/:id` to stay current (adaptive: stops at terminal
   states, pauses when backgrounded);
2. renders the full **17-state** booking lifecycle as customer-facing phases;
3. drives the three **customer-side keystone gates** — confirm-arrival,
   approve/decline diagnosis, completion-OTP mint.

Payment (the Razorpay pay / cash flow) is **deferred to Slice 5** (blocked on
Razorpay KYC); this slice shows the amount owed and a "payment coming soon"
placeholder at payable states.

## Non-goals (deliberate, not omissions)

- **No live GPS map / WebSocket.** The backend exposes no location stream to the
  customer (arrival GPS is record-only, never in the DTO). Slice 4 tracks *state*,
  not a moving dot. That's a later slice with its own backend work.
- **No payment execution.** Deferred to Slice 5.
- **No backend change.** The `address` field is only `{id}`; we join the label
  app-side from the existing `/me/addresses` list.

---

## The backend contract (verified against `apps/backend/`)

### State graph (17 states) + customer-driven transitions

`ALLOWED_TRANSITIONS` (`bookings.state.ts`), verbatim order:

```
CREATED            -> DISPATCHED | CANCELLED_BY_CUSTOMER
DISPATCHED         -> ACCEPTED | CANCELLED_BY_CUSTOMER | CANCELLED_BY_TECHNICIAN
ACCEPTED           -> EN_ROUTE | CANCELLED_BY_CUSTOMER | CANCELLED_BY_TECHNICIAN
EN_ROUTE           -> ARRIVED | CANCELLED_BY_CUSTOMER | CANCELLED_BY_TECHNICIAN
ARRIVED            -> DIAGNOSED
DIAGNOSED          -> CUSTOMER_APPROVED | DECLINED_BY_CUSTOMER
CUSTOMER_APPROVED  -> PARTS_REQUESTED | REPAIR_IN_PROGRESS
PARTS_REQUESTED    -> PARTS_ACQUIRED
PARTS_ACQUIRED     -> REPAIR_IN_PROGRESS
REPAIR_IN_PROGRESS -> REPAIR_COMPLETE
REPAIR_COMPLETE    -> CUSTOMER_CONFIRMED
CUSTOMER_CONFIRMED -> PAYMENT_RECEIVED | DISPUTED
PAYMENT_RECEIVED   -> CLOSED | DISPUTED
DISPUTED           -> CLOSED
CLOSED             -> ∅
CANCELLED_BY_CUSTOMER   -> ∅
CANCELLED_BY_TECHNICIAN -> ∅
DECLINED_BY_CUSTOMER    -> PAYMENT_RECEIVED   (locked visit fee still owed)
```

**Customer-driven target states** (`ALLOWED_ACTORS`, actor kind `CUSTOMER`):
`ARRIVED`, `CANCELLED_BY_CUSTOMER`, `CUSTOMER_APPROVED`, `DECLINED_BY_CUSTOMER`,
`DISPUTED`. **Keystone asymmetry:** `CUSTOMER_CONFIRMED` is driven by the
**TECHNICIAN** entering the customer's completion code — the customer's screen
mints + displays the code, it never has a "verify" button.

### Customer endpoints (all `requireAuth` + `requireCustomerRole`; foreign id → 404)

| Method + Path | Body | Valid-from | Effect / failures |
|---|---|---|---|
| `GET /me/bookings/:id` | — | any | one own booking → `BookingDto` |
| `GET /me/bookings` | — | any | own bookings desc → `BookingDto[]` |
| `POST /me/bookings/:id/cancel` | — | CREATED/DISPATCHED/ACCEPTED/EN_ROUTE | → `CANCELLED_BY_CUSTOMER` |
| `POST /me/bookings/:id/confirm-arrival` | `{code: /^\d{6}$/}` | **EN_ROUTE** (else 409 `Booking is not awaiting arrival confirmation`) | verify tech's code → `ARRIVED`, lock visit fee. 401 `Invalid or expired arrival code`; 409 `The technician has not marked arrival yet`; 422 `Arrival GPS is outside the service address` |
| `POST /me/bookings/:id/approve` | — | **DIAGNOSED** (else 409 `Booking is not awaiting a decision`) | → `CUSTOMER_APPROVED`, freeze cart |
| `POST /me/bookings/:id/decline` | — | **DIAGNOSED** (same guard) | → `DECLINED_BY_CUSTOMER`, visit fee stays owed |
| `POST /me/bookings/:id/request-completion-otp` | — | **REPAIR_COMPLETE** (else 409 `Booking is not awaiting completion confirmation`) | mint 6-digit OTP, SMS to customer's phone. Throttle **3 / 900s** → 429 `Too many code requests. Try again later.` Response `{ok:true}` (+`devOtp` non-prod) |

`pay` / `pay-cash` exist but are **out of scope** for Slice 4.

### `BookingDto` (already fully modeled app-side — `booking_dtos.dart`)

`id, bookingNumber, state, scheduledSlot, visitFeePaise, laborPaise, laborTier,
service{id,name}, zone{id,name}, address{id}, technician?{name,maskedPhone},
diagnosis?{issueName}, parts[]{id,sku,name,ceilingPricePaise,qty},
estimate{laborPaise,partsPaise,visitFeeCreditPaise,totalPayablePaise},
photos[]{kind,capturedAt,url}, payment?{status,method,amountPaise},
dispute?{status,outcome?,refundPaise?}`.

- `address` = **only `{id}`** → app-side label join.
- `technician` present once **ACCEPTED** (real name, masked phone).
- `estimate` always present; pre-quote states have `visitFeeCreditPaise: 0`;
  DIAGNOSED onward the visit fee is credited + frozen; declined/cancelled →
  `totalPayablePaise: 0`.
- `photos[].url` = short-lived (15 min) signed R2 read URL (empty in practice
  until R2 billing is wired).

---

## Architecture & data flow

### Polling controller — `BookingTrackingController(bookingId)` (`@riverpod` family)

- Loads `GET /me/bookings/:id` immediately; exposes `AsyncValue<BookingDto>`.
- **Adaptive poll:** re-fetch every **5s** while non-terminal; **stop** the timer
  when terminal (`CLOSED`, `CANCELLED_BY_CUSTOMER`, `CANCELLED_BY_TECHNICIAN`, or
  `DECLINED_BY_CUSTOMER` once `payment != null`).
- **Lifecycle pause:** an `AppLifecycleListener` cancels the timer when the app is
  not `resumed`; on return it resumes + does an immediate refetch.
- **Keep-last-good:** a *poll* failure keeps the last good `BookingDto` on screen
  and retries next tick. Only the **first** load surfaces an error UI.
- `refetch()`: forced immediate reload — called right after a gate succeeds so the
  UI advances at once instead of waiting for the next tick.

### Gate calls — extend `BookingRepository`

`confirmArrival(id, code) -> Result<void>`, `approve(id) -> Result<void>`,
`decline(id) -> Result<void>`, `requestCompletionOtp(id) -> Result<CompletionOtpDto>`.
All bodyless except confirm-arrival (`{code}`). Each returns a typed `Result`;
on `Ok` the screen triggers `controller.refetch()`.

### App-side address label — `bookingAddressLabelProvider(addressId)`

Reads `addressRepositoryProvider.list()`, finds the matching `AddressDto`, returns
a formatted label (`label · line1, pincode`). Falls back to the raw id when not
found (e.g. a since-deleted address). No backend change.

---

## The 17-state → customer-phase mapping

One pure function `phaseFor(BookingDto) -> TrackingPhase` (an enum + active-gate
flag). Rendered as a **timeline stepper** (Booked → Assigned → Arrived → Diagnosis
→ Repair → Done → Paid) plus a phase-specific action card.

| Backend state(s) | Customer label | Active card |
|---|---|---|
| `CREATED`, `DISPATCHED` | Finding you a technician… | none (spinner pulse) |
| `ACCEPTED` | {Tech} is assigned | technician block |
| `EN_ROUTE` | {Tech} is on the way | **arrival card** (6-digit code entry) |
| `ARRIVED` | Technician has arrived | none |
| `DIAGNOSED` | Review the diagnosis | **approve/decline card** (issue + parts + estimate) |
| `CUSTOMER_APPROVED`, `PARTS_REQUESTED`, `PARTS_ACQUIRED`, `REPAIR_IN_PROGRESS` | Repair in progress | parts/photos as they arrive |
| `REPAIR_COMPLETE` | Confirm the work is done | **completion card** (mint OTP → "texted to your phone") |
| `CUSTOMER_CONFIRMED`, `PAYMENT_RECEIVED` | Payment | **pay placeholder** (amount owed) — Slice 5 |
| `DISPUTED` | Under review | dispute summary (read-only) |
| `CLOSED` | Completed | receipt summary (terminal) |
| `CANCELLED_BY_CUSTOMER`, `CANCELLED_BY_TECHNICIAN` | Cancelled | terminal |
| `DECLINED_BY_CUSTOMER` | Declined | "visit fee still owed" → pay placeholder |

**Cancel** is shown only while `isCancellable` (state in
`CREATED/DISPATCHED/ACCEPTED/EN_ROUTE`) — matches the graph, no 409 surprises.

`phaseFor` + `isCancellable` + `isTerminal` + `activeGate` live in one pure,
Flutter-free file, exhaustively unit-tested against all 17 states so no state
renders a blank screen.

---

## Gate interactions & error handling

Never swallow a `Failure` — map each to UX:

- **Confirm-arrival:** inline 6-digit validation before calling. On `Failure`,
  show the backend message inline under the field (`Invalid or expired arrival
  code` / `The technician has not marked arrival yet` / `Arrival GPS is outside
  the service address`); keep the field editable to retry. On `Ok` → refetch →
  card disappears as state flips to `ARRIVED`.
- **Approve:** one tap → spinner → refetch. `Failure` → SnackBar.
- **Decline:** **confirm dialog** ("You'll still owe the ₹X visit fee. Decline this
  repair?", ₹X from the estimate) → on confirm call `/decline` → refetch.
- **Completion OTP:** "Confirm work is done" → mint. On `Ok`, show the "code texted
  to your phone — read it to your technician" panel; **in dev**, also show the
  echoed `devOtp` in a monospace chip. Handle **429 throttle** (surface message,
  brief button disable). A "Resend code" affordance (3/900s).

**Stale-state races:** a tap on a stale card (poll advanced underneath) yields a
409, surfaced as a SnackBar; the refetch reconciles the screen. Cards are always
derived from the *current* `BookingDto`, so this self-heals.

**In-flight guard:** a gate call in flight disables that card's buttons
(per-card busy flag, not global) — no double-fire.

---

## Files

**Data:**
- `booking/data/booking_repository.dart` — **extend:** `confirmArrival`, `approve`,
  `decline`, `requestCompletionOtp`.
- `booking/data/booking_dtos.dart` — **add:** `CompletionOtpDto {bool ok, String? devOtp}`.

**Presentation:**
- `booking/presentation/tracking_phase.dart` — **new, pure:** `TrackingPhase` enum
  + `phaseFor` + `isCancellable`/`isTerminal`/`activeGate`.
- `booking/presentation/booking_tracking_controller.dart` — **new `@riverpod`:**
  adaptive polling family controller (timer, lifecycle pause, keep-last-good,
  `refetch()`).
- `booking/presentation/booking_tracking_screen.dart` — **rewrite:** timeline +
  phase cards, split into small private widgets (`_ArrivalCard`, `_DiagnosisCard`,
  `_CompletionCard`, `_PayPlaceholder`, `_TerminalSummary`).
- `booking/presentation/booking_address_label.dart` — **new:**
  `bookingAddressLabelProvider(addressId)`.

**Reuse:** `rupees()` (home), `FixCareColors/Radii` (theme), the `Result` switch
idiom, `formatScheduledSlot` (wizard).

---

## Testing strategy

Bar: `flutter analyze` 0 issues; all tests hermetic (mock transport); TDD.

1. **`phaseFor` — pure unit tests.** Parameterized table over all 17 states →
   expected phase + active-gate + `isCancellable`/`isTerminal`. Exhaustive.
2. **Repository — contract-guarded (`_CapturingAdapter`/`FullHttpRequestMatcher`).**
   `confirmArrival` sends `{code}` (body present); the bodyless POSTs carry no
   `application/json`; 401/409/422/429 → right `FailureKind` + message surfaced;
   `requestCompletionOtp` parses `devOtp`.
3. **Controller — fake repo + `fakeAsync`.** Poll advances after 5s; **stops at
   terminal**; **keep-last-good** on a mid-stream network `Failure`; gate success
   triggers an immediate refetch.
4. **Widget — `ProviderScope` overrides.** Per active-gate phase: right card + right
   control renders; `EN_ROUTE` inline error on `Failure`; `DIAGNOSED` decline opens
   the **confirm dialog** (text mentions the visit fee) and only confirm calls
   `/decline`; `REPAIR_COMPLETE` mint → code panel + `devOtp` chip; terminal → no
   cancel button; address label (not raw id) renders from the fake list.

**Deferred follow-up (noted, not built here):** add a real-backend proof of the new
endpoints to `test/contract/backend_contract_smoke_test.dart` once the harness can
drive a booking to `EN_ROUTE`/`DIAGNOSED`/`REPAIR_COMPLETE` (needs a technician
actor the smoke harness doesn't have yet).

---

## Carry-forwards honored

- App sends only what each endpoint's Zod body allows (confirm-arrival `{code}`;
  the rest bodyless). Never a customer id (JWT-derived), never a client-snapshotted
  price (estimate comes from the DTO).
- No address PII sent; label is joined app-side from the customer's own address list.
- Completion is the keystone: the customer's screen only **mints + displays**; the
  technician enters the code. No customer-side "verify".
