import 'package:flutter/foundation.dart';

/// Lets globally-mounted UI (see `AppUpdateGate`) know that a payment or the
/// booking it pays for is not finished yet, without depending on the payment
/// screen's internals. The counterpart of `ActiveCallTracker`.
class PaymentInProgressTracker {
  PaymentInProgressTracker._();

  static final PaymentInProgressTracker instance = PaymentInProgressTracker._();

  // A counter for the same reason as ActiveCallTracker's.
  final ValueNotifier<int> activeCount = ValueNotifier<int>(0);

  bool get isActive => activeCount.value > 0;

  void markActive() => activeCount.value++;

  void markInactive() {
    if (activeCount.value > 0) activeCount.value--;
  }
}
