import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config/api_config.dart';

class SocketService {
  SocketService._()
    : _socket = io.io(
        _socketBaseUrl,
        io.OptionBuilder()
            .setTransports(['websocket'])
            .disableAutoConnect()
            .build(),
      );

  static final SocketService instance = SocketService._();

  final io.Socket _socket;

  static String get _socketBaseUrl {
    final base = ApiConfig.baseUrl;
    return base.endsWith('/api') ? base.substring(0, base.length - 4) : base;
  }

  bool get connected => _socket.connected;

  void connect() => _socket.connect();

  void emit(String event, dynamic data) => _socket.emit(event, data);

  void on(String event, void Function(dynamic) handler) {
    _socket.on(event, handler);
  }

  void once(String event, void Function(dynamic) handler) {
    _socket.once(event, handler);
  }
}
