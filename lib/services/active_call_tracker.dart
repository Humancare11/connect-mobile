import 'package:flutter/foundation.dart';

/// Lets globally-mounted UI (see `ConnectivityGate`) know whether the video
/// call screen is currently on screen, without depending on
/// `VideoCallController` internals or touching its call/signaling logic.
///
/// `VideoCallScreen` already shows its own connectivity-loss UI (see
/// `VideoCallController.isOffline`) — the global "No Internet" screen backs
/// off while a call is active so the two don't cover each other.
class ActiveCallTracker {
  ActiveCallTracker._();

  static final ActiveCallTracker instance = ActiveCallTracker._();

  // A counter (not a bool) so an unexpected double markActive()/markInactive()
  // pairing (e.g. hot reload) can't leave this stuck reporting "active".
  final ValueNotifier<int> activeCount = ValueNotifier<int>(0);

  bool get isActive => activeCount.value > 0;

  void markActive() => activeCount.value++;

  void markInactive() {
    if (activeCount.value > 0) activeCount.value--;
  }
}
