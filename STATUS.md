# FixCare — Status

> **Live source of truth** for where the project is. Claude Code reads this at
> session start and updates it at session end. Keep it short — this is a
> dashboard, not a journal. Detail goes in `CHANGELOG.md` and weekly notes.

_Last updated: 2026-07-25_

---

## Phase
**Month 3 — core business logic.** Auth + profile + catalog + addresses + **booking B1 + B2a + B3** merged
to `main`. **Booking module underway** — 7 sub-slices (B1 creation → B2 dispatch → B3 arrival handshake →
B4 diagnosis → B5 completion handshake → B6 payment → B7 disputes); B2 split into B2a (dispatch, merged) /
B2b (accept-timer+BullMQ, deferred) / B2c (weighted algo, deferred); B4a/B4b/OTP-primitive/B5 merged
(PRs #14–#17). B6 split into **B6a (UPI charge, DONE on branch)** / B6b (cash path) / B6c (settlement
ledger). **Money moves for the first time** — on Razorpay test keys until KYC.

## Active task
**Booking Slice B6c** complete on `feature/booking-b6c-settlement` — **settlement ledger + CLOSED**.
`LedgerEntry` (append-only, 6 action types: EARNING_CREDIT / COMMISSION / CASH_DEBT / SETTLEMENT_PAID /
REPAYMENT / PLATFORM_ADJUSTMENT); `Booking.paidAt` + `Booking.closedAt`; `SETTLEMENT_EVENT` audit action;
`CHECK (cashDebtPaise >= 0)` (B6b carry-forward); `@@index([method,status,capturedAt])` on Payment.
`ALLOWED_ACTORS.CLOSED = [SYSTEM]`. Config: `COMMISSION_RATE_BPS`=2000 / `DISPUTE_WINDOW_HOURS`=48 /
`SETTLEMENT_SWEEP_INTERVAL_MINUTES`=15. Settlement service: `splitPaise` (80/20), ledger-derived balances,
`recordCashCollected` wired into `confirmCashPayment` tx, `settleClosableBookings` idempotent 48h-close sweep
(FOR-UPDATE-locked cash-debt auto-offset + stale-CASH-CREATED cleanup + error-per-booking logging). Zero-payable
chain at `confirmCompletion` (CUSTOMER_CONFIRMED→PAYMENT_RECEIVED as SYSTEM when nothing owed). Debt-limit
accept-gate (422 before DISPATCHED→ACCEPTED when `cashDebtPaise` exceeds limit). **BullMQ settlement sweep
(the codebase's first background work):** `shared/queue/settlement-sweep.ts` schedules a repeating job every 15 min
via `queue.upsertJobScheduler`; worker calls `settleClosableBookings`; `startSettlementSweep()` wired into
`server.ts` with a graceful SIGTERM/SIGINT shutdown hook. Endpoints: `GET /technician/me/balance`;
`POST /admin/settlements/payouts` + `/repayments` (MANAGER+, CHECK→409); `GET /admin/settlements/technicians/:id`.
323/323 tests green, tsc clean, server boots clean. Awaiting PR → `main`.
Design: [`docs/designs/2026-07-19-booking-b6c-settlement-design.md`]; plan:
[`docs/plans/2026-07-19-booking-b6c-settlement.md`].

## Last shipped
- **Booking Slice B6c** (`apps/backend`, settlement ledger + CLOSED): append-only `LedgerEntry`;
  `paidAt`/`closedAt` on Booking; 48h dispute-window sweep closes PAYMENT_RECEIVED bookings to CLOSED;
  zero-payable short-circuit; debt-limit accept-gate; balance + payout + repayment + technician-settlement
  admin endpoints; BullMQ sweep scheduling (codebase's first background work). 323 tests. On branch —
  awaiting PR.
- **Booking Slice B6b** (`apps/backend`, cash path): CASH payment method; receipt OTP handshake
  (customer mints via shared primitive, technician enters); `Technician.cashDebtPaise` running
  balance; UX-level + post-lock enforcement debt + velocity gates; idempotent CASH attempt;
  PAYMENT_RECEIVED as TECHNICIAN with evidence; `cash_initiated`/`cash_received` audits. 304 tests.
  On branch — all gates passed, awaiting PR.
- **Booking Slice B6a** — **merged to `main`** (PR #18, squash `1123a6f`): Payment attempt model +
  PaymentGateway wrapper (lazy-cred Razorpay, timing-safe HMAC); chargeAmountFor (approved total /
  declined visit fee); idempotent pay endpoint; signature-authed amount-verified duplicate-safe
  webhook → PAYMENT_RECEIVED as SYSTEM; payment in customer DTO. Test keys until KYC.
- **Booking Slice B5** — **merged to `main`** (PR #17, squash `d2f54e5`): repair path
  (parts-needed/acquired + start-repair + complete-repair with the 3-repair-photo gate);
  PHOTO_WINDOW per-kind capture windows; completion OTP handshake (customer mint throttled 3/900s,
  technician entry, single-use 6-digit) → CUSTOMER_CONFIRMED + confirmedAt; atomic Lua OTP mint;
  milestone columns + REPAIR_* enum migration. Both keystones end-to-end. 262 tests.
- **Booking Slice B4b** — **merged to `main`** (PR #16, squash `d225f10`): PhotoStorage R2 wrapper
  (presigned direct PUT jpeg-only/1MB-signed/24h, HEAD verify, 15-min signed reads, Dev stub for
  tests, optional R2_* keys, lazy-cred boot safety); `PhotoEvidence` slot model + `PHOTO_UPLOADED`
  audit; sign/confirm endpoints (booking+slot-scoped keys, HEAD-verified, retake = soft-delete
  replace, in-tx freeze guard); 2-photo gate on ARRIVED→DIAGNOSED with photoIds in the audit
  evidence; photos in customer + technician DTOs. 246 tests.
- **Shared OTP primitive** — **merged to `main`** (PR #15, squash `d8bdce8`): `shared/auth/otp-store.ts`
  — single audited single-use OTP store (mint/verify, SHA-256 hash at rest, attempt cap, single-use
  delete, generic typed payload, 4-arm status union, opt-in send throttle); `arrival-code.ts` + auth
  `sendOtp`/`verifyOtp` refactored onto it with their original suites passing unchanged; final-review
  hardening + /code-review fixes (payload guard → 401 not crash; maxAttempts out of the mint config).
  230 tests.
- **Booking Slice B4a** — **merged to `main`** (PR #14, squash `8aedf89`): diagnosis + parts cart +
  approve/decline. `DiagnosedIssue` admin catalog
  (MANAGER+, category-scoped, `@@unique([categoryId,name])`, soft-delete, `CATALOG_UPDATED` audit) +
  `/catalog/issues` CRUD; `BookingPart` snapshot cart line (no soft-delete by design = pre-approval mutable
  cart) + `BookingPart.partsCatalogId` index; Booking diagnosis fields (`diagnosedIssueId/Name`,
  `diagnosedAt`, `declinedAt`); `DIAGNOSIS_UPDATED` audit action; `DIAGNOSED/CUSTOMER_APPROVED/
  DECLINED_BY_CUSTOMER` actor entries; tech `diagnose` (ARRIVED→DIAGNOSED, category-match 422, issue
  snapshot, audited) + `parts` add/remove (price snapshot from catalog not request — Golden Rule 4; part
  category-match; DIAGNOSED-only; audited in-tx); customer `approve`/`decline` (owner-scoped 404, role-gated
  403, terminal decline, cart frozen at approval, audit carries the frozen-cart evidence read in-tx);
  `computeEstimate` (visit-fee credit, floored at 0, integer paise); `BookingDto` += diagnosis/parts/
  estimate. 220 tests; all three agents + per-task spec/quality review — findings fixed, OTP deferred
  (decision doc).
- **Booking Slice B3** (`apps/backend`, arrival handshake — keystone #1): 4 nullable evidence columns
  on `Booking` (`arrivalLat/Lng`, `arrivedAt`, `visitFeeLockedAt`); `haversineMeters` geo helper;
  single-use hashed Redis arrival code (6-digit, 5-attempt cap, 10-min TTL); `EN_ROUTE→TECHNICIAN` +
  `ARRIVED→CUSTOMER` actor entries; `POST /technician/jobs/:id/en-route` + `/arrive` (GPS gate
  validate-if-present, record GPS always, mint code, **no state change**, assigned-tech identity) +
  `POST /me/bookings/:id/confirm-arrival` (verify code → ARRIVED + `visitFeeLockedAt`); `transitionBooking`
  gained an optional no-PII `evidence` param (audit records `gpsRecorded/withinGeofence/codeConfirmed`,
  never raw coords). Two-sided, evidence-gated, no single-party path to ARRIVED. 196 tests; all three
  agents — no blocking issues. On branch.
- **Booking Slice B2a** (`apps/backend`): broadcast dispatch — `Booking.technicianId` + `Service.requiredSkill`
  (backfilled) + `JobSkip`; auto-open `CREATED→DISPATCHED` (SYSTEM) at creation; `GET /technician/jobs/available`
  (VERIFIED + skill-matched, masked customer view), `/mine`, `POST /accept` (atomic first-to-accept via the
  optimistic lock + `technicianId:null` claim guard), `/skip` (per-tech, idempotent); the `ALLOWED_ACTORS`
  role gate added to `transitionBooking` (3rd gate after legality + lock); directional masking (tech sees
  masked customer phone/no name; customer sees tech name + masked phone). Dispatch model push→broadcast
  (decision doc + core-flow updated). 179 tests; all three agents — no blocking issues. On branch.
- **Booking Slice B1** (`apps/backend`, first slice of the booking module): `Booking` model + full
  `BookingState` enum + `BOOKING_STATE_CHANGED` audit; `POST /me/bookings` (CUSTOMER-only) captures a
  **price snapshot** (zone + visitFee + labor + tier, denormalized) — later catalog/coverage edits
  never change a created booking (proven by test, the core fraud defense); unserviceable/unpriced →
  422; central `ALLOWED_TRANSITIONS` + guarded `transitionBooking` (full graph declared; B1 wires
  create + customer-cancel, audit in-tx); `GET /me/bookings`, `GET :id`, `POST :id/cancel`,
  owner-scoped (others' ids → 404, no IDOR); human `bookingNumber` (FC-); `UnprocessableError`(422).
  164 tests; reviewed by all three agents — no blocking issues. On branch.
- **Addresses Slice B** (`apps/backend`, completes the addresses module): `Address` model + migration
  (PII fields + optional lat/lng + cached `zoneId` hint + `isDefault` + soft-delete); owner-scoped
  `GET/POST/GET:id/PATCH/DELETE /me/addresses` — CUSTOMER-only (others 403), another customer's id →
  404 (no IDOR), one-default-enforced transaction, resolve-at-save + **re-resolve-on-read**
  serviceability in every DTO, out-of-area saves 201, lat/lng both-or-neither, pincode editable
  (re-resolves zone). **No audit on address CRUD** (decision 8); **no address PII in logs**
  (Golden Rule 7, verified). 145 tests; reviewed by all three agents — no blocking issues. On branch.
- **Addresses Slice A** (`apps/backend`): `PincodeZone` model + migration (admin-managed
  pincode→zone map, reuses `CatalogStatus`); `resolvePincode` resolver (live map; INACTIVE/
  soft-deleted mapping *or* zone → unserviceable); `GET /serviceability?pincode=` (6-digit Zod,
  any authed user, explicit `{serviceable, zone, message}` for app UX); admin `GET/POST/PATCH/
  DELETE /catalog/pincodes` (MANAGER+, `CATALOG_UPDATED` audit in-tx, dup→409, unknown-zone→404,
  changed-only PATCH capturing from→to zone); seeded 3 Vadodara/Padra pincodes (idempotent).
  127 tests; reviewed by all three agents — no blocking issues. On branch.
- **Service catalog sub-slice B** (`apps/backend`, completes the catalog module): `PartsCatalog`
  (platform-set zone-agnostic `ceilingPricePaise` Int, optional category, unique `sku`,
  soft-delete) + migration; `GET /catalog/parts` (any authed user, ACTIVE-only, categoryId
  filter) + `POST`/`PATCH /catalog/parts` (MANAGER+; dup-sku 409, neg/float paise 400,
  PRICE_CHANGED on ceiling change / CATALOG_UPDATED otherwise — in-transaction; soft-delete
  hides from reads; 404 on missing/soft-deleted part or unknown category). Idempotent
  `seedCatalog` (Vadodara ₹149 / Padra ₹99 + 2 categories + 2 services + 4 geofenced prices
  + 2 parts; upsert-keyed; writes no audit; refuses to run in production). 101 tests green.
  Reviewed by prisma-migration-reviewer / golden-rules-auditor / fraud-vector-checker — no
  blocking issues; module-wide hardening items deferred (see below). On branch.
- **Service catalog sub-slice A** (`apps/backend`, first money module): `Zone` (geofenced
  visit fee) + `ServiceCategory` + `Service` (tier) + per-zone `ServicePrice`; new
  `shared/utils/currency.ts` (integer paise) + `requireAdminLevel(MANAGER)` RBAC (first
  piece of rbac.ts) + `ConflictError`(409). Reads = any authed user; writes = MANAGER+;
  price changes audited (PRICE_CHANGED from→to), catalog changes (CATALOG_UPDATED).
  84 tests; security-reviewed (fixed updateZone 409 + audit completeness + inactive-zone
  guard). On branch. Smoke equivalent covered by the integration suite.
- **Profile-update slice** — merged to `main` (GET/PATCH /me/profile, first protected feature).
- **Auth module COMPLETE** — merged to `main`: schema slice; bootstrap; OTP login +
  registration; JWT + refresh rotation + reuse-detection + requireAuth + logout/logout-all;
  admin email/password login + SUPER_ADMIN seed.
- **Auth + users schema slice** — merged to `main` (`User`, `RefreshToken`,
  Customer/Technician/Merchant/Admin, `AuditLog`; migration applied).
- Monorepo structure + git initialized (`apps/`, `packages/`, docs folders).
- Doc paths reconciled; Superpowers specs pinned to `docs/designs/`.
- "Worker" → "Technician" rename across all docs.
- Progress-tracking system (this file + weekly notes).
- ADRs 0001-0004.
- **11 project skills** (7 backend, 4 Flutter) + **4 custom review agents**
  in `.claude/`. Listed in CLAUDE.md → "Project Skills & Agents".
- Commit-authorship hooks (`.githooks/commit-msg` + Claude PreToolUse hook).

## Next 3 targets
1. **B7 — disputes** (DISPUTED state, customer-raise window, admin adjudication, partial refunds via
   B6a's `refund.*` webhook skeleton). The 48h dispute window is already enforced by the B6c sweep.
2. **B2b — accept-timer** (30-sec unclaimed-job re-broadcast; BullMQ infra NOW EXISTS — reuse the
   `shared/queue/` scaffolding from B6c). Apply for Razorpay KYC + Route NOW if not in flight.
3. **Flutter customer app** (Month 5 start): booking creation flow + live status polling + payment UI.
   Provision Cloudflare R2 account + creds (`R2_*` env) before launch.

## Deferred follow-ups (carry forward)
- **Auth rate-limiting hardening pass:** tighter per-IP/email limit + lockout on
  `/admin/auth/login`; rate-limit `/auth/refresh` (review notes from B + C — both
  need a valid token/account first, so low urgency).
- **Admin-login timing oracle** (review note from C): unknown-email skips argon2 →
  faster response can reveal whether an email is registered. Fix = dummy-hash verify
  on the unknown path. Minor / V1-acceptable at single-digit admin scale.
- **Catalog module-wide hardening** (still outstanding, applies to ALL catalog entities incl. the
  already-merged A — fix all-at-once or not at all for V1): (a) existence checks + `existing` reads
  run outside `$transaction` (TOCTOU; stale `fromPaise` under concurrency — V1-acceptable at
  single-admin scale); (b) money paise validated by a local Zod schema, not `shared/utils/currency.ts`
  — route through a shared `paiseSchema`. Plus **`ServicePrice` missing `deletedAt`** (financial
  record without soft-delete — add before financial mutations write against it). Plus **2-admin
  approval on category create** (fraud-defenses §15 — pre-existing, deferred).
  _(Fixed in the post-review pass on sub-slice B: phantom-CATALOG_UPDATED on no-op edits + DB-write-
  without-audit on unchanged price — now audit only real changes, applied to `updateZone` + `updatePart`;
  `GET /catalog/parts` query Zod-validated; seed env guard → whitelist; nullable `categoryId`;
  explicit `return asConflict(...)`.)_
- Add a `Merchant` smoke test (the one profile without a dedicated test).
- **Arrival GPS geofence is record-only when the address has no lat/lng** (B3 accepted V1 tradeoff):
  the >200m hard gate only fires when the address carries coordinates. Close this once addresses
  are backfilled with coordinates / PostGIS lands — make the arrival geofence a universal gate.
- **B4a deferred (carry to B5/B6):** (a) ~~2 mandatory diagnosis photos + R2 wrapper~~ — **DONE in
  B4b** (`PhotoEvidence`, sign/confirm, diagnosis gate; B5 reuses via REPAIR_* enum extension); (b)
  **customer-side OTP/confirmation token on approve/decline** — primitive now EXISTS
  (`shared/auth/otp-store.ts`); wire the token when B5 wires its completion OTP; decision:
  `docs/decisions/2026-06-16-approve-decline-no-otp-b4a.md`; (c) auto-suggested parts
  + diagnosis-vs-actual mismatch fraud rule = B6.
- **B4a `/code-review` altitude items (deferred, module-wide — fix all-at-once):** (a) the category-match
  rule + the `prisma.diagnosedIssue`/`prisma.partsCatalog` reads live in technician-jobs = **cross-module
  DB query** (CLAUDE.md says service-call/event only) — extract a catalog service fn when the cross-module
  RBAC/helper refactor happens; (b) `diagnoseJob` inlines the assigned-booking guard instead of calling
  `ownAssignedBookingOrThrow('ARRIVED')` — fold in with that refactor; (c) per-row ownership lives in each
  handler while `ALLOWED_ACTORS` gates only the kind — co-locate when the actor gate is generalised; (d)
  `diagnoseJob` writes both `BOOKING_STATE_CHANGED` and `DIAGNOSIS_UPDATED` (intentional: state event vs
  domain event — kept); (e) approve/decline mutation responses omit the technician block (client re-fetches
  via GET — minor).
- **OTP store throttle: INCR→EXPIRE→SET non-atomic** (`otp-store.ts` mint path; pre-existing behavior
  carried over from the old auth code). Two failure shapes: crash between INCR and SET burns a send
  slot (worst case one wasted slot per 900s window); crash between INCR and EXPIRE leaves a TTL-less
  counter = that phone throttled until a manual redis del. Fix once via Lua/MULTI when B5 next touches
  the store; all call sites benefit.
- Dynamic-introspection TRUNCATE in test helpers (vs the hand-maintained table list).
- Future env keys (R2_*, RAZORPAY_*, MSG91_* real values) added to `.env.example` when
  their features land.
- _(Done in B: composite RefreshToken index; reuse-detection behavioral test; dev/build/start
  scripts; JWT/Redis env keys.)_

## Blocked on
- Vendor approvals (parallel, applied for): Razorpay + **Razorpay Route** (2-4 wks),
  MSG91 DLT (1-2 wks), Setu + Karza KYC sandbox, WhatsApp/Gupshup (3-6 wks).
- Open decisions to settle (see `docs/07-reference/next-steps.md`): cash-model
  legal structure, customer-support channel, designer hire.

## Pointers
- **Build order:** Backend → Customer app → Technician app → Admin → Merchant
  (ADR-0004). Operate via direct API calls (Bruno/Postman) until admin is built.
- Branch model: trunk-based, `feature/*` → PR → `/code-review` → `main` (ADR-0002).
- Current week's retro: `docs/progress/weekly-notes/` (none yet — first on Saturday).
