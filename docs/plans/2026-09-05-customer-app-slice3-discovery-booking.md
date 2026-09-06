# Customer App Slice 3 — Discovery + Create Booking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A logged-in customer browses the real catalog, books a service at their address for a chosen future slot via a 3-step wizard, and lands on a booking tracking stub.

**Architecture:** Two new feature-first modules — `catalog/` (categories + per-zone services) and `booking/` (full BookingDto + create/get/cancel repo, a 3-step wizard, a tracking stub). Home is rebuilt to load real categories and, using the customer's default-address zone, real services. Everything rides the Slices 1-2 backbone (Riverpod `@riverpod` codegen, go_router, dio + interceptor, typed `Result<T>`, freezed, theme tokens). The app sends only `{addressId, serviceId, scheduledSlot}`; the backend derives the customer from the JWT and snapshots zone + price server-side.

**Tech Stack:** Flutter (Android + iOS), flutter_riverpod + riverpod_annotation/generator, go_router 18, dio 5, freezed 4.0.1 + json_serializable, http_mock_adapter (tests).

**Spec:** `docs/designs/2026-09-05-customer-app-slice3-discovery-booking-design.md`

## Global Constraints

- **Backend contract is authoritative** (read from `apps/backend/src/modules/{catalog,bookings}`):
  - `GET /catalog/categories` → `[{ id, name, status }]`.
  - `GET /catalog/services?zoneId=&categoryId=` (**`zoneId` REQUIRED**, `categoryId` optional) →
    `[{ id, name, tier('T1'|'T2'|'T3'), categoryId, laborPaise: number|null, visitFeePaise: number }]`.
  - `POST /me/bookings { addressId, serviceId, scheduledSlot }` → **BookingDto** (state `DISPATCHED`).
    `scheduledSlot` is ISO 8601 and **must be in the future**.
  - `GET /me/bookings/:id` → BookingDto. `POST /me/bookings/:id/cancel` → 200 BookingDto (treat as `Result<void>`).
  - Create **422s**: `"We don't serve this area yet"` / `"This service is unavailable in your area"`.
  - Error envelope is **`{ code, message }`** — repositories read `message`, never `error`.
- **BookingDto fields (exact):** `id, bookingNumber, state, scheduledSlot, visitFeePaise, laborPaise, laborTier,
  service{id,name}, zone{id,name}, address{id}, technician?{name,maskedPhone}, diagnosis:{issueName}|null,
  parts:[{id,sku,name,ceilingPricePaise,qty}], estimate:{laborPaise,partsPaise,visitFeeCreditPaise,totalPayablePaise},
  photos:[{kind,capturedAt,url}], payment:{status,method,amountPaise}|null, dispute:{status,outcome,refundPaise|null}|null`.
- **CARRY-FORWARDS (Slice-2 review, non-negotiable):** the app **NEVER sends a customer id** (backend derives from
  JWT); the app **NEVER snapshots price client-side** — it sends only `{addressId, serviceId, scheduledSlot}`.
- **Repositories return `Result<T>`**; no raw dio/JSON above the data layer. Reuse the Slice-2 repo shape
  (`_guard` / `_ok` / `_msg`) verbatim in style.
- **Every action handler that receives a `Result` MUST surface a `Failure`** (SnackBar or inline) — no silent
  swallow. (This class of bug hit Slice 2 twice; the confirm step gets an explicit 422-surfaces regression test.)
- **Tests use `DioAdapter(dio: dio, matcher: const FullHttpRequestMatcher(needsExactBody: true))`** and MUST assert
  the create body is **exactly** `{addressId, serviceId, scheduledSlot}` + that `{code,message}` maps to `Failure.message`.
- **freezed 4.0.1 syntax:** `abstract class X with _$X`. **Generated `*.g.dart`/`*.freezed.dart` ARE committed.**
- **Commit author** `MohammadKaifSaiyad <saiyedkgn6@gmail.com>`, **NO Claude/Co-Authored-By trailer**:
  `git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "..."`.
- All commands run from `apps/customer`. After touching any `@freezed`/`@riverpod` file:
  `dart run build_runner build --delete-conflicting-outputs`. Gate every commit on `flutter analyze` (clean) +
  `flutter test` (green). go_router 18: **assert rendered content (keys/text), not `router...currentConfiguration.uri.path`**
  after a push (known quirk).

---

## Task 1: Catalog module — DTOs + repository

**Files:**
- Create: `lib/features/catalog/data/catalog_dtos.dart`, `lib/features/catalog/data/catalog_repository.dart`
- Test: `test/catalog/catalog_repository_test.dart`

**Interfaces:**
- Consumes: `core/result.dart` (`Result`/`Ok`/`Failure`/`FailureKind`/`failureKindFromStatus`), `core/network/dio_client.dart` (`dioProvider`).
- Produces:
  - `CategoryDto({required String id, required String name, required String status})` + `.fromJson`.
  - `ServiceDto({required String id, required String name, required String tier, required String categoryId, int? laborPaise, required int visitFeePaise})` + `.fromJson`.
  - `CatalogRepository(Dio)` with `Future<Result<List<CategoryDto>>> categories()` and `Future<Result<List<ServiceDto>>> services({required String zoneId, String? categoryId})`.
  - `final catalogRepositoryProvider = Provider<CatalogRepository>((ref) => CatalogRepository(ref.read(dioProvider)));`.

- [ ] **Step 1: Write the failing test** — `test/catalog/catalog_repository_test.dart`

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:fixcare_customer/core/result.dart';
import 'package:fixcare_customer/features/catalog/data/catalog_repository.dart';

Map<String, dynamic> _cat(String id, String name) => {'id': id, 'name': name, 'status': 'ACTIVE'};
Map<String, dynamic> _svc({int? labor = 45000}) =>
    {'id': 's1', 'name': 'Fridge not cooling', 'tier': 'T2', 'categoryId': 'c1', 'laborPaise': labor, 'visitFeePaise': 14900};

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late CatalogRepository repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://test', validateStatus: (_) => true));
    adapter = DioAdapter(dio: dio, matcher: const FullHttpRequestMatcher(needsExactBody: true));
    repo = CatalogRepository(dio);
  });

  test('categories 200 -> Ok(list)', () async {
    adapter.onGet('/catalog/categories', (s) => s.reply(200, [_cat('c1', 'Refrigerator')]));
    final r = await repo.categories();
    expect((r as Ok<List<CategoryDto>>).value.single.name, 'Refrigerator');
  });

  test('services sends zoneId + categoryId query and parses', () async {
    adapter.onGet('/catalog/services', (s) => s.reply(200, [_svc()]),
        queryParameters: {'zoneId': 'z1', 'categoryId': 'c1'});
    final r = await repo.services(zoneId: 'z1', categoryId: 'c1');
    final svc = (r as Ok<List<ServiceDto>>).value.single;
    expect(svc.tier, 'T2');
    expect(svc.laborPaise, 45000);
    expect(svc.visitFeePaise, 14900);
  });

  test('services with null laborPaise parses (unpriced in zone)', () async {
    adapter.onGet('/catalog/services', (s) => s.reply(200, [_svc(labor: null)]),
        queryParameters: {'zoneId': 'z1'});
    final r = await repo.services(zoneId: 'z1');
    expect((r as Ok<List<ServiceDto>>).value.single.laborPaise, isNull);
  });

  test('services 400 -> Failure(validation) with backend message', () async {
    adapter.onGet('/catalog/services', (s) => s.reply(400, {'code': 'VALIDATION', 'message': 'zoneId is required'}),
        queryParameters: {'zoneId': 'z1'});
    final r = await repo.services(zoneId: 'z1');
    final f = r as Failure;
    expect(f.kind, FailureKind.validation);
    expect(f.message, 'zoneId is required');
  });
}
```

- [ ] **Step 2: Run it — verify it FAILS** (`flutter test test/catalog/catalog_repository_test.dart` → compile error, CatalogRepository undefined).

- [ ] **Step 3: Write `catalog_dtos.dart`**

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
part 'catalog_dtos.freezed.dart';
part 'catalog_dtos.g.dart';

@freezed
abstract class CategoryDto with _$CategoryDto {
  const factory CategoryDto({required String id, required String name, required String status}) = _CategoryDto;
  factory CategoryDto.fromJson(Map<String, dynamic> j) => _$CategoryDtoFromJson(j);
}

@freezed
abstract class ServiceDto with _$ServiceDto {
  const factory ServiceDto({
    required String id,
    required String name,
    required String tier, // 'T1' | 'T2' | 'T3'
    required String categoryId,
    int? laborPaise, // null = unpriced in the requested zone
    required int visitFeePaise,
  }) = _ServiceDto;
  factory ServiceDto.fromJson(Map<String, dynamic> j) => _$ServiceDtoFromJson(j);
}
```

- [ ] **Step 4: Write `catalog_repository.dart`** (reuses the Slice-2 `_guard`/`_ok`/`_msg` shape)

```dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/result.dart';
import 'catalog_dtos.dart';

export 'catalog_dtos.dart';

class CatalogRepository {
  CatalogRepository(this._dio);
  final Dio _dio;

  String _msg(dynamic data) =>
      (data is Map && data['message'] is String) ? data['message'] as String : 'Something went wrong.';

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

  Future<Result<List<CategoryDto>>> categories() => _guard(() async {
    final res = await _dio.get('/catalog/categories');
    return _ok<List<CategoryDto>>(res, (data) =>
        (data as List).map((e) => CategoryDto.fromJson((e as Map).cast<String, dynamic>())).toList());
  });

  Future<Result<List<ServiceDto>>> services({required String zoneId, String? categoryId}) => _guard(() async {
    final res = await _dio.get('/catalog/services', queryParameters: {
      'zoneId': zoneId,
      if (categoryId != null) 'categoryId': categoryId,
    });
    return _ok<List<ServiceDto>>(res, (data) =>
        (data as List).map((e) => ServiceDto.fromJson((e as Map).cast<String, dynamic>())).toList());
  });
}

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) => CatalogRepository(ref.read(dioProvider)));
```

- [ ] **Step 5: Codegen + run** — `dart run build_runner build --delete-conflicting-outputs`, then `flutter test test/catalog/catalog_repository_test.dart` (4/4 pass), `flutter analyze` (clean).

- [ ] **Step 6: Commit**

```bash
dart run build_runner build --delete-conflicting-outputs
git add lib/features/catalog test/catalog
git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(customer): catalog module — CategoryDto/ServiceDto + repository (slice 3)"
```

---

## Task 2: Booking module — DTOs + repository

**Files:**
- Create: `lib/features/booking/data/booking_dtos.dart`, `lib/features/booking/data/booking_repository.dart`
- Test: `test/booking/booking_repository_test.dart`

**Interfaces:**
- Consumes: `core/result.dart`, `core/network/dio_client.dart` (`dioProvider`).
- Produces:
  - Full `BookingDto` (freezed) with nested `BookingServiceDto{id,name}`, `BookingZoneDto{id,name}`, `BookingAddressRefDto{id}`, `TechnicianRefDto{name,maskedPhone}`, `DiagnosisDto{issueName}`, `PartDto{id,sku,name,ceilingPricePaise,qty}`, `EstimateDto{laborPaise,partsPaise,visitFeeCreditPaise,totalPayablePaise}`, `PhotoDto{kind,capturedAt,url}`, `PaymentSummaryDto{status,method,amountPaise}`, `DisputeSummaryDto{status,outcome,refundPaise?}` — all `+ .fromJson`.
  - `BookingRepository(Dio)`: `Future<Result<BookingDto>> create({required String addressId, required String serviceId, required String scheduledSlot})`, `Future<Result<BookingDto>> get(String id)`, `Future<Result<void>> cancel(String id)`.
  - `final bookingRepositoryProvider = Provider<BookingRepository>((ref) => BookingRepository(ref.read(dioProvider)));`.

- [ ] **Step 1: Write the failing test** — `test/booking/booking_repository_test.dart`

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:fixcare_customer/core/result.dart';
import 'package:fixcare_customer/features/booking/data/booking_repository.dart';

Map<String, dynamic> _bookingJson({String state = 'DISPATCHED'}) => {
  'id': 'b1', 'bookingNumber': 'FC-1001', 'state': state,
  'scheduledSlot': '2026-09-10T09:00:00.000Z', 'visitFeePaise': 14900, 'laborPaise': 45000, 'laborTier': 'T2',
  'service': {'id': 's1', 'name': 'Fridge not cooling'},
  'zone': {'id': 'z1', 'name': 'Vadodara'},
  'address': {'id': 'a1'},
  'diagnosis': null,
  'parts': <Map<String, dynamic>>[],
  'estimate': {'laborPaise': 45000, 'partsPaise': 0, 'visitFeeCreditPaise': 0, 'totalPayablePaise': 45000},
  'photos': <Map<String, dynamic>>[],
  'payment': null, 'dispute': null,
};

void main() {
  late Dio dio;
  late DioAdapter adapter;
  late BookingRepository repo;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'http://test', validateStatus: (_) => true));
    adapter = DioAdapter(dio: dio, matcher: const FullHttpRequestMatcher(needsExactBody: true));
    repo = BookingRepository(dio);
  });

  test('create posts EXACTLY {addressId, serviceId, scheduledSlot} and parses BookingDto', () async {
    adapter.onPost('/me/bookings', (s) => s.reply(201, _bookingJson()),
        data: {'addressId': 'a1', 'serviceId': 's1', 'scheduledSlot': '2026-09-10T09:00:00.000Z'});
    final r = await repo.create(addressId: 'a1', serviceId: 's1', scheduledSlot: '2026-09-10T09:00:00.000Z');
    final b = (r as Ok<BookingDto>).value;
    expect(b.bookingNumber, 'FC-1001');
    expect(b.state, 'DISPATCHED');
    expect(b.service.name, 'Fridge not cooling');
    expect(b.estimate.totalPayablePaise, 45000);
  });

  test('create 422 -> Failure(validation) with the backend message', () async {
    adapter.onPost('/me/bookings',
        (s) => s.reply(422, {'code': 'UNPROCESSABLE', 'message': "We don't serve this area yet"}),
        data: {'addressId': 'a1', 'serviceId': 's1', 'scheduledSlot': '2026-09-10T09:00:00.000Z'});
    final r = await repo.create(addressId: 'a1', serviceId: 's1', scheduledSlot: '2026-09-10T09:00:00.000Z');
    final f = r as Failure;
    // NB: failureKindFromStatus(422) returns FailureKind.unknown (only 400 is `validation`); the MESSAGE
    // is what the confirm step surfaces, so the message assertion below is the load-bearing one.
    expect(f.kind, FailureKind.unknown);
    expect(f.message, "We don't serve this area yet");
  });

  test('get 200 -> Ok(BookingDto)', () async {
    adapter.onGet('/me/bookings/b1', (s) => s.reply(200, _bookingJson()));
    final r = await repo.get('b1');
    expect((r as Ok<BookingDto>).value.id, 'b1');
  });

  test('cancel 200 -> Ok(void)', () async {
    adapter.onPost('/me/bookings/b1/cancel', (s) => s.reply(200, _bookingJson(state: 'CANCELLED_BY_CUSTOMER')));
    final r = await repo.cancel('b1');
    expect(r, isA<Ok<void>>());
  });
}
```

> **Note on 422→validation:** verify `failureKindFromStatus` in `core/result.dart` maps 422. If 422 currently
> falls to `FailureKind.unknown` (only 400 is `validation`), change the test's expected kind to what the code
> actually returns AND, since the spec wants the two 422 create errors surfaced with their message, the UI keys
> off `Failure.message` (always present) not the kind — so the message assertion is the load-bearing one. Do NOT
> change `failureKindFromStatus` here; the message is what the confirm step shows.

- [ ] **Step 2: Run it — verify it FAILS** (BookingRepository undefined).

- [ ] **Step 3: Write `booking_dtos.dart`**

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
part 'booking_dtos.freezed.dart';
part 'booking_dtos.g.dart';

@freezed
abstract class BookingServiceDto with _$BookingServiceDto {
  const factory BookingServiceDto({required String id, required String name}) = _BookingServiceDto;
  factory BookingServiceDto.fromJson(Map<String, dynamic> j) => _$BookingServiceDtoFromJson(j);
}

@freezed
abstract class BookingZoneDto with _$BookingZoneDto {
  const factory BookingZoneDto({required String id, required String name}) = _BookingZoneDto;
  factory BookingZoneDto.fromJson(Map<String, dynamic> j) => _$BookingZoneDtoFromJson(j);
}

@freezed
abstract class BookingAddressRefDto with _$BookingAddressRefDto {
  const factory BookingAddressRefDto({required String id}) = _BookingAddressRefDto;
  factory BookingAddressRefDto.fromJson(Map<String, dynamic> j) => _$BookingAddressRefDtoFromJson(j);
}

@freezed
abstract class TechnicianRefDto with _$TechnicianRefDto {
  const factory TechnicianRefDto({required String name, required String maskedPhone}) = _TechnicianRefDto;
  factory TechnicianRefDto.fromJson(Map<String, dynamic> j) => _$TechnicianRefDtoFromJson(j);
}

@freezed
abstract class DiagnosisDto with _$DiagnosisDto {
  const factory DiagnosisDto({required String issueName}) = _DiagnosisDto;
  factory DiagnosisDto.fromJson(Map<String, dynamic> j) => _$DiagnosisDtoFromJson(j);
}

@freezed
abstract class PartDto with _$PartDto {
  const factory PartDto({
    required String id, required String sku, required String name,
    required int ceilingPricePaise, required int qty,
  }) = _PartDto;
  factory PartDto.fromJson(Map<String, dynamic> j) => _$PartDtoFromJson(j);
}

@freezed
abstract class EstimateDto with _$EstimateDto {
  const factory EstimateDto({
    required int laborPaise, required int partsPaise,
    required int visitFeeCreditPaise, required int totalPayablePaise,
  }) = _EstimateDto;
  factory EstimateDto.fromJson(Map<String, dynamic> j) => _$EstimateDtoFromJson(j);
}

@freezed
abstract class PhotoDto with _$PhotoDto {
  const factory PhotoDto({required String kind, required String capturedAt, required String url}) = _PhotoDto;
  factory PhotoDto.fromJson(Map<String, dynamic> j) => _$PhotoDtoFromJson(j);
}

@freezed
abstract class PaymentSummaryDto with _$PaymentSummaryDto {
  const factory PaymentSummaryDto({required String status, required String method, required int amountPaise}) = _PaymentSummaryDto;
  factory PaymentSummaryDto.fromJson(Map<String, dynamic> j) => _$PaymentSummaryDtoFromJson(j);
}

@freezed
abstract class DisputeSummaryDto with _$DisputeSummaryDto {
  const factory DisputeSummaryDto({required String status, required String outcome, int? refundPaise}) = _DisputeSummaryDto;
  factory DisputeSummaryDto.fromJson(Map<String, dynamic> j) => _$DisputeSummaryDtoFromJson(j);
}

@freezed
abstract class BookingDto with _$BookingDto {
  const factory BookingDto({
    required String id,
    required String bookingNumber,
    required String state,
    required String scheduledSlot,
    required int visitFeePaise,
    required int laborPaise,
    String? laborTier,
    required BookingServiceDto service,
    required BookingZoneDto zone,
    required BookingAddressRefDto address,
    TechnicianRefDto? technician,
    DiagnosisDto? diagnosis,
    @Default(<PartDto>[]) List<PartDto> parts,
    required EstimateDto estimate,
    @Default(<PhotoDto>[]) List<PhotoDto> photos,
    PaymentSummaryDto? payment,
    DisputeSummaryDto? dispute,
  }) = _BookingDto;
  factory BookingDto.fromJson(Map<String, dynamic> j) => _$BookingDtoFromJson(j);
}
```

- [ ] **Step 4: Write `booking_repository.dart`**

```dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/result.dart';
import 'booking_dtos.dart';

export 'booking_dtos.dart';

class BookingRepository {
  BookingRepository(this._dio);
  final Dio _dio;

  String _msg(dynamic data) =>
      (data is Map && data['message'] is String) ? data['message'] as String : 'Something went wrong.';

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

  // The app sends ONLY these three fields. The customer id is derived from the JWT server-side, and the
  // zone + price are snapshotted server-side from addressId — the app never sends either (Golden Rule 4 /
  // Slice-2 carry-forward).
  Future<Result<BookingDto>> create({
    required String addressId,
    required String serviceId,
    required String scheduledSlot,
  }) => _guard(() async {
    final res = await _dio.post('/me/bookings',
        data: {'addressId': addressId, 'serviceId': serviceId, 'scheduledSlot': scheduledSlot});
    return _ok<BookingDto>(res, (data) => BookingDto.fromJson((data as Map).cast<String, dynamic>()));
  });

  Future<Result<BookingDto>> get(String id) => _guard(() async {
    final res = await _dio.get('/me/bookings/$id');
    return _ok<BookingDto>(res, (data) => BookingDto.fromJson((data as Map).cast<String, dynamic>()));
  });

  Future<Result<void>> cancel(String id) => _guard(() async {
    final res = await _dio.post('/me/bookings/$id/cancel');
    final status = res.statusCode ?? 0;
    if (status >= 200 && status < 300) return const Ok(null);
    return Failure(failureKindFromStatus(status), _msg(res.data));
  });
}

final bookingRepositoryProvider = Provider<BookingRepository>((ref) => BookingRepository(ref.read(dioProvider)));
```

- [ ] **Step 5: Codegen + run** — build_runner, then `flutter test test/booking/booking_repository_test.dart` (4/4), `flutter analyze` clean. Adjust the 422 test's expected `FailureKind` to whatever `failureKindFromStatus(422)` actually returns (the message assertion is the load-bearing one).

- [ ] **Step 6: Commit**

```bash
dart run build_runner build --delete-conflicting-outputs
git add lib/features/booking/data test/booking
git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(customer): booking module — full BookingDto + repository (create/get/cancel) (slice 3)"
```

---

## Task 3: Booking wizard controller + slot-ISO helper

**Files:**
- Create: `lib/features/booking/presentation/booking_wizard_controller.dart`, `lib/features/booking/presentation/slot.dart`
- Test: `test/booking/slot_test.dart`

**Interfaces:**
- Consumes: (none from earlier tasks — pure helpers).
- Produces:
  - `enum SlotWindow { morning, afternoon, evening }` with `int get startHour` (9 / 12 / 15) and `String get label`.
  - `String? slotToIso(DateTime day, SlotWindow window, {DateTime? now})` — returns a UTC ISO 8601 string for that day+window's start hour in **local** time, or **null** if the resulting instant is not strictly in the future (guards past slots). `now` defaults to `DateTime.now()` (injectable for tests).
  - `@riverpod class BookingWizard extends _$BookingWizard` holding `BookingWizardState({required String serviceId, String? addressId, String? scheduledSlot})`; methods `setAddress(String id)`, `setSlot(String iso)`. `build(String serviceId)` seeds `serviceId`. (Family provider keyed by serviceId.)

- [ ] **Step 1: Write the failing test** — `test/booking/slot_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fixcare_customer/features/booking/presentation/slot.dart';

void main() {
  test('morning window maps to 09:00 local and returns a future ISO', () {
    final now = DateTime(2026, 9, 8, 8, 0); // 8am, before the 9am morning slot today
    final iso = slotToIso(DateTime(2026, 9, 8), SlotWindow.morning, now: now);
    expect(iso, isNotNull);
    final dt = DateTime.parse(iso!);
    expect(dt.isAfter(now), isTrue);
    // 9am local on the 8th
    expect(DateTime(2026, 9, 8, 9, 0).toUtc().toIso8601String(), iso);
  });

  test('a window whose start hour has already passed today returns null', () {
    final now = DateTime(2026, 9, 8, 13, 0); // 1pm — morning (9) already gone
    expect(slotToIso(DateTime(2026, 9, 8), SlotWindow.morning, now: now), isNull);
  });

  test('afternoon (12) / evening (15) start hours', () {
    expect(SlotWindow.afternoon.startHour, 12);
    expect(SlotWindow.evening.startHour, 15);
  });

  test('a future day is always valid regardless of window', () {
    final now = DateTime(2026, 9, 8, 23, 0);
    expect(slotToIso(DateTime(2026, 9, 9), SlotWindow.morning, now: now), isNotNull);
  });
}
```

- [ ] **Step 2: Run it — verify it FAILS** (slot.dart undefined).

- [ ] **Step 3: Write `slot.dart`**

```dart
enum SlotWindow { morning, afternoon, evening }

extension SlotWindowX on SlotWindow {
  int get startHour => switch (this) {
        SlotWindow.morning => 9,
        SlotWindow.afternoon => 12,
        SlotWindow.evening => 15,
      };
  String get label => switch (this) {
        SlotWindow.morning => 'Morning · 9–12',
        SlotWindow.afternoon => 'Afternoon · 12–3',
        SlotWindow.evening => 'Evening · 3–6',
      };
}

/// A UTC ISO 8601 string for [day] at [window]'s start hour in local time, or null if that instant
/// is not strictly in the future (the backend requires scheduledSlot > now).
String? slotToIso(DateTime day, SlotWindow window, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final local = DateTime(day.year, day.month, day.day, window.startHour);
  if (!local.isAfter(n)) return null;
  return local.toUtc().toIso8601String();
}
```

- [ ] **Step 4: Run it — verify PASS** (`flutter test test/booking/slot_test.dart`, 4/4).

- [ ] **Step 5: Write `booking_wizard_controller.dart`**

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
part 'booking_wizard_controller.freezed.dart';
part 'booking_wizard_controller.g.dart';

@freezed
abstract class BookingWizardState with _$BookingWizardState {
  const factory BookingWizardState({required String serviceId, String? addressId, String? scheduledSlot}) =
      _BookingWizardState;
}

@riverpod
class BookingWizard extends _$BookingWizard {
  @override
  BookingWizardState build(String serviceId) => BookingWizardState(serviceId: serviceId);

  void setAddress(String id) => state = state.copyWith(addressId: id);
  void setSlot(String iso) => state = state.copyWith(scheduledSlot: iso);
}
```

- [ ] **Step 6: Codegen + run + commit**

```bash
dart run build_runner build --delete-conflicting-outputs
flutter analyze && flutter test test/booking/slot_test.dart
git add lib/features/booking/presentation/booking_wizard_controller.dart lib/features/booking/presentation/booking_wizard_controller.g.dart lib/features/booking/presentation/booking_wizard_controller.freezed.dart lib/features/booking/presentation/slot.dart test/booking/slot_test.dart
git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(customer): booking wizard controller + future-ISO slot helper (slice 3)"
```

---

## Task 4: Home rebuild — real catalog with default-address zone

**Files:**
- Modify: `lib/features/home/presentation/home_screen.dart` (replace the stub body; keep the header/`accountAvatar`/bottom-tab-bar chrome)
- Test: `test/home/home_widget_test.dart`

**Interfaces:**
- Consumes: `catalogRepositoryProvider`/`CategoryDto`/`ServiceDto` (Task 1), `addressControllerProvider`/`AddressDto`/`ZoneDto` (Slice 2), theme tokens.
- Produces: a Home that, given the default address's `zone.id`, lists categories and their services with price teasers; tapping a service does `context.push('/book/${service.id}')`. No default address → categories grid + an "Add an address to see services & book" CTA with a `Key('homeAddAddressCta')` → `context.push('/address/new')`.

**Design note:** keep the existing header (SERVICE AT + `accountAvatar` → `/account`) and bottom tab bar. Replace the static `_categories` grid + search stub with the live catalog UI below. Show the default address's `label · zone.name` in the header instead of the hardcoded "Home · Padra".

- [ ] **Step 1: Write the failing test** — `test/home/home_widget_test.dart`

```dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fixcare_customer/core/result.dart';
import 'package:fixcare_customer/features/address/data/address_repository.dart';
import 'package:fixcare_customer/features/catalog/data/catalog_repository.dart';
import 'package:fixcare_customer/features/home/presentation/home_screen.dart';

Map<String, dynamic> _addr({bool isDefault = true}) => {
  'id': 'a1', 'label': 'Home', 'line1': '12 MG Road', 'line2': null, 'landmark': null,
  'pincode': '390001', 'lat': null, 'lng': null, 'isDefault': isDefault, 'status': 'ACTIVE',
  'serviceable': true, 'zone': {'id': 'z1', 'name': 'Vadodara', 'visitFeePaise': 14900},
};

class _FakeAddressRepo extends AddressRepository {
  _FakeAddressRepo(this._list) : super(Dio());
  final List<AddressDto> _list;
  @override
  Future<Result<List<AddressDto>>> list() async => Ok(_list);
}

class _FakeCatalogRepo extends CatalogRepository {
  _FakeCatalogRepo() : super(Dio());
  @override
  Future<Result<List<CategoryDto>>> categories() async =>
      const Ok([CategoryDto(id: 'c1', name: 'Refrigerator', status: 'ACTIVE')]);
  @override
  Future<Result<List<ServiceDto>>> services({required String zoneId, String? categoryId}) async =>
      const Ok([ServiceDto(id: 's1', name: 'Fridge not cooling', tier: 'T2', categoryId: 'c1', laborPaise: 45000, visitFeePaise: 14900)]);
}

Future<void> _pump(WidgetTester tester, {required AddressRepository addr, required CatalogRepository cat}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      addressRepositoryProvider.overrideWithValue(addr),
      catalogRepositoryProvider.overrideWithValue(cat),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(initialLocation: '/home', routes: [
        GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
        GoRoute(path: '/book/:serviceId', builder: (_, _) => const Scaffold(body: Text('wizard stub'))),
        GoRoute(path: '/address/new', builder: (_, _) => const Scaffold(body: Text('add address stub'))),
        GoRoute(path: '/account', builder: (_, _) => const Scaffold(body: Text('account stub'))),
      ]),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('with a default address, categories + priced service render', (tester) async {
    await _pump(tester, addr: _FakeAddressRepo([AddressDto.fromJson(_addr())]), cat: _FakeCatalogRepo());
    expect(find.text('Refrigerator'), findsWidgets);
    expect(find.text('Fridge not cooling'), findsOneWidget);
    expect(find.textContaining('149'), findsWidgets); // visit fee ₹149 teaser (14900 paise)
  });

  testWidgets('no default address -> add-address CTA, no crash', (tester) async {
    await _pump(tester, addr: _FakeAddressRepo(const []), cat: _FakeCatalogRepo());
    expect(find.byKey(const Key('homeAddAddressCta')), findsOneWidget);
    // never crashes trying to fetch services without a zone
  });
}
```

- [ ] **Step 2: Run it — verify it FAILS** (Home has no such behavior yet).

- [ ] **Step 3: Rebuild `home_screen.dart`.** Convert to a `ConsumerWidget` that:
  - `ref.watch(addressControllerProvider)` → `AsyncValue<List<AddressDto>>`.
  - Derive `defaultZone`: `list.firstWhere((a) => a.isDefault, orElse: list.firstOrNull).zone` (a serviceable default may still have a zone; if the list is empty or no zone → null).
  - Header: show `defaultAddress.label · zone.name` (fallback to a generic label when none).
  - Body: `ref.watch` a services-by-zone future via a small `FutureProvider.family`/inline load, OR — simplest — a `FutureBuilder` over `catalogRepository.categories()` for the grid, and per category `catalogRepository.services(zoneId: zone.id, categoryId: c.id)`. Use the reference implementation below.
  - No zone → the CTA (Key `homeAddAddressCta`).
  Keep helper widgets (category tile, service row, price teaser).

Reference structure (write it out fully — do not abbreviate):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/result.dart';
import '../../../core/theme.dart';
import '../../address/data/address_repository.dart';
import '../../address/presentation/address_controller.dart';
import '../../catalog/data/catalog_repository.dart';

/// ₹ from integer paise, no trailing .00 when whole rupees.
String rupees(int paise) {
  final r = paise / 100;
  return r == r.roundToDouble() ? '₹${r.toInt()}' : '₹${r.toStringAsFixed(2)}';
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addressesAsync = ref.watch(addressControllerProvider);
    return Scaffold(
      body: SafeArea(
        child: addressesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => _ErrorRetry(onRetry: () => ref.invalidate(addressControllerProvider)),
          data: (addresses) {
            final def = addresses.where((a) => a.isDefault).cast<AddressDto?>().firstWhere((_) => true, orElse: () => addresses.isEmpty ? null : addresses.first);
            final zone = def?.zone;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Header(label: def?.label, zoneName: zone?.name),
                Expanded(
                  child: zone == null
                      ? _NoAddress()
                      : _Catalog(zoneId: zone.id),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: const _BottomBar(),
    );
  }
}
```

The plan's implementer writes the remaining widgets: `_Header` (SERVICE AT eyebrow, `label · zoneName`, and the `accountAvatar` InkResponse → `/account` — copy from the current stub), `_NoAddress` (an illustration/text + a `FilledButton` with `Key('homeAddAddressCta')` → `context.push('/address/new')`), `_Catalog` (a `ConsumerWidget` that `FutureBuilder`s `ref.read(catalogRepositoryProvider).categories()`; for each category a section with a `FutureBuilder` over `services(zoneId: zoneId, categoryId: category.id)` rendering `_ServiceRow`s), `_ServiceRow` (name, tier badge, a "Visit fee {rupees(visitFeePaise)}" teaser + "· Labor from {rupees(laborPaise!)}" when non-null; `onTap: () => context.push('/book/${service.id}')`), `_ErrorRetry`, and `_BottomBar` (copy the tab bar from the stub). All styled with `FixCareColors`/`FixCareRadii`.

- [ ] **Step 4: Codegen (none needed unless a provider added), run** — `flutter test test/home/home_widget_test.dart` (2/2), `flutter analyze` clean, and the FULL suite (the old home smoke/stub assertions may need updating — the Slice-1 test asserted `find.text("What needs fixing?")`; update/replace any test that asserted the stub's static content).

- [ ] **Step 5: Commit**

```bash
git add lib/features/home test/home
# also stage any Slice-1/2 test updated because the home stub content changed
git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(customer): home — real catalog by default-address zone + no-address CTA (slice 3)"
```

---

## Task 5: Booking wizard screen (address → slot → confirm) + routing

**Files:**
- Create: `lib/features/booking/presentation/booking_wizard_screen.dart`
- Modify: `lib/core/router/app_router.dart` (add `/book/:serviceId` and `/booking/:id` routes — the tracking route builder is finalized in Task 6; here add both, pointing `/booking/:id` at a temporary `BookingTrackingScreen(bookingId:)` created in Task 6 — so add the wizard route now and the tracking route in Task 6, OR add both routes here with the tracking builder referencing the Task-6 screen. To keep tasks compiling independently, add ONLY `/book/:serviceId` here; Task 6 adds `/booking/:id`.)
- Test: `test/booking/wizard_widget_test.dart`

**Interfaces:**
- Consumes: `bookingWizardProvider` family (Task 3), `slot.dart` (Task 3), `addressControllerProvider`/`AddressDto` (Slice 2), `catalogRepositoryProvider`/`ServiceDto` (Task 1 — to show the service name/fee; fetch the single service via the zone or pass minimal info), `bookingRepositoryProvider` (Task 2).
- Produces: `BookingWizardScreen({required String serviceId})`, a 3-step flow with `Key('wizardAddress')`, `Key('wizardSlot')`, `Key('wizardConfirm')`, `Key('confirmBookingBtn')`. On confirm success → `context.go('/booking/${booking.id}')`.

**Behavior:**
- **Step gating:** an `int _step` (0/1/2). "Continue" advances; "Back" goes back a step (or pops at step 0). Address step: a radio list of `ref.watch(addressControllerProvider)` addresses, default preselected into the wizard (`setAddress`); each row shows label/line1 + a serviceability chip (reuse `serviceable`); an "Add address" text button → `context.push('/address/new')`. Slot step: horizontal date chips (today … +7 via `List.generate(8, (i) => DateTime.now().add(Duration(days: i)))`), then window chips (`SlotWindow.values`), disabling a window whose `slotToIso(day, w)` is null; picking sets `setSlot(iso)`. Confirm step: show the chosen address, the slot (formatted), and the **visit fee** (from the chosen address's `zone.visitFeePaise`); `FilledButton` `confirmBookingBtn` → `bookingRepository.create(addressId, serviceId, scheduledSlot)`.
- **Result handling:** `Ok(b)` → `context.go('/booking/${b.id}')`. `Failure(message: m)` → `setState(() => _error = m)` shown inline above the button (NEVER swallowed). Guard the button while busy.
- To display the service name/fee on the confirm step without an extra fetch: read it from the wizard's originating context is awkward; simplest is to pass the `ServiceDto` via the route `extra` (Home's `_ServiceRow` does `context.push('/book/${s.id}', extra: s)`), and `BookingWizardScreen` accepts an optional `ServiceDto? service`. If `extra` is null (deep link), fall back to showing just "Service" and the address-zone visit fee. **Update Home's `_ServiceRow.onTap` in this task to pass `extra: service`.**

- [ ] **Step 1: Write the failing widget test** — `test/booking/wizard_widget_test.dart`

```dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fixcare_customer/core/result.dart';
import 'package:fixcare_customer/features/address/data/address_repository.dart';
import 'package:fixcare_customer/features/booking/data/booking_repository.dart';
import 'package:fixcare_customer/features/booking/presentation/booking_wizard_screen.dart';

Map<String, dynamic> _addr() => {
  'id': 'a1', 'label': 'Home', 'line1': '12 MG Road', 'line2': null, 'landmark': null,
  'pincode': '390001', 'lat': null, 'lng': null, 'isDefault': true, 'status': 'ACTIVE',
  'serviceable': true, 'zone': {'id': 'z1', 'name': 'Vadodara', 'visitFeePaise': 14900},
};
Map<String, dynamic> _booking() => {
  'id': 'b1', 'bookingNumber': 'FC-1001', 'state': 'DISPATCHED',
  'scheduledSlot': '2026-09-10T09:00:00.000Z', 'visitFeePaise': 14900, 'laborPaise': 45000, 'laborTier': 'T2',
  'service': {'id': 's1', 'name': 'Fridge not cooling'}, 'zone': {'id': 'z1', 'name': 'Vadodara'},
  'address': {'id': 'a1'}, 'diagnosis': null, 'parts': [],
  'estimate': {'laborPaise': 45000, 'partsPaise': 0, 'visitFeeCreditPaise': 0, 'totalPayablePaise': 45000},
  'photos': [], 'payment': null, 'dispute': null,
};

class _FakeAddressRepo extends AddressRepository {
  _FakeAddressRepo() : super(Dio());
  @override
  Future<Result<List<AddressDto>>> list() async => Ok([AddressDto.fromJson(_addr())]);
}

class _FakeBookingRepo extends BookingRepository {
  _FakeBookingRepo({this.createResult}) : super(Dio());
  Result<BookingDto>? createResult;
  Map<String, dynamic>? lastBody;
  @override
  Future<Result<BookingDto>> create({required String addressId, required String serviceId, required String scheduledSlot}) async {
    lastBody = {'addressId': addressId, 'serviceId': serviceId, 'scheduledSlot': scheduledSlot};
    return createResult ?? Ok(BookingDto.fromJson(_booking()));
  }
}

Future<void> _pump(WidgetTester tester, _FakeBookingRepo booking) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      addressRepositoryProvider.overrideWithValue(_FakeAddressRepo()),
      bookingRepositoryProvider.overrideWithValue(booking),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(initialLocation: '/book/s1', routes: [
        GoRoute(path: '/book/:serviceId', builder: (_, s) => BookingWizardScreen(serviceId: s.pathParameters['serviceId']!)),
        GoRoute(path: '/booking/:id', builder: (_, s) => Scaffold(body: Text('tracking ${s.pathParameters['id']}'))),
      ]),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('happy path: address(default) -> slot -> confirm -> create with 3 fields -> tracking', (tester) async {
    final booking = _FakeBookingRepo();
    await _pump(tester, booking);
    // address step: default preselected, tap Continue
    expect(find.byKey(const Key('wizardAddress')), findsOneWidget);
    await tester.tap(find.text('Continue')); await tester.pumpAndSettle();
    // slot step: pick a future window (implementer ensures at least one enabled), then Continue
    expect(find.byKey(const Key('wizardSlot')), findsOneWidget);
    await tester.tap(find.text('Morning · 9–12').first); await tester.pumpAndSettle();
    await tester.tap(find.text('Continue')); await tester.pumpAndSettle();
    // confirm
    expect(find.byKey(const Key('wizardConfirm')), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmBookingBtn'))); await tester.pumpAndSettle();
    expect(booking.lastBody!.keys.toSet(), {'addressId', 'serviceId', 'scheduledSlot'});
    expect(booking.lastBody!['serviceId'], 's1');
    expect(find.text('tracking b1'), findsOneWidget);
  });

  testWidgets('422 create surfaces the message and stays on confirm', (tester) async {
    final booking = _FakeBookingRepo(createResult: const Failure(FailureKind.validation, "We don't serve this area yet"));
    await _pump(tester, booking);
    await tester.tap(find.text('Continue')); await tester.pumpAndSettle();
    await tester.tap(find.text('Morning · 9–12').first); await tester.pumpAndSettle();
    await tester.tap(find.text('Continue')); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmBookingBtn'))); await tester.pumpAndSettle();
    expect(find.text("We don't serve this area yet"), findsOneWidget);
    expect(find.byKey(const Key('wizardConfirm')), findsOneWidget); // still on confirm, not navigated
  });
}
```

> **Note (test determinism):** the slot test taps "Morning · 9–12". If the test runs after 9am local, that
> window would be disabled for *today*. The implementer must make the date default to a **future day** (e.g.
> preselect tomorrow) OR have the slot step auto-select the first date whose morning window is still in the
> future, so "Morning" is always tappable. Whatever you choose, keep the label text `Morning · 9–12` stable.

- [ ] **Step 2: Run it — verify it FAILS** (BookingWizardScreen undefined).

- [ ] **Step 3: Write `booking_wizard_screen.dart`** — a `ConsumerStatefulWidget` implementing the 3-step behavior above, with the four keys, inline `_error` on confirm, and `context.go('/booking/${b.id}')` on Ok. Preselect a future date so the morning window is always available. Use theme tokens. (Full widget code by the implementer, following the behavior spec + the test's expectations.)

- [ ] **Step 4: Add the `/book/:serviceId` route** to `app_router.dart` routes list:

```dart
GoRoute(
  path: '/book/:serviceId',
  builder: (_, state) => BookingWizardScreen(serviceId: state.pathParameters['serviceId']!),
),
```

(and import the screen). Update Home's `_ServiceRow.onTap` to `context.push('/book/${service.id}', extra: service)` and accept an optional `ServiceDto? service` in the wizard (from `state.extra`) for the confirm-step name/fee.

- [ ] **Step 5: Codegen (if any provider changed), run + commit** — `flutter test test/booking/wizard_widget_test.dart` (2/2) + full suite + `flutter analyze` clean.

```bash
dart run build_runner build --delete-conflicting-outputs
git add lib/features/booking/presentation/booking_wizard_screen.dart lib/core/router/app_router.dart lib/features/home
git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(customer): booking wizard — address/slot/confirm + create (422 surfaced) (slice 3)"
```

---

## Task 6: Booking tracking stub screen + route

**Files:**
- Create: `lib/features/booking/presentation/booking_tracking_screen.dart`
- Modify: `lib/core/router/app_router.dart` (add `/booking/:id`)
- Test: `test/booking/tracking_stub_test.dart`

**Interfaces:**
- Consumes: `bookingRepositoryProvider` (Task 2, `get(id)` + `cancel(id)`), `BookingDto`.
- Produces: `BookingTrackingScreen({required String bookingId})` — loads `get(bookingId)`; renders bookingNumber, a state badge ("Finding you a technician…" for DISPATCHED), service name, slot (formatted), address id, visit fee; a **Cancel** button `Key('cancelBookingBtn')` → `cancel(id)` on Ok `context.go('/home')`, on Failure a SnackBar (no swallow); a "Live tracking coming soon" banner.

**Route:** the wizard already does `context.go('/booking/:id')`; add the route:

```dart
GoRoute(
  path: '/booking/:id',
  builder: (_, state) => BookingTrackingScreen(bookingId: state.pathParameters['id']!),
),
```

- [ ] **Step 1: Write the failing test** — `test/booking/tracking_stub_test.dart`

```dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fixcare_customer/core/result.dart';
import 'package:fixcare_customer/features/booking/data/booking_repository.dart';
import 'package:fixcare_customer/features/booking/presentation/booking_tracking_screen.dart';

Map<String, dynamic> _booking() => {
  'id': 'b1', 'bookingNumber': 'FC-1001', 'state': 'DISPATCHED',
  'scheduledSlot': '2026-09-10T09:00:00.000Z', 'visitFeePaise': 14900, 'laborPaise': 45000, 'laborTier': 'T2',
  'service': {'id': 's1', 'name': 'Fridge not cooling'}, 'zone': {'id': 'z1', 'name': 'Vadodara'},
  'address': {'id': 'a1'}, 'diagnosis': null, 'parts': [],
  'estimate': {'laborPaise': 45000, 'partsPaise': 0, 'visitFeeCreditPaise': 0, 'totalPayablePaise': 45000},
  'photos': [], 'payment': null, 'dispute': null,
};

class _FakeBookingRepo extends BookingRepository {
  _FakeBookingRepo() : super(Dio());
  @override
  Future<Result<BookingDto>> get(String id) async => Ok(BookingDto.fromJson(_booking()));
}

void main() {
  testWidgets('renders bookingNumber + state + service', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [bookingRepositoryProvider.overrideWithValue(_FakeBookingRepo())],
      child: MaterialApp.router(
        routerConfig: GoRouter(initialLocation: '/booking/b1', routes: [
          GoRoute(path: '/booking/:id', builder: (_, s) => BookingTrackingScreen(bookingId: s.pathParameters['id']!)),
          GoRoute(path: '/home', builder: (_, _) => const Scaffold(body: Text('home'))),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('FC-1001'), findsOneWidget);
    expect(find.textContaining('Finding you a technician'), findsOneWidget);
    expect(find.text('Fridge not cooling'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run — verify FAILS.**
- [ ] **Step 3: Write `booking_tracking_screen.dart`** (ConsumerStatefulWidget loading `get(bookingId)`; the render + Cancel + banner per the behavior spec; state → label via a small `switch`/map with a "Finding you a technician…" default for DISPATCHED/CREATED). Format the slot with a lightweight `DateTime.parse(iso).toLocal()` display.
- [ ] **Step 4: Add the `/booking/:id` route + import.**
- [ ] **Step 5: Run + commit** — `flutter test test/booking/tracking_stub_test.dart` + full suite + analyze clean.

```bash
git add lib/features/booking/presentation/booking_tracking_screen.dart lib/core/router/app_router.dart test/booking/tracking_stub_test.dart
git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "feat(customer): booking tracking stub screen + /booking/:id route (slice 3)"
```

---

## Task 7: Final verification + docs

**Files:**
- Modify: `STATUS.md`, `CHANGELOG.md`

- [ ] **Step 1: Full verification.**
  - `dart run build_runner build --delete-conflicting-outputs` → **0 outputs** on a second run (idempotent); `git status` shows no uncommitted generated diff.
  - `flutter analyze` → **No issues found!**
  - `flutter test` → **all green** (report the count).
- [ ] **Step 2: Update `STATUS.md`** — Phase stays Month 5 customer app; Active task = Slice 3 complete on branch; Last shipped prepend a Slice 3 bullet (catalog + booking modules, Home real catalog, wizard, tracking stub); Next = Slice 4 (state-driven tracking + polling + actions). Note the Slice-2 carry-forwards were honored.
- [ ] **Step 3: Update `CHANGELOG.md`** — new `## 2026-09-05 — Customer app Slice 3` entry: catalog module (categories + per-zone services), booking module (full BookingDto + create/get/cancel), Home rebuilt to real catalog keyed on the default-address zone (no-address → add-address CTA), booking wizard (service→address→slot→confirm, future-ISO slot, 422 surfaced), tracking stub + cancel. Contract-guarded tests (exact-body create, {code,message} envelope). N tests, analyze clean.
- [ ] **Step 4: Commit**

```bash
git add STATUS.md CHANGELOG.md
git -c user.name="MohammadKaifSaiyad" -c user.email="saiyedkgn6@gmail.com" commit -m "docs(customer): slice 3 verification + STATUS + CHANGELOG (discovery + create booking)"
```

---

## Self-Review

**1. Spec coverage:**
- Home real catalog (categories + per-zone services) → Task 4 ✓; no-address CTA → Task 4 ✓.
- Booking wizard service→address→slot→confirm → Tasks 3 (controller/slot) + 5 (screen) ✓.
- `POST /me/bookings` exactly 3 fields, backend snapshots → Task 2 (repo, exact-body test) ✓; carry-forwards honored in the repo comment + test ✓.
- Land on tracking stub + Cancel → Task 6 ✓.
- 422 surfaced not swallowed → Task 5 test ✓.
- Contract-guarded tests (exact-body matcher, {code,message} envelope) → Tasks 1/2 ✓.
- Routing /book/:serviceId + /booking/:id → Tasks 5/6 ✓.
- Full BookingDto modeled now → Task 2 ✓.

**2. Placeholder scan:** every code step carries real code; the only prose-described widgets (Home's sub-widgets, the wizard screen body, the tracking screen body) have an explicit behavior spec + a driving test + the exact keys/text to hit — acceptable for UI whose full markup is long, and each is constrained by its test. No "TBD"/"handle errors"/"similar to".

**3. Type consistency:** `CatalogRepository.services({required String zoneId, String? categoryId})`, `BookingRepository.create({addressId, serviceId, scheduledSlot})`, `BookingWizard.build(String serviceId)`, `slotToIso(DateTime, SlotWindow, {DateTime? now})`, `BookingDto` field names — all consistent across tasks. `rupees(int paise)` helper defined in Task 4, referenced in Tasks 5/6 (implementer imports it from home or lifts it to a shared util — note: to avoid a cross-feature import, the implementer may duplicate the 2-line `rupees` helper in the booking screens or place it in `core/`; either is fine, flag it once).

**Gaps found & fixed inline:** (a) added the note that `failureKindFromStatus(422)` may be `unknown` not `validation` — the message assertion is load-bearing, don't change the shared helper; (b) added the test-determinism note for the slot window (preselect a future date); (c) split the two new routes across Tasks 5 and 6 so each task compiles/tests independently; (d) flagged the `rupees` helper's home for reuse.
