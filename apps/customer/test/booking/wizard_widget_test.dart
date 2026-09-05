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
