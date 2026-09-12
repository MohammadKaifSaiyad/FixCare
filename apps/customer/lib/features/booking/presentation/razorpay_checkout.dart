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

CheckoutOutcome outcomeForError(PaymentFailureResponse r) =>
    CheckoutFailed(code: r.code, message: r.message ?? 'Payment failed');

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
        (PaymentSuccessResponse r) => done(outcomeForSuccess(r)));
    rzp.on(Razorpay.EVENT_PAYMENT_ERROR,
        (PaymentFailureResponse r) => done(outcomeForError(r)));
    rzp.on(Razorpay.EVENT_EXTERNAL_WALLET,
        (ExternalWalletResponse r) => done(const CheckoutDismissed()));

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
