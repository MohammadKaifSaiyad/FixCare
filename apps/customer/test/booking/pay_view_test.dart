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
