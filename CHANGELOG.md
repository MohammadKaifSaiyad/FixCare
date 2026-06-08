# Changelog

Significant changes, most recent first. Rolling ~30-day window — older entries
can be trimmed. The *live* project state lives in [`STATUS.md`](STATUS.md);
this is the history of how it got there.

Format: `## YYYY-MM-DD` headers, bullet entries. Update every session.

---

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
