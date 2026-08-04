import 'dart:async';

import 'package:flutter/widgets.dart';

import 'active_call_tracker.dart';
import 'session_expired_service.dart';
import 'token_storage_service.dart';

/// Logs the user out after 30 minutes of continuous inactivity, mirroring
/// the web app's `SessionTimeoutManager` idle timer
/// (connect/frontend/src/utils/session.js `ROLE_TIMEOUT_MS`) — every role
/// gets the same 30-minute window there now, and this app has no
/// admin/employee-admin surface, so there's just the one timeout to track
/// here.
///
/// While a video call is active ([ActiveCallTracker]), the effective budget
/// extends to [callActiveTimeout] (90 min) instead of [timeout] (30 min) —
/// long enough to cover a real consultation. Reaching that extended
/// deadline marks the session expired *silently* (no UI at all — see
/// [_onDeadlineReached]) and the actual logout is executed the moment the
/// call ends (see [_onActiveCallChanged]), never interrupting it.
///
/// Activity resets the countdown from three sources, mirroring web's
/// coverage there (mouse/keyboard/touch/scroll + every API call):
/// - any pointer interaction, app-wide (see `IdleActivityListener`)
/// - any app navigation (see `IdleActivityNavigatorObserver`)
/// - any API call (see `ApiClient`'s verb methods)
///
/// Note `ApiClient.refreshAccessToken` — the periodic keep-alive heartbeat
/// `VideoCallController` calls during a call — deliberately does *not* call
/// [registerActivity] (unlike the app's `get`/`post`/`put`/`patch`
/// methods). If it did, that heartbeat (every 4 min, well under 30) would
/// perpetually reset this timer on its own and the inactivity timeout would
/// never fire for anyone, call or no call. That heartbeat still keeps the
/// access/refresh token pair alive server-side (and resets the backend's
/// own inactivity check — see `connect/backend/middleware/verifyToken.js`)
/// completely independently of this timer's state.
///
/// Deliberately not persisted across process death — if the OS kills the
/// app while backgrounded and it's relaunched well past the deadline,
/// [AuthGateScreen] restarts this timer fresh, but the very next API call's
/// access token (15 min) will already be stale, and the backend's own
/// server-side inactivity check will reject the refresh attempt, landing on
/// the exact same [ApiClient]-driven expiry path. The backend is the
/// authoritative enforcement point either way; this timer is purely a
/// proactive client-side UX layer while the app is alive.
class IdleSessionTimer with WidgetsBindingObserver {
  IdleSessionTimer._();

  static final IdleSessionTimer instance = IdleSessionTimer._();

  static const Duration timeout = Duration(minutes: 30);
  static const Duration callActiveTimeout = Duration(minutes: 90);

  // Pointer-move events can fire dozens of times a second during a single
  // scroll/drag; cancelling and re-arming a Timer on every one of them is
  // wasted work. Throttling to once per this interval bounds the worst-case
  // actual timeout to `timeout + _minRearmInterval` past the true last
  // activity — a few seconds of slack that doesn't matter against a
  // 30-minute window.
  static const Duration _minRearmInterval = Duration(seconds: 5);

  Timer? _timer;
  bool _running = false;
  bool _pendingLogout = false;
  DateTime? _lastActivityAt;
  final TokenStorageService _tokenStorage = const TokenStorageService();

  /// Starts the idle countdown. Call once a session exists — cold start
  /// with a stored session ([AuthGateScreen]) or right after
  /// login/register/Google-auth ([AuthService.saveSession]). Idempotent.
  void start() {
    if (_running) return;
    _running = true;
    WidgetsBinding.instance.addObserver(this);
    ActiveCallTracker.instance.activeCount.addListener(_onActiveCallChanged);
    registerActivity();
  }

  /// Stops the countdown entirely. Call on logout — manual ([AccountScreen])
  /// or automatic ([ApiClient._handleSessionExpired], or this class's own
  /// [_logout]) — so a stale timer can't log the user out a second time
  /// after they're already signed out. Idempotent.
  void stop() {
    if (!_running) return;
    _running = false;
    _pendingLogout = false;
    _timer?.cancel();
    _timer = null;
    _lastActivityAt = null;
    WidgetsBinding.instance.removeObserver(this);
    ActiveCallTracker.instance.activeCount.removeListener(_onActiveCallChanged);
  }

  /// Resets the countdown. Safe to call whether or not the timer is
  /// running (a no-op while signed out) and from any isolate-safe context.
  void registerActivity() {
    if (!_running) return;
    final now = DateTime.now();
    if (_lastActivityAt != null &&
        now.difference(_lastActivityAt!) < _minRearmInterval) {
      return;
    }
    _lastActivityAt = now;
    _pendingLogout = false;
    _rearm();
  }

  void _onActiveCallChanged() {
    if (!_running) return;
    if (ActiveCallTracker.instance.isActive) {
      // Call just (re)started — the effective deadline just got longer;
      // re-arm against it.
      _rearm();
      return;
    }

    if (_pendingLogout) {
      _pendingLogout = false;
      unawaited(_logout());
      return;
    }
    // Call just ended with nothing pending — the call itself counted as
    // legitimate engagement, so treat its end as fresh activity rather than
    // instantly re-applying the shorter 30-minute threshold against
    // whatever time already elapsed while protected.
    _lastActivityAt = DateTime.now();
    _rearm();
  }

  /// (Re)computes the correct deadline for the current call state and
  /// elapsed-since-last-activity, and arms a single timer for it — the one
  /// source of truth for both the normal activity-reset path and the
  /// app-resume path below, so the two can never disagree about what
  /// should happen next.
  void _rearm() {
    _timer?.cancel();
    if (_lastActivityAt == null) return;

    final callActive = ActiveCallTracker.instance.isActive;
    final effectiveTimeout = callActive ? callActiveTimeout : timeout;
    final elapsed = DateTime.now().difference(_lastActivityAt!);
    final remaining = effectiveTimeout - elapsed;

    if (remaining <= Duration.zero) {
      _onDeadlineReached();
      return;
    }
    _timer = Timer(remaining, _onDeadlineReached);
  }

  void _onDeadlineReached() {
    if (!_running) return;
    if (ActiveCallTracker.instance.isActive) {
      // Never interrupt an in-progress consultation: mark expired silently
      // — no UI at all — and wait for _onActiveCallChanged to execute the
      // actual logout once the call ends.
      _pendingLogout = true;
      return;
    }
    unawaited(_logout());
  }

  Future<void> _logout() async {
    if (!_running) return; // already handled via another path
    stop();
    await _tokenStorage.clearAll();
    SessionExpiredService.instance.trigger();
  }

  // Standard mobile OSes suspend/throttle Dart Timers while the app is
  // backgrounded, so a Timer armed before backgrounding can't be trusted to
  // fire on schedule. On resume, re-derive the correct state from the real
  // elapsed wall-clock time instead.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!_running || _lastActivityAt == null) return;
    _rearm();
  }
}

/// Marks navigation as activity, mirroring the web app's route-change reset
/// (`SessionTimeoutManager`'s `location.pathname` effect in App.jsx).
/// Attach via `MaterialApp(navigatorObservers: [IdleActivityNavigatorObserver()])`.
class IdleActivityNavigatorObserver extends NavigatorObserver {
  void _mark() => IdleSessionTimer.instance.registerActivity();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _mark();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _mark();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _mark();
}
