# ADR-0006 — razorpay_flutter for in-app UPI checkout

**Status:** Accepted
**Date:** 2026-09-12
**Context:** Customer app Slice 5 (payment)

## Context

Slice 5 wires the customer-facing pay flow. The UPI path needs to present a
Razorpay checkout to the customer inside the Flutter app. `CLAUDE.md` requires an
ADR before introducing new tech; `razorpay_flutter` is a new native dependency
(Android + iOS), so it gets one.

The backend already owns payment integrity: `POST /me/bookings/:id/pay` creates a
Razorpay order and returns `{orderId, amountPaise, keyId}`; the actual state change
to `PAYMENT_RECEIVED` happens **server-side, driven by the Razorpay webhook**
(`POST /webhooks/razorpay`, HMAC-verified, amount-checked, idempotent). The app's
only job is to present the checkout and then let the existing booking poll observe
the confirmed result.

## Decision

Adopt **`razorpay_flutter`** (Razorpay's official Flutter plugin) for the in-app UPI
checkout sheet.

- The app calls `/pay`, receives `{orderId, amountPaise, keyId}`, and opens the
  native checkout with those values.
- **Payment success from the checkout callback is NOT trusted as "paid."** The app
  treats a successful callback only as a cue to show "confirming…" and refetch; the
  booking flips to `PAYMENT_RECEIVED` only when the polled DTO shows
  `payment.status == CAPTURED` (set by the webhook). This keeps Golden Rule 1 (money
  never moves without evidence) — the evidence is the gateway webhook, not the client.

## Alternatives considered

1. **Hosted Razorpay web checkout in a WebView / external browser.** No native dep,
   works everywhere, but a worse UPI UX (app-switch friction, fragile return
   handling) and still needs the plugin's equivalent callbacks. Rejected for UX.
2. **Build a bespoke UPI intent flow.** Far more work, must handle every PSP app,
   reinvents what the plugin does. Rejected (YAGNI, risk).

## Consequences

- **New native dependency** with per-platform setup: Android needs a ProGuard rule
  (kept in `android/app/proguard-rules.pro`); iOS pods are installed via
  `flutter build`/`flutter run` (never Xcode ▶ — the project's standing rule).
- **`keyId` is null without configured Razorpay keys.** `/pay` returns
  `keyId: RAZORPAY_KEY_ID ?? null`, and the backend gateway is a no-network dev stub
  unless `NODE_ENV=production`. So in dev/CI (and until Razorpay TEST keys are added
  to the backend `.env`), the app **cannot** open real checkout. The app handles this
  as a first-class branch: `keyId == null` → "UPI unavailable, pay by cash" — cash is
  fully functional without any Razorpay config. UPI lights up automatically once keys
  are set. No code change needed to switch test→live keys (it's a backend env swap).
- **The plugin is callback-based and leaks native listeners if not cleared.** It is
  wrapped in a `RazorpayCheckout` service that always `clear()`s in a `finally` and
  exposes a `Future`-returning `open(...)`, injected via a provider so it's fakeable
  in hermetic tests (the real plugin runs on-device only).
- Confirmation stays webhook-driven; the app adds no client-trusted payment state.
