import 'package:flutter/material.dart';

import '../services/idle_session_timer.dart';

/// Marks any pointer interaction, app-wide, as activity for
/// [IdleSessionTimer] — mirroring the web app's
/// `mousemove`/`mousedown`/`keydown`/`touchstart`/`scroll` listeners in
/// `SessionTimeoutManager`. Mount once at the app root (see `main.dart`'s
/// `MaterialApp.builder`), outermost, so it sees taps/scrolls anywhere,
/// including on top of `SessionExpiredGate`/`ConnectivityGate`'s overlays.
///
/// `HitTestBehavior.translucent` means this never consumes or blocks the
/// pointer event — it only observes, so every existing gesture/tap/scroll
/// handler in the app keeps working exactly as before.
class IdleActivityListener extends StatelessWidget {
  const IdleActivityListener({super.key, required this.child});

  final Widget child;

  void _mark(PointerEvent _) => IdleSessionTimer.instance.registerActivity();

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _mark,
      onPointerMove: _mark,
      onPointerSignal: _mark,
      child: child,
    );
  }
}
