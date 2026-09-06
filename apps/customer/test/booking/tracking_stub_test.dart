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
  _FakeBookingRepo({this.cancelResult}) : super(Dio());
  final Result<void>? cancelResult;

  @override
  Future<Result<BookingDto>> get(String id) async => Ok(BookingDto.fromJson(_booking()));

  @override
  Future<Result<void>> cancel(String id) async =>
      cancelResult ?? const Failure(FailureKind.unknown, 'should not be called without override');
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
    expect(find.text('₹149'), findsOneWidget);
  });

  testWidgets('cancel failure surfaces a SnackBar, never swallowed', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        bookingRepositoryProvider.overrideWithValue(
          _FakeBookingRepo(cancelResult: const Failure(FailureKind.server, 'Cannot cancel now.')),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(initialLocation: '/booking/b1', routes: [
          GoRoute(path: '/booking/:id', builder: (_, s) => BookingTrackingScreen(bookingId: s.pathParameters['id']!)),
          GoRoute(path: '/home', builder: (_, _) => const Scaffold(body: Text('home'))),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cancelBookingBtn')));
    await tester.pumpAndSettle();

    expect(find.text('Cannot cancel now.'), findsOneWidget);
    // Still on the tracking screen, not navigated to /home.
    expect(find.text('FC-1001'), findsOneWidget);
  });
}
