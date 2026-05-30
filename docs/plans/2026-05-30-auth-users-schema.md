# Auth + Users Schema Slice — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scaffold the `apps/backend` project and implement the auth + users vertical slice of the Prisma schema (User, RefreshToken, the four role profiles, AuditLog) with passing invariant tests and a first migration applied to the local Postgres+PostGIS.

**Architecture:** A Fastify 5 + TypeScript (strict) backend using Prisma 6 against PostgreSQL 16/PostGIS (running in Docker). This plan builds only the data layer + its invariant tests — no routes/services yet. Base `User` + 1:1 role-profile tables (Approach A), refresh tokens persisted in Postgres, OTPs deferred to Redis (not in schema). Design spec: `docs/designs/2026-05-30-auth-users-schema-design.md`.

**Tech Stack:** Node 22 LTS, pnpm 9.15.2, Fastify 5, TypeScript 5 (strict), Prisma 6, PostgreSQL 16 + PostGIS, Vitest (test runner), tsx (TS execution).

---

## Shell prerequisite (applies to EVERY command step)

The non-interactive shell defaults to system Node 25. **Every `node`/`pnpm`/`npx` command in this plan must run on Node 22.** Prefix each command with:

```bash
export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh" && nvm use 22 >/dev/null
```

Commands below assume you have run that in the current shell (it persists for the shell's lifetime). Working directory for all backend commands: `apps/backend`.

The Docker data stack (Postgres+PostGIS, Redis) must be running. Verify from repo root:
```bash
docker compose ps   # postgres + redis should be "healthy"
```
If not: `docker compose up -d` from the repo root.

## File Structure

```
apps/backend/
├── package.json              # deps, scripts, "packageManager": "pnpm@9.15.2"
├── tsconfig.json             # strict TS config
├── vitest.config.ts          # test runner config
├── .env                      # DATABASE_URL (gitignored — already covered by root .gitignore)
├── .env.example              # template (committed)
├── prisma/
│   └── schema.prisma         # the auth+users slice models
└── src/
    └── shared/
        └── database/
            └── prisma.ts      # Prisma client singleton
    tests/
    └── schema/
        ├── helpers.ts         # test DB setup/teardown helpers
        ├── user.test.ts       # one-role-per-phone, soft-delete
        ├── profile.test.ts    # role↔profile 1:1 + uniqueness
        ├── refresh-token.test.ts  # rotation, reuse-detection shape, sliding expiry field
        └── audit-log.test.ts  # append-only create, enums
```

Tests live under `apps/backend/tests/` (integration-style, hitting the real local Postgres — Prisma schema behavior can only be meaningfully tested against a real DB). A dedicated test database `fixcare_test` is used so tests never touch dev data.

---

### Task 1: Scaffold the backend project

**Files:**
- Create: `apps/backend/package.json`
- Create: `apps/backend/tsconfig.json`
- Create: `apps/backend/.env`
- Create: `apps/backend/.env.example`

- [ ] **Step 1: Initialize package.json**

Create `apps/backend/package.json`:
```json
{
  "name": "@fixcare/backend",
  "version": "0.0.0",
  "private": true,
  "type": "module",
  "packageManager": "pnpm@9.15.2",
  "scripts": {
    "db:generate": "prisma generate",
    "db:migrate": "prisma migrate dev",
    "db:studio": "prisma studio",
    "test": "vitest run",
    "test:watch": "vitest"
  }
}
```

- [ ] **Step 2: Install dependencies**

Run (in `apps/backend`):
```bash
pnpm add fastify@^5 @prisma/client@^6
pnpm add -D prisma@^6 typescript@^5 tsx vitest @types/node
```
Expected: `node_modules/` created, `pnpm-lock.yaml` written, no errors.

- [ ] **Step 3: Create tsconfig.json (strict)**

Create `apps/backend/tsconfig.json`:
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "resolveJsonModule": true,
    "outDir": "dist",
    "rootDir": "."
  },
  "include": ["src", "tests", "prisma"]
}
```

- [ ] **Step 4: Create .env and .env.example**

Create `apps/backend/.env`:
```
DATABASE_URL="postgresql://fixcare:fixcare_dev@localhost:5432/fixcare_dev?schema=public"
TEST_DATABASE_URL="postgresql://fixcare:fixcare_dev@localhost:5432/fixcare_test?schema=public"
```
Create `apps/backend/.env.example` (same keys, placeholder values):
```
DATABASE_URL="postgresql://USER:PASSWORD@localhost:5432/fixcare_dev?schema=public"
TEST_DATABASE_URL="postgresql://USER:PASSWORD@localhost:5432/fixcare_test?schema=public"
```

- [ ] **Step 5: Create the test database**

Run (from repo root):
```bash
docker compose exec -T postgres psql -U fixcare -d fixcare_dev -c "CREATE DATABASE fixcare_test OWNER fixcare;"
```
Expected: `CREATE DATABASE` (or "already exists" — safe to ignore).

- [ ] **Step 6: Commit**

```bash
git add apps/backend/package.json apps/backend/tsconfig.json apps/backend/.env.example apps/backend/pnpm-lock.yaml
git commit -m "chore(backend): scaffold Fastify + TypeScript + Prisma project"
```
Note: `.env` is gitignored by the root `.gitignore`; do not commit it.

---

### Task 2: Initialize Prisma + Postgres connection

**Files:**
- Create: `apps/backend/prisma/schema.prisma`
- Create: `apps/backend/src/shared/database/prisma.ts`

- [ ] **Step 1: Initialize Prisma**

Run (in `apps/backend`):
```bash
pnpm exec prisma init --datasource-provider postgresql
```
Expected: creates `prisma/schema.prisma` and appends to `.env`. If it duplicates `DATABASE_URL` in `.env`, keep the one from Task 1 Step 4 and delete the duplicate.

- [ ] **Step 2: Set the base schema with PostGIS + sections**

Replace `apps/backend/prisma/schema.prisma` with:
```prisma
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider   = "postgresql"
  url        = env("DATABASE_URL")
  extensions = [postgis]
}

// PostGIS is enabled for future geo work (addresses/dispatch); no geo columns in this slice.

// =============================================================================
// AUTH
// =============================================================================

// (models added in later tasks)

// =============================================================================
// USERS & ROLES
// =============================================================================

// =============================================================================
// AUDIT
// =============================================================================
```
Note: `extensions = [postgis]` requires the preview feature flag. Add to the generator: change `generator client` block to:
```prisma
generator client {
  provider        = "prisma-client-js"
  previewFeatures = ["postgresqlExtensions"]
}
```

- [ ] **Step 3: Create the Prisma client singleton**

Create `apps/backend/src/shared/database/prisma.ts`:
```ts
import { PrismaClient } from '@prisma/client';

export const prisma = new PrismaClient();
```

- [ ] **Step 4: Verify Prisma can reach the database**

Run (in `apps/backend`):
```bash
pnpm exec prisma db execute --stdin <<< "SELECT 1;"
```
Expected: completes with no error (empty/success output). Confirms `DATABASE_URL` reaches the running Postgres.

- [ ] **Step 5: Commit**

```bash
git add apps/backend/prisma/schema.prisma apps/backend/src/shared/database/prisma.ts
git commit -m "chore(backend): init Prisma with PostGIS extension + client singleton"
```

---

### Task 3: User model + UserRole/UserStatus enums (TDD)

**Files:**
- Modify: `apps/backend/prisma/schema.prisma` (AUTH section)
- Create: `apps/backend/tests/schema/helpers.ts`
- Create: `apps/backend/tests/schema/user.test.ts`
- Create: `apps/backend/vitest.config.ts`

- [ ] **Step 1: Create the Vitest config + test helper**

Create `apps/backend/vitest.config.ts`:
```ts
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    fileParallelism: false, // tests share one DB; run serially
    setupFiles: [],
    env: { DATABASE_URL: process.env.TEST_DATABASE_URL ?? '' },
  },
});
```
Create `apps/backend/tests/schema/helpers.ts`:
```ts
import { PrismaClient } from '@prisma/client';

export const prisma = new PrismaClient({
  datasources: { db: { url: process.env.TEST_DATABASE_URL } },
});

// Truncate all tables between tests so each test starts clean.
export async function resetDb() {
  await prisma.$executeRawUnsafe(
    'TRUNCATE TABLE "AuditLog","RefreshToken","Admin","Merchant","Technician","Customer","User" RESTART IDENTITY CASCADE;'
  );
}
```
Note: the TRUNCATE list must include every table; later tasks add tables to it.

- [ ] **Step 2: Write the failing test**

Create `apps/backend/tests/schema/user.test.ts`:
```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { prisma, resetDb } from './helpers.js';

describe('User model', () => {
  beforeEach(resetDb);
  afterAll(() => prisma.$disconnect());

  it('creates a user with a unique phone and a role', async () => {
    const u = await prisma.user.create({
      data: { phone: '+919800000001', role: 'CUSTOMER' },
    });
    expect(u.id).toBeTruthy();
    expect(u.status).toBe('ACTIVE'); // default
    expect(u.deletedAt).toBeNull();
  });

  it('rejects a duplicate phone (one role per phone)', async () => {
    await prisma.user.create({ data: { phone: '+919800000002', role: 'CUSTOMER' } });
    await expect(
      prisma.user.create({ data: { phone: '+919800000002', role: 'TECHNICIAN' } })
    ).rejects.toThrow();
  });
});
```

- [ ] **Step 3: Run the test to verify it fails**

Run (in `apps/backend`):
```bash
pnpm test tests/schema/user.test.ts
```
Expected: FAIL — `prisma.user` undefined / type error (model doesn't exist yet).

- [ ] **Step 4: Add the User model + enums to the schema**

In `apps/backend/prisma/schema.prisma`, under the `AUTH` section header, add:
```prisma
model User {
  id            String     @id @default(uuid())
  phone         String     @unique
  role          UserRole
  status        UserStatus @default(ACTIVE)
  createdAt     DateTime   @default(now())
  updatedAt     DateTime   @updatedAt
  deletedAt     DateTime?

  customer      Customer?
  technician    Technician?
  merchant      Merchant?
  admin         Admin?
  refreshTokens RefreshToken[]
}

enum UserRole   { CUSTOMER  TECHNICIAN  MERCHANT  ADMIN }
enum UserStatus { ACTIVE  SUSPENDED }
```
Note: this references `Customer`/`Technician`/`Merchant`/`Admin`/`RefreshToken` which are added in Tasks 4-5. Prisma will not validate until those exist — so this task's migration is run AFTER Task 5. To keep the test loop tight, temporarily comment out the four profile relations + `refreshTokens` line, push just `User`, then uncomment in Task 5. (Alternative: do Tasks 3-5 schema edits together, then one migration. Chosen here: build schema additively, one migration at end of Task 5.)

- [ ] **Step 5: Push the schema to the test DB and generate client**

Run (in `apps/backend`), with the profile/refreshTokens relation lines temporarily commented:
```bash
TEST=1 DATABASE_URL="$TEST_DATABASE_URL" pnpm exec prisma db push --skip-generate --accept-data-loss
pnpm exec prisma generate
```
Expected: schema pushed to `fixcare_test`, client generated. (`db push` is used for the fast test loop; the real migration is created in Task 6.)

- [ ] **Step 6: Run the test to verify it passes**

Run:
```bash
pnpm test tests/schema/user.test.ts
```
Expected: PASS (both `it` blocks).

- [ ] **Step 7: Commit**

```bash
git add apps/backend/prisma/schema.prisma apps/backend/tests/schema/ apps/backend/vitest.config.ts
git commit -m "feat(backend): add User model + UserRole/UserStatus with tests"
```

---

### Task 4: The four role profiles + per-role enums (TDD)

**Files:**
- Modify: `apps/backend/prisma/schema.prisma` (USERS & ROLES section)
- Create: `apps/backend/tests/schema/profile.test.ts`

- [ ] **Step 1: Write the failing test**

Create `apps/backend/tests/schema/profile.test.ts`:
```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { prisma, resetDb } from './helpers.js';

describe('Role profiles (1:1 with User)', () => {
  beforeEach(resetDb);
  afterAll(() => prisma.$disconnect());

  it('links a Technician 1:1 to its User', async () => {
    const user = await prisma.user.create({ data: { phone: '+919800000010', role: 'TECHNICIAN' } });
    const tech = await prisma.technician.create({
      data: { userId: user.id, name: 'Ramesh', skills: ['AC', 'FAN'] },
    });
    expect(tech.status).toBe('PENDING'); // default
    const loaded = await prisma.user.findUnique({ where: { id: user.id }, include: { technician: true } });
    expect(loaded?.technician?.id).toBe(tech.id);
  });

  it('enforces one profile per user (unique userId)', async () => {
    const user = await prisma.user.create({ data: { phone: '+919800000011', role: 'CUSTOMER' } });
    await prisma.customer.create({ data: { userId: user.id, name: 'A' } });
    await expect(
      prisma.customer.create({ data: { userId: user.id, name: 'B' } })
    ).rejects.toThrow();
  });

  it('stores an Admin with email + passwordHash + adminLevel', async () => {
    const user = await prisma.user.create({ data: { phone: '+919800000012', role: 'ADMIN' } });
    const admin = await prisma.admin.create({
      data: { userId: user.id, name: 'Boss', email: 'boss@fixcare.in', passwordHash: 'argon2-hash', adminLevel: 'SUPER_ADMIN' },
    });
    expect(admin.adminLevel).toBe('SUPER_ADMIN');
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
pnpm test tests/schema/profile.test.ts
```
Expected: FAIL — `prisma.technician`/`customer`/`admin` undefined.

- [ ] **Step 3: Add the profile models + enums to the schema**

In `apps/backend/prisma/schema.prisma`, under `USERS & ROLES`, add:
```prisma
model Customer {
  id        String         @id @default(uuid())
  userId    String         @unique
  user      User           @relation(fields: [userId], references: [id])
  name      String
  status    CustomerStatus @default(ACTIVE)
  createdAt DateTime       @default(now())
  updatedAt DateTime       @updatedAt
  deletedAt DateTime?
}

model Technician {
  id        String           @id @default(uuid())
  userId    String           @unique
  user      User             @relation(fields: [userId], references: [id])
  name      String
  skills    ServiceSkill[]
  status    TechnicianStatus @default(PENDING)
  createdAt DateTime         @default(now())
  updatedAt DateTime         @updatedAt
  deletedAt DateTime?
}

model Merchant {
  id        String         @id @default(uuid())
  userId    String         @unique
  user      User           @relation(fields: [userId], references: [id])
  shopName  String
  status    MerchantStatus @default(PENDING)
  createdAt DateTime       @default(now())
  updatedAt DateTime       @updatedAt
  deletedAt DateTime?
}

model Admin {
  id           String      @id @default(uuid())
  userId       String      @unique
  user         User        @relation(fields: [userId], references: [id])
  name         String
  email        String      @unique
  passwordHash String
  adminLevel   AdminLevel  @default(SUPPORT)
  status       AdminStatus @default(ACTIVE)
  createdAt    DateTime    @default(now())
  updatedAt    DateTime    @updatedAt
  deletedAt    DateTime?
}

enum CustomerStatus   { ACTIVE  SUSPENDED }
enum TechnicianStatus { PENDING  KYC_SUBMITTED  VERIFIED  SUSPENDED  DEACTIVATED }
enum MerchantStatus   { PENDING  VERIFIED  SUSPENDED }
enum AdminLevel       { SUPER_ADMIN  MANAGER  SUPPORT }
enum AdminStatus      { ACTIVE  SUSPENDED }
enum ServiceSkill     { AC  FAN  ELECTRICAL  WIRING  APPLIANCE }
```
Then uncomment the `customer`/`technician`/`merchant`/`admin` relation lines on `User` (added in Task 3 Step 4).

- [ ] **Step 4: Push schema + regenerate**

Run:
```bash
DATABASE_URL="$TEST_DATABASE_URL" pnpm exec prisma db push --skip-generate --accept-data-loss
pnpm exec prisma generate
```
Expected: success.

- [ ] **Step 5: Run the test to verify it passes**

Run:
```bash
pnpm test tests/schema/profile.test.ts
```
Expected: PASS (all three).

- [ ] **Step 6: Commit**

```bash
git add apps/backend/prisma/schema.prisma apps/backend/tests/schema/profile.test.ts
git commit -m "feat(backend): add Customer/Technician/Merchant/Admin profiles with tests"
```

---

### Task 5: RefreshToken model (rotation + sliding expiry) (TDD)

**Files:**
- Modify: `apps/backend/prisma/schema.prisma` (AUTH section)
- Create: `apps/backend/tests/schema/refresh-token.test.ts`

- [ ] **Step 1: Write the failing test**

Create `apps/backend/tests/schema/refresh-token.test.ts`:
```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { prisma, resetDb } from './helpers.js';

describe('RefreshToken model', () => {
  beforeEach(resetDb);
  afterAll(() => prisma.$disconnect());

  async function makeUser(phone: string) {
    return prisma.user.create({ data: { phone, role: 'CUSTOMER' } });
  }

  it('stores a hashed token with an expiry', async () => {
    const user = await makeUser('+919800000020');
    const t = await prisma.refreshToken.create({
      data: { userId: user.id, tokenHash: 'hash-1', expiresAt: new Date(Date.now() + 30 * 864e5) },
    });
    expect(t.revokedAt).toBeNull();
    expect(t.tokenHash).toBe('hash-1');
  });

  it('links a rotation chain via replacedById and is unique', async () => {
    const user = await makeUser('+919800000021');
    const oldT = await prisma.refreshToken.create({
      data: { userId: user.id, tokenHash: 'old', expiresAt: new Date(Date.now() + 864e5) },
    });
    const newT = await prisma.refreshToken.create({
      data: { userId: user.id, tokenHash: 'new', expiresAt: new Date(Date.now() + 30 * 864e5) },
    });
    const rotated = await prisma.refreshToken.update({
      where: { id: oldT.id },
      data: { revokedAt: new Date(), replacedById: newT.id },
    });
    expect(rotated.replacedById).toBe(newT.id);
  });

  it('rejects a duplicate tokenHash', async () => {
    const user = await makeUser('+919800000022');
    await prisma.refreshToken.create({ data: { userId: user.id, tokenHash: 'dup', expiresAt: new Date(Date.now() + 864e5) } });
    await expect(
      prisma.refreshToken.create({ data: { userId: user.id, tokenHash: 'dup', expiresAt: new Date(Date.now() + 864e5) } })
    ).rejects.toThrow();
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
pnpm test tests/schema/refresh-token.test.ts
```
Expected: FAIL — `prisma.refreshToken` undefined.

- [ ] **Step 3: Add the RefreshToken model to the schema**

In `apps/backend/prisma/schema.prisma`, under `AUTH` (after `User`), add:
```prisma
model RefreshToken {
  id           String        @id @default(uuid())
  userId       String
  user         User          @relation(fields: [userId], references: [id])
  tokenHash    String        @unique
  expiresAt    DateTime
  createdAt    DateTime      @default(now())
  revokedAt    DateTime?
  replacedById String?       @unique
  replacedBy   RefreshToken? @relation("TokenRotation", fields: [replacedById], references: [id])
  previous     RefreshToken? @relation("TokenRotation")
  userAgent    String?
  ipHash       String?

  @@index([userId])
  @@index([expiresAt])
}
```

- [ ] **Step 4: Push schema + regenerate**

Run:
```bash
DATABASE_URL="$TEST_DATABASE_URL" pnpm exec prisma db push --skip-generate --accept-data-loss
pnpm exec prisma generate
```
Expected: success.

- [ ] **Step 5: Run the test to verify it passes**

Run:
```bash
pnpm test tests/schema/refresh-token.test.ts
```
Expected: PASS (all three).

- [ ] **Step 6: Commit**

```bash
git add apps/backend/prisma/schema.prisma apps/backend/tests/schema/refresh-token.test.ts
git commit -m "feat(backend): add RefreshToken model (rotation + sliding expiry) with tests"
```

---

### Task 6: AuditLog model (append-only) (TDD)

**Files:**
- Modify: `apps/backend/prisma/schema.prisma` (AUDIT section)
- Modify: `apps/backend/tests/schema/helpers.ts` (TRUNCATE already includes AuditLog — verify)
- Create: `apps/backend/tests/schema/audit-log.test.ts`

- [ ] **Step 1: Write the failing test**

Create `apps/backend/tests/schema/audit-log.test.ts`:
```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { prisma, resetDb } from './helpers.js';

describe('AuditLog model', () => {
  beforeEach(resetDb);
  afterAll(() => prisma.$disconnect());

  it('records an enumerated action with PII-free metadata', async () => {
    const row = await prisma.auditLog.create({
      data: {
        action: 'ADMIN_LEVEL_CHANGED',
        actorType: 'ADMIN',
        actorId: 'admin-1',
        subjectId: 'admin-2',
        metadata: { fromLevel: 'SUPPORT', toLevel: 'MANAGER' },
      },
    });
    expect(row.action).toBe('ADMIN_LEVEL_CHANGED');
    expect(row.createdAt).toBeInstanceOf(Date);
  });

  it('allows a SYSTEM actor with null actorId', async () => {
    const row = await prisma.auditLog.create({
      data: { action: 'REFRESH_TOKEN_REUSE_DETECTED', actorType: 'SYSTEM' },
    });
    expect(row.actorId).toBeNull();
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
pnpm test tests/schema/audit-log.test.ts
```
Expected: FAIL — `prisma.auditLog` undefined.

- [ ] **Step 3: Add the AuditLog model + enums to the schema**

In `apps/backend/prisma/schema.prisma`, under `AUDIT`, add:
```prisma
model AuditLog {
  id        String      @id @default(uuid())
  action    AuditAction
  actorType ActorType
  actorId   String?
  subjectId String?
  metadata  Json?
  createdAt DateTime    @default(now())

  @@index([actorId])
  @@index([subjectId])
  @@index([action])
  @@index([createdAt])
}

enum ActorType   { USER  ADMIN  SYSTEM }
enum AuditAction {
  USER_REGISTERED
  USER_LOGGED_IN
  USER_SUSPENDED
  USER_REACTIVATED
  ADMIN_LEVEL_CHANGED
  REFRESH_TOKEN_REUSE_DETECTED
}
```

- [ ] **Step 4: Push schema + regenerate**

Run:
```bash
DATABASE_URL="$TEST_DATABASE_URL" pnpm exec prisma db push --skip-generate --accept-data-loss
pnpm exec prisma generate
```
Expected: success.

- [ ] **Step 5: Run the test to verify it passes**

Run:
```bash
pnpm test tests/schema/audit-log.test.ts
```
Expected: PASS (both).

- [ ] **Step 6: Commit**

```bash
git add apps/backend/prisma/schema.prisma apps/backend/tests/schema/audit-log.test.ts
git commit -m "feat(backend): add append-only AuditLog model with tests"
```

---

### Task 7: Soft-delete behavior test + full suite green

**Files:**
- Modify: `apps/backend/tests/schema/user.test.ts` (add soft-delete case)

- [ ] **Step 1: Add the soft-delete test**

Append to the `describe('User model', ...)` block in `apps/backend/tests/schema/user.test.ts`:
```ts
  it('soft-deletes a user (deletedAt set, row still present)', async () => {
    const u = await prisma.user.create({ data: { phone: '+919800000030', role: 'CUSTOMER' } });
    await prisma.user.update({ where: { id: u.id }, data: { deletedAt: new Date() } });

    const active = await prisma.user.findMany({ where: { deletedAt: null } });
    expect(active.find((x) => x.id === u.id)).toBeUndefined(); // excluded by the convention filter

    const all = await prisma.user.findMany();
    expect(all.find((x) => x.id === u.id)).toBeTruthy(); // row physically still there
  });
```

- [ ] **Step 2: Run the full test suite**

Run (in `apps/backend`):
```bash
pnpm test
```
Expected: ALL tests pass across user/profile/refresh-token/audit-log files.

- [ ] **Step 3: Commit**

```bash
git add apps/backend/tests/schema/user.test.ts
git commit -m "test(backend): assert soft-delete excludes via deletedAt filter"
```

---

### Task 8: Create the real migration + apply to dev DB

**Files:**
- Create: `apps/backend/prisma/migrations/<timestamp>_auth_users_slice/migration.sql` (generated)

- [ ] **Step 1: Generate and apply the initial migration to the DEV database**

Run (in `apps/backend`) — note this targets `DATABASE_URL` (dev), not the test DB:
```bash
pnpm exec prisma migrate dev --name auth_users_slice
```
Expected: a migration folder created under `prisma/migrations/`, applied to `fixcare_dev`, client regenerated. PostGIS extension included.

- [ ] **Step 2: Verify the tables exist in the dev DB**

Run (from repo root):
```bash
docker compose exec -T postgres psql -U fixcare -d fixcare_dev -c "\dt"
```
Expected: lists `User`, `RefreshToken`, `Customer`, `Technician`, `Merchant`, `Admin`, `AuditLog` (+ `_prisma_migrations`).

- [ ] **Step 3: Review the migration with the prisma-migration-reviewer agent**

Dispatch the `prisma-migration-reviewer` agent on the generated `migration.sql` + `schema.prisma` diff. Address any BLOCKING findings (float money, missing soft-delete, unmasked Aadhaar, destructive ops). Expected: clean (this slice has no money/Aadhaar fields; soft-delete present on User+profiles).

- [ ] **Step 4: Commit**

```bash
git add apps/backend/prisma/migrations/
git commit -m "feat(backend): initial auth+users migration applied to dev DB"
```

---

### Task 9: Wire backend into the monorepo workspace + docs

**Files:**
- Modify: `apps/backend/README.md` (note it's now scaffolded)
- Modify: `STATUS.md` (Last shipped / Active task)
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Verify pnpm workspace picks up the backend**

Run (from repo root):
```bash
pnpm -r exec node -e "console.log('workspace ok')"
```
Expected: runs in `@fixcare/backend` without error (confirms `pnpm-workspace.yaml` includes it).

- [ ] **Step 2: Update STATUS.md**

In `STATUS.md`, set Active task to the next slice and add to Last shipped:
```
- `apps/backend` scaffolded (Fastify+TS+Prisma); auth+users schema slice migrated
  to dev DB with passing invariant tests.
```

- [ ] **Step 3: Update CHANGELOG.md**

Add under the current date:
```
- **Backend auth+users schema slice.** Scaffolded apps/backend (Fastify 5 + TS strict
  + Prisma 6 + Vitest); implemented User, RefreshToken, Customer/Technician/Merchant/Admin,
  AuditLog with TDD invariant tests; first migration applied to fixcare_dev.
```

- [ ] **Step 4: Commit**

```bash
git add apps/backend/README.md STATUS.md CHANGELOG.md
git commit -m "docs: record backend scaffold + auth-users schema slice"
```

---

## Definition of Done

- `pnpm test` in `apps/backend` is fully green (user, profile, refresh-token, audit-log, soft-delete).
- `prisma migrate dev` has produced a committed migration; `\dt` shows all 7 tables in `fixcare_dev`.
- `prisma-migration-reviewer` agent reports no BLOCKING issues.
- Schema matches the design spec exactly (Technician naming, soft-delete on User+profiles, hashed RefreshToken with rotation chain, append-only AuditLog, no money/Aadhaar fields).
- STATUS.md + CHANGELOG.md updated; all commits authored by you (authorship hook enforces).

## Notes / known follow-ups (NOT this plan)
- OTP storage in Redis, JWT signing, and the actual auth **routes/services** are the next slice (this plan is data-layer only).
- The role↔profile *application* invariant (role=TECHNICIAN ⇒ Technician row) is enforced in the user-creation **service** — that's the next slice; this plan covers the DB-level uniqueness only.
- `db push` is used for the fast test loop; `migrate dev` (Task 8) is the source of truth for the dev DB. Tests run against `fixcare_test` via `db push`.
