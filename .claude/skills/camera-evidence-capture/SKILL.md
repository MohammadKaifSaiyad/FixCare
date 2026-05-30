---
name: camera-evidence-capture
description: Use when implementing photo capture/upload in apps/technician (Flutter) — the 3 mandatory repair photos or any evidence photo. Enforces camera-only (gallery disabled), geotag + timestamp at capture, compress <500KB, and queued retrying upload to R2. Security-critical — these photos gate money via the completion handshake.
---

# Camera Evidence Capture (FixCare technician app)

The 3 mandatory repair photos (old part removed, new part packaging, new part
installed) are **evidence that gates payment** (see `keystone-handshake`). They must
be trustworthy, so capture is constrained.

## Non-negotiables (coding-conventions.md Photos + CLAUDE.md)
- **Camera only.** Gallery/file-picker is **disabled** — photos must be taken live,
  not selected. (A gallery import is a fraud vector.)
- **Geotag + timestamp at capture** — embed location + time so the photo is verifiable
  against the job's GPS/arrival handshake.
- **Compress to <500 KB** before upload (low-end devices, Indian data costs).
- **Queued upload with retry** to Cloudflare R2 — do **not** block the UI on upload;
  use an in-app retry queue with backoff (NOT BullMQ — that's backend-only). Surface
  per-photo upload state (pending/uploading/done/failed-retry).
- **The 3 checkpoints are mandatory** — completion cannot proceed until all 3 exist
  (enforced backend-side too).
- **No PII leakage** — don't log image bytes or precise coordinates to analytics.

## Pattern (shape)

```dart
// presentation: capture
final photo = await CameraService.capture();        // camera-only API; no gallery
final tagged = await PhotoTagger.geotagAndTimestamp(photo);   // embed lat/lng + time
final compressed = await ImageCompressor.toUnder500kb(tagged);

// data: queued upload (in-app retry, NOT BullMQ)
uploadQueue.enqueue(R2Upload(checkpoint: Checkpoint.oldPartRemoved, file: compressed));
// queue retries with backoff; UI observes upload state per checkpoint
```

## Process
1. Use a camera-only capture path; ensure no gallery entry point exists in the app.
2. Geotag + timestamp, then compress <500KB.
3. Enqueue to the in-app retry upload queue (R2 via presigned URL from backend).
4. Block completion until all 3 checkpoints uploaded; show clear per-photo state.
5. Run `flutter-widget-reviewer` + `fraud-vector-checker` before merge.

> Reference: `docs/05-development/coding-conventions.md` (Photos), `CLAUDE.md` (3 mandatory photos, Keystone Interactions), `docs/02-product/fraud-defenses.md`.
