import 'package:flutter/material.dart';

import '../screens/login_screen.dart';
import '../services/active_call_tracker.dart';
import '../services/notification_service.dart';
import '../services/session_expired_service.dart';
import 'session_expired_screen.dart';

/// Wraps the whole app so the global "Session Expired" screen can be shown
/// above every screen, driven by [SessionExpiredService]. Mount once at the
/// app root (see `main.dart`'s `MaterialApp.builder`), alongside
/// `ConnectivityGate` — screens never need to know this exists.
///
/// Also drives the actual automatic redirect back to [LoginScreen] — the
/// user should never have to tap anything for this to happen, matching the
/// web app's `SessionTimeoutManager`, which navigates on its own the moment
/// a session is declared dead. [SessionExpiredScreen]'s own "Log In Again"
/// button remains as a fallback for the rare case the automatic redirect
/// can't run yet (see [_tryAutoRedirect]).
///
/// Suppressed while a video call is active ([ActiveCallTracker]), same
/// precedent as `ConnectivityGate`: force-closing an in-progress
/// consultation the instant a background API call's token expires would be
/// far more harmful than letting the call finish and redirecting
/// immediately after. The call's own reconnect/heartbeat logic
/// (`VideoCallController`) already re-authenticates independently.
class SessionExpiredGate extends StatefulWidget {
  const SessionExpiredGate({super.key, required this.child});

  final Widget child;

  @override
  State<SessionExpiredGate> createState() => _SessionExpiredGateState();
}

class _SessionExpiredGateState extends State<SessionExpiredGate> {
  // Guards against scheduling more than one redirect for the same expiry —
  // SessionExpiredService and ActiveCallTracker can each fire this within
  // the same frame.
  bool _redirectScheduled = false;

  @override
  void initState() {
    super.initState();
    SessionExpiredService.instance.addListener(_maybeAutoRedirect);
    ActiveCallTracker.instance.activeCount.addListener(_maybeAutoRedirect);
  }

  @override
  void dispose() {
    SessionExpiredService.instance.removeListener(_maybeAutoRedirect);
    ActiveCallTracker.instance.activeCount.removeListener(_maybeAutoRedirect);
    super.dispose();
  }

  /// Attempts the automatic redirect. Re-armed by clearing
  /// [_redirectScheduled] once the session is no longer expired, so the
  /// next expiry (a fresh login followed by a fresh timeout) redirects
  /// again. Deferred while a call is active — retried automatically via the
  /// [ActiveCallTracker] listener the moment the call ends.
  void _maybeAutoRedirect() {
    if (!SessionExpiredService.instance.isExpired) {
      _redirectScheduled = false;
      return;
    }
    if (ActiveCallTracker.instance.isActive) return;
    if (_redirectScheduled) return;

    // NotificationService.navigatorKey is attached once the root Navigator
    // has built its first frame. It's already mounted by the time this
    // widget (part of MaterialApp.builder) runs in the overwhelmingly
    // common case; the rare miss (a 401 arriving before the very first
    // frame) simply leaves SessionExpiredScreen's manual button as the way
    // back in, and this listener retries on every subsequent notification.
    final navigator = NotificationService.navigatorKey.currentState;
    if (navigator == null) return;

    _redirectScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Reset before navigating so the overlay this build() paints doesn't
      // stay stuck showing over the freshly-pushed LoginScreen.
      SessionExpiredService.instance.reset();
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Catches the case where SessionExpiredService's listener fired before
    // the navigator key was attached (e.g. very first frame at cold start)
    // — every subsequent rebuild retries.
    _maybeAutoRedirect();

    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: ListenableBuilder(
            listenable: SessionExpiredService.instance,
            builder: (context, _) {
              return ValueListenableBuilder<int>(
                valueListenable: ActiveCallTracker.instance.activeCount,
                builder: (context, activeCallCount, _) {
                  final showExpired =
                      SessionExpiredService.instance.isExpired &&
                      activeCallCount == 0;

                  return IgnorePointer(
                    ignoring: !showExpired,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: showExpired
                          ? const SessionExpiredScreen(
                              key: ValueKey('session-expired'),
                            )
                          : const SizedBox.shrink(key: ValueKey('active')),
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
