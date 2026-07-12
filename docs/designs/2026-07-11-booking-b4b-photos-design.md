# Booking B4b — R2 Photo Evidence + 2 Mandatory Diagnosis Photos — Design

**Date:** 2026-07-11
**Branch:** `feature/booking-b4b-photos`
**Status:** Approved (brainstorming) → ready for `writing-plans`
**Depends on:** B4a (merged, PR #14), shared OTP primitive (merged, PR #15 — not used here, but B5 needs both)

---

## Problem

B4a shipped diagnosis + parts cart but deferred its photo evidence. The product docs mandate
**2 diagnosis photos** (appliance overview + fault close-up — `core-flow.md:87-89`) as the
evidence that justifies the estimate the customer approves, and **B5's completion handshake
(keystone #2) requires 3 repair photos** — which need the same storage pipeline. Nothing in the
backend can store a photo today.

## Goal

Build the photo-evidence pipeline (Cloudflare R2, presigned direct uploads) and wire the 2
mandatory diagnosis photos as a hard gate on `ARRIVED→DIAGNOSED`. B5 must be able to add its 3
repair photos by **extending one enum** — no new infrastructure.

Non-goals: server-side image processing (compression is app-side, <500KB — user decision
2026-07-11), malware scanning (V2), the Flutter capture UI (camera-only, gallery blocked —
re-confirmed 2026-07-11; app slice builds it), dispute/ops photo dashboards.

## Decisions (from brainstorming, 2026-07-11)

1. **Named slots + replace:** `PhotoKind` enum (`DIAGNOSIS_OVERVIEW`, `DIAGNOSIS_CLOSEUP`; B5
   appends `REPAIR_OLD_PART`, `REPAIR_NEW_PACKAGING`, `REPAIR_INSTALLED`). One **active** photo
   per (booking, kind); a retake soft-deletes the old row and inserts the new one in a transaction
   — the evidence trail is never destroyed. Gate = both named slots have an active row.
2. **HEAD-verified uploads:** the confirm endpoint calls `objectExists(key)` before creating the
   row — evidence must be real, not claimed (Golden Rule 1). 422 if the object isn't in R2.
3. **Customer sees photos now:** `GET /me/bookings/:id` returns `photos: [{kind, capturedAt, url}]`
   with **15-minute signed GET URLs** (the photos justify the estimate being approved; exercised
   via Bruno until the customer app lands).
4. **Presign policy:** `image/jpeg` only, 1 MB cap (app compresses to <500KB; 1MB is headroom),
   24h upload-URL expiry. Content-Type pinned server-side — the client does not choose.
5. **Geotag optional:** `geotagLat/Lng` nullable (indoor GPS reality on budget Androids);
   `capturedAt` required; audit records `hasGeotag` so fraud review can weight absence.
6. **Placement:** photo endpoints live in the **technician-jobs module** (they are technician
   actions on an assigned job, like arrive/diagnose); the R2 wrapper lives in
   `shared/third-party/` per the third-party-wrapper skill. No new module, no generic
   `/uploads` endpoint (YAGNI — one upload consumer in V1).

## Schema

```prisma
enum PhotoKind {
  DIAGNOSIS_OVERVIEW
  DIAGNOSIS_CLOSEUP
  // B5 appends: REPAIR_OLD_PART, REPAIR_NEW_PACKAGING, REPAIR_INSTALLED
}

model PhotoEvidence {
  id         String     @id @default(cuid())
  bookingId  String
  booking    Booking    @relation(fields: [bookingId], references: [id])
  kind       PhotoKind
  r2Key      String     // jobs/{bookingId}/{kind}-{cuid}.jpg — no PII in the key
  geotagLat  Float?
  geotagLng  Float?
  capturedAt DateTime   // client-claimed capture time
  deletedAt  DateTime?  // soft-delete = replaced by a retake; NEVER hard-delete evidence
  createdAt  DateTime   @default(now())
  updatedAt  DateTime   @updatedAt

  @@index([bookingId, kind])
}
```

Plus `Booking.photos PhotoEvidence[]` back-relation and `PHOTO_UPLOADED` added to `AuditAction`.
One additive migration; applied to dev and `fixcare_test` (test DB comes from migrations).
"One active per (booking, kind)" is enforced in the service transaction (soft-delete-then-create),
not by a DB unique constraint (deletedAt-aware partial uniques are Prisma-awkward; the tx is the
single writer).

## R2 wrapper (`shared/third-party/r2-storage.ts` — third-party-wrapper skill)

```ts
export interface PhotoStorage {
  presignUpload(key: string): Promise<{ url: string; expiresAt: Date }>; // PUT, image/jpeg, ≤1MB, 24h
  objectExists(key: string): Promise<boolean>;                            // HEAD
  presignRead(key: string): Promise<string>;                              // GET, 15-min expiry
}
```

- `DevPhotoStorage` — in-memory `Set<string>` of "uploaded" keys + deterministic fake URLs;
  exposes a test hook to mark a key uploaded. Used whenever `NODE_ENV !== 'production'` or R2 env
  is absent.
- `R2PhotoStorage` — `@aws-sdk/client-s3` + `@aws-sdk/s3-request-presigner` against the R2
  endpoint (`https://<accountid>.r2.cloudflarestorage.com`). SDK errors wrapped in a typed error;
  raw SDK errors never leak. Inert until R2 credentials are provisioned (same posture as MSG91).
- `makePhotoStorage()` factory; module-level singleton in the service (same as `makeOtpSender()`).
- Config: `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET` — all
  `.optional()` in the Zod config schema + stubbed in `.env.example`. Secrets env-only.
- New deps: `@aws-sdk/client-s3`, `@aws-sdk/s3-request-presigner` (S3-compatible SDK is the
  documented approach — `backend-stack.md:343`; no new ADR needed, R2 is in the locked stack).

## Endpoints (technician-jobs module)

Both gated by `requireTechnician` + `ownAssignedBookingOrThrow(techId, id, 'ARRIVED')` — photos
are taken during the on-site diagnosis window.

1. **`POST /technician/jobs/:id/photos/sign`** — body `{kind: PhotoKind}` (Zod-validated, strict).
   Generates `key = jobs/{bookingId}/{kind}-{cuid}.jpg`, returns `{url, key, expiresAt}`.
2. **`POST /technician/jobs/:id/photos`** — body `{kind, key, capturedAt, geotagLat?, geotagLng?}`
   (lat/lng both-or-neither, same idiom as addresses). Checks:
   - `key` starts with `jobs/{bookingId}/` → else 422 (no cross-booking confirms);
   - `objectExists(key)` → else 422 `'upload not found'`;
   - tx: soft-delete any active row for `(bookingId, kind)` → create the new row →
     `PHOTO_UPLOADED` audit `{bookingId, kind, hasGeotag, replaced}` (no coords, no key with
     credentials — Rule 7).
   Returns the photo summary `{id, kind, capturedAt}`.

## The diagnosis gate

`diagnoseJob` (`technician-jobs.service.ts`) gains, inside its existing transaction: an active-row
check for BOTH diagnosis kinds → missing ⇒ 422 `'2 diagnosis photos required (overview + close-up)'`.
Photo ids are passed as `evidence` to `transitionBooking` (which already writes them into the
`BOOKING_STATE_CHANGED` audit). Reading inside the tx uses the same freeze idiom as B4a's cart —
a photo cannot be soft-deleted-out from under a concurrent diagnose.

## DTOs

- `BookingDto` (customer) `+= photos: [{kind, capturedAt, url}]` — `url` from `presignRead`
  (15-min). Active rows only, owner-scoped as today.
- `TechnicianJobDto` gets the same block for the assigned technician.
- No raw `r2Key` in any DTO.

## Testing (Dev wrapper only — no network)

- otp-sender-style: the module singleton resolves to `DevPhotoStorage` in test env.
- New tests: sign happy path + Zod 400s + ownership 404 + wrong-state 409; confirm happy path,
  not-uploaded 422, cross-booking-key 422, retake-replaces (old row soft-deleted, audit
  `replaced: true`), both-or-neither geotag 400; diagnose without photos 422, with photos → 200 +
  evidence in audit; customer DTO carries signed URLs.
- `resetDb` TRUNCATE list += `"PhotoEvidence"`.
- Existing `diagnosis.test.ts` (+ any fixture reaching DIAGNOSED) gains a `seedDiagnosisPhotos()`
  precondition — the ONE documented change to existing tests, with a rationale comment.

## Golden Rules check

- **Rule 1 (money needs evidence):** the photos are the evidence for the DIAGNOSED state whose
  estimate the customer approves; the gate makes them non-optional.
- **Rule 2:** untouched — approve/decline stay customer-side.
- **Rule 5:** `PHOTO_UPLOADED` + state-change audits written in-transaction.
- **Rule 7:** no PII in keys, logs, or audit; no coords in audit (only `hasGeotag`); no
  credentialed URLs logged.
- **Fraud defenses §2/§11:** phantom-parts/absent-visit vectors — photos geotag+timestamped where
  hardware allows, HEAD-verified, replace-not-delete, hard gate on the state machine.

## B5 readiness

B5 adds `REPAIR_*` values to `PhotoKind`, reuses sign/confirm verbatim (its window gates on the
post-approval states), and its completion gate counts the 3 repair slots the same way the
diagnosis gate counts 2. No new storage code.
