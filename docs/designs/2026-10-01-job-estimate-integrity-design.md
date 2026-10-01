# Job Estimate Integrity — parts during diagnosis + single-job GET (Design)

**Date:** 2026-10-01
**Branch:** `feature/job-estimate-integrity` (cut from `main` @ `9737679`, technician Slice 2 merged #37)
**Status:** Approved design → ready for plan
**Fixes:** the three "BLOCK any real-customer pilot" follow-ups from technician Slice 2 (STATUS.md)
**Builds on:** B4a diagnosis + cart (`docs/designs/2026-06-14-booking-b4a-diagnosis-design.md`),
technician Slice 2 (`docs/designs/2026-09-20-technician-app-slice2-job-flow-design.md`)

---

## Problem

Today the technician diagnoses (ARRIVED → DIAGNOSED) with an **empty** cart and adds parts only while
DIAGNOSED — the same window in which the customer can approve. Three consequences:

1. **Instant labor-only approval.** A customer who approves right after diagnosis approves before any
   parts exist; the cart then freezes and the repair can't be priced honestly.
2. **Bait-and-switch.** Approval carries no notion of "the estimate I saw": the technician can add parts
   while the customer is looking at the total, so the customer can approve a total they never saw.
3. **Cart lost on restart → duplicate lines.** The technician DTO has no `parts[]`; the app keeps the cart
   in a session-only provider. After an app restart the cart shows empty and re-adding a part creates a
   second backend line, inflating the customer's estimate.

Also: the job-detail screen re-downloads the technician's entire job history (with freshly signed photo
URLs) every 5s, and the issue/parts pickers can't filter by the job's category (no `categoryId`).

## Goal & success criteria

The total a customer approves is exactly the complete estimate they saw. Concretely:
- A customer can only approve/decline a **final** estimate (cart frozen before approval is possible).
- After an app restart the technician sees the real cart from the backend and can remove any line.
- Issue and parts pickers show only the job's category (+ generic parts).
- The job-detail screen fetches one job, not the whole history.

## Decisions (agreed in brainstorming)

1. **Parts are added during diagnosis.** "Submit diagnosis" sends the complete estimate; DIAGNOSED =
   cart frozen + approvable. No new booking state, no schema migration. (Chosen over an explicit "Send
   estimate" step — which needs a new marker + both apps — and over an approve-with-expected-total
   check, which doesn't stop instant labor-only approval.)
2. **Single-job GET** `GET /technician/jobs/:id` returning a detail DTO (job + `parts[]`); `categoryId`
   added to the job DTO. (Chosen over extending `mine()`, which keeps the full-history poll, and over
   also trimming `mine()` to active jobs, which is a separate product decision.)
3. **No "revise after sending" in V1.** If the estimate is wrong the customer declines (visit fee only).
4. **Parts stay optional** — an empty cart is a valid labor-only estimate.

---

## Backend changes

### Cart rules (technician-jobs module)

| Endpoint | Before | After |
|---|---|---|
| `POST /technician/jobs/:id/parts` (201) | state DIAGNOSED | **state ARRIVED** — same guards: assigned technician, catalog price snapshot, category match (generic `categoryId = null` allowed anywhere), qty 1..99, audit `DIAGNOSIS_UPDATED part_added` |
| `DELETE /technician/jobs/:id/parts/:partId` (204) | state DIAGNOSED | **state ARRIVED** — idempotent delete, audit `part_removed` |
| `POST /technician/jobs/:id/diagnose` | ARRIVED → DIAGNOSED | unchanged gate (2 photos + issue category match), **plus** reads the cart inside its transaction and records `partCount` + `partsTotalPaise` (via `sumParts`) in the transition evidence |

- The in-tx optimistic freeze guard (`assertStillInState`) now asserts **ARRIVED**, message
  **`The cart is locked — the diagnosis has been submitted`** (409). A part add racing "Submit
  diagnosis" either commits before the diagnose tx takes the booking row lock or gets this 409.
- Unchanged: approve / decline (the cart is already frozen at DIAGNOSED), parts-needed (non-empty
  approved cart), parts-acquired, photo windows, `computeEstimate`, the customer `BookingDto`.

### Catalog filter (catalog module)

`GET /catalog/parts?categoryId=X` returns parts whose `categoryId` is **X or null** (generic) — matching
`addPart`'s own rule. The only caller is the technician app. `GET /catalog/issues?categoryId=X` stays an
exact match (every issue has a category).

### Single-job GET (technician-jobs module)

`GET /technician/jobs/:id` — `requireAuth` first; VERIFIED technician (`requireTechnician`, else 403
`Verified technician required`); Zod-validated `:id`. Booking missing / soft-deleted → 404
`Job not found`; assigned to another technician → 403 `This job is not assigned to you`. Any state is
readable while assigned (terminal included).

Returns `TechnicianJobDetailDto` = all `TechnicianJobDto` fields **+**
`parts: { id, partsCatalogId, sku, name, qty, ceilingPricePaise }[]` (line `id` is what `DELETE` takes;
integer paise from the snapshot) + active photos with fresh 15-minute signed read URLs (this job only).

`TechnicianJobDto.service` gains **`categoryId`** — so `available()`, `mine()` and the new endpoint all
carry it. Same directional PII as today (full address, masked phone, no customer name). Mapping stays in
`technician-jobs.types.ts`; no cross-module DB queries.

## Technician app changes (`apps/technician`)

- **Data.** `TechnicianJobRepository.job(String id) → Future<Result<JobDetail>>` (bodyless GET).
  `JobDetail` composes the existing `TechnicianJobDto job` + `List<JobPartLine> parts` (freezed), so every
  existing helper/card (`jobActionFor`, `photosReady`, …) keeps taking the plain job DTO.
  `JobServiceDto` gains `categoryId`.
- **Job-detail controller** polls `job(id)` (not `mine()` + find). Keeps: one-shot re-arm, request
  sequencing (late responses dropped), background pause/resume, skip-if-only-photo-URLs-changed.
  A 404/403 → immediate `"This job is no longer assigned to you."` error state, polling stops (replaces the
  3-consecutive-misses rule).
- **Diagnosis form (ARRIVED)** becomes the complete estimate:
  - the 2 diagnosis photo slots (unchanged);
  - issue picker filtered by `job.service.categoryId`;
  - **parts section** (moved here from the DIAGNOSED card): parts picker filtered by `categoryId`
    (category + generic) with qty stepper + Add → `addPart` → refetch; the cart rendered from the
    server's `parts` with Remove → `removePart` → refetch; any Failure (409 cart locked, 422 category)
    shown verbatim in a SnackBar; per-row busy, try/finally, `mounted` guards;
  - **"Customer will see: ₹…"** = `max(0, labor + Σ(ceilingPricePaise × qty) − visitFee)` — exactly the
    backend's DIAGNOSED quote (integer paise);
  - **Submit diagnosis** — enabled when both photos are ready and an issue is picked (parts optional);
    tapping shows a confirm dialog: *"Send this estimate to the customer? You won't be able to change
    parts after this."* → `diagnose`.
- **DIAGNOSED card** → read-only: *"Estimate sent — waiting for the customer to approve or decline"* +
  the frozen part lines + the total.
- **Removed:** the session-only keepAlive `jobCartProvider` — the backend is the single source of truth.
- Unchanged: jobs home (still `mine()`), the photo pipeline, all other cards.

## Customer app

**No code change.** Parts + total render only on the approve/decline card at DIAGNOSED
(`booking_tracking_screen.dart`, `TrackingGate.decision`), which can now only show a frozen, complete
estimate. Its suite must stay green unchanged.

---

## Testing

**Backend (vitest, real Postgres):**
- add/remove part: OK in ARRIVED; 409 in DIAGNOSED and every later state; category mismatch 422; generic
  part allowed; unassigned/foreign tech rejected.
- after diagnose, add → 409 `The cart is locked — the diagnosis has been submitted`.
- diagnose evidence records `partCount` + `partsTotalPaise` matching the cart.
- `GET /technician/jobs/:id`: assigned tech 200 with `parts[]`, `service.categoryId`, photos; other tech
  403; customer 403; unverified tech 403; missing 404.
- `categoryId` present on `available` / `mine` DTOs.
- catalog parts filter returns category + generic parts.
- Update the existing callers that add parts while DIAGNOSED — `tests/bookings/diagnosis.test.ts`,
  `tests/technician-jobs/repair-path.test.ts` (≈15 call sites) — to add parts before diagnose;
  `tests/catalog/parts.test.ts` for the new filter semantics. Full suite + `tsc` green.

**Technician app (flutter, hermetic):** `job(id)` contract (bodyless GET; `parts` + `categoryId` parsed);
controller polls the single GET + 404/403 → no-longer-assigned + ported poll behaviors; diagnosis form
(cart from server, add/remove → repo + refetch, pickers pass `categoryId`, estimate math, submit confirm
dialog, gate); DIAGNOSED read-only card (frozen lines + total); `flutter analyze` 0 issues.

**Customer app:** suite unchanged and green.

**Review gates:** per-task spec + quality review → whole-branch review + golden-rules-auditor +
fraud-vector-checker (estimate / money path) → `/code-review` + one fix wave → run on the simulators.

## Rollout

No schema migration, no new state. Bookings already DIAGNOSED at deploy keep their (frozen) cart — dev
data only today. Docs: add a note to the B4a design (parts now ARRIVED-only, frozen at diagnose); STATUS
(pilot blockers (a)(b)(c) resolved); CHANGELOG. The dev harness (`scripts/dev-drive-booking.sh`) needs no
change (its `diagnose` stage never adds parts).

## Out of scope (tracked)

Revising an estimate after it is sent; `mine()` active-only; `Position.isMocked` arrival signal; R2 presign
settings (checksum, content-type); `NODE_ENV` fail-open; technician-app login with a customer's number
silently logs into the customer account (role mismatch not rejected); the "Verification pending" screen
never re-checks status.
