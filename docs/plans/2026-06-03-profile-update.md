# Profile-update Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an authenticated customer/technician read and update their own profile (`GET` / `PATCH /me/profile`) — the first `requireAuth`-protected feature.

**Architecture:** A new `profiles/` module. Both routes are gated by the existing `requireAuth` (which sets `request.user = {id, role}`). The service role-routes to the `Customer` or `Technician` row (looked up by `userId` — ownership is implicit, no id in the URL), returns a role-shaped DTO, and on update writes a PII-free `PROFILE_UPDATED` audit entry. Skills are full-replace.

**Tech Stack:** Node 22, Fastify 5, Prisma 6, Zod v4, Vitest.

**Scope:** This slice only. On branch `feature/profile-update` (created off `main`, which has the full auth module merged).

---

## Shell prerequisite (EVERY command step)
```bash
export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh" && nvm use 22 >/dev/null   # shell defaults to Node 25
```
Load env (from `apps/backend`): `set -a; . ./.env; set +a`. Work dir: `apps/backend`. ESM/NodeNext → local imports use `.js`. Docker Postgres+Redis running. Commits authored `MohammadKaifSaiyad <saiyedkgn6@gmail.com>`, NO Claude co-author trailer (`.githooks/commit-msg` enforces; never write that literal phrase in a message).

## Existing foundation (on main — do NOT recreate)
- `src/shared/middleware/auth.ts`: `requireAuth` (preHandler → `request.user = {id, role}`), `assertOwnership`.
- `src/shared/database/prisma.ts` (`prisma`); `src/shared/errors.ts` (`ValidationError`→400, `ForbiddenError`→403, `NotFoundError`→404, `UnauthorizedError`→401).
- `src/shared/auth/tokens.ts`: `signAccessToken(userId, role)` — lets tests mint a token directly.
- `src/app.ts` `buildApp()` registers: security → error handler → `await registerAuthRoutes(app)` → `/health` → `return app`. **Add `await registerProfileRoutes(app)` after the auth line.**
- Route convention (from auth): `const parsed = schema.safeParse(request.body); if (!parsed.success) throw new ValidationError(parsed.error.issues[0]?.message ?? 'Invalid input');`
- Prisma `Customer {name, status, deletedAt}`, `Technician {name, skills: ServiceSkill[], status, deletedAt}`, `ServiceSkill (AC|FAN|ELECTRICAL|WIRING|APPLIANCE)`, `AuditLog`, `AuditAction` enum.
- Tests: `tests/schema/helpers.ts` (`prisma`, `resetDb`), `tests/helpers/redis.ts` (`flushTestRedis`).

## File Structure

```
apps/backend/
├── prisma/schema.prisma          # + PROFILE_UPDATED in AuditAction
├── prisma/migrations/<ts>_profile_updated_audit_action/
└── src/
    ├── app.ts                    # + registerProfileRoutes
    └── modules/profiles/
        ├── profiles.types.ts     # Customer/Technician profile DTOs + mappers
        ├── profiles.schemas.ts   # Zod customerPatchBody / technicianPatchBody (strict, ≥1 field)
        ├── profiles.service.ts   # getMyProfile / updateMyProfile (role-routed)
        └── profiles.routes.ts    # registerProfileRoutes: GET + PATCH /me/profile
tests/profiles/
├── helpers.ts                    # registerCustomer / registerTechnician → access token
├── get-profile.test.ts
└── update-profile.test.ts
```

---

### Task 1: Add PROFILE_UPDATED to AuditAction + migration

**Files:** Modify `apps/backend/prisma/schema.prisma`; Create migration

- [ ] **Step 1: Add the enum value**

In `apps/backend/prisma/schema.prisma`, in the `AuditAction` enum, add `PROFILE_UPDATED` (after the existing values):
```prisma
enum AuditAction {
  USER_REGISTERED
  USER_LOGGED_IN
  USER_SUSPENDED
  USER_REACTIVATED
  ADMIN_LEVEL_CHANGED
  REFRESH_TOKEN_REUSE_DETECTED
  PROFILE_UPDATED
}
```

- [ ] **Step 2: Create + apply the migration (dev DB)**

Run (in `apps/backend`, Node 22, env loaded — targets `fixcare_dev`):
```bash
export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh" && nvm use 22 >/dev/null
set -a; . ./.env; set +a
pnpm exec prisma migrate dev --name profile_updated_audit_action
```
Expected: a migration with `ALTER TYPE "AuditAction" ADD VALUE 'PROFILE_UPDATED';`, applied cleanly, client regenerated. **Adding an enum value is non-destructive — NO reset should be prompted.** If a reset IS prompted, STOP and report (do not reset).
Note: Postgres can't add an enum value inside a transaction in some setups; Prisma handles this — if the migration errors about "ALTER TYPE ... ADD VALUE cannot run inside a transaction block", report it (Prisma 6 normally splits this correctly).

- [ ] **Step 3: Verify + commit**

```bash
docker compose exec -T postgres psql -U fixcare -d fixcare_dev -c "SELECT enom.enumlabel FROM pg_enum enom JOIN pg_type t ON enom.enumtypid=t.oid WHERE t.typname='AuditAction' AND enom.enumlabel='PROFILE_UPDATED';"
```
(Expected: one row.) Then:
```bash
cd /Users/mohammadkaifsaiyad/Development/FixCare && git add apps/backend/prisma/ && git commit -m "feat(backend): add PROFILE_UPDATED audit action"
```

---

### Task 2: Profile DTOs + Zod schemas

**Files:** Create `apps/backend/src/modules/profiles/profiles.types.ts`, `apps/backend/src/modules/profiles/profiles.schemas.ts`

- [ ] **Step 1: Create profiles.types.ts**

```ts
import type { Customer, Technician } from '@prisma/client';

export interface CustomerProfileDto {
  id: string;
  role: 'CUSTOMER';
  name: string;
  status: Customer['status'];
}

export interface TechnicianProfileDto {
  id: string;
  role: 'TECHNICIAN';
  name: string;
  skills: Technician['skills'];
  status: Technician['status'];
}

export type ProfileDto = CustomerProfileDto | TechnicianProfileDto;

export function toCustomerProfileDto(c: Customer): CustomerProfileDto {
  return { id: c.id, role: 'CUSTOMER', name: c.name, status: c.status };
}

export function toTechnicianProfileDto(t: Technician): TechnicianProfileDto {
  return { id: t.id, role: 'TECHNICIAN', name: t.name, skills: t.skills, status: t.status };
}
```

- [ ] **Step 2: Create profiles.schemas.ts**

```ts
import { z } from 'zod';

const serviceSkill = z.enum(['AC', 'FAN', 'ELECTRICAL', 'WIRING', 'APPLIANCE']);

// At least one field required; unknown keys rejected (.strict()).
export const customerPatchBody = z
  .object({ name: z.string().min(1, 'name must not be empty') })
  .partial()
  .strict()
  .refine((b) => Object.keys(b).length > 0, { message: 'At least one field is required' });
export type CustomerPatchBody = z.infer<typeof customerPatchBody>;

export const technicianPatchBody = z
  .object({
    name: z.string().min(1, 'name must not be empty'),
    skills: z.array(serviceSkill).nonempty('skills must not be empty'),
  })
  .partial()
  .strict()
  .refine((b) => Object.keys(b).length > 0, { message: 'At least one field is required' });
export type TechnicianPatchBody = z.infer<typeof technicianPatchBody>;
```
Note: `.partial()` makes each field optional; `.strict()` rejects unknown keys (e.g. `status`) with a Zod error → mapped to 400. The `.refine` enforces ≥1 field so an empty `{}` → 400. `skills` full-replace: the array given replaces the stored set; `z.array(...).nonempty()` means if `skills` is present it can't be `[]` (to clear all skills is out of scope — a non-empty set when provided is the V1 rule; document this).

- [ ] **Step 3: Typecheck + commit**

```bash
pnpm exec tsc --noEmit
cd /Users/mohammadkaifsaiyad/Development/FixCare && git add apps/backend/src/modules/profiles/profiles.types.ts apps/backend/src/modules/profiles/profiles.schemas.ts && git commit -m "feat(backend): profile DTOs + patch Zod schemas"
```
Expected: tsc clean.

---

### Task 3: profiles.service.ts — getMyProfile + updateMyProfile (TDD)

**Files:** Create `apps/backend/tests/profiles/helpers.ts`, `apps/backend/src/modules/profiles/profiles.service.ts`, `apps/backend/src/modules/profiles/profiles.routes.ts`; Modify `apps/backend/src/app.ts`; Create `apps/backend/tests/profiles/get-profile.test.ts`

- [ ] **Step 1: Create the test auth helper**

Create `apps/backend/tests/profiles/helpers.ts`:
```ts
import { buildApp } from '../../src/app.js';

type App = Awaited<ReturnType<typeof buildApp>>;

/** Drive the real OTP flow to register a user and return a usable access token. */
export async function registerAndToken(app: App, phone: string, role: 'CUSTOMER' | 'TECHNICIAN') {
  const send = await app.inject({ method: 'POST', url: '/auth/otp/send', payload: { phone, role } });
  const otp = send.json().devOtp as string;
  const verify = await app.inject({ method: 'POST', url: '/auth/otp/verify', payload: { phone, role, otp } });
  const body = verify.json() as { accessToken: string; user: { id: string } };
  return { token: body.accessToken, userId: body.user.id };
}
```

- [ ] **Step 2: Write the failing GET tests**

Create `apps/backend/tests/profiles/get-profile.test.ts`:
```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { registerAndToken } from './helpers.js';
import { signAccessToken } from '../../src/shared/auth/tokens.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });

describe('GET /me/profile', () => {
  it('returns a customer profile (no skills field)', async () => {
    const { token } = await registerAndToken(app, '9800000070', 'CUSTOMER');
    const res = await app.inject({ method: 'GET', url: '/me/profile', headers: { authorization: `Bearer ${token}` } });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.role).toBe('CUSTOMER');
    expect(body).toHaveProperty('name');
    expect(body.skills).toBeUndefined();
  });

  it('returns a technician profile with skills', async () => {
    const { token } = await registerAndToken(app, '9800000071', 'TECHNICIAN');
    const res = await app.inject({ method: 'GET', url: '/me/profile', headers: { authorization: `Bearer ${token}` } });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.role).toBe('TECHNICIAN');
    expect(Array.isArray(body.skills)).toBe(true);
  });

  it('rejects a request with no token (401)', async () => {
    const res = await app.inject({ method: 'GET', url: '/me/profile' });
    expect(res.statusCode).toBe(401);
  });

  it('rejects an ADMIN caller (403 — endpoint is customer/technician only)', async () => {
    const user = await prisma.user.create({ data: { phone: '9800000072', role: 'ADMIN' } });
    const token = signAccessToken(user.id, 'ADMIN');
    const res = await app.inject({ method: 'GET', url: '/me/profile', headers: { authorization: `Bearer ${token}` } });
    expect(res.statusCode).toBe(403);
  });

  it('returns 404 when the profile is soft-deleted', async () => {
    const { token, userId } = await registerAndToken(app, '9800000073', 'CUSTOMER');
    await prisma.customer.update({ where: { userId }, data: { deletedAt: new Date() } });
    const res = await app.inject({ method: 'GET', url: '/me/profile', headers: { authorization: `Bearer ${token}` } });
    expect(res.statusCode).toBe(404);
  });
});
```

- [ ] **Step 3: Run, expect FAIL (route 404)**

```bash
export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh" && nvm use 22 >/dev/null
set -a; . ./.env; set +a
pnpm test tests/profiles/get-profile.test.ts
```
Expected: FAIL — `/me/profile` returns 404 for all (route not registered). (The "no token → 401" test would 404 too at this point.)

- [ ] **Step 4: Create profiles.service.ts (getMyProfile)**

```ts
import { prisma } from '../../shared/database/prisma.js';
import type { UserRole } from '@prisma/client';
import { ForbiddenError, NotFoundError } from '../../shared/errors.js';
import {
  toCustomerProfileDto, toTechnicianProfileDto, type ProfileDto,
} from './profiles.types.js';

export interface AuthedUser { id: string; role: UserRole; }

export async function getMyProfile(user: AuthedUser): Promise<ProfileDto> {
  if (user.role === 'CUSTOMER') {
    const c = await prisma.customer.findFirst({ where: { userId: user.id, deletedAt: null } });
    if (!c) throw new NotFoundError('Profile not found');
    return toCustomerProfileDto(c);
  }
  if (user.role === 'TECHNICIAN') {
    const t = await prisma.technician.findFirst({ where: { userId: user.id, deletedAt: null } });
    if (!t) throw new NotFoundError('Profile not found');
    return toTechnicianProfileDto(t);
  }
  throw new ForbiddenError('No self-service profile for this role');
}
```

- [ ] **Step 5: Create profiles.routes.ts (GET only for now)**

```ts
import type { FastifyInstance } from 'fastify';
import { requireAuth } from '../../shared/middleware/auth.js';
import { getMyProfile } from './profiles.service.js';

export async function registerProfileRoutes(app: FastifyInstance) {
  app.get('/me/profile', { preHandler: [requireAuth] }, async (request, reply) => {
    const result = await getMyProfile(request.user!);
    return reply.code(200).send(result);
  });
}
```

- [ ] **Step 6: Register in app.ts**

In `apps/backend/src/app.ts`, add the import near the other route import:
```ts
import { registerProfileRoutes } from './modules/profiles/profiles.routes.js';
```
and add this line right AFTER `await registerAuthRoutes(app);`:
```ts
  await registerProfileRoutes(app);
```

- [ ] **Step 7: Run, expect PASS**

```bash
set -a; . ./.env; set +a
pnpm test tests/profiles/get-profile.test.ts
```
Expected: 5 passed.

- [ ] **Step 8: Typecheck + commit**

```bash
pnpm exec tsc --noEmit
cd /Users/mohammadkaifsaiyad/Development/FixCare && git add apps/backend/src/modules/profiles/ apps/backend/src/app.ts apps/backend/tests/profiles/ && git commit -m "feat(backend): GET /me/profile (role-routed, requireAuth-gated)"
```

---

### Task 4: updateMyProfile + PATCH route (TDD)

**Files:** Modify `apps/backend/src/modules/profiles/profiles.service.ts`, `apps/backend/src/modules/profiles/profiles.routes.ts`; Create `apps/backend/tests/profiles/update-profile.test.ts`

- [ ] **Step 1: Write the failing PATCH tests**

Create `apps/backend/tests/profiles/update-profile.test.ts`:
```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { registerAndToken } from './helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });

function auth(token: string) { return { authorization: `Bearer ${token}` }; }

describe('PATCH /me/profile', () => {
  it('updates a customer name', async () => {
    const { token, userId } = await registerAndToken(app, '9800000080', 'CUSTOMER');
    const res = await app.inject({ method: 'PATCH', url: '/me/profile', headers: auth(token), payload: { name: 'Asha' } });
    expect(res.statusCode).toBe(200);
    expect(res.json().name).toBe('Asha');
    const row = await prisma.customer.findUnique({ where: { userId } });
    expect(row!.name).toBe('Asha');
  });

  it('updates a technician name + full-replaces skills', async () => {
    const { token, userId } = await registerAndToken(app, '9800000081', 'TECHNICIAN');
    await prisma.technician.update({ where: { userId }, data: { skills: ['AC', 'FAN'] } });
    const res = await app.inject({ method: 'PATCH', url: '/me/profile', headers: auth(token), payload: { name: 'Ramesh', skills: ['ELECTRICAL'] } });
    expect(res.statusCode).toBe(200);
    expect(res.json().name).toBe('Ramesh');
    expect(res.json().skills).toEqual(['ELECTRICAL']); // full replace, not merge
  });

  it('partial PATCH (skills only) leaves name unchanged', async () => {
    const { token, userId } = await registerAndToken(app, '9800000082', 'TECHNICIAN');
    await prisma.technician.update({ where: { userId }, data: { name: 'Keep', skills: ['AC'] } });
    const res = await app.inject({ method: 'PATCH', url: '/me/profile', headers: auth(token), payload: { skills: ['WIRING'] } });
    expect(res.statusCode).toBe(200);
    expect(res.json().name).toBe('Keep');
    expect(res.json().skills).toEqual(['WIRING']);
  });

  it('empty body → 400', async () => {
    const { token } = await registerAndToken(app, '9800000083', 'CUSTOMER');
    const res = await app.inject({ method: 'PATCH', url: '/me/profile', headers: auth(token), payload: {} });
    expect(res.statusCode).toBe(400);
  });

  it('unknown/forbidden field (status) → 400', async () => {
    const { token } = await registerAndToken(app, '9800000084', 'CUSTOMER');
    const res = await app.inject({ method: 'PATCH', url: '/me/profile', headers: auth(token), payload: { status: 'SUSPENDED' } });
    expect(res.statusCode).toBe(400);
  });

  it('writes a PROFILE_UPDATED audit with field NAMES (not values)', async () => {
    const { token, userId } = await registerAndToken(app, '9800000085', 'CUSTOMER');
    await app.inject({ method: 'PATCH', url: '/me/profile', headers: auth(token), payload: { name: 'Secret Name' } });
    const audit = await prisma.auditLog.findFirst({ where: { action: 'PROFILE_UPDATED', actorId: userId } });
    expect(audit).toBeTruthy();
    expect(audit!.actorType).toBe('USER');
    const meta = audit!.metadata as { fields: string[] };
    expect(meta.fields).toContain('name');
    expect(JSON.stringify(meta)).not.toContain('Secret Name'); // names only, no values
  });
});
```

- [ ] **Step 2: Run, expect FAIL (PATCH route 404)**

```bash
set -a; . ./.env; set +a
pnpm test tests/profiles/update-profile.test.ts
```
Expected: FAIL — PATCH route not registered.

- [ ] **Step 3: Add updateMyProfile to profiles.service.ts**

Append to `apps/backend/src/modules/profiles/profiles.service.ts` (add imports for the patch types + ForbiddenError already imported):
```ts
import type { CustomerPatchBody, TechnicianPatchBody } from './profiles.schemas.js';

export async function updateMyProfile(
  user: AuthedUser,
  patch: CustomerPatchBody | TechnicianPatchBody,
): Promise<ProfileDto> {
  const fields = Object.keys(patch); // field NAMES only — never the values (no PII in audit)

  if (user.role === 'CUSTOMER') {
    return prisma.$transaction(async (tx) => {
      const existing = await tx.customer.findFirst({ where: { userId: user.id, deletedAt: null } });
      if (!existing) throw new NotFoundError('Profile not found');
      const updated = await tx.customer.update({ where: { id: existing.id }, data: patch as CustomerPatchBody });
      await tx.auditLog.create({ data: { action: 'PROFILE_UPDATED', actorType: 'USER', actorId: user.id, metadata: { fields } } });
      return toCustomerProfileDto(updated);
    });
  }
  if (user.role === 'TECHNICIAN') {
    return prisma.$transaction(async (tx) => {
      const existing = await tx.technician.findFirst({ where: { userId: user.id, deletedAt: null } });
      if (!existing) throw new NotFoundError('Profile not found');
      const updated = await tx.technician.update({ where: { id: existing.id }, data: patch as TechnicianPatchBody });
      await tx.auditLog.create({ data: { action: 'PROFILE_UPDATED', actorType: 'USER', actorId: user.id, metadata: { fields } } });
      return toTechnicianProfileDto(updated);
    });
  }
  throw new ForbiddenError('No self-service profile for this role');
}
```

- [ ] **Step 4: Add the PATCH route (role-selected schema)**

In `apps/backend/src/modules/profiles/profiles.routes.ts` — update imports + add the route:
```ts
import { ValidationError } from '../../shared/errors.js';
import { customerPatchBody, technicianPatchBody } from './profiles.schemas.js';
import { getMyProfile, updateMyProfile } from './profiles.service.js';
```
```ts
  app.patch('/me/profile', { preHandler: [requireAuth] }, async (request, reply) => {
    const user = request.user!;
    const schema = user.role === 'TECHNICIAN' ? technicianPatchBody : customerPatchBody;
    const parsed = schema.safeParse(request.body);
    if (!parsed.success) throw new ValidationError(parsed.error.issues[0]?.message ?? 'Invalid input');
    const result = await updateMyProfile(user, parsed.data);
    return reply.code(200).send(result);
  });
```
Note: for a MERCHANT/ADMIN caller, the customer schema is selected and parse may pass, but `updateMyProfile` throws `ForbiddenError` (403) on the role check — so non-C/T never mutate anything. (A dedicated 403 test for PATCH is optional; GET already covers the role gate, and the service guard is shared.)

- [ ] **Step 5: Run, expect PASS**

```bash
set -a; . ./.env; set +a
pnpm test tests/profiles/update-profile.test.ts
```
Expected: 6 passed.

- [ ] **Step 6: Typecheck + commit**

```bash
pnpm exec tsc --noEmit
cd /Users/mohammadkaifsaiyad/Development/FixCare && git add apps/backend/src/modules/profiles/ apps/backend/tests/profiles/update-profile.test.ts && git commit -m "feat(backend): PATCH /me/profile (partial update, skills full-replace, audited)"
```

---

### Task 5: Full suite + smoke + docs

**Files:** Modify `STATUS.md`, `CHANGELOG.md`

- [ ] **Step 1: Full suite**

```bash
cd /Users/mohammadkaifsaiyad/Development/FixCare/apps/backend
export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh" && nvm use 22 >/dev/null
set -a; . ./.env; set +a
pnpm test
```
Expected: all pass — 45 (prior) + 5 get-profile + 6 update-profile = 56.

- [ ] **Step 2: Smoke (real server: register → GET → PATCH)**

```bash
set -a; . ./.env; set +a
pnpm exec tsx src/server.ts > /tmp/fc-prof.log 2>&1 &
SRV=$!; sleep 4
OTP=$(curl -s -XPOST localhost:3000/auth/otp/send -H 'content-type: application/json' -d '{"phone":"9800000090","role":"TECHNICIAN"}' | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>console.log(JSON.parse(d).devOtp))")
TOK=$(curl -s -XPOST localhost:3000/auth/otp/verify -H 'content-type: application/json' -d "{\"phone\":\"9800000090\",\"role\":\"TECHNICIAN\",\"otp\":\"$OTP\"}" | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>console.log(JSON.parse(d).accessToken))")
echo "GET:" && curl -s localhost:3000/me/profile -H "authorization: Bearer $TOK"; echo
echo "PATCH:" && curl -s -XPATCH localhost:3000/me/profile -H "authorization: Bearer $TOK" -H 'content-type: application/json' -d '{"name":"Ramesh","skills":["AC","ELECTRICAL"]}'; echo
kill $SRV 2>/dev/null
# cleanup the smoke user
cd /Users/mohammadkaifsaiyad/Development/FixCare && docker compose exec -T postgres psql -U fixcare -d fixcare_dev -c "DELETE FROM \"AuditLog\" WHERE \"actorId\" IN (SELECT id FROM \"User\" WHERE phone='9800000090'); DELETE FROM \"RefreshToken\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE phone='9800000090'); DELETE FROM \"Technician\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE phone='9800000090'); DELETE FROM \"User\" WHERE phone='9800000090';"
```
Expected: GET returns a technician profile; PATCH returns `name: "Ramesh"`, `skills: ["AC","ELECTRICAL"]`.

- [ ] **Step 3: Update STATUS.md** — Active task → "next backend module (bookings/catalog)"; add to Last shipped:
```
- Profile-update slice: GET/PATCH /me/profile (first requireAuth-protected feature;
  role-routed, implicit ownership, skills full-replace, PROFILE_UPDATED audit). 56 tests.
```

- [ ] **Step 4: Update CHANGELOG.md** (under the current date):
```
- **Profile-update slice (first protected feature).** GET /me/profile + PATCH /me/profile,
  both requireAuth-gated. Role-routed (customer: name; technician: name + skills full-replace),
  implicit ownership (own row by userId), empty body → 400, unknown field → 400, MERCHANT/ADMIN
  → 403, soft-deleted → 404. PROFILE_UPDATED audit (field names, no values). New profiles/ module.
  56 tests.
```

- [ ] **Step 5: Commit**

```bash
cd /Users/mohammadkaifsaiyad/Development/FixCare && git add STATUS.md CHANGELOG.md && git commit -m "docs: record profile-update slice"
```

---

## Definition of Done

- `pnpm test` green: 56 (45 prior + 5 get + 6 update).
- Smoke: register → GET returns the profile → PATCH updates name+skills (full-replace).
- GET/PATCH gated by `requireAuth` (no token → 401); MERCHANT/ADMIN → 403; soft-deleted → 404; empty/unknown-field PATCH → 400.
- `PROFILE_UPDATED` audit row carries `metadata.fields` (NAMES) and no values.
- `tsc --noEmit` clean. All commits authored by you, no Claude trailer.

## Out of scope (deferred)
Addresses, avatar/photo, phone change (OTP-reverify), technician KYC/bank/deposit/trust, admin & merchant profile management, status self-service, clearing skills to empty (V1 requires a non-empty set when `skills` is provided).

## Verification
- `pnpm test` → 56 passed.
- Smoke GET/PATCH as above.
- `git log --oneline main..HEAD` → the profile-update commits, all authored by MohammadKaifSaiyad.
