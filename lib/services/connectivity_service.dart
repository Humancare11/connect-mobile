import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Global, singleton source of truth for whether the device currently has a
/// network interface up (Wi-Fi/cellular/ethernet), driving the app-wide
/// "No Internet Connection" screen (see `ConnectivityGate`).
///
/// Mirrors the detection approach already used for the video call screen in
/// [VideoCallController] (`connectivity_plus`'s interface-level signal,
/// deduped against the previous result set) rather than adding a separate
/// reachability probe — this only reports NIC status, not true internet
/// reachability, matching that existing precedent.
class ConnectivityService extends ChangeNotifier {
  ConnectivityService._() {
    _init();
  }

  static final ConnectivityService instance = ConnectivityService._();

  // A brief interface handoff (e.g. Wi-Fi -> cellular) can report
  // ConnectivityResult.none for a moment without the device ever truly
  // losing internet. Debounce only the "going offline" transition so a
  // handoff like that doesn't flash the full-screen page; coming back
  // online is reported immediately.
  static const Duration _offlineDebounce = Duration(milliseconds: 700);

  bool _isOnline = true;
  List<ConnectivityResult> _lastResults = const [];
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _offlineDebounceTimer;

  bool get isOnline => _isOnline;

  Future<void> _init() async {
    try {
      final initial = await Connectivity().checkConnectivity();
      _lastResults = initial;
      _isOnline = !_allNone(initial);
      notifyListeners();
    } catch (_) {
      // Best-effort, same as VideoCallController._initConnectivityWatch: if
      // the platform channel isn't available, default to online rather than
      // permanently trapping the app behind the No Internet screen.
    }

    _subscription = Connectivity().onConnectivityChanged.listen(_handleResults);
  }

  /// Re-checks immediately, bypassing the debounce — used by the "Retry"
  /// button so tapping it always gives instant feedback instead of waiting
  /// out the offline-transition debounce window.
  Future<void> retryNow() async {
    try {
      final results = await Connectivity().checkConnectivity();
      _handleResults(results);
    } catch (_) {
      // Ignore -- worst case the user taps Retry again.
    }
  }

  void _handleResults(List<ConnectivityResult> results) {
    if (!_resultsChanged(results, _lastResults)) return;
    _lastResults = results;

    final offline = _allNone(results);

    if (!offline) {
      _offlineDebounceTimer?.cancel();
      _offlineDebounceTimer = null;
      _setOnline(true);
      return;
    }

    _offlineDebounceTimer?.cancel();
    _offlineDebounceTimer = Timer(_offlineDebounce, () {
      _offlineDebounceTimer = null;
      _setOnline(false);
    });
  }

  bool _allNone(List<ConnectivityResult> results) =>
      results.every((r) => r == ConnectivityResult.none);

  bool _resultsChanged(List<ConnectivityResult> a, List<ConnectivityResult> b) {
    final setA = a.toSet();
    final setB = b.toSet();
    return setA.length != setB.length || !setA.containsAll(setB);
  }

  void _setOnline(bool value) {
    if (_isOnline == value) return;
    _isOnline = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _offlineDebounceTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
