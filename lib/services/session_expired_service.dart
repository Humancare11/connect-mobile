import 'package:flutter/foundation.dart';

/// Global, singleton source of truth for whether the current session has
/// been invalidated — an API call came back `401` while an access token was
/// attached, and the follow-up token refresh either failed or there was no
/// refresh token to try. Driving the app-wide "Session Expired" screen (see
/// `SessionExpiredGate`), mirroring [ConnectivityService]'s shape.
///
/// Pure state holder, same as `ConnectivityService` — no navigation and no
/// storage side effects live here. `ApiClient` clears stored tokens before
/// calling [trigger]; `SessionExpiredGate`/`SessionExpiredScreen` handle
/// navigating back to the login screen.
class SessionExpiredService extends ChangeNotifier {
  SessionExpiredService._();

  static final SessionExpiredService instance = SessionExpiredService._();

  bool _expired = false;

  bool get isExpired => _expired;

  /// Marks the session as expired. Idempotent: safe to call from several
  /// concurrent 401 responses without re-notifying listeners or re-running
  /// whatever they do in response (e.g. clearing tokens) more than once.
  void trigger() {
    if (_expired) return;
    _expired = true;
    notifyListeners();
  }

  /// Clears the expired flag. Call once the user lands back on the login
  /// screen so a stale flag can't immediately re-show the gate after a
  /// fresh login.
  void reset() {
    if (!_expired) return;
    _expired = false;
    notifyListeners();
  }
}
