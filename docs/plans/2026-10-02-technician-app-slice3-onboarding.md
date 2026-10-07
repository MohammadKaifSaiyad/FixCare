# Technician App Slice 3 — Onboarding + Verification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new technician fills in name + skills + service zones in the app and submits; ops verifies, sends back with a reason, suspends or reinstates via audited admin endpoints; the app re-checks status by itself; dispatch only offers in-zone jobs; logging into the wrong app is rejected with a clear message.

**Architecture:** Backend adds a status machine on the existing `Technician` row (reusing `TechnicianStatus`: PENDING → KYC_SUBMITTED → VERIFIED ⇄ SUSPENDED, with send-back KYC_SUBMITTED → PENDING) owned by a new `technicians` module, plus a `TechnicianZone` link table; every transition is a guarded `updateMany` + audit row in one transaction. `profiles` delegates its technician branch to `technicians`; `technician-jobs` filters dispatch by the technician's zones; `auth.verifyOtp` rejects a role mismatch after the OTP is proven. The technician app replaces the static pending screen with a `HomeGate` that watches the session and shows onboarding / under review (30 s poll, paused in background) / suspended / jobs.

**Tech Stack:** Backend — Node 22, Fastify 5, TypeScript strict, Prisma 6 / Postgres 16, Zod 4, vitest 4 (real DB). Apps — Flutter 3 / Dart 3, Riverpod 3 (`@riverpod` codegen), freezed 4 + json_serializable, dio 5, http_mock_adapter, flutter_test.

**Spec:** `docs/designs/2026-10-02-technician-app-slice3-onboarding-design.md`

## Global Constraints

- Branch `feature/technician-app-slice3-onboarding`; run `git branch --show-current` before every commit; never commit to `main`.
- Git: if `/usr/bin/git` fails with the Xcode-license error, use `/Library/Developer/CommandLineTools/usr/bin/git` (same repo, same commands).
- Commit author `MohammadKaifSaiyad <saiyedkgn6@gmail.com>` (`git -c user.name=MohammadKaifSaiyad -c user.email=saiyedkgn6@gmail.com commit …`); NO Co-Authored-By / Claude trailer.
- NEVER stage `apps/customer/ios/*`, `apps/customer/ios/Podfile.lock`, or any `xcshareddata/swiftpm/` folder (pre-existing, founder-owned). Stage files by explicit path.
- Golden Rule 6/7 — no documents, no Aadhaar; no PII in logs or audit metadata: audit rows carry field NAMES and status values only (plus ops' reason text); no `console.log` / `print` / `debugPrint`; the admin list shows the phone ONLY through `maskPhone()` (`src/shared/utils/mask.ts`).
- Golden Rule 5 — every status change and every skills/zones edit writes its audit row in the SAME transaction as the write.
- Backend: auth first (`requireAuth` preHandler), Zod at the boundary (body, params AND query), DB writes in the service layer, DTOs only (never raw Prisma rows), TS strict, no `any`; errors via `src/shared/errors.ts` classes (envelope `{code, message}`). Zone data is read through `catalog.service` functions; booking data through `bookings.state` helpers — no cross-module table queries in new code.
- Apps: Riverpod + repositories only (UI never touches dio); never set a global dio content-type; bodyless requests carry no body; busy flags reset in `try/finally`; `if (!mounted) return;` after every await before touching `context`/`setState`; Failure messages shown verbatim; unexpected throws reported via `FlutterError.reportError` (never swallowed).
- Exact copy strings (use verbatim):
  - backend 409 `PROFILE_LOCKED`: `Your profile is locked while under review`
  - backend 409 `INVALID_TECHNICIAN_TRANSITION`: submit `Your profile has already been submitted`; verify / send-back `Only a technician awaiting review can be verified or sent back`; suspend `Only a verified technician can be suspended`; reinstate `Only a suspended technician can be reinstated`
  - backend 409 `TECHNICIAN_HAS_ACTIVE_JOB`: `This technician has an active job — resolve it before suspending`
  - backend 422 submit: `Add your name before submitting` / `Choose at least one skill before submitting` / `Choose at least one service zone before submitting` / `One of your service zones is no longer available — update your zones and submit again`
  - backend 422 zones: `Choose service zones from the list`
  - backend 403 `TECHNICIAN_NOT_VERIFIED`: `Verified technician required` (unchanged text)
  - backend 403 `JOB_OUT_OF_ZONE`: `This job is outside your service zones`
  - backend 409 `ROLE_MISMATCH`: CUSTOMER `This number is registered as a customer. Please use the FixCare customer app.`; TECHNICIAN `This number is registered as a FixCare technician. Please use the FixCare Pro app.`; any other role `This number can't be used to sign in here.`
  - app confirm dialog body: `Submit your details? You won't be able to change them while FixCare reviews your profile.`
  - app sent-back banner: title `FixCare sent your profile back`, then the reason, then `Please fix and resubmit.`
  - app under review: title `Verification pending`, body `Your details are with FixCare for verification`
  - app suspended: title `Account suspended`, body `Contact FixCare support`
  - app profile load error: `Couldn't load your profile`
- Backend tests need the local Docker stack (Postgres + Redis) — it is RUNNING; do not start, stop, or restart containers. Command: `cd apps/backend && set -a && source .env && set +a && pnpm vitest run <file>`; full suite `pnpm vitest run`; typecheck/build `pnpm build`. Each test file uses ONE app instance and the per-app rate limit is 100 requests/minute — keep a file under ~90 injects or split it.
- Migrations apply to BOTH DBs: dev via `pnpm prisma migrate dev`, test via `DATABASE_URL="$TEST_DATABASE_URL" pnpm prisma migrate deploy`. Never `db push` the test DB and never hand-edit `_prisma_migrations` — if the ledger drifts, STOP and report BLOCKED.
- App tests: `cd apps/<app> && flutter test <file>`; full `flutter test`; `flutter analyze` must report 0 issues. After editing a `@freezed`/`@riverpod` file run `dart run build_runner build --delete-conflicting-outputs` and commit the regenerated files (generated files are tracked).

## Review Focus

1. **A submit whose response is lost but which the backend applied** → the retry's PATCH answers 409 `PROFILE_LOCKED`; the app must re-check the profile (gate moves to Under review) instead of stranding the technician on a form that can never submit. Pinned in Task 9.
2. **A prefilled zone that ops deactivated after the send-back** → it isn't in `GET /catalog/zones`, so it must not be sent on resubmit (a 422 forever). Pinned in Task 9: only zones present in the fetched list are sent.
3. **Long server text on a small phone** (a `ROLE_MISMATCH` message, a 500-character `reviewNote`) → must wrap, never overflow. Pinned in Task 10 (500-char note at 320 px width) and Task 12 (Expanded error text).
4. **Logout or session loss while a `refreshProfile()` is in flight** → the late profile must not resurrect the session. Pinned in Task 8.
5. **Suspended while on a job screen** → a job call answers `TECHNICIAN_NOT_VERIFIED`; the app must re-check and leave the job route for the Suspended screen (not a stuck error). Pinned in Task 8 (interceptor → refresh) and Task 11 (`/job/*` redirect when not verified).

---

## File map

**Backend (`apps/backend`)**
- `prisma/schema.prisma` — Technician fields, `TechnicianZone`, `AuditAction.TECHNICIAN_STATUS_CHANGED` (Task 1)
- `prisma/migrations/<ts>_technician_onboarding/` — generated (Task 1)
- `src/modules/technicians/technicians.types.ts` — `TechnicianProfileDto`, `AdminTechnicianDto` + mappers (Tasks 2, 4)
- `src/modules/technicians/technicians.schemas.ts` — skills / zoneIds / name fields, patch bodies, reason, params, query (Tasks 2, 4)
- `src/modules/technicians/technicians.lifecycle.ts` — transition table + `applyTechnicianTransition` (Task 3)
- `src/modules/technicians/technicians.service.ts` — own profile, submit, admin list/review/patch, `technicianZoneIds` (Tasks 2–4)
- `src/modules/technicians/technicians.routes.ts` — `POST /technician/me/submit`, `/admin/technicians/*` (Tasks 3, 4)
- `src/modules/catalog/catalog.service.ts` + `catalog.types.ts` — `findActiveZones`, `zoneRefs`, `ZoneRef` (Task 2)
- `src/modules/bookings/bookings.state.ts` — `TECHNICIAN_ACTIVE_STATES`, `countActiveJobsForTechnician` (Task 4)
- `src/modules/profiles/*` — technician branch delegates to `technicians` (Task 2)
- `src/modules/technician-jobs/technician-jobs.service.ts` — zone filter + codes (Task 5)
- `src/modules/auth/auth.service.ts` — `ROLE_MISMATCH` (Task 6)
- `src/app.ts` — register technicians routes (Task 3)
- tests: `tests/schema/technician-zone.test.ts`, `tests/profiles/technician-onboarding-profile.test.ts`, `tests/technicians/submit.test.ts`, `tests/technicians/admin-technicians.test.ts`, `tests/technician-jobs/dispatch.test.ts`, `tests/auth/otp-verify.test.ts`, `tests/bookings/helpers.ts`, `tests/schema/helpers.ts`
- `../../scripts/dev-drive-booking.sh` — link the dev technician to the booking's zone (Task 5)

**Technician app (`apps/technician`)**
- `lib/features/profile/data/technician_profile_dto.dart` (+ generated) — `ZoneRefDto`, new fields (Task 7)
- `lib/features/profile/data/technician_profile_repository.dart` — `updateProfile`, `submit` (Task 7)
- `lib/features/jobs/data/catalog_repository.dart` — `zones()` (Task 7)
- `lib/features/auth/presentation/auth_controller.dart` (+ generated) — `refreshProfile()` (Task 8)
- `lib/core/network/not_verified_interceptor.dart`, `lib/core/network/dio_client.dart` (Task 8)
- `lib/features/onboarding/presentation/skills.dart`, `onboarding_screen.dart` (Task 9)
- `lib/features/onboarding/presentation/under_review_screen.dart`, `suspended_screen.dart`, `submitted_summary.dart` (Task 10)
- `lib/features/onboarding/presentation/home_gate.dart`, `lib/core/router/app_router.dart`; delete `lib/features/jobs/presentation/verification_pending_screen.dart` (Task 11)
- `lib/features/auth/presentation/otp_entry_screen.dart` (Task 12)
- tests under `test/profile/`, `test/jobs/`, `test/auth/`, `test/core/`, `test/onboarding/`, `test/router/`

**Customer app (`apps/customer`)** — `lib/core/result.dart`, `lib/features/auth/data/auth_repository.dart`, `lib/features/auth/presentation/auth_controller.dart`, `lib/features/auth/presentation/otp_entry_screen.dart`, `test/auth/otp_role_mismatch_test.dart` (Task 12)

**Docs** — `docs/06-operations/technician-review-runbook.md`, `docs/06-operations/README.md`, `STATUS.md`, `CHANGELOG.md` (Task 13)

---

### Task 1: Schema — technician review fields, `TechnicianZone`, audit action; test fixtures

**Files:**
- Modify: `apps/backend/prisma/schema.prisma` (Technician model ~line 83, Zone model ~line 211, AuditAction enum ~line 190)
- Create: migration via `prisma migrate dev --name technician_onboarding`
- Modify: `apps/backend/tests/schema/helpers.ts` (resetDb)
- Modify: `apps/backend/tests/bookings/helpers.ts` (`makeTechnician`, `makeAdmin`, `makeAdminToken`)
- Test: `apps/backend/tests/schema/technician-zone.test.ts`

**Interfaces:**
- Produces: Prisma `technician.reviewNote: string | null`, `technician.submittedAt: Date | null`, `technician.reviewedAt: Date | null`, relation `technician.zones: TechnicianZone[]`, model `technicianZone { technicianId, zoneId, createdAt }` (composite id `technicianId_zoneId`), `zone.technicians`, enum value `AuditAction.TECHNICIAN_STATUS_CHANGED`.
- Produces (test helpers): `makeTechnician(skills: ServiceSkill[] = ['AC'], status: TechnicianStatus = 'VERIFIED', zoneIds: string[] = []): Promise<{ token: string; userId: string; technicianId: string }>`; `makeAdmin(level: AdminLevel = 'MANAGER'): Promise<{ token: string; userId: string }>`; `makeAdminToken(level: AdminLevel = 'MANAGER'): Promise<string>`.

- [ ] **Step 1: Write the failing test** — `apps/backend/tests/schema/technician-zone.test.ts`

```ts
import { beforeEach, describe, expect, it } from 'vitest';
import { prisma, resetDb } from './helpers.js';

async function techAndZone() {
  const user = await prisma.user.create({ data: { phone: '9811100001', role: 'TECHNICIAN' } });
  const t = await prisma.technician.create({ data: { userId: user.id, name: 'Tech', skills: ['AC'] } });
  const z = await prisma.zone.create({ data: { name: 'Padra', visitFeePaise: 9900 } });
  return { t, z };
}

describe('Technician onboarding schema', () => {
  beforeEach(resetDb);

  it('a new technician has no review fields set', async () => {
    const { t } = await techAndZone();
    expect(t.reviewNote).toBeNull();
    expect(t.submittedAt).toBeNull();
    expect(t.reviewedAt).toBeNull();
  });

  it('links a technician to a zone once (the composite key rejects a duplicate)', async () => {
    const { t, z } = await techAndZone();
    await prisma.technicianZone.create({ data: { technicianId: t.id, zoneId: z.id } });
    await expect(prisma.technicianZone.create({ data: { technicianId: t.id, zoneId: z.id } }))
      .rejects.toMatchObject({ code: 'P2002' });
    const withZones = await prisma.technician.findUniqueOrThrow({ where: { id: t.id }, include: { zones: true } });
    expect(withZones.zones.map((x) => x.zoneId)).toEqual([z.id]);
  });

  it('accepts the TECHNICIAN_STATUS_CHANGED audit action', async () => {
    const row = await prisma.auditLog.create({
      data: { action: 'TECHNICIAN_STATUS_CHANGED', actorType: 'ADMIN', actorId: 'a1', subjectId: 't1', metadata: { from: 'KYC_SUBMITTED', to: 'VERIFIED' } },
    });
    expect(row.action).toBe('TECHNICIAN_STATUS_CHANGED');
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd apps/backend && set -a && source .env && set +a && pnpm vitest run tests/schema/technician-zone.test.ts`
Expected: FAIL — `prisma.technicianZone` is undefined / unknown fields `reviewNote` / invalid enum value.

- [ ] **Step 3: Edit the schema**

In `model Technician`, after `cashDebtPaise Int @default(0)` add:

```prisma
  // Slice 3 review loop. reviewNote = ops' reason when sending back or suspending (shown to the
  // technician; cleared on verify / reinstate). submittedAt = last submit; reviewedAt = last ops decision.
  reviewNote  String?
  submittedAt DateTime?
  reviewedAt  DateTime?
```

and add `zones TechnicianZone[]` to its relation list (after `ledgerEntries  LedgerEntry[]`).

In `model Zone`, add `technicians TechnicianZone[]` after `addresses Address[]`.

Add a new model right after `model Technician`:

```prisma
/// The service zones a technician works in. Dispatch only offers / lets them accept a booking whose
/// snapshotted zoneId is one of these. Replaced wholesale on edit (technician while PENDING, ops any time).
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

Append `TECHNICIAN_STATUS_CHANGED` as the last value of `enum AuditAction` (after `DISPUTE_EVENT`).

- [ ] **Step 4: Generate + apply the migration to both DBs**

```bash
cd apps/backend && set -a && source .env && set +a && pnpm prisma migrate dev --name technician_onboarding
DATABASE_URL="$TEST_DATABASE_URL" pnpm prisma migrate deploy
```

Expected: one new folder `prisma/migrations/<timestamp>_technician_onboarding/migration.sql` containing `ALTER TYPE "AuditAction" ADD VALUE 'TECHNICIAN_STATUS_CHANGED'`, three `ADD COLUMN` (all nullable), `CREATE TABLE "TechnicianZone"` with the composite primary key, the `zoneId` index and two foreign keys. No `DROP`. `migrate deploy` reports the migration applied.

- [ ] **Step 5: Update the test fixtures**

`apps/backend/tests/schema/helpers.ts` — add `"TechnicianZone",` to the TRUNCATE list right before `"Booking"` (CASCADE would cover it, but the list is the readable inventory of tables).

`apps/backend/tests/bookings/helpers.ts` — change the import line and the two helpers:

```ts
import type { AdminLevel, ServiceSkill, TechnicianStatus } from '@prisma/client';
```

```ts
export async function makeAdmin(level: AdminLevel = 'MANAGER'): Promise<{ token: string; userId: string }> {
  const user = await prisma.user.create({ data: { phone: uniquePhone(), role: 'ADMIN' } });
  await prisma.admin.create({ data: { userId: user.id, name: 'Adm', email: `adm-${user.id}@fixcare.in`, passwordHash: 'x', adminLevel: level } });
  return { token: signAccessToken(user.id, 'ADMIN'), userId: user.id };
}

export async function makeAdminToken(level: AdminLevel = 'MANAGER'): Promise<string> {
  return (await makeAdmin(level)).token;
}
```

```ts
/** A technician with the given skills / status, linked to `zoneIds` (dispatch only offers in-zone jobs —
 *  a test that goes through /available or /accept must pass the booking's zone). */
export async function makeTechnician(skills: ServiceSkill[] = ['AC'], status: TechnicianStatus = 'VERIFIED', zoneIds: string[] = []) {
  const user = await prisma.user.create({ data: { phone: uniquePhone(), role: 'TECHNICIAN' } });
  const t = await prisma.technician.create({ data: { userId: user.id, name: 'Tech', skills, status } });
  if (zoneIds.length) await prisma.technicianZone.createMany({ data: zoneIds.map((zoneId) => ({ technicianId: t.id, zoneId })) });
  return { token: signAccessToken(user.id, 'TECHNICIAN'), userId: user.id, technicianId: t.id };
}
```

- [ ] **Step 6: Run the test + full suite + build**

Run: `pnpm vitest run tests/schema/technician-zone.test.ts` → PASS (3). Then `pnpm vitest run` → all green (no behavior changed yet) and `pnpm build` → no errors.

- [ ] **Step 7: Commit**

```bash
git add apps/backend/prisma/schema.prisma apps/backend/prisma/migrations apps/backend/tests/schema/technician-zone.test.ts apps/backend/tests/schema/helpers.ts apps/backend/tests/bookings/helpers.ts
git commit -m "feat(backend): technician review fields + TechnicianZone + status audit action"
```

---

### Task 2: `technicians` module — own profile with zones, locked once submitted

**Files:**
- Modify: `apps/backend/src/modules/catalog/catalog.types.ts` (add `ZoneRef`), `apps/backend/src/modules/catalog/catalog.service.ts` (add `findActiveZones`, `zoneRefs`)
- Create: `apps/backend/src/modules/technicians/technicians.types.ts`, `technicians.schemas.ts`, `technicians.service.ts`
- Modify: `apps/backend/src/modules/profiles/profiles.service.ts`, `profiles.types.ts`, `profiles.schemas.ts`, `profiles.routes.ts`
- Test: `apps/backend/tests/profiles/technician-onboarding-profile.test.ts`

**Interfaces:**
- Consumes: Task 1 schema + `makeTechnician(skills, status, zoneIds)`.
- Produces (catalog): `interface ZoneRef { id: string; name: string }`; `findActiveZones(ids: readonly string[]): Promise<ZoneRef[]>` (ACTIVE + not deleted only); `zoneRefs(ids: readonly string[]): Promise<ZoneRef[]>` (any status, not deleted — display labels), both ordered by name.
- Produces (technicians): `TechnicianProfileDto { id; role: 'TECHNICIAN'; name; skills: ServiceSkill[]; status: TechnicianStatus; zones: ZoneRef[]; reviewNote: string | null; submittedAt: string | null }`; `getTechnicianProfile(userId: string): Promise<TechnicianProfileDto>`; `updateOwnTechnicianProfile(userId: string, patch: TechnicianPatchBody): Promise<TechnicianProfileDto>`; `technicianZoneIds(technicianId: string): Promise<string[]>`; internal helpers `zoneIdsOf(db, technicianId)`, `replaceZones(tx, technicianId, zoneIds)`, `assertActiveZones(zoneIds)`, `toProfileDto(t)` (exported for Task 3); constant `PROFILE_LOCKED = 'PROFILE_LOCKED'`.
- Produces (schemas): `serviceSkill`, `skillsField`, `zoneIdsField`, `nameField`, `technicianPatchBody` + `TechnicianPatchBody`.

- [ ] **Step 1: Write the failing test** — `apps/backend/tests/profiles/technician-onboarding-profile.test.ts`

```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, makeTechnician } from '../bookings/helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
async function zone(name: string, extra: { status?: 'ACTIVE' | 'INACTIVE'; deletedAt?: Date } = {}) {
  return prisma.zone.create({ data: { name, visitFeePaise: 9900, ...extra } });
}
const patch = (token: string, payload: unknown) => app.inject({ method: 'PATCH', url: '/me/profile', headers: auth(token), payload });

describe('technician profile — zones + lock', () => {
  it('PENDING: sets name, skills and zones (replacing earlier zones); audit lists field names only', async () => {
    const t = await makeTechnician([], 'PENDING');
    const padra = await zone('Padra');
    const vadodara = await zone('Vadodara');
    expect((await patch(t.token, { zoneIds: [padra.id] })).statusCode).toBe(200);
    const res = await patch(t.token, { name: '  Ramesh  ', skills: ['AC', 'FAN'], zoneIds: [vadodara.id] });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({
      id: t.technicianId, role: 'TECHNICIAN', name: 'Ramesh', skills: ['AC', 'FAN'], status: 'PENDING',
      zones: [{ id: vadodara.id, name: 'Vadodara' }], reviewNote: null, submittedAt: null,
    });
    expect(await prisma.technicianZone.count({ where: { technicianId: t.technicianId } })).toBe(1);
    const audits = await prisma.auditLog.findMany({ where: { action: 'PROFILE_UPDATED', actorId: t.userId }, orderBy: { createdAt: 'asc' } });
    expect(audits).toHaveLength(2);
    expect(audits[1]!.metadata).toEqual({ fields: ['name', 'skills', 'zoneIds'] });
    expect(JSON.stringify(audits)).not.toContain('Ramesh');
  });

  it('locked once submitted: 409 PROFILE_LOCKED in KYC_SUBMITTED, VERIFIED and SUSPENDED; nothing changes', async () => {
    const z = await zone('Padra');
    for (const status of ['KYC_SUBMITTED', 'VERIFIED', 'SUSPENDED'] as const) {
      const t = await makeTechnician(['AC'], status, [z.id]);
      const res = await patch(t.token, { skills: ['AC', 'WIRING'] });
      expect(res.statusCode).toBe(409);
      expect(res.json()).toEqual({ code: 'PROFILE_LOCKED', message: 'Your profile is locked while under review' });
      expect((await prisma.technician.findUniqueOrThrow({ where: { id: t.technicianId } })).skills).toEqual(['AC']);
    }
    expect(await prisma.auditLog.count({ where: { action: 'PROFILE_UPDATED' } })).toBe(0);
  });

  it('an inactive, deleted or unknown zone → 422 and nothing changes', async () => {
    const t = await makeTechnician(['AC'], 'PENDING');
    const inactive = await zone('Old', { status: 'INACTIVE' });
    const deleted = await zone('Gone', { deletedAt: new Date() });
    for (const id of [inactive.id, deleted.id, '00000000-0000-0000-0000-000000000000']) {
      const res = await patch(t.token, { zoneIds: [id] });
      expect(res.statusCode).toBe(422);
      expect(res.json().message).toBe('Choose service zones from the list');
    }
    expect(await prisma.technicianZone.count()).toBe(0);
  });

  it('400 for repeated skills or zones, an empty zone list, a blank or over-long name, unknown keys', async () => {
    const t = await makeTechnician(['AC'], 'PENDING');
    const z = await zone('Padra');
    for (const payload of [
      { skills: ['AC', 'AC'] }, { zoneIds: [z.id, z.id] }, { zoneIds: [] }, { zoneIds: ['nope'] },
      { name: '   ' }, { name: 'x'.repeat(81) }, { status: 'VERIFIED' }, {},
    ]) {
      expect((await patch(t.token, payload)).statusCode).toBe(400);
    }
  });

  it('GET /me/profile carries zones, reviewNote and submittedAt; customer profile unchanged', async () => {
    const z = await zone('Padra');
    const t = await makeTechnician(['AC'], 'PENDING', [z.id]);
    await prisma.technician.update({ where: { id: t.technicianId }, data: { reviewNote: 'Add your full name', submittedAt: new Date('2026-10-01T10:00:00.000Z') } });
    const res = await app.inject({ method: 'GET', url: '/me/profile', headers: auth(t.token) });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ zones: [{ id: z.id, name: 'Padra' }], reviewNote: 'Add your full name', submittedAt: '2026-10-01T10:00:00.000Z' });
    const c = await makeCustomer();
    const cust = await app.inject({ method: 'GET', url: '/me/profile', headers: auth(c.token) });
    expect(Object.keys(cust.json()).sort()).toEqual(['id', 'name', 'role', 'status']);
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `pnpm vitest run tests/profiles/technician-onboarding-profile.test.ts`
Expected: FAIL — `zoneIds` rejected by `.strict()` (400), no `zones` in the DTO, no lock.

- [ ] **Step 3: Catalog zone lookups**

`apps/backend/src/modules/catalog/catalog.types.ts` — add:

```ts
/** A zone's id + display name — what other modules (technician service zones) need, nothing more. */
export interface ZoneRef { id: string; name: string; }
```

`apps/backend/src/modules/catalog/catalog.service.ts` — import `type ZoneRef` from `./catalog.types.js` and add after `listZones`:

```ts
/** The ACTIVE, non-deleted zones among `ids` — how the technicians module validates a technician's chosen
 *  service zones (it never queries Zone itself). Unknown / inactive / deleted ids are simply absent. */
export async function findActiveZones(ids: readonly string[]): Promise<ZoneRef[]> {
  if (ids.length === 0) return [];
  return prisma.zone.findMany({
    where: { id: { in: [...ids] }, deletedAt: null, status: 'ACTIVE' },
    select: { id: true, name: true },
    orderBy: { name: 'asc' },
  });
}

/** Display labels for zone ids already linked to a technician — any status (a zone ops deactivated still
 *  shows by name), soft-deleted excluded. */
export async function zoneRefs(ids: readonly string[]): Promise<ZoneRef[]> {
  if (ids.length === 0) return [];
  return prisma.zone.findMany({
    where: { id: { in: [...ids] }, deletedAt: null },
    select: { id: true, name: true },
    orderBy: { name: 'asc' },
  });
}
```

- [ ] **Step 4: technicians types + schemas**

`apps/backend/src/modules/technicians/technicians.types.ts`:

```ts
import type { Technician } from '@prisma/client';
import type { ZoneRef } from '../catalog/catalog.types.js';

/** The technician's own view of their profile (GET/PATCH /me/profile, POST /technician/me/submit). */
export interface TechnicianProfileDto {
  id: string;
  role: 'TECHNICIAN';
  name: string;
  skills: Technician['skills'];
  status: Technician['status'];
  zones: ZoneRef[];
  /** Ops' reason when the profile was sent back or the account suspended; null otherwise. */
  reviewNote: string | null;
  submittedAt: string | null;
}

export function toTechnicianProfileDto(t: Technician, zones: ZoneRef[]): TechnicianProfileDto {
  return {
    id: t.id, role: 'TECHNICIAN', name: t.name, skills: t.skills, status: t.status, zones,
    reviewNote: t.reviewNote, submittedAt: t.submittedAt?.toISOString() ?? null,
  };
}
```

`apps/backend/src/modules/technicians/technicians.schemas.ts`:

```ts
import { z } from 'zod';

export const serviceSkill = z.enum(['AC', 'FAN', 'ELECTRICAL', 'WIRING', 'APPLIANCE']);
const unique = <T>(a: readonly T[]) => new Set(a).size === a.length;

export const nameField = z.string().trim().min(1, 'name must not be empty').max(80, 'name is too long');
export const skillsField = z.array(serviceSkill).nonempty('skills must not be empty').refine(unique, 'skills must not repeat');
export const zoneIdsField = z.array(z.string().uuid('zoneIds must be zone ids')).nonempty('zoneIds must not be empty').refine(unique, 'zoneIds must not repeat');

// The technician's own PATCH /me/profile. At least one field; unknown keys rejected. Declared in this order
// on purpose — the audit row's `fields` follow it.
export const technicianPatchBody = z
  .object({ name: nameField, skills: skillsField, zoneIds: zoneIdsField })
  .partial()
  .strict()
  .refine((b) => Object.keys(b).length > 0, { message: 'At least one field is required' });
export type TechnicianPatchBody = z.infer<typeof technicianPatchBody>;
```

- [ ] **Step 5: technicians service (own profile)**

`apps/backend/src/modules/technicians/technicians.service.ts`:

```ts
import type { Prisma, Technician } from '@prisma/client';
import { prisma } from '../../shared/database/prisma.js';
import { ConflictError, NotFoundError, UnprocessableError } from '../../shared/errors.js';
import { findActiveZones, zoneRefs } from '../catalog/catalog.service.js';
import { toTechnicianProfileDto, type TechnicianProfileDto } from './technicians.types.js';
import type { TechnicianPatchBody } from './technicians.schemas.js';

/** The technician's own edits are allowed only while PENDING (new, or sent back by ops). */
export const PROFILE_LOCKED = 'PROFILE_LOCKED';

type Db = Prisma.TransactionClient | typeof prisma;

export async function zoneIdsOf(db: Db, technicianId: string): Promise<string[]> {
  const rows = await db.technicianZone.findMany({ where: { technicianId }, select: { zoneId: true } });
  return rows.map((r) => r.zoneId);
}

/** The technician's service-zone ids — dispatch (technician-jobs) offers only bookings in these zones. */
export async function technicianZoneIds(technicianId: string): Promise<string[]> {
  return zoneIdsOf(prisma, technicianId);
}

export async function replaceZones(tx: Prisma.TransactionClient, technicianId: string, zoneIds: readonly string[]): Promise<void> {
  await tx.technicianZone.deleteMany({ where: { technicianId } });
  await tx.technicianZone.createMany({ data: zoneIds.map((zoneId) => ({ technicianId, zoneId })) });
}

/** Every id must be an ACTIVE, non-deleted zone (ids are unique — Zod enforces it). */
export async function assertActiveZones(zoneIds: readonly string[]): Promise<void> {
  const found = await findActiveZones(zoneIds);
  if (found.length !== zoneIds.length) throw new UnprocessableError('Choose service zones from the list');
}

export async function toProfileDto(t: Technician): Promise<TechnicianProfileDto> {
  return toTechnicianProfileDto(t, await zoneRefs(await zoneIdsOf(prisma, t.id)));
}

export async function getTechnicianProfile(userId: string): Promise<TechnicianProfileDto> {
  const t = await prisma.technician.findFirst({ where: { userId, deletedAt: null } });
  if (!t) throw new NotFoundError('Profile not found');
  return toProfileDto(t);
}

export async function updateOwnTechnicianProfile(userId: string, patch: TechnicianPatchBody): Promise<TechnicianProfileDto> {
  const fields = Object.keys(patch); // field NAMES only — never the values (no PII in audit)
  const { zoneIds, ...columns } = patch;
  // Pre-tx validation (a read of another module's data): a zone deactivated in the gap is caught again at submit.
  if (zoneIds) await assertActiveZones(zoneIds);
  const updated = await prisma.$transaction(async (tx) => {
    const existing = await tx.technician.findFirst({ where: { userId, deletedAt: null } });
    if (!existing) throw new NotFoundError('Profile not found');
    // The UPDATE itself re-checks PENDING, so a submit racing this edit can't slip a change past the lock.
    // updatedAt is set explicitly so the statement always runs (even for a zones-only edit).
    const res = await tx.technician.updateMany({ where: { id: existing.id, status: 'PENDING' }, data: { ...columns, updatedAt: new Date() } });
    if (res.count === 0) throw new ConflictError('Your profile is locked while under review', PROFILE_LOCKED);
    if (zoneIds) await replaceZones(tx, existing.id, zoneIds);
    await tx.auditLog.create({ data: { action: 'PROFILE_UPDATED', actorType: 'USER', actorId: userId, subjectId: existing.id, metadata: { fields } } });
    return tx.technician.findUniqueOrThrow({ where: { id: existing.id } });
  });
  return toProfileDto(updated);
}
```

- [ ] **Step 6: profiles delegates its technician branch**

`apps/backend/src/modules/profiles/profiles.types.ts` — delete the local `TechnicianProfileDto` interface and `toTechnicianProfileDto`; import the type instead and keep the union:

```ts
import type { Customer } from '@prisma/client';
import type { TechnicianProfileDto } from '../technicians/technicians.types.js';

export type { TechnicianProfileDto };
```

(keep `CustomerProfileDto`, `ProfileDto = CustomerProfileDto | TechnicianProfileDto`, `toCustomerProfileDto` as they are.)

`apps/backend/src/modules/profiles/profiles.schemas.ts` — delete the local `serviceSkill` and `technicianPatchBody`/`TechnicianPatchBody` and re-export them so existing imports keep working:

```ts
export { technicianPatchBody, type TechnicianPatchBody } from '../technicians/technicians.schemas.js';
```

`apps/backend/src/modules/profiles/profiles.service.ts` — replace the two TECHNICIAN branches:

```ts
import { getTechnicianProfile, updateOwnTechnicianProfile } from '../technicians/technicians.service.js';
// …
  if (user.role === 'TECHNICIAN') return getTechnicianProfile(user.id);
// …
  if (user.role === 'TECHNICIAN') return updateOwnTechnicianProfile(user.id, patch as TechnicianPatchBody);
```

Remove the now-unused `toTechnicianProfileDto` import. `profiles.routes.ts` needs no change (it imports `technicianPatchBody` from `./profiles.schemas.js`, which re-exports it). Run `grep -rn "toTechnicianProfileDto" apps/backend/src apps/backend/tests` — the only remaining hits must be in `technicians.types.ts` / `technicians.service.ts`.

- [ ] **Step 7: Run the tests + suite + build**

Run: `pnpm vitest run tests/profiles` → all PASS (new file + existing `update-profile.test.ts` / `get-profile.test.ts`; the existing technician-name test creates a PENDING technician via OTP, so it still passes). Then `pnpm vitest run` and `pnpm build` → green. If an existing test PATCHes the profile of a technician who is NOT PENDING and expects 200, that test pinned the trust hole this task closes — make its technician PENDING (if it is about editing) or expect 409 `PROFILE_LOCKED` (if it is about status); record which in the report.

- [ ] **Step 8: Commit**

```bash
git add apps/backend/src/modules/catalog/catalog.types.ts apps/backend/src/modules/catalog/catalog.service.ts apps/backend/src/modules/technicians apps/backend/src/modules/profiles apps/backend/tests/profiles/technician-onboarding-profile.test.ts
git commit -m "feat(backend): technician profile carries service zones and locks once submitted"
```

---

### Task 3: Lifecycle core + `POST /technician/me/submit`

**Files:**
- Create: `apps/backend/src/modules/technicians/technicians.lifecycle.ts`, `apps/backend/src/modules/technicians/technicians.routes.ts`
- Modify: `apps/backend/src/modules/technicians/technicians.service.ts` (add `submitForReview`), `apps/backend/src/app.ts`
- Test: `apps/backend/tests/technicians/submit.test.ts`

**Interfaces:**
- Consumes: Task 2 `zoneIdsOf`, `getTechnicianProfile`, `findActiveZones`.
- Produces: `type TechnicianReviewAction = 'submit' | 'verify' | 'sendBack' | 'suspend' | 'reinstate'`; `TECHNICIAN_TRANSITIONS`; `INVALID_TECHNICIAN_TRANSITION = 'INVALID_TECHNICIAN_TRANSITION'`; `applyTechnicianTransition(tx: Prisma.TransactionClient, technicianId: string, action: TechnicianReviewAction, actor: { type: 'USER' | 'ADMIN'; id: string }, reason?: string): Promise<void>`; `submitForReview(userId: string): Promise<TechnicianProfileDto>`; `registerTechnicianRoutes(app: FastifyInstance): Promise<void>`.

- [ ] **Step 1: Write the failing test** — `apps/backend/tests/technicians/submit.test.ts`

```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, makeTechnician } from '../bookings/helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
const submit = (token: string) => app.inject({ method: 'POST', url: '/technician/me/submit', headers: auth(token) });
async function zone(name = 'Padra') { return prisma.zone.create({ data: { name, visitFeePaise: 9900 } }); }
const audits = () => prisma.auditLog.findMany({ where: { action: 'TECHNICIAN_STATUS_CHANGED' } });

describe('POST /technician/me/submit', () => {
  it('a complete PENDING profile → KYC_SUBMITTED, submittedAt set, one audit row by the technician', async () => {
    const z = await zone();
    const t = await makeTechnician(['AC'], 'PENDING', [z.id]);
    const res = await submit(t.token);
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ id: t.technicianId, status: 'KYC_SUBMITTED', zones: [{ id: z.id, name: 'Padra' }] });
    expect(res.json().submittedAt).toEqual(expect.any(String));
    const a = await audits();
    expect(a).toHaveLength(1);
    expect(a[0]).toMatchObject({ actorType: 'USER', actorId: t.userId, subjectId: t.technicianId, metadata: { from: 'PENDING', to: 'KYC_SUBMITTED' } });
  });

  it('incomplete → 422 with a clear message, status unchanged', async () => {
    const z = await zone();
    const inactive = await prisma.zone.create({ data: { name: 'Old', visitFeePaise: 9900, status: 'INACTIVE' } });
    const cases: Array<[Promise<{ token: string; technicianId: string }>, string]> = [
      [makeTechnician([], 'PENDING', [z.id]), 'Choose at least one skill before submitting'],
      [makeTechnician(['AC'], 'PENDING', []), 'Choose at least one service zone before submitting'],
      [makeTechnician(['AC'], 'PENDING', [inactive.id]), 'One of your service zones is no longer available — update your zones and submit again'],
    ];
    for (const [made, message] of cases) {
      const t = await made;
      const res = await submit(t.token);
      expect(res.statusCode).toBe(422);
      expect(res.json().message).toBe(message);
      expect((await prisma.technician.findUniqueOrThrow({ where: { id: t.technicianId } })).status).toBe('PENDING');
    }
    const noName = await makeTechnician(['AC'], 'PENDING', [z.id]);
    await prisma.technician.update({ where: { id: noName.technicianId }, data: { name: '' } });
    expect((await submit(noName.token)).json().message).toBe('Add your name before submitting');
    expect(await audits()).toHaveLength(0);
  });

  it('already submitted / verified / suspended → 409 INVALID_TECHNICIAN_TRANSITION', async () => {
    const z = await zone();
    for (const status of ['KYC_SUBMITTED', 'VERIFIED', 'SUSPENDED'] as const) {
      const t = await makeTechnician(['AC'], status, [z.id]);
      const res = await submit(t.token);
      expect(res.statusCode).toBe(409);
      expect(res.json()).toEqual({ code: 'INVALID_TECHNICIAN_TRANSITION', message: 'Your profile has already been submitted' });
    }
  });

  it('two submits racing → exactly one succeeds and exactly one audit row', async () => {
    const z = await zone();
    const t = await makeTechnician(['AC'], 'PENDING', [z.id]);
    const [a, b] = await Promise.all([submit(t.token), submit(t.token)]);
    expect([a.statusCode, b.statusCode].sort()).toEqual([200, 409]);
    expect(await audits()).toHaveLength(1);
  });

  it('a resubmit after send-back keeps reviewNote until the next decision', async () => {
    const z = await zone();
    const t = await makeTechnician(['AC'], 'PENDING', [z.id]);
    await prisma.technician.update({ where: { id: t.technicianId }, data: { reviewNote: 'Remove Wiring' } });
    const res = await submit(t.token);
    expect(res.json()).toMatchObject({ status: 'KYC_SUBMITTED', reviewNote: 'Remove Wiring' });
  });

  it('after submit the profile is locked; non-technicians → 403; no token → 401', async () => {
    const z = await zone();
    const t = await makeTechnician(['AC'], 'PENDING', [z.id]);
    await submit(t.token);
    expect((await app.inject({ method: 'PATCH', url: '/me/profile', headers: auth(t.token), payload: { name: 'X' } })).statusCode).toBe(409);
    const c = await makeCustomer();
    expect((await submit(c.token)).statusCode).toBe(403);
    expect((await app.inject({ method: 'POST', url: '/technician/me/submit' })).statusCode).toBe(401);
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `pnpm vitest run tests/technicians/submit.test.ts`
Expected: FAIL — 404 route not found.

- [ ] **Step 3: Lifecycle core** — `apps/backend/src/modules/technicians/technicians.lifecycle.ts`

```ts
import type { Prisma, TechnicianStatus } from '@prisma/client';
import { ConflictError } from '../../shared/errors.js';

export const INVALID_TECHNICIAN_TRANSITION = 'INVALID_TECHNICIAN_TRANSITION';

export type TechnicianReviewAction = 'submit' | 'verify' | 'sendBack' | 'suspend' | 'reinstate';

/** The whole technician lifecycle. Anything not listed here is refused (409). DEACTIVATED is untouched. */
export const TECHNICIAN_TRANSITIONS: Record<TechnicianReviewAction, { from: TechnicianStatus; to: TechnicianStatus; refused: string }> = {
  submit:    { from: 'PENDING',       to: 'KYC_SUBMITTED', refused: 'Your profile has already been submitted' },
  verify:    { from: 'KYC_SUBMITTED', to: 'VERIFIED',      refused: 'Only a technician awaiting review can be verified or sent back' },
  sendBack:  { from: 'KYC_SUBMITTED', to: 'PENDING',       refused: 'Only a technician awaiting review can be verified or sent back' },
  suspend:   { from: 'VERIFIED',      to: 'SUSPENDED',     refused: 'Only a verified technician can be suspended' },
  reinstate: { from: 'SUSPENDED',     to: 'VERIFIED',      refused: 'Only a suspended technician can be reinstated' },
};

export interface TransitionActor { type: 'USER' | 'ADMIN'; id: string; }

/**
 * Move one technician along the lifecycle and write its audit row, inside the caller's transaction.
 * The UPDATE is guarded on the expected FROM status, so a racing double-submit / double-review loses with
 * 409 instead of transitioning (and auditing) twice.
 */
export async function applyTechnicianTransition(
  tx: Prisma.TransactionClient,
  technicianId: string,
  action: TechnicianReviewAction,
  actor: TransitionActor,
  reason?: string,
): Promise<void> {
  const { from, to, refused } = TECHNICIAN_TRANSITIONS[action];
  const now = new Date();
  const data: Prisma.TechnicianUpdateManyMutationInput = { status: to, updatedAt: now };
  if (action === 'submit') data.submittedAt = now; // reviewNote kept: the technician still sees what was asked
  else data.reviewedAt = now;
  if (action === 'sendBack' || action === 'suspend') {
    if (!reason) throw new Error(`${action} requires a reason`); // programming error — routes validate it
    data.reviewNote = reason;
  }
  if (action === 'verify' || action === 'reinstate') data.reviewNote = null;
  const res = await tx.technician.updateMany({ where: { id: technicianId, status: from, deletedAt: null }, data });
  if (res.count === 0) throw new ConflictError(refused, INVALID_TECHNICIAN_TRANSITION);
  await tx.auditLog.create({
    data: {
      action: 'TECHNICIAN_STATUS_CHANGED', actorType: actor.type, actorId: actor.id, subjectId: technicianId,
      metadata: { from, to, ...(reason ? { reason } : {}) },
    },
  });
}
```

- [ ] **Step 4: `submitForReview`** — append to `technicians.service.ts` (add `ConflictError` is already imported; import `applyTechnicianTransition, INVALID_TECHNICIAN_TRANSITION` from `./technicians.lifecycle.js`):

```ts
export async function submitForReview(userId: string): Promise<TechnicianProfileDto> {
  const t = await prisma.technician.findFirst({ where: { userId, deletedAt: null } });
  if (!t) throw new NotFoundError('Profile not found');
  if (t.status !== 'PENDING') throw new ConflictError('Your profile has already been submitted', INVALID_TECHNICIAN_TRANSITION);
  if (!t.name.trim()) throw new UnprocessableError('Add your name before submitting');
  if (t.skills.length === 0) throw new UnprocessableError('Choose at least one skill before submitting');
  const zoneIds = await zoneIdsOf(prisma, t.id);
  if (zoneIds.length === 0) throw new UnprocessableError('Choose at least one service zone before submitting');
  if ((await findActiveZones(zoneIds)).length !== zoneIds.length) {
    throw new UnprocessableError('One of your service zones is no longer available — update your zones and submit again');
  }
  await prisma.$transaction((tx) => applyTechnicianTransition(tx, t.id, 'submit', { type: 'USER', id: userId }));
  return getTechnicianProfile(userId);
}
```

- [ ] **Step 5: Routes + registration** — `apps/backend/src/modules/technicians/technicians.routes.ts`

```ts
import type { FastifyInstance } from 'fastify';
import { requireAuth } from '../../shared/middleware/auth.js';
import { ForbiddenError } from '../../shared/errors.js';
import { submitForReview } from './technicians.service.js';

export async function registerTechnicianRoutes(app: FastifyInstance): Promise<void> {
  // Technician-role only — NOT the VERIFIED gate (submitting is how a technician gets verified).
  app.post('/technician/me/submit', { preHandler: [requireAuth] }, async (req, reply) => {
    if (req.user!.role !== 'TECHNICIAN') throw new ForbiddenError('Technician access required');
    return reply.send(await submitForReview(req.user!.id));
  });
}
```

`apps/backend/src/app.ts` — import `registerTechnicianRoutes` from `./modules/technicians/technicians.routes.js` and call `await registerTechnicianRoutes(app);` right after `await registerTechnicianJobRoutes(app);`.

- [ ] **Step 6: Run tests + suite + build**

Run: `pnpm vitest run tests/technicians/submit.test.ts` → PASS (6). Then `pnpm vitest run` and `pnpm build` → green.

- [ ] **Step 7: Commit**

```bash
git add apps/backend/src/modules/technicians apps/backend/src/app.ts apps/backend/tests/technicians/submit.test.ts
git commit -m "feat(backend): technician lifecycle core + submit for verification"
```

---

### Task 4: Admin technician endpoints — list, verify, send back, suspend, reinstate, edit skills/zones

**Files:**
- Modify: `apps/backend/src/modules/bookings/bookings.state.ts` (add active-job helper)
- Modify: `apps/backend/src/modules/technicians/technicians.types.ts`, `technicians.schemas.ts`, `technicians.service.ts`, `technicians.routes.ts`
- Test: `apps/backend/tests/technicians/admin-technicians.test.ts`

**Interfaces:**
- Consumes: Task 3 `applyTechnicianTransition`; Task 2 `replaceZones`, `assertActiveZones`, `zoneRefs`; Task 1 `makeAdmin(level)`.
- Produces: `TECHNICIAN_ACTIVE_STATES: readonly BookingState[]`, `countActiveJobsForTechnician(tx, technicianId): Promise<number>` (bookings); `AdminTechnicianDto { id; maskedPhone; name; skills; status; zones: ZoneRef[]; submittedAt: string | null; reviewedAt: string | null; reviewNote: string | null; createdAt: string }`; `listTechnicians(status?: TechnicianStatus): Promise<AdminTechnicianDto[]>`; `reviewTechnician(adminUserId, technicianId, action: Exclude<TechnicianReviewAction, 'submit'>, reason?): Promise<AdminTechnicianDto>`; `adminUpdateTechnician(adminUserId, technicianId, patch: AdminTechnicianPatchBody): Promise<AdminTechnicianDto>`.

**Ruling (active job):** "active" = assigned and in `ACCEPTED … CUSTOMER_CONFIRMED` or `DECLINED_BY_CUSTOMER` (work or a possible cash collection still needs the technician). `PAYMENT_RECEIVED`, `CLOSED`, cancelled and `DISPUTED` (ops owns it) do not block. A technician accepting a job in the instant between the count and the suspend commit is a known, accepted race (ops reinstates; money still needs the customer's OTP).

- [ ] **Step 1: Write the failing test** — `apps/backend/tests/technicians/admin-technicians.test.ts`

```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeAdmin, makeAdminToken, makeCustomer, makeTechnician, seedBookable } from '../bookings/helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
const post = (token: string, url: string, payload?: unknown) =>
  app.inject({ method: 'POST', url, headers: auth(token), ...(payload === undefined ? {} : { payload }) });
async function zone(name = 'Padra') { return prisma.zone.create({ data: { name, visitFeePaise: 9900 } }); }
const statusOf = async (id: string) => (await prisma.technician.findUniqueOrThrow({ where: { id } })).status;
const audits = (subjectId: string) =>
  prisma.auditLog.findMany({ where: { action: 'TECHNICIAN_STATUS_CHANGED', subjectId }, orderBy: { createdAt: 'asc' } });
function future() { return new Date(Date.now() + 86_400_000).toISOString(); }

describe('admin technicians', () => {
  it('walls every route: 401 without a token; 403 for a SUPPORT admin, a customer, a technician', async () => {
    const z = await zone();
    const t = await makeTechnician(['AC'], 'KYC_SUBMITTED', [z.id]);
    const callers = [await makeAdminToken('SUPPORT'), (await makeCustomer()).token, t.token];
    const routes = [
      { method: 'GET' as const, url: '/admin/technicians' },
      { method: 'POST' as const, url: `/admin/technicians/${t.technicianId}/verify` },
      { method: 'POST' as const, url: `/admin/technicians/${t.technicianId}/send-back`, payload: { reason: 'x' } },
      { method: 'POST' as const, url: `/admin/technicians/${t.technicianId}/suspend`, payload: { reason: 'x' } },
      { method: 'POST' as const, url: `/admin/technicians/${t.technicianId}/reinstate` },
      { method: 'PATCH' as const, url: `/admin/technicians/${t.technicianId}`, payload: { skills: ['FAN'] } },
    ];
    for (const r of routes) {
      expect((await app.inject(r)).statusCode).toBe(401);
      for (const token of callers) expect((await app.inject({ ...r, headers: auth(token) })).statusCode).toBe(403);
    }
    expect(await statusOf(t.technicianId)).toBe('KYC_SUBMITTED');
  });

  it('lists by status, oldest submission first, phone masked and never in full', async () => {
    const admin = await makeAdminToken();
    const z = await zone();
    const a = await makeTechnician(['AC'], 'KYC_SUBMITTED', [z.id]);
    const b = await makeTechnician(['FAN'], 'KYC_SUBMITTED', [z.id]);
    await makeTechnician(['AC'], 'VERIFIED', [z.id]);
    await prisma.technician.update({ where: { id: a.technicianId }, data: { submittedAt: new Date('2026-10-01T10:00:00Z') } });
    await prisma.technician.update({ where: { id: b.technicianId }, data: { submittedAt: new Date('2026-10-01T09:00:00Z') } });
    const res = await app.inject({ method: 'GET', url: '/admin/technicians?status=KYC_SUBMITTED', headers: auth(admin) });
    expect(res.statusCode).toBe(200);
    const list = res.json() as Array<Record<string, unknown>>;
    expect(list.map((x) => x.id)).toEqual([b.technicianId, a.technicianId]);
    const phone = (await prisma.user.findUniqueOrThrow({ where: { id: a.userId } })).phone;
    expect(list[1]).toMatchObject({
      maskedPhone: `••••••${phone.slice(-4)}`, name: 'Tech', skills: ['AC'], status: 'KYC_SUBMITTED',
      zones: [{ id: z.id, name: 'Padra' }], submittedAt: '2026-10-01T10:00:00.000Z', reviewedAt: null, reviewNote: null,
    });
    expect(res.body).not.toContain(phone);
    expect((await app.inject({ method: 'GET', url: '/admin/technicians', headers: auth(admin) })).json()).toHaveLength(3);
    expect((await app.inject({ method: 'GET', url: '/admin/technicians?status=NOPE', headers: auth(admin) })).statusCode).toBe(400);
  });

  it('verify: KYC_SUBMITTED → VERIFIED, reviewedAt set, note cleared, one audit row by the admin', async () => {
    const z = await zone();
    const t = await makeTechnician(['AC'], 'KYC_SUBMITTED', [z.id]);
    await prisma.technician.update({ where: { id: t.technicianId }, data: { reviewNote: 'old note' } });
    const admin = await makeAdmin();
    const res = await post(admin.token, `/admin/technicians/${t.technicianId}/verify`);
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ id: t.technicianId, status: 'VERIFIED', reviewNote: null, reviewedAt: expect.any(String) });
    const a = await audits(t.technicianId);
    expect(a).toHaveLength(1);
    expect(a[0]).toMatchObject({ actorType: 'ADMIN', actorId: admin.userId, metadata: { from: 'KYC_SUBMITTED', to: 'VERIFIED' } });
  });

  it('send-back: reason required (1..500); KYC_SUBMITTED → PENDING with the note; the technician can edit again', async () => {
    const z = await zone();
    const t = await makeTechnician(['AC'], 'KYC_SUBMITTED', [z.id]);
    const admin = await makeAdminToken();
    const url = `/admin/technicians/${t.technicianId}/send-back`;
    for (const payload of [undefined, {}, { reason: '   ' }, { reason: 'x'.repeat(501) }, { reason: 'ok', extra: 1 }]) {
      expect((await post(admin, url, payload)).statusCode).toBe(400);
    }
    const reason = 'Add the Wiring skill only if you hold a licence';
    const res = await post(admin, url, { reason });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ status: 'PENDING', reviewNote: reason });
    expect((await audits(t.technicianId))[0]!.metadata).toEqual({ from: 'KYC_SUBMITTED', to: 'PENDING', reason });
    expect((await app.inject({ method: 'PATCH', url: '/me/profile', headers: auth(t.token), payload: { skills: ['AC'] } })).statusCode).toBe(200);
  });

  it('suspend (reason) and reinstate; every disallowed move → 409 INVALID_TECHNICIAN_TRANSITION', async () => {
    const z = await zone();
    const t = await makeTechnician(['AC'], 'VERIFIED', [z.id]);
    const admin = await makeAdminToken();
    const base = `/admin/technicians/${t.technicianId}`;
    expect((await post(admin, `${base}/suspend`, {})).statusCode).toBe(400);
    expect((await post(admin, `${base}/suspend`, { reason: 'Customer complaint under review' })).json()).toMatchObject({ status: 'SUSPENDED', reviewNote: 'Customer complaint under review' });
    expect((await post(admin, `${base}/reinstate`)).json()).toMatchObject({ status: 'VERIFIED', reviewNote: null });
    const refused: Array<[string, unknown, string]> = [
      ['verify', undefined, 'Only a technician awaiting review can be verified or sent back'],
      ['send-back', { reason: 'x' }, 'Only a technician awaiting review can be verified or sent back'],
      ['reinstate', undefined, 'Only a suspended technician can be reinstated'],
    ];
    for (const [action, payload, message] of refused) {
      const res = await post(admin, `${base}/${action}`, payload);
      expect(res.statusCode).toBe(409);
      expect(res.json()).toEqual({ code: 'INVALID_TECHNICIAN_TRANSITION', message });
    }
    const pending = await makeTechnician(['AC'], 'PENDING', [z.id]);
    expect((await post(admin, `/admin/technicians/${pending.technicianId}/suspend`, { reason: 'x' })).json()).toEqual({ code: 'INVALID_TECHNICIAN_TRANSITION', message: 'Only a verified technician can be suspended' });
    expect(await audits(t.technicianId)).toHaveLength(2);
  });

  it('suspend is refused while the technician has an active job; allowed once it is closed', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const t = await makeTechnician(['AC'], 'VERIFIED', [f.zone.id]);
    const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(t.token) })).statusCode).toBe(200);
    const admin = await makeAdminToken();
    const url = `/admin/technicians/${t.technicianId}/suspend`;
    const res = await post(admin, url, { reason: 'x' });
    expect(res.statusCode).toBe(409);
    expect(res.json()).toEqual({ code: 'TECHNICIAN_HAS_ACTIVE_JOB', message: 'This technician has an active job — resolve it before suspending' });
    expect(await statusOf(t.technicianId)).toBe('VERIFIED');
    await prisma.booking.update({ where: { id: booking.id }, data: { state: 'CLOSED' } });
    expect((await post(admin, url, { reason: 'x' })).statusCode).toBe(200);
  });

  it('PATCH edits skills/zones in any status, audited by the admin; 404 / 400 / 422 guards', async () => {
    const padra = await zone('Padra');
    const vadodara = await zone('Vadodara');
    const t = await makeTechnician(['AC'], 'VERIFIED', [padra.id]);
    const admin = await makeAdmin();
    const url = `/admin/technicians/${t.technicianId}`;
    const res = await app.inject({ method: 'PATCH', url, headers: auth(admin.token), payload: { skills: ['AC', 'WIRING'], zoneIds: [vadodara.id] } });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ status: 'VERIFIED', skills: ['AC', 'WIRING'], zones: [{ id: vadodara.id, name: 'Vadodara' }] });
    const audit = await prisma.auditLog.findFirstOrThrow({ where: { action: 'PROFILE_UPDATED', subjectId: t.technicianId } });
    expect(audit).toMatchObject({ actorType: 'ADMIN', actorId: admin.userId, metadata: { fields: ['skills', 'zoneIds'], by: 'admin' } });
    expect((await app.inject({ method: 'PATCH', url, headers: auth(admin.token), payload: {} })).statusCode).toBe(400);
    expect((await app.inject({ method: 'PATCH', url, headers: auth(admin.token), payload: { name: 'X' } })).statusCode).toBe(400);
    const inactive = await prisma.zone.create({ data: { name: 'Old', visitFeePaise: 9900, status: 'INACTIVE' } });
    expect((await app.inject({ method: 'PATCH', url, headers: auth(admin.token), payload: { zoneIds: [inactive.id] } })).statusCode).toBe(422);
    const missing = '00000000-0000-0000-0000-000000000000';
    expect((await app.inject({ method: 'PATCH', url: `/admin/technicians/${missing}`, headers: auth(admin.token), payload: { skills: ['AC'] } })).statusCode).toBe(404);
    expect((await post(admin.token, `/admin/technicians/${missing}/verify`)).statusCode).toBe(404);
    expect((await post(admin.token, '/admin/technicians/not-a-uuid/verify')).statusCode).toBe(400);
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `pnpm vitest run tests/technicians/admin-technicians.test.ts`
Expected: FAIL — admin routes return 404.

- [ ] **Step 3: Active-job helper** — append to `apps/backend/src/modules/bookings/bookings.state.ts`:

```ts
/** Assigned-booking states in which the technician still has work (or a cash collection) left. Ops may not
 *  suspend a technician mid-job — every job route requires VERIFIED, so it would strand the customer.
 *  PAYMENT_RECEIVED onward, cancellations and DISPUTED (ops owns it) need nothing more from them. */
export const TECHNICIAN_ACTIVE_STATES: readonly BookingState[] = [
  'ACCEPTED', 'EN_ROUTE', 'ARRIVED', 'DIAGNOSED', 'CUSTOMER_APPROVED', 'PARTS_REQUESTED', 'PARTS_ACQUIRED',
  'REPAIR_IN_PROGRESS', 'REPAIR_COMPLETE', 'CUSTOMER_CONFIRMED', 'DECLINED_BY_CUSTOMER',
];

export async function countActiveJobsForTechnician(tx: Prisma.TransactionClient, technicianId: string): Promise<number> {
  return tx.booking.count({ where: { technicianId, deletedAt: null, state: { in: [...TECHNICIAN_ACTIVE_STATES] } } });
}
```

- [ ] **Step 4: Admin DTO + schemas**

Append to `technicians.types.ts` (add `import { maskPhone } from '../../shared/utils/mask.js';`):

```ts
/** Ops' view of a technician. The phone is masked here and nowhere else is it exposed. */
export interface AdminTechnicianDto {
  id: string;
  maskedPhone: string;
  name: string;
  skills: Technician['skills'];
  status: Technician['status'];
  zones: ZoneRef[];
  submittedAt: string | null;
  reviewedAt: string | null;
  reviewNote: string | null;
  createdAt: string;
}

export function toAdminTechnicianDto(t: Technician, phone: string, zones: ZoneRef[]): AdminTechnicianDto {
  return {
    id: t.id, maskedPhone: maskPhone(phone), name: t.name, skills: t.skills, status: t.status, zones,
    submittedAt: t.submittedAt?.toISOString() ?? null, reviewedAt: t.reviewedAt?.toISOString() ?? null,
    reviewNote: t.reviewNote, createdAt: t.createdAt.toISOString(),
  };
}
```

Append to `technicians.schemas.ts`:

```ts
export const technicianIdParams = z.object({ id: z.string().uuid('Invalid technician id') });

export const listTechniciansQuery = z
  .object({ status: z.enum(['PENDING', 'KYC_SUBMITTED', 'VERIFIED', 'SUSPENDED', 'DEACTIVATED']).optional() })
  .strict();

export const reasonBody = z.object({ reason: z.string().trim().min(1, 'reason is required').max(500, 'reason is too long') }).strict();

export const adminTechnicianPatchBody = z
  .object({ skills: skillsField, zoneIds: zoneIdsField })
  .partial()
  .strict()
  .refine((b) => Object.keys(b).length > 0, { message: 'At least one field is required' });
export type AdminTechnicianPatchBody = z.infer<typeof adminTechnicianPatchBody>;
```

- [ ] **Step 5: Admin service functions** — append to `technicians.service.ts` (imports: `type TechnicianStatus` from `@prisma/client`; `countActiveJobsForTechnician` from `../bookings/bookings.state.js`; `toAdminTechnicianDto, type AdminTechnicianDto` from `./technicians.types.js`; `type TechnicianReviewAction` from `./technicians.lifecycle.js`; `type AdminTechnicianPatchBody` from `./technicians.schemas.js`; `type ZoneRef` from `../catalog/catalog.types.js`):

```ts
const adminInclude = { user: { select: { phone: true } }, zones: { select: { zoneId: true } } } satisfies Prisma.TechnicianInclude;
type AdminRow = Prisma.TechnicianGetPayload<{ include: typeof adminInclude }>;

async function toAdminDtos(rows: AdminRow[]): Promise<AdminTechnicianDto[]> {
  const refs = await zoneRefs([...new Set(rows.flatMap((r) => r.zones.map((z) => z.zoneId)))]);
  const byId = new Map(refs.map((z) => [z.id, z]));
  return rows.map((r) => {
    const zones = r.zones.map((z) => byId.get(z.zoneId)).filter((z): z is ZoneRef => z !== undefined);
    return toAdminTechnicianDto(r, r.user.phone, zones.sort((a, b) => a.name.localeCompare(b.name)));
  });
}

async function getAdminTechnician(technicianId: string): Promise<AdminTechnicianDto> {
  const row = await prisma.technician.findFirst({ where: { id: technicianId, deletedAt: null }, include: adminInclude });
  if (!row) throw new NotFoundError('Technician not found');
  return (await toAdminDtos([row]))[0]!;
}

/** Ops' review queue: oldest submission first (never-submitted last), then oldest account. */
export async function listTechnicians(status?: TechnicianStatus): Promise<AdminTechnicianDto[]> {
  const rows = await prisma.technician.findMany({
    where: { deletedAt: null, ...(status ? { status } : {}) },
    include: adminInclude,
    orderBy: [{ submittedAt: { sort: 'asc', nulls: 'last' } }, { createdAt: 'asc' }],
  });
  return toAdminDtos(rows);
}

export async function reviewTechnician(
  adminUserId: string,
  technicianId: string,
  action: Exclude<TechnicianReviewAction, 'submit'>,
  reason?: string,
): Promise<AdminTechnicianDto> {
  await prisma.$transaction(async (tx) => {
    const t = await tx.technician.findFirst({ where: { id: technicianId, deletedAt: null }, select: { id: true } });
    if (!t) throw new NotFoundError('Technician not found');
    if (action === 'suspend' && (await countActiveJobsForTechnician(tx, technicianId)) > 0) {
      throw new ConflictError('This technician has an active job — resolve it before suspending', 'TECHNICIAN_HAS_ACTIVE_JOB');
    }
    await applyTechnicianTransition(tx, technicianId, action, { type: 'ADMIN', id: adminUserId }, reason);
  });
  return getAdminTechnician(technicianId);
}

/** Ops changes skills / zones in any status (the technician's own edits stop at submit). */
export async function adminUpdateTechnician(adminUserId: string, technicianId: string, patch: AdminTechnicianPatchBody): Promise<AdminTechnicianDto> {
  if (patch.zoneIds) await assertActiveZones(patch.zoneIds);
  await prisma.$transaction(async (tx) => {
    const t = await tx.technician.findFirst({ where: { id: technicianId, deletedAt: null }, select: { id: true } });
    if (!t) throw new NotFoundError('Technician not found');
    if (patch.skills) await tx.technician.update({ where: { id: t.id }, data: { skills: patch.skills } });
    if (patch.zoneIds) await replaceZones(tx, t.id, patch.zoneIds);
    await tx.auditLog.create({
      data: { action: 'PROFILE_UPDATED', actorType: 'ADMIN', actorId: adminUserId, subjectId: t.id, metadata: { fields: Object.keys(patch), by: 'admin' } },
    });
  });
  return getAdminTechnician(technicianId);
}
```

(`applyTechnicianTransition` is already imported in Task 3.)

- [ ] **Step 6: Admin routes** — extend `technicians.routes.ts`:

```ts
import type { FastifyInstance } from 'fastify';
import type { z } from 'zod';
import { requireAuth } from '../../shared/middleware/auth.js';
import { requireAdminLevel } from '../../shared/middleware/rbac.js';
import { ForbiddenError, ValidationError } from '../../shared/errors.js';
import { adminTechnicianPatchBody, listTechniciansQuery, reasonBody, technicianIdParams } from './technicians.schemas.js';
import { adminUpdateTechnician, listTechnicians, reviewTechnician, submitForReview } from './technicians.service.js';

function parse<T>(schema: z.ZodType<T>, value: unknown): T {
  const p = schema.safeParse(value);
  if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
  return p.data;
}

export async function registerTechnicianRoutes(app: FastifyInstance): Promise<void> {
  // … the submit route from Task 3 stays here unchanged …

  const manager = { preHandler: [requireAuth, requireAdminLevel('MANAGER')] };

  app.get('/admin/technicians', manager, async (req, reply) => {
    const { status } = parse(listTechniciansQuery, req.query);
    return reply.send(await listTechnicians(status));
  });

  app.post('/admin/technicians/:id/verify', manager, async (req, reply) => {
    const { id } = parse(technicianIdParams, req.params);
    return reply.send(await reviewTechnician(req.user!.id, id, 'verify'));
  });

  app.post('/admin/technicians/:id/send-back', manager, async (req, reply) => {
    const { id } = parse(technicianIdParams, req.params);
    const { reason } = parse(reasonBody, req.body);
    return reply.send(await reviewTechnician(req.user!.id, id, 'sendBack', reason));
  });

  app.post('/admin/technicians/:id/suspend', manager, async (req, reply) => {
    const { id } = parse(technicianIdParams, req.params);
    const { reason } = parse(reasonBody, req.body);
    return reply.send(await reviewTechnician(req.user!.id, id, 'suspend', reason));
  });

  app.post('/admin/technicians/:id/reinstate', manager, async (req, reply) => {
    const { id } = parse(technicianIdParams, req.params);
    return reply.send(await reviewTechnician(req.user!.id, id, 'reinstate'));
  });

  app.patch('/admin/technicians/:id', manager, async (req, reply) => {
    const { id } = parse(technicianIdParams, req.params);
    const body = parse(adminTechnicianPatchBody, req.body);
    return reply.send(await adminUpdateTechnician(req.user!.id, id, body));
  });
}
```

Note: `requireAuth` runs first (401 before 403). If `z.ZodType<T>` does not infer for the refined schemas under Zod 4 typing, use `parse<T>(schema: { safeParse(v: unknown): { success: true; data: T } | { success: false; error: z.ZodError } }, value: unknown)` — do not fall back to `any`.

- [ ] **Step 7: Run tests + suite + build**

Run: `pnpm vitest run tests/technicians` → PASS. Then `pnpm vitest run` and `pnpm build` → green.

- [ ] **Step 8: Commit**

```bash
git add apps/backend/src/modules/bookings/bookings.state.ts apps/backend/src/modules/technicians apps/backend/tests/technicians/admin-technicians.test.ts
git commit -m "feat(backend): ops technician review endpoints (verify, send back, suspend, reinstate, edit)"
```

---

### Task 5: Dispatch zone filter + `TECHNICIAN_NOT_VERIFIED` code; fix existing tests and the dev script

**Files:**
- Modify: `apps/backend/src/modules/technician-jobs/technician-jobs.service.ts` (`requireTechnician` ~line 26, `listAvailableJobs` ~line 32, `acceptJob` ~line 80)
- Modify: `apps/backend/tests/technician-jobs/dispatch.test.ts` + every test file that calls `/technician/jobs/available` or `/accept` expecting success (from `grep -rln "jobs/available\|/accept" apps/backend/tests`: `bookings/booking-state`, `bookings/payment`, `bookings/diagnosis`, `settlements/zero-payable`, `technician-jobs/{completion,job-detail,photos,repair-path,arrival,dispatch}`, `dev/mark-uploaded`)
- Modify: `scripts/dev-drive-booking.sh` (`ensure_tech`, ~line 110)

**Interfaces:**
- Consumes: Task 2 `technicianZoneIds(technicianId)`; Task 1 `makeTechnician(skills, status, zoneIds)`.
- Produces: `requireTechnician` returns `{ id: string; skills: ServiceSkill[]; zoneIds: string[] }` and throws `ForbiddenError('Verified technician required', 'TECHNICIAN_NOT_VERIFIED')`; accept of an out-of-zone job throws `ForbiddenError('This job is outside your service zones', 'JOB_OUT_OF_ZONE')`.

**Ruling:** the zone check sits next to the existing skill check in `acceptJob` (pre-transaction, like the skill check); `booking.zoneId` is an immutable snapshot, so there is nothing to race on the booking side.

- [ ] **Step 1: Write the failing tests** — append to `describe(...)` in `tests/technician-jobs/dispatch.test.ts`:

```ts
  it('available lists only jobs in the technician\'s zones; accepting an out-of-zone job → 403 JOB_OUT_OF_ZONE', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const booking = await book(c.token, f.address.id, f.service.id);
    const elsewhere = await prisma.zone.create({ data: { name: 'Elsewhere', visitFeePaise: 9900 } });
    const outside = await makeTechnician(['AC'], 'VERIFIED', [elsewhere.id]);
    expect((await app.inject({ method: 'GET', url: '/technician/jobs/available', headers: auth(outside.token) })).json()).toHaveLength(0);
    const res = await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(outside.token) });
    expect(res.statusCode).toBe(403);
    expect(res.json()).toEqual({ code: 'JOB_OUT_OF_ZONE', message: 'This job is outside your service zones' });
    const noZones = await makeTechnician(['AC']);
    expect((await app.inject({ method: 'GET', url: '/technician/jobs/available', headers: auth(noZones.token) })).json()).toHaveLength(0);
    const inside = await makeTechnician(['AC'], 'VERIFIED', [elsewhere.id, f.zone.id]);
    expect((await app.inject({ method: 'GET', url: '/technician/jobs/available', headers: auth(inside.token) })).json()).toHaveLength(1);
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(inside.token) })).statusCode).toBe(200);
  });

  it('the VERIFIED gate answers 403 with code TECHNICIAN_NOT_VERIFIED', async () => {
    for (const status of ['PENDING', 'KYC_SUBMITTED', 'SUSPENDED'] as const) {
      const t = await makeTechnician(['AC'], status);
      const res = await app.inject({ method: 'GET', url: '/technician/jobs/mine', headers: auth(t.token) });
      expect(res.statusCode).toBe(403);
      expect(res.json()).toEqual({ code: 'TECHNICIAN_NOT_VERIFIED', message: 'Verified technician required' });
    }
  });
```

- [ ] **Step 2: Run it to verify it fails**

Run: `pnpm vitest run tests/technician-jobs/dispatch.test.ts`
Expected: the two new tests FAIL (out-of-zone tech sees the job; code is `FORBIDDEN`).

- [ ] **Step 3: Implement** — in `technician-jobs.service.ts` import `technicianZoneIds` from `../technicians/technicians.service.js`, then:

```ts
const TECHNICIAN_NOT_VERIFIED = 'TECHNICIAN_NOT_VERIFIED';
const JOB_OUT_OF_ZONE = 'JOB_OUT_OF_ZONE';

async function requireTechnician(userId: string): Promise<{ id: string; skills: import('@prisma/client').ServiceSkill[]; zoneIds: string[] }> {
  const t = await prisma.technician.findFirst({ where: { userId, deletedAt: null } });
  // Stable code: the technician app re-checks the profile on it (suspended mid-session → Suspended screen).
  if (!t || t.status !== 'VERIFIED') throw new ForbiddenError('Verified technician required', TECHNICIAN_NOT_VERIFIED);
  return { id: t.id, skills: t.skills, zoneIds: await technicianZoneIds(t.id) };
}
```

In `listAvailableJobs`'s `where`, add after the `service` line:

```ts
      zoneId: { in: tech.zoneIds }, // the booking's SNAPSHOTTED zone — never re-resolved from the address
```

In `acceptJob`, right after the skill check:

```ts
  if (!tech.zoneIds.includes(booking.zoneId)) throw new ForbiddenError('This job is outside your service zones', JOB_OUT_OF_ZONE);
```

- [ ] **Step 4: Fix the existing suite**

Run `pnpm vitest run`. Every failure is a test whose technician now has no zone. Fix each by passing the booking's zone to the helper — e.g. `makeTechnician(['AC'])` → `makeTechnician(['AC'], 'VERIFIED', [f.zone.id])` (the fixture variable holding `seedBookable(...)`'s result varies per file: `f`, `s`, `fx` — use that file's). Do NOT change assertions, and do NOT give a zone to technicians whose test expects them NOT to see / accept (wrong-skill, unverified, skip, foreign-tech cases keep working either way — leave them as they are unless the test then fails for the wrong reason). Tests that assign `technicianId` directly through prisma need no zone.

- [ ] **Step 5: Dev harness** — in `scripts/dev-drive-booking.sh` `ensure_tech()`, right after the `update "Technician" set status='VERIFIED' …` line:

```sh
  # Slice 3: dispatch only offers in-zone jobs — link this technician to the booking's (snapshotted) zone.
  $PG -c "insert into \"TechnicianZone\" (\"technicianId\",\"zoneId\") select '$techid', \"zoneId\" from \"Booking\" where id='$BID' on conflict do nothing;" >/dev/null
```

- [ ] **Step 6: Run the full suite + build**

Run: `pnpm vitest run` → all green; `pnpm build` → no errors; `bash -n scripts/dev-drive-booking.sh` → no syntax errors.

- [ ] **Step 7: Commit**

```bash
git add apps/backend/src/modules/technician-jobs/technician-jobs.service.ts apps/backend/tests scripts/dev-drive-booking.sh
git commit -m "feat(backend): dispatch offers only in-zone jobs; TECHNICIAN_NOT_VERIFIED code"
```

---

### Task 6: Login role mismatch → 409 `ROLE_MISMATCH`

**Files:**
- Modify: `apps/backend/src/modules/auth/auth.service.ts` (`verifyOtp`)
- Modify: `apps/backend/tests/auth/otp-verify.test.ts` (replace the "existing user logs in as STORED role (ignores role hint)" test)

**Interfaces:**
- Produces: `POST /auth/otp/verify` → 409 `{ code: 'ROLE_MISMATCH', message }` when the phone's existing user has a different role than the OTP was sent for.

- [ ] **Step 1: Write the failing tests** — in `tests/auth/otp-verify.test.ts`, DELETE the test `'existing user logs in as STORED role (ignores role hint) + audits USER_LOGGED_IN'` (it pins the bug) and add:

```ts
  it('existing user, same role → logs in + audits USER_LOGGED_IN', async () => {
    const phone = '9800000011';
    let otp = await sendAndGetOtp(phone, 'CUSTOMER');
    await app.inject({ method: 'POST', url: '/auth/otp/verify', payload: { phone, role: 'CUSTOMER', otp } });
    otp = await sendAndGetOtp(phone, 'CUSTOMER');
    const res = await app.inject({ method: 'POST', url: '/auth/otp/verify', payload: { phone, role: 'CUSTOMER', otp } });
    expect(res.statusCode).toBe(200);
    expect(res.json().user.role).toBe('CUSTOMER');
    const user = await prisma.user.findUniqueOrThrow({ where: { phone } });
    expect(await prisma.auditLog.count({ where: { action: 'USER_LOGGED_IN', actorId: user.id } })).toBe(1);
  });

  it('customer number in the technician app → 409 ROLE_MISMATCH; no tokens, no technician profile, OTP consumed', async () => {
    const phone = '9800000014';
    let otp = await sendAndGetOtp(phone, 'CUSTOMER');
    await app.inject({ method: 'POST', url: '/auth/otp/verify', payload: { phone, role: 'CUSTOMER', otp } });
    otp = await sendAndGetOtp(phone, 'TECHNICIAN');
    const res = await app.inject({ method: 'POST', url: '/auth/otp/verify', payload: { phone, role: 'TECHNICIAN', otp } });
    expect(res.statusCode).toBe(409);
    expect(res.json()).toEqual({ code: 'ROLE_MISMATCH', message: 'This number is registered as a customer. Please use the FixCare customer app.' });
    const user = await prisma.user.findUniqueOrThrow({ where: { phone }, include: { technician: true } });
    expect(user.role).toBe('CUSTOMER');
    expect(user.technician).toBeNull();
    expect(await prisma.refreshToken.count({ where: { userId: user.id } })).toBe(1); // only the first, real login
    expect(await prisma.auditLog.count({ where: { action: 'USER_LOGGED_IN', actorId: user.id } })).toBe(0);
    const again = await app.inject({ method: 'POST', url: '/auth/otp/verify', payload: { phone, role: 'TECHNICIAN', otp } });
    expect(again.statusCode).toBe(401);
  });

  it('technician number in the customer app → 409 with the FixCare Pro message', async () => {
    const phone = '9800000015';
    let otp = await sendAndGetOtp(phone, 'TECHNICIAN');
    await app.inject({ method: 'POST', url: '/auth/otp/verify', payload: { phone, role: 'TECHNICIAN', otp } });
    otp = await sendAndGetOtp(phone, 'CUSTOMER');
    const res = await app.inject({ method: 'POST', url: '/auth/otp/verify', payload: { phone, role: 'CUSTOMER', otp } });
    expect(res.statusCode).toBe(409);
    expect(res.json()).toEqual({ code: 'ROLE_MISMATCH', message: 'This number is registered as a FixCare technician. Please use the FixCare Pro app.' });
    expect(await prisma.customer.count()).toBe(0);
  });

  it('an admin\'s number in either app → 409 with the neutral message', async () => {
    const phone = '9800000016';
    await prisma.user.create({ data: { phone, role: 'ADMIN' } });
    const otp = await sendAndGetOtp(phone, 'CUSTOMER');
    const res = await app.inject({ method: 'POST', url: '/auth/otp/verify', payload: { phone, role: 'CUSTOMER', otp } });
    expect(res.json()).toEqual({ code: 'ROLE_MISMATCH', message: "This number can't be used to sign in here." });
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `pnpm vitest run tests/auth/otp-verify.test.ts`
Expected: the three mismatch tests FAIL (200 instead of 409).

- [ ] **Step 3: Implement** — in `auth.service.ts` add `ConflictError` to the errors import, then above `verifyOtp`:

```ts
const ROLE_MISMATCH = 'ROLE_MISMATCH';

/** Shown when a number already belongs to another kind of account. Only reached AFTER the OTP proved the
 *  caller owns the number, so it never tells a stranger which numbers are registered. */
function roleMismatchMessage(existing: UserRole): string {
  if (existing === 'CUSTOMER') return 'This number is registered as a customer. Please use the FixCare customer app.';
  if (existing === 'TECHNICIAN') return 'This number is registered as a FixCare technician. Please use the FixCare Pro app.';
  return "This number can't be used to sign in here.";
}
```

and in `verifyOtp`'s transaction change the `else if` chain to:

```ts
    if (!existing) {
      user = await createUserWithProfile(tx, phone, role);
      isNew = true;
    } else if (existing.role !== role) {
      // The OTP was sent for another app's role. Refuse — never log into (or create) a different account.
      throw new ConflictError(roleMismatchMessage(existing.role), ROLE_MISMATCH);
    } else if (existing.status !== 'ACTIVE' || existing.deletedAt) {
      throw new ForbiddenError('Account is not active');
    }
```

- [ ] **Step 4: Run tests + suite + build**

Run: `pnpm vitest run tests/auth` → PASS; `pnpm vitest run` → green (if any other test logged one phone in under two roles, fix that TEST to use two phones — it was relying on the bug); `pnpm build` → green.

- [ ] **Step 5: Commit**

```bash
git add apps/backend/src/modules/auth/auth.service.ts apps/backend/tests/auth/otp-verify.test.ts
git commit -m "fix(auth): reject a login whose number belongs to another app's role (ROLE_MISMATCH)"
```

---

### Task 7: Technician app data layer — profile DTO, profile repository, zones

**Files:**
- Modify: `apps/technician/lib/features/profile/data/technician_profile_dto.dart` (+ regenerate `.freezed.dart` / `.g.dart`)
- Modify: `apps/technician/lib/features/profile/data/technician_profile_repository.dart`
- Modify: `apps/technician/lib/features/jobs/data/catalog_repository.dart`
- Test: `apps/technician/test/profile/technician_profile_repository_test.dart`, `apps/technician/test/jobs/catalog_repository_test.dart`

**Interfaces:**
- Produces: `ZoneRefDto({required String id, required String name})`; `TechnicianProfileDto` gains `List<ZoneRefDto> zones` (default `[]`), `String? reviewNote`, `String? submittedAt`; `TechnicianProfileRepository.updateProfile({required String name, required List<String> skills, required List<String> zoneIds}) → Future<Result<TechnicianProfileDto>>` (PATCH `/me/profile`); `TechnicianProfileRepository.submit() → Future<Result<TechnicianProfileDto>>` (bodyless POST `/technician/me/submit`); `CatalogRepository.zones() → Future<Result<List<ZoneRefDto>>>` (bodyless GET `/catalog/zones`).

- [ ] **Step 1: Write the failing tests**

In `test/profile/technician_profile_repository_test.dart`, change the setUp adapter to exact-body matching — `adapter = DioAdapter(dio: dio, matcher: const FullHttpRequestMatcher(needsExactBody: true));` — and append:

```dart
  Map<String, dynamic> profile(String status) => {
        'id': 't1', 'role': 'TECHNICIAN', 'name': 'Ramesh', 'skills': ['AC'], 'status': status,
        'zones': [{'id': 'z1', 'name': 'Padra'}], 'reviewNote': null, 'submittedAt': null,
      };

  test('getProfile parses zones, reviewNote and submittedAt', () async {
    adapter.onGet('/me/profile', (s) => s.reply(200, {...profile('PENDING'), 'reviewNote': 'Add your full name', 'submittedAt': '2026-10-01T10:00:00.000Z'}));
    final v = (await repo.getProfile() as Ok<TechnicianProfileDto>).value;
    expect(v.zones, [const ZoneRefDto(id: 'z1', name: 'Padra')]);
    expect(v.reviewNote, 'Add your full name');
    expect(v.submittedAt, '2026-10-01T10:00:00.000Z');
  });

  test('a profile without zones/reviewNote (older backend) still parses', () async {
    adapter.onGet('/me/profile', (s) => s.reply(200, {'id': 't1', 'role': 'TECHNICIAN', 'name': '', 'skills': <String>[], 'status': 'PENDING'}));
    final v = (await repo.getProfile() as Ok<TechnicianProfileDto>).value;
    expect(v.zones, isEmpty);
    expect(v.reviewNote, isNull);
  });

  test('updateProfile PATCHes exactly {name, skills, zoneIds}', () async {
    adapter.onPatch('/me/profile', (s) => s.reply(200, profile('PENDING')),
        data: {'name': 'Ramesh', 'skills': ['AC'], 'zoneIds': ['z1']});
    final v = (await repo.updateProfile(name: 'Ramesh', skills: ['AC'], zoneIds: ['z1']) as Ok<TechnicianProfileDto>).value;
    expect(v.zones.single.name, 'Padra');
  });

  test('updateProfile 409 PROFILE_LOCKED -> Failure with the code and message', () async {
    adapter.onPatch('/me/profile', (s) => s.reply(409, {'code': 'PROFILE_LOCKED', 'message': 'Your profile is locked while under review'}),
        data: {'name': 'R', 'skills': ['AC'], 'zoneIds': ['z1']});
    final f = await repo.updateProfile(name: 'R', skills: ['AC'], zoneIds: ['z1']) as Failure;
    expect(f.code, 'PROFILE_LOCKED');
    expect(f.message, 'Your profile is locked while under review');
  });

  test('submit is a bodyless POST and parses the submitted profile', () async {
    adapter.onPost('/technician/me/submit', (s) => s.reply(200, profile('KYC_SUBMITTED')));
    final v = (await repo.submit() as Ok<TechnicianProfileDto>).value;
    expect(v.status, 'KYC_SUBMITTED');
  });

  test('submit network error -> Failure(network)', () async {
    adapter.onPost('/technician/me/submit', (s) => s.throws(0, DioException.connectionError(requestOptions: RequestOptions(path: '/technician/me/submit'), reason: 'down')));
    expect((await repo.submit() as Failure).kind, FailureKind.network);
  });
```

In `test/jobs/catalog_repository_test.dart` append (using that file's existing `adapter`/`repo`):

```dart
  test('zones is a bodyless GET and parses id + name (extra fields ignored)', () async {
    adapter.onGet('/catalog/zones', (s) => s.reply(200, [
          {'id': 'z1', 'name': 'Padra', 'visitFeePaise': 9900, 'status': 'ACTIVE'},
          {'id': 'z2', 'name': 'Vadodara', 'visitFeePaise': 14900, 'status': 'ACTIVE'},
        ]));
    final v = (await repo.zones() as Ok<List<ZoneRefDto>>).value;
    expect(v.map((z) => z.name), ['Padra', 'Vadodara']);
  });

  test('zones 500 -> Failure with the server message', () async {
    adapter.onGet('/catalog/zones', (s) => s.reply(500, {'code': 'X', 'message': 'boom'}));
    expect((await repo.zones() as Failure).message, 'boom');
  });
```

(Add `import 'package:fixcare_technician/features/profile/data/technician_profile_dto.dart';` to the catalog test.)

- [ ] **Step 2: Run to verify they fail**

Run: `cd apps/technician && flutter test test/profile/technician_profile_repository_test.dart test/jobs/catalog_repository_test.dart`
Expected: compile errors — `ZoneRefDto`, `updateProfile`, `submit`, `zones` undefined.

- [ ] **Step 3: DTO** — `technician_profile_dto.dart`:

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
part 'technician_profile_dto.freezed.dart';
part 'technician_profile_dto.g.dart';

/// A service zone, by id + display name (`GET /catalog/zones` items and the profile's `zones`).
@freezed
abstract class ZoneRefDto with _$ZoneRefDto {
  const factory ZoneRefDto({required String id, required String name}) = _ZoneRefDto;
  factory ZoneRefDto.fromJson(Map<String, dynamic> j) => _$ZoneRefDtoFromJson(j);
}

@freezed
abstract class TechnicianProfileDto with _$TechnicianProfileDto {
  const factory TechnicianProfileDto({
    required String id,
    required String role,
    required String name,
    @Default(<String>[]) List<String> skills,
    required String status,
    @Default(<ZoneRefDto>[]) List<ZoneRefDto> zones,
    /// Ops' reason when the profile was sent back or the account suspended.
    String? reviewNote,
    String? submittedAt,
  }) = _TechnicianProfileDto;
  factory TechnicianProfileDto.fromJson(Map<String, dynamic> j) => _$TechnicianProfileDtoFromJson(j);
}
```

Run: `dart run build_runner build --delete-conflicting-outputs`.

- [ ] **Step 4: Repository** — replace the body of `TechnicianProfileRepository` (keep `_msg` and `_parse`):

```dart
  Future<Result<TechnicianProfileDto>> _guard(Future<Response> Function() send) async {
    try {
      return _parse(await send());
    } on DioException catch (e) {
      if (e.response != null) {
        return Failure(failureKindFromStatus(e.response!.statusCode), _msg(e.response!.data), code: errorCodeOf(e.response!.data));
      }
      return const Failure(FailureKind.network, 'Network error. Check your connection.');
    }
  }

  Future<Result<TechnicianProfileDto>> getProfile() => _guard(() => _dio.get('/me/profile'));

  /// Saves the onboarding form. Allowed only while PENDING (409 PROFILE_LOCKED otherwise).
  Future<Result<TechnicianProfileDto>> updateProfile({required String name, required List<String> skills, required List<String> zoneIds}) =>
      _guard(() => _dio.patch('/me/profile', data: {'name': name, 'skills': skills, 'zoneIds': zoneIds}));

  /// PENDING → KYC_SUBMITTED. Bodyless.
  Future<Result<TechnicianProfileDto>> submit() => _guard(() => _dio.post('/technician/me/submit'));
```

- [ ] **Step 5: Catalog zones** — in `catalog_repository.dart` add `import '../../profile/data/technician_profile_dto.dart';` and:

```dart
  Future<Result<List<ZoneRefDto>>> zones() => _guard(() async {
    final res = await _dio.get('/catalog/zones');
    final status = res.statusCode ?? 0;
    if (status >= 200 && status < 300) {
      final data = res.data;
      if (data is! List) return const Failure(FailureKind.server, 'Unexpected response from the server.');
      return Ok(data.map((e) => ZoneRefDto.fromJson((e as Map).cast<String, dynamic>())).toList());
    }
    return Failure(failureKindFromStatus(status), _msg(res.data), code: errorCodeOf(res.data));
  });
```

- [ ] **Step 6: Run tests + analyze**

Run: `flutter test test/profile test/jobs/catalog_repository_test.dart` → PASS; `flutter test` → green; `flutter analyze` → 0 issues.

- [ ] **Step 7: Commit**

```bash
git add apps/technician/lib/features/profile/data apps/technician/lib/features/jobs/data/catalog_repository.dart apps/technician/test/profile/technician_profile_repository_test.dart apps/technician/test/jobs/catalog_repository_test.dart
git commit -m "feat(technician): profile zones/review fields, save + submit, zones list"
```

---

### Task 8: `AuthController.refreshProfile()` + not-verified interceptor

**Files:**
- Modify: `apps/technician/lib/features/auth/presentation/auth_controller.dart` (+ regenerate `.g.dart`)
- Create: `apps/technician/lib/core/network/not_verified_interceptor.dart`
- Modify: `apps/technician/lib/core/network/dio_client.dart`
- Test: `apps/technician/test/auth/auth_controller_test.dart` (append), `apps/technician/test/core/not_verified_interceptor_test.dart`

**Interfaces:**
- Consumes: Task 7 `TechnicianProfileRepository.getProfile()`.
- Produces: `AuthController.refreshProfile() → Future<Result<TechnicianProfileDto>>` — re-fetches the profile; Ok → emits `SessionAuthenticated(profile, hydrated: true)` unless the session is already hydrated with an equal profile; unauthorized → clears tokens + `SessionUnauthenticated`; other Failure → session unchanged; not signed in → `Failure(FailureKind.unauthorized, 'Not signed in.')` without a request; concurrent calls share one request; a logout during the request wins. `NotVerifiedInterceptor(void Function() onNotVerified)` — calls back on any 403 whose envelope code is `TECHNICIAN_NOT_VERIFIED`.

- [ ] **Step 1: Write the failing tests**

Append to `test/auth/auth_controller_test.dart` (top-level, next to `_FakeProfileRepo`):

```dart
/// Returns queued results in order (the last one repeats); [gate], when set, holds every call until completed.
class _SeqProfileRepo extends TechnicianProfileRepository {
  _SeqProfileRepo(this._results) : super(Dio());
  final List<Result<TechnicianProfileDto>> _results;
  int calls = 0;
  Completer<void>? gate;
  @override
  Future<Result<TechnicianProfileDto>> getProfile() async {
    final r = _results[calls < _results.length ? calls : _results.length - 1];
    calls++;
    if (gate case final g?) await g.future;
    return r;
  }
}

TechnicianProfileDto _p(String status) => TechnicianProfileDto(id: 't1', role: 'TECHNICIAN', name: 'Ramesh', skills: const ['AC'], status: status);
```

(add `import 'dart:async';` at the top), and inside `main()`:

```dart
  Future<(ProviderContainer, _SeqProfileRepo)> booted(List<Result<TechnicianProfileDto>> results) async {
    backing['fixcare.access'] = 'a'; backing['fixcare.refresh'] = 'r';
    final repo = _SeqProfileRepo(results);
    final container = ProviderContainer(overrides: [technicianProfileRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    return (container, repo);
  }

  Session? sessionOf(ProviderContainer c) => c.read(authControllerProvider).value;

  test('refreshProfile: a status change updates the session', () async {
    final (c, _) = await booted([Ok(_p('KYC_SUBMITTED')), Ok(_p('VERIFIED'))]);
    final r = await c.read(authControllerProvider.notifier).refreshProfile();
    expect(r, isA<Ok<TechnicianProfileDto>>());
    expect((sessionOf(c)! as SessionAuthenticated).status, 'VERIFIED');
  });

  test('refreshProfile: an unchanged profile does not re-emit the session', () async {
    final (c, _) = await booted([Ok(_p('KYC_SUBMITTED'))]);
    var emits = 0;
    c.listen(authControllerProvider, (_, _) => emits++);
    await c.read(authControllerProvider.notifier).refreshProfile();
    expect(emits, 0);
  });

  test('refreshProfile: a network failure keeps the current session', () async {
    final (c, _) = await booted([Ok(_p('KYC_SUBMITTED')), const Failure(FailureKind.network, 'down')]);
    final r = await c.read(authControllerProvider.notifier).refreshProfile();
    expect((r as Failure).kind, FailureKind.network);
    expect((sessionOf(c)! as SessionAuthenticated).status, 'KYC_SUBMITTED');
  });

  test('refreshProfile: 401 clears tokens and signs out', () async {
    final (c, _) = await booted([Ok(_p('VERIFIED')), const Failure(FailureKind.unauthorized, 'stale')]);
    await c.read(authControllerProvider.notifier).refreshProfile();
    expect(sessionOf(c), isA<SessionUnauthenticated>());
    expect(backing['fixcare.access'], isNull);
  });

  test('refreshProfile: an unhydrated session becomes hydrated', () async {
    final (c, _) = await booted([const Failure(FailureKind.network, 'down'), Ok(_p('PENDING'))]);
    expect((sessionOf(c)! as SessionAuthenticated).hydrated, false);
    await c.read(authControllerProvider.notifier).refreshProfile();
    expect((sessionOf(c)! as SessionAuthenticated).hydrated, true);
  });

  test('refreshProfile: concurrent calls share one request', () async {
    final (c, repo) = await booted([Ok(_p('KYC_SUBMITTED')), Ok(_p('VERIFIED'))]);
    final n = c.read(authControllerProvider.notifier);
    await Future.wait([n.refreshProfile(), n.refreshProfile(), n.refreshProfile()]);
    expect(repo.calls, 2); // 1 boot + 1 shared refresh
  });

  test('refreshProfile: a logout while the request is in flight is not undone', () async {
    final (c, repo) = await booted([Ok(_p('KYC_SUBMITTED')), Ok(_p('VERIFIED'))]);
    repo.gate = Completer<void>();
    final pending = c.read(authControllerProvider.notifier).refreshProfile();
    c.read(authControllerProvider.notifier).onAuthLost();
    repo.gate!.complete();
    await pending;
    expect(sessionOf(c), isA<SessionUnauthenticated>());
  });

  test('refreshProfile when signed out makes no request', () async {
    final repo = _SeqProfileRepo([Ok(_p('VERIFIED'))]);
    final c = ProviderContainer(overrides: [technicianProfileRepositoryProvider.overrideWithValue(repo)]);
    addTearDown(c.dispose);
    await c.read(authControllerProvider.future);
    final r = await c.read(authControllerProvider.notifier).refreshProfile();
    expect((r as Failure).kind, FailureKind.unauthorized);
    expect(repo.calls, 0);
  });
```

Create `test/core/not_verified_interceptor_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:fixcare_technician/core/network/not_verified_interceptor.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late int calls;
  setUp(() {
    calls = 0;
    dio = Dio(BaseOptions(baseUrl: 'http://test', validateStatus: (_) => true));
    dio.interceptors.add(NotVerifiedInterceptor(() => calls++));
    adapter = DioAdapter(dio: dio);
  });

  test('403 TECHNICIAN_NOT_VERIFIED → callback, response passed through', () async {
    adapter.onGet('/technician/jobs/mine', (s) => s.reply(403, {'code': 'TECHNICIAN_NOT_VERIFIED', 'message': 'Verified technician required'}));
    final res = await dio.get('/technician/jobs/mine');
    expect(res.statusCode, 403);
    expect(calls, 1);
  });

  test('other 403s, other codes and successes → no callback', () async {
    adapter.onGet('/a', (s) => s.reply(403, {'code': 'JOB_NOT_ASSIGNED', 'message': 'x'}));
    adapter.onGet('/b', (s) => s.reply(409, {'code': 'TECHNICIAN_NOT_VERIFIED', 'message': 'x'}));
    adapter.onGet('/c', (s) => s.reply(200, {'ok': true}));
    await dio.get('/a');
    await dio.get('/b');
    await dio.get('/c');
    expect(calls, 0);
  });
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/auth/auth_controller_test.dart test/core/not_verified_interceptor_test.dart`
Expected: compile errors — `refreshProfile` / `NotVerifiedInterceptor` undefined.

- [ ] **Step 3: Implement `refreshProfile`** — in `AuthController` add:

```dart
  Future<Result<TechnicianProfileDto>>? _refreshing;

  /// Re-reads the profile so status changes made by ops (verified, sent back, suspended, reinstated) reach
  /// the home gate without a re-login. Concurrent callers share one request. A transient failure keeps the
  /// current session (never eject on a blip); 401 signs out.
  Future<Result<TechnicianProfileDto>> refreshProfile() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<Result<TechnicianProfileDto>> _refresh() async {
    // Never the stale value of an error state (Riverpod 3 keeps the previous value on AsyncError).
    final before = state.hasError ? null : state.value;
    if (before is! SessionAuthenticated) return const Failure(FailureKind.unauthorized, 'Not signed in.');
    final r = await ref.read(technicianProfileRepositoryProvider).getProfile();
    if (!ref.mounted) return r;
    // A logout / session loss that landed while the request was in flight wins — never resurrect a session.
    final now = state.hasError ? null : state.value;
    if (now is! SessionAuthenticated) return r;
    switch (r) {
      case Ok(value: final profile):
        if (!(now.hydrated && now.profile == profile)) state = AsyncData(SessionAuthenticated(profile, hydrated: true));
      case Failure(kind: FailureKind.unauthorized):
        await ref.read(tokenStoreProvider).clear();
        if (ref.mounted) state = const AsyncData(SessionUnauthenticated());
      case Failure():
        break;
    }
    return r;
  }
```

Run: `dart run build_runner build --delete-conflicting-outputs`.

- [ ] **Step 4: Interceptor** — `lib/core/network/not_verified_interceptor.dart`:

```dart
import 'package:dio/dio.dart';
import '../result.dart';

/// A job call answered 403 `TECHNICIAN_NOT_VERIFIED`: ops suspended (or un-verified) this technician while
/// they were using the app. Tell the session to re-check the profile so the home gate shows the right
/// screen instead of a generic error. The response itself is passed through untouched.
class NotVerifiedInterceptor extends Interceptor {
  NotVerifiedInterceptor(this._onNotVerified);
  final void Function() _onNotVerified;

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (response.statusCode == 403 && errorCodeOf(response.data) == 'TECHNICIAN_NOT_VERIFIED') _onNotVerified();
    handler.next(response);
  }
}
```

In `dio_client.dart` (add `import 'dart:async';` and `import 'not_verified_interceptor.dart';`), add BEFORE the `AuthInterceptor` (so it sees every response, including ones the auth interceptor later resolves):

```dart
  dio.interceptors.add(NotVerifiedInterceptor(
    // Lazy read at call time (no provider cycle); refreshProfile de-dupes a burst of 403s into one fetch.
    () => unawaited(ref.read(authControllerProvider.notifier).refreshProfile()),
  ));
```

- [ ] **Step 5: Run tests + analyze**

Run: `flutter test test/auth test/core` → PASS; `flutter test` → green; `flutter analyze` → 0 issues.

- [ ] **Step 6: Commit**

```bash
git add apps/technician/lib/features/auth/presentation apps/technician/lib/core/network apps/technician/test/auth/auth_controller_test.dart apps/technician/test/core/not_verified_interceptor_test.dart
git commit -m "feat(technician): refreshProfile + re-check on TECHNICIAN_NOT_VERIFIED"
```

---

### Task 9: Onboarding form (PENDING)

**Files:**
- Create: `apps/technician/lib/features/onboarding/presentation/skills.dart`, `apps/technician/lib/features/onboarding/presentation/onboarding_screen.dart`
- Test: `apps/technician/test/onboarding/onboarding_screen_test.dart`

**Interfaces:**
- Consumes: Task 7 `updateProfile`, `submit`, `zones()`; Task 8 `refreshProfile()`; session `SessionAuthenticated.profile`.
- Produces: `const kSkills = <(String, String)>[...]` and `String skillLabel(String code)`; `OnboardingScreen` (key `onboardingScreen`); widget keys `sentBackBanner`, `nameField`, `skill_<CODE>`, `zone_<id>`, `zonesLoading`, `zonesError`, `zonesRetryBtn`, `zonesEmpty`, `submitForVerificationBtn`, `confirmSubmitBtn`, `cancelSubmitBtn`, `logoutBtn`; `const kSubmitConfirmBody`.

- [ ] **Step 1: Write the failing test** — `test/onboarding/onboarding_screen_test.dart`

```dart
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/features/auth/domain/session.dart';
import 'package:fixcare_technician/features/auth/presentation/auth_controller.dart';
import 'package:fixcare_technician/features/jobs/data/catalog_repository.dart';
import 'package:fixcare_technician/features/onboarding/presentation/onboarding_screen.dart';
import 'package:fixcare_technician/features/profile/data/technician_profile_repository.dart';

const _padra = ZoneRefDto(id: 'z1', name: 'Padra');
const _vadodara = ZoneRefDto(id: 'z2', name: 'Vadodara');

TechnicianProfileDto _profile({String name = 'Ramesh', List<String> skills = const ['AC'], List<ZoneRefDto> zones = const [_padra], String? reviewNote}) =>
    TechnicianProfileDto(id: 't1', role: 'TECHNICIAN', name: name, skills: skills, status: 'PENDING', zones: zones, reviewNote: reviewNote);

class _FakeAuth extends AuthController {
  _FakeAuth(this._session);
  final Session _session;
  int refreshCalls = 0;
  @override
  Future<Session> build() async => _session;
  @override
  Future<Result<TechnicianProfileDto>> refreshProfile() async {
    refreshCalls++;
    return Ok(_profile());
  }
}

class _FakeProfileRepo extends TechnicianProfileRepository {
  _FakeProfileRepo() : super(Dio());
  final calls = <String>[];
  Map<String, Object?>? lastPatch;
  List<Result<TechnicianProfileDto>> patchResults = [Ok(_profile())];
  List<Result<TechnicianProfileDto>> submitResults = [Ok(_profile())];
  @override
  Future<Result<TechnicianProfileDto>> updateProfile({required String name, required List<String> skills, required List<String> zoneIds}) async {
    calls.add('patch');
    lastPatch = {'name': name, 'skills': skills, 'zoneIds': zoneIds};
    return patchResults.length > 1 ? patchResults.removeAt(0) : patchResults.first;
  }
  @override
  Future<Result<TechnicianProfileDto>> submit() async {
    calls.add('submit');
    return submitResults.length > 1 ? submitResults.removeAt(0) : submitResults.first;
  }
}

class _FakeCatalog extends CatalogRepository {
  _FakeCatalog(this.results) : super(Dio());
  final List<Result<List<ZoneRefDto>>> results;
  int calls = 0;
  Completer<void>? gate;
  @override
  Future<Result<List<ZoneRefDto>>> zones() async {
    final r = results[calls < results.length ? calls : results.length - 1];
    calls++;
    if (gate case final g?) await g.future;
    return r;
  }
}

void main() {
  late _FakeAuth auth;
  late _FakeProfileRepo profileRepo;
  late _FakeCatalog catalog;

  /// Builds the screen only once the session has loaded — exactly what HomeGate guarantees in the app
  /// (the screen prefills from the session in initState).
  Future<void> pump(WidgetTester tester, {TechnicianProfileDto? profile, List<Result<List<ZoneRefDto>>>? zones, _FakeCatalog? catalogOverride, bool settle = true}) async {
    auth = _FakeAuth(SessionAuthenticated(profile ?? _profile()));
    profileRepo = _FakeProfileRepo();
    catalog = catalogOverride ?? _FakeCatalog(zones ?? [const Ok([_padra, _vadodara])]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => auth),
        technicianProfileRepositoryProvider.overrideWithValue(profileRepo),
        catalogRepositoryProvider.overrideWithValue(catalog),
      ],
      child: MaterialApp(
        home: Consumer(builder: (_, ref, _) => ref.watch(authControllerProvider).hasValue ? const OnboardingScreen() : const SizedBox()),
      ),
    ));
    await tester.pump();
    await tester.pump();
    if (settle) await tester.pumpAndSettle();
  }

  FilledButton submitBtn(WidgetTester t) => t.widget<FilledButton>(find.byKey(const Key('submitForVerificationBtn')));

  Future<void> submitAndConfirm(WidgetTester tester) async {
    // A SnackBar from an earlier attempt could sit over the button.
    ScaffoldMessenger.of(tester.element(find.byType(OnboardingScreen))).removeCurrentSnackBar();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('submitForVerificationBtn')));
    await tester.tap(find.byKey(const Key('submitForVerificationBtn')));
    await tester.pumpAndSettle();
    expect(find.text(kSubmitConfirmBody), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmSubmitBtn')));
    await tester.pumpAndSettle();
  }

  testWidgets('prefills name, skills and zones from the profile; submit enabled', (tester) async {
    await pump(tester);
    expect(tester.widget<TextField>(find.byKey(const Key('nameField'))).controller!.text, 'Ramesh');
    expect(tester.widget<FilterChip>(find.byKey(const Key('skill_AC'))).selected, true);
    expect(tester.widget<FilterChip>(find.byKey(const Key('skill_FAN'))).selected, false);
    expect(tester.widget<CheckboxListTile>(find.byKey(const Key('zone_z1'))).value, true);
    expect(tester.widget<CheckboxListTile>(find.byKey(const Key('zone_z2'))).value, false);
    expect(submitBtn(tester).onPressed, isNotNull);
    expect(find.byKey(const Key('sentBackBanner')), findsNothing);
  });

  testWidgets('submit disabled without a name, a skill or a zone', (tester) async {
    await pump(tester, profile: _profile(name: '', skills: const [], zones: const []));
    expect(submitBtn(tester).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('nameField')), 'Ramesh');
    await tester.tap(find.byKey(const Key('skill_FAN')));
    await tester.pump();
    expect(submitBtn(tester).onPressed, isNull); // still no zone
    await tester.tap(find.byKey(const Key('zone_z2')));
    await tester.pump();
    expect(submitBtn(tester).onPressed, isNotNull);
    await tester.enterText(find.byKey(const Key('nameField')), '   ');
    await tester.pump();
    expect(submitBtn(tester).onPressed, isNull);
  });

  testWidgets('sent back: the banner shows ops\' reason', (tester) async {
    await pump(tester, profile: _profile(reviewNote: 'Remove Wiring unless you hold a licence'));
    expect(find.byKey(const Key('sentBackBanner')), findsOneWidget);
    expect(find.text('FixCare sent your profile back'), findsOneWidget);
    expect(find.text('Remove Wiring unless you hold a licence'), findsOneWidget);
    expect(find.text('Please fix and resubmit.'), findsOneWidget);
  });

  testWidgets('cancel in the confirm dialog sends nothing', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('submitForVerificationBtn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cancelSubmitBtn')));
    await tester.pumpAndSettle();
    expect(profileRepo.calls, isEmpty);
  });

  testWidgets('confirm → save (trimmed, canonical order) → submit → refresh, in order', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('nameField')), '  Ramesh Patel ');
    await tester.tap(find.byKey(const Key('skill_WIRING')));
    await tester.tap(find.byKey(const Key('zone_z2')));
    await tester.pump();
    await submitAndConfirm(tester);
    expect(profileRepo.calls, ['patch', 'submit']);
    expect(profileRepo.lastPatch, {'name': 'Ramesh Patel', 'skills': ['AC', 'WIRING'], 'zoneIds': ['z1', 'z2']});
    expect(auth.refreshCalls, 1);
  });

  testWidgets('save failure → SnackBar with the message, no submit, button usable again', (tester) async {
    await pump(tester);
    profileRepo.patchResults = [const Failure(FailureKind.server, 'Choose service zones from the list')];
    await submitAndConfirm(tester);
    expect(find.text('Choose service zones from the list'), findsOneWidget);
    expect(profileRepo.calls, ['patch']);
    expect(submitBtn(tester).onPressed, isNotNull);
  });

  testWidgets('submit failure → SnackBar; tapping again re-saves then submits', (tester) async {
    await pump(tester);
    profileRepo.submitResults = [const Failure(FailureKind.network, 'Network error. Check your connection.'), Ok(_profile())];
    await submitAndConfirm(tester);
    expect(find.text('Network error. Check your connection.'), findsOneWidget);
    await submitAndConfirm(tester);
    expect(profileRepo.calls, ['patch', 'submit', 'patch', 'submit']);
    expect(auth.refreshCalls, 1);
  });

  testWidgets('save answers PROFILE_LOCKED (an earlier submit landed) → re-checks the profile', (tester) async {
    await pump(tester);
    profileRepo.patchResults = [const Failure(FailureKind.unknown, 'Your profile is locked while under review', code: 'PROFILE_LOCKED')];
    await submitAndConfirm(tester);
    expect(auth.refreshCalls, 1);
    expect(profileRepo.calls, ['patch']);
  });

  testWidgets('a prefilled zone that is no longer offered is not sent', (tester) async {
    await pump(tester, profile: _profile(zones: const [_padra, ZoneRefDto(id: 'zOld', name: 'Old')]), zones: [const Ok([_padra])]);
    await submitAndConfirm(tester);
    expect(profileRepo.lastPatch!['zoneIds'], ['z1']);
  });

  testWidgets('zones: loading, then error with Retry, then empty state', (tester) async {
    final gated = _FakeCatalog([const Failure(FailureKind.server, 'boom'), const Ok(<ZoneRefDto>[])])..gate = Completer<void>();
    await pump(tester, profile: _profile(zones: const []), catalogOverride: gated, settle: false);
    expect(find.byKey(const Key('zonesLoading')), findsOneWidget);
    catalog.gate!.complete();
    catalog.gate = null;
    await tester.pumpAndSettle();
    expect(find.text('boom'), findsOneWidget);
    await tester.tap(find.byKey(const Key('zonesRetryBtn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('zonesEmpty')), findsOneWidget);
    expect(submitBtn(tester).onPressed, isNull);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/onboarding/onboarding_screen_test.dart`
Expected: compile error — `onboarding_screen.dart` missing.

- [ ] **Step 3: Skills** — `lib/features/onboarding/presentation/skills.dart`:

```dart
/// The backend's ServiceSkill values with their display labels, in display (and submit) order.
const kSkills = <(String, String)>[
  ('AC', 'AC'),
  ('FAN', 'Fan'),
  ('ELECTRICAL', 'Electrical'),
  ('WIRING', 'Wiring'),
  ('APPLIANCE', 'Appliance'),
];

String skillLabel(String code) => kSkills.firstWhere((s) => s.$1 == code, orElse: () => (code, code)).$2;
```

- [ ] **Step 4: Screen** — `lib/features/onboarding/presentation/onboarding_screen.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result.dart';
import '../../../core/theme.dart';
import '../../auth/domain/session.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../jobs/data/catalog_repository.dart';
import '../../profile/data/technician_profile_repository.dart';
import 'skills.dart';

const kSubmitConfirmBody = "Submit your details? You won't be able to change them while FixCare reviews your profile.";

/// A PENDING technician (new, or sent back by ops): name + skills + service zones, then "Submit for
/// verification". Ops verifies in person — no documents are collected here.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _name = TextEditingController();
  final _skills = <String>{};
  final _zoneIds = <String>{};
  String? _reviewNote;
  List<ZoneRefDto>? _zones; // null while loading
  String? _zonesError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final s = ref.read(authControllerProvider).value;
    if (s is SessionAuthenticated) {
      _name.text = s.profile.name;
      _skills.addAll(s.profile.skills.where((c) => kSkills.any((k) => k.$1 == c)));
      _zoneIds.addAll(s.profile.zones.map((z) => z.id));
      _reviewNote = s.profile.reviewNote;
    }
    _name.addListener(_onNameChanged);
    unawaited(_fetchZones());
  }

  @override
  void dispose() {
    _name.removeListener(_onNameChanged);
    _name.dispose();
    super.dispose();
  }

  void _onNameChanged() => setState(() {});

  Future<void> _fetchZones() async {
    final r = await ref.read(catalogRepositoryProvider).zones();
    if (!mounted) return;
    setState(() {
      switch (r) {
        case Ok(value: final zones):
          _zones = zones;
        case Failure(message: final m):
          _zonesError = m;
      }
    });
  }

  void _retryZones() {
    setState(() {
      _zones = null;
      _zonesError = null;
    });
    unawaited(_fetchZones());
  }

  /// Only zones still offered are sent: a prefilled zone ops has since deactivated would 422 forever.
  List<String> get _selectedZoneIds => [for (final z in _zones ?? const <ZoneRefDto>[]) if (_zoneIds.contains(z.id)) z.id];

  bool get _valid => _name.text.trim().isNotEmpty && _skills.isNotEmpty && _selectedZoneIds.isNotEmpty;

  void _snack(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _submit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Submit for verification'),
        content: const Text(kSubmitConfirmBody),
        actions: [
          TextButton(key: const Key('cancelSubmitBtn'), onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(key: const Key('confirmSubmitBtn'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Submit')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(technicianProfileRepositoryProvider);
      final saved = await repo.updateProfile(
        name: _name.text.trim(),
        skills: [for (final (code, _) in kSkills) if (_skills.contains(code)) code],
        zoneIds: _selectedZoneIds,
      );
      if (!mounted) return;
      if (saved case Failure(:final message, :final code)) {
        _snack(message);
        // Already submitted (an earlier tap whose response was lost): re-check so the gate shows "under review".
        if (code == 'PROFILE_LOCKED') await ref.read(authControllerProvider.notifier).refreshProfile();
        return;
      }
      final sent = await repo.submit();
      if (!mounted) return;
      if (sent case Failure(:final message)) {
        _snack(message);
        return;
      }
      // KYC_SUBMITTED → the home gate swaps this screen for "Verification pending".
      await ref.read(authControllerProvider.notifier).refreshProfile();
    } catch (e, st) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: e,
        stack: st,
        library: 'fixcare onboarding',
        context: ErrorDescription('submitting the onboarding form'),
      ));
      if (mounted) _snack('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('onboardingScreen'),
      appBar: AppBar(
        title: const Text('Your details'),
        actions: [
          TextButton(
            key: const Key('logoutBtn'),
            onPressed: _busy ? null : () => ref.read(authControllerProvider.notifier).logout(),
            child: const Text('Log out'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            if (_reviewNote case final note? when note.trim().isNotEmpty) _SentBackBanner(note: note),
            const Text(
              'Tell FixCare about your work. Our team will verify you in person.',
              style: TextStyle(fontSize: 14.5, color: FixCareColors.textMuted, height: 1.5),
            ),
            const SizedBox(height: 20),
            TextField(
              key: const Key('nameField'),
              controller: _name,
              enabled: !_busy,
              maxLength: 80,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Full name'),
            ),
            const SizedBox(height: 8),
            const _SectionTitle('Skills'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (code, label) in kSkills)
                  FilterChip(
                    key: Key('skill_$code'),
                    label: Text(label),
                    selected: _skills.contains(code),
                    onSelected: _busy ? null : (on) => setState(() => on ? _skills.add(code) : _skills.remove(code)),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            const _SectionTitle('Service zones'),
            _zonesSection(),
            const SizedBox(height: 28),
            FilledButton(
              key: const Key('submitForVerificationBtn'),
              onPressed: _valid && !_busy ? _submit : null,
              child: _busy
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Submit for verification'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _zonesSection() {
    if (_zonesError case final err?) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(err, key: const Key('zonesError'), style: const TextStyle(color: FixCareColors.errorText)),
          TextButton(key: const Key('zonesRetryBtn'), onPressed: _retryZones, child: const Text('Retry')),
        ],
      );
    }
    final zones = _zones;
    if (zones == null) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator(key: Key('zonesLoading'))),
      );
    }
    if (zones.isEmpty) {
      return const Text('No service zones are open yet. Please check back later.', key: Key('zonesEmpty'));
    }
    return Column(
      children: [
        for (final z in zones)
          CheckboxListTile(
            key: Key('zone_${z.id}'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(z.name),
            value: _zoneIds.contains(z.id),
            onChanged: _busy ? null : (on) => setState(() => on == true ? _zoneIds.add(z.id) : _zoneIds.remove(z.id)),
          ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: FixCareColors.textPrimary)),
      );
}

class _SentBackBanner extends StatelessWidget {
  const _SentBackBanner({required this.note});
  final String note;
  @override
  Widget build(BuildContext context) => Container(
        key: const Key('sentBackBanner'),
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: FixCareColors.errorFill,
          border: Border.all(color: FixCareColors.errorBorder),
          borderRadius: BorderRadius.circular(FixCareRadii.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('FixCare sent your profile back', style: TextStyle(fontWeight: FontWeight.w600, color: FixCareColors.errorText)),
            const SizedBox(height: 6),
            Text(note, style: const TextStyle(color: FixCareColors.errorText, height: 1.4)),
            const SizedBox(height: 6),
            const Text('Please fix and resubmit.', style: TextStyle(color: FixCareColors.errorText)),
          ],
        ),
      );
}
```

- [ ] **Step 5: Run tests + analyze**

Run: `flutter test test/onboarding/onboarding_screen_test.dart` → PASS; `flutter test` → green; `flutter analyze` → 0 issues.

- [ ] **Step 6: Commit**

```bash
git add apps/technician/lib/features/onboarding apps/technician/test/onboarding/onboarding_screen_test.dart
git commit -m "feat(technician): onboarding form — name, skills, service zones, submit for verification"
```

---

### Task 10: Under review (polls) + Suspended screens

**Files:**
- Create: `apps/technician/lib/features/onboarding/presentation/submitted_summary.dart`, `under_review_screen.dart`, `suspended_screen.dart`
- Test: `apps/technician/test/onboarding/under_review_screen_test.dart`, `apps/technician/test/onboarding/suspended_screen_test.dart`

**Interfaces:**
- Consumes: Task 8 `refreshProfile()`; Task 9 `skillLabel`.
- Produces: `const reviewPollInterval = Duration(seconds: 30)`; `UnderReviewScreen` (key `underReviewScreen`, text key `verificationStatusText`, button `checkStatusBtn`, `logoutBtn`); `SuspendedScreen` (key `suspendedScreen`, reason key `suspensionReason`, button `checkAgainBtn`, `logoutBtn`); `SubmittedSummary(profile)` (key `submittedSummary`).

- [ ] **Step 1: Write the failing tests**

`test/onboarding/under_review_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/features/auth/domain/session.dart';
import 'package:fixcare_technician/features/auth/presentation/auth_controller.dart';
import 'package:fixcare_technician/features/onboarding/presentation/under_review_screen.dart';
import 'package:fixcare_technician/features/profile/data/technician_profile_dto.dart';

TechnicianProfileDto _p(String status) => TechnicianProfileDto(
    id: 't1', role: 'TECHNICIAN', name: 'Ramesh', skills: const ['AC', 'WIRING'], status: status,
    zones: const [ZoneRefDto(id: 'z1', name: 'Padra')]);

class _FakeAuth extends AuthController {
  int refreshCalls = 0;
  Result<TechnicianProfileDto> next = Ok(_p('KYC_SUBMITTED'));
  @override
  Future<Session> build() async => SessionAuthenticated(_p('KYC_SUBMITTED'));
  @override
  Future<Result<TechnicianProfileDto>> refreshProfile() async {
    refreshCalls++;
    return next;
  }
}

void main() {
  late _FakeAuth auth;
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester tester) async {
    auth = _FakeAuth();
    await tester.pumpWidget(ProviderScope(
      overrides: [authControllerProvider.overrideWith(() => auth)],
      child: const MaterialApp(home: UnderReviewScreen()),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) => tester.pumpWidget(const SizedBox());

  testWidgets('shows the copy and a read-only summary of what was submitted', (tester) async {
    await pump(tester);
    expect(find.text('Verification pending'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('verificationStatusText'))).data, 'Your details are with FixCare for verification');
    expect(find.text('Ramesh'), findsOneWidget);
    expect(find.text('AC, Wiring'), findsOneWidget);
    expect(find.text('Padra'), findsOneWidget);
    expect(auth.refreshCalls, 0); // no check on mount (the session was just loaded)
    await unmount(tester);
  });

  testWidgets('re-checks every 30 s while in the foreground', (tester) async {
    await pump(tester);
    await tester.pump(const Duration(seconds: 29));
    expect(auth.refreshCalls, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(auth.refreshCalls, 1);
    await tester.pump(reviewPollInterval);
    expect(auth.refreshCalls, 2);
    await unmount(tester);
  });

  testWidgets('pauses in the background; checks right away on resume', (tester) async {
    addTearDown(() => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));
    await pump(tester);
    for (final st in const [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      binding.handleAppLifecycleStateChanged(st);
    }
    await tester.pump(const Duration(minutes: 3));
    expect(auth.refreshCalls, 0);
    for (final st in const [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      binding.handleAppLifecycleStateChanged(st);
    }
    await tester.pump();
    expect(auth.refreshCalls, 1);
    await tester.pump(reviewPollInterval);
    expect(auth.refreshCalls, 2);
    await unmount(tester);
  });

  testWidgets('Check status: still under review → a SnackBar; a failure → its message', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('checkStatusBtn')));
    await tester.pumpAndSettle();
    expect(find.text("Still under review. We'll update this screen when FixCare decides."), findsOneWidget);
    auth.next = const Failure(FailureKind.network, 'Network error. Check your connection.');
    await tester.tap(find.byKey(const Key('checkStatusBtn')));
    await tester.pumpAndSettle();
    expect(find.text('Network error. Check your connection.'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('pull to refresh re-checks', (tester) async {
    await pump(tester);
    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(auth.refreshCalls, 1);
    await unmount(tester);
  });
}
```

`test/onboarding/suspended_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/features/auth/domain/session.dart';
import 'package:fixcare_technician/features/auth/presentation/auth_controller.dart';
import 'package:fixcare_technician/features/onboarding/presentation/suspended_screen.dart';
import 'package:fixcare_technician/features/profile/data/technician_profile_dto.dart';

TechnicianProfileDto _p({String? note}) =>
    TechnicianProfileDto(id: 't1', role: 'TECHNICIAN', name: 'Ramesh', status: 'SUSPENDED', reviewNote: note);

class _FakeAuth extends AuthController {
  _FakeAuth(this.profile);
  final TechnicianProfileDto profile;
  int refreshCalls = 0;
  @override
  Future<Session> build() async => SessionAuthenticated(profile);
  @override
  Future<Result<TechnicianProfileDto>> refreshProfile() async {
    refreshCalls++;
    return Ok(profile);
  }
}

void main() {
  Future<_FakeAuth> pump(WidgetTester tester, TechnicianProfileDto p) async {
    final auth = _FakeAuth(p);
    await tester.pumpWidget(ProviderScope(
      overrides: [authControllerProvider.overrideWith(() => auth)],
      child: const MaterialApp(home: SuspendedScreen()),
    ));
    await tester.pumpAndSettle();
    return auth;
  }

  testWidgets('shows the reason and the support pointer; Check again re-checks', (tester) async {
    final auth = await pump(tester, _p(note: 'Customer complaint under review'));
    expect(find.text('Account suspended'), findsOneWidget);
    expect(find.text('Customer complaint under review'), findsOneWidget);
    expect(find.text('Contact FixCare support'), findsOneWidget);
    await tester.tap(find.byKey(const Key('checkAgainBtn')));
    await tester.pumpAndSettle();
    expect(auth.refreshCalls, 1);
    expect(find.text('Your account is still suspended.'), findsOneWidget);
  });

  testWidgets('no reason → no reason box', (tester) async {
    await pump(tester, _p());
    expect(find.byKey(const Key('suspensionReason')), findsNothing);
  });

  testWidgets('a 500-character reason wraps on a 320 px wide phone (no overflow)', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester, _p(note: 'word ' * 100));
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/onboarding/under_review_screen_test.dart test/onboarding/suspended_screen_test.dart`
Expected: compile errors — screens missing.

- [ ] **Step 3: Summary widget** — `lib/features/onboarding/presentation/submitted_summary.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../profile/data/technician_profile_dto.dart';
import 'skills.dart';

/// Read-only recap of what the technician submitted (name, skills, zone names).
class SubmittedSummary extends StatelessWidget {
  const SubmittedSummary({super.key, required this.profile});
  final TechnicianProfileDto profile;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('submittedSummary'),
      margin: const EdgeInsets.symmetric(vertical: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FixCareColors.surface,
        border: Border.all(color: FixCareColors.border),
        borderRadius: BorderRadius.circular(FixCareRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row('Name', profile.name),
          _row('Skills', profile.skills.map(skillLabel).join(', ')),
          _row('Service zones', profile.zones.map((z) => z.name).join(', ')),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12.5, color: FixCareColors.textMuted)),
            Text(value, style: const TextStyle(fontSize: 15, color: FixCareColors.textPrimary)),
          ],
        ),
      );
}
```

- [ ] **Step 4: Under review screen** — `lib/features/onboarding/presentation/under_review_screen.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result.dart';
import '../../../core/theme.dart';
import '../../auth/domain/session.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../profile/data/technician_profile_dto.dart';
import 'submitted_summary.dart';

const reviewPollInterval = Duration(seconds: 30);

/// KYC_SUBMITTED: waiting for ops. Re-checks the profile every 30 s while in the foreground (a chain of
/// one-shot timers — the next check is armed only after the current one finishes), pauses in the
/// background, checks right away on resume, and on pull-to-refresh / "Check status". When ops decides,
/// the home gate swaps this screen out (which disposes the timer).
class UnderReviewScreen extends ConsumerStatefulWidget {
  const UnderReviewScreen({super.key});

  @override
  ConsumerState<UnderReviewScreen> createState() => _UnderReviewScreenState();
}

class _UnderReviewScreenState extends ConsumerState<UnderReviewScreen> {
  late final AppLifecycleListener _lifecycle;
  Timer? _timer;
  bool _paused = false;
  bool _checking = false;
  bool _manualBusy = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onHide: _pause, onPause: _pause, onResume: _resume);
    _arm();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  void _arm() {
    _timer?.cancel();
    _timer = null;
    if (_paused || !mounted) return;
    _timer = Timer(reviewPollInterval, () => unawaited(_tick()));
  }

  Future<void> _tick() async {
    await _check();
    _arm();
  }

  void _pause() {
    _paused = true;
    _timer?.cancel();
    _timer = null;
  }

  void _resume() {
    if (!_paused) return;
    _paused = false;
    unawaited(_tick());
  }

  /// One check at a time; null when one was already running.
  Future<Result<TechnicianProfileDto>?> _check() async {
    if (_checking || !mounted) return null;
    _checking = true;
    try {
      return await ref.read(authControllerProvider.notifier).refreshProfile();
    } catch (e, st) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: e,
        stack: st,
        library: 'fixcare onboarding',
        context: ErrorDescription('re-checking the verification status'),
      ));
      return null;
    } finally {
      _checking = false;
    }
  }

  Future<void> _manualCheck() async {
    setState(() => _manualBusy = true);
    try {
      final r = await _check();
      if (!mounted || r == null) return;
      final msg = switch (r) {
        Ok(value: final p) when p.status == 'KYC_SUBMITTED' => "Still under review. We'll update this screen when FixCare decides.",
        Ok() => null,
        Failure(message: final m) => m,
      };
      if (msg != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _manualBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(authControllerProvider).value;
    final profile = s is SessionAuthenticated ? s.profile : null;
    return Scaffold(
      key: const Key('underReviewScreen'),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _manualCheck,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 24),
              const Icon(Icons.hourglass_top, size: 48, color: FixCareColors.primary),
              const SizedBox(height: 20),
              Text('Verification pending', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 10),
              const Text(
                'Your details are with FixCare for verification',
                key: Key('verificationStatusText'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14.5, color: FixCareColors.textMuted, height: 1.5),
              ),
              if (profile != null) SubmittedSummary(profile: profile),
              FilledButton(
                key: const Key('checkStatusBtn'),
                onPressed: _manualBusy ? null : _manualCheck,
                child: const Text('Check status'),
              ),
              const SizedBox(height: 8),
              TextButton(
                key: const Key('logoutBtn'),
                onPressed: () => ref.read(authControllerProvider.notifier).logout(),
                child: const Text('Log out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Suspended screen** — `lib/features/onboarding/presentation/suspended_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result.dart';
import '../../../core/theme.dart';
import '../../auth/domain/session.dart';
import '../../auth/presentation/auth_controller.dart';

/// SUSPENDED (or DEACTIVATED): blocked from jobs. Shows ops' reason; "Check again" / pull-to-refresh
/// re-checks so a reinstated technician gets back in (no timer — reinstatement is rare).
class SuspendedScreen extends ConsumerStatefulWidget {
  const SuspendedScreen({super.key});

  @override
  ConsumerState<SuspendedScreen> createState() => _SuspendedScreenState();
}

class _SuspendedScreenState extends ConsumerState<SuspendedScreen> {
  bool _busy = false;

  Future<void> _check() async {
    setState(() => _busy = true);
    try {
      final r = await ref.read(authControllerProvider.notifier).refreshProfile();
      if (!mounted) return;
      final msg = switch (r) {
        Ok(value: final p) when p.status != 'VERIFIED' => 'Your account is still suspended.',
        Ok() => null,
        Failure(message: final m) => m,
      };
      if (msg != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e, st) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: e,
        stack: st,
        library: 'fixcare onboarding',
        context: ErrorDescription('re-checking a suspended account'),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(authControllerProvider).value;
    final reason = s is SessionAuthenticated ? s.profile.reviewNote : null;
    return Scaffold(
      key: const Key('suspendedScreen'),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _check,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 24),
              const Icon(Icons.block, size: 48, color: FixCareColors.primary),
              const SizedBox(height: 20),
              Text('Account suspended', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
              if (reason case final r? when r.trim().isNotEmpty)
                Container(
                  key: const Key('suspensionReason'),
                  margin: const EdgeInsets.only(top: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: FixCareColors.errorFill,
                    border: Border.all(color: FixCareColors.errorBorder),
                    borderRadius: BorderRadius.circular(FixCareRadii.card),
                  ),
                  child: Text(r, style: const TextStyle(color: FixCareColors.errorText, height: 1.4)),
                ),
              const SizedBox(height: 16),
              const Text(
                'Contact FixCare support',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14.5, color: FixCareColors.textMuted),
              ),
              const SizedBox(height: 28),
              FilledButton(key: const Key('checkAgainBtn'), onPressed: _busy ? null : _check, child: const Text('Check again')),
              const SizedBox(height: 8),
              TextButton(
                key: const Key('logoutBtn'),
                onPressed: () => ref.read(authControllerProvider.notifier).logout(),
                child: const Text('Log out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Run tests + analyze**

Run: `flutter test test/onboarding` → PASS; `flutter test` → green; `flutter analyze` → 0 issues.

- [ ] **Step 7: Commit**

```bash
git add apps/technician/lib/features/onboarding apps/technician/test/onboarding
git commit -m "feat(technician): under-review screen that re-checks status + suspended screen"
```

---

### Task 11: `HomeGate` + router — wire the screens, eject unverified technicians from job routes

**Files:**
- Create: `apps/technician/lib/features/onboarding/presentation/home_gate.dart`
- Modify: `apps/technician/lib/core/router/app_router.dart`
- Delete: `apps/technician/lib/features/jobs/presentation/verification_pending_screen.dart`
- Test: `apps/technician/test/router/token_gate_test.dart` (update + extend)

**Interfaces:**
- Consumes: Tasks 9–10 screens; Task 8 `refreshProfile()`.
- Produces: `HomeGate` — watches the session: not hydrated → `profileLoadError` screen with `retryProfileBtn`; PENDING → `OnboardingScreen`; KYC_SUBMITTED → `UnderReviewScreen`; VERIFIED → `JobsHomeScreen`; anything else → `SuspendedScreen`. Router: an authenticated, non-VERIFIED session on `/job/*` is redirected to `/home`.

- [ ] **Step 1: Update + write the failing tests** — in `test/router/token_gate_test.dart`:

Add a fake catalog (the onboarding screen loads zones) and let the fake profile repo simulate a failed fetch (add `import 'package:fixcare_technician/features/jobs/data/catalog_repository.dart';`):

```dart
class _FakeCatalog extends CatalogRepository {
  _FakeCatalog() : super(Dio());
  @override
  Future<Result<List<ZoneRefDto>>> zones() async => const Ok([ZoneRefDto(id: 'z1', name: 'Padra')]);
}

/// Fake profile repo per test: the boot hydration reads getProfile() to resolve the session's
/// TechnicianStatus. A null status simulates a failed (network) fetch → an unhydrated session.
class _FakeProfileRepo extends TechnicianProfileRepository {
  _FakeProfileRepo(this._status) : super(Dio());
  final String? _status;
  @override
  Future<Result<TechnicianProfileDto>> getProfile() async => switch (_status) {
        final String status => Ok(TechnicianProfileDto(id: 't1', role: 'TECHNICIAN', name: 'Ramesh', skills: const ['FAN'], status: status)),
        null => const Failure(FailureKind.network, 'down'),
      };
}
```

and change `pumpApp` to:

```dart
  Future<GoRouter> pumpApp(WidgetTester tester, {String? status, bool profileFails = false}) async {
    late GoRouter router;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (status != null || profileFails)
            technicianProfileRepositoryProvider.overrideWithValue(_FakeProfileRepo(profileFails ? null : status)),
          catalogRepositoryProvider.overrideWithValue(_FakeCatalog()),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            router = ref.watch(goRouterProvider);
            return MaterialApp.router(routerConfig: router);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }
```

Replace the PENDING and SUSPENDED tests and add:

```dart
  testWidgets('PENDING → onboarding form', (tester) async {
    backing['fixcare.access'] = 'a-token'; backing['fixcare.refresh'] = 'r-token';
    final router = await pumpApp(tester, status: 'PENDING');
    expect(router.routerDelegate.currentConfiguration.uri.path, '/home');
    expect(find.byKey(const Key('onboardingScreen')), findsOneWidget);
  });

  testWidgets('KYC_SUBMITTED → under review', (tester) async {
    backing['fixcare.access'] = 'a-token'; backing['fixcare.refresh'] = 'r-token';
    await pumpApp(tester, status: 'KYC_SUBMITTED');
    expect(find.byKey(const Key('underReviewScreen')), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // dispose the poll timer
  });

  testWidgets('SUSPENDED and DEACTIVATED → suspended screen', (tester) async {
    for (final status in ['SUSPENDED', 'DEACTIVATED']) {
      backing['fixcare.access'] = 'a-token'; backing['fixcare.refresh'] = 'r-token';
      await pumpApp(tester, status: status);
      expect(find.byKey(const Key('suspendedScreen')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('VERIFIED → jobs home', (tester) async {
    backing['fixcare.access'] = 'a-token'; backing['fixcare.refresh'] = 'r-token';
    await pumpApp(tester, status: 'VERIFIED');
    expect(find.byKey(const Key('jobsHomeScreen')), findsOneWidget);
  });

  testWidgets('profile could not load → "Couldn\'t load your profile" + Retry, never a blank form', (tester) async {
    backing['fixcare.access'] = 'a-token'; backing['fixcare.refresh'] = 'r-token';
    await pumpApp(tester, profileFails: true);
    expect(find.byKey(const Key('profileLoadError')), findsOneWidget);
    expect(find.text("Couldn't load your profile"), findsOneWidget);
    expect(find.byKey(const Key('onboardingScreen')), findsNothing);
    await tester.tap(find.byKey(const Key('retryProfileBtn')));
    await tester.pumpAndSettle();
    expect(find.text('down'), findsOneWidget); // the failure is shown, not swallowed
  });

  testWidgets('a non-verified technician on a job route is sent home', (tester) async {
    backing['fixcare.access'] = 'a-token'; backing['fixcare.refresh'] = 'r-token';
    final router = await pumpApp(tester, status: 'SUSPENDED');
    router.go('/job/b1');
    await tester.pumpAndSettle();
    expect(router.routerDelegate.currentConfiguration.uri.path, '/home');
    expect(find.byKey(const Key('suspendedScreen')), findsOneWidget);
  });
```

Delete the old `'token + VERIFIED session → reaches /home …'` test (the new VERIFIED test supersedes it, and its comment about a placeholder is stale). The jobs home renders with the default repositories in tests today (the old VERIFIED test already did), so it needs no override.

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/router/token_gate_test.dart`
Expected: FAIL — PENDING shows the old pending screen, no `profileLoadError`, job route not redirected.

- [ ] **Step 3: HomeGate** — `lib/features/onboarding/presentation/home_gate.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result.dart';
import '../../../core/theme.dart';
import '../../auth/domain/session.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../jobs/presentation/jobs_home_screen.dart';
import 'onboarding_screen.dart';
import 'suspended_screen.dart';
import 'under_review_screen.dart';

/// `/home`: picks the screen from the technician's status, and WATCHES the session so a status change
/// made by ops (verified, sent back, suspended, reinstated) swaps the screen without a re-login.
class HomeGate extends ConsumerWidget {
  const HomeGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(authControllerProvider).value;
    if (s is! SessionAuthenticated) return const SizedBox.shrink(); // the router redirects away
    if (!s.hydrated) return const _ProfileLoadError();
    return switch (s.status) {
      'VERIFIED' => const JobsHomeScreen(),
      'PENDING' => const OnboardingScreen(),
      'KYC_SUBMITTED' => const UnderReviewScreen(),
      // SUSPENDED, DEACTIVATED, or a status this build doesn't know: blocked — never the jobs screen.
      _ => const SuspendedScreen(),
    };
  }
}

/// Signed in, but the profile fetch failed (network). Never show a blank onboarding form for an
/// unknown status — offer a retry instead.
class _ProfileLoadError extends ConsumerStatefulWidget {
  const _ProfileLoadError();

  @override
  ConsumerState<_ProfileLoadError> createState() => _ProfileLoadErrorState();
}

class _ProfileLoadErrorState extends ConsumerState<_ProfileLoadError> {
  bool _busy = false;

  Future<void> _retry() async {
    setState(() => _busy = true);
    try {
      final r = await ref.read(authControllerProvider.notifier).refreshProfile();
      if (!mounted) return;
      if (r case Failure(:final message)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e, st) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: e,
        stack: st,
        library: 'fixcare onboarding',
        context: ErrorDescription('retrying the profile load'),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('profileLoadError'),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 48, color: FixCareColors.primary),
                const SizedBox(height: 20),
                Text("Couldn't load your profile", textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 24),
                FilledButton(key: const Key('retryProfileBtn'), onPressed: _busy ? null : _retry, child: const Text('Retry')),
                const SizedBox(height: 8),
                TextButton(
                  key: const Key('logoutBtn'),
                  onPressed: () => ref.read(authControllerProvider.notifier).logout(),
                  child: const Text('Log out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Router** — in `app_router.dart`: replace the `jobs_home_screen.dart` and `verification_pending_screen.dart` imports with `import '../../features/onboarding/presentation/home_gate.dart';`; change the `SessionAuthenticated()` case to:

```dart
        case SessionAuthenticated():
          // Keep them out of splash/auth screens; /home itself (HomeGate) decides what to render.
          if (loc == '/splash' || onAuthScreen) return '/home';
          // Not VERIFIED (e.g. suspended mid-session): job screens are off-limits — the gate shows why.
          if (!session.isVerified && loc.startsWith('/job/')) return '/home';
          return null;
```

and the `/home` route to `GoRoute(path: '/home', builder: (_, _) => const HomeGate()),`. Delete `lib/features/jobs/presentation/verification_pending_screen.dart` (`git rm`). Run `grep -rn "verification_pending_screen\|VerificationPendingScreen" apps/technician/lib apps/technician/test` → no hits.

- [ ] **Step 5: Run tests + analyze**

Run: `flutter test` → green; `flutter analyze` → 0 issues.

- [ ] **Step 6: Commit**

```bash
git add apps/technician/lib/features/onboarding/presentation/home_gate.dart apps/technician/lib/core/router/app_router.dart apps/technician/test/router/token_gate_test.dart
git rm apps/technician/lib/features/jobs/presentation/verification_pending_screen.dart
git commit -m "feat(technician): home gate picks onboarding / under review / suspended / jobs from live status"
```

---

### Task 12: OTP screen shows the role-mismatch message (both apps)

**Files:**
- Modify: `apps/technician/lib/features/auth/presentation/otp_entry_screen.dart`
- Test: `apps/technician/test/auth/otp_role_mismatch_test.dart`
- Modify: `apps/customer/lib/core/result.dart`, `apps/customer/lib/features/auth/data/auth_repository.dart`, `apps/customer/lib/features/auth/presentation/auth_controller.dart`, `apps/customer/lib/features/auth/presentation/otp_entry_screen.dart`
- Test: `apps/customer/test/auth/otp_role_mismatch_test.dart`

**Interfaces:**
- Consumes: backend 409 `{code: 'ROLE_MISMATCH', message}` (Task 6).
- Produces: customer `Failure` gains an optional `String? code` and `errorCodeOf(dynamic data)` (same as the technician app); both OTP screens show the server message (key `otpErrorText`) when `code == 'ROLE_MISMATCH'`, otherwise the existing `That code isn't right.`.

- [ ] **Step 1: Write the failing tests**

`apps/technician/test/auth/otp_role_mismatch_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/features/auth/domain/session.dart';
import 'package:fixcare_technician/features/auth/presentation/auth_controller.dart';
import 'package:fixcare_technician/features/auth/presentation/otp_entry_screen.dart';
import 'package:fixcare_technician/features/auth/presentation/phone_entry_screen.dart';

const _mismatch = 'This number is registered as a customer. Please use the FixCare customer app.';

class _FakeAuth extends AuthController {
  _FakeAuth(this.result);
  final Result<void> result;
  @override
  Future<Session> build() async => const SessionUnauthenticated();
  @override
  Future<Result<void>> submitOtp(String phone, String code) async => result;
}

void main() {
  Future<void> pumpAndVerify(WidgetTester tester, Result<void> result) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [authControllerProvider.overrideWith(() => _FakeAuth(result))],
      child: const MaterialApp(home: OtpEntryScreen(args: OtpArgs('9800000011', null))),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('otpField')), '123456');
    await tester.tap(find.byKey(const Key('verifyBtn')));
    await tester.pumpAndSettle();
  }

  testWidgets('ROLE_MISMATCH → the server message, wrapped (no overflow at 320 px)', (tester) async {
    await pumpAndVerify(tester, const Failure(FailureKind.unknown, _mismatch, code: 'ROLE_MISMATCH'));
    expect(find.text(_mismatch), findsOneWidget);
    expect(find.text("That code isn't right."), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wrong code still reads "That code isn\'t right."', (tester) async {
    await pumpAndVerify(tester, const Failure(FailureKind.unauthorized, 'Invalid or expired OTP', code: 'UNAUTHORIZED'));
    expect(find.text("That code isn't right."), findsOneWidget);
  });
}
```

`apps/customer/test/auth/otp_role_mismatch_test.dart` (the customer screen uses the same `otpField` / `verifyBtn` keys):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fixcare_customer/core/result.dart';
import 'package:fixcare_customer/features/auth/domain/session.dart';
import 'package:fixcare_customer/features/auth/presentation/auth_controller.dart';
import 'package:fixcare_customer/features/auth/presentation/otp_entry_screen.dart';
import 'package:fixcare_customer/features/auth/presentation/phone_entry_screen.dart';

const _mismatch = 'This number is registered as a FixCare technician. Please use the FixCare Pro app.';

class _FakeAuth extends AuthController {
  _FakeAuth(this.result);
  final Result<void> result;
  @override
  Future<Session> build() async => const SessionUnauthenticated();
  @override
  Future<Result<void>> submitOtp(String phone, String code) async => result;
}

void main() {
  Future<void> pumpAndVerify(WidgetTester tester, Result<void> result) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [authControllerProvider.overrideWith(() => _FakeAuth(result))],
      child: const MaterialApp(home: OtpEntryScreen(args: OtpArgs('9800000011', null))),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('otpField')), '123456');
    await tester.tap(find.byKey(const Key('verifyBtn')));
    await tester.pumpAndSettle();
  }

  testWidgets('ROLE_MISMATCH → the server message, wrapped (no overflow at 320 px)', (tester) async {
    await pumpAndVerify(tester, const Failure(FailureKind.unknown, _mismatch, code: 'ROLE_MISMATCH'));
    expect(find.text(_mismatch), findsOneWidget);
    expect(find.text("That code isn't right."), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wrong code still reads "That code isn\'t right."', (tester) async {
    await pumpAndVerify(tester, const Failure(FailureKind.unauthorized, 'Invalid or expired OTP'));
    expect(find.text("That code isn't right."), findsOneWidget);
  });
}
```

If the customer `AuthController.build()` signature or `Session` import path differs from the above, match the customer app's actual names (`apps/customer/lib/features/auth/presentation/auth_controller.dart`, `apps/customer/lib/features/auth/domain/session.dart`) — do not change the app code to fit the test.

- [ ] **Step 2: Run to verify they fail**

Run: `cd apps/technician && flutter test test/auth/otp_role_mismatch_test.dart` and `cd apps/customer && flutter test test/auth/otp_role_mismatch_test.dart`
Expected: FAIL — `That code isn't right.` shown; customer `Failure` has no `code` (compile error).

- [ ] **Step 3: Customer plumbing**

`apps/customer/lib/core/result.dart` — `Failure` gains the optional code and the helper (mirroring the technician app):

```dart
class Failure<T> extends Result<T> {
  final FailureKind kind;
  final String message;

  /// The backend's stable machine code from its `{code, message}` error envelope (e.g. `ROLE_MISMATCH`) —
  /// callers branch on this, never on [message]. Null when the response carried none.
  final String? code;
  const Failure(this.kind, this.message, {this.code});
}

/// The `code` of the backend's `{code, message}` error envelope, or null when absent.
String? errorCodeOf(dynamic data) => (data is Map && data['code'] is String) ? data['code'] as String : null;
```

`apps/customer/lib/features/auth/data/auth_repository.dart` — in `_post`, pass `code: errorCodeOf(res.data)` (line ~33) and `code: errorCodeOf(e.response!.data)` (line ~36) to the two status-derived `Failure`s.

`apps/customer/lib/features/auth/presentation/auth_controller.dart` — `submitOtp`'s last line becomes `return Failure(f.kind, f.message, code: f.code);`.

- [ ] **Step 4: Both OTP screens** — in each `otp_entry_screen.dart`:

Add `String? _errorMessage;` next to `bool _error = false;`. In the controller listener, clear it with the flag: `if (_error) { _error = false; _errorMessage = null; }`. In `_verify`'s switch, replace the two Failure branches with:

```dart
      case Failure(:final code, :final message):
        setState(() {
          _error = true;
          // The number belongs to the other app — say so; every other failure keeps the code-error copy.
          _errorMessage = code == 'ROLE_MISMATCH' ? message : null;
        });
```

and in the error row replace the `const Row(...)` with (no `const`; the text can be long, so it wraps):

```dart
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline, size: 16, color: FixCareColors.errorText),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _errorMessage ?? "That code isn't right.",
                        key: const Key('otpErrorText'),
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: FixCareColors.errorText),
                      ),
                    ),
                  ],
                ),
```

Also reset `_errorMessage = null` wherever the screen already resets `_error = false` (start of `_verify`, `_resend`).

- [ ] **Step 5: Run tests + analyze (both apps)**

Run: `cd apps/technician && flutter test && flutter analyze` and `cd apps/customer && flutter test && flutter analyze` → all green, 0 issues.

- [ ] **Step 6: Commit**

```bash
git add apps/technician/lib/features/auth/presentation/otp_entry_screen.dart apps/technician/test/auth/otp_role_mismatch_test.dart apps/customer/lib/core/result.dart apps/customer/lib/features/auth apps/customer/test/auth/otp_role_mismatch_test.dart
git commit -m "feat(apps): OTP screen explains a number registered to the other app"
```

---

### Task 13: Docs — ops runbook, STATUS, CHANGELOG

**Files:**
- Create: `docs/06-operations/technician-review-runbook.md`
- Modify: `docs/06-operations/README.md` (index line), `STATUS.md`, `CHANGELOG.md`

- [ ] **Step 1: Runbook** — `docs/06-operations/technician-review-runbook.md`, covering, with copy-pasteable curl (Bruno equivalent noted) against `$BASE` with a MANAGER admin token `$ADMIN` (obtained via `POST /auth/admin/login`):
  - the review queue: `curl -s "$BASE/admin/technicians?status=KYC_SUBMITTED" -H "authorization: Bearer $ADMIN"`;
  - verify / send back / suspend / reinstate (`POST /admin/technicians/<id>/verify`, `/send-back` + `{"reason":"…"}`, `/suspend` + `{"reason":"…"}`, `/reinstate`), each with the 409 it can return and what it means (`INVALID_TECHNICIAN_TRANSITION`, `TECHNICIAN_HAS_ACTIVE_JOB`);
  - editing skills / zones: `PATCH /admin/technicians/<id>` with `{"skills":[…]}` and/or `{"zoneIds":[…]}` (zone ids from `GET /catalog/zones`); note a VERIFIED technician with no zones sees no jobs;
  - the in-person check ops does before verifying (identity seen, skills confirmed) — and that NO document images or Aadhaar numbers are collected or typed into a reason (Golden Rules 6–7: reasons are shown to the technician and stored in the audit log);
  - the lifecycle table from the spec.
- [ ] **Step 2: README index** — add one line for the runbook in `docs/06-operations/README.md` in the existing list style.
- [ ] **Step 3: STATUS.md** — mark job estimate integrity (#38) shipped; set Active to "Technician app Slice 3 — onboarding + verification (branch `feature/technician-app-slice3-onboarding`)"; remove the deferred "Technician auth" bullets (a) and (b) (both fixed here); add the slice's tracked out-of-scope items (spec "Out of scope") and the known suspend/accept race (Task 4 ruling); keep "next 3" current.
- [ ] **Step 4: CHANGELOG.md** — one dated entry (2026-10-02) summarizing: technician lifecycle + `TechnicianZone` migration, ops review endpoints, in-zone dispatch, `ROLE_MISMATCH`, app onboarding / under review / suspended screens with live status.
- [ ] **Step 5: Commit**

```bash
git add docs/06-operations/technician-review-runbook.md docs/06-operations/README.md STATUS.md CHANGELOG.md
git commit -m "docs: technician review runbook; STATUS + CHANGELOG for Slice 3"
```

---

## Final verification (after all tasks)

- `cd apps/backend && set -a && source .env && set +a && pnpm vitest run && pnpm build` → green.
- `DATABASE_URL="$TEST_DATABASE_URL" pnpm prisma migrate status` → "Database schema is up to date".
- `cd apps/technician && flutter test && flutter analyze` and `cd apps/customer && flutter test && flutter analyze` → green, 0 issues.
- `git status --short` shows only the founder-owned iOS leftovers as unstaged.
