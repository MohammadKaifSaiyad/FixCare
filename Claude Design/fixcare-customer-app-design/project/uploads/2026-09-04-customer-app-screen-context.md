# FixCare Customer App — Screen Context (for design)

**Date:** 2026-09-04 · **Purpose:** ground the customer-app screen designs in the ACTUAL backend
(endpoints, DTOs, the 17-state booking machine). Every data point below is what the API really
returns — design to these, not to assumptions. This is a design reference, not app code.

## What the app is (the one-paragraph anchor)

A homeowner in Vadodara/Padra books a verified technician to repair an appliance, at transparent
catalog prices, and pays through the platform. The app's spine is **one booking moving through a
state machine**, gated at two points by **two-sided handshakes** the customer participates in:
(1) arrival — the customer confirms the technician showed up; (2) completion — the customer's OTP
unlocks payment. The customer never sees a price a technician set (catalog only), never a raw
phone number (masked), and money never moves without the customer's action.

## Platform constraints that shape every screen

- **Android-first, low-end devices** — big tap targets, minimal animation, works on slow networks.
- **No realtime in V1** — booking status is by **polling `GET /me/bookings/:id`** (~every 10–20s on
  the tracking screen), NOT websockets. Design a "pull to refresh" + auto-poll, not a live socket feel.
- **Money is integer paise** — every amount below is paise; display as ₹ (divide by 100). Never a float.
- **Dev vs prod** — on dev/test builds, OTP endpoints return the code in the response (`devOtp`);
  in prod it arrives by SMS. The app shows an OTP-entry screen either way.
- **Two languages of trust** — masked technician phone, technician real name only after accept,
  photos via short-lived signed URLs.

## Auth & session (Slice 1 — being built now)

- **Phone entry** → `POST /auth/otp/send { phone }`. Indian 10-digit mobile. → success = "OTP sent".
- **OTP entry** → `POST /auth/otp/verify { phone, code }` → returns `{ accessToken, refreshToken, user }`
  (access 15m, refresh 30d). New number auto-registers as a CUSTOMER. Dev: the code is in the send
  response. Screen: 6-digit code, resend (throttled — expect a 429 "try later"), wrong code = 401.
- **Silent refresh** → `POST /auth/refresh { refreshToken }` on 401; reuse-detected refresh → forced
  re-login. **Logout** → `/auth/logout`. Tokens live in secure storage.
- Screens: Splash/gate (has token? → home : phone entry) · Phone entry · OTP entry.

## Onboarding / profile / addresses

- **Profile** — `GET/PATCH /me/profile` (name etc.). First-run: capture name.
- **Addresses** — `GET/POST/GET:id/PATCH/DELETE /me/addresses`. An address has line1/line2/landmark/
  pincode, optional lat/lng, one `isDefault`. Each address DTO reports **serviceability** (resolved
  on save AND re-checked on read) — the app shows "we serve this area" or "out of area" per address.
- **Serviceability check** — `GET /serviceability?pincode=` → `{ serviceable, zone, message }`.
  Use before/while adding an address; out-of-area still saves (201) but is flagged.
- Screens: Profile · Address list · Add/Edit address (with live pincode serviceability) .

## Discovery (what can I book?)

- `GET /catalog/categories` → categories · `GET /catalog/services` (filter by category) → a service
  has `{ id, name, tier, requiredSkill }`. Price is per-zone: the visit fee + labor come from the
  booking snapshot once created; the catalog read is for browsing. `GET /catalog/parts` exists but
  parts are technician-added post-diagnosis, not customer-picked.
- Screens: Category grid · Service list (per category) · Service detail (what it is, that a visit fee
  applies, "book" CTA).

## Create a booking

- `POST /me/bookings { addressId, serviceId, scheduledSlot(ISO) }` → returns the full **BookingDto**
  (see below), state `DISPATCHED` (auto-opened to the technician pool). Unserviceable/unpriced → 422.
- Screen: Booking wizard — pick service → pick address (default preselected) → pick slot → confirm
  (shows the visit fee that will apply). One creating action; on success → tracking screen.

## The booking (the heart) — `BookingDto`

Every booking-detail / tracking screen renders this exact object (`GET /me/bookings/:id`, list via
`GET /me/bookings`):

```
id, bookingNumber ("FC-…" — show this to the user)
state           // one of the 17 states below — THE driver of what the screen shows
scheduledSlot   // ISO
visitFeePaise, laborPaise, laborTier
service { id, name }, zone { id, name }, address { id }   // resolve address details from /me/addresses
technician?     { name, maskedPhone }   // PRESENT ONLY after ACCEPTED. name real, phone masked.
diagnosis       { issueName } | null    // set at DIAGNOSED
parts           [{ id, sku, name, ceilingPricePaise, qty }]   // technician's cart, post-diagnosis
estimate        { laborPaise, partsPaise, visitFeeCreditPaise, totalPayablePaise }  // computed, integer paise
photos          [{ kind, capturedAt, url }]   // signed URLs, ~15-min TTL — refetch if stale. kinds: DIAGNOSIS_*/REPAIR_*
payment         { status, method, amountPaise } | null   // status CREATED/CAPTURED/FAILED; method UPI/CASH
dispute         { status, outcome, refundPaise } | null   // status OPEN/RESOLVED; reason is NOT here (admin-only)
```

### The 17 states → what the customer screen shows and can DO

| State | Customer sees | Customer action available |
|---|---|---|
| `CREATED` / `DISPATCHED` | "Finding you a technician…" | Cancel |
| `ACCEPTED` | Technician name + masked phone, "on the way soon" | Cancel |
| `EN_ROUTE` | "Technician is on the way" | Cancel |
| `ARRIVED` | "Technician has arrived — confirm to start" | **Confirm arrival**: `POST /me/bookings/:id/confirm-arrival { code }` — the customer enters/scans the technician's arrival code (keystone #1). |
| `DIAGNOSED` | The diagnosis (`diagnosis.issueName`) + the quote (`estimate.totalPayablePaise`, parts list, visit-fee credit) | **Approve** `/approve` or **Decline** `/decline` |
| `CUSTOMER_APPROVED` → `PARTS_REQUESTED` → `PARTS_ACQUIRED` → `REPAIR_IN_PROGRESS` | "Repair in progress" + milestone; repair photos appear in `photos` as they're taken | (watch) |
| `REPAIR_COMPLETE` | "Work done — confirm to release payment" | **Request completion OTP**: `POST /me/bookings/:id/request-completion-otp` → OTP to the customer; the customer reads it to the technician (keystone #2). Dev: `devOtp` in response. |
| `CUSTOMER_CONFIRMED` | "Confirmed — pay now" + the amount (`estimate.totalPayablePaise`) | **Pay UPI**: `POST /pay` → `{ orderId, amountPaise, keyId }` (hand to Razorpay checkout; test keys). **Pay cash**: `POST /pay-cash` → mints a receipt OTP to the customer to read to the technician. |
| `DECLINED_BY_CUSTOMER` | "You declined the repair — visit fee due" | **Pay** the visit fee (same /pay or /pay-cash; amount = visit fee). |
| `PAYMENT_RECEIVED` | "Paid ✓ — 48-hour window to raise an issue" + `payment` summary | **Raise dispute** (within 48h): `POST /me/bookings/:id/raise-dispute { reason }` → booking → DISPUTED, payout held. |
| `DISPUTED` | "Dispute open — under review" + `dispute` summary | (wait for admin resolution) |
| `CLOSED` | "Completed" + final `payment`/`dispute` summary | (terminal — rate/rework is a later slice) |
| `CANCELLED_BY_CUSTOMER` / `CANCELLED_BY_TECHNICIAN` | "Cancelled" | (terminal) |

Screens implied: **Home / bookings list** (each row: bookingNumber, service name, state badge,
amount) · **Booking tracking/detail** (the state-driven hero above + the current action) · plus the
action sub-screens: **Confirm-arrival (code entry/scan)** · **Diagnosis review + approve/decline** ·
**Completion-OTP display** · **Payment method choice + UPI checkout + cash-receipt-OTP display** ·
**Raise-dispute (reason form)**.

## Money display rules

- Estimate breakdown: labor + parts − visit-fee credit = total payable (all from `estimate`, paise).
- Payment status badge: CREATED = "awaiting payment", CAPTURED = "paid", FAILED = "failed, retry".
- Dispute: OPEN = "under review"; RESOLVED = outcome (FAVOR_CUSTOMER/FAVOR_TECHNICIAN/PARTIAL) +
  `refundPaise` if any.

## Error/edge states every screen needs

- 401 → silent refresh, else re-login. · 404 on someone else's booking (never happens for own data). ·
  409 "not in the right state" (the customer acted on a stale screen → refetch). · 422 gate messages
  (out of area, cash limit → "pay by UPI", nothing payable). · 429 (OTP resend throttle). · offline /
  slow: the app has an in-app retry queue for writes; reads show a retry affordance.

## Explicitly NOT in the app yet (don't design screens for these)

Live map tracking (no realtime V1 — polling only) · rating/review (post-CLOSE, later slice) ·
in-app chat · wallet/referrals · the technician's own app · any admin surface · dispute reason
read-back (admin-only). Razorpay is on TEST keys; SMS is dev-stubbed until MSG91 DLT.

## Design system note

Android-first, Material 3 baseline, high-contrast, large touch targets, works one-handed. The state
badge + the single primary action per screen is the recurring pattern — the customer should always
know "what's happening" and "what, if anything, I do next."
