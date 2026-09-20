# Technician App Slice 2 — Drive a Job (Design)

**Date:** 2026-09-20
**Branch:** `feature/technician-app-slice2-job-flow`
**Status:** Approved design → ready for plan
**ADR:** `docs/adrs/ADR-0007-technician-camera-capture.md` (camera plugin)
**Builds on:** technician Slice 1 (merged #35) — `TechnicianJobDto` + repo + jobs home.

---

## Goal

Let a VERIFIED technician drive an **accepted** job through its whole lifecycle from a
state-driven **job-detail screen**: en-route → arrive → diagnose (+2 photos) → parts →
repair (+3 photos) → confirm-completion → confirm-cash. This closes the loop with the
customer app: the two apps together run the full booking end-to-end (both keystone
handshakes + cash payment) without the `dev-drive-booking.sh` harness.

## Non-goals (deliberate)

- **No background-location tracking** (the "technician on the way" live map). `arrive`
  uses a one-shot foreground location; Android background location is a known-hard V1
  risk, out of scope.
- **UPI payment** is entirely customer-side; the technician only handles the **cash**
  receipt code (`confirm-cash`).
- **No backend change** for the job flow. One dev-only backend hook is added for local
  photo testing (guarded to non-production) — dev tooling, not shipped behavior.
- The technician's `mine` DTO carries no parts array; the app tracks added parts
  **client-side** (no DTO extension this slice).

---

## Backend contract (verified against `apps/backend/`)

Every route below is `/technician/jobs/:id/...`, `requireAuth` + technician role +
VERIFIED gate; ownership-checked (foreign/wrong id → `Job not found` / `not assigned`).
Bodyless unless noted. Valid-from states + the exact transition:

| Endpoint | Body | From → To | Notes / gate errors |
|---|---|---|---|
| `POST …/en-route` | — | ACCEPTED → EN_ROUTE | `Job is not in ACCEPTED` |
| `POST …/arrive` | `{lat, lng}` | EN_ROUTE (no state change) | Records GPS; geofence 422 `You are too far from the customer location`; **mints** `{arrivalCode, withinGeofence?}` the tech shows the customer. The CUSTOMER flips EN_ROUTE→ARRIVED via `/me/bookings/:id/confirm-arrival {code}`. |
| `POST …/diagnose` | `{diagnosedIssueId}` | ARRIVED → DIAGNOSED | Issue must exist + category-match (`That issue does not apply to this service`); **2-photo gate** `2 diagnosis photos required (overview + close-up)` |
| `POST …/parts` (201) | `{partsCatalogId, qty≤99}` | DIAGNOSED | catalog-priced snapshot; cart-freeze guard after approve |
| `DELETE …/parts/:partId` (204) | — | DIAGNOSED | idempotent |
| `POST …/parts-needed` | — | CUSTOMER_APPROVED → PARTS_REQUESTED | requires non-empty cart |
| `POST …/parts-acquired` | — | PARTS_REQUESTED → PARTS_ACQUIRED | |
| `POST …/start-repair` | — | CUSTOMER_APPROVED\|PARTS_ACQUIRED → REPAIR_IN_PROGRESS | opens repair-photo window |
| `POST …/complete-repair` | — | REPAIR_IN_PROGRESS → REPAIR_COMPLETE | **3-photo gate** `3 repair photos required (old part removed, new packaging, installed)` |
| `POST …/photos/sign` | `{kind, contentLengthBytes≤1MB}` | per PHOTO_WINDOW[kind] | → `{url, key, expiresAt}` |
| `POST …/photos` (201) | `{kind, key, capturedAt, geotagLat?, geotagLng?}` | per PHOTO_WINDOW[kind] | HEAD-verifies object exists (`Upload not found — PUT the photo to the signed URL first`); geotags both-or-neither |
| `POST …/confirm-completion` | `{code}` (len 6) | REPAIR_COMPLETE → CUSTOMER_CONFIRMED | customer's completion OTP; `No active code…` (409) / `Invalid or expired completion code` (401); zero-payable chain → PAYMENT_RECEIVED |
| `POST …/confirm-cash` | `{code}` (len 6) | CUSTOMER_CONFIRMED\|DECLINED_BY_CUSTOMER → PAYMENT_RECEIVED | customer's cash receipt OTP; → `{id, state, cashDebtPaise}`; cash-limit 422s (`Outstanding cash debt limit reached…` / `Daily cash collection limit reached…`) |

**Photo kinds:** diagnosis = `DIAGNOSIS_OVERVIEW`, `DIAGNOSIS_CLOSEUP` (window ARRIVED);
repair = `REPAIR_OLD_PART`, `REPAIR_NEW_PACKAGING`, `REPAIR_INSTALLED` (window
REPAIR_IN_PROGRESS).

**Two-sided handshakes:** technician `arrive` mints the arrival code → customer confirms
(customer drives ARRIVED). Technician `confirm-completion`/`confirm-cash` *enters the
customer's* code (customer minted it via `request-completion-otp`/`pay-cash`). No single
party both mints and consumes (Golden Rule 2).

**No single-job GET.** Full job detail (incl. photos, 15-min signed read URLs) comes only
from `GET /technician/jobs/mine`. The DTO has NO parts array (only the diagnosed-issue
snapshot + labor/visitFee); parts are tracked app-side.

**Catalog (shared, any authed user):** `GET /catalog/issues?categoryId=` and
`GET /catalog/parts?categoryId=` supply the diagnose issue-picker and add-part list.

**Local photo dev affordance:** dev `DevPhotoStorage` returns a fake `dev-r2.local`
presign URL and `confirm` HEAD-verifies existence → real device uploads fail locally.
A dev-only backend route `POST /dev/photos/mark-uploaded {key}` (guarded
`NODE_ENV !== production`) calls `markUploaded` so `confirm` succeeds in local testing;
the app calls it (instead of the real PUT) only when it sees a `dev-r2.local` URL.

---

## Architecture

### State → action model — `job_action.dart` (pure)
`JobAction jobActionFor(TechnicianJobDto)` maps `booking.state` → the technician's next
action; `List<String> requiredPhotoKinds(String state)` gives the slots for the current
photo window. Flutter-free, exhaustively unit-tested (mirrors the customer's `phaseFor`).

| state | JobAction (card) |
|---|---|
| ACCEPTED | enRoute — "I'm on my way" |
| EN_ROUTE | arrive — "I've arrived" → show arrival code, "waiting for customer to confirm" |
| ARRIVED | diagnose — 2 photos + issue picker + parts + "Submit diagnosis" |
| DIAGNOSED | waitingApproval — read-only |
| CUSTOMER_APPROVED | startRepair (or partsNeeded if cart non-empty) |
| PARTS_REQUESTED | partsAcquired |
| PARTS_ACQUIRED | startRepair |
| REPAIR_IN_PROGRESS | completeRepair — 3 photos + "Complete repair" |
| REPAIR_COMPLETE | confirmCompletion — enter customer's OTP |
| CUSTOMER_CONFIRMED / DECLINED_BY_CUSTOMER | confirmCash — enter customer's receipt OTP |
| PAYMENT_RECEIVED / CLOSED / CANCELLED_* | terminal summary |
| (unknown) | safe fallback (read-only summary) |

### Job-detail controller
`@riverpod` family `JobDetail(bookingId)` — loads the job from `mine`, **adaptive-polls**
(5s while active, stops at terminal, keep-last-good on a blip, `refetch()`), reusing the
customer Slice-4 controller shape. The technician screen must observe customer-side
transitions (confirm-arrival, approve, request-otp), hence the poll. After a technician
action succeeds → immediate `refetch()`.

### Repository — extend `TechnicianJobRepository`
Add: `enRoute`, `arrive(id,{lat,lng})→ArriveResultDto`, `diagnose(id,issueId)`,
`addPart(id,{partsCatalogId,qty})`, `removePart(id,partId)`, `partsNeeded`,
`partsAcquired`, `startRepair`, `completeRepair`, `confirmCompletion(id,code)`,
`confirmCash(id,code)→{id,state,cashDebtPaise}`, `signPhoto(id,{kind,contentLengthBytes})
→PhotoSignDto`, `confirmPhoto(id,{kind,key,capturedAt,geotagLat?,geotagLng?})`. All →
`Result`; errors surface the exact backend messages (never swallowed).

New thin `CatalogRepository` (issues + parts lists) + DTOs.

### Photo pipeline (camera-evidence conventions)
Per slot: **camera-only capture** (no gallery — fraud vector) → **geotag + timestamp at
capture** → **compress <500KB** → **presigned PUT** → **confirm** (HEAD-verified).
An in-app `PhotoUploadQueue` with backoff retry drains uploads off the UI thread; the UI
shows per-slot state (pending/uploading/done/failed-retry). Gate buttons ("Submit
diagnosis", "Complete repair") stay disabled until all required slots for the phase are
`done` (backend enforces too). Retake = re-capture (backend soft-deletes + replaces).
Capture + upload behind injectable seams (`CameraService`, `PhotoUploadQueue`) for
hermetic tests. New camera dep → ADR-0007.

### App-side parts tracking
The diagnose screen keeps the parts it adds in local controller state (add returns a
line id; remove by id) and shows an **indicative estimate** (labor + Σ parts − visit-fee
credit) for the tech's reference. The backend is the source of truth at approval.

---

## Data flow

Jobs home (`mine`) → tap job → `JobDetailScreen(bookingId)` → controller loads + polls →
`jobActionFor` picks the card → technician acts (gate endpoint) → refetch advances the
card. Photo actions run through the queue; customer-side transitions arrive via the poll.

## Error handling

Never swallow a `Failure`. Geofence 422 → inline on arrive (retry closer). Photo-gate
422 → shouldn't fire (button gated) but SnackBar if it does. confirm-completion/cash
409/401 → inline on the code field. cash-limit 422 → surfaced verbatim (tell customer to
pay UPI). 409 stale-state → SnackBar + refetch (self-heals as the poll reconciles).
Per-card busy flags prevent double-fire.

---

## Files

**ADR:** `docs/adrs/ADR-0007-technician-camera-capture.md`.

**Data (`lib/features/jobs/data/`):**
- `technician_job_repository.dart` — extend (the ~13 methods).
- `technician_job_dtos.dart` — add `ArriveResultDto`, `PhotoSignDto`, `PhotoConfirmDto`.
- `catalog_repository.dart` + `catalog_dtos.dart` — new (`issues`/`parts`).

**Presentation (`lib/features/jobs/presentation/`):**
- `job_action.dart` — new, pure (`JobAction`, `jobActionFor`, `requiredPhotoKinds`).
- `job_detail_controller.dart` — new `@riverpod` family (adaptive poll).
- `job_detail_screen.dart` — new; state-driven, split into phase-card widgets
  (`_EnRouteCard`/`_ArriveCard`/`_DiagnoseCard`/`_RepairCard`/`_CompletionCard`/
  `_CashCard`/`_TerminalSummary`).
- `diagnosis_form.dart` — new (2 photo slots + issue picker + parts + estimate + submit).
- `photo_capture.dart` — new (`CameraService`, `PhotoUploadQueue`,
  `photoUploadQueueProvider`, `_PhotoSlot` widget).

**Native config:** `pubspec.yaml` (camera + compression + location deps); iOS Info.plist
(`NSCameraUsageDescription`, `NSLocationWhenInUseUsageDescription`); Android manifest
(`CAMERA` + location, runtime-requested).

**Backend dev tooling (separate, small):** `POST /dev/photos/mark-uploaded {key}`,
guarded `NODE_ENV !== production`.

**Reuse:** Slice-1 `TechnicianJobDto`/jobs home; customer Slice-4 polling-controller
shape; `rupees`, theme, `Result` idiom.

---

## Testing strategy

Bar: `flutter analyze` 0 issues; hermetic (faked transport/camera/upload); TDD. Final
review also runs the domain agents the camera skill names: `flutter-widget-reviewer` +
`fraud-vector-checker`.

1. **`job_action.dart` — pure unit tests.** Table over every state → `JobAction` +
   `requiredPhotoKinds`; unknown → safe fallback. Exhaustive.
2. **Repository — contract-guarded** (`FullHttpRequestMatcher(needsExactBody: true)`):
   each method's path + body (bodyless vs `{lat,lng}`/`{diagnosedIssueId}`/`{partsCatalogId,
   qty}`/`{code}`/photo bodies); error mapping surfaces exact messages (geofence,
   photo-gate, no-code, invalid-code, cash-limit, stale-state); arrive/confirm-cash parse
   their DTOs.
3. **Photo pipeline — faked seams:** camera returns a fixed image → queue enqueues with
   the right kind; sign→PUT→confirm sends the correct confirm body (capturedAt, geotag
   both-or-neither); per-slot state pending→uploading→done; failed PUT → failed-retry →
   retry succeeds. **Camera-only guard test** (no gallery path exists) — a fraud
   regression guard.
4. **Widget tests — `ProviderScope` overrides:** each state renders the right card;
   arrive shows the arrival code (`Key('arrivalCode')`); "Submit diagnosis"/"Complete
   repair" disabled until required photos `done`; confirm-completion/cash code entry
   submits the customer's code with the right args; action success → refetch advances;
   409 → SnackBar + refetch; geofence 422 → inline; busy flag blocks double-tap.
5. **Controller — `fakeAsync`:** poll advances (mine re-fetched), stops at terminal,
   keep-last-good on a blip, refetch after an action.

**Deferred follow-up (noted, not built):** a real-backend contract-smoke of the full
technician flow once R2 is wired (photo `confirm` can't run against dev R2); local live
testing uses the dev `mark-uploaded` hook.

---

## Carry-forwards honored

- Camera-only, geotag+timestamp, <500KB, queued retry upload, per-slot state, photos
  gate completion — the `camera-evidence-capture` skill's non-negotiables, in full.
- No PII in logs (no image bytes, no precise coords).
- Directional masking respected (the DTO already gives masked phone / no name / full
  address); the app requests nothing more.
- Two-sided handshakes preserved: the technician mints the arrival code + enters the
  customer's completion/cash codes; never both sides of one handshake.
- App sends only each endpoint's allowed body; catalog-priced parts (no client pricing).
