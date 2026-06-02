# FixCare — Status

> **Live source of truth** for where the project is. Claude Code reads this at
> session start and updates it at session end. Keep it short — this is a
> dashboard, not a journal. Detail goes in `CHANGELOG.md` and weekly notes.

_Last updated: 2026-05-30_

---

## Phase
**Month 1-2 — Backend foundation.** Schema + bootstrap + OTP (sub-slice A) merged
to `main`. Auth module nearly complete (0,A done; B done on branch; C next).

## Active task
Auth **sub-slice B (JWT + refresh rotation + requireAuth)** complete on
`feature/auth-jwt-refresh` (requireAuth, /auth/refresh rotation + reuse-detection,
logout/logout-all, composite index; 37 tests green; register→refresh→reuse smoke
passes). Next: **sub-slice C — admin email/password login** (`/admin/auth/login`,
argon2id, seed script — the last auth sub-slice). Design:
[`docs/designs/2026-05-31-auth-module-design.md`].

## Last shipped
- **Auth sub-slice B (JWT + refresh + requireAuth)** (`apps/backend`): `requireAuth`
  middleware (verify JWT → per-request user load → reject suspended/deleted → typed
  `request.user`) + `assertOwnership`; `POST /auth/refresh` (rotation: old revoked+linked,
  sliding 30d; reuse-detection → revoke all user tokens + `REFRESH_TOKEN_REUSE_DETECTED`
  audit → 401); `/auth/logout` + `/auth/logout-all`; composite `RefreshToken(userId,expiresAt)`
  index. 37 tests green; security-reviewed (no blocking issues). On branch.
- **Auth sub-slice A (OTP + registration)** — merged to `main` (`/auth/otp/send` + `/verify`,
  invariant guard, token issue, OtpSender stub).
- **Auth bootstrap (sub-slice 0)** — merged to `main` (Fastify app, config, Redis,
  error handler, /health).
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
1. Sub-slice C — admin email/password (argon2id) login + `/admin/auth/login` + seed
   script (the last auth sub-slice; admins reuse the requireAuth built in B).
2. After auth: first protected resource route using `requireAuth` + profile-detail
   updates (technician name/skills), then the next backend module (bookings/catalog).
3. Hardening backlog: rate-limit `/auth/refresh`; MSG91 wiring once DLT approved.

## Deferred follow-ups (carry forward)
- **Rate-limit `/auth/refresh`** (review note from sub-slice B — brute-force needs a
  valid token first, so low urgency; do with the broader rate-limit hardening pass).
- Add a `Merchant` smoke test (the one profile without a dedicated test).
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
