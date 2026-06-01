# FixCare — Status

> **Live source of truth** for where the project is. Claude Code reads this at
> session start and updates it at session end. Keep it short — this is a
> dashboard, not a journal. Detail goes in `CHANGELOG.md` and weekly notes.

_Last updated: 2026-05-30_

---

## Phase
**Month 1-2 — Backend foundation.** Schema + bootstrap merged to `main`. Auth
module underway (sub-slices 0→A→B→C). Sub-slice A on `feature/auth-otp-registration`.

## Active task
Auth **sub-slice A (OTP + registration)** complete on `feature/auth-otp-registration`
(send/verify, invariant guard, token issue; 25 tests green; real send→verify smoke
returns tokens). Next: **sub-slice B — JWT + refresh rotation + `requireAuth`**
(`/auth/refresh` with rotation + reuse-detection, logout/logout-all, `requireAuth`
middleware + ownership, composite `RefreshToken(userId,expiresAt)` index migration).
Design: [`docs/designs/2026-05-31-auth-module-design.md`].

## Last shipped
- **Auth sub-slice A (OTP + registration)** (`apps/backend`): `POST /auth/otp/send`
  (per-phone rate-limit → 429, dev OTP in non-prod) + `POST /auth/otp/verify`
  (single-use, 5-attempt cap, find-or-create via `createUserWithProfile` invariant
  guard, AuditLog, issues access JWT + hashed RefreshToken). OtpSender interface
  (dev stub + inert MSG91). 25 tests green; reviewed (no blocking issues). On branch.
- **Auth bootstrap (sub-slice 0)** — merged to `main` (Fastify app, config, Redis,
  error handler, /health; 17 tests).
- **Auth + users schema slice** — merged to `main` (`User`, `RefreshToken`,
  Customer/Technician/Merchant/Admin, `AuditLog`; 11 tests; migration applied).
- Monorepo structure + git initialized (`apps/`, `packages/`, docs folders).
- Doc paths reconciled; Superpowers specs pinned to `docs/designs/`.
- "Worker" → "Technician" rename across all docs.
- Progress-tracking system (this file + weekly notes).
- ADRs 0001-0004.
- **11 project skills** (7 backend, 4 Flutter) + **4 custom review agents**
  in `.claude/`. Listed in CLAUDE.md → "Project Skills & Agents".
- Commit-authorship hooks (`.githooks/commit-msg` + Claude PreToolUse hook).

## Next 3 targets
1. Sub-slice B — `requireAuth` middleware + ownership; `/auth/refresh` rotation +
   reuse-detection; logout/logout-all; composite `RefreshToken(userId,expiresAt)` index.
2. Sub-slice C — admin email/password (argon2id) login + `/admin/auth/login` + seed script.
3. After auth: profile-detail updates (name/skills) and the first protected resource
   using `requireAuth` — then on to the next backend module (bookings/catalog).

## Deferred follow-ups (from review, pick up in the auth-module slice)
- Composite index `RefreshToken(userId, expiresAt)` (replaces the two single-column
  indexes) — confirm against real query patterns when the auth service exists.
- Add a `Merchant` smoke test (the one profile without a dedicated test).
- Dynamic-introspection TRUNCATE in test helpers (vs the hand-maintained table list).
- Deferred env keys (JWT_SECRET, REDIS_URL, PORT, R2_*, RAZORPAY_*) added to
  `.env.example` when their features land; `dev`/`build`/`start` scripts when the server entry exists.

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
