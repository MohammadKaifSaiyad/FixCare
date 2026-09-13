import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

sealed class CheckoutOutcome {
  const CheckoutOutcome();
}

class CheckoutSuccess extends CheckoutOutcome {
  const CheckoutSuccess({this.paymentId, this.signature});
  final String? paymentId;
  final String? signature;
}

class CheckoutFailed extends CheckoutOutcome {
  const CheckoutFailed({this.code, required this.message});
  final int? code;
  final String message;
}

class CheckoutDismissed extends CheckoutOutcome {
  const CheckoutDismissed();
}

/// Pure mapping seams (unit-testable without opening a sheet).
CheckoutOutcome outcomeForSuccess(PaymentSuccessResponse r) =>
    CheckoutSuccess(paymentId: r.paymentId, signature: r.signature);

/// The plugin has no separate "dismissed" event: a user backing out of the
/// sheet arrives as an error with `code == Razorpay.PAYMENT_CANCELLED` (== 2).
/// That is benign — map it to [CheckoutDismissed] (the caller stays quiet).
/// Any other error code is a real failure the caller surfaces.
CheckoutOutcome outcomeForError(PaymentFailureResponse r) =>
    r.code == Razorpay.PAYMENT_CANCELLED
        ? const CheckoutDismissed()
        : CheckoutFailed(code: r.code, message: r.message ?? 'Payment failed');

/// Routes ONE plugin event to a terminal outcome, or ignores it. Only success
/// and error are terminal. `EVENT_EXTERNAL_WALLET` (`payment.external_wallet`)
/// is informational (carries the wallet name) and fires BEFORE the real
/// success/error in razorpay_flutter 1.4.6 — completing on it would drop the
/// actual payment result, so it is deliberately ignored here. Pure + testable.
void handleCheckoutEvent(String event, Object response, void Function(CheckoutOutcome) done) {
  switch (event) {
    case Razorpay.EVENT_PAYMENT_SUCCESS:
      done(outcomeForSuccess(response as PaymentSuccessResponse));
    case Razorpay.EVENT_PAYMENT_ERROR:
      done(outcomeForError(response as PaymentFailureResponse));
    case Razorpay.EVENT_EXTERNAL_WALLET:
      // Informational, not terminal — keep waiting for success/error.
      break;
  }
}

/// Wraps the callback-based razorpay_flutter plugin in a Future. Always clears
/// the plugin's native listeners. Payment SUCCESS here is NOT "paid" — the
/// caller shows a pending state and lets the booking poll confirm via webhook.
class RazorpayCheckout {
  Future<CheckoutOutcome> open({
    required String keyId,
    required String orderId,
    required int amountPaise,
    required String name,
    required String description,
    String? prefillContact,
  }) async {
    final rzp = Razorpay();
    final completer = Completer<CheckoutOutcome>();
    void done(CheckoutOutcome o) {
      if (!completer.isCompleted) completer.complete(o);
    }

    rzp.on(Razorpay.EVENT_PAYMENT_SUCCESS,
        (PaymentSuccessResponse r) => handleCheckoutEvent(Razorpay.EVENT_PAYMENT_SUCCESS, r, done));
    rzp.on(Razorpay.EVENT_PAYMENT_ERROR,
        (PaymentFailureResponse r) => handleCheckoutEvent(Razorpay.EVENT_PAYMENT_ERROR, r, done));
    // Informational, fires before the real outcome — must NOT complete/clear.
    rzp.on(Razorpay.EVENT_EXTERNAL_WALLET,
        (ExternalWalletResponse r) => handleCheckoutEvent(Razorpay.EVENT_EXTERNAL_WALLET, r, done));

    try {
      rzp.open({
        'key': keyId,
        'order_id': orderId,
        'amount': amountPaise,
        'currency': 'INR',
        'name': name,
        'description': description,
        if (prefillContact != null) 'prefill': {'contact': prefillContact},
      });
      return await completer.future;
    } finally {
      rzp.clear();
    }
  }
}

final razorpayCheckoutProvider =
    Provider<RazorpayCheckout>((ref) => RazorpayCheckout());
