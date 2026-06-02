# Auth Module — Sub-slice C (Admin email/password login) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Admin email/password login (`POST /admin/auth/login`, argon2id), reusing the existing token machinery, plus a seed script that creates the first SUPER_ADMIN. This is the **last auth sub-slice** — after it, the auth module is complete.

**Architecture:** Admins authenticate by email + password (not phone-OTP). `adminLogin` verifies an argon2id hash, checks both the Admin profile and parent User are active, then issues the same access JWT + hashed RefreshToken used everywhere (admins reuse `requireAuth` from sub-slice B; their JWT carries `role: ADMIN`). The first admin is bootstrapped by an idempotent seed script from env.

**Tech Stack:** Node 22, Fastify 5, Prisma 6, argon2 (argon2id), jsonwebtoken, Zod v4, Vitest.

**Scope:** Sub-slice C only — admin login + seed. No `rbac.ts` permission mapping (deferred), no admin account-creation endpoints (seed only). On branch `feature/auth-admin-login`. **No DB migration** (the `Admin` model already exists); the only DB-touching step is running the seed against `fixcare_dev` (a non-destructive insert).

---

## Shell prerequisite (EVERY command step)
```bash
export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh" && nvm use 22 >/dev/null   # shell defaults to Node 25
```
Load env (from `apps/backend`): `set -a; . ./.env; set +a`. Work dir: `apps/backend`. ESM/NodeNext → local imports use `.js`. Docker Postgres+Redis running. Commits authored `MohammadKaifSaiyad <saiyedkgn6@gmail.com>`, NO Claude co-author trailer (`.githooks/commit-msg` enforces; never write that literal phrase in a message).

## Existing foundation (sub-slices 0+A+B on main — do NOT recreate)
- `src/shared/auth/tokens.ts`: `signAccessToken(userId, role)`, `hashRefreshToken`, `issueRefreshToken(tx, userId, meta?)` → `{raw, id}`.
- `src/shared/middleware/auth.ts`: `requireAuth`, `assertOwnership`; `request.user` typed `{id, role}`.
- `src/shared/config.ts`: `config` (Zod v4 schema). `src/shared/errors.ts`: `UnauthorizedError`, `ForbiddenError`, `ValidationError`.
- `src/modules/auth/auth.service.ts` imports already include: `prisma`, `Prisma`/`UserRole` types, `signAccessToken`/`issueRefreshToken`/`hashRefreshToken`, `UnauthorizedError`/`ForbiddenError`, `toUserDto`+`AuthTokens`, the schema body types.
- `src/modules/auth/auth.types.ts`: `UserDto`, `AuthTokens`, `toUserDto`. `auth.schemas.ts` uses `import { z } from 'zod'`.
- `src/modules/auth/auth.routes.ts`: `registerAuthRoutes(app)` with send/verify/refresh/logout/logout-all.
- Prisma `Admin`: `id`, `userId @unique`, `name`, `email @unique`, `passwordHash`, `adminLevel` (SUPER_ADMIN|MANAGER|SUPPORT, default SUPPORT), `status` (ACTIVE|SUSPENDED), `deletedAt`. `User`: `role` (incl ADMIN), `status`, `deletedAt`.
- `prisma.config.ts` uses the new Prisma config (no `package.json#prisma.seed`) — so we run the seed via a plain `tsx prisma/seed.ts` script, NOT `prisma db seed`.
- Tests: `tests/schema/helpers.ts` (`prisma`, `resetDb`), `tests/helpers/redis.ts` (`flushTestRedis`).

## File Structure

```
apps/backend/
├── package.json                  # + argon2 dep, + db:seed script
├── .env / .env.example           # + SEED_ADMIN_EMAIL, SEED_ADMIN_PASSWORD
├── src/
│   ├── shared/
│   │   ├── config.ts             # + SEED_ADMIN_* (optional)
│   │   └── auth/argon2.ts        # NEW: hashPassword / verifyPassword (argon2id)
│   └── modules/auth/
│       ├── auth.types.ts         # + AdminDto + toAdminDto
│       ├── auth.schemas.ts       # + adminLoginBody
│       ├── auth.service.ts       # + adminLogin()
│       └── auth.routes.ts        # + POST /admin/auth/login
├── prisma/seed.ts                # NEW: idempotent first-SUPER_ADMIN seed
└── tests/auth/
    ├── argon2.test.ts            # NEW
    ├── admin-login.test.ts       # NEW
    └── seed.test.ts              # NEW
```

---

### Task 1: Install argon2 + password helpers (TDD)

**Files:** Modify `apps/backend/package.json`; Create `apps/backend/src/shared/auth/argon2.ts`, `apps/backend/tests/auth/argon2.test.ts`

- [ ] **Step 1: Install argon2**

Run (in `apps/backend`, Node 22):
```bash
pnpm add argon2
```
Expected: argon2 added to dependencies. (Native module — pnpm runs its prebuilt-binary install; if it needs a build it happens here. If install fails to find a prebuilt binary for this platform, report it.)

- [ ] **Step 2: Write the failing test**

Create `apps/backend/tests/auth/argon2.test.ts`:
```ts
import { describe, expect, it } from 'vitest';
import { hashPassword, verifyPassword } from '../../src/shared/auth/argon2.js';

describe('argon2 password helpers', () => {
  it('hashes then verifies the correct password', async () => {
    const hash = await hashPassword('s3cret-password');
    expect(hash).not.toBe('s3cret-password'); // not plaintext
    expect(hash.startsWith('$argon2id$')).toBe(true);
    expect(await verifyPassword(hash, 's3cret-password')).toBe(true);
  });

  it('rejects a wrong password', async () => {
    const hash = await hashPassword('s3cret-password');
    expect(await verifyPassword(hash, 'wrong')).toBe(false);
  });
});
```

- [ ] **Step 3: Run, expect FAIL**

```bash
export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh" && nvm use 22 >/dev/null
set -a; . ./.env; set +a
pnpm test tests/auth/argon2.test.ts
```
Expected: FAIL — `hashPassword` not found.

- [ ] **Step 4: Implement argon2.ts**

Create `apps/backend/src/shared/auth/argon2.ts`:
```ts
import argon2 from 'argon2';

/** Hash a plaintext password with argon2id. */
export function hashPassword(plain: string): Promise<string> {
  return argon2.hash(plain, { type: argon2.argon2id });
}

/** Verify a plaintext password against an argon2id hash. Returns false on mismatch (never throws for a bad password). */
export async function verifyPassword(hash: string, plain: string): Promise<boolean> {
  try {
    return await argon2.verify(hash, plain);
  } catch {
    return false; // malformed hash etc. → treat as a failed verification
  }
}
```

- [ ] **Step 5: Run, expect PASS**

```bash
set -a; . ./.env; set +a
pnpm test tests/auth/argon2.test.ts
```
Expected: 2 passed.

- [ ] **Step 6: Commit**

```bash
cd /Users/mohammadkaifsaiyad/Development/FixCare && git add apps/backend/package.json pnpm-lock.yaml apps/backend/src/shared/auth/argon2.ts apps/backend/tests/auth/argon2.test.ts && git commit -m "feat(backend): argon2id password hash/verify helpers"
```

---

### Task 2: AdminDto + adminLoginBody schema + SEED_ADMIN config

**Files:** Modify `apps/backend/src/modules/auth/auth.types.ts`, `apps/backend/src/modules/auth/auth.schemas.ts`, `apps/backend/src/shared/config.ts`

- [ ] **Step 1: Add AdminDto + toAdminDto to auth.types.ts**

Append to `apps/backend/src/modules/auth/auth.types.ts`:
```ts
import type { Admin } from '@prisma/client';

export interface AdminDto {
  id: string;
  email: string;
  name: string;
  adminLevel: Admin['adminLevel'];
  status: Admin['status'];
}

/** Admin DTO — NEVER includes passwordHash. */
export function toAdminDto(admin: Admin): AdminDto {
  return { id: admin.id, email: admin.email, name: admin.name, adminLevel: admin.adminLevel, status: admin.status };
}

export interface AdminAuthTokens {
  accessToken: string;
  refreshToken: string;
  admin: AdminDto;
}
```
(Merge the `import type { Admin }` with the existing `import type { User } from '@prisma/client';` line if you prefer: `import type { User, Admin } from '@prisma/client';`.)

- [ ] **Step 2: Add adminLoginBody to auth.schemas.ts**

Append to `apps/backend/src/modules/auth/auth.schemas.ts`:
```ts
export const adminLoginBody = z.object({
  email: z.email('Invalid email'),         // Zod v4: z.email() (not z.string().email())
  password: z.string().min(1, 'Password required'),
});
export type AdminLoginBody = z.infer<typeof adminLoginBody>;
```
Note: Zod v4 — use `z.email()`. If `z.email` is somehow unavailable, fall back to `z.string().email()` and report it.

- [ ] **Step 3: Add SEED_ADMIN_* (optional) to config.ts**

In `apps/backend/src/shared/config.ts`, add these two fields to the `ConfigSchema` object (optional — the app must boot without them; the seed asserts they exist):
```ts
  SEED_ADMIN_EMAIL: z.email().optional(),
  SEED_ADMIN_PASSWORD: z.string().min(8).optional(),
```

- [ ] **Step 4: Typecheck + commit**

```bash
export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh" && nvm use 22 >/dev/null
pnpm exec tsc --noEmit
cd /Users/mohammadkaifsaiyad/Development/FixCare && git add apps/backend/src/modules/auth/auth.types.ts apps/backend/src/modules/auth/auth.schemas.ts apps/backend/src/shared/config.ts && git commit -m "feat(backend): AdminDto + adminLoginBody schema + optional SEED_ADMIN config"
```
Expected: tsc clean.

---

### Task 3: adminLogin service + /admin/auth/login route (TDD)

**Files:** Modify `apps/backend/src/modules/auth/auth.service.ts`, `apps/backend/src/modules/auth/auth.routes.ts`; Create `apps/backend/tests/auth/admin-login.test.ts`

- [ ] **Step 1: Write the failing test**

Create `apps/backend/tests/auth/admin-login.test.ts`:
```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { hashPassword } from '../../src/shared/auth/argon2.js';
import { requireAuth } from '../../src/shared/middleware/auth.js';

const app = await buildApp();
app.get('/__me', { preHandler: [requireAuth] }, async (req) => ({ id: req.user!.id, role: req.user!.role }));
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });

async function makeAdmin(email: string, password: string, opts: { status?: 'ACTIVE' | 'SUSPENDED'; deleted?: boolean } = {}) {
  const user = await prisma.user.create({ data: { phone: '9' + Math.floor(1e9 + Math.random() * 8e9), role: 'ADMIN' } });
  await prisma.admin.create({
    data: {
      userId: user.id, name: 'Boss', email, passwordHash: await hashPassword(password),
      adminLevel: 'SUPER_ADMIN', status: opts.status ?? 'ACTIVE',
      ...(opts.deleted ? { deletedAt: new Date() } : {}),
    },
  });
  return user;
}

describe('POST /admin/auth/login', () => {
  it('valid credentials → 200 + tokens + admin DTO (no passwordHash) + ADMIN role', async () => {
    await makeAdmin('boss@fixcare.in', 'super-secret-pw');
    const res = await app.inject({ method: 'POST', url: '/admin/auth/login', payload: { email: 'boss@fixcare.in', password: 'super-secret-pw' } });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.accessToken).toBeTruthy();
    expect(body.refreshToken).toBeTruthy();
    expect(body.admin.email).toBe('boss@fixcare.in');
    expect(body.admin.adminLevel).toBe('SUPER_ADMIN');
    expect(body.admin.passwordHash).toBeUndefined(); // NEVER leaked

    // the issued access token works with requireAuth and carries ADMIN role
    const me = await app.inject({ method: 'GET', url: '/__me', headers: { authorization: `Bearer ${body.accessToken}` } });
    expect(me.statusCode).toBe(200);
    expect(me.json().role).toBe('ADMIN');
  });

  it('wrong password → 401, and unknown email → identical 401 (no enumeration)', async () => {
    await makeAdmin('boss2@fixcare.in', 'super-secret-pw');
    const wrong = await app.inject({ method: 'POST', url: '/admin/auth/login', payload: { email: 'boss2@fixcare.in', password: 'nope' } });
    const unknown = await app.inject({ method: 'POST', url: '/admin/auth/login', payload: { email: 'ghost@fixcare.in', password: 'whatever' } });
    expect(wrong.statusCode).toBe(401);
    expect(unknown.statusCode).toBe(401);
    expect(wrong.json()).toEqual(unknown.json()); // same body — no account enumeration
  });

  it('suspended admin → 403', async () => {
    await makeAdmin('susp@fixcare.in', 'super-secret-pw', { status: 'SUSPENDED' });
    const res = await app.inject({ method: 'POST', url: '/admin/auth/login', payload: { email: 'susp@fixcare.in', password: 'super-secret-pw' } });
    expect(res.statusCode).toBe(403);
  });

  it('soft-deleted admin → 403', async () => {
    await makeAdmin('del@fixcare.in', 'super-secret-pw', { deleted: true });
    const res = await app.inject({ method: 'POST', url: '/admin/auth/login', payload: { email: 'del@fixcare.in', password: 'super-secret-pw' } });
    expect(res.statusCode).toBe(403);
  });
});
```

- [ ] **Step 2: Run, expect FAIL**

```bash
set -a; . ./.env; set +a
pnpm test tests/auth/admin-login.test.ts
```
Expected: FAIL — route 404.

- [ ] **Step 3: Add adminLogin to auth.service.ts**

Add imports (merge into existing import lines — `prisma`, `signAccessToken`/`issueRefreshToken`, `UnauthorizedError`/`ForbiddenError` already imported; ADD `verifyPassword` + the admin DTO/types):
```ts
import { verifyPassword } from '../../shared/auth/argon2.js';
import { toAdminDto, type AdminAuthTokens } from './auth.types.js';
import type { AdminLoginBody } from './auth.schemas.js';
```
(Update the existing `./auth.types.js` import to also pull `toAdminDto`/`AdminAuthTokens`, and the existing `./auth.schemas.js` type import to also pull `AdminLoginBody`.)
Append the function:
```ts
export async function adminLogin({ email, password }: AdminLoginBody): Promise<AdminAuthTokens> {
  const admin = await prisma.admin.findUnique({ where: { email }, include: { user: true } });

  // Generic failure for BOTH unknown email and wrong password (no account enumeration).
  // Still run a verify against a found hash so timing is similar; if no admin, fail generically.
  const ok = admin ? await verifyPassword(admin.passwordHash, password) : false;
  if (!admin || !ok) throw new UnauthorizedError('Invalid email or password');

  if (admin.status !== 'ACTIVE' || admin.deletedAt || admin.user.status !== 'ACTIVE' || admin.user.deletedAt) {
    throw new ForbiddenError('Account is not active');
  }

  const result = await prisma.$transaction(async (tx) => {
    await tx.auditLog.create({ data: { action: 'USER_LOGGED_IN', actorType: 'ADMIN', actorId: admin.user.id } });
    const accessToken = signAccessToken(admin.user.id, admin.user.role);
    const { raw: refreshToken } = await issueRefreshToken(tx, admin.user.id);
    return { accessToken, refreshToken, admin: toAdminDto(admin) };
  });
  return result;
}
```
Note: the suspended/deleted check is AFTER the password check on purpose — a suspended admin with a wrong password should still get the generic 401 (don't reveal the account exists). Only a correct password reveals the 403.

- [ ] **Step 4: Add the route to auth.routes.ts**

Update imports + add the route in `registerAuthRoutes`:
```ts
import { sendOtpBody, verifyOtpBody, refreshBody, logoutBody, adminLoginBody } from './auth.schemas.js';
import { sendOtp, verifyOtp, refreshTokens, logout, logoutAll, adminLogin } from './auth.service.js';
```
```ts
  app.post('/admin/auth/login', async (request, reply) => {
    const parsed = adminLoginBody.safeParse(request.body);
    if (!parsed.success) throw new ValidationError(parsed.error.issues[0]?.message ?? 'Invalid input');
    const result = await adminLogin(parsed.data);
    return reply.code(200).send(result);
  });
```

- [ ] **Step 5: Run, expect PASS**

```bash
set -a; . ./.env; set +a
pnpm test tests/auth/admin-login.test.ts
```
Expected: 4 passed.

- [ ] **Step 6: Typecheck + commit**

```bash
pnpm exec tsc --noEmit
cd /Users/mohammadkaifsaiyad/Development/FixCare && git add apps/backend/src/modules/auth/ apps/backend/tests/auth/admin-login.test.ts && git commit -m "feat(backend): admin email/password login (/admin/auth/login, argon2id)"
```

---

### Task 4: Seed script for the first SUPER_ADMIN (TDD)

**Files:** Modify `apps/backend/package.json`, `apps/backend/.env`, `apps/backend/.env.example`; Create `apps/backend/prisma/seed.ts`, `apps/backend/tests/auth/seed.test.ts`

- [ ] **Step 1: Add SEED_ADMIN_* to .env and .env.example**

Append to `apps/backend/.env`:
```
SEED_ADMIN_EMAIL="admin@fixcare.in"
SEED_ADMIN_PASSWORD="change-me-admin-pw-min8"
```
Append to `apps/backend/.env.example`:
```
SEED_ADMIN_EMAIL="admin@fixcare.in"
SEED_ADMIN_PASSWORD="CHANGE_ME_min_8_chars"
```

- [ ] **Step 2: Write the failing test**

Create `apps/backend/tests/auth/seed.test.ts`:
```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { prisma, resetDb } from '../schema/helpers.js';
import { seedSuperAdmin } from '../../prisma/seed.js';

afterAll(() => prisma.$disconnect());
beforeEach(resetDb);

describe('seedSuperAdmin', () => {
  it('creates a SUPER_ADMIN user + admin profile', async () => {
    await seedSuperAdmin(prisma, 'admin@fixcare.in', 'super-secret-pw');
    const admin = await prisma.admin.findUnique({ where: { email: 'admin@fixcare.in' }, include: { user: true } });
    expect(admin).toBeTruthy();
    expect(admin!.adminLevel).toBe('SUPER_ADMIN');
    expect(admin!.user.role).toBe('ADMIN');
    expect(admin!.passwordHash.startsWith('$argon2id$')).toBe(true);
  });

  it('is idempotent — running twice does not duplicate or throw', async () => {
    await seedSuperAdmin(prisma, 'admin@fixcare.in', 'super-secret-pw');
    await seedSuperAdmin(prisma, 'admin@fixcare.in', 'super-secret-pw'); // again
    const count = await prisma.admin.count({ where: { email: 'admin@fixcare.in' } });
    expect(count).toBe(1);
  });
});
```

- [ ] **Step 3: Run, expect FAIL**

```bash
set -a; . ./.env; set +a
pnpm test tests/auth/seed.test.ts
```
Expected: FAIL — cannot import `seedSuperAdmin`.

- [ ] **Step 4: Implement prisma/seed.ts**

Create `apps/backend/prisma/seed.ts`:
```ts
import { PrismaClient } from '@prisma/client';
import { hashPassword } from '../src/shared/auth/argon2.js';
import { config } from '../src/shared/config.js';

/** Idempotently create the first SUPER_ADMIN. Exported for tests; run() is the CLI entry. */
export async function seedSuperAdmin(prisma: PrismaClient, email: string, password: string): Promise<void> {
  const existing = await prisma.admin.findUnique({ where: { email } });
  if (existing) {
    console.log(`[seed] admin ${email} already exists — skipping`);
    return;
  }
  const passwordHash = await hashPassword(password);
  await prisma.$transaction(async (tx) => {
    const user = await tx.user.create({ data: { phone: `seed-${Date.now()}`, role: 'ADMIN' } });
    await tx.admin.create({ data: { userId: user.id, name: 'Super Admin', email, passwordHash, adminLevel: 'SUPER_ADMIN' } });
  });
  console.log(`[seed] created SUPER_ADMIN ${email}`);
}

async function run(): Promise<void> {
  if (!config.SEED_ADMIN_EMAIL || !config.SEED_ADMIN_PASSWORD) {
    throw new Error('SEED_ADMIN_EMAIL and SEED_ADMIN_PASSWORD must be set to seed an admin');
  }
  const prisma = new PrismaClient();
  try {
    await seedSuperAdmin(prisma, config.SEED_ADMIN_EMAIL, config.SEED_ADMIN_PASSWORD);
  } finally {
    await prisma.$disconnect();
  }
}

// Run only when executed directly (tsx prisma/seed.ts), not when imported by tests.
// import.meta.url vs argv check keeps the test import side-effect-free.
const invokedDirectly = process.argv[1] && import.meta.url === `file://${process.argv[1]}`;
if (invokedDirectly) {
  run().catch((err) => { console.error(err); process.exit(1); });
}
```
Note on the phone field: `User.phone` is `@unique` and non-null, but an admin logs in by email, not phone. We use a synthetic unique placeholder (`seed-<timestamp>`) so the NOT-NULL/unique constraint is satisfied without colliding with real E.164 phones. (A future admin-management slice can refine this; acceptable for the seed.)

- [ ] **Step 5: Run, expect PASS**

```bash
set -a; . ./.env; set +a
pnpm test tests/auth/seed.test.ts
```
Expected: 2 passed.

- [ ] **Step 6: Add the db:seed script**

In `apps/backend/package.json` `scripts`, add:
```json
    "db:seed": "tsx prisma/seed.ts",
```

- [ ] **Step 7: Typecheck + commit** (do NOT commit `.env`)

```bash
pnpm exec tsc --noEmit
cd /Users/mohammadkaifsaiyad/Development/FixCare && git add apps/backend/prisma/seed.ts apps/backend/tests/auth/seed.test.ts apps/backend/package.json apps/backend/.env.example && git commit -m "feat(backend): idempotent SUPER_ADMIN seed script + db:seed"
```

---

### Task 5: Full suite + seed-against-dev + admin-login smoke + docs

**Files:** Modify `STATUS.md`, `CHANGELOG.md`

- [ ] **Step 1: Full suite**

```bash
cd /Users/mohammadkaifsaiyad/Development/FixCare/apps/backend
export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh" && nvm use 22 >/dev/null
set -a; . ./.env; set +a
pnpm test
```
Expected: all pass — 37 (prior) + 2 argon2 + 4 admin-login + 2 seed = 45.

- [ ] **Step 2: Seed the dev DB + admin-login smoke**

```bash
set -a; . ./.env; set +a
pnpm db:seed   # creates admin@fixcare.in in fixcare_dev (idempotent)
pnpm exec tsx src/server.ts > /tmp/fc-c.log 2>&1 &
SRV=$!; sleep 4
echo "admin login HTTP:" && curl -s -o /dev/null -w "%{http_code}\n" -XPOST localhost:3000/admin/auth/login -H 'content-type: application/json' -d '{"email":"admin@fixcare.in","password":"change-me-admin-pw-min8"}'
echo "wrong pw HTTP:" && curl -s -o /dev/null -w "%{http_code}\n" -XPOST localhost:3000/admin/auth/login -H 'content-type: application/json' -d '{"email":"admin@fixcare.in","password":"wrong"}'
kill $SRV 2>/dev/null
```
Expected: valid login `200`, wrong password `401`. (The seeded admin stays in `fixcare_dev` — that's intended; it's your first real admin. Leave it.)

- [ ] **Step 3: Update STATUS.md** — Active task → "Auth module COMPLETE; next: first protected resource / next backend module"; add to Last shipped:
```
- Auth sub-slice C (admin login): POST /admin/auth/login (argon2id, generic 401 no
  enumeration, suspended/deleted → 403, reuses requireAuth + token machinery) +
  idempotent SUPER_ADMIN seed script. 45 tests green. AUTH MODULE COMPLETE.
```

- [ ] **Step 4: Update CHANGELOG.md** (under the current date):
```
- **Auth sub-slice C (admin email/password login) — auth module complete.**
  `POST /admin/auth/login` (argon2id verify; generic 401 for unknown-email AND
  wrong-password — no enumeration; suspended/deleted → 403; reuses the access JWT +
  hashed RefreshToken + requireAuth from earlier sub-slices; AuditLog USER_LOGGED_IN
  actorType ADMIN; admin DTO never exposes passwordHash). Idempotent `prisma/seed.ts`
  + `db:seed` create the first SUPER_ADMIN from env. 45 tests. The full auth module
  (OTP for customer/technician + admin password + session lifecycle) is now in place.
```

- [ ] **Step 5: Commit**

```bash
cd /Users/mohammadkaifsaiyad/Development/FixCare && git add STATUS.md CHANGELOG.md && git commit -m "docs: record auth sub-slice C (admin login) — auth module complete"
```

---

## Definition of Done

- `pnpm test` green: 45 tests (37 prior + 2 argon2 + 4 admin-login + 2 seed).
- `pnpm db:seed` creates the first SUPER_ADMIN in `fixcare_dev` (idempotent); admin-login smoke → `200`, wrong password → `401`.
- Admin login: argon2id verify; unknown-email and wrong-password return an **identical** generic 401 (no enumeration); suspended/deleted → 403; the issued access token works with `requireAuth` and carries `role: ADMIN`; the admin DTO **never** includes `passwordHash`.
- `tsc --noEmit` clean. All commits authored by you, no Claude trailer.

## Out of scope / deferred
- `rbac.ts` permission mapping (which `adminLevel` can do what) — deferred until admin endpoints exist.
- Admin account-creation endpoints (only the seed creates admins for now).
- A tighter per-IP/email rate-limit + lockout on `/admin/auth/login` — noted; the global 100/min/IP applies for now; do with the broader rate-limit hardening pass.
- The synthetic seed `phone` placeholder — a future admin-management slice can refine the admin↔User shape.

## Verification
- `pnpm test` → 45 passed.
- `pnpm db:seed` then `curl /admin/auth/login` (valid → 200, wrong → 401).
- `git log --oneline main..HEAD` → sub-slice C commits, all authored by MohammadKaifSaiyad.
- **Auth module is complete** after this merges.
