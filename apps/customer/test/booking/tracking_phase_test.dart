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
