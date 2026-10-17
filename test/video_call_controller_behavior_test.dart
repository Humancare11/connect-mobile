// Behaviour tests for VideoCallController driven through a fake signaling
// socket and a fake RTCPeerConnection (no native WebRTC, no network). Time is
// virtual (fakeAsync) so 30s of backoff runs instantly.
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:humancare_connect/controllers/video_call_controller.dart';
import 'package:humancare_connect/services/socket_service.dart';

class FakeSocket implements SocketService {
  final Map<String, List<void Function(dynamic)>> handlers = {};
  final List<MapEntry<String, dynamic>> emitted = [];
  bool _connected = true;
  int _seq = 1;
  int connectCalls = 0;
  int disconnectCalls = 0;
  bool ackResponds = true;

  @override
  bool get connected => _connected;
  @override
  String? get id => 'sock-$_seq';

  @override
  void connect() {
    connectCalls++;
    if (!_connected) _seq++;
    _connected = true;
  }

  @override
  void disconnect() {
    disconnectCalls++;
    _connected = false;
  }

  @override
  void emit(String event, dynamic data) => emitted.add(MapEntry(event, data));

  @override
  void emitWithAck(String event, dynamic data, void Function(dynamic) ack) {
    emitted.add(MapEntry(event, data));
    if (ackResponds) ack({'ok': true});
  }

  @override
  void on(String event, void Function(dynamic) handler) => (handlers[event] ??= []).add(handler);

  @override
  void off(String event, [void Function(dynamic)? handler]) {
    if (handler == null) {
      handlers.remove(event);
    } else {
      handlers[event]?.remove(handler);
    }
  }

  @override
  void once(String event, void Function(dynamic) handler) => on(event, handler);

  @override
  void onManager(String event, void Function(dynamic) handler) {}

  @override
  void offManager(String event, [void Function(dynamic)? handler]) {}

  void trigger(String event, [dynamic data]) {
    for (final h in List.of(handlers[event] ?? const [])) {
      h(data);
    }
  }

  int count(String event) => emitted.where((e) => e.key == event).length;
}

class FakePc implements RTCPeerConnection {
  RTCPeerConnectionState state = RTCPeerConnectionState.RTCPeerConnectionStateConnected;
  RTCIceConnectionState iceState = RTCIceConnectionState.RTCIceConnectionStateConnected;
  RTCSignalingState sigState = RTCSignalingState.RTCSignalingStateStable;
  bool closed = false;

  @override
  RTCPeerConnectionState? get connectionState => state;
  @override
  RTCIceConnectionState? get iceConnectionState => iceState;
  @override
  RTCSignalingState? get signalingState => sigState;

  @override
  Future<void> close() async {
    closed = true;
    sigState = RTCSignalingState.RTCSignalingStateClosed;
  }

  @override
  Future<RTCSessionDescription> createOffer([Map<String, dynamic>? constraints]) async =>
      RTCSessionDescription('v=0\r\ns=-\r\n', 'offer');

  @override
  Future<void> setLocalDescription(RTCSessionDescription description) async {
    sigState = RTCSignalingState.RTCSignalingStateHaveLocalOffer;
  }

  @override
  Future<List<StatsReport>> getStats([MediaStreamTrack? track]) async => <StatsReport>[];

  // Callback setters (onTrack = ..., onConnectionState = ...) and anything else unused.
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

VideoCallController makeController(FakeSocket socket) {
  final c = VideoCallController(
    appointmentId: 'appt-1',
    initialAppointment: {'_id': 'appt-1', 'status': 'confirmed'},
    initialPatient: {'_id': 'patient-1'},
    initialRole: 'patient',
    socket: socket,
  );
  c.debugRegisterSocketListeners();
  return c;
}

// Elapse virtual time in small steps so chained timers/microtasks all run.
void elapse(dynamic async, Duration total) {
  var left = total.inMilliseconds;
  while (left > 0) {
    final step = left > 250 ? 250 : left;
    async.elapse(Duration(milliseconds: step));
    left -= step;
  }
  async.flushMicrotasks();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Secure storage (tokens) has no native side in unit tests: answer every call
  // with "nothing stored" so token reads/refreshes complete instead of hanging.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
  });

  group('room-access-denied by reason', () {
    test('terminal reasons end the call', () {
      for (final reason in ['appointment_ended', 'not_participant', 'appointment_not_found']) {
        fakeAsync((async) {
          final socket = FakeSocket();
          final c = makeController(socket);
          socket.trigger('room-access-denied', {'reason': reason, 'msg': 'nope'});
          async.flushMicrotasks();
          expect(c.apptError, 'nope', reason: reason);
          expect(c.debugCompleted, isTrue, reason: reason);
          expect(c.joinRetryPhase, isNull, reason: reason);
        });
      }
    });

    test('retryable reasons keep the call, retry with backoff, then offer a Retry button', () {
      for (final reason in ['unauthenticated', 'room_full', 'server_error', 'invalid_appointment', null]) {
        fakeAsync((async) {
          final socket = FakeSocket();
          final c = makeController(socket)..isReady = true;
          for (var attempt = 0; attempt < kJoinRetryDelaysMs.length; attempt++) {
            socket.trigger('room-access-denied', {'reason': ?reason});
            async.flushMicrotasks();
            expect(c.joinRetryPhase, 'retrying', reason: '$reason #$attempt');
            expect(c.apptError, isEmpty);
            expect(c.debugCompleted, isFalse);
            elapse(async, Duration(milliseconds: kJoinRetryDelaysMs[attempt]));
          }
          // each retry re-emitted the join
          expect(socket.count('join-appointment-room'), kJoinRetryDelaysMs.length, reason: '$reason');
          // budget exhausted -> failed state with a manual Retry
          socket.trigger('room-access-denied', {'reason': ?reason});
          async.flushMicrotasks();
          expect(c.joinRetryPhase, 'failed', reason: '$reason');
          c.retryJoinManually();
          expect(c.joinRetryPhase, 'retrying');
          elapse(async, const Duration(seconds: 1));
          expect(socket.count('join-appointment-room'), kJoinRetryDelaysMs.length + 1, reason: '$reason');
          // an accepted join (chat history arrives) clears the retry state
          socket.trigger('appointment-chat-history', {'appointmentId': 'appt-1', 'messages': []});
          expect(c.joinRetryPhase, isNull);
        });
      }
    });
  });

  group('socket drop and reconnect', () {
    test('a signaling-only drop does not touch the media state', () {
      fakeAsync((async) {
        final socket = FakeSocket();
        final c = makeController(socket);
        c.debugSetPeerConnection(FakePc());
        c.isRemoteConnected = true;
        c.connectionState = 'connected';
        socket.trigger('disconnect', 'transport close');
        expect(c.signalingConnected, isFalse);
        expect(c.isRemoteConnected, isTrue);
        expect(c.connectionState, 'connected');
        socket.trigger('connect');
        expect(c.signalingConnected, isTrue);
      });
    });

    test('a drop while the media path is also down marks the call disconnected', () {
      fakeAsync((async) {
        final socket = FakeSocket();
        final c = makeController(socket);
        c.debugSetPeerConnection(FakePc()
          ..state = RTCPeerConnectionState.RTCPeerConnectionStateDisconnected
          ..iceState = RTCIceConnectionState.RTCIceConnectionStateDisconnected);
        c.isRemoteConnected = true;
        socket.trigger('disconnect', 'ping timeout');
        expect(c.signalingConnected, isFalse);
        expect(c.isRemoteConnected, isFalse);
        expect(c.connectionState, 'disconnected');
      });
    });

    test('reconnect re-joins the room', () {
      fakeAsync((async) {
        final socket = FakeSocket();
        final c = makeController(socket)..isReady = true;
        socket.trigger('connect');
        elapse(async, const Duration(seconds: 1));
        expect(socket.count('join-appointment-room'), 1);
        socket.trigger('disconnect', 'transport close');
        socket.disconnect();
        socket.connect(); // new socket id
        socket.trigger('connect');
        elapse(async, const Duration(seconds: 1));
        expect(socket.count('join-appointment-room'), 2, reason: 'a new connection must join again');
        expect(c.signalingConnected, isTrue);
      });
    });
  });

  group('offline handling', () {
    test('ICE recovery does not spend attempts while offline, keeps looping, and resumes online', () {
      fakeAsync((async) {
        final socket = FakeSocket();
        final c = makeController(socket)..isReady = true;
        c.debugSetPeerConnection(FakePc()
          ..state = RTCPeerConnectionState.RTCPeerConnectionStateDisconnected
          ..iceState = RTCIceConnectionState.RTCIceConnectionStateDisconnected);
        c.peerJoined = true;
        c.isOffline = true;

        c.debugScheduleIceRestart();
        elapse(async, const Duration(seconds: 30)); // way more than the 4-attempt budget
        expect(socket.count('video-offer'), 0, reason: 'nothing may be sent while offline');
        expect(socket.count('ice-restart-request'), 0);
        expect(c.debugIceRestartPending, isTrue, reason: 'the loop must stay alive');

        c.debugConnectivityRestored();
        elapse(async, const Duration(seconds: 3));
        expect(socket.count('video-offer'), 1, reason: 'first attempt goes out as soon as we are back');
      });
    });

    test('same when only the signaling socket is down', () {
      fakeAsync((async) {
        final socket = FakeSocket();
        final c = makeController(socket)..isReady = true;
        c.debugSetPeerConnection(FakePc()
          ..state = RTCPeerConnectionState.RTCPeerConnectionStateFailed
          ..iceState = RTCIceConnectionState.RTCIceConnectionStateFailed);
        c.peerJoined = true;
        socket.disconnect();
        c.debugScheduleIceRestart();
        elapse(async, const Duration(seconds: 20));
        expect(socket.count('video-offer'), 0);
        expect(c.debugIceRestartPending, isTrue);
      });
    });

    test('join waits for connectivity instead of joining with a stale token', () {
      fakeAsync((async) {
        final socket = FakeSocket();
        final c = makeController(socket)..isReady = true;
        c.isOffline = true; // token refresh cannot succeed
        socket.trigger('connect');
        elapse(async, const Duration(seconds: 20));
        expect(socket.count('join-appointment-room'), 0, reason: 'must wait while offline');
        c.debugConnectivityRestored();
        elapse(async, const Duration(seconds: 2));
        expect(socket.count('join-appointment-room'), 1);
      });
    });
  });

  group('participant left / rejoined', () {
    test('participant-left closes the pc and stops all recovery; peer-joined clears the notice', () {
      fakeAsync((async) {
        final socket = FakeSocket();
        final c = makeController(socket)..isReady = true;
        final pc = FakePc()
          ..state = RTCPeerConnectionState.RTCPeerConnectionStateDisconnected
          ..iceState = RTCIceConnectionState.RTCIceConnectionStateDisconnected;
        c.debugSetPeerConnection(pc);
        c.peerJoined = true;
        c.debugScheduleIceRestart();
        expect(c.debugIceRestartPending, isTrue);

        socket.trigger('participant-left');
        async.flushMicrotasks();
        expect(pc.closed, isTrue, reason: 'stale connection must be dropped');
        expect(c.debugIceRestartPending, isFalse);
        expect(c.peerLeft, isTrue);

        c.debugScheduleIceRestart(); // gated on peerJoined
        elapse(async, const Duration(seconds: 60));
        expect(c.debugIceRestartPending, isFalse);
        expect(socket.count('video-offer'), 0);
        expect(socket.count('ice-restart-request'), 0);

        c.reconnectInProgress = true; // skip the native rebuild that a real rejoin triggers
        socket.trigger('peer-joined', {'resumedCall': true});
        expect(c.peerJoined, isTrue);
        expect(c.peerLeft, isFalse);
      });
    });
  });

  group('app lifecycle', () {
    test('resume with a healthy socket sends one ping and keeps the connection', () {
      fakeAsync((async) {
        final socket = FakeSocket()..ackResponds = true;
        final c = makeController(socket);
        c.debugSetPeerConnection(FakePc());
        c.handleAppPaused();
        c.handleAppResumed();
        elapse(async, const Duration(seconds: 5));
        expect(socket.count('hc-ping'), 1);
        expect(socket.disconnectCalls, 0);
      });
    });

    test('resume with a zombie socket (no ack) forces a reconnect', () {
      fakeAsync((async) {
        final socket = FakeSocket()..ackResponds = false;
        final c = makeController(socket);
        c.debugSetPeerConnection(FakePc());
        c.handleAppPaused();
        c.handleAppResumed();
        elapse(async, const Duration(milliseconds: kSocketProbeTimeoutMs + 500));
        elapse(async, const Duration(seconds: 2));
        expect(socket.disconnectCalls, 1, reason: 'zombie socket must be dropped');
        expect(socket.connectCalls, greaterThanOrEqualTo(1), reason: 'and replaced');
      });
    });
  });

  group('cleanup', () {
    test('leaving cancels every timer: nothing is sent afterwards', () {
      fakeAsync((async) {
        final socket = FakeSocket();
        final c = makeController(socket)..isReady = true;
        final pc = FakePc()
          ..state = RTCPeerConnectionState.RTCPeerConnectionStateDisconnected
          ..iceState = RTCIceConnectionState.RTCIceConnectionStateDisconnected;
        c.debugSetPeerConnection(pc);
        c.peerJoined = true;
        c.debugScheduleIceRestart();
        socket.trigger('room-access-denied', {'reason': 'server_error'}); // pending retry timer
        expect(c.debugIceRestartPending, isTrue);

        unawaited(c.leaveCall());
        async.flushMicrotasks();
        expect(pc.closed, isTrue);
        expect(c.debugIceRestartPending, isFalse);
        final before = socket.emitted.length;
        elapse(async, const Duration(seconds: 120));
        expect(socket.emitted.length, before, reason: 'no timer may fire after leaving');
      });
    });

    test('dispose cancels pending join retries', () {
      fakeAsync((async) {
        final socket = FakeSocket();
        final c = makeController(socket)..isReady = true;
        socket.trigger('room-access-denied', {'reason': 'room_full'});
        c.dispose();
        async.flushMicrotasks();
        final before = socket.count('join-appointment-room');
        elapse(async, const Duration(seconds: 120));
        expect(socket.count('join-appointment-room'), before);
      });
    });
  });
}
