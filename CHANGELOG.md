# Changelog

Significant changes, most recent first. Rolling ~30-day window — older entries
can be trimmed. The *live* project state lives in [`STATUS.md`](STATUS.md);
this is the history of how it got there.

Format: `## YYYY-MM-DD` headers, bullet entries. Update every session.

---

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
