# Customer App Slice 2 — Boot Hydration + Profile + Addresses Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A logged-in customer has a real identity (name fetched on boot, captured on first run) and can manage service addresses with live pincode serviceability and a Google-Maps-picked location.

**Architecture:** Two new feature-first modules (`features/profile`, `features/address`) on the Slice-1 backbone (Riverpod `@riverpod` codegen, go_router, dio + single-flight interceptor, `Result<T>`, freezed, theme tokens). `AuthController` gains boot-hydration (fetch `/me/profile`) and `updateName`; `Session` carries the real profile. New dep `google_maps_flutter`, wired to degrade gracefully without an API key.

**Tech Stack:** Flutter 3.47 (Dart 3), flutter_riverpod + riverpod_annotation/generator, go_router 18, dio 5, flutter_secure_storage 11, freezed 4.0.1, json_serializable, build_runner, google_maps_flutter, http_mock_adapter (dev).

**Spec:** `docs/designs/2026-09-05-customer-app-slice2-profile-addresses-design.md`

## Global Constraints

- **Backend contract is authoritative** (read from `apps/backend/src/modules/{profiles,addresses}`): `GET /me/profile` → `{id, role:'CUSTOMER', name, status}` (name may be `""`); `PATCH /me/profile` body is **exactly `{name}`** → same DTO. `GET /me/addresses` → `AddressDto[]`; `POST /me/addresses` → **201** `AddressDto`; `PATCH /me/addresses/:id` → 200; `DELETE /me/addresses/:id` → **204 (empty body)**; `GET /serviceability?pincode=` → `{serviceable, zone, message?}`.
- **`AddressDto` fields exactly:** `id, label, line1, line2?, landmark?, pincode, lat?, lng?, isDefault, status, serviceable, zone:{id,name,visitFeePaise}|null, message?`.
- **Create/Update body:** `label, line1, line2?, landmark?, pincode(6-digit), lat?, lng?, isDefault?` — **lat & lng both-or-neither**. Out-of-area still saves (201, `serviceable:false`).
- **Error envelope is `{code, message}`** — repositories read `message`, never `error`.
- **Repositories return `Result<T>`; no raw dio/JSON above the data layer.** UI switches on `FailureKind`.
- **Tests use mocked transport** (http_mock_adapter for repos; mocked secure-storage method channel for controllers/widgets) and **MUST assert exact request bodies + the `{code,message}` envelope** (the Slice-1 `/code-review` lesson: mocks that encode the wrong contract hide real bugs).
- **freezed 4.0.1 syntax:** `abstract class X with _$X`. **Generated `*.g.dart`/`*.freezed.dart` ARE committed.**
- **Commit author** `MohammadKaifSaiyad <saiyedkgn6@gmail.com>`, **NO Claude/Co-Authored-By trailer**: commit via `git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "..."`.
- **Maps key never committed**; the map widget must **degrade gracefully without a key** (placeholder, no crash) so the slice is testable/mergeable before the key is provisioned.
- All commands run from `apps/customer` unless noted. After touching any `@freezed`/`@riverpod` file: `dart run build_runner build --delete-conflicting-outputs`. Gate every commit on `flutter analyze` (clean) + `flutter test` (green).

---

## File structure

**Create:**
- `lib/features/profile/data/profile_dtos.dart` — freezed `CustomerProfileDto`.
- `lib/features/profile/data/profile_repository.dart` — `ProfileRepository`, `profileRepositoryProvider`.
- `lib/features/profile/presentation/name_capture_screen.dart` — `/name`.
- `lib/features/profile/presentation/account_screen.dart` — `/account`.
- `lib/features/address/data/address_dtos.dart` — freezed `AddressDto`, `ServiceabilityDto`, `ZoneDto`.
- `lib/features/address/data/address_repository.dart` — `AddressRepository`, `addressRepositoryProvider`.
- `lib/features/address/presentation/address_controller.dart` — `@riverpod AddressController` (list state).
- `lib/features/address/presentation/address_list_screen.dart` — `/addresses`.
- `lib/features/address/presentation/address_form_screen.dart` — `/address/new`, `/address/:id/edit`.
- `lib/features/address/presentation/widgets/serviceability_chip.dart`.
- `lib/features/address/presentation/widgets/address_map_picker.dart` — Google Maps, graceful-no-key.
- Tests: `test/profile/profile_repository_test.dart`, `test/address/address_repository_test.dart`, `test/auth/auth_controller_boot_test.dart`, `test/router/name_gate_test.dart`, `test/address/address_form_widget_test.dart`.

**Modify:**
- `lib/features/auth/domain/session.dart` — `SessionAuthenticated` holds `CustomerProfileDto` + `hydrated` flag.
- `lib/features/auth/presentation/auth_controller.dart` — boot hydration, `submitOtp` profile fetch, `updateName`.
- `lib/core/storage/token_store.dart` — persist/read phone (for Account display).
- `lib/core/router/app_router.dart` — new routes + name-gate redirect.
- `lib/features/home/presentation/home_screen.dart` — avatar → `/account` (logout moves to Account).
- `pubspec.yaml` — add `google_maps_flutter`.
- `android/app/src/main/AndroidManifest.xml`, `ios/Runner/AppDelegate.swift` — Maps key wiring (placeholder).
- `apps/customer/README.md` — Maps key runbook.
- `test/router/token_gate_test.dart`, `test/auth/otp_flow_widget_test.dart` — override profile fetch (boot hydration).

---

## Task 1: Profile module — DTO + repository

**Files:**
- Create: `lib/features/profile/data/profile_dtos.dart`, `lib/features/profile/data/profile_repository.dart`
- Test: `test/profile/profile_repository_test.dart`

**Interfaces:**
- Consumes: `core/result.dart` (`Result`/`Ok`/`Failure`/`FailureKind`/`failureKindFromStatus`), `core/network/dio_client.dart` (`dioProvider`).
- Produces:
  - `CustomerProfileDto({required String id, required String role, required String name, required String status})` + `.fromJson`.
  - `ProfileRepository(Dio)` with `Future<Result<CustomerProfileDto>> getProfile()` and `Future<Result<CustomerProfileDto>> updateName(String name)`.
  - `final profileRepositoryProvider = Provider<ProfileRepository>(...)`.

- [ ] **Step 1: Write the failing test** — `test/profile/profile_repository_test.dart`

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:fixcare_customer/core/result.dart';
import 'package:fixcare_customer/features/profile/data/profile_repository.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late ProfileRepository repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://test', validateStatus: (_) => true));
    adapter = DioAdapter(dio: dio);
    repo = ProfileRepository(dio);
  });

  test('getProfile 200 -> Ok(dto)', () async {
    adapter.onGet('/me/profile',
        (s) => s.reply(200, {'id': 'u1', 'role': 'CUSTOMER', 'name': 'Ravi', 'status': 'ACTIVE'}));
    final r = await repo.getProfile();
    expect((r as Ok<CustomerProfileDto>).value.name, 'Ravi');
  });

  test('getProfile 401 -> Failure(unauthorized)', () async {
    adapter.onGet('/me/profile', (s) => s.reply(401, {'code': 'UNAUTHORIZED', 'message': 'nope'}));
    final r = await repo.getProfile();
    final f = r as Failure;
    expect(f.kind, FailureKind.unauthorized);
    expect(f.message, 'nope'); // reads {message}, not {error}
  });

  test('updateName PATCHes exactly {name} and 200 -> Ok(dto)', () async {
    adapter.onPatch('/me/profile',
        (s) => s.reply(200, {'id': 'u1', 'role': 'CUSTOMER', 'name': 'Sita', 'status': 'ACTIVE'}),
        data: {'name': 'Sita'});
    final r = await repo.updateName('Sita');
    expect((r as Ok<CustomerProfileDto>).value.name, 'Sita');
  });

  test('updateName 400 -> Failure(validation) with server message', () async {
    adapter.onPatch('/me/profile',
        (s) => s.reply(400, {'code': 'VALIDATION', 'message': 'name must not be empty'}),
        data: {'name': ''});
    final r = await repo.updateName('');
    final f = r as Failure;
    expect(f.kind, FailureKind.validation);
    expect(f.message, 'name must not be empty');
  });
}
```

- [ ] **Step 2: Run to verify it fails** — `flutter test test/profile/profile_repository_test.dart` → FAIL (ProfileRepository not defined).

- [ ] **Step 3: Write `profile_dtos.dart`**

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
part 'profile_dtos.freezed.dart';
part 'profile_dtos.g.dart';

@freezed
abstract class CustomerProfileDto with _$CustomerProfileDto {
  const factory CustomerProfileDto({
    required String id,
    required String role,
    required String name,
    required String status,
  }) = _CustomerProfileDto;
  factory CustomerProfileDto.fromJson(Map<String, dynamic> j) => _$CustomerProfileDtoFromJson(j);
}
```

- [ ] **Step 4: Write `profile_repository.dart`**

```dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/result.dart';
import 'profile_dtos.dart';

export 'profile_dtos.dart';

class ProfileRepository {
  ProfileRepository(this._dio);
  final Dio _dio;

  // Backend error envelope is { code, message } (errorHandler.ts).
  String _msg(dynamic data) =>
      (data is Map && data['message'] is String) ? data['message'] as String : 'Something went wrong.';

  Result<CustomerProfileDto> _parse(Response res) {
    final status = res.statusCode ?? 0;
    if (status >= 200 && status < 300) {
      final data = res.data;
      if (data is! Map) return const Failure(FailureKind.server, 'Unexpected response from the server.');
      return Ok(CustomerProfileDto.fromJson(data.cast<String, dynamic>()));
    }
    return Failure(failureKindFromStatus(status), _msg(res.data));
  }

  Future<Result<CustomerProfileDto>> getProfile() async {
    try {
      return _parse(await _dio.get('/me/profile'));
    } on DioException catch (e) {
      if (e.response != null) {
        return Failure(failureKindFromStatus(e.response!.statusCode), _msg(e.response!.data));
      }
      return const Failure(FailureKind.network, 'Network error. Check your connection.');
    }
  }

  Future<Result<CustomerProfileDto>> updateName(String name) async {
    try {
      return _parse(await _dio.patch('/me/profile', data: {'name': name}));
    } on DioException catch (e) {
      if (e.response != null) {
        return Failure(failureKindFromStatus(e.response!.statusCode), _msg(e.response!.data));
      }
      return const Failure(FailureKind.network, 'Network error. Check your connection.');
    }
  }
}

final profileRepositoryProvider =
    Provider<ProfileRepository>((ref) => ProfileRepository(ref.read(dioProvider)));
```

- [ ] **Step 5: Codegen** — `dart run build_runner build --delete-conflicting-outputs` → generates `profile_dtos.freezed.dart` + `.g.dart`.

- [ ] **Step 6: Run test to verify it passes** — `flutter test test/profile/profile_repository_test.dart` → PASS (4/4).

- [ ] **Step 7: analyze** — `flutter analyze` → clean.

- [ ] **Step 8: Commit**

```bash
git add lib/features/profile/data test/profile
git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(customer): profile module — CustomerProfileDto + repository (slice 2)"
```

---

## Task 2: Session carries the profile

**Files:**
- Modify: `lib/features/auth/domain/session.dart`
- Modify: `lib/core/router/app_router.dart:56-62` (the switch — only the `SessionAuthenticated()` arm compiles unchanged; add name access), `lib/features/home/presentation/home_screen.dart` (no Session read today — leave), `lib/features/auth/presentation/auth_controller.dart` (constructs `SessionAuthenticated` — updated fully in Task 3)
- Modify: `test/auth/otp_flow_widget_test.dart` (its fake constructs no Session directly — leave; profile override added in Task 4), `test/router/token_gate_test.dart` (leave; Task 4)

**Interfaces:**
- Produces: `SessionAuthenticated({required CustomerProfileDto profile, required bool hydrated})` with getters `String get name => profile.name;`. `SessionUnauthenticated` unchanged.
- Consumes: `CustomerProfileDto` (Task 1).

**Note on interim compile:** After this task `auth_controller.dart` won't compile until Task 3 (it still builds `SessionAuthenticated(UserDto(...))`). That is expected — **Tasks 2 and 3 are committed together** (Task 2 has no standalone green state). Do Task 2's edits, then Task 3's, then run tests once and commit both. (Task 2 kept separate here only for reviewer clarity of the type change.)

- [ ] **Step 1: Rewrite `session.dart`**

```dart
import '../../profile/data/profile_dtos.dart';

/// The customer's resolved auth state. "Booting" is AsyncLoading on the
/// controller, not a member here.
sealed class Session {
  const Session();
}

class SessionUnauthenticated extends Session {
  const SessionUnauthenticated();
}

/// Authenticated. [profile] is the real user. [hydrated] is true when the
/// profile was fetched successfully this session; false means we have a token
/// but the boot fetch failed on network (option a: stay logged in, don't
/// name-gate). The name-gate only fires when hydrated && name is empty.
class SessionAuthenticated extends Session {
  final CustomerProfileDto profile;
  final bool hydrated;
  const SessionAuthenticated(this.profile, {this.hydrated = true});

  String get name => profile.name;
}
```

- [ ] **Step 2:** proceed directly to Task 3 (no build/commit yet — see note above).

---

## Task 3: AuthController boot hydration + submitOtp + updateName

**Files:**
- Modify: `lib/features/auth/presentation/auth_controller.dart`
- Modify: `lib/core/storage/token_store.dart` (persist phone for Account)
- Test: `test/auth/auth_controller_boot_test.dart`

**Interfaces:**
- Consumes: `profileRepositoryProvider` (Task 1), `SessionAuthenticated(profile, {hydrated})` (Task 2), `tokenStoreProvider`, `authRepositoryProvider`.
- Produces: `AuthController` with `build()` (hydrating), `requestOtp`, `submitOtp`, `updateName(String) → Future<Result<void>>`, `logout`, `onAuthLost`. `TokenStore.savePhone/readPhone`.

- [ ] **Step 1: Write the failing test** — `test/auth/auth_controller_boot_test.dart`

```dart
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fixcare_customer/core/result.dart';
import 'package:fixcare_customer/core/storage/token_store.dart';
import 'package:fixcare_customer/features/auth/domain/session.dart';
import 'package:fixcare_customer/features/auth/presentation/auth_controller.dart';
import 'package:fixcare_customer/features/profile/data/profile_repository.dart';

class _FakeProfileRepo extends ProfileRepository {
  _FakeProfileRepo(this._result) : super(Dio());
  final Result<CustomerProfileDto> _result;
  @override
  Future<Result<CustomerProfileDto>> getProfile() async => _result;
  @override
  Future<Result<CustomerProfileDto>> updateName(String name) async =>
      Ok(CustomerProfileDto(id: 'u1', role: 'CUSTOMER', name: name, status: 'ACTIVE'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backing = <String, String>{};

  void mockStorage() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        switch (call.method) {
          case 'write': backing[call.arguments['key'] as String] = call.arguments['value'] as String; return null;
          case 'read': return backing[call.arguments['key'] as String];
          case 'delete': backing.remove(call.arguments['key'] as String); return null;
          case 'deleteAll': backing.clear(); return null;
          case 'readAll': return Map<String, String>.from(backing);
          case 'containsKey': return backing.containsKey(call.arguments['key'] as String);
        }
        return null;
      },
    );
  }

  setUp(() { backing.clear(); mockStorage(); });

  Future<Session> boot(Result<CustomerProfileDto> profileResult) async {
    final container = ProviderContainer(overrides: [
      profileRepositoryProvider.overrideWithValue(_FakeProfileRepo(profileResult)),
    ]);
    addTearDown(container.dispose);
    return container.read(authControllerProvider.future);
  }

  test('no token -> Unauthenticated', () async {
    final s = await boot(const Ok(CustomerProfileDto(id: 'u1', role: 'CUSTOMER', name: 'Ravi', status: 'ACTIVE')));
    expect(s, isA<SessionUnauthenticated>());
  });

  test('token + named profile -> Authenticated(hydrated, named)', () async {
    backing['fixcare.access'] = 'a'; backing['fixcare.refresh'] = 'r';
    final s = await boot(const Ok(CustomerProfileDto(id: 'u1', role: 'CUSTOMER', name: 'Ravi', status: 'ACTIVE')));
    final a = s as SessionAuthenticated;
    expect(a.hydrated, true);
    expect(a.name, 'Ravi');
  });

  test('token + empty-name profile -> Authenticated(hydrated, name empty)', () async {
    backing['fixcare.access'] = 'a'; backing['fixcare.refresh'] = 'r';
    final s = await boot(const Ok(CustomerProfileDto(id: 'u1', role: 'CUSTOMER', name: '', status: 'ACTIVE')));
    final a = s as SessionAuthenticated;
    expect(a.hydrated, true);
    expect(a.name, '');
  });

  test('token + 401 -> tokens cleared, Unauthenticated', () async {
    backing['fixcare.access'] = 'a'; backing['fixcare.refresh'] = 'r';
    final s = await boot(const Failure(FailureKind.unauthorized, 'stale'));
    expect(s, isA<SessionUnauthenticated>());
    expect(backing['fixcare.access'], isNull);
  });

  test('token + network fail -> Authenticated but NOT hydrated (stays logged in)', () async {
    backing['fixcare.access'] = 'a'; backing['fixcare.refresh'] = 'r';
    final s = await boot(const Failure(FailureKind.network, 'offline'));
    final a = s as SessionAuthenticated;
    expect(a.hydrated, false);
    expect(backing['fixcare.access'], 'a'); // not cleared
  });
}
```

- [ ] **Step 2: Run to verify it fails** — `flutter test test/auth/auth_controller_boot_test.dart` → FAIL.

- [ ] **Step 3: Add phone persistence to `token_store.dart`** (add inside `TokenStore`, keep existing members)

```dart
  static const _kPhone = 'fixcare.phone';
  Future<void> savePhone(String phone) => _s.write(key: _kPhone, value: phone);
  Future<String?> readPhone() => _s.read(key: _kPhone);
```

Also add phone deletion to `clear()`:

```dart
  Future<void> clear() async {
    await _s.delete(key: _kAccess);
    await _s.delete(key: _kRefresh);
    await _s.delete(key: _kPhone);
  }
```

- [ ] **Step 4: Rewrite `auth_controller.dart`**

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/result.dart';
import '../../../core/storage/token_store.dart';
import '../../profile/data/profile_repository.dart';
import '../data/auth_repository.dart';
import '../domain/session.dart';

part 'auth_controller.g.dart';

@Riverpod(keepAlive: true)
class AuthController extends _$AuthController {
  @override
  Future<Session> build() async {
    final access = await ref.read(tokenStoreProvider).readAccess();
    if (access == null) return const SessionUnauthenticated();
    return _hydrate();
  }

  /// Token present → fetch the real profile. 401 = stale token → clear + logout.
  /// network/other = stay logged in but unhydrated (option a): don't eject the
  /// user or name-gate on a transient blip.
  Future<Session> _hydrate() async {
    final r = await ref.read(profileRepositoryProvider).getProfile();
    switch (r) {
      case Ok(value: final profile):
        return SessionAuthenticated(profile, hydrated: true);
      case Failure(kind: FailureKind.unauthorized):
        await ref.read(tokenStoreProvider).clear();
        return const SessionUnauthenticated();
      case Failure():
        return const SessionAuthenticated(
          CustomerProfileDto(id: '', role: 'CUSTOMER', name: '', status: 'ACTIVE'),
          hydrated: false,
        );
    }
  }

  Future<Result<SendOtpResponse>> requestOtp(String phone) =>
      ref.read(authRepositoryProvider).sendOtp(phone);

  Future<Result<void>> submitOtp(String phone, String code) async {
    final r = await ref.read(authRepositoryProvider).verifyOtp(phone, code);
    if (r is Ok<VerifyResponse>) {
      final store = ref.read(tokenStoreProvider);
      await store.save(access: r.value.accessToken, refresh: r.value.refreshToken);
      await store.savePhone(phone);
      // verify's user has no name — fetch the real profile so the name-gate works.
      state = AsyncData(await _hydrate());
      return const Ok(null);
    }
    final f = r as Failure<VerifyResponse>;
    return Failure(f.kind, f.message);
  }

  /// Update the display name; on success re-emit the session with the new name.
  Future<Result<void>> updateName(String name) async {
    final r = await ref.read(profileRepositoryProvider).updateName(name);
    if (r is Ok<CustomerProfileDto>) {
      state = AsyncData(SessionAuthenticated(r.value, hydrated: true));
      return const Ok(null);
    }
    final f = r as Failure<CustomerProfileDto>;
    return Failure(f.kind, f.message);
  }

  Future<void> logout() async {
    final refresh = await ref.read(tokenStoreProvider).readRefresh();
    if (refresh != null) {
      await ref.read(authRepositoryProvider).logout(refresh);
    }
    await ref.read(tokenStoreProvider).clear();
    state = const AsyncData(SessionUnauthenticated());
  }

  void onAuthLost() => state = const AsyncData(SessionUnauthenticated());
}
```

- [ ] **Step 5: Codegen** — `dart run build_runner build --delete-conflicting-outputs`.

- [ ] **Step 6: Run the boot test** — `flutter test test/auth/auth_controller_boot_test.dart` → PASS (5/5).

- [ ] **Step 7: analyze** — `flutter analyze` → clean (Task-2 session.dart + this now compile together).

- [ ] **Step 8: Commit (Tasks 2 + 3 together)**

```bash
git add lib/features/auth/domain/session.dart lib/features/auth/presentation/auth_controller.dart lib/core/storage/token_store.dart test/auth/auth_controller_boot_test.dart
git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(customer): boot-hydrate session from /me/profile + updateName + persist phone (slice 2)"
```

---

## Task 4: Fix the two Slice-1 widget tests for boot hydration

The `token_gate_test` and `otp_flow_widget_test` now trigger a real `/me/profile` fetch (via the real `profileRepositoryProvider`) which fails with no backend. Override the profile repo so they stay deterministic.

**Files:**
- Modify: `test/router/token_gate_test.dart`, `test/auth/otp_flow_widget_test.dart`

**Interfaces:**
- Consumes: `profileRepositoryProvider`, `CustomerProfileDto`, `ProfileRepository`.

- [ ] **Step 1: token_gate_test** — add a fake profile repo and override it. At top of the file add:

```dart
import 'package:dio/dio.dart';
import 'package:fixcare_customer/features/profile/data/profile_repository.dart';

class _FakeProfileRepo extends ProfileRepository {
  _FakeProfileRepo() : super(Dio());
  @override
  Future<Result<CustomerProfileDto>> getProfile() async =>
      const Ok(CustomerProfileDto(id: 'u1', role: 'CUSTOMER', name: 'Ravi', status: 'ACTIVE'));
  @override
  Future<Result<CustomerProfileDto>> updateName(String name) async =>
      Ok(CustomerProfileDto(id: 'u1', role: 'CUSTOMER', name: name, status: 'ACTIVE'));
}
```

Add the `Result`/`Ok` import (`package:fixcare_customer/core/result.dart`). In `pumpApp`, add the override to the `ProviderScope`:

```dart
      ProviderScope(
        overrides: [profileRepositoryProvider.overrideWithValue(_FakeProfileRepo())],
        child: Consumer( ... ),
      ),
```

The "token present → lands on home" test now boots with a named profile → `/home` (unchanged expectation). The "no token" test never calls getProfile → `/phone` (unchanged).

- [ ] **Step 2: otp_flow_widget_test** — the `_FakeAuthRepository.verifyOtp` returns tokens; `submitOtp` then calls `getProfile`. Add a fake profile repo returning a **named** profile (so it lands on home, not the name-gate) and override it. Add near `_FakeAuthRepository`:

```dart
import 'package:fixcare_customer/features/profile/data/profile_repository.dart';

class _FakeProfileRepo extends ProfileRepository {
  _FakeProfileRepo() : super(Dio());
  @override
  Future<Result<CustomerProfileDto>> getProfile() async =>
      const Ok(CustomerProfileDto(id: 'u1', role: 'CUSTOMER', name: 'Ravi', status: 'ACTIVE'));
  @override
  Future<Result<CustomerProfileDto>> updateName(String name) async =>
      Ok(CustomerProfileDto(id: 'u1', role: 'CUSTOMER', name: name, status: 'ACTIVE'));
}
```

In BOTH `ProviderScope`s of that file add `profileRepositoryProvider.overrideWithValue(_FakeProfileRepo())` to `overrides`. The happy-path test still ends on `find.text('What needs fixing?')`.

- [ ] **Step 3: Run both** — `flutter test test/router/token_gate_test.dart test/auth/otp_flow_widget_test.dart` → PASS.

- [ ] **Step 4: Full suite** — `flutter test` → all green (prior 16 + Task 1's 4 + Task 3's 5).

- [ ] **Step 5: Commit**

```bash
git add test/router/token_gate_test.dart test/auth/otp_flow_widget_test.dart
git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "test(customer): override profile fetch in slice-1 widget tests for boot hydration (slice 2)"
```

---

## Task 5: Name-gate routing + name capture screen

**Files:**
- Modify: `lib/core/router/app_router.dart`
- Create: `lib/features/profile/presentation/name_capture_screen.dart`
- Test: `test/router/name_gate_test.dart`

**Interfaces:**
- Consumes: `authControllerProvider`, `SessionAuthenticated` (`.name`, `.hydrated`), `updateName`.
- Produces: routes `/name`,`/account`,`/addresses`,`/address/new`,`/address/:id/edit`; `NameCaptureScreen`.

- [ ] **Step 1: Write the failing test** — `test/router/name_gate_test.dart`

```dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fixcare_customer/core/result.dart';
import 'package:fixcare_customer/core/router/app_router.dart';
import 'package:fixcare_customer/features/profile/data/profile_repository.dart';

class _NamelessRepo extends ProfileRepository {
  _NamelessRepo() : super(Dio());
  @override
  Future<Result<CustomerProfileDto>> getProfile() async =>
      const Ok(CustomerProfileDto(id: 'u1', role: 'CUSTOMER', name: '', status: 'ACTIVE'));
  @override
  Future<Result<CustomerProfileDto>> updateName(String name) async =>
      Ok(CustomerProfileDto(id: 'u1', role: 'CUSTOMER', name: name, status: 'ACTIVE'));
}

class _NamedRepo extends ProfileRepository {
  _NamedRepo() : super(Dio());
  @override
  Future<Result<CustomerProfileDto>> getProfile() async =>
      const Ok(CustomerProfileDto(id: 'u1', role: 'CUSTOMER', name: 'Ravi', status: 'ACTIVE'));
  @override
  Future<Result<CustomerProfileDto>> updateName(String name) async =>
      Ok(CustomerProfileDto(id: 'u1', role: 'CUSTOMER', name: name, status: 'ACTIVE'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backing = <String, String>{'fixcare.access': 'a', 'fixcare.refresh': 'r'};

  void mockStorage() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        switch (call.method) {
          case 'write': backing[call.arguments['key'] as String] = call.arguments['value'] as String; return null;
          case 'read': return backing[call.arguments['key'] as String];
          case 'delete': backing.remove(call.arguments['key'] as String); return null;
          case 'deleteAll': backing.clear(); return null;
          case 'readAll': return Map<String, String>.from(backing);
          case 'containsKey': return backing.containsKey(call.arguments['key'] as String);
        }
        return null;
      },
    );
  }

  setUp(mockStorage);

  Future<String> pump(WidgetTester tester, ProfileRepository repo) async {
    late GoRouter router;
    await tester.pumpWidget(ProviderScope(
      overrides: [profileRepositoryProvider.overrideWithValue(repo)],
      child: Consumer(builder: (c, ref, _) {
        router = ref.watch(goRouterProvider);
        return MaterialApp.router(routerConfig: router);
      }),
    ));
    await tester.pumpAndSettle();
    return router.routerDelegate.currentConfiguration.uri.path;
  }

  testWidgets('authenticated + empty name -> /name', (tester) async {
    expect(await pump(tester, _NamelessRepo()), '/name');
  });

  testWidgets('authenticated + named -> /home', (tester) async {
    expect(await pump(tester, _NamedRepo()), '/home');
  });
}
```

- [ ] **Step 2: Run to verify it fails** — `flutter test test/router/name_gate_test.dart` → FAIL (route `/name` missing; no gate).

- [ ] **Step 3: Write `name_capture_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result.dart';
import '../../../core/theme.dart';
import '../../auth/presentation/auth_controller.dart';

class NameCaptureScreen extends ConsumerStatefulWidget {
  const NameCaptureScreen({super.key});
  @override
  ConsumerState<NameCaptureScreen> createState() => _NameCaptureScreenState();
}

class _NameCaptureScreenState extends ConsumerState<NameCaptureScreen> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  Future<void> _continue() async {
    final name = _controller.text.trim();
    if (name.isEmpty) { setState(() => _error = 'Please enter your name.'); return; }
    setState(() { _error = null; _busy = true; });
    final res = await ref.read(authControllerProvider.notifier).updateName(name);
    if (!mounted) return;
    setState(() => _busy = false);
    // On Ok the session flips to a named profile → the router redirect lands /home.
    if (res is Failure) {
      setState(() => _error = (res as Failure).message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('What should we call you?', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 6),
              const Text('This is the name your technician will see.',
                  style: TextStyle(fontSize: 14.5, color: FixCareColors.textMuted, height: 1.5)),
              const SizedBox(height: 26),
              TextField(
                key: const Key('nameField'),
                controller: _controller,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: 'Your name', errorText: _error),
              ),
              const Spacer(),
              FilledButton(
                key: const Key('nameContinueBtn'),
                onPressed: _busy ? null : _continue,
                child: _busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Edit `app_router.dart`** — add imports, the name-gate, and routes. Add imports at top:

```dart
import '../../features/profile/presentation/name_capture_screen.dart';
import '../../features/profile/presentation/account_screen.dart';
import '../../features/address/presentation/address_list_screen.dart';
import '../../features/address/presentation/address_form_screen.dart';
```

Replace the `SessionAuthenticated()` switch arm with a name-gated version:

```dart
      switch (session) {
        case SessionUnauthenticated():
          return onAuthScreen ? null : '/phone';
        case SessionAuthenticated(hydrated: final hydrated, name: final name):
          // Hydrated but nameless → force name capture (allow only /name).
          if (hydrated && name.trim().isEmpty) {
            return loc == '/name' ? null : '/name';
          }
          // Named (or unhydrated): keep them out of splash/auth/name screens.
          if (loc == '/splash' || onAuthScreen || loc == '/name') return '/home';
          return null;
      }
```

Add the routes to the `routes:` list (after `/home`):

```dart
      GoRoute(path: '/name', builder: (_, _) => const NameCaptureScreen()),
      GoRoute(path: '/account', builder: (_, _) => const AccountScreen()),
      GoRoute(path: '/addresses', builder: (_, _) => const AddressListScreen()),
      GoRoute(path: '/address/new', builder: (_, _) => const AddressFormScreen(addressId: null)),
      GoRoute(
        path: '/address/:id/edit',
        builder: (_, state) => AddressFormScreen(addressId: state.pathParameters['id']),
      ),
```

**Note:** `AccountScreen`, `AddressListScreen`, `AddressFormScreen` are created in Tasks 6/8/9. To keep this task compiling in isolation, create minimal stub files now (they'll be filled in later) OR sequence: create the stubs as part of this task. **Do the stubs here** — add three files each with a `const ClassName({super.key})` (and `AddressFormScreen({super.key, required this.addressId}); final String? addressId;`) returning `Scaffold(body: Center(child: Text('<name>')))`. Tasks 6/8/9 replace the bodies.

- [ ] **Step 5: Create the three stubs** so the router compiles:

`lib/features/profile/presentation/account_screen.dart`:
```dart
import 'package:flutter/material.dart';
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Account')));
}
```
`lib/features/address/presentation/address_list_screen.dart`:
```dart
import 'package:flutter/material.dart';
class AddressListScreen extends StatelessWidget {
  const AddressListScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Addresses')));
}
```
`lib/features/address/presentation/address_form_screen.dart`:
```dart
import 'package:flutter/material.dart';
class AddressFormScreen extends StatelessWidget {
  const AddressFormScreen({super.key, required this.addressId});
  final String? addressId;
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: Text(addressId == null ? 'New address' : 'Edit $addressId')));
}
```

- [ ] **Step 6: Run** — `flutter test test/router/name_gate_test.dart` → PASS (2/2).

- [ ] **Step 7: analyze + full suite** — `flutter analyze` clean; `flutter test` green.

- [ ] **Step 8: Commit**

```bash
git add lib/core/router/app_router.dart lib/features/profile/presentation lib/features/address/presentation/address_list_screen.dart lib/features/address/presentation/address_form_screen.dart test/router/name_gate_test.dart
git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(customer): name-gate routing + name capture screen + route stubs (slice 2)"
```

---

## Task 6: Account screen

**Files:**
- Modify: `lib/features/profile/presentation/account_screen.dart` (replace the stub)
- Modify: `lib/features/home/presentation/home_screen.dart:58-75` (avatar → `/account` instead of logout)

**Interfaces:**
- Consumes: `authControllerProvider` (session → `.profile.name`), `tokenStoreProvider.readPhone`, `updateName`, `logout`.

- [ ] **Step 1: Write `account_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/result.dart';
import '../../../core/storage/token_store.dart';
import '../../../core/theme.dart';
import '../../auth/domain/session.dart';
import '../../auth/presentation/auth_controller.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).valueOrNull;
    final name = session is SessionAuthenticated ? session.name : '';
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _NameTile(name: name),
          const SizedBox(height: 8),
          FutureBuilder<String?>(
            future: ref.read(tokenStoreProvider).readPhone(),
            builder: (c, snap) => _InfoRow(label: 'Mobile', value: snap.data == null ? '—' : '+91 ${snap.data}'),
          ),
          const SizedBox(height: 20),
          ListTile(
            key: const Key('myAddressesTile'),
            shape: RoundedRectangleBorder(
                side: const BorderSide(color: FixCareColors.border), borderRadius: BorderRadius.circular(FixCareRadii.card)),
            leading: const Icon(Icons.location_on_outlined, color: FixCareColors.primary),
            title: const Text('My addresses'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/addresses'),
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            key: const Key('signOutBtn'),
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              foregroundColor: FixCareColors.errorText,
              side: const BorderSide(color: FixCareColors.border),
            ),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label; final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(color: FixCareColors.textMuted)),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w600, color: FixCareColors.textPrimary)),
    ]),
  );
}

class _NameTile extends ConsumerStatefulWidget {
  const _NameTile({required this.name});
  final String name;
  @override
  ConsumerState<_NameTile> createState() => _NameTileState();
}

class _NameTileState extends ConsumerState<_NameTile> {
  bool _editing = false;
  late final TextEditingController _c = TextEditingController(text: widget.name);
  bool _busy = false;

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  Future<void> _save() async {
    final n = _c.text.trim();
    if (n.isEmpty) return;
    setState(() => _busy = true);
    final res = await ref.read(authControllerProvider.notifier).updateName(n);
    if (!mounted) return;
    setState(() { _busy = false; if (res is Ok) _editing = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (!_editing) {
      return _InfoRowEditable(
        label: 'Name', value: widget.name.isEmpty ? '—' : widget.name,
        onEdit: () => setState(() { _c.text = widget.name; _editing = true; }));
    }
    return Row(children: [
      Expanded(child: TextField(key: const Key('accountNameField'), controller: _c,
          textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Name'))),
      const SizedBox(width: 8),
      IconButton(
        key: const Key('accountNameSave'),
        onPressed: _busy ? null : _save,
        icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check, color: FixCareColors.success)),
    ]);
  }
}

class _InfoRowEditable extends StatelessWidget {
  const _InfoRowEditable({required this.label, required this.value, required this.onEdit});
  final String label; final String value; final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: FixCareColors.textMuted)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: FixCareColors.textPrimary)),
      ])),
      TextButton(key: const Key('editNameBtn'), onPressed: onEdit, child: const Text('Edit')),
    ]),
  );
}
```

- [ ] **Step 2: Edit `home_screen.dart`** — change the avatar `InkResponse` to navigate to `/account`. Replace `onTap: () => ref.read(authControllerProvider.notifier).logout(),` with `onTap: () => context.push('/account'),` and keep `key: const Key('logoutBtn')` renamed to `key: const Key('accountAvatar')`. Add `import 'package:go_router/go_router.dart';` to home_screen.dart. (The Home widget is a `ConsumerWidget` — `context.push` works.)

- [ ] **Step 3: analyze + test** — `flutter analyze` clean; `flutter test` green (no test asserts the old `logoutBtn` behavior — otp_flow lands on home via text, unaffected).

- [ ] **Step 4: Commit**

```bash
git add lib/features/profile/presentation/account_screen.dart lib/features/home/presentation/home_screen.dart
git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(customer): account screen (name edit, phone, sign out) + home avatar -> account (slice 2)"
```

---

## Task 7: Address module — DTOs + repository

**Files:**
- Create: `lib/features/address/data/address_dtos.dart`, `lib/features/address/data/address_repository.dart`
- Test: `test/address/address_repository_test.dart`

**Interfaces:**
- Produces:
  - `ZoneDto({required String id, required String name, required int visitFeePaise})`.
  - `AddressDto` with all fields (see Global Constraints) + `.fromJson`.
  - `ServiceabilityDto({required bool serviceable, ZoneDto? zone, String? message})`.
  - `CreateAddress`/`UpdateAddress` as plain `Map<String,dynamic> toJson()` value classes (or build the map inline in the repo — see below).
  - `AddressRepository(Dio)`: `list`, `create(Map body)`, `update(id, Map body)`, `delete(id)`, `checkServiceability(pincode)`.
  - `addressRepositoryProvider`.

- [ ] **Step 1: Write the failing test** — `test/address/address_repository_test.dart`

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:fixcare_customer/core/result.dart';
import 'package:fixcare_customer/features/address/data/address_repository.dart';

Map<String, dynamic> _addrJson({bool serviceable = true, bool isDefault = false}) => {
  'id': 'a1', 'label': 'Home', 'line1': '12 MG Road', 'line2': null, 'landmark': null,
  'pincode': '390001', 'lat': null, 'lng': null, 'isDefault': isDefault, 'status': 'ACTIVE',
  'serviceable': serviceable,
  'zone': serviceable ? {'id': 'z1', 'name': 'Vadodara', 'visitFeePaise': 14900} : null,
  if (!serviceable) 'message': "We don't serve this area yet",
};

void main() {
  late Dio dio; late DioAdapter adapter; late AddressRepository repo;
  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://test', validateStatus: (_) => true));
    adapter = DioAdapter(dio: dio);
    repo = AddressRepository(dio);
  });

  test('list 200 -> Ok(list)', () async {
    adapter.onGet('/me/addresses', (s) => s.reply(200, [_addrJson()]));
    final r = await repo.list();
    final v = (r as Ok<List<AddressDto>>).value;
    expect(v.single.label, 'Home');
    expect(v.single.zone!.visitFeePaise, 14900);
  });

  test('create POSTs the exact body and 201 -> Ok(dto)', () async {
    adapter.onPost('/me/addresses', (s) => s.reply(201, _addrJson()),
        data: {'label': 'Home', 'line1': '12 MG Road', 'pincode': '390001'});
    final r = await repo.create({'label': 'Home', 'line1': '12 MG Road', 'pincode': '390001'});
    expect((r as Ok<AddressDto>).value.id, 'a1');
  });

  test('create out-of-area still 201 -> Ok(serviceable:false + message)', () async {
    adapter.onPost('/me/addresses', (s) => s.reply(201, _addrJson(serviceable: false)),
        data: {'label': 'Home', 'line1': 'x', 'pincode': '999999'});
    final r = await repo.create({'label': 'Home', 'line1': 'x', 'pincode': '999999'});
    final dto = (r as Ok<AddressDto>).value;
    expect(dto.serviceable, false);
    expect(dto.message, isNotNull);
  });

  test('update PATCHes the body and 200 -> Ok', () async {
    adapter.onPatch('/me/addresses/a1', (s) => s.reply(200, _addrJson(isDefault: true)),
        data: {'isDefault': true});
    final r = await repo.update('a1', {'isDefault': true});
    expect((r as Ok<AddressDto>).value.isDefault, true);
  });

  test('delete 204 -> Ok(void)', () async {
    adapter.onDelete('/me/addresses/a1', (s) => s.reply(204, null));
    final r = await repo.delete('a1');
    expect(r, isA<Ok<void>>());
  });

  test('checkServiceability GET -> Ok(dto)', () async {
    adapter.onGet('/serviceability', (s) => s.reply(200, {'serviceable': true, 'zone': {'id': 'z1', 'name': 'Vadodara', 'visitFeePaise': 14900}}),
        queryParameters: {'pincode': '390001'});
    final r = await repo.checkServiceability('390001');
    expect((r as Ok<ServiceabilityDto>).value.zone!.name, 'Vadodara');
  });

  test('list 500 -> Failure(server) with {code,message} message', () async {
    adapter.onGet('/me/addresses', (s) => s.reply(500, {'code': 'INTERNAL_ERROR', 'message': 'boom'}));
    final r = await repo.list();
    final f = r as Failure;
    expect(f.kind, FailureKind.server);
    expect(f.message, 'boom');
  });
}
```

- [ ] **Step 2: Run to verify it fails** — `flutter test test/address/address_repository_test.dart` → FAIL.

- [ ] **Step 3: Write `address_dtos.dart`**

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
part 'address_dtos.freezed.dart';
part 'address_dtos.g.dart';

@freezed
abstract class ZoneDto with _$ZoneDto {
  const factory ZoneDto({required String id, required String name, required int visitFeePaise}) = _ZoneDto;
  factory ZoneDto.fromJson(Map<String, dynamic> j) => _$ZoneDtoFromJson(j);
}

@freezed
abstract class AddressDto with _$AddressDto {
  const factory AddressDto({
    required String id,
    required String label,
    required String line1,
    String? line2,
    String? landmark,
    required String pincode,
    double? lat,
    double? lng,
    required bool isDefault,
    required String status,
    required bool serviceable,
    ZoneDto? zone,
    String? message,
  }) = _AddressDto;
  factory AddressDto.fromJson(Map<String, dynamic> j) => _$AddressDtoFromJson(j);
}

@freezed
abstract class ServiceabilityDto with _$ServiceabilityDto {
  const factory ServiceabilityDto({required bool serviceable, ZoneDto? zone, String? message}) = _ServiceabilityDto;
  factory ServiceabilityDto.fromJson(Map<String, dynamic> j) => _$ServiceabilityDtoFromJson(j);
}
```

- [ ] **Step 4: Write `address_repository.dart`**

```dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/result.dart';
import 'address_dtos.dart';

export 'address_dtos.dart';

class AddressRepository {
  AddressRepository(this._dio);
  final Dio _dio;

  String _msg(dynamic data) =>
      (data is Map && data['message'] is String) ? data['message'] as String : 'Something went wrong.';

  Never _rethrowAsNever() => throw StateError('unreachable');

  Result<T> _ok<T>(Response res, T Function(dynamic data) parse) {
    final status = res.statusCode ?? 0;
    if (status >= 200 && status < 300) return Ok(parse(res.data));
    return Failure(failureKindFromStatus(status), _msg(res.data));
  }

  Future<Result<T>> _guard<T>(Future<Result<T>> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      if (e.response != null) {
        return Failure(failureKindFromStatus(e.response!.statusCode), _msg(e.response!.data));
      }
      return const Failure(FailureKind.network, 'Network error. Check your connection.');
    }
  }

  Future<Result<List<AddressDto>>> list() => _guard(() async {
    final res = await _dio.get('/me/addresses');
    return _ok<List<AddressDto>>(res, (data) =>
        (data as List).map((e) => AddressDto.fromJson((e as Map).cast<String, dynamic>())).toList());
  });

  Future<Result<AddressDto>> create(Map<String, dynamic> body) => _guard(() async {
    final res = await _dio.post('/me/addresses', data: body);
    return _ok<AddressDto>(res, (data) => AddressDto.fromJson((data as Map).cast<String, dynamic>()));
  });

  Future<Result<AddressDto>> update(String id, Map<String, dynamic> body) => _guard(() async {
    final res = await _dio.patch('/me/addresses/$id', data: body);
    return _ok<AddressDto>(res, (data) => AddressDto.fromJson((data as Map).cast<String, dynamic>()));
  });

  Future<Result<void>> delete(String id) => _guard(() async {
    final res = await _dio.delete('/me/addresses/$id');
    final status = res.statusCode ?? 0;
    if (status >= 200 && status < 300) return const Ok(null); // 204, empty body
    return Failure(failureKindFromStatus(status), _msg(res.data));
  });

  Future<Result<ServiceabilityDto>> checkServiceability(String pincode) => _guard(() async {
    final res = await _dio.get('/serviceability', queryParameters: {'pincode': pincode});
    return _ok<ServiceabilityDto>(res, (data) => ServiceabilityDto.fromJson((data as Map).cast<String, dynamic>()));
  });
}

final addressRepositoryProvider =
    Provider<AddressRepository>((ref) => AddressRepository(ref.read(dioProvider)));
```

(Remove the unused `_rethrowAsNever` helper — it's not needed; delete that line.)

- [ ] **Step 5: Codegen** — `dart run build_runner build --delete-conflicting-outputs`.

- [ ] **Step 6: Run test** — `flutter test test/address/address_repository_test.dart` → PASS (7/7).

- [ ] **Step 7: analyze** — `flutter analyze` → clean.

- [ ] **Step 8: Commit**

```bash
git add lib/features/address/data test/address/address_repository_test.dart
git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(customer): address module — DTOs + repository (list/create/update/delete/serviceability) (slice 2)"
```

---

## Task 8: Address list screen + controller + serviceability chip

**Files:**
- Create: `lib/features/address/presentation/address_controller.dart`, `lib/features/address/presentation/widgets/serviceability_chip.dart`
- Modify: `lib/features/address/presentation/address_list_screen.dart` (replace the stub)

**Interfaces:**
- Consumes: `addressRepositoryProvider`, `AddressDto`.
- Produces: `@riverpod class AddressController extends _$AddressController { Future<List<AddressDto>> build(); Future<void> refresh(); Future<Result<void>> setDefault(String id); Future<Result<void>> remove(String id); }`; `ServiceabilityChip({required bool serviceable})`.

- [ ] **Step 1: Write `serviceability_chip.dart`**

```dart
import 'package:flutter/material.dart';
import '../../../../core/theme.dart';

class ServiceabilityChip extends StatelessWidget {
  const ServiceabilityChip({super.key, required this.serviceable});
  final bool serviceable;

  @override
  Widget build(BuildContext context) {
    final ok = serviceable;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: ok ? const Color(0xFFE9F5EF) : FixCareColors.disabledFill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(ok ? Icons.check_circle : Icons.info_outline, size: 14,
            color: ok ? FixCareColors.success : FixCareColors.textMuted),
        const SizedBox(width: 5),
        Text(ok ? 'We serve this area' : 'Out of service area',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                color: ok ? FixCareColors.success : FixCareColors.textMuted)),
      ]),
    );
  }
}
```

- [ ] **Step 2: Write `address_controller.dart`**

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/result.dart';
import '../data/address_repository.dart';

part 'address_controller.g.dart';

@riverpod
class AddressController extends _$AddressController {
  @override
  Future<List<AddressDto>> build() async {
    final r = await ref.read(addressRepositoryProvider).list();
    return switch (r) {
      Ok(value: final list) => list,
      Failure(message: final m) => throw Exception(m),
    };
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final r = await ref.read(addressRepositoryProvider).list();
      return switch (r) {
        Ok(value: final list) => list,
        Failure(message: final m) => throw Exception(m),
      };
    });
  }

  Future<Result<void>> setDefault(String id) async {
    final r = await ref.read(addressRepositoryProvider).update(id, {'isDefault': true});
    if (r is Ok) { await refresh(); return const Ok(null); }
    final f = r as Failure;
    return Failure(f.kind, f.message);
  }

  Future<Result<void>> remove(String id) async {
    final r = await ref.read(addressRepositoryProvider).delete(id);
    if (r is Ok) { await refresh(); return const Ok(null); }
    final f = r as Failure;
    return Failure(f.kind, f.message);
  }
}
```

- [ ] **Step 3: Write `address_list_screen.dart`** (replace stub)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme.dart';
import '../data/address_dtos.dart';
import 'address_controller.dart';
import 'widgets/serviceability_chip.dart';

class AddressListScreen extends ConsumerWidget {
  const AddressListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(addressControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('My addresses')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('addAddressBtn'),
        backgroundColor: FixCareColors.primary,
        onPressed: () => context.push('/address/new'),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add address', style: TextStyle(color: Colors.white)),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _Retry(onRetry: () => ref.read(addressControllerProvider.notifier).refresh()),
        data: (list) => list.isEmpty
            ? const _Empty()
            : RefreshIndicator(
                onRefresh: () => ref.read(addressControllerProvider.notifier).refresh(),
                child: ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (c, i) => _AddressCard(a: list[i]),
                ),
              ),
      ),
    );
  }
}

class _AddressCard extends ConsumerWidget {
  const _AddressCard({required this.a});
  final AddressDto a;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FixCareColors.surface,
        borderRadius: BorderRadius.circular(FixCareRadii.card),
        border: Border.all(color: FixCareColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(a.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: FixCareColors.textPrimary)),
          const SizedBox(width: 8),
          if (a.isDefault) Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: FixCareColors.primaryTint, borderRadius: BorderRadius.circular(999)),
            child: const Text('Default', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: FixCareColors.primary)),
          ),
          const Spacer(),
          PopupMenuButton<String>(
            key: Key('addrMenu_${a.id}'),
            onSelected: (v) async {
              final ctrl = ref.read(addressControllerProvider.notifier);
              if (v == 'edit') { if (context.mounted) context.push('/address/${a.id}/edit'); }
              if (v == 'default') await ctrl.setDefault(a.id);
              if (v == 'delete') await ctrl.remove(a.id);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              if (!a.isDefault) const PopupMenuItem(value: 'default', child: Text('Set as default')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ]),
        const SizedBox(height: 4),
        Text([a.line1, if (a.line2 != null) a.line2, a.pincode].join(', '),
            style: const TextStyle(fontSize: 14, color: FixCareColors.textSecondary)),
        const SizedBox(height: 10),
        ServiceabilityChip(serviceable: a.serviceable),
      ]),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(padding: EdgeInsets.all(24),
      child: Text('No addresses yet.\nAdd your first address to book a repair.',
          textAlign: TextAlign.center, style: TextStyle(color: FixCareColors.textMuted))),
  );
}

class _Retry extends StatelessWidget {
  const _Retry({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text("Couldn't load your addresses.", style: TextStyle(color: FixCareColors.textMuted)),
      const SizedBox(height: 12),
      OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
    ]),
  );
}
```

- [ ] **Step 4: Codegen + analyze + test** — `dart run build_runner build --delete-conflicting-outputs`; `flutter analyze` clean; `flutter test` green (no new test file here — covered by repository test + the form widget test in Task 9; the list screen is exercised manually).

- [ ] **Step 5: Commit**

```bash
git add lib/features/address/presentation/address_controller.dart lib/features/address/presentation/address_list_screen.dart lib/features/address/presentation/widgets/serviceability_chip.dart
git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(customer): address list screen + controller + serviceability chip (slice 2)"
```

---

## Task 9: Address form screen + widget test (serviceability, save)

**Files:**
- Modify: `lib/features/address/presentation/address_form_screen.dart` (replace the stub)
- Test: `test/address/address_form_widget_test.dart`

**Interfaces:**
- Consumes: `addressRepositoryProvider` (checkServiceability, create, update), `addressControllerProvider` (refresh after save), `AddressDto`, `ServiceabilityDto`, `AddressMapPicker` (Task 10 — until then, a placeholder is inlined and Task 10 swaps it in).

**Debounce note:** the pincode serviceability check debounces ~400ms. In the widget test, use `tester.pump(const Duration(milliseconds: 450))` after entering the pincode to let the debounce fire.

- [ ] **Step 1: Write the failing widget test** — `test/address/address_form_widget_test.dart`

```dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fixcare_customer/core/result.dart';
import 'package:fixcare_customer/core/theme.dart';
import 'package:fixcare_customer/features/address/data/address_repository.dart';
import 'package:fixcare_customer/features/address/presentation/address_form_screen.dart';

class _FakeAddrRepo extends AddressRepository {
  _FakeAddrRepo(this._serviceable) : super(Dio());
  final bool _serviceable;
  int createCalls = 0;
  Map<String, dynamic>? lastCreateBody;

  @override
  Future<Result<ServiceabilityDto>> checkServiceability(String pincode) async =>
      Ok(ServiceabilityDto(
        serviceable: _serviceable,
        zone: _serviceable ? const ZoneDto(id: 'z1', name: 'Vadodara', visitFeePaise: 14900) : null,
        message: _serviceable ? null : "We don't serve this area yet",
      ));

  @override
  Future<Result<AddressDto>> create(Map<String, dynamic> body) async {
    createCalls++; lastCreateBody = body;
    return Ok(AddressDto(
      id: 'a1', label: body['label'] as String, line1: body['line1'] as String,
      pincode: body['pincode'] as String, isDefault: false, status: 'ACTIVE',
      serviceable: _serviceable, zone: null,
    ));
  }

  @override
  Future<Result<List<AddressDto>>> list() async => const Ok([]);
}

Future<void> _pump(WidgetTester tester, _FakeAddrRepo repo) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [addressRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(theme: buildFixCareTheme(), home: const AddressFormScreen(addressId: null)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('serviceable pincode shows the serve affordance', (tester) async {
    final repo = _FakeAddrRepo(true);
    await _pump(tester, repo);
    await tester.enterText(find.byKey(const Key('pincodeField')), '390001');
    await tester.pump(const Duration(milliseconds: 450)); // debounce
    await tester.pumpAndSettle();
    expect(find.text('We serve this area'), findsOneWidget);
  });

  testWidgets('out-of-area shows warning but save stays enabled and saves', (tester) async {
    final repo = _FakeAddrRepo(false);
    await _pump(tester, repo);
    await tester.enterText(find.byKey(const Key('labelField')), 'Home');
    await tester.enterText(find.byKey(const Key('line1Field')), '12 MG Road');
    await tester.enterText(find.byKey(const Key('pincodeField')), '999999');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(find.text('Out of service area'), findsOneWidget);
    // Save is still enabled and calls create.
    await tester.tap(find.byKey(const Key('saveAddressBtn')));
    await tester.pumpAndSettle();
    expect(repo.createCalls, 1);
    expect(repo.lastCreateBody!['pincode'], '999999');
  });
}
```

- [ ] **Step 2: Run to verify it fails** — `flutter test test/address/address_form_widget_test.dart` → FAIL (form is still the stub).

- [ ] **Step 3: Write `address_form_screen.dart`** (replace stub; map picker inlined as a placeholder for now, Task 10 swaps in the real widget)

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/result.dart';
import '../../../core/theme.dart';
import '../data/address_dtos.dart';
import '../data/address_repository.dart';
import 'address_controller.dart';
import 'widgets/serviceability_chip.dart';
// Task 10 adds: import 'widgets/address_map_picker.dart';

class AddressFormScreen extends ConsumerStatefulWidget {
  const AddressFormScreen({super.key, required this.addressId});
  final String? addressId;
  @override
  ConsumerState<AddressFormScreen> createState() => _AddressFormScreenState();
}

class _AddressFormScreenState extends ConsumerState<AddressFormScreen> {
  final _label = TextEditingController();
  final _line1 = TextEditingController();
  final _line2 = TextEditingController();
  final _landmark = TextEditingController();
  final _pincode = TextEditingController();
  double? _lat, _lng;
  bool _isDefault = false;

  Timer? _debounce;
  bool _checking = false;
  ServiceabilityDto? _svc;
  String? _svcError;
  bool _busy = false;
  String? _formError;

  bool get _isEdit => widget.addressId != null;

  @override
  void initState() {
    super.initState();
    _pincode.addListener(_onPincodeChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_label, _line1, _line2, _landmark, _pincode]) { c.dispose(); }
    super.dispose();
  }

  void _onPincodeChanged() {
    _debounce?.cancel();
    final p = _pincode.text.trim();
    if (p.length != 6) { setState(() { _svc = null; _svcError = null; }); return; }
    _debounce = Timer(const Duration(milliseconds: 400), _check);
  }

  Future<void> _check() async {
    setState(() { _checking = true; _svcError = null; });
    final r = await ref.read(addressRepositoryProvider).checkServiceability(_pincode.text.trim());
    if (!mounted) return;
    setState(() {
      _checking = false;
      switch (r) {
        case Ok(value: final s): _svc = s;
        case Failure(): _svc = null; _svcError = "Couldn't check — you can still save.";
      }
    });
  }

  Map<String, dynamic> _body() => {
    'label': _label.text.trim(),
    'line1': _line1.text.trim(),
    if (_line2.text.trim().isNotEmpty) 'line2': _line2.text.trim(),
    if (_landmark.text.trim().isNotEmpty) 'landmark': _landmark.text.trim(),
    'pincode': _pincode.text.trim(),
    if (_lat != null && _lng != null) 'lat': _lat, // both-or-neither
    if (_lat != null && _lng != null) 'lng': _lng,
    'isDefault': _isDefault,
  };

  Future<void> _save() async {
    if (_label.text.trim().isEmpty || _line1.text.trim().isEmpty || _pincode.text.trim().length != 6) {
      setState(() => _formError = 'Fill label, address line 1 and a 6-digit pincode.');
      return;
    }
    setState(() { _formError = null; _busy = true; });
    final repo = ref.read(addressRepositoryProvider);
    final r = _isEdit ? await repo.update(widget.addressId!, _body()) : await repo.create(_body());
    if (!mounted) return;
    setState(() => _busy = false);
    switch (r) {
      case Ok():
        await ref.read(addressControllerProvider.notifier).refresh();
        if (mounted) context.pop();
      case Failure(message: final m):
        setState(() => _formError = m);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit address' : 'Add address')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(key: const Key('labelField'), controller: _label,
              decoration: const InputDecoration(labelText: 'Label (Home, Work…)')),
          const SizedBox(height: 12),
          TextField(key: const Key('line1Field'), controller: _line1,
              decoration: const InputDecoration(labelText: 'Address line 1')),
          const SizedBox(height: 12),
          TextField(key: const Key('line2Field'), controller: _line2,
              decoration: const InputDecoration(labelText: 'Address line 2 (optional)')),
          const SizedBox(height: 12),
          TextField(key: const Key('landmarkField'), controller: _landmark,
              decoration: const InputDecoration(labelText: 'Landmark (optional)')),
          const SizedBox(height: 12),
          TextField(
            key: const Key('pincodeField'), controller: _pincode,
            keyboardType: TextInputType.number, maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Pincode', counterText: ''),
          ),
          const SizedBox(height: 8),
          if (_checking) const Text('Checking serviceability…', style: TextStyle(color: FixCareColors.textMuted, fontSize: 13)),
          if (!_checking && _svc != null) ServiceabilityChip(serviceable: _svc!.serviceable),
          if (!_checking && _svc != null && !_svc!.serviceable)
            const Padding(padding: EdgeInsets.only(top: 6),
              child: Text("We don't serve this area yet — you can still save it.",
                  style: TextStyle(color: FixCareColors.textMuted, fontSize: 13))),
          if (_svcError != null) Text(_svcError!, style: const TextStyle(color: FixCareColors.textMuted, fontSize: 13)),
          const SizedBox(height: 16),
          // Task 10 replaces this placeholder with AddressMapPicker.
          const _MapPlaceholder(),
          const SizedBox(height: 8),
          SwitchListTile(
            key: const Key('defaultSwitch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Set as default address'),
            value: _isDefault,
            activeThumbColor: FixCareColors.primary,
            onChanged: (v) => setState(() => _isDefault = v),
          ),
          if (_formError != null) Padding(padding: const EdgeInsets.only(bottom: 8),
            child: Text(_formError!, style: const TextStyle(color: FixCareColors.errorText, fontSize: 13))),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('saveAddressBtn'),
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : Text(_isEdit ? 'Save changes' : 'Save address'),
          ),
        ],
      ),
    );
  }
}

class _MapPlaceholder extends StatelessWidget {
  const _MapPlaceholder();
  @override
  Widget build(BuildContext context) => Container(
    height: 160,
    decoration: BoxDecoration(
      color: FixCareColors.surface,
      borderRadius: BorderRadius.circular(FixCareRadii.card),
      border: Border.all(color: FixCareColors.border),
    ),
    alignment: Alignment.center,
    child: const Text('Map (optional) — pin your exact location',
        style: TextStyle(color: FixCareColors.textMuted, fontSize: 13)),
  );
}
```

- [ ] **Step 4: Run test** — `flutter test test/address/address_form_widget_test.dart` → PASS (2/2).

- [ ] **Step 5: analyze + full suite** — `flutter analyze` clean; `flutter test` green.

- [ ] **Step 6: Commit**

```bash
git add lib/features/address/presentation/address_form_screen.dart test/address/address_form_widget_test.dart
git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(customer): add/edit address form — debounced serviceability + save (slice 2)"
```

---

## Task 10: Google Maps picker (graceful without a key) + platform wiring

**Files:**
- Modify: `pubspec.yaml` (add `google_maps_flutter`)
- Create: `lib/features/address/presentation/widgets/address_map_picker.dart`
- Modify: `lib/features/address/presentation/address_form_screen.dart` (swap `_MapPlaceholder` for `AddressMapPicker`)
- Modify: `android/app/src/main/AndroidManifest.xml` (Maps meta-data, placeholder value), `ios/Runner/AppDelegate.swift` (GMSServices, placeholder), `apps/customer/README.md` (runbook)

**Interfaces:**
- Consumes: `_lat`, `_lng`, an `onPicked(double lat, double lng)` callback.
- Produces: `AddressMapPicker({double? lat, double? lng, required void Function(double, double) onPicked})`.

- [ ] **Step 1: Add the dependency**

Run: `flutter pub add google_maps_flutter` (pins the latest stable compatible with Dart ^3.13 / Flutter 3.47). Then `flutter pub get`.

- [ ] **Step 2: Write `address_map_picker.dart` — graceful without a key**

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/env.dart';
import '../../../../core/theme.dart';

/// A tap-to-drop-pin map for the address lat/lng. If no Maps API key is
/// configured, renders a bordered placeholder instead of crashing — the rest
/// of the form still works. Whether a key exists is signalled by
/// Env.mapsEnabled (a --dart-define, default false) so debug/test builds
/// without a key don't attempt to instantiate the native map view.
class AddressMapPicker extends StatefulWidget {
  const AddressMapPicker({super.key, this.lat, this.lng, required this.onPicked});
  final double? lat;
  final double? lng;
  final void Function(double lat, double lng) onPicked;

  @override
  State<AddressMapPicker> createState() => _AddressMapPickerState();
}

class _AddressMapPickerState extends State<AddressMapPicker> {
  static const _vadodara = LatLng(22.3072, 73.1812);
  LatLng? _pin;

  @override
  void initState() {
    super.initState();
    if (widget.lat != null && widget.lng != null) _pin = LatLng(widget.lat!, widget.lng!);
  }

  @override
  Widget build(BuildContext context) {
    if (!Env.mapsEnabled) return const _MapPlaceholder();
    return ClipRRect(
      borderRadius: BorderRadius.circular(FixCareRadii.card),
      child: SizedBox(
        height: 180,
        child: GoogleMap(
          initialCameraPosition: CameraPosition(target: _pin ?? _vadodara, zoom: 14),
          onTap: (pos) {
            setState(() => _pin = pos);
            widget.onPicked(pos.latitude, pos.longitude);
          },
          markers: _pin == null ? {} : {Marker(markerId: const MarkerId('pin'), position: _pin!)},
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
        ),
      ),
    );
  }
}

class _MapPlaceholder extends StatelessWidget {
  const _MapPlaceholder();
  @override
  Widget build(BuildContext context) => Container(
    height: 160,
    decoration: BoxDecoration(
      color: FixCareColors.surface,
      borderRadius: BorderRadius.circular(FixCareRadii.card),
      border: Border.all(color: FixCareColors.border),
    ),
    alignment: Alignment.center,
    padding: const EdgeInsets.all(16),
    child: Text(
      kReleaseMode
          ? 'Map unavailable'
          : 'Map disabled — set MAPS_API_KEY + run with --dart-define=MAPS_ENABLED=true (see README).',
      textAlign: TextAlign.center,
      style: const TextStyle(color: FixCareColors.textMuted, fontSize: 13),
    ),
  );
}
```

- [ ] **Step 3: Add `Env.mapsEnabled`** to `lib/core/env.dart`:

```dart
  // Whether the Google Maps key is wired (opt-in via --dart-define). Default
  // false so builds/tests without a key never instantiate the native map view.
  static const bool mapsEnabled = bool.fromEnvironment('MAPS_ENABLED', defaultValue: false);
```

- [ ] **Step 4: Swap the placeholder in `address_form_screen.dart`** — add `import 'widgets/address_map_picker.dart';`, delete the local `_MapPlaceholder` class, and replace `const _MapPlaceholder(),` with:

```dart
          AddressMapPicker(
            lat: _lat, lng: _lng,
            onPicked: (lat, lng) => setState(() { _lat = lat; _lng = lng; }),
          ),
```

- [ ] **Step 5: Android manifest** — add inside `<application>` in `android/app/src/main/AndroidManifest.xml`:

```xml
        <!-- Google Maps API key. Do NOT commit a real key. Provide it at build
             time or via a git-ignored secrets file (see apps/customer/README.md).
             The map degrades to a placeholder when MAPS_ENABLED is not set. -->
        <meta-data android:name="com.google.android.geo.API_KEY"
            android:value="${MAPS_API_KEY}" />
```

And in `android/app/build.gradle.kts` `defaultConfig`, add a manifest placeholder default so the build doesn't fail when unset:

```kotlin
        manifestPlaceholders["MAPS_API_KEY"] = System.getenv("MAPS_API_KEY") ?: ""
```

- [ ] **Step 6: iOS AppDelegate** — `ios/Runner/AppDelegate.swift`: add `import GoogleMaps` and, in `didFinishLaunchingWithOptions` before `GeneratedPluginRegistrant`, a guarded key provide:

```swift
    // Google Maps key from an env var at build time; never committed. Without it
    // the map shows a placeholder (MAPS_ENABLED gate in Dart), so this is safe to
    // leave unset for testing.
    if let mapsKey = ProcessInfo.processInfo.environment["MAPS_API_KEY"], !mapsKey.isEmpty {
      GMSServices.provideAPIKey(mapsKey)
    }
```

(Comment in the file: for a real device build, set the key in the scheme's environment or hardcode locally — never commit it.)

- [ ] **Step 7: README runbook** — append the "Google Maps API key" section to `apps/customer/README.md` (the 5-step runbook from the design's "Maps API key runbook", plus: to enable the map at runtime, run with `--dart-define=MAPS_ENABLED=true` and the key wired per above; without it the placeholder shows).

- [ ] **Step 8: analyze + test** — `flutter analyze` clean; `flutter test` green (tests never set `MAPS_ENABLED`, so `AddressMapPicker` renders the placeholder — no native view instantiated, the form widget test still passes).

- [ ] **Step 9: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/core/env.dart lib/features/address/presentation/widgets/address_map_picker.dart lib/features/address/presentation/address_form_screen.dart android/app/src/main/AndroidManifest.xml android/app/build.gradle.kts ios/Runner/AppDelegate.swift README.md
git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(customer): google maps address pin-picker (graceful without key) + platform wiring + runbook (slice 2)"
```

---

## Task 11: Final verification + docs

**Files:**
- Modify: `STATUS.md`, `CHANGELOG.md`

- [ ] **Step 1: Codegen idempotent** — `dart run build_runner build --delete-conflicting-outputs` then `git status --short` → clean (all generated files committed).
- [ ] **Step 2: analyze** — `flutter analyze` → "No issues found!".
- [ ] **Step 3: full test suite** — `flutter test` → all green (16 prior + profile 4 + boot 5 + name-gate 2 + address repo 7 + address form 2 = 36).
- [ ] **Step 4: Update `STATUS.md`** — Last shipped: Slice 2 (boot hydration + profile + addresses + maps), on branch; Next targets → Slice 3 (catalog + booking creation). Note the Maps key is founder-provisioned before a real map test.
- [ ] **Step 5: Update `CHANGELOG.md`** — new dated entry summarizing the slice.
- [ ] **Step 6: Commit**

```bash
git add STATUS.md CHANGELOG.md
git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "docs(customer): STATUS + CHANGELOG for Slice 2 (profile + addresses + maps)"
```

---

## Self-Review

**Spec coverage:** boot hydration (Task 3) ✓; name capture + gate (Tasks 3,5) ✓; Account (Task 6) ✓; address list/add/edit/delete/default (Tasks 7,8,9) ✓; live serviceability (Task 9) ✓; Google Maps pin-drop graceful-no-key (Task 10) ✓; contract-guarded tests (Tasks 1,7) ✓; Session carries profile (Task 2) ✓; routing additions (Task 5) ✓; Maps runbook (Task 10) ✓; out-of-area warn-but-save (Task 9) ✓.

**Placeholder scan:** every code step has real code; no TBD/"handle errors"/"similar to". Stubs in Task 5 are explicit, minimal, real code, replaced in named later tasks.

**Type consistency:** `CustomerProfileDto{id,role,name,status}` used identically in Tasks 1,3,4,5. `SessionAuthenticated(profile,{hydrated})` + `.name` getter used in Tasks 2,3,5,6. `AddressDto`/`ServiceabilityDto`/`ZoneDto` fields consistent Tasks 7,8,9. Repo method names (`getProfile`,`updateName`,`list`,`create`,`update`,`delete`,`checkServiceability`) consistent across producer + consumers. `updateName` returns `Result<void>` in Task 3, consumed as such in Tasks 5,6.

**Spec gaps found & resolved (report to founder):**
1. **Phone not available client-side for Account.** Neither the session (`UserDto`) nor `CustomerProfileDto` carries phone; the design's Account "phone read-only from session" had no source. Resolved: **persist the phone in `TokenStore` at login** (`savePhone` in `submitOtp`, Task 3) and read it in Account (Task 6). Cost: phone lives in secure storage only, cleared on logout.
2. **Two Slice-1 widget tests break under boot hydration** (they'd hit a real `/me/profile`). Resolved: Task 4 overrides `profileRepositoryProvider` in both. This is a required, not optional, task.
3. **Map view instantiation without a key** can throw natively. Resolved: an `Env.mapsEnabled` (`--dart-define=MAPS_ENABLED`) gate so the native `GoogleMap` widget is only built when the key is wired; default builds/tests show the placeholder. This is stronger than "graceful" — it never instantiates the native view without a key.
