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

  test('error code PAYMENT_CANCELLED (user backed out) maps to CheckoutDismissed', () {
    // The plugin has no separate dismiss event; a user cancel arrives as an
    // error with code == Razorpay.PAYMENT_CANCELLED (== 2). That is benign —
    // map it to CheckoutDismissed so the caller stays quiet (no error snack).
    final r = PaymentFailureResponse(Razorpay.PAYMENT_CANCELLED, 'Payment cancelled', null);
    final out = outcomeForError(r);
    expect(out, isA<CheckoutDismissed>());
  });

  test('a non-cancel error maps to CheckoutFailed with its message', () {
    final r = PaymentFailureResponse(1, 'Network error', null);
    final out = outcomeForError(r);
    expect(out, isA<CheckoutFailed>());
    expect((out as CheckoutFailed).message, 'Network error');
  });

  test('error response with null message falls back to a default message', () {
    final r = PaymentFailureResponse(1, null, null);
    final out = outcomeForError(r);
    expect((out as CheckoutFailed).message, isNotEmpty);
  });

  group('event routing (razorpay_flutter 1.4.6)', () {
    test('external-wallet event is NOT terminal — it never completes the checkout', () {
      // EVENT_EXTERNAL_WALLET is informational (carries the wallet name) and
      // fires BEFORE the real success/error. Treating it as terminal would drop
      // the actual payment result. handleCheckoutEvent must ignore it.
      CheckoutOutcome? completed;
      handleCheckoutEvent(
        Razorpay.EVENT_EXTERNAL_WALLET,
        ExternalWalletResponse('gpay'),
        (o) => completed = o,
      );
      expect(completed, isNull);
    });

    test('success event completes with CheckoutSuccess', () {
      CheckoutOutcome? completed;
      handleCheckoutEvent(
        Razorpay.EVENT_PAYMENT_SUCCESS,
        PaymentSuccessResponse('pay_9', 'order_9', 'sig_9', null),
        (o) => completed = o,
      );
      expect(completed, isA<CheckoutSuccess>());
    });

    test('error event with cancel code completes with CheckoutDismissed', () {
      CheckoutOutcome? completed;
      handleCheckoutEvent(
        Razorpay.EVENT_PAYMENT_ERROR,
        PaymentFailureResponse(Razorpay.PAYMENT_CANCELLED, 'Payment cancelled', null),
        (o) => completed = o,
      );
      expect(completed, isA<CheckoutDismissed>());
    });

    test('error event with a real failure code completes with CheckoutFailed', () {
      CheckoutOutcome? completed;
      handleCheckoutEvent(
        Razorpay.EVENT_PAYMENT_ERROR,
        PaymentFailureResponse(1, 'Bank declined', null),
        (o) => completed = o,
      );
      expect(completed, isA<CheckoutFailed>());
    });
  });
}
