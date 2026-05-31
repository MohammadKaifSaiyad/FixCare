# FixCare — Status

> **Live source of truth** for where the project is. Claude Code reads this at
> session start and updates it at session end. Keep it short — this is a
> dashboard, not a journal. Detail goes in `CHANGELOG.md` and weekly notes.

_Last updated: 2026-05-30_

---

## Phase
**Month 1-2 — Backend foundation.** Monorepo/docs done. First backend slice
(auth + users schema) implemented on branch `feature/auth-users-schema` — pending
PR/merge to `main`.

## Active task
Auth + users **schema slice** complete on `feature/auth-users-schema` (11 tests
green, migration applied to `fixcare_dev`). Next: open the PR / merge, then the
**auth module** (OTP→JWT→refresh service + routes) — the schema's service-layer
counterpart. Design: [`docs/designs/2026-05-30-auth-users-schema-design.md`].

## Last shipped
- **Auth + users schema slice** (`apps/backend`): scaffolded Fastify 5 + TS strict
  + Prisma 6 + Vitest; User, RefreshToken, Customer/Technician/Merchant/Admin,
  AuditLog; 11 TDD invariant tests green; first migration `20260531052019_auth_users_slice`
  applied to `fixcare_dev` (migration-reviewed, no blocking issues). On branch, not yet merged.
- Monorepo structure + git initialized (`apps/`, `packages/`, docs folders).
- Doc paths reconciled; Superpowers specs pinned to `docs/designs/`.
- "Worker" → "Technician" rename across all docs.
- Progress-tracking system (this file + weekly notes).
- ADRs 0001-0004.
- **11 project skills** (7 backend, 4 Flutter) + **4 custom review agents**
  in `.claude/`. Listed in CLAUDE.md → "Project Skills & Agents".
- Commit-authorship hooks (`.githooks/commit-msg` + Claude PreToolUse hook).

## Next 3 targets
1. PR + merge `feature/auth-users-schema` to `main` (`/code-review` first).
2. Auth module: OTP (Redis) send/verify → JWT issue → refresh-token rotation
   (service + Zod routes), using the RefreshToken + AuditLog models.
3. User-creation service enforcing the role↔profile invariant (the app-layer guard).

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
