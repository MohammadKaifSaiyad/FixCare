# Changelog

Significant changes, most recent first. Rolling ~30-day window — older entries
can be trimmed. The *live* project state lives in [`STATUS.md`](STATUS.md);
this is the history of how it got there.

Format: `## YYYY-MM-DD` headers, bullet entries. Update every session.

---

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
