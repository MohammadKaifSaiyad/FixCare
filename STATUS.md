# FixCare — Status

> **Live source of truth** for where the project is. Claude Code reads this at
> session start and updates it at session end. Keep it short — this is a
> dashboard, not a journal. Detail goes in `CHANGELOG.md` and weekly notes.

_Last updated: 2026-05-30_

---

## Phase
**Month 1-2 — Backend foundation.** Full auth module merged to `main`. First
protected feature (profile-update) done on branch. Next: the next backend module
(bookings or service catalog).

## Active task
**Profile-update slice** complete on `feature/profile-update` (GET/PATCH /me/profile
— first requireAuth-protected feature; 60 tests green; live smoke GET→PATCH works).
Next: brainstorm the **next backend module** — likely the booking lifecycle or the
service catalog (per `docs/05-development/build-sequence.md`). Start with `brainstorming`.

## Last shipped
- **Profile-update slice** (`apps/backend`, first protected feature): `GET /me/profile`
  + `PATCH /me/profile`, both `requireAuth`-gated; role-routed (customer name; technician
  name + skills full-replace); implicit ownership (own row by userId — no IDOR); empty
  body / unknown field → 400; MERCHANT/ADMIN → 403; soft-deleted → 404; `PROFILE_UPDATED`
  audit (field names, no values). New `profiles/` module. 60 tests; security-reviewed
  (no code defects; added MERCHANT/ADMIN + soft-delete-PATCH coverage). On branch.
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
1. Next backend module — **service catalog** (service categories + geofenced labor
   pricing + parts master) OR **booking lifecycle** (state machine). Decide + brainstorm.
   Per build-sequence Months 1-3.
2. Customer addresses module (needed by booking/dispatch) + geofence zones (PostGIS).
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
