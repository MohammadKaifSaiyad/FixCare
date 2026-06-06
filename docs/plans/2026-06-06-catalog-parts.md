# Service Catalog Sub-Slice B — Parts Master + Catalog Seed — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the platform-set `PartsCatalog` (ceiling price, zone-agnostic) with read/write endpoints, plus an idempotent catalog seed (Vadodara/Padra zones + sample categories/services/prices + parts) — completing the service-catalog module.

**Architecture:** Extends the existing `apps/backend/src/modules/catalog/` module (route → service → DTO, auth-first, MANAGER+ on writes) and the existing `prisma/seed.ts`. Parts are zone-agnostic: a single `ceilingPricePaise` per SKU, optionally tied to a `ServiceCategory`. Price-affecting writes audit `PRICE_CHANGED`; structural writes audit `CATALOG_UPDATED` — same transaction as the mutation, identical to sub-slice A. Money is integer paise throughout.

**Tech Stack:** Node 22, Fastify 5, Prisma 6 + PostgreSQL 16, Zod, Vitest (`app.inject()`), TypeScript strict. Branch: `feature/catalog-parts` (already cut off `main`).

**Design reference:** `docs/designs/2026-06-04-service-catalog-design.md` (decisions 1, 9, 11; schema `PartsCatalog`; endpoints `GET/POST/PATCH /catalog/parts`; seed scope).

**Golden Rules in play:** #4 catalog prices only (platform-set ceiling, no technician discretion), money is integer paise, #5 price/catalog mutations audited in-transaction.

---

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `apps/backend/prisma/schema.prisma` | `PartsCatalog` model + `ServiceCategory.parts` back-relation | Modify |
| `apps/backend/prisma/migrations/<ts>_parts_catalog/` | The generated migration | Create (via `prisma migrate dev`) |
| `apps/backend/tests/schema/helpers.ts` | Add `PartsCatalog` to the TRUNCATE list | Modify |
| `apps/backend/src/modules/catalog/catalog.schemas.ts` | `createPartBody`, `updatePartBody` Zod schemas | Modify |
| `apps/backend/src/modules/catalog/catalog.types.ts` | `PartDto` + `toPartDto` | Modify |
| `apps/backend/src/modules/catalog/catalog.service.ts` | `listParts`, `createPart`, `updatePart` | Modify |
| `apps/backend/src/modules/catalog/catalog.routes.ts` | `GET/POST/PATCH /catalog/parts` | Modify |
| `apps/backend/tests/catalog/parts.test.ts` | Parts endpoint tests | Create |
| `apps/backend/prisma/seed.ts` | `seedCatalog(prisma)` idempotent | Modify |
| `apps/backend/tests/catalog/seed-catalog.test.ts` | Seed idempotency + content tests | Create |

All paths below are relative to repo root `/Users/mohammadkaifsaiyad/Development/FixCare`. Run `pnpm` commands from `apps/backend`.

---

## Task 1: Add the `PartsCatalog` model + migration

**Files:**
- Modify: `apps/backend/prisma/schema.prisma` (CATALOG section, after `ServicePrice` ~line 242; and `ServiceCategory` ~line 207)
- Modify: `apps/backend/tests/schema/helpers.ts:14` (TRUNCATE list)
- Create: `apps/backend/prisma/migrations/<timestamp>_parts_catalog/migration.sql` (generated)

- [ ] **Step 1: Add the `parts` back-relation to `ServiceCategory`**

In `apps/backend/prisma/schema.prisma`, the `ServiceCategory` model currently ends:

```prisma
model ServiceCategory {
  id        String        @id @default(uuid())
  name      String        @unique
  status    CatalogStatus @default(ACTIVE)
  createdAt DateTime      @default(now())
  updatedAt DateTime      @updatedAt
  deletedAt DateTime?
  services  Service[]
}
```

Add the `parts` relation line after `services`:

```prisma
  services  Service[]
  parts     PartsCatalog[]
}
```

- [ ] **Step 2: Add the `PartsCatalog` model**

In the same file, after the `ServicePrice` model (before `enum CatalogStatus`), add:

```prisma
model PartsCatalog {
  id                String           @id @default(uuid())
  sku               String           @unique
  name              String
  categoryId        String?
  category          ServiceCategory? @relation(fields: [categoryId], references: [id])
  ceilingPricePaise Int                                 // platform-set catalog price (zone-agnostic)
  status            CatalogStatus    @default(ACTIVE)
  createdAt         DateTime         @default(now())
  updatedAt         DateTime         @updatedAt
  deletedAt         DateTime?
  @@index([categoryId])
}
```

- [ ] **Step 3: Add `PartsCatalog` to the test TRUNCATE list**

In `apps/backend/tests/schema/helpers.ts`, the `resetDb` TRUNCATE statement currently reads:

```ts
    'TRUNCATE TABLE "ServicePrice","Service","ServiceCategory","Zone","AuditLog","RefreshToken","Admin","Merchant","Technician","Customer","User" RESTART IDENTITY CASCADE;'
```

Add `"PartsCatalog"` to the front of the table list (before `"ServicePrice"`):

```ts
    'TRUNCATE TABLE "PartsCatalog","ServicePrice","Service","ServiceCategory","Zone","AuditLog","RefreshToken","Admin","Merchant","Technician","Customer","User" RESTART IDENTITY CASCADE;'
```

- [ ] **Step 4: Generate and apply the migration**

Run (from `apps/backend`):

```bash
pnpm prisma migrate dev --name parts_catalog
```

Expected: a new `prisma/migrations/<timestamp>_parts_catalog/migration.sql` is created and applied to `fixcare_dev`; Prisma Client regenerates. The SQL should `CREATE TABLE "PartsCatalog"` with a unique index on `sku`, an index on `categoryId`, and an FK `categoryId → ServiceCategory(id)`. No `DROP`/destructive ops.

- [ ] **Step 5: Verify the migration is additive (no destructive ops)**

Run:

```bash
grep -iE 'DROP|TRUNCATE|ALTER COLUMN' prisma/migrations/*_parts_catalog/migration.sql || echo "clean: additive only"
```

Expected: `clean: additive only` (the new-table migration contains only `CREATE TABLE` / `CREATE INDEX` / `ADD CONSTRAINT`).

- [ ] **Step 6: Commit**

```bash
git add apps/backend/prisma/schema.prisma apps/backend/prisma/migrations apps/backend/tests/schema/helpers.ts
git commit -m "feat(backend): add PartsCatalog model + migration (catalog sub-slice B)"
```

---

## Task 2: Parts DTO + Zod schemas

**Files:**
- Modify: `apps/backend/src/modules/catalog/catalog.types.ts`
- Modify: `apps/backend/src/modules/catalog/catalog.schemas.ts`

- [ ] **Step 1: Add `PartDto` + `toPartDto`**

In `apps/backend/src/modules/catalog/catalog.types.ts`, extend the import on line 1 and append the DTO + mapper at the end of the file.

Change line 1 from:

```ts
import type { Zone, ServiceCategory, Service } from '@prisma/client';
```

to:

```ts
import type { Zone, ServiceCategory, Service, PartsCatalog } from '@prisma/client';
```

Append at end of file:

```ts
export interface PartDto {
  id: string;
  sku: string;
  name: string;
  categoryId: string | null;
  ceilingPricePaise: number;
  status: PartsCatalog['status'];
}

export function toPartDto(p: PartsCatalog): PartDto {
  return { id: p.id, sku: p.sku, name: p.name, categoryId: p.categoryId, ceilingPricePaise: p.ceilingPricePaise, status: p.status };
}
```

- [ ] **Step 2: Add `createPartBody` + `updatePartBody` Zod schemas**

In `apps/backend/src/modules/catalog/catalog.schemas.ts`, append after `upsertPriceBody` (reuse the existing `paise` schema defined at the top of the file):

```ts
export const createPartBody = z
  .object({
    sku: z.string().min(1),
    name: z.string().min(1),
    categoryId: z.string().min(1).optional(),
    ceilingPricePaise: paise,
  })
  .strict();
export type CreatePartBody = z.infer<typeof createPartBody>;

export const updatePartBody = z
  .object({
    name: z.string().min(1),
    categoryId: z.string().min(1),
    ceilingPricePaise: paise,
    status: z.enum(['ACTIVE', 'INACTIVE']),
  })
  .partial()
  .strict()
  .refine((b) => Object.keys(b).length > 0, { message: 'At least one field is required' });
export type UpdatePartBody = z.infer<typeof updatePartBody>;
```

Note: `sku` is intentionally **not** updatable (it is the stable unique key) — matches how `ServicePrice` keys are immutable. `categoryId` in update is required-if-present (min 1); to detach a part from a category, that is out of scope for V1.

- [ ] **Step 3: Type-check**

Run (from `apps/backend`):

```bash
pnpm build
```

Expected: PASS (no `any`, no unused). If `PartsCatalog` type is missing, re-run `pnpm prisma generate`.

- [ ] **Step 4: Commit**

```bash
git add apps/backend/src/modules/catalog/catalog.types.ts apps/backend/src/modules/catalog/catalog.schemas.ts
git commit -m "feat(backend): parts DTO + Zod schemas (catalog sub-slice B)"
```

---

## Task 3: Parts read endpoint — `GET /catalog/parts`

**Files:**
- Modify: `apps/backend/src/modules/catalog/catalog.service.ts`
- Modify: `apps/backend/src/modules/catalog/catalog.routes.ts`
- Create: `apps/backend/tests/catalog/parts.test.ts`

- [ ] **Step 1: Write the failing test**

Create `apps/backend/tests/catalog/parts.test.ts`:

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

describe('parts catalog — reads', () => {
  it('MANAGER creates a part; any authed user reads it (active only)', async () => {
    const mgr = await makeAdminToken('MANAGER');
    const create = await app.inject({ method: 'POST', url: '/catalog/parts', headers: auth(mgr), payload: { sku: 'AC-COMP-1.5T', name: 'AC compressor 1.5T', ceilingPricePaise: 850000 } });
    expect(create.statusCode).toBe(201);
    const cust = await makeCustomerToken();
    const list = await app.inject({ method: 'GET', url: '/catalog/parts', headers: auth(cust) });
    expect(list.statusCode).toBe(200);
    expect(list.json()).toHaveLength(1);
    expect(list.json()[0]).toMatchObject({ sku: 'AC-COMP-1.5T', ceilingPricePaise: 850000, categoryId: null });
  });

  it('GET /catalog/parts requires a token → 401', async () => {
    const res = await app.inject({ method: 'GET', url: '/catalog/parts' });
    expect(res.statusCode).toBe(401);
  });

  it('INACTIVE and soft-deleted parts are hidden from reads', async () => {
    const mgr = await makeAdminToken('MANAGER');
    const active = (await app.inject({ method: 'POST', url: '/catalog/parts', headers: auth(mgr), payload: { sku: 'A', name: 'Active', ceilingPricePaise: 100 } })).json();
    const inactive = (await app.inject({ method: 'POST', url: '/catalog/parts', headers: auth(mgr), payload: { sku: 'B', name: 'Inactive', ceilingPricePaise: 200 } })).json();
    const deleted = (await app.inject({ method: 'POST', url: '/catalog/parts', headers: auth(mgr), payload: { sku: 'C', name: 'Deleted', ceilingPricePaise: 300 } })).json();
    await prisma.partsCatalog.update({ where: { id: inactive.id }, data: { status: 'INACTIVE' } });
    await prisma.partsCatalog.update({ where: { id: deleted.id }, data: { deletedAt: new Date() } });
    const cust = await makeCustomerToken();
    const ids = (await app.inject({ method: 'GET', url: '/catalog/parts', headers: auth(cust) })).json().map((p: { id: string }) => p.id);
    expect(ids).toEqual([active.id]);
  });

  it('filters by categoryId', async () => {
    const mgr = await makeAdminToken('MANAGER');
    const cat = (await app.inject({ method: 'POST', url: '/catalog/categories', headers: auth(mgr), payload: { name: 'AC' } })).json();
    await app.inject({ method: 'POST', url: '/catalog/parts', headers: auth(mgr), payload: { sku: 'IN-CAT', name: 'In cat', categoryId: cat.id, ceilingPricePaise: 100 } });
    await app.inject({ method: 'POST', url: '/catalog/parts', headers: auth(mgr), payload: { sku: 'NO-CAT', name: 'No cat', ceilingPricePaise: 200 } });
    const cust = await makeCustomerToken();
    const list = (await app.inject({ method: 'GET', url: `/catalog/parts?categoryId=${cat.id}`, headers: auth(cust) })).json();
    expect(list).toHaveLength(1);
    expect(list[0].sku).toBe('IN-CAT');
  });
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run (from `apps/backend`):

```bash
pnpm test -- tests/catalog/parts.test.ts
```

Expected: FAIL — `POST /catalog/parts` returns 404 (route not registered) so the first assertion (`201`) fails.

- [ ] **Step 3: Add `listParts` to the service**

In `apps/backend/src/modules/catalog/catalog.service.ts`, extend the type import on line 4 to add `toPartDto` and `PartDto`:

```ts
import { toZoneDto, toCategoryDto, toPartDto, type ZoneDto, type CategoryDto, type ServicePriceDto, type PartDto } from './catalog.types.js';
```

and extend the schemas import on line 5 to add the part body types:

```ts
import type { CreateZoneBody, UpdateZoneBody, CreateCategoryBody, CreateServiceBody, UpsertPriceBody, CreatePartBody, UpdatePartBody } from './catalog.schemas.js';
```

Append at the end of the file:

```ts
export async function listParts(categoryId?: string): Promise<PartDto[]> {
  const parts = await prisma.partsCatalog.findMany({
    where: { deletedAt: null, status: 'ACTIVE', ...(categoryId ? { categoryId } : {}) },
    orderBy: { name: 'asc' },
  });
  return parts.map(toPartDto);
}
```

- [ ] **Step 4: Register the read route**

In `apps/backend/src/modules/catalog/catalog.routes.ts`, extend the service import (line 6) to add `listParts`, `createPart`, `updatePart` and the schemas import (line 5) to add `createPartBody`, `updatePartBody` (the create/update functions land in Task 4, but import them now to keep one edit per import line):

Change line 5 to:

```ts
import { createZoneBody, updateZoneBody, createCategoryBody, createServiceBody, upsertPriceBody, createPartBody, updatePartBody } from './catalog.schemas.js';
```

Change line 6 to:

```ts
import { listZones, createZone, updateZone, listCategories, createCategory, listServicesByZone, createService, upsertServicePrice, listParts, createPart, updatePart } from './catalog.service.js';
```

Add the read route before the closing `}` of `registerCatalogRoutes`:

```ts
  app.get('/catalog/parts', { preHandler: [requireAuth] }, async (req, reply) => {
    const q = req.query as { categoryId?: string };
    return reply.send(await listParts(q.categoryId));
  });
```

> The POST/PATCH routes are added in Task 4; this task only adds GET. The imports reference `createPart`/`updatePart`/`createPartBody`/`updatePartBody` which don't exist yet — so build will fail until Task 4. To keep this task green on its own, add the POST and PATCH routes from Task 4 Step 3 **now as well** (they share the import line). The parts.test.ts in this task already exercises POST, so registering POST here is required for the test to pass.

**Action:** also add these two write routes now (their service functions come in Task 4 — so complete Task 4 Steps 1-2 before re-running tests, OR fold Task 4 into this task. Recommended: do Tasks 3 and 4 together as written below.)

```ts
  app.post('/catalog/parts', { preHandler: [requireAuth, requireAdminLevel('MANAGER')] }, async (req, reply) => {
    const p = createPartBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.code(201).send(await createPart(req.user!.id, p.data));
  });

  app.patch('/catalog/parts/:id', { preHandler: [requireAuth, requireAdminLevel('MANAGER')] }, async (req, reply) => {
    const p = updatePartBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.send(await updatePart(req.user!.id, (req.params as { id: string }).id, p.data));
  });
```

(`requireAdminLevel`, `requireAuth`, `ValidationError` are already imported at the top of the file.)

- [ ] **Step 5: Implement `createPart` + `updatePart` (from Task 4) so the test passes**

Proceed to Task 4 Steps 1-2 (add `createPart`/`updatePart` to the service), then return here.

- [ ] **Step 6: Run the test to verify it passes**

Run:

```bash
pnpm test -- tests/catalog/parts.test.ts
```

Expected: PASS (all read tests, plus the create/inactive/filter tests). If `createPart` is not yet implemented, the `201` assertions fail — finish Task 4 first.

---

## Task 4: Parts write endpoints — `POST` + `PATCH /catalog/parts` (with audit)

**Files:**
- Modify: `apps/backend/src/modules/catalog/catalog.service.ts`
- Modify: `apps/backend/tests/catalog/parts.test.ts` (add write/audit/conflict tests)

- [ ] **Step 1: Add the write/audit/conflict tests**

Append inside the `describe` block of `apps/backend/tests/catalog/parts.test.ts`:

```ts
  it('SUPPORT cannot create a part → 403', async () => {
    const sup = await makeAdminToken('SUPPORT');
    const res = await app.inject({ method: 'POST', url: '/catalog/parts', headers: auth(sup), payload: { sku: 'X', name: 'X', ceilingPricePaise: 100 } });
    expect(res.statusCode).toBe(403);
  });

  it('duplicate sku → 409', async () => {
    const mgr = await makeAdminToken('MANAGER');
    await app.inject({ method: 'POST', url: '/catalog/parts', headers: auth(mgr), payload: { sku: 'DUP', name: 'A', ceilingPricePaise: 100 } });
    const dup = await app.inject({ method: 'POST', url: '/catalog/parts', headers: auth(mgr), payload: { sku: 'DUP', name: 'B', ceilingPricePaise: 200 } });
    expect(dup.statusCode).toBe(409);
  });

  it('negative or float ceilingPricePaise → 400', async () => {
    const mgr = await makeAdminToken('MANAGER');
    expect((await app.inject({ method: 'POST', url: '/catalog/parts', headers: auth(mgr), payload: { sku: 'N', name: 'N', ceilingPricePaise: -1 } })).statusCode).toBe(400);
    expect((await app.inject({ method: 'POST', url: '/catalog/parts', headers: auth(mgr), payload: { sku: 'F', name: 'F', ceilingPricePaise: 99.5 } })).statusCode).toBe(400);
  });

  it('create writes a CATALOG_UPDATED audit', async () => {
    const mgr = await makeAdminToken('MANAGER');
    const part = (await app.inject({ method: 'POST', url: '/catalog/parts', headers: auth(mgr), payload: { sku: 'AUD', name: 'Aud', ceilingPricePaise: 100 } })).json();
    const audit = await prisma.auditLog.findFirst({ where: { action: 'CATALOG_UPDATED', metadata: { path: ['entityId'], equals: part.id } } });
    expect(audit).toBeTruthy();
    expect((audit!.metadata as { entity: string }).entity).toBe('PartsCatalog');
  });

  it('PATCH changing ceiling price writes a PRICE_CHANGED audit (from→to)', async () => {
    const mgr = await makeAdminToken('MANAGER');
    const part = (await app.inject({ method: 'POST', url: '/catalog/parts', headers: auth(mgr), payload: { sku: 'PC', name: 'Pc', ceilingPricePaise: 1000 } })).json();
    const res = await app.inject({ method: 'PATCH', url: `/catalog/parts/${part.id}`, headers: auth(mgr), payload: { ceilingPricePaise: 1500 } });
    expect(res.statusCode).toBe(200);
    expect(res.json().ceilingPricePaise).toBe(1500);
    const audit = await prisma.auditLog.findFirst({ where: { action: 'PRICE_CHANGED', metadata: { path: ['entityId'], equals: part.id } } });
    expect(audit).toBeTruthy();
    const md = audit!.metadata as { field: string; fromPaise: number; toPaise: number };
    expect(md).toMatchObject({ field: 'ceilingPricePaise', fromPaise: 1000, toPaise: 1500 });
  });

  it('PATCH changing name only writes CATALOG_UPDATED, not PRICE_CHANGED', async () => {
    const mgr = await makeAdminToken('MANAGER');
    const part = (await app.inject({ method: 'POST', url: '/catalog/parts', headers: auth(mgr), payload: { sku: 'NM', name: 'Old', ceilingPricePaise: 1000 } })).json();
    await app.inject({ method: 'PATCH', url: `/catalog/parts/${part.id}`, headers: auth(mgr), payload: { name: 'New' } });
    const priceAudit = await prisma.auditLog.findFirst({ where: { action: 'PRICE_CHANGED', metadata: { path: ['entityId'], equals: part.id } } });
    const catAudit = await prisma.auditLog.findFirst({ where: { action: 'CATALOG_UPDATED', metadata: { path: ['entityId'], equals: part.id }, NOT: { metadata: { path: ['fields'], equals: undefined } } } });
    expect(priceAudit).toBeNull();
    expect(catAudit).toBeTruthy();
  });

  it('PATCH a non-existent or soft-deleted part → 404', async () => {
    const mgr = await makeAdminToken('MANAGER');
    expect((await app.inject({ method: 'PATCH', url: '/catalog/parts/00000000-0000-0000-0000-000000000000', headers: auth(mgr), payload: { name: 'X' } })).statusCode).toBe(404);
    const part = (await app.inject({ method: 'POST', url: '/catalog/parts', headers: auth(mgr), payload: { sku: 'GONE', name: 'Gone', ceilingPricePaise: 100 } })).json();
    await prisma.partsCatalog.update({ where: { id: part.id }, data: { deletedAt: new Date() } });
    expect((await app.inject({ method: 'PATCH', url: `/catalog/parts/${part.id}`, headers: auth(mgr), payload: { name: 'X' } })).statusCode).toBe(404);
  });

  it('PATCH with an unknown categoryId → 404', async () => {
    const mgr = await makeAdminToken('MANAGER');
    const part = (await app.inject({ method: 'POST', url: '/catalog/parts', headers: auth(mgr), payload: { sku: 'CAT', name: 'Cat', ceilingPricePaise: 100 } })).json();
    const res = await app.inject({ method: 'PATCH', url: `/catalog/parts/${part.id}`, headers: auth(mgr), payload: { categoryId: '00000000-0000-0000-0000-000000000000' } });
    expect(res.statusCode).toBe(404);
  });

  it('soft-delete via PATCH status INACTIVE removes it from reads', async () => {
    const mgr = await makeAdminToken('MANAGER');
    const part = (await app.inject({ method: 'POST', url: '/catalog/parts', headers: auth(mgr), payload: { sku: 'DEL', name: 'Del', ceilingPricePaise: 100 } })).json();
    await app.inject({ method: 'PATCH', url: `/catalog/parts/${part.id}`, headers: auth(mgr), payload: { status: 'INACTIVE' } });
    const cust = await makeCustomerToken();
    const list = (await app.inject({ method: 'GET', url: '/catalog/parts', headers: auth(cust) })).json();
    expect(list.find((p: { id: string }) => p.id === part.id)).toBeUndefined();
  });
```

- [ ] **Step 2: Implement `createPart` + `updatePart` in the service**

Append to `apps/backend/src/modules/catalog/catalog.service.ts` (uses the existing `asConflict` helper, `NotFoundError`, and `prisma.$transaction` pattern — identical to `createZone`/`updateZone`):

```ts
export async function createPart(actorId: string, body: CreatePartBody): Promise<PartDto> {
  if (body.categoryId) {
    const cat = await prisma.serviceCategory.findFirst({ where: { id: body.categoryId, deletedAt: null } });
    if (!cat) throw new NotFoundError('Category not found');
  }
  try {
    return await prisma.$transaction(async (tx) => {
      const part = await tx.partsCatalog.create({
        data: { sku: body.sku, name: body.name, categoryId: body.categoryId ?? null, ceilingPricePaise: body.ceilingPricePaise },
      });
      await tx.auditLog.create({ data: { action: 'CATALOG_UPDATED', actorType: 'ADMIN', actorId, metadata: { entity: 'PartsCatalog', entityId: part.id, fields: Object.keys(body) } } });
      return toPartDto(part);
    });
  } catch (e) { asConflict(e, 'A part with that SKU already exists'); }
}

export async function updatePart(actorId: string, id: string, body: UpdatePartBody): Promise<PartDto> {
  const existing = await prisma.partsCatalog.findFirst({ where: { id, deletedAt: null } });
  if (!existing) throw new NotFoundError('Part not found');
  if (body.categoryId) {
    const cat = await prisma.serviceCategory.findFirst({ where: { id: body.categoryId, deletedAt: null } });
    if (!cat) throw new NotFoundError('Category not found');
  }
  return prisma.$transaction(async (tx) => {
    const part = await tx.partsCatalog.update({ where: { id }, data: body });
    if (body.ceilingPricePaise !== undefined && body.ceilingPricePaise !== existing.ceilingPricePaise) {
      await tx.auditLog.create({ data: { action: 'PRICE_CHANGED', actorType: 'ADMIN', actorId, metadata: { entity: 'PartsCatalog', entityId: id, field: 'ceilingPricePaise', fromPaise: existing.ceilingPricePaise, toPaise: body.ceilingPricePaise } } });
    }
    const nonPriceFields = Object.keys(body).filter((f) => f !== 'ceilingPricePaise');
    if (nonPriceFields.length > 0) {
      await tx.auditLog.create({ data: { action: 'CATALOG_UPDATED', actorType: 'ADMIN', actorId, metadata: { entity: 'PartsCatalog', entityId: id, fields: nonPriceFields } } });
    }
    return toPartDto(part);
  });
}
```

Note: `sku` is not in `updatePartBody`, so no dup-sku conflict path on update — matches the design (SKU is immutable). The `updatePart` `update` therefore can't hit a P2002, so no `asConflict` wrap is needed here.

- [ ] **Step 3: Confirm routes are registered**

The POST and PATCH routes were added in Task 3 Step 4. If you split the tasks and did not add them, add them now (see Task 3 Step 4 for the exact route code).

- [ ] **Step 4: Run all parts tests**

Run (from `apps/backend`):

```bash
pnpm test -- tests/catalog/parts.test.ts
```

Expected: PASS — all read + write + audit + conflict + 404 tests green.

- [ ] **Step 5: Build (type-check whole module)**

Run:

```bash
pnpm build
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/backend/src/modules/catalog apps/backend/tests/catalog/parts.test.ts
git commit -m "feat(backend): parts catalog read/write endpoints with audit (catalog sub-slice B)"
```

---

## Task 5: Idempotent catalog seed

**Files:**
- Modify: `apps/backend/prisma/seed.ts`
- Create: `apps/backend/tests/catalog/seed-catalog.test.ts`

- [ ] **Step 1: Write the failing seed test**

Create `apps/backend/tests/catalog/seed-catalog.test.ts`:

```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { prisma, resetDb } from '../schema/helpers.js';
import { seedCatalog } from '../../prisma/seed.js';

afterAll(() => prisma.$disconnect());
beforeEach(resetDb);

describe('seedCatalog', () => {
  it('creates the documented zones, categories, services, prices, and parts', async () => {
    await seedCatalog(prisma);
    const vadodara = await prisma.zone.findUnique({ where: { name: 'Vadodara' } });
    const padra = await prisma.zone.findUnique({ where: { name: 'Padra' } });
    expect(vadodara!.visitFeePaise).toBe(14900);
    expect(padra!.visitFeePaise).toBe(9900);
    expect(await prisma.serviceCategory.count()).toBeGreaterThanOrEqual(2);
    expect(await prisma.service.count()).toBeGreaterThanOrEqual(2);
    expect(await prisma.partsCatalog.count()).toBeGreaterThanOrEqual(2);

    // geofencing: the same service is priced differently per zone
    const svc = await prisma.service.findFirst({ where: { name: 'AC gas refill' } });
    const vPrice = await prisma.servicePrice.findUnique({ where: { serviceId_zoneId: { serviceId: svc!.id, zoneId: vadodara!.id } } });
    const pPrice = await prisma.servicePrice.findUnique({ where: { serviceId_zoneId: { serviceId: svc!.id, zoneId: padra!.id } } });
    expect(vPrice!.laborPaise).toBeGreaterThan(0);
    expect(pPrice!.laborPaise).toBeGreaterThan(0);
    expect(vPrice!.laborPaise).not.toBe(pPrice!.laborPaise);
  });

  it('is idempotent — running twice does not duplicate', async () => {
    await seedCatalog(prisma);
    await seedCatalog(prisma);
    expect(await prisma.zone.count()).toBe(2);
    const acCat = await prisma.serviceCategory.count({ where: { name: 'AC' } });
    expect(acCat).toBe(1);
    const svcCount = await prisma.service.count();
    await seedCatalog(prisma);
    expect(await prisma.service.count()).toBe(svcCount);
    expect(await prisma.partsCatalog.count({ where: { sku: 'AC-GAS-R32-1KG' } })).toBe(1);
  });

  it('does not write audit logs (seed is system bootstrap, not an admin action)', async () => {
    await seedCatalog(prisma);
    expect(await prisma.auditLog.count()).toBe(0);
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

Run (from `apps/backend`):

```bash
pnpm test -- tests/catalog/seed-catalog.test.ts
```

Expected: FAIL — `seedCatalog` is not exported from `prisma/seed.ts`.

- [ ] **Step 3: Implement `seedCatalog` in `prisma/seed.ts`**

In `apps/backend/prisma/seed.ts`, add the `seedCatalog` export (after `seedSuperAdmin`). It uses `upsert` keyed on the unique fields (`name` for zones/categories, `categoryId_name` for services, `serviceId_zoneId` for prices, `sku` for parts) so it is idempotent and writes no audit logs:

```ts
/** Idempotently seed the Vadodara/Padra zones + sample categories/services/prices + parts.
 *  Uses upsert on unique keys so repeated runs do not duplicate. No audit logs (system bootstrap). */
export async function seedCatalog(prisma: PrismaClient): Promise<void> {
  const vadodara = await prisma.zone.upsert({
    where: { name: 'Vadodara' }, update: { visitFeePaise: 14900 },
    create: { name: 'Vadodara', visitFeePaise: 14900 },
  });
  const padra = await prisma.zone.upsert({
    where: { name: 'Padra' }, update: { visitFeePaise: 9900 },
    create: { name: 'Padra', visitFeePaise: 9900 },
  });

  const ac = await prisma.serviceCategory.upsert({ where: { name: 'AC' }, update: {}, create: { name: 'AC' } });
  const fan = await prisma.serviceCategory.upsert({ where: { name: 'Fan' }, update: {}, create: { name: 'Fan' } });

  const gasRefill = await prisma.service.upsert({
    where: { categoryId_name: { categoryId: ac.id, name: 'AC gas refill' } },
    update: {}, create: { categoryId: ac.id, name: 'AC gas refill', tier: 'T2' },
  });
  const fanRepair = await prisma.service.upsert({
    where: { categoryId_name: { categoryId: fan.id, name: 'Ceiling fan repair' } },
    update: {}, create: { categoryId: fan.id, name: 'Ceiling fan repair', tier: 'T1' },
  });

  // Geofenced labor: same service, different price per zone.
  const prices: Array<{ serviceId: string; zoneId: string; laborPaise: number }> = [
    { serviceId: gasRefill.id, zoneId: vadodara.id, laborPaise: 60000 },
    { serviceId: gasRefill.id, zoneId: padra.id, laborPaise: 50000 },
    { serviceId: fanRepair.id, zoneId: vadodara.id, laborPaise: 25000 },
    { serviceId: fanRepair.id, zoneId: padra.id, laborPaise: 20000 },
  ];
  for (const p of prices) {
    await prisma.servicePrice.upsert({
      where: { serviceId_zoneId: { serviceId: p.serviceId, zoneId: p.zoneId } },
      update: { laborPaise: p.laborPaise },
      create: p,
    });
  }

  const parts: Array<{ sku: string; name: string; categoryId: string; ceilingPricePaise: number }> = [
    { sku: 'AC-GAS-R32-1KG', name: 'R32 refrigerant gas (1kg)', categoryId: ac.id, ceilingPricePaise: 70000 },
    { sku: 'FAN-CAP-2.5MFD', name: 'Fan capacitor 2.5 MFD', categoryId: fan.id, ceilingPricePaise: 12000 },
  ];
  for (const part of parts) {
    await prisma.partsCatalog.upsert({
      where: { sku: part.sku },
      update: { name: part.name, categoryId: part.categoryId, ceilingPricePaise: part.ceilingPricePaise },
      create: part,
    });
  }

  console.log('[seed] catalog: 2 zones, 2 categories, 2 services, 4 prices, 2 parts (idempotent)');
}
```

- [ ] **Step 4: Call `seedCatalog` from the CLI `run()` entry**

In `apps/backend/prisma/seed.ts`, the `run()` function currently calls only `seedSuperAdmin`. Add the catalog seed after it (still inside the `try`):

```ts
    await seedSuperAdmin(prisma, config.SEED_ADMIN_EMAIL, config.SEED_ADMIN_PASSWORD);
    await seedCatalog(prisma);
```

- [ ] **Step 5: Run the seed test to verify it passes**

Run (from `apps/backend`):

```bash
pnpm test -- tests/catalog/seed-catalog.test.ts
```

Expected: PASS (content, idempotency, no-audit).

- [ ] **Step 6: Run the seed CLI against the dev DB to verify end-to-end**

Run (from `apps/backend`, requires `SEED_ADMIN_EMAIL`/`SEED_ADMIN_PASSWORD` in `.env`):

```bash
pnpm db:seed
```

Expected: logs `[seed] admin ... ` (or "already exists — skipping") then `[seed] catalog: 2 zones, ...`. Run it a second time — no errors, no duplicates.

- [ ] **Step 7: Commit**

```bash
git add apps/backend/prisma/seed.ts apps/backend/tests/catalog/seed-catalog.test.ts
git commit -m "feat(backend): idempotent catalog seed — zones/services/prices/parts (catalog sub-slice B)"
```

---

## Task 6: Full suite + review + status/changelog

**Files:**
- Modify: `STATUS.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Run the whole backend test suite**

Run (from `apps/backend`):

```bash
pnpm test
```

Expected: ALL green — the prior 84 (sub-slice A) + auth/profile suites + the new parts tests + seed-catalog tests. Note the total count for the changelog.

- [ ] **Step 2: Run the FixCare review agents (read-only, before merge)**

Spawn the project review agents against this diff:
- `golden-rules-auditor` — Golden Rules #4/#5 + money-is-paise + audit-in-transaction.
- `prisma-migration-reviewer` — the `parts_catalog` migration (additive, indexed, FK, no float money).
- `fraud-vector-checker` — catalog/pricing fraud paths (catalog-prices-only).

Address any blocking findings (re-run the relevant test after each fix). Then run `/code-review` on the branch.

- [ ] **Step 3: Update `STATUS.md`**

Set `Phase` to note sub-slice B done; move `Active task` to the next target (booking lifecycle or addresses module); add to `Last shipped` a bullet for sub-slice B (PartsCatalog + endpoints + seed, test count, review result); update `Next 3 targets` (drop sub-slice B). Set the `_Last updated_` date to `2026-06-06`.

- [ ] **Step 4: Add a `CHANGELOG.md` entry**

Add at the top under a `## 2026-06-06 — Service catalog sub-slice B (parts master + seed)` header: PartsCatalog model (zone-agnostic ceiling price, optional category) + migration; `GET/POST/PATCH /catalog/parts` (reads any authed user, writes MANAGER+, dup-sku 409, neg/float paise 400, PRICE_CHANGED on ceiling change / CATALOG_UPDATED otherwise, soft-delete hidden); idempotent `seedCatalog` (2 zones / 2 categories / 2 services / 4 geofenced prices / 2 parts, no audit); test count; review notes. Mark the catalog module COMPLETE.

- [ ] **Step 5: Commit docs**

```bash
git add STATUS.md CHANGELOG.md
git commit -m "docs: status + changelog for catalog sub-slice B"
```

- [ ] **Step 6: Finish the branch**

Use the `superpowers:finishing-a-development-branch` skill to open the PR (`feature/catalog-parts` → `main`) and run `/code-review`, per the trunk-based workflow (ADR-0002).

---

## Self-Review notes

- **Spec coverage:** PartsCatalog model ✓ (T1), zone-agnostic ceiling price ✓, optional category ✓, `GET/POST/PATCH /catalog/parts` ✓ (T3/T4), MANAGER+ writes ✓, audit (PRICE_CHANGED/CATALOG_UPDATED) ✓ (T4), idempotent seed with zones/services/prices/parts ✓ (T5). Deferred items (merchant-catalog, PostGIS, snapshot) remain out of scope — not in this plan, correct.
- **Type consistency:** `PartDto`/`toPartDto`, `CreatePartBody`/`UpdatePartBody`, `createPart`/`updatePart`, `listParts` names match across types/schemas/service/routes/tests. `prisma.partsCatalog` is the Prisma client accessor for model `PartsCatalog` (camelCase first letter) — used consistently.
- **Migration safety:** new table only — additive, with `@@index([categoryId])` and `@unique` on `sku`. Verified in T1 Step 5.
- **Task 3/4 coupling:** the parts POST route and `createPart` are mutually dependent; the plan flags doing Tasks 3 and 4 together (Task 3 registers all three routes; Task 4 supplies the create/update service fns). Execute them as a pair to keep each test run meaningful.
