# Booking B5 — Repair Execution + Completion Handshake (Keystone #2) — Design

**Date:** 2026-07-12
**Branch:** `feature/booking-b5-completion`
**Status:** Approved (brainstorming) → ready for `writing-plans`
**Depends on:** shared OTP primitive (merged PR #15), B4b photo pipeline (merged PR #16)

---

## Problem

After B4a's customer approval, the booking graph declares a repair-execution path
(`CUSTOMER_APPROVED → [PARTS_REQUESTED → PARTS_ACQUIRED →] REPAIR_IN_PROGRESS → REPAIR_COMPLETE →
CUSTOMER_CONFIRMED`) but none of it is wired — no actor entries, no endpoints, no evidence. The
**completion handshake is keystone #2** (CLAUDE.md): customer confirms work done → OTP to customer
→ customer reads it to the technician → technician enters it → payment unlocks. Without it, B6
(payment) has nothing to gate on.

## Goal

Wire the full repair-execution path with technician-driven transitions, gate `REPAIR_COMPLETE` on
the **3 mandatory repair photos**, and implement the completion OTP handshake exactly per
`core-flow.md:164-174` / the keystone-handshake skill. Both keystones then exist end-to-end:
CREATED → … → CUSTOMER_CONFIRMED is fully drivable via the API.

Non-goals: payment/charge (B6 reads CUSTOMER_CONFIRMED), dispute filing (B7 — but the evidence it
needs is left ready), trust-score events, cash handling, any merchant API (parts procurement is
WhatsApp-manual in V1 — the parts states are tracked + audited only).

## Decisions (from brainstorming, 2026-07-12)

1. **Full path incl. parts states**, all technician-driven simple markers (no merchant API). Every
   declared transition becomes reachable; B4a's parts cart gets its follow-through.
2. **B4a approve/decline token: deferred to B6.** The completion OTP IS the customer's money-gating
   confirmation; a second OTP at approve doubles friction for a pre-payment action that already has
   actor separation + frozen-cart audit. `docs/decisions/2026-06-16-approve-decline-no-otp-b4a.md`
   gets updated with this resolution (B6 re-evaluates binding a token at the charge).
3. **6-digit OTP** (primitive unchanged); `core-flow.md` "4-digit" corrected to 6 in this slice.
4. **`sendLimit` on the completion mint** (3 per 900s per booking) — the mint sends a real SMS in
   prod; throttle prevents SMS-spend abuse. Zero new code (opt-in store feature).
5. **Lua atomicity fix rides along** — the backlog item ("fix once via Lua/MULTI when B5 next
   touches the store") comes due: `mintOtp`'s INCR→EXPIRE→limit-check→SET becomes one atomic Lua
   script. Existing otp-store/auth/arrival suites must stay green UNCHANGED.

## State transitions + endpoints

| Transition | Endpoint (technician-jobs unless noted) | Gate / evidence |
|---|---|---|
| CUSTOMER_APPROVED→PARTS_REQUESTED | `POST /technician/jobs/:id/parts-needed` | assigned tech; **cart non-empty → else 422** (a parts detour with an empty cart is dishonest state) |
| PARTS_REQUESTED→PARTS_ACQUIRED | `POST .../parts-acquired` | assigned tech |
| CUSTOMER_APPROVED \| PARTS_ACQUIRED → REPAIR_IN_PROGRESS | `POST .../start-repair` | assigned tech; sets `repairStartedAt` |
| REPAIR_IN_PROGRESS→REPAIR_COMPLETE | `POST .../complete-repair` | assigned tech; **3-photo gate** (all `REPAIR_*` slots active, read in-tx AFTER the booking row lock — B4b idiom; `photoIds` in transition evidence); sets `repairCompletedAt` |
| REPAIR_COMPLETE→CUSTOMER_CONFIRMED | `POST .../confirm-completion` `{code}` | **keystone**: verifies the customer's completion OTP; sets `confirmedAt`; evidence `{codeConfirmed: true}` |
| (mint) | `POST /me/bookings/:id/request-completion-otp` (bookings module, customer) | owner-scoped (foreign id → 404), REPAIR_COMPLETE only → else 409; mints + "sends" the OTP |

- `ALLOWED_ACTORS` += `PARTS_REQUESTED/PARTS_ACQUIRED/REPAIR_IN_PROGRESS/REPAIR_COMPLETE/
  CUSTOMER_CONFIRMED`, all `['TECHNICIAN']`. Golden Rule 2 holds because the technician cannot
  reach CUSTOMER_CONFIRMED without the code only the **customer's phone** received — the exact
  mirror of the arrival keystone (customer drives ARRIVED with the technician's code).
- Simple transitions use `ownAssignedBookingOrThrow` (union widened with the new states) +
  `transitionBooking` in a tx — the established trio.
- New Booking columns: `repairStartedAt`, `repairCompletedAt`, `confirmedAt` (all `DateTime?`).
  `confirmedAt` is dispute-critical: `dispute-resolution.md:89` keys Tier-1 auto-resolution off
  "customer OTP exists at completion". Parts states get NO columns — the audit log covers them.

## Completion OTP (mirrors arrival-code exactly, roles reversed)

`src/modules/bookings/completion-code.ts` — thin wrapper over `shared/auth/otp-store.js`:

- Key `completion:{bookingId}`; 6-digit; TTL 600s; 5 verify attempts;
  `sendLimit {max: 3, windowSeconds: 900}` → mint returns `'throttled'` → 429.
- **Mint** (customer taps "confirm work completed"): `request-completion-otp` mints, then delivers
  via `otpSender.send(customerPhone, code)` (Dev sender logs; MSG91 inert until DLT). Non-prod
  response carries `devOtp` (auth's posture). NOTE: `flushTestRedis` already covers nothing under
  `completion:*` — its scan list gains the prefix.
- **Verify** (technician enters the code): same tri-state mapping as arrival —
  `ok` → transition; `invalid` → 401; `exhausted`/`no-code` → if the flow provably started
  (`repairCompletedAt` set — mint is only reachable after REPAIR_COMPLETE) treat `no-code` as
  expired/exhausted → 401, else 409 "customer has not requested the confirmation code yet".
  Single-use: a correct code is consumed; re-verify → no-code.
- Re-mint replaces the prior code (store semantics, same as arrival).
- Audit: never the code, never the phone. `PHOTO_UPLOADED`-style dedicated action is NOT needed —
  the `BOOKING_STATE_CHANGED` evidence (`codeConfirmed: true`) is the record, as with arrival.

## Repair photos (B4b extension — the planned one-enum change)

- `PhotoKind` += `REPAIR_OLD_PART`, `REPAIR_NEW_PACKAGING`, `REPAIR_INSTALLED` (additive
  migration; both DBs).
- `REPAIR_KINDS` const beside `DIAGNOSIS_KINDS`; `photoKind` Zod = union of both lists.
- **`PHOTO_WINDOW: Record<PhotoKind, BookingState>`** (`DIAGNOSIS_* → ARRIVED`,
  `REPAIR_* → REPAIR_IN_PROGRESS`) drives sign/confirm: `ownAssignedBookingOrThrow(techId, id,
  PHOTO_WINDOW[kind])` and the in-tx freeze `assertStillInState(tx, id, PHOTO_WINDOW[kind], …)`
  (union widened). Sign, HEAD-verified confirm, `photoKeyPrefix`, replace-by-soft-delete: reused
  verbatim — zero new storage code.
- `complete-repair`'s gate = B4b's gate pattern with `REPAIR_KINDS` (booking row lock first, then
  the photo read — the audit `photoIds` always reference the final committed set).

## OTP-store Lua fix (`shared/auth/otp-store.ts`)

`mintOtp`'s throttle path (INCR → conditional EXPIRE → limit check) + the OTP SET collapse into
one `redis.eval` Lua script: atomically increment the counter, set its TTL on first increment,
reject if over limit, else write the OTP key with its TTL. Closes both crash shapes (burned send
slot; TTL-less counter = permanent throttle). `verifyOtp` unchanged (its GET→SET/DEL races are
benign). Contract proof: ALL existing otp-store/auth/arrival tests pass unchanged.

## Docs riding along

- `core-flow.md`: completion OTP "4-digit" → "6-digit".
- `docs/decisions/2026-06-16-approve-decline-no-otp-b4a.md`: resolution appended — token deferred
  to B6 charge; completion OTP is the customer's money-gating confirmation.

## Golden Rules check

- **Rule 1:** payment unlock (CUSTOMER_CONFIRMED) is gated on 3 HEAD-verified photos + the
  customer's single-use OTP — evidence, twice over.
- **Rule 2:** two-sided — technician drives the transition but only with the customer's code;
  customer mints but cannot transition. No single-party path to CUSTOMER_CONFIRMED.
- **Rule 5:** every transition through `transitionBooking` (audit in-tx); OTP evidence in the
  state-change audit.
- **Rule 7:** no code/phone/coords in audit or logs; devOtp only in non-prod responses.
- **Fraud defenses:** "no photos = no completion = no payment" enforced at REPAIR_COMPLETE;
  photos frozen once the booking leaves REPAIR_IN_PROGRESS (window map); OTP attempt-capped,
  single-use, throttled.

## Testing

- Per transition: happy path, wrong-state 409, foreign tech 403, customer-role 403,
  parts-needed-with-empty-cart 422.
- Photo gate: 422 at 0/1/2 repair photos, 200 at 3; soft-deleted slot doesn't count; diagnosis
  photos do NOT satisfy repair slots; repair photo sign/confirm rejected outside
  REPAIR_IN_PROGRESS (409) — and diagnosis kinds still rejected outside ARRIVED.
- OTP: mint before REPAIR_COMPLETE → 409; foreign customer → 404; wrong code → 401 (attempts);
  expired/exhausted → 401; single-use; re-mint replaces; sendLimit → 429; devOtp in test env.
- Full E2E: CREATED → … → CUSTOMER_CONFIRMED through both keystones in one test.
- Lua fix: existing store suites unchanged; throttle behavior re-proven.
- Fixtures: `repairCompleteBooking()` helper building on B4b's `arrivedBooking` +
  `seedDiagnosisPhotos` + new `seedRepairPhotos`.
