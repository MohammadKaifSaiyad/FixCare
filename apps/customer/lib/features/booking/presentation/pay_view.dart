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
