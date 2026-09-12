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
