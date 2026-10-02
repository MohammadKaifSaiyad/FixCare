# Job Estimate Integrity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A customer can only approve a complete, frozen estimate — the technician builds the parts cart during diagnosis (ARRIVED), "Submit diagnosis" sends and freezes it, and the technician app reads the real cart from a new single-job GET.

**Architecture:** Backend moves part add/remove from DIAGNOSED to ARRIVED (no new state, no migration), snapshots the cart into the diagnose transition evidence, filters catalog parts as category-or-generic, and adds `GET /technician/jobs/:id` returning the job + `parts[]` (+ `service.categoryId` on every technician job DTO). The technician app polls that single endpoint, renders the cart from the server inside the diagnosis form, and shows a read-only "estimate sent" card at DIAGNOSED. The customer app is unchanged.

**Tech Stack:** Backend — Node 22, Fastify 5, TypeScript strict, Prisma 6 / Postgres 16, Zod, vitest (real DB). Technician app — Flutter 3 / Dart 3, Riverpod 3 (`@riverpod` codegen), freezed 4 + json_serializable, dio 5, http_mock_adapter, flutter_test.

**Spec:** `docs/designs/2026-10-01-job-estimate-integrity-design.md`

## Global Constraints

- Branch `feature/job-estimate-integrity`; run `git branch --show-current` before every commit; never commit to `main`.
- Commit author `MohammadKaifSaiyad <saiyedkgn6@gmail.com>` (`git -c user.name=MohammadKaifSaiyad -c user.email=saiyedkgn6@gmail.com commit …`); NO Co-Authored-By / Claude trailer.
- NEVER stage `apps/customer/ios/*`, `apps/customer/ios/Podfile.lock`, or any `xcshareddata/swiftpm/` folder (pre-existing, founder-owned). Stage files by explicit path.
- Golden Rule 4 — catalog prices only: the technician never sends a price; cart lines carry the backend's snapshot `ceilingPricePaise`.
- Money is integer paise everywhere; only `rupees()` (`apps/technician/lib/core/format.dart`) formats for display.
- Golden Rule 7 — no PII in logs: no `print`/`debugPrint`/`console.log`; never log phone, address, codes, keys, signed URLs.
- Backend: auth first, Zod at the boundary (body AND params for the new route), ownership verified, DB writes in the service layer, no cross-module DB queries, TS strict, no `any`; errors via `src/shared/errors.ts` classes (envelope `{code, message}`).
- Technician app: Riverpod + repositories only (UI never touches dio); never set a global dio content-type (bodyless GET); busy flags reset in try/finally; `if (!mounted) return;` after every await before touching `context`/`setState`; Failure messages shown verbatim; no `dynamic` misuse.
- Exact copy strings (use verbatim):
  - backend 409: `The cart is locked — the diagnosis has been submitted`
  - backend 409 before arrival: `Job is not in ARRIVED`
  - app vanished: `This job is no longer assigned to you.`
  - app estimate label: `Customer will see: ` + `rupees(...)`
  - app confirm dialog body: `Send this estimate to the customer? You won't be able to change parts after this.`
  - app DIAGNOSED card heading: `Estimate sent — waiting for the customer to approve or decline`
- Backend tests need the local Docker stack (Postgres + Redis) — it is RUNNING; do not start, stop, or restart containers. Command: `cd apps/backend && set -a && source .env && set +a && pnpm vitest run <file>`; full suite `pnpm vitest run`; build `pnpm build`.
- App tests: `cd apps/technician && flutter test <file>`; full `flutter test`; `flutter analyze` must report 0 issues. After editing a `@freezed`/`@riverpod` file run `dart run build_runner build --delete-conflicting-outputs` and commit the regenerated files (generated files are tracked).

## Review Focus

1. **A part add whose response is lost but which the backend applied** (timeout / network error) → the screen must still converge to the server's cart (no ghost, no duplicate on re-add). Pinned in Task 6: every add/remove outcome — Ok, Failure, or throw — refetches the job.
2. **"Submit diagnosis" tapped while a cart edit is still in flight** → the estimate sent could differ from the one on screen. Pinned in Task 7: Submit is disabled while any part add/remove is pending.
3. **A job whose `service.categoryId` is absent (older backend)** → pickers must fall back to unfiltered lists, not crash or show nothing. Pinned in Tasks 6 + 7: `categoryId == null` calls `parts()` / `issues()` with no filter.
4. **Visit fee larger than labor + parts** → "Customer will see" and the DIAGNOSED total show ₹0, never a negative number, and both use the same function. Pinned in Task 6.
5. **Job reassigned mid-diagnosis** → the single GET answers 403; part edits answer 403 → the screen moves to "This job is no longer assigned to you." instead of looping errors. Pinned in Task 5 (controller) and Task 6 (add 403 → SnackBar + refetch).

---

## File map

**Backend (`apps/backend`)**
- Modify `src/modules/technician-jobs/technician-jobs.service.ts` — cart open only in ARRIVED (`ownOpenCartBookingOrThrow`, `assertCartStillOpen`, `CART_LOCKED_MESSAGE`), diagnose cart snapshot, new `getMyJob`, `toTechnicianJobDto` call sites pass `service`.
- Modify `src/modules/technician-jobs/technician-jobs.types.ts` — `service.categoryId`, `TechnicianJobPartLine`, `TechnicianJobDetailDto`, `toTechnicianJobDetailDto`.
- Modify `src/modules/technician-jobs/technician-jobs.schemas.ts` — `jobIdParams`.
- Modify `src/modules/technician-jobs/technician-jobs.routes.ts` — `GET /technician/jobs/:id`.
- Modify `src/modules/catalog/catalog.service.ts` — `listParts` category-or-generic.
- Modify `src/modules/bookings/bookings.service.ts` — one comment in `approveDiagnosis`.
- Tests: modify `tests/bookings/diagnosis.test.ts`, `tests/catalog/parts.test.ts`; create `tests/technician-jobs/job-detail.test.ts`. (`tests/technician-jobs/repair-path.test.ts` seeds its cart line directly in SQL — unaffected.)

**Technician app (`apps/technician`)**
- Modify `lib/core/result.dart` — `FailureKind.forbidden` (403), `FailureKind.notFound` (404).
- Modify `lib/features/jobs/presentation/photo_capture.dart` — classify the two new kinds as terminal.
- Modify `lib/features/jobs/data/technician_job_dto.dart` — `JobServiceDto.categoryId`, `JobPartLineDto`, `TechnicianJobDetailDto`.
- Modify `lib/features/jobs/data/technician_job_repository.dart` — `job(id)`.
- Modify `lib/features/jobs/presentation/job_detail_controller.dart` — poll `job(id)`, state `TechnicianJobDetailDto`, 403/404 → vanished.
- Modify `lib/features/jobs/presentation/job_detail_screen.dart` — consume the detail DTO; DIAGNOSED → `EstimateSentCard`; ARRIVED → `DiagnosisForm(detail:)`.
- Rewrite `lib/features/jobs/presentation/parts_cart.dart` — `estimatePaise`, `partsCatalogProvider`, `PartsSection`, `EstimateSentCard`; delete `parts_cart.g.dart`.
- Modify `lib/features/jobs/presentation/diagnosis_form.dart` — takes `detail`, category-filtered issues, embeds `PartsSection`, confirm dialog, Submit blocked while the cart is busy.
- Tests: create `test/core/result_test.dart`; modify `test/jobs/technician_job_repository_test.dart`, `test/jobs/photo_upload_queue_test.dart`, `test/jobs/job_detail_controller_test.dart`, `test/jobs/job_detail_screen_test.dart`, `test/jobs/diagnosis_form_test.dart`, `test/jobs/repair_photos_card_test.dart` (only if it fakes `mine()` for the controller); rewrite `test/jobs/parts_cart_test.dart`.

**Docs:** `docs/designs/2026-06-14-booking-b4a-diagnosis-design.md` (note), `STATUS.md`, `CHANGELOG.md`.

---

### Task 1: Backend — the cart is open only while diagnosing (ARRIVED), frozen at diagnose

**Files:**
- Modify: `apps/backend/src/modules/technician-jobs/technician-jobs.service.ts` (imports; `addPart` ~line 175; `assertStillDiagnosed` ~line 211; `removePart` ~line 215; `diagnoseJob` ~line 142; near `ownAssignedBookingOrThrow` ~line 101)
- Modify: `apps/backend/src/modules/bookings/bookings.service.ts` (`approveDiagnosis` comment ~line 221)
- Test: `apps/backend/tests/bookings/diagnosis.test.ts`

**Interfaces:**
- Consumes: `sumParts(parts: {ceilingPricePaise:number; qty:number}[]): number` from `src/modules/bookings/estimate.ts`; `transitionBooking(tx, booking, to, actor, evidence?)` (evidence lands in the `BOOKING_STATE_CHANGED` audit row's `metadata`).
- Produces: `export const CART_LOCKED_MESSAGE = 'The cart is locked — the diagnosis has been submitted'`; `POST/DELETE /technician/jobs/:id/parts…` valid only in ARRIVED; diagnose evidence keys `partCount`, `partsTotalPaise`.

- [ ] **Step 1: Update the existing cart tests + add the new ones (failing first)** — in `tests/bookings/diagnosis.test.ts`, inside `describe('diagnose + parts cart', …)`:

  - In `'add a part snapshots the ceiling price…'`, `'qty < 1 → 400…'`, and `'a part from a different category → 422…'`: DELETE the line that POSTs `/diagnose` before the parts calls (parts are now added in ARRIVED). In the first test change the destructuring to `const { t, bookingId, part } = await arrivedBooking();`; in the category test to `const { t, bookingId } = await arrivedBooking();`; in the qty test to `const { t, bookingId, part } = await arrivedBooking();`.
  - Replace the whole `'add/remove only while DIAGNOSED; remove works + writes audit'` test with:

```ts
  it('add/remove work while ARRIVED; remove works + writes audit', async () => {
    const { t, bookingId, part } = await arrivedBooking();
    const line = (await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts`, headers: auth(t.token), payload: { partsCatalogId: part.id, qty: 1 } })).json();
    expect((await app.inject({ method: 'DELETE', url: `/technician/jobs/${bookingId}/parts/${line.id}`, headers: auth(t.token) })).statusCode).toBe(204);
    expect(await prisma.bookingPart.count({ where: { bookingId } })).toBe(0);
    const audits = await prisma.auditLog.findMany({ where: { action: 'DIAGNOSIS_UPDATED' } });
    expect(audits.length).toBeGreaterThanOrEqual(2); // part_added + part_removed
  });

  it('after diagnose the cart is locked: add and remove → 409 with the locked message', async () => {
    const { t, bookingId, issue, part } = await arrivedBooking();
    const line = (await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts`, headers: auth(t.token), payload: { partsCatalogId: part.id, qty: 1 } })).json();
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id } })).statusCode).toBe(200);
    const add = await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts`, headers: auth(t.token), payload: { partsCatalogId: part.id, qty: 1 } });
    expect(add.statusCode).toBe(409);
    expect(add.json().message).toBe('The cart is locked — the diagnosis has been submitted');
    const del = await app.inject({ method: 'DELETE', url: `/technician/jobs/${bookingId}/parts/${line.id}`, headers: auth(t.token) });
    expect(del.statusCode).toBe(409);
    expect(del.json().message).toBe('The cart is locked — the diagnosis has been submitted');
    expect(await prisma.bookingPart.count({ where: { bookingId } })).toBe(1);
  });

  it('before arrival the cart is not open: add while EN_ROUTE → 409 "Job is not in ARRIVED"', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const t = await makeTechnician(['AC']);
    const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
    await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(t.token) });
    await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/en-route`, headers: auth(t.token) });
    const part = await prisma.partsCatalog.create({ data: { sku: `P-${Math.random().toString(36).slice(2, 8)}`, name: 'Capacitor', ceilingPricePaise: 50000, categoryId: f.cat.id } });
    const res = await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/parts`, headers: auth(t.token), payload: { partsCatalogId: part.id, qty: 1 } });
    expect(res.statusCode).toBe(409);
    expect(res.json().message).toBe('Job is not in ARRIVED');
  });

  it('diagnose records the cart it sent (partCount + partsTotalPaise) in the transition evidence', async () => {
    const { t, bookingId, issue, part } = await arrivedBooking(); // part = 50000 paise
    await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts`, headers: auth(t.token), payload: { partsCatalogId: part.id, qty: 2 } });
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id } })).statusCode).toBe(200);
    const rows = await prisma.auditLog.findMany({ where: { action: 'BOOKING_STATE_CHANGED' } });
    const toDiagnosed = rows.map((r) => r.metadata as Record<string, unknown>).find((m) => m.bookingId === bookingId && m.to === 'DIAGNOSED');
    expect(toDiagnosed).toMatchObject({ partCount: 1, partsTotalPaise: 100000 });
  });

  it('an empty cart is a valid labor-only estimate (partCount 0, partsTotalPaise 0)', async () => {
    const { t, bookingId, issue } = await arrivedBooking();
    expect((await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/diagnose`, headers: auth(t.token), payload: { diagnosedIssueId: issue.id } })).statusCode).toBe(200);
    const rows = await prisma.auditLog.findMany({ where: { action: 'BOOKING_STATE_CHANGED' } });
    const toDiagnosed = rows.map((r) => r.metadata as Record<string, unknown>).find((m) => m.bookingId === bookingId && m.to === 'DIAGNOSED');
    expect(toDiagnosed).toMatchObject({ partCount: 0, partsTotalPaise: 0 });
  });
```

  - In `describe('approve / decline', …)`, replace `diagnosedWithPart` so the part is added BEFORE diagnose:

```ts
  async function diagnosedWithPart() {
    const a = await arrivedBooking();
    await app.inject({ method: 'POST', url: `/technician/jobs/${a.bookingId}/parts`, headers: auth(a.t.token), payload: { partsCatalogId: a.part.id, qty: 1 } });
    await app.inject({ method: 'POST', url: `/technician/jobs/${a.bookingId}/diagnose`, headers: auth(a.t.token), payload: { diagnosedIssueId: a.issue.id } });
    return a;
  }
```

- [ ] **Step 2: Run the file — confirm the new/changed tests fail for the right reason**

Run: `cd apps/backend && set -a && source .env && set +a && pnpm vitest run tests/bookings/diagnosis.test.ts`
Expected: FAIL — ARRIVED adds return 409 `Job is not in DIAGNOSED`; the evidence tests find no `partCount`.

- [ ] **Step 3: Implement** — in `technician-jobs.service.ts`:

  1. Change the estimate import to `import { computeEstimate, sumParts } from '../bookings/estimate.js';`.
  2. Directly below `ownAssignedBookingOrThrow`, add:

```ts
/** The cart is editable only while the technician is diagnosing (ARRIVED). "Submit diagnosis" sends the
 *  complete estimate and freezes it, so the customer can only ever approve a final cart (no instant
 *  labor-only approval, no bait-and-switch). */
export const CART_LOCKED_MESSAGE = 'The cart is locked — the diagnosis has been submitted';

/** Own + assigned + cart open. After diagnose (`diagnosedAt` set) the message says the cart is locked;
 *  before arrival it is the usual wrong-state 409. */
async function ownOpenCartBookingOrThrow(techId: string, bookingId: string) {
  const b = await prisma.booking.findFirst({ where: { id: bookingId, deletedAt: null }, include: { address: true, service: true } });
  if (!b) throw new NotFoundError('Job not found');
  if (b.technicianId !== techId) throw new ForbiddenError('This job is not assigned to you');
  if (b.state !== 'ARRIVED') throw new ConflictError(b.diagnosedAt ? CART_LOCKED_MESSAGE : 'Job is not in ARRIVED');
  return b;
}
```

  3. In `addPart`: replace `const booking = await ownAssignedBookingOrThrow(tech.id, bookingId, 'DIAGNOSED');` with `const booking = await ownOpenCartBookingOrThrow(tech.id, bookingId);` and `await assertStillDiagnosed(tx, bookingId);` with `await assertCartStillOpen(tx, bookingId);`. Update its in-tx comment to: `// Re-assert ARRIVED inside the tx (optimistic guard): if "Submit diagnosis" committed concurrently the cart is frozen, so this matches 0 rows → reject.`
  4. Replace `assertStillDiagnosed` (the function and its doc comment) with:

```ts
/** Cart freeze: a concurrent "Submit diagnosis" already moved the booking out of ARRIVED. */
async function assertCartStillOpen(tx: import('@prisma/client').Prisma.TransactionClient, bookingId: string): Promise<void> {
  await assertStillInState(tx, bookingId, 'ARRIVED', CART_LOCKED_MESSAGE);
}
```

  5. In `removePart`: replace `await ownAssignedBookingOrThrow(tech.id, bookingId, 'DIAGNOSED');` with `await ownOpenCartBookingOrThrow(tech.id, bookingId);` and `await assertStillDiagnosed(tx, bookingId);` with `await assertCartStillOpen(tx, bookingId);`.
  6. In `diagnoseJob`, inside the transaction, AFTER the photo-gate `if (!DIAGNOSIS_KINDS.every…) throw …` and BEFORE `transitionBooking(…)`, insert the cart read and pass it as evidence:

```ts
    // The cart IS the estimate the customer will approve — snapshot exactly what was sent. Read after the
    // booking-row lock above: a part add that committed first is included; one racing this tx is rejected
    // by assertCartStillOpen once the state leaves ARRIVED.
    const cart = await tx.bookingPart.findMany({ where: { bookingId }, select: { ceilingPricePaise: true, qty: true } });
    await transitionBooking(tx, booking, 'DIAGNOSED', { type: 'USER', kind: 'TECHNICIAN', id: userId }, { diagnosedIssueId: issue.id, photoIds: activePhotos.map((p) => p.id), partCount: cart.length, partsTotalPaise: sumParts(cart) });
```

  (Delete the old `transitionBooking(...)` line it replaces.) If the `'DIAGNOSED'` member of `assertStillInState`'s state union is now unused, leave the union as is (harmless).

  7. In `apps/backend/src/modules/bookings/bookings.service.ts` `approveDiagnosis`, replace the comment line `// (the transition makes DIAGNOSED-only add/remove illegal, so the cart cannot change after this).` with `// (the cart was frozen when the technician submitted the diagnosis — part edits are ARRIVED-only).`

- [ ] **Step 4: Run the file, then the full backend suite + build**

Run: `cd apps/backend && set -a && source .env && set +a && pnpm vitest run tests/bookings/diagnosis.test.ts && pnpm vitest run && pnpm build`
Expected: all PASS; tsc clean.

- [ ] **Step 5: Commit**

```bash
git add apps/backend/src/modules/technician-jobs/technician-jobs.service.ts apps/backend/src/modules/bookings/bookings.service.ts apps/backend/tests/bookings/diagnosis.test.ts
git -c user.name=MohammadKaifSaiyad -c user.email=saiyedkgn6@gmail.com commit -m "feat(backend): parts cart is built during diagnosis (ARRIVED) and frozen at diagnose; diagnose snapshots the cart"
```

---

### Task 2: Backend — catalog parts filter returns the category plus generic parts

**Files:**
- Modify: `apps/backend/src/modules/catalog/catalog.service.ts` (`listParts` ~line 111)
- Test: `apps/backend/tests/catalog/parts.test.ts` (`'filters by categoryId'` ~line 41)

**Interfaces:**
- Produces: `GET /catalog/parts?categoryId=X` → parts with `categoryId = X` OR `categoryId = null`; no `categoryId` → all active parts (unchanged).

- [ ] **Step 1: Replace the filter test (failing first)**

```ts
  it('filters by categoryId: that category + generic (null-category) parts; other categories excluded', async () => {
    const mgr = await makeAdminToken('MANAGER');
    const cat = (await app.inject({ method: 'POST', url: '/catalog/categories', headers: auth(mgr), payload: { name: 'AC' } })).json();
    const other = (await app.inject({ method: 'POST', url: '/catalog/categories', headers: auth(mgr), payload: { name: 'Fan' } })).json();
    await app.inject({ method: 'POST', url: '/catalog/parts', headers: auth(mgr), payload: { sku: 'IN-CAT', name: 'In cat', categoryId: cat.id, ceilingPricePaise: 100 } });
    await app.inject({ method: 'POST', url: '/catalog/parts', headers: auth(mgr), payload: { sku: 'NO-CAT', name: 'No cat', ceilingPricePaise: 200 } });
    await app.inject({ method: 'POST', url: '/catalog/parts', headers: auth(mgr), payload: { sku: 'OTHER-CAT', name: 'Other cat', categoryId: other.id, ceilingPricePaise: 300 } });
    const cust = await makeCustomerToken();
    const list = (await app.inject({ method: 'GET', url: `/catalog/parts?categoryId=${cat.id}`, headers: auth(cust) })).json();
    expect(list.map((p: { sku: string }) => p.sku).sort()).toEqual(['IN-CAT', 'NO-CAT']);
  });
```

- [ ] **Step 2: Run — expect FAIL** (`['IN-CAT']` only)

Run: `cd apps/backend && set -a && source .env && set +a && pnpm vitest run tests/catalog/parts.test.ts`

- [ ] **Step 3: Implement** — in `listParts` replace the `where` line with:

```ts
    // A category filter returns that category's parts PLUS generic ones (categoryId null): a generic part
    // applies to any job — the same rule the technician addPart category check enforces.
    where: { deletedAt: null, status: 'ACTIVE', ...(categoryId ? { OR: [{ categoryId }, { categoryId: null }] } : {}) },
```

- [ ] **Step 4: Run the file, the full suite, and the build**

Run: `cd apps/backend && set -a && source .env && set +a && pnpm vitest run tests/catalog/parts.test.ts && pnpm vitest run && pnpm build`
Expected: PASS; tsc clean.

- [ ] **Step 5: Commit**

```bash
git add apps/backend/src/modules/catalog/catalog.service.ts apps/backend/tests/catalog/parts.test.ts
git -c user.name=MohammadKaifSaiyad -c user.email=saiyedkgn6@gmail.com commit -m "feat(backend): catalog parts category filter includes generic parts"
```

---

### Task 3: Backend — `service.categoryId` on technician job DTOs + `GET /technician/jobs/:id`

**Files:**
- Modify: `apps/backend/src/modules/technician-jobs/technician-jobs.types.ts`
- Modify: `apps/backend/src/modules/technician-jobs/technician-jobs.service.ts` (3 `toTechnicianJobDto` call sites ~lines 39, 49, 84; new `getMyJob`)
- Modify: `apps/backend/src/modules/technician-jobs/technician-jobs.schemas.ts`
- Modify: `apps/backend/src/modules/technician-jobs/technician-jobs.routes.ts`
- Test: create `apps/backend/tests/technician-jobs/job-detail.test.ts`

**Interfaces:**
- Consumes: Prisma `Booking` relations `address`, `service` (has non-null `categoryId`), `customer.user`, `photos`, `bookingParts` (model `BookingPart {id, partsCatalogId, sku, name, ceilingPricePaise, qty, createdAt}`); `toPhotoSummaries` from `../bookings/bookings.types.js`.
- Produces:
  - `TechnicianJobDto.service = { name; requiredSkill; categoryId: string }` on available / mine / accept / detail.
  - `GET /technician/jobs/:id` → `TechnicianJobDetailDto` = `TechnicianJobDto & { parts: { id, partsCatalogId, sku, name, qty, ceilingPricePaise }[] }` (parts ordered by `createdAt` asc). Errors: not a TECHNICIAN role → 403 `Technician access required`; unverified → 403 `Verified technician required`; missing → 404 `Job not found`; foreign → 403 `This job is not assigned to you`; bad `:id` → 400.

- [ ] **Step 1: Write the failing tests** — create `tests/technician-jobs/job-detail.test.ts`:

```ts
import { afterAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../../src/app.js';
import { prisma, resetDb } from '../schema/helpers.js';
import { flushTestRedis } from '../helpers/redis.js';
import { makeCustomer, makeTechnician, seedBookable, seedDiagnosisPhotos } from '../bookings/helpers.js';

const app = await buildApp();
afterAll(() => app.close());
beforeEach(async () => { await resetDb(); await flushTestRedis(); });
function auth(t: string) { return { authorization: `Bearer ${t}` }; }
function future() { return new Date(Date.now() + 86_400_000).toISOString(); }

/** A booking driven to ARRIVED for a fresh AC technician, with both diagnosis photos seeded. */
async function arrivedJob() {
  const c = await makeCustomer();
  const f = await seedBookable(c.customerId);
  const t = await makeTechnician(['AC']);
  const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(t.token) });
  await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/en-route`, headers: auth(t.token) });
  const code = (await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/arrive`, headers: auth(t.token), payload: { lat: 22.31, lng: 73.18 } })).json().arrivalCode;
  await app.inject({ method: 'POST', url: `/me/bookings/${booking.id}/confirm-arrival`, headers: auth(c.token), payload: { code } });
  await seedDiagnosisPhotos(booking.id);
  return { c, f, t, bookingId: booking.id as string };
}

describe('GET /technician/jobs/:id', () => {
  it('assigned technician gets the job with parts[], service.categoryId and active photos (masked phone, no name)', async () => {
    const { f, t, bookingId } = await arrivedJob();
    const part = await prisma.partsCatalog.create({ data: { sku: 'CAP-1', name: 'Capacitor', ceilingPricePaise: 50000, categoryId: f.cat.id } });
    const line = (await app.inject({ method: 'POST', url: `/technician/jobs/${bookingId}/parts`, headers: auth(t.token), payload: { partsCatalogId: part.id, qty: 2 } })).json();
    const res = await app.inject({ method: 'GET', url: `/technician/jobs/${bookingId}`, headers: auth(t.token) });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.id).toBe(bookingId);
    expect(body.state).toBe('ARRIVED');
    expect(body.service.categoryId).toBe(f.cat.id);
    expect(body.parts).toEqual([{ id: line.id, partsCatalogId: part.id, sku: 'CAP-1', name: 'Capacitor', qty: 2, ceilingPricePaise: 50000 }]);
    expect(body.photos.map((p: { kind: string }) => p.kind).sort()).toEqual(['DIAGNOSIS_CLOSEUP', 'DIAGNOSIS_OVERVIEW']);
    expect(Object.keys(body.customer)).toEqual(['maskedPhone']);
  });

  it('another technician → 403; a customer → 403; an unverified technician → 403; a missing job → 404', async () => {
    const { c, bookingId } = await arrivedJob();
    const other = await makeTechnician(['AC']);
    expect((await app.inject({ method: 'GET', url: `/technician/jobs/${bookingId}`, headers: auth(other.token) })).statusCode).toBe(403);
    expect((await app.inject({ method: 'GET', url: `/technician/jobs/${bookingId}`, headers: auth(c.token) })).statusCode).toBe(403);
    const pending = await makeTechnician(['AC'], 'PENDING');
    expect((await app.inject({ method: 'GET', url: `/technician/jobs/${bookingId}`, headers: auth(pending.token) })).statusCode).toBe(403);
    const t2 = await makeTechnician(['AC']);
    const missing = await app.inject({ method: 'GET', url: '/technician/jobs/00000000-0000-0000-0000-000000000000', headers: auth(t2.token) });
    expect(missing.statusCode).toBe(404);
    expect(missing.json().message).toBe('Job not found');
  });

  it('static routes still win: /technician/jobs/available and /mine are not treated as an :id', async () => {
    const { t } = await arrivedJob();
    expect((await app.inject({ method: 'GET', url: '/technician/jobs/available', headers: auth(t.token) })).statusCode).toBe(200);
    expect((await app.inject({ method: 'GET', url: '/technician/jobs/mine', headers: auth(t.token) })).statusCode).toBe(200);
  });

  it('available and mine carry service.categoryId', async () => {
    const c = await makeCustomer();
    const f = await seedBookable(c.customerId);
    const t = await makeTechnician(['AC']);
    const booking = (await app.inject({ method: 'POST', url: '/me/bookings', headers: auth(c.token), payload: { addressId: f.address.id, serviceId: f.service.id, scheduledSlot: future() } })).json();
    const available = (await app.inject({ method: 'GET', url: '/technician/jobs/available', headers: auth(t.token) })).json();
    expect(available.find((j: { id: string }) => j.id === booking.id).service.categoryId).toBe(f.cat.id);
    await app.inject({ method: 'POST', url: `/technician/jobs/${booking.id}/accept`, headers: auth(t.token) });
    const mine = (await app.inject({ method: 'GET', url: '/technician/jobs/mine', headers: auth(t.token) })).json();
    expect(mine.find((j: { id: string }) => j.id === booking.id).service.categoryId).toBe(f.cat.id);
  });
});
```

- [ ] **Step 2: Run — expect FAIL** (404 route / missing `categoryId`)

Run: `cd apps/backend && set -a && source .env && set +a && pnpm vitest run tests/technician-jobs/job-detail.test.ts`

- [ ] **Step 3: Types** — in `technician-jobs.types.ts`:
  - Change the import to `import type { Booking, Address, ServiceSkill, BookingPart } from '@prisma/client';`.
  - In `TechnicianJobDto` change `service: { name: string; requiredSkill: ServiceSkill };` to `service: { name: string; requiredSkill: ServiceSkill; categoryId: string };`.
  - Change `toTechnicianJobDto`'s third parameter from `requiredSkill: ServiceSkill` to `service: { requiredSkill: ServiceSkill; categoryId: string }`, update its doc comment (`` `service` is the joined Service row (requiredSkill + categoryId) ``), and its body line to `service: { name: booking.serviceName, requiredSkill: service.requiredSkill, categoryId: service.categoryId },`.
  - Append:

```ts
/** One cart line as the technician sees it — the snapshot price, never a live catalog read. */
export interface TechnicianJobPartLine {
  id: string;
  partsCatalogId: string;
  sku: string;
  name: string;
  qty: number;
  ceilingPricePaise: number;
}

/** GET /technician/jobs/:id — the list DTO plus the job's parts cart (open while ARRIVED, frozen after). */
export interface TechnicianJobDetailDto extends TechnicianJobDto {
  parts: TechnicianJobPartLine[];
}

export function toTechnicianJobDetailDto(
  booking: Booking,
  address: Address,
  service: { requiredSkill: ServiceSkill; categoryId: string },
  customerPhone: string,
  photos: PhotoSummary[],
  parts: BookingPart[],
): TechnicianJobDetailDto {
  return {
    ...toTechnicianJobDto(booking, address, service, customerPhone, photos),
    parts: parts.map((p) => ({ id: p.id, partsCatalogId: p.partsCatalogId, sku: p.sku, name: p.name, qty: p.qty, ceilingPricePaise: p.ceilingPricePaise })),
  };
}
```

- [ ] **Step 4: Service** — in `technician-jobs.service.ts`:
  - Change the types import to `import { toTechnicianJobDto, toTechnicianJobDetailDto, type TechnicianJobDto, type TechnicianJobDetailDto } from './technician-jobs.types.js';`.
  - In the three existing calls replace the `x.service.requiredSkill` argument with `x.service` (`b.service` in `listAvailableJobs` and `listMyJobs`, `full.service` in `acceptJob`).
  - Add below `listMyJobs`:

```ts
/** One job, in full, for its assigned technician — the job-detail screen's poll target (one booking + its
 *  cart + its photos, instead of the whole history). Any state is readable while assigned. */
export async function getMyJob(userId: string, bookingId: string): Promise<TechnicianJobDetailDto> {
  const tech = await requireTechnician(userId);
  const b = await prisma.booking.findFirst({
    where: { id: bookingId, deletedAt: null },
    include: {
      address: true,
      service: true,
      customer: { include: { user: true } },
      photos: { where: { deletedAt: null } },
      bookingParts: { orderBy: { createdAt: 'asc' } },
    },
  });
  if (!b) throw new NotFoundError('Job not found');
  if (b.technicianId !== tech.id) throw new ForbiddenError('This job is not assigned to you');
  return toTechnicianJobDetailDto(b, b.address, b.service, b.customer.user.phone, await toPhotoSummaries(b.photos), b.bookingParts);
}
```

- [ ] **Step 5: Schema + route**
  - `technician-jobs.schemas.ts` — append: `export const jobIdParams = z.object({ id: z.string().min(1).max(64) }).strict();`
  - `technician-jobs.routes.ts` — add `getMyJob` to the service import and `jobIdParams` to the schemas import; register right after the `/technician/jobs/mine` route:

```ts
  app.get('/technician/jobs/:id', { preHandler: [requireAuth] }, async (req, reply) => {
    requireTechnicianRole(req);
    const p = jobIdParams.safeParse(req.params);
    if (!p.success) throw new ValidationError(p.error.issues[0]?.message ?? 'Invalid input');
    return reply.send(await getMyJob(req.user!.id, p.data.id));
  });
```

- [ ] **Step 6: Run the file, the full suite (fix any existing assertion that compares a technician job's `service` object with `toEqual` — add `categoryId: <the seeded category id>`), and the build**

Run: `cd apps/backend && set -a && source .env && set +a && pnpm vitest run tests/technician-jobs/job-detail.test.ts && pnpm vitest run && pnpm build`
Expected: PASS; tsc clean.

- [ ] **Step 7: Commit**

```bash
git add apps/backend/src/modules/technician-jobs/technician-jobs.types.ts apps/backend/src/modules/technician-jobs/technician-jobs.service.ts apps/backend/src/modules/technician-jobs/technician-jobs.schemas.ts apps/backend/src/modules/technician-jobs/technician-jobs.routes.ts apps/backend/tests/technician-jobs/job-detail.test.ts
git -c user.name=MohammadKaifSaiyad -c user.email=saiyedkgn6@gmail.com commit -m "feat(backend): GET /technician/jobs/:id (job + parts cart) and service.categoryId on technician job DTOs"
```
(Add any other test file you had to touch in Step 6 to the `git add` line.)

---

### Task 4: App — `FailureKind.forbidden/notFound`, detail DTOs, `TechnicianJobRepository.job(id)`

**Files:**
- Modify: `apps/technician/lib/core/result.dart`
- Modify: `apps/technician/lib/features/jobs/presentation/photo_capture.dart` (`_terminalMessage` switch ~line 404)
- Modify: `apps/technician/lib/features/jobs/data/technician_job_dto.dart`
- Modify: `apps/technician/lib/features/jobs/data/technician_job_repository.dart`
- Test: create `apps/technician/test/core/result_test.dart`; modify `apps/technician/test/jobs/technician_job_repository_test.dart`, `apps/technician/test/jobs/photo_upload_queue_test.dart`

**Interfaces:**
- Produces:
  - `enum FailureKind { network, unauthorized, forbidden, notFound, rateLimited, validation, server, unknown }`; `failureKindFromStatus(403) == forbidden`, `(404) == notFound`; all other mappings unchanged.
  - `JobServiceDto({required String name, required String requiredSkill, String? categoryId})` (nullable: older backends / fixtures without it keep working).
  - `JobPartLineDto({required String id, required String partsCatalogId, required String sku, required String name, required int qty, required int ceilingPricePaise})` with `fromJson`.
  - `TechnicianJobDetailDto({required TechnicianJobDto job, List<JobPartLineDto> parts = const []})` (freezed, NO `fromJson` — parsed by the repository).
  - `Future<Result<TechnicianJobDetailDto>> TechnicianJobRepository.job(String id)` — bodyless `GET /technician/jobs/$id`.

- [ ] **Step 1: Failing tests**
  - Create `test/core/result_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fixcare_technician/core/result.dart';

void main() {
  test('403 → forbidden, 404 → notFound', () {
    expect(failureKindFromStatus(403), FailureKind.forbidden);
    expect(failureKindFromStatus(404), FailureKind.notFound);
  });

  test('existing mappings are unchanged', () {
    expect(failureKindFromStatus(401), FailureKind.unauthorized);
    expect(failureKindFromStatus(429), FailureKind.rateLimited);
    expect(failureKindFromStatus(400), FailureKind.validation);
    expect(failureKindFromStatus(408), FailureKind.network);
    expect(failureKindFromStatus(500), FailureKind.server);
    expect(failureKindFromStatus(409), FailureKind.unknown);
    expect(failureKindFromStatus(422), FailureKind.unknown);
    expect(failureKindFromStatus(null), FailureKind.unknown);
  });
}
```

  - Append to `test/jobs/technician_job_repository_test.dart` (inside `main`):

```dart
  test('job(id) is a bodyless GET and parses the job + parts + categoryId', () async {
    adapter.onGet('/technician/jobs/b1', (s) => s.reply(200, {
      ..._job(),
      'state': 'ARRIVED',
      'service': {'name': 'Ceiling fan repair', 'requiredSkill': 'FAN', 'categoryId': 'cat-fan'},
      'parts': [
        {'id': 'l1', 'partsCatalogId': 'p1', 'sku': 'CAP', 'name': 'Capacitor', 'qty': 2, 'ceilingPricePaise': 15000},
      ],
    }));
    final v = (await repo.job('b1') as Ok<TechnicianJobDetailDto>).value;
    expect(v.job.state, 'ARRIVED');
    expect(v.job.service.categoryId, 'cat-fan');
    expect(v.parts, const [
      JobPartLineDto(id: 'l1', partsCatalogId: 'p1', sku: 'CAP', name: 'Capacitor', qty: 2, ceilingPricePaise: 15000),
    ]);
  });

  test('job(id) with no parts key → empty parts; no categoryId → null', () async {
    adapter.onGet('/technician/jobs/b1', (s) => s.reply(200, _job()));
    final v = (await repo.job('b1') as Ok<TechnicianJobDetailDto>).value;
    expect(v.parts, isEmpty);
    expect(v.job.service.categoryId, isNull);
  });

  test('job(id) 404 → Failure(notFound, message); 403 → Failure(forbidden, message)', () async {
    adapter.onGet('/technician/jobs/gone', (s) => s.reply(404, {'code': 'NOT_FOUND', 'message': 'Job not found'}));
    final gone = await repo.job('gone') as Failure<TechnicianJobDetailDto>;
    expect(gone.kind, FailureKind.notFound);
    expect(gone.message, 'Job not found');
    adapter.onGet('/technician/jobs/theirs', (s) => s.reply(403, {'code': 'FORBIDDEN', 'message': 'This job is not assigned to you'}));
    final theirs = await repo.job('theirs') as Failure<TechnicianJobDetailDto>;
    expect(theirs.kind, FailureKind.forbidden);
    expect(theirs.message, 'This job is not assigned to you');
  });

  test('job(id) non-object body → Failure(server)', () async {
    adapter.onGet('/technician/jobs/b1', (s) => s.reply(200, ['not', 'a', 'map']));
    expect((await repo.job('b1') as Failure).kind, FailureKind.server);
  });
```

  - In `test/jobs/photo_upload_queue_test.dart`, the parameterized terminal-kind test inside `group('failure classification (terminal vs transient)', …)` (≈ line 463) loops over `const [FailureKind.unauthorized, FailureKind.validation, FailureKind.unknown]`. Extend that list to `const [FailureKind.unauthorized, FailureKind.forbidden, FailureKind.notFound, FailureKind.validation, FailureKind.unknown]` — no other change; the existing body already asserts `failed`, the verbatim message, one sign call, and no PUT.

- [ ] **Step 2: Run — expect FAIL** (missing enum values / `job` / DTOs)

Run: `cd apps/technician && flutter test test/core/result_test.dart test/jobs/technician_job_repository_test.dart test/jobs/photo_upload_queue_test.dart`

- [ ] **Step 3: Implement**
  - `lib/core/result.dart`: change the enum to `enum FailureKind { network, unauthorized, forbidden, notFound, rateLimited, validation, server, unknown }` and add to `failureKindFromStatus`, right after the `401` case:

```dart
    // The backend saying "not yours" / "gone" — distinct kinds so callers (e.g. the job-detail poll)
    // can stop instead of treating them like a transient failure.
    case 403: return FailureKind.forbidden;
    case 404: return FailureKind.notFound;
```

  - `photo_capture.dart` `_terminalMessage`: change the terminal arm to `FailureKind.unauthorized || FailureKind.forbidden || FailureKind.notFound || FailureKind.validation || FailureKind.unknown => error.message,` (the transient arm is unchanged).
  - `technician_job_dto.dart`: change `JobServiceDto` to

```dart
@freezed
abstract class JobServiceDto with _$JobServiceDto {
  // categoryId: the job's service category — filters the issue/parts pickers. Nullable so an older
  // backend (or a fixture) without it still parses; pickers then fall back to unfiltered lists.
  const factory JobServiceDto({required String name, required String requiredSkill, String? categoryId}) =
      _JobServiceDto;
  factory JobServiceDto.fromJson(Map<String, dynamic> j) => _$JobServiceDtoFromJson(j);
}
```

  and append

```dart
/// One cart line as the backend stores it — the snapshot price, never a live catalog read (Golden Rule 4).
@freezed
abstract class JobPartLineDto with _$JobPartLineDto {
  const factory JobPartLineDto({
    required String id,
    required String partsCatalogId,
    required String sku,
    required String name,
    required int qty,
    required int ceilingPricePaise,
  }) = _JobPartLineDto;
  factory JobPartLineDto.fromJson(Map<String, dynamic> j) => _$JobPartLineDtoFromJson(j);
}

/// GET /technician/jobs/:id — the job plus its parts cart. Composed (not a subtype) so every existing
/// helper/card keeps taking the plain [TechnicianJobDto]. Parsed by [TechnicianJobRepository.job].
@freezed
abstract class TechnicianJobDetailDto with _$TechnicianJobDetailDto {
  const factory TechnicianJobDetailDto({
    required TechnicianJobDto job,
    @Default(<JobPartLineDto>[]) List<JobPartLineDto> parts,
  }) = _TechnicianJobDetailDto;
}
```

  - `technician_job_repository.dart`: add below `mine()`:

```dart
  /// The job-detail screen's poll target: one job + its parts cart. 403 = not yours, 404 = gone.
  Future<Result<TechnicianJobDetailDto>> job(String id) => _guard(() async {
    final res = await _dio.get('/technician/jobs/$id');
    final status = res.statusCode ?? 0;
    if (status < 200 || status >= 300) return Failure(failureKindFromStatus(status), _msg(res.data));
    final data = res.data;
    if (data is! Map) return const Failure(FailureKind.server, 'Unexpected response from the server.');
    final map = data.cast<String, dynamic>();
    final rawParts = map['parts'];
    return Ok(TechnicianJobDetailDto(
      job: TechnicianJobDto.fromJson(map),
      parts: rawParts is List
          ? rawParts.map((e) => JobPartLineDto.fromJson((e as Map).cast<String, dynamic>())).toList()
          : const <JobPartLineDto>[],
    ));
  });
```

- [ ] **Step 4: Codegen, run the tests, full suite, analyze**

Run: `cd apps/technician && dart run build_runner build --delete-conflicting-outputs && flutter test && flutter analyze`
Expected: all PASS; `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add apps/technician/lib/core/result.dart apps/technician/lib/features/jobs/presentation/photo_capture.dart apps/technician/lib/features/jobs/data/technician_job_dto.dart apps/technician/lib/features/jobs/data/technician_job_dto.freezed.dart apps/technician/lib/features/jobs/data/technician_job_dto.g.dart apps/technician/lib/features/jobs/data/technician_job_repository.dart apps/technician/test/core/result_test.dart apps/technician/test/jobs/technician_job_repository_test.dart apps/technician/test/jobs/photo_upload_queue_test.dart
git -c user.name=MohammadKaifSaiyad -c user.email=saiyedkgn6@gmail.com commit -m "feat(technician): job(id) single-job fetch with parts cart + categoryId; FailureKind forbidden/notFound"
```

---

### Task 5: App — the job-detail controller polls `job(id)`; 403/404 → "no longer assigned"

**Files:**
- Modify: `apps/technician/lib/features/jobs/presentation/job_detail_controller.dart` (+ regenerate `.g.dart`)
- Modify: `apps/technician/lib/features/jobs/presentation/job_detail_screen.dart`
- Test: `apps/technician/test/jobs/job_detail_controller_test.dart`, `apps/technician/test/jobs/job_detail_screen_test.dart`; any other test whose fake repository feeds the real `JobDetail` controller through `mine()` (check `diagnosis_form_test.dart`, `repair_photos_card_test.dart`, `parts_cart_test.dart` with `grep -n "mine()" test/jobs/*.dart`).

**Interfaces:**
- Consumes: Task 4 `job(id)`, `TechnicianJobDetailDto`, `FailureKind.forbidden/notFound`.
- Produces: `jobDetailProvider(bookingId)` is now `AsyncValue<TechnicianJobDetailDto>`; `refetch()`, `pause()`, `resume()` unchanged in name/behavior; `JobVanishedException` (unchanged `toString()` = `This job is no longer assigned to you.`). `kMaxConsecutiveMisses` is REMOVED.

- [ ] **Step 1: Failing controller tests** — in `test/jobs/job_detail_controller_test.dart` switch the fake repository from `mine()` to `job(id)` (keep all existing behavior tests: one-shot re-arm, no overlapping polls, late response dropped, pause/resume, photo-url-only change does not notify) and DELETE the 3-consecutive-misses tests. The fake overrides:

```dart
  @override
  Future<Result<List<TechnicianJobDto>>> mine() async =>
      throw StateError('the job-detail controller must not call mine()');

  @override
  Future<Result<TechnicianJobDetailDto>> job(String id) async {
    jobCalls++;
    return nextJobResult ?? Ok(TechnicianJobDetailDto(job: current, parts: parts));
  }
```

(`current` = the fake's current `TechnicianJobDto`, `parts` = a mutable `List<JobPartLineDto>`, `nextJobResult` = an optional one-shot override the test sets and the fake clears after use.) Add:

```dart
  test('404 on first load → AsyncError(JobVanishedException) and nothing is polled', () {
    fakeAsync((async) {
      final repo = _FakeRepo()..nextJobResult = const Failure(FailureKind.notFound, 'Job not found');
      final container = _container(repo);
      container.listen(jobDetailProvider('b1'), (_, _) {});
      async.flushMicrotasks();
      expect(container.read(jobDetailProvider('b1')).error, isA<JobVanishedException>());
      async.elapse(const Duration(seconds: 30));
      expect(repo.jobCalls, 1);
      container.dispose();
    });
  });

  test('403 during polling → AsyncError(JobVanishedException) and polling stops', () {
    fakeAsync((async) {
      final repo = _FakeRepo();
      final container = _container(repo);
      container.listen(jobDetailProvider('b1'), (_, _) {});
      async.flushMicrotasks();
      repo.nextJobResult = const Failure(FailureKind.forbidden, 'This job is not assigned to you');
      async.elapse(jobPollInterval);
      async.flushMicrotasks();
      expect(container.read(jobDetailProvider('b1')).error, isA<JobVanishedException>());
      final calls = repo.jobCalls;
      async.elapse(const Duration(seconds: 30));
      expect(repo.jobCalls, calls);
      container.dispose();
    });
  });

  test('a transient failure (network) during polling keeps the last good data and keeps polling', () {
    fakeAsync((async) {
      final repo = _FakeRepo();
      final container = _container(repo);
      container.listen(jobDetailProvider('b1'), (_, _) {});
      async.flushMicrotasks();
      repo.nextJobResult = const Failure(FailureKind.network, 'Network error. Check your connection.');
      async.elapse(jobPollInterval);
      async.flushMicrotasks();
      expect(container.read(jobDetailProvider('b1')).value?.job.id, 'b1');
      final calls = repo.jobCalls;
      async.elapse(jobPollInterval);
      async.flushMicrotasks();
      expect(repo.jobCalls, calls + 1);
      container.dispose();
    });
  });

  test('a parts change between polls DOES notify (unlike a photo-url-only change)', () {
    fakeAsync((async) {
      final repo = _FakeRepo();
      final container = _container(repo);
      var notifications = 0;
      container.listen(jobDetailProvider('b1'), (_, _) => notifications++);
      async.flushMicrotasks();
      final before = notifications;
      repo.parts.add(const JobPartLineDto(id: 'l1', partsCatalogId: 'p1', sku: 'CAP', name: 'Capacitor', qty: 1, ceilingPricePaise: 15000));
      async.elapse(jobPollInterval);
      async.flushMicrotasks();
      expect(notifications, before + 1);
      expect(container.read(jobDetailProvider('b1')).value!.parts.single.id, 'l1');
      container.dispose();
    });
  });
```

(`_container(repo)` = the file's existing `ProviderContainer(overrides: [technicianJobRepositoryProvider.overrideWithValue(repo)])` helper; reuse whatever the file already calls it. Match the file's existing `fakeAsync` import/style.)

- [ ] **Step 2: Run — expect FAIL**

Run: `cd apps/technician && flutter test test/jobs/job_detail_controller_test.dart`

- [ ] **Step 3: Implement the controller** — replace the body of `job_detail_controller.dart` from `const jobPollInterval` down (keep the imports, adding `import 'package:flutter/foundation.dart' show listEquals;`):

```dart
const jobPollInterval = Duration(seconds: 5);

/// The job is no longer this technician's: the single-job GET answered 404 (gone) or 403 (reassigned).
/// Distinct from a transient fetch failure so the job-detail screen shows this exact copy.
class JobVanishedException implements Exception {
  const JobVanishedException();
  @override
  String toString() => 'This job is no longer assigned to you.';
}

bool _isGone(FailureKind k) => k == FailureKind.notFound || k == FailureKind.forbidden;

/// Loads and adaptively polls ONE job (`GET /technician/jobs/:id`) for the job-detail screen, so it can
/// observe customer-side transitions (arrival confirmation, approval, completion, cash decline) without
/// the technician acting — and reads the job's real parts cart.
///
/// Polling is a chain of ONE-SHOT timers: the next tick is armed only after the current poll completes,
/// so a slow network never stacks requests. Every fetch (poll or [refetch]) takes a sequence number and is
/// applied only if newer than the last one applied — a late response never regresses the card.
/// [pause]/[resume] stop and restart the chain while the app is backgrounded.
@riverpod
class JobDetail extends _$JobDetail {
  Timer? _timer;
  late String _bookingId;

  // Monotonic across polls AND refetches (and rebuilds of this notifier).
  int _requestSeq = 0;
  int _appliedSeq = 0;
  bool _pollInFlight = false;
  bool _paused = false;
  bool _vanished = false;

  @override
  Future<TechnicianJobDetailDto> build(String bookingId) async {
    _bookingId = bookingId;
    _vanished = false;
    ref.onDispose(_cancelTimer);
    final seq = ++_requestSeq;
    final r = await ref.read(technicianJobRepositoryProvider).job(bookingId);
    final detail = switch (r) {
      Ok(value: final v) => v,
      Failure(kind: final k) when _isGone(k) => throw const JobVanishedException(),
      Failure(message: final m) => throw Exception(m),
    };
    if (seq > _appliedSeq) _appliedSeq = seq;
    _rearm(detail);
    return detail;
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Arms the next one-shot tick — unless paused, a poll is still in flight (it re-arms itself when it
  /// completes), the job vanished, or the job is terminal.
  void _rearm(TechnicianJobDetailDto? detail) {
    _cancelTimer();
    if (_paused || _pollInFlight || _vanished) return;
    if (detail == null || isTerminalJob(detail.job)) return;
    _timer = Timer(jobPollInterval, _poll);
  }

  Future<void> _poll() async {
    _timer = null;
    if (!ref.mounted || _pollInFlight) return;
    _pollInFlight = true;
    try {
      await _fetchAndApply();
    } finally {
      _pollInFlight = false;
    }
    if (!ref.mounted) return;
    _rearm(state.value);
  }

  /// One sequenced fetch. keep-last-good on a transient Failure (never flashes AsyncLoading/AsyncError);
  /// 404/403 → the job is gone → AsyncError(JobVanishedException) and polling stops. A response that
  /// differs only in photo URLs (the app never shows them) is applied silently (no listener notify).
  Future<void> _fetchAndApply() async {
    final seq = ++_requestSeq;
    final r = await ref.read(technicianJobRepositoryProvider).job(_bookingId);
    if (!ref.mounted) return;
    if (seq <= _appliedSeq) return; // an older response landing late: drop it
    switch (r) {
      case Ok(value: final detail):
        _appliedSeq = seq;
        _vanished = false;
        final current = state.value;
        if (current != null && _sameIgnoringPhotoUrls(current, detail)) return;
        state = AsyncData(detail);
      case Failure(kind: final k) when _isGone(k):
        _appliedSeq = seq;
        _vanished = true;
        _cancelTimer();
        state = AsyncError(const JobVanishedException(), StackTrace.current);
      case Failure():
        return; // transient (network/5xx/…): keep last good, retry next tick
    }
  }

  /// Forced immediate reload (after an action, or on resume). Never flashes AsyncLoading.
  Future<void> refetch() async {
    await _fetchAndApply();
    if (!ref.mounted) return;
    _rearm(state.value);
  }

  /// App backgrounded: stop polling (no data/battery burn off-screen).
  void pause() {
    _paused = true;
    _cancelTimer();
  }

  /// App foregrounded: fetch now, then re-arm polling (unless terminal / vanished).
  Future<void> resume() {
    _paused = false;
    return refetch();
  }
}

/// "Unchanged" check for [JobDetail._fetchAndApply]: identical except each photo's `url` — the app only
/// reads a photo's `kind`, never displays its (freshly re-signed) URL. Parts must match exactly.
bool _sameIgnoringPhotoUrls(TechnicianJobDetailDto a, TechnicianJobDetailDto b) {
  final x = a.job;
  final y = b.job;
  if (x.id != y.id ||
      x.bookingNumber != y.bookingNumber ||
      x.state != y.state ||
      x.scheduledSlot != y.scheduledSlot ||
      x.service != y.service ||
      x.zone != y.zone ||
      x.visitFeePaise != y.visitFeePaise ||
      x.laborPaise != y.laborPaise ||
      x.address != y.address ||
      x.customer != y.customer) {
    return false;
  }
  if (!listEquals(a.parts, b.parts)) return false;
  if (x.photos.length != y.photos.length) return false;
  for (var i = 0; i < x.photos.length; i++) {
    if (x.photos[i].kind != y.photos[i].kind || x.photos[i].capturedAt != y.photos[i].capturedAt) return false;
  }
  return true;
}
```

- [ ] **Step 4: Plumb the detail DTO through the screen** — in `job_detail_screen.dart`:
  - `AsyncData(value: final job) => _buildBody(job),` → `AsyncData(value: final detail) => _buildBody(detail),`
  - Any `async.value?.bookingNumber` (AppBar title) → `async.value?.job.bookingNumber`.
  - `Widget _buildBody(TechnicianJobDto job)` → `Widget _buildBody(TechnicianJobDetailDto detail)`; inside, `final job = detail.job;` keeps `_JobInfoCard(job: job)`; call `_buildActionCard(detail)`.
  - `Widget _buildActionCard(TechnicianJobDto job)` → `Widget _buildActionCard(TechnicianJobDetailDto detail)` with `final job = detail.job;` as its first line; every card keeps receiving `job` (Task 6/7 switch two of them to `detail`).
- [ ] **Step 5: Update the remaining test fakes** — in every test file that feeds the real `JobDetail` controller via a fake repo's `mine()` (screen test and any others found by the grep in Files), add the `job(String id)` override returning `Ok(TechnicianJobDetailDto(job: <that fake's current job>, parts: const []))` and make any state mutation the fake does on actions (e.g. `enRoute` flipping state) visible through `job()`. Where a test reads `jobDetailProvider(...).value` as a `TechnicianJobDto`, read `.value!.job` instead. Where a test asserts "a refetch happened" by counting `mine()` calls (e.g. `mineCalls` in `diagnosis_form_test.dart` / `repair_photos_card_test.dart`), count `job()` calls instead (`jobCalls`) — the controller no longer calls `mine()`. Add to `job_detail_screen_test.dart`:

```dart
  testWidgets('a 403 from the single-job GET shows "This job is no longer assigned to you."', (tester) async {
    final repo = _FakeRepo()..jobResultOverride = const Failure(FailureKind.forbidden, 'This job is not assigned to you');
    await _pump(tester, repo);
    expect(find.text('This job is no longer assigned to you.'), findsOneWidget);
    expect(find.byKey(const Key('jobDetailRetry')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
```

(`jobResultOverride` = a field the fake's `job()` returns when non-null; `_pump` = the file's existing pump helper.)

- [ ] **Step 6: Codegen, full suite, analyze**

Run: `cd apps/technician && dart run build_runner build --delete-conflicting-outputs && flutter test && flutter analyze`
Expected: PASS; `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add apps/technician/lib/features/jobs/presentation/job_detail_controller.dart apps/technician/lib/features/jobs/presentation/job_detail_controller.g.dart apps/technician/lib/features/jobs/presentation/job_detail_screen.dart apps/technician/test/jobs/job_detail_controller_test.dart apps/technician/test/jobs/job_detail_screen_test.dart
git -c user.name=MohammadKaifSaiyad -c user.email=saiyedkgn6@gmail.com commit -m "feat(technician): job-detail polls the single-job GET; 403/404 → no longer assigned"
```
(Add any other test file you updated in Step 5.)

---

### Task 6: App — server-backed parts section + read-only "estimate sent" card; remove the session cart

**Files:**
- Rewrite: `apps/technician/lib/features/jobs/presentation/parts_cart.dart`; delete `apps/technician/lib/features/jobs/presentation/parts_cart.g.dart`
- Modify: `apps/technician/lib/features/jobs/presentation/job_detail_screen.dart` (`JobAction.waitingApproval` branch)
- Test: rewrite `apps/technician/test/jobs/parts_cart_test.dart`; update `apps/technician/test/jobs/job_detail_screen_test.dart` (DIAGNOSED case)

**Interfaces:**
- Consumes: `TechnicianJobDetailDto`, `JobPartLineDto` (Task 4); `jobDetailProvider(id).notifier.refetch()` (Task 5); `catalogRepositoryProvider.parts({String? categoryId})`; `technicianJobRepositoryProvider.addPart(id, {partsCatalogId, qty}) → Result<String>`, `.removePart(id, partId) → Result<void>`; `rupees`, `FixCareColors`.
- Produces (Task 7 relies on these exact names):
  - `int estimatePaise(TechnicianJobDto job, List<JobPartLineDto> parts)`
  - `final partsCatalogProvider = FutureProvider.autoDispose.family<Result<List<PartCatalogDto>>, String?>(…)`
  - `PartsSection({Key? key, required TechnicianJobDetailDto detail, required ValueChanged<bool> onBusyChanged})` — keys `partsFilter`, `partsRetry`, `qtyMinus_<partId>`, `qtyPlus_<partId>`, `addPartBtn_<partId>`, `cartLine_<lineId>`, `removePartBtn_<lineId>`, `customerWillSee`.
  - `EstimateSentCard({Key? key, required TechnicianJobDetailDto detail})` — root `Key('waitingApprovalCard')`, `estimateLine_<lineId>`, `estimateLaborOnly`, `estimateTotal`.
  - REMOVED: `CartLine`, `JobCart` / `jobCartProvider`, `indicativeEstimatePaise`, `PartsCartCard`.

- [ ] **Step 1: Write the failing tests** — replace `test/jobs/parts_cart_test.dart` with:

```dart
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/features/jobs/data/catalog_repository.dart';
import 'package:fixcare_technician/features/jobs/data/technician_job_repository.dart';
import 'package:fixcare_technician/features/jobs/presentation/job_detail_controller.dart';
import 'package:fixcare_technician/features/jobs/presentation/parts_cart.dart';

TechnicianJobDto _job({String state = 'ARRIVED', int labor = 20000, int visit = 9900, String? categoryId = 'cat-fan'}) =>
    TechnicianJobDto.fromJson({
      'id': 'b1', 'bookingNumber': 'FC-1', 'state': state, 'scheduledSlot': '2026-10-01T09:00:00.000Z',
      'service': {'name': 'Ceiling fan repair', 'requiredSkill': 'FAN', 'categoryId': categoryId},
      'zone': {'name': 'Padra'}, 'visitFeePaise': visit, 'laborPaise': labor,
      'address': {'line1': 'A/27 Umiya Nagar', 'pincode': '391440'},
      'customer': {'maskedPhone': '••••••8384'}, 'photos': <Map<String, dynamic>>[],
    });

const _capacitor = PartCatalogDto(id: 'p1', sku: 'CAP', name: 'Capacitor', categoryId: 'cat-fan', ceilingPricePaise: 15000, status: 'ACTIVE');

/// Server-side cart: addPart/removePart mutate it; job() returns it — like the real backend.
class _FakeJobRepo extends TechnicianJobRepository {
  _FakeJobRepo({this.categoryId = 'cat-fan'}) : super(Dio());
  final String? categoryId;
  final List<JobPartLineDto> serverParts = [];
  int jobCalls = 0;
  int addCalls = 0;
  ({String partsCatalogId, int qty})? lastAdd;
  String? lastRemoved;
  Result<String>? addResultOverride;
  bool applyAddDespiteFailure = false;
  Completer<void>? addGate;

  @override
  Future<Result<TechnicianJobDetailDto>> job(String id) async {
    jobCalls++;
    return Ok(TechnicianJobDetailDto(job: _job(categoryId: categoryId), parts: List.of(serverParts)));
  }

  @override
  Future<Result<String>> addPart(String id, {required String partsCatalogId, required int qty}) async {
    addCalls++;
    lastAdd = (partsCatalogId: partsCatalogId, qty: qty);
    if (addGate != null) await addGate!.future;
    final override = addResultOverride;
    if (override == null || applyAddDespiteFailure) {
      serverParts.add(JobPartLineDto(id: 'l${serverParts.length + 1}', partsCatalogId: partsCatalogId, sku: 'CAP', name: 'Capacitor', qty: qty, ceilingPricePaise: 15000));
    }
    return override ?? Ok('l${serverParts.length}');
  }

  @override
  Future<Result<void>> removePart(String id, String partId) async {
    lastRemoved = partId;
    serverParts.removeWhere((p) => p.id == partId);
    return const Ok(null);
  }
}

class _FakeCatalog extends CatalogRepository {
  _FakeCatalog() : super(Dio());
  final List<String?> partsCategoryArgs = [];
  @override
  Future<Result<List<PartCatalogDto>>> parts({String? categoryId}) async {
    partsCategoryArgs.add(categoryId);
    return const Ok([_capacitor]);
  }
}

/// Renders PartsSection the way the diagnosis form does: from the live jobDetailProvider.
Future<void> _pump(WidgetTester tester, _FakeJobRepo repo, _FakeCatalog catalog, {ValueChanged<bool>? onBusy}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      technicianJobRepositoryProvider.overrideWithValue(repo),
      catalogRepositoryProvider.overrideWithValue(catalog),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Consumer(builder: (context, ref, _) {
          final async = ref.watch(jobDetailProvider('b1'));
          return switch (async) {
            AsyncData(value: final d) => SingleChildScrollView(child: PartsSection(detail: d, onBusyChanged: onBusy ?? (_) {})),
            _ => const SizedBox(),
          };
        }),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('estimatePaise (what the customer will see — mirrors the backend DIAGNOSED quote)', () {
    test('labor 20000 + 2 × 15000 − visit fee 9900 = 40100', () {
      expect(estimatePaise(_job(), const [JobPartLineDto(id: 'l1', partsCatalogId: 'p1', sku: 'CAP', name: 'Capacitor', qty: 2, ceilingPricePaise: 15000)]), 40100);
    });
    test('floors at 0 when the visit fee exceeds labor + parts', () {
      expect(estimatePaise(_job(labor: 5000, visit: 9900), const []), 0);
    });
  });

  group('PartsSection', () {
    testWidgets('the cart shown is the server cart; the parts list is fetched for the job category', (tester) async {
      final repo = _FakeJobRepo()..serverParts.add(const JobPartLineDto(id: 'l9', partsCatalogId: 'p1', sku: 'CAP', name: 'Capacitor', qty: 1, ceilingPricePaise: 15000));
      final catalog = _FakeCatalog();
      await _pump(tester, repo, catalog);
      expect(find.byKey(const Key('cartLine_l9')), findsOneWidget);
      expect(catalog.partsCategoryArgs, ['cat-fan']);
      expect(find.text('Customer will see: ₹251'), findsOneWidget); // 20000 + 15000 − 9900 = 25100 paise
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('no categoryId (older backend) → the parts list is unfiltered', (tester) async {
      final catalog = _FakeCatalog();
      await _pump(tester, _FakeJobRepo(categoryId: null), catalog);
      expect(catalog.partsCategoryArgs, [null]);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('add with qty 2 → addPart(qty: 2) then a refetch renders the server line + new estimate', (tester) async {
      final repo = _FakeJobRepo();
      await _pump(tester, repo, _FakeCatalog());
      final callsBefore = repo.jobCalls;
      await tester.tap(find.byKey(const Key('qtyPlus_p1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('addPartBtn_p1')));
      await tester.pumpAndSettle();
      expect(repo.lastAdd, (partsCatalogId: 'p1', qty: 2));
      expect(repo.jobCalls, greaterThan(callsBefore));
      expect(find.byKey(const Key('cartLine_l1')), findsOneWidget);
      expect(find.text('Customer will see: ₹401'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('remove → removePart(lineId) then the line disappears', (tester) async {
      final repo = _FakeJobRepo()..serverParts.add(const JobPartLineDto(id: 'l9', partsCatalogId: 'p1', sku: 'CAP', name: 'Capacitor', qty: 1, ceilingPricePaise: 15000));
      await _pump(tester, repo, _FakeCatalog());
      await tester.tap(find.byKey(const Key('removePartBtn_l9')));
      await tester.pumpAndSettle();
      expect(repo.lastRemoved, 'l9');
      expect(find.byKey(const Key('cartLine_l9')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a lost add response the backend applied still converges to the server cart (no ghost, no dupe)', (tester) async {
      final repo = _FakeJobRepo()
        ..addResultOverride = const Failure(FailureKind.network, 'Network error. Check your connection.')
        ..applyAddDespiteFailure = true;
      await _pump(tester, repo, _FakeCatalog());
      await tester.tap(find.byKey(const Key('addPartBtn_p1')));
      await tester.pumpAndSettle();
      expect(find.text('Network error. Check your connection.'), findsOneWidget); // surfaced
      expect(find.byKey(const Key('cartLine_l1')), findsOneWidget); // server truth shown after refetch
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a locked-cart 409 / not-assigned 403 is shown verbatim and refetches', (tester) async {
      final repo = _FakeJobRepo()..addResultOverride = const Failure(FailureKind.unknown, 'The cart is locked — the diagnosis has been submitted');
      await _pump(tester, repo, _FakeCatalog());
      final callsBefore = repo.jobCalls;
      await tester.tap(find.byKey(const Key('addPartBtn_p1')));
      await tester.pumpAndSettle();
      expect(find.text('The cart is locked — the diagnosis has been submitted'), findsOneWidget);
      expect(repo.jobCalls, greaterThan(callsBefore));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('reports busy while an add is in flight (and a double tap is ignored)', (tester) async {
      final repo = _FakeJobRepo()..addGate = Completer<void>();
      final busy = <bool>[];
      await _pump(tester, repo, _FakeCatalog(), onBusy: busy.add);
      await tester.tap(find.byKey(const Key('addPartBtn_p1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('addPartBtn_p1')), warnIfMissed: false);
      await tester.pump();
      expect(busy.last, isTrue);
      expect(repo.addCalls, 1);
      repo.addGate!.complete();
      await tester.pumpAndSettle();
      expect(busy.last, isFalse);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('EstimateSentCard (DIAGNOSED, read-only)', () {
    testWidgets('shows the frozen lines and the total; no edit controls', (tester) async {
      final detail = TechnicianJobDetailDto(job: _job(state: 'DIAGNOSED'), parts: const [JobPartLineDto(id: 'l1', partsCatalogId: 'p1', sku: 'CAP', name: 'Capacitor', qty: 2, ceilingPricePaise: 15000)]);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: EstimateSentCard(detail: detail))));
      expect(find.byKey(const Key('waitingApprovalCard')), findsOneWidget);
      expect(find.text('Estimate sent — waiting for the customer to approve or decline'), findsOneWidget);
      expect(find.byKey(const Key('estimateLine_l1')), findsOneWidget);
      expect(find.text('Total: ₹401'), findsOneWidget);
      expect(find.byType(IconButton), findsNothing);
    });

    testWidgets('labor-only estimate and a total floored at ₹0', (tester) async {
      final detail = TechnicianJobDetailDto(job: _job(state: 'DIAGNOSED', labor: 5000, visit: 9900));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: EstimateSentCard(detail: detail))));
      expect(find.byKey(const Key('estimateLaborOnly')), findsOneWidget);
      expect(find.text('Total: ₹0'), findsOneWidget);
    });
  });
}
```

(If `PartCatalogDto`'s constructor differs from the one used above, match `lib/features/jobs/data/catalog_dtos.dart` exactly — fields are `id, sku, name, categoryId?, ceilingPricePaise, status`. `rupees(25100)` renders `₹251`, `rupees(40100)` renders `₹401` — check `rupees` in `lib/core/format.dart` and adjust the expected strings to its exact output.)

- [ ] **Step 2: Run — expect FAIL** (`PartsSection`/`EstimateSentCard`/`estimatePaise` undefined)

Run: `cd apps/technician && flutter test test/jobs/parts_cart_test.dart`

- [ ] **Step 3: Rewrite `parts_cart.dart`** — the whole file becomes:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/result.dart';
import '../../../core/theme.dart';
import '../data/catalog_repository.dart';
import '../data/technician_job_repository.dart';
import 'job_detail_controller.dart';

/// What the customer will see at DIAGNOSED — mirrors the backend quote (computeEstimate): labor +
/// Σ(snapshot ceiling price × qty) − visit fee (credited once quoted), floored at 0. Integer paise; only
/// `rupees()` formats. Shared by the diagnosis form preview and the read-only DIAGNOSED card.
int estimatePaise(TechnicianJobDto job, List<JobPartLineDto> parts) {
  final partsTotal = parts.fold<int>(0, (sum, p) => sum + p.ceilingPricePaise * p.qty);
  final total = job.laborPaise + partsTotal - job.visitFeePaise;
  return total < 0 ? 0 : total;
}

/// Parts catalog for a job's category (the backend returns that category + generic parts). `null` (an
/// older backend without categoryId) → unfiltered. autoDispose: re-fetched each time the form opens.
final partsCatalogProvider =
    FutureProvider.autoDispose.family<Result<List<PartCatalogDto>>, String?>((ref, categoryId) {
  return ref.read(catalogRepositoryProvider).parts(categoryId: categoryId);
});

/// The parts section of the diagnosis form (ARRIVED). The cart shown is ALWAYS the backend's
/// (`detail.parts`): every add/remove goes to the backend and then refetches the job — whatever the
/// outcome — so an app restart, a lost response, or a locked cart can never show a stale or duplicated
/// cart. Catalog prices only (Golden Rule 4): the technician picks a part and a qty, never a price.
class PartsSection extends ConsumerStatefulWidget {
  const PartsSection({super.key, required this.detail, required this.onBusyChanged});

  final TechnicianJobDetailDto detail;

  /// Whether any cart edit is in flight — the form blocks "Submit diagnosis" until the cart settles, so the
  /// estimate sent is exactly the one on screen.
  final ValueChanged<bool> onBusyChanged;

  @override
  ConsumerState<PartsSection> createState() => _PartsSectionState();
}

class _PartsSectionState extends ConsumerState<PartsSection> {
  final _filterController = TextEditingController();
  String _filter = '';
  final Map<String, int> _qty = {}; // selected qty per catalog part (1..99, default 1) — UI-only until Add
  final Set<String> _busyPartIds = {};
  final Set<String> _busyLineIds = {};

  @override
  void initState() {
    super.initState();
    _filterController.addListener(_onFilterChanged);
  }

  void _onFilterChanged() => setState(() => _filter = _filterController.text.trim().toLowerCase());

  @override
  void dispose() {
    _filterController.removeListener(_onFilterChanged);
    _filterController.dispose();
    super.dispose();
  }

  String get _jobId => widget.detail.job.id;
  int _qtyFor(String partId) => _qty[partId] ?? 1;
  void _incQty(String partId) => setState(() => _qty[partId] = (_qtyFor(partId) + 1).clamp(1, 99));
  void _decQty(String partId) => setState(() => _qty[partId] = (_qtyFor(partId) - 1).clamp(1, 99));

  void _reportBusy() => widget.onBusyChanged(_busyPartIds.isNotEmpty || _busyLineIds.isNotEmpty);

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addPart(PartCatalogDto part) async {
    if (_busyPartIds.contains(part.id)) return;
    final repo = ref.read(technicianJobRepositoryProvider);
    final detail = ref.read(jobDetailProvider(_jobId).notifier);
    setState(() => _busyPartIds.add(part.id));
    _reportBusy();
    try {
      final result = await repo.addPart(_jobId, partsCatalogId: part.id, qty: _qtyFor(part.id));
      if (result case Failure(message: final m)) _snack(m);
    } catch (_) {
      _snack('Something went wrong.');
    } finally {
      // Refetch on EVERY outcome: a timed-out add the backend applied shows up; a 409 locked / 403
      // not-assigned moves the screen on. The cart on screen is always the server's.
      if (mounted) await detail.refetch();
      if (mounted) {
        setState(() => _busyPartIds.remove(part.id));
        _reportBusy();
      }
    }
  }

  Future<void> _removeLine(JobPartLineDto line) async {
    if (_busyLineIds.contains(line.id)) return;
    final repo = ref.read(technicianJobRepositoryProvider);
    final detail = ref.read(jobDetailProvider(_jobId).notifier);
    setState(() => _busyLineIds.add(line.id));
    _reportBusy();
    try {
      final result = await repo.removePart(_jobId, line.id);
      if (result case Failure(message: final m)) _snack(m);
    } catch (_) {
      _snack('Something went wrong.');
    } finally {
      if (mounted) await detail.refetch();
      if (mounted) {
        setState(() => _busyLineIds.remove(line.id));
        _reportBusy();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
    final partsAsync = ref.watch(partsCatalogProvider(detail.job.service.categoryId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Parts', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          key: const Key('partsFilter'),
          controller: _filterController,
          decoration: const InputDecoration(labelText: 'Filter parts'),
        ),
        const SizedBox(height: 12),
        _buildPartsList(partsAsync),
        if (detail.parts.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('In this estimate', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          for (final line in detail.parts) _buildCartLine(line),
        ],
        const SizedBox(height: 16),
        Text(
          'Customer will see: ${rupees(estimatePaise(detail.job, detail.parts))}',
          key: const Key('customerWillSee'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        const Text('(labor + parts − visit fee)', style: TextStyle(fontSize: 12, color: FixCareColors.textMuted)),
      ],
    );
  }

  Widget _buildPartsList(AsyncValue<Result<List<PartCatalogDto>>> async) {
    return switch (async) {
      AsyncData(value: Ok(value: final parts)) => _partsColumn(parts),
      AsyncData(value: Failure(message: final m)) => _partsError(m),
      AsyncError() => _partsError('Something went wrong.'),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }

  /// A load failure must be recoverable in place — the technician is at the customer's door.
  Widget _partsError(String message) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const Key('partsRetry'),
            onPressed: () => ref.invalidate(partsCatalogProvider(widget.detail.job.service.categoryId)),
            child: const Text('Retry'),
          ),
        ),
      ],
    );
  }

  Widget _partsColumn(List<PartCatalogDto> parts) {
    final filtered = _filter.isEmpty ? parts : parts.where((p) => p.name.toLowerCase().contains(_filter)).toList();
    // Low-end devices: a plain Column of rows (no nested scrollable inside the screen's ListView).
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final p in filtered) _buildPartRow(p)]);
  }

  Widget _buildPartRow(PartCatalogDto part) {
    final qty = _qtyFor(part.id);
    final busy = _busyPartIds.contains(part.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(part.name),
                Text(rupees(part.ceilingPricePaise), style: const TextStyle(fontSize: 12, color: FixCareColors.textMuted)),
              ],
            ),
          ),
          IconButton(key: Key('qtyMinus_${part.id}'), icon: const Icon(Icons.remove), onPressed: busy ? null : () => _decQty(part.id)),
          Text('$qty'),
          IconButton(key: Key('qtyPlus_${part.id}'), icon: const Icon(Icons.add), onPressed: busy ? null : () => _incQty(part.id)),
          FilledButton(
            key: Key('addPartBtn_${part.id}'),
            onPressed: busy ? null : () => _addPart(part),
            child: busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Add'),
          ),
        ],
      ),
    );
  }

  Widget _buildCartLine(JobPartLineDto line) {
    final busy = _busyLineIds.contains(line.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        key: Key('cartLine_${line.id}'),
        children: [
          Expanded(child: Text('${line.name} × ${line.qty} · ${rupees(line.ceilingPricePaise * line.qty)}')),
          IconButton(
            key: Key('removePartBtn_${line.id}'),
            icon: const Icon(Icons.delete_outline),
            onPressed: busy ? null : () => _removeLine(line),
          ),
        ],
      ),
    );
  }
}

/// DIAGNOSED: the estimate has been sent and the cart is frozen (the backend rejects any change). Read-only
/// — the customer approves or declines in their app; the job poll moves this screen on.
class EstimateSentCard extends StatelessWidget {
  const EstimateSentCard({super.key, required this.detail});

  final TechnicianJobDetailDto detail;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('waitingApprovalCard'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Estimate sent — waiting for the customer to approve or decline',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            if (detail.parts.isEmpty)
              const Text('Labor only — no parts.', key: Key('estimateLaborOnly'))
            else
              for (final p in detail.parts)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text('${p.name} × ${p.qty} · ${rupees(p.ceilingPricePaise * p.qty)}', key: Key('estimateLine_${p.id}')),
                ),
            const SizedBox(height: 12),
            Text(
              'Total: ${rupees(estimatePaise(detail.job, detail.parts))}',
              key: const Key('estimateTotal'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
```

  Then `git rm apps/technician/lib/features/jobs/presentation/parts_cart.g.dart`.

- [ ] **Step 4: Wire DIAGNOSED** — in `job_detail_screen.dart`, `case JobAction.waitingApproval:` returns `EstimateSentCard(detail: detail);`. Leave `case JobAction.diagnose:` as `DiagnosisForm(job: job)` for now (Task 7). In `job_detail_screen_test.dart`, the DIAGNOSED test: give the fake job one part line and assert `find.byKey(const Key('waitingApprovalCard'))` AND `find.byKey(const Key('estimateTotal'))`.

- [ ] **Step 5: Codegen (the deleted provider's generated code is gone), full suite, analyze**

Run: `cd apps/technician && dart run build_runner build --delete-conflicting-outputs && flutter test && flutter analyze`
Expected: PASS; `No issues found!` (If `diagnosis_form.dart` or another file still referenced `jobCartProvider`/`PartsCartCard`/`indicativeEstimatePaise`, the analyzer flags it — remove that reference; `DiagnosisForm` is rewritten in Task 7.)

- [ ] **Step 6: Commit**

```bash
git add apps/technician/lib/features/jobs/presentation/parts_cart.dart apps/technician/lib/features/jobs/presentation/job_detail_screen.dart apps/technician/test/jobs/parts_cart_test.dart apps/technician/test/jobs/job_detail_screen_test.dart
git -c user.name=MohammadKaifSaiyad -c user.email=saiyedkgn6@gmail.com commit -m "feat(technician): server-backed parts section + read-only estimate-sent card; drop the session-only cart"
```
(The `git rm` of `parts_cart.g.dart` is already staged.)

---

### Task 7: App — the diagnosis form sends the complete estimate (parts + category filters + confirm)

**Files:**
- Modify: `apps/technician/lib/features/jobs/presentation/diagnosis_form.dart`
- Modify: `apps/technician/lib/features/jobs/presentation/job_detail_screen.dart` (`JobAction.diagnose` branch)
- Test: `apps/technician/test/jobs/diagnosis_form_test.dart`, `apps/technician/test/jobs/job_detail_screen_test.dart` (ARRIVED case)

**Interfaces:**
- Consumes: Task 6 `PartsSection(detail:, onBusyChanged:)`; Task 4 `TechnicianJobDetailDto`; `catalogRepositoryProvider.issues({String? categoryId})`; `technicianJobRepositoryProvider.diagnose(id, issueId)`; `photosReady`, `PhotoSlot`, `photoSlotLabels`, `requiredPhotoKinds`; `jobDetailProvider(id).notifier.refetch()`.
- Produces: `DiagnosisForm({Key? key, required TechnicianJobDetailDto detail})`; keys `issuePicker`, `issuesRetry`, `diagnosisError`, `submitDiagnosisBtn`, `confirmSendEstimateBtn`, `cancelSendEstimateBtn`.

- [ ] **Step 1: Failing tests** — edit `test/jobs/diagnosis_form_test.dart` (its harness renders `DiagnosisForm` directly with `_FakeCatalogRepo`, `_FakeJobRepo`, `_pump`, `_disposeTree`, `_submitBtn`; Task 5 already gave `_FakeJobRepo` a `job()` override):

  1. Harness changes:
     - `_jobJson` gains `String? categoryId = 'cat-fan'` and its service becomes `'service': {'name': 'Ceiling fan repair', 'requiredSkill': 'FAN', 'categoryId': categoryId},`; `_dto` gains and forwards the same `String? categoryId = 'cat-fan'` parameter.
     - `_FakeCatalogRepo` gains `final List<String?> issuesCategoryArgs = [];` (append `categoryId` at the top of `issues()`) and `List<PartCatalogDto> catalogParts = const [];` (return `Ok(catalogParts)` from `parts()`).
     - `_FakeJobRepo` gains `Completer<void>? addGate;` and:

```dart
  @override
  Future<Result<String>> addPart(String id, {required String partsCatalogId, required int qty}) async {
    if (addGate != null) await addGate!.future;
    return const Ok('l1');
  }
```

     - `_pump` renders `MaterialApp(home: Scaffold(body: SingleChildScrollView(child: DiagnosisForm(detail: TechnicianJobDetailDto(job: job)))))` (the parts section makes the form taller than the 800×600 test viewport).
     - Add helpers (`import 'dart:async';` at the top for `Completer`):

```dart
List<Map<String, dynamic>> _bothServerPhotos() => [
  {'kind': 'DIAGNOSIS_OVERVIEW', 'capturedAt': '2026-09-20T09:30:00.000Z', 'url': 'https://r2.example.com/a'},
  {'kind': 'DIAGNOSIS_CLOSEUP', 'capturedAt': '2026-09-20T09:31:00.000Z', 'url': 'https://r2.example.com/b'},
];

/// Scroll a keyed widget into view, then tap it (the form is taller than the test viewport).
Future<void> _tapKey(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
}

Future<void> _pickIssue(WidgetTester tester) async {
  await _tapKey(tester, const Key('issuePicker'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Fan capacitor failure').last);
  await tester.pumpAndSettle();
}
```

  2. Existing tests keep their assertions; every place that taps `submitDiagnosisBtn` and then expects a diagnose call now does `await _tapKey(tester, const Key('submitDiagnosisBtn')); await tester.pumpAndSettle(); await tester.tap(find.byKey(const Key('confirmSendEstimateBtn'))); await tester.pumpAndSettle();`. Replace other bare `tester.tap(find.byKey(...))` calls on form widgets with `_tapKey` if they report "offset is off-screen".
  3. Add:

```dart
  testWidgets('Submit asks to confirm; "Not yet" sends nothing, "Send estimate" calls diagnose', (tester) async {
    final job = _dto(photos: _bothServerPhotos());
    final jobRepo = _FakeJobRepo(job: job);
    final queue = PhotoUploadQueue(repo: jobRepo, put: ({required url, required key, required bytes}) async {});
    await _pump(tester, job: job, jobRepo: jobRepo, catalogRepo: _FakeCatalogRepo(), queue: queue);
    await _pickIssue(tester);

    await _tapKey(tester, const Key('submitDiagnosisBtn'));
    await tester.pumpAndSettle();
    expect(find.text("Send this estimate to the customer? You won't be able to change parts after this."), findsOneWidget);
    await tester.tap(find.byKey(const Key('cancelSendEstimateBtn')));
    await tester.pumpAndSettle();
    expect(jobRepo.diagnoseCalls, 0);

    await _tapKey(tester, const Key('submitDiagnosisBtn'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmSendEstimateBtn')));
    await tester.pumpAndSettle();
    expect(jobRepo.diagnoseCalls, 1);
    expect(jobRepo.lastDiagnose, (id: 'b1', issueId: 'i1'));
    await _disposeTree(tester);
  });

  testWidgets('issues are fetched for the job category; no category (older backend) → unfiltered', (tester) async {
    final catalog = _FakeCatalogRepo();
    final job = _dto();
    final jobRepo = _FakeJobRepo(job: job);
    await _pump(tester, job: job, jobRepo: jobRepo, catalogRepo: catalog,
        queue: PhotoUploadQueue(repo: jobRepo, put: ({required url, required key, required bytes}) async {}));
    expect(catalog.issuesCategoryArgs, ['cat-fan']);
    await _disposeTree(tester);

    final unfiltered = _FakeCatalogRepo();
    final legacyJob = _dto(categoryId: null);
    final legacyRepo = _FakeJobRepo(job: legacyJob);
    await _pump(tester, job: legacyJob, jobRepo: legacyRepo, catalogRepo: unfiltered,
        queue: PhotoUploadQueue(repo: legacyRepo, put: ({required url, required key, required bytes}) async {}));
    expect(unfiltered.issuesCategoryArgs, [null]);
    await _disposeTree(tester);
  });

  testWidgets('Submit is disabled while a part add is still in flight', (tester) async {
    final job = _dto(photos: _bothServerPhotos());
    final jobRepo = _FakeJobRepo(job: job)..addGate = Completer<void>();
    final catalog = _FakeCatalogRepo()
      ..catalogParts = const [PartCatalogDto(id: 'p1', sku: 'CAP', name: 'Capacitor', categoryId: 'cat-fan', ceilingPricePaise: 15000, status: 'ACTIVE')];
    await _pump(tester, job: job, jobRepo: jobRepo, catalogRepo: catalog,
        queue: PhotoUploadQueue(repo: jobRepo, put: ({required url, required key, required bytes}) async {}));
    await _pickIssue(tester);
    expect(_submitBtn(tester).onPressed, isNotNull);

    await _tapKey(tester, const Key('addPartBtn_p1'));
    await tester.pump();
    expect(_submitBtn(tester).onPressed, isNull);
    expect(find.text('Updating the parts…'), findsOneWidget);

    jobRepo.addGate!.complete();
    await tester.pumpAndSettle();
    expect(_submitBtn(tester).onPressed, isNotNull);
    await _disposeTree(tester);
  });
```

  (`PartCatalogDto` must match `lib/features/jobs/data/catalog_dtos.dart` — fields `id, sku, name, categoryId?, ceilingPricePaise, status`.)

- [ ] **Step 2: Run — expect FAIL**

Run: `cd apps/technician && flutter test test/jobs/diagnosis_form_test.dart`

- [ ] **Step 3: Implement** — in `diagnosis_form.dart`:
  - Imports: add `import 'parts_cart.dart';`.
  - Replace `_issuesProvider` with a family keyed by category:

```dart
/// The job category's issues (null = an older backend without categoryId → unfiltered). The backend still
/// re-validates the issue's category on diagnose (422 surfaced inline).
final _issuesProvider =
    FutureProvider.autoDispose.family<Result<List<DiagnosedIssueDto>>, String?>((ref, categoryId) {
  return ref.read(catalogRepositoryProvider).issues(categoryId: categoryId);
});
```

  - Update the class doc comment to: `/// ARRIVED: the complete estimate — the two evidence photos, the diagnosed issue, and the parts cart. "Submit diagnosis" sends it to the customer and freezes the cart (backend-enforced).`
  - `DiagnosisForm({super.key, required this.detail}); final TechnicianJobDetailDto detail;`
  - State: add `bool _cartBusy = false;`. Replace `_submit` with:

```dart
  Future<void> _confirmAndSubmit() async {
    final issueId = _issueId;
    if (issueId == null || _busy || _cartBusy) return;
    final send = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send estimate?'),
        content: const Text("Send this estimate to the customer? You won't be able to change parts after this."),
        actions: [
          TextButton(key: const Key('cancelSendEstimateBtn'), onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Not yet')),
          FilledButton(key: const Key('confirmSendEstimateBtn'), onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Send estimate')),
        ],
      ),
    );
    if (send != true || !mounted) return;
    await _submit(issueId);
  }

  Future<void> _submit(String issueId) async {
    final jobId = widget.detail.job.id;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(technicianJobRepositoryProvider).diagnose(jobId, issueId);
      if (!mounted) return;
      switch (result) {
        case Ok():
          await ref.read(jobDetailProvider(jobId).notifier).refetch();
        case Failure(message: final m):
          setState(() => _error = m);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
```

  - In `build`: `final job = widget.detail.job;` and `final issuesAsync = ref.watch(_issuesProvider(job.service.categoryId));`. After `_buildIssuePicker(issuesAsync)` insert:

```dart
            const SizedBox(height: 20),
            PartsSection(
              detail: widget.detail,
              onBusyChanged: (busy) {
                if (mounted && busy != _cartBusy) setState(() => _cartBusy = busy);
              },
            ),
```

  - In the submit `ListenableBuilder`: `final enabled = ready && _issueId != null && !_busy && !_cartBusy;`, `onPressed: enabled ? _confirmAndSubmit : null`, and the helper text when disabled becomes `Text(_cartBusy ? 'Updating the parts…' : 'Take both photos and pick the issue to continue.', style: …)` (drop `const`).
  - In `_issuesError`, the retry becomes `onPressed: () => ref.invalidate(_issuesProvider(widget.detail.job.service.categoryId)),`.
  - In `job_detail_screen.dart`: `case JobAction.diagnose:` returns `DiagnosisForm(detail: detail);`. In `job_detail_screen_test.dart` the ARRIVED test also asserts `find.byKey(const Key('partsFilter'))` (give that file's harness a fake catalog override returning empty lists).

- [ ] **Step 4: Full suite, analyze**

Run: `cd apps/technician && flutter test && flutter analyze`
Expected: PASS; `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add apps/technician/lib/features/jobs/presentation/diagnosis_form.dart apps/technician/lib/features/jobs/presentation/job_detail_screen.dart apps/technician/test/jobs/diagnosis_form_test.dart apps/technician/test/jobs/job_detail_screen_test.dart
git -c user.name=MohammadKaifSaiyad -c user.email=saiyedkgn6@gmail.com commit -m "feat(technician): diagnosis form sends the complete estimate — parts cart, category-filtered pickers, confirm before send"
```

---

### Task 8: Docs — B4a note, STATUS, CHANGELOG

**Files:**
- Modify: `docs/designs/2026-06-14-booking-b4a-diagnosis-design.md`, `STATUS.md`, `CHANGELOG.md`

- [ ] **Step 1: B4a design note** — directly under the doc's title block insert:

```markdown
> **Superseded in part (2026-10-01, job estimate integrity):** part add/remove is now **ARRIVED-only** — the
> technician builds the cart during diagnosis and `POST /diagnose` freezes it (`The cart is locked — the
> diagnosis has been submitted`, 409) and snapshots `partCount` + `partsTotalPaise` in the transition
> evidence. DIAGNOSED therefore always shows the customer a final cart. See
> `docs/designs/2026-10-01-job-estimate-integrity-design.md`.
```

- [ ] **Step 2: STATUS.md** — set `_Last updated:` to today; in the Phase paragraph record technician Slice 2 merged (#37); replace the Active task with this work (branch `feature/job-estimate-integrity`, ready for PR, test counts from the final runs); in "Deferred follow-ups" DELETE the "Technician Slice 2 — BLOCK any real-customer pilot" bullet (resolved here) and add a short bullet listing what remains from it: `mine()` active-only (jobs-home payload grows with history), revising an estimate after sending (not supported — customer declines). Add the two new follow-ups found during the dev run: technician-app login with a customer's number silently logs into the customer account (backend `verifyOtp` ignores the requested role for an existing phone — should reject with "this number is registered as a customer"); the "Verification pending" screen never re-checks status (a newly verified technician must log out/in). Update "Next 3 targets".
- [ ] **Step 3: CHANGELOG.md** — add a dated entry at the top: parts during diagnosis + cart frozen at diagnose (with evidence snapshot); catalog parts filter includes generic parts; `GET /technician/jobs/:id` + `service.categoryId`; technician app polls one job, renders the server cart, confirm-before-send, read-only estimate-sent card; session cart removed; customer app unchanged.
- [ ] **Step 4: Commit**

```bash
git add docs/designs/2026-06-14-booking-b4a-diagnosis-design.md STATUS.md CHANGELOG.md
git -c user.name=MohammadKaifSaiyad -c user.email=saiyedkgn6@gmail.com commit -m "docs: job estimate integrity — B4a note, STATUS, CHANGELOG"
```

---

## Self-Review (run at plan time)

- **Spec coverage:** cart ARRIVED-only + locked message + evidence → Task 1; catalog category-or-generic → Task 2; single GET + `categoryId` + detail DTO → Task 3; app DTO/repo → Task 4; controller single GET + 403/404 vanished → Task 5; DIAGNOSED read-only card + server cart + session cart removed → Task 6; diagnosis form parts + category filters + estimate + confirm → Task 7; customer app unchanged (no task; its suite must stay green — run `cd apps/customer && flutter test` once at the final review); docs/rollout → Task 8. Out-of-scope items are only recorded (Task 8).
- **Deviation from spec (naming only):** the composed app DTO is `TechnicianJobDetailDto` (the spec's working name `JobDetail` collides with the existing `JobDetail` Riverpod notifier / `jobDetailProvider`).
- **Type consistency:** `TechnicianJobDetailDto{job, parts}`, `JobPartLineDto{id, partsCatalogId, sku, name, qty, ceilingPricePaise}`, `estimatePaise(job, parts)`, `partsCatalogProvider(categoryId)`, `PartsSection(detail, onBusyChanged)`, `EstimateSentCard(detail)`, `DiagnosisForm(detail)`, `CART_LOCKED_MESSAGE`, `getMyJob`, `toTechnicianJobDetailDto`, `jobIdParams` are used identically across tasks.
- **Review Focus:** all five lines have a pinning test (Tasks 5, 6, 7).
