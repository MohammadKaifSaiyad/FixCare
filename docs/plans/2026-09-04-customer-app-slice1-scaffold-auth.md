# Customer App Slice 1 — Scaffold + Phone-OTP Auth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Flutter customer app (Android-first) where a homeowner logs in via phone OTP and lands on a stub home, with the access/refresh token lifecycle handled transparently by a dio interceptor.

**Architecture:** Feature-first Flutter app in `apps/customer`. Riverpod 2.x (`@riverpod` codegen) for state, go_router for navigation with a token-gate redirect, dio + a single-flight auth interceptor for the network layer, flutter_secure_storage for tokens, freezed/json_serializable for DTOs. Repositories return a typed `Result`, never raw dio/JSON.

**Tech Stack:** Flutter 3.47 (Dart 3), flutter_riverpod + riverpod_annotation/generator, go_router, dio, flutter_secure_storage, freezed, json_serializable, build_runner.

**Spec:** `docs/designs/2026-09-04-customer-app-slice1-scaffold-auth-design.md`

## Global Constraints

- **Android-first V1** — `flutter create` with `--platforms=android` (+ web for dev convenience). NO iOS.
- **Org/package:** `--org in.fixcare`, project name `fixcare_customer`, app dir `apps/customer`.
- **Base URL from `--dart-define=BASE_URL`**, default `http://10.0.2.2:3000` (Android-emulator route to host localhost). `Env.isDev = !kReleaseMode`.
- **Backend `/auth/*` EXACT shapes (verified against the source):**
  - `POST /auth/otp/send { phone }` → `{ ok: true, devOtp?: string }` (devOtp dev-only). 429 throttled.
  - `POST /auth/otp/verify { phone, code }` → `{ accessToken, refreshToken, user }`, `user = { id, role, status }`. 401 wrong/expired.
  - `POST /auth/refresh { refreshToken }` → `{ accessToken, refreshToken }` — **NO user field**. 401 on reuse/expiry.
  - `POST /auth/logout { refreshToken }` → `{ ok: true }`.
- Repositories return `Result<T>` (`Ok<T>` | `Failure(kind, message)`); `FailureKind` ∈ {network, unauthorized, rateLimited, validation, server, unknown}. No raw dio error/JSON above the data layer.
- The auth interceptor is the ONLY place a refresh happens; it must be single-flight (concurrent 401s → one refresh).
- Theme: Material 3, primary `#C2521B`, success `#1D6B4F`, Outfit font. Screens English-only.
- **Every task ends with `flutter analyze` clean + `flutter test` green.** After editing any `@riverpod`/freezed file, run `dart run build_runner build --delete-conflicting-outputs` before analyze/test.
- Run flutter from `apps/customer`. Commit author: `git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "..."` — NO Claude trailer.

---

### Task 1: Project scaffold + deps + theme + env (compiles, analyzes, trivial test passes)

**Files:**
- Create: the whole `apps/customer` Flutter project (via `flutter create`)
- Create/Modify: `apps/customer/pubspec.yaml`, `apps/customer/analysis_options.yaml`
- Create: `apps/customer/lib/core/env.dart`, `apps/customer/lib/core/theme.dart`
- Modify: `apps/customer/lib/main.dart`
- Create: `apps/customer/test/smoke_test.dart`
- Create: `apps/customer/README.md`

**Interfaces:**
- Produces: `Env.baseUrl` (String), `Env.isDev` (bool) in `core/env.dart`; `fixCareTheme` (ThemeData) in `core/theme.dart`; `FixCareApp` widget in `main.dart` (MaterialApp for now, becomes MaterialApp.router in Task 5).

- [ ] **Step 1: Scaffold the project**

From `apps/customer`'s PARENT (`apps/`), but the dir already exists with only README.md — so create into a temp and move, OR create in place. Run from repo root:

```bash
cd apps && flutter create --org in.fixcare --project-name fixcare_customer --platforms=android,web customer
```

If `flutter create` refuses because `customer/` is non-empty (the README), it still populates alongside it — verify `apps/customer/pubspec.yaml` and `apps/customer/lib/main.dart` now exist. Keep the existing `README.md` (Task 1 Step 8 overwrites it).

- [ ] **Step 2: Add dependencies**

From `apps/customer`:

```bash
flutter pub add flutter_riverpod riverpod_annotation go_router dio flutter_secure_storage freezed_annotation json_annotation
flutter pub add dev:riverpod_generator dev:build_runner dev:freezed dev:json_serializable dev:custom_lint dev:riverpod_lint
```

- [ ] **Step 3: analysis_options.yaml** — enable the lints + custom_lint:

```yaml
include: package:flutter_lints/flutter.yaml
analyzer:
  plugins:
    - custom_lint
  exclude:
    - "**/*.g.dart"
    - "**/*.freezed.dart"
```

- [ ] **Step 4: `lib/core/env.dart`**

```dart
import 'package:flutter/foundation.dart';

class Env {
  static const String baseUrl =
      String.fromEnvironment('BASE_URL', defaultValue: 'http://10.0.2.2:3000');
  static bool get isDev => !kReleaseMode;
}
```

- [ ] **Step 5: `lib/core/theme.dart`**

```dart
import 'package:flutter/material.dart';

const fixCarePrimary = Color(0xFFC2521B);
const fixCareSuccess = Color(0xFF1D6B4F);

ThemeData buildFixCareTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: fixCarePrimary,
    primary: fixCarePrimary,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Outfit', // bundled later; falls back to system until then
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52), // ≥48dp touch targets
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}
```

(Font asset bundling is deferred — the family name is set so it activates once the ttf is added; system font is a fine fallback and does not fail analyze/test.)

- [ ] **Step 6: `lib/main.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme.dart';

void main() => runApp(const ProviderScope(child: FixCareApp()));

class FixCareApp extends StatelessWidget {
  const FixCareApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FixCare',
      debugShowCheckedModeBanner: false,
      theme: buildFixCareTheme(),
      home: const Scaffold(body: Center(child: Text('FixCare'))),
    );
  }
}
```

- [ ] **Step 7: `test/smoke_test.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fixcare_customer/main.dart';

void main() {
  testWidgets('app boots and shows the brand name', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: FixCareApp()));
    expect(find.text('FixCare'), findsOneWidget);
  });
}
```

- [ ] **Step 8: README + verify**

Write `apps/customer/README.md` with the run commands (backend up, `flutter run --dart-define=BASE_URL=http://10.0.2.2:3000`, chrome variant, build_runner, test, analyze — copy from the design's "Run commands").

Run: `flutter analyze` (clean) and `flutter test` (smoke passes).

- [ ] **Step 9: Commit**

```bash
git add -A && git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(customer): Flutter scaffold — deps, theme, env, smoke test (slice 1)"
```

---

### Task 2: Result type + TokenStore + dio client

**Files:**
- Create: `lib/core/result.dart`, `lib/core/storage/token_store.dart`, `lib/core/network/dio_client.dart`
- Test: `test/core/token_store_test.dart`, `test/core/result_test.dart`

**Interfaces:**
- Produces:
  - `sealed class Result<T>` with `Ok<T>(T value)` and `Failure<T>(FailureKind kind, String message)`; `enum FailureKind { network, unauthorized, rateLimited, validation, server, unknown }`; a helper `FailureKind failureKindFromStatus(int? status)`.
  - `class TokenStore { Future<void> save({required String access, required String refresh}); Future<String?> readAccess(); Future<String?> readRefresh(); Future<void> clear(); }` + `tokenStoreProvider`.
  - `dioProvider` (Riverpod `@riverpod`) returning a configured `Dio` (baseUrl `Env.baseUrl`, JSON content-type, connect/receive timeouts 15s). Interceptor is added in Task 4.

- [ ] **Step 1: Failing tests** — `test/core/result_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fixcare_customer/core/result.dart';

void main() {
  test('failureKindFromStatus maps HTTP codes', () {
    expect(failureKindFromStatus(401), FailureKind.unauthorized);
    expect(failureKindFromStatus(429), FailureKind.rateLimited);
    expect(failureKindFromStatus(400), FailureKind.validation);
    expect(failureKindFromStatus(500), FailureKind.server);
    expect(failureKindFromStatus(503), FailureKind.server);
    expect(failureKindFromStatus(null), FailureKind.unknown);
  });
}
```

`test/core/token_store_test.dart` — use an in-memory map via `FlutterSecureStorage`'s test channel mock:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fixcare_customer/core/storage/token_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = <String, String>{};
  setUp(() {
    store.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        switch (call.method) {
          case 'write': store[call.arguments['key']] = call.arguments['value']; return null;
          case 'read': return store[call.arguments['key']];
          case 'delete': store.remove(call.arguments['key']); return null;
          case 'deleteAll': store.clear(); return null;
          case 'readAll': return Map<String, String>.from(store);
          case 'containsKey': return store.containsKey(call.arguments['key']);
        }
        return null;
      },
    );
  });

  test('save then read returns the tokens; clear removes them', () async {
    final ts = TokenStore();
    await ts.save(access: 'a1', refresh: 'r1');
    expect(await ts.readAccess(), 'a1');
    expect(await ts.readRefresh(), 'r1');
    await ts.clear();
    expect(await ts.readAccess(), isNull);
    expect(await ts.readRefresh(), isNull);
  });
}
```

Run `flutter test test/core/` → FAIL (files missing).

- [ ] **Step 2: `lib/core/result.dart`**

```dart
enum FailureKind { network, unauthorized, rateLimited, validation, server, unknown }

FailureKind failureKindFromStatus(int? status) {
  switch (status) {
    case 401: return FailureKind.unauthorized;
    case 429: return FailureKind.rateLimited;
    case 400: return FailureKind.validation;
    case null: return FailureKind.unknown;
    default: return status >= 500 ? FailureKind.server : FailureKind.unknown;
  }
}

sealed class Result<T> {
  const Result();
}

class Ok<T> extends Result<T> {
  final T value;
  const Ok(this.value);
}

class Failure<T> extends Result<T> {
  final FailureKind kind;
  final String message;
  const Failure(this.kind, this.message);
}
```

- [ ] **Step 3: `lib/core/storage/token_store.dart`**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStore {
  TokenStore([FlutterSecureStorage? storage])
      : _s = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;
  static const _kAccess = 'fixcare.access';
  static const _kRefresh = 'fixcare.refresh';

  Future<void> save({required String access, required String refresh}) async {
    await _s.write(key: _kAccess, value: access);
    await _s.write(key: _kRefresh, value: refresh);
  }
  Future<String?> readAccess() => _s.read(key: _kAccess);
  Future<String?> readRefresh() => _s.read(key: _kRefresh);
  Future<void> clear() async {
    await _s.delete(key: _kAccess);
    await _s.delete(key: _kRefresh);
  }
}

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());
```

- [ ] **Step 4: `lib/core/network/dio_client.dart`**

```dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../env.dart';

final dioProvider = Provider<Dio>((ref) {
  return Dio(BaseOptions(
    baseUrl: Env.baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
    contentType: 'application/json',
    // Do not throw on any status — repositories map status → Result.
    validateStatus: (_) => true,
  ));
  // Auth interceptor is attached in Task 4 (authInterceptorProvider).
});
```

(Plain `Provider`, not codegen, for these infra singletons — codegen is used for the auth controller. This is the established split: infra = plain providers, feature state = @riverpod.)

- [ ] **Step 5: Run** `flutter test test/core/` → PASS; `flutter analyze` clean.

- [ ] **Step 6: Commit**

```bash
git add -A && git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(customer): Result type, TokenStore, dio client (slice 1)"
```

---

### Task 3: Auth DTOs + AuthRepository (against mocked dio)

**Files:**
- Create: `lib/features/auth/data/auth_dtos.dart`, `lib/features/auth/data/auth_repository.dart`
- Test: `test/auth/auth_repository_test.dart`

**Interfaces:**
- Consumes: `Result`/`FailureKind` (Task 2), `dioProvider` (Task 2).
- Produces:
  - freezed DTOs: `UserDto { String id; String role; String status }`, `VerifyResponse { String accessToken; String refreshToken; UserDto user }`, `RefreshResponse { String accessToken; String refreshToken }`, `SendOtpResponse { bool ok; String? devOtp }`.
  - `class AuthRepository` (ctor takes `Dio`): `Future<Result<SendOtpResponse>> sendOtp(String phone)`, `Future<Result<VerifyResponse>> verifyOtp(String phone, String code)`, `Future<Result<RefreshResponse>> refresh(String refreshToken)`, `Future<Result<void>> logout(String refreshToken)`.
  - `authRepositoryProvider` (Provider) building `AuthRepository(ref.read(dioProvider))`.

- [ ] **Step 1: Failing tests** — `test/auth/auth_repository_test.dart` uses `DioAdapter` from `http_mock_adapter` (add it: `flutter pub add dev:http_mock_adapter`) OR a hand-rolled mock. Use http_mock_adapter:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:fixcare_customer/core/result.dart';
import 'package:fixcare_customer/features/auth/data/auth_repository.dart';

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late AuthRepository repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://test', validateStatus: (_) => true));
    adapter = DioAdapter(dio: dio);
    repo = AuthRepository(dio);
  });

  test('sendOtp 200 → Ok with devOtp', () async {
    adapter.onPost('/auth/otp/send', (s) => s.reply(200, {'ok': true, 'devOtp': '123456'}),
        data: {'phone': '9999999999'});
    final r = await repo.sendOtp('9999999999');
    expect(r, isA<Ok<SendOtpResponse>>());
    expect((r as Ok<SendOtpResponse>).value.devOtp, '123456');
  });

  test('sendOtp 429 → Failure(rateLimited)', () async {
    adapter.onPost('/auth/otp/send', (s) => s.reply(429, {'error': 'slow down'}),
        data: {'phone': '9999999999'});
    final r = await repo.sendOtp('9999999999');
    expect((r as Failure).kind, FailureKind.rateLimited);
  });

  test('verifyOtp 200 → Ok with tokens + user', () async {
    adapter.onPost('/auth/otp/verify',
        (s) => s.reply(200, {'accessToken': 'a', 'refreshToken': 'r', 'user': {'id': 'u1', 'role': 'CUSTOMER', 'status': 'ACTIVE'}}),
        data: {'phone': '9999999999', 'code': '123456'});
    final r = await repo.verifyOtp('9999999999', '123456');
    final v = (r as Ok<VerifyResponse>).value;
    expect(v.accessToken, 'a');
    expect(v.user.id, 'u1');
  });

  test('verifyOtp 401 → Failure(unauthorized)', () async {
    adapter.onPost('/auth/otp/verify', (s) => s.reply(401, {'error': 'bad code'}),
        data: {'phone': '9999999999', 'code': '000000'});
    final r = await repo.verifyOtp('9999999999', '000000');
    expect((r as Failure).kind, FailureKind.unauthorized);
  });

  test('refresh 200 → Ok (no user field)', () async {
    adapter.onPost('/auth/refresh', (s) => s.reply(200, {'accessToken': 'a2', 'refreshToken': 'r2'}),
        data: {'refreshToken': 'r1'});
    final r = await repo.refresh('r1');
    expect((r as Ok<RefreshResponse>).value.accessToken, 'a2');
  });
}
```

Run → FAIL.

- [ ] **Step 2: `lib/features/auth/data/auth_dtos.dart`** (freezed + json):

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
part 'auth_dtos.freezed.dart';
part 'auth_dtos.g.dart';

@freezed
class UserDto with _$UserDto {
  const factory UserDto({required String id, required String role, required String status}) = _UserDto;
  factory UserDto.fromJson(Map<String, dynamic> j) => _$UserDtoFromJson(j);
}

@freezed
class VerifyResponse with _$VerifyResponse {
  const factory VerifyResponse({required String accessToken, required String refreshToken, required UserDto user}) = _VerifyResponse;
  factory VerifyResponse.fromJson(Map<String, dynamic> j) => _$VerifyResponseFromJson(j);
}

@freezed
class RefreshResponse with _$RefreshResponse {
  const factory RefreshResponse({required String accessToken, required String refreshToken}) = _RefreshResponse;
  factory RefreshResponse.fromJson(Map<String, dynamic> j) => _$RefreshResponseFromJson(j);
}

@freezed
class SendOtpResponse with _$SendOtpResponse {
  const factory SendOtpResponse({required bool ok, String? devOtp}) = _SendOtpResponse;
  factory SendOtpResponse.fromJson(Map<String, dynamic> j) => _$SendOtpResponseFromJson(j);
}
```

- [ ] **Step 3: `lib/features/auth/data/auth_repository.dart`**

```dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/result.dart';
import 'auth_dtos.dart';

class AuthRepository {
  AuthRepository(this._dio);
  final Dio _dio;

  Future<Result<T>> _post<T>(String path, Object body, T Function(Map<String, dynamic>) parse) async {
    try {
      final res = await _dio.post(path, data: body);
      final status = res.statusCode ?? 0;
      if (status >= 200 && status < 300) {
        return Ok(parse((res.data as Map).cast<String, dynamic>()));
      }
      return Failure(failureKindFromStatus(status), _msg(res.data));
    } on DioException catch (e) {
      if (e.response != null) {
        return Failure(failureKindFromStatus(e.response!.statusCode), _msg(e.response!.data));
      }
      return Failure(FailureKind.network, 'Network error. Check your connection.');
    }
  }

  String _msg(dynamic data) {
    if (data is Map && data['error'] is String) return data['error'] as String;
    return 'Something went wrong.';
  }

  Future<Result<SendOtpResponse>> sendOtp(String phone) =>
      _post('/auth/otp/send', {'phone': phone}, SendOtpResponse.fromJson);

  Future<Result<VerifyResponse>> verifyOtp(String phone, String code) =>
      _post('/auth/otp/verify', {'phone': phone, 'code': code}, VerifyResponse.fromJson);

  Future<Result<RefreshResponse>> refresh(String refreshToken) =>
      _post('/auth/refresh', {'refreshToken': refreshToken}, RefreshResponse.fromJson);

  Future<Result<void>> logout(String refreshToken) async {
    final r = await _post('/auth/logout', {'refreshToken': refreshToken}, (_) => null);
    return r is Ok ? const Ok(null) : r as Failure<void>;
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository(ref.read(dioProvider)));
```

- [ ] **Step 4:** `dart run build_runner build --delete-conflicting-outputs` → generates the `.freezed.dart`/`.g.dart`. Then `flutter test test/auth/auth_repository_test.dart` → PASS; `flutter analyze` clean.

- [ ] **Step 5: Commit**

```bash
git add -A && git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(customer): auth DTOs + AuthRepository with typed Result (slice 1)"
```

---

### Task 4: Auth interceptor (single-flight 401 → refresh → retry)

**Files:**
- Create: `lib/core/network/auth_interceptor.dart`
- Modify: `lib/core/network/dio_client.dart` (attach the interceptor)
- Test: `test/auth/auth_interceptor_test.dart`

**Interfaces:**
- Consumes: `TokenStore` (Task 2), `AuthRepository.refresh` (Task 3).
- Produces: `class AuthInterceptor extends Interceptor` — ctor `(TokenStore store, Future<Result<RefreshResponse>> Function(String) refresh, void Function() onAuthLost, Dio retryDio)`. Attaches Bearer access on request; on a 401 response (not for `/auth/*` paths) performs a single-flight refresh, updates the store, retries the original request via `retryDio`; on refresh failure calls `onAuthLost` and passes the 401 through.

- [ ] **Step 1: Failing test** — `test/auth/auth_interceptor_test.dart`. Simulate: a dio whose adapter returns 401 for the first hit on `/me/x` then 200 after; assert refresh called ONCE across two concurrent requests. Use http_mock_adapter with a call counter on `/auth/refresh`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:fixcare_customer/core/network/auth_interceptor.dart';
import 'package:fixcare_customer/core/result.dart';
import 'package:fixcare_customer/features/auth/data/auth_dtos.dart';
import 'package:fixcare_customer/core/storage/token_store.dart';
// Reuse the secure-storage mock channel from token_store_test (copy the setUp block).

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // ... secure-storage mock setUp (as in token_store_test) ...

  test('two concurrent 401s trigger exactly ONE refresh, both retried', () async {
    int refreshCalls = 0;
    final store = TokenStore();
    await store.save(access: 'old', refresh: 'r1');

    final dio = Dio(BaseOptions(baseUrl: 'http://test', validateStatus: (_) => true));
    final adapter = DioAdapter(dio: dio);
    // first call with old token → 401; after refresh, new token → 200
    adapter
      ..onGet('/me/a', (s) => s.reply(401, {}), headers: {'Authorization': 'Bearer old'})
      ..onGet('/me/a', (s) => s.reply(200, {'ok': true}), headers: {'Authorization': 'Bearer new'})
      ..onGet('/me/b', (s) => s.reply(401, {}), headers: {'Authorization': 'Bearer old'})
      ..onGet('/me/b', (s) => s.reply(200, {'ok': true}), headers: {'Authorization': 'Bearer new'});

    Future<Result<RefreshResponse>> refresh(String r) async {
      refreshCalls++;
      await store.save(access: 'new', refresh: 'r2');
      return const Ok(RefreshResponse(accessToken: 'new', refreshToken: 'r2'));
    }

    dio.interceptors.add(AuthInterceptor(store, refresh, () {}, dio));
    final results = await Future.wait([dio.get('/me/a'), dio.get('/me/b')]);
    expect(refreshCalls, 1); // single-flight
    expect(results.every((r) => r.statusCode == 200), isTrue);
  });

  test('refresh failure → onAuthLost called, 401 surfaced', () async {
    // ... refresh returns Failure(unauthorized); assert onAuthLost fired and the response is 401 ...
  });
}
```

NOTE to implementer: http_mock_adapter's header-matching can be finicky; if matching on the Authorization header proves flaky, instead assert the single-flight property with a hand-rolled `HttpClientAdapter` stub that counts `/auth/refresh` hits and flips a `token` variable. The invariant under test is: **refreshCalls == 1 for N concurrent 401s, and all retried requests succeed.** Keep that assertion however the mock is built.

Run → FAIL.

- [ ] **Step 2: `lib/core/network/auth_interceptor.dart`**

```dart
import 'package:dio/dio.dart';
import '../result.dart';
import '../storage/token_store.dart';
import '../../features/auth/data/auth_dtos.dart';

class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._store, this._refresh, this._onAuthLost, this._retryDio);
  final TokenStore _store;
  final Future<Result<RefreshResponse>> Function(String refreshToken) _refresh;
  final void Function() _onAuthLost;
  final Dio _retryDio;

  Future<void>? _inFlight; // single-flight guard

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (!options.path.startsWith('/auth/')) {
      final access = await _store.readAccess();
      if (access != null) options.headers['Authorization'] = 'Bearer $access';
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    if (response.statusCode != 401 || response.requestOptions.path.startsWith('/auth/')) {
      return handler.next(response);
    }
    final refreshed = await _refreshOnce();
    if (!refreshed) {
      _onAuthLost();
      return handler.next(response); // surface the 401
    }
    try {
      final retried = await _retry(response.requestOptions);
      return handler.resolve(retried);
    } catch (_) {
      return handler.next(response);
    }
  }

  Future<bool> _refreshOnce() async {
    _inFlight ??= _doRefresh();
    try {
      await _inFlight;
    } finally {
      // allow a future 401 to refresh again once this cycle settles
    }
    final ok = await _store.readAccess() != null && _lastRefreshOk;
    _inFlight = null;
    return ok;
  }

  bool _lastRefreshOk = false;
  Future<void> _doRefresh() async {
    final refresh = await _store.readRefresh();
    if (refresh == null) { _lastRefreshOk = false; return; }
    final r = await _refresh(refresh);
    if (r is Ok<RefreshResponse>) {
      await _store.save(access: r.value.accessToken, refresh: r.value.refreshToken);
      _lastRefreshOk = true;
    } else {
      await _store.clear();
      _lastRefreshOk = false;
    }
  }

  Future<Response> _retry(RequestOptions o) async {
    final access = await _store.readAccess();
    final headers = Map<String, dynamic>.from(o.headers)..['Authorization'] = 'Bearer $access';
    return _retryDio.request(
      o.path,
      data: o.data,
      queryParameters: o.queryParameters,
      options: Options(method: o.method, headers: headers),
    );
  }
}
```

NOTE: the single-flight uses a shared `_inFlight` future — concurrent 401s all await the same `_doRefresh()`. Implementer: verify the counter test passes; if `_inFlight = null` timing races the second waiter, capture the future locally before awaiting. The test is the arbiter.

- [ ] **Step 3: Wire into dio_client** — but the interceptor needs `AuthRepository.refresh` + an `onAuthLost` that the auth controller provides. To avoid a provider cycle (dio ← interceptor ← repository ← dio), the interceptor uses a SEPARATE bare Dio for refresh/retry. Update `dioProvider`:

```dart
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(baseUrl: Env.baseUrl, connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15), contentType: 'application/json', validateStatus: (_) => true));
  final refreshDio = Dio(BaseOptions(baseUrl: Env.baseUrl, validateStatus: (_) => true)); // no interceptor → no recursion
  final store = ref.read(tokenStoreProvider);
  final repo = AuthRepository(refreshDio);
  dio.interceptors.add(AuthInterceptor(store, repo.refresh, () => ref.read(authControllerProvider.notifier).onAuthLost(), dio));
  return dio;
});
```

`onAuthLost` forward-references Task 5's controller — if that creates an ordering issue, pass a mutable callback the controller sets, OR read the controller lazily inside the lambda (as written, `ref.read` is lazy at call-time — fine). Implementer: keep the refresh/retry on a bare `refreshDio` so the interceptor never recurses.

- [ ] **Step 4:** build_runner (if needed), `flutter test test/auth/auth_interceptor_test.dart` → PASS; `flutter analyze` clean.

- [ ] **Step 5: Commit**

```bash
git add -A && git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(customer): single-flight auth interceptor (401→refresh→retry) (slice 1)"
```

---

### Task 5: AuthController + router token-gate + the four screens

**Files:**
- Create: `lib/features/auth/domain/session.dart`, `lib/features/auth/presentation/auth_controller.dart`
- Create: `lib/features/auth/presentation/{splash_screen,phone_entry_screen,otp_entry_screen}.dart`
- Create: `lib/features/home/presentation/home_screen.dart`
- Create: `lib/core/router/app_router.dart`
- Modify: `lib/main.dart` (→ MaterialApp.router)
- Test: `test/router/token_gate_test.dart`, `test/auth/otp_flow_widget_test.dart`

**Interfaces:**
- Consumes: `authRepositoryProvider`, `tokenStoreProvider`, DTOs, Result.
- Produces:
  - `sealed class Session { }` → `SessionUnknown`, `SessionUnauthenticated`, `SessionAuthenticated(UserDto user)`.
  - `@riverpod class AuthController extends _$AuthController` with `FutureOr<Session> build()` (reads TokenStore → Authenticated if access present else Unauthenticated); methods `Future<Result<...>> requestOtp(String phone)`, `Future<Result<void>> submitOtp(String phone, String code)` (on Ok saves tokens + sets Authenticated), `Future<void> logout()`, `void onAuthLost()` (clears state → Unauthenticated).
  - `goRouterProvider` with redirect keyed on the current `Session`.

- [ ] **Step 1: Failing tests.** `test/router/token_gate_test.dart` — pump the app with a `ProviderScope` overriding `tokenStoreProvider` to a fake with/without tokens; assert the initial route resolves to phone (no token) vs home (token). `test/auth/otp_flow_widget_test.dart` — override `authRepositoryProvider` with a fake returning Ok for send+verify; drive: phone screen → enter 10 digits → tap continue → OTP screen → enter code → tap verify → home visible. (Full widget-test code written by the implementer following these assertions; keep them concrete: `find.byKey(const Key('phoneField'))`, `Key('continueBtn')`, `Key('otpField')`, `Key('verifyBtn')`, and `find.text('You're logged in')` on home.)

Run → FAIL.

- [ ] **Step 2: `session.dart`**

```dart
import '../data/auth_dtos.dart';
sealed class Session { const Session(); }
class SessionUnknown extends Session { const SessionUnknown(); }
class SessionUnauthenticated extends Session { const SessionUnauthenticated(); }
class SessionAuthenticated extends Session { final UserDto user; const SessionAuthenticated(this.user); }
```

- [ ] **Step 3: `auth_controller.dart`** (`@riverpod`)

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/result.dart';
import '../../../core/storage/token_store.dart';
import '../data/auth_dtos.dart';
import '../data/auth_repository.dart';
import '../domain/session.dart';
part 'auth_controller.g.dart';

@riverpod
class AuthController extends _$AuthController {
  @override
  Future<Session> build() async {
    final access = await ref.read(tokenStoreProvider).readAccess();
    return access != null ? const SessionAuthenticated(UserDto(id: '', role: 'CUSTOMER', status: 'ACTIVE')) : const SessionUnauthenticated();
    // NOTE: we don't have the user object from storage; a later slice fetches /me/profile.
    // For slice 1, presence of a token = authenticated; the placeholder user is replaced on verify.
  }

  Future<Result<SendOtpResponse>> requestOtp(String phone) =>
      ref.read(authRepositoryProvider).sendOtp(phone);

  Future<Result<void>> submitOtp(String phone, String code) async {
    final r = await ref.read(authRepositoryProvider).verifyOtp(phone, code);
    if (r is Ok<VerifyResponse>) {
      await ref.read(tokenStoreProvider).save(access: r.value.accessToken, refresh: r.value.refreshToken);
      state = AsyncData(SessionAuthenticated(r.value.user));
      return const Ok(null);
    }
    return r as Failure<VerifyResponse>;
  }

  Future<void> logout() async {
    final refresh = await ref.read(tokenStoreProvider).readRefresh();
    if (refresh != null) await ref.read(authRepositoryProvider).logout(refresh);
    await ref.read(tokenStoreProvider).clear();
    state = const AsyncData(SessionUnauthenticated());
  }

  void onAuthLost() => state = const AsyncData(SessionUnauthenticated());
}
```

- [ ] **Step 4: screens** — build `splash_screen.dart` (brand + spinner), `phone_entry_screen.dart` (10-digit field `Key('phoneField')`, validation, `Key('continueBtn')` → `requestOtp`; on Ok go to `/otp` with phone + devOtp extra), `otp_entry_screen.dart` (`Key('otpField')`, on dev show the devOtp + autofill, `Key('verifyBtn')` → `submitOtp`; Failure(unauthorized) inline error, resend), `home_screen.dart` (`find.text('You're logged in')` + logout button → `logout()`). Use the design's palette/spacing. Full widget code by the implementer per these keys/labels.

- [ ] **Step 5: `app_router.dart`** — `goRouterProvider` with routes `/splash /phone /otp /home` and a `redirect` reading `ref.watch(authControllerProvider)`: while `AsyncLoading`/`SessionUnknown` → `/splash`; `SessionUnauthenticated` → `/phone` (allow `/phone`,`/otp`); `SessionAuthenticated` → `/home`. Use `refreshListenable` bound to the controller so redirects re-run on session change.

- [ ] **Step 6: main.dart → MaterialApp.router** using `goRouterProvider`.

- [ ] **Step 7:** build_runner, `flutter test` (ALL tests), `flutter analyze` → green/clean.

- [ ] **Step 8: Commit**

```bash
git add -A && git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(customer): auth controller + token-gate router + phone/OTP/home screens (slice 1)"
```

---

### Task 6: Full verification + docs

**Files:**
- Modify: `apps/customer/README.md` (finalize), `STATUS.md`, `CHANGELOG.md`

- [ ] **Step 1: Full app verification** from `apps/customer`:

```bash
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
```

Expected: analyze clean, ALL tests pass. Report exact test count.

- [ ] **Step 2: Boot-smoke against the real backend (manual, document the result).** With the backend running (`docker compose up -d`; `pnpm dev` in apps/backend) and an Android emulator or Chrome, run
`flutter run -d chrome --dart-define=BASE_URL=http://localhost:3000`, do a phone→OTP(dev autofill)→home round-trip, confirm it lands on home. Note in the report whether this manual step was performed or left to the user (the app cannot assume an emulator exists in CI).

- [ ] **Step 3: STATUS.md + CHANGELOG.md** — Active task → customer app slice 1 complete (scaffold + auth) on branch; Last shipped entry; Next 3 → customer slice 2 (home + profile + addresses) / booking-creation slice / B2b accept-timer. CHANGELOG: new dated section for the customer app slice 1.

- [ ] **Step 4: Commit**

```bash
git add -A && git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "docs: STATUS/CHANGELOG + README — customer app slice 1 complete"
```
