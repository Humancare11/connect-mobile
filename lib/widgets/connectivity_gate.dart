import 'package:flutter/material.dart';

import '../services/active_call_tracker.dart';
import '../services/connectivity_service.dart';
import 'no_internet_screen.dart';

/// Wraps the whole app so the global "No Internet Connection" screen can be
/// shown above every screen, driven by [ConnectivityService]. Mount once at
/// the app root (see `main.dart`'s `MaterialApp.builder`) — screens never
/// need to know this exists.
///
/// Suppressed while a video call is active ([ActiveCallTracker]) since
/// `VideoCallScreen` already has its own connectivity-loss UI; the two
/// would otherwise cover each other.
class ConnectivityGate extends StatelessWidget {
  const ConnectivityGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: ListenableBuilder(
            listenable: ConnectivityService.instance,
            builder: (context, _) {
              return ValueListenableBuilder<int>(
                valueListenable: ActiveCallTracker.instance.activeCount,
                builder: (context, activeCallCount, _) {
                  final showOffline =
                      !ConnectivityService.instance.isOnline &&
                      activeCallCount == 0;

                  return IgnorePointer(
                    ignoring: !showOffline,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: showOffline
                          ? const NoInternetScreen(key: ValueKey('no-internet'))
                          : const SizedBox.shrink(key: ValueKey('online')),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
