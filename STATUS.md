# FixCare — Status

> **Live source of truth** for where the project is. Claude Code reads this at
> session start and updates it at session end. Keep it short — this is a
> dashboard, not a journal. Detail goes in `CHANGELOG.md` and weekly notes.

_Last updated: 2026-05-30_

---

## Phase
**Month 1-2 — Backend foundation.** Schema + bootstrap + OTP + JWT/refresh merged
to `main`. **Auth module COMPLETE** (sub-slice C done on branch). Next: first
protected feature / next backend module.

## Active task
Auth **sub-slice C (admin login)** complete on `feature/auth-admin-login`
(`/admin/auth/login` argon2id, generic 401 no-enumeration, suspended/deleted → 403,
reuses requireAuth + token machinery; idempotent SUPER_ADMIN seed; 45 tests green;
seeded `fixcare_dev` + admin-login smoke 200/401/401). **The auth module is now
complete** (customer/technician OTP + admin password + full session lifecycle).
Next: a first `requireAuth`-protected resource (e.g. technician profile-detail
updates: name/skills), then the next backend module (bookings or catalog) — start
that with `brainstorming`.

## Last shipped
- **Auth sub-slice C (admin login)** (`apps/backend`): `POST /admin/auth/login`
  (argon2id verify; identical generic 401 for unknown-email AND wrong-password — no
  enumeration; suspended/deleted → 403; reuses access JWT + hashed RefreshToken +
  requireAuth; AuditLog USER_LOGGED_IN/ADMIN; DTO never exposes passwordHash) +
  idempotent `prisma/seed.ts` + `db:seed`. 45 tests green; security-reviewed. On branch.
- **Auth sub-slices 0/A/B** — merged to `main`: bootstrap (Fastify app, config, Redis,
  error handler, /health); OTP send/verify + registration + invariant guard; JWT +
  refresh rotation + reuse-detection + requireAuth + logout/logout-all.
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
1. First `requireAuth`-protected resource: technician/customer profile-detail updates
   (name, technician skills) — brainstorm → design → plan → build.
2. Next backend module — bookings lifecycle or service catalog (per build-sequence).
3. Hardening backlog (see deferred): rate-limit `/auth/refresh` + `/admin/auth/login`;
   admin-login timing-oracle dummy-verify; MSG91 wiring once DLT approved.

## Deferred follow-ups (carry forward)
- **Auth rate-limiting hardening pass:** tighter per-IP/email limit + lockout on
  `/admin/auth/login`; rate-limit `/auth/refresh` (review notes from B + C — both
  need a valid token/account first, so low urgency).
- **Admin-login timing oracle** (review note from C): unknown-email skips argon2 →
  faster response can reveal whether an email is registered. Fix = dummy-hash verify
  on the unknown path. Minor / V1-acceptable at single-digit admin scale.
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
