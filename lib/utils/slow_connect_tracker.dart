/// "Still trying" notice: the user has joined, the other person is in the call,
/// but our peer connection has not reached "connected" for [delaySeconds].
/// Purely observational - it only reads status, it never touches retry or
/// recovery. Driven by a 1-second tick (call [tick] once per second), so it
/// needs no clock. Mirrors frontend/src/utils/slowConnectNotice.js.
class SlowConnectTracker {
  SlowConnectTracker({this.delaySeconds = 30});

  final int delaySeconds;
  int _waitingSeconds = 0;

  /// Returns whether the notice should be showing after this tick.
  bool tick({
    required bool joined,
    required bool peerPresent,
    required bool connected,
    required bool suppressed,
  }) {
    if (!joined || !peerPresent || connected) {
      _waitingSeconds = 0;
      return false;
    }
    _waitingSeconds += 1;
    return !suppressed && _waitingSeconds >= delaySeconds;
  }

  void reset() => _waitingSeconds = 0;
}
