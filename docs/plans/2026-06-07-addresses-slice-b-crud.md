# Addresses Slice B — Customer Address CRUD — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the customer `Address` model + owner-scoped `/me/addresses` CRUD (CUSTOMER-only, one-default-enforced), with live serviceability baked into every address DTO (reusing Slice A's `resolvePincode`).

**Architecture:** Extends the existing `apps/backend/src/modules/addresses/` module (which already holds `resolvePincode` + `GET /serviceability`). Adds `Address` (+ `AddressStatus` enum) to Prisma, an `addresses.service.ts` (owner-scoped CRUD, default-address transaction, resolve-at-save + re-resolve-on-read), an `addresses.types.ts` (DTO with serviceability verdict), and CRUD routes. Follows the profiles module's `/me/*` implicit-ownership pattern (resolve the Customer row from `request.user.id`) and the catalog module's route→service→DTO + soft-delete conventions.

**Tech Stack:** Node 22, Fastify 5, Prisma 6 + PostgreSQL 16, Zod, Vitest (`app.inject()`), TypeScript strict. Branch: `feature/addresses-crud` (already cut off `main`).

**Design reference:** `docs/designs/2026-06-06-addresses-module-design.md` (decisions 2,3,5,6,7,8,9; schema `Address`; the `/me/addresses` endpoints; validation; default-address rule; PII discipline).

**Conventions in play:** Zod at the boundary (`.strict()`); route→service→DTO (never raw Prisma); auth-first; **CUSTOMER-only** + **ownership** (another customer's id → 404, no IDOR); soft-delete; **no audit on customer address CRUD** (decision 8); **Golden Rule 7 — no address PII in logs/audit ever**; resolve-at-save stores a `zoneId` hint, reads re-resolve live.

---

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `apps/backend/prisma/schema.prisma` | `Address` model + `AddressStatus` enum + `Customer.addresses` + `Zone.addresses` back-relations | Modify |
| `apps/backend/prisma/migrations/<ts>_address/` | Generated migration | Create (migrate dev) |
| `apps/backend/tests/schema/helpers.ts` | Add `Address` to TRUNCATE list | Modify |
| `apps/backend/src/modules/addresses/addresses.types.ts` | `AddressDto` (+ serviceability fields) + `toAddressDto` | Create |
| `apps/backend/src/modules/addresses/addresses.schemas.ts` | `createAddressBody`, `updateAddressBody` | Modify |
| `apps/backend/src/modules/addresses/addresses.service.ts` | owner-scoped list/get/create/update/delete + default-address tx + serviceability assembly | Create |
| `apps/backend/src/modules/addresses/addresses.routes.ts` | `/me/addresses` CRUD routes (CUSTOMER-only) | Modify |
| `apps/backend/tests/addresses/addresses-crud.test.ts` | CRUD + ownership + default + serviceability tests | Create |

All paths relative to repo root `/Users/mohammadkaifsaiyad/Development/FixCare`. Run `pnpm` from `apps/backend`. **Tests need env loaded** — every test command is prefixed `set -a && . ./.env && set +a &&`.

**Commit-authorship (every commit):** author `MohammadKaifSaiyad <saiyedkgn6@gmail.com>`, **no** Claude/`Co-Authored-By` trailer (a git hook rejects it).

---

## Task 1: `Address` model + migration

**Files:**
- Modify: `apps/backend/prisma/schema.prisma` (ADDRESSES section; `Customer` and `Zone` models)
- Modify: `apps/backend/tests/schema/helpers.ts`
- Create: `apps/backend/prisma/migrations/<ts>_address/migration.sql` (generated)

- [ ] **Step 1: Add the `Address` model + `AddressStatus` enum**

In `apps/backend/prisma/schema.prisma`, after the `PincodeZone` model (and near it, since both are the addresses module), add:
```prisma
model Address {
  id         String        @id @default(uuid())
  customerId String
  customer   Customer      @relation(fields: [customerId], references: [id])
  label      String                       // "Home", "Office"
  line1      String
  line2      String?
  landmark   String?
  pincode    String                       // 6-digit, validated at the boundary
  lat        Float?                        // optional device map-pin (later arrival-GPS)
  lng        Float?
  zoneId     String?                       // resolved-at-save HINT; null = unserviceable
  zone       Zone?         @relation(fields: [zoneId], references: [id])
  isDefault  Boolean       @default(false)
  status     AddressStatus @default(ACTIVE)
  createdAt  DateTime      @default(now())
  updatedAt  DateTime      @updatedAt
  deletedAt  DateTime?
  @@index([customerId])
}

enum AddressStatus {
  ACTIVE
  INACTIVE
}
```

- [ ] **Step 2: Add the back-relations on `Customer` and `Zone`**

In the `Customer` model, the current last field before `}` is `deletedAt DateTime?`. Add an `addresses` relation:
```prisma
  deletedAt DateTime?
  addresses Address[]
}
```

In the `Zone` model (which currently ends with `servicePrices ServicePrice[]` and `pincodeZones PincodeZone[]`), add:
```prisma
  pincodeZones  PincodeZone[]
  addresses     Address[]
}
```

- [ ] **Step 3: Add `Address` to the test TRUNCATE list**

In `apps/backend/tests/schema/helpers.ts`, the `resetDb` TRUNCATE currently starts `TRUNCATE TABLE "PincodeZone","PartsCatalog",...`. Add `"Address"` at the FRONT (before `"PincodeZone"`):
```ts
    'TRUNCATE TABLE "Address","PincodeZone","PartsCatalog","ServicePrice","Service","ServiceCategory","Zone","AuditLog","RefreshToken","Admin","Merchant","Technician","Customer","User" RESTART IDENTITY CASCADE;'
```

- [ ] **Step 4: Generate + apply the migration**
```bash
set -a && . ./.env && set +a && pnpm prisma migrate dev --name address
```
Expected: `prisma/migrations/<ts>_address/migration.sql` created + applied to `fixcare_dev`; client regenerates with an `address` accessor. CREATE TABLE with index on `customerId`, FKs to `Customer` and `Zone` (zone FK nullable). If migrate can't reach the DB, report BLOCKED with the exact error — do NOT use `db push` or hand-edit SQL or hand-patch `_prisma_migrations`.

- [ ] **Step 5: Verify additive-only**
```bash
grep -iE 'DROP|TRUNCATE|ALTER COLUMN' apps/backend/prisma/migrations/*_address/migration.sql || echo "clean: additive only"
```
Expected: `clean: additive only`.

- [ ] **Step 6: Commit**
```bash
git add apps/backend/prisma/schema.prisma apps/backend/prisma/migrations apps/backend/tests/schema/helpers.ts
git commit -m "feat(backend): add Address model + migration (addresses slice B)"
```

---

## Task 2: `AddressDto` + `toAddressDto`

**Files:**
- Create: `apps/backend/src/modules/addresses/addresses.types.ts`

- [ ] **Step 1: Create the DTO + mapper**

The DTO carries the address fields PLUS the live serviceability verdict (the API-UX core — the app never infers). `toAddressDto` takes the Prisma `Address` row AND a `Serviceability` (computed by the service via `resolvePincode`), so the mapper stays pure.

Create `apps/backend/src/modules/addresses/addresses.types.ts`:
```ts
import type { Address } from '@prisma/client';
import type { Serviceability } from './serviceability.service.js';

export interface AddressDto {
  id: string;
  label: string;
  line1: string;
  line2: string | null;
  landmark: string | null;
  pincode: string;
  lat: number | null;
  lng: number | null;
  isDefault: boolean;
  status: Address['status'];
  serviceable: boolean;
  zone: Serviceability['zone'];   // { id, name, visitFeePaise } | null
  message?: string;               // present only when unserviceable
}

export function toAddressDto(a: Address, s: Serviceability): AddressDto {
  return {
    id: a.id,
    label: a.label,
    line1: a.line1,
    line2: a.line2,
    landmark: a.landmark,
    pincode: a.pincode,
    lat: a.lat,
    lng: a.lng,
    isDefault: a.isDefault,
    status: a.status,
    serviceable: s.serviceable,
    zone: s.zone,
    ...(s.message !== undefined ? { message: s.message } : {}),
  };
}
```

- [ ] **Step 2: Type-check + commit**
```bash
cd apps/backend && pnpm build   # expect clean
git add apps/backend/src/modules/addresses/addresses.types.ts
git commit -m "feat(backend): AddressDto + serviceability mapper (addresses slice B)"
```

---

## Task 3: `createAddressBody` + `updateAddressBody` Zod schemas

**Files:**
- Modify: `apps/backend/src/modules/addresses/addresses.schemas.ts`

- [ ] **Step 1: Add the schemas**

`addresses.schemas.ts` already defines `const pincode = z.string().length(6).regex(/^\d{6}$/, ...)` at the top — REUSE it. Append (lat/lng are both-or-neither via a refine; PATCH is partial+strict+≥1-field):
```ts
const latLng = {
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
};

export const createAddressBody = z
  .object({
    label: z.string().min(1),
    line1: z.string().min(1),
    line2: z.string().min(1).optional(),
    landmark: z.string().min(1).optional(),
    pincode,
    lat: latLng.lat.optional(),
    lng: latLng.lng.optional(),
    isDefault: z.boolean().optional(),
  })
  .strict()
  .refine((b) => (b.lat === undefined) === (b.lng === undefined), {
    message: 'lat and lng must be provided together',
  });
export type CreateAddressBody = z.infer<typeof createAddressBody>;

export const updateAddressBody = z
  .object({
    label: z.string().min(1),
    line1: z.string().min(1),
    line2: z.string().min(1).nullable(),
    landmark: z.string().min(1).nullable(),
    pincode,
    lat: latLng.lat.nullable(),
    lng: latLng.lng.nullable(),
    isDefault: z.boolean(),
  })
  .partial()
  .strict()
  .refine((b) => Object.keys(b).length > 0, { message: 'At least one field is required' })
  .refine((b) => !('lat' in b || 'lng' in b) || (('lat' in b) === ('lng' in b)), {
    message: 'lat and lng must be updated together',
  });
export type UpdateAddressBody = z.infer<typeof updateAddressBody>;
```
Notes: on create, `line2`/`landmark`/`lat`/`lng` are optional. On update, they are nullable (so the customer can clear `line2`/`landmark` or remove the geo pin) — but lat/lng must move together. `pincode` IS editable (a customer can correct it; the service re-resolves the zone on update).

- [ ] **Step 2: Type-check + commit**
```bash
cd apps/backend && pnpm build   # expect clean
git add apps/backend/src/modules/addresses/addresses.schemas.ts
git commit -m "feat(backend): address Zod schemas (addresses slice B)"
```

---

## Task 4: `addresses.service.ts` — owner-scoped CRUD + default + serviceability

**Files:**
- Create: `apps/backend/src/modules/addresses/addresses.service.ts`
- Create: `apps/backend/tests/addresses/addresses-crud.test.ts`

This is the heart of the slice. Build it test-first in chunks. Steps 1-4 = list+create; Steps 5-8 = get/update/delete + default + ownership.

- [ ] **Step 1: Write the failing create+list tests**

Create `apps/backend/tests/addresses/addresses-crud.test.ts`:
```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomerToken, makeAdminToken, seedZoneWithPincode } from './helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }

const base = { label: 'Home', line1: '12 MG Road', pincode: '390001' };

describe('POST /me/addresses + GET /me/addresses', () => {
  it('customer creates an address (first one auto-default) with live serviceability', async () => {
    await seedZoneWithPincode('Vadodara', 14900, '390001');
    const tok = await makeCustomerToken();
    const res = await app.inject({ method: 'POST', url: '/me/addresses', headers: auth(tok), payload: base });
    expect(res.statusCode).toBe(201);
    expect(res.json()).toMatchObject({
      label: 'Home', line1: '12 MG Road', pincode: '390001',
      isDefault: true, serviceable: true, zone: { name: 'Vadodara', visitFeePaise: 14900 },
    });
  });

  it('out-of-area pincode still saves (201) but serviceable:false + message', async () => {
    const tok = await makeCustomerToken();
    const res = await app.inject({ method: 'POST', url: '/me/addresses', headers: auth(tok), payload: { ...base, pincode: '395003' } });
    expect(res.statusCode).toBe(201);
    expect(res.json()).toMatchObject({ serviceable: false, zone: null, message: "We don't serve this area yet" });
  });

  it('GET lists only the caller’s own active addresses with LIVE serviceability', async () => {
    await seedZoneWithPincode('Vadodara', 14900, '390001');
    const a = await makeCustomerToken();
    await app.inject({ method: 'POST', url: '/me/addresses', headers: auth(a), payload: base });
    const b = await makeCustomerToken();
    await app.inject({ method: 'POST', url: '/me/addresses', headers: auth(b), payload: { ...base, label: 'B' } });
    const listA = await app.inject({ method: 'GET', url: '/me/addresses', headers: auth(a) });
    expect(listA.statusCode).toBe(200);
    expect(listA.json()).toHaveLength(1);
    expect(listA.json()[0].label).toBe('Home');
    expect(listA.json()[0].serviceable).toBe(true);
  });

  it('coverage expansion: an out-of-area address becomes serviceable after admin adds its pincode (re-resolve on read)', async () => {
    const tok = await makeCustomerToken();
    const created = (await app.inject({ method: 'POST', url: '/me/addresses', headers: auth(tok), payload: { ...base, pincode: '390050' } })).json();
    expect(created.serviceable).toBe(false);
    await seedZoneWithPincode('Vadodara', 14900, '390050');
    const list = (await app.inject({ method: 'GET', url: '/me/addresses', headers: auth(tok) })).json();
    expect(list[0].serviceable).toBe(true);
    expect(list[0].zone.name).toBe('Vadodara');
  });

  it('non-CUSTOMER (admin) → 403; no token → 401; lat without lng → 400', async () => {
    const adm = await makeAdminToken('MANAGER');
    expect((await app.inject({ method: 'POST', url: '/me/addresses', headers: auth(adm), payload: base })).statusCode).toBe(403);
    expect((await app.inject({ method: 'GET', url: '/me/addresses' })).statusCode).toBe(401);
    const tok = await makeCustomerToken();
    expect((await app.inject({ method: 'POST', url: '/me/addresses', headers: auth(tok), payload: { ...base, lat: 22.3 } })).statusCode).toBe(400);
  });
});
```

- [ ] **Step 2: Run — confirm FAIL**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/addresses/addresses-crud.test.ts
```
Expected: FAIL (routes not registered).

- [ ] **Step 3: Create `addresses.service.ts` with list + create**

Create `apps/backend/src/modules/addresses/addresses.service.ts`. The service resolves the Customer row from `userId` (CUSTOMER-only — the route guards role, but the service also throws if no customer row), and assembles serviceability via `resolvePincode`:
```ts
import { prisma } from '../../shared/database/prisma.js';
import { ForbiddenError, NotFoundError } from '../../shared/errors.js';
import { resolvePincode } from './serviceability.service.js';
import { toAddressDto, type AddressDto } from './addresses.types.js';
import type { CreateAddressBody, UpdateAddressBody } from './addresses.schemas.js';

/** Resolve the caller's Customer row (CUSTOMER self-service only). */
async function requireCustomer(userId: string): Promise<{ id: string }> {
  const c = await prisma.customer.findFirst({ where: { userId, deletedAt: null } });
  if (!c) throw new ForbiddenError('Only customers have addresses');
  return { id: c.id };
}

export async function listAddresses(userId: string): Promise<AddressDto[]> {
  const { id: customerId } = await requireCustomer(userId);
  const rows = await prisma.address.findMany({
    where: { customerId, deletedAt: null, status: 'ACTIVE' },
    orderBy: [{ isDefault: 'desc' }, { createdAt: 'asc' }],
  });
  // re-resolve serviceability live for each (stored zoneId is just a hint)
  return Promise.all(rows.map(async (a) => toAddressDto(a, await resolvePincode(a.pincode))));
}

export async function createAddress(userId: string, body: CreateAddressBody): Promise<AddressDto> {
  const { id: customerId } = await requireCustomer(userId);
  const svc = await resolvePincode(body.pincode);
  const row = await prisma.$transaction(async (tx) => {
    const count = await tx.address.count({ where: { customerId, deletedAt: null } });
    const makeDefault = body.isDefault === true || count === 0; // first address auto-defaults
    if (makeDefault) {
      await tx.address.updateMany({ where: { customerId, deletedAt: null, isDefault: true }, data: { isDefault: false } });
    }
    return tx.address.create({
      data: {
        customerId,
        label: body.label,
        line1: body.line1,
        line2: body.line2 ?? null,
        landmark: body.landmark ?? null,
        pincode: body.pincode,
        lat: body.lat ?? null,
        lng: body.lng ?? null,
        zoneId: svc.zone?.id ?? null,   // resolved-at-save hint
        isDefault: makeDefault,
      },
    });
  });
  return toAddressDto(row, svc);
}
```

- [ ] **Step 4: Add list+create routes (partial route file) + run to GREEN for these tests**

In `apps/backend/src/modules/addresses/addresses.routes.ts`, extend imports and add the two routes. The full final route file (all CRUD) is shown in Task 5 Step 3 — for now add list + create so Step-1 tests pass. Update the file to:
```ts
import type { FastifyInstance } from 'fastify';
import { requireAuth } from '../../shared/middleware/auth.js';
import { ValidationError, ForbiddenError } from '../../shared/errors.js';
import { serviceabilityQuery, createAddressBody, updateAddressBody } from './addresses.schemas.js';
import { resolvePincode } from './serviceability.service.js';
import { listAddresses, createAddress, getAddress, updateAddress, deleteAddress } from './addresses.service.js';

/** /me/addresses is CUSTOMER self-service only. */
function requireCustomerRole(req: { user?: { role: string } }): void {
  if (req.user?.role !== 'CUSTOMER') throw new ForbiddenError('Only customers have addresses');
}

export async function registerAddressesRoutes(app: FastifyInstance) {
  app.get('/serviceability', { preHandler: [requireAuth] }, async (req, reply) => {
    const q = serviceabilityQuery.safeParse(req.query);
    if (!q.success) throw new ValidationError(q.error.issues[0]?.message ?? 'Invalid query');
    return reply.send(await resolvePincode(q.data.pincode));
  });

  app.get('/me/addresses', { preHandler: [requireAuth] }, async (req, reply) => {
    requireCustomerRole(req);
    return reply.send(await listAddresses(req.user!.id));
  });

  app.post('/me/addresses', { preHandler: [requireAuth] }, async (req, reply) => {
    requireCustomerRole(req);
    const p = createAddressBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.code(201).send(await createAddress(req.user!.id, p.data));
  });

  app.get('/me/addresses/:id', { preHandler: [requireAuth] }, async (req, reply) => {
    requireCustomerRole(req);
    return reply.send(await getAddress(req.user!.id, (req.params as { id: string }).id));
  });

  app.patch('/me/addresses/:id', { preHandler: [requireAuth] }, async (req, reply) => {
    requireCustomerRole(req);
    const p = updateAddressBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.send(await updateAddress(req.user!.id, (req.params as { id: string }).id, p.data));
  });

  app.delete('/me/addresses/:id', { preHandler: [requireAuth] }, async (req, reply) => {
    requireCustomerRole(req);
    await deleteAddress(req.user!.id, (req.params as { id: string }).id);
    return reply.code(204).send();
  });
}
```
NOTE: this route file references `getAddress`/`updateAddress`/`deleteAddress` which are implemented in Task 5 — so the build will fail until Task 5 Step 2 is done. Recommended: do Tasks 4 and 5 together (this slice's CRUD is one coherent unit). After Task 5 Step 2, run:
```bash
set -a && . ./.env && set +a && pnpm test -- tests/addresses/addresses-crud.test.ts
```
Expected (after Task 5): the create+list tests PASS.

- [ ] **Step 5: Commit (after Task 5 lands the rest)**
Defer the commit to Task 5 Step 5 (CRUD ships as one unit).

---

## Task 5: get / update / delete + default-reassignment + ownership

**Files:**
- Modify: `apps/backend/src/modules/addresses/addresses.service.ts`
- Modify: `apps/backend/tests/addresses/addresses-crud.test.ts`

- [ ] **Step 1: Add the get/update/delete/default/ownership tests**

Append to `apps/backend/tests/addresses/addresses-crud.test.ts`:
```ts
describe('GET/PATCH/DELETE /me/addresses/:id + default rule', () => {
  it('GET :id returns own; another customer’s id → 404 (no IDOR)', async () => {
    const a = await makeCustomerToken();
    const addr = (await app.inject({ method: 'POST', url: '/me/addresses', headers: auth(a), payload: base })).json();
    const got = await app.inject({ method: 'GET', url: `/me/addresses/${addr.id}`, headers: auth(a) });
    expect(got.statusCode).toBe(200);
    expect(got.json().id).toBe(addr.id);
    const b = await makeCustomerToken();
    expect((await app.inject({ method: 'GET', url: `/me/addresses/${addr.id}`, headers: auth(b) })).statusCode).toBe(404);
  });

  it('GET a non-existent id → 404', async () => {
    const a = await makeCustomerToken();
    expect((await app.inject({ method: 'GET', url: '/me/addresses/00000000-0000-0000-0000-000000000000', headers: auth(a) })).statusCode).toBe(404);
  });

  it('PATCH updates own fields; can clear line2 to null', async () => {
    const a = await makeCustomerToken();
    const addr = (await app.inject({ method: 'POST', url: '/me/addresses', headers: auth(a), payload: { ...base, line2: 'Flat 4' } })).json();
    const res = await app.inject({ method: 'PATCH', url: `/me/addresses/${addr.id}`, headers: auth(a), payload: { label: 'Work', line2: null } });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ label: 'Work', line2: null });
  });

  it('PATCH another customer’s address → 404; empty body → 400', async () => {
    const a = await makeCustomerToken();
    const addr = (await app.inject({ method: 'POST', url: '/me/addresses', headers: auth(a), payload: base })).json();
    const b = await makeCustomerToken();
    expect((await app.inject({ method: 'PATCH', url: `/me/addresses/${addr.id}`, headers: auth(b), payload: { label: 'X' } })).statusCode).toBe(404);
    expect((await app.inject({ method: 'PATCH', url: `/me/addresses/${addr.id}`, headers: auth(a), payload: {} })).statusCode).toBe(400);
  });

  it('PATCH pincode re-resolves the zone (serviceability updates)', async () => {
    await seedZoneWithPincode('Vadodara', 14900, '390001');
    const a = await makeCustomerToken();
    const addr = (await app.inject({ method: 'POST', url: '/me/addresses', headers: auth(a), payload: { ...base, pincode: '395003' } })).json();
    expect(addr.serviceable).toBe(false);
    const res = await app.inject({ method: 'PATCH', url: `/me/addresses/${addr.id}`, headers: auth(a), payload: { pincode: '390001' } });
    expect(res.json()).toMatchObject({ serviceable: true, zone: { name: 'Vadodara' } });
  });

  it('setting a new default clears the previous one (exactly one default)', async () => {
    const a = await makeCustomerToken();
    const first = (await app.inject({ method: 'POST', url: '/me/addresses', headers: auth(a), payload: base })).json();
    const second = (await app.inject({ method: 'POST', url: '/me/addresses', headers: auth(a), payload: { ...base, label: 'Office' } })).json();
    expect(first.isDefault).toBe(true);
    expect(second.isDefault).toBe(false);
    await app.inject({ method: 'PATCH', url: `/me/addresses/${second.id}`, headers: auth(a), payload: { isDefault: true } });
    const list = (await app.inject({ method: 'GET', url: '/me/addresses', headers: auth(a) })).json();
    const defaults = list.filter((x: { isDefault: boolean }) => x.isDefault);
    expect(defaults).toHaveLength(1);
    expect(defaults[0].id).toBe(second.id);
  });

  it('DELETE soft-deletes own; then it is gone from list and GET :id → 404', async () => {
    const a = await makeCustomerToken();
    const addr = (await app.inject({ method: 'POST', url: '/me/addresses', headers: auth(a), payload: base })).json();
    expect((await app.inject({ method: 'DELETE', url: `/me/addresses/${addr.id}`, headers: auth(a) })).statusCode).toBe(204);
    expect((await app.inject({ method: 'GET', url: '/me/addresses', headers: auth(a) })).json()).toHaveLength(0);
    expect((await app.inject({ method: 'GET', url: `/me/addresses/${addr.id}`, headers: auth(a) })).statusCode).toBe(404);
  });

  it('DELETE another customer’s address → 404', async () => {
    const a = await makeCustomerToken();
    const addr = (await app.inject({ method: 'POST', url: '/me/addresses', headers: auth(a), payload: base })).json();
    const b = await makeCustomerToken();
    expect((await app.inject({ method: 'DELETE', url: `/me/addresses/${addr.id}`, headers: auth(b) })).statusCode).toBe(404);
  });

  it('no address CRUD writes any AuditLog row (decision 8: addresses are not audited)', async () => {
    await seedZoneWithPincode('Vadodara', 14900, '390001');
    const a = await makeCustomerToken();
    const addr = (await app.inject({ method: 'POST', url: '/me/addresses', headers: auth(a), payload: base })).json();
    await app.inject({ method: 'PATCH', url: `/me/addresses/${addr.id}`, headers: auth(a), payload: { label: 'X' } });
    await app.inject({ method: 'DELETE', url: `/me/addresses/${addr.id}`, headers: auth(a) });
    expect(await prisma.auditLog.count()).toBe(0);
  });
});
```

- [ ] **Step 2: Implement get/update/delete in `addresses.service.ts`**

Append to `apps/backend/src/modules/addresses/addresses.service.ts`. Ownership is enforced by scoping every query to the caller's `customerId` (another customer's id is indistinguishable from missing → both 404):
```ts
/** Load an address scoped to the caller; 404 if not theirs or soft-deleted. */
async function ownAddressOrThrow(customerId: string, id: string) {
  const a = await prisma.address.findFirst({ where: { id, customerId, deletedAt: null } });
  if (!a) throw new NotFoundError('Address not found');
  return a;
}

export async function getAddress(userId: string, id: string): Promise<AddressDto> {
  const { id: customerId } = await requireCustomer(userId);
  const a = await ownAddressOrThrow(customerId, id);
  return toAddressDto(a, await resolvePincode(a.pincode));
}

export async function updateAddress(userId: string, id: string, body: UpdateAddressBody): Promise<AddressDto> {
  const { id: customerId } = await requireCustomer(userId);
  await ownAddressOrThrow(customerId, id);
  // re-resolve zone if the pincode is being changed (else keep the row's current pincode for the verdict)
  const row = await prisma.$transaction(async (tx) => {
    const existing = await tx.address.findFirst({ where: { id, customerId, deletedAt: null } });
    if (!existing) throw new NotFoundError('Address not found');
    const data: Record<string, unknown> = { ...body };
    if (body.pincode !== undefined) {
      const svc = await resolvePincode(body.pincode);
      data.zoneId = svc.zone?.id ?? null;   // refresh the stored hint
    }
    if (body.isDefault === true) {
      await tx.address.updateMany({ where: { customerId, deletedAt: null, isDefault: true, NOT: { id } }, data: { isDefault: false } });
    }
    return tx.address.update({ where: { id }, data });
  });
  return toAddressDto(row, await resolvePincode(row.pincode));
}

export async function deleteAddress(userId: string, id: string): Promise<void> {
  const { id: customerId } = await requireCustomer(userId);
  await ownAddressOrThrow(customerId, id);
  await prisma.address.update({ where: { id }, data: { deletedAt: new Date() } });
}
```
Notes: `data: { ...body }` is safe — `updateAddressBody` is `.strict()` and every key (label/line1/line2/landmark/pincode/lat/lng/isDefault) is a real `Address` column. `isDefault: false` in a PATCH does NOT auto-promote another address (decision 7 — deleting/unsetting the default leaves none). No `AuditLog` writes anywhere (decision 8).

- [ ] **Step 3: Confirm the full route file (from Task 4 Step 4) is in place**
All five routes (list/create/get/update/delete) + `requireCustomerRole` were added in Task 4 Step 4. They reference the service fns now implemented. No further route edits.

- [ ] **Step 4: Run the full CRUD test file → GREEN**
```bash
set -a && . ./.env && set +a && pnpm test -- tests/addresses/addresses-crud.test.ts
```
Expected: PASS (create+list from Task 4 AND get/update/delete/default/ownership/no-audit here).

- [ ] **Step 5: Build + commit the whole CRUD unit**
```bash
cd apps/backend && pnpm build   # expect clean
git add apps/backend/src/modules/addresses/addresses.service.ts apps/backend/src/modules/addresses/addresses.routes.ts apps/backend/tests/addresses/addresses-crud.test.ts
git commit -m "feat(backend): customer /me/addresses CRUD — owner-scoped, default-enforced, serviceability in DTO (addresses slice B)"
```

---

## Task 6: full suite + reviews + status/changelog

**Files:**
- Modify: `STATUS.md`, `CHANGELOG.md`

- [ ] **Step 1: Full backend suite**
```bash
set -a && . ./.env && set +a && cd apps/backend && pnpm test
```
Expected: ALL green (the prior 131 + the new address-CRUD tests). Note the total.

- [ ] **Step 2: Run the FixCare review agents (read-only, before merge)**

Spawn against this diff:
- `prisma-migration-reviewer` — the `address` migration (additive, indexed, nullable zone FK; note: `Address` stores PII — confirm no PII concern in the *migration* itself, that's a runtime/logging concern).
- `golden-rules-auditor` — **Golden Rule 7 is the focus**: assert no address PII (line1/line2/landmark/pincode/lat/lng/label) reaches any log or audit; confirm decision-8 (no audit on address CRUD) holds; ownership (404-not-403 on others' ids); CUSTOMER-only.
- `fraud-vector-checker` — address paths (no self-assigned zone — zone is resolved server-side from pincode, not customer input; address-frequency anomaly detection is a later module).

Address blocking findings (re-run the relevant test after each fix). Then run `/code-review` on the branch (twice if the first pass finds fixes, as with prior slices).

- [ ] **Step 3: Update `STATUS.md`**
Phase: addresses module COMPLETE (Slice A merged; Slice B done on branch). Active task → Slice B summary. Last shipped bullet (Address model + `/me/addresses` CRUD + serviceability-in-DTO + default rule; test count; review result). Next 3 → booking lifecycle (with the zone+price snapshot requirement). `_Last updated_` 2026-06-07.

- [ ] **Step 4: `CHANGELOG.md` entry**
Under `## 2026-06-07 — Addresses slice B (customer address CRUD) — addresses module COMPLETE`: Address model + migration; `/me/addresses` GET/POST/GET:id/PATCH/DELETE (CUSTOMER-only, owner-scoped 404-not-403, one-default-enforced transaction, resolve-at-save + re-resolve-on-read serviceability in every DTO, out-of-area saves 201, lat/lng both-or-neither, soft-delete); no audit on address CRUD (decision 8); no address PII in logs/audit (Golden Rule 7); test count; review notes.

- [ ] **Step 5: Commit docs**
```bash
git add STATUS.md CHANGELOG.md
git commit -m "docs: status + changelog for addresses slice B"
```

- [ ] **Step 6: Finish the branch**
Use `superpowers:finishing-a-development-branch` → PR `feature/addresses-crud` → `main`, `/code-review`. (Pushing/PR is the user's step in this environment.)

---

## Self-Review notes

- **Spec coverage (Slice B):** Address model + AddressStatus + optional geo + cached zoneId hint ✓ (T1); AddressDto with explicit serviceability ✓ (T2); create/update Zod incl. lat/lng both-or-neither + nullable-on-update ✓ (T3); owner-scoped list/create with resolve-at-save + re-resolve-on-read + first-auto-default + out-of-area-201 ✓ (T4); get/update/delete + one-default-enforced tx + ownership-404 + pincode-re-resolve + no-audit ✓ (T5). CUSTOMER-only (403 for others) ✓. Deferred items (PostGIS, arrival-GPS, booking enforcement, marketing page) remain out of scope — correct.
- **Placeholder scan:** none — every step has concrete code/commands.
- **Type consistency:** `AddressDto`/`toAddressDto(a, s)` (mapper takes the row + a `Serviceability`) used consistently; `createAddressBody`/`updateAddressBody`, `listAddresses`/`createAddress`/`getAddress`/`updateAddress`/`deleteAddress`, `requireCustomer` (service) vs `requireCustomerRole` (route) named distinctly. `prisma.address` accessor. `resolvePincode`→`Serviceability` reused from Slice A unchanged. `zone: Serviceability['zone']` keeps the DTO's zone shape identical to the serviceability endpoint.
- **Tasks 4+5 coupling:** the route file (T4 S4) references service fns implemented in T5 — flagged to execute T4+T5 together as one CRUD unit; the commit lands in T5 S5.
- **PII:** no `AuditLog` writes in the service at all (decision 8); DTO mapping is explicit (no raw Prisma); nothing logs body fields.
