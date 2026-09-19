# Technician App Slice 1 — Scaffold + Phone-OTP Auth + Jobs (Design)

**Date:** 2026-09-19
**Branch:** `feature/technician-app-slice1-scaffold-auth`
**Status:** Approved design → ready for plan
**Build order:** the technician app is the next app after the customer app (ADR-0004).

---

## Goal

Stand up `apps/technician` (Flutter, Android + iOS per ADR-0005) with:
1. **Phone-OTP auth** for role `TECHNICIAN` (same backend endpoints as the customer app).
2. A **verification-aware home**: a VERIFIED technician sees a **jobs screen** (available
   jobs + accept + my jobs); a non-verified technician sees a **status screen**.

This unblocks the *other* side of every keystone handshake — a real technician can claim
a booking — so the customer flow can be tested end-to-end without the
`dev-drive-booking.sh` harness.

## Non-goals (deliberate)

- **Driving a job forward** (en-route / arrive / diagnose / photos / complete / confirm-cash)
  is Slice 2. Slice 1's "my jobs" is read-only.
- **No admin app** exists to verify technicians — verification is a server-side status an
  admin sets. Slice 1 handles the not-verified state gracefully; for testing, status is
  flipped to VERIFIED via SQL (dev shortcut).
- **No shared Flutter package** — the proven core is duplicated from `apps/customer` (each
  app self-contained; the pnpm workspace is backend+admin only, not Flutter). Extracting a
  shared package is a later refactor.
- No Google Maps / Razorpay deps (the technician doesn't book or pay in Slice 1).
- No polling / real-time dispatch — manual pull-to-refresh for the jobs list.

---

## Backend contract (verified against `apps/backend/`)

### Auth (same endpoints as customer; `role:'TECHNICIAN'`)
- `POST /auth/otp/send` — body `{phone, role:'TECHNICIAN'}`. `phone` = bare 10-digit Indian
  `^[6-9]\d{9}$` (no +91).
- `POST /auth/otp/verify` — body `{phone, role:'TECHNICIAN', otp}` (otp `^\d{6}$`) →
  `{accessToken, refreshToken, user:{id, role:'TECHNICIAN', status}}`. **Note:** `user.status`
  here is the **User** status (ACTIVE/SUSPENDED), NOT the technician status. `role` is ignored
  for an existing phone (stored role wins); it only sets the profile created for a new phone.
- `POST /auth/refresh` — body `{refreshToken}` → `{accessToken, refreshToken}` (rotated 30d,
  reuse-detected).
- A **new** technician phone → `User{role:TECHNICIAN, status:ACTIVE}` + `Technician{name:'',
  skills:[], status:PENDING}` (Prisma default).

### Profile — `GET /me/profile` (shared route, `requireAuth` only)
Returns for a technician: `{id, role:'TECHNICIAN', name, skills: ServiceSkill[], status:
TechnicianStatus}`. NO phone. A fresh signup → `name:''`, `skills:[]`, `status:'PENDING'`.

- `TechnicianStatus` enum (verbatim): `PENDING`, `KYC_SUBMITTED`, `VERIFIED`, `SUSPENDED`,
  `DEACTIVATED`.
- `ServiceSkill` enum: `AC`, `FAN`, `ELECTRICAL`, `WIRING`, `APPLIANCE`.

### Login vs work — two separate gates
- **Login works while PENDING** — `requireAuth` only checks the User row (must exist, not
  deleted, `status==ACTIVE`). A PENDING technician gets a valid token and can call `/me/profile`.
- **Work requires VERIFIED** — every `/technician/jobs/*` service fn calls `requireTechnician`,
  which throws `403 'Verified technician required'` unless `technician.status == 'VERIFIED'`.
  There is also a route-layer role check: `403 'Technician access required'` if the JWT role
  isn't TECHNICIAN.

### Jobs endpoints (Slice-1 relevant)
- `GET /technician/jobs/available` — `requireAuth` + technician role + VERIFIED gate. Returns
  `TechnicianJobDto[]`: `DISPATCHED`, unassigned, **skill-matched** (`service.requiredSkill ∈
  tech.skills`), minus skipped, newest first. A tech with `skills:[]` gets `[]`.
- `GET /technician/jobs/mine` — same gates; the tech's own bookings (all states).
- `POST /technician/jobs/:id/accept` — same gates; guards in order: `404 'Job not found'`;
  `409 'This job is no longer available'` (not DISPATCHED / already assigned); `403 'You are
  not skilled for this job'`; `422 'Settle your cash debt to accept new jobs'`; then an
  optimistic-locked DISPATCHED→ACCEPTED + first-to-accept claim (loser → 409). Returns the
  accepted `TechnicianJobDto`.

### `TechnicianJobDto` (verbatim fields)
`id, bookingNumber, state, scheduledSlot (ISO), service{name, requiredSkill}, zone{name},
visitFeePaise, laborPaise, address{line1, line2?, landmark?, pincode}, customer{maskedPhone},
photos[]{kind, capturedAt, url}`.

**Directional PII masking (Golden Rule 7):** the technician sees the **full address** (needs
to reach the site) but only the customer's **masked phone** (`••••••1234`) and **no customer
name**. (Contrast: the customer's BookingDto sees the technician's real name + masked phone,
and only `address:{id}`.)

---

## Architecture & components

### Core (duplicated from `apps/customer`, adapted)
`core/env.dart` (`--dart-define=BASE_URL`, default `10.0.2.2:3000`), `core/result.dart`
(`Result`/`Ok`/`Failure`/`FailureKind`/`failureKindFromStatus`), `core/storage/token_store.dart`
(secure-storage), `core/network/dio_client.dart` + `auth_interceptor.dart` (single-flight:
401→one refresh→retry via bare dio; fail→clear+onAuthLost; **no global content-type** — carries
the DELETE-bug fix forward), `core/theme.dart` (FixCare tokens), `core/router/app_router.dart`
(token-gate).

### Auth + session
- `AuthRepository`→`Result`: `sendOtp(phone)`/`verifyOtp(phone, otp)` posting `role:'TECHNICIAN'`;
  saves tokens to `TokenStore`.
- `TechnicianProfileRepository`: `GET /me/profile` → `TechnicianProfileDto{id, role, name,
  skills, status}`.
- `AuthController` (`@riverpod`): on build, read token; present → hydrate via `/me/profile` →
  `SessionAuthenticated`; absent → `SessionUnauthenticated`; a hydrate 401 → clear.
- Sealed `Session`: `SessionLoading`, `SessionUnauthenticated`, `SessionAuthenticated({id,
  name, skills, status})` with `bool get isVerified => status == 'VERIFIED'`.

### The verification gate
The home route branches on `session.isVerified`:
- **VERIFIED** → the **jobs home**.
- **NOT verified** → the **verification/status screen**, copy per status:
  - `PENDING`/`KYC_SUBMITTED` → "Your account is under review. We'll notify you once verified."
  - `SUSPENDED`/`DEACTIVATED` → "Your account is suspended. Contact support." (distinct copy).

**Defense in depth:** the jobs repository ALSO maps `403 'Verified technician required'` to a
"verification pending" state (never a raw error), because the server is the authority and
status can change between hydration and a call.

### Jobs feature
- `TechnicianJobDto` (freezed, the DTO above) + `TechnicianJobRepository`: `available()`,
  `mine()`, `accept(id)` → `Result`. 403→verification-pending; 409→"already taken";
  422→cash-debt message surfaced.
- `AvailableJobsController` + `MyJobsController` (`@riverpod` async lists with `refresh()`),
  mirroring the customer `AddressController` pattern. `accept` lives on the controller and
  refreshes both lists on success.
- **Jobs home screen** — two views (Available / My jobs). Available: job cards (service, ₹
  visit fee + labor, zone, address, scheduled slot, masked phone) each with **Accept**; empty
  → "No jobs available right now". My jobs: read-only list of the tech's bookings. Accept: tap
  → `accept(id)` → `Ok` refreshes both lists; `409` → "This job was just taken" SnackBar +
  refresh Available (self-heals); other `Failure` → SnackBar. Per-card busy flag prevents
  double-accept.

---

## Data flow

launch → token-gate reads token → `AuthController` hydrates `/me/profile` → `Session` →
router shows: no token → phone/OTP; token + VERIFIED → jobs home (loads `available` + `mine`);
token + not-verified → status screen. Accept → `POST /accept` → refresh lists.

## Error handling

Never swallow a `Failure`. Auth errors (400/401/429) → inline/SnackBar with the backend
message. Jobs: 403 → verification-pending state; 409 → "already taken" + refresh; 422 →
surfaced verbatim. A hydrate/interceptor 401 that can't refresh → clear session → phone screen.

---

## Files

**Scaffold:** `apps/technician/` — `pubspec.yaml` (riverpod + codegen, go_router, dio,
flutter_secure_storage, freezed, json_serializable, build_runner), Android (`in.fixcare.
fixcareTechnician`) + iOS (bundle, iOS 15+, `localhost` ATS exception) folders, `README.md`
(run commands, per-platform base URLs, PENDING→VERIFIED dev note).

**`lib/core/`:** env, result, theme, storage/token_store, network/dio_client +
auth_interceptor, router/app_router.

**`lib/features/auth/`:** data (auth DTOs + repository), domain/session.dart,
presentation (auth_controller + splash/phone/OTP screens).

**`lib/features/profile/`:** data (technician_profile_dto + repository).

**`lib/features/jobs/`:** data (technician_job_dto + repository),
presentation (jobs_home_screen, available_jobs_controller, my_jobs_controller,
verification_pending_screen).

**`lib/main.dart`** + token-gate wiring.

---

## Testing strategy

Bar: `flutter analyze` 0 issues; hermetic (mock transport / fake repos); TDD.

1. **Auth repository — contract-guarded** (`FullHttpRequestMatcher(needsExactBody: true)`):
   `sendOtp` posts exactly `{phone, role:'TECHNICIAN'}`; `verifyOtp` posts `{phone, role, otp}`
   and parses `{accessToken, refreshToken, user{id,role,status}}`; 400/401/429 → right
   `FailureKind` + message.
2. **Single-flight auth interceptor** — ported from customer: 401→one refresh→retry via bare
   dio; concurrent 401s share one refresh; refresh-fail → clear + onAuthLost.
3. **TechnicianProfileRepository** — parses `{id, role, name, skills[], status}` incl. the
   fresh-signup shape (`name:''`, `skills:[]`, `status:'PENDING'`).
4. **Session / gate** — `isVerified` true only for `'VERIFIED'`; `AuthController` hydration
   (token+profile → authenticated with status; no token → unauthenticated; hydrate 401 → clear).
5. **TechnicianJobRepository — contract-guarded** — `available`/`mine` parse the DTO list
   (masked phone / full address / no name); `accept` parses the returned job; **403
   'Verified technician required' → verification-pending; 409 'This job is no longer available'
   → "already taken"; 422 cash-debt → surfaced.**
6. **Widget tests** — token-gate routing (no token → phone; token+VERIFIED → jobs home;
   token+PENDING → verification screen, jobs NOT shown); jobs home renders cards + empty state;
   accept calls the right id, `Ok` refreshes both lists, `409` shows "just taken" + refresh,
   busy flag blocks double-tap; SUSPENDED/DEACTIVATED show the distinct suspended copy.

**Deferred follow-up (noted, not built):** a real-backend contract-smoke test for the
technician auth+jobs path (like the customer app's), once we decide whether to share or
duplicate that harness.

**Dev/testing shortcuts (SQL, not code):** flip a fresh technician to `VERIFIED` and assign a
skill (e.g. `FAN`) so the jobs list populates — same shortcuts the `dev-drive-booking.sh`
harness already uses; no admin app yet.

---

## Carry-forwards honored

- Same backend, same auth backbone; app sends only `{phone, role, otp}` — no secrets, no PII
  beyond the phone the user types.
- No global dio content-type (carries the DELETE-bug fix from the customer app).
- Directional PII masking respected — the app only ever receives the masked phone + no
  customer name; it never asks for more.
- The technician never sees or drives money in Slice 1; VERIFIED-gating is enforced both
  app-side (UX) and via the repo's 403 handling (correctness).
