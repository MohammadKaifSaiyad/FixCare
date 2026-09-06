# Customer App Slice 4 — Booking Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Slice-3 tracking *stub* at `/booking/:id` with a live, state-driven tracking screen that polls the booking and drives the three customer-side keystone gates (confirm-arrival, approve/decline, completion-OTP).

**Architecture:** A pure `phaseFor()` maps the 17 backend states → customer phases; an `@riverpod` family controller adaptively polls `GET /me/bookings/:id` (stops at terminal, pauses when backgrounded, keeps last-good on a poll failure); the screen renders a timeline + a phase-specific action card; gate calls live on `BookingRepository` and trigger an immediate refetch on success. Address label is joined app-side from `/me/addresses` (backend `address` is only `{id}`).

**Tech Stack:** Flutter 3.47, Riverpod 3.x `@riverpod` codegen, go_router 18, dio 5, freezed 4, `http_mock_adapter` + `flutter_test` (hermetic). Codegen: `dart run build_runner build --delete-conflicting-outputs`.

**Spec:** `docs/designs/2026-09-06-customer-app-slice4-booking-tracking-design.md`

## Global Constraints

- **`flutter analyze` must report 0 issues** before every commit (an `info` lint counts). Run from `apps/customer/`.
- **TDD:** write the failing test first, watch it fail, then the minimal implementation. All tests are hermetic — mock the transport (`http_mock_adapter`) or inject a fake repo; never hit a real network.
- **Repository requests use `FullHttpRequestMatcher(needsExactBody: true)`** in tests — a bodyless POST must send NO body; a bodied POST must send exactly the expected body (guards the DELETE/GET content-type class of bug).
- **Never swallow a `Failure`** — every gate maps `Result` → visible UX (inline message / SnackBar / dialog), surfacing the backend `{code,message}`.
- **App never sends a customer id** (JWT-derived server-side) and **never a client-snapshotted price** (estimate comes from the DTO). Confirm-arrival sends only `{code}`; approve/decline/request-completion-otp are bodyless.
- **Completion is the keystone asymmetry:** the customer screen only **mints + displays** the OTP; the technician enters it. No customer-side "verify".
- **Money is integer paise**; render with the existing `rupees(int paise)` from `home_screen.dart`.
- After adding/removing any `@riverpod` provider or freezed class, **re-run build_runner and commit the regenerated `*.g.dart`/`*.freezed.dart`**.
- Commit as `MohammadKaifSaiyad <saiyedkgn6@gmail.com>`, no Claude trailer.

---

## File Structure

**Data:**
- `lib/features/booking/data/booking_dtos.dart` — **modify:** add `CompletionOtpDto`.
- `lib/features/booking/data/booking_repository.dart` — **modify:** add `confirmArrival`, `approve`, `decline`, `requestCompletionOtp`.

**Presentation:**
- `lib/features/booking/presentation/tracking_phase.dart` — **create, pure** (no Flutter import): `TrackingPhase` enum, `TrackingGate` enum, `phaseFor()`, `isCancellable()`, `isTerminal()`.
- `lib/features/booking/presentation/booking_address_label.dart` — **create:** `bookingAddressLabelProvider(String addressId)`.
- `lib/features/booking/presentation/booking_tracking_controller.dart` — **create, `@riverpod`:** adaptive polling family controller.
- `lib/features/booking/presentation/booking_tracking_screen.dart` — **rewrite:** timeline + phase cards + gates.

**Tests:**
- `test/booking/booking_repository_test.dart` — **modify:** add gate-method cases.
- `test/booking/tracking_phase_test.dart` — **create:** exhaustive 17-state table.
- `test/booking/booking_address_label_test.dart` — **create.**
- `test/booking/booking_tracking_controller_test.dart` — **create:** `fakeAsync` polling.
- `test/booking/tracking_stub_test.dart` — **delete** (screen it tested is replaced).
- `test/booking/booking_tracking_screen_test.dart` — **create:** phase/gate widget tests.

---

## Task 1: `CompletionOtpDto` + repository gate methods

**Files:**
- Modify: `lib/features/booking/data/booking_dtos.dart`
- Modify: `lib/features/booking/data/booking_repository.dart`
- Test: `test/booking/booking_repository_test.dart` (append cases)

**Interfaces:**
- Consumes: existing `BookingRepository` (`_dio`, `_ok`, `_guard`, `_msg`), `Result`/`Ok`/`Failure`/`FailureKind`/`failureKindFromStatus` from `core/result.dart`.
- Produces:
  - `CompletionOtpDto({required bool ok, String? devOtp})` with `.fromJson`.
  - `Future<Result<void>> BookingRepository.confirmArrival(String id, String code)` → `POST /me/bookings/:id/confirm-arrival` body `{'code': code}`.
  - `Future<Result<void>> BookingRepository.approve(String id)` → bodyless `POST /me/bookings/:id/approve`.
  - `Future<Result<void>> BookingRepository.decline(String id)` → bodyless `POST /me/bookings/:id/decline`.
  - `Future<Result<CompletionOtpDto>> BookingRepository.requestCompletionOtp(String id)` → bodyless `POST /me/bookings/:id/request-completion-otp`.

- [ ] **Step 1: Write the failing tests** — append to `test/booking/booking_repository_test.dart` (reuse the existing `dio`/`adapter`/`repo` `setUp`):

```dart
test('confirmArrival POSTs EXACTLY {code} and 200 -> Ok(void)', () async {
  adapter.onPost('/me/bookings/b1/confirm-arrival', (s) => s.reply(200, {'state': 'ARRIVED'}),
      data: {'code': '123456'});
  final r = await repo.confirmArrival('b1', '123456');
  expect(r, isA<Ok<void>>());
});

test('confirmArrival 401 -> Failure(unauthorized) with backend message', () async {
  adapter.onPost('/me/bookings/b1/confirm-arrival',
      (s) => s.reply(401, {'code': 'UNAUTHORIZED', 'message': 'Invalid or expired arrival code'}),
      data: {'code': '000000'});
  final r = await repo.confirmArrival('b1', '000000');
  final f = r as Failure;
  expect(f.kind, FailureKind.unauthorized);
  expect(f.message, 'Invalid or expired arrival code');
});

test('confirmArrival 409 (tech not arrived yet) -> Failure with message', () async {
  adapter.onPost('/me/bookings/b1/confirm-arrival',
      (s) => s.reply(409, {'code': 'CONFLICT', 'message': 'The technician has not marked arrival yet'}),
      data: {'code': '123456'});
  final r = await repo.confirmArrival('b1', '123456');
  expect((r as Failure).message, 'The technician has not marked arrival yet');
});

test('approve is a BODYLESS POST and 200 -> Ok(void)', () async {
  adapter.onPost('/me/bookings/b1/approve', (s) => s.reply(200, {'state': 'CUSTOMER_APPROVED'}));
  final r = await repo.approve('b1');
  expect(r, isA<Ok<void>>());
});

test('approve 409 (not awaiting a decision) -> Failure with message', () async {
  adapter.onPost('/me/bookings/b1/approve',
      (s) => s.reply(409, {'code': 'CONFLICT', 'message': 'Booking is not awaiting a decision'}));
  final r = await repo.approve('b1');
  expect((r as Failure).message, 'Booking is not awaiting a decision');
});

test('decline is a BODYLESS POST and 200 -> Ok(void)', () async {
  adapter.onPost('/me/bookings/b1/decline', (s) => s.reply(200, {'state': 'DECLINED_BY_CUSTOMER'}));
  final r = await repo.decline('b1');
  expect(r, isA<Ok<void>>());
});

test('requestCompletionOtp bodyless POST 200 -> Ok(CompletionOtpDto with devOtp)', () async {
  adapter.onPost('/me/bookings/b1/request-completion-otp', (s) => s.reply(200, {'ok': true, 'devOtp': '654321'}));
  final r = await repo.requestCompletionOtp('b1');
  final dto = (r as Ok<CompletionOtpDto>).value;
  expect(dto.ok, isTrue);
  expect(dto.devOtp, '654321');
});

test('requestCompletionOtp 200 without devOtp (prod shape) -> Ok(ok:true, devOtp:null)', () async {
  adapter.onPost('/me/bookings/b1/request-completion-otp', (s) => s.reply(200, {'ok': true}));
  final r = await repo.requestCompletionOtp('b1');
  expect((r as Ok<CompletionOtpDto>).value.devOtp, isNull);
});

test('requestCompletionOtp 429 throttle -> Failure(rateLimited) with message', () async {
  adapter.onPost('/me/bookings/b1/request-completion-otp',
      (s) => s.reply(429, {'code': 'TOO_MANY_REQUESTS', 'message': 'Too many code requests. Try again later.'}));
  final r = await repo.requestCompletionOtp('b1');
  final f = r as Failure;
  expect(f.kind, FailureKind.rateLimited);
  expect(f.message, 'Too many code requests. Try again later.');
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/booking/booking_repository_test.dart`
Expected: FAIL — `confirmArrival`/`approve`/`decline`/`requestCompletionOtp`/`CompletionOtpDto` are undefined.

- [ ] **Step 3: Add `CompletionOtpDto`** to `lib/features/booking/data/booking_dtos.dart` (place after `PaymentSummaryDto`, before `BookingDto`):

```dart
@freezed
abstract class CompletionOtpDto with _$CompletionOtpDto {
  const factory CompletionOtpDto({required bool ok, String? devOtp}) = _CompletionOtpDto;
  factory CompletionOtpDto.fromJson(Map<String, dynamic> j) => _$CompletionOtpDtoFromJson(j);
}
```

- [ ] **Step 4: Add the gate methods** to `lib/features/booking/data/booking_repository.dart` (inside the class, after `cancel`). Follow the existing `cancel` idiom for the void ones (a 2xx-with-non-map body must still be `Ok(null)`, so do NOT route the bodyless ones through `_ok`):

```dart
Future<Result<void>> confirmArrival(String id, String code) => _guard(() async {
  final res = await _dio.post('/me/bookings/$id/confirm-arrival', data: {'code': code});
  return _okVoid(res);
});

Future<Result<void>> approve(String id) => _guard(() async {
  final res = await _dio.post('/me/bookings/$id/approve');
  return _okVoid(res);
});

Future<Result<void>> decline(String id) => _guard(() async {
  final res = await _dio.post('/me/bookings/$id/decline');
  return _okVoid(res);
});

Future<Result<CompletionOtpDto>> requestCompletionOtp(String id) => _guard(() async {
  final res = await _dio.post('/me/bookings/$id/request-completion-otp');
  return _ok<CompletionOtpDto>(res, (data) => CompletionOtpDto.fromJson((data as Map).cast<String, dynamic>()));
});
```

Extract the shared void-mapping already inlined in `cancel` into a private helper (and make `cancel` call it too):

```dart
Result<void> _okVoid(Response res) {
  final status = res.statusCode ?? 0;
  if (status >= 200 && status < 300) return const Ok(null);
  return Failure(failureKindFromStatus(status), _msg(res.data));
}
```

- [ ] **Step 5: Regenerate codegen**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: `booking_dtos.g.dart` + `booking_dtos.freezed.dart` updated with `CompletionOtpDto`.

- [ ] **Step 6: Run tests + analyze**

Run: `flutter test test/booking/booking_repository_test.dart && flutter analyze`
Expected: all pass; analyze `No issues found!`.

- [ ] **Step 7: Commit**

```bash
git add lib/features/booking/data/booking_dtos.dart lib/features/booking/data/booking_dtos.g.dart \
  lib/features/booking/data/booking_dtos.freezed.dart lib/features/booking/data/booking_repository.dart \
  test/booking/booking_repository_test.dart
git commit -m "feat(customer): booking repo — confirmArrival/approve/decline/completionOtp gates (slice 4)"
```

---

## Task 2: `tracking_phase.dart` — pure 17-state mapper

**Files:**
- Create: `lib/features/booking/presentation/tracking_phase.dart`
- Test: `test/booking/tracking_phase_test.dart`

**Interfaces:**
- Consumes: `BookingDto` from `../data/booking_dtos.dart` (needs `.state` String and `.payment` nullable).
- Produces:
  - `enum TrackingPhase { finding, assigned, enRoute, arrived, diagnosis, repairing, confirmCompletion, payment, disputed, completed, cancelled, declined }`
  - `enum TrackingGate { none, arrival, decision, completion }`
  - `TrackingPhase phaseFor(BookingDto b)`
  - `TrackingGate gateFor(BookingDto b)`
  - `bool isCancellable(BookingDto b)` — state ∈ {CREATED, DISPATCHED, ACCEPTED, EN_ROUTE}
  - `bool isTerminal(BookingDto b)` — state ∈ {CLOSED, CANCELLED_BY_CUSTOMER, CANCELLED_BY_TECHNICIAN}, OR (DECLINED_BY_CUSTOMER AND payment != null)

- [ ] **Step 1: Write the failing test** — `test/booking/tracking_phase_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fixcare_customer/features/booking/data/booking_dtos.dart';
import 'package:fixcare_customer/features/booking/presentation/tracking_phase.dart';

BookingDto _b(String state, {Map<String, dynamic>? payment}) => BookingDto.fromJson({
  'id': 'b1', 'bookingNumber': 'FC-1', 'state': state,
  'scheduledSlot': '2026-09-10T09:00:00.000Z', 'visitFeePaise': 14900, 'laborPaise': 45000, 'laborTier': 'T2',
  'service': {'id': 's1', 'name': 'Svc'}, 'zone': {'id': 'z1', 'name': 'Vadodara'}, 'address': {'id': 'a1'},
  'diagnosis': null, 'parts': <Map<String, dynamic>>[],
  'estimate': {'laborPaise': 45000, 'partsPaise': 0, 'visitFeeCreditPaise': 0, 'totalPayablePaise': 45000},
  'photos': <Map<String, dynamic>>[], 'payment': payment, 'dispute': null,
});

void main() {
  final cases = <String, (TrackingPhase, TrackingGate)>{
    'CREATED': (TrackingPhase.finding, TrackingGate.none),
    'DISPATCHED': (TrackingPhase.finding, TrackingGate.none),
    'ACCEPTED': (TrackingPhase.assigned, TrackingGate.none),
    'EN_ROUTE': (TrackingPhase.enRoute, TrackingGate.arrival),
    'ARRIVED': (TrackingPhase.arrived, TrackingGate.none),
    'DIAGNOSED': (TrackingPhase.diagnosis, TrackingGate.decision),
    'CUSTOMER_APPROVED': (TrackingPhase.repairing, TrackingGate.none),
    'PARTS_REQUESTED': (TrackingPhase.repairing, TrackingGate.none),
    'PARTS_ACQUIRED': (TrackingPhase.repairing, TrackingGate.none),
    'REPAIR_IN_PROGRESS': (TrackingPhase.repairing, TrackingGate.none),
    'REPAIR_COMPLETE': (TrackingPhase.confirmCompletion, TrackingGate.completion),
    'CUSTOMER_CONFIRMED': (TrackingPhase.payment, TrackingGate.none),
    'PAYMENT_RECEIVED': (TrackingPhase.payment, TrackingGate.none),
    'DISPUTED': (TrackingPhase.disputed, TrackingGate.none),
    'CLOSED': (TrackingPhase.completed, TrackingGate.none),
    'CANCELLED_BY_CUSTOMER': (TrackingPhase.cancelled, TrackingGate.none),
    'CANCELLED_BY_TECHNICIAN': (TrackingPhase.cancelled, TrackingGate.none),
    'DECLINED_BY_CUSTOMER': (TrackingPhase.declined, TrackingGate.none),
  };

  cases.forEach((state, expected) {
    test('phaseFor($state) -> ${expected.$1} / gate ${expected.$2}', () {
      final b = _b(state);
      expect(phaseFor(b), expected.$1);
      expect(gateFor(b), expected.$2);
    });
  });

  test('all 18 backend states are covered by the table', () {
    expect(cases.length, 18);
  });

  test('isCancellable only for CREATED/DISPATCHED/ACCEPTED/EN_ROUTE', () {
    for (final s in ['CREATED', 'DISPATCHED', 'ACCEPTED', 'EN_ROUTE']) {
      expect(isCancellable(_b(s)), isTrue, reason: s);
    }
    for (final s in ['ARRIVED', 'DIAGNOSED', 'REPAIR_COMPLETE', 'CLOSED', 'CANCELLED_BY_CUSTOMER']) {
      expect(isCancellable(_b(s)), isFalse, reason: s);
    }
  });

  test('isTerminal: CLOSED + both cancels are terminal; DECLINED terminal only once paid', () {
    for (final s in ['CLOSED', 'CANCELLED_BY_CUSTOMER', 'CANCELLED_BY_TECHNICIAN']) {
      expect(isTerminal(_b(s)), isTrue, reason: s);
    }
    expect(isTerminal(_b('DECLINED_BY_CUSTOMER')), isFalse, reason: 'declined, not yet paid');
    expect(
      isTerminal(_b('DECLINED_BY_CUSTOMER', payment: {'status': 'CAPTURED', 'method': 'UPI', 'amountPaise': 14900})),
      isTrue, reason: 'declined + visit fee paid');
    expect(isTerminal(_b('EN_ROUTE')), isFalse);
  });

  test('an unknown state does not throw — falls back to finding/none/non-terminal', () {
    final b = _b('SOME_FUTURE_STATE');
    expect(phaseFor(b), TrackingPhase.finding);
    expect(gateFor(b), TrackingGate.none);
    expect(isTerminal(b), isFalse);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/booking/tracking_phase_test.dart`
Expected: FAIL — `tracking_phase.dart` / its symbols don't exist.

- [ ] **Step 3: Create `lib/features/booking/presentation/tracking_phase.dart`** (pure Dart, no Flutter import):

```dart
import '../data/booking_dtos.dart';

enum TrackingPhase {
  finding, assigned, enRoute, arrived, diagnosis, repairing,
  confirmCompletion, payment, disputed, completed, cancelled, declined,
}

enum TrackingGate { none, arrival, decision, completion }

/// Maps a backend booking state to a customer-facing phase. Unknown/future
/// states fall back to `finding` so the UI never renders a blank screen.
TrackingPhase phaseFor(BookingDto b) => switch (b.state) {
      'CREATED' || 'DISPATCHED' => TrackingPhase.finding,
      'ACCEPTED' => TrackingPhase.assigned,
      'EN_ROUTE' => TrackingPhase.enRoute,
      'ARRIVED' => TrackingPhase.arrived,
      'DIAGNOSED' => TrackingPhase.diagnosis,
      'CUSTOMER_APPROVED' || 'PARTS_REQUESTED' || 'PARTS_ACQUIRED' || 'REPAIR_IN_PROGRESS' =>
        TrackingPhase.repairing,
      'REPAIR_COMPLETE' => TrackingPhase.confirmCompletion,
      'CUSTOMER_CONFIRMED' || 'PAYMENT_RECEIVED' => TrackingPhase.payment,
      'DISPUTED' => TrackingPhase.disputed,
      'CLOSED' => TrackingPhase.completed,
      'CANCELLED_BY_CUSTOMER' || 'CANCELLED_BY_TECHNICIAN' => TrackingPhase.cancelled,
      'DECLINED_BY_CUSTOMER' => TrackingPhase.declined,
      _ => TrackingPhase.finding,
    };

/// The active customer gate for a state (the one interactive action available).
TrackingGate gateFor(BookingDto b) => switch (b.state) {
      'EN_ROUTE' => TrackingGate.arrival,
      'DIAGNOSED' => TrackingGate.decision,
      'REPAIR_COMPLETE' => TrackingGate.completion,
      _ => TrackingGate.none,
    };

bool isCancellable(BookingDto b) =>
    b.state == 'CREATED' || b.state == 'DISPATCHED' || b.state == 'ACCEPTED' || b.state == 'EN_ROUTE';

bool isTerminal(BookingDto b) =>
    b.state == 'CLOSED' ||
    b.state == 'CANCELLED_BY_CUSTOMER' ||
    b.state == 'CANCELLED_BY_TECHNICIAN' ||
    (b.state == 'DECLINED_BY_CUSTOMER' && b.payment != null);
```

- [ ] **Step 4: Run tests + analyze**

Run: `flutter test test/booking/tracking_phase_test.dart && flutter analyze`
Expected: all pass; analyze clean.

- [ ] **Step 5: Commit**

```bash
git add lib/features/booking/presentation/tracking_phase.dart test/booking/tracking_phase_test.dart
git commit -m "feat(customer): tracking_phase — pure 17-state -> customer phase/gate mapper (slice 4)"
```

---

## Task 3: `bookingAddressLabelProvider` — app-side address join

**Files:**
- Create: `lib/features/booking/presentation/booking_address_label.dart`
- Test: `test/booking/booking_address_label_test.dart`

**Interfaces:**
- Consumes: `addressRepositoryProvider` + `AddressDto` from `../../address/data/address_repository.dart` (`AddressDto` has `id`, `label`, `line1`, `pincode`); `Result`/`Ok`/`Failure`.
- Produces: `final bookingAddressLabelProvider = FutureProvider.family<String, String>(...)` — given an `addressId`, returns `"<label> · <line1>, <pincode>"`, or the raw `addressId` when the id isn't in the customer's list (deleted / not found / list fetch failed).

- [ ] **Step 1: Write the failing test** — `test/booking/booking_address_label_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fixcare_customer/core/result.dart';
import 'package:fixcare_customer/features/address/data/address_repository.dart';
import 'package:fixcare_customer/features/booking/presentation/booking_address_label.dart';

AddressDto _addr(String id) => AddressDto.fromJson({
  'id': id, 'label': 'Home', 'line1': '12 MG Road', 'line2': null, 'landmark': null,
  'pincode': '390001', 'lat': null, 'lng': null, 'isDefault': true, 'status': 'ACTIVE',
  'serviceable': true, 'zone': {'id': 'z1', 'name': 'Vadodara', 'visitFeePaise': 14900},
});

class _FakeAddressRepo extends AddressRepository {
  _FakeAddressRepo(this._result) : super(Dio());
  final Result<List<AddressDto>> _result;
  @override
  Future<Result<List<AddressDto>>> list() async => _result;
}

void main() {
  test('matching id -> "label · line1, pincode"', () async {
    final c = ProviderContainer(overrides: [
      addressRepositoryProvider.overrideWithValue(_FakeAddressRepo(Ok([_addr('a1')]))),
    ]);
    addTearDown(c.dispose);
    final label = await c.read(bookingAddressLabelProvider('a1').future);
    expect(label, 'Home · 12 MG Road, 390001');
  });

  test('id not in the list -> falls back to the raw id', () async {
    final c = ProviderContainer(overrides: [
      addressRepositoryProvider.overrideWithValue(_FakeAddressRepo(Ok([_addr('a1')]))),
    ]);
    addTearDown(c.dispose);
    final label = await c.read(bookingAddressLabelProvider('a2').future);
    expect(label, 'a2');
  });

  test('list fetch fails -> falls back to the raw id (never throws)', () async {
    final c = ProviderContainer(overrides: [
      addressRepositoryProvider.overrideWithValue(
        _FakeAddressRepo(const Failure(FailureKind.network, 'offline'))),
    ]);
    addTearDown(c.dispose);
    final label = await c.read(bookingAddressLabelProvider('a1').future);
    expect(label, 'a1');
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/booking/booking_address_label_test.dart`
Expected: FAIL — provider undefined.

- [ ] **Step 3: Create `lib/features/booking/presentation/booking_address_label.dart`** (plain `FutureProvider.family` — no codegen needed, keeps it simple):

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/result.dart';
import '../../address/data/address_repository.dart';

/// Joins a booking's `address.id` (the backend BookingDto carries only the id)
/// to a human label from the customer's own address list. Falls back to the
/// raw id when the address isn't found (deleted) or the list can't be fetched —
/// never throws, so the tracking screen always has something to show.
final bookingAddressLabelProvider = FutureProvider.family<String, String>((ref, addressId) async {
  final r = await ref.read(addressRepositoryProvider).list();
  return switch (r) {
    Ok(value: final list) => _labelFor(list, addressId),
    Failure() => addressId,
  };
});

String _labelFor(List<AddressDto> list, String addressId) {
  for (final a in list) {
    if (a.id == addressId) return '${a.label} · ${a.line1}, ${a.pincode}';
  }
  return addressId;
}
```

- [ ] **Step 4: Run tests + analyze**

Run: `flutter test test/booking/booking_address_label_test.dart && flutter analyze`
Expected: all pass; analyze clean.

- [ ] **Step 5: Commit**

```bash
git add lib/features/booking/presentation/booking_address_label.dart test/booking/booking_address_label_test.dart
git commit -m "feat(customer): bookingAddressLabelProvider — app-side address label join (slice 4)"
```

---

## Task 4: `BookingTrackingController` — adaptive polling controller

**Files:**
- Create: `lib/features/booking/presentation/booking_tracking_controller.dart`
- Test: `test/booking/booking_tracking_controller_test.dart`

**Interfaces:**
- Consumes: `bookingRepositoryProvider` + `BookingDto` (`../data/booking_repository.dart`); `isTerminal` (`tracking_phase.dart`); `Result`/`Ok`/`Failure`.
- Produces: `@riverpod class BookingTracking extends _$BookingTracking` with `Future<BookingDto> build(String bookingId)` (does the first load + arms the poll timer) and `Future<void> refetch()` (forced immediate reload). Poll interval is a top-level `const trackingPollInterval = Duration(seconds: 5)`.

**Design notes for the implementer:**
- On `build`: read the repo, `get(bookingId)`; `Ok` → return the dto and, if `!isTerminal(dto)`, start a periodic `Timer` (interval `trackingPollInterval`) that calls an internal poll; `Failure` → `throw Exception(message)` (first-load error surfaces as `AsyncError`, like `AddressController`).
- **Poll tick:** call `get(bookingId)`. On `Ok`, set `state = AsyncData(dto)`; if `isTerminal(dto)`, cancel the timer. On `Failure`, **do nothing** — keep the last `AsyncData` on screen (keep-last-good); the next tick retries.
- Use `ref.onDispose` to cancel the timer. Guard every timer callback with a disposed check (`if (!ref.mounted) return;` — Riverpod 3 exposes `ref.mounted`).
- `refetch()`: call `get`; on `Ok` set `AsyncData` (and cancel the timer if now terminal); on `Failure` keep last-good. Do NOT set `AsyncLoading` (avoids a flash mid-tracking).
- Lifecycle pause (foreground/background) is a **screen-level** concern (Task 5) via `AppLifecycleListener` → the screen calls `refetch()` on resume; the controller itself is lifecycle-agnostic and fully testable with `fakeAsync`. (This keeps the controller free of `WidgetsBinding`.)

- [ ] **Step 1: Write the failing test** — `test/booking/booking_tracking_controller_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fixcare_customer/core/result.dart';
import 'package:fixcare_customer/features/booking/data/booking_repository.dart';
import 'package:fixcare_customer/features/booking/presentation/booking_tracking_controller.dart';

BookingDto _b(String state) => BookingDto.fromJson({
  'id': 'b1', 'bookingNumber': 'FC-1', 'state': state,
  'scheduledSlot': '2026-09-10T09:00:00.000Z', 'visitFeePaise': 14900, 'laborPaise': 45000, 'laborTier': 'T2',
  'service': {'id': 's1', 'name': 'Svc'}, 'zone': {'id': 'z1', 'name': 'Vadodara'}, 'address': {'id': 'a1'},
  'diagnosis': null, 'parts': <Map<String, dynamic>>[],
  'estimate': {'laborPaise': 45000, 'partsPaise': 0, 'visitFeeCreditPaise': 0, 'totalPayablePaise': 45000},
  'photos': <Map<String, dynamic>>[], 'payment': null, 'dispute': null,
});

/// A scripted repo: returns states[callIndex], clamping at the last entry.
class _ScriptedRepo extends BookingRepository {
  _ScriptedRepo(this.results) : super(Dio());
  final List<Result<BookingDto>> results;
  int calls = 0;
  @override
  Future<Result<BookingDto>> get(String id) async {
    final r = results[calls < results.length ? calls : results.length - 1];
    calls++;
    return r;
  }
}

void main() {
  test('polls every 5s while active; stops once terminal', () {
    fakeAsync((async) {
      final repo = _ScriptedRepo([
        Ok(_b('EN_ROUTE')), Ok(_b('ARRIVED')), Ok(_b('CLOSED')), Ok(_b('CLOSED')),
      ]);
      final c = ProviderContainer(overrides: [bookingRepositoryProvider.overrideWithValue(repo)]);
      addTearDown(c.dispose);
      c.listen(bookingTrackingProvider('b1'), (_, __) {}, fireImmediately: true);
      async.flushMicrotasks(); // first load
      expect(repo.calls, 1);
      async.elapse(const Duration(seconds: 5)); // tick -> ARRIVED
      expect(repo.calls, 2);
      async.elapse(const Duration(seconds: 5)); // tick -> CLOSED (terminal, timer cancels)
      expect(repo.calls, 3);
      async.elapse(const Duration(seconds: 15)); // no more polls after terminal
      expect(repo.calls, 3);
    });
  });

  test('a poll Failure keeps the last good BookingDto (keep-last-good)', () {
    fakeAsync((async) {
      final repo = _ScriptedRepo([
        Ok(_b('EN_ROUTE')),
        const Failure(FailureKind.network, 'blip'),
        Ok(_b('ARRIVED')),
      ]);
      final c = ProviderContainer(overrides: [bookingRepositoryProvider.overrideWithValue(repo)]);
      addTearDown(c.dispose);
      c.listen(bookingTrackingProvider('b1'), (_, __) {}, fireImmediately: true);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 5)); // tick -> Failure
      final afterBlip = c.read(bookingTrackingProvider('b1'));
      expect(afterBlip.value?.state, 'EN_ROUTE', reason: 'last-good retained on a poll failure');
      expect(afterBlip.hasError, isFalse);
      async.elapse(const Duration(seconds: 5)); // tick -> ARRIVED
      expect(c.read(bookingTrackingProvider('b1')).value?.state, 'ARRIVED');
    });
  });

  test('first-load Failure surfaces as AsyncError', () {
    fakeAsync((async) {
      final repo = _ScriptedRepo([const Failure(FailureKind.network, 'offline')]);
      final c = ProviderContainer(overrides: [bookingRepositoryProvider.overrideWithValue(repo)]);
      addTearDown(c.dispose);
      c.listen(bookingTrackingProvider('b1'), (_, __) {}, fireImmediately: true);
      async.flushMicrotasks();
      expect(c.read(bookingTrackingProvider('b1')).hasError, isTrue);
    });
  });
}
```

> Note: the generated family provider is `bookingTrackingProvider` (from class `BookingTracking`). If `fake_async` isn't already a dev dependency, add it: `flutter pub add --dev fake_async` (commit the `pubspec.yaml`/`pubspec.lock` change with this task).

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/booking/booking_tracking_controller_test.dart`
Expected: FAIL — controller/provider undefined.

- [ ] **Step 3: Create `lib/features/booking/presentation/booking_tracking_controller.dart`**:

```dart
import 'dart:async';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../core/result.dart';
import '../data/booking_repository.dart';
import 'tracking_phase.dart';

part 'booking_tracking_controller.g.dart';

const trackingPollInterval = Duration(seconds: 5);

@riverpod
class BookingTracking extends _$BookingTracking {
  Timer? _timer;

  @override
  Future<BookingDto> build(String bookingId) async {
    ref.onDispose(() => _timer?.cancel());
    final dto = await _fetchOrThrow(bookingId);
    _arm(bookingId, dto);
    return dto;
  }

  Future<BookingDto> _fetchOrThrow(String bookingId) async {
    final r = await ref.read(bookingRepositoryProvider).get(bookingId);
    return switch (r) {
      Ok(value: final dto) => dto,
      Failure(message: final m) => throw Exception(m),
    };
  }

  void _arm(String bookingId, BookingDto dto) {
    _timer?.cancel();
    if (isTerminal(dto)) return;
    _timer = Timer.periodic(trackingPollInterval, (_) => _poll(bookingId));
  }

  Future<void> _poll(String bookingId) async {
    if (!ref.mounted) return;
    final r = await ref.read(bookingRepositoryProvider).get(bookingId);
    if (!ref.mounted) return;
    switch (r) {
      case Ok(value: final dto):
        state = AsyncData(dto);
        _arm(bookingId, dto); // cancels itself if now terminal
      case Failure():
        // keep-last-good: leave state as-is, retry next tick.
        break;
    }
  }

  /// Forced immediate reload (e.g. after a gate succeeds or on app resume).
  /// Keeps last-good on failure; never flashes AsyncLoading.
  Future<void> refetch() async {
    final bookingId = state.value?.id ?? (arg);
    final r = await ref.read(bookingRepositoryProvider).get(bookingId);
    if (!ref.mounted) return;
    switch (r) {
      case Ok(value: final dto):
        state = AsyncData(dto);
        _arm(bookingId, dto);
      case Failure():
        break;
    }
  }
}
```

> `arg` is the generated accessor for the family argument (`bookingId`) in a `@riverpod` class. If codegen names it differently, store `bookingId` in a field during `build` and use that.

- [ ] **Step 4: Regenerate codegen**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: `booking_tracking_controller.g.dart` created (`bookingTrackingProvider`).

- [ ] **Step 5: Run tests + analyze**

Run: `flutter test test/booking/booking_tracking_controller_test.dart && flutter analyze`
Expected: all pass; analyze clean.

- [ ] **Step 6: Commit**

```bash
git add lib/features/booking/presentation/booking_tracking_controller.dart \
  lib/features/booking/presentation/booking_tracking_controller.g.dart \
  test/booking/booking_tracking_controller_test.dart pubspec.yaml pubspec.lock
git commit -m "feat(customer): BookingTracking controller — adaptive poll, keep-last-good, refetch (slice 4)"
```

---

## Task 5: Rewrite the tracking screen — timeline + phase cards + gates

**Files:**
- Rewrite: `lib/features/booking/presentation/booking_tracking_screen.dart`
- Delete: `test/booking/tracking_stub_test.dart`
- Test: `test/booking/booking_tracking_screen_test.dart`

**Interfaces:**
- Consumes: `bookingTrackingProvider` + `BookingTracking.refetch()` (Task 4); `phaseFor`/`gateFor`/`isCancellable`/`TrackingGate`/`TrackingPhase` (Task 2); `bookingAddressLabelProvider` (Task 3); `BookingRepository.confirmArrival/approve/decline/requestCompletionOtp/cancel` (Task 1); `rupees` (home); `formatScheduledSlot` (wizard); `FixCareColors`/`FixCareRadii` (theme); `Env` for the dev-echo gate.
- Produces: the rewritten `BookingTrackingScreen` (same constructor `{required String bookingId}`, same route `/booking/:id` — no router change).

**Design notes for the implementer:**
- `ConsumerStatefulWidget`. `ref.watch(bookingTrackingProvider(bookingId))` → `AsyncValue<BookingDto>`; render:
  - `loading` (first load only) → `CircularProgressIndicator`.
  - `error` → the existing `_ErrorRetry` calling `ref.invalidate(bookingTrackingProvider(bookingId))`.
  - `data(booking)` → `_Tracking(booking, ...)`.
- **Lifecycle:** hold an `AppLifecycleListener` in state; `onResume` → `ref.read(bookingTrackingProvider(bookingId).notifier).refetch()`. Dispose it in `dispose()`.
- **Timeline:** a horizontal/vertical stepper derived from `phaseFor` — a fixed ordered list of milestones (Booked, Assigned, Arrived, Diagnosis, Repair, Done, Paid) with the current one highlighted. Keep it a small private `_Timeline` widget; do not over-build.
- **Info card:** service, time (`formatScheduledSlot`), address (`ref.watch(bookingAddressLabelProvider(booking.address.id)).maybeWhen(data: (l) => l, orElse: () => booking.address.id)`), visit fee (`rupees`). Technician block (name + masked phone) when `booking.technician != null`.
- **Gate card** by `gateFor(booking)`:
  - `arrival` → `_ArrivalCard`: a 6-digit `TextField` (validate `/^\d{6}$/` before calling), "Confirm arrival" button → `confirmArrival(id, code)`; on `Ok` → `refetch()`; on `Failure` → inline message under the field; per-card busy flag disables the button while in flight.
  - `decision` → `_DiagnosisCard`: shows `diagnosis?.issueName`, the parts list (name × qty, `rupees(ceilingPricePaise)`), and `rupees(estimate.totalPayablePaise)`. **Approve** (one tap → `approve(id)` → `refetch()`). **Decline** → `showDialog` confirm ("You'll still owe the ${rupees(booking.visitFeePaise)} visit fee. Decline this repair?") → on confirm `decline(id)` → `refetch()`. `Failure` → SnackBar.
  - `completion` → `_CompletionCard`: "Confirm work is done" → `requestCompletionOtp(id)`; on `Ok` show a panel "We texted a 6-digit code to your phone — read it to your technician." + a "Resend code" button; if `Env` is a dev build AND `dto.devOtp != null`, also show the code in a monospace chip with `Key('devCompletionOtp')`. 429 `Failure` → SnackBar + brief button disable.
  - `none` → for `payment` phase show a `_PayPlaceholder` ("Payment coming soon", `rupees(estimate.totalPayablePaise)`); for `disputed` show the dispute summary; for terminal phases show a small terminal summary; otherwise nothing.
- **Cancel** button (`Key('cancelBookingBtn')`) only when `isCancellable(booking)` → `cancel(id)` → on `Ok` `context.go('/home')`, on `Failure` SnackBar. Reuse the existing pattern.
- Keep `_ErrorRetry` and `_Row` (or equivalent). Split cards into private widgets so the file stays readable.
- For the dev-echo check use the same env signal the app already uses (e.g. `!kReleaseMode` from `package:flutter/foundation.dart`), so the `devOtp` chip never renders in a release build.

- [ ] **Step 1: Write the failing widget tests** — `test/booking/booking_tracking_screen_test.dart`. Use a `_FakeBookingRepo extends BookingRepository` (super `Dio()`) overriding `get` (returns a state-specific dto) + the gate methods, and a `_FakeAddressRepo` for the label. Pump inside a `ProviderScope` + `MaterialApp.router` with `/booking/:id` + `/home` routes (mirror `tracking_stub_test.dart`'s harness). Cover:

```dart
// Sketch of the required cases (implementer writes the full harness):
// 1. EN_ROUTE -> a 6-digit field renders; entering '123456' + tapping Confirm calls confirmArrival('b1','123456');
//    a Failure(confirmArrival) shows its message inline.
// 2. DIAGNOSED -> issueName + parts + total render; Approve calls approve('b1');
//    Decline opens a dialog whose text contains the visit fee (e.g. '149'); confirming calls decline('b1').
// 3. REPAIR_COMPLETE -> 'Confirm work is done' calls requestCompletionOtp('b1');
//    on Ok(devOtp:'654321') the panel + find.byKey(Key('devCompletionOtp')) with '654321' appear.
// 4. isCancellable state (DISPATCHED) -> cancelBookingBtn present; ARRIVED -> cancelBookingBtn absent.
// 5. address label: with a matching address in the fake list, the joined label (not the raw 'a1') renders.
```

Each test asserts the specific `find.text` / `find.byKey` / that the fake's gate method was invoked (record calls on the fake).

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/booking/booking_tracking_screen_test.dart`
Expected: FAIL — new screen behavior/keys don't exist yet.

- [ ] **Step 3: Delete the obsolete stub test**

```bash
git rm test/booking/tracking_stub_test.dart
```

- [ ] **Step 4: Rewrite `lib/features/booking/presentation/booking_tracking_screen.dart`** per the design notes above (watch `bookingTrackingProvider`, timeline, info card, gate cards, cancel, `AppLifecycleListener`, dev-echo behind `!kReleaseMode`). Remove the "Live tracking coming soon" dev-hint block and the raw-`address.id` row.

- [ ] **Step 5: Run tests + analyze**

Run: `flutter test test/booking/booking_tracking_screen_test.dart && flutter analyze`
Expected: all pass; analyze clean.

- [ ] **Step 6: Run the FULL suite** (this task touches the router-reachable screen)

Run: `flutter test`
Expected: `All tests passed!` (the smoke tests skip with no `BASE_URL`). Analyze clean.

- [ ] **Step 7: Commit**

```bash
git add lib/features/booking/presentation/booking_tracking_screen.dart test/booking/booking_tracking_screen_test.dart
git commit -m "feat(customer): live booking tracking screen — timeline + arrival/decision/completion gates (slice 4)"
```

---

## Self-Review

**1. Spec coverage:**
- Adaptive poll (5s, stop-at-terminal, lifecycle pause, keep-last-good) → Task 4 (controller) + Task 5 (lifecycle). ✓
- 17-state → phase mapping, exhaustive → Task 2. ✓
- Three gates (confirm-arrival `{code}`, approve/decline bodyless, completion mint) → Task 1 (repo) + Task 5 (UI). ✓
- Decline confirm dialog (visit fee) → Task 5, case 2. ✓
- Completion OTP mint + "texted to your phone" + dev echo + 429 → Task 1 + Task 5, case 3. ✓
- App-side address join → Task 3. ✓
- Payment deferred (placeholder + amount owed) → Task 5 (`_PayPlaceholder`). ✓
- Cancel only while cancellable → Task 2 (`isCancellable`) + Task 5, case 4. ✓
- Contract-guarded repo tests (exact body) → Task 1. ✓
- Deferred real-backend smoke proof → noted in the spec; not a task (correct — the harness can't drive tech-side states yet). ✓

**2. Placeholder scan:** No TBD/TODO. Task 5's widget-test bodies are sketched as required cases rather than full source — acceptable because the harness is a direct copy of the existing `tracking_stub_test.dart` pattern and each case's assertion target is named explicitly; the implementer writes the harness once and fills the 5 cases. Every production code block is complete.

**3. Type consistency:** `bookingTrackingProvider` (from class `BookingTracking`), `CompletionOtpDto({ok, devOtp})`, `TrackingGate {none,arrival,decision,completion}`, `TrackingPhase` (12 values), `phaseFor`/`gateFor`/`isCancellable`/`isTerminal`, `confirmArrival(id,code)`/`approve(id)`/`decline(id)`/`requestCompletionOtp(id)` are used identically across tasks. `_okVoid` introduced in Task 1 and reused. `isTerminal` from Task 2 consumed in Task 4. ✓
