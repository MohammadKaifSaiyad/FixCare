# Customer App — Slice 1: Scaffold + Phone-OTP Auth (design)

**Date:** 2026-09-04 · **Branch:** `feature/customer-app-skeleton-auth` · **Status:** approved
**App:** `apps/customer` (Flutter, Android-first V1). First slice of the customer app; establishes the
architecture (Riverpod codegen + go_router + dio + secure-storage) and the auth/token backbone every
later slice rides on. Screen designs: `Claude Design/fixcare-customer-app-design`. API contract +
screen map: `docs/designs/2026-09-04-customer-app-screen-context.md`.

## Goal

A homeowner opens the app, logs in with a phone OTP, and lands on a (stub) home — with the token
lifecycle (15-min access / 30-day refresh + rotation + reuse-detection) handled transparently. The
smallest slice that proves the whole app→backend stack end to end.

## Scope decisions (settled)

| Decision | Choice |
|---|---|
| State mgmt | **Riverpod 2.x with `@riverpod` codegen** (build_runner) — the app-wide standard for every provider. |
| Dev wiring | Base URL via **`--dart-define=BASE_URL`** (default `http://10.0.2.2:3000`, the Android-emulator route to host localhost). On **dev/debug** builds the OTP screen surfaces the backend's `devOtp` + one-tap autofill; release builds never do. |
| Token refresh | **Dio auth interceptor with single-flight refresh**: attach access token to every request; on 401, refresh ONCE via `/auth/refresh` (concurrent 401s share the one refresh), store the rotated pair, retry; on refresh failure → clear tokens → phone entry. |
| Slice boundary | Scaffold + full auth flow (splash/token-gate → phone → OTP → **home stub**). Home content, profile, addresses, bookings are later slices. |

## Project structure (feature-first, per the flutter-feature skill)

```
apps/customer/
  pubspec.yaml                 // deps below
  README.md                    // run commands
  lib/
    main.dart                  // ProviderScope + FixCareApp (MaterialApp.router)
    core/
      env.dart                 // Env.baseUrl (--dart-define), Env.isDev (!kReleaseMode)
      theme.dart               // Material3 theme: primary #C2521B, success #1D6B4F, Outfit font
      result.dart             // sealed Result<T> = Ok<T> | Failure(kind, message); FailureKind enum
      network/
        dio_client.dart        // dioProvider — BaseOptions(baseUrl), JSON, timeouts
        auth_interceptor.dart  // token attach + single-flight 401→refresh→retry
      storage/
        token_store.dart       // TokenStore (flutter_secure_storage): read/write/clear {access,refresh}
      router/
        app_router.dart        // goRouterProvider + redirect (token-gate)
    features/
      auth/
        data/
          auth_dtos.dart       // freezed: VerifyOtpResponse{accessToken,refreshToken,user}, UserDto, SendOtpResponse{devOtp?}
          auth_repository.dart // authRepositoryProvider: sendOtp/verifyOtp/refresh/logout → Result
        domain/
          session.dart         // sealed Session = Unknown | Unauthenticated | Authenticated(UserDto)
        presentation/
          auth_controller.dart // @riverpod AuthController (AsyncNotifier<Session>): bootstrap/verify/logout
          splash_screen.dart
          phone_entry_screen.dart
          otp_entry_screen.dart
      home/
        presentation/home_screen.dart  // stub: greeting + logout
  test/
    auth/auth_repository_test.dart
    auth/auth_interceptor_test.dart
    auth/otp_flow_widget_test.dart
    router/token_gate_test.dart
```

## Dependencies (pubspec)

- `flutter_riverpod`, `riverpod_annotation` + dev `riverpod_generator`, `build_runner`, `custom_lint`, `riverpod_lint`
- `go_router`
- `dio`
- `flutter_secure_storage`
- `freezed_annotation`, `json_annotation` + dev `freezed`, `json_serializable`
- dev `flutter_lints`

## API contract (the backend endpoints this slice calls)

- `POST /auth/otp/send { phone }` → `200 { devOtp? }` (devOtp present only on dev). 429 if throttled.
- `POST /auth/otp/verify { phone, code }` → `200 { accessToken, refreshToken, user }`. 401 wrong/expired.
- `POST /auth/refresh { refreshToken }` → `200 { accessToken, refreshToken, user }`. 401 on reuse/expiry.
- `POST /auth/logout { refreshToken }` → `200 { ok: true }`.

DTOs are freezed models mapped from these shapes; repositories return `Result`, never raw dio/JSON.

## Data flow

1. **Launch** → `AuthController.build()` reads TokenStore. Tokens present → `Authenticated` (optionally
   validated lazily by the first real call's interceptor); absent → `Unauthenticated`. While reading →
   `Unknown` (splash shown).
2. **Router redirect** keys off Session: `Unknown`→`/splash`, `Unauthenticated`→`/phone`,
   `Authenticated`→`/home`. Deep-links respected once authed.
3. **Phone entry** → `authRepository.sendOtp(phone)` → on `Ok`, navigate to `/otp` (carrying phone +
   any devOtp). Validation: 10-digit Indian mobile before the call.
4. **OTP entry** → `authRepository.verifyOtp(phone, code)` → on `Ok`, TokenStore.write(pair),
   `AuthController` → `Authenticated(user)`, redirect to `/home`. `Failure(unauthorized)` → inline
   "wrong or expired code". Resend → sendOtp again; `Failure(rateLimited)` → "try again shortly".
5. **Interceptor** (all requests): attach `Authorization: Bearer <access>`. On 401 (non-auth routes):
   single-flight `refresh()`; success → store rotated pair, retry the original; failure → TokenStore.clear,
   `AuthController` → `Unauthenticated` (router pushes `/phone`).
6. **Logout** → `authRepository.logout(refresh)` (best-effort) → TokenStore.clear → `/phone`.

## Error handling

Typed `Result`. `FailureKind`: `network` (timeout/offline), `unauthorized` (401), `rateLimited` (429),
`validation` (400), `server` (5xx), `unknown`. UI shows a human message per kind; no raw dio error or
JSON ever reaches the widget layer. The interceptor is the ONLY place that performs a refresh.

## Testing (flutter test — real RED→GREEN, no backend needed; dio mocked)

- **auth_repository_test:** sendOtp/verifyOtp/refresh/logout map 200 → `Ok` with parsed DTO; 401 →
  `Failure(unauthorized)`; 429 → `Failure(rateLimited)`; network error → `Failure(network)`.
- **auth_interceptor_test:** two concurrent requests both 401 → exactly ONE `/auth/refresh` call
  (single-flight), both retried with the new token; refresh 401 → tokens cleared, error surfaced.
- **otp_flow_widget_test:** phone screen validates the number; OTP screen entering a code calls
  verifyOtp and, on Ok, the router lands on home.
- **token_gate_test:** Unknown→splash, Unauthenticated→phone, Authenticated→home redirects.
- `flutter analyze` clean; `dart run build_runner build` generates riverpod/freezed code with no errors.

## Run commands (also in apps/customer/README.md)

- **Backend up:** `docker compose up -d` (repo root) then, from `apps/backend`,
  `set -a && source .env && set +a && pnpm dev` → API on `:3000`.
- **App (Android emulator):** from `apps/customer`,
  `flutter run --dart-define=BASE_URL=http://10.0.2.2:3000`.
- **App (iOS simulator):** from `apps/customer`,
  `flutter run --dart-define=BASE_URL=http://localhost:3000`. _(Added by ADR-0005; iOS
  scaffolded in the PR after this slice. The web/Chrome run command was **removed** —
  web is no longer a target.)_
- **Codegen (after touching a provider/DTO):** `dart run build_runner build --delete-conflicting-outputs`.
- **Tests / lint:** `flutter test` · `flutter analyze`.

## Out of scope (recorded)

Home content, profile, addresses/serviceability, catalog browse, booking creation/tracking, payment,
disputes, camera evidence — all later slices. ~~iOS (Android-only V1)~~ **iOS is now a V1 target
(ADR-0005) — scaffolded in the PR right after this slice; the shared Dart code needs no change.**
Real SMS (backend dev-stub until MSG91 DLT). Localization/language toggle (screens are English-only
per the design; a toggle is a later concern). Push notifications, deep-link auth, biometric unlock.

## Follow-ups from the final review (deferred, recorded)

- **Boot-time token validation** — `AuthController.build()` treats a stored access token as
  authenticated without validating it; on a cold boot with an expired refresh the user briefly lands
  on `/home`, the first call 401s, refresh fails, and they bounce to `/phone`. A boot-time refresh (or
  a `/me/profile` probe) would remove the flash. Fold this into the next slice's boot flow that
  hydrates the real user (the placeholder-`UserDto` follow-up) — one boot request does both.
- **401 policy nuance** — the interceptor refreshes on any non-`/auth/` 401. The backend uses 403
  (`ForbiddenError`) for authorization failures, so this is safe today; if a future endpoint returns
  401 for a non-expiry reason, the interceptor should key off an error code to avoid a spurious
  refresh/logout. Revisit when such an endpoint appears.
