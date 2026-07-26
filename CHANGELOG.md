# Changelog

Significant changes, most recent first. Rolling ~30-day window — older entries
can be trimmed. The *live* project state lives in [`STATUS.md`](STATUS.md);
this is the history of how it got there.

Format: `## YYYY-MM-DD` headers, bullet entries. Update every session.

---

## 2026-07-26 — B6c final gates + `/code-review` pass (branch finalized, awaiting PR)

- **Final gates:** opus whole-branch "Ready to merge" — the ledger↔cache reconciliation invariant
  (`cashDebtPaise` == Σ CASH_COLLECTED − Σ CASH_DEBT_OFFSET − Σ DEBT_REPAYMENT) holds on all three
  debt paths (each mutates cache + ledger in ONE tx); money conserved (split sums exact, offset moves
  `min(earning,debt)` from both payable and debt); `paidAt` on all three PAYMENT_RECEIVED paths so no
  booking strands; DISPUTED excluded from the sweep. prisma/golden-rules/fraud-vector clean — folded
  in the prisma WARNs (`LedgerEntry.bookingId` FK → RESTRICT, `@@index([technicianId, type])`).
- **`/code-review` (8 finder angles → verified → fixed in `6915507`), 324/324 green:**
- **Gate boundary mismatch** — the accept-gate blocked at `>= limit` while the initiate/capture gates
  allow debt to land at *exactly* the limit (`> limit`); a technician who captured cash to exactly the
  limit was then locked out of the next job the platform just permitted. Accept-gate now uses `>`.
- **Zero-amount ledger rows** — a zero-priced service (catalog Zod allows `min(0)`) made `splitPaise`
  return `{0,0}`, writing zero-amount EARNING_CREDIT/COMMISSION rows that violate the always-positive
  invariant. The sweep now skips zero-amount entries (the booking still CLOSEs).
- **Balance snapshot + best-effort flag** — `technicianBalance` read the cache column and the ledger in
  two separate queries, firing FALSE reconciliation flags when a capture committed mid-read; now one
  snapshot transaction. The reconciliation audit write is best-effort so a transient DB error can't
  500 a balance that computed fine. Also: fail loud (not silent-skip) if a FOR-UPDATE'd technician row
  vanishes mid-settlement; `sumLedgerByType` helper (one groupBy, enum-typed key).
- Backlogged: `splitPaise` → `currency.ts` + `assertValidPaise`, `:id` UUID Zod (module-wide),
  reconciliation-spam cooldown, SETTLEMENT_EVENT shape union, a `shared/queue` factory for B2b's
  accept-timer.

## 2026-07-25 — Booking slice B6c (settlement ledger + CLOSED)

- **Schema (all additive):** `LedgerEntry` model — append-only financial record with 6 types
  (`EARNING_CREDIT`, `COMMISSION`, `CASH_COLLECTED`, `CASH_DEBT_OFFSET`, `PAYOUT`, `DEBT_REPAYMENT`);
  FK to Booking + Technician; `amountPaise Int`. `Booking.paidAt` + `Booking.closedAt` nullable timestamp
  columns. `SETTLEMENT_EVENT` audit action. `ALLOWED_ACTORS.CLOSED = [SYSTEM]` (the sweep is the sole
  closer — no human can race it). `CHECK (cashDebtPaise >= 0)` on Technician (B6b carry-forward — ships
  WITH the settlement decrement so the constraint is always satisfiable). `@@index([method,status,capturedAt])`
  on Payment (B6b carry-forward). Config: `COMMISSION_RATE_BPS` / `DISPUTE_WINDOW_HOURS` /
  `SETTLEMENT_SWEEP_INTERVAL_MINUTES` (all defaulted; `.env.example` updated).
- **Settlement service** (`settlements.service.ts`): `splitPaise(total, bps)` → `{technicianPaise, commissionPaise}`
  (integer-safe, BPS rounding); ledger-derived `getTechnicianBalance` (sum by action type, reconciliation flag
  for unexpected divergence); `recordCashCollected` (writes `CASH_DEBT` + `EARNING_CREDIT` ledger rows inside
  the existing `confirmCashPayment` tx — cash receipt immediately visible in the balance); `settleClosableBookings`
  — idempotent sweep: locks each closable booking row (`FOR UPDATE`), auto-offsets cash debt against the ledger
  credit before the payout, closes stale `CASH_CREATED` payment attempts, logs per-booking errors rather than
  aborting the batch. Merchant-payout and DISPUTED flows deferred to B7 + post-Route-approval.
- **Zero-payable short-circuit:** `confirmCompletion` now chains `CUSTOMER_CONFIRMED → PAYMENT_RECEIVED` as SYSTEM
  when `chargeAmountFor` is 0 (visit-fee credit covers the whole job); the booking closes on the next sweep cycle.
  This closes the B6a `/code-review` gap (a ₹0 gateway order could never be created anyway — the 422 guard
  remains, but now the zero-payable path resolves cleanly end-to-end).
- **Debt-limit accept-gate:** `acceptJob` 422s (before `DISPATCHED→ACCEPTED`) when the technician's
  `cashDebtPaise` already meets or exceeds `CASH_DEBT_LIMIT_PAISE`. Prevents a tech from accepting more
  work while carrying an unpaid balance beyond the flat tier limit.
- **Endpoints:** `GET /technician/me/balance` (own ledger balance + `cashDebtPaise`); MANAGER+-only
  `POST /admin/settlements/payouts` (record a manual bank transfer as `SETTLEMENT_PAID`; `CHECK→409` if
  the payment would over-pay the payable); `POST /admin/settlements/repayments` (record a technician cash
  repayment as `REPAYMENT`; same CHECK→409 guard — empirically `PrismaClientUnknownRequestError` in 6.19.3,
  narrowed in the catch so only the constraint violation → 409 while P2025/transient errors re-throw);
  `GET /admin/settlements/technicians/:id` (ledger history + balance for any technician).
- **BullMQ settlement sweep — the codebase's first background work:** `shared/queue/settlement-sweep.ts`
  creates a dedicated ioredis connection with `maxRetriesPerRequest: null` (BullMQ rejects the shared client's
  value of 3; connection options passed as a plain object to avoid the peer-ioredis-version type mismatch).
  `queue.upsertJobScheduler` fires every `SETTLEMENT_SWEEP_INTERVAL_MINUTES * 60_000 ms`. Worker calls
  `settleClosableBookings`; `failed` events log to stderr. `startSettlementSweep()` is wired into `server.ts`
  (NOT `app.ts` — tests import `app.ts` and must never boot BullMQ) with SIGTERM + SIGINT shutdown hooks.
  B2b's accept-timer reuses this scaffolding.
- **Deferred (recorded in SDD ledger):** merchant payouts (WhatsApp-manual until merchant module lands);
  DISPUTED flows (customer raise + admin adjudication, B7); automated Razorpay Route splits (post-approval);
  debt-aging >7d auto-restrict + cycling detection (fraud-defenses.md note); `cashDebtPaise` on the technician
  job DTO; `cash_otp_resent` audit event; SIM-swap OTP-interception fraud note.
- Per-task spec+quality reviews all Approved (T2 controller-inline revert of an unplanned enum-reorder
  migration — tail-wags-dog; T3 zero-payable Important addressed as comment-only, accept-gate TOCTOU
  is UX-not-financial; T4 session-limited implementer, controller recovered inline, re-review Approved
  after CHECK→409 narrowing empirically verified). 323/323 tests, tsc clean.

## 2026-07-19 — B6b final gates + `/code-review` pass (branch finalized, awaiting PR)

- **Final gates:** opus whole-branch "Ready to merge" — cross-method money interleavings verified
  both directions (UPI-wins → confirm-cash 409s with zero debt; cash-wins → late UPI webhook lands
  in B6a's `duplicate_capture` machinery unchanged); concurrency sound under READ COMMITTED via the
  increment-first row lock (assumption now documented in-code, `1a8a085`). prisma / golden-rules /
  fraud-vector all clean; B6c carry-forwards logged (add `CHECK (cashDebtPaise >= 0)` WITH the
  settlement decrement; `@@index([method,status,capturedAt])` on Payment pre-scale; debt-aging
  >7d auto-restrict rule once settlement exists).
- **`/code-review` (8 finder angles → verified → fixed in `a7e220e`), 304/304 green:**
- **DTO capture-masking (CONFIRMED)** — a stale CASH CREATED attempt created after a UPI order
  won the DTO's take-1-latest pick when the UPI webhook then captured: a PAID booking showed
  `payment {status: CREATED, method: CASH}`. The DTO now prefers the CAPTURED payment, else the
  latest attempt (+ regression tests in their own file).
- **Deleted-technician dead-end (CONFIRMED)** — cash initiation didn't mirror confirm-cash's
  `deletedAt`/VERIFIED filters, so a customer could mint a receipt OTP the capture endpoint would
  reject forever. Initiation now 422s with the UPI fallback before creating anything.
- **Payload positivity (hardened)** — `verifyCashReceiptCode` accepted zero/negative/float amounts
  (unconstructible via the API today, but the value drives the debt increment); now a positive
  integer or fail-closed invalid (+ unit tests).
- Refuted with evidence in the ledger: TECHNICIAN actor bypass (all transitionBooking call sites
  traced — only the OTP-gated path drives PAYMENT_RECEIVED), UPI-null-orderId second order
  (unconstructible), OTP burn in the pre-tx race window (documented fails-safe trade-off).
  Backlogged: orphaned CASH CREATED cleanup (B6c sweep), `cashDebtPaise` on the technician job
  DTO (design deviation, folds into B6c), cleanup/dedup items.

## 2026-07-19 — Booking slice B6b (cash payment path)

- **`PaymentMethod.CASH`** added; `Payment.razorpayOrderId` made nullable (cash has no gateway
  order); **`Technician.cashDebtPaise`** Int column tracks the running platform-debt balance.
  Migration `payment_cash` applied on both DBs. Config keys: `CASH_DEBT_LIMIT_PAISE` (flat
  ₹500 new-tech debt limit) + `CASH_VELOCITY_CAP_PAISE` (₹3000 24h trailing window).
- **`ALLOWED_ACTORS.PAYMENT_RECEIVED`** widened: SYSTEM (UPI webhook) + TECHNICIAN (cash confirm).
  Cash: the technician drives the PAYMENT_RECEIVED transition ONLY with a receipt OTP minted to
  the customer — the two-sided confirmation (Golden Rule 2 mirror of B5's completion handshake).
- **`POST /me/bookings/:id/pay-cash`** (customer): any-method already-CAPTURED → 409; `chargeAmountFor`
  for the amount (same as UPI — CUSTOMER_CONFIRMED → approved total; DECLINED → visit fee); zero-payable
  → 422; UX-level debt gate (running balance + new charge > debt limit → 422) + velocity gate (24h
  trailing cash total > cap → 422); idempotent CASH attempt row (re-initiation returns the existing
  CREATED row, skipping a second OTP send); receipt OTP minted via `shared/auth/otp-store` with
  3/900s send throttle → 429 (payload pins paymentId + amount at initiation); `cash_initiated` audit
  in-tx. `/pay` (UPI) also widened to 409 'already paid' on any-method CAPTURED row.
- **`POST /technician/jobs/:id/confirm-cash`** (technician): OTP verify against the pinned payload →
  confirmed paymentId + amount before the tx opens; one tx: debt increment FIRST (the `UPDATE
  Technician SET cashDebtPaise += amount WHERE id = ?` is the serializing row lock) → both gates
  re-checked post-lock (this is the enforcement read, not just UX) → Payment CAPTURED keyed on
  CREATED → `transitionBooking(PAYMENT_RECEIVED, TECHNICIAN)` with evidence → `cash_received` audit.
  Any failure rolls back the debt increment. Response carries the updated `cashDebtPaise` balance.
- READ COMMITTED isolation assumption behind the in-tx velocity re-read documented; **OTP consumed
  pre-tx** (verify consumes the code before the tx opens — fails-safe: a tx rollback cannot re-use
  the code, the technician requests a fresh initiation).
- Deferred by design: cash settlement / repayment + accept-gate + CLOSED (B6c), trust-ladder limits
  (trust module), ₹20 UPI discount (pricing slice), mismatch auto-dispute (B7).
- Per-task reviews all Approved (T3 re-review after concurrency model fix; guard-comment accuracy
  + distinct 422 messages + test hardcode fixed in `04c22ce`). 297/297 tests green, tsc clean.

## 2026-07-19 — B6a `/code-review` pass (branch finalized, awaiting PR)

- 6 finder angles → ~25 candidates → verified; 4 confirmed bugs fixed (`79ea502`), 284/284 green:
- **Declined-then-paid estimate hole** — the new `DECLINED_BY_CUSTOMER → PAYMENT_RECEIVED` edge
  meant a settled declined booking left the estimate's cancelled branch and showed the FULL quoted
  repair total again. Cancelled branch now also keys on `declinedAt` (+ regression test).
- **Zero-amount order guard** — when the visit-fee credit covers the whole job the payable is 0;
  `/pay` now 422s instead of creating a ₹0 gateway order (prod 500) or a 0-amount Payment row that a
  0-amount capture could "pay" (Golden Rule 1). Zero-payable auto-settlement lands with B6c.
- **Webhook body now Zod-validated** (envelope + payment entity, `amount` must be a nonneg int) —
  was a TS cast. This killed a latent MASS-FAIL: an entity missing `order_id` made
  `payment.failed`'s `updateMany` drop its `razorpayOrderId` filter (Prisma treats `undefined` as
  no-filter) → every open payment would have been marked FAILED.
- **Signature compare decodes hex** (was utf8 bytes of the hex string) — casing can never reject a
  legitimate capture; invalid hex fails closed.
- Hardening: `captured` PAYMENT_EVENT audit row in the capture tx (one queryable action now holds
  the full payment timeline); unit test pinning PAYMENT_RECEIVED as SYSTEM-only (ADMIN denied).
- Refuted (reasoning in the SDD ledger): webhook P2025 retry-loop (FK keeps the row), third-order
  leak on FAILED rows (409s correctly), TOCTOU dangling CREATED (duplicate_capture flag is the
  designed mitigation). Backlogged: `receivePayment()` cross-module seam (decide at B6b),
  anomaly-flag helper, keystone-fixture dedup.

## 2026-07-18 — Booking slice B6a (UPI charge — the first money movement)

- **B6 split** into B6a (UPI charge) / B6b (cash path) / B6c (settlement ledger) — smallest
  reviewable money surface first. B6a runs entirely on Razorpay TEST keys; live keys swap in
  post-KYC with zero code change.
- **`Payment` attempt model** — append-only evidence (no soft-delete; status = lifecycle);
  `razorpayOrderId`/`razorpayPaymentId` unique = the idempotency anchors. `PAYMENT_EVENT` audit
  action. Graph: `DECLINED_BY_CUSTOMER → PAYMENT_RECEIVED` opened (**declined visits now pay their
  locked visit fee** — revenue leak closed); `PAYMENT_RECEIVED` is SYSTEM-only.
- **PaymentGateway wrapper** (`shared/third-party/razorpay.ts`): Dev fake (deterministic orders +
  `signPayload` hook so tests sign valid webhooks) + real `razorpay` SDK with LAZY creds (production
  boots before KYC); timing-safe HMAC-SHA256 webhook verification; optional `RAZORPAY_*` config.
- **`chargeAmountFor`** — the ONE amount source (Golden Rule 4, snapshots only):
  CUSTOMER_CONFIRMED → the invariant-locked approved total; DECLINED_BY_CUSTOMER → `visitFeePaise`.
- **`POST /me/bookings/:id/pay`** — idempotent (open CREATED attempt returns the SAME order;
  CAPTURED → 409 'already paid', checked BEFORE the state gate so stale post-webhook retries hear
  the right story); gateway order created before the DB tx (orphaned orders expire gateway-side).
- **`POST /webhooks/razorpay`** — the HMAC signature over the RAW body IS the auth (scoped raw-body
  parser; 401 on bad/missing). `payment.captured`: amount-verified (mismatch → flagged audit, NO
  transition, 200-ack — a tampered/partial capture can never close a booking) → one tx
  {Payment→CAPTURED + `transitionBooking(PAYMENT_RECEIVED, SYSTEM)` with evidence}; duplicates
  no-op twice over (status guard + optimistic lock). `payment.failed` → FAILED + re-pay issues a
  NEW order. Malformed-JSON-with-valid-signature always-ACKs (audit flag — no gateway retry loop).
  `refund.*` = audited B7 skeleton. **Route exempt from the global rate limiter** (gateway
  deliveries must never 429 into retry storms; the signature is the gate, Caddy is the DoS
  backstop) — a plan deviation surfaced by the test run, adjudicated and approved in review.
- `BookingDto.payment` `{status, method, amountPaise}` — gateway ids never leak to the app.
- **B4a-token question CLOSED** (decision doc final entry): no charge-time OTP — the completion OTP
  + the customer's UPI-app authorization are the two confirmations.
- Subagent-driven with two controller-inline recoveries (session-limited implementers); per-task
  reviews Approved; 2 Importants fixed in-branch (pay guard ordering; webhook malformed-JSON ACK)
  + 1 Task-1 test escape (DECLINED no longer terminal in booking-state-unit).

## 2026-07-13 — Booking slice B5 (repair execution + completion handshake — keystone #2)

- **Both keystone interactions now exist end-to-end**: CREATED → … → CUSTOMER_CONFIRMED is fully
  drivable via the API. B6 (payment) gates on CUSTOMER_CONFIRMED.
- **Repair path (all technician-driven):** `POST /technician/jobs/:id/parts-needed`
  (CUSTOMER_APPROVED→PARTS_REQUESTED; **empty cart → 422** — a parts detour with no approved parts is
  dishonest state; merchant procurement stays WhatsApp-manual, tracked+audited only) →
  `/parts-acquired` → `/start-repair` (from CUSTOMER_APPROVED or PARTS_ACQUIRED; `repairStartedAt`)
  → `/complete-repair` (REPAIR_IN_PROGRESS→REPAIR_COMPLETE; **3-repair-photo gate** — all
  `REPAIR_OLD_PART`/`REPAIR_NEW_PACKAGING`/`REPAIR_INSTALLED` slots active, row-lock-first in-tx
  read, `photoIds` in the transition audit; `repairCompletedAt`).
- **PHOTO_WINDOW map** — per-kind capture windows (DIAGNOSIS_*→ARRIVED, REPAIR_*→REPAIR_IN_PROGRESS)
  drive B4b's sign/confirm state gate + in-tx freeze. One enum extension + one map; zero new storage
  code. Diagnosis kinds still ARRIVED-only (proven by B4b's untouched suite).
- **The completion handshake (core-flow.md:164-174 verbatim):** customer
  `POST /me/bookings/:id/request-completion-otp` (owner-scoped 404, REPAIR_COMPLETE-only 409,
  **throttled 3/900s → 429** — the mint sends a real SMS in prod; devOtp in dev) mints a 6-digit
  single-use code (`completion:{bookingId}`, 10-min TTL, 5 attempts) delivered to the CUSTOMER's
  phone; the customer reads it to the technician; technician
  `POST /technician/jobs/:id/confirm-completion {code}` verifies (4-arm mapping:
  invalid/exhausted→401, no-code→409 "ask the customer to request one"; single-use; re-mint
  replaces) → CUSTOMER_CONFIRMED + `confirmedAt` + `{codeConfirmed: true}` audit evidence.
  **Rule 2 airtight** — the technician drives the transition ONLY with the code minted to the
  customer's phone (exact mirror of the arrival keystone, roles reversed). No code/phone in audit.
- **OTP-store mint is now ONE atomic Lua script** (INCR + first-hit EXPIRE + limit check + SET) —
  the "fix via Lua/MULTI when B5 touches the store" backlog item retired; both crash shapes closed;
  existing otp-store/auth/arrival suites passed UNCHANGED as the behavior-preservation proof.
- **Schema:** `PhotoKind` += 3 REPAIR_* values; `Booking` += `repairStartedAt`/`repairCompletedAt`/
  `confirmedAt` (dispute Tier-1 keys off confirmedAt). Additive migration on both DBs.
- **Decisions:** B4a approve/decline token RESOLVED — not bound to approve; the completion OTP is
  the customer's money-gating confirmation; B6 re-evaluates a token at the charge
  (decision doc updated). core-flow.md OTP digit counts corrected 4→6 (one shared primitive).
- **Final gates + `/code-review`:** whole-branch review "With fixes" → both Importants fixed
  (partsNeeded in-tx cart count; confirm-completion customer-403 test) + keystone actor-unit
  assertions + direct-path timestamp assertion. prisma-migration-reviewer CLEAN; golden-rules CLEAN
  (DevOtpSender dev-log accepted by design); fraud-vector — all documented blocks intact.
  `/code-review` (8 angles) caught **one real money-display bug**: `computeEstimate`'s quoted set
  was never extended for the B5 states, so the visit-fee credit silently VANISHED from the
  customer's displayed total the moment the repair path started. Fixed with a `PRE_QUOTE_STATES`
  list (new states keep the credit by default) + an invariance regression test across all 7
  post-approval states. Also: `photoKeyPrefix` typed to `PhotoKindValue`; the deliberate
  exhausted-fold difference between arrival/completion wrappers documented in both.
- 262 tests (246 + 16 new), tsc clean. Subagent-driven; per-task spec+quality reviews all Approved
  (keystone review: 19/19 spec points, two-sided property verified airtight; two session-limit
  implementer stalls recovered by controller verification with zero rework).

## 2026-07-12 — Booking slice B4b (R2 photo evidence + 2 mandatory diagnosis photos)

- **The photo-evidence pipeline exists** — the missing half of B5's dependencies (OTP primitive was
  the other). Cloudflare R2 via the `PhotoStorage` third-party wrapper
  (`shared/third-party/r2-storage.ts`, otp-sender pattern): presigned direct PUT with `image/jpeg`
  AND the exact byte length **signed into the URL** (cryptographic 1MB cap; app compresses <500KB
  client-side — no server-side image processing), 24h upload expiry, HEAD `objectExists`, 15-min
  signed GETs, typed error boundary, Dev stub for tests, `R2_*` config keys optional until the
  account is provisioned. New deps: `@aws-sdk/client-s3` + `@aws-sdk/s3-request-presigner`.
- **`PhotoEvidence` slot model:** `PhotoKind` (`DIAGNOSIS_OVERVIEW`/`DIAGNOSIS_CLOSEUP`; B5 appends 3
  `REPAIR_*` values — that is the ENTIRE B5 storage change). One ACTIVE row per (booking, kind);
  retake = soft-delete + insert in one tx — **evidence is never destroyed**. `PHOTO_UPLOADED` audit
  in-tx with `{kind, hasGeotag, replaced}` — never coordinates (Golden Rule 7).
- **Endpoints:** `POST /technician/jobs/:id/photos/sign` + `POST .../photos` (confirm) — ARRIVED-only,
  assigned-tech, booking-scoped keys (cross-booking 422), **HEAD-verified** (evidence must EXIST in
  R2, not be claimed — Golden Rule 1), in-tx `assertStillInState('ARRIVED')` freeze guard (the cart's
  guard generalized).
- **The diagnosis gate:** ARRIVED→DIAGNOSED now requires BOTH photo slots active (422 `'2 diagnosis
  photos required (overview + close-up)'`), read inside the transaction; the passing `photoIds` ride
  the `BOOKING_STATE_CHANGED` audit evidence. Geotag optional (indoor GPS on budget Androids),
  `capturedAt` required. Camera-only capture re-confirmed (gallery stays blocked, app-side rule).
- **DTOs:** customer `GET /me/bookings(/:id)` + technician `/mine` carry
  `photos: [{kind, capturedAt, url}]` (15-min signed reads; raw `r2Key` structurally excluded).
- **Final-gate fixes (whole-branch + prisma + golden-rules + fraud-vector reviews):** production-boot
  crash fixed — `R2PhotoStorage` creds are checked LAZILY on first use, never in the constructor, so a
  deploy before the R2 account exists boots inert instead of dying at import (+ boot test);
  **slot-pinned keys** — confirm now requires `jobs/{bookingId}/{kind}-…`, so one uploaded object
  cannot be confirmed into both diagnosis slots (fraud-vector finding, + test); `PhotoEvidence.id`
  cuid→uuid (consistency; Prisma-level default, table shipped empty). Golden-rules audit CLEAN.
  Backlog: `capturedAt` is client-claimed/advisory (doc note for fraud-defenses before B5);
  presign fan-out batching when repair photos land.
- **`/code-review` pass (8 finder angles, verified):** fixed — `diagnoseJob` now takes the booking
  row lock BEFORE reading photos (a concurrent retake could previously slip between the gate read
  and the commit, leaving soft-deleted photoIds in the audit evidence); `DIAGNOSIS_KINDS` single
  source of truth for the slot list (Zod enum + gate filter — deliberately not nativeEnum so B5's
  REPAIR_* kinds stay invalid in the diagnosis window); `photoKeyPrefix()` owns the key shape for
  both sign (build) and confirm (verify). Refuted by tx reasoning: concurrent-confirm double-active-
  row (the freeze guard's booking-row write serializes confirm txs); unverified-key-suffix attack
  (a key cannot exist in R2 unless sign minted its presigned PUT). Backlog: cross-module
  photoEvidence access (fold into the existing module-wide refactor), test-helper dedup, dynamic SDK
  import, capturedAt-must-be-UTC app note.
- 246 tests (230 + 16 new), tsc clean. Subagent-driven: per-task spec+quality reviews all Approved;
  2 Important findings fixed in-branch during task gates (R2 SDK typed-boundary wrap + robust 404
  detection; confirmPhoto TOCTOU freeze guard).

## 2026-07-11 — Shared single-use OTP primitive (`shared/auth/otp-store.ts`)

- **The hashed-OTP-in-Redis idiom is now ONE audited implementation** instead of hand-rolled copies —
  `mintOtp<P>(key, {ttlSeconds, maxAttempts, sendLimit?}, payload?)` / `verifyOtp<P>(key, code, {maxAttempts})`.
  SHA-256 at rest, verify-attempt cap, single-use delete; generic typed payload; tagged status union
  `ok | invalid | exhausted | no-code`; **opt-in** send throttle (counter at `<key>:rl`).
- **Both existing sites refactored onto it, behavior-preserving** (their original test suites passed
  UNCHANGED as the proof): `arrival-code.ts` is now a thin wrapper (`exhausted` maps to its `'no-code'`
  → keeps the asserted exhausted→409 semantics); auth `sendOtp`/`verifyOtp` (the `{role}` payload
  round-trips through the store; every verify failure still folds into the one generic 401; devOtp
  unchanged; throttle key moved `otp-rl:<phone>` → `otp:<phone>:rl` — ephemeral counter, plan-documented).
- **Design refinement during planning:** the verify union gained a distinct `exhausted` arm (vs folding
  into `invalid`) because `arrival-code.test.ts` asserts exhausted→`'no-code'` — each caller now chooses
  its mapping, making the refactor exactly behavior-preserving.
- **Plan bug found by the full-suite run + fixed:** the new otp-store test used keys outside
  `flushTestRedis`'s prefixes, so the 900s-TTL throttle counter leaked across runs (first mint →
  `throttled` on any re-run inside the window). Test keys moved under `otp:`; proven by back-to-back runs.
- **Ready for B5** (completion OTP) and the deferred B4a approve/decline token — zero new crypto needed.
- **Final review pass:** whole-branch review Ready-to-merge YES; golden-rules-auditor CLEAN;
  fraud-vector-checker — all documented blocks (brute-force cap, single-use, TTL, actor separation,
  send-flood throttle) intact. Minors folded in: `verifyOtp` corrupt-value fail-safe (del + `no-code`
  instead of an unhandled throw, + test); arrival-code JSDoc restored + compile-time exhaustiveness
  `default`; dead `otp-rl:*` scan removed from the test flush helper. Throttle INCR→SET non-atomicity
  (pre-existing) → hardening backlog.
- **`/code-review` pass (8 finder angles, verified):** fixed — auth verify guards `!r.payload` (a
  payload-less key, e.g. a pre-refactor in-flight OTP during the deploy window, now yields the generic
  401 instead of a destructuring TypeError/500); `maxAttempts` removed from `OtpStoreConfig` (mint never
  read it — verify-side only, kills the two-place drift surface); boundary test added (correct code on
  the last allowed attempt succeeds). Refuted: folding `exhausted` into `invalid` (breaks arrival's
  asserted 409), throttled-user-can-verify-old-OTP (intended), RTT micro-opts (V1 noise). Backlog
  expanded: INCR→EXPIRE crash variant (TTL-less counter = manual-del throttle) noted alongside INCR→SET.
- 230 tests (220 + 10 new otp-store units). Executed subagent-driven: per-task spec+quality reviews all
  Approved.

## 2026-06-16 — Booking slice B4a (diagnosis + parts cart + approve/decline)

- **Structured diagnosis, snapshot-priced cart, two-sided diagnosis→approval handoff. No money moves**
  (the charge is the later B6 slice) — this slice gates *what* B6 will charge.
- **DiagnosedIssue admin catalog:** `/catalog/issues` CRUD (MANAGER+, category-scoped,
  `@@unique([categoryId,name])`, soft-delete, `CATALOG_UPDATED` audit) — diagnosis is a structured FK pick,
  **never free text** (fraud-defense: no fabricated diagnoses).
- **Technician flow:** `POST /technician/jobs/:id/diagnose {diagnosedIssueId}` (`ARRIVED→DIAGNOSED`; the
  issue's category must equal the booking's service category → 422 otherwise; snapshots `diagnosedIssueName`
  + `diagnosedAt`) → `POST /parts {partsCatalogId, qty}` / `DELETE /parts/:partId` (DIAGNOSED-only mutable
  cart). Each cart line **snapshots** sku/name/`ceilingPricePaise` from `PartsCatalog` at add-time, so a
  later catalog price edit can never change a quoted line (proven by test). The part's category must match
  the service category (no padding the cart with unrelated parts). `qty` is Zod int ≥ 1.
- **Catalog prices only (Golden Rule 4):** the technician supplies `{partsCatalogId, qty}` only — the price
  is read server-side from the catalog row; the request carries no price field. Zero pricing discretion.
- **Customer flow:** `POST /me/bookings/:id/approve` (`DIAGNOSED→CUSTOMER_APPROVED`, **cart frozen** — any
  further add/remove is rejected once the booking leaves DIAGNOSED) or `/decline`
  (`DIAGNOSED→DECLINED_BY_CUSTOMER`, terminal, sets `declinedAt`; the visit fee **stays locked** — declining
  does not refund the B3 visit-fee milestone). Owner-scoped (others → 404, no IDOR), role-gated (technician
  → 403). Both transitions write audit **evidence read inside the same transaction** (`source`, frozen-cart
  `partCount`/`partsTotalPaise`).
- **Estimate:** `computeEstimate` = `max(0, laborPaise + Σ(ceilingPricePaise × qty) − visitFeePaise credit)`
  — the visit fee is credited toward labor+parts, floored at 0; all integer paise. Surfaced on `BookingDto`
  (`diagnosis`, `parts`, `estimate`).
- **State machine:** `DIAGNOSED→TECHNICIAN`, `CUSTOMER_APPROVED→CUSTOMER`, `DECLINED_BY_CUSTOMER→CUSTOMER`
  added to `ALLOWED_ACTORS` (mandatory under default-deny). New `DIAGNOSIS_UPDATED` audit action
  (diagnose/add/remove); state changes still emit `BOOKING_STATE_CHANGED` via `transitionBooking`.
- **Schema:** `DiagnosedIssue` + `BookingPart` models + Booking diagnosis fields + 2 additive migrations
  (the models; then a `BookingPart.partsCatalogId` index). `BookingPart` intentionally has no soft-delete
  (pre-approval mutable cart; the financial record of truth is the post-charge ledger in B6).
- **Reviews:** all three agents (prisma-migration / golden-rules / fraud-vector) + per-task spec/quality.
  Fixed the real findings — part category-match guard, approve/decline audit-evidence + in-tx cart read,
  `BookingPart.partsCatalogId` index + intent comment. **Deferred (recorded):** B4b's 2 mandatory diagnosis
  photos (R2 wrapper); customer-side OTP on approve/decline → shared OTP primitive pre-B5
  (`docs/decisions/2026-06-16-approve-decline-no-otp-b4a.md`); auto-suggest + mismatch rule → B6.
- **`/code-review` pass** (high-recall, 7 finder angles) — fixed 6: **lifecycle-aware estimate** (no
  visit-fee pre-credit before DIAGNOSED — a fresh booking no longer shows a credited/zero payable;
  declined → 0 payable); **`listBookings` parts-inclusive** (list estimate now matches the detail view —
  was labor-only); **`qty` capped at 99** (the unit price is catalog-fixed, so an unbounded qty was the
  last estimate-inflation lever); **idempotent `removePart`** (`deleteMany` — a double-remove no longer
  500s on Prisma P2025); **in-tx DIAGNOSED freeze guard** on add/remove (closes the cart-freeze TOCTOU
  vs a concurrent approve); **`sumParts` + `ownDiagnosedBookingOrThrow` extracted** (one parts-total
  formula, one approve/decline guard prelude). Altitude items (cross-module catalog query, diagnose
  inline-guard dedup, actor-gate co-location) deferred to the module-wide refactor (STATUS).
- **220 backend tests** (was 196), all green; build clean. On branch `feature/booking-diagnosis`.

## 2026-06-13 — Booking slice B3 (arrival handshake — KEYSTONE #1)

- **The project's first keystone interaction + first money-gating evidence** (Golden Rules 1-2). A
  two-sided, evidence-gated handshake locks the visit-fee milestone; neither party alone can reach `ARRIVED`.
- **Flow:** tech `POST /technician/jobs/:id/en-route` (`ACCEPTED→EN_ROUTE`) → tech `POST /technician/jobs/:id/arrive`
  `{lat,lng}` (GPS-validated, mints a single-use code, **no state change**) → customer
  `POST /me/bookings/:id/confirm-arrival` `{code}` (`EN_ROUTE→ARRIVED`, sets `arrivedAt` + `visitFeeLockedAt`).
- **GPS gate (fraud-defense #11):** when the customer address has coordinates, haversine distance > 200m → 422;
  the technician's GPS is **always recorded** (`arrivalLat/Lng`) for review. Record-only when the address has no
  coordinates (accepted V1 tradeoff — universal geofence lands with PostGIS).
- **Arrival code:** server-minted 6-digit, **hashed in Redis**, single-use, 5-attempt-capped, 10-min TTL
  (reuses the auth OTP idiom). Only the GPS-stamped arrive-tap mints it; only the customer entering it
  transitions to ARRIVED → genuine two-sided proof. Brute-force-resistant (1M space + cap + TTL).
- **Lock = milestone, no money moves:** `visitFeeLockedAt` is set only at the code-verified ARRIVED transition;
  the payment slice (B6) will require it before any visit-fee claim.
- **State machine:** `EN_ROUTE→TECHNICIAN`, `ARRIVED→CUSTOMER` added to `ALLOWED_ACTORS` (mandatory under
  default-deny). `transitionBooking` gained an optional `evidence` param → the ARRIVED audit records
  `{gpsRecorded, withinGeofence, codeConfirmed}` with **no raw coordinates / no phone** (Golden Rule 7).
  Assigned-technician identity + customer owner-scope enforced (others → 403 / 404).
- New `haversineMeters` (`shared/utils/geo.ts`); arrival-code helper (`bookings/arrival-code.ts`); 4 nullable
  evidence columns + additive migration.
- 196 backend tests green (TDD, real Postgres + Redis). Reviewed by `prisma-migration-reviewer` (additive),
  `golden-rules-auditor` + spec (keystone integrity — no single-party ARRIVED — audit-in-tx, no PII verified),
  `fraud-vector-checker` (#11 GPS gate + #1 farming both blocked; code brute-force-resistant) — no blocking
  issues; fixed the one finding (missing `requireCustomerRole` on the confirm-arrival route). **Deferred:** B4
  diagnosis+parts, B5 completion handshake (keystone #2), B6 visit-fee charge, universal geofence (PostGIS).
  Built subagent-driven on `feature/booking-arrival` (pending PR/merge).

## 2026-06-13 — Booking slice B2a (broadcast dispatch + accept + actor-permissions)

- **B2 decomposed** → B2a (this) / B2b (accept-timer + BullMQ, deferred) / B2c (weighted matching algo,
  deferred — needs trust-score/location/cash models that don't exist). **Dispatch model changed from
  push → broadcast / first-to-accept** (the documented `rating×proximity×load×cash` algorithm can't be
  built yet); `core-flow.md` updated + `docs/decisions/2026-06-13-dispatch-broadcast-model.md` records it.
- **Schema:** `Booking.technicianId` (nullable FK, SET NULL, indexed) + `Service.requiredSkill` (NOT NULL,
  migrated add-nullable→backfill-by-category→set-not-null) + `JobSkip` (per-tech dismissal, composite-unique).
- **Auto-open:** `POST /me/bookings` now transitions `CREATED→DISPATCHED` (SYSTEM) in the create flow —
  the booking opens to the eligible pool immediately. Audit trail `null→CREATED→DISPATCHED`.
- **Actor-permission gate (completes the deferred B1 item):** `ALLOWED_ACTORS` map + a 3rd gate in
  `transitionBooking` (after legality, before the optimistic lock) — SYSTEM opens, TECHNICIAN accepts,
  CUSTOMER cancels; default-deny for mapped to-states. Role-gate in the state machine; identity/ownership
  in the service.
- **Technician dispatch — new `/technician/jobs/*` (TECHNICIAN-only):** `GET /available` (eligible =
  VERIFIED + booking's `requiredSkill` ∈ tech skills, open, not-skipped), `GET /mine`, `POST /:id/accept`
  (atomic first-to-accept via the optimistic lock + a `technicianId:null` claim guard — concurrent loser
  409, exactly one ACCEPTED audit), `POST /:id/skip` (idempotent per-tech hide).
- **Directional PII masking (Golden Rule 7):** the technician job view masks the customer phone + omits
  the customer name; the customer booking detail shows the technician's name + masked phone. `maskPhone` helper.
- **Deferred, documented (not dropped):** the weighted matching algorithm (B2c), the 30-sec accept timer +
  BullMQ infra (B2b), zone-coverage filtering, visit-fee UPI authorization (payment), and the Phase-A fraud
  locks (customer-unsettled-payment, technician-cash-debt-limit, self-dealing — need the cash/trust subsystems).
- 179 backend tests green (TDD, real Postgres + Redis). Reviewed by `prisma-migration-reviewer` (backfill
  safe; added the `technicianId` index it flagged), `golden-rules-auditor` (masking + atomic claim + audit-in-tx +
  no-money verified; hardened the claim guard), `fraud-vector-checker` (all 6 in-scope vectors implemented;
  Phase-A locks correctly deferred with a trail) — no blocking issues. Built subagent-driven on
  `feature/booking-dispatch` (pending PR/merge).

## 2026-06-08 — Booking slice B1 (creation + price snapshot + state skeleton)

- **Booking module decomposed** into 7 sub-slices (B1 creation+snapshot → B2 dispatch → B3 arrival
  handshake → B4 diagnosis → B5 completion handshake → B6 payment → B7 disputes). This is **B1**.
- **Booking model + migration** — full 18-value `BookingState` enum + `BOOKING_STATE_CHANGED` audit
  action; FKs to Customer/Address/Service (RESTRICT); human `bookingNumber` (FC- + Crockford base32);
  indexes on customerId + state.
- **Price snapshot (the core fraud defense).** `POST /me/bookings` resolves the address pincode→zone
  **live** at creation, looks up the catalog `ServicePrice`, and **denormalizes** zone+visitFee+labor+tier
  onto the booking row. A test mutates the catalog price + zone visit fee + soft-deletes the pincode
  mapping after creation and asserts the booking is **unchanged** — later catalog/coverage edits can
  never reprice a created booking (an admin can't retroactively change what a customer was quoted).
  Money is integer paise. Unserviceable address / service-unpriced-in-zone → **422** (every CREATED
  booking has a complete locked price). New `UnprocessableError`(422).
- **Guarded state machine.** A central `ALLOWED_TRANSITIONS` table (full graph declared; cancel edges
  only before ARRIVED; handshake states ARRIVED/CUSTOMER_CONFIRMED/PAYMENT_RECEIVED unreachable
  without their predecessors) + one `transitionBooking` that validates legality and writes
  `BOOKING_STATE_CHANGED` in the same transaction. B1 wires only create (→CREATED) + customer-cancel
  (CREATED→CANCELLED_BY_CUSTOMER). Actor-permission enforcement is deferred per-transition to the
  slices that expose each route.
- **`/me/bookings`** GET (list own) / GET :id / POST :id/cancel — CUSTOMER-only, owner-scoped
  (another customer's id → 404, no IDOR); illegal transition → 409. No money moves in B1 (snapshot
  recorded only). No booking/address PII in audit (metadata = bookingId/from/to only).
- 164 backend tests green (TDD, real Postgres + Redis). Reviewed by `prisma-migration-reviewer`
  (additive, Int paise, indexed), `golden-rules-auditor` (snapshot integrity + audit-in-tx + IDOR +
  no-money-in-B1 verified), `fraud-vector-checker` (all 6 in-scope vectors implemented; Phase-A
  payment/self-dealing locks correctly deferred to B2/B6) — no blocking issues. Built subagent-driven
  on `feature/booking-module` (B2 dispatch next; pending PR/merge).

## 2026-06-07 — Addresses slice B (customer address CRUD) — addresses module COMPLETE

- **Address model + migration.** Customer saved addresses: `label`/`line1`/`line2?`/`landmark?`/`pincode`
  (PII), optional `lat`/`lng` (for later arrival-GPS), a cached `zoneId` hint (FK ON DELETE SET NULL),
  `isDefault`, `AddressStatus`, soft-delete, `@@index([customerId])`.
- **`/me/addresses` CRUD** — `GET` (list own active, default-first) / `POST` / `GET :id` / `PATCH :id` /
  `DELETE :id`. **CUSTOMER-only** (technician/admin/merchant → 403, both route + service guard).
  **Owner-scoped:** every `:id` query bound to the caller's `customerId`; another customer's id is
  indistinguishable from missing → **404, no IDOR**. **One default enforced:** first address
  auto-defaults; `isDefault:true` clears the prior default in the same transaction (`isDefault:false`
  doesn't auto-promote). **Serviceability in every DTO:** resolved-at-save (stores the `zoneId` hint)
  but **re-resolved live on every read** via Slice A's `resolvePincode`, so coverage expansion instantly
  flips a saved address to serviceable. Out-of-area pincode still **saves (201)** with
  `serviceable:false` + message. `lat`/`lng` are both-or-neither (400 otherwise); `line2`/`landmark`/geo
  clearable to null on PATCH; `pincode` editable (re-resolves the zone). Soft-delete → 204.
- **No audit on address CRUD** (decision 8 — addresses aren't a money/trust event) and **no address PII
  in logs/audit** (Golden Rule 7 — Fastify `logger:false`, clean DTOs, generic errors; verified).
  Zone is resolved server-side from the pincode (no customer-controlled `zoneId`), so a customer can't
  self-assign a cheaper zone.
- **The addresses module is now COMPLETE** (Slice A pincode map/serviceability + Slice B address CRUD).
- 145 backend tests green (TDD, real Postgres + Redis). Reviewed by `prisma-migration-reviewer`
  (additive, indexed, soft-delete), `golden-rules-auditor` (Golden Rule 7 + IDOR + decision-8 audit-free
  verified), and `fraud-vector-checker` (zone self-assignment blocked; pincode-spoofing is an accepted
  V1 tradeoff — real defense is the later arrival-GPS handshake) — no blocking issues; one WARN fixed
  (blind body-spread → typed `AddressUpdateInput`). Booking-time zone+price snapshot tracked for the
  booking module. Built subagent-driven on `feature/addresses-crud` (pending PR/merge).

## 2026-06-06 — Addresses slice A (pincode→zone map + serviceability)

- **PincodeZone map.** New `PincodeZone` model + additive migration — an admin-managed map from a
  6-digit pincode to a `Zone` (coverage config; reuses `CatalogStatus`, soft-delete, FK ON DELETE
  RESTRICT). This is V1 zone resolution (no PostGIS): a customer's pincode → the zone whose visit
  fee + geofenced labor prices apply.
- **`resolvePincode` resolver** (`src/modules/addresses/serviceability.service.ts`) — reads the LIVE
  map; a pincode is unserviceable if there is no active mapping, or the mapping/zone is INACTIVE or
  soft-deleted. Returns `{ serviceable, zone:{id,name,visitFeePaise}|null, message? }`.
- **`GET /serviceability?pincode=`** (any authed user; 6-digit Zod → 400) — explicit serviceability
  verdict so the app can show "we don't serve this area yet" live during signup, before saving.
- **Admin `GET/POST/PATCH/DELETE /catalog/pincodes`** (MANAGER+, reads any authed user) — `CATALOG_UPDATED`
  audit in-transaction on every mutation; dup pincode → 409; unknown zoneId → 404; changed-only PATCH
  (no phantom audit), and a zone re-point captures `fromZoneId`/`toZoneId` in the audit (price-significant);
  soft-delete via DELETE → 204; `listPincodes` excludes INACTIVE/soft-deleted (consistent with the resolver).
- **Seed.** 3 Vadodara/Padra pincodes added to the idempotent `seedCatalog`.
- 127 backend tests green (TDD, real Postgres + Redis). Reviewed by `prisma-migration-reviewer`
  (additive, indexed, no PII), `golden-rules-auditor` (audit-in-tx + RBAC sound), and `fraud-vector-checker`
  (coverage writes gated + audited; visit-fee disclosure is public catalog data; zone resolved server-side,
  not customer-input) — no blocking issues; the two medium/low findings (from→to-zone audit, INACTIVE-in-list)
  fixed. Booking-time **zone+price snapshot** requirement recorded for the booking module. Built
  subagent-driven on `feature/addresses-module` (Slice B = customer address CRUD, pending). Also: reset the
  local `fixcare_test` migration ledger (had drifted out of sync with the schema; now clean, 6/6 applied).

## 2026-06-06 — Service catalog sub-slice B (parts master + seed) — catalog module COMPLETE

- **Parts master.** `PartsCatalog` model — platform-set, **zone-agnostic** ceiling price
  (`ceilingPricePaise` Int paise), optional `categoryId` FK (ON DELETE SET NULL), unique `sku`,
  `status` + soft-delete, `@@index([categoryId])`; additive migration. `GET /catalog/parts[?categoryId=]`
  (any authed user; ACTIVE + non-deleted only; DTO out, never raw Prisma) and `POST`/`PATCH
  /catalog/parts` (MANAGER+ via `requireAdminLevel`). Writes audit in the same transaction:
  `PRICE_CHANGED` (from→to paise) when the ceiling changes, `CATALOG_UPDATED` otherwise. Duplicate
  `sku` → 409; negative/float paise → 400; missing/soft-deleted part or unknown category → 404;
  `sku` immutable (absent from the update schema). Golden Rule 4 (catalog-prices-only) enforced
  structurally — technician/customer tokens categorically rejected at the RBAC gate.
- **Idempotent catalog seed.** `seedCatalog` (alongside the SUPER_ADMIN seed, wired into `db:seed`):
  Vadodara (₹149) / Padra (₹99) zones + AC/Fan categories + 2 services + 4 **geofenced** prices
  (same service, different price per zone) + 2 parts. Upsert-keyed on unique fields → running it
  N times never duplicates; writes **no** audit logs (system bootstrap). **Refuses to run when
  `NODE_ENV=production`** — closes the fraud vector of using the unaudited seed to apply prod price
  changes (those must go through the audited catalog service).
- **The service-catalog module is now COMPLETE** (sub-slice A zones/labor + sub-slice B parts/seed).
- **Post-review fix pass** (`/code-review` on the branch surfaced 6 findings; all fixed subagent-driven
  + re-audited by `golden-rules-auditor`): audit only fields/prices that **actually changed** — no more
  phantom `CATALOG_UPDATED` on no-op edits, and no DB-write-without-audit when an unchanged price is
  PATCHed (applied consistently to `updateZone` **and** `updatePart`); `GET /catalog/parts` `categoryId`
  now Zod-validated (empty string → 400 instead of silently returning all parts); seed env guard
  hardened from a `=== 'production'` blacklist to a `development|test` **whitelist** (blocks staging/unset);
  `updatePartBody.categoryId` nullable so a part can be detached from its category; `asConflict` catch
  paths made explicit (`return asConflict(...)`) to remove a `never`-typed fall-through risk.
- **108 backend tests green** (TDD, real Postgres + Redis; 101 for the feature + 7 for the fixes).
  Reviewed per-task by the `prisma-migration-reviewer`, `golden-rules-auditor`, and `fraud-vector-checker`
  agents — no blocking issues. Remaining module-wide hardening (TOCTOU pre-checks, shared paise validator,
  `ServicePrice.deletedAt`, 2-admin category approval) deferred to a future slice (see STATUS).
  Built subagent-driven on `feature/catalog-parts` (pending PR/merge).

## 2026-06-05 — Service catalog sub-slice A (first money module)

- **Service catalog sub-slice A.** Admin-managed `Zone` (geofenced visit fee) + `ServiceCategory`
  + `Service` (tier T1/T2/T3) + per-zone `ServicePrice` (geofenced labor). New
  `shared/utils/currency.ts` (integer-paise helpers — the first real money module) and
  `requireAdminLevel(MANAGER)` RBAC (the first piece of `rbac.ts`) + `ConflictError`(409).
  Reads = any authed user; writes = MANAGER+ (SUPPORT → 403). Price changes write
  `PRICE_CHANGED` (from→to paise) and catalog changes `CATALOG_UPDATED`, in the same
  transaction as the mutation; geofencing proven (same service, different price per zone +
  the zone's visit fee; unpriced-in-zone → laborPaise null). Duplicate name → 409;
  non-integer/negative paise → 400; soft-deleted/INACTIVE hidden from reads. 84 tests;
  security-reviewed (fixed a `updateZone` dup-rename 500→409, audit-completeness on combined
  edits, and an inactive-zone read guard). Parts master + catalog seed = sub-slice B.

## 2026-06-03 — Profile-update slice (first protected feature)

- **Profile-update slice.** `GET /me/profile` + `PATCH /me/profile`, both `requireAuth`-gated
  — the first protected resource (proves the auth backbone on a real feature). Role-routed
  from the JWT: customer edits `name`; technician edits `name` + `skills` (full-replace).
  **Implicit ownership** (own row by `userId`, no id in the URL → no IDOR). Empty body /
  unknown field → 400 (strict Zod, no mass-assignment); MERCHANT/ADMIN → 403; soft-deleted
  → 404. `PROFILE_UPDATED` audit records changed field **names only** (no values / no PII).
  New `profiles/` module; `PROFILE_UPDATED` added to the AuditAction enum (migration). 60
  tests; security-reviewed (no code defects; added MERCHANT/ADMIN + soft-delete-PATCH coverage).

## 2026-06-02 — Auth module complete (sub-slice C)

- **Auth sub-slice C (admin email/password login).** `POST /admin/auth/login`:
  argon2id verify; **identical generic 401** for unknown-email AND wrong-password
  (no account enumeration); suspended/soft-deleted (admin or parent user) → 403 only
  after a correct password; reuses the access JWT + hashed RefreshToken + `requireAuth`
  from earlier sub-slices (admin JWT carries `role: ADMIN`); `AuditLog USER_LOGGED_IN`
  (actorType ADMIN); admin DTO never exposes `passwordHash`. Idempotent `prisma/seed.ts`
  + `db:seed` create the first SUPER_ADMIN from env. 45 tests; security-reviewed
  (one minor V1-acceptable timing-oracle note deferred); seeded `fixcare_dev` and
  admin-login smoke verified (200 / 401 / 401).
- **The auth module is now COMPLETE**: phone-OTP login + registration for
  customer/technician, admin email/password login, and the full session lifecycle
  (access JWT + refresh rotation with reuse-detection + logout/logout-all + requireAuth).

## 2026-06-01 (sub-slice B)

- **Auth sub-slice B (JWT + refresh rotation + requireAuth).** `requireAuth` Fastify
  preHandler (verify HS256 access JWT → load user from DB per request → reject
  suspended (403) / deleted (401) → typed `request.user`) + `assertOwnership`.
  `POST /auth/refresh` rotates the refresh token (old `revokedAt` + `replacedById`
  linked to new; sliding 30d) with **reuse-detection** — a revoked token replayed
  revokes ALL the user's active tokens + writes `AuditLog REFRESH_TOKEN_REUSE_DETECTED`
  (SYSTEM) and returns 401 (the theft response commits before the 401). `/auth/logout`
  (revoke one) + `/auth/logout-all` (auth-gated, revoke all). Composite
  `RefreshToken(userId, expiresAt)` index. 37 tests; security-reviewed; register→refresh→reuse
  smoke passes. Known accepted edge: concurrent refresh double-fire (no grace window in V1).

## 2026-06-01 (later)

- **Auth sub-slice A (OTP + registration).** `POST /auth/otp/send` (per-phone
  rate-limit → 429; dev OTP returned in non-prod, prod-gated) and `POST /auth/otp/verify`
  (single-use OTP, 5-attempt cap, find-or-create via `createUserWithProfile` — the
  atomic role↔profile invariant guard; existing users log in as their stored role,
  not the request hint; writes AuditLog USER_REGISTERED/USER_LOGGED_IN; issues an
  HS256 access JWT + a hashed RefreshToken row). Added `OtpSender` interface (dev stub
  + inert MSG91 stub), OTP/token crypto helpers, jsonwebtoken. 25 tests green; reviewed,
  no blocking issues; real send→verify smoke returns tokens. Token rotation/reuse-detection
  + `requireAuth` are seamed to sub-slice B.

## 2026-06-01

- **Auth bootstrap (sub-slice 0).** Fastify app skeleton for `apps/backend`:
  `buildApp()`/`server.ts`, Zod-validated fail-fast `config.ts`, ioredis singleton,
  typed error classes + global error handler (unexpected errors → generic 500, no
  internal-detail/stack leak), helmet/cors/rate-limit plugins, and `GET /health`
  (DB + Redis readiness). Added zod/ioredis/@fastify plugins + dotenv devDep +
  dev/build/start scripts + bootstrap env keys. 17 tests green (TDD via `app.inject()`);
  server boots and `/health` returns ok/up/up. Built subagent-driven on
  `feature/auth-module`. Auth-users **schema slice merged to `main`**.

## 2026-05-31

- **Backend auth + users schema slice (first real code).** Scaffolded `apps/backend`
  (Fastify 5 + TypeScript strict + Prisma 6 + Vitest, Node 22 / pnpm 9.15.2) and
  implemented the auth+users Prisma schema test-first: `User` (one-role-per-phone),
  `RefreshToken` (hashed, rotation chain, sliding-expiry field), `Customer`/`Technician`/
  `Merchant`/`Admin` 1:1 profiles, append-only `AuditLog`. 11 TDD invariant tests green;
  first migration `20260531052019_auth_users_slice` applied to `fixcare_dev`. Built via
  subagent-driven development with per-task spec+quality review; migration passed the
  migration-safety review (no blocking issues). On `feature/auth-users-schema` — pending merge.
  Design: `docs/designs/2026-05-30-auth-users-schema-design.md`; plan:
  `docs/plans/2026-05-30-auth-users-schema.md`.

## 2026-05-30

- **Build order changed (ADR-0004).** New order: Backend → Customer app → Technician
  app → Admin → Merchant (admin moved from 2nd to 4th). Trade-off: operate the platform
  via direct API calls until admin is built. Updated `CLAUDE.md` Build Order,
  `build-sequence.md` (reality-check bullets + month-section banner), `STATUS.md`.
- **Enforced commit authorship via hooks.** `.githooks/commit-msg` (via `core.hooksPath`)
  + a Claude Code PreToolUse hook reject commits with a Claude co-author trailer or a
  non-`saiyedkgn6@gmail.com` author. Rewrote the prior 11 commits to the correct author.

- **Added project skills + custom agents.** Expanded `.claude/` with FixCare-specific
  automation (generic workflow stays with Superpowers):
  - 4 new backend skills: `prisma-schema-model`, `keystone-handshake`,
    `bullmq-worker` (backend-only — apps use in-app retry, not BullMQ),
    `third-party-wrapper`. (Now 7 backend skills total.)
  - 4 new Flutter/apps skills (first app-side skills): `flutter-feature`,
    `api-repository`, `camera-evidence-capture`, `riverpod-provider`.
  - 4 read-only review agents in `.claude/agents/`: `golden-rules-auditor`,
    `prisma-migration-reviewer`, `flutter-widget-reviewer`, `fraud-vector-checker`.
  - Listed them in `CLAUDE.md` → "Project Skills & Agents". Each cites its source doc.

- **Project setup (pre-development).** Established the working structure so the
  documented Claude-Code + Superpowers workflow can actually run:
  - Initialized git (single **monorepo**, trunk = `main`) and committed the
    existing planning docs.
  - Scaffolded `apps/{backend,admin,customer,technician}` + `packages/shared-types`
    with purpose READMEs; stub `pnpm-workspace.yaml` + `docker-compose.yml`.
  - Created the missing docs folders (`06-operations`, `adrs`, `designs`,
    `plans`, `decisions`, `progress/weekly-notes`) with index READMEs.
  - Reconciled conflicting artifact paths → `docs/designs` + `docs/plans`;
    pinned Superpowers brainstorming output to `docs/designs`.
  - Renamed the technician actor **"Worker" → "Technician"** across all docs
    (preserving BullMQ/background-job "worker" terminology).
  - Added the progress-tracking system: `STATUS.md` + weekly-notes template,
    wired into the session ritual in `CLAUDE.md`.
  - Added 3 project-level skills: `scaffold-module`, `zod-validated-route`,
    `audit-logged-mutation`.
  - Wrote ADR-0001 (monorepo), ADR-0002 (trunk-based branching),
    ADR-0003 (worker→technician).
