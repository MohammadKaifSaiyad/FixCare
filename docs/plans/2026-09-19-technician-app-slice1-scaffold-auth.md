# Technician App Slice 1 — Scaffold + Auth + Jobs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up `apps/technician` (Flutter, Android+iOS) with phone-OTP auth (role TECHNICIAN), a verification-aware home (VERIFIED → jobs screen; else status screen), and a jobs feature (available list + accept + my-jobs).

**Architecture:** New Flutter app mirroring `apps/customer`. The core backbone (Result, TokenStore, dio + single-flight AuthInterceptor, Env, theme, token-gate router) and the auth layer are **copied and adapted** from the proven, merged customer app — not rewritten. Technician-specific: the session carries the TechnicianStatus and gates the whole app on VERIFIED; the jobs feature reflects the backend's directional PII masking (full address, masked phone, no name).

**Tech Stack:** Flutter 3.47, Riverpod 3.x `@riverpod` codegen, go_router 18, dio 5, flutter_secure_storage 11, freezed 4, json_serializable; `http_mock_adapter` + `flutter_test` (hermetic). Codegen: `dart run build_runner build --delete-conflicting-outputs`.

**Spec:** `docs/designs/2026-09-19-technician-app-slice1-scaffold-auth-design.md`

## Global Constraints

- **`flutter analyze` 0 issues** before every commit (an `info` counts). Run from `apps/technician/`.
- **TDD:** failing test first, watch it fail, then the minimal implementation. All tests hermetic — mock the transport (`http_mock_adapter`) or inject fakes; never hit a real network.
- **Copy-and-adapt, don't rewrite:** where a task says "copy from `apps/customer/...`", read that file and reproduce it verbatim except the named adaptations. These files are merged + proven; do not "improve" them.
- **No global dio content-type** — the copied `dio_client.dart` must keep the customer's comment + behavior (a global `application/json` breaks bodyless GET/DELETE → Fastify `FST_ERR_CTP_EMPTY_JSON_BODY`).
- **Auth sends `role: 'TECHNICIAN'`** on `/auth/otp/send` and `/auth/otp/verify`.
- **The verification gate keys on the TechnicianStatus from `GET /me/profile`**, NOT the `user.status` in the verify response (that's the User status ACTIVE/SUSPENDED — a different field). `isVerified == (status == 'VERIFIED')`.
- **Never swallow a `Failure`** — map every `Result` to visible UX; jobs 403 `'Verified technician required'` → a verification-pending state, 409 `'This job is no longer available'` → "already taken", 422 cash-debt message surfaced.
- **Directional PII:** `TechnicianJobDto` exposes full `address` + `customer.maskedPhone` + NO customer name — reflect exactly what the backend sends; never request more.
- Money is integer paise; render with a local `rupees(int)` helper (copy the customer's).
- After adding `@riverpod`/freezed classes, re-run build_runner and commit generated `*.g.dart`/`*.freezed.dart`.
- Bundle id `in.fixcare.fixcareTechnician`; iOS 15+; default `BASE_URL` `http://10.0.2.2:3000`.
- Commit as `MohammadKaifSaiyad <saiyedkgn6@gmail.com>`, no Claude trailer.

---

## File Structure

**Scaffold:** `apps/technician/` (pubspec, android/, ios/, README.md, analysis_options.yaml).

**`lib/core/`** (copied from customer): `env.dart`, `result.dart`, `theme.dart`,
`storage/token_store.dart`, `network/dio_client.dart`, `network/auth_interceptor.dart`,
`router/app_router.dart` (adapted routes).

**`lib/features/auth/`:** `data/auth_dtos.dart`, `data/auth_repository.dart` (role TECHNICIAN),
`domain/session.dart` (technician session + isVerified), `presentation/auth_controller.dart`,
`presentation/{splash_screen,phone_entry_screen,otp_entry_screen}.dart`.

**`lib/features/profile/`:** `data/technician_profile_dto.dart`, `data/technician_profile_repository.dart`.

**`lib/features/jobs/`:** `data/technician_job_dto.dart`, `data/technician_job_repository.dart`,
`presentation/{jobs_home_screen,available_jobs_controller,my_jobs_controller,verification_pending_screen}.dart`.

**`lib/main.dart`.**

---

## Task 1: Scaffold the Flutter app

**Files:**
- Create: `apps/technician/` (via `flutter create`), then `pubspec.yaml`, `README.md`, `analysis_options.yaml`
- Reference: `apps/customer/pubspec.yaml`, `apps/customer/README.md`, `apps/customer/analysis_options.yaml`

**Interfaces:**
- Produces: a buildable empty Flutter app at `apps/technician` with the same dependency set as the customer app (minus google_maps_flutter + razorpay_flutter, which Slice 1 doesn't use).

- [ ] **Step 1: Create the project**

Run from `apps/`:
```bash
flutter create --org in.fixcare --project-name fixcare_technician --platforms=android,ios technician
```
Expected: `apps/technician/` created with android/ + ios/ (no web).

- [ ] **Step 2: Set the dependencies** — replace `apps/technician/pubspec.yaml`'s deps to mirror `apps/customer/pubspec.yaml` EXCEPT omit `google_maps_flutter` and `razorpay_flutter`. Required:

```yaml
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  flutter_riverpod: ^3.4.3
  riverpod_annotation: ^4.0.7
  go_router: ^18.0.1
  dio: ^5.11.1
  flutter_secure_storage: ^11.0.0
  freezed_annotation: ^3.1.0
  json_annotation: ^4.12.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0
  build_runner: ^2.4.13
  freezed: ^3.2.0
  json_serializable: ^6.8.0
  riverpod_generator: ^4.0.9
  http_mock_adapter: ^0.6.1
```
(Match the customer app's exact version constraints — read `apps/customer/pubspec.yaml` and copy the versions verbatim for the shared deps; the above are the known-good values.)

- [ ] **Step 3: pub get + analyze the empty app**

Run from `apps/technician/`:
```bash
flutter pub get && flutter analyze
```
Expected: `No issues found!` (the generated counter app analyzes clean).

- [ ] **Step 4: iOS + Android config** — mirror the customer app: set iOS deployment target 15.0 and add the `localhost`/`10.0.2.2` ATS cleartext exception the customer uses (read `apps/customer/ios/Runner/Info.plist` for the `NSAppTransportSecurity` block and reproduce it in `apps/technician/ios/Runner/Info.plist`). Confirm the Android `applicationId` is `in.fixcare.fixcare_technician` (flutter create sets this from --org + --project-name).

- [ ] **Step 5: README** — create `apps/technician/README.md` mirroring `apps/customer/README.md`: run commands (`flutter run --dart-define=BASE_URL=...`, per-platform base URLs — iOS sim `localhost:3000`, Android emu `10.0.2.2:3000`), the build-via-flutter-not-Xcode note, and a **"Technician verification (dev)"** note: a fresh signup is `PENDING` and `/technician/jobs/*` 403 until an admin sets `status='VERIFIED'`; for local testing flip it via SQL (`update "Technician" set status='VERIFIED', skills='{FAN}' where id=...`).

- [ ] **Step 6: Commit**

```bash
git add apps/technician
git commit -m "feat(technician): scaffold apps/technician Flutter app (android+ios, riverpod+dio+go_router)"
```

---

## Task 2: Core backbone (copied from customer)

**Files:**
- Create: `apps/technician/lib/core/env.dart`, `core/result.dart`, `core/theme.dart`, `core/storage/token_store.dart`, `core/network/dio_client.dart`, `core/network/auth_interceptor.dart`
- Test: `apps/technician/test/core/auth_interceptor_test.dart`
- Reference (copy verbatim): the same-named files under `apps/customer/lib/core/`, and `apps/customer/test/` for the interceptor test.

**Interfaces:**
- Produces: `Env.baseUrl`; `Result`/`Ok`/`Failure`/`FailureKind`/`failureKindFromStatus` (result.dart); `TokenStore` + `tokenStoreProvider` (readAccess/readRefresh/save/savePhone/clear); `dioProvider` (dio + single-flight AuthInterceptor); `FixCareColors`/`FixCareRadii` (theme.dart).

- [ ] **Step 1: Copy the leaf core files verbatim** — copy these from `apps/customer/lib/core/` to `apps/technician/lib/core/`, changing ONLY import package names if any are absolute (`package:fixcare_customer/...` → `package:fixcare_technician/...`; the customer files use relative imports, so likely no change):
  - `env.dart` (keep default `http://10.0.2.2:3000`)
  - `result.dart` (verbatim)
  - `storage/token_store.dart` (verbatim)
  - `theme.dart` (verbatim — same design system)

- [ ] **Step 2: Copy `dio_client.dart` + `auth_interceptor.dart` verbatim** from `apps/customer/lib/core/network/`. These carry the single-flight refresh + the **no-global-content-type** fix — reproduce exactly, including comments. The only edit: the interceptor's `onAuthLost` wiring references `authControllerProvider` — leave the import path relative; it resolves once Task 4 creates the controller. (If build_runner/analyze can't resolve `authControllerProvider` yet, that's expected until Task 4; this task's test stubs the interceptor's deps directly — see Step 3.)

> Ruling for the implementer: `dio_client.dart` imports `authControllerProvider`. To keep Task 2 independently compilable+testable, copy `dio_client.dart` but if it won't analyze without the controller, create a minimal `auth_controller.dart` stub in Task 2 ONLY if necessary; otherwise defer the `dioProvider` wiring assertion to Task 4. Prefer: copy auth_interceptor.dart + its test now (it's self-contained — takes a token store + refresh fn + onAuthLost callback as constructor args), and copy dio_client.dart in Task 4 alongside the controller. Adjust the task boundary if the customer's dio_client hard-depends on the controller at import.

- [ ] **Step 3: Port the interceptor test** — copy `apps/customer`'s auth-interceptor test to `apps/technician/test/core/auth_interceptor_test.dart` verbatim (adapt import package name). It asserts: 401 → one refresh → retry via the bare dio; concurrent 401s share a single refresh; refresh-fail → clears tokens + calls onAuthLost.

- [ ] **Step 4: Run the test + analyze**

Run from `apps/technician/`:
```bash
flutter test test/core/auth_interceptor_test.dart && flutter analyze
```
Expected: pass; clean. (If `dio_client.dart` was deferred to Task 4, analyze the files present.)

- [ ] **Step 5: Commit**

```bash
git add apps/technician/lib/core apps/technician/test/core
git commit -m "feat(technician): core backbone — Result/TokenStore/dio+single-flight interceptor/theme (copied from customer)"
```

---

## Task 3: Auth data + repository (role TECHNICIAN)

**Files:**
- Create: `apps/technician/lib/features/auth/data/auth_dtos.dart`, `data/auth_repository.dart`
- Test: `apps/technician/test/auth/auth_repository_test.dart`
- Reference: `apps/customer/lib/features/auth/data/auth_dtos.dart` + `auth_repository.dart`, `apps/customer/test/auth/auth_repository_test.dart`

**Interfaces:**
- Consumes: `dioProvider`, `Result`, `FailureKind` (Task 2).
- Produces: `UserDto{id,role,status}`, `VerifyResponse{accessToken,refreshToken,user}`, `RefreshResponse{accessToken,refreshToken}`, `SendOtpResponse{ok,devOtp?}`; `AuthRepository` (`sendOtp(phone)`, `verifyOtp(phone,otp)`, `refresh(token)`, `logout(token)`) + `authRepositoryProvider`.

- [ ] **Step 1: Copy the auth DTOs verbatim** — copy `apps/customer/lib/features/auth/data/auth_dtos.dart` to the technician path unchanged (the DTO shapes are identical; verify returns `{accessToken, refreshToken, user:{id,role,status}}` for both roles).

- [ ] **Step 2: Copy `auth_repository.dart`, change the role** — copy the customer's `auth_repository.dart`; change the ONE line `static const _role = 'CUSTOMER';` → `static const _role = 'TECHNICIAN';` and update the comment to say technician. Keep everything else (the `_post` helper, `_msg`, all four methods) verbatim.

- [ ] **Step 3: Write the failing test** — `apps/technician/test/auth/auth_repository_test.dart` (adapt the customer's, asserting role TECHNICIAN):

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/features/auth/data/auth_repository.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late AuthRepository repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://test', validateStatus: (_) => true));
    adapter = DioAdapter(dio: dio, matcher: const FullHttpRequestMatcher(needsExactBody: true));
    repo = AuthRepository(dio);
  });

  test('sendOtp posts EXACTLY {phone, role:TECHNICIAN} and parses devOtp', () async {
    adapter.onPost('/auth/otp/send', (s) => s.reply(200, {'ok': true, 'devOtp': '123456'}),
        data: {'phone': '9990001111', 'role': 'TECHNICIAN'});
    final r = await repo.sendOtp('9990001111');
    expect((r as Ok<SendOtpResponse>).value.devOtp, '123456');
  });

  test('verifyOtp posts {phone, role:TECHNICIAN, otp} and parses tokens + user', () async {
    adapter.onPost('/auth/otp/verify',
        (s) => s.reply(200, {'accessToken': 'a', 'refreshToken': 'r', 'user': {'id': 'u1', 'role': 'TECHNICIAN', 'status': 'ACTIVE'}}),
        data: {'phone': '9990001111', 'role': 'TECHNICIAN', 'otp': '123456'});
    final r = await repo.verifyOtp('9990001111', '123456');
    final v = (r as Ok<VerifyResponse>).value;
    expect(v.accessToken, 'a');
    expect(v.user.role, 'TECHNICIAN');
  });

  test('sendOtp 429 -> Failure(rateLimited) with backend message', () async {
    adapter.onPost('/auth/otp/send',
        (s) => s.reply(429, {'code': 'TOO_MANY_REQUESTS', 'message': 'Too many OTP requests. Try again later.'}),
        data: {'phone': '9990001111', 'role': 'TECHNICIAN'});
    final r = await repo.sendOtp('9990001111');
    final f = r as Failure;
    expect(f.kind, FailureKind.rateLimited);
    expect(f.message, 'Too many OTP requests. Try again later.');
  });

  test('verifyOtp 401 -> Failure(unauthorized)', () async {
    adapter.onPost('/auth/otp/verify',
        (s) => s.reply(401, {'code': 'UNAUTHORIZED', 'message': 'Invalid or expired OTP'}),
        data: {'phone': '9990001111', 'role': 'TECHNICIAN', 'otp': '000000'});
    final r = await repo.verifyOtp('9990001111', '000000');
    expect((r as Failure).kind, FailureKind.unauthorized);
  });
}
```

- [ ] **Step 2b: Regenerate codegen** (the DTOs are freezed/json):

Run: `dart run build_runner build --delete-conflicting-outputs`

- [ ] **Step 4: Run + analyze**

Run: `flutter test test/auth/auth_repository_test.dart && flutter analyze`
Expected: pass; clean.

- [ ] **Step 5: Commit**

```bash
git add apps/technician/lib/features/auth/data apps/technician/test/auth/auth_repository_test.dart
git commit -m "feat(technician): auth DTOs + repository (role TECHNICIAN)"
```

---

## Task 4: Profile + Session + AuthController (verification gate)

**Files:**
- Create: `apps/technician/lib/features/profile/data/technician_profile_dto.dart`, `data/technician_profile_repository.dart`, `lib/features/auth/domain/session.dart`, `lib/features/auth/presentation/auth_controller.dart`
- Create (if deferred from Task 2): `lib/core/network/dio_client.dart`
- Test: `apps/technician/test/profile/technician_profile_repository_test.dart`, `test/auth/auth_controller_test.dart`
- Reference: `apps/customer/lib/features/profile/data/profile_repository.dart`, `apps/customer/lib/features/auth/{domain/session.dart,presentation/auth_controller.dart}`

**Interfaces:**
- Consumes: `dioProvider`, `Result`/`FailureKind`, `TokenStore`, `AuthRepository` (Tasks 2-3).
- Produces:
  - `TechnicianProfileDto({required String id, required String role, required String name, @Default(<String>[]) List<String> skills, required String status})` + `.fromJson`.
  - `TechnicianProfileRepository.getProfile() -> Result<TechnicianProfileDto>` + `technicianProfileRepositoryProvider`.
  - sealed `Session`: `SessionUnauthenticated`, `SessionAuthenticated(TechnicianProfileDto profile, {bool hydrated}) ` with `String get name`, `String get status`, `bool get isVerified => profile.status == 'VERIFIED'`.
  - `@Riverpod(keepAlive: true) class AuthController` with `Future<Session> build()`, `requestOtp(phone)`, `submitOtp(phone, code)`, `logout()`, `onAuthLost()`; `authControllerProvider`.

- [ ] **Step 1: `TechnicianProfileDto`** — create it (freezed + json), fields per the Interfaces above. `skills` is `List<String>` (the backend sends `ServiceSkill[]` strings).

- [ ] **Step 2: `TechnicianProfileRepository`** — copy `apps/customer`'s `profile_repository.dart` structure; keep only `getProfile()` (`GET /me/profile` → `TechnicianProfileDto`) — DROP `updateName` (not needed in Slice 1). Same `_parse`/`_msg`/DioException handling.

- [ ] **Step 3: `Session`** — adapt the customer's `session.dart`:

```dart
import '../../profile/data/technician_profile_dto.dart';

sealed class Session {
  const Session();
}

class SessionUnauthenticated extends Session {
  const SessionUnauthenticated();
}

/// Authenticated technician. [hydrated] is false when we have a token but the
/// boot profile fetch failed on a transient network error (stay logged in).
class SessionAuthenticated extends Session {
  final TechnicianProfileDto profile;
  final bool hydrated;
  const SessionAuthenticated(this.profile, {this.hydrated = true});

  String get name => profile.name;
  String get status => profile.status;
  bool get isVerified => profile.status == 'VERIFIED';
}
```

- [ ] **Step 4: `AuthController`** — adapt the customer's `auth_controller.dart`: same build/boot (read token → `_hydrate` via `technicianProfileRepositoryProvider`), same `requestOtp`/`submitOtp` (submit saves tokens + savePhone + re-hydrates), same `logout`/`onAuthLost`. DROP `updateName`. On the `Failure()` (non-401) hydrate branch, emit `SessionAuthenticated(TechnicianProfileDto(id:'', role:'TECHNICIAN', name:'', skills: const [], status:'PENDING'), hydrated:false)` — an unhydrated technician is treated as not-verified (PENDING), never accidentally VERIFIED.

- [ ] **Step 5: Copy `dio_client.dart`** (if deferred from Task 2) now that `authControllerProvider` exists; it wires `onAuthLost` via `ref.read(authControllerProvider.notifier).onAuthLost()`.

- [ ] **Step 6: Write the failing tests**

`test/profile/technician_profile_repository_test.dart`:
```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/features/profile/data/technician_profile_repository.dart';

void main() {
  late Dio dio; late DioAdapter adapter; late TechnicianProfileRepository repo;
  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://test', validateStatus: (_) => true));
    adapter = DioAdapter(dio: dio);
    repo = TechnicianProfileRepository(dio);
  });

  test('getProfile parses a VERIFIED technician with skills', () async {
    adapter.onGet('/me/profile', (s) => s.reply(200, {'id': 't1', 'role': 'TECHNICIAN', 'name': 'Ramesh', 'skills': ['FAN', 'AC'], 'status': 'VERIFIED'}));
    final v = (await repo.getProfile() as Ok<TechnicianProfileDto>).value;
    expect(v.status, 'VERIFIED');
    expect(v.skills, ['FAN', 'AC']);
  });

  test('getProfile parses a fresh PENDING technician (empty name/skills)', () async {
    adapter.onGet('/me/profile', (s) => s.reply(200, {'id': 't1', 'role': 'TECHNICIAN', 'name': '', 'skills': <String>[], 'status': 'PENDING'}));
    final v = (await repo.getProfile() as Ok<TechnicianProfileDto>).value;
    expect(v.status, 'PENDING');
    expect(v.name, '');
    expect(v.skills, isEmpty);
  });

  test('getProfile 401 -> Failure(unauthorized)', () async {
    adapter.onGet('/me/profile', (s) => s.reply(401, {'code': 'UNAUTHORIZED', 'message': 'nope'}));
    expect((await repo.getProfile() as Failure).kind, FailureKind.unauthorized);
  });
}
```

`test/auth/auth_controller_test.dart` — using a `ProviderContainer` with fake repos + a mocked secure-storage channel (mirror the customer app's `auth_controller_test.dart`). Assert:
- no token → `build()` → `SessionUnauthenticated`.
- token + profile VERIFIED → `SessionAuthenticated` with `isVerified == true`.
- token + profile PENDING → `SessionAuthenticated` with `isVerified == false`.
- token + profile 401 → clears token → `SessionUnauthenticated`.
- token + profile network Failure → `SessionAuthenticated(hydrated:false)` with `isVerified == false` (PENDING fallback).
(Read `apps/customer/test/auth/*controller*` or the token-gate tests for the secure-storage channel-mock setup and reuse it.)

- [ ] **Step 7: build_runner + run + analyze**

Run: `dart run build_runner build --delete-conflicting-outputs && flutter test test/profile test/auth && flutter analyze`
Expected: pass; clean.

- [ ] **Step 8: Commit**

```bash
git add apps/technician/lib/features/profile apps/technician/lib/features/auth/domain apps/technician/lib/features/auth/presentation/auth_controller.dart apps/technician/lib/core/network/dio_client.dart apps/technician/test/profile apps/technician/test/auth/auth_controller_test.dart
git commit -m "feat(technician): profile DTO/repo + session (isVerified) + AuthController hydration"
```

---

## Task 5: Auth screens + router token-gate + verification screen

**Files:**
- Create: `apps/technician/lib/features/auth/presentation/{splash_screen,phone_entry_screen,otp_entry_screen}.dart`, `lib/features/jobs/presentation/verification_pending_screen.dart`, `lib/core/router/app_router.dart`, `lib/main.dart`
- Test: `apps/technician/test/router/token_gate_test.dart`
- Reference: `apps/customer/lib/features/auth/presentation/*`, `apps/customer/lib/core/router/app_router.dart`, `apps/customer/lib/main.dart`

**Interfaces:**
- Consumes: `AuthController`/`Session`/`isVerified` (Task 4), `authRepositoryProvider` (Task 3).
- Produces: the app's routing — `/splash`, `/phone`, `/otp`, and the authed home which is either the jobs home (Task 6, referenced) or the verification screen; `goRouterProvider`; `main.dart` runs the app.

- [ ] **Step 1: Copy the auth screens** — copy `splash_screen.dart`, `phone_entry_screen.dart`, `otp_entry_screen.dart` from `apps/customer` verbatim (adapt import package names + any customer-specific copy like "Book a repair" → technician-appropriate wording, e.g. "Log in to FixCare Partner"). They call `authControllerProvider.notifier.requestOtp/submitOtp` — unchanged.

- [ ] **Step 2: Create `verification_pending_screen.dart`** — a `ConsumerWidget` that reads the session's `status` and shows:
  - `PENDING`/`KYC_SUBMITTED` → title "Verification pending", body "Your account is under review. We'll notify you once you're verified.", plus a logout button.
  - `SUSPENDED`/`DEACTIVATED` → title "Account suspended", body "Your account is suspended. Please contact support.", plus logout.
  Use a `Key('verificationPendingScreen')` on the root and `Key('verificationStatusText')` on the body text so tests can assert the copy.

- [ ] **Step 3: Copy + adapt the router** — copy `apps/customer/lib/core/router/app_router.dart`. Keep the `_AuthRefresh` bridge + the redirect logic (booting→splash, error→phone, unauthenticated→phone, authenticated→home). Change the routes: remove all customer routes (address/booking/catalog/account); add `/splash`, `/phone`, `/otp`, and `/home`. **The `/home` builder branches on verification:** `final s = ref.read(authControllerProvider).value; return (s is SessionAuthenticated && s.isVerified) ? const JobsHomeScreen() : const VerificationPendingScreen();` (JobsHomeScreen from Task 6 — import it; if Task 6 isn't done yet, temporarily point `/home` at `VerificationPendingScreen` and wire JobsHomeScreen in Task 6). The redirect sends an authenticated user to `/home` regardless of verification (the screen decides what to show), and an unauthenticated user to `/phone`.

- [ ] **Step 4: `main.dart`** — copy the customer's `main.dart` (ProviderScope + MaterialApp.router with `goRouterProvider` + theme). Adapt the app title to "FixCare Partner".

- [ ] **Step 5: Write the failing widget test** — `test/router/token_gate_test.dart`, using `ProviderScope` overrides (fake AuthController state via a fake profile repo + mocked secure-storage channel, mirroring the customer token-gate test):
  - no token → lands on the phone screen (`find` the phone entry).
  - token + VERIFIED session → lands on the jobs home (assert a jobs-home key; if Task 6 pending, assert NOT the verification screen).
  - token + PENDING session → lands on the verification screen (`find.byKey(Key('verificationPendingScreen'))`, and the "under review" copy).
  - token + SUSPENDED session → verification screen with the "suspended" copy.

- [ ] **Step 6: Run + analyze**

Run: `flutter test test/router/token_gate_test.dart && flutter analyze`
Expected: pass; clean.

- [ ] **Step 7: Commit**

```bash
git add apps/technician/lib/features/auth/presentation apps/technician/lib/features/jobs/presentation/verification_pending_screen.dart apps/technician/lib/core/router apps/technician/lib/main.dart apps/technician/test/router
git commit -m "feat(technician): auth screens + token-gate router + verification-pending screen"
```

---

## Task 6: Jobs feature (list + accept)

**Files:**
- Create: `apps/technician/lib/features/jobs/data/technician_job_dto.dart`, `data/technician_job_repository.dart`, `presentation/available_jobs_controller.dart`, `presentation/my_jobs_controller.dart`, `presentation/jobs_home_screen.dart`
- Create: `apps/technician/lib/core/format.dart` (a `rupees(int)` helper — copy from customer's home_screen `rupees`)
- Modify: `lib/core/router/app_router.dart` (point `/home` at `JobsHomeScreen` for verified)
- Test: `apps/technician/test/jobs/technician_job_repository_test.dart`, `test/jobs/jobs_home_widget_test.dart`
- Reference: `apps/customer/lib/features/address/presentation/address_controller.dart` (the `@riverpod` async-list + refresh pattern)

**Interfaces:**
- Consumes: `dioProvider`, `Result`/`FailureKind`, `rupees`.
- Produces:
  - `TechnicianJobDto` (freezed): `id, bookingNumber, state, scheduledSlot, service:JobServiceDto{name,requiredSkill}, zone:JobZoneDto{name}, visitFeePaise, laborPaise, address:JobAddressDto{line1, line2?, landmark?, pincode}, customer:JobCustomerDto{maskedPhone}, @Default(<JobPhotoDto>[]) photos` (JobPhotoDto{kind,capturedAt,url}).
  - `TechnicianJobRepository`: `available() -> Result<List<TechnicianJobDto>>`, `mine() -> Result<List<TechnicianJobDto>>`, `accept(String id) -> Result<TechnicianJobDto>` + `technicianJobRepositoryProvider`.
  - `AvailableJobsController` + `MyJobsController` (`@riverpod`, `Future<List<TechnicianJobDto>> build()`, `refresh()`); accept on the available controller → refreshes both.
  - `JobsHomeScreen`.

- [ ] **Step 1: `TechnicianJobDto`** — create the freezed DTOs per the Interfaces (nested `JobServiceDto`/`JobZoneDto`/`JobAddressDto`/`JobCustomerDto`/`JobPhotoDto`). Match the backend `TechnicianJobDto` exactly: full address, `customer.maskedPhone` only (no name field), photos default `[]`.

- [ ] **Step 2: `TechnicianJobRepository`** — `available()`/`mine()` GET the list endpoints and parse `List<TechnicianJobDto>` (a 2xx non-list body → `Failure(server)`); `accept(id)` POSTs `/technician/jobs/$id/accept` (bodyless) and parses a `TechnicianJobDto`. Map errors via `failureKindFromStatus` + the `{code,message}` message: 403 → `Failure(FailureKind.unauthorized... )` — actually use a dedicated check: **surface the message verbatim** and let the UI branch on it (403 message `'Verified technician required'`, 409 `'This job is no longer available'`, 422 cash-debt). Mirror the customer repos' `_guard`/`_ok` structure.

- [ ] **Step 3: Write the failing repository test** — `test/jobs/technician_job_repository_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:fixcare_technician/core/result.dart';
import 'package:fixcare_technician/features/jobs/data/technician_job_repository.dart';

Map<String, dynamic> _job() => {
  'id': 'b1', 'bookingNumber': 'FC-1', 'state': 'DISPATCHED', 'scheduledSlot': '2026-09-20T09:00:00.000Z',
  'service': {'name': 'Ceiling fan repair', 'requiredSkill': 'FAN'},
  'zone': {'name': 'Padra'}, 'visitFeePaise': 9900, 'laborPaise': 20000,
  'address': {'line1': 'A/27 Umiya Nagar', 'line2': 'Padra', 'landmark': 'HP Gas', 'pincode': '391440'},
  'customer': {'maskedPhone': '••••••8384'}, 'photos': <Map<String, dynamic>>[],
};

void main() {
  late Dio dio; late DioAdapter adapter; late TechnicianJobRepository repo;
  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://test', validateStatus: (_) => true));
    adapter = DioAdapter(dio: dio, matcher: const FullHttpRequestMatcher(needsExactBody: true));
    repo = TechnicianJobRepository(dio);
  });

  test('available parses a job list (full address, masked phone, no name)', () async {
    adapter.onGet('/technician/jobs/available', (s) => s.reply(200, [_job()]));
    final v = (await repo.available() as Ok<List<TechnicianJobDto>>).value;
    expect(v.single.bookingNumber, 'FC-1');
    expect(v.single.address.line1, 'A/27 Umiya Nagar');
    expect(v.single.customer.maskedPhone, '••••••8384');
  });

  test('available 403 Verified technician required -> Failure with that message', () async {
    adapter.onGet('/technician/jobs/available',
        (s) => s.reply(403, {'code': 'FORBIDDEN', 'message': 'Verified technician required'}));
    expect((await repo.available() as Failure).message, 'Verified technician required');
  });

  test('accept is a bodyless POST and parses the job', () async {
    adapter.onPost('/technician/jobs/b1/accept', (s) => s.reply(200, {..._job(), 'state': 'ACCEPTED'}));
    final v = (await repo.accept('b1') as Ok<TechnicianJobDto>).value;
    expect(v.state, 'ACCEPTED');
  });

  test('accept 409 already taken -> Failure with that message', () async {
    adapter.onPost('/technician/jobs/b1/accept',
        (s) => s.reply(409, {'code': 'CONFLICT', 'message': 'This job is no longer available'}));
    expect((await repo.accept('b1') as Failure).message, 'This job is no longer available');
  });

  test('accept 422 cash-debt -> Failure with that message', () async {
    adapter.onPost('/technician/jobs/b1/accept',
        (s) => s.reply(422, {'code': 'UNPROCESSABLE', 'message': 'Settle your cash debt to accept new jobs'}));
    expect((await repo.accept('b1') as Failure).message, 'Settle your cash debt to accept new jobs');
  });
}
```

- [ ] **Step 4: Controllers** — `AvailableJobsController`/`MyJobsController` (`@riverpod`, async list build calling the repo, throw Exception(message) on Failure like the customer `AddressController`; `refresh()`). `accept(id)` on the available controller: call `repo.accept`, on Ok refresh both lists (read the my-jobs provider's notifier and refresh), on Failure return the `Result` for the UI to snack.

- [ ] **Step 5: `JobsHomeScreen`** — a `ConsumerWidget` with two sections (Available / My jobs), rendering `TechnicianJobDto` cards (service name, `rupees(visitFeePaise)`/`rupees(laborPaise)`, zone name, address, scheduled slot, masked phone). Available cards have an Accept button (`Key('acceptJob_<id>')`) with a per-card busy flag; tap → controller.accept → Ok refreshes, Failure → SnackBar(message). Empty available → "No jobs available right now" (`Key('noJobsEmpty')`). Add `Key('jobsHomeScreen')` on the root. Pull-to-refresh (`RefreshIndicator`) on each list.

- [ ] **Step 6: Wire the router** — in `app_router.dart`, the `/home` verified branch now returns `const JobsHomeScreen()` (replace the temporary placeholder from Task 5).

- [ ] **Step 7: Write the failing widget test** — `test/jobs/jobs_home_widget_test.dart` (fake `TechnicianJobRepository` recording calls, `ProviderScope` overrides):
  - available list renders a card (service name + `rupees` + masked phone + address); empty list → `noJobsEmpty`.
  - tap `acceptJob_b1` → fake repo's `accept('b1')` invoked; on `Ok` both lists refresh (assert via call counts / the job moving); on `409 Failure` a SnackBar with "This job is no longer available" shows.

- [ ] **Step 8: build_runner + run + analyze + full suite**

Run: `dart run build_runner build --delete-conflicting-outputs && flutter test && flutter analyze`
Expected: all pass; `No issues found!`.

- [ ] **Step 9: Commit**

```bash
git add apps/technician/lib/features/jobs apps/technician/lib/core/format.dart apps/technician/lib/core/router/app_router.dart apps/technician/test/jobs
git commit -m "feat(technician): jobs feature — available/mine list + accept, jobs home screen"
```

---

## Self-Review

**1. Spec coverage:**
- Scaffold (Android+iOS, deps, README, dev note) → Task 1. ✓
- Core backbone copied (Result/TokenStore/dio+interceptor/theme/no-global-content-type) → Task 2. ✓
- Auth role TECHNICIAN + DTOs + repo → Task 3. ✓
- Profile DTO/repo + Session.isVerified + AuthController hydration (PENDING fallback, gate on TechnicianStatus not user.status) → Task 4. ✓
- Auth screens + token-gate router + verification screen (pending vs suspended copy) → Task 5. ✓
- Jobs DTO (directional masking) + repo (403/409/422 messages) + list/accept + home → Task 6. ✓
- Deferred real-backend smoke → noted in spec, not a task (correct). ✓

**2. Placeholder scan:** No TBD/TODO in production steps. Task 2 flags a real ordering nuance (dio_client depends on the controller) and gives an explicit ruling to defer dio_client to Task 4 if needed — that's a boundary decision, not a placeholder. Widget-test bodies in Tasks 4-6 are specified as concrete assertions to write against named keys (harness copied from the customer app), with full code for the repository tests.

**3. Type consistency:** `TechnicianProfileDto{id,role,name,skills,status}`, `Session.isVerified`, `TechnicianJobDto` (+ nested Job*Dto), `available/mine/accept`, `authControllerProvider`, `technicianProfileRepositoryProvider`, `technicianJobRepositoryProvider` used consistently across tasks. `status`-gates key on the profile's TechnicianStatus, never the verify `user.status`. Keys (`verificationPendingScreen`, `jobsHomeScreen`, `acceptJob_<id>`, `noJobsEmpty`) consistent between the screen tasks and their tests.
