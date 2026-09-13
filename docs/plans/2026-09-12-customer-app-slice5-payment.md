# Customer App Slice 5 — Payment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Slice-4 "payment coming soon" placeholder with a real pay card offering UPI (Razorpay checkout) and Cash (receipt-OTP handshake) at the two payable states.

**Architecture:** Two bodyless repo calls (`initiatePayment`/`initiateCashPayment`); a pure `payViewFor()` derives the pay sub-state from `booking.state` + `booking.payment`; a `RazorpayCheckout` wrapper (fakeable provider) drives the native `razorpay_flutter` sheet; the `_PhaseSummary` payment/declined branch becomes a `payViewFor`-driven `_PayCard`. Payment confirmation is webhook/technician-driven server-side — the app never trusts its own callback for `paid`; it rides Slice-4's booking poll.

**Tech Stack:** Flutter 3.47, Riverpod 3.x, freezed 4, dio 5, `razorpay_flutter` (new, per ADR-0006), `http_mock_adapter` + `flutter_test` (hermetic). Codegen: `dart run build_runner build --delete-conflicting-outputs`.

**Spec:** `docs/designs/2026-09-12-customer-app-slice5-payment-design.md` (+ `docs/adrs/ADR-0006-razorpay-flutter-checkout.md`)

## Global Constraints

- **`flutter analyze` 0 issues** before every commit (an `info` counts). Run from `apps/customer/`.
- **TDD:** failing test first, watch it fail, then minimal implementation. All tests hermetic — mock the transport (`http_mock_adapter`) or inject fakes; never hit a real network, never invoke the real native plugin in tests.
- **Repository requests use `FullHttpRequestMatcher(needsExactBody: true)`** in tests. Both pay endpoints are **bodyless POSTs** — the app sends NO body (the server computes the amount). Route through the repo's existing `_ok` helper (they return a JSON object).
- **Never swallow a `Failure`** — every pay action maps `Result` → visible UX (SnackBar / inline), surfacing the backend `{code,message}`.
- **App sends no amount, no customer id, no client-snapshotted price.** Both pay calls are bodyless.
- **`paid` is NEVER set from the checkout callback.** A successful checkout → `upiPending` + `refetch()`; `paid` comes only from the polled DTO (`payment.status == 'CAPTURED'`).
- **The customer app NEVER submits the cash OTP** — it only displays it. No customer-side verify/submit control for cash.
- **`keyId == null`** (dev / no Razorpay keys) → a first-class "UPI unavailable — pay by cash" branch; the plugin is never opened.
- **Cash dev-echo OTP** renders only behind `!kReleaseMode` (`import 'package:flutter/foundation.dart' show kReleaseMode;`), key `Key('devCashOtp')`.
- **Money is integer paise**; render with the existing `rupees(int paise)`.
- After adding a freezed class or a new dep, re-run build_runner / `flutter pub get` and commit generated + lock files.
- Commit as `MohammadKaifSaiyad <saiyedkgn6@gmail.com>`, no Claude trailer.

---

## File Structure

**Data:**
- `lib/features/booking/data/booking_dtos.dart` — **modify:** add `PaymentInitDto`, `CashInitDto`.
- `lib/features/booking/data/booking_repository.dart` — **modify:** add `initiatePayment`, `initiateCashPayment`.

**Presentation:**
- `lib/features/booking/presentation/pay_view.dart` — **create, pure:** `PayView` enum, `payViewFor()`, `payableAmountPaise()`.
- `lib/features/booking/presentation/razorpay_checkout.dart` — **create:** `RazorpayCheckout` + `CheckoutOutcome` + `razorpayCheckoutProvider`.
- `lib/features/booking/presentation/booking_tracking_screen.dart` — **modify:** thread `onRefetch`/`onSnack` into `_PhaseSummary`; add `_PayCard` (+ `_PayChoose`/`_UpiPending`/`_CashPending`/`_PaidReceipt`) for the payment/declined branches.

**Native config:**
- `pubspec.yaml` / `pubspec.lock` — add `razorpay_flutter`.
- `android/app/proguard-rules.pro` — Razorpay keep rules.

**Tests:**
- `test/booking/booking_repository_test.dart` — **modify:** add pay-method cases.
- `test/booking/pay_view_test.dart` — **create.**
- `test/booking/razorpay_checkout_test.dart` — **create.**
- `test/booking/booking_tracking_screen_test.dart` — **modify:** add pay-card cases.

---

## Task 1: `PaymentInitDto` + `CashInitDto` + repository pay methods

**Files:**
- Modify: `lib/features/booking/data/booking_dtos.dart`
- Modify: `lib/features/booking/data/booking_repository.dart`
- Test: `test/booking/booking_repository_test.dart` (append)

**Interfaces:**
- Consumes: existing `BookingRepository` (`_dio`, `_ok`, `_guard`), `Result`/`Ok`/`Failure`/`FailureKind`.
- Produces:
  - `PaymentInitDto({required String orderId, required int amountPaise, String? keyId})` + `.fromJson`.
  - `CashInitDto({required int amountPaise, String? devOtp})` + `.fromJson`.
  - `Future<Result<PaymentInitDto>> BookingRepository.initiatePayment(String id)` → bodyless `POST /me/bookings/:id/pay`.
  - `Future<Result<CashInitDto>> BookingRepository.initiateCashPayment(String id)` → bodyless `POST /me/bookings/:id/pay-cash`.

- [ ] **Step 1: Write the failing tests** — append to `test/booking/booking_repository_test.dart` (reuse the existing `dio`/`adapter`/`repo` `setUp`):

```dart
test('initiatePayment is a BODYLESS POST, 200 -> Ok(PaymentInitDto)', () async {
  adapter.onPost('/me/bookings/b1/pay',
      (s) => s.reply(200, {'orderId': 'order_123', 'amountPaise': 45000, 'keyId': 'rzp_test_abc'}));
  final r = await repo.initiatePayment('b1');
  final v = (r as Ok<PaymentInitDto>).value;
  expect(v.orderId, 'order_123');
  expect(v.amountPaise, 45000);
  expect(v.keyId, 'rzp_test_abc');
});

test('initiatePayment parses keyId: null (dev / no Razorpay keys)', () async {
  adapter.onPost('/me/bookings/b1/pay',
      (s) => s.reply(200, {'orderId': 'order_dev_1', 'amountPaise': 45000, 'keyId': null}));
  final r = await repo.initiatePayment('b1');
  expect((r as Ok<PaymentInitDto>).value.keyId, isNull);
});

test('initiatePayment 409 already paid -> Failure with backend message', () async {
  adapter.onPost('/me/bookings/b1/pay',
      (s) => s.reply(409, {'code': 'CONFLICT', 'message': 'This booking is already paid'}));
  final r = await repo.initiatePayment('b1');
  expect((r as Failure).message, 'This booking is already paid');
});

test('initiatePayment 422 nothing payable -> Failure(unknown) with message', () async {
  adapter.onPost('/me/bookings/b1/pay',
      (s) => s.reply(422, {'code': 'UNPROCESSABLE', 'message': 'Nothing is payable for this booking'}));
  final r = await repo.initiatePayment('b1');
  final f = r as Failure;
  expect(f.kind, FailureKind.unknown); // failureKindFromStatus(422) == unknown
  expect(f.message, 'Nothing is payable for this booking');
});

test('initiateCashPayment BODYLESS POST 200 -> Ok(CashInitDto with devOtp)', () async {
  adapter.onPost('/me/bookings/b1/pay-cash', (s) => s.reply(200, {'amountPaise': 45000, 'devOtp': '654321'}));
  final r = await repo.initiateCashPayment('b1');
  final v = (r as Ok<CashInitDto>).value;
  expect(v.amountPaise, 45000);
  expect(v.devOtp, '654321');
});

test('initiateCashPayment 200 without devOtp (prod shape) -> devOtp null', () async {
  adapter.onPost('/me/bookings/b1/pay-cash', (s) => s.reply(200, {'amountPaise': 45000}));
  final r = await repo.initiateCashPayment('b1');
  expect((r as Ok<CashInitDto>).value.devOtp, isNull);
});

test('initiateCashPayment 422 cash unavailable -> Failure with message', () async {
  adapter.onPost('/me/bookings/b1/pay-cash',
      (s) => s.reply(422, {'code': 'UNPROCESSABLE', 'message': 'Cash is unavailable for this booking — please pay by UPI'}));
  final r = await repo.initiateCashPayment('b1');
  expect((r as Failure).message, 'Cash is unavailable for this booking — please pay by UPI');
});

test('initiateCashPayment 429 throttle -> Failure(rateLimited) with message', () async {
  adapter.onPost('/me/bookings/b1/pay-cash',
      (s) => s.reply(429, {'code': 'TOO_MANY_REQUESTS', 'message': 'Too many code requests. Try again later.'}));
  final r = await repo.initiateCashPayment('b1');
  final f = r as Failure;
  expect(f.kind, FailureKind.rateLimited);
  expect(f.message, 'Too many code requests. Try again later.');
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `flutter test test/booking/booking_repository_test.dart`
Expected: FAIL — `initiatePayment`/`initiateCashPayment`/`PaymentInitDto`/`CashInitDto` undefined.

- [ ] **Step 3: Add the DTOs** to `lib/features/booking/data/booking_dtos.dart` (after `CompletionOtpDto`, before `BookingDto`):

```dart
@freezed
abstract class PaymentInitDto with _$PaymentInitDto {
  const factory PaymentInitDto({required String orderId, required int amountPaise, String? keyId}) =
      _PaymentInitDto;
  factory PaymentInitDto.fromJson(Map<String, dynamic> j) => _$PaymentInitDtoFromJson(j);
}

@freezed
abstract class CashInitDto with _$CashInitDto {
  const factory CashInitDto({required int amountPaise, String? devOtp}) = _CashInitDto;
  factory CashInitDto.fromJson(Map<String, dynamic> j) => _$CashInitDtoFromJson(j);
}
```

- [ ] **Step 4: Add the repo methods** to `lib/features/booking/data/booking_repository.dart` (after `requestCompletionOtp`, inside the class). Bodyless POST (no `data:`), mapped via `_ok`:

```dart
Future<Result<PaymentInitDto>> initiatePayment(String id) => _guard(() async {
  final res = await _dio.post('/me/bookings/$id/pay');
  return _ok<PaymentInitDto>(res, (data) => PaymentInitDto.fromJson((data as Map).cast<String, dynamic>()));
});

Future<Result<CashInitDto>> initiateCashPayment(String id) => _guard(() async {
  final res = await _dio.post('/me/bookings/$id/pay-cash');
  return _ok<CashInitDto>(res, (data) => CashInitDto.fromJson((data as Map).cast<String, dynamic>()));
});
```

- [ ] **Step 5: Regenerate codegen**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: `booking_dtos.g.dart` + `booking_dtos.freezed.dart` updated with the two DTOs.

- [ ] **Step 6: Run tests + analyze**

Run: `flutter test test/booking/booking_repository_test.dart && flutter analyze`
Expected: all pass; `No issues found!`.

- [ ] **Step 7: Commit**

```bash
git add lib/features/booking/data/booking_dtos.dart lib/features/booking/data/booking_dtos.g.dart \
  lib/features/booking/data/booking_dtos.freezed.dart lib/features/booking/data/booking_repository.dart \
  test/booking/booking_repository_test.dart
git commit -m "feat(customer): booking repo — initiatePayment/initiateCashPayment (slice 5)"
```

---

## Task 2: `pay_view.dart` — pure pay-state mapper

**Files:**
- Create: `lib/features/booking/presentation/pay_view.dart`
- Test: `test/booking/pay_view_test.dart`

**Interfaces:**
- Consumes: `BookingDto` (needs `.state`, `.payment` (nullable `PaymentSummaryDto` with `.status`/`.method`), `.estimate.totalPayablePaise`, `.visitFeePaise`).
- Produces:
  - `enum PayView { none, choose, upiPending, cashPending, paid }`
  - `PayView payViewFor(BookingDto b)`
  - `int payableAmountPaise(BookingDto b)`

**Rules (from the spec table):**
- Payable states = `CUSTOMER_CONFIRMED`, `DECLINED_BY_CUSTOMER`.
- `payment.status == 'CAPTURED'` → `paid` (regardless of state — covers PAYMENT_RECEIVED/DISPUTED/CLOSED that carry a captured payment).
- else if NOT a payable state → `none`.
- else (payable, not captured): `payment == null` → `choose`; `FAILED` → `choose`; `CREATED` + `method=='UPI'` → `upiPending`; `CREATED` + `method=='CASH'` → `cashPending`.
- `payableAmountPaise`: `CUSTOMER_CONFIRMED` → `estimate.totalPayablePaise`; `DECLINED_BY_CUSTOMER` → `visitFeePaise`; else `0`.

- [ ] **Step 1: Write the failing test** — `test/booking/pay_view_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fixcare_customer/features/booking/data/booking_dtos.dart';
import 'package:fixcare_customer/features/booking/presentation/pay_view.dart';

BookingDto _b(String state, {Map<String, dynamic>? payment}) => BookingDto.fromJson({
  'id': 'b1', 'bookingNumber': 'FC-1', 'state': state,
  'scheduledSlot': '2026-09-10T09:00:00.000Z', 'visitFeePaise': 14900, 'laborPaise': 45000, 'laborTier': 'T2',
  'service': {'id': 's1', 'name': 'Svc'}, 'zone': {'id': 'z1', 'name': 'Vadodara'}, 'address': {'id': 'a1'},
  'diagnosis': null, 'parts': <Map<String, dynamic>>[],
  'estimate': {'laborPaise': 45000, 'partsPaise': 0, 'visitFeeCreditPaise': 0, 'totalPayablePaise': 45000},
  'photos': <Map<String, dynamic>>[], 'payment': payment, 'dispute': null,
});

Map<String, dynamic> _pay(String status, String method) =>
    {'status': status, 'method': method, 'amountPaise': 45000};

void main() {
  test('CUSTOMER_CONFIRMED, no payment -> choose', () {
    expect(payViewFor(_b('CUSTOMER_CONFIRMED')), PayView.choose);
  });
  test('DECLINED_BY_CUSTOMER, no payment -> choose (visit fee payable)', () {
    expect(payViewFor(_b('DECLINED_BY_CUSTOMER')), PayView.choose);
  });
  test('CREATED/UPI -> upiPending', () {
    expect(payViewFor(_b('CUSTOMER_CONFIRMED', payment: _pay('CREATED', 'UPI'))), PayView.upiPending);
  });
  test('CREATED/CASH -> cashPending', () {
    expect(payViewFor(_b('CUSTOMER_CONFIRMED', payment: _pay('CREATED', 'CASH'))), PayView.cashPending);
  });
  test('FAILED -> choose', () {
    expect(payViewFor(_b('CUSTOMER_CONFIRMED', payment: _pay('FAILED', 'UPI'))), PayView.choose);
  });
  test('CAPTURED -> paid (at PAYMENT_RECEIVED)', () {
    expect(payViewFor(_b('PAYMENT_RECEIVED', payment: _pay('CAPTURED', 'UPI'))), PayView.paid);
  });
  test('CAPTURED cash at DECLINED -> paid', () {
    expect(payViewFor(_b('DECLINED_BY_CUSTOMER', payment: _pay('CAPTURED', 'CASH'))), PayView.paid);
  });
  test('non-payable states -> none', () {
    for (final s in ['EN_ROUTE', 'DIAGNOSED', 'REPAIR_COMPLETE', 'ARRIVED']) {
      expect(payViewFor(_b(s)), PayView.none, reason: s);
    }
  });
  test('payableAmountPaise: CUSTOMER_CONFIRMED -> estimate total; DECLINED -> visit fee; else 0', () {
    expect(payableAmountPaise(_b('CUSTOMER_CONFIRMED')), 45000);
    expect(payableAmountPaise(_b('DECLINED_BY_CUSTOMER')), 14900);
    expect(payableAmountPaise(_b('EN_ROUTE')), 0);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/booking/pay_view_test.dart`
Expected: FAIL — `pay_view.dart` / symbols undefined.

- [ ] **Step 3: Create `lib/features/booking/presentation/pay_view.dart`** (pure Dart, only imports the DTOs):

```dart
import '../data/booking_dtos.dart';

enum PayView { none, choose, upiPending, cashPending, paid }

bool _isPayable(String state) => state == 'CUSTOMER_CONFIRMED' || state == 'DECLINED_BY_CUSTOMER';

/// Derives the payment sub-view from the booking state + its payment summary.
/// A CAPTURED payment always reads as `paid` (covers PAYMENT_RECEIVED onward).
PayView payViewFor(BookingDto b) {
  final p = b.payment;
  if (p != null && p.status == 'CAPTURED') return PayView.paid;
  if (!_isPayable(b.state)) return PayView.none;
  if (p == null || p.status == 'FAILED') return PayView.choose;
  // p.status == 'CREATED'
  return p.method == 'CASH' ? PayView.cashPending : PayView.upiPending;
}

/// The amount owed BEFORE a pay call is initiated. After init, the UI uses the
/// server's `amountPaise` from the /pay|/pay-cash response instead.
int payableAmountPaise(BookingDto b) => switch (b.state) {
      'CUSTOMER_CONFIRMED' => b.estimate.totalPayablePaise,
      'DECLINED_BY_CUSTOMER' => b.visitFeePaise,
      _ => 0,
    };
```

- [ ] **Step 4: Run tests + analyze**

Run: `flutter test test/booking/pay_view_test.dart && flutter analyze`
Expected: pass; clean.

- [ ] **Step 5: Commit**

```bash
git add lib/features/booking/presentation/pay_view.dart test/booking/pay_view_test.dart
git commit -m "feat(customer): pay_view — pure payment sub-state mapper (slice 5)"
```

---

## Task 3: `razorpay_flutter` dep + `RazorpayCheckout` wrapper + provider

**Files:**
- Modify: `pubspec.yaml` (+ `pubspec.lock`)
- Modify: `android/app/proguard-rules.pro` (create if absent)
- Create: `lib/features/booking/presentation/razorpay_checkout.dart`
- Test: `test/booking/razorpay_checkout_test.dart`

**Interfaces:**
- Produces:
  - `sealed class CheckoutOutcome` with `CheckoutSuccess({String? paymentId, String? signature})`, `CheckoutFailed({int? code, required String message})`, `CheckoutDismissed()`.
  - `class RazorpayCheckout` with `Future<CheckoutOutcome> open({required String keyId, required String orderId, required int amountPaise, required String name, required String description, String? prefillContact})` and `void dispose()`.
  - `final razorpayCheckoutProvider = Provider<RazorpayCheckout>(...)` — overridable in tests.

**Design notes for the implementer:**
- Add the dep: `flutter pub add razorpay_flutter` (pins a version into pubspec + lock). If it reports a `minSdkVersion` requirement above the app's current `android/app/build.gradle` value, raise `minSdkVersion` to satisfy it and note the change in the commit.
- `razorpay_flutter` API: `final rzp = Razorpay();` then `rzp.on(Razorpay.EVENT_PAYMENT_SUCCESS, handler)`, `EVENT_PAYMENT_ERROR`, `EVENT_EXTERNAL_WALLET`; `rzp.open({...})`; `rzp.clear()` to release listeners. It is **callback-based** — wrap it in a `Completer<CheckoutOutcome>`.
- In `open`: create a fresh `Razorpay()`, register the three handlers, `open` with `{'key': keyId, 'order_id': orderId, 'amount': amountPaise, 'currency': 'INR', 'name': name, 'description': description, if prefillContact != null 'prefill': {'contact': prefillContact}}`, `await` the completer, and **always `rzp.clear()` in a `finally`**. Map: success → `CheckoutSuccess(paymentId: resp.paymentId, signature: resp.signature)`; error → `CheckoutFailed(code: resp.code, message: resp.message ?? 'Payment failed')`; external wallet → treat as `CheckoutDismissed()` (V1: we don't complete via external wallet). Guard the completer against double-complete.
- **Do NOT trust success as paid** — that decision lives in the screen (Task 4); this wrapper only reports the raw outcome.
- The wrapper must be constructable and its outcome-mapping unit-testable WITHOUT opening a real sheet. Factor the event→outcome mapping into a pure, testable seam: a top-level (or static) function `CheckoutOutcome outcomeForSuccess(PaymentSuccessResponse r)`, `outcomeForError(PaymentFailureResponse r)` that the test can call directly. (The `open()` orchestration itself is on-device only.)

- [ ] **Step 1: Add the dependency**

Run: `flutter pub add razorpay_flutter`
Expected: `pubspec.yaml` gains `razorpay_flutter: ^<version>`, `pubspec.lock` updated. Run `flutter pub get` if needed.

- [ ] **Step 2: Add the Android ProGuard rule** — create/append `android/app/proguard-rules.pro`:

```proguard
# Razorpay (razorpay_flutter) — keep SDK + its Google Pay / annotation deps.
-keepclassmembers class * { @android.webkit.JavascriptInterface <methods>; }
-keepattributes JavascriptInterface
-keep class com.razorpay.** { *; }
-keep class proguard.annotation.** { *; }
-dontwarn com.razorpay.**
-dontwarn proguard.annotation.**
```

(If `android/app/build.gradle` doesn't already wire `proguardFiles` for release, that's fine — the rule is inert until minify is enabled; keeping the file avoids a future release-build crash. Do not enable minify in this task.)

- [ ] **Step 3: Write the failing test** — `test/booking/razorpay_checkout_test.dart` (tests the pure mapping seam + that the types exist):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:fixcare_customer/features/booking/presentation/razorpay_checkout.dart';

void main() {
  test('success response maps to CheckoutSuccess with ids', () {
    final r = PaymentSuccessResponse('pay_123', 'order_1', 'sig_1', null);
    final out = outcomeForSuccess(r);
    expect(out, isA<CheckoutSuccess>());
    expect((out as CheckoutSuccess).paymentId, 'pay_123');
  });

  test('error response maps to CheckoutFailed with message', () {
    final r = PaymentFailureResponse(2, 'User cancelled', null);
    final out = outcomeForError(r);
    expect(out, isA<CheckoutFailed>());
    expect((out as CheckoutFailed).message, 'User cancelled');
  });

  test('error response with null message falls back to a default message', () {
    final r = PaymentFailureResponse(1, null, null);
    final out = outcomeForError(r);
    expect((out as CheckoutFailed).message, isNotEmpty);
  });
}
```

> Note: the `razorpay_flutter` response constructors above match its public API (`PaymentSuccessResponse(paymentId, orderId, signature, data)`, `PaymentFailureResponse(code, message, error)`). If a pinned version's constructor signature differs, adapt the test to the actual constructor — the assertion (mapping → outcome) is the load-bearing part.

- [ ] **Step 4: Run to verify it fails**

Run: `flutter test test/booking/razorpay_checkout_test.dart`
Expected: FAIL — `razorpay_checkout.dart` / symbols undefined.

- [ ] **Step 5: Create `lib/features/booking/presentation/razorpay_checkout.dart`**:

```dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

sealed class CheckoutOutcome {
  const CheckoutOutcome();
}

class CheckoutSuccess extends CheckoutOutcome {
  const CheckoutSuccess({this.paymentId, this.signature});
  final String? paymentId;
  final String? signature;
}

class CheckoutFailed extends CheckoutOutcome {
  const CheckoutFailed({this.code, required this.message});
  final int? code;
  final String message;
}

class CheckoutDismissed extends CheckoutOutcome {
  const CheckoutDismissed();
}

/// Pure mapping seams (unit-testable without opening a sheet).
CheckoutOutcome outcomeForSuccess(PaymentSuccessResponse r) =>
    CheckoutSuccess(paymentId: r.paymentId, signature: r.signature);

CheckoutOutcome outcomeForError(PaymentFailureResponse r) =>
    CheckoutFailed(code: r.code, message: r.message ?? 'Payment failed');

/// Wraps the callback-based razorpay_flutter plugin in a Future. Always clears
/// the plugin's native listeners. Payment SUCCESS here is NOT "paid" — the
/// caller shows a pending state and lets the booking poll confirm via webhook.
class RazorpayCheckout {
  Future<CheckoutOutcome> open({
    required String keyId,
    required String orderId,
    required int amountPaise,
    required String name,
    required String description,
    String? prefillContact,
  }) async {
    final rzp = Razorpay();
    final completer = Completer<CheckoutOutcome>();
    void done(CheckoutOutcome o) {
      if (!completer.isCompleted) completer.complete(o);
    }

    rzp.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) => done(outcomeForSuccess(r)));
    rzp.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) => done(outcomeForError(r)));
    rzp.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse r) => done(const CheckoutDismissed()));

    try {
      rzp.open({
        'key': keyId,
        'order_id': orderId,
        'amount': amountPaise,
        'currency': 'INR',
        'name': name,
        'description': description,
        if (prefillContact != null) 'prefill': {'contact': prefillContact},
      });
      return await completer.future;
    } finally {
      rzp.clear();
    }
  }
}

final razorpayCheckoutProvider = Provider<RazorpayCheckout>((ref) => RazorpayCheckout());
```

- [ ] **Step 6: Run tests + analyze**

Run: `flutter test test/booking/razorpay_checkout_test.dart && flutter analyze`
Expected: pass; clean.

- [ ] **Step 7: Commit**

```bash
git add pubspec.yaml pubspec.lock android/app/proguard-rules.pro \
  lib/features/booking/presentation/razorpay_checkout.dart test/booking/razorpay_checkout_test.dart
git commit -m "feat(customer): razorpay_flutter checkout wrapper + provider (slice 5, ADR-0006)"
```

---

## Task 4: `_PayCard` — wire UPI + cash into the tracking screen

**Files:**
- Modify: `lib/features/booking/presentation/booking_tracking_screen.dart`
- Test: `test/booking/booking_tracking_screen_test.dart` (append pay cases)

**Interfaces:**
- Consumes: `payViewFor`/`payableAmountPaise`/`PayView` (Task 2); `razorpayCheckoutProvider` + `CheckoutOutcome`/`CheckoutSuccess`/`CheckoutFailed`/`CheckoutDismissed` (Task 3); `initiatePayment`/`initiateCashPayment` (Task 1); `rupees`, `FixCareColors`/`FixCareRadii`, the `Result` idiom, `kReleaseMode`; and the screen's existing `onRefetch`/`onSnack` callbacks.
- Produces: the payment/declined branches of `_PhaseSummary` now render `_PayCard`.

**Design notes for the implementer (read the current file first):**
- `_GateCard.build` at `TrackingGate.none` currently calls `_PhaseSummary(booking: booking)` (~line 189). Change it to `_PhaseSummary(booking: booking, onRefetch: onRefetch, onSnack: onSnack)` and add those two fields to `_PhaseSummary` (`Future<void> Function() onRefetch;`, `void Function(String) onSnack;`).
- In `_PhaseSummary.build`: replace the current `phase == TrackingPhase.payment` branch (the "Payment coming soon" `_CardShell`) AND make the `declined` phase render the pay card when it is still payable. Concretely: compute `final pv = payViewFor(booking);` — if `pv != PayView.none`, return `_PayCard(booking: booking, onRefetch: onRefetch, onSnack: onSnack)`. Keep the existing `disputed`, `completed`, `cancelled` branches. (For a `declined` booking that is already `paid`, `payViewFor` returns `paid` → `_PayCard` shows the receipt; for one still owing the visit fee it returns `choose`.)
- `_PayCard` is a `ConsumerStatefulWidget` (mirrors `_CompletionCard`): a `_busy` flag, plus fields for the cash panel (`_cashSent`, `_cashDevOtp`) and the UPI pending flag. It switches on `payViewFor(booking)`:
  - `PayView.choose` → `_CardShell(title: 'Payment')` with the amount (`rupees(payableAmountPaise(booking))`) and two buttons: `FilledButton` `Key('payUpiBtn')` "Pay by UPI" → `_payUpi()`; `OutlinedButton` `Key('payCashBtn')` "Pay cash" → `_payCash()`. If the last attempt was `FAILED`, prefix a "Last payment didn't go through" line.
  - `PayView.upiPending` → "Confirming your payment…" + a spinner (+ a "Pay another way" `TextButton` that returns to choose by clearing local pending — optional escape).
  - `PayView.cashPending` → the cash OTP panel (mirror `_CompletionCard`): "Read this 6-digit code to your technician." + the dev chip `Key('devCashOtp')` behind `!kReleaseMode && _cashDevOtp != null`, + "Waiting for your technician to confirm…". **No submit/verify field.**
  - `PayView.paid` → `_CardShell(title: 'Paid')` with `✓ {method} · {rupees(payment.amountPaise)}`.
- `_payUpi()`: `setState(_busy=true)`; `final r = await ref.read(bookingRepositoryProvider).initiatePayment(booking.id);` On `Failure` → `onSnack(m)`, `_busy=false`. On `Ok(init)`:
  - **if `init.keyId == null`** → `onSnack('UPI isn\'t available right now — please pay by cash.')`, `_busy=false`, return (never open the plugin).
  - else → `final outcome = await ref.read(razorpayCheckoutProvider).open(keyId: init.keyId!, orderId: init.orderId, amountPaise: init.amountPaise, name: 'FixCare', description: booking.service.name);` then `if (!mounted) return;` switch: `CheckoutSuccess` → `setState(_busy=false)` + `await onRefetch()` (the poll + webhook confirm; UI moves to `upiPending`); `CheckoutFailed(message)` → `onSnack(message)`, `_busy=false`; `CheckoutDismissed` → `_busy=false` (quiet).
- `_payCash()`: `setState(_busy=true)`; `final r = await ref.read(bookingRepositoryProvider).initiateCashPayment(booking.id);` On `Failure(m)` → `onSnack(m)`, `_busy=false`. On `Ok(init)` → `setState(_busy=false, _cashSent=true, _cashDevOtp=init.devOtp)` + `await onRefetch()` (so the DTO's payment becomes CREATED/CASH → `cashPending` renders). 
- Guard every in-flight action with `_busy` disabling the buttons (no double-fire). Guard `setState` with `if (mounted)` after every await.
- Remove the old "Payment coming soon" `_CardShell` and the `declined` static "visit fee still applies" text (the pay card replaces both). Keep `_CardShell`, `_Row`.

- [ ] **Step 1: Write the failing widget tests** — append to `test/booking/booking_tracking_screen_test.dart`. Extend the existing `_FakeBookingRepo` to override `initiatePayment`/`initiateCashPayment` (recording calls + returning a settable `Result`), and add a `_FakeRazorpayCheckout extends RazorpayCheckout` overriding `open` to return a settable `CheckoutOutcome` (recording whether it was called). Override `razorpayCheckoutProvider` in the `ProviderScope`. Cover (mirror the existing harness's pump helpers):

```dart
// Required cases (implementer writes the harness + bodies):
// 1. CUSTOMER_CONFIRMED, payment:null -> payUpiBtn + payCashBtn render; amount shows rupees(estimate.totalPayablePaise).
// 2. Tap payUpiBtn, initiatePayment -> Ok(keyId:'rzp_test'): fake checkout.open IS called; on CheckoutSuccess, onRefetch fires (assert via a refetch spy / repo.get call count).
// 3. Tap payUpiBtn, initiatePayment -> Ok(keyId:null): fake checkout.open is NOT called; a SnackBar with the "UPI isn't available" message shows; cash button still present.
// 4. Tap payCashBtn -> initiateCashPayment called; on Ok(devOtp:'654321'), after the DTO flips to CREATED/CASH the panel + find.byKey(Key('devCashOtp')) '654321' render; assert NO text field / submit control exists in the card.
// 5. payment CREATED/UPI -> upiPending "Confirming" copy; no pay buttons.
// 6. payment CAPTURED (PAYMENT_RECEIVED) -> paid receipt line; no pay buttons.
// 7. DECLINED_BY_CUSTOMER, payment:null -> pay card shows rupees(visitFeePaise) and both buttons.
// 8. initiateCashPayment -> Failure(429, 'Too many code requests. Try again later.') -> SnackBar with that message.
```

Each test asserts the exact `find.text`/`find.byKey` and that the fake's method was invoked (record calls on the fakes).

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/booking/booking_tracking_screen_test.dart`
Expected: FAIL — pay card / keys don't exist yet.

- [ ] **Step 3: Implement** — thread `onRefetch`/`onSnack` into `_PhaseSummary`, add `_PayCard` (+ sub-widgets) per the design notes, and remove the old placeholder + declined static text.

- [ ] **Step 4: Run tests + analyze**

Run: `flutter test test/booking/booking_tracking_screen_test.dart && flutter analyze`
Expected: pass; clean.

- [ ] **Step 5: Run the FULL suite**

Run: `flutter test`
Expected: `All tests passed!` (the contract-smoke tests skip with no `BASE_URL`). Analyze clean.

- [ ] **Step 6: Commit**

```bash
git add lib/features/booking/presentation/booking_tracking_screen.dart test/booking/booking_tracking_screen_test.dart
git commit -m "feat(customer): pay card — UPI (keyId-gated) + cash OTP in tracking screen (slice 5)"
```

---

## Self-Review

**1. Spec coverage:**
- Bodyless `/pay` + `/pay-cash` repo calls, DTOs incl. `keyId:null` → Task 1. ✓
- `payViewFor` (choose/upiPending/cashPending/paid/none) + `payableAmountPaise` → Task 2. ✓
- `razorpay_flutter` dep + ADR wiring + `RazorpayCheckout` wrapper (always-clear, provider) → Task 3. ✓
- `keyId == null` → UPI-unavailable branch, plugin never opened → Task 4 `_payUpi`, case 3. ✓
- `paid` only via poll (checkout success → refetch, not paid) → Task 4 `_payUpi` CheckoutSuccess, case 2 + the `payViewFor` CAPTURED rule. ✓
- Customer never submits cash OTP (display-only, dev echo behind `!kReleaseMode`) → Task 4 `cashPending`, case 4. ✓
- Declined bookings can pay the visit fee → Task 2 payable rule + Task 4 `_PhaseSummary` declined branch, case 7. ✓
- Never-swallow (409/422/429 surfaced) → Task 1 tests + Task 4 `onSnack`, cases 3/8. ✓
- Deferred real-backend smoke proof → noted in spec, not a task (correct). ✓

**2. Placeholder scan:** No TBD/TODO. Task 4's widget-test bodies are sketched as named cases (the harness is a direct extension of the existing `booking_tracking_screen_test.dart` fakes); every production code block is complete. Task 3 flags that the `razorpay_flutter` response constructor signature must be matched to the pinned version — that's a real API-verification step, not a placeholder.

**3. Type consistency:** `PaymentInitDto{orderId,amountPaise,keyId?}`, `CashInitDto{amountPaise,devOtp?}`, `PayView{none,choose,upiPending,cashPending,paid}`, `payViewFor`/`payableAmountPaise`, `CheckoutOutcome`/`CheckoutSuccess`/`CheckoutFailed`/`CheckoutDismissed`, `razorpayCheckoutProvider`, `initiatePayment`/`initiateCashPayment` are used identically across tasks. Keys (`payUpiBtn`/`payCashBtn`/`devCashOtp`) consistent. `payment.status`/`method` string values (`CAPTURED`/`CREATED`/`FAILED`, `UPI`/`CASH`) match the backend enums. ✓
