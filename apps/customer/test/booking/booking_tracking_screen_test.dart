import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fixcare_customer/core/result.dart';
import 'package:fixcare_customer/features/address/data/address_repository.dart';
import 'package:fixcare_customer/features/booking/data/booking_repository.dart';
import 'package:fixcare_customer/features/booking/presentation/booking_tracking_screen.dart';
import 'package:fixcare_customer/features/booking/presentation/razorpay_checkout.dart';

/// A booking snapshot in [state], with optional diagnosis/parts/technician so a
/// test can drive any gate. Field names mirror the backend BookingDto JSON.
Map<String, dynamic> _booking(
  String state, {
  bool withTech = false,
  bool withDiagnosis = false,
  Map<String, dynamic>? payment,
}) => {
  'id': 'b1',
  'bookingNumber': 'FC-1001',
  'state': state,
  'scheduledSlot': '2026-09-10T09:00:00.000Z',
  'visitFeePaise': 14900,
  'laborPaise': 45000,
  'laborTier': 'T2',
  'service': {'id': 's1', 'name': 'Fridge not cooling'},
  'zone': {'id': 'z1', 'name': 'Vadodara'},
  'address': {'id': 'a1'},
  'technician': withTech ? {'name': 'Ravi K.', 'maskedPhone': '+91·····3210'} : null,
  'diagnosis': withDiagnosis ? {'issueName': 'Compressor relay failure'} : null,
  'parts': withDiagnosis
      ? [
          {'id': 'p1', 'sku': 'RLY-1', 'name': 'Relay', 'ceilingPricePaise': 30000, 'qty': 2},
        ]
      : <Map<String, dynamic>>[],
  'estimate': {
    'laborPaise': 45000,
    'partsPaise': withDiagnosis ? 60000 : 0,
    'visitFeeCreditPaise': 0,
    'totalPayablePaise': withDiagnosis ? 105000 : 45000,
  },
  'photos': <Map<String, dynamic>>[],
  'payment': payment,
  'dispute': null,
};

Map<String, dynamic> _pay(String status, String method, int amountPaise) =>
    {'status': status, 'method': method, 'amountPaise': amountPaise};

class _FakeBookingRepo extends BookingRepository {
  _FakeBookingRepo(this.json, {this.completionResult}) : super(Dio());

  /// Mutable so a pay call can flip the snapshot the next `get()` returns.
  Map<String, dynamic> json;
  final Result<CompletionOtpDto>? completionResult;

  // Recorded calls, so tests can assert what the UI invoked.
  int getCalls = 0;
  final List<String> confirmArrivalCalls = [];
  final List<String> approveCalls = [];
  final List<String> declineCalls = [];
  final List<String> completionCalls = [];
  final List<String> initiatePaymentCalls = [];
  final List<String> initiateCashPaymentCalls = [];

  /// When set, `confirmArrival` returns this instead of Ok — drives the
  /// inline-error case.
  Result<void>? confirmArrivalResult;

  /// Settable pay results. Defaults are the common Ok path.
  Result<PaymentInitDto> initiatePaymentResult =
      const Ok(PaymentInitDto(orderId: 'order_1', amountPaise: 45000, keyId: 'rzp_test'));
  Result<CashInitDto> initiateCashPaymentResult =
      const Ok(CashInitDto(amountPaise: 45000, devOtp: '654321'));

  /// When set, applied to `json` right after a successful cash init so the next
  /// polled `get()` reflects the CREATED/CASH payment.
  Map<String, dynamic>? onCashInitPayment;

  /// When set, `get()` awaits this before returning — lets a test hold a
  /// refetch open and inspect the UI mid-flight (double-order guard).
  Future<void>? gateNextGet;

  @override
  Future<Result<BookingDto>> get(String id) async {
    getCalls++;
    final gate = gateNextGet;
    if (gate != null) {
      gateNextGet = null;
      await gate;
    }
    return Ok(BookingDto.fromJson(json));
  }

  @override
  Future<Result<void>> confirmArrival(String id, String code) async {
    confirmArrivalCalls.add('$id:$code');
    return confirmArrivalResult ?? const Ok(null);
  }

  @override
  Future<Result<void>> approve(String id) async {
    approveCalls.add(id);
    return const Ok(null);
  }

  @override
  Future<Result<void>> decline(String id) async {
    declineCalls.add(id);
    return const Ok(null);
  }

  @override
  Future<Result<CompletionOtpDto>> requestCompletionOtp(String id) async {
    completionCalls.add(id);
    return completionResult ?? const Ok(CompletionOtpDto(ok: true));
  }

  @override
  Future<Result<PaymentInitDto>> initiatePayment(String id) async {
    initiatePaymentCalls.add(id);
    return initiatePaymentResult;
  }

  @override
  Future<Result<CashInitDto>> initiateCashPayment(String id) async {
    initiateCashPaymentCalls.add(id);
    final r = initiateCashPaymentResult;
    if (r is Ok<CashInitDto> && onCashInitPayment != null) {
      json = {...json, 'payment': onCashInitPayment};
    }
    return r;
  }
}

/// A checkout double: records whether `open` was invoked and returns a settable
/// outcome. Never touches the native plugin.
class _FakeRazorpayCheckout extends RazorpayCheckout {
  CheckoutOutcome outcome = const CheckoutSuccess(paymentId: 'pay_1', signature: 'sig_1');
  int openCalls = 0;

  @override
  Future<CheckoutOutcome> open({
    required String keyId,
    required String orderId,
    required int amountPaise,
    required String name,
    required String description,
    String? prefillContact,
  }) async {
    openCalls++;
    return outcome;
  }
}

class _FakeAddressRepo extends AddressRepository {
  _FakeAddressRepo(this.addresses) : super(Dio());
  final List<AddressDto> addresses;

  @override
  Future<Result<List<AddressDto>>> list() async => Ok(addresses);
}

AddressDto _addr(String id, String label, String line1, String pincode) => AddressDto(
  id: id,
  label: label,
  line1: line1,
  pincode: pincode,
  isDefault: true,
  status: 'ACTIVE',
  serviceable: true,
);

Widget _harness(
  _FakeBookingRepo repo, {
  _FakeAddressRepo? addressRepo,
  _FakeRazorpayCheckout? checkout,
}) {
  return ProviderScope(
    overrides: [
      bookingRepositoryProvider.overrideWithValue(repo),
      if (addressRepo != null) addressRepositoryProvider.overrideWithValue(addressRepo),
      if (checkout != null) razorpayCheckoutProvider.overrideWithValue(checkout),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/booking/b1',
        routes: [
          GoRoute(
            path: '/booking/:id',
            builder: (_, s) => BookingTrackingScreen(bookingId: s.pathParameters['id']!),
          ),
          GoRoute(path: '/home', builder: (_, _) => const Scaffold(body: Text('home'))),
        ],
      ),
    ),
  );
}

/// Pumps enough frames to flush the initial-load future + any pending
/// microtasks WITHOUT `pumpAndSettle` — the polling controller arms a periodic
/// 5s timer for non-terminal states, so `pumpAndSettle` would never settle.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(); // build
  await tester.pump(const Duration(milliseconds: 50)); // async get() resolves
  await tester.pump(const Duration(milliseconds: 50)); // dependent futures (label)
}

/// Scrolls [key] into view (buttons live in a ListView), lets the scroll
/// settle, then taps it. A bare `ensureVisible` + `tap` can miss because the
/// tap coordinate is computed before the scroll frame is applied.
Future<void> _tapKey(WidgetTester tester, Key key) async {
  final f = find.byKey(key);
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _settle(tester);
}

void main() {
  testWidgets('EN_ROUTE — arrival gate confirms with the entered code', (tester) async {
    final repo = _FakeBookingRepo(_booking('EN_ROUTE', withTech: true));
    await tester.pumpWidget(_harness(repo));
    await _settle(tester);

    // A 6-digit field renders.
    final field = find.byKey(const Key('arrivalCodeField'));
    expect(field, findsOneWidget);

    await tester.enterText(field, '123456');
    await _tapKey(tester, const Key('confirmArrivalBtn'));

    expect(repo.confirmArrivalCalls, ['b1:123456']);
  });

  testWidgets('EN_ROUTE — a confirmArrival Failure shows its message inline', (tester) async {
    final repo = _FakeBookingRepo(_booking('EN_ROUTE'))
      ..confirmArrivalResult = const Failure(FailureKind.validation, 'That code is not valid.');
    await tester.pumpWidget(_harness(repo));
    await _settle(tester);

    await tester.enterText(find.byKey(const Key('arrivalCodeField')), '123456');
    await _tapKey(tester, const Key('confirmArrivalBtn'));

    expect(find.text('That code is not valid.'), findsOneWidget);
  });

  testWidgets('DIAGNOSED — diagnosis renders; Approve calls approve; Decline dialog shows the visit fee', (tester) async {
    final repo = _FakeBookingRepo(_booking('DIAGNOSED', withTech: true, withDiagnosis: true));
    await tester.pumpWidget(_harness(repo));
    await _settle(tester);

    expect(find.text('Compressor relay failure'), findsOneWidget);
    expect(find.textContaining('Relay'), findsWidgets);
    expect(find.text('₹1050'), findsWidgets); // totalPayablePaise = 105000

    // Decline opens a confirm dialog whose text mentions the visit fee.
    await _tapKey(tester, const Key('declineRepairBtn'));
    expect(find.textContaining('149'), findsWidgets);

    // Confirm the decline (dialog button — no scrolling needed).
    await tester.tap(find.byKey(const Key('declineConfirmBtn')));
    await tester.pump(); // pop the dialog
    await tester.pump(const Duration(milliseconds: 400)); // dismiss animation + decline()
    await _settle(tester);
    expect(repo.declineCalls, ['b1']);

    // Approve one-tap.
    await _tapKey(tester, const Key('approveRepairBtn'));
    expect(repo.approveCalls, ['b1']);
  });

  testWidgets('REPAIR_COMPLETE — Confirm mints the OTP; dev echo chip shows the code', (tester) async {
    final repo = _FakeBookingRepo(
      _booking('REPAIR_COMPLETE', withTech: true),
      completionResult: const Ok(CompletionOtpDto(ok: true, devOtp: '654321')),
    );
    await tester.pumpWidget(_harness(repo));
    await _settle(tester);

    await _tapKey(tester, const Key('confirmCompletionBtn'));

    expect(repo.completionCalls, ['b1']);
    expect(find.textContaining('read it to your technician'), findsOneWidget);
    final chip = find.byKey(const Key('devCompletionOtp'));
    await tester.ensureVisible(chip);
    expect(chip, findsOneWidget);
    expect(find.descendant(of: chip, matching: find.text('654321')), findsOneWidget);
  });

  testWidgets('cancel button present while cancellable (DISPATCHED)', (tester) async {
    await tester.pumpWidget(_harness(_FakeBookingRepo(_booking('DISPATCHED'))));
    await _settle(tester);
    expect(find.byKey(const Key('cancelBookingBtn')), findsOneWidget);
  });

  testWidgets('cancel button absent once no longer cancellable (ARRIVED)', (tester) async {
    await tester.pumpWidget(_harness(_FakeBookingRepo(_booking('ARRIVED', withTech: true))));
    await _settle(tester);
    expect(find.byKey(const Key('cancelBookingBtn')), findsNothing);
  });

  testWidgets('address label — the joined label renders, not the raw id', (tester) async {
    final repo = _FakeBookingRepo(_booking('DISPATCHED'));
    final addressRepo = _FakeAddressRepo([_addr('a1', 'Home', '12 Baroda St', '390001')]);
    await tester.pumpWidget(_harness(repo, addressRepo: addressRepo));
    await _settle(tester);

    expect(find.textContaining('Home · 12 Baroda St, 390001'), findsOneWidget);
    expect(find.text('a1'), findsNothing);
  });

  // ── Pay card (Slice 5) ─────────────────────────────────────────────────────

  testWidgets('1. CUSTOMER_CONFIRMED, payment:null — UPI + cash buttons render with the amount', (tester) async {
    final repo = _FakeBookingRepo(_booking('CUSTOMER_CONFIRMED', withTech: true));
    await tester.pumpWidget(_harness(repo, checkout: _FakeRazorpayCheckout()));
    await _settle(tester);

    expect(find.byKey(const Key('payUpiBtn')), findsOneWidget);
    expect(find.byKey(const Key('payCashBtn')), findsOneWidget);
    // totalPayablePaise = 45000 (no diagnosis parts).
    expect(find.textContaining('₹450'), findsWidgets);
  });

  testWidgets('2. Tap payUpiBtn — Ok(keyId) opens checkout; CheckoutSuccess triggers a refetch', (tester) async {
    final repo = _FakeBookingRepo(_booking('CUSTOMER_CONFIRMED', withTech: true));
    final checkout = _FakeRazorpayCheckout()
      ..outcome = const CheckoutSuccess(paymentId: 'pay_1', signature: 'sig_1');
    await tester.pumpWidget(_harness(repo, checkout: checkout));
    await _settle(tester);
    final getsBefore = repo.getCalls;

    await _tapKey(tester, const Key('payUpiBtn'));

    expect(repo.initiatePaymentCalls, ['b1']);
    expect(checkout.openCalls, 1);
    // onRefetch() fires -> another get() beyond the initial load.
    expect(repo.getCalls, greaterThan(getsBefore));
  });

  testWidgets('3. Tap payUpiBtn — Ok(keyId:null) never opens checkout; shows UPI-unavailable snack', (tester) async {
    final repo = _FakeBookingRepo(_booking('CUSTOMER_CONFIRMED', withTech: true))
      ..initiatePaymentResult = const Ok(PaymentInitDto(orderId: 'order_1', amountPaise: 45000));
    final checkout = _FakeRazorpayCheckout();
    await tester.pumpWidget(_harness(repo, checkout: checkout));
    await _settle(tester);

    await _tapKey(tester, const Key('payUpiBtn'));

    expect(repo.initiatePaymentCalls, ['b1']);
    expect(checkout.openCalls, 0);
    expect(find.textContaining("UPI isn't available right now"), findsOneWidget);
    // Cash remains an option.
    expect(find.byKey(const Key('payCashBtn')), findsOneWidget);
  });

  testWidgets('4. Tap payCashBtn — Ok(devOtp) flips to CREATED/CASH; dev chip shows the code; no submit field', (tester) async {
    final repo = _FakeBookingRepo(_booking('CUSTOMER_CONFIRMED', withTech: true))
      ..initiateCashPaymentResult = const Ok(CashInitDto(amountPaise: 45000, devOtp: '654321'))
      ..onCashInitPayment = _pay('CREATED', 'CASH', 45000);
    await tester.pumpWidget(_harness(repo, checkout: _FakeRazorpayCheckout()));
    await _settle(tester);

    await _tapKey(tester, const Key('payCashBtn'));

    expect(repo.initiateCashPaymentCalls, ['b1']);
    final chip = find.byKey(const Key('devCashOtp'));
    await tester.ensureVisible(chip);
    expect(chip, findsOneWidget);
    expect(find.descendant(of: chip, matching: find.text('654321')), findsOneWidget);
    // The customer NEVER submits the cash OTP — display only.
    expect(find.byType(TextField), findsNothing);
    expect(find.byKey(const Key('payUpiBtn')), findsNothing);
    expect(find.byKey(const Key('payCashBtn')), findsNothing);
  });

  testWidgets('5. payment CREATED/UPI — upiPending copy; no pay buttons', (tester) async {
    final repo = _FakeBookingRepo(
      _booking('CUSTOMER_CONFIRMED', withTech: true, payment: _pay('CREATED', 'UPI', 45000)),
    );
    await tester.pumpWidget(_harness(repo, checkout: _FakeRazorpayCheckout()));
    await _settle(tester);

    expect(find.textContaining('Confirming your payment'), findsOneWidget);
    expect(find.byKey(const Key('payUpiBtn')), findsNothing);
    expect(find.byKey(const Key('payCashBtn')), findsNothing);
  });

  testWidgets('6. payment CAPTURED — paid receipt; no pay buttons', (tester) async {
    final repo = _FakeBookingRepo(
      _booking('PAYMENT_RECEIVED', withTech: true, payment: _pay('CAPTURED', 'UPI', 45000)),
    );
    await tester.pumpWidget(_harness(repo, checkout: _FakeRazorpayCheckout()));
    await _settle(tester);

    // "Paid" also appears as a timeline milestone, so assert the receipt line.
    expect(find.textContaining('✓ UPI · ₹450'), findsOneWidget);
    expect(find.byKey(const Key('payUpiBtn')), findsNothing);
    expect(find.byKey(const Key('payCashBtn')), findsNothing);
  });

  testWidgets('7. DECLINED_BY_CUSTOMER, payment:null — pay card shows the visit fee + both buttons', (tester) async {
    final repo = _FakeBookingRepo(_booking('DECLINED_BY_CUSTOMER', withTech: true));
    await tester.pumpWidget(_harness(repo, checkout: _FakeRazorpayCheckout()));
    await _settle(tester);

    // visitFeePaise = 14900.
    expect(find.textContaining('₹149'), findsWidgets);
    expect(find.byKey(const Key('payUpiBtn')), findsOneWidget);
    expect(find.byKey(const Key('payCashBtn')), findsOneWidget);
  });

  testWidgets('8. initiateCashPayment Failure(429) surfaces its message as a snack', (tester) async {
    final repo = _FakeBookingRepo(_booking('CUSTOMER_CONFIRMED', withTech: true))
      ..initiateCashPaymentResult =
          const Failure(FailureKind.rateLimited, 'Too many code requests. Try again later.');
    await tester.pumpWidget(_harness(repo, checkout: _FakeRazorpayCheckout()));
    await _settle(tester);

    await _tapKey(tester, const Key('payCashBtn'));

    expect(repo.initiateCashPaymentCalls, ['b1']);
    expect(find.text('Too many code requests. Try again later.'), findsOneWidget);
  });

  testWidgets('9. CheckoutSuccess — pay buttons stay disabled across the refetch (no double-order)',
      (tester) async {
    final repo = _FakeBookingRepo(_booking('CUSTOMER_CONFIRMED', withTech: true));
    final checkout = _FakeRazorpayCheckout()
      ..outcome = const CheckoutSuccess(paymentId: 'pay_1', signature: 'sig_1');
    await tester.pumpWidget(_harness(repo, checkout: checkout));
    await _settle(tester);

    // Hold the post-success refetch open so we can inspect the button mid-flight.
    final gate = Completer<void>();
    repo.gateNextGet = gate.future;

    // Scroll the button into view, then tap WITHOUT settling (settling would
    // flush past the gated refetch).
    final upi = find.byKey(const Key('payUpiBtn'));
    await tester.ensureVisible(upi);
    await tester.pump();
    await tester.tap(upi);
    // Flush: initiatePayment -> open() -> onRefetch() get() (now blocked on gate).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(repo.initiatePaymentCalls, ['b1']);
    expect(checkout.openCalls, 1);
    // While the refetch is in flight, the UPI button must be disabled — a second
    // tap must NOT start a second Razorpay order for an already-paid booking.
    final btn = tester.widget<FilledButton>(upi);
    expect(btn.onPressed, isNull, reason: 'busy must stay true across the post-success refetch');

    // Release the refetch; the (still CUSTOMER_CONFIRMED) snapshot re-enables it.
    gate.complete();
    await _settle(tester);
    expect(checkout.openCalls, 1);
  });

  testWidgets('10. PAYMENT_RECEIVED without a CAPTURED payment — renders a non-blank status card',
      (tester) async {
    // Summary lags: booking has advanced to PAYMENT_RECEIVED but the payment
    // summary is null (or a non-captured attempt). Must not be a blank card.
    final repo = _FakeBookingRepo(_booking('PAYMENT_RECEIVED', withTech: true));
    await tester.pumpWidget(_harness(repo, checkout: _FakeRazorpayCheckout()));
    await _settle(tester);

    expect(find.textContaining('Payment received'), findsOneWidget);
    // No stale pay buttons in this non-payable state.
    expect(find.byKey(const Key('payUpiBtn')), findsNothing);
    expect(find.byKey(const Key('payCashBtn')), findsNothing);
  });

  testWidgets('11. unpaid CUSTOMER_CONFIRMED — timeline does NOT light the "Paid" milestone',
      (tester) async {
    final repo = _FakeBookingRepo(_booking('CUSTOMER_CONFIRMED', withTech: true));
    await tester.pumpWidget(_harness(repo, checkout: _FakeRazorpayCheckout()));
    await _settle(tester);

    // The pay card is asking for payment, so "Paid" must not read as reached.
    // (The paid receipt card is absent here, so this is the sole "Paid" text.)
    final paid = tester.widget<Text>(find.text('Paid'));
    expect(paid.style?.fontWeight, isNot(FontWeight.w700),
        reason: '"Paid" must not be the active milestone for an unpaid payable booking');
  });

  testWidgets('12. CAPTURED payment — timeline DOES light the "Paid" milestone', (tester) async {
    final repo = _FakeBookingRepo(
      _booking('PAYMENT_RECEIVED', withTech: true, payment: _pay('CAPTURED', 'UPI', 45000)),
    );
    await tester.pumpWidget(_harness(repo, checkout: _FakeRazorpayCheckout()));
    await _settle(tester);

    // "Paid" is both the receipt card title and the timeline milestone; the
    // active timeline milestone is the bold (w700) one.
    final bold = tester
        .widgetList<Text>(find.text('Paid'))
        .where((t) => t.style?.fontWeight == FontWeight.w700);
    expect(bold, isNotEmpty, reason: '"Paid" milestone must be active once payment is CAPTURED');
  });
}
