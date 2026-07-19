// Signaling / WebRTC / call-lifecycle controller, ported 1:1 from the
// behavior of frontend/src/pages/VideoCall.jsx's big `useEffect`. Kept
// deliberately close to the React control flow (same event names, same
// perfect-negotiation/ICE-restart machinery, same constants) rather than
// "improved," since the whole point is behavioral parity with the web app
// and the shared Node backend.
//
// This app only ever authenticates as a patient (see appointments_screen.dart
// — `initialRole` is always 'user', and there is no doctor login flow), so
// `isDoctor` below is always false at runtime. The branching is kept anyway
// because it's shared signaling/call-lifecycle logic (who is the "polite"
// peer in perfect negotiation, who can complete the appointment) mirrored
// from the same source the web app uses — not doctor-only UI.

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/api_service.dart';
import '../services/ice_server_config.dart';
import '../services/socket_service.dart';
import '../services/token_storage_service.dart';
import '../utils/direct_upload.dart';

const Map<String, dynamic> kMediaConstraints = {
  'audio': {
    'echoCancellation': true,
    'noiseSuppression': true,
    'autoGainControl': true,
    'channelCount': {'ideal': 2},
    'sampleRate': {'ideal': 48000},
    'sampleSize': {'ideal': 16},
  },
  'video': {
    'width': {'ideal': 1280, 'max': 1920},
    'height': {'ideal': 720, 'max': 1080},
    'frameRate': {'ideal': 30, 'max': 30},
    'facingMode': 'user',
  },
};

const int kCameraBitrate = 1200000;
const int kScreenShareBitrate = 2000000;
const int kVoiceBitrate = 64000;
const int kIceRestartDelayMs = 2500;
const int kConnectionFailTimeoutMs = 25000;
const int kIceMaxRecoveryAttempts = 4;
const int kIceRecoveryCooldownMs = 30000;
const int kStatsIntervalMs = 30000;
const int kPeerJoinTimeoutMs = 20000;

class ChatMessage {
  final String senderId;
  final String senderName;
  final String text;
  final String? fileUrl;
  final String? fileName;
  final String? fileType;
  final String? createdAt;

  ChatMessage({
    required this.senderId,
    required this.senderName,
    this.text = '',
    this.fileUrl,
    this.fileName,
    this.fileType,
    this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        senderId: (json['senderId'] ?? '').toString(),
        senderName: (json['senderName'] ?? '').toString(),
        text: (json['text'] ?? '').toString(),
        fileUrl: json['fileUrl'] as String?,
        fileName: json['fileName'] as String?,
        fileType: json['fileType'] as String?,
        createdAt: json['createdAt'] as String?,
      );
}

class VideoCallController extends ChangeNotifier {
  VideoCallController({
    required this.appointmentId,
    Map<String, dynamic>? initialAppointment,
    Map<String, dynamic>? initialDoctor,
    Map<String, dynamic>? initialPatient,
    String initialRole = '',
    this.onCompletedByPeer,
  })  : appt = initialAppointment,
        _initialDoctor = initialDoctor,
        _initialPatient = initialPatient,
        _initialRole = initialRole,
        activeRole = initialRole,
        apptLoading = initialAppointment == null;

  final String appointmentId;
  final Map<String, dynamic>? _initialDoctor;
  final Map<String, dynamic>? _initialPatient;
  final String _initialRole;
  final SocketService _socket = SocketService.instance;

  /// Called ~4s after the peer marks the appointment complete (patient side
  /// only) so the widget can navigate away. Kept as a callback instead of a
  /// Navigator call here, since the controller has no BuildContext.
  final VoidCallback? onCompletedByPeer;

  // ── Renderers (equivalent of the two <video> elements) ────────────────
  final RTCVideoRenderer mainRenderer = RTCVideoRenderer();
  final RTCVideoRenderer pipRenderer = RTCVideoRenderer();

  bool _disposed = false;
  bool _rendererReady = false;

  // ── Appointment ─────────────────────────────────────────────────────
  Map<String, dynamic>? appt;
  bool apptLoading;
  String apptError = '';
  String activeRole;
  bool _callSessionStarted = false;

  // This app only has a patient login flow (see class doc comment), so
  // there is never a logged-in doctor identity to attempt that role's
  // endpoint with, and a user identity is always present by the time this
  // screen is reachable (navigation requires being logged in already).
  bool get _hasUserIdentity => true;
  bool get _hasDoctorIdentity => false;

  Map<String, dynamic>? get _doctor {
    if (_initialDoctor != null && _initialDoctor.isNotEmpty) return _initialDoctor;
    final value = appt?['doctorId'];
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  Map<String, dynamic>? get _user {
    if (_initialPatient != null && _initialPatient.isNotEmpty) return _initialPatient;
    final value = appt?['patientId'];
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  String get doctorId => (_doctor?['_id'] ?? _doctor?['id'] ?? '').toString();
  String get userId => (_user?['_id'] ?? '').toString();

  String get apptDoctorId {
    final d = appt?['doctorId'];
    if (d is Map) return (d['_id'] ?? '').toString();
    return (d ?? '').toString();
  }

  String get apptPatientId {
    final p = appt?['patientId'];
    if (p is Map) return (p['_id'] ?? '').toString();
    return (p ?? '').toString();
  }

  /// Matches VideoCall.jsx exactly: gated purely on `confirmed`. (A prior
  /// port of this screen also allowed `assigned`, an unauthorized deviation
  /// from the backend's own semantics — removed.)
  bool get canJoinConsultation => appt?['status'] == 'confirmed';

  bool get isDoctor {
    if (activeRole.isNotEmpty) return activeRole == 'doctor';
    if (doctorId.isNotEmpty && apptDoctorId.isNotEmpty && doctorId == apptDoctorId) {
      return true;
    }
    if (userId.isNotEmpty && apptPatientId.isNotEmpty && userId == apptPatientId) {
      return false;
    }
    return _hasDoctorIdentity && !_hasUserIdentity;
  }

  Map<String, String> get currentUser {
    if (isDoctor) {
      return {
        'id': doctorId.isEmpty ? 'doctor' : doctorId,
        'name': (_doctor?['name'] ?? 'Doctor').toString(),
      };
    }
    return {
      'id': userId.isEmpty ? 'user' : userId,
      'name': (_user?['name'] ?? 'Patient').toString(),
    };
  }

  Map<String, dynamic>? get otherParty {
    final a = appt;
    if (a == null) return null;
    if (isDoctor) {
      final patient = a['patientId'];
      final name = (patient is Map ? patient['name'] : null) ?? 'Unknown Patient';
      return {
        'label': 'Patient',
        'name': name,
        'sub': a['problem'] ?? '',
        'initial': (name is String && name.isNotEmpty) ? name[0].toUpperCase() : 'P',
      };
    }
    final doc = a['doctorId'];
    final docName = (doc is Map ? doc['name'] : null) ?? 'Unknown';
    return {
      'label': 'Doctor',
      'name': 'Dr. $docName',
      'sub': (doc is Map ? doc['email'] : null) ?? '',
      'initial': (docName is String && docName.isNotEmpty) ? docName[0].toUpperCase() : 'D',
    };
  }

  // ── Media / peer connection ─────────────────────────────────────────
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  RTCPeerConnection? _pc;
  Completer<bool> _localReady = Completer<bool>();
  bool _isPolitePeer = false;

  // ── Perfect negotiation state ────────────────────────────────────────
  bool _makingOffer = false;
  bool _ignoreOffer = false;
  bool _settingRemoteAnswerPending = false;
  final List<dynamic> _pendingRemoteCandidates = [];
  Timer? _ignoreOfferResetTimer;

  // ── Reconnect / ICE-restart machinery ───────────────────────────────
  Timer? _iceRestartTimer;
  Timer? _connectionFailTimer;
  Timer? _reconnectStallTimer;
  bool _restartRequestInFlight = false;
  int _iceRecoveryAttempts = 0;
  DateTime _lastIceRecoveryAt = DateTime.fromMillisecondsSinceEpoch(0);
  String _joinedSocketId = '';
  Timer? _joinTimeoutTimer;
  bool reconnectStalled = false;
  // Mirrors VideoCall.jsx's hasConnectedOnceRef — distinguishes the first
  // "Establishing secure connection..." from a later "Reconnecting..." on
  // the waiting overlay.
  bool hasConnectedOnce = false;
  bool retryingMedia = false;

  // ── Call lifecycle ────────────────────────────────────────────────────
  bool _completedFlag = false;
  Timer? _callTimer;
  Timer? _heartbeatTimer;
  Timer? _statsTimer;
  bool isReady = false;
  bool peerJoined = false;
  bool peerLeft = false;
  bool inCall = false;
  bool isRemoteConnected = false;
  String connectionState = 'idle';
  int callDuration = 0;
  bool isMuted = false;
  bool isCamOff = false;
  bool isSwapped = false;
  bool isScreenSharing = false;
  MediaStream? _screenStream;
  bool _screenShareStartInProgress = false;
  bool _screenShareStopInProgress = false;
  bool camError = false;
  String camErrorReason = '';
  // idle | checking | ready | failed — mirrors React's `deviceCheck.status`.
  String deviceCheckStatus = 'idle';
  String deviceCheckCamera = 'unknown';
  String deviceCheckMicrophone = 'unknown';
  String deviceCheckSpeaker = 'unknown';
  bool completing = false;
  String inlineError = '';
  Timer? _inlineErrorTimer;
  bool showCompletedOverlay = false;

  // ── Chat ──────────────────────────────────────────────────────────────
  bool chatOpen = false;
  final List<ChatMessage> messages = [];
  int unreadCount = 0;
  bool uploadingFile = false;

  // ── Prescription notification (patient-facing toast) ───────────────────
  Map<String, dynamic>? prescriptionNotif;
  Timer? _prescriptionTimer;

  String iceConfigError = '';
  bool _fetchingIceConfig = false;

  // ─────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────

  Future<void> init() async {
    await mainRenderer.initialize();
    await pipRenderer.initialize();
    _rendererReady = true;
    if (_disposed) return;

    if (appt != null) {
      apptLoading = false;
      notifyListeners();
      _afterApptLoaded();
    }
    await fetchAppointment();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(performCleanup());
    if (_rendererReady) {
      mainRenderer.dispose();
      pipRenderer.dispose();
    }
    _inlineErrorTimer?.cancel();
    _prescriptionTimer?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────
  // Appointment fetch (role-aware dual-endpoint fallback)
  // ─────────────────────────────────────────────────────────────────────

  Future<void> fetchAppointment() async {
    if (appointmentId.isEmpty) {
      apptError = 'No appointment ID found.';
      apptLoading = false;
      notifyListeners();
      return;
    }

    apptLoading = true;
    apptError = '';
    notifyListeners();

    Object? lastError;
    final roleAttempts = _initialRole == 'doctor'
        ? ['doctor', 'user']
        : _initialRole == 'user'
            ? ['user', 'doctor']
            : (_hasDoctorIdentity && !_hasUserIdentity)
                ? ['doctor']
                : (_hasUserIdentity && !_hasDoctorIdentity)
                    ? ['user']
                    : ['doctor', 'user'];

    for (final role in roleAttempts) {
      if (role == 'doctor' && !_hasDoctorIdentity) continue;
      if (role == 'user' && !_hasUserIdentity) continue;

      try {
        final endpoint = role == 'doctor'
            ? '/api/appointments/doctor/$appointmentId'
            : '/api/appointments/patient/$appointmentId';
        final data = await ApiService.instance.get(endpoint);
        if (_disposed) return;
        appt = Map<String, dynamic>.from(data as Map);
        activeRole = role;
        apptLoading = false;
        notifyListeners();
        _afterApptLoaded();
        return;
      } catch (err) {
        lastError = err;
      }
    }

    if (_disposed) return;
    apptError = (!_hasUserIdentity && !_hasDoctorIdentity)
        ? 'Please login to access this appointment.'
        : (lastError?.toString() ?? 'Could not load appointment.');
    apptLoading = false;
    notifyListeners();
  }

  void _afterApptLoaded() {
    if (canJoinConsultation && !_callSessionStarted) {
      _callSessionStarted = true;
      unawaited(startCallSession());
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // WebRTC + socket session
  // ─────────────────────────────────────────────────────────────────────

  Future<void> startCallSession() async {
    if (_fetchingIceConfig) return;
    _fetchingIceConfig = true;
    final iceSetup = await fetchIceServerConfig();
    _fetchingIceConfig = false;
    if (_disposed) return;

    if (!iceSetup.isUsable) {
      iceConfigError = iceSetup.error;
      apptError = 'Video consultation is not configured: ${iceSetup.error}';
      notifyListeners();
      return;
    }
    iceConfigError = '';

    _completedFlag = false;
    _pendingRemoteCandidates.clear();
    _ignoreOffer = false;
    _settingRemoteAnswerPending = false;
    _iceRestartTimer?.cancel();
    _iceRestartTimer = null;
    _ignoreOfferResetTimer?.cancel();
    _ignoreOfferResetTimer = null;
    _reconnectStallTimer?.cancel();
    _reconnectStallTimer = null;
    reconnectStalled = false;
    _localReady = Completer<bool>();
    _isPolitePeer = isDoctor;

    if (_pc != null) {
      await _pc!.close();
      _pc = null;
    }

    final pc = await createPeerConnection(iceSetup.config);
    if (_disposed) {
      await pc.close();
      return;
    }
    _pc = pc;
    _logEvent('peer_connection_created', {
      'iceServerCount': (iceSetup.config['iceServers'] as List).length,
      'hasTurn': iceSetup.hasTurn,
    });

    final remoteStream = await createLocalMediaStream('remote');
    _remoteStream = remoteStream;
    mainRenderer.srcObject = remoteStream;

    pc.onTrack = (event) => unawaited(_handleTrack(event, remoteStream));
    pc.onIceCandidate = _handleLocalIceCandidate;
    pc.onConnectionState = _handleConnectionStateChange;
    pc.onIceConnectionState = _handleIceConnectionStateChange;

    _registerSocketListeners();

    unawaited(_acquireLocalMedia(pc));

    if (_socket.connected) {
      _emitOnlineAndJoinRoom();
    } else {
      _socket.connect();
    }
  }

  Future<void> _acquireLocalMedia(RTCPeerConnection pc) async {
    try {
      deviceCheckStatus = 'checking';
      notifyListeners();

      final summary = await _deviceCheckSummary();
      deviceCheckCamera = summary['camera'] ?? 'unknown';
      deviceCheckMicrophone = summary['microphone'] ?? 'unknown';
      deviceCheckSpeaker = summary['speaker'] ?? 'unknown';
      notifyListeners();
      _logEvent('device_check', summary);

      final stream = await _getConsultationMediaStream();
      if (_disposed || _pc != pc) {
        for (final t in stream.getTracks()) {
          await t.stop();
        }
        if (!_localReady.isCompleted) _localReady.complete(false);
        return;
      }

      await _attachLocalMediaStream(stream, pc);

      isReady = true;
      camError = false;
      camErrorReason = '';
      deviceCheckStatus = 'ready';
      notifyListeners();
      _logEvent('media_ready', {
        'audioTracks': stream.getAudioTracks().length,
        'videoTracks': stream.getVideoTracks().length,
      });

      if (_socket.connected) _emitOnlineAndJoinRoom();

      if (!isDoctor && peerJoined) {
        Timer(const Duration(milliseconds: 300), () {
          if (_disposed || _pc != pc) return;
          if (_isConnectedState(pc)) return;
          unawaited(_createAndSendOffer(iceRestart: inCall));
        });
      }
      if (!_localReady.isCompleted) _localReady.complete(true);
    } catch (err) {
      debugPrint('[video-call] media permission failed: $err');
      _logEvent('media_permission_failed', {'error': err.toString()});
      if (!_disposed) {
        camError = true;
        camErrorReason = _mediaErrorMessage(err);
        deviceCheckStatus = 'failed';
        notifyListeners();
      }
      if (!_localReady.isCompleted) _localReady.complete(false);
    }
  }

  Future<Map<String, dynamic>> _deviceCheckSummary() async {
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      return {
        'camera': devices.any((d) => d.kind == 'videoinput') ? 'available' : 'missing',
        'microphone': devices.any((d) => d.kind == 'audioinput') ? 'available' : 'missing',
        'speaker': devices.any((d) => d.kind == 'audiooutput') ? 'available' : 'unknown',
      };
    } catch (_) {
      return {'camera': 'unknown', 'microphone': 'unknown', 'speaker': 'unknown'};
    }
  }

  /// Same 3-step fallback chain as `getConsultationMediaStream` in
  /// VideoCall.jsx: full constraints -> basic audio+video -> split
  /// audio-only/video-only so a call still connects if only one device
  /// grants permission.
  Future<MediaStream> _getConsultationMediaStream() async {
    try {
      return await navigator.mediaDevices.getUserMedia(kMediaConstraints);
    } catch (firstErr) {
      debugPrint('[video-call] high-quality media failed, trying basic: $firstErr');
      try {
        return await navigator.mediaDevices.getUserMedia({'audio': true, 'video': true});
      } catch (secondErr) {
        debugPrint('[video-call] basic media failed, trying split devices: $secondErr');
        final partial = await createLocalMediaStream('partial');
        Object lastErr = secondErr;

        try {
          final videoOnly = await navigator.mediaDevices
              .getUserMedia({'audio': false, 'video': kMediaConstraints['video']});
          for (final track in videoOnly.getTracks()) {
            await partial.addTrack(track);
          }
        } catch (videoErr) {
          debugPrint('[video-call] video-only media failed: $videoErr');
          lastErr = videoErr;
        }

        try {
          final audioOnly = await navigator.mediaDevices
              .getUserMedia({'audio': kMediaConstraints['audio'], 'video': false});
          for (final track in audioOnly.getTracks()) {
            await partial.addTrack(track);
          }
        } catch (audioErr) {
          debugPrint('[video-call] audio-only media failed: $audioErr');
          lastErr = audioErr;
        }

        if (partial.getTracks().isNotEmpty) return partial;
        throw lastErr;
      }
    }
  }

  String _mediaErrorMessage(Object err) {
    final msg = err.toString();
    if (msg.contains('NotAllowedError') || msg.contains('PermissionDeniedError')) {
      return 'Camera/microphone permission was denied. Allow access in your device settings, then retry.';
    }
    if (msg.contains('NotFoundError') || msg.contains('DevicesNotFoundError')) {
      return 'No camera or microphone was found on this device.';
    }
    if (msg.contains('NotReadableError') || msg.contains('TrackStartError')) {
      return 'Your camera or microphone is already in use by another app. Close it and retry.';
    }
    return 'Camera or microphone access failed. Check app permissions and reload.';
  }

  Future<bool> _attachLocalMediaStream(MediaStream stream, RTCPeerConnection pc) async {
    if (pc.signalingState == RTCSignalingState.RTCSignalingStateClosed) return false;

    final previousStream = _localStream;
    for (final track in stream.getVideoTracks()) {
      track.enabled = !isCamOff;
    }
    for (final track in stream.getAudioTracks()) {
      track.enabled = !isMuted;
    }

    _localStream = stream;
    pipRenderer.srcObject = stream;

    await _ensureMediaTransceivers(
      pc,
      audio: stream.getAudioTracks().isEmpty,
      video: stream.getVideoTracks().isEmpty,
    );

    for (final track in stream.getTracks()) {
      final kind = track.kind ?? '';
      final existingSender = await _getSenderForKind(pc, kind);
      RTCRtpSender activeSender;
      if (existingSender != null) {
        await existingSender.replaceTrack(track);
        activeSender = existingSender;
      } else {
        activeSender = await pc.addTrack(track, stream);
      }
      await _tuneSenderQuality(
        activeSender,
        maxBitrate: kind == 'video' ? kCameraBitrate : kVoiceBitrate,
        maxFramerate: kind == 'video' ? 30 : null,
      );
    }

    if (previousStream != null && previousStream != stream) {
      for (final track in previousStream.getTracks()) {
        await track.stop();
      }
    }

    _assignStreams(isSwapped);
    return true;
  }

  Future<RTCRtpSender?> _getSenderForKind(RTCPeerConnection pc, String kind) async {
    final senders = await pc.getSenders();
    for (final s in senders) {
      if (s.track?.kind == kind) return s;
    }
    final transceivers = await pc.getTransceivers();
    for (final t in transceivers) {
      if (t.receiver.track?.kind == kind) return t.sender;
    }
    return null;
  }

  Future<void> _ensureMediaTransceivers(
    RTCPeerConnection pc, {
    bool audio = true,
    bool video = true,
  }) async {
    if (pc.signalingState == RTCSignalingState.RTCSignalingStateClosed) return;
    final transceivers = await pc.getTransceivers();
    bool hasKind(String kind) => transceivers.any(
          (t) => t.sender.track?.kind == kind || t.receiver.track?.kind == kind,
        );
    if (audio && !hasKind('audio')) {
      await pc.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendRecv),
      );
    }
    if (video && !hasKind('video')) {
      await pc.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendRecv),
      );
    }
  }

  Future<void> _tuneSenderQuality(
    RTCRtpSender sender, {
    int? maxBitrate,
    int? maxFramerate,
  }) async {
    if (sender.track == null) return;
    try {
      final params = sender.parameters;
      final encodings = params.encodings ?? [RTCRtpEncoding()];
      final encoding = encodings.isNotEmpty ? encodings.first : RTCRtpEncoding();
      if (maxBitrate != null) encoding.maxBitrate = maxBitrate;
      if (maxFramerate != null) encoding.maxFramerate = maxFramerate;
      params.encodings = [encoding, ...encodings.skip(1)];
      await sender.setParameters(params);
    } catch (_) {
      // Mirrors the swallowed try/catch in tuneSenderQuality in VideoCall.jsx.
    }
  }

  void _assignStreams(bool swapped) {
    mainRenderer.srcObject = swapped ? _localStream : _remoteStream;
    pipRenderer.srcObject = swapped ? _remoteStream : _localStream;
  }

  Future<void> _handleTrack(RTCTrackEvent event, MediaStream remoteStream) async {
    final incoming = event.streams.isNotEmpty
        ? event.streams.expand((s) => s.getTracks()).toList()
        : [event.track];

    for (final track in incoming) {
      // The sender only ever sends one track per kind, so a new track of a
      // given kind always replaces the previous one for that kind — matters
      // after the remote peer's connection is recreated (e.g. they
      // reconnected): their new track has a different id and wouldn't dedupe
      // by id, so without pruning the dead old track stays alongside the new
      // live one and the renderer can end up stuck on the wrong track.
      final stale = remoteStream
          .getTracks()
          .where((t) => t.kind == track.kind && t.id != track.id)
          .toList();
      for (final s in stale) {
        await remoteStream.removeTrack(s);
      }
      if (remoteStream.getTrackById(track.id ?? '') == null) {
        await remoteStream.addTrack(track);
      }
    }

    if (_disposed) return;
    _logEvent('remote_track_received', {
      'tracks': incoming.map((t) => t.kind).toList(),
      'streamCount': event.streams.length,
    });
    _assignStreams(isSwapped);
    isRemoteConnected = true;
    peerLeft = false;
    notifyListeners();
  }

  void _handleLocalIceCandidate(RTCIceCandidate candidate) {
    final raw = candidate.candidate;
    if (raw == null || raw.isEmpty) {
      _logEvent('ice_gathering_complete', {});
      return;
    }
    _logEvent('ice_candidate_gathered', {'type': _iceCandidateType(raw)});
    _socket.emit('ice-candidate', {
      'appointmentId': appointmentId,
      'candidate': candidate.toMap(),
    });
  }

  String _iceCandidateType(String candidate) {
    if (candidate.contains(' typ host')) return 'host';
    if (candidate.contains(' typ srflx')) return 'srflx';
    if (candidate.contains(' typ relay')) return 'relay';
    if (candidate.contains(' typ prflx')) return 'prflx';
    return 'unknown';
  }

  bool _isConnectedState(RTCPeerConnection pc) {
    return pc.connectionState == RTCPeerConnectionState.RTCPeerConnectionStateConnected ||
        pc.iceConnectionState == RTCIceConnectionState.RTCIceConnectionStateConnected ||
        pc.iceConnectionState == RTCIceConnectionState.RTCIceConnectionStateCompleted;
  }

  void _handleConnectionStateChange(RTCPeerConnectionState state) {
    if (_disposed) return;
    if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
      _iceRestartTimer?.cancel();
      _iceRestartTimer = null;
      _connectionFailTimer?.cancel();
      _restartRequestInFlight = false;
      _iceRecoveryAttempts = 0;
      _clearReconnectStallWatch();
      connectionState = 'connected';
      isRemoteConnected = true;
      hasConnectedOnce = true;
      notifyListeners();
      _markInCall();
      final pc = _pc;
      if (pc != null) _startStatsCollection(pc);
    } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnecting) {
      connectionState = 'connecting';
      notifyListeners();
      _startConnectionWatchdog();
    } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
        state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
      _logEvent('peer_connection_unhealthy', {'state': state.toString()});
      connectionState = 'disconnected';
      isRemoteConnected = false;
      notifyListeners();
      _scheduleIceRestart();
    }
  }

  // Fallback for platforms where onConnectionState fires late or not at all.
  void _handleIceConnectionStateChange(RTCIceConnectionState state) {
    if (_disposed) return;
    if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
        state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
      _iceRestartTimer?.cancel();
      _iceRestartTimer = null;
      _connectionFailTimer?.cancel();
      _restartRequestInFlight = false;
      _iceRecoveryAttempts = 0;
      _clearReconnectStallWatch();
      connectionState = 'connected';
      isRemoteConnected = true;
      hasConnectedOnce = true;
      notifyListeners();
      _markInCall();
      final pc = _pc;
      if (pc != null) _startStatsCollection(pc);
    } else if (state == RTCIceConnectionState.RTCIceConnectionStateChecking) {
      if (!inCall) {
        connectionState = 'connecting';
        notifyListeners();
      }
      _startConnectionWatchdog();
    } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
      _logEvent('ice_connection_failed', {});
      connectionState = 'disconnected';
      isRemoteConnected = false;
      notifyListeners();
      _scheduleIceRestart();
    } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
      _logEvent('ice_connection_disconnected', {});
      connectionState = 'connecting';
      notifyListeners();
      _scheduleIceRestart();
    }
  }

  void _markInCall() {
    if (inCall) return;
    inCall = true;
    notifyListeners();

    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      callDuration++;
      notifyListeners();
    });

    // A live call has no other API traffic, so the inactivity timer + short-
    // lived access token can expire mid-consultation. Refresh on a cadence
    // well under both timeouts, same as VideoCall.jsx's heartbeat effect.
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 4), (_) {
      ApiService.instance
          .post('/api/auth/refresh', {'authRole': isDoctor ? 'doctor' : 'user'})
          .catchError((_) => null);
    });
  }

  // ── Perfect negotiation (glare handling) ────────────────────────────

  void _resetIgnoredOffer() {
    _ignoreOfferResetTimer?.cancel();
    _ignoreOfferResetTimer = null;
    _ignoreOffer = false;
  }

  void _markIgnoredOffer() {
    _ignoreOffer = true;
    _ignoreOfferResetTimer?.cancel();
    _ignoreOfferResetTimer = Timer(
      const Duration(milliseconds: kIceRestartDelayMs * 2),
      () {
        _ignoreOffer = false;
        _ignoreOfferResetTimer = null;
      },
    );
  }

  Future<void> _flushPendingIceCandidates() async {
    final pc = _pc;
    if (pc == null) return;
    final remoteDesc = await pc.getRemoteDescription();
    if (remoteDesc == null) return;
    final pending = List<dynamic>.from(_pendingRemoteCandidates);
    _pendingRemoteCandidates.clear();
    for (final candidateMap in pending) {
      try {
        await pc.addCandidate(RTCIceCandidate(
          candidateMap['candidate'],
          candidateMap['sdpMid'],
          candidateMap['sdpMLineIndex'],
        ));
      } catch (err) {
        debugPrint('[video-call] queued ICE candidate rejected: $err');
      }
    }
  }

  Future<bool> _createAndSendOffer({bool iceRestart = false}) async {
    final pc = _pc;
    if (pc == null || _disposed || _makingOffer) {
      debugPrint('[video-call] offer skipped: pc=$_pc disposed=$_disposed makingOffer=$_makingOffer');
      return false;
    }
    if (!isReady) {
      debugPrint('[video-call] offer skipped: not ready');
      return false;
    }
    if (pc.signalingState != RTCSignalingState.RTCSignalingStateStable) {
      debugPrint('[video-call] offer skipped: signalingState=${pc.signalingState}');
      return false;
    }

    try {
      _makingOffer = true;
      _resetIgnoredOffer();
      final offer = await pc.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': true,
        if (iceRestart) 'iceRestart': true,
      });
      if (_disposed || pc.signalingState == RTCSignalingState.RTCSignalingStateClosed) {
        return false;
      }
      await pc.setLocalDescription(offer);
      _logEvent('offer_sent', {'iceRestart': iceRestart, 'sdpLength': offer.sdp?.length ?? 0});
      _socket.emit('video-offer', {
        'appointmentId': appointmentId,
        'offer': {'sdp': offer.sdp, 'type': offer.type},
      });
      if (iceRestart) _logEvent('ice_restart_offer_sent', {});
      return true;
    } catch (err) {
      debugPrint('[video-call] ${iceRestart ? "ICE restart offer" : "offer"} failed: $err');
      if (iceRestart) _logEvent('ice_restart_offer_failed', {'error': err.toString()});
      return false;
    } finally {
      _makingOffer = false;
    }
  }

  // ── Connection watchdog / ICE-restart recovery ──────────────────────

  void _startConnectionWatchdog() {
    _connectionFailTimer?.cancel();
    _connectionFailTimer = Timer(const Duration(milliseconds: kConnectionFailTimeoutMs), () {
      final pc = _pc;
      if (_disposed || pc == null) return;
      if (_isConnectedState(pc)) return;
      debugPrint('[video-call] connection establishment timed out; scheduling ICE recovery');
      _scheduleIceRestart();
    });
  }

  void _clearReconnectStallWatch() {
    _reconnectStallTimer?.cancel();
    _reconnectStallTimer = null;
    if (reconnectStalled) {
      reconnectStalled = false;
      notifyListeners();
    }
  }

  void _startReconnectStallWatch(int delayMs) {
    if (_reconnectStallTimer != null) return;
    _reconnectStallTimer = Timer(Duration(milliseconds: delayMs), () {
      _reconnectStallTimer = null;
      final pc = _pc;
      if (_disposed || pc == null) return;
      if (_isConnectedState(pc)) return;
      reconnectStalled = true;
      notifyListeners();
    });
  }

  void _startJoinTimeout() {
    _joinTimeoutTimer?.cancel();
    if (peerJoined) return;
    _joinTimeoutTimer = Timer(const Duration(milliseconds: kPeerJoinTimeoutMs), () {
      if (_disposed || peerJoined || inCall) return;
      _logEvent('join_timed_out', {});
      _showInlineMessage(
        'The other participant has not joined yet. The call will retry automatically.',
        const Duration(seconds: 6),
      );
      reconnectStalled = true;
      notifyListeners();
    });
  }

  void _clearJoinTimeout() {
    _joinTimeoutTimer?.cancel();
    _joinTimeoutTimer = null;
  }

  void _requestPeerIceRestart() {
    if (_restartRequestInFlight) return;
    _restartRequestInFlight = true;
    _socket.emit('ice-restart-request', {'appointmentId': appointmentId});
    _logEvent('ice_restart_requested_from_peer', {});
    Timer(const Duration(milliseconds: kIceRestartDelayMs * 2), () {
      _restartRequestInFlight = false;
    });
  }

  void _scheduleIceRestart() {
    if (_disposed || _iceRestartTimer != null) return;
    _iceRestartTimer = Timer(const Duration(milliseconds: kIceRestartDelayMs), () async {
      _iceRestartTimer = null;
      final pc = _pc;
      if (_disposed || pc == null) return;
      if (_isConnectedState(pc)) return;

      final now = DateTime.now();
      if (now.difference(_lastIceRecoveryAt).inMilliseconds > kIceRecoveryCooldownMs) {
        _iceRecoveryAttempts = 0;
      }
      _lastIceRecoveryAt = now;

      if (_iceRecoveryAttempts >= kIceMaxRecoveryAttempts) {
        _logEvent('ice_recovery_exhausted', {'attempts': _iceRecoveryAttempts});
        _requestPeerIceRestart();
        return;
      }

      _iceRecoveryAttempts += 1;
      _logEvent('ice_recovery_attempt', {'attempts': _iceRecoveryAttempts});

      if (_isPolitePeer) {
        _requestPeerIceRestart();
        return;
      }
      await _createAndSendOffer(iceRestart: true);
    });
  }

  /// Manual escape hatch: tears down and rebuilds the RTCPeerConnection and
  /// rejoins the room from scratch. Mirrors `forceReconnect`'s nonce bump in
  /// VideoCall.jsx.
  Future<void> forceReconnect() async {
    reconnectStalled = false;
    notifyListeners();
    await _teardownSession(leaveRoom: false);
    await startCallSession();
  }

  /// No direct React equivalent (browser tabs don't get suspended the same
  /// way), but a real mobile gap: the OS can freeze networking while the app
  /// is backgrounded, leaving the socket client's own reconnection backoff
  /// timer stale by the time the app returns to the foreground. Proactively
  /// kicking the socket on resume starts recovery immediately instead of
  /// waiting out whatever backoff delay was in flight when the app was
  /// backgrounded.
  void handleAppResumed() {
    final pc = _pc;
    if (_disposed || pc == null) return;
    if (_isConnectedState(pc)) return;
    _socket.connect();
  }

  Future<void> retryMediaPermissions() async {
    final pc = _pc;
    if (pc == null || pc.signalingState == RTCSignalingState.RTCSignalingStateClosed) {
      camError = true;
      camErrorReason =
          'The call connection is no longer active. Rejoin the consultation and try again.';
      notifyListeners();
      return;
    }

    camError = false;
    deviceCheckStatus = 'checking';
    retryingMedia = true;
    notifyListeners();

    try {
      final summary = await _deviceCheckSummary();
      deviceCheckCamera = summary['camera'] ?? 'unknown';
      deviceCheckMicrophone = summary['microphone'] ?? 'unknown';
      deviceCheckSpeaker = summary['speaker'] ?? 'unknown';
      _logEvent('media_retry_started', summary);

      final stream = await _getConsultationMediaStream();
      await _attachLocalMediaStream(stream, pc);

      isReady = true;
      camError = false;
      camErrorReason = '';
      deviceCheckStatus = 'ready';
      retryingMedia = false;
      notifyListeners();
      _logEvent('media_retry_succeeded', {
        'audioTracks': stream.getAudioTracks().length,
        'videoTracks': stream.getVideoTracks().length,
      });
      _emitOnlineAndJoinRoom();

      if (pc.signalingState == RTCSignalingState.RTCSignalingStateHaveRemoteOffer) {
        final answer = await pc.createAnswer({
          'offerToReceiveAudio': true,
          'offerToReceiveVideo': true,
        });
        await pc.setLocalDescription(answer);
        _socket.emit('video-answer', {
          'appointmentId': appointmentId,
          'answer': {'sdp': answer.sdp, 'type': answer.type},
        });
      }
    } catch (err) {
      camError = true;
      camErrorReason = _mediaErrorMessage(err);
      deviceCheckStatus = 'failed';
      retryingMedia = false;
      _logEvent('media_retry_failed', {'error': err.toString()});
      notifyListeners();
    }
  }

  // ── Socket signaling handlers ────────────────────────────────────────

  /// Flutter Web's socket_io_client v2 wraps event data as [payload, ackId]
  /// instead of passing the raw Map. Unwrap both formats transparently.
  Map<String, dynamic>? _toMap(dynamic data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is List && data.isNotEmpty && data[0] is Map) {
      return Map<String, dynamic>.from(data[0]);
    }
    return null;
  }

  Future<void> _handleOffer(dynamic raw) async {
    if (_disposed) return;
    final data = _toMap(raw);
    if (data == null) return;
    final offerMap = data['offer'];
    if (offerMap == null || offerMap is! Map) return;
    final pc = _pc;
    if (pc == null) return;

    try {
      connectionState = 'connecting';
      notifyListeners();

      final signalingState = pc.signalingState;
      final readyForOffer = !_makingOffer &&
          (signalingState == RTCSignalingState.RTCSignalingStateStable ||
              _settingRemoteAnswerPending);
      final offerCollision = !readyForOffer;
      final shouldIgnoreOffer = !_isPolitePeer && offerCollision;

      if (shouldIgnoreOffer) {
        _markIgnoredOffer();
        return;
      }
      _resetIgnoredOffer();

      if (offerCollision && signalingState == RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
        await pc.setLocalDescription(RTCSessionDescription('', 'rollback'));
      } else if (offerCollision) {
        return;
      }

      await pc.setRemoteDescription(RTCSessionDescription(
        offerMap['sdp'] as String?,
        offerMap['type'] as String?,
      ));
      _resetIgnoredOffer();
      await _flushPendingIceCandidates();

      final localReady = await _localReady.future;
      if (_disposed) return;
      if (!localReady) {
        camError = true;
        camErrorReason =
            'Allow camera or microphone access, then retry to join the consultation.';
        notifyListeners();
        return;
      }

      final answer = await pc.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': true,
      });
      await pc.setLocalDescription(answer);
      _socket.emit('video-answer', {
        'appointmentId': appointmentId,
        'answer': {'sdp': answer.sdp, 'type': answer.type},
      });
      _markInCall();
    } catch (err) {
      debugPrint('[video-call] offer error: $err');
    }
  }

  Future<void> _handleAnswer(dynamic raw) async {
    if (_disposed) return;
    final data = _toMap(raw);
    if (data == null) return;
    final answerMap = data['answer'];
    if (answerMap == null || answerMap is! Map) return;
    final pc = _pc;
    if (pc == null) return;

    try {
      if (pc.signalingState != RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
        return;
      }
      _settingRemoteAnswerPending = true;
      _logEvent('answer_received', {'sdpLength': answerMap['sdp']?.toString().length ?? 0});
      await pc.setRemoteDescription(RTCSessionDescription(
        answerMap['sdp'] as String?,
        answerMap['type'] as String?,
      ));
      _resetIgnoredOffer();
      await _flushPendingIceCandidates();
      _markInCall();
    } catch (err) {
      debugPrint('[video-call] answer error: $err');
      _logEvent('answer_error', {'error': err.toString()});
    } finally {
      _settingRemoteAnswerPending = false;
    }
  }

  Future<void> _handleIce(dynamic raw) async {
    if (_disposed) return;
    final data = _toMap(raw);
    if (data == null) return;
    final candidateMap = data['candidate'];
    if (candidateMap == null || candidateMap is! Map) return;
    final pc = _pc;
    if (pc == null) return;

    final rawCandidate = candidateMap['candidate']?.toString() ?? '';
    _logEvent('ice_candidate_received', {
      'type': rawCandidate.isNotEmpty ? _iceCandidateType(rawCandidate) : 'end-of-candidates',
    });

    final remoteDesc = await pc.getRemoteDescription();
    if (remoteDesc == null) {
      if (_ignoreOffer) return;
      _pendingRemoteCandidates.add(candidateMap);
      return;
    }
    try {
      await pc.addCandidate(RTCIceCandidate(
        candidateMap['candidate'] as String?,
        candidateMap['sdpMid'] as String?,
        candidateMap['sdpMLineIndex'] as int?,
      ));
    } catch (err) {
      if (_ignoreOffer) return;
      debugPrint('[video-call] ICE candidate rejected: $err');
    }
  }

  Future<void> _handleIceRestartRequest(dynamic _) async {
    if (_disposed || isDoctor || !isReady) return;
    _logEvent('ice_restart_request_received', {});
    await _createAndSendOffer(iceRestart: true);
  }

  void _handlePeerJoined(dynamic raw) {
    if (_disposed) return;
    _clearJoinTimeout();
    final data = _toMap(raw);
    final resumedCall = data?['resumedCall'] == true;
    peerJoined = true;
    peerLeft = false;
    notifyListeners();

    final pc = _pc;
    if (isReady && !inCall) {
      _startConnectionWatchdog();
      _startReconnectStallWatch(resumedCall ? 8000 : 20000);
    }

    if (!isDoctor && isReady && pc != null) {
      Timer(const Duration(milliseconds: 300), () {
        if (_disposed || _pc != pc) return;
        if (_isConnectedState(pc)) return;
        unawaited(_createAndSendOffer(iceRestart: inCall));
      });
    }

    // Doctor never self-initiates an offer (polite peer), so recovery after
    // a doctor-side reconnect otherwise depends on the connection watchdog.
    // When the server confirms this room was already active (resumedCall),
    // nudge the patient to renegotiate immediately instead of waiting.
    if (isDoctor && resumedCall && isReady && pc != null) {
      Timer(const Duration(milliseconds: 500), () {
        if (_disposed || _pc != pc) return;
        if (_isConnectedState(pc)) return;
        _requestPeerIceRestart();
      });
    }
  }

  void _handleParticipantLeft(dynamic _) {
    if (_disposed) return;
    _clearJoinTimeout();
    peerJoined = false;
    isRemoteConnected = false;
    connectionState = 'disconnected';
    peerLeft = true;
    notifyListeners();
    _clearReconnectStallWatch();
  }

  void _handleChatMessage(dynamic raw) {
    if (_disposed) return;
    final data = _toMap(raw);
    if (data == null) {
      debugPrint('[video-call] chat_message received with non-Map data: $raw');
      return;
    }
    _logEvent('chat_received', {'senderId': data['senderId'], 'hasText': data['text'] is String && (data['text'] as String).isNotEmpty});
    messages.add(ChatMessage.fromJson(data));
    if (!chatOpen) unreadCount++;
    notifyListeners();
  }

  void _handleChatHistory(dynamic raw) {
    if (_disposed) return;
    final data = _toMap(raw);
    if (data == null) {
      debugPrint('[video-call] chat_history received with non-Map data: $raw');
      return;
    }
    if (data['appointmentId'] != appointmentId) {
      debugPrint('[video-call] chat_history mismatched appointmentId: expected=$appointmentId got=${data['appointmentId']}');
      return;
    }
    final list = data['messages'] as List<dynamic>? ?? [];
    _logEvent('chat_history_received', {'count': list.length});
    messages
      ..clear()
      ..addAll(list.map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m as Map))));
    notifyListeners();
  }

  void _handleApptUpdated(dynamic raw) {
    if (_disposed) return;
    final data = _toMap(raw);
    if (data == null) return;
    final status = data['status'];
    if ((status == 'complete' || status == 'completed') && !isDoctor) {
      showCompletedOverlay = true;
      notifyListeners();
      Timer(const Duration(seconds: 4), () {
        if (!_disposed) onCompletedByPeer?.call();
      });
    }
  }

  void _handleNewPrescription(dynamic raw) {
    if (_disposed || isDoctor) return;
    final data = _toMap(raw);
    if (data == null) return;
    prescriptionNotif = {'diagnosis': data['diagnosis']};
    notifyListeners();
    _prescriptionTimer?.cancel();
    _prescriptionTimer = Timer(const Duration(seconds: 10), () {
      if (_disposed) return;
      prescriptionNotif = null;
      notifyListeners();
    });
  }

  void _handleRoomDenied(dynamic data) {
    if (_disposed) return;
    final msg = (data is Map) ? data['msg']?.toString() : null;
    apptError = msg ?? 'Access to this call room was denied.';
    notifyListeners();
  }

  void _handleDuplicateSession(dynamic data) {
    if (_disposed) return;
    final pc = _pc;
    if (pc != null && pc.signalingState != RTCSignalingState.RTCSignalingStateClosed) {
      unawaited(pc.close());
    }
    _localStream?.getTracks().forEach((t) => unawaited(t.stop()));
    _localStream = null;
    final msg = (data is Map) ? data['msg']?.toString() : null;
    apptError = msg ?? 'Another consultation session was started elsewhere.';
    notifyListeners();
  }

  // ── Socket connection lifecycle ──────────────────────────────────────

  void _registerSocketListeners() {
    _socket.on('video-offer', _handleOffer);
    _socket.on('video-answer', _handleAnswer);
    _socket.on('ice-candidate', _handleIce);
    _socket.on('ice-restart-request', _handleIceRestartRequest);
    _socket.on('peer-joined', _handlePeerJoined);
    _socket.on('participant-left', _handleParticipantLeft);
    _socket.on('appointment-message', _handleChatMessage);
    _socket.on('appointment-chat-history', _handleChatHistory);
    _socket.on('appointment-updated', _handleApptUpdated);
    _socket.on('new-prescription', _handleNewPrescription);
    _socket.on('room-access-denied', _handleRoomDenied);
    _socket.on('duplicate-session', _handleDuplicateSession);
    _socket.on('connect', _handleSocketConnect);
    _socket.on('disconnect', _handleSocketDisconnect);
    _socket.on('connect_error', _handleSocketConnectError);
    _socket.onManager('reconnect', _handleSocketReconnect);
  }

  void _unregisterSocketListeners() {
    _socket.off('video-offer', _handleOffer);
    _socket.off('video-answer', _handleAnswer);
    _socket.off('ice-candidate', _handleIce);
    _socket.off('ice-restart-request', _handleIceRestartRequest);
    _socket.off('peer-joined', _handlePeerJoined);
    _socket.off('participant-left', _handleParticipantLeft);
    _socket.off('appointment-message', _handleChatMessage);
    _socket.off('appointment-chat-history', _handleChatHistory);
    _socket.off('appointment-updated', _handleApptUpdated);
    _socket.off('new-prescription', _handleNewPrescription);
    _socket.off('room-access-denied', _handleRoomDenied);
    _socket.off('duplicate-session', _handleDuplicateSession);
    _socket.off('connect', _handleSocketConnect);
    _socket.off('disconnect', _handleSocketDisconnect);
    _socket.off('connect_error', _handleSocketConnectError);
    _socket.offManager('reconnect', _handleSocketReconnect);
  }

  bool _emitOnlineAndJoinRoom() {
    if (!_socket.connected || !isReady) return false;
    if (_joinedSocketId == _socket.id) return true;

    _joinedSocketId = _socket.id ?? '';
    if (connectionState != 'connected') {
      connectionState = 'connecting';
      notifyListeners();
    }

    _startJoinTimeout();

    final activeUserId = isDoctor ? doctorId : userId;
    final activeRole = isDoctor ? 'doctor' : 'user';
    unawaited(_emitOnlineAndJoinRoomPayload(activeUserId, activeRole));
    return true;
  }

  /// Split out from `_emitOnlineAndJoinRoom` because fetching the token is
  /// async while the join dedup check above must stay synchronous. Explicit,
  /// role-scoped `token` on both emits — matches VideoCall.jsx: each event is
  /// handled independently and asynchronously on the server, so
  /// join-appointment-room can't assume user-online (emitted first) has
  /// already finished resolving identity from the connection-time auth
  /// snapshot alone (see server.js's resolveSocketIdentity). This app only
  /// ever authenticates as a patient today, so the connection-time handshake
  /// token is normally enough on its own — this is defense-in-depth so
  /// per-event identity resolution stays correct if that ever changes.
  Future<void> _emitOnlineAndJoinRoomPayload(String activeUserId, String role) async {
    final token = await const TokenStorageService().getToken() ?? '';

    if (activeUserId.isNotEmpty) {
      _socket.emit('user-online', {
        'userId': activeUserId,
        'role': role,
        'token': token,
      });
    }
    _socket.emit('join-appointment-room', {
      'appointmentId': appointmentId,
      'userId': activeUserId,
      'role': role,
      'token': token,
    });
    _logEvent('appointment_room_join_requested', {'socketId': _socket.id});
  }

  void _handleSocketConnect(dynamic _) {
    _emitOnlineAndJoinRoom();
  }

  void _handleSocketDisconnect(dynamic reason) {
    _joinedSocketId = '';
    if (_disposed) return;
    _logEvent('socket_disconnected_during_call', {'inCall': inCall});
    connectionState = 'disconnected';
    isRemoteConnected = false;
    notifyListeners();
  }

  void _handleSocketConnectError(dynamic err) {
    if (_disposed) return;
    _logEvent('socket_connect_error', {'error': err.toString()});
    if (!isReady) {
      _showInlineMessage(
        'Connection to the call service failed. Please check your internet and try again.',
        const Duration(seconds: 8),
      );
    }
  }

  void _handleSocketReconnect(dynamic _) {
    if (_disposed) return;
    _joinedSocketId = '';
    _emitOnlineAndJoinRoom();
    _logEvent('socket_reconnected_during_call', {
      'inCall': inCall,
      'role': isDoctor ? 'doctor' : 'user',
    });

    final pc = _pc;
    if (pc == null) return;

    if (isDoctor) {
      Timer(const Duration(milliseconds: 500), () {
        if (_disposed || !_socket.connected || _pc != pc) return;
        if (_isConnectedState(pc)) return;
        _requestPeerIceRestart();
      });
      return;
    }
    if (isReady) {
      Timer(const Duration(milliseconds: 500), () {
        if (_disposed || !_socket.connected || _pc != pc) return;
        if (_isConnectedState(pc)) return;
        unawaited(_createAndSendOffer(iceRestart: inCall));
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // Controls
  // ─────────────────────────────────────────────────────────────────────

  void toggleMute() {
    isMuted = !isMuted;
    _localStream?.getAudioTracks().forEach((t) => t.enabled = !isMuted);
    notifyListeners();
  }

  void toggleCamera() {
    isCamOff = !isCamOff;
    _localStream?.getVideoTracks().forEach((t) => t.enabled = !isCamOff);
    notifyListeners();
  }

  // ── Screen sharing ───────────────────────────────────────────────────
  // Ported from startScreenShare/stopScreenShare/toggleScreenShare in
  // VideoCall.jsx: replace the existing video sender's track with a
  // screen-capture track, then swap it back to the camera on stop.
  //
  // One real platform gap vs. the web version: browsers fire
  // `track.onended` when the OS-level share is stopped from outside the
  // page (e.g. the browser's "Stop sharing" bar). flutter_webrtc 1.5.2's
  // native MediaStreamTrack does not surface an equivalent callback, so
  // there is no reliable way to detect the user stopping the capture from
  // the platform's screen-recording control (Android's status-bar/quick-
  // settings "Stop", the iOS Control Center recording indicator) — only
  // the in-app "Stop" button reliably restores the camera. This is a
  // constraint of the plugin version, not something worth faking with a
  // callback that would never actually fire.

  Future<RTCRtpSender?> _videoSender() {
    final pc = _pc;
    if (pc == null) return Future.value(null);
    return _getSenderForKind(pc, 'video');
  }

  bool _backgroundExecutionEnabled = false;

  /// Android requires a running `mediaProjection`-typed foreground service
  /// for the duration of a MediaProjection capture, or getDisplayMedia
  /// throws a SecurityException — see AndroidManifest.xml. iOS's
  /// getDisplayMedia routes through in-process RPScreenRecorder and needs
  /// none of this, so it's a no-op there.
  Future<bool> _startBackgroundExecutionForScreenShare() async {
    // dart:io's Platform throws UnsupportedError on web if touched at all —
    // kIsWeb must short-circuit before Platform.isAndroid ever evaluates.
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final initialized = await FlutterBackground.initialize(
        androidConfig: const FlutterBackgroundAndroidConfig(
          notificationTitle: 'Humancare Connect',
          notificationText: 'Screen sharing is active in your consultation.',
          notificationImportance: AndroidNotificationImportance.normal,
        ),
      );
      if (!initialized) return false;
      _backgroundExecutionEnabled =
          await FlutterBackground.enableBackgroundExecution();
      return _backgroundExecutionEnabled;
    } catch (err) {
      debugPrint('[video-call] flutter_background init/enable failed: $err');
      return false;
    }
  }

  Future<void> _stopBackgroundExecutionForScreenShare() async {
    if (kIsWeb || !Platform.isAndroid || !_backgroundExecutionEnabled) return;
    _backgroundExecutionEnabled = false;
    try {
      await FlutterBackground.disableBackgroundExecution();
    } catch (err) {
      debugPrint('[video-call] flutter_background disable failed: $err');
    }
  }

  Future<void> startScreenShare() async {
    final pc = _pc;
    if (pc == null ||
        isScreenSharing ||
        _screenShareStartInProgress ||
        _screenShareStopInProgress) {
      return;
    }

    final sender = await _videoSender();
    if (sender == null) {
      _showInlineMessage(
        'Screen sharing requires an active video sender. Enable camera first, then try again.',
      );
      return;
    }

    _screenShareStartInProgress = true;
    MediaStream? screen;
    try {
      final backgroundReady = await _startBackgroundExecutionForScreenShare();
      if (!backgroundReady) {
        _showInlineMessage(
          'Screen sharing could not be started (background permission denied).',
        );
        return;
      }

      screen = await navigator.mediaDevices
          .getDisplayMedia({'video': true, 'audio': false});
      final screenTrack = screen.getVideoTracks().isNotEmpty ? screen.getVideoTracks().first : null;
      if (screenTrack == null) {
        for (final t in screen.getTracks()) {
          await t.stop();
        }
        _showInlineMessage('No screen video track was shared by the system.');
        return;
      }

      await sender.replaceTrack(screenTrack);
      await _tuneSenderQuality(sender, maxBitrate: kScreenShareBitrate, maxFramerate: 30);

      _screenStream = screen;
      isScreenSharing = true;
      notifyListeners();
      _logEvent('screen_share_started', {});
    } catch (err) {
      if (screen != null) {
        for (final t in screen.getTracks()) {
          await t.stop();
        }
      }
      try {
        await _restoreCameraAfterScreenShare(sender);
      } catch (restoreErr) {
        debugPrint('[video-call] camera restore after failed screen share start failed: $restoreErr');
      }
      debugPrint('[video-call] screen share error: $err');
      _logEvent('screen_share_failed', {'error': err.toString()});
      _showInlineMessage('Screen sharing could not be started on this device.');
    } finally {
      _screenShareStartInProgress = false;
      if (!isScreenSharing) await _stopBackgroundExecutionForScreenShare();
    }
  }

  Future<void> stopScreenShare() async {
    if (_screenShareStopInProgress) return;
    _screenShareStopInProgress = true;

    final screenStream = _screenStream;
    _screenStream = null;

    try {
      if (screenStream != null) {
        for (final t in screenStream.getTracks()) {
          await t.stop();
        }
      }
      final sender = await _videoSender();
      if (sender != null) {
        await _restoreCameraAfterScreenShare(sender);
      }
      _logEvent('screen_share_stopped', {});
    } catch (err) {
      debugPrint('[video-call] camera restore after screen share failed: $err');
      _logEvent('screen_share_restore_failed', {'error': err.toString()});
      _showInlineMessage(
        'Screen sharing stopped, but camera could not be restored. Toggle the camera or rejoin the call.',
      );
    } finally {
      isScreenSharing = false;
      _screenShareStartInProgress = false;
      _screenShareStopInProgress = false;
      await _stopBackgroundExecutionForScreenShare();
      notifyListeners();
    }
  }

  Future<void> _restoreCameraAfterScreenShare(RTCRtpSender sender) async {
    final camTrack = _localStream?.getVideoTracks().isNotEmpty == true
        ? _localStream!.getVideoTracks().first
        : null;
    await sender.replaceTrack(camTrack);
    if (camTrack != null) {
      await _tuneSenderQuality(sender, maxBitrate: kCameraBitrate, maxFramerate: 30);
    }
    _assignStreams(isSwapped);
  }

  void toggleScreenShare() {
    if (isScreenSharing) {
      unawaited(stopScreenShare());
    } else {
      unawaited(startScreenShare());
    }
  }

  void toggleSwap() {
    isSwapped = !isSwapped;
    _assignStreams(isSwapped);
    notifyListeners();
  }

  void setChatOpen(bool open) {
    chatOpen = open;
    if (open) unreadCount = 0;
    notifyListeners();
  }

  void sendMessage(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final senderId = currentUser['id'] ?? '';
    final senderName = currentUser['name'] ?? '';
    messages.add(ChatMessage(
      senderId: senderId,
      senderName: senderName,
      text: trimmed,
      createdAt: DateTime.now().toIso8601String(),
    ));
    if (!chatOpen) unreadCount++;
    notifyListeners();
    _logEvent('chat_send', {'text': trimmed.length > 50 ? '${trimmed.substring(0, 50)}...' : trimmed});
    _socket.emit('appointment-message', {
      'appointmentId': appointmentId,
      'senderId': senderId,
      'senderName': senderName,
      'text': trimmed,
    });
  }

  Future<void> attachFile(UploadCandidate file) async {
    if (file.sizeBytes > 10 * 1024 * 1024) {
      _showInlineMessage('File too large. Max 10 MB.');
      return;
    }
    uploadingFile = true;
    notifyListeners();
    try {
      final uploaded = await uploadFileDirectToS3(file);
      final senderId = currentUser['id'] ?? '';
      final senderName = currentUser['name'] ?? '';
      messages.add(ChatMessage(
        senderId: senderId,
        senderName: senderName,
        text: '',
        fileUrl: uploaded.key,
        fileName: uploaded.name,
        fileType: uploaded.type,
        createdAt: DateTime.now().toIso8601String(),
      ));
      if (!chatOpen) unreadCount++;
      notifyListeners();
      _logEvent('chat_attach', {'name': uploaded.name, 'type': uploaded.type});
      _socket.emit('appointment-message', {
        'appointmentId': appointmentId,
        'senderId': senderId,
        'senderName': senderName,
        'text': '',
        'fileUrl': uploaded.key,
        'fileName': uploaded.name,
        'fileType': uploaded.type,
      });
    } catch (err) {
      final message = err.toString().replaceFirst('Exception: ', '');
      _showInlineMessage(message.isNotEmpty ? message : 'File upload failed.');
    } finally {
      uploadingFile = false;
      notifyListeners();
    }
  }

  void _showInlineMessage(String message, [Duration duration = const Duration(seconds: 4)]) {
    inlineError = message;
    notifyListeners();
    _inlineErrorTimer?.cancel();
    _inlineErrorTimer = Timer(duration, () {
      if (_disposed) return;
      inlineError = '';
      notifyListeners();
    });
  }

  // ─────────────────────────────────────────────────────────────────────
  // Call lifecycle: leave / complete / cleanup
  // ─────────────────────────────────────────────────────────────────────

  Future<void> _teardownSession({bool leaveRoom = true}) async {
    _unregisterSocketListeners();
    _callTimer?.cancel();
    _callTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _iceRestartTimer?.cancel();
    _iceRestartTimer = null;
    _connectionFailTimer?.cancel();
    _connectionFailTimer = null;
    _ignoreOfferResetTimer?.cancel();
    _ignoreOfferResetTimer = null;
    _reconnectStallTimer?.cancel();
    _reconnectStallTimer = null;
    _clearJoinTimeout();
    _stopStatsCollection();

    if (leaveRoom && _joinedSocketId.isNotEmpty && _socket.connected) {
      _socket.emit('leave-appointment-room', {'appointmentId': appointmentId});
    }

    final pc = _pc;
    _pc = null;
    await pc?.close();

    // The screen-capture stream is independent of the RTCPeerConnection, so
    // closing `pc` above doesn't stop it — matches VideoCall.jsx's main
    // effect cleanup, which stops screenStreamRef's tracks on every
    // teardown (including a forced reconnect), not just on final leave.
    final screenStream = _screenStream;
    _screenStream = null;
    if (screenStream != null) {
      for (final t in screenStream.getTracks()) {
        await t.stop();
      }
    }
    isScreenSharing = false;
    _screenShareStartInProgress = false;
    _screenShareStopInProgress = false;
    await _stopBackgroundExecutionForScreenShare();

    _pendingRemoteCandidates.clear();
    _joinedSocketId = '';
    _ignoreOffer = false;
    _restartRequestInFlight = false;
  }

  /// [emitLeave] mirrors React's `pageUnloadingRef` gate on the
  /// `leave-appointment-room` emit: user-initiated leaves (leaveCall,
  /// completeAppointment, normal widget dispose) should tell the peer
  /// immediately, but an app-process kill (see
  /// `didChangeAppLifecycleState(AppLifecycleState.detached)` in the
  /// screen) should not — the socket disconnecting on its own gives the
  /// server's grace-period logic a chance to treat a quick relaunch as a
  /// resume instead of an abrupt "peer left".
  Future<void> performCleanup({bool emitLeave = true}) async {
    if (_completedFlag) return;
    _completedFlag = true;

    await _teardownSession(leaveRoom: emitLeave);

    final tracks = _localStream?.getTracks() ?? const [];
    for (final t in tracks) {
      await t.stop();
    }
    _localStream = null;
  }

  Future<void> leaveCall() async {
    if (completing) return;
    await performCleanup();
  }

  Future<bool> completeAppointment() async {
    if (!isDoctor || completing) return false;
    completing = true;
    notifyListeners();
    try {
      final status = appt?['status'];
      if (status == 'assigned' || status == 'confirmed') {
        await ApiService.instance.put('/api/appointments/$appointmentId/complete', const {});
      }
      await performCleanup();
      return true;
    } catch (err) {
      completing = false;
      _showInlineMessage(
        'Failed to complete appointment. Please try again.',
        const Duration(seconds: 5),
      );
      return false;
    }
  }

  // ── WebRTC connection-quality stats polling ─────────────────────────
  // Ported from VideoCall.jsx's startStatsCollection/stopStatsCollection —
  // same STATS_INTERVAL_MS cadence and the same `webrtc_stats` telemetry
  // event/shape, so mobile calls surface in the same monitoring data as web.

  void _stopStatsCollection() {
    _statsTimer?.cancel();
    _statsTimer = null;
  }

  void _startStatsCollection(RTCPeerConnection pc) {
    _stopStatsCollection();
    _statsTimer = Timer.periodic(
      const Duration(milliseconds: kStatsIntervalMs),
      (_) async {
        if (_disposed ||
            pc.signalingState == RTCSignalingState.RTCSignalingStateClosed) {
          _stopStatsCollection();
          return;
        }
        try {
          final stats = await pc.getStats();
          final diagnostics = <String, dynamic>{
            'rtt': null,
            'packetsSent': 0,
            'packetsLost': 0,
            'bytesSent': 0,
            'bytesReceived': 0,
            'localCandidateType': 'unknown',
            'remoteCandidateType': 'unknown',
            'selectedPairState': 'unknown',
          };

          for (final report in stats) {
            if (report.type != 'candidate-pair' ||
                report.values['state'] != 'succeeded') {
              continue;
            }
            diagnostics['selectedPairState'] = report.values['state'];

            final rtt = report.values['currentRoundTripTime'];
            if (rtt is num) diagnostics['rtt'] = (rtt * 1000).round();
            final bytesSent = report.values['bytesSent'];
            if (bytesSent is num) diagnostics['bytesSent'] = bytesSent;
            final bytesReceived = report.values['bytesReceived'];
            if (bytesReceived is num) {
              diagnostics['bytesReceived'] = bytesReceived;
            }
            final packetsSent = report.values['packetsSent'];
            if (packetsSent is num) diagnostics['packetsSent'] = packetsSent;
            final packetsLost = report.values['packetsLost'];
            if (packetsLost is num) diagnostics['packetsLost'] = packetsLost;

            final localId = report.values['localCandidateId'];
            final remoteId = report.values['remoteCandidateId'];
            for (final inner in stats) {
              if (inner.type == 'local-candidate' && inner.id == localId) {
                diagnostics['localCandidateType'] =
                    inner.values['candidateType'] ?? inner.type;
              }
              if (inner.type == 'remote-candidate' && inner.id == remoteId) {
                diagnostics['remoteCandidateType'] =
                    inner.values['candidateType'] ?? inner.type;
              }
            }
          }

          debugPrint('[webrtc-stats] $diagnostics');
          _logEvent('webrtc_stats', diagnostics);
        } catch (err) {
          debugPrint('[webrtc-stats] getStats failed: $err');
        }
      },
    );
  }

  // ── Lightweight telemetry ────────────────────────────────────────────

  void _logEvent(String event, Map<String, dynamic> details) {
    debugPrint('[video-call] $event $details');
    if (_socket.connected && appointmentId.isNotEmpty) {
      _socket.emit('video-telemetry', {
        'appointmentId': appointmentId,
        'event': event,
        'role': isDoctor ? 'doctor' : 'user',
        'timestamp': DateTime.now().toIso8601String(),
        'details': details,
      });
    }
  }
}
