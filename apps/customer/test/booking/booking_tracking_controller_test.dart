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
      c.listen(bookingTrackingProvider('b1'), (_, next) {}, fireImmediately: true);
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
      c.listen(bookingTrackingProvider('b1'), (_, next) {}, fireImmediately: true);
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
      c.listen(bookingTrackingProvider('b1'), (_, next) {}, fireImmediately: true);
      async.flushMicrotasks();
      expect(c.read(bookingTrackingProvider('b1')).hasError, isTrue);
    });
  });
}
