# FixCare — Status

> **Live source of truth** for where the project is. Claude Code reads this at
> session start and updates it at session end. Keep it short — this is a
> dashboard, not a journal. Detail goes in `CHANGELOG.md` and weekly notes.

_Last updated: 2026-09-05_

---

## Phase
**Month 5 — customer app (Flutter).** Backend booking module COMPLETE (B1→B7 merged, PR #21). Build order
(ADR-0004) advanced to the **customer app** (`apps/customer`, Android + iOS per ADR-0005; Riverpod codegen +
go_router + dio + secure-storage). **Merged:** Slice 1 auth (#22), iOS-target/web-drop (#23), design-fidelity
(#24). **Slice 2 (boot hydration + profile + addresses + maps) complete on branch, in final review.** Money
still on Razorpay test keys until KYC.

## Active task
**Customer app Slice 2** complete on `feature/customer-app-slice2-profile-addresses` — **boot hydration +
profile + addresses (with live serviceability + a Google Maps pin-picker)**. Replaces the Slice-1 placeholder
user: `AuthController.build()` now fetches `GET /me/profile` on boot (`SessionAuthenticated(CustomerProfileDto,
hydrated)`; 401→clear→login; network-blip→stay logged in, no name-gate). First-run **name capture** gated after
login when name empty. **Account** screen (name edit, phone read-only from secure storage, sign out). Full
**address CRUD** (list/add/edit/delete/set-default) with debounced live pincode **serviceability** (warn but
allow out-of-area, per backend 201), and a **Google Maps** pin-drop for lat/lng that **degrades gracefully
without a key** (`MAPS_ENABLED`-gated placeholder — the app builds/tests/runs keyless; only the live map needs
one). Built via SDD (11 tasks, each spec+quality reviewed — 5 fix-loops caught real defects: 2 weak contract
tests, 2 silent error-swallows, 1 blank-edit-form). 64 tests; `flutter analyze` clean; build_runner idempotent
(generated files committed). Design: `docs/designs/2026-09-05-customer-app-slice2-profile-addresses-design.md`.
**Next: final whole-branch review + golden-rules/flutter-widget reviewers + `/code-review`, then PR → `main`.**
**Founder action for full testing: provision a Google Maps API key (runbook in apps/customer/README.md) — the
map picker shows a placeholder until then; everything else works.**

## Last shipped
- **Customer app Slice 2** (`apps/customer`, on branch, final review) — profile + addresses + boot hydration +
  maps. Profile module (`CustomerProfileDto` + repo); session carries the profile; boot hydration + name-gate;
  Account screen; address module (`AddressDto`/`ZoneDto`/`ServiceabilityDto` + repo, contract-guarded tests);
  address list + `@riverpod` controller + serviceability chip; add/edit form (debounced serviceability + edit
  pre-fill + save-failure surfaced); `google_maps_flutter` pin-picker (graceful without a key). 64 tests,
  analyze clean.
- **Customer app — design-faithful auth screens** (`feature/customer-app-auth-design-fidelity`, on branch):
  ported the full design system into `theme.dart` (FixCareColors/FixCareRadii tokens, exact palette, Outfit
  typography), **bundled the Outfit font** (offline, OFL), drew the wrench+check logo via CustomPainter (no
  svg dep), and rebuilt splash/phone/OTP/home to the design mockup. Closes the fidelity gap from Slice 1
  (which used only 2 colors + system font). Spec at `docs/designs/2026-09-05-auth-screens-visual-spec.md`.
  Phone screen + logo verified on iOS simulator; founder approved. 16 tests, analyze clean. On branch,
  review pending.
- **Customer app — iOS target + web dropped** (`feature/customer-app-ios-drop-web`, **merged PR #23**): scope
  reversal recorded in **ADR-0005** — V1 is now **Android + iOS** (both apps, first-priority); **web dropped**.
  Scaffolded `apps/customer/ios/` (bundle `in.fixcare.fixcareCustomer`, iOS 15+); `localhost`-only ATS
  cleartext exception in `Info.plist` (release HTTPS-only); removed `web/` + Chrome commands. Docs updated
  (CLAUDE.md, mobile-stack.md, slice-1 design/plan notes, README with per-platform base URLs + iOS Xcode/
  CocoaPods setup). The shared Dart is unchanged (platform-neutral): `flutter analyze` clean, 16/16 tests.
  **iOS build/simulator smoke-test pending on the founder's Mac (needs Xcode — cannot build in this env).**
- **Customer app Slice 1** (`apps/customer`, Flutter — first app slice) — **merged (PR #22, `1003e9d`)**: project scaffold (Flutter 3.47,
  Riverpod 3.x `@riverpod` codegen, go_router 18, dio 5, flutter_secure_storage 11, freezed 4) + phone-OTP
  auth. `Env` (`--dart-define=BASE_URL`, default `10.0.2.2:3000`), Material3 theme (primary `#C2521B`,
  success `#1D6B4F`); sealed `Result<T>` + `FailureKind`; `TokenStore` (secure-storage); freezed auth DTOs +
  `AuthRepository`→Result; **single-flight auth interceptor** (401→one refresh→retry via bare dio;
  fail→clear+onAuthLost); `AuthController` (@riverpod) + sealed `Session`; go_router token-gate
  (`refreshListenable` on the controller); splash/phone/OTP/home screens. 15 tests, analyze clean. On branch,
  final gates pending.
- **Booking Slice B7** (`apps/backend`, disputes) — **merged to `main`** (PR #21): `Dispute` model + migration; raise-dispute endpoint
  (PAYMENT_RECEIVED→DISPUTED as CUSTOMER, payout held, DISPUTED excluded from the settlement sweep);
  gateway `refund` method + real `refund.*` webhook (idempotent reversal recording); admin resolve-dispute
  (atomic OPEN→RESOLVED claim gates the refund call — no double-refund on a double-submit; earning = labor
  prorated by the retained charge fraction, parts never credited to the tech; refund on FAVOR_CUSTOMER/PARTIAL;
  booking→CLOSED as ADMIN) + admin list/detail queries; `BookingDto.dispute` summary (status/outcome/refundPaise
  only — reason stays internal). 361 tests. On branch, all gates + /code-review passed, ready for PR.
- **Booking Slice B6c** — **merged to `main`** (PR #20, `dca81e1`): settlement ledger + CLOSED. Append-only
  `LedgerEntry`; `paidAt`/`closedAt` on Booking; 48h dispute-window sweep closes PAYMENT_RECEIVED bookings to
  CLOSED with the 80/20 split + cash-debt auto-offset; zero-payable short-circuit; debt-limit accept-gate;
  balance + payout + repayment + technician-settlement admin endpoints; BullMQ sweep scheduling (codebase's
  first background work). 324 tests.
- **Booking Slice B6b** — **merged to `main`** (PR #19, squash `9fa2088`): cash path — CASH payment
  method; receipt OTP handshake; `Technician.cashDebtPaise` running balance; debt + velocity gates;
  idempotent CASH attempt; PAYMENT_RECEIVED as TECHNICIAN with evidence. 304 tests.
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
1. **Customer app Slice 2** — home + profile + addresses: home/bookings list (`GET /me/bookings`),
   profile capture (`GET/PATCH /me/profile`), address CRUD (`/me/addresses`) with live pincode
   serviceability (`GET /serviceability`). Replace the Slice-1 placeholder user (fetch `/me/profile`
   on boot). Reuse the Slice-1 `Result`/repository/interceptor backbone.
2. **Customer app Slice 3** — discovery + booking creation: catalog browse
   (`/catalog/categories`,`/catalog/services`) → booking wizard (`POST /me/bookings`) → tracking screen
   (polling `GET /me/bookings/:id`, the 17-state hero). Provision Cloudflare R2 (`R2_*`) before the
   photo-evidence slice.
3. **Backend B2b — accept-timer** (deferred; 30-sec unclaimed-job re-broadcast; reuse `shared/queue/`
   from B6c) — pick up when the app work needs it, else after the core customer flow. Apply for
   Razorpay KYC + Route NOW if not already in flight.

## Deferred follow-ups (carry forward)
- **B7 (disputes) deferred scope:** tier-based auto-resolve (small-refund disputes settled without
  admin review); customer/technician appeals on a RESOLVED dispute; abuse-detection (repeat-disputer
  flagging, feeds the trust system); admin dispute dashboard UI (queries exist, no UI until admin
  lands); technician-raised disputes (currently customer-only); warranty/rework flow as a dispute
  outcome (vs. only refund/no-refund/partial today); deposit deduction (no security-deposit model yet).
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
