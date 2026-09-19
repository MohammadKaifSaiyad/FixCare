# apps/technician — FixCare Technician App

Flutter 3.x (**Android + iOS**) + Riverpod + go_router + dio. The technician-side
app: onboarding + KYC, go online/offline, accept jobs, navigate, the arrival &
completion handshakes, 3 mandatory repair photos, wallet + cash debt + trust score.
One shared Dart codebase (`lib/`) runs on both platforms; `android/` and `ios/`
are only the thin per-platform launch shells. Web is not a target — see
[`docs/adrs/ADR-0005-mobile-platforms-android-ios.md`](../../docs/adrs/ADR-0005-mobile-platforms-android-ios.md).

> **Naming:** the technician is the verified person who performs repairs. The
> public/product term and all code/DB use **Technician** (not "Worker"). See
> [`docs/adrs/ADR-0003-worker-to-technician.md`](../../docs/adrs/ADR-0003-worker-to-technician.md).
> Background-job "workers" (BullMQ) are unrelated and keep the "worker" term.

Mobile architecture & conventions: [`docs/03-tech-stack/mobile-stack.md`](../../docs/03-tech-stack/mobile-stack.md)
and the Flutter section of [`docs/05-development/coding-conventions.md`](../../docs/05-development/coding-conventions.md).

## Build timing
Built **Months 7-9** per [`docs/05-development/build-sequence.md`](../../docs/05-development/build-sequence.md),
after the customer app.

## Toolchain note
Uses its own `pubspec.yaml` (Dart/Flutter). **Not** part of the root pnpm
workspace — see [`docs/adrs/ADR-0001-monorepo.md`](../../docs/adrs/ADR-0001-monorepo.md).

## Run commands

Backend must be up first. Start the Docker stack (Postgres+PostGIS, Redis) from
the repo root, then run the API from `apps/backend` (it needs its `.env` loaded):

```bash
docker compose up -d                        # from repo root
cd apps/backend && set -a && source .env && set +a && pnpm dev   # API on :3000
```

Run the app against the local backend. **The base URL differs by platform** because
each reaches the host machine differently:

- **Android emulator** — `10.0.2.2` is the emulator's alias for the host's `localhost`:
  ```bash
  flutter run --dart-define=BASE_URL=http://10.0.2.2:3000
  ```
- **iOS simulator** — reaches the host as `localhost` directly:
  ```bash
  flutter run --dart-define=BASE_URL=http://localhost:3000
  ```
- **Physical device (either platform)** — use the host Mac's LAN IP (same Wi-Fi),
  e.g. `--dart-define=BASE_URL=http://192.168.1.42:3000`.

`--dart-define` is baked in at build time — after changing it, fully restart
`flutter run` (hot reload won't pick it up).

### iOS toolchain (one-time setup)

iOS needs the full **Xcode** (App Store) + **CocoaPods** (`sudo gem install cocoapods`).
Then `flutter doctor` should show iOS ✓, and `open -a Simulator` launches an iPhone.
The debug build's cleartext-HTTP allowance for the dev backend lives in
`ios/Runner/Info-Debug.plist` (scoped to `localhost` only) and is wired to the **Debug
build config only** — Release/Profile use the clean `Info.plist`, so shipped builds are
HTTPS-only. A **simulator is free**; an
Apple Developer account ($99/yr) is only needed to run on a physical iPhone or ship.

**Always build via `flutter run` / `flutter build ios`, never the Xcode ▶ button** —
Xcode-▶ builds miss pod install steps that `flutter` wires in automatically and
routinely fail on stale `build/`/`ios/Pods` state. If you hit a stale-file build
error, recover with `flutter clean && flutter pub get && flutter build ios`.

Generate code (freezed / json_serializable / riverpod_generator):

```bash
dart run build_runner build --delete-conflicting-outputs
```

**Generated files are committed.** The `*.freezed.dart`, `*.g.dart` outputs live
in git (no `.gitignore` exclusion) so the tree builds without a codegen step on
checkout and diffs show generated changes. After editing any `@freezed` DTO or
`@riverpod` provider, re-run build_runner and commit the regenerated files
alongside your source change.

Run tests:

```bash
flutter test
```

Analyze (must be clean before every commit):

```bash
flutter analyze
```

## Technician verification (dev)

A fresh technician signup lands in `status='PENDING'` and stays there until an
admin verifies KYC. While `PENDING`, every `/technician/jobs/*` route 403s —
there is no way to go online or accept jobs. Since the admin dashboard isn't
built yet (it lands after both apps — see
[`docs/adrs/ADR-0004-build-order.md`](../../docs/adrs/ADR-0004-build-order.md)),
local testing flips this directly via SQL against the dev Postgres:

```sql
update "Technician" set status='VERIFIED', skills='{FAN}' where id='<technician-id>';
```

Find the id from the row created at signup (e.g. `select id, phone, status from
"Technician" order by "createdAt" desc limit 1;`). Without this flip, the app's
auth/signup flow works but every jobs-list call will 403 by design — that's the
Golden-Rule-driven verification gate working as intended, not a bug.

## Known toolchain gap — custom_lint / riverpod_lint

As of 2026-09-04, `custom_lint` (all published versions) caps `analyzer <9.0.0`,
while `riverpod_generator ^4.0.9` (pulled in for Riverpod 3.x codegen via
`flutter_riverpod ^3.4.3`) requires `analyzer >=13.0.0`. `custom_lint` and
`riverpod_lint` cannot currently be added to this project's `dev_dependencies`
without downgrading Riverpod, which we've chosen not to do. They are
intentionally omitted from `pubspec.yaml` and from the `analyzer.plugins` list
in `analysis_options.yaml`. Revisit once custom_lint ships an
analyzer-13+-compatible release. (Same gap as `apps/customer` — see its README.)

## Status

**Slice 1, Task 1 complete** — empty project scaffold only (`flutter create`
default counter app), dependency set aligned with `apps/customer` (minus
`google_maps_flutter` + `razorpay_flutter`, unused by this app), iOS deployment
target 15.0, debug-only cleartext ATS/network-security exceptions for the local
dev backend, `flutter analyze` clean. Real code (scaffold backbone, phone-OTP
auth, jobs list/accept) lands in the remaining Slice 1 tasks.
