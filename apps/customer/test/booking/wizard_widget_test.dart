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
Map<String, dynamic> _nonServiceableAddr() => {
  'id': 'a2', 'label': 'Office', 'line1': '9 Out of Zone Rd', 'line2': null, 'landmark': null,
  'pincode': '390099', 'lat': null, 'lng': null, 'isDefault': false, 'status': 'ACTIVE',
  'serviceable': false, 'zone': null,
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
  _FakeAddressRepo([List<Map<String, dynamic>>? addresses])
      : addresses = addresses ?? [_addr()],
        super(Dio());
  final List<Map<String, dynamic>> addresses;
  @override
  Future<Result<List<AddressDto>>> list() async =>
      Ok(addresses.map(AddressDto.fromJson).toList());
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

Future<void> _pump(WidgetTester tester, _FakeBookingRepo booking, {_FakeAddressRepo? address}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      addressRepositoryProvider.overrideWithValue(address ?? _FakeAddressRepo()),
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

  testWidgets('changing the date after picking a window clears the stale slot: Continue disables until re-pick', (tester) async {
    final booking = _FakeBookingRepo();
    await _pump(tester, booking);
    // address step -> continue
    await tester.tap(find.text('Continue')); await tester.pumpAndSettle();
    expect(find.byKey(const Key('wizardSlot')), findsOneWidget);
    // pick a window for date A (the default selected date, tomorrow) -> Continue enabled
    await tester.tap(find.text('Morning · 9–12').first); await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
    // change to date B (a different day chip)
    final dayChips = find.byType(ChoiceChip);
    await tester.tap(dayChips.at(2)); // any day chip other than the currently-selected one
    await tester.pumpAndSettle();
    // no window is highlighted for date B and the stale slot was cleared -> Continue disabled
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
  });

  testWidgets('selecting a non-serviceable address disables Continue and shows the inline note', (tester) async {
    final booking = _FakeBookingRepo();
    final address = _FakeAddressRepo([_addr(), _nonServiceableAddr()]);
    await _pump(tester, booking, address: address);
    // default (serviceable) address preselected -> Continue enabled
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
    expect(find.byKey(const Key('wizardNonServiceableNote')), findsNothing);
    // select the non-serviceable address
    await tester.tap(find.text('Office')); await tester.pumpAndSettle();
    expect(find.byKey(const Key('wizardNonServiceableNote')), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
  });

  group('formatScheduledSlot', () {
    // Build the ISO string from a LOCAL DateTime (toUtc) rather than a fixed
    // "Z" literal so the expected local hour is correct regardless of the
    // test machine's timezone (formatScheduledSlot converts back .toLocal()).
    test('an hour matching a fixed window (9/12/15) shows the window label', () {
      final iso = DateTime(2026, 9, 10, 9, 0).toUtc().toIso8601String();
      expect(formatScheduledSlot(iso), contains('Morning · 9–12'));
    });

    test('an hour NOT matching any fixed window (e.g. 14:00) shows the actual time, not "Morning"', () {
      final iso = DateTime(2026, 9, 10, 14, 0).toUtc().toIso8601String();
      final label = formatScheduledSlot(iso);
      expect(label, isNot(contains('Morning')));
      expect(label, contains('2:00 pm'));
    });
  });
}
