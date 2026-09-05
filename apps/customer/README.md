# apps/customer — FixCare Customer App

Flutter 3.x (**Android + iOS**) + Riverpod + go_router + dio. Customer books →
tracks → pays → rates from mobile. One shared Dart codebase (`lib/`) runs on both
platforms; `android/` and `ios/` are only the thin per-platform launch shells.
Web is not a target — see [`docs/adrs/ADR-0005-mobile-platforms-android-ios.md`](../../docs/adrs/ADR-0005-mobile-platforms-android-ios.md).

Mobile architecture & conventions: [`docs/03-tech-stack/mobile-stack.md`](../../docs/03-tech-stack/mobile-stack.md)
and the Flutter section of [`docs/05-development/coding-conventions.md`](../../docs/05-development/coding-conventions.md).

## Build timing
Built **Months 5-6** per [`docs/05-development/build-sequence.md`](../../docs/05-development/build-sequence.md).
Built before the technician app to validate customer demand before investing in
supply-side tooling.

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

## Known toolchain gap — custom_lint / riverpod_lint

As of 2026-09-04, `custom_lint` (all published versions) caps `analyzer <9.0.0`,
while `riverpod_generator ^4.0.9` (pulled in for Riverpod 3.x codegen via
`flutter_riverpod ^3.4.3`) requires `analyzer >=13.0.0`. `custom_lint` and
`riverpod_lint` cannot currently be added to this project's `dev_dependencies`
without downgrading Riverpod, which we've chosen not to do. They are
intentionally omitted from `pubspec.yaml` and from the `analyzer.plugins` list
in `analysis_options.yaml`. Revisit once custom_lint ships an
analyzer-13+-compatible release.

## Auth flow (Slice 1)

The first slice ships the full phone-OTP auth backbone every later slice rides on:

- **Splash / token gate** — on launch, `AuthController.build()` reads the access
  token from secure storage. Present → authenticated; absent → phone entry. While
  reading, the router shows the splash (`AsyncLoading`).
- **Phone entry** → `POST /auth/otp/send`. Validates a 10-digit Indian mobile
  (`^[6-9]\d{9}$`) before the call.
- **OTP entry** → `POST /auth/otp/verify` → stores the `{access, refresh}` pair,
  flips the session to authenticated, lands on the home stub. On **dev/debug**
  builds the backend echoes the code as `devOtp`; the screen shows and autofills
  it. Release builds never see it. Wrong code → inline error; resend → re-sends
  (429 → "try again shortly").
- **Silent refresh** — a dio auth interceptor attaches the bearer token and, on a
  401, performs a **single-flight** `POST /auth/refresh` (N concurrent 401s share
  one refresh), stores the rotated pair, and retries. Refresh failure clears the
  tokens and drops to phone entry. The interceptor is the ONLY place a refresh
  happens; refresh/retry run through a bare, interceptor-free dio (no recursion).
- **Logout** → best-effort `POST /auth/logout` + local token clear → phone entry.

Try it end-to-end: start the backend (above), run the app, enter any 10-digit
number, and use the dev code shown on the OTP screen.

## Google Maps API key (address pin-drop picker)

The address form's map (`AddressMapPicker`) is **gated by `Env.mapsEnabled`**
(a `--dart-define=MAPS_ENABLED=true` flag, default `false`). Without it, the
form renders a bordered placeholder instead of the live map — the rest of the
app builds, analyzes, and tests with **no API key present**. Only enabling the
live map at runtime needs a key. To turn it on:

1. **Get a key.** In the [Google Cloud Console](https://console.cloud.google.com/),
   create (or reuse) a project, enable **Maps SDK for Android** and
   **Maps SDK for iOS**, then create an API key under **APIs & Services → Credentials**.
2. **Restrict it.** Edit the key: set an **Android app restriction** (this app's
   package `in.fixcare.fixcare_customer` + your debug/release SHA-1 fingerprints,
   from `keytool -list -v -keystore ~/.android/debug.keystore`), and/or an
   **iOS app restriction** (bundle id `in.fixcare.fixcare_customer`, or whatever
   `ios/Runner.xcodeproj` currently has set). Also restrict the **API list** to
   just the two Maps SDKs above. Never use an unrestricted key.
3. **Wire it into the Android build** — export it as an environment variable
   before building/running (never hardcode it in `AndroidManifest.xml` or
   `build.gradle.kts`, both of which read it from the environment):
   ```bash
   export MAPS_API_KEY=your-real-key-here
   ```
   The manifest placeholder `${MAPS_API_KEY}` (in
   `android/app/src/main/AndroidManifest.xml`) is resolved from
   `manifestPlaceholders["MAPS_API_KEY"]` in `android/app/build.gradle.kts`,
   which reads the same env var (defaults to `""` when unset, so the build
   never fails without a key).
4. **Wire it into iOS** — same env var, but resolved **at build time**, not
   read from the process environment at launch. `ProcessInfo.processInfo
   .environment` only sees vars for processes Xcode itself launches (a
   debug run from a scheme) — a real device install, TestFlight, or a
   release build never has that env var, so that approach silently never
   gets the key outside of Xcode-launched debug runs. Instead the key flows:
   the `MAPS_API_KEY` env var (exported before `flutter build ios` /
   `xcodebuild`, same as step 3) →  the `MAPS_API_KEY` **user-defined Xcode
   build setting** on the Runner target (`ios/Runner.xcodeproj/project.pbxproj`,
   present on Debug/Profile/Release, defaults to empty when the env var is
   unset) → baked into `Info.plist` (and the debug-only `Info-Debug.plist`,
   kept in sync) as `<key>MapsApiKey</key><string>$(MAPS_API_KEY)</string>` →
   read back at **runtime** in `ios/Runner/AppDelegate.swift` via
   `Bundle.main.object(forInfoDictionaryKey: "MapsApiKey")` and passed to
   `GMSServices.provideAPIKey(...)` only when non-empty. This is what
   actually reaches a real installed build. Exporting the env var before any
   `xcodebuild`/`flutter build ios`/`flutter run` invocation (including from
   Xcode itself, which inherits your shell's exported vars when launched
   from a terminal, or via the scheme's **Run → Arguments → Environment
   Variables** if launched from Xcode's UI directly) is sufficient — no
   further Xcode configuration is needed.
5. **Verify the map renders.** With the key exported (Android) or set in the
   scheme (iOS), run the app with the Dart flag flipped on:
   ```bash
   flutter run --dart-define=MAPS_ENABLED=true --dart-define=BASE_URL=http://10.0.2.2:3000
   ```
   Open Add/Edit address — the map should render centered on the address (or a
   Vadodara default) instead of the placeholder text, and tapping it should
   drop/move a pin and update the saved lat/lng. Without `MAPS_ENABLED=true`
   (or without a key wired per steps 3-4), the placeholder shows instead —
   this is the expected, safe default for anyone building the app without a key.

## Status

**Slice 1 complete** — project scaffold + full phone-OTP auth flow
(splash/token-gate → phone → OTP → home stub) with transparent token refresh.
State via Riverpod `@riverpod` codegen; navigation via go_router with a
session-keyed redirect; typed `Result<T>` end to end (no raw dio/JSON above the
data layer). 15 tests (repository, single-flight interceptor, token-gate router,
OTP widget flow); `flutter analyze` clean.

Next slices: home content, profile, addresses/serviceability, catalog browse,
booking creation + status polling, payment UI, disputes UI, camera evidence.
