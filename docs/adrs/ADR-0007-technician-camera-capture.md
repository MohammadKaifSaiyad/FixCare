# ADR-0007 — Camera plugin for technician evidence photos

**Status:** Accepted
**Date:** 2026-09-20
**Context:** Technician app Slice 2 (job flow — the mandatory diagnosis + repair photos)

## Context

Slice 2 requires the technician to capture the mandatory evidence photos (2 diagnosis
+ 3 repair) that gate diagnosis and completion — and, via completion, payment (Golden
Rule 1). `CLAUDE.md` requires an ADR before new tech; a native camera plugin (+ an
image-compression package) is a new dependency, so it gets one.

The `camera-evidence-capture` project skill sets the non-negotiables: camera-only (no
gallery — a documented fraud vector), geotag + timestamp at capture, compress <500KB,
queued retry upload to R2 via presigned URL, per-slot upload state, no PII in logs.

## Decision

Adopt a **camera-only capture path** (`image_picker` with `source: ImageSource.camera`,
or an equivalent camera plugin) plus an **image-compression package** (e.g.
`flutter_image_compress`) to hit the <500KB target. Exact package pins are chosen at
implementation; the constraint is: a live-camera capture API with **no gallery/file
entry point anywhere in the app**.

- Location for the geotag is read at capture time (a location package, camera-time
  one-shot — not background tracking).
- Upload goes through the backend's presigned-PUT + confirm contract; a HEAD verify
  server-side means the evidence must actually exist (not be claimed).

**Pins (recorded at implementation, 2026-09-27):** `image_picker 1.2.3` (called only with
`source: ImageSource.camera`, `maxWidth: 1920`, `imageQuality: 85`), `flutter_image_compress 2.5.1`
(quality ladder, then dimension downscale, to stay under the 500KB budget), `geolocator 14.0.3`
(one-shot reads with a 20s time limit; Android declares FINE + COARSE; approximate-only grants are
refused for arrival and produce no geotag).

**Upload client (added during implementation):** the presigned PUT to R2 goes through a
**bare Dio with no interceptors**, never the app's authenticated client — otherwise the auth
interceptor attaches the technician's JWT to the R2 request (leaking it to a third party, and R2
rejects presigned requests that also carry an `Authorization` header). Guarded by real-transport
tests (`apps/technician/test/jobs/photo_put_test.dart`).

## Alternatives considered

1. **`image_picker` with gallery enabled.** Rejected outright — a gallery import lets a
   technician submit a photo they didn't take on site, defeating the evidence guarantee
   (fraud-defenses). Gallery must be unreachable.
2. **A full custom camera UI (`camera` package).** More control, more surface; not
   needed for V1 — the OS camera via `image_picker(source: camera)` is sufficient and
   simpler. Revisit if in-frame overlays/guides are wanted later.

## Consequences

- **New native deps** + per-platform permission setup: iOS `NSCameraUsageDescription`
  + `NSLocationWhenInUseUsageDescription` in Info.plist; Android `CAMERA` + location
  permissions, runtime-requested. iOS pods installed via `flutter build`/`run` (never
  Xcode ▶ — standing rule).
- **Photos can't be captured against local dev R2.** `DevPhotoStorage` returns a fake
  `https://dev-r2.local/...` presign URL and `confirm` HEAD-verifies the object exists,
  so a genuine device upload fails locally, and diagnose/complete-repair (photo-gated)
  are then blocked past ARRIVED. A **dev-only backend hook** (`POST /dev/photos/
  mark-uploaded`, guarded `NODE_ENV !== production`) calls `DevPhotoStorage.markUploaded`
  so `confirm` succeeds in local testing; the app calls it instead of the real PUT only
  when it sees a `dev-r2.local` URL. Production runs the real PUT-to-R2 path untouched.
- The capture + upload are wrapped behind injectable seams (`CameraService`,
  `PhotoUploadQueue`) so the app's photo logic (slot gating, retry states, confirm-body
  shape, camera-only guard) is fully testable without a real camera or network.
