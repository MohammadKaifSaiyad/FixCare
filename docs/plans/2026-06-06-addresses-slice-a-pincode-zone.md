# Addresses Slice A — Pincode→Zone Map + Serviceability — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an admin-managed `PincodeZone` map + a `resolvePincode` resolver + `GET /serviceability?pincode=` + admin `/catalog/pincodes` CRUD (audited) + seeded Vadodara/Padra pincodes — so the app can check serviceability and admins can manage coverage.

**Architecture:** Extends the existing `apps/backend/src/modules/catalog/` module (pincode map is coverage config → catalog, MANAGER+, `CATALOG_UPDATED` audit) and adds a tiny new `src/modules/addresses/` module holding the public-ish `GET /serviceability` route + the shared `resolvePincode` resolver that Slice B will reuse. The resolver reads the live `PincodeZone` map; a pincode mapped to a soft-deleted/INACTIVE zone resolves as unserviceable.

**Tech Stack:** Node 22, Fastify 5, Prisma 6 + PostgreSQL 16, Zod, Vitest (`app.inject()`), TypeScript strict. Branch: `feature/addresses-module` (already cut off `main`).

**Design reference:** `docs/designs/2026-06-06-addresses-module-design.md` (decisions 1, 3, 4, 5, 9; schema `PincodeZone`; resolver; `/serviceability` + `/catalog/pincodes` endpoints; seed).

**Conventions in play:** Zod at the boundary; route→service→DTO (never raw Prisma); auth-first + `requireAdminLevel(MANAGER)` on writes; `CATALOG_UPDATED` audit in-transaction; dup unique → 409 via the existing `asConflict` helper; Golden Rule 7 (no PII — but a pincode map has no PII; address PII is Slice B).

---

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `apps/backend/prisma/schema.prisma` | `PincodeZone` model + `Zone.pincodeZones` back-relation | Modify |
| `apps/backend/prisma/migrations/<ts>_pincode_zone/` | Generated migration | Create (via migrate dev) |
| `apps/backend/tests/schema/helpers.ts` | Add `PincodeZone` to TRUNCATE list | Modify |
| `apps/backend/src/modules/addresses/serviceability.service.ts` | `resolvePincode` resolver + `Serviceability` type (shared; Slice B reuses) | Create |
| `apps/backend/src/modules/addresses/addresses.routes.ts` | `GET /serviceability` route + `registerAddressesRoutes` | Create |
| `apps/backend/src/modules/addresses/addresses.schemas.ts` | `serviceabilityQuery` (pincode) Zod schema | Create |
| `apps/backend/src/app.ts` | Register addresses routes | Modify |
| `apps/backend/src/modules/catalog/catalog.schemas.ts` | `createPincodeBody`, `updatePincodeBody` | Modify |
| `apps/backend/src/modules/catalog/catalog.types.ts` | `PincodeZoneDto` + `toPincodeZoneDto` | Modify |
| `apps/backend/src/modules/catalog/catalog.service.ts` | `listPincodes`/`createPincode`/`updatePincode`/`deletePincode` | Modify |
| `apps/backend/src/modules/catalog/catalog.routes.ts` | `GET/POST/PATCH/DELETE /catalog/pincodes` | Modify |
| `apps/backend/prisma/seed.ts` | Seed Vadodara/Padra pincodes in `seedCatalog` | Modify |
| `apps/backend/tests/addresses/serviceability.test.ts` | Resolver + `/serviceability` tests | Create |
| `apps/backend/tests/addresses/helpers.ts` | Token helpers for the addresses suite | Create |
| `apps/backend/tests/catalog/pincodes.test.ts` | Admin pincode CRUD + audit tests | Create |
| `apps/backend/tests/catalog/seed-catalog.test.ts` | Extend: seed creates pincode mappings | Modify |

All paths relative to repo root `/Users/mohammadkaifsaiyad/Development/FixCare`. Run `pnpm` from `apps/backend`. **Tests need env loaded** — every test command is prefixed `set -a && . ./.env && set +a &&` so `TEST_DATABASE_URL` reaches vitest.

**Commit-authorship (every commit):** author `MohammadKaifSaiyad <saiyedkgn6@gmail.com>`, **no** Claude/`Co-Authored-By` trailer (a git hook rejects it).

---

## Task 1: `PincodeZone` model + migration

**Files:**
- Modify: `apps/backend/prisma/schema.prisma` (CATALOG section; and the `Zone` model)
- Modify: `apps/backend/tests/schema/helpers.ts`
- Create: `apps/backend/prisma/migrations/<ts>_pincode_zone/migration.sql` (generated)

- [ ] **Step 1: Add the `pincodeZones` back-relation to `Zone`**

In `apps/backend/prisma/schema.prisma`, the `Zone` model currently ends:
```prisma
  deletedAt     DateTime?
  servicePrices ServicePrice[]
}
```
Add the back-relation:
```prisma
  deletedAt     DateTime?
  servicePrices ServicePrice[]
  pincodeZones  PincodeZone[]
}
```

- [ ] **Step 2: Add the `PincodeZone` model**

After the `PartsCatalog` model and before `enum CatalogStatus`, add:
```prisma
model PincodeZone {
  id        String        @id @default(uuid())
  pincode   String        @unique          // "390001"
  zoneId    String
  zone      Zone          @relation(fields: [zoneId], references: [id])
  status    CatalogStatus @default(ACTIVE)
  createdAt DateTime      @default(now())
  updatedAt DateTime      @updatedAt
  deletedAt DateTime?
  @@index([zoneId])
}
```

- [ ] **Step 3: Add `PincodeZone` to the test TRUNCATE list**

In `apps/backend/tests/schema/helpers.ts`, the `resetDb` TRUNCATE currently starts `TRUNCATE TABLE "PartsCatalog","ServicePrice",...`. Add `"PincodeZone"` at the front:
```ts
    'TRUNCATE TABLE "PincodeZone","PartsCatalog","ServicePrice","Service","ServiceCategory","Zone","AuditLog","RefreshToken","Admin","Merchant","Technician","Customer","User" RESTART IDENTITY CASCADE;'
```

- [ ] **Step 4: Generate + apply the migration**

Run (from `apps/backend`):
```bash
set -a && . ./.env && set +a && pnpm prisma migrate dev --name pincode_zone
```
Expected: `prisma/migrations/<ts>_pincode_zone/migration.sql` created + applied to `fixcare_dev`; client regenerates with a `pincodeZone` accessor. If migrate cannot reach the DB, report BLOCKED with the error — do NOT use `db push` or hand-edit SQL.

- [ ] **Step 5: Verify additive-only**

```bash
grep -iE 'DROP|TRUNCATE|ALTER COLUMN' apps/backend/prisma/migrations/*_pincode_zone/migration.sql || echo "clean: additive only"
```
Expected: `clean: additive only` (one `CREATE TABLE` + unique index on `pincode` + index on `zoneId` + FK to `Zone`).

- [ ] **Step 6: Commit**
```bash
git add apps/backend/prisma/schema.prisma apps/backend/prisma/migrations apps/backend/tests/schema/helpers.ts
git commit -m "feat(backend): add PincodeZone model + migration (addresses slice A)"
```

---

## Task 2: The `resolvePincode` resolver (new addresses module)

**Files:**
- Create: `apps/backend/src/modules/addresses/serviceability.service.ts`
- Create: `apps/backend/tests/addresses/helpers.ts`
- Create: `apps/backend/tests/addresses/serviceability.test.ts`

- [ ] **Step 1: Write the failing resolver test**

Create `apps/backend/tests/addresses/helpers.ts`:
```ts
import { prisma } from '../schema/helpers.js';
import { signAccessToken } from '../../src/shared/auth/tokens.js';
import type { AdminLevel } from '@prisma/client';

let seq = 0;
function uniquePhone(): string { return '9' + String(200000000 + seq++); }

export async function makeCustomerToken(): Promise<string> {
  const user = await prisma.user.create({ data: { phone: uniquePhone(), role: 'CUSTOMER' } });
  await prisma.customer.create({ data: { userId: user.id, name: 'Cust' } });
  return signAccessToken(user.id, 'CUSTOMER');
}

export async function makeAdminToken(level: AdminLevel): Promise<string> {
  const user = await prisma.user.create({ data: { phone: uniquePhone(), role: 'ADMIN' } });
  await prisma.admin.create({ data: { userId: user.id, name: 'Adm', email: `adm-${user.id}@fixcare.in`, passwordHash: 'x', adminLevel: level } });
  return signAccessToken(user.id, 'ADMIN');
}

/** Create an ACTIVE zone + an ACTIVE pincode mapping; return both ids. */
export async function seedZoneWithPincode(name: string, visitFeePaise: number, pincode: string) {
  const zone = await prisma.zone.create({ data: { name, visitFeePaise } });
  await prisma.pincodeZone.create({ data: { pincode, zoneId: zone.id } });
  return zone;
}
```

Create `apps/backend/tests/addresses/serviceability.test.ts`:
```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { prisma, resetDb } from '../schema/helpers.js';
import { resolvePincode } from '../../src/modules/addresses/serviceability.service.js';
import { seedZoneWithPincode } from './helpers.js';

afterAll(() => prisma.$disconnect());
beforeEach(resetDb);

describe('resolvePincode', () => {
  it('maps a known pincode to its active zone', async () => {
    const zone = await seedZoneWithPincode('Vadodara', 14900, '390001');
    const res = await resolvePincode('390001');
    expect(res.serviceable).toBe(true);
    expect(res.zone).toMatchObject({ id: zone.id, name: 'Vadodara', visitFeePaise: 14900 });
  });

  it('unknown pincode → unserviceable with message', async () => {
    const res = await resolvePincode('395003');
    expect(res.serviceable).toBe(false);
    expect(res.zone).toBeNull();
    expect(res.message).toBe("We don't serve this area yet");
  });

  it('pincode mapped to a soft-deleted zone → unserviceable', async () => {
    const zone = await seedZoneWithPincode('Gone', 100, '390002');
    await prisma.zone.update({ where: { id: zone.id }, data: { deletedAt: new Date() } });
    const res = await resolvePincode('390002');
    expect(res.serviceable).toBe(false);
    expect(res.zone).toBeNull();
  });

  it('pincode mapped to an INACTIVE zone → unserviceable', async () => {
    const zone = await seedZoneWithPincode('Off', 100, '390003');
    await prisma.zone.update({ where: { id: zone.id }, data: { status: 'INACTIVE' } });
    expect((await resolvePincode('390003')).serviceable).toBe(false);
  });

  it('a soft-deleted/INACTIVE pincode mapping → unserviceable even if the zone is active', async () => {
    const zone = await seedZoneWithPincode('Vadodara', 14900, '390004');
    await prisma.pincodeZone.updateMany({ where: { pincode: '390004' }, data: { status: 'INACTIVE' } });
    expect((await resolvePincode('390004')).serviceable).toBe(false);
    await prisma.pincodeZone.updateMany({ where: { pincode: '390004' }, data: { status: 'ACTIVE', deletedAt: new Date() } });
    expect((await resolvePincode('390004')).serviceable).toBe(false);
    void zone;
  });
});
```

- [ ] **Step 2: Run it — confirm FAIL**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/addresses/serviceability.test.ts
```
Expected: FAIL — `resolvePincode` not found.

- [ ] **Step 3: Implement the resolver**

Create `apps/backend/src/modules/addresses/serviceability.service.ts`:
```ts
import { prisma } from '../../shared/database/prisma.js';

export const OUT_OF_AREA_MESSAGE = "We don't serve this area yet";

export interface ServiceabilityZone { id: string; name: string; visitFeePaise: number; }
export interface Serviceability {
  serviceable: boolean;
  zone: ServiceabilityZone | null;
  message?: string;
}

/** Resolve a pincode to its serviceable zone using the LIVE PincodeZone map.
 *  Unserviceable if no active mapping, or the mapping/zone is soft-deleted/INACTIVE. */
export async function resolvePincode(pincode: string): Promise<Serviceability> {
  const mapping = await prisma.pincodeZone.findFirst({
    where: {
      pincode,
      deletedAt: null,
      status: 'ACTIVE',
      zone: { deletedAt: null, status: 'ACTIVE' },
    },
    include: { zone: true },
  });
  if (!mapping) return { serviceable: false, zone: null, message: OUT_OF_AREA_MESSAGE };
  return {
    serviceable: true,
    zone: { id: mapping.zone.id, name: mapping.zone.name, visitFeePaise: mapping.zone.visitFeePaise },
  };
}
```

- [ ] **Step 4: Run it — confirm PASS**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/addresses/serviceability.test.ts
```
Expected: PASS (all 5).

- [ ] **Step 5: Commit**
```bash
git add apps/backend/src/modules/addresses/serviceability.service.ts apps/backend/tests/addresses
git commit -m "feat(backend): resolvePincode resolver (addresses slice A)"
```

---

## Task 3: `GET /serviceability` route

**Files:**
- Create: `apps/backend/src/modules/addresses/addresses.schemas.ts`
- Create: `apps/backend/src/modules/addresses/addresses.routes.ts`
- Modify: `apps/backend/src/app.ts`
- Modify: `apps/backend/tests/addresses/serviceability.test.ts` (add HTTP tests)

- [ ] **Step 1: Add the failing HTTP tests**

Append to `apps/backend/tests/addresses/serviceability.test.ts` (add `buildApp` + `makeCustomerToken` imports at the top, and an app instance):

Add to the imports block at the top of the file:
```ts
import { buildApp } from '../../src/app.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomerToken } from './helpers.js';
```
Then below the existing `describe('resolvePincode', ...)` block add:
```ts
const app = await buildApp();
afterAll(() => app.close());
function auth(t: string) { return { authorization: `Bearer ${t}` }; }

describe('GET /serviceability', () => {
  beforeEach(async () => { await resetDb(); await flushTestRedis(); });

  it('known pincode → 200 serviceable with zone', async () => {
    await seedZoneWithPincode('Vadodara', 14900, '390001');
    const tok = await makeCustomerToken();
    const res = await app.inject({ method: 'GET', url: '/serviceability?pincode=390001', headers: auth(tok) });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ serviceable: true, zone: { name: 'Vadodara', visitFeePaise: 14900 } });
  });

  it('unknown pincode → 200 unserviceable with message', async () => {
    const tok = await makeCustomerToken();
    const res = await app.inject({ method: 'GET', url: '/serviceability?pincode=395003', headers: auth(tok) });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ serviceable: false, zone: null, message: "We don't serve this area yet" });
  });

  it('non-6-digit pincode → 400', async () => {
    const tok = await makeCustomerToken();
    expect((await app.inject({ method: 'GET', url: '/serviceability?pincode=39', headers: auth(tok) })).statusCode).toBe(400);
    expect((await app.inject({ method: 'GET', url: '/serviceability?pincode=abcdef', headers: auth(tok) })).statusCode).toBe(400);
  });

  it('no token → 401', async () => {
    expect((await app.inject({ method: 'GET', url: '/serviceability?pincode=390001' })).statusCode).toBe(401);
  });
});
```
NOTE: the existing `describe('resolvePincode')` block already has its own `beforeEach(resetDb)` at file top — keep it; the new block adds its own `beforeEach` that also flushes Redis (needed because `buildApp` wires rate-limit/Redis).

- [ ] **Step 2: Run — confirm FAIL**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/addresses/serviceability.test.ts
```
Expected: the new HTTP tests FAIL (route 404 / not registered).

- [ ] **Step 3: Add the query schema**

Create `apps/backend/src/modules/addresses/addresses.schemas.ts`:
```ts
import { z } from 'zod';

const pincode = z.string().regex(/^\d{6}$/, 'pincode must be 6 digits');

export const serviceabilityQuery = z.object({ pincode }).strict();
export type ServiceabilityQuery = z.infer<typeof serviceabilityQuery>;
```

- [ ] **Step 4: Add the route module**

Create `apps/backend/src/modules/addresses/addresses.routes.ts`:
```ts
import type { FastifyInstance } from 'fastify';
import { requireAuth } from '../../shared/middleware/auth.js';
import { ValidationError } from '../../shared/errors.js';
import { serviceabilityQuery } from './addresses.schemas.js';
import { resolvePincode } from './serviceability.service.js';

export async function registerAddressesRoutes(app: FastifyInstance) {
  app.get('/serviceability', { preHandler: [requireAuth] }, async (req, reply) => {
    const q = serviceabilityQuery.safeParse(req.query);
    if (!q.success) throw new ValidationError(q.error.issues[0]?.message ?? 'Invalid query');
    return reply.send(await resolvePincode(q.data.pincode));
  });
}
```

- [ ] **Step 5: Register in `buildApp`**

In `apps/backend/src/app.ts`, the imports include `registerCatalogRoutes` and `buildApp` calls `await registerCatalogRoutes(app);`. Add an import alongside it:
```ts
import { registerAddressesRoutes } from './modules/addresses/addresses.routes.js';
```
and after the `await registerCatalogRoutes(app);` line:
```ts
  await registerAddressesRoutes(app);
```

- [ ] **Step 6: Run — confirm PASS**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/addresses/serviceability.test.ts
```
Expected: PASS (all resolver + HTTP tests).

- [ ] **Step 7: Build + commit**
```bash
cd apps/backend && pnpm build   # expect clean
git add apps/backend/src/modules/addresses apps/backend/src/app.ts apps/backend/tests/addresses/serviceability.test.ts
git commit -m "feat(backend): GET /serviceability endpoint (addresses slice A)"
```

---

## Task 4: Admin pincode-map DTO + Zod schemas (catalog module)

**Files:**
- Modify: `apps/backend/src/modules/catalog/catalog.types.ts`
- Modify: `apps/backend/src/modules/catalog/catalog.schemas.ts`

- [ ] **Step 1: Add `PincodeZoneDto` + `toPincodeZoneDto`**

In `apps/backend/src/modules/catalog/catalog.types.ts`, add `PincodeZone` to the `@prisma/client` import on line 1, then append:
```ts
export interface PincodeZoneDto {
  id: string;
  pincode: string;
  zoneId: string;
  status: PincodeZone['status'];
}

export function toPincodeZoneDto(p: PincodeZone): PincodeZoneDto {
  return { id: p.id, pincode: p.pincode, zoneId: p.zoneId, status: p.status };
}
```

- [ ] **Step 2: Add `createPincodeBody` + `updatePincodeBody`**

In `apps/backend/src/modules/catalog/catalog.schemas.ts`, append (define a local `pincode` regex schema):
```ts
const pincode6 = z.string().regex(/^\d{6}$/, 'pincode must be 6 digits');

export const createPincodeBody = z.object({ pincode: pincode6, zoneId: z.string().min(1) }).strict();
export type CreatePincodeBody = z.infer<typeof createPincodeBody>;

export const updatePincodeBody = z
  .object({ zoneId: z.string().min(1), status: z.enum(['ACTIVE', 'INACTIVE']) })
  .partial().strict()
  .refine((b) => Object.keys(b).length > 0, { message: 'At least one field is required' });
export type UpdatePincodeBody = z.infer<typeof updatePincodeBody>;
```
(`pincode` is immutable — not in the update body. To re-point coverage, change `zoneId` or soft-delete + re-create.)

- [ ] **Step 3: Type-check + commit**
```bash
cd apps/backend && pnpm build   # expect clean
git add apps/backend/src/modules/catalog/catalog.types.ts apps/backend/src/modules/catalog/catalog.schemas.ts
git commit -m "feat(backend): pincode DTO + schemas (addresses slice A)"
```

---

## Task 5: Admin pincode-map endpoints (catalog module, audited)

**Files:**
- Modify: `apps/backend/src/modules/catalog/catalog.service.ts`
- Modify: `apps/backend/src/modules/catalog/catalog.routes.ts`
- Create: `apps/backend/tests/catalog/pincodes.test.ts`

- [ ] **Step 1: Write the failing tests**

Create `apps/backend/tests/catalog/pincodes.test.ts`:
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

async function makeZone(name: string, fee: number) {
  const mgr = await makeAdminToken('MANAGER');
  return (await app.inject({ method: 'POST', url: '/catalog/zones', headers: auth(mgr), payload: { name, visitFeePaise: fee } })).json();
}

describe('admin pincode map', () => {
  it('MANAGER creates a mapping; any authed user lists it', async () => {
    const zone = await makeZone('Vadodara', 14900);
    const mgr = await makeAdminToken('MANAGER');
    const create = await app.inject({ method: 'POST', url: '/catalog/pincodes', headers: auth(mgr), payload: { pincode: '390001', zoneId: zone.id } });
    expect(create.statusCode).toBe(201);
    expect(create.json()).toMatchObject({ pincode: '390001', zoneId: zone.id, status: 'ACTIVE' });
    const cust = await makeCustomerToken();
    const list = await app.inject({ method: 'GET', url: '/catalog/pincodes', headers: auth(cust) });
    expect(list.statusCode).toBe(200);
    expect(list.json().some((p: { pincode: string }) => p.pincode === '390001')).toBe(true);
  });

  it('SUPPORT cannot create a mapping → 403; create writes a CATALOG_UPDATED audit', async () => {
    const zone = await makeZone('Vadodara', 14900);
    const sup = await makeAdminToken('SUPPORT');
    expect((await app.inject({ method: 'POST', url: '/catalog/pincodes', headers: auth(sup), payload: { pincode: '390001', zoneId: zone.id } })).statusCode).toBe(403);
    const mgr = await makeAdminToken('MANAGER');
    const p = (await app.inject({ method: 'POST', url: '/catalog/pincodes', headers: auth(mgr), payload: { pincode: '390002', zoneId: zone.id } })).json();
    const audit = await prisma.auditLog.findFirst({ where: { action: 'CATALOG_UPDATED', metadata: { path: ['entityId'], equals: p.id } } });
    expect(audit).toBeTruthy();
    expect((audit!.metadata as { entity: string }).entity).toBe('PincodeZone');
  });

  it('duplicate pincode → 409', async () => {
    const zone = await makeZone('Vadodara', 14900);
    const mgr = await makeAdminToken('MANAGER');
    await app.inject({ method: 'POST', url: '/catalog/pincodes', headers: auth(mgr), payload: { pincode: '390001', zoneId: zone.id } });
    const dup = await app.inject({ method: 'POST', url: '/catalog/pincodes', headers: auth(mgr), payload: { pincode: '390001', zoneId: zone.id } });
    expect(dup.statusCode).toBe(409);
  });

  it('non-6-digit pincode → 400', async () => {
    const zone = await makeZone('Vadodara', 14900);
    const mgr = await makeAdminToken('MANAGER');
    expect((await app.inject({ method: 'POST', url: '/catalog/pincodes', headers: auth(mgr), payload: { pincode: '39', zoneId: zone.id } })).statusCode).toBe(400);
  });

  it('POST with unknown zoneId → 404', async () => {
    const mgr = await makeAdminToken('MANAGER');
    const res = await app.inject({ method: 'POST', url: '/catalog/pincodes', headers: auth(mgr), payload: { pincode: '390001', zoneId: '00000000-0000-0000-0000-000000000000' } });
    expect(res.statusCode).toBe(404);
  });

  it('PATCH re-points zone / sets INACTIVE; CATALOG_UPDATED audit', async () => {
    const v = await makeZone('Vadodara', 14900);
    const p2 = await makeZone('Padra', 9900);
    const mgr = await makeAdminToken('MANAGER');
    const pin = (await app.inject({ method: 'POST', url: '/catalog/pincodes', headers: auth(mgr), payload: { pincode: '391440', zoneId: v.id } })).json();
    const res = await app.inject({ method: 'PATCH', url: `/catalog/pincodes/${pin.id}`, headers: auth(mgr), payload: { zoneId: p2.id } });
    expect(res.statusCode).toBe(200);
    expect(res.json().zoneId).toBe(p2.id);
  });

  it('PATCH a non-existent mapping → 404; PATCH with unknown zoneId → 404', async () => {
    const v = await makeZone('Vadodara', 14900);
    const mgr = await makeAdminToken('MANAGER');
    expect((await app.inject({ method: 'PATCH', url: '/catalog/pincodes/00000000-0000-0000-0000-000000000000', headers: auth(mgr), payload: { status: 'INACTIVE' } })).statusCode).toBe(404);
    const pin = (await app.inject({ method: 'POST', url: '/catalog/pincodes', headers: auth(mgr), payload: { pincode: '391441', zoneId: v.id } })).json();
    expect((await app.inject({ method: 'PATCH', url: `/catalog/pincodes/${pin.id}`, headers: auth(mgr), payload: { zoneId: '00000000-0000-0000-0000-000000000000' } })).statusCode).toBe(404);
  });

  it('DELETE soft-deletes and hides from list', async () => {
    const v = await makeZone('Vadodara', 14900);
    const mgr = await makeAdminToken('MANAGER');
    const pin = (await app.inject({ method: 'POST', url: '/catalog/pincodes', headers: auth(mgr), payload: { pincode: '391442', zoneId: v.id } })).json();
    expect((await app.inject({ method: 'DELETE', url: `/catalog/pincodes/${pin.id}`, headers: auth(mgr) })).statusCode).toBe(204);
    const cust = await makeCustomerToken();
    const list = (await app.inject({ method: 'GET', url: '/catalog/pincodes', headers: auth(cust) })).json();
    expect(list.find((p: { id: string }) => p.id === pin.id)).toBeUndefined();
  });
});
```

- [ ] **Step 2: Run — confirm FAIL**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/catalog/pincodes.test.ts
```
Expected: FAIL (routes not registered).

- [ ] **Step 3: Add service functions**

In `apps/backend/src/modules/catalog/catalog.service.ts`, extend the types import to add `toPincodeZoneDto, type PincodeZoneDto` and the schemas import to add `CreatePincodeBody, UpdatePincodeBody`. Append:
```ts
export async function listPincodes(): Promise<PincodeZoneDto[]> {
  const rows = await prisma.pincodeZone.findMany({ where: { deletedAt: null }, orderBy: { pincode: 'asc' } });
  return rows.map(toPincodeZoneDto);
}

export async function createPincode(actorId: string, body: CreatePincodeBody): Promise<PincodeZoneDto> {
  const zone = await prisma.zone.findFirst({ where: { id: body.zoneId, deletedAt: null } });
  if (!zone) throw new NotFoundError('Zone not found');
  try {
    return await prisma.$transaction(async (tx) => {
      const row = await tx.pincodeZone.create({ data: { pincode: body.pincode, zoneId: body.zoneId } });
      await tx.auditLog.create({ data: { action: 'CATALOG_UPDATED', actorType: 'ADMIN', actorId, metadata: { entity: 'PincodeZone', entityId: row.id, fields: Object.keys(body) } } });
      return toPincodeZoneDto(row);
    });
  } catch (e) { return asConflict(e, 'A mapping for that pincode already exists'); }
}

export async function updatePincode(actorId: string, id: string, body: UpdatePincodeBody): Promise<PincodeZoneDto> {
  const existing = await prisma.pincodeZone.findFirst({ where: { id, deletedAt: null } });
  if (!existing) throw new NotFoundError('Pincode mapping not found');
  if (body.zoneId) {
    const zone = await prisma.zone.findFirst({ where: { id: body.zoneId, deletedAt: null } });
    if (!zone) throw new NotFoundError('Zone not found');
  }
  const changedFields = (Object.keys(body) as (keyof typeof body)[])
    .filter((k) => (body as Record<string, unknown>)[k] !== (existing as Record<string, unknown>)[k]);
  if (changedFields.length === 0) return toPincodeZoneDto(existing);
  return prisma.$transaction(async (tx) => {
    const row = await tx.pincodeZone.update({ where: { id }, data: body });
    await tx.auditLog.create({ data: { action: 'CATALOG_UPDATED', actorType: 'ADMIN', actorId, metadata: { entity: 'PincodeZone', entityId: id, fields: changedFields } } });
    return toPincodeZoneDto(row);
  });
}

export async function deletePincode(actorId: string, id: string): Promise<void> {
  const existing = await prisma.pincodeZone.findFirst({ where: { id, deletedAt: null } });
  if (!existing) throw new NotFoundError('Pincode mapping not found');
  await prisma.$transaction(async (tx) => {
    await tx.pincodeZone.update({ where: { id }, data: { deletedAt: new Date() } });
    await tx.auditLog.create({ data: { action: 'CATALOG_UPDATED', actorType: 'ADMIN', actorId, metadata: { entity: 'PincodeZone', entityId: id, fields: ['deletedAt'] } } });
  });
}
```
(`createPincode`/`updatePincode` mirror `createPart`/`updatePart`; `updatePincode` uses the changed-only audit pattern established in the catalog review fixes; `NotFoundError` and `asConflict` are already imported in this file.)

- [ ] **Step 4: Register routes**

In `apps/backend/src/modules/catalog/catalog.routes.ts`, extend the schemas import to add `createPincodeBody, updatePincodeBody` and the service import to add `listPincodes, createPincode, updatePincode, deletePincode`. Before the closing `}` of `registerCatalogRoutes`, add:
```ts
  app.get('/catalog/pincodes', { preHandler: [requireAuth] }, async (_req, reply) => reply.send(await listPincodes()));

  app.post('/catalog/pincodes', { preHandler: [requireAuth, requireAdminLevel('MANAGER')] }, async (req, reply) => {
    const p = createPincodeBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.code(201).send(await createPincode(req.user!.id, p.data));
  });

  app.patch('/catalog/pincodes/:id', { preHandler: [requireAuth, requireAdminLevel('MANAGER')] }, async (req, reply) => {
    const p = updatePincodeBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.send(await updatePincode(req.user!.id, (req.params as { id: string }).id, p.data));
  });

  app.delete('/catalog/pincodes/:id', { preHandler: [requireAuth, requireAdminLevel('MANAGER')] }, async (req, reply) => {
    await deletePincode(req.user!.id, (req.params as { id: string }).id);
    return reply.code(204).send();
  });
```

- [ ] **Step 5: Run — confirm PASS**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/catalog/pincodes.test.ts
```
Expected: PASS (all).

- [ ] **Step 6: Build + commit**
```bash
cd apps/backend && pnpm build   # expect clean
git add apps/backend/src/modules/catalog/catalog.service.ts apps/backend/src/modules/catalog/catalog.routes.ts apps/backend/tests/catalog/pincodes.test.ts
git commit -m "feat(backend): admin pincode-map CRUD with audit (addresses slice A)"
```

---

## Task 6: Seed Vadodara/Padra pincodes

**Files:**
- Modify: `apps/backend/prisma/seed.ts`
- Modify: `apps/backend/tests/catalog/seed-catalog.test.ts`

- [ ] **Step 1: Add the failing seed assertion**

In `apps/backend/tests/catalog/seed-catalog.test.ts`, add to the first test (the "creates the documented zones..." test) — after the existing assertions — a check that pincode mappings exist and resolve:
```ts
    expect(await prisma.pincodeZone.count()).toBeGreaterThanOrEqual(2);
    const vadoPin = await prisma.pincodeZone.findUnique({ where: { pincode: '390001' } });
    expect(vadoPin!.zoneId).toBe(vadodara!.id);
    const padraPin = await prisma.pincodeZone.findUnique({ where: { pincode: '391440' } });
    expect(padraPin!.zoneId).toBe(padra!.id);
```
And to the idempotency test add:
```ts
    expect(await prisma.pincodeZone.count({ where: { pincode: '390001' } })).toBe(1);
```

- [ ] **Step 2: Run — confirm FAIL**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/catalog/seed-catalog.test.ts
```
Expected: FAIL (no pincode rows yet).

- [ ] **Step 3: Seed pincodes in `seedCatalog`**

In `apps/backend/prisma/seed.ts`, inside `seedCatalog`, after the `parts` upsert loop and before the final `console.log`, add:
```ts
  const pincodes: Array<{ pincode: string; zoneId: string }> = [
    { pincode: '390001', zoneId: vadodara.id },
    { pincode: '390002', zoneId: vadodara.id },
    { pincode: '391440', zoneId: padra.id },
  ];
  for (const pz of pincodes) {
    await prisma.pincodeZone.upsert({
      where: { pincode: pz.pincode },
      update: { zoneId: pz.zoneId },
      create: pz,
    });
  }
```
Update the final `console.log` to mention pincodes:
```ts
  console.log('[seed] catalog: 2 zones, 2 categories, 2 services, 4 prices, 2 parts, 3 pincodes (idempotent)');
```

- [ ] **Step 4: Run — confirm PASS**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/catalog/seed-catalog.test.ts
```
Expected: PASS (content + idempotency, including pincodes).

- [ ] **Step 5: Run the seed CLI end-to-end (idempotency)**
```bash
set -a && . ./.env && set +a && pnpm db:seed && pnpm db:seed
```
Expected: both runs succeed; second run no errors/dups; log mentions "3 pincodes".

- [ ] **Step 6: Commit**
```bash
git add apps/backend/prisma/seed.ts apps/backend/tests/catalog/seed-catalog.test.ts
git commit -m "feat(backend): seed Vadodara/Padra pincode mappings (addresses slice A)"
```

---

## Task 7: Full suite + reviews + status/changelog

**Files:**
- Modify: `STATUS.md`, `CHANGELOG.md`

- [ ] **Step 1: Full backend suite**
```bash
set -a && . ./.env && set +a && cd apps/backend && pnpm test
```
Expected: ALL green (the 108 from the catalog work + the new addresses/pincode/serviceability/seed tests). Note the total.

- [ ] **Step 2: Run the FixCare review agents (read-only, before merge)**

Spawn against this diff:
- `prisma-migration-reviewer` — the `pincode_zone` migration (additive, indexed, FK, no money/PII concerns).
- `golden-rules-auditor` — `CATALOG_UPDATED` audit in-transaction on pincode writes; MANAGER+ RBAC; no PII (pincode map has none; confirm `/serviceability` leaks nothing).
- `fraud-vector-checker` — serviceability/zone-coverage paths (catalog-prices-only adjacency; no way for a non-admin to alter coverage).

Address blocking findings (re-run the relevant test after each fix). Then run `/code-review` on the branch.

- [ ] **Step 3: Update `STATUS.md`**

Set Phase to note addresses Slice A done; Active task → Slice B (Address CRUD); add a `Last shipped` bullet (PincodeZone + resolver + `/serviceability` + admin `/catalog/pincodes` + seed; test count; review result); update `Next 3 targets` (Slice B, then booking). Set `_Last updated_` to `2026-06-06`.

- [ ] **Step 4: `CHANGELOG.md` entry**

Add under `## 2026-06-06 — Addresses slice A (pincode→zone + serviceability)`: PincodeZone model + migration; `resolvePincode` (live map, INACTIVE/soft-deleted → unserviceable); `GET /serviceability` (6-digit Zod, any authed user, explicit serviceable/zone/message); admin `GET/POST/PATCH/DELETE /catalog/pincodes` (MANAGER+, dup→409, unknown zone→404, `CATALOG_UPDATED` audit, changed-only on PATCH); seeded 3 pincodes; test count; review notes.

- [ ] **Step 5: Commit docs**
```bash
git add STATUS.md CHANGELOG.md
git commit -m "docs: status + changelog for addresses slice A"
```

- [ ] **Step 6: Finish the branch**

Use `superpowers:finishing-a-development-branch`. NOTE: Slice B (Address CRUD) builds on this in the SAME module/branch — confirm with the user whether to PR Slice A now or continue to Slice B on the same branch before opening a PR.

---

## Self-Review notes

- **Spec coverage:** PincodeZone model ✓ (T1); resolver with live re-resolution + INACTIVE/soft-deleted guards ✓ (T2); `GET /serviceability` explicit verdict + 6-digit validation + auth ✓ (T3); admin `/catalog/pincodes` CRUD MANAGER+, audited, dup→409, unknown-zone→404 ✓ (T4/T5); seeded Vadodara/Padra pincodes idempotent ✓ (T6). Address CRUD + the cached `zoneId` hint + DTO serviceability + default-address + ownership are **Slice B** (separate plan) — correctly out of this plan.
- **Placeholder scan:** none — every step has concrete code/commands.
- **Type consistency:** `resolvePincode`→`Serviceability`/`ServiceabilityZone`/`OUT_OF_AREA_MESSAGE` used consistently across resolver, route, and tests; `PincodeZoneDto`/`toPincodeZoneDto`, `createPincodeBody`/`updatePincodeBody`, `listPincodes`/`createPincode`/`updatePincode`/`deletePincode` names match across service/routes/tests. `prisma.pincodeZone` is the client accessor for model `PincodeZone`. The serviceability route uses its own `serviceabilityQuery` schema (addresses module); the admin create uses `createPincodeBody` (catalog module) — two separate pincode validators by design (different modules), both `/^\d{6}$/`.
- **Cross-module note:** `GET /serviceability` lives in the new `addresses/` module but reads `PincodeZone` via the shared resolver — inter-module read through the resolver service, not a cross-module raw query. The admin write endpoints live in `catalog/` (coverage config). This matches the spec's placement.
