# Booking B4b — R2 Photo Evidence + Diagnosis Photos Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cloudflare R2 photo-evidence pipeline (presigned direct uploads, HEAD-verified) + the 2 mandatory diagnosis photos as a hard gate on ARRIVED→DIAGNOSED.

**Architecture:** A `PhotoStorage` third-party wrapper (`shared/third-party/r2-storage.ts`, Dev stub + real R2 impl, otp-sender pattern) issues presigned PUT/GET URLs; two technician-jobs endpoints (sign, confirm) create soft-delete-replaceable `PhotoEvidence` rows keyed by a `PhotoKind` slot enum; `diagnoseJob` refuses to transition unless both diagnosis slots have active rows; customer + technician DTOs surface `{kind, capturedAt, url}` with 15-min signed reads.

**Tech Stack:** Node 22, Fastify 5, Prisma 6, Zod 4, Vitest; new deps `@aws-sdk/client-s3` + `@aws-sdk/s3-request-presigner`.

## Global Constraints

- Commit author MUST be `MohammadKaifSaiyad <saiyedkgn6@gmail.com>` with NO Co-Authored-By/Claude trailer (hook rejects it). Commit via `git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "..."`.
- Run all backend commands from `apps/backend` with env sourced: `set -a && source .env && set +a` before `pnpm vitest run` / `pnpm tsc --noEmit` (plain invocation fails config validation). Docker stack must be up (`docker compose up -d` from repo root).
- No `any`; TypeScript strict; ESM imports with `.js` extension; Zod-validated route inputs; DB writes in the service layer; DTOs only (never raw Prisma objects); auth check first; ownership verified (foreign id → 404/403 per existing idiom).
- Rule 5: audit writes inside the same transaction. Rule 7: NO PII/coords/keys-with-credentials in logs or audit metadata — audit records `hasGeotag`, never lat/lng.
- Photos are evidence: soft-delete only (`deletedAt`), never hard-delete. One ACTIVE row per (booking, kind), enforced in the service transaction.
- Presign policy: `image/jpeg` only, `contentLengthBytes` 1..1_048_576 signed into the URL (cryptographic 1MB cap), 24h upload expiry, 15-min read expiry. No server-side image processing (app compresses <500KB client-side).
- R2 config keys are OPTIONAL in the Zod config (feature inert until provisioned, MSG91 posture).
- Design (source of truth): `docs/designs/2026-07-11-booking-b4b-photos-design.md`. One refinement vs the design: the sign body carries `contentLengthBytes` — it is HOW the design's "1MB cap" is enforced (the length is signed into the presigned PUT).

---

### Task 1: Schema — PhotoKind, PhotoEvidence, PHOTO_UPLOADED (+ migration, both DBs)

**Files:**
- Modify: `apps/backend/prisma/schema.prisma` (AuditAction enum ~line 196; Booking model ~line 334; new enum+model after DiagnosedIssue)
- Modify: `apps/backend/tests/schema/helpers.ts:15` (TRUNCATE list)
- Test: `apps/backend/tests/schema/photo-evidence.test.ts`

**Interfaces:**
- Consumes: existing `Booking` model.
- Produces: `PhotoKind` enum (`DIAGNOSIS_OVERVIEW`, `DIAGNOSIS_CLOSEUP`), `prisma.photoEvidence` (fields: `id, bookingId, kind, r2Key, geotagLat?, geotagLng?, capturedAt, deletedAt?, createdAt, updatedAt`), `Booking.photos: PhotoEvidence[]`, `AuditAction.PHOTO_UPLOADED`. Later tasks rely on these exact names.

- [ ] **Step 1: Write the failing test** (`apps/backend/tests/schema/photo-evidence.test.ts`)

```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { prisma, resetDb } from './helpers.js';

afterAll(() => prisma.$disconnect());
beforeEach(resetDb);

async function seedBooking() {
  const user = await prisma.user.create({ data: { phone: `98${Math.floor(Math.random() * 1e8)}`, role: 'CUSTOMER' } });
  const customer = await prisma.customer.create({ data: { userId: user.id, name: 'C' } });
  const zone = await prisma.zone.create({ data: { name: `Z-${Math.random().toString(36).slice(2, 8)}`, visitFeePaise: 9900 } });
  const cat = await prisma.serviceCategory.create({ data: { name: `Cat-${Math.random().toString(36).slice(2, 8)}` } });
  const service = await prisma.service.create({ data: { name: 'S', categoryId: cat.id, tier: 'BASIC', requiredSkill: 'AC' } });
  const address = await prisma.address.create({ data: { customerId: customer.id, line1: 'L1', pincode: '390001', zoneId: zone.id } });
  return prisma.booking.create({
    data: {
      bookingNumber: `FC-${Math.random().toString(36).slice(2, 8)}`,
      customerId: customer.id, addressId: address.id, serviceId: service.id,
      zoneId: zone.id, zoneName: zone.name, serviceName: service.name,
      visitFeePaise: 9900, laborPaise: 50000, laborTier: 'BASIC',
      scheduledSlot: new Date(Date.now() + 86_400_000),
    },
  });
}

describe('PhotoEvidence model', () => {
  it('stores a diagnosis photo slot with optional geotag and reads back via Booking.photos', async () => {
    const b = await seedBooking();
    await prisma.photoEvidence.create({
      data: { bookingId: b.id, kind: 'DIAGNOSIS_OVERVIEW', r2Key: `jobs/${b.id}/DIAGNOSIS_OVERVIEW-x.jpg`, capturedAt: new Date() },
    });
    const withPhotos = await prisma.booking.findUnique({ where: { id: b.id }, include: { photos: true } });
    expect(withPhotos!.photos).toHaveLength(1);
    expect(withPhotos!.photos[0]!.kind).toBe('DIAGNOSIS_OVERVIEW');
    expect(withPhotos!.photos[0]!.geotagLat).toBeNull();
    expect(withPhotos!.photos[0]!.deletedAt).toBeNull();
  });

  it('soft-delete replace: two rows for one kind, only one active', async () => {
    const b = await seedBooking();
    const first = await prisma.photoEvidence.create({
      data: { bookingId: b.id, kind: 'DIAGNOSIS_CLOSEUP', r2Key: `jobs/${b.id}/DIAGNOSIS_CLOSEUP-a.jpg`, capturedAt: new Date() },
    });
    await prisma.photoEvidence.update({ where: { id: first.id }, data: { deletedAt: new Date() } });
    await prisma.photoEvidence.create({
      data: { bookingId: b.id, kind: 'DIAGNOSIS_CLOSEUP', r2Key: `jobs/${b.id}/DIAGNOSIS_CLOSEUP-b.jpg`, capturedAt: new Date() },
    });
    expect(await prisma.photoEvidence.count({ where: { bookingId: b.id } })).toBe(2);
    expect(await prisma.photoEvidence.count({ where: { bookingId: b.id, deletedAt: null } })).toBe(1);
  });

  it('PHOTO_UPLOADED is a valid audit action', async () => {
    const log = await prisma.auditLog.create({ data: { action: 'PHOTO_UPLOADED', actorType: 'USER', metadata: { kind: 'DIAGNOSIS_OVERVIEW', hasGeotag: false } } });
    expect(log.action).toBe('PHOTO_UPLOADED');
  });
});
```

> NOTE for the implementer: check the exact required fields of `Service`/`Address` against `prisma/schema.prisma` when the test fails to compile — the seed above mirrors existing schema tests; copy any missing required field idiom from `tests/schema/` neighbors rather than changing the schema.

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/backend && set -a && source .env && set +a && pnpm vitest run tests/schema/photo-evidence.test.ts`
Expected: FAIL — `photoEvidence` does not exist on PrismaClient / `PHOTO_UPLOADED` not a valid enum value.

- [ ] **Step 3: Edit `apps/backend/prisma/schema.prisma`**

Add `PHOTO_UPLOADED` to the AuditAction enum (after `DIAGNOSIS_UPDATED`, line ~196):

```prisma
  DIAGNOSIS_UPDATED
  PHOTO_UPLOADED
}
```

Add to the Booking model, next to `bookingParts BookingPart[]` (~line 334):

```prisma
  photos             PhotoEvidence[]
```

Add after the `DiagnosedIssue` model block:

```prisma
// Photo evidence for a booking (B4b: 2 diagnosis slots; B5 appends 3 REPAIR_* slots).
// One ACTIVE row per (booking, kind) — a retake soft-deletes the old row and inserts a new
// one in the same transaction (evidence trail is never destroyed; NEVER hard-delete).
enum PhotoKind {
  DIAGNOSIS_OVERVIEW
  DIAGNOSIS_CLOSEUP
}

model PhotoEvidence {
  id         String    @id @default(cuid())
  bookingId  String
  booking    Booking   @relation(fields: [bookingId], references: [id])
  kind       PhotoKind
  r2Key      String // jobs/{bookingId}/{kind}-{uuid}.jpg — opaque, no PII
  geotagLat  Float? // nullable: indoor GPS is genuinely unavailable on budget devices
  geotagLng  Float?
  capturedAt DateTime // client-claimed capture time
  deletedAt  DateTime? // soft-delete = replaced by a retake
  createdAt  DateTime  @default(now())
  updatedAt  DateTime  @updatedAt

  @@index([bookingId, kind])
}
```

- [ ] **Step 4: Create + apply the migration on BOTH DBs**

```bash
cd apps/backend && set -a && source .env && set +a
pnpm prisma migrate dev --name photo_evidence
DATABASE_URL="$TEST_DATABASE_URL" pnpm prisma migrate deploy
```

Expected: migration `*_photo_evidence` created and applied; `migrate deploy` reports it applied to fixcare_test. (If Postgres is unreachable: `docker compose up -d` from the repo root first.)

- [ ] **Step 5: Add `"PhotoEvidence"` to the TRUNCATE list** in `apps/backend/tests/schema/helpers.ts:15` — the list becomes:

```ts
    'TRUNCATE TABLE "PhotoEvidence","BookingPart","DiagnosedIssue","JobSkip","Booking","Address","PincodeZone","PartsCatalog","ServicePrice","Service","ServiceCategory","Zone","AuditLog","RefreshToken","Admin","Merchant","Technician","Customer","User" RESTART IDENTITY CASCADE;'
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd apps/backend && set -a && source .env && set +a && pnpm vitest run tests/schema/photo-evidence.test.ts`
Expected: PASS (3 tests).

- [ ] **Step 7: Typecheck + commit**

```bash
pnpm tsc --noEmit
git add prisma/schema.prisma prisma/migrations tests/schema/photo-evidence.test.ts tests/schema/helpers.ts
git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(backend): PhotoEvidence model + PHOTO_UPLOADED audit action (B4b schema)"
```

---

### Task 2: PhotoStorage wrapper (Dev + R2) + config keys

**Files:**
- Create: `apps/backend/src/shared/third-party/r2-storage.ts`
- Modify: `apps/backend/src/shared/config.ts` (add optional R2_* keys after `OTP_MAX_VERIFY_ATTEMPTS`)
- Modify: `apps/backend/.env.example` (stub R2_* keys)
- Modify: `apps/backend/package.json` (via `pnpm add @aws-sdk/client-s3 @aws-sdk/s3-request-presigner`)
- Test: `apps/backend/tests/shared/r2-storage.test.ts`

**Interfaces:**
- Consumes: `config` from `../config.js`.
- Produces (later tasks import these exactly):
  - `interface PhotoStorage { presignUpload(key: string, contentLengthBytes: number): Promise<{ url: string; expiresAt: Date }>; objectExists(key: string): Promise<boolean>; presignRead(key: string): Promise<string>; }`
  - `class DevPhotoStorage implements PhotoStorage` with an extra test hook `markUploaded(key: string): void`
  - `const photoStorage: PhotoStorage` (module singleton via `makePhotoStorage()`)

- [ ] **Step 1: Install the SDK deps**

```bash
cd apps/backend && pnpm add @aws-sdk/client-s3 @aws-sdk/s3-request-presigner
```

Expected: both added to `dependencies`. (S3-compatible SDK is the documented R2 approach — `backend-stack.md:343`; no ADR needed.)

- [ ] **Step 2: Write the failing test** (`apps/backend/tests/shared/r2-storage.test.ts`)

```ts
import { describe, expect, it } from 'vitest';
import { DevPhotoStorage, photoStorage } from '../../src/shared/third-party/r2-storage.js';

describe('DevPhotoStorage', () => {
  it('presigns an upload with a 24h expiry and a deterministic dev URL', async () => {
    const s = new DevPhotoStorage();
    const { url, expiresAt } = await s.presignUpload('jobs/b1/DIAGNOSIS_OVERVIEW-x.jpg', 100_000);
    expect(url).toContain('jobs%2Fb1%2FDIAGNOSIS_OVERVIEW-x.jpg');
    expect(expiresAt.getTime()).toBeGreaterThan(Date.now() + 23 * 3600 * 1000);
  });

  it('objectExists is false until markUploaded', async () => {
    const s = new DevPhotoStorage();
    expect(await s.objectExists('jobs/b1/k.jpg')).toBe(false);
    s.markUploaded('jobs/b1/k.jpg');
    expect(await s.objectExists('jobs/b1/k.jpg')).toBe(true);
  });

  it('presignRead returns a dev read URL', async () => {
    const s = new DevPhotoStorage();
    expect(await s.presignRead('jobs/b1/k.jpg')).toContain('read');
  });

  it('the module singleton is the Dev impl outside production', () => {
    expect(photoStorage).toBeInstanceOf(DevPhotoStorage);
  });
});
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd apps/backend && set -a && source .env && set +a && pnpm vitest run tests/shared/r2-storage.test.ts`
Expected: FAIL — cannot find module `r2-storage.js`.

- [ ] **Step 4: Add the optional R2 keys to `apps/backend/src/shared/config.ts`** — insert after the `OTP_MAX_VERIFY_ATTEMPTS` line (line 14):

```ts
  // Cloudflare R2 (photo evidence). Optional until the account is provisioned — the storage
  // wrapper stays inert (Dev stub) without them; production requires all four.
  R2_ACCOUNT_ID: z.string().optional(),
  R2_ACCESS_KEY_ID: z.string().optional(),
  R2_SECRET_ACCESS_KEY: z.string().optional(),
  R2_BUCKET: z.string().optional(),
```

And append to `apps/backend/.env.example` (after the OTP block):

```
# Cloudflare R2 (photo evidence) — leave empty until the account is provisioned
R2_ACCOUNT_ID=""
R2_ACCESS_KEY_ID=""
R2_SECRET_ACCESS_KEY=""
R2_BUCKET=""
```

- [ ] **Step 5: Write the wrapper** (`apps/backend/src/shared/third-party/r2-storage.ts`)

```ts
import { S3Client, PutObjectCommand, GetObjectCommand, HeadObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { config } from '../config.js';

const UPLOAD_TTL_SECONDS = 24 * 3600; // 24h — infrastructure.md:186-205
const READ_TTL_SECONDS = 15 * 60; // 15-min signed customer reads (design decision 3)

/** Abstraction over photo object storage. The rest of the code depends on this, not the S3 SDK. */
export interface PhotoStorage {
  /** Presigned PUT: Content-Type pinned to image/jpeg and the exact byte length signed in (1MB cap). */
  presignUpload(key: string, contentLengthBytes: number): Promise<{ url: string; expiresAt: Date }>;
  /** HEAD the object — evidence must exist in R2 before it is recorded (Golden Rule 1). */
  objectExists(key: string): Promise<boolean>;
  /** Short-lived signed GET for DTOs. Never expose raw keys or permanent URLs. */
  presignRead(key: string): Promise<string>;
}

/** Dev/test storage: in-memory, deterministic URLs, no network. `markUploaded` fakes the PUT. */
export class DevPhotoStorage implements PhotoStorage {
  private uploaded = new Set<string>();
  markUploaded(key: string): void {
    this.uploaded.add(key);
  }
  async presignUpload(key: string, _contentLengthBytes: number): Promise<{ url: string; expiresAt: Date }> {
    return { url: `https://dev-r2.local/upload/${encodeURIComponent(key)}`, expiresAt: new Date(Date.now() + UPLOAD_TTL_SECONDS * 1000) };
  }
  async objectExists(key: string): Promise<boolean> {
    return this.uploaded.has(key);
  }
  async presignRead(key: string): Promise<string> {
    return `https://dev-r2.local/read/${encodeURIComponent(key)}`;
  }
}

/** Real R2 (S3-compatible). Throws a clear error if the R2 env keys are missing. */
export class R2PhotoStorage implements PhotoStorage {
  private readonly client: S3Client;
  private readonly bucket: string;
  constructor() {
    if (!config.R2_ACCOUNT_ID || !config.R2_ACCESS_KEY_ID || !config.R2_SECRET_ACCESS_KEY || !config.R2_BUCKET) {
      throw new Error('R2 storage is not configured (R2_ACCOUNT_ID/R2_ACCESS_KEY_ID/R2_SECRET_ACCESS_KEY/R2_BUCKET)');
    }
    this.bucket = config.R2_BUCKET;
    this.client = new S3Client({
      region: 'auto',
      endpoint: `https://${config.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
      credentials: { accessKeyId: config.R2_ACCESS_KEY_ID, secretAccessKey: config.R2_SECRET_ACCESS_KEY },
    });
  }
  async presignUpload(key: string, contentLengthBytes: number): Promise<{ url: string; expiresAt: Date }> {
    // ContentType + ContentLength become SIGNED headers: the PUT must match them exactly,
    // which is how the jpeg-only + 1MB policy is enforced cryptographically.
    const cmd = new PutObjectCommand({ Bucket: this.bucket, Key: key, ContentType: 'image/jpeg', ContentLength: contentLengthBytes });
    const url = await getSignedUrl(this.client, cmd, { expiresIn: UPLOAD_TTL_SECONDS });
    return { url, expiresAt: new Date(Date.now() + UPLOAD_TTL_SECONDS * 1000) };
  }
  async objectExists(key: string): Promise<boolean> {
    try {
      await this.client.send(new HeadObjectCommand({ Bucket: this.bucket, Key: key }));
      return true;
    } catch (e) {
      if (e && typeof e === 'object' && 'name' in e && (e as { name: string }).name === 'NotFound') return false;
      throw new Error('R2 objectExists failed'); // typed boundary: never leak raw SDK errors
    }
  }
  async presignRead(key: string): Promise<string> {
    return getSignedUrl(this.client, new GetObjectCommand({ Bucket: this.bucket, Key: key }), { expiresIn: READ_TTL_SECONDS });
  }
}

/** Factory: dev stub everywhere except production (same posture as makeOtpSender). */
export function makePhotoStorage(): PhotoStorage {
  return config.NODE_ENV === 'production' ? new R2PhotoStorage() : new DevPhotoStorage();
}

/** Module singleton — services import this; tests reach the Dev impl through it. */
export const photoStorage: PhotoStorage = makePhotoStorage();
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd apps/backend && set -a && source .env && set +a && pnpm vitest run tests/shared/r2-storage.test.ts`
Expected: PASS (4 tests).

- [ ] **Step 7: Typecheck + commit**

```bash
pnpm tsc --noEmit
git add src/shared/third-party/r2-storage.ts src/shared/config.ts .env.example package.json pnpm-lock.yaml tests/shared/r2-storage.test.ts
git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(backend): PhotoStorage third-party wrapper (Dev + R2) + config keys"
```

> Note: `pnpm-lock.yaml` lives at the REPO ROOT (pnpm workspace) — `git add` it from there: `git add ../../pnpm-lock.yaml`.

---

### Task 3: Sign + confirm photo endpoints (technician-jobs)

**Files:**
- Modify: `apps/backend/src/modules/technician-jobs/technician-jobs.schemas.ts` (append)
- Modify: `apps/backend/src/modules/technician-jobs/technician-jobs.service.ts` (append two fns + import)
- Modify: `apps/backend/src/modules/technician-jobs/technician-jobs.routes.ts` (two routes)
- Test: `apps/backend/tests/technician-jobs/photos.test.ts`

**Interfaces:**
- Consumes: `photoStorage`, `DevPhotoStorage` from `../../shared/third-party/r2-storage.js` (Task 2); `prisma.photoEvidence` (Task 1); existing `requireTechnician`, `ownAssignedBookingOrThrow` (NOTE: its `expectedState` union must gain `'ARRIVED'` — see Step 4), `UnprocessableError`.
- Produces (Task 4/5 rely on): `signPhotoUpload(userId, bookingId, body): Promise<{url: string; key: string; expiresAt: string}>`, `confirmPhoto(userId, bookingId, body): Promise<{id: string; kind: PhotoKind; capturedAt: string}>`; Zod exports `signPhotoBody`/`SignPhotoBody`, `confirmPhotoBody`/`ConfirmPhotoBody`; routes `POST /technician/jobs/:id/photos/sign` (200) and `POST /technician/jobs/:id/photos` (201).

- [ ] **Step 1: Write the failing tests** (`apps/backend/tests/technician-jobs/photos.test.ts`)

```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, makeTechnician, seedBookable } from '../bookings/helpers.js';
import { photoStorage, DevPhotoStorage } from '../../src/shared/third-party/r2-storage.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
function future() { return new Date(Date.now() + 86_400_000).toISOString(); }
const dev = photoStorage as DevPhotoStorage;

/** Booking driven to ARRIVED (photo window). Mirrors tests/bookings/diagnosis.test.ts. */
async function arrivedBooking() {
  const c = await makeCustomer();
  const f = await seedBookable(c.customerId);
  const t = await makeTechnician(['AC']);
  const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(t.token) });
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/en-route`, headers: auth(t.token) });
  const code = (await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/arrive`, headers: auth(t.token), payload: { lat: 22.31, lng: 73.18 } })).json().arrivalCode;
  await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/confirm-arrival`, headers: auth(c.token), payload: { code } });
  return { c, t, bookingId: booking.id as string };
}

/** sign + fake-PUT + confirm one slot; returns the confirm response. */
async function uploadPhoto(token: string, bookingId: string, kind: string, extra: Record<string, unknown> = {}) {
  const sign = (await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/photos/sign`, headers: auth(token), payload: { kind, contentLengthBytes: 200_000 } })).json();
  dev.markUploaded(sign.key);
  return app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/photos`, headers: auth(token), payload: { kind, key: sign.key, capturedAt: new Date().toISOString(), ...extra } });
}

describe('photo sign + confirm', () => {
  it('sign returns a presigned URL + booking-scoped key; confirm creates the row + audit', async () => {
    const { t, bookingId } = await arrivedBooking();
    const sign = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/photos/sign`, headers: auth(t.token), payload: { kind: 'DIAGNOSIS_OVERVIEW', contentLengthBytes: 200_000 } });
    expect(sign.statusCode).toBe(200);
    const body = sign.json();
    expect(body.key.startsWith(`jobs/${bookingId}/DIAGNOSIS_OVERVIEW-`)).toBe(true);
    expect(body.url).toContain('upload');

    dev.markUploaded(body.key);
    const confirm = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/photos`, headers: auth(t.token), payload: { kind: 'DIAGNOSIS_OVERVIEW', key: body.key, capturedAt: new Date().toISOString(), geotagLat: 22.31, geotagLng: 73.18 } });
    expect(confirm.statusCode).toBe(201);
    const rows = await prisma.photoEvidence.findMany({ where: { bookingId } });
    expect(rows).toHaveLength(1);
    expect(rows[0]!.geotagLat).toBe(22.31);
    const audits = await prisma.auditLog.findMany({ where: { action: 'PHOTO_UPLOADED' } });
    expect(audits).toHaveLength(1);
    const meta = audits[0]!.metadata as { hasGeotag: boolean; kind: string };
    expect(meta.hasGeotag).toBe(true);
    expect(meta.kind).toBe('DIAGNOSIS_OVERVIEW');
  });

  it('confirm without a real upload → 422; key from another booking → 422', async () => {
    const { t, bookingId } = await arrivedBooking();
    const sign = (await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/photos/sign`, headers: auth(t.token), payload: { kind: 'DIAGNOSIS_OVERVIEW', contentLengthBytes: 1000 } })).json();
    // no markUploaded — the object does not exist
    const notUploaded = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/photos`, headers: auth(t.token), payload: { kind: 'DIAGNOSIS_OVERVIEW', key: sign.key, capturedAt: new Date().toISOString() } });
    expect(notUploaded.statusCode).toBe(422);
    const foreignKey = 'jobs/some-other-booking/DIAGNOSIS_OVERVIEW-x.jpg';
    dev.markUploaded(foreignKey);
    const crossBooking = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/photos`, headers: auth(t.token), payload: { kind: 'DIAGNOSIS_OVERVIEW', key: foreignKey, capturedAt: new Date().toISOString() } });
    expect(crossBooking.statusCode).toBe(422);
  });

  it('retake replaces: old row soft-deleted, audit says replaced', async () => {
    const { t, bookingId } = await arrivedBooking();
    expect((await uploadPhoto(t.token, bookingId, 'DIAGNOSIS_CLOSEUP')).statusCode).toBe(201);
    expect((await uploadPhoto(t.token, bookingId, 'DIAGNOSIS_CLOSEUP')).statusCode).toBe(201);
    expect(await prisma.photoEvidence.count({ where: { bookingId, kind: 'DIAGNOSIS_CLOSEUP' } })).toBe(2);
    expect(await prisma.photoEvidence.count({ where: { bookingId, kind: 'DIAGNOSIS_CLOSEUP', deletedAt: null } })).toBe(1);
    const audits = await prisma.auditLog.findMany({ where: { action: 'PHOTO_UPLOADED' }, orderBy: { createdAt: 'asc' } });
    expect((audits[1]!.metadata as { replaced: boolean }).replaced).toBe(true);
  });

  it('validation: bad kind 400; oversize 400; geotag lat-without-lng 400; wrong state 409; foreign tech 403', async () => {
    const { c, t, bookingId } = await arrivedBooking();
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/photos/sign`, headers: auth(t.token), payload: { kind: 'SELFIE', contentLengthBytes: 1000 } })).statusCode).toBe(400);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/photos/sign`, headers: auth(t.token), payload: { kind: 'DIAGNOSIS_OVERVIEW', contentLengthBytes: 2_000_000 } })).statusCode).toBe(400);
    expect((await uploadPhoto(t.token, bookingId, 'DIAGNOSIS_OVERVIEW', { geotagLat: 22.3 })).statusCode).toBe(400);
    const other = await makeTechnician(['AC']);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/photos/sign`, headers: auth(other.token), payload: { kind: 'DIAGNOSIS_OVERVIEW', contentLengthBytes: 1000 } })).statusCode).toBe(403);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/photos/sign`, headers: auth(c.token), payload: { kind: 'DIAGNOSIS_OVERVIEW', contentLengthBytes: 1000 } })).statusCode).toBe(403);
    // wrong state: cancel then try to sign → 409
    const fresh = await arrivedBooking();
    await prisma.booking.update({ where: { id: fresh.bookingId }, data: { state: 'CUSTOMER_APPROVED' } });
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${fresh.bookingId}/photos/sign`, headers: auth(fresh.t.token), payload: { kind: 'DIAGNOSIS_OVERVIEW', contentLengthBytes: 1000 } })).statusCode).toBe(409);
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd apps/backend && set -a && source .env && set +a && pnpm vitest run tests/technician-jobs/photos.test.ts`
Expected: FAIL — 404s (routes don't exist yet).

- [ ] **Step 3: Append the Zod schemas** to `apps/backend/src/modules/technician-jobs/technician-jobs.schemas.ts`:

```ts
export const photoKind = z.enum(['DIAGNOSIS_OVERVIEW', 'DIAGNOSIS_CLOSEUP']);

// contentLengthBytes is signed into the presigned PUT — this IS the 1MB cap (jpeg-only is pinned
// server-side; the client never chooses the Content-Type).
export const signPhotoBody = z.object({
  kind: photoKind,
  contentLengthBytes: z.number().int().min(1).max(1_048_576),
}).strict();
export type SignPhotoBody = z.infer<typeof signPhotoBody>;

export const confirmPhotoBody = z.object({
  kind: photoKind,
  key: z.string().min(1),
  capturedAt: z.string().datetime(), // ISO 8601
  geotagLat: z.number().min(-90).max(90).optional(),
  geotagLng: z.number().min(-180).max(180).optional(),
}).strict().refine((b) => (b.geotagLat === undefined) === (b.geotagLng === undefined), {
  message: 'geotagLat and geotagLng must be provided together',
});
export type ConfirmPhotoBody = z.infer<typeof confirmPhotoBody>;
```

- [ ] **Step 4: Append the service functions** to `apps/backend/src/modules/technician-jobs/technician-jobs.service.ts`.

Add to the imports: `import { photoStorage } from '../../shared/third-party/r2-storage.js';`, `import { randomUUID } from 'node:crypto';`, extend the schemas type import with `SignPhotoBody, ConfirmPhotoBody`, and widen `ownAssignedBookingOrThrow`'s `expectedState` union (line 81) to `'ACCEPTED' | 'EN_ROUTE' | 'ARRIVED' | 'DIAGNOSED'`. Then append:

```ts
/** Presign a photo upload slot. ARRIVED-only (the on-site diagnosis window). */
export async function signPhotoUpload(userId: string, bookingId: string, body: SignPhotoBody): Promise<{ url: string; key: string; expiresAt: string }> {
  const tech = await requireTechnician(userId);
  await ownAssignedBookingOrThrow(tech.id, bookingId, 'ARRIVED');
  const key = `jobs/${bookingId}/${body.kind}-${randomUUID()}.jpg`;
  const { url, expiresAt } = await photoStorage.presignUpload(key, body.contentLengthBytes);
  return { url, key, expiresAt: expiresAt.toISOString() };
}

/** Confirm an uploaded photo: HEAD-verified (evidence must EXIST, not be claimed — Golden Rule 1),
 *  booking-scoped key, replace-by-soft-delete per (booking, kind), audited in-tx. */
export async function confirmPhoto(userId: string, bookingId: string, body: ConfirmPhotoBody): Promise<{ id: string; kind: ConfirmPhotoBody['kind']; capturedAt: string }> {
  const tech = await requireTechnician(userId);
  await ownAssignedBookingOrThrow(tech.id, bookingId, 'ARRIVED');
  if (!body.key.startsWith(`jobs/${bookingId}/`)) throw new UnprocessableError('Key does not belong to this booking');
  if (!(await photoStorage.objectExists(body.key))) throw new UnprocessableError('Upload not found — PUT the photo to the signed URL first');

  const created = await prisma.$transaction(async (tx) => {
    // Retake = replace: soft-delete the previous active row for this slot (evidence trail kept).
    const replaced = await tx.photoEvidence.updateMany({ where: { bookingId, kind: body.kind, deletedAt: null }, data: { deletedAt: new Date() } });
    const row = await tx.photoEvidence.create({
      data: { bookingId, kind: body.kind, r2Key: body.key, geotagLat: body.geotagLat ?? null, geotagLng: body.geotagLng ?? null, capturedAt: new Date(body.capturedAt) },
    });
    // No coords in audit (Rule 7) — only whether a geotag exists.
    await tx.auditLog.create({
      data: { action: 'PHOTO_UPLOADED', actorType: 'USER', actorId: userId, metadata: { bookingId, kind: body.kind, hasGeotag: body.geotagLat != null, replaced: replaced.count > 0 } },
    });
    return row;
  });
  return { id: created.id, kind: body.kind, capturedAt: created.capturedAt.toISOString() };
}
```

- [ ] **Step 5: Register the routes** in `apps/backend/src/modules/technician-jobs/technician-jobs.routes.ts` — extend the service import with `signPhotoUpload, confirmPhoto`, the schemas import with `signPhotoBody, confirmPhotoBody`, and add before the closing brace:

```ts
  app.post('/technician/jobs/:id/photos/sign', { preHandler: [requireAuth] }, async (req, reply) => {
    requireTechnicianRole(req);
    const p = signPhotoBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.send(await signPhotoUpload(req.user!.id, (req.params as { id: string }).id, p.data));
  });

  app.post('/technician/jobs/:id/photos', { preHandler: [requireAuth] }, async (req, reply) => {
    requireTechnicianRole(req);
    const p = confirmPhotoBody.safeParse(req.body);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.code(201).send(await confirmPhoto(req.user!.id, (req.params as { id: string }).id, p.data));
  });
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `cd apps/backend && set -a && source .env && set +a && pnpm vitest run tests/technician-jobs/photos.test.ts`
Expected: PASS (4 tests). Also run `pnpm vitest run tests/technician-jobs` to confirm no regression from the `ownAssignedBookingOrThrow` union widening.

- [ ] **Step 7: Typecheck + commit**

```bash
pnpm tsc --noEmit
git add src/modules/technician-jobs tests/technician-jobs/photos.test.ts
git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(backend): photo sign + confirm endpoints (HEAD-verified, replace-by-soft-delete)"
```

---

### Task 4: The diagnosis gate (2 photos required for ARRIVED→DIAGNOSED)

**Files:**
- Modify: `apps/backend/src/modules/technician-jobs/technician-jobs.service.ts:117-134` (`diagnoseJob`)
- Modify: `apps/backend/tests/bookings/helpers.ts` (add `seedDiagnosisPhotos`)
- Modify: `apps/backend/tests/bookings/diagnosis.test.ts:14-26` (`arrivedBooking` fixture)
- Test: extend `apps/backend/tests/technician-jobs/photos.test.ts`

**Interfaces:**
- Consumes: `prisma.photoEvidence` (Task 1); `uploadPhoto` test helper (Task 3).
- Produces: `diagnoseJob` throws `UnprocessableError` (422, message `'2 diagnosis photos required (overview + close-up)'`) when either slot is empty; passes `photoIds` in the transition evidence. Test helper `seedDiagnosisPhotos(bookingId: string): Promise<void>` in `tests/bookings/helpers.ts`.

- [ ] **Step 1: Write the failing tests** — append to `tests/technician-jobs/photos.test.ts` (inside the file, new describe; reuse `arrivedBooking`/`uploadPhoto`; add `seedIssue` to the helpers import from `../bookings/helpers.js`):

```ts
describe('diagnosis photo gate', () => {
  it('diagnose without both photos → 422; with both → 200 and audit carries photoIds', async () => {
    const { t, bookingId } = await arrivedBooking();
    const issue = await (async () => {
      const cat = await prisma.booking.findUnique({ where: { id: bookingId }, include: { service: true } });
      return seedIssue(cat!.service.categoryId);
    })();
    // 0 photos
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id } })).statusCode).toBe(422);
    // 1 of 2
    await uploadPhoto(t.token, bookingId, 'DIAGNOSIS_OVERVIEW');
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id } })).statusCode).toBe(422);
    // both
    await uploadPhoto(t.token, bookingId, 'DIAGNOSIS_CLOSEUP');
    const ok = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id } });
    expect(ok.statusCode).toBe(200);
    const audit = await prisma.auditLog.findFirst({ where: { action: 'BOOKING_STATE_CHANGED', metadata: { path: ['to'], equals: 'DIAGNOSED' } } });
    const meta = audit!.metadata as { photoIds?: string[] };
    expect(meta.photoIds).toHaveLength(2);
  });

  it('a soft-deleted (replaced-away) slot does not count', async () => {
    const { t, bookingId } = await arrivedBooking();
    const cat = await prisma.booking.findUnique({ where: { id: bookingId }, include: { service: true } });
    const issue = await seedIssue(cat!.service.categoryId);
    await uploadPhoto(t.token, bookingId, 'DIAGNOSIS_OVERVIEW');
    await uploadPhoto(t.token, bookingId, 'DIAGNOSIS_CLOSEUP');
    // simulate a slot whose only row got soft-deleted (no active replacement)
    await prisma.photoEvidence.updateMany({ where: { bookingId, kind: 'DIAGNOSIS_CLOSEUP' }, data: { deletedAt: new Date() } });
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id } })).statusCode).toBe(422);
  });
});
```

- [ ] **Step 2: Run to verify the new tests fail**

Run: `cd apps/backend && set -a && source .env && set +a && pnpm vitest run tests/technician-jobs/photos.test.ts`
Expected: the two new tests FAIL (diagnose currently succeeds without photos).

- [ ] **Step 3: Add the gate inside `diagnoseJob`'s transaction** — replace the `prisma.$transaction` block in `diagnoseJob` (`technician-jobs.service.ts:127-132`) with:

```ts
  await prisma.$transaction(async (tx) => {
    // Photo gate (B4b): both diagnosis slots must have an ACTIVE photo before the booking can be
    // DIAGNOSED — the photos are the evidence behind the estimate the customer approves (Rule 1).
    // Read inside the tx so a concurrent retake/replace can't be half-visible.
    const activePhotos = await tx.photoEvidence.findMany({
      where: { bookingId, deletedAt: null, kind: { in: ['DIAGNOSIS_OVERVIEW', 'DIAGNOSIS_CLOSEUP'] } },
      select: { id: true, kind: true },
    });
    const slots = new Set(activePhotos.map((p) => p.kind));
    if (!slots.has('DIAGNOSIS_OVERVIEW') || !slots.has('DIAGNOSIS_CLOSEUP')) {
      throw new UnprocessableError('2 diagnosis photos required (overview + close-up)');
    }
    await tx.booking.update({ where: { id: bookingId }, data: { diagnosedIssueId: issue.id, diagnosedIssueName: issue.name, diagnosedAt: new Date() } });
    // transitionBooking checks the from-state (still ARRIVED in this tx) via its optimistic lock.
    await transitionBooking(tx, booking, 'DIAGNOSED', { type: 'USER', kind: 'TECHNICIAN', id: userId }, { diagnosedIssueId: issue.id, photoIds: activePhotos.map((p) => p.id) });
    await tx.auditLog.create({ data: { action: 'DIAGNOSIS_UPDATED', actorType: 'USER', actorId: userId, metadata: { bookingId, action: 'diagnosed', diagnosedIssueId: issue.id } } });
  });
```

- [ ] **Step 4: Add the fixture helper** — append to `apps/backend/tests/bookings/helpers.ts`:

```ts
/** B4b: diagnosis requires both photo slots. Seed them directly (the photo ENDPOINTS have their own
 *  tests in tests/technician-jobs/photos.test.ts — fixtures shortcut through prisma for speed). */
export async function seedDiagnosisPhotos(bookingId: string) {
  for (const kind of ['DIAGNOSIS_OVERVIEW', 'DIAGNOSIS_CLOSEUP'] as const) {
    await prisma.photoEvidence.create({
      data: { bookingId, kind, r2Key: `jobs/${bookingId}/${kind}-seed.jpg`, capturedAt: new Date() },
    });
  }
}
```

(Confirm `helpers.ts` already exports/imports `prisma`; mirror its existing import if not.)

- [ ] **Step 5: Update the existing fixture** — in `apps/backend/tests/bookings/diagnosis.test.ts`, add `seedDiagnosisPhotos` to the `./helpers.js` import and insert into `arrivedBooking()` right after the confirm-arrival inject (line 22):

```ts
  await seedDiagnosisPhotos(booking.id); // B4b: diagnose now requires both photo slots filled
```

- [ ] **Step 6: Run the full suite** (other fixtures may also reach diagnose)

Run: `cd apps/backend && set -a && source .env && set +a && pnpm vitest run`
Expected: all tests pass. If any OTHER test file fails with the new 422, add the same one-line `seedDiagnosisPhotos(...)` call to its fixture with the same comment — that is the only sanctioned change to existing tests.

- [ ] **Step 7: Typecheck + commit**

```bash
pnpm tsc --noEmit
git add src/modules/technician-jobs/technician-jobs.service.ts tests/technician-jobs/photos.test.ts tests/bookings/helpers.ts tests/bookings/diagnosis.test.ts
git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(backend): 2-photo gate on ARRIVED→DIAGNOSED (keystone evidence)"
```

---

### Task 5: Photos in the customer + technician DTOs (signed reads)

**Files:**
- Modify: `apps/backend/src/modules/bookings/bookings.types.ts` (BookingDto + toBookingDto 4th param)
- Modify: `apps/backend/src/modules/bookings/bookings.service.ts` (`listBookings`, `getBooking`)
- Modify: `apps/backend/src/modules/technician-jobs/technician-jobs.types.ts` (TechnicianJobDto + 5th param)
- Modify: `apps/backend/src/modules/technician-jobs/technician-jobs.service.ts` (`listMyJobs`)
- Test: extend `apps/backend/tests/technician-jobs/photos.test.ts`

**Interfaces:**
- Consumes: `photoStorage.presignRead(key)` (Task 2); `PhotoEvidence` rows (Task 1).
- Produces: `PhotoSummary = { kind: PhotoKind; capturedAt: string; url: string }`; `BookingDto.photos: PhotoSummary[]`; `TechnicianJobDto.photos: PhotoSummary[]`; helper `toPhotoSummaries(photos: PhotoEvidence[]): Promise<PhotoSummary[]>` exported from `bookings.types.ts`.

- [ ] **Step 1: Write the failing test** — append to `tests/technician-jobs/photos.test.ts`:

```ts
describe('photos in DTOs', () => {
  it('customer GET /me/bookings/:id and technician /mine carry {kind, capturedAt, url} for ACTIVE photos only', async () => {
    const { c, t, bookingId } = await arrivedBooking();
    await uploadPhoto(t.token, bookingId, 'DIAGNOSIS_OVERVIEW');
    await uploadPhoto(t.token, bookingId, 'DIAGNOSIS_CLOSEUP');
    await uploadPhoto(t.token, bookingId, 'DIAGNOSIS_CLOSEUP'); // retake — only the replacement shows

    const got = (await app.inject({ method: 'GET', url: `/me/bookings/${bookingId}`, headers: auth(c.token) })).json();
    expect(got.photos).toHaveLength(2);
    const kinds = got.photos.map((p: { kind: string }) => p.kind).sort();
    expect(kinds).toEqual(['DIAGNOSIS_CLOSEUP', 'DIAGNOSIS_OVERVIEW']);
    for (const p of got.photos) {
      expect(p.url).toContain('read'); // signed READ url, never the raw key
      expect(p).not.toHaveProperty('r2Key');
    }
    const mine = (await app.inject({ method: 'GET', url: '/technician/jobs/mine', headers: auth(t.token) })).json();
    const job = mine.find((j: { id: string }) => j.id === bookingId);
    expect(job.photos).toHaveLength(2);
  });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd apps/backend && set -a && source .env && set +a && pnpm vitest run tests/technician-jobs/photos.test.ts`
Expected: the new test FAILS (`photos` undefined on both DTOs).

- [ ] **Step 3: Extend `bookings.types.ts`** — add to the imports `PhotoEvidence` (type) from `@prisma/client` and `photoStorage` from `../../shared/third-party/r2-storage.js`; add to `BookingDto`:

```ts
  // Active photo evidence with SHORT-LIVED signed read URLs (15 min) — raw r2Key never leaves the API.
  photos: PhotoSummary[];
```

and above/below the DTO:

```ts
export interface PhotoSummary { kind: PhotoEvidence['kind']; capturedAt: string; url: string }

/** Map ACTIVE photo rows to summaries with signed read URLs. Async because presignRead signs. */
export async function toPhotoSummaries(photos: PhotoEvidence[]): Promise<PhotoSummary[]> {
  return Promise.all(photos.map(async (p) => ({ kind: p.kind, capturedAt: p.capturedAt.toISOString(), url: await photoStorage.presignRead(p.r2Key) })));
}
```

then give `toBookingDto` a 4th param `photos: PhotoSummary[] = []` and add `photos,` to the returned object.

- [ ] **Step 4: Wire the bookings service** — in `listBookings` and `getBooking` (`bookings.service.ts:89-111`), extend the `include` with `photos: { where: { deletedAt: null } }` and pass the mapped summaries; e.g. `getBooking` becomes:

```ts
  const b = await prisma.booking.findFirst({
    where: { id, customerId, deletedAt: null },
    include: { technician: { include: { user: true } }, bookingParts: true, photos: { where: { deletedAt: null } } },
  });
  if (!b) throw new NotFoundError('Booking not found');
  return toBookingDto(b, b.technician ? { name: b.technician.name, phone: b.technician.user.phone } : undefined, b.bookingParts, await toPhotoSummaries(b.photos));
```

(and the analogous `rows.map` in `listBookings` becomes an async map wrapped in `Promise.all`). Import `toPhotoSummaries` from `./bookings.types.js`. Mutation endpoints (`createBooking`, `cancelBooking`, `confirmArrival`, approve/decline) keep the default `[]` — same convention as the technician block there.

- [ ] **Step 5: Wire the technician side** — `TechnicianJobDto` gets `photos: PhotoSummary[];` (import the type from `../bookings/bookings.types.js`), `toTechnicianJobDto` gets a 5th param `photos: PhotoSummary[] = []`, and `listMyJobs` includes `photos: { where: { deletedAt: null } }` and maps with `await toPhotoSummaries(b.photos)` (async map + `Promise.all`). `listAvailableJobs` keeps `[]` (unassigned jobs have no photos).

- [ ] **Step 6: Run the photo tests + the full suite**

Run: `cd apps/backend && set -a && source .env && set +a && pnpm vitest run tests/technician-jobs/photos.test.ts && pnpm vitest run`
Expected: all green (DTO additions are additive — no existing assertion checks for absence of `photos`).

- [ ] **Step 7: Typecheck + commit**

```bash
pnpm tsc --noEmit
git add src/modules/bookings src/modules/technician-jobs tests/technician-jobs/photos.test.ts
git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(backend): photo evidence in customer + technician DTOs (15-min signed reads)"
```

---

### Task 6: Full suite + docs (STATUS/CHANGELOG)

**Files:**
- Modify: `STATUS.md`, `CHANGELOG.md` (repo root)

- [ ] **Step 1: Full verification**

Run: `cd apps/backend && set -a && source .env && set +a && pnpm tsc --noEmit && pnpm vitest run`
Expected: 0 type errors; ALL tests pass (230 pre-B4b + the new photo/schema tests; note the exact count).
> Known harness quirk: two request-heavy files in one process can trip the global 100-req/min rate limiter (429s). If that happens, re-run the affected file alone to confirm green — it is a test-harness artifact, not a product bug.

- [ ] **Step 2: Update `STATUS.md`** — Active task → B4b done on branch (R2 wrapper, PhotoEvidence slots, HEAD-verified confirm, 2-photo diagnosis gate, signed-read DTOs, test count); move B4b out of the deferred list; Next targets → B5 completion handshake (now FULLY unblocked: OTP ✅ + photos ✅), noting B5 extends `PhotoKind` with the 3 REPAIR_* slots.

- [ ] **Step 3: Add a `CHANGELOG.md` entry** under `## 2026-07-11` (or a new dated header if a different day): R2 photo pipeline (presigned direct PUT, jpeg-only + 1MB signed cap, 24h), PhotoEvidence slot model (replace-by-soft-delete), HEAD-verified confirm, 2-photo gate on ARRIVED→DIAGNOSED with photoIds in the transition evidence, 15-min signed reads in customer/technician DTOs, R2_* optional config keys.

- [ ] **Step 4: Commit**

```bash
git add STATUS.md CHANGELOG.md
git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "docs: status + changelog for booking B4b (photo evidence)"
```

---

## Self-Review

**Spec coverage:** named slots + replace (T1 schema + T3 confirm) ✓; HEAD-verify (T3) ✓; signed customer reads now (T5) ✓; jpeg-only/1MB/24h presign (T2/T3 `contentLengthBytes`) ✓; geotag optional + both-or-neither (T3 schema) ✓; placement in technician-jobs + shared/third-party (T3/T2) ✓; diagnosis gate + evidence photoIds (T4) ✓; audit PHOTO_UPLOADED in-tx, hasGeotag not coords (T3) ✓; config optional R2 keys (T2) ✓; resetDb TRUNCATE (T1) ✓; the ONE existing-test change documented (T4) ✓; B5 readiness = enum-only extension (T1 comment) ✓. No gaps.

**Placeholder scan:** no TBD/TODO; every code step carries full code; commands have expected outcomes. The one deliberate degree of freedom (T1 seed fields, T4 Step 6 "other fixtures") names exactly what to do and the sanctioned pattern. ✓

**Type consistency:** `PhotoStorage`/`DevPhotoStorage`/`photoStorage` (T2) used identically in T3/T5; `signPhotoUpload`/`confirmPhoto` names match routes (T3); `PhotoSummary`/`toPhotoSummaries` defined in T5 and used in both DTO wirings; `seedDiagnosisPhotos` defined T4 Step 4, consumed T4 Step 5; `ownAssignedBookingOrThrow` union widened once (T3 Step 4) and relied on by both T3 fns. ✓
