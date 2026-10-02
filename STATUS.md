# FixCare — Status

> **Live source of truth** for where the project is. Claude Code reads this at
> session start and updates it at session end. Keep it short — this is a
> dashboard, not a journal. Detail goes in `CHANGELOG.md` and weekly notes.

_Last updated: 2026-10-02_

---

## Phase
**Technician app (Flutter).** Backend booking module COMPLETE (B1→B7, PR #21); **customer app Slices 1-5 all
merged** (#22-#33). Build order (ADR-0004) is on the **technician app** (`apps/technician`, Android + iOS per
ADR-0005): **Slice 1 scaffold+auth+jobs merged (#35)**, customer interceptor retried-401 back-port merged (#36),
**Slice 2 "drive a job" merged (#37)**, and the **job estimate integrity** follow-up (the Slice 2 pilot blockers) is
complete on branch, ready for PR. Money still on Razorpay test keys until KYC (UPI method blocked on Razorpay account
activation — see Blocked on).

## Active task
**Job estimate integrity** COMPLETE on `feature/job-estimate-integrity` (cut from `main` @ `9737679`, after
Slice 2 merged), **ready for PR → `main`** (not pushed). Resolves the three Slice 2 pilot blockers: the customer can
no longer approve an estimate the technician is still editing, and the technician app reads the cart from the server.
- **Backend:** parts add/remove are **ARRIVED-only**; "Submit diagnosis" (`POST /technician/jobs/:id/diagnose`)
  **freezes the cart** (409 `The cart is locked — the diagnosis has been submitted`) and snapshots `partCount` +
  `partsTotalPaise` in the transition evidence, so DIAGNOSED always shows the customer a final cart.
  `GET /catalog/parts?categoryId=` returns the category's parts + generic parts. New `GET /technician/jobs/:id`
  (job + `parts[]` + active photos); `service.categoryId` on all technician job DTOs.
- **Technician app:** `FailureKind.forbidden/notFound`; `job(id)`; job-detail polls the single job (403/404 → "This
  job is no longer assigned to you.", recovers if it comes back). The ARRIVED diagnosis form carries the **complete
  estimate** (2 photos + category-filtered issue picker + server-backed parts cart + "Customer will see: ₹…" + a
  confirm dialog before sending; Submit blocked while a cart edit is in flight). DIAGNOSED is a read-only "Estimate
  sent — waiting for the customer to approve or decline" card with the frozen lines + total. Session-only cart removed.
- **Final-review fix wave (4 commits):** backend — one line per part (409) + 20-line cap (422), per-line audit
  evidence on diagnose/add/remove (remove audits only a real delete), decline evidence parity, ownership + race tests;
  technician — `refetch()` reports success and an unconfirmed cart blocks Submit (`Couldn't confirm the latest parts.`
  + Retry), throw-safe poll, cart locked while sending, the confirm dialog lists the lines + total, 8-row parts list,
  a non-"not assigned" 403 (e.g. `Verified technician required`) shown verbatim; customer — the approve card shows
  line totals + a Labor / Parts / Visit fee credit breakdown. Estimate-integrity vectors added to
  `docs/02-product/fraud-defenses.md` (#16).
- **`/code-review` fix round (4 commits):** diagnose is **bound to the confirmed cart** — the app sends the confirm
  dialog's `expectedPartLineIds` and any drift → 409 `ESTIMATE_CHANGED` (`The estimate changed — check the parts and
  send again`; booking stays ARRIVED, nothing written; field optional for older builds); stable **`JOB_NOT_FOUND` /
  `JOB_NOT_ASSIGNED`** codes on the technician job errors, and `Failure.code` in the app — a vanish keys on the code
  only (a code-less 404 is transient on poll / a generic error on first load); `GET /technician/jobs/:id` carries a
  **server-computed `customerQuote`** that "Customer will see", the confirm dialog and the sent card display (client
  `estimatePaise` deleted; no quote → amount hidden); "unconfirmed cart" is cleared by **fetch sequence**
  (`jobFetchOkSeq`), and a superseded refetch counts as success; a catalog part already in the estimate shows "In
  estimate"; one line formula (`lineTotalPaise`, both apps) + one `PartLineText` widget; **no silent catches**
  (`FlutterError.reportError`, exception + stack only).
- **Deploy order:** requires the matching backend — **deploy the backend first**. Slice-2 technician builds can only
  send labor-only estimates (part adds 409). This technician build on an older backend: diagnose 400s (strict body
  rejects `expectedPartLineIds`), the quote is hidden, and a job-detail 404/403 without a job code is not treated as
  "no longer assigned".
- **Gates:** backend **400/400 (67 files), tsc clean**; technician app **320 tests, analyze clean**; customer app
  **+179 ~5, analyze clean**.
  Design/plan: `docs/designs/2026-10-01-job-estimate-integrity-design.md`, `docs/plans/2026-10-01-job-estimate-integrity.md`.
**Next: PR → `main` (founder pushes); on-device smoke (physical Android 12+ phone + iPhone); then the follow-ups below.**

## PRIOR active task (customer app Slice 5 — payment, MERGED #31; kept below for history)
**Customer app Slice 5 — payment** COMPLETE on `feature/customer-app-slice5-payment` (commits `5c337a3..ebe211b`),
**ready for PR → `main`**. Replaces the Slice-4 "payment coming soon" placeholder with a real pay card at the two
payable states (`CUSTOMER_CONFIRMED` = approved total; `DECLINED_BY_CUSTOMER` = visit fee). Two paths: **UPI** via
the `razorpay_flutter` native checkout (bodyless `POST …/pay` → `{orderId, amountPaise, keyId}` → checkout sheet;
confirmation is **webhook-driven server-side**, the app only refetches — never client-trusts "paid"), and **Cash**
(bodyless `POST …/pay-cash` → 6-digit receipt OTP SMS'd to the customer, displayed to read to the technician who
enters it — keystone asymmetry, the customer never submits it; dev echoes `devOtp` behind `!kReleaseMode`). A pure
`payViewFor` derives the pay sub-state (choose/upiPending/cashPending/paid/none) from state + payment. **`keyId ==
null` (dev / no Razorpay keys) → a first-class "UPI unavailable, pay by cash" branch — the plugin is never opened.**
New native dep recorded in **ADR-0006**. Built via SDD (4 tasks, each spec+quality reviewed; final whole-branch
review MERGE-READY, Golden Rules 1/3 verified). 166 tests (`+166 ~5` hermetic, contract-smoke skips without
BASE_URL); `flutter analyze` clean. Design/plan: `docs/designs/2026-09-12-…-design.md`, `docs/plans/2026-09-12-…md`.
**iOS pod integration (razorpay_flutter's pod) is a founder-Mac follow-up** (`flutter build ios`; the pbxproj/
Podfile.lock changes were intentionally NOT committed — pod resolution was incomplete).
**Next: PR → `main` (founder pushes/merges). Then Razorpay TEST keys to exercise UPI end-to-end, or the next slice.**

## Last shipped
- **Technician app Slice 2 — drive a job end-to-end** (**merged PR #37**) — state-driven job-detail screen: en-route →
  arrive (mints the arrival code) → diagnose (2 evidence photos + issue) → parts → repair (3 photos) → confirm
  completion/cash by entering the customer's codes. Camera-evidence pipeline (ADR-0007: camera-only, capture-time
  timestamp + geotag, <500KB, retrying upload queue, presigned PUT via a bare Dio — fixed a JWT-to-R2 leak). Dev-only
  `POST /dev/photos/mark-uploaded` (not registered in prod). Built via SDD + final review → one fix wave.
  249 app tests, backend 375/375.
- **Technician app Slice 1 — scaffold + phone-OTP auth + jobs** (**merged PR #35**) — new Flutter app
  `apps/technician`; backbone adapted from the customer app; VERIFIED-gated jobs home (available/mine/accept).
  31 tests. Plus **customer auth-interceptor retried-401 back-port** (**merged PR #36**).
- **Customer app Slice 5 — payment** (`feature/customer-app-slice5-payment`, on branch, `5c337a3..ebe211b`) — pay
  card with UPI (`razorpay_flutter`, keyId-gated) + cash (receipt-OTP handshake, customer displays not submits).
  Bodyless pay calls; paid only via poll/webhook (never client-trusted); pure `payViewFor` mapper; keyId-null
  fallback. ADR-0006. 166 tests, analyze clean; final review MERGE-READY, Golden Rules 1/3 held.
- **Customer app Slice 4 — booking tracking** (**merged PR #30**) — live 18-state tracking: adaptive-poll
  `@riverpod` controller (stop-at-terminal, keep-last-good, refetch), pure `phaseFor` mapper, timeline +
  arrival/decision/completion gate cards, decline confirm-dialog, dev-echo OTP behind `!kReleaseMode`, app-side
  address-label join. 145 tests, analyze clean.
- **Customer app — backend contract-smoke test** (**merged PR #29**) — one test that exercises real dio → real
  backend → seeded dev DB across auth/profile/address/catalog/booking. Guards the DELETE-content-type class of
  bug the mocked suite can't see. Skips cleanly with no
  backend so the default suite stays green. README documents the run steps. Analyze clean; 5/5 live, hermetic green.
- **Customer app — founder bug-fixes** (`fix/home-avatar-initials`, **merged PR #28**): (1) empty `fixcare_dev`
  DB → ran `NODE_ENV=development pnpm db:seed` (no code change; "391440 not serviceable" was missing seed data);
  (2) home avatar shows the customer's **real initials** via `initialsOf(name)` ("Kaif Saiyad"→"KS") instead of a
  hardcoded "RP"; (3) **DELETE address 400** fixed — removed the global dio `contentType: application/json` that
  stamped bodyless GET/DELETE and made Fastify reject them (`FST_ERR_CTP_EMPTY_JSON_BODY`); added a regression test
  (`dio_content_type_test.dart`). Analyze clean.
- **Customer app Slice 3** (`apps/customer`, **merged PR #27**) — discovery + create booking. Catalog module
  (Category/Service DTOs + repo); full BookingDto + repo (create/get/cancel); Home real-catalog by default-address
  zone; booking wizard (address/slot/confirm + create, 422 surfaced not swallowed); tracking stub. 88 tests,
  analyze clean.
- **Customer app Slice 2** (`apps/customer`, **merged PR #25/#26**) — profile + addresses + boot hydration +
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
1. **PR job estimate integrity** → `main` (founder pushes/merges `feature/job-estimate-integrity`). Then a clean
   `flutter build ios` on the Mac to wire the Slice 2 pods (image_picker / flutter_image_compress / geolocator).
2. **On-device smoke** of the full job flow against the local backend (dev photo hook): a **physical Android 12+
   phone** (ideally 2-3GB RAM) and an **iPhone** — the iOS simulator has no camera. Include deny-then-allow for
   camera + location, the new diagnosis-form confirm dialog / cart-lock path, and an airplane-mode toggle during a
   part add at ARRIVED (should show "Couldn't confirm the latest parts." + Retry). Record anything found (e.g.
   image_picker activity-kill → `retrieveLostData`).
3. **Auth follow-ups found in the dev run** (see Deferred follow-ups → "Technician auth"): reject a technician login
   with a customer's number, and re-check status on the "Verification pending" screen. Then the remaining Slice 2
   follow-ups; provision Cloudflare R2 (`R2_*`) — and fix the presign settings first.

## Deferred follow-ups (carry forward)
- **Job estimate integrity — deferred from the final review (the pilot blockers and the review's Important/Medium
  items are fixed on `feature/job-estimate-integrity`):** (a) minimum-app-version gate for technician builds;
  (b) bind the customer's approve to a cart version / expected total (latent while nothing writes parts after
  ARRIVED) — optionally an `expectedPartsTotalPaise` check on diagnose; (c) estimate revision after sending, and a
  rule watching visit-fee farming via deliberately bad estimates (product); (d) `getMyJob` returns the full address
  after a cancel (parity with `mine()`); (e) ~~diagnose not bound to the confirmed cart~~ — **DONE in the
  `/code-review` round** (`expectedPartLineIds` → 409 `ESTIMATE_CHANGED`); (f) a real-screen test of a poll tick at
  ARRIVED; (g) `mine()` still returns the full job history (not yet trimmed to active jobs); (h) a **DB unique index
  on `(bookingId, partsCatalogId)`** as defense in depth for one-line-per-part (needs a migration that first
  de-duplicates any existing duplicate dev lines; review with `prisma-migration-reviewer`); (i) cosmetic: a catalog
  row's qty resets to 1 when a filtered-out row reappears.
- **Technician auth (found in a dev run; fix together):** (a) **technician-app login with a number already registered
  as a CUSTOMER silently logs into the customer account** — backend `verifyOtp`
  (`apps/backend/src/modules/auth/auth.service.ts`) ignores the requested role for an existing phone; it should
  reject with a clear "this number is registered as a customer" error, and the technician app should show it
  instead of "Verification pending"; (b) the technician **"Verification pending" screen never re-checks status** — a
  newly verified technician must log out and back in.
- **Technician Slice 2 — other follow-ups (non-blocking):** `Position.isMocked` arrival signal (needs backend
  `arriveBody` field + a block-vs-flag product decision); **R2 presign before provisioning** — set
  `requestChecksumCalculation: 'WHEN_REQUIRED'` on the S3Client (recent SDKs add checksum params R2 rejects) and note
  content-type is unsignable in the presigner (jpeg-only not cryptographically enforced, despite the comment in
  `r2-storage.ts`); `NODE_ENV` defaults to `development` (fail-open — an unset prod env would register the dev photo
  route and devOtp); dev route checks auth not the TECHNICIAN role; iOS `BYPASS_PERMISSION_LOCATION_ALWAYS` Podfile
  macro before the first TestFlight upload (ITMS-90683); upload queue not reset on logout (≤1 stray retry, backend
  rejects it); `image_picker` `retrieveLostData` for low-memory activity kills is unhandled; real-backend contract
  smoke for the technician flow.
- **Slice 5 payment follow-up (non-blocking — final review MERGE-READY, Golden Rules held):** (a) **iOS pod
  integration** — run a clean `flutter build ios` on the Mac to pull `razorpay_flutter`'s pod into Podfile.lock +
  pbxproj (the incomplete first-time-CocoaPods scaffolding in the working tree was intentionally NOT committed);
  (b) **Razorpay TEST keys** in backend `.env` so UPI checkout runs (keyId is null without them → app shows the
  cash-only fallback); (c) missing widget tests for `CheckoutFailed`/`CheckoutDismissed` outcomes, the
  checkout-`open` arg pass-through, and the FAILED-retry prefix (all correct by inspection; the pure outcome
  mappers ARE unit-tested); (d) real-backend smoke proof of `/pay` + `/pay-cash` once keys + a drivable
  technician `confirm-cash` actor exist. **Cash confirm needs the technician app** (or curl) — the customer app
  builds only its half.
- **Slice 4 tracking follow-up (one ticket, non-blocking — final review MERGE-READY):** (a) **background-poll
  pause** — the design said the 5s poll "pauses when backgrounded"; the controller only refetches on resume, so
  the timer keeps firing while backgrounded (single timer, cleanly disposed — battery/spec-conformance nit, not
  correctness); (b) missing widget tests for the completion **429/Failure SnackBar** (a spec-named no-swallow
  path), the decline-dialog **"Keep repair"** cancel branch, and the **AppLifecycleListener resume→refetch**
  (all correct by inspection, untested); (c) redundant pre-await `ref.mounted` check in `_poll` (cosmetic).
  Also **real-backend smoke proof** of the new gate endpoints (confirm-arrival/approve/decline/completion) once
  the contract-smoke harness can drive a booking to EN_ROUTE/DIAGNOSED/REPAIR_COMPLETE (needs a technician actor).
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
- **Google Maps live tiles need billing enabled** on the Cloud project (deferred by founder).
  The address map picker is wired + crash-safe (`MAPS_ENABLED`+key gate → placeholder without it);
  runbook + Android SHA-1 in `apps/customer/README.md`. Enable billing to render the map; everything
  else works without it.

## Pointers
- **Build order:** Backend → Customer app → Technician app → Admin → Merchant
  (ADR-0004). Operate via direct API calls (Bruno/Postman) until admin is built.
- Branch model: trunk-based, `feature/*` → PR → `/code-review` → `main` (ADR-0002).
- Latest weekly retro: `docs/progress/weekly-notes/2026-09-26.md` (retros for 09-12 and 09-19 were skipped).
