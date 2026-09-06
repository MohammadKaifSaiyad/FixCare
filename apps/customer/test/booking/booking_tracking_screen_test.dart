import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fixcare_customer/core/result.dart';
import 'package:fixcare_customer/features/address/data/address_repository.dart';
import 'package:fixcare_customer/features/booking/data/booking_repository.dart';
import 'package:fixcare_customer/features/booking/presentation/booking_tracking_screen.dart';

/// A booking snapshot in [state], with optional diagnosis/parts/technician so a
/// test can drive any gate. Field names mirror the backend BookingDto JSON.
Map<String, dynamic> _booking(
  String state, {
  bool withTech = false,
  bool withDiagnosis = false,
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
  'payment': null,
  'dispute': null,
};

class _FakeBookingRepo extends BookingRepository {
  _FakeBookingRepo(this.json, {this.completionResult}) : super(Dio());

  final Map<String, dynamic> json;
  final Result<CompletionOtpDto>? completionResult;

  // Recorded calls, so tests can assert what the UI invoked.
  final List<String> confirmArrivalCalls = [];
  final List<String> approveCalls = [];
  final List<String> declineCalls = [];
  final List<String> completionCalls = [];

  /// When set, `confirmArrival` returns this instead of Ok — drives the
  /// inline-error case.
  Result<void>? confirmArrivalResult;

  @override
  Future<Result<BookingDto>> get(String id) async => Ok(BookingDto.fromJson(json));

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

Widget _harness(_FakeBookingRepo repo, {_FakeAddressRepo? addressRepo}) {
  return ProviderScope(
    overrides: [
      bookingRepositoryProvider.overrideWithValue(repo),
      if (addressRepo != null) addressRepositoryProvider.overrideWithValue(addressRepo),
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
}
