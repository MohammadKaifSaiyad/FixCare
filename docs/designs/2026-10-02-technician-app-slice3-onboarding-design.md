# Technician App Slice 3 — Onboarding + Verification (Design)

**Date:** 2026-10-02
**Branch:** `feature/technician-app-slice3-onboarding` (cut from `main` @ `e370a9c`, job estimate integrity merged #38)
**Status:** Approved design → ready for plan
**Folds in:** the two "Technician auth" follow-ups from STATUS.md — (a) technician-app login with a customer's
number silently logs into the customer account; (b) the "Verification pending" screen never re-checks status.
**Builds on:** technician Slice 1 (`docs/designs/2026-09-19-technician-app-slice1-scaffold-auth-design.md`), Slice 2 job flow
(`docs/designs/2026-09-20-technician-app-slice2-job-flow-design.md`)

---

## Problem

A new technician today has no way to become a working technician. After phone OTP they land on a
"Verification pending" screen that never re-checks, there is no backend status transition at all (a
technician is made VERIFIED by hand in SQL), and nothing captures *where* they work. Specifically:

1. **No onboarding.** Name + skills are editable via `PATCH /me/profile`, but there is no submit step, no
   review, and no service zones.
2. **Trust hole.** Skills are editable at any time — a VERIFIED technician can add skills ops never vetted,
   and dispatch will then offer them jobs for those skills.
3. **Dispatch ignores geography.** `listAvailableJobs` / `acceptJob` filter by skill only; a Padra
   technician is offered Vadodara jobs.
4. **No ops controls.** There is no endpoint to verify, send back, suspend, or reinstate a technician.
5. **Auth role bug.** `verifyOtp` ignores the requested role for an existing phone, so entering a
   customer's number in the technician app logs into the *customer* account.
6. **Pending screen is dead-ended.** `/home` reads the session once; nothing refreshes it.

## Goal & success criteria

- A new technician can fill in **name + skills + service zones**, submit, and see the outcome in-app
  without logging out.
- Ops can **verify**, **send back with a reason**, **suspend** (with reason) and **reinstate** — every change
  audited.
- Once submitted, a technician **cannot change** their own name/skills/zones; ops can change skills/zones
  via an audited admin API.
- Technicians are only offered and can only accept jobs **in their zones** (and skills, as today).
- Logging into an app with a number registered under a different role is **rejected with a clear
  message**, and no tokens are issued.

## Decisions (agreed in brainstorming)

1. **Collect name + skills + service zones; ops verifies in person.** No documents stored in V1 — no KYC
   vendors, no bank details, no security deposit, no Aadhaar images (Golden Rule 6).
2. **Locked once submitted.** Self-edit only while PENDING; ops edits skills/zones afterwards (audited).
3. **Review outcomes: verify, or send back with a reason** (app shows the reason, form unlocks for
   resubmit). Plus a separate ops **suspend** / **reinstate** for already-verified technicians.
4. **Status machine on the existing `Technician` row** (Option 1), reusing `TechnicianStatus`:
   `PENDING` = draft / sent back, `KYC_SUBMITTED` = submitted for review (V1 meaning), `VERIFIED`,
   `SUSPENDED`. Chosen over a separate application table (duplicates the profile) and over a status-less
   "verified flag" (no review history, no lock).
5. **Role mismatch is rejected at OTP verify**, not at send (rejecting at send would let anyone probe
   which numbers are registered).

---

## Backend changes

### Schema (one additive migration)

- `Technician` gains `reviewNote String?` (ops' send-back / suspend reason), `submittedAt DateTime?`,
  `reviewedAt DateTime?`.
- New link table:
  ```prisma
  model TechnicianZone {
    technicianId String
    zoneId       String
    createdAt    DateTime   @default(now())
    technician   Technician @relation(fields: [technicianId], references: [id])
    zone         Zone       @relation(fields: [zoneId], references: [id])
    @@id([technicianId, zoneId])
    @@index([zoneId])
  }
  ```
- `AuditAction` gains `TECHNICIAN_STATUS_CHANGED` — metadata `{from, to, reason?}`. Admin skill/zone
  edits reuse `PROFILE_UPDATED` with metadata `{fields, by: 'admin'}`. Audit rows carry field names, never
  values; no phone or other PII.

### Status lifecycle

Each transition runs in one transaction with its audit row, and re-reads the status inside the
transaction (a racing double-submit / double-review gets the 409, not a double audit row).

| From | Action | To | Actor | Notes |
|---|---|---|---|---|
| PENDING | submit | KYC_SUBMITTED | technician | requires name, ≥1 skill, ≥1 ACTIVE non-deleted zone; sets `submittedAt` |
| KYC_SUBMITTED | verify | VERIFIED | ops | sets `reviewedAt`, clears `reviewNote` |
| KYC_SUBMITTED | send back `{reason}` | PENDING | ops | reason required (1..500); sets `reviewNote`, `reviewedAt` |
| VERIFIED | suspend `{reason}` | SUSPENDED | ops | reason required; **409 while the technician has an active (non-terminal) job** |
| SUSPENDED | reinstate | VERIFIED | ops | sets `reviewedAt`, clears `reviewNote` |

- Any other transition → **409 `INVALID_TECHNICIAN_TRANSITION`**.
- Suspend is refused mid-job because every job route already requires VERIFIED — suspending mid-job
  would strand the customer with a locked visit fee. A suspended technician cannot move money anyway:
  completion and cash both need the customer's OTP (two-sided confirmation). Ops resolves the active job
  first.
- A resubmit after send-back keeps `reviewNote` until the next review decision, so the technician can
  still see what was asked of them.
- `DEACTIVATED` is untouched by this slice (no transitions in or out).

### Technician endpoints

- **`PATCH /me/profile`** (technician branch) — body `{name, skills, zoneIds}` (Zod: name 1..80 trimmed,
  skills non-empty unique `ServiceSkill[]`, zoneIds non-empty unique uuid[]). Allowed **only while
  PENDING**; otherwise **409 `PROFILE_LOCKED`** *"Your profile is locked while under review"*. Zones are
  replaced (delete + insert in the tx). Zone IDs are validated through a **catalog-module service call**
  (ACTIVE, not deleted) — no cross-module DB query; an invalid zone → 422. Audit `PROFILE_UPDATED`
  `{fields}` as today. Customer branch unchanged.
- **`POST /technician/me/submit`** — bodyless; `requireAuth` → technician role (not the VERIFIED gate).
  Re-validates completeness server-side (incl. zones still ACTIVE) → 422 with a clear message if not.
- **Profile DTO** (`GET /me/profile`, technician) gains `zones: {id, name}[]`, `reviewNote: string|null`,
  `submittedAt: string|null`.

### Admin endpoints (`/admin/technicians`, `[requireAuth, requireAdminLevel('MANAGER')]`)

| Route | Body | Result |
|---|---|---|
| `GET /admin/technicians?status=` | — | list DTO: id, **masked phone `••••••XXXX`**, name, skills, zones, status, submittedAt, reviewedAt, reviewNote |
| `POST /admin/technicians/:id/verify` | — | KYC_SUBMITTED → VERIFIED |
| `POST /admin/technicians/:id/send-back` | `{reason}` | KYC_SUBMITTED → PENDING |
| `POST /admin/technicians/:id/suspend` | `{reason}` | VERIFIED → SUSPENDED |
| `POST /admin/technicians/:id/reinstate` | — | SUSPENDED → VERIFIED |
| `PATCH /admin/technicians/:id` | `{skills?, zoneIds?}` (≥1 field) | edits in any status; audited `PROFILE_UPDATED {fields, by:'admin'}` |

All `:id` params and bodies Zod-validated; missing technician → 404. The audit row's actor is the admin.
The full phone number never appears in any admin response.

### Dispatch zone filter (technician-jobs module)

- `listAvailableJobs` adds `zoneId ∈ technician's zones` (the booking's **snapshotted** `zoneId` — never
  re-resolved from the address).
- `acceptJob` checks the same and rejects an out-of-zone job with **403** *"This job is outside your
  service zones"* (checked inside the accept transaction alongside the skill check).
- The technician's zones are read through a technician-profile service call, not a cross-module query.

### `TECHNICIAN_NOT_VERIFIED` code

`requireTechnician` (the VERIFIED gate on every `/technician/jobs/*` route) keeps its 403 *"Verified
technician required"* but adds code **`TECHNICIAN_NOT_VERIFIED`**, so the app can react to a mid-session
suspension.

### Login role-mismatch fix (auth module)

In `verifyOtp`, **after** the OTP is verified (proving ownership of the number), if the phone already has a
user whose `role` ≠ the role carried in the OTP payload → **409 `ROLE_MISMATCH`** with a role-specific
message:
- existing CUSTOMER, technician app: *"This number is registered as a customer. Please use the FixCare
  customer app."*
- existing TECHNICIAN, customer app: *"This number is registered as a FixCare technician. Please use the
  FixCare Pro app."*
- existing ADMIN: *"This number can't be used to sign in here."*

No tokens are issued, nothing is created, the OTP is consumed. New sign-up and same-role login unchanged.

---

## Technician app changes (`apps/technician`)

### Home gate

`/home` builds a **`HomeGate`** `ConsumerWidget` that **watches** the session (today's builder reads it once,
which is why the pending screen never moves on):

| Session | Screen |
|---|---|
| authenticated, not hydrated (profile fetch failed) | "Couldn't load your profile" + **Retry** — never a blank form |
| PENDING | **Onboarding form** |
| KYC_SUBMITTED | **Under review** |
| VERIFIED | Jobs home (unchanged) |
| SUSPENDED / DEACTIVATED | **Account suspended** |

`AuthController.refreshProfile()` re-fetches `/me/profile` and updates the session (unauthorized → logout as
today; network failure keeps the current session — no stale-error shortcut, no auto-retry loop, per the
Riverpod 3 rules in memory).

### Data

- `TechnicianProfileDto` gains `zones: List<ZoneRefDto>` (`{id, name}`), `reviewNote`, `submittedAt`.
- `TechnicianProfileRepository.updateProfile({name, skills, zoneIds})` (PATCH, JSON body) and
  `submit()` (bodyless POST).
- `CatalogRepository.zones()` → `GET /catalog/zones` (bodyless GET).

### Onboarding form (PENDING)

- **Sent-back banner** when `reviewNote` is set: *"FixCare sent your profile back: «reason». Please fix and
  resubmit."*
- **Name** field (prefilled), **skills** as chips (AC / Fan / Electrical / Wiring / Appliance, ≥1),
  **service zones** checklist from `zones()` (≥1) with loading / error-with-Retry / empty states.
  Prefilled from the profile (incl. zones) on resubmit.
- **Submit for verification** enabled when valid → confirm dialog *"Submit your details? You won't be able
  to change them while FixCare reviews your profile."* → `updateProfile` → `submit` → `refreshProfile` (the
  gate moves to Under review). If the PATCH succeeded but submit failed, tapping again re-PATCHes the same
  values then submits — idempotent. Any Failure message shown verbatim in a SnackBar; busy flag,
  try/finally, `mounted` guards.
- No separate "save draft" — the form is short.

### Under review screen (KYC_SUBMITTED)

- *"Your details are with FixCare for verification"* + a read-only summary (name, skills, zone names).
- **Re-checks status:** a 30 s poll while foregrounded that **pauses when backgrounded** (same pattern as
  `job_detail_controller`), an immediate check on resume, pull-to-refresh, and a **Check status** button.
  Log out stays.

### Suspended screen

*"Account suspended"* + ops' reason (`reviewNote`) + *"Contact FixCare support"*. **Check again** button and
pull-to-refresh (no timer — reinstatement is rare). Log out stays.

### Mid-session suspension

When any job call returns code `TECHNICIAN_NOT_VERIFIED`, the app calls `refreshProfile()` → the gate shows
the Suspended screen instead of a generic error.

### OTP screen — role mismatch (both apps)

Both apps currently show *"That code isn't right."* for every failure. On code `ROLE_MISMATCH` they show
the server's message instead. Customer app: that one case + a test; nothing else changes there.

---

## Testing

**Backend (vitest, real Postgres):**
- Lifecycle: each allowed transition → one `TECHNICIAN_STATUS_CHANGED` audit row (`{from, to, reason?}`, no
  PII) and correct `submittedAt` / `reviewedAt` / `reviewNote`; every disallowed transition → 409
  `INVALID_TECHNICIAN_TRANSITION`; send-back / suspend without reason → 400; suspend with an active job → 409.
- Submit: incomplete (no name / skill / zone, inactive or deleted zone) → 422; complete → KYC_SUBMITTED.
- Profile lock: technician PATCH OK while PENDING (zones replaced; audit field names only); 409
  `PROFILE_LOCKED` in KYC_SUBMITTED / VERIFIED / SUSPENDED; invalid zone 422; customer PATCH unchanged;
  profile DTO carries zones / reviewNote / submittedAt.
- Admin: 401 without a token; 403 for a SUPPORT admin, a customer, a technician; list filters by status and
  masks the phone (full number absent from the response body); admin PATCH audited with `by: 'admin'`;
  missing technician 404.
- Dispatch: `available` hides out-of-zone jobs; `accept` out-of-zone → 403.
- Auth: customer number via technician OTP → 409 `ROLE_MISMATCH`, no tokens, no new user/profile; and the
  reverse; normal login and new sign-up unchanged.
- `TECHNICIAN_NOT_VERIFIED` code on the existing 403.
- Existing suite: `makeTechnician()` gains optional `zoneIds`; tests that go through `available` / `accept`
  pass the booking's zone; tests that set `technicianId` directly need none. `tsc` + full suite green.

**Technician app (flutter, hermetic, `http_mock_adapter`):** repository contracts (PATCH body
`{name, skills, zoneIds}`; bodyless submit POST; bodyless zones GET; DTO parses zones / reviewNote /
submittedAt); HomeGate maps each status (+ unhydrated) and swaps on change; onboarding form (validation
gate, confirm dialog, PATCH → submit → refresh order, idempotent retry, sent-back banner, zones
loading / error / empty); under-review polling (30 s, background pause, resume check, pull-to-refresh,
button, transition to VERIFIED); suspended screen (reason, Check again); `TECHNICIAN_NOT_VERIFIED` →
refresh; OTP screen `ROLE_MISMATCH` message. `flutter analyze` 0 issues.

**Customer app:** one OTP-screen `ROLE_MISMATCH` test; rest of the suite unchanged and green.

**Review gates:** per-task spec + quality review → `prisma-migration-reviewer` on the migration →
whole-branch review + golden-rules-auditor (audit, PII) + fraud-vector-checker (trust system:
self-verification, post-verification skill/zone changes, out-of-zone dispatch) + flutter-widget-reviewer →
`/code-review` + one fix wave → run both apps on the simulators.

## Rollout

- **One additive migration** (3 nullable columns, `TechnicianZone`, one enum value). Nothing destructive.
- **No backfill.** Existing VERIFIED dev technicians have no zones → they see no jobs until ops adds zones
  via the admin PATCH (dev data only today).
- **Dev harness:** `scripts/dev-drive-booking.sh` `ensure_tech` also inserts a `TechnicianZone` row for the
  booking's zone, so the dev flow keeps working.
- **Docs:** a short Bruno/curl runbook for the ops review endpoints in `docs/06-operations/` (no admin UI
  until later, ADR-0004); `docs/02-product/trust-system.md` needs no change (it doesn't describe the V1
  intake flow; the deposit stays deferred); STATUS.md (#38 shipped, this slice active, remove "Technician
  auth" (a)(b) from deferred); CHANGELOG.

## Out of scope (tracked)

KYC vendors (Setu / Karza), bank account, security deposit, skill video, document capture; push / SMS
"you're verified" notifications (the app learns by polling); the admin dashboard UI; ops reassigning a
suspended technician's active job; technicians self-editing zones after verification.
