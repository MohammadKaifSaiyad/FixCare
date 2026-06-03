# Design — Profile-update Slice

_Date: 2026-06-03 · Status: approved (pending spec review) · Scope: the first `requireAuth`-protected feature in `apps/backend`_

## Context

The auth module is complete (OTP login for customer/technician, admin password login,
JWT + refresh rotation + reuse-detection, `requireAuth` + `assertOwnership`, logout/
logout-all). Every endpoint so far has been an *auth* endpoint. This slice is the
**first protected resource** — letting an authenticated customer/technician read and
update their own profile detail — and so it's the proving ground for `requireAuth` on a
real feature. It's deliberately small.

Grounded in: the merged auth module, `docs/04-architecture/module-structure.md` (module
pattern), `docs/05-development/coding-conventions.md` (route→service→DTO, auth-first,
own-data-only), `CLAUDE.md` Golden Rule ("a user can only access their own data").

## Decisions locked (during brainstorming)

1. **`GET /me/profile` + `PATCH /me/profile`** — single role-routed surface; the caller's
   role (from the JWT) selects the Customer or Technician table.
2. **Ownership is implicit** — the row is always the caller's own, looked up by
   `request.user.id` (= the User id). No resource id in the URL → nothing to abuse;
   `assertOwnership` is not needed here (it's for routes that take a resource id).
3. **Editable:** Customer `name`; Technician `name` + `skills`. PATCH is partial (any
   subset); **skills is full-replace** (the body's array replaces the stored set).
4. **Immutable here:** `status`, `deletedAt`, `role`, `phone`, `userId` (lifecycle/admin
   concerns, not self-service). Zod rejects unknown/forbidden fields.
5. **Audit updates only:** PATCH writes `AuditLog { action: PROFILE_UPDATED, actorType:
   USER, actorId, metadata: { fields: [...names] } }` — **field names, never values** (no
   PII). GET is not audited (reads aren't state changes).
6. **New `profiles/` module** following the documented pattern; registered in `buildApp()`.
7. **Empty PATCH → 400** (at least one field required). **MERCHANT/ADMIN → 403** (no
   self-editable profile in this slice).

## Existing pieces this builds on

- `requireAuth` (preHandler) sets `request.user = { id, role }` (the **User** id). `auth.ts`.
- Prisma `Customer { name, status, deletedAt }`, `Technician { name, skills: ServiceSkill[], status, deletedAt }`, both 1:1 to `User` via `userId @unique`.
- `ServiceSkill` enum: `AC, FAN, ELECTRICAL, WIRING, APPLIANCE`.
- `AuditLog { action, actorType, actorId?, subjectId?, metadata? }` (append-only).
- Route/service/Zod/DTO conventions + the global error handler (typed errors → safe responses).

## Module structure

```
apps/backend/src/modules/profiles/
├── profiles.routes.ts      # GET /me/profile, PATCH /me/profile (both requireAuth)
├── profiles.service.ts     # getMyProfile(user), updateMyProfile(user, patch)
├── profiles.schemas.ts     # Zod: customerPatch, technicianPatch (role-selected)
├── profiles.types.ts       # CustomerProfileDto, TechnicianProfileDto, toProfileDto
└── __tests__/profiles.test.ts
```
Registered in `apps/backend/src/app.ts` via `registerProfileRoutes(app)`, like auth.

## Endpoints

| Method | Path | Auth | Body → Result |
|---|---|---|---|
| GET | `/me/profile` | requireAuth | → `{ id, role, name, skills?, status }` (role-shaped DTO) |
| PATCH | `/me/profile` | requireAuth | `{ name? }` (customer) / `{ name?, skills? }` (technician) → updated DTO |

## Flows

**GET `/me/profile`:** requireAuth → role. Service loads the role's profile by `userId`
filtering `deletedAt: null`. CUSTOMER → `{ id, role:'CUSTOMER', name, status }`;
TECHNICIAN → `{ id, role:'TECHNICIAN', name, skills, status }`. MERCHANT/ADMIN → 403.
Missing row (shouldn't happen — the role↔profile invariant guarantees one) → 404 (defensive).
Returns a DTO, never the raw Prisma object.

**PATCH `/me/profile`:** requireAuth → role → Zod-validate the role-appropriate body
(Customer `{ name? }`; Technician `{ name?, skills? }`, `skills` an array of `ServiceSkill`,
deduped, unknown rejected; **at least one field required** else 400). Update only the
provided fields on the caller's row in a transaction; write the `PROFILE_UPDATED` audit row
(field names only). Return the updated DTO. MERCHANT/ADMIN → 403.

## Schema change

Add one value `PROFILE_UPDATED` to the `AuditAction` enum (non-destructive
`ALTER TYPE ... ADD VALUE` migration to `fixcare_dev`). No other schema change.

## Error contract (existing global handler)

400 (validation / empty body), 401 (no/invalid token — from `requireAuth`), 403
(merchant/admin), 404 (profile missing — defensive). Generic, no internal-detail leak.

## Testing (TDD, `app.inject()`, against `fixcare_test` + test Redis)

GET as customer / technician returns the correct role-shaped DTO; PATCH customer `name`;
PATCH technician `name` + `skills` (full-replace verified: new array replaces old); partial
PATCH (one field); empty body → 400; unknown/forbidden field (e.g. `status`) → 400; no token
→ 401; MERCHANT/ADMIN token → 403; `PROFILE_UPDATED` audit row written with the changed field
names (and NO values); soft-deleted profile excluded. To create an authed caller, drive the
real flow: OTP send+verify (from the auth module) to obtain an access token, then call `/me/profile`.

## Conventions honored

Auth-first (requireAuth); a user only ever touches their own data (Golden Rule — implicit
ownership); route validates with Zod → service → DTO out (never raw Prisma); soft-delete
filter; no PII in audit or logs; typed errors via the global handler.

## Out of scope (deferred)

Addresses; avatar/photo; phone change (an OTP-reverify flow); technician KYC / bank / deposit
/ trust (their own slices); admin & merchant profile management; status self-service.

## Next step

writing-plans → break into TDD tasks (the `PROFILE_UPDATED` enum migration + the
`profiles/` module + tests). Branch `feature/profile-update` off `main` once the auth
sub-slice C PR is merged.
