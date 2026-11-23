import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

/// Razorpay Checkout for customers priced in rupees (India). A port of the web
/// app's `razorpayCheckout.js` / `paymentFields.js`:
///
///  * the SERVER creates the order (`POST /razorpay/create-order`), so the
///    amount and the currency are its decision; the app only opens Checkout for
///    that order and hands the result back;
///  * the three values Checkout returns (order id, payment id, signature) go to
///    the booking request, where the server verifies them before anything is
///    booked.

/// Texts the web shows (`AppointmentBookingForm.jsx`).
const String kRazorpayCancelledMessage =
    'Payment was cancelled. You have not been charged. You can try again.';
const String kRazorpayFailedMessage = 'Payment failed. Please try again.';
const String kRazorpayStartFailedMessage =
    'Failed to start the payment. Please try again.';

/// What Checkout returns after a successful payment.
class RazorpayPayment {
  const RazorpayPayment({
    required this.orderId,
    required this.paymentId,
    required this.signature,
  });

  factory RazorpayPayment.fromJson(Map<String, dynamic> json) {
    return RazorpayPayment(
      orderId: (json['orderId'] ?? '').toString(),
      paymentId: (json['paymentId'] ?? '').toString(),
      signature: (json['signature'] ?? '').toString(),
    );
  }

  final String orderId;
  final String paymentId;
  final String signature;

  /// The payment reference fields of the booking request (web
  /// `paymentFields("razorpay", ref)`).
  Map<String, String> toBookingFields() => {
    'razorpayOrderId': orderId,
    'razorpayPaymentId': paymentId,
    'razorpaySignature': signature,
  };

  Map<String, dynamic> toJson() => {
    'orderId': orderId,
    'paymentId': paymentId,
    'signature': signature,
  };

  bool get isComplete =>
      orderId.isNotEmpty && paymentId.isNotEmpty && signature.isNotEmpty;
}

/// How a Checkout session ended.
sealed class RazorpayOutcome {
  const RazorpayOutcome();
}

class RazorpaySuccess extends RazorpayOutcome {
  const RazorpaySuccess(this.payment);
  final RazorpayPayment payment;
}

/// The customer closed Checkout without paying.
class RazorpayCancelled extends RazorpayOutcome {
  const RazorpayCancelled();
}

class RazorpayFailed extends RazorpayOutcome {
  const RazorpayFailed(this.message);
  final String message;
}

/// Opens Razorpay Checkout. A seam so tests can replace the native SDK.
abstract class RazorpayLauncher {
  Future<RazorpayOutcome> open(Map<String, dynamic> options);
}

class RazorpayCheckout {
  const RazorpayCheckout._();

  /// The launcher the payment screen uses. Replaceable in tests.
  static RazorpayLauncher launcher = SdkRazorpayLauncher();

  /// The options Checkout opens with (web `buildRazorpayOptions`). `amount`
  /// is in paise and `keyId` is the public key the server returned with the
  /// order.
  static Map<String, dynamic> buildOptions({
    required String keyId,
    required String orderId,
    required int amountPaise,
    required String description,
    String name = '',
    String email = '',
    String contact = '',
  }) {
    return {
      'key': keyId,
      'order_id': orderId,
      'amount': amountPaise,
      'currency': 'INR',
      'name': 'Humancare Connect',
      'description': description,
      'prefill': {
        'name': name.trim(),
        'email': email.trim(),
        'contact': contact.trim(),
      },
      'theme': {'color': '#0a1f44'},
      'retry': {'enabled': true, 'max_count': 4},
    };
  }
}

/// What to tell the customer when Checkout reports a failed payment: the
/// description Razorpay sent (web `failure.error.description`), else the
/// generic text.
String razorpayFailureText({String? message, Map<dynamic, dynamic>? error}) {
  final nested = error?['error'];
  final description = nested is Map ? nested['description'] : null;
  final text = (description ?? '').toString().trim();
  if (text.isNotEmpty) return text;
  final plain = (message ?? '').trim();
  // A raw JSON blob is not something to show a customer.
  if (plain.isNotEmpty && !plain.startsWith('{') && !plain.startsWith('[')) {
    return plain;
  }
  return kRazorpayFailedMessage;
}

/// The real thing: the Razorpay SDK (Android and iOS).
class SdkRazorpayLauncher implements RazorpayLauncher {
  @override
  Future<RazorpayOutcome> open(Map<String, dynamic> options) async {
    final razorpay = Razorpay();
    final done = Completer<RazorpayOutcome>();
    void finish(RazorpayOutcome outcome) {
      if (!done.isCompleted) done.complete(outcome);
    }

    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
      final payment = RazorpayPayment(
        orderId: r.orderId ?? '',
        paymentId: r.paymentId ?? '',
        signature: r.signature ?? '',
      );
      finish(
        payment.isComplete
            ? RazorpaySuccess(payment)
            : const RazorpayFailed(kRazorpayFailedMessage),
      );
    });
    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
      if (r.code == Razorpay.PAYMENT_CANCELLED) {
        finish(const RazorpayCancelled());
      } else {
        finish(
          RazorpayFailed(
            razorpayFailureText(message: r.message, error: r.error),
          ),
        );
      }
    });
    // An external wallet app takes over; Checkout still reports the result.
    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse r) {});

    try {
      razorpay.open(options);
      return await done.future;
    } catch (_) {
      return const RazorpayFailed(kRazorpayStartFailedMessage);
    } finally {
      razorpay.clear();
    }
  }
}

/// A rupee payment that went through but whose booking has not been saved yet:
/// everything needed to finish the booking without charging again.
class PendingRazorpayBooking {
  const PendingRazorpayBooking({
    required this.payment,
    required this.args,
    required this.amount,
  });

  factory PendingRazorpayBooking.fromJson(Map<String, dynamic> json) {
    final args = json['args'];
    return PendingRazorpayBooking(
      payment: RazorpayPayment.fromJson(
        Map<String, dynamic>.from(json['payment'] as Map),
      ),
      args: args is Map
          ? args.map((key, value) => MapEntry(key.toString(), value))
          : <String, dynamic>{},
      amount: json['amount'] is num ? json['amount'] as num : 0,
    );
  }

  final RazorpayPayment payment;

  /// The booking selection and form (category, date, time, problem, reports).
  final Map<String, dynamic> args;

  /// The USD price of the selection (what the booking records as its
  /// `consultationPrice`).
  final num amount;

  Map<String, dynamic> toJson() => {
    'payment': payment.toJson(),
    'args': args,
    'amount': amount,
  };
}

/// Keeps a paid-but-unsaved rupee booking across an app restart, so the
/// customer can finish it without paying again. Stored in secure storage (the
/// booking text can hold health details) under a key of the signed-in
/// customer, and removed as soon as the booking is saved.
class PendingRazorpayBookingStore {
  PendingRazorpayBookingStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  /// The store the payment screen uses. Replaceable in tests.
  static PendingRazorpayBookingStore instance = PendingRazorpayBookingStore();

  final FlutterSecureStorage _storage;

  static String _key(String userId) => 'pending_razorpay_booking_$userId';

  Future<void> save(String userId, PendingRazorpayBooking booking) async {
    if (userId.trim().isEmpty) return;
    try {
      await _storage.write(
        key: _key(userId),
        value: jsonEncode(booking.toJson()),
      );
    } catch (error) {
      // The booking can still be finished in this session.
      debugPrint('[Razorpay] could not save the pending booking: $error');
    }
  }

  /// The saved booking of this customer, or null. A damaged entry is dropped.
  Future<PendingRazorpayBooking?> load(String userId) async {
    if (userId.trim().isEmpty) return null;
    try {
      final raw = await _storage.read(key: _key(userId));
      if (raw == null || raw.isEmpty) return null;
      final booking = PendingRazorpayBooking.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
      if (!booking.payment.isComplete) {
        await clear(userId);
        return null;
      }
      return booking;
    } catch (_) {
      await clear(userId);
      return null;
    }
  }

  Future<void> clear(String userId) async {
    if (userId.trim().isEmpty) return;
    try {
      await _storage.delete(key: _key(userId));
    } catch (_) {}
  }
}
