// Socket.IO client wiring, ported from frontend/src/socket.js.
//
// Two things the previous version of this file was missing, both required
// for the mobile app to work against the shared backend at all:
//
//  1. Auth handshake payload. backend/server.js's `io.use(...)` middleware
//     authenticates HttpOnly cookies first, but explicitly falls back to
//     `socket.handshake.auth.token` (a Bearer access token) specifically for
//     clients — like this app — that cannot rely on cookies. Without it,
//     every socket connects with no identity and `join-appointment-room`
//     is rejected with `room-access-denied`.
//  2. Reconnection tuning + manager-level event access, matching socket.js
//     (`reconnection: true`, effectively-unlimited attempts, backoff/jitter)
//     so a dropped connection (cellular handoff, app backgrounding) actually
//     recovers instead of going silent.

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config/api_config.dart';
import 'token_storage_service.dart';

class SocketService {
  SocketService._() : _socket = io.io(_socketBaseUrl, _buildOptions()) {
    _installDiagnostics();
  }

  static final SocketService instance = SocketService._();

  final io.Socket _socket;

  static String get _socketBaseUrl {
    final base = ApiConfig.baseUrl;
    return base.endsWith('/api') ? base.substring(0, base.length - 4) : base;
  }

  static Map<String, dynamic> _buildOptions() {
    return io.OptionBuilder()
        .setPath('/socket.io/')
        // On native platforms (Android/iOS/desktop), this package's
        // transport factory (lib/src/engine/transport/io_transports.dart)
        // always instantiates a raw WebSocket regardless of the requested
        // transport name, but the request's `transport` query parameter
        // still reflects whichever name was requested first — so listing
        // 'polling' first sends a genuine WebSocket upgrade mislabeled as
        // `transport=polling`. The server's Engine.IO layer picks its
        // handshake handling based on that query param, so the mismatch
        // leaves the socket stuck at the raw-upgrade layer (HTTP 101)
        // without ever completing the Engine.IO-level handshake — every
        // connection attempt times out and retries, indefinitely. Native
        // builds request 'websocket' only, fixing the label from the very
        // first attempt (nothing lost — 'polling' was never actually
        // reachable there anyway). Web keeps the original list unchanged:
        // it has its own real polling implementation and is unaffected by
        // any of this.
        .setTransports(kIsWeb ? ['polling', 'websocket'] : ['websocket'])
        .disableAutoConnect()
        .enableReconnection()
        .setReconnectionAttempts(double.infinity)
        .setReconnectionDelay(1000)
        .setReconnectionDelayMax(5000)
        .setRandomizationFactor(0.5)
        .setTimeout(20000)
        // Evaluated fresh on every connect/reconnect attempt (see
        // Socket.open() in the socket_io_client source), so a rotated token
        // is always picked up without needing to rebuild the socket.
        .setAuthFn((callback) async {
      final token = await _instanceTokenStorage.getToken();
      callback({'token': token ?? ''});
    }).build();
  }

  // `_buildOptions` runs before `instance` exists (it feeds the constructor
  // initializer list), so the authFn closure can't reference `this`; a
  // static token storage instance is fine since TokenStorageService is
  // stateless (reads secure storage fresh on every call).
  static const TokenStorageService _instanceTokenStorage = TokenStorageService();

  void _installDiagnostics() {
    _socket.onConnect((_) {
      debugPrint('[socket] connected id=${_socket.id}');
    });
    _socket.onDisconnect((reason) {
      debugPrint('[socket] disconnected reason=$reason');
    });
    _socket.onConnectError((err) {
      debugPrint('[socket] connect_error $err');
    });
    _socket.io.on('reconnect_attempt', (attempt) {
      debugPrint('[socket] reconnect_attempt $attempt');
    });
    _socket.io.on('reconnect', (attempt) {
      debugPrint('[socket] reconnected after $attempt attempt(s)');
    });
    _socket.io.on('reconnect_failed', (_) {
      debugPrint('[socket] reconnect_failed');
    });
  }

  bool get connected => _socket.connected;
  String? get id => _socket.id;

  void connect() => _socket.connect();

  void disconnect() => _socket.disconnect();

  void emit(String event, dynamic data) => _socket.emit(event, data);

  void on(String event, void Function(dynamic) handler) {
    _socket.on(event, handler);
  }

  void off(String event, [void Function(dynamic)? handler]) {
    if (handler == null) {
      _socket.off(event);
      return;
    }
    _socket.off(event, handler);
  }

  void once(String event, void Function(dynamic) handler) {
    _socket.once(event, handler);
  }

  /// Manager-level events (`socket.io.on(...)` in the JS client): `reconnect`,
  /// `reconnect_attempt`, `reconnect_failed`, `reconnect_error`. Distinct
  /// from per-socket `on`, which only covers `connect`/`disconnect`/app
  /// events.
  void onManager(String event, void Function(dynamic) handler) {
    _socket.io.on(event, handler);
  }

  void offManager(String event, [void Function(dynamic)? handler]) {
    _socket.io.off(event, handler);
  }
}
