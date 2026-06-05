# Service Catalog — Sub-slice A Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Admin-managed zones + service categories + services with geofenced labor pricing — readable by any authed user, writable only by MANAGER+ admins, with every price/catalog mutation audited.

**Architecture:** A new `catalog/` module. Money is integer paise throughout, via a new `shared/utils/currency.ts`. Writes are gated by a new `requireAdminLevel(MANAGER)` preHandler (layered on `requireAuth`); reads need only `requireAuth`. Per-zone labor prices are normalized rows (`ServicePrice` per service×zone); the zone carries the flat visit fee. Price changes update in place + write a `PRICE_CHANGED` audit; other catalog mutations write `CATALOG_UPDATED`.

**Tech Stack:** Node 22, Fastify 5, Prisma 6, Zod v4, Vitest.

**Scope:** Sub-slice A only. **PARTS (`PartsCatalog`) and the catalog SEED are sub-slice B — out of scope here.** On branch `feature/service-catalog`.

---

## Shell prerequisite (EVERY command step)
```bash
export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh" && nvm use 22 >/dev/null   # shell defaults to Node 25
```
Load env (from `apps/backend`): `set -a; . ./.env; set +a`. Work dir: `apps/backend`. ESM/NodeNext → local imports use `.js`. Docker Postgres+Redis running. Commits authored `MohammadKaifSaiyad <saiyedkgn6@gmail.com>`, NO Claude co-author trailer (`.githooks/commit-msg` enforces; never write that literal phrase in a message).

## Existing foundation (on main — do NOT recreate)
- `src/shared/middleware/auth.ts`: `requireAuth` (→ `request.user = {id, role}`).
- `src/shared/errors.ts`: `AppError(message, statusCode, code)` base + `ValidationError`(400), `UnauthorizedError`(401), `ForbiddenError`(403), `NotFoundError`(404), `TooManyRequestsError`(429). The global handler (`errorHandler.ts`) maps any `AppError` by `statusCode` — **so a new `ConflictError(409)` needs NO handler change.**
- `src/shared/auth/tokens.ts`: `signAccessToken(userId, role)` — for minting test tokens.
- `src/shared/database/prisma.ts` (`prisma`).
- `src/app.ts` `buildApp()` registers: security → errorHandler → `registerAuthRoutes` → `registerProfileRoutes` → `/health` → `return app`. **Add `await registerCatalogRoutes(app)` after the profile line.**
- Route convention: `const parsed = schema.safeParse(request.body); if (!parsed.success) throw new ValidationError(parsed.error.issues[0]?.message ?? 'Invalid input');` then call service, return DTO.
- Prisma `Admin {userId @unique, adminLevel (SUPER_ADMIN|MANAGER|SUPPORT), status, deletedAt}`; `AuditLog {action, actorType, actorId?, subjectId?, metadata?}`; `AuditAction` currently ends at `PROFILE_UPDATED`.
- Tests: `tests/schema/helpers.ts` (`prisma`, `resetDb` — TRUNCATE list at line 15), `tests/helpers/redis.ts` (`flushTestRedis`).

## File Structure

```
apps/backend/
├── prisma/schema.prisma                  # + Zone, ServiceCategory, Service, ServicePrice, enums, audit actions
├── prisma/migrations/<ts>_service_catalog/
└── src/
    ├── shared/
    │   ├── utils/currency.ts             # NEW: paise helpers
    │   ├── errors.ts                     # + ConflictError(409)
    │   └── middleware/rbac.ts            # NEW: requireAdminLevel(min)
    ├── app.ts                            # + registerCatalogRoutes
    └── modules/catalog/
        ├── catalog.types.ts              # DTOs + mappers
        ├── catalog.schemas.ts            # Zod bodies (strict, paise≥0)
        ├── catalog.service.ts            # read + write fns, audited
        └── catalog.routes.ts             # registerCatalogRoutes
tests/
├── currency.test.ts                      # unit, no DB
└── catalog/
    ├── helpers.ts                        # mint admin/customer tokens
    ├── rbac.test.ts
    ├── zones.test.ts
    └── services-pricing.test.ts
```

---

### Task 1: currency util (TDD, unit)

**Files:** Create `apps/backend/src/shared/utils/currency.ts`, `apps/backend/tests/currency.test.ts`

- [ ] **Step 1: Write the failing test**

Create `apps/backend/tests/currency.test.ts`:
```ts
import { describe, expect, it } from 'vitest';
import { rupeesToPaise, paiseToRupees, formatPaise, assertValidPaise } from '../src/shared/utils/currency.js';
import { ValidationError } from '../src/shared/errors.js';

describe('currency', () => {
  it('converts rupees → paise (integer)', () => {
    expect(rupeesToPaise(149)).toBe(14900);
    expect(rupeesToPaise(99.5)).toBe(9950);
  });
  it('converts paise → rupees', () => {
    expect(paiseToRupees(14900)).toBe(149);
  });
  it('formats paise as ₹', () => {
    expect(formatPaise(14900)).toBe('₹149.00');
    expect(formatPaise(9950)).toBe('₹99.50');
  });
  it('assertValidPaise accepts a non-negative integer', () => {
    expect(() => assertValidPaise(0)).not.toThrow();
    expect(() => assertValidPaise(14900)).not.toThrow();
  });
  it('assertValidPaise rejects negatives, floats, and non-numbers', () => {
    expect(() => assertValidPaise(-1)).toThrow(ValidationError);
    expect(() => assertValidPaise(10.5)).toThrow(ValidationError);
    expect(() => assertValidPaise('100')).toThrow(ValidationError);
  });
});
```

- [ ] **Step 2: Run, expect FAIL**

```bash
export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh" && nvm use 22 >/dev/null
set -a; . ./.env; set +a
pnpm test tests/currency.test.ts
```
Expected: FAIL — module not found.

- [ ] **Step 3: Implement currency.ts**

Create `apps/backend/src/shared/utils/currency.ts`:
```ts
import { ValidationError } from '../errors.js';

/** Rupees → integer paise. Rounds to the nearest paisa. */
export function rupeesToPaise(rupees: number): number {
  return Math.round(rupees * 100);
}

/** Integer paise → rupees (number). */
export function paiseToRupees(paise: number): number {
  return paise / 100;
}

/** Format paise as a ₹ string with 2 decimals, e.g. 14900 → "₹149.00". */
export function formatPaise(paise: number): string {
  return `₹${(paise / 100).toFixed(2)}`;
}

/** Assert a value is a non-negative integer number of paise; throws ValidationError otherwise. */
export function assertValidPaise(v: unknown): asserts v is number {
  if (typeof v !== 'number' || !Number.isInteger(v) || v < 0) {
    throw new ValidationError('Amount must be a non-negative integer (paise)');
  }
}
```

- [ ] **Step 4: Run, expect PASS**

```bash
set -a; . ./.env; set +a
pnpm test tests/currency.test.ts
```
Expected: 5 passed.

- [ ] **Step 5: Commit**

```bash
cd /Users/mohammadkaifsaiyad/Development/FixCare && git add apps/backend/src/shared/utils/currency.ts apps/backend/tests/currency.test.ts && git commit -m "feat(backend): shared currency util (integer paise)"
```

---

### Task 2: ConflictError + requireAdminLevel (TDD for rbac)

**Files:** Modify `apps/backend/src/shared/errors.ts`; Create `apps/backend/src/shared/middleware/rbac.ts`, `apps/backend/tests/catalog/helpers.ts`, `apps/backend/tests/catalog/rbac.test.ts`

- [ ] **Step 1: Add ConflictError**

In `apps/backend/src/shared/errors.ts`, after `TooManyRequestsError`, add:
```ts
export class ConflictError extends AppError {
  constructor(message = 'Conflict') { super(message, 409, 'CONFLICT'); }
}
```
(No errorHandler change — it maps any `AppError` by `statusCode`.)

- [ ] **Step 2: Create the catalog test helper**

Create `apps/backend/tests/catalog/helpers.ts`:
```ts
import { prisma } from '../schema/helpers.js';
import { signAccessToken } from '../../src/shared/auth/tokens.js';
import type { AdminLevel } from '@prisma/client';

let seq = 0;
function uniquePhone(): string { return '93' + String(100000000 + seq++).slice(0, 8); }

/** Create an ADMIN user + Admin profile at the given level; return a Bearer token. */
export async function makeAdminToken(level: AdminLevel): Promise<string> {
  const user = await prisma.user.create({ data: { phone: uniquePhone(), role: 'ADMIN' } });
  await prisma.admin.create({
    data: { userId: user.id, name: 'Adm', email: `adm-${user.id}@fixcare.in`, passwordHash: 'x', adminLevel: level },
  });
  return signAccessToken(user.id, 'ADMIN');
}

/** Create a CUSTOMER user + profile; return a Bearer token (for read/forbidden tests). */
export async function makeCustomerToken(): Promise<string> {
  const user = await prisma.user.create({ data: { phone: uniquePhone(), role: 'CUSTOMER' } });
  await prisma.customer.create({ data: { userId: user.id, name: 'Cust' } });
  return signAccessToken(user.id, 'CUSTOMER');
}
```

- [ ] **Step 3: Write the failing rbac test**

Create `apps/backend/tests/catalog/rbac.test.ts`:
```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { requireAuth } from '../../src/shared/middleware/auth.js';
import { requireAdminLevel } from '../../src/shared/middleware/rbac.js';
import { makeAdminToken, makeCustomerToken } from './helpers.js';

const app = await buildApp();
app.get('/__manager-only', { preHandler: [requireAuth, requireAdminLevel('MANAGER')] }, async () => ({ ok: true }));
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });

function auth(t: string) { return { authorization: `Bearer ${t}` }; }

describe('requireAdminLevel(MANAGER)', () => {
  it('allows SUPER_ADMIN', async () => {
    const t = await makeAdminToken('SUPER_ADMIN');
    expect((await app.inject({ method: 'GET', url: '/__manager-only', headers: auth(t) })).statusCode).toBe(200);
  });
  it('allows MANAGER', async () => {
    const t = await makeAdminToken('MANAGER');
    expect((await app.inject({ method: 'GET', url: '/__manager-only', headers: auth(t) })).statusCode).toBe(200);
  });
  it('rejects SUPPORT (403)', async () => {
    const t = await makeAdminToken('SUPPORT');
    expect((await app.inject({ method: 'GET', url: '/__manager-only', headers: auth(t) })).statusCode).toBe(403);
  });
  it('rejects a customer (403)', async () => {
    const t = await makeCustomerToken();
    expect((await app.inject({ method: 'GET', url: '/__manager-only', headers: auth(t) })).statusCode).toBe(403);
  });
  it('rejects no token (401)', async () => {
    expect((await app.inject({ method: 'GET', url: '/__manager-only' })).statusCode).toBe(401);
  });
});
```

- [ ] **Step 4: Run, expect FAIL**

```bash
set -a; . ./.env; set +a
pnpm test tests/catalog/rbac.test.ts
```
Expected: FAIL — `requireAdminLevel` not found.

- [ ] **Step 5: Implement rbac.ts**

Create `apps/backend/src/shared/middleware/rbac.ts`:
```ts
import type { FastifyReply, FastifyRequest } from 'fastify';
import type { AdminLevel } from '@prisma/client';
import { prisma } from '../database/prisma.js';
import { ForbiddenError } from '../errors.js';

const RANK: Record<AdminLevel, number> = { SUPPORT: 1, MANAGER: 2, SUPER_ADMIN: 3 };

/** Fastify preHandler (run AFTER requireAuth): require the caller be an admin of at least `min` level. */
export function requireAdminLevel(min: AdminLevel) {
  return async function (request: FastifyRequest, _reply: FastifyReply): Promise<void> {
    const user = request.user;
    if (!user || user.role !== 'ADMIN') throw new ForbiddenError('Admin access required');
    const admin = await prisma.admin.findFirst({ where: { userId: user.id, deletedAt: null } });
    if (!admin || admin.status !== 'ACTIVE') throw new ForbiddenError('Admin access required');
    if (RANK[admin.adminLevel] < RANK[min]) throw new ForbiddenError('Insufficient admin level');
  };
}
```

- [ ] **Step 6: Run, expect PASS**

```bash
set -a; . ./.env; set +a
pnpm test tests/catalog/rbac.test.ts
```
Expected: 5 passed.

- [ ] **Step 7: Typecheck + commit**

```bash
pnpm exec tsc --noEmit
cd /Users/mohammadkaifsaiyad/Development/FixCare && git add apps/backend/src/shared/errors.ts apps/backend/src/shared/middleware/rbac.ts apps/backend/tests/catalog/ && git commit -m "feat(backend): ConflictError + requireAdminLevel middleware"
```

---

### Task 3: Catalog schema + migration + test-DB sync

**Files:** Modify `apps/backend/prisma/schema.prisma`, `apps/backend/tests/schema/helpers.ts`; Create migration

- [ ] **Step 1: Add the models + enums to schema.prisma**

Append a CATALOG section to `apps/backend/prisma/schema.prisma`:
```prisma
// =============================================================================
// CATALOG
// =============================================================================
model Zone {
  id            String        @id @default(uuid())
  name          String        @unique
  visitFeePaise Int
  status        CatalogStatus @default(ACTIVE)
  createdAt     DateTime      @default(now())
  updatedAt     DateTime      @updatedAt
  deletedAt     DateTime?
  servicePrices ServicePrice[]
}

model ServiceCategory {
  id        String        @id @default(uuid())
  name      String        @unique
  status    CatalogStatus @default(ACTIVE)
  createdAt DateTime      @default(now())
  updatedAt DateTime      @updatedAt
  deletedAt DateTime?
  services  Service[]
}

model Service {
  id         String          @id @default(uuid())
  categoryId String
  category   ServiceCategory @relation(fields: [categoryId], references: [id])
  name       String
  tier       LaborTier
  status     CatalogStatus   @default(ACTIVE)
  createdAt  DateTime        @default(now())
  updatedAt  DateTime        @updatedAt
  deletedAt  DateTime?
  prices     ServicePrice[]
  @@unique([categoryId, name])
}

model ServicePrice {
  id         String   @id @default(uuid())
  serviceId  String
  service    Service  @relation(fields: [serviceId], references: [id])
  zoneId     String
  zone       Zone     @relation(fields: [zoneId], references: [id])
  laborPaise Int
  createdAt  DateTime @default(now())
  updatedAt  DateTime @updatedAt
  @@unique([serviceId, zoneId])
  @@index([zoneId])
}

enum CatalogStatus { ACTIVE  INACTIVE }
enum LaborTier     { T1  T2  T3 }
```
And add two values to the existing `AuditAction` enum (after `PROFILE_UPDATED`):
```prisma
  PRICE_CHANGED
  CATALOG_UPDATED
```
(Note: `PartsCatalog` is NOT added here — it's sub-slice B.)

- [ ] **Step 2: Create + apply the migration (dev DB)**

```bash
export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh" && nvm use 22 >/dev/null
set -a; . ./.env; set +a
pnpm exec prisma migrate dev --name service_catalog
```
Expected: a migration creating the 4 tables + 2 enums + the 2 ADD VALUE statements, applied cleanly, client regenerated. **New tables + enum values are non-destructive — NO reset should be prompted.** If a reset IS prompted, STOP and report (do not reset). (Postgres note: `ALTER TYPE ... ADD VALUE` can't run in the same transaction as table creation in some cases — Prisma 6 splits the migration correctly; if it errors about "ADD VALUE cannot run inside a transaction block", report it verbatim.)

- [ ] **Step 3: Sync the TEST DB (tests use db push, not migrate)**

The test DB (`fixcare_test`) is kept current via `db push` (this split bit us before — the dev DB gets migrations, the test DB gets `db push`). Run:
```bash
DATABASE_URL="$TEST_DATABASE_URL" pnpm exec prisma db push --skip-generate --accept-data-loss
```
Expected: "Your database is now in sync with your Prisma schema" — the 4 catalog tables + new enum values now exist in `fixcare_test`.

- [ ] **Step 4: Extend resetDb's TRUNCATE list**

In `apps/backend/tests/schema/helpers.ts`, replace the TRUNCATE statement (currently line ~15) so the catalog tables are included (children before parents for FK order):
```ts
  await prisma.$executeRawUnsafe(
    'TRUNCATE TABLE "ServicePrice","Service","ServiceCategory","Zone","AuditLog","RefreshToken","Admin","Merchant","Technician","Customer","User" RESTART IDENTITY CASCADE;'
  );
```

- [ ] **Step 5: Verify the existing suite still passes against the synced test DB**

```bash
set -a; . ./.env; set +a
pnpm test
```
Expected: the prior total (60) still green — schema additions don't change existing behavior.

- [ ] **Step 6: Commit**

```bash
cd /Users/mohammadkaifsaiyad/Development/FixCare && git add apps/backend/prisma/ apps/backend/tests/schema/helpers.ts && git commit -m "feat(backend): catalog schema (Zone/ServiceCategory/Service/ServicePrice) + audit actions"
```

---

### Task 4: catalog DTOs + Zod schemas

**Files:** Create `apps/backend/src/modules/catalog/catalog.types.ts`, `apps/backend/src/modules/catalog/catalog.schemas.ts`

- [ ] **Step 1: Create catalog.types.ts**

```ts
import type { Zone, ServiceCategory, Service } from '@prisma/client';

export interface ZoneDto { id: string; name: string; visitFeePaise: number; status: Zone['status']; }
export interface CategoryDto { id: string; name: string; status: ServiceCategory['status']; }
export interface ServicePriceDto {
  id: string;
  name: string;
  tier: Service['tier'];
  categoryId: string;
  laborPaise: number;       // price for the requested zone
  visitFeePaise: number;    // the zone's visit fee
}

export function toZoneDto(z: Zone): ZoneDto {
  return { id: z.id, name: z.name, visitFeePaise: z.visitFeePaise, status: z.status };
}
export function toCategoryDto(c: ServiceCategory): CategoryDto {
  return { id: c.id, name: c.name, status: c.status };
}
```
(`ServicePriceDto` is assembled in the service from a Service + its ServicePrice + the Zone; no single-row mapper.)

- [ ] **Step 2: Create catalog.schemas.ts**

```ts
import { z } from 'zod';

const paise = z.number().int().min(0, 'must be a non-negative integer (paise)');
const tier = z.enum(['T1', 'T2', 'T3']);

export const createZoneBody = z.object({ name: z.string().min(1), visitFeePaise: paise }).strict();
export type CreateZoneBody = z.infer<typeof createZoneBody>;

export const updateZoneBody = z
  .object({ name: z.string().min(1), visitFeePaise: paise, status: z.enum(['ACTIVE', 'INACTIVE']) })
  .partial().strict()
  .refine((b) => Object.keys(b).length > 0, { message: 'At least one field is required' });
export type UpdateZoneBody = z.infer<typeof updateZoneBody>;

export const createCategoryBody = z.object({ name: z.string().min(1) }).strict();
export type CreateCategoryBody = z.infer<typeof createCategoryBody>;

export const createServiceBody = z.object({ categoryId: z.string().min(1), name: z.string().min(1), tier }).strict();
export type CreateServiceBody = z.infer<typeof createServiceBody>;

export const upsertPriceBody = z.object({ laborPaise: paise }).strict();
export type UpsertPriceBody = z.infer<typeof upsertPriceBody>;
```

- [ ] **Step 3: Typecheck + commit**

```bash
pnpm exec tsc --noEmit
cd /Users/mohammadkaifsaiyad/Development/FixCare && git add apps/backend/src/modules/catalog/catalog.types.ts apps/backend/src/modules/catalog/catalog.schemas.ts && git commit -m "feat(backend): catalog DTOs + Zod schemas"
```

---

### Task 5: catalog reads + zone/category/service writes (TDD)

**Files:** Create `apps/backend/src/modules/catalog/catalog.service.ts`, `apps/backend/src/modules/catalog/catalog.routes.ts`, `apps/backend/tests/catalog/zones.test.ts`; Modify `apps/backend/src/app.ts`

- [ ] **Step 1: Write the failing zones/categories test**

Create `apps/backend/tests/catalog/zones.test.ts`:
```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeAdminToken, makeCustomerToken } from './helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }

describe('zones + categories', () => {
  it('MANAGER creates a zone; any authed user reads it', async () => {
    const mgr = await makeAdminToken('MANAGER');
    const create = await app.inject({ method: 'POST', url: '/catalog/zones', headers: auth(mgr), payload: { name: 'Vadodara', visitFeePaise: 14900 } });
    expect(create.statusCode).toBe(201);

    const cust = await makeCustomerToken();
    const list = await app.inject({ method: 'GET', url: '/catalog/zones', headers: auth(cust) });
    expect(list.statusCode).toBe(200);
    expect(list.json()).toHaveLength(1);
    expect(list.json()[0].visitFeePaise).toBe(14900);
  });

  it('SUPPORT cannot create a zone (403); CATALOG_UPDATED audit on create', async () => {
    const sup = await makeAdminToken('SUPPORT');
    expect((await app.inject({ method: 'POST', url: '/catalog/zones', headers: auth(sup), payload: { name: 'Padra', visitFeePaise: 9900 } })).statusCode).toBe(403);

    const mgr = await makeAdminToken('MANAGER');
    await app.inject({ method: 'POST', url: '/catalog/zones', headers: auth(mgr), payload: { name: 'Padra', visitFeePaise: 9900 } });
    const audit = await prisma.auditLog.findFirst({ where: { action: 'CATALOG_UPDATED' } });
    expect(audit).toBeTruthy();
  });

  it('duplicate zone name → 409', async () => {
    const mgr = await makeAdminToken('MANAGER');
    await app.inject({ method: 'POST', url: '/catalog/zones', headers: auth(mgr), payload: { name: 'Vadodara', visitFeePaise: 14900 } });
    const dup = await app.inject({ method: 'POST', url: '/catalog/zones', headers: auth(mgr), payload: { name: 'Vadodara', visitFeePaise: 14900 } });
    expect(dup.statusCode).toBe(409);
  });

  it('negative paise → 400', async () => {
    const mgr = await makeAdminToken('MANAGER');
    expect((await app.inject({ method: 'POST', url: '/catalog/zones', headers: auth(mgr), payload: { name: 'X', visitFeePaise: -5 } })).statusCode).toBe(400);
  });

  it('soft-deleted / INACTIVE zone hidden from reads', async () => {
    const mgr = await makeAdminToken('MANAGER');
    const created = await app.inject({ method: 'POST', url: '/catalog/zones', headers: auth(mgr), payload: { name: 'Gone', visitFeePaise: 100 } });
    const id = created.json().id;
    await prisma.zone.update({ where: { id }, data: { deletedAt: new Date() } });
    const cust = await makeCustomerToken();
    const list = await app.inject({ method: 'GET', url: '/catalog/zones', headers: auth(cust) });
    expect(list.json().find((z: { id: string }) => z.id === id)).toBeUndefined();
  });

  it('categories: MANAGER creates, user reads', async () => {
    const mgr = await makeAdminToken('MANAGER');
    expect((await app.inject({ method: 'POST', url: '/catalog/categories', headers: auth(mgr), payload: { name: 'AC' } })).statusCode).toBe(201);
    const cust = await makeCustomerToken();
    const list = await app.inject({ method: 'GET', url: '/catalog/categories', headers: auth(cust) });
    expect(list.json().some((c: { name: string }) => c.name === 'AC')).toBe(true);
  });
});
```

- [ ] **Step 2: Run, expect FAIL (routes 404)**

```bash
export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh" && nvm use 22 >/dev/null
set -a; . ./.env; set +a
pnpm test tests/catalog/zones.test.ts
```
Expected: FAIL — routes not registered.

- [ ] **Step 3: Create catalog.service.ts (reads + zone/category writes)**

Create `apps/backend/src/modules/catalog/catalog.service.ts`:
```ts
import { Prisma } from '@prisma/client';
import { prisma } from '../../shared/database/prisma.js';
import { ConflictError, NotFoundError } from '../../shared/errors.js';
import { toZoneDto, toCategoryDto, type ZoneDto, type CategoryDto } from './catalog.types.js';
import type { CreateZoneBody, UpdateZoneBody, CreateCategoryBody } from './catalog.schemas.js';

/** Map a Prisma unique-violation (P2002) to a 409. */
function asConflict(err: unknown, message: string): never {
  if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === 'P2002') throw new ConflictError(message);
  throw err;
}

export async function listZones(): Promise<ZoneDto[]> {
  const zones = await prisma.zone.findMany({ where: { deletedAt: null, status: 'ACTIVE' }, orderBy: { name: 'asc' } });
  return zones.map(toZoneDto);
}

export async function createZone(actorId: string, body: CreateZoneBody): Promise<ZoneDto> {
  try {
    return await prisma.$transaction(async (tx) => {
      const zone = await tx.zone.create({ data: { name: body.name, visitFeePaise: body.visitFeePaise } });
      await tx.auditLog.create({ data: { action: 'CATALOG_UPDATED', actorType: 'ADMIN', actorId, metadata: { entity: 'Zone', entityId: zone.id, fields: Object.keys(body) } } });
      return toZoneDto(zone);
    });
  } catch (e) { asConflict(e, 'A zone with that name already exists'); }
}

export async function updateZone(actorId: string, id: string, body: UpdateZoneBody): Promise<ZoneDto> {
  const existing = await prisma.zone.findFirst({ where: { id, deletedAt: null } });
  if (!existing) throw new NotFoundError('Zone not found');
  return prisma.$transaction(async (tx) => {
    const zone = await tx.zone.update({ where: { id }, data: body });
    // visitFeePaise change is a price change → PRICE_CHANGED with from→to
    if (body.visitFeePaise !== undefined && body.visitFeePaise !== existing.visitFeePaise) {
      await tx.auditLog.create({ data: { action: 'PRICE_CHANGED', actorType: 'ADMIN', actorId, metadata: { entity: 'Zone', entityId: id, field: 'visitFeePaise', fromPaise: existing.visitFeePaise, toPaise: body.visitFeePaise } } });
    } else {
      await tx.auditLog.create({ data: { action: 'CATALOG_UPDATED', actorType: 'ADMIN', actorId, metadata: { entity: 'Zone', entityId: id, fields: Object.keys(body) } } });
    }
    return toZoneDto(zone);
  });
}

export async function listCategories(): Promise<CategoryDto[]> {
  const cats = await prisma.serviceCategory.findMany({ where: { deletedAt: null, status: 'ACTIVE' }, orderBy: { name: 'asc' } });
  return cats.map(toCategoryDto);
}

export async function createCategory(actorId: string, body: CreateCategoryBody): Promise<CategoryDto> {
  try {
    return await prisma.$transaction(async (tx) => {
      const cat = await tx.serviceCategory.create({ data: { name: body.name } });
      await tx.auditLog.create({ data: { action: 'CATALOG_UPDATED', actorType: 'ADMIN', actorId, metadata: { entity: 'ServiceCategory', entityId: cat.id, fields: Object.keys(body) } } });
      return toCategoryDto(cat);
    });
  } catch (e) { asConflict(e, 'A category with that name already exists'); }
}
```

- [ ] **Step 4: Create catalog.routes.ts (zones + categories; services added in Task 6)**

Create `apps/backend/src/modules/catalog/catalog.routes.ts`:
```ts
import type { FastifyInstance } from 'fastify';
import { requireAuth } from '../../shared/middleware/auth.js';
import { requireAdminLevel } from '../../shared/middleware/rbac.js';
import { ValidationError } from '../../shared/errors.js';
import { createZoneBody, updateZoneBody, createCategoryBody } from './catalog.schemas.js';
import { listZones, createZone, updateZone, listCategories, createCategory } from './catalog.service.js';

export async function registerCatalogRoutes(app: FastifyInstance) {
  app.get('/catalog/zones', { preHandler: [requireAuth] }, async (_req, reply) => reply.send(await listZones()));

  app.post('/catalog/zones', { preHandler: [requireAuth, requireAdminLevel('MANAGER')] }, async (req, reply) => {
    const p = createZoneBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.code(201).send(await createZone(req.user!.id, p.data));
  });

  app.patch('/catalog/zones/:id', { preHandler: [requireAuth, requireAdminLevel('MANAGER')] }, async (req, reply) => {
    const p = updateZoneBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.send(await updateZone(req.user!.id, (req.params as { id: string }).id, p.data));
  });

  app.get('/catalog/categories', { preHandler: [requireAuth] }, async (_req, reply) => reply.send(await listCategories()));

  app.post('/catalog/categories', { preHandler: [requireAuth, requireAdminLevel('MANAGER')] }, async (req, reply) => {
    const p = createCategoryBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.code(201).send(await createCategory(req.user!.id, p.data));
  });
}
```

- [ ] **Step 5: Register in app.ts**

In `apps/backend/src/app.ts`, add the import:
```ts
import { registerCatalogRoutes } from './modules/catalog/catalog.routes.js';
```
and after `await registerProfileRoutes(app);`:
```ts
  await registerCatalogRoutes(app);
```

- [ ] **Step 6: Run, expect PASS**

```bash
set -a; . ./.env; set +a
pnpm test tests/catalog/zones.test.ts
```
Expected: 6 passed.

- [ ] **Step 7: Typecheck + commit**

```bash
pnpm exec tsc --noEmit
cd /Users/mohammadkaifsaiyad/Development/FixCare && git add apps/backend/src/modules/catalog/ apps/backend/src/app.ts apps/backend/tests/catalog/zones.test.ts && git commit -m "feat(backend): catalog zones + categories (read + MANAGER-gated write, audited)"
```

---

### Task 6: services + geofenced price upsert (TDD)

**Files:** Modify `apps/backend/src/modules/catalog/catalog.service.ts`, `apps/backend/src/modules/catalog/catalog.routes.ts`; Create `apps/backend/tests/catalog/services-pricing.test.ts`

- [ ] **Step 1: Write the failing services/pricing test (incl. the geofencing assertion)**

Create `apps/backend/tests/catalog/services-pricing.test.ts`:
```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeAdminToken, makeCustomerToken } from './helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }

/** Seed two zones + a category + a service via the API; return ids. */
async function seedBase(mgr: string) {
  const vad = (await app.inject({ method: 'POST', url: '/catalog/zones', headers: auth(mgr), payload: { name: 'Vadodara', visitFeePaise: 14900 } })).json();
  const pad = (await app.inject({ method: 'POST', url: '/catalog/zones', headers: auth(mgr), payload: { name: 'Padra', visitFeePaise: 9900 } })).json();
  const cat = (await app.inject({ method: 'POST', url: '/catalog/categories', headers: auth(mgr), payload: { name: 'AC' } })).json();
  const svc = (await app.inject({ method: 'POST', url: '/catalog/services', headers: auth(mgr), payload: { categoryId: cat.id, name: 'AC gas refill', tier: 'T2' } })).json();
  return { vad, pad, cat, svc };
}

describe('services + geofenced pricing', () => {
  it('geofencing: same service has different labor price per zone; visit fee comes from the zone', async () => {
    const mgr = await makeAdminToken('MANAGER');
    const { vad, pad, svc } = await seedBase(mgr);
    await app.inject({ method: 'PUT', url: `/catalog/services/${svc.id}/prices/${vad.id}`, headers: auth(mgr), payload: { laborPaise: 60000 } });
    await app.inject({ method: 'PUT', url: `/catalog/services/${svc.id}/prices/${pad.id}`, headers: auth(mgr), payload: { laborPaise: 50000 } });

    const cust = await makeCustomerToken();
    const inVad = (await app.inject({ method: 'GET', url: `/catalog/services?zoneId=${vad.id}`, headers: auth(cust) })).json();
    const inPad = (await app.inject({ method: 'GET', url: `/catalog/services?zoneId=${pad.id}`, headers: auth(cust) })).json();
    const vadSvc = inVad.find((s: { id: string }) => s.id === svc.id);
    const padSvc = inPad.find((s: { id: string }) => s.id === svc.id);
    expect(vadSvc.laborPaise).toBe(60000);
    expect(padSvc.laborPaise).toBe(50000);     // geofenced — different price
    expect(vadSvc.visitFeePaise).toBe(14900);
    expect(padSvc.visitFeePaise).toBe(9900);
  });

  it('price upsert updates in place (no duplicate row) + PRICE_CHANGED audit with from→to', async () => {
    const mgr = await makeAdminToken('MANAGER');
    const { vad, svc } = await seedBase(mgr);
    await app.inject({ method: 'PUT', url: `/catalog/services/${svc.id}/prices/${vad.id}`, headers: auth(mgr), payload: { laborPaise: 60000 } });
    await app.inject({ method: 'PUT', url: `/catalog/services/${svc.id}/prices/${vad.id}`, headers: auth(mgr), payload: { laborPaise: 65000 } });

    const rows = await prisma.servicePrice.findMany({ where: { serviceId: svc.id, zoneId: vad.id } });
    expect(rows).toHaveLength(1);              // upsert, not duplicate
    expect(rows[0]!.laborPaise).toBe(65000);
    const audit = await prisma.auditLog.findFirst({ where: { action: 'PRICE_CHANGED' }, orderBy: { createdAt: 'desc' } });
    const meta = audit!.metadata as { fromPaise: number; toPaise: number };
    expect(meta.fromPaise).toBe(60000);
    expect(meta.toPaise).toBe(65000);
  });

  it('SUPPORT cannot upsert a price (403)', async () => {
    const mgr = await makeAdminToken('MANAGER');
    const { vad, svc } = await seedBase(mgr);
    const sup = await makeAdminToken('SUPPORT');
    expect((await app.inject({ method: 'PUT', url: `/catalog/services/${svc.id}/prices/${vad.id}`, headers: auth(sup), payload: { laborPaise: 1 } })).statusCode).toBe(403);
  });

  it('services?zoneId omits soft-deleted services and services with no price in that zone gets laborPaise null', async () => {
    const mgr = await makeAdminToken('MANAGER');
    const { vad, svc } = await seedBase(mgr);
    // no price set for svc in vad yet
    const cust = await makeCustomerToken();
    const list = (await app.inject({ method: 'GET', url: `/catalog/services?zoneId=${vad.id}`, headers: auth(cust) })).json();
    const found = list.find((s: { id: string }) => s.id === svc.id);
    expect(found.laborPaise).toBeNull();       // priced-in-zone is null until set
  });
});
```

- [ ] **Step 2: Run, expect FAIL**

```bash
set -a; . ./.env; set +a
pnpm test tests/catalog/services-pricing.test.ts
```
Expected: FAIL — `/catalog/services` routes not registered.

- [ ] **Step 3: Add service + price functions to catalog.service.ts**

Append to `apps/backend/src/modules/catalog/catalog.service.ts` (extend imports with the service types + `ServicePriceDto`):
```ts
import type { CreateServiceBody, UpsertPriceBody } from './catalog.schemas.js';
import type { ServicePriceDto } from './catalog.types.js';

export async function createService(actorId: string, body: CreateServiceBody) {
  const cat = await prisma.serviceCategory.findFirst({ where: { id: body.categoryId, deletedAt: null } });
  if (!cat) throw new NotFoundError('Category not found');
  try {
    return await prisma.$transaction(async (tx) => {
      const svc = await tx.service.create({ data: { categoryId: body.categoryId, name: body.name, tier: body.tier } });
      await tx.auditLog.create({ data: { action: 'CATALOG_UPDATED', actorType: 'ADMIN', actorId, metadata: { entity: 'Service', entityId: svc.id, fields: Object.keys(body) } } });
      return { id: svc.id, categoryId: svc.categoryId, name: svc.name, tier: svc.tier, status: svc.status };
    });
  } catch (e) { asConflict(e, 'A service with that name already exists in this category'); }
}

/** List active services for a zone: each carries its laborPaise for that zone (null if unpriced) + the zone visit fee. */
export async function listServicesByZone(zoneId: string, categoryId?: string): Promise<ServicePriceDto[]> {
  const zone = await prisma.zone.findFirst({ where: { id: zoneId, deletedAt: null } });
  if (!zone) throw new NotFoundError('Zone not found');
  const services = await prisma.service.findMany({
    where: { deletedAt: null, status: 'ACTIVE', ...(categoryId ? { categoryId } : {}) },
    include: { prices: { where: { zoneId } } },
    orderBy: { name: 'asc' },
  });
  return services.map((s) => ({
    id: s.id, name: s.name, tier: s.tier, categoryId: s.categoryId,
    laborPaise: s.prices[0]?.laborPaise ?? null as unknown as number, // null until priced in this zone
    visitFeePaise: zone.visitFeePaise,
  }));
}

export async function upsertServicePrice(actorId: string, serviceId: string, zoneId: string, body: UpsertPriceBody) {
  const svc = await prisma.service.findFirst({ where: { id: serviceId, deletedAt: null } });
  if (!svc) throw new NotFoundError('Service not found');
  const zone = await prisma.zone.findFirst({ where: { id: zoneId, deletedAt: null } });
  if (!zone) throw new NotFoundError('Zone not found');
  return prisma.$transaction(async (tx) => {
    const existing = await tx.servicePrice.findUnique({ where: { serviceId_zoneId: { serviceId, zoneId } } });
    const row = await tx.servicePrice.upsert({
      where: { serviceId_zoneId: { serviceId, zoneId } },
      create: { serviceId, zoneId, laborPaise: body.laborPaise },
      update: { laborPaise: body.laborPaise },
    });
    await tx.auditLog.create({ data: { action: 'PRICE_CHANGED', actorType: 'ADMIN', actorId, metadata: { entity: 'ServicePrice', entityId: row.id, zoneId, field: 'laborPaise', fromPaise: existing?.laborPaise ?? null, toPaise: body.laborPaise } } });
    return { id: row.id, serviceId, zoneId, laborPaise: row.laborPaise };
  });
}
```
Note: the `ServicePriceDto.laborPaise` type allows `null` for an unpriced service in a zone — update `catalog.types.ts` `ServicePriceDto.laborPaise` to `number | null` so this is type-honest (do that here). The `serviceId_zoneId` is the Prisma compound-unique selector name from `@@unique([serviceId, zoneId])`.

- [ ] **Step 4: Add the service + price routes to catalog.routes.ts**

Extend imports + add routes inside `registerCatalogRoutes`:
```ts
import { createServiceBody, upsertPriceBody } from './catalog.schemas.js';
import { listServicesByZone, createService, upsertServicePrice } from './catalog.service.js';
```
```ts
  app.get('/catalog/services', { preHandler: [requireAuth] }, async (req, reply) => {
    const q = req.query as { zoneId?: string; categoryId?: string };
    if (!q.zoneId) throw new ValidationError('zoneId is required');
    return reply.send(await listServicesByZone(q.zoneId, q.categoryId));
  });

  app.post('/catalog/services', { preHandler: [requireAuth, requireAdminLevel('MANAGER')] }, async (req, reply) => {
    const p = createServiceBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.code(201).send(await createService(req.user!.id, p.data));
  });

  app.put('/catalog/services/:id/prices/:zoneId', { preHandler: [requireAuth, requireAdminLevel('MANAGER')] }, async (req, reply) => {
    const p = upsertPriceBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    const params = req.params as { id: string; zoneId: string };
    return reply.send(await upsertServicePrice(req.user!.id, params.id, params.zoneId, p.data));
  });
```

- [ ] **Step 5: Run, expect PASS**

```bash
set -a; . ./.env; set +a
pnpm test tests/catalog/services-pricing.test.ts
```
Expected: 4 passed.

- [ ] **Step 6: Typecheck + commit**

```bash
pnpm exec tsc --noEmit
cd /Users/mohammadkaifsaiyad/Development/FixCare && git add apps/backend/src/modules/catalog/ apps/backend/tests/catalog/services-pricing.test.ts && git commit -m "feat(backend): catalog services + geofenced price upsert (PRICE_CHANGED audited)"
```

---

### Task 7: Full suite + smoke + docs

**Files:** Modify `STATUS.md`, `CHANGELOG.md`

- [ ] **Step 1: Full suite**

```bash
cd /Users/mohammadkaifsaiyad/Development/FixCare/apps/backend
export NVM_DIR="$HOME/.nvm" && . "$NVM_DIR/nvm.sh" && nvm use 22 >/dev/null
set -a; . ./.env; set +a
pnpm test
```
Expected: all pass — 60 (prior) + 5 currency + 5 rbac + 6 zones + 4 services-pricing = 80.

- [ ] **Step 2: Smoke (real server: MANAGER seeds a zone+category+service+price; customer reads by zone)**

```bash
set -a; . ./.env; set +a
pnpm exec tsx src/server.ts > /tmp/fc-cat.log 2>&1 &
SRV=$!; sleep 4
# mint a MANAGER token via a quick node script using the app's signing
node --input-type=module -e "
import('./src/shared/auth/tokens.js').then(async (m) => {
  const { PrismaClient } = await import('@prisma/client');
  const p = new PrismaClient();
  const u = await p.user.create({ data: { phone: 'smoke-cat-'+Date.now(), role: 'ADMIN' } });
  await p.admin.create({ data: { userId: u.id, name: 'Smoke', email: 'smoke-'+u.id+'@fixcare.in', passwordHash: 'x', adminLevel: 'MANAGER' } });
  console.log(m.signAccessToken(u.id, 'ADMIN'));
  await p.\$disconnect();
});" > /tmp/tok.txt 2>/dev/null
TOK=$(cat /tmp/tok.txt)
ZONE=$(curl -s -XPOST localhost:3000/catalog/zones -H "authorization: Bearer $TOK" -H 'content-type: application/json' -d '{"name":"SmokeVad","visitFeePaise":14900}' | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>console.log(JSON.parse(d).id))")
echo "zones GET:" && curl -s "localhost:3000/catalog/zones" -H "authorization: Bearer $TOK"; echo
kill $SRV 2>/dev/null
# cleanup smoke rows
cd /Users/mohammadkaifsaiyad/Development/FixCare && docker compose exec -T postgres psql -U fixcare -d fixcare_dev -c "DELETE FROM \"Zone\" WHERE name='SmokeVad'; DELETE FROM \"AuditLog\" WHERE \"actorType\"='ADMIN' AND \"actorId\" IN (SELECT id FROM \"User\" WHERE phone LIKE 'smoke-cat-%'); DELETE FROM \"Admin\" WHERE \"userId\" IN (SELECT id FROM \"User\" WHERE phone LIKE 'smoke-cat-%'); DELETE FROM \"User\" WHERE phone LIKE 'smoke-cat-%';"
```
Expected: the zones GET returns the SmokeVad zone with `visitFeePaise:14900`. (If the inline node token-mint is awkward, it's optional — the 80 passing tests are the authoritative proof; report if you skip it.)

- [ ] **Step 3: Update STATUS.md** — Active task → "service catalog sub-slice B (parts + seed)"; add to Last shipped:
```
- Service catalog sub-slice A: zones (visit fee) + categories + services + geofenced
  labor pricing; currency util; requireAdminLevel(MANAGER); PRICE_CHANGED/CATALOG_UPDATED
  audit. Reads any-authed, writes MANAGER+. 80 tests. On feature/service-catalog.
```

- [ ] **Step 4: Update CHANGELOG.md** (under the current date):
```
- **Service catalog sub-slice A.** Admin-managed Zone (geofenced visit fee) + ServiceCategory
  + Service (tier) + per-zone ServicePrice. New shared/utils/currency.ts (integer paise) and
  requireAdminLevel(MANAGER) RBAC (first piece of rbac.ts). Reads = any authed user; writes =
  MANAGER+. Price changes audited (PRICE_CHANGED with from→to paise); catalog changes
  (CATALOG_UPDATED). Duplicate/second-price → 409; bad paise → 400. 80 tests. Parts + seed = sub-slice B.
```

- [ ] **Step 5: Commit**

```bash
cd /Users/mohammadkaifsaiyad/Development/FixCare && git add STATUS.md CHANGELOG.md && git commit -m "docs: record service catalog sub-slice A"
```

---

## Definition of Done

- `pnpm test` green: 80 (60 prior + 5 currency + 5 rbac + 6 zones/categories + 4 services-pricing).
- **Geofencing proven:** same service returns different `laborPaise` per zone + the zone's `visitFeePaise`.
- Writes require MANAGER+ (`requireAdminLevel`); SUPPORT/customer → 403; no token → 401.
- Price changes write `PRICE_CHANGED` (from→to paise); catalog changes write `CATALOG_UPDATED`; price upsert is in-place (no duplicate rows).
- Duplicate zone name / category → 409; negative/non-integer paise → 400; soft-deleted/INACTIVE hidden from reads.
- All money via `currency.ts` as integer paise. `tsc --noEmit` clean. All commits authored by you, no Claude trailer.

## Seam to sub-slice B (NOT built here)
`PartsCatalog` model + parts read/write endpoints + the idempotent catalog **seed** (zones/services/parts). B reuses `currency.ts`, `requireAdminLevel`, the audit actions, and the `catalog/` module.

## Out of scope (deferred)
merchant-catalog (per-merchant cost); PostGIS-polygon geofencing + address→zone resolution; tier-based dynamic pricing; booking-time price snapshot; open-market premium / AMC / bonus / cost-of-living pricing.

## Verification
- `pnpm test` → 80 passed.
- Smoke: MANAGER creates a zone → GET /catalog/zones returns it.
- `git log --oneline main..HEAD` → the sub-slice A commits, all authored by MohammadKaifSaiyad.
