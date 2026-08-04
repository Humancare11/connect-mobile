import 'dart:async';

import 'package:flutter/foundation.dart';

/// Global, singleton source of truth for the app-wide loading overlay.
///
/// Backed by a request counter (not a bool) so concurrent API calls don't
/// flicker the overlay off just because one of several in-flight requests
/// finished — the overlay only hides once the counter returns to zero.
///
/// Dart runs single-threaded per isolate, so there's no lock/mutex needed
/// here; the correctness concerns are purely about async ordering: [show]
/// and [hide] can be called in any interleaving (rapid navigation, several
/// concurrent requests, requests that throw) and must never let the counter
/// go negative, never leave a stale [Timer] able to hide the overlay out
/// from under a request that's still running, and never get stuck visible
/// or hidden.
class LoadingService extends ChangeNotifier {
  LoadingService._();

  static final LoadingService instance = LoadingService._();

  static const Duration _minVisibleDuration = Duration(milliseconds: 250);

  int _counter = 0;
  DateTime? _shownAt;
  Timer? _pendingHideTimer;
  bool _visible = false;

  bool get isLoading => _visible;

  /// Marks one request as in-flight. Safe to call any number of times
  /// concurrently; the overlay stays visible until every matching [hide]
  /// call has landed.
  void show() {
    // A request just started, so any previously scheduled "hide after the
    // minimum duration" timer from a prior 0-in-flight moment is now stale
    // — cancel it so it can't fire later and hide the overlay while this
    // new request is still running.
    _cancelPendingHideTimer();

    _counter++;
    if (_counter == 1) {
      _shownAt = DateTime.now();
      _setVisible(true);
    }
  }

  /// Marks one in-flight request as finished (success, error, or exception —
  /// callers are expected to call this from a `finally` block). Ignores
  /// extra/unmatched calls instead of driving the counter negative.
  void hide() {
    if (_counter == 0) return;

    _counter--;
    if (_counter > 0) return;

    final shownAt = _shownAt;
    final elapsed = shownAt == null
        ? _minVisibleDuration
        : DateTime.now().difference(shownAt);

    if (elapsed >= _minVisibleDuration) {
      _hideNow();
      return;
    }

    // The overlay hasn't been visible long enough yet — defer the actual
    // hide so fast requests don't produce a one-frame flash. Re-check the
    // counter when the timer fires: a new request may have started during
    // the wait, in which case this timer is stale and must be a no-op.
    final remaining = _minVisibleDuration - elapsed;
    _pendingHideTimer = Timer(remaining, () {
      _pendingHideTimer = null;
      if (_counter == 0) {
        _hideNow();
      }
    });
  }

  void _hideNow() {
    _cancelPendingHideTimer();
    _shownAt = null;
    _setVisible(false);
  }

  void _cancelPendingHideTimer() {
    _pendingHideTimer?.cancel();
    _pendingHideTimer = null;
  }

  void _setVisible(bool value) {
    if (_visible == value) return;
    _visible = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _cancelPendingHideTimer();
    super.dispose();
  }
}
